extends Node2D

enum SEASONS { WINTER, SPRING, SUMMER, AUTUMN }

var season = SEASONS.WINTER
var turn = 0

var my_pl_id = 0

var players = {}

@onready var provinces = $provinces
@onready var armies = $armies
@onready var camera: Camera2D = $Camera2D
@onready var path_line: Line2D = $PathLine
@onready var tilemap: Node2D = $tilemap

@onready var gui_node = $BasebottomGUI

# Pathfinding and army selection (terrain only; armies do not block movement)
var astar_graph: AStar2D
var walkable_cells: Dictionary = {}
var cell_to_point_id: Dictionary = {}
var point_id_to_cell: Dictionary = {}
var map_layer: TileMapLayer
var selected_army: Node2D = null
var path_target_cell: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)  # invalid sentinel
var current_path: Array[Vector2i] = []
const ARMY_CENTER_OFFSET := Vector2(32, 16)
const MOVE_DIRS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

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
	
	_setup_astar_grid()
	_snap_armies_to_cell_centers()
	for child in armies.get_children():
		if child.has_method("setup_selection_input"):
			child.setup_selection_input()


func _get_map_layer() -> TileMapLayer:
	for child in tilemap.get_children():
		if child is TileMapLayer and child.tile_set != null:
			return child as TileMapLayer
	return null


func _setup_astar_grid() -> void:
	map_layer = _get_map_layer()
	if map_layer == null:
		return
	astar_graph = AStar2D.new()
	walkable_cells.clear()
	cell_to_point_id.clear()
	point_id_to_cell.clear()

	for cell in map_layer.get_used_cells():
		var tile_data = map_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		var walkable_data = tile_data.get_custom_data("walkable")
		var is_walkable := true
		if walkable_data != null:
			is_walkable = bool(walkable_data)
		if is_walkable:
			walkable_cells[cell] = true

	var next_id := 0
	for cell_variant in walkable_cells.keys():
		var cell: Vector2i = cell_variant
		cell_to_point_id[cell] = next_id
		point_id_to_cell[next_id] = cell
		# Use isometric tile center positions for A* cost/heuristic so routes are straight in screen space.
		astar_graph.add_point(next_id, map_layer.map_to_local(cell))
		next_id += 1

	for cell_variant in walkable_cells.keys():
		var cell: Vector2i = cell_variant
		var from_id: int = cell_to_point_id[cell]
		for dir_variant in MOVE_DIRS:
			var dir: Vector2i = dir_variant
			var to_cell := cell + dir
			if not walkable_cells.has(to_cell):
				continue
			var to_id: int = cell_to_point_id[to_cell]
			if not astar_graph.are_points_connected(from_id, to_id):
				astar_graph.connect_points(from_id, to_id, true)


func _snap_armies_to_cell_centers() -> void:
	if map_layer == null:
		return
	for army in armies.get_children():
		var cell := get_army_cell(army)
		if _is_walkable_cell(cell):
			army.global_position = _get_cell_center_global(cell) - ARMY_CENTER_OFFSET


func _is_walkable_cell(cell: Vector2i) -> bool:
	return walkable_cells.has(cell)


func _find_path_cells(from_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	if astar_graph == null:
		return []
	if not _is_walkable_cell(from_cell) or not _is_walkable_cell(target_cell):
		return []
	var from_id: int = cell_to_point_id[from_cell]
	var to_id: int = cell_to_point_id[target_cell]
	var id_path: PackedInt64Array = astar_graph.get_id_path(from_id, to_id)
	var cell_path: Array[Vector2i] = []
	for id in id_path:
		cell_path.append(point_id_to_cell[id])
	return cell_path


func get_cell_at_mouse() -> Vector2i:
	if map_layer == null:
		return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	var global_mouse := get_global_mouse_position()
	var local := map_layer.to_local(global_mouse)
	return map_layer.local_to_map(local)


func get_army_cell(army: Node2D) -> Vector2i:
	if map_layer == null:
		return Vector2i(0, 0)
	var local := map_layer.to_local(_get_army_center_global(army))
	return map_layer.local_to_map(local)


func _get_cell_center_global(cell: Vector2i) -> Vector2:
	if map_layer == null:
		return Vector2.ZERO
	var local := map_layer.map_to_local(cell)
	return map_layer.global_position + local


func _get_army_center_global(army: Node2D) -> Vector2:
	return army.global_position + ARMY_CENTER_OFFSET


func select_army(army: Node2D) -> void:
	if selected_army != null and selected_army != army and selected_army.has_method("set_selected"):
		selected_army.set_selected(false)
	selected_army = army
	clear_path_preview()
	if army != null and army.has_method("set_selected"):
		army.set_selected(true)


func clear_path_preview() -> void:
	path_line.clear_points()
	current_path.clear()
	path_target_cell = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if selected_army != null and selected_army.has_method("set_selected"):
				selected_army.set_selected(false)
			selected_army = null
			clear_path_preview()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and selected_army != null and astar_graph != null:
			var cell := get_cell_at_mouse()
			if not _is_walkable_cell(cell):
				return
			if cell == path_target_cell and current_path.size() > 0:
				execute_move()
			else:
				_try_show_path(cell)


func _try_show_path(target_cell: Vector2i) -> void:
	var from_cell := get_army_cell(selected_army)
	if not _is_walkable_cell(from_cell):
		return
	var path_ids: Array[Vector2i] = _find_path_cells(from_cell, target_cell)
	print("Army path from %s to %s: %s" % [from_cell, target_cell, path_ids])
	current_path.clear()
	for id in path_ids:
		current_path.append(id)
	if current_path.is_empty():
		clear_path_preview()
		return
	path_target_cell = target_cell
	path_line.clear_points()
	for cell in current_path:
		path_line.add_point(to_local(_get_cell_center_global(cell)))


func execute_move() -> void:
	if selected_army == null or current_path.is_empty() or map_layer == null:
		clear_path_preview()
		return
	var end_cell: Vector2i = current_path[current_path.size() - 1]
	var army = selected_army
	army.global_position = _get_cell_center_global(end_cell) - ARMY_CENTER_OFFSET
	if army.has_method("set_selected"):
		army.set_selected(false)
	clear_path_preview()
	selected_army = null


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
