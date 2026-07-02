extends Node2D

enum SEASONS { WINTER, SPRING, SUMMER, AUTUMN }

var season = SEASONS.WINTER
var turn = 0

var my_pl_id = 0

var players = {}

@onready var provinces = $provinces
@onready var armies = $armies
@onready var camera: Camera2D = $Camera2D
@onready var pathfinding = $pathfinding

@onready var gui_node = $BasebottomGUI

func dummy_player_data():
	players[0] = GlobalStuff.PlayerData.new(0, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 0, "Richard", {"marks": 100, "people": 0})
	players[1] = GlobalStuff.PlayerData.new(1, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 1, "William", {"marks": 2300, "people": 0})
	players[0].color = {"red": 0, "green": 100, "blue": 255}
	players[1].color = {"red": 255, "green": 0, "blue": 0}


func _ready() -> void:
	dummy_player_data()
	update_player_data.rpc(players)
	assign_players_home_provinces()
	initialize_map()
	set_players_turn()


func initialize_map() -> void:	
	for child in provinces.get_children():
		child.base_map = self
		child.sync_player_owner_to_children()
		child.set_flags()
	
	for child in armies.get_children():
		child.base_map = self
		child.set_flags()
	# pathfinding
	pathfinding.initialize()


func on_army_clicked(army: Node2D) -> void:
	if army.player_owner == my_pl_id:
		pathfinding.select_army(army)
	else:
		show_army_owner_popup(army)


func show_army_owner_popup(army: Node2D) -> void:
	var owner_name := "Unknown"
	if players.has(army.player_owner):
		owner_name = str(players[army.player_owner].name_)
	gui_node.show_info_popup("Army of %s" % owner_name)


