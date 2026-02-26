extends Node2D

enum SEASONS { WINTER, SPRING, SUMMER, AUTUMN }

var season = SEASONS.WINTER
var turn = 0

var my_pl_id = 0

var players = {}

@onready var provinces = $provinces

@onready var gui_node = $BasebottomGUI

func dummy_player_data():
	players[0] = GlobalStuff.PlayerData.new(0, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 0, "Richard", {"marks": 100})
	players[1] = GlobalStuff.PlayerData.new(1, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 1, "William", {"marks": 2300})


func _ready() -> void:
	dummy_player_data()
	update_player_data.rpc(players)
	set_players_turn()

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
	#calculate and then display the new data
	#update_data()
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
	
	season = new_season

func update_visuals_and_stats():
	update_stats()
	update_gui()
	
func update_gui():
	gui_node.update_season(season)
	gui_node.update_pname(players[my_pl_id].name_)
	gui_node.update_money(players[my_pl_id].game_data["marks"])

func update_stats():
	recalculate_all_settlements_growth()


func recalculate_all_settlements_growth() -> void:
	for prov in provinces.get_children():
		prov.recalculate_settlements_growth()

func add_population():
	recalculate_all_settlements_growth()
	for prov in provinces.get_children():
		prov.apply_predicted_growth_to_settlements()

func add_player_momo():
	for prov in provinces.get_children():
		pass
