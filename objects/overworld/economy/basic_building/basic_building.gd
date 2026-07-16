extends Node2D

enum SUBTYPES { WOODCUTTER, IRONMINE, GOLDMINE, SILVERMINE, STONEQUARRY, BLACKSMITH }

var type_ = GlobalStuff.BUILDING_TYPE.ECONOMY
@export var subtype = SUBTYPES.WOODCUTTER

enum STAGES { EMPTY, SMALL, MEDIUM, BIG, RAZED }

@export var stage = STAGES.SMALL

@onready var building_spr: Sprite2D = $building_spr

@export var player_owner = 1

# Max men this building can garrison (single flat pool). Starts empty.
const GARRISON_CAPACITY := 50

# Designer-authored starting garrison (Array of stack specs); see GlobalUnits.units_from_spec.
@export var start_garrison: Array = []

var base_map

func get_garrison_capacity(_spot: int = GlobalUnits.SPOT.FLAT) -> int:
	return GARRISON_CAPACITY

func setup_building() -> void:
	set_flags()


func set_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag != null:
		flag.setup_flag()


func get_garrison_units() -> Array:
	if base_map == null:
		return []
	return base_map.get_all_building_garrison(self)


func get_owner_set() -> Array:
	return GlobalUnits.owners_in(get_garrison_units())


func get_banner_pids() -> Array:
	return get_owner_set()


func shows_ownership_triangle() -> bool:
	return false

func get_pathfinding_blocked_tile_centers() -> Array:
	return [global_position + Vector2(32, 16)]

func _ready() -> void:
	update_for_stage()
	
	
func update_for_stage():
	change_sprite()


func change_sprite():
	var textures := {
		SUBTYPES.WOODCUTTER: 
			{
			STAGES.SMALL: preload("uid://c43brywdf0lxo"),
			},
		SUBTYPES.STONEQUARRY: 
			{
			STAGES.SMALL: preload("uid://ft668a4yuq1k"),
			}
	}
	
	if stage == STAGES.EMPTY:
		building_spr.visible = false
		return
	building_spr.visible = true
	var subtype_tex: Dictionary = textures.get(subtype, {})
	# RAZED/MEDIUM/BIG fall back to SMALL art until dedicated sprites exist.
	var tex = subtype_tex.get(stage, subtype_tex.get(STAGES.SMALL, null))
	if tex != null:
		building_spr.texture = tex


func get_subtype_name() -> String:
	match subtype:
		SUBTYPES.WOODCUTTER: return "Woodcutter"
		SUBTYPES.IRONMINE: return "Iron Mine"
		SUBTYPES.GOLDMINE: return "Gold Mine"
		SUBTYPES.SILVERMINE: return "Silver Mine"
		SUBTYPES.STONEQUARRY: return "Stone Quarry"
		SUBTYPES.BLACKSMITH: return "Blacksmith"
	return "Economy Building"


func get_stage_name() -> String:
	match stage:
		STAGES.EMPTY: return "Empty"
		STAGES.SMALL: return "Small"
		STAGES.MEDIUM: return "Medium"
		STAGES.BIG: return "Big"
		STAGES.RAZED: return "Razed"
	return ""
