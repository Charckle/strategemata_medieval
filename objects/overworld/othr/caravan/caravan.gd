extends Node2D

## Map caravan: cargo in transit between provinces. Ownership is `player_owner`.
## Destination is a province id; each season the map auto-spends movement toward
## that province's town. Authoritative cargo/dest live on this node (synced via RPCs).

@export var player_owner: int = 0
@export var movement_points := 10

var base_map
var caravan_id: String = ""
var dest_province_id: String = ""
var cargo: Dictionary = {}
var path_fail_streak: int = 0
var path_fail_notified: bool = false
var movement_left := movement_points

var _outline_material: ShaderMaterial

const OUTLINE_SHADER := preload("res://objects/overworld/army/army_map_unit/selection_outline.gdshader")
const GREYED_MODULATE := Color(0.5, 0.5, 0.5, 1.0)
const NORMAL_MODULATE := Color(1, 1, 1, 1)


func _ready() -> void:
	movement_left = movement_points


func is_caravan() -> bool:
	return true


func setup_building() -> void:
	set_flags()


func set_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag != null:
		flag.setup_flag()


func get_controller() -> int:
	return player_owner


func is_controllable_by(pid: int) -> bool:
	return player_owner == pid


func shows_ownership_triangle() -> bool:
	return true


func get_banner_pids() -> Array:
	return []


func get_owner_set() -> Array:
	return [player_owner]


func effective_max_mp() -> int:
	return movement_points


func reset_movement() -> void:
	movement_left = effective_max_mp()


func set_greyed(state: bool) -> void:
	var figure := get_node_or_null("figure")
	if figure == null:
		return
	figure.modulate = GREYED_MODULATE if state else NORMAL_MODULATE


func set_selected(selected: bool) -> void:
	var figure := get_node_or_null("figure")
	if figure == null:
		return
	if selected:
		if _outline_material == null:
			_outline_material = ShaderMaterial.new()
			_outline_material.shader = OUTLINE_SHADER
		figure.material = _outline_material
	else:
		figure.material = null


func cargo_summary() -> String:
	var bits: PackedStringArray = []
	for k in GlobalUnits.WEAPON_KEYS:
		var amt := int(cargo.get(k, 0))
		if amt > 0:
			bits.append("%d %s" % [amt, GlobalUnits.weapon_name(k)])
	for k in GlobalUnits.MATERIAL_KEYS:
		var amt := int(cargo.get(k, 0))
		if amt > 0:
			bits.append("%d %s" % [amt, GlobalUnits.material_name(k)])
	if bits.is_empty():
		return "(empty)"
	return ", ".join(bits)


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if base_map == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if base_map.has_method("should_suppress_army_click") and base_map.should_suppress_army_click():
			return
		base_map.on_caravan_clicked(self)
		get_viewport().set_input_as_handled()
