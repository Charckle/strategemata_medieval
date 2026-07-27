extends Node


enum BUILDING_TYPE { VILLAGE, TOWN, CASTLE, ECONOMY, FIELD, MERCHANT, SELLSWORDS }

enum PLAYER_TYPE { HUMAN_LOCAL, AI, LOCAL_COUNCIL }

## Map-authored unowned province; resolved to a LOCAL_COUNCIL at map start.
const UNOWNED_PLAYER := -1

## Session-only master switch for secret AI lord cheats (not saved). Admin can toggle.
var ai_cheats_enabled: bool = GameBalance.AI_CHEATS_DEFAULT


func is_local_council(type_) -> bool:
	return int(type_) == int(PLAYER_TYPE.LOCAL_COUNCIL)


func is_ai_lord(type_) -> bool:
	return int(type_) == int(PLAYER_TYPE.AI)


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
	# RGB 0-255; map identity for flags / province borders (independent of heraldry).
	var color : Dictionary = {"red": 128, "green": 128, "blue": 128}
	# Coat of arms recipe (see Heraldry autoload). Empty → rolled at map start.
	var heraldry : Dictionary = {}
	
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


## Distinct map colours for lords (borders, flags, score). Not heraldic tinctures.
const ORDER_PALETTE: Array = [
	{"red": 200, "green": 40, "blue": 40},
	{"red": 40, "green": 90, "blue": 200},
	{"red": 30, "green": 140, "blue": 60},
	{"red": 220, "green": 130, "blue": 20},
	{"red": 140, "green": 50, "blue": 180},
	{"red": 20, "green": 160, "blue": 170},
	{"red": 210, "green": 60, "blue": 130},
	{"red": 160, "green": 110, "blue": 40},
	{"red": 230, "green": 200, "blue": 40},
	{"red": 80, "green": 200, "blue": 100},
	{"red": 60, "green": 60, "blue": 160},
	{"red": 180, "green": 80, "blue": 50},
]

const ORDER_COLOR_UNSET := {"red": 128, "green": 128, "blue": 128}
const COUNCIL_ORDER_COLOR := {"red": 140, "green": 140, "blue": 140}


func order_color_key(c: Dictionary) -> String:
	return "%d,%d,%d" % [
		int(c.get("red", 128)),
		int(c.get("green", 128)),
		int(c.get("blue", 128)),
	]


func normalize_order_color(c) -> Dictionary:
	if c is Dictionary:
		return {
			"red": clampi(int(c.get("red", 128)), 0, 255),
			"green": clampi(int(c.get("green", 128)), 0, 255),
			"blue": clampi(int(c.get("blue", 128)), 0, 255),
		}
	return ORDER_PALETTE[0].duplicate()


func order_color_to_color(c: Dictionary) -> Color:
	var n := normalize_order_color(c)
	return Color8(int(n["red"]), int(n["green"]), int(n["blue"]))


func is_palette_order_color(c: Dictionary) -> bool:
	var key := order_color_key(normalize_order_color(c))
	for entry in ORDER_PALETTE:
		if order_color_key(entry) == key:
			return true
	return false


## First free palette colour not in `used_keys` (keys from order_color_key).
## If `prefer` is set and free, returns it; otherwise the first free palette entry.
func pick_free_order_color(used_keys: Dictionary, prefer: Dictionary = {}) -> Dictionary:
	if not prefer.is_empty():
		var pref := normalize_order_color(prefer)
		if not used_keys.has(order_color_key(pref)):
			return pref.duplicate()
	for entry in ORDER_PALETTE:
		var k := order_color_key(entry)
		if not used_keys.has(k):
			return entry.duplicate()
	return _fallback_order_color(used_keys)


## Next free palette colour after `current` (always advances when possible).
func cycle_order_color(used_keys: Dictionary, current: Dictionary = {}) -> Dictionary:
	var cur := normalize_order_color(current) if not current.is_empty() else {}
	var start := 0
	if not cur.is_empty():
		for i in ORDER_PALETTE.size():
			if order_color_key(ORDER_PALETTE[i]) == order_color_key(cur):
				start = (i + 1) % ORDER_PALETTE.size()
				break
	for step in ORDER_PALETTE.size():
		var entry: Dictionary = ORDER_PALETTE[(start + step) % ORDER_PALETTE.size()]
		var k := order_color_key(entry)
		if not used_keys.has(k):
			return entry.duplicate()
	return _fallback_order_color(used_keys)


func _fallback_order_color(used_keys: Dictionary) -> Dictionary:
	var fallback: Dictionary = ORDER_PALETTE[0].duplicate()
	fallback["red"] = clampi(int(fallback["red"]) + used_keys.size() * 17, 0, 255)
	fallback["green"] = clampi(int(fallback["green"]) + used_keys.size() * 11, 0, 255)
	return fallback


## Collect used colour keys for lords in `slots` / players, optionally skipping one index/pid.
func used_order_color_keys_from_slots(slots: Array, skip_idx: int = -1) -> Dictionary:
	var used := {}
	for i in slots.size():
		if i == skip_idx:
			continue
		var c = slots[i].get("color", {})
		if c is Dictionary and not c.is_empty():
			used[order_color_key(normalize_order_color(c))] = true
	return used


## Ensure every non-council player has a unique order colour. Councils stay gray.
func ensure_order_colors(players: Dictionary) -> void:
	var used := {}
	var need_assign: Array = []
	for pid in players.keys():
		var p = players[pid]
		if is_local_council(p.type):
			p.color = COUNCIL_ORDER_COLOR.duplicate()
			continue
		var c := normalize_order_color(p.color if p.get("color") != null else {})
		var key := order_color_key(c)
		if key == order_color_key(ORDER_COLOR_UNSET) \
				or key == order_color_key(COUNCIL_ORDER_COLOR) \
				or used.has(key):
			need_assign.append(pid)
		else:
			p.color = c
			used[key] = true
	for pid in need_assign:
		var picked := pick_free_order_color(used)
		players[pid].color = picked
		used[order_color_key(picked)] = true


func get_season_name(season_id):
	match season_id:
		0: return "Winter"
		1: return "Spring"
		2: return "Summer"
		3: return "Autumn"
		_: return "Unknown"
