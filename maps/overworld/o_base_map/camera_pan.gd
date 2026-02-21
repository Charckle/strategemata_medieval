extends Camera2D

## Enables middle-mouse drag-to-pan and mouse-wheel zoom on the map.
var _prev_mouse_pos: Vector2

const ZOOM_MIN := 0.25
const ZOOM_MAX := 4.0
const ZOOM_STEP := 0.1


func _process(_delta: float) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var mouse_pos := get_viewport().get_mouse_position()
		position += _prev_mouse_pos - mouse_pos
		_prev_mouse_pos = mouse_pos
	else:
		_prev_mouse_pos = get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var viewport_size := get_viewport_rect().size
			var viewport_center := viewport_size / 2.0
			var mouse_pos := get_viewport().get_mouse_position()

			# World position under cursor before zoom
			var world_pos := position + (mouse_pos - viewport_center) / zoom

			# Apply zoom
			var zoom_delta := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -ZOOM_STEP
			zoom += Vector2.ONE * zoom_delta
			zoom = zoom.clamp(Vector2.ONE * ZOOM_MIN, Vector2.ONE * ZOOM_MAX)

			# Move camera so the same world point stays under the cursor
			position = world_pos - (mouse_pos - viewport_center) / zoom

			get_viewport().set_input_as_handled()
