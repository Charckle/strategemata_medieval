extends Node

## Updates province map labels based on camera zoom, position, and settings.

const ZOOM_SHOW := 0.75
const ZOOM_HIDE := 2.0
const VIEWPORT_MARGIN := 80.0

var _base_map: Node2D
var _camera: Camera2D
var _provinces: Node2D

var _last_cam_pos := Vector2(INF, INF)
var _last_cam_zoom := Vector2(INF, INF)
var _setting_enabled := true
var _force_update := true


func _ready() -> void:
	_base_map = get_parent() as Node2D
	_camera = _base_map.get_node("Camera2D") as Camera2D
	_provinces = _base_map.get_node("provinces") as Node2D
	_setting_enabled = GlobalSet.settings.get("show_province_names", 1) != 0


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
	_setting_enabled = GlobalSet.settings.get("show_province_names", 1) != 0
	_force_update = true


func _hide_all() -> void:
	for prov in _provinces.get_children():
		if prov.has_method("set_map_label_alpha"):
			prov.set_map_label_alpha(0.0)


func _update_labels() -> void:
	var alpha := _zoom_alpha()
	var inv_zoom := 1.0 / _camera.zoom.x
	var cam_pos := _camera.get_screen_center_position()
	var viewport_size := _camera.get_viewport_rect().size / _camera.zoom
	var half := viewport_size / 2.0
	var margin := Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN) / _camera.zoom
	var visible_rect := Rect2(cam_pos - half - margin, viewport_size + margin * 2.0)

	for prov in _provinces.get_children():
		if not prov.has_method("get_label_world_position"):
			continue
		var world_pos: Vector2 = prov.get_label_world_position()
		if not visible_rect.has_point(world_pos):
			prov.set_map_label_alpha(0.0)
			continue
		prov.set_map_label_alpha(alpha)
		prov.set_map_label_scale(inv_zoom)


func _zoom_alpha() -> float:
	var t := inverse_lerp(ZOOM_HIDE, ZOOM_SHOW, _camera.zoom.x)
	return smoothstep(0.0, 1.0, t)