@rpc("any_peer", "call_local", "reliable")
func request_army_move(army_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	if !multiplayer.is_server():
		return
	var army = armies.get_node_or_null(army_name)
	if army == null:
		return
	steps = clampi(steps, 0, army.movement_left)
	if steps <= 0:
		return
	apply_army_move.rpc(army_name, cell_x, cell_y, steps)


@rpc("authority", "call_local", "reliable")
func apply_army_move(army_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	var army = armies.get_node_or_null(army_name)
	if army == null:
		return
	pathfinding.place_army_at_cell(army, Vector2i(cell_x, cell_y))
	army.movement_left -= steps
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


func reset_all_army_movement() -> void:
	for army in armies.get_children():
		army.reset_movement()


func update_all_army_visuals() -> void:
	for army in armies.get_children():
		army.set_greyed(army.player_owner == my_pl_id and army.movement_left <= 0)


func get_objects_with_pathfinding_blocked_tiles() -> Array:
	var result: Array = []
	for prov in provinces.get_children():
		for key in ["settlements", "fields", "economy", "defense"]:
			var container = prov.get_node_or_null(key)
			if container:
				for node in container.get_children():
					if node.has_method("get_pathfinding_blocked_tile_centers"):
						result.append(node)
	return result


@rpc("any_peer", "call_local", "reliable")
func player_ended_turn(player_id):
	if !multiplayer.is_server():
		return
	players[player_id].ended_turn = true
	
	# update player data
	update_player_data.rpc(players)
	
	# calculate if the client of the user has hotseat, and if it should switch to the next user
	var peer_id = players[player_id].owner_peer_id
	var remaining = get_unfinished_players_for_peer(peer_id)
	
	if not remaining.is_empty():
		# send the request to the peer to switch the player playing
		var r_player_id = remaining[0].player_id
		var new_peer_id = players[r_player_id].owner_peer_id
		switch_to_player.rpc_id(new_peer_id, r_player_id)
	
	if multiplayer.is_server():
		check_if_end_turn.rpc_id(1)

func restore_ended_turn_players():
	for p : GlobalStuff.PlayerData in players.values():
		p.ended_turn = false
	
	# update player data
	update_player_data.rpc(players)
	
func get_unfinished_players_for_peer(peer_id:int) -> Array:
	var result := []

	for p : GlobalStuff.PlayerData in players.values():
		if (p.owner_peer_id == peer_id and !p.ended_turn and p.type != GlobalStuff.PLAYER_TYPE.AI and 
					p.status == GlobalStuff.PLAYER_STATUS.PLAYING):
			result.append(p)

	return result

@rpc("authority", "call_remote", "reliable")
func update_player_data(player_data_):
	players = player_data_

@rpc("authority", "call_local", "reliable")
func switch_to_player(r_player_id):
	my_pl_id = r_player_id
	pathfinding.deselect_army()
	# recalculate everything
	update_visuals_and_stats()
	center_camera_on_current_player_home()

@rpc("authority", "call_local", "reliable")
func check_if_end_turn():
	for player_id in players:
		if players[player_id].ended_turn == false:
			return
	end_turn()

func end_turn():
	restore_ended_turn_players()
	bump_season_i_turn.rpc()
	set_players_turn()
	calculate_new_turn_game_data.rpc()

@rpc("authority", "call_local", "reliable")
func calculate_new_turn_game_data():
	assign_players_home_provinces()
	reset_all_army_movement()
	#calculate and then display the new data
	add_resources()
	update_visuals_and_stats()
	
func set_players_turn():
	# set the first players for the turn on each client
	for p : GlobalStuff.PlayerData in players.values():
		var next_player_id = get_starting_player_for_peer(p.owner_peer_id).player_id
		switch_to_player.rpc_id(p.owner_peer_id, next_player_id)

func get_starting_player_for_peer(peer_id:int) -> GlobalStuff.PlayerData:
	var selected : GlobalStuff.PlayerData = null

	for p : GlobalStuff.PlayerData in players.values():
		if p.owner_peer_id != peer_id:
			continue
		if p.ended_turn:
			continue
		if p.type == GlobalStuff.PLAYER_TYPE.AI:
			continue
		if p.status != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue

		# choose lowest local_slot
		if selected == null or p.local_slot < selected.local_slot:
			selected = p

	return selected

@rpc("authority", "call_local", "reliable")
func bump_season_i_turn():
	turn += 1
	
	var new_season = season +1
	
	if new_season > 3:
		new_season = 0
	
	season = new_season as SEASONS

func update_visuals_and_stats():
	update_stats()
	update_gui()
	update_all_army_visuals()
	
func update_gui():
	gui_node.update_season(season)
	gui_node.update_pname(players[my_pl_id].name_)
	gui_node.update_money(players[my_pl_id].game_data["marks"])
	update_menus()

func update_menus():
	gui_node.update_economy_menu(self)

func update_stats():
	recalculate_all_settlements_growth()
	recalculate_all_settlements_marks()
	update_players_population()


func recalculate_all_settlements_growth() -> void:
	for prov in provinces.get_children():
		prov.recalculate_settlements_growth()

func add_population():
	recalculate_all_settlements_growth()
	for prov in provinces.get_children():
		prov.apply_predicted_growth_to_settlements()
	update_players_population()

func update_players_population() -> void:
	for pid in players:
		players[pid].game_data["people"] = 0
	for prov in provinces.get_children():
		var has_by_player: Dictionary = prov.resources["population"]["has"]
		for player_id in has_by_player:
			if players.has(player_id):
				players[player_id].game_data["people"] +=  int(has_by_player[player_id])

func recalculate_all_settlements_marks() -> void:
	for prov in provinces.get_children():
		prov.recalculate_marks_will_by_player()


func add_marks_to_players() -> void:
	recalculate_all_settlements_marks()
	for prov in provinces.get_children():
		var will_by_player: Dictionary = prov.resources["marks"]["will"]
		for player_id in will_by_player:
			if players.has(player_id):
				players[player_id].game_data["marks"] += int(will_by_player[player_id])


func add_resources():
	add_marks_to_players()


func _provinces_for_player(player_id: int) -> Array:
	var owned := []
	var other_interest := []
	for prov in provinces.get_children():
		if prov.player_owner == player_id:
			owned.append(prov)
		elif prov.defacto == player_id or prov.dejure == player_id:
			other_interest.append(prov)
	owned.append_array(other_interest)
	return owned


func get_player_overview_data(player_id: int) -> Dictionary:
	if not players.has(player_id):
		return {}
	var pl = players[player_id]
	var prov_list = _provinces_for_player(player_id)
	var population := 0
	for prov in prov_list:
		population += prov.resources["population"]["has"]["all"]
	return {
		"num_provinces": prov_list.size(),
		"marks": pl.game_data.get("marks", 0),
		"population": population
	}


func get_all_provinces_list_data(player_id: int) -> Array:
	var owned := []
	var other := []
	for prov in provinces.get_children():
		var entry = {
			"id": prov.name,
			"name": prov.p_name,
			"population": prov.resources["population"]["has"]["all"],
			"predicted_income": prov.resources["marks"]["will"]["all"],
			"owned": prov.player_owner == player_id
		}
		if prov.player_owner == player_id:
			owned.append(entry)
		elif prov.defacto == player_id or prov.dejure == player_id:
			other.append(entry)
	owned.append_array(other)
	return owned


func _get_province_by_id(province_id: String) -> Node:
	for prov in provinces.get_children():
		if prov.name == province_id:
			return prov
	return null


func get_province_data(province_id: String) -> Dictionary:
	var prov = _get_province_by_id(province_id)
	if prov == null:
		return {}
	return prov.get_display_data(players)


func assign_players_home_provinces() -> void:
	var prov_list: Array = provinces.get_children()
	prov_list.sort_custom(func(a, b): return a.name < b.name)
	var assigned := {}
	for prov in prov_list:
		var pid = prov.player_owner
		if not players.has(pid) or assigned.has(pid):
			continue
		players[pid].game_data["home_province_id"] = prov.name
		assigned[pid] = true
	# Override with any province marked as home_province for that player
	for prov in prov_list:
		if prov.home_province and players.has(prov.player_owner):
			players[prov.player_owner].game_data["home_province_id"] = prov.name


func center_camera_on_current_player_home() -> void:
	if not players.has(my_pl_id):
		return
	var home_id: String = players[my_pl_id].game_data.get("home_province_id", "")
	if home_id.is_empty():
		return
	var prov = _get_province_by_id(home_id)
	if prov == null:
		return
	for s in prov.settlements.get_children():
		if s.get("type_") != null and s.type_ == GlobalStuff.BUILDING_TYPE.TOWN:
			camera.position = s.global_position
			return
