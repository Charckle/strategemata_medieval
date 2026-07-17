extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.CASTLE

enum CASTLE_TYPE { WOODEN_FORT, MOTTE_AND_BAILEY, NORMAN_KEEP, ENCLOSED_CASTLE, POLIWARDED_CASTLE, CONCENTRIC_CASTLE }

# Men each type holds INSIDE (gets the castle bonus). OUTSIDE holds double, no bonus.
const INSIDE_CAPACITY := {
	CASTLE_TYPE.WOODEN_FORT: 100,
	CASTLE_TYPE.MOTTE_AND_BAILEY: 200,
	CASTLE_TYPE.NORMAN_KEEP: 250,
	CASTLE_TYPE.ENCLOSED_CASTLE: 500,
	CASTLE_TYPE.POLIWARDED_CASTLE: 700,
	CASTLE_TYPE.CONCENTRIC_CASTLE: 1000,
}

@export var castle_type: CASTLE_TYPE = CASTLE_TYPE.WOODEN_FORT

@export var player_owner = 1

# Designer-authored starting garrisons (Arrays of stack specs); see GlobalUnits.units_from_spec.
@export var start_inside: Array = []
@export var start_outside: Array = []

var base_map: Node = null

func get_inside_capacity() -> int:
	return INSIDE_CAPACITY.get(castle_type, 0)

func get_outside_capacity() -> int:
	return get_inside_capacity() * 2

func get_garrison_capacity(spot: int = GlobalUnits.SPOT.INSIDE) -> int:
	if spot == GlobalUnits.SPOT.OUTSIDE:
		return get_outside_capacity()
	return get_inside_capacity()

func get_castle_type_name() -> String:
	match castle_type:
		CASTLE_TYPE.WOODEN_FORT: return "Wooden Fort"
		CASTLE_TYPE.MOTTE_AND_BAILEY: return "Motte-and-Bailey"
		CASTLE_TYPE.NORMAN_KEEP: return "Norman Keep"
		CASTLE_TYPE.ENCLOSED_CASTLE: return "Enclosed Castle"
		CASTLE_TYPE.POLIWARDED_CASTLE: return "Poliwarded Castle"
		CASTLE_TYPE.CONCENTRIC_CASTLE: return "Concentric Castle"
	return "Castle"

func get_stage_name() -> String:
	return get_castle_type_name()

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
	return false

func get_pathfinding_blocked_tile_centers() -> Array:
	return [
		global_position + Vector2(32, 32),
		global_position + Vector2(64, 16),
		global_position + Vector2(64, 48),
		global_position + Vector2(96, 32)
	]
