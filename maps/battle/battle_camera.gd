extends Camera2D

## Right-mouse drag pan, arrow-key pan, mouse-wheel zoom. Optional board clamp.
@export var zoom_min := 0.2
@export var zoom_max := 3.0
@export var zoom_step := 0.1
@export var arrow_pan_speed := 700.0
@export var clamp_to_board := true

var _prev_mouse_pos := Vector2.ZERO
var _rmb_panning := false
var _board_rect := Rect2()


func set_board_rect(rect: Rect2) -> void:
	_board_rect = rect
	_clamp_position()


func _process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir != Vector2.ZERO:
		position += dir * arrow_pan_speed * delta / zoom
		_clamp_position()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_pos := get_viewport().get_mouse_position()
		if _rmb_panning:
			position += (_prev_mouse_pos - mouse_pos) / zoom
			_clamp_position()
		else:
			_rmb_panning = true
		_prev_mouse_pos = mouse_pos
	else:
		_rmb_panning = false
		_prev_mouse_pos = get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var viewport_size := get_viewport_rect().size
			var viewport_center := viewport_size / 2.0
			var mouse_pos := get_viewport().get_mouse_position()
			var world_pos := position + (mouse_pos - viewport_center) / zoom

			var zoom_delta := zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else -zoom_step
			zoom += Vector2.ONE * zoom_delta
			zoom = zoom.clamp(Vector2.ONE * zoom_min, Vector2.ONE * zoom_max)

			position = world_pos - (mouse_pos - viewport_center) / zoom
			_clamp_position()
			get_viewport().set_input_as_handled()


func _clamp_position() -> void:
	if not clamp_to_board or _board_rect.size == Vector2.ZERO:
		return
	var half_view := get_viewport_rect().size / (zoom * 2.0)
	var min_pos := _board_rect.position + half_view
	var max_pos := _board_rect.position + _board_rect.size - half_view
	if min_pos.x > max_pos.x:
		position.x = _board_rect.get_center().x
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)
	if min_pos.y > max_pos.y:
		position.y = _board_rect.get_center().y
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)
