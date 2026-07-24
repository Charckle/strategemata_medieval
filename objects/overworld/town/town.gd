extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.TOWN

## Display / razed state. Economic tier is derived live from `population`.
enum STAGES { SMALL, MEDIUM, BIG, VERY_BIG, RAZED }

## Designer-authored starting population; stage follows from this at runtime.
@export var population: int = 300

@export var player_owner = 1

## Visual tier (lagged one turn) or RAZED. Not map-authored.
var stage: int = STAGES.SMALL

var fields = []

# Soft pop cap (may overshoot; overflow shrink applies while above).
const MAX_POPULATION := 2000

# Max men this building can garrison (single flat pool). Starts empty.
const GARRISON_CAPACITY := 300

# Designer-authored starting garrison (Array of stack specs); see GlobalUnits.units_from_spec.
@export var start_garrison: Array = []

var base_map: Node = null

@onready var town_spr: Sprite2D = $town_spr

const TOWN_TEXTURES := {
	STAGES.SMALL: preload("res://sprites/overworld/objects/province/town/town.png"),
	STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/town/town_lvl_2.png"),
	STAGES.BIG: preload("res://sprites/overworld/objects/province/town/town_lvl_3.png"),
	STAGES.VERY_BIG: preload("res://sprites/overworld/objects/province/town/town_lvl_4.png"),
}

func get_garrison_capacity(_spot: int = GlobalUnits.SPOT.FLAT) -> int:
	return GARRISON_CAPACITY


func get_population_cap() -> int:
	return MAX_POPULATION


func get_overflow_jitter() -> int:
	return GlobalUnits.TOWN_OVERFLOW_JITTER


func get_pathfinding_blocked_tile_centers() -> Array:
	return [
		global_position + Vector2(32, 32),
		global_position + Vector2(64, 16),
		global_position + Vector2(64, 48),
		global_position + Vector2(96, 32)
	]

## 0–100; moved by rations, taxes, and levy (see province holding ticks).
var happiness: float = 100.0
## Uncollected tax marks stored here (owner collects with an army).
var tax_marks: int = 0
var predicted_growth
var predicted_marks = 0

func _ready() -> void:
	population = maxi(0, int(population))
	# First load: visual matches current pop (lag only applies across turns).
	if stage != STAGES.RAZED:
		stage = population_tier()
	change_sprite()
	get_start_data()


func setup_building() -> void:
	set_flags()


func set_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag != null:
		flag.setup_flag()
	refresh_vip_crown()


func refresh_vip_crown() -> void:
	var crown := get_node_or_null("crown")
	if crown == null:
		return
	var show := false
	if base_map != null and base_map.has_method("building_has_any_vip"):
		show = base_map.building_has_any_vip(self)
	crown.visible = show


func get_garrison_units() -> Array:
	if base_map == null:
		return []
	return base_map.get_all_building_garrison(self)


func get_owner_set() -> Array:
	return GlobalUnits.owners_in(get_garrison_units())


func get_banner_pids() -> Array:
	return get_owner_set()


func shows_ownership_triangle() -> bool:
	return true


## Live economic tier from current population (ignores display lag).
func population_tier() -> int:
	if stage == STAGES.RAZED:
		return STAGES.RAZED
	var idx := GlobalUnits.settlement_tier_index(int(population), GlobalUnits.TOWN_TIER_POP_MAX)
	match idx:
		1: return STAGES.MEDIUM
		2: return STAGES.BIG
		3: return STAGES.VERY_BIG
		_: return STAGES.SMALL


func settlement_marks_bonus_fraction() -> float:
	var tier := population_tier()
	if tier == STAGES.RAZED:
		return 0.0
	var idx := GlobalUnits.settlement_tier_index(int(population), GlobalUnits.TOWN_TIER_POP_MAX)
	return GlobalUnits.settlement_tier_marks_bonus(idx)


func get_start_data():
	calculate_predicted_growth()
	calculate_predicted_marks()


func calculate_predicted_marks() -> void:
	# Province overwrites from holding tax rate; razed earns nothing.
	if stage == STAGES.RAZED:
		predicted_marks = 0
		return
	predicted_marks = 0


func calculate_predicted_growth() -> void:
	# Province sets ration-based predicted_growth; razed never grows.
	if stage == STAGES.RAZED:
		predicted_growth = 0
		return
	predicted_growth = 0


func can_receive_ration_growth() -> bool:
	return stage != STAGES.RAZED


## Sync display sprite to current population tier (call on new turn).
func refresh_visual_stage() -> void:
	if stage == STAGES.RAZED:
		return
	var want := population_tier()
	if stage != want:
		stage = want
	change_sprite()


func update_for_stage() -> void:
	change_sprite()


func change_sprite() -> void:
	if town_spr == null:
		return
	# Razed: keep standing art; smoke is attached by the map.
	if stage == STAGES.RAZED:
		return
	var tex: Texture2D = TOWN_TEXTURES.get(stage, TOWN_TEXTURES[STAGES.SMALL])
	town_spr.texture = tex
	town_spr.visible = true


func get_stage_name() -> String:
	# UI shows live economic tier (sprite may lag one turn).
	var live := population_tier() if stage != STAGES.RAZED else STAGES.RAZED
	match live:
		STAGES.SMALL: return "Small"
		STAGES.MEDIUM: return "Medium"
		STAGES.BIG: return "Big"
		STAGES.VERY_BIG: return "Very Big"
		STAGES.RAZED: return "Razed"
	return ""
