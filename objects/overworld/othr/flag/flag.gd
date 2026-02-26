extends Node2D

const DEFAULT_GRAY := Vector3i(128, 128, 128)

@onready var settlement = get_parent()
@onready var flag_sprite = $flag_spr

func setup_flag() -> void:
	var player_id: int = settlement.player_owner
	var map_node = settlement.get("base_map")
	if map_node == null or not map_node.get("players"):
		flag_sprite._set_flag_color_rgb(DEFAULT_GRAY.x, DEFAULT_GRAY.y, DEFAULT_GRAY.z)
		return
	var players_dict: Dictionary = map_node.players
	if not players_dict.has(player_id):
		flag_sprite._set_flag_color_rgb(DEFAULT_GRAY.x, DEFAULT_GRAY.y, DEFAULT_GRAY.z)
		return
	var pl = players_dict[player_id]
	var c: Dictionary = pl.color
	var r: int = c.get("red", DEFAULT_GRAY.x)
	var g: int = c.get("green", DEFAULT_GRAY.y)
	var b: int = c.get("blue", DEFAULT_GRAY.z)
	flag_sprite._set_flag_color_rgb(r, g, b)
