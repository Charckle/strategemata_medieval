extends Camera2D

## Right-mouse drag-to-pan, arrow-key pan (zoom-scaled), and mouse-wheel zoom.
var _prev_mouse_pos: Vector2
var _rmb_panning := false

const ZOOM_MIN := 0.25
const ZOOM_MAX := 4.0
const ZOOM_STEP := 0.1
## Screen-pixels-per-second for arrow-key pan (converted to world via zoom).
const ARROW_PAN_SPEED := 600.0


func _process(delta: float) -> void:
	if not _is_pan_blocked():
		var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if dir != Vector2.ZERO:
			position += dir * ARROW_PAN_SPEED * delta / zoom

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_pos := get_viewport().get_mouse_position()
		if _rmb_panning:
			position += (_prev_mouse_pos - mouse_pos) / zoom
		elif not _is_pan_blocked():
			# Deselect is handled by pathfinding on press; start pan once free of UI.
			_rmb_panning = true
		_prev_mouse_pos = mouse_pos
	else:
		_rmb_panning = false
		_prev_mouse_pos = get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _is_pan_blocked():
				return
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


func _is_pan_blocked() -> bool:
	var base := get_parent()
	if base == null:
		return false
	if base.has_method("is_mouse_over_gui") and base.is_mouse_over_gui():
		return true
	var gui := base.get_node_or_null("BasebottomGUI")
	if gui != null and gui.has_method("blocks_camera_pan") and gui.blocks_camera_pan():
		return true
	return false
