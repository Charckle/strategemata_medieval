extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.TOWN

enum STAGES { SMALL, MEDIUM, BIG, RAZED }

@export var stage = STAGES.SMALL

var fields = []

@export var player_owner = 1

# Max men this building can garrison (single flat pool). Starts empty.
const GARRISON_CAPACITY := 300

# Designer-authored starting garrison (Array of stack specs); see GlobalUnits.units_from_spec.
@export var start_garrison: Array = []

var base_map: Node = null

func get_garrison_capacity(_spot: int = GlobalUnits.SPOT.FLAT) -> int:
	return GARRISON_CAPACITY

func get_pathfinding_blocked_tile_centers() -> Array:
	return [
		global_position + Vector2(32, 32),
		global_position + Vector2(64, 16),
		global_position + Vector2(64, 48),
		global_position + Vector2(96, 32)
	]

var population
var base_pop_growth = 0.05
var predicted_growth
var predicted_marks = 0

func _ready() -> void:
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


func get_start_data():
	get_pop()
	calculate_predicted_growth()
	calculate_predicted_marks()


func calculate_predicted_marks() -> void:
	if stage == STAGES.RAZED:
		predicted_marks = 0
		return
	predicted_marks = int(ceil(population * 0.10))


func calculate_predicted_growth() -> void:
	if stage == STAGES.RAZED:
		predicted_growth = 0
		return
	predicted_growth = population * base_pop_growth

func get_pop():
	var pop := {
		STAGES.SMALL: 300,
		STAGES.MEDIUM: 600,
		STAGES.BIG: 900,
		STAGES.RAZED: 0,
	}
	
	population = pop[stage]


func get_stage_name() -> String:
	match stage:
		STAGES.SMALL: return "Small"
		STAGES.MEDIUM: return "Medium"
		STAGES.BIG: return "Big"
		STAGES.RAZED: return "Razed"
	return ""
	
