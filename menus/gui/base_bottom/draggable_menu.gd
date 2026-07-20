extends PanelContainer

## Panel with header (title + close button). Centers on show. Drag via header.
## When custom_minimum_size is set, the panel is locked to that size (content should scroll inside).

@export var menu_title: String = "Menu"

var _close_btn: Button
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	# Capture clicks so Area2D map objects cannot be clicked through menus.
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_close_btn = $margin/vbox/header/close_btn
	_close_btn.pressed.connect(_on_close_pressed)
	var margin: Control = $margin
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox: Control = $margin/vbox
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	var header: Control = $margin/vbox/header
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_gui_input)
	var tabs: Control = $margin/vbox/tabs
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	tabs.gui_input.connect(_on_tabs_gui_input)
	for tab_child in tabs.get_children():
		if tab_child is Control:
			(tab_child as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	var title_lbl := header.get_node_or_null("title")
	if title_lbl is Label:
		title_lbl.text = menu_title
		# Pass events to header so title clicks start a drag.
		title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	_enforce_designed_size()
	_center_on_screen()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and custom_minimum_size != Vector2.ZERO:
		var target := _designed_size()
		if not size.is_equal_approx(target):
			# Keep the designed size; content scrolls inside tabs.
			size = target


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_apply_drag_position()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		get_viewport().set_input_as_handled()


func _designed_size() -> Vector2:
	if custom_minimum_size == Vector2.ZERO:
		return size
	var target := custom_minimum_size
	var viewport_size := get_viewport_rect().size
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		target.x = minf(target.x, viewport_size.x)
		target.y = minf(target.y, viewport_size.y)
	return target


func _enforce_designed_size() -> void:
	if custom_minimum_size == Vector2.ZERO:
		return
	var target := _designed_size()
	if size.is_equal_approx(target):
		return
	size = target
	offset_right = offset_left + target.x
	offset_bottom = offset_top + target.y


func _center_on_screen() -> void:
	_enforce_designed_size()
	var viewport_size := get_viewport_rect().size
	var sz := _designed_size()
	var left := viewport_size.x / 2.0 - sz.x / 2.0
	var top := viewport_size.y / 2.0 - sz.y / 2.0
	# Keep the header on-screen even if the panel is taller than the viewport.
	left = clampf(left, 0.0, maxf(0.0, viewport_size.x - sz.x))
	top = clampf(top, 0.0, maxf(0.0, viewport_size.y - sz.y))
	offset_left = left
	offset_top = top
	offset_right = offset_left + sz.x
	offset_bottom = offset_top + sz.y


func _on_close_pressed() -> void:
	_dragging = false
	visible = false


func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _close_btn.get_global_rect().has_point(event.global_position):
				return
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			_bring_self_to_front()
			accept_event()
		else:
			_dragging = false
			accept_event()


func _on_tabs_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_bring_self_to_front()


func _apply_drag_position() -> void:
	var viewport_size := get_viewport_rect().size
	var sz := size
	var new_pos := get_global_mouse_position() - _drag_offset
	# Keep at least a strip of the header on-screen.
	var min_visible := 40.0
	new_pos.x = clampf(new_pos.x, -sz.x + min_visible, viewport_size.x - min_visible)
	new_pos.y = clampf(new_pos.y, 0.0, viewport_size.y - min_visible)
	global_position = new_pos


func _bring_self_to_front() -> void:
	var parent := get_parent()
	parent.move_child(self, parent.get_child_count() - 1)


func show_menu() -> void:
	_center_on_screen()
	visible = true
