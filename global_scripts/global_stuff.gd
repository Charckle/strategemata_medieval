extends Node


enum BUILDING_TYPE { VILLAGE, TOWN, CASTLE, ECONOMY, FIELD, MERCHANT, SELLSWORDS }

enum PLAYER_TYPE { HUMAN_LOCAL, AI, LOCAL_COUNCIL }

## Map-authored unowned province; resolved to a LOCAL_COUNCIL at map start.
const UNOWNED_PLAYER := -1


func is_local_council(type_) -> bool:
	return int(type_) == int(PLAYER_TYPE.LOCAL_COUNCIL)


## AI lords and local councils — no human hotseat turn.
func is_auto_turn_player(type_) -> bool:
	var t := int(type_)
	return t == int(PLAYER_TYPE.AI) or t == int(PLAYER_TYPE.LOCAL_COUNCIL)

enum PLAYER_STATUS {
	PLAYING,      # normal turn participant
	DEFEATED,     # lost the game
	SURRENDERED,  # voluntarily left
	DISCONNECTED, # temporary network loss
	SPECTATOR     # observing only
}

class PlayerData:
	var player_id : int
	var type      # HUMAN_LOCAL, AI, LOCAL_COUNCIL
	# who controls this player
	var owner_peer_id : int = 1
	# multiplayer peer that owns this player
	var local_slot : int = 0
	# WHICH local hotseat player on that peer
	var name_
	var status : PLAYER_STATUS = PLAYER_STATUS.PLAYING
	var ended_turn
	
	var game_data = {"dummy": true}
	# RGB 0-255; used for flags, UI; default gray until set (e.g. from lobby)
	var color : Dictionary = {"red": 128, "green": 128, "blue": 128}
	
	func _init(
			p_player_id:int,
			p_type:PLAYER_TYPE,
			p_peer_id:int,
			slot:int,
			p_name:String,
			game_data_
		):
		player_id = p_player_id
		type = p_type
		owner_peer_id = p_peer_id
		local_slot = slot
		name_ = p_name
		ended_turn = false
		game_data = game_data_
	
	func _to_string() -> String:
		return "PlayerData(" \
			+ "id=" + str(player_id) \
			+ ", name=" + str(name_) \
			+ ", type=" + str(type) \
			+ ", owner_peer_id=" + str(owner_peer_id) \
			+ ", local_slot=" + str(local_slot) \
			+ ", status=" + str(status) \
			+ ", ended_turn=" + str(ended_turn) \
			+ ")"

func get_season_name(season_id):
	match season_id:
		0: return "Winter"
		1: return "Spring"
		2: return "Summer"
		3: return "Autumn"
		_: return "Unknown"
