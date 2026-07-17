extends Node2D

## Pure VIEW of a force located on a map cell. The authoritative roster (which
## units, owned by whom) lives in the map's `forces` registry, keyed by
## `force_id`. This node only holds a reference to that id plus transient,
## per-turn movement state. `player_owner` mirrors the force's `controller`
## (who commands the army), not who contributes the most troops.

# Display/controller player id (mirrors forces[force_id].controller).
@export var player_owner = 0
# Base movement points before knights/wound modifiers (see effective_max_mp).
@export var movement_points := 10

# Designer-authored starting roster (Array of stack specs); see GlobalUnits.units_from_spec.
@export var start_units: Array = []

# Id into base_map.forces holding this army's authoritative roster.
var force_id: String = ""

var base_map
# Movement points left this turn; enter-cost is 1 on road, 2 off-road.
var movement_left := movement_points

var _outline_material: ShaderMaterial

const OUTLINE_SHADER := preload("res://objects/overworld/army/army_map_unit/selection_outline.gdshader")

const GREYED_MODULATE := Color(0.5, 0.5, 0.5, 1.0)
const NORMAL_MODULATE := Color(1, 1, 1, 1)


func _ready() -> void:
	# Read after the scene has applied the exported value.
	movement_left = movement_points


func setup_building() -> void:
	set_flags()


func set_flags():
	$Flag.setup_flag()


# Bind this view to a registry force and refresh derived state/visuals.
func bind_force(fid: String) -> void:
	force_id = fid
	refresh_from_force()


func refresh_from_force() -> void:
	var controller := get_controller()
	if controller != -1:
		player_owner = controller
	if base_map != null and base_map.get("players"):
		set_flags()
	# Roster changes (wounds, merges) can lower max MP mid-turn.
	clamp_movement_to_max()
	refresh_vip_crown()


func refresh_vip_crown() -> void:
	var crown := get_node_or_null("crown")
	if crown == null:
		return
	var show := false
	if base_map != null and force_id != "" and base_map.has_method("force_has_any_vip"):
		show = base_map.force_has_any_vip(force_id)
	crown.visible = show


func get_controller() -> int:
	if base_map != null and base_map.forces.has(force_id):
		return int(base_map.forces[force_id].get("controller", -1))
	return player_owner


func get_units() -> Array:
	if base_map == null or not base_map.forces.has(force_id):
		return []
	return base_map.forces[force_id]["units"]


func get_owner_set() -> Array:
	return GlobalUnits.owners_in(get_units())


func shows_ownership_triangle() -> bool:
	return true


# Wavy banners for every fighting-force owner except the army controller
# (triangle already shows them). Hostages / wounded / captured do not fly flags.
func get_banner_pids() -> Array:
	var controller := get_controller()
	var out: Array = []
	for pid in GlobalUnits.owners_in(GlobalUnits.fighting_units(get_units())):
		if int(pid) != controller:
			out.append(int(pid))
	return out


# Only the army controller can move/disband the force as a whole.
func is_controllable_by(pid: int) -> bool:
	return get_controller() == pid


func has_units_of(pid: int) -> bool:
	return GlobalUnits.men_of_owner(get_units(), pid) > 0


func effective_max_mp() -> int:
	return GlobalUnits.effective_movement_points(get_units(), movement_points)


func reset_movement() -> void:
	movement_left = effective_max_mp()


## Cap leftover MP after roster changes (merge/battle); does not refill.
func clamp_movement_to_max() -> void:
	movement_left = mini(movement_left, effective_max_mp())


func set_greyed(state: bool) -> void:
	var figure := get_node_or_null("figure")
	if figure == null:
		return
	figure.modulate = GREYED_MODULATE if state else NORMAL_MODULATE


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if base_map == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if base_map.has_method("should_suppress_army_click") and base_map.should_suppress_army_click():
			return
		# Clicking the selected army (same spot) opens its menu instead of moving.
		base_map.on_army_clicked(self)
		get_viewport().set_input_as_handled()


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
