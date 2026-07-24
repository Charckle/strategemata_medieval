extends Node
class_name PanelDragController

## Attach to a panel so its header can be dragged. Optional close button is ignored for drag start.
## Left-clicking anywhere on the panel (or its children) raises it above sibling menus.

var _panel: Control
var _header: Control
var _close_btn: Control
var _dragging := false
var _drag_offset := Vector2.ZERO


static func attach(panel: Control, header: Control, close_btn: Control = null) -> PanelDragController:
	if panel == null or header == null:
		return null
	var existing := panel.get_node_or_null("PanelDragController")
	if existing is PanelDragController:
		return existing as PanelDragController
	var ctrl := PanelDragController.new()
	ctrl.name = "PanelDragController"
	ctrl._panel = panel
	ctrl._header = header
	ctrl._close_btn = close_btn
	panel.add_child(ctrl)
	ctrl._wire()
	return ctrl


func _wire() -> void:
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_gui_input)
	for child in _header.get_children():
		# Buttons keep STOP so they remain clickable; everything else passes to header.
		if child is BaseButton:
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_PASS


func _input(event: InputEvent) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _panel.visible and _is_pointer_over_panel():
			_bring_to_front()
	if not _dragging:
		return
	if not _panel.visible:
		_dragging = false
		return
	if event is InputEventMouseMotion:
		_apply_drag_position()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		get_viewport().set_input_as_handled()


func _is_pointer_over_panel() -> bool:
	var hovered := _panel.get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered == _panel or _panel.is_ancestor_of(hovered)


func _on_header_gui_input(event: InputEvent) -> void:
	if _panel == null or not is_instance_valid(_panel) or not _panel.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _close_btn != null and is_instance_valid(_close_btn) \
					and _close_btn.get_global_rect().has_point(event.global_position):
				return
			_dragging = true
			_drag_offset = _panel.get_global_mouse_position() - _panel.global_position
			_bring_to_front()
			_header.accept_event()
		else:
			_dragging = false
			_header.accept_event()


func _apply_drag_position() -> void:
	var viewport_size := _panel.get_viewport().get_visible_rect().size
	var sz := _panel.size
	var new_pos := _panel.get_global_mouse_position() - _drag_offset
	var min_visible := 40.0
	new_pos.x = clampf(new_pos.x, -sz.x + min_visible, viewport_size.x - min_visible)
	new_pos.y = clampf(new_pos.y, 0.0, viewport_size.y - min_visible)
	_panel.global_position = new_pos


func _bring_to_front() -> void:
	var parent := _panel.get_parent()
	if parent != null:
		parent.move_child(_panel, parent.get_child_count() - 1)
