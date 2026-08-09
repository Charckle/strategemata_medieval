extends Control

## Centered turn-start announcement: heraldry, lord name, season + year.
## Visible for 2s, then closes. Click anywhere to dismiss immediately.

signal closed

const HOLD_SEC := 2.0
const SHIELD_SIZE := 72
const DIALOG_MIN := Vector2(320, 180)

var _dialog: PanelContainer
var _shield: TextureRect
var _name_lbl: Label
var _date_lbl: Label
var _tween: Tween
var _built := false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func show_for(player, season_id: int, year: int) -> void:
	if not _built:
		_build_ui()
	_kill_tween()
	modulate = Color(1, 1, 1, 1)

	_shield.texture = Heraldry.texture_for_player(player, SHIELD_SIZE)
	_name_lbl.text = str(player.name_)
	_date_lbl.text = "%s %d" % [GlobalStuff.get_season_name(season_id), year]

	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	move_to_front()
	_start_auto_close()


func is_open() -> bool:
	return visible


func close() -> void:
	_kill_tween()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not visible:
		return
	visible = false
	modulate = Color(1, 1, 1, 1)
	closed.emit()


func _build_ui() -> void:
	if _built:
		return
	_built = true

	# Full-screen catcher so a click anywhere dismisses.
	var catcher := ColorRect.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.color = Color(0, 0, 0, 0.01)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_click_anywhere)
	add_child(catcher)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog = PanelContainer.new()
	_dialog.custom_minimum_size = DIALOG_MIN
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.07, 0.96)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.55, 0.42, 0.22, 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 24
	sb.content_margin_top = 20
	sb.content_margin_right = 24
	sb.content_margin_bottom = 20
	_dialog.add_theme_stylebox_override("panel", sb)
	center.add_child(_dialog)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(col)

	_shield = TextureRect.new()
	_shield.custom_minimum_size = Vector2(SHIELD_SIZE, SHIELD_SIZE)
	_shield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shield.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shield.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_shield)

	_name_lbl = Label.new()
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.add_theme_font_size_override("font_size", 22)
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name_lbl)

	_date_lbl = Label.new()
	_date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_lbl.add_theme_font_size_override("font_size", 16)
	_date_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62, 1))
	_date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_date_lbl)


func _start_auto_close() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_interval(HOLD_SEC)
	_tween.finished.connect(close, CONNECT_ONE_SHOT)


func _on_click_anywhere(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
