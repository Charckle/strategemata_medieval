extends Sprite2D

var _camera: Camera2D


func _ready() -> void:
	var map_root := get_parent()
	if map_root != null:
		_camera = map_root.get_node_or_null("Camera2D") as Camera2D
	centered = true


func _process(_delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	# Follow the camera so the shadow overlay always covers the visible area.
	global_position = _camera.get_screen_center_position()
	# Viewport texture is in screen pixels; scale into world space for zoom.
	var z := _camera.zoom
	if z.x != 0.0 and z.y != 0.0:
		scale = Vector2(1.0 / z.x, 1.0 / z.y)
