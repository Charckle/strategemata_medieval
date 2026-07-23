extends Node

const ArmyNames := preload("res://global_scripts/army_names.gd")

var load_saved_continue = false
var settings: Dictionary = {}

## When true, main menu opens the New Game panel on load (after score Continue).
var return_to_new_game := false

## Pending New Game config consumed by the map on load. Cleared after apply.
## Shape: { "map_path": String, "slots": Array[Dictionary] }
## Slot: { "type": "human"|"ai", "name": String, "heraldry": Dictionary,
##         "color": {red,green,blue}, "ai_doctrine": "offense"|"defense" (AI only) }
var pending_game_setup: Dictionary = {}

const TEST_MAP_01 := "res://maps/overworld/test_maps/test_map_01/test_map_01.tscn"
const MAX_SETUP_PLAYERS := 4


func _ready() -> void:
	SettingsLoad.load_settings()


func clear_pending_game_setup() -> void:
	pending_game_setup = {}


func has_pending_game_setup() -> bool:
	return not pending_game_setup.is_empty() and pending_game_setup.get("slots") is Array \
		and not (pending_game_setup["slots"] as Array).is_empty()


func make_default_human_slot(used_colors: Dictionary = {}) -> Dictionary:
	return {
		"type": "human",
		"name": random_lord_name(),
		"heraldry": Heraldry.random_heraldry(),
		"color": GlobalStuff.pick_free_order_color(used_colors),
	}


func make_default_ai_slot(used_colors: Dictionary = {}) -> Dictionary:
	var doctrine := LordAI.DOCTRINE_OFFENSE if randf() < 0.5 else LordAI.DOCTRINE_DEFENSE
	return {
		"type": "ai",
		"name": random_lord_name(),
		"heraldry": Heraldry.random_heraldry(),
		"ai_doctrine": doctrine,
		"color": GlobalStuff.pick_free_order_color(used_colors),
	}


func random_lord_name(used: Dictionary = {}) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = ArmyNames.PERSONS
	if pool.is_empty():
		return "Lord"
	for _i in 12:
		var n := str(pool[rng.randi() % pool.size()])
		if not used.has(n):
			return n
	var base := str(pool[rng.randi() % pool.size()])
	var suffix := 2
	while used.has("%s %d" % [base, suffix]):
		suffix += 1
	return "%s %d" % [base, suffix]
