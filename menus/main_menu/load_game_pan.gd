extends PanelContainer

## Load / rename / delete named saves (+ autosave).

var _list_box: VBoxContainer
var _empty_lbl: Label
var _rename_dialog: AcceptDialog
var _rename_edit: LineEdit
var _rename_id: String = ""
var _delete_dialog: ConfirmationDialog
var _delete_id: String = ""


func _ready() -> void:
	_build_ui()


func open_panel() -> void:
	visible = true
	refresh_list()


func _build_ui() -> void:
	while get_child_count() > 0:
		var ch := get_child(0)
		remove_child(ch)
		ch.free()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Load Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	root.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)

	_empty_lbl = Label.new()
	_empty_lbl.text = "No saved games."
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_empty_lbl)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(100, 40)
	back.pressed.connect(func(): visible = false)
	root.add_child(back)

	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename save"
	_rename_dialog.ok_button_text = "Rename"
	var box := VBoxContainer.new()
	_rename_edit = LineEdit.new()
	box.add_child(_rename_edit)
	_rename_dialog.add_child(box)
	_style_dialog_panel(_rename_dialog)
	add_child(_rename_dialog)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete save"
	_delete_dialog.dialog_text = "Delete this save permanently?"
	_style_dialog_panel(_delete_dialog)
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)


func _style_dialog_panel(dialog: Window) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.07, 0.98)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.05, 0.03, 0.015, 1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 4
	dialog.add_theme_stylebox_override("panel", sb)
	dialog.add_theme_stylebox_override("embedded_border", sb)
	dialog.add_theme_stylebox_override("embedded_unfocused_border", sb)
	dialog.transparent = false


func refresh_list() -> void:
	while _list_box.get_child_count() > 0:
		var ch := _list_box.get_child(0)
		_list_box.remove_child(ch)
		ch.free()
	var saves := SaveGame.list_saves()
	_empty_lbl.visible = saves.is_empty()
	for meta in saves:
		_list_box.add_child(_make_row(meta))


func _make_row(meta: Dictionary) -> PanelContainer:
	var id := str(meta.get("id", ""))
	var panel := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = str(meta.get("display_name", id))
	name_lbl.add_theme_font_size_override("font_size", 16)
	col.add_child(name_lbl)

	var detail := Label.new()
	var year := int(meta.get("year", 1100))
	var season_name := str(meta.get("season_name", ""))
	var turn := int(meta.get("turn", 0))
	var lord := str(meta.get("lord_name", ""))
	detail.text = "%s, Year %d  ·  Turn %d  ·  %s" % [season_name, year, turn, lord]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(detail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func(): _on_load(id))
	row.add_child(load_btn)

	var is_auto := bool(meta.get("is_autosave", id == SaveGame.AUTOSAVE_ID))
	if not is_auto:
		var ren := Button.new()
		ren.text = "Rename"
		ren.pressed.connect(func(): _on_rename(id, str(meta.get("display_name", ""))))
		row.add_child(ren)

	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func(): _on_delete(id))
	row.add_child(del)

	return panel


func _on_load(save_id: String) -> void:
	if SaveGame.begin_load(save_id):
		visible = false


func _on_rename(save_id: String, current: String) -> void:
	_rename_id = save_id
	_rename_edit.text = current
	_rename_dialog.popup_centered(Vector2(320, 100))


func _on_rename_confirmed() -> void:
	if _rename_id.is_empty():
		return
	SaveGame.rename_save(_rename_id, _rename_edit.text)
	_rename_id = ""
	refresh_list()


func _on_delete(save_id: String) -> void:
	_delete_id = save_id
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _delete_id.is_empty():
		return
	SaveGame.delete_save(_delete_id)
	_delete_id = ""
	refresh_list()
