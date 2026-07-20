extends Node

## Floating army nicknames — opposite of province names:
## invisible when zoomed out (far), fade in as you zoom closer.

const ZOOM_HIDE := 0.9   # fully invisible at/below this (far)
const ZOOM_SHOW := 2.0   # fully visible at/above this (close)
const VIEWPORT_MARGIN := 80.0

var _base_map: Node2D
var _camera: Camera2D
var _armies: Node2D

var _last_cam_pos := Vector2(INF, INF)
var _last_cam_zoom := Vector2(INF, INF)
var _setting_enabled := true
var _force_update := true


func _ready() -> void:
	_base_map = get_parent() as Node2D
	_camera = _base_map.get_node("Camera2D") as Camera2D
	_armies = _base_map.get_node("armies") as Node2D
	_setting_enabled = GlobalSet.settings.get("show_army_names", 1) != 0


func _process(_delta: float) -> void:
	if not _setting_enabled:
		if _force_update:
			_hide_all()
			_force_update = false
		return
	if not _force_update and _camera.position == _last_cam_pos and _camera.zoom == _last_cam_zoom:
		return
	_last_cam_pos = _camera.position
	_last_cam_zoom = _camera.zoom
	_force_update = false
	_update_labels()


func refresh() -> void:
	_setting_enabled = GlobalSet.settings.get("show_army_names", 1) != 0
	_force_update = true


func _hide_all() -> void:
	if _armies == null:
		return
	for army in _armies.get_children():
		if army.has_method("set_name_label_alpha"):
			army.set_name_label_alpha(0.0)


func _update_labels() -> void:
	if _armies == null:
		return
	var alpha := _zoom_alpha()
	var inv_zoom := 1.0 / _camera.zoom.x
	var cam_pos := _camera.get_screen_center_position()
	var viewport_size := _camera.get_viewport_rect().size / _camera.zoom
	var half := viewport_size / 2.0
	var margin := Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN) / _camera.zoom
	var visible_rect := Rect2(cam_pos - half - margin, viewport_size + margin * 2.0)

	for army in _armies.get_children():
		if not army.has_method("get_name_label_world_position"):
			continue
		var world_pos: Vector2 = army.get_name_label_world_position()
		if not visible_rect.has_point(world_pos):
			army.set_name_label_alpha(0.0)
			continue
		army.set_name_label_alpha(alpha)
		army.set_name_label_scale(inv_zoom)


func _zoom_alpha() -> float:
	# Higher zoom.x = closer. Fade in toward ZOOM_SHOW.
	var t := inverse_lerp(ZOOM_HIDE, ZOOM_SHOW, _camera.zoom.x)
	return smoothstep(0.0, 1.0, t)
