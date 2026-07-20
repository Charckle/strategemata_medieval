extends Node2D

## Map transport fleet. `ship_count` stacks (capacity = count × 100).
## Embarked armies stay in `base_map.forces` with location kind "aboard";
## this node holds `aboard_force_ids` and map movement state.

@export var player_owner: int = 0
@export var movement_points := 20
@export var ship_count: int = 1

var base_map
var fleet_id: String = ""
## Force ids currently aboard (whole armies).
var aboard_force_ids: Array = []
var movement_left := movement_points

## When multiple fleets share a tile, only the primary draws the figure/flag.
var stack_primary: bool = true
var _stack_owner_pids: Array = []

var _outline_material: ShaderMaterial

const OUTLINE_SHADER := preload("res://objects/overworld/army/army_map_unit/selection_outline.gdshader")
const GREYED_MODULATE := Color(0.5, 0.5, 0.5, 1.0)
const NORMAL_MODULATE := Color(1, 1, 1, 1)


func _ready() -> void:
	movement_left = movement_points
	if fleet_id == "":
		fleet_id = String(name)


func is_fleet() -> bool:
	return true


func setup_building() -> void:
	set_flags()


func set_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag == null:
		return
	if not stack_primary:
		flag.visible = false
		return
	flag.visible = true
	flag.setup_flag()


func get_controller() -> int:
	return player_owner


func is_controllable_by(pid: int) -> bool:
	return player_owner == pid


func shows_ownership_triangle() -> bool:
	# Stacked fleets: small banners only (one per owner color).
	return _stack_owner_pids.size() <= 1


func get_banner_pids() -> Array:
	if _stack_owner_pids.size() > 1:
		var out: Array = []
		for pid in _stack_owner_pids:
			out.append(int(pid))
		return out
	return []


func get_owner_set() -> Array:
	return [player_owner]


func capacity() -> int:
	return ship_count * GlobalUnits.TRANSPORT_SHIP_CAPACITY


func men_aboard() -> int:
	if base_map == null:
		return 0
	var total := 0
	for fid in aboard_force_ids:
		if base_map.forces.has(fid):
			total += GlobalUnits.total_men(base_map.forces[fid]["units"])
	return total


func free_capacity() -> int:
	return maxi(0, capacity() - men_aboard())


func has_army_aboard() -> bool:
	return not aboard_force_ids.is_empty()


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


func set_stack_display(primary: bool, owner_pids: Array) -> void:
	stack_primary = primary
	_stack_owner_pids = owner_pids.duplicate()
	var figure := get_node_or_null("figure")
	if figure != null:
		figure.visible = primary
	set_flags()


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if base_map == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if base_map.has_method("should_suppress_army_click") and base_map.should_suppress_army_click():
			return
		base_map.on_fleet_clicked(self)
		get_viewport().set_input_as_handled()
