extends PanelContainer

## Panel with header (title + close button). Centers on show.

@export var menu_title: String = "Menu"

var _close_btn: Button


func _ready() -> void:
	_close_btn = $margin/vbox/header/close_btn
	_close_btn.pressed.connect(_on_close_pressed)
	$margin/vbox/header.gui_input.connect(_on_header_or_tabs_gui_input)
	$margin/vbox/tabs.gui_input.connect(_on_header_or_tabs_gui_input)
	var title_lbl := $margin/vbox/header.get_node_or_null("title")
	if title_lbl is Label:
		title_lbl.text = menu_title
	_center_on_screen()


func _center_on_screen() -> void:
	var viewport_size := get_viewport_rect().size
	var sz := size
	offset_left = viewport_size.x / 2.0 - sz.x / 2.0
	offset_top = viewport_size.y / 2.0 - sz.y / 2.0
	offset_right = offset_left + sz.x
	offset_bottom = offset_top + sz.y


func _on_close_pressed() -> void:
	visible = false


func _on_header_or_tabs_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_bring_self_to_front()


func _bring_self_to_front() -> void:
	var parent := get_parent()
	parent.move_child(self, parent.get_child_count() - 1)


func show_menu() -> void:
	_center_on_screen()
	visible = true
