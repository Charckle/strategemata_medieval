extends Control

## Shared heraldry draft modal (New Game + in-game Settings).
## open(heraldry, title) → edit → accepted(dict) or cancelled.

signal accepted(heraldry: Dictionary)
signal cancelled

const DIALOG_SIZE := Vector2(720, 560)
const SHIELD_SIZE := 128

var _dialog: PanelContainer
var _title_lbl: Label
var _preview: TextureRect
var _code_edit: LineEdit
var _code_hint: Label
var _opt_division: OptionButton
var _fields_box: VBoxContainer
var _field_rows: Array = []
var _tincture_keys: Array = []
var _draft: Dictionary = {}
var _syncing := false
var _syncing_code := false
var _built := false
var _code_normal_sb: StyleBox
var _code_invalid_sb: StyleBoxFlat


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func open(initial: Dictionary = {}, title: String = "Edit shield") -> void:
	if not _built:
		_build_ui()
	_draft = Heraldry.normalize(initial if initial is Dictionary else {})
	_title_lbl.text = title
	_sync_editors()
	visible = true
	move_to_front()


func close() -> void:
	visible = false
	_draft = {}


func is_open() -> bool:
	return visible


func _build_ui() -> void:
	if _built:
		return
	_built = true
	_tincture_keys = Heraldry.field_tincture_options()

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog = PanelContainer.new()
	_dialog.custom_minimum_size = DIALOG_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.07, 0.98)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.05, 0.03, 0.015, 1)
	sb.set_corner_radius_all(4)
	_dialog.add_theme_stylebox_override("panel", sb)
	center.add_child(_dialog)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_bottom", 14)
	_dialog.add_child(m)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	m.add_child(col)

	_title_lbl = Label.new()
	_title_lbl.text = "Edit shield"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 20)
	col.add_child(_title_lbl)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)

	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(SHIELD_SIZE, SHIELD_SIZE)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_preview)

	var top_right := VBoxContainer.new()
	top_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_right.add_theme_constant_override("separation", 8)
	top.add_child(top_right)

	var hint := Label.new()
	hint.text = "Each half/quarter has its own base, ink, pattern, and charges."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_right.add_child(hint)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	top_right.add_child(code_row)
	var code_lbl := Label.new()
	code_lbl.text = "Code"
	code_lbl.custom_minimum_size = Vector2(48, 0)
	code_row.add_child(code_lbl)
	_code_edit = LineEdit.new()
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.placeholder_text = "Shield code"
	_code_edit.caret_blink = true
	_code_edit.text_changed.connect(_on_code_text_changed)
	_code_edit.focus_exited.connect(_on_code_focus_exited)
	code_row.add_child(_code_edit)
	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.tooltip_text = "Copy shield code"
	copy_btn.pressed.connect(_on_copy_code_pressed)
	code_row.add_child(copy_btn)
	_code_hint = Label.new()
	_code_hint.text = "Edits update the code; paste a code to load a shield."
	_code_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_code_hint.add_theme_font_size_override("font_size", 12)
	_code_hint.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1))
	top_right.add_child(_code_hint)
	_code_normal_sb = _code_edit.get_theme_stylebox("normal")
	if _code_normal_sb is StyleBoxFlat:
		_code_invalid_sb = (_code_normal_sb as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		_code_invalid_sb = StyleBoxFlat.new()
		_code_invalid_sb.bg_color = Color(0.22, 0.16, 0.1, 1)
		_code_invalid_sb.set_content_margin_all(6)
	_code_invalid_sb.bg_color = Color(0.35, 0.12, 0.1, 1)
	_code_invalid_sb.set_border_width_all(2)
	_code_invalid_sb.border_color = Color(0.85, 0.25, 0.2, 1)

	var roll_btn := Button.new()
	roll_btn.text = "Random"
	roll_btn.custom_minimum_size = Vector2(120, 36)
	roll_btn.pressed.connect(_on_random_pressed)
	top_right.add_child(roll_btn)

	var div_row := HBoxContainer.new()
	div_row.add_theme_constant_override("separation", 10)
	top_right.add_child(div_row)
	var div_lbl := Label.new()
	div_lbl.text = "Division"
	div_lbl.custom_minimum_size = Vector2(80, 0)
	div_row.add_child(div_lbl)
	_opt_division = OptionButton.new()
	_opt_division.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in Heraldry.division_labels():
		_opt_division.add_item(str(item))
	_opt_division.item_selected.connect(_on_division_changed)
	div_row.add_child(_opt_division)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_fields_box = VBoxContainer.new()
	_fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_fields_box)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(action_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(_on_cancel)
	action_row.add_child(cancel_btn)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(100, 40)
	accept_btn.pressed.connect(_on_accept)
	action_row.add_child(accept_btn)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_cancel()


func _on_cancel() -> void:
	close()
	cancelled.emit()


func _on_accept() -> void:
	var result := Heraldry.normalize(_draft)
	close()
	accepted.emit(result)


func _on_random_pressed() -> void:
	_draft = Heraldry.random_heraldry()
	_sync_editors()


func _sync_editors() -> void:
	_draft = Heraldry.normalize(_draft)
	_preview.texture = Heraldry.make_texture(_draft, SHIELD_SIZE)
	_syncing = true
	var division := clampi(int(_draft.get("division", 0)), 0, 2)
	_opt_division.select(division)
	_rebuild_field_editors(division, _draft.get("fields", []))
	_syncing = false
	_refresh_code_field()


func _refresh_code_field(force: bool = false) -> void:
	if _code_edit == null:
		return
	if not force and _code_edit.has_focus():
		return
	_syncing_code = true
	_code_edit.text = Heraldry.to_code(_draft)
	_set_code_invalid(false)
	_syncing_code = false


func _on_code_text_changed(new_text: String) -> void:
	if _syncing_code:
		return
	var s := new_text.strip_edges()
	if s.is_empty():
		_set_code_invalid(false)
		return
	var parsed := Heraldry.from_code(s)
	if parsed.is_empty():
		_set_code_invalid(true)
		return
	_set_code_invalid(false)
	_draft = Heraldry.normalize(parsed)
	_preview.texture = Heraldry.make_texture(_draft, SHIELD_SIZE)
	_syncing = true
	var division := clampi(int(_draft.get("division", 0)), 0, 2)
	_opt_division.select(division)
	_rebuild_field_editors(division, _draft.get("fields", []))
	_syncing = false


func _on_code_focus_exited() -> void:
	if _code_edit == null:
		return
	var s := _code_edit.text.strip_edges()
	if s.is_empty():
		_refresh_code_field(true)
		return
	var parsed := Heraldry.from_code(s)
	if parsed.is_empty():
		# Restore canonical code for the current draft.
		_refresh_code_field(true)
		return
	_draft = Heraldry.normalize(parsed)
	_sync_editors()


func _on_copy_code_pressed() -> void:
	if _code_edit == null:
		return
	var s := _code_edit.text.strip_edges()
	if s.is_empty():
		s = Heraldry.to_code(_draft)
	DisplayServer.clipboard_set(s)


func _set_code_invalid(invalid: bool) -> void:
	if _code_edit == null:
		return
	if invalid:
		_code_edit.add_theme_stylebox_override("normal", _code_invalid_sb)
		_code_edit.add_theme_stylebox_override("focus", _code_invalid_sb)
		if _code_hint != null:
			_code_hint.text = "Invalid shield code."
			_code_hint.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35, 1))
	else:
		if _code_normal_sb != null:
			_code_edit.add_theme_stylebox_override("normal", _code_normal_sb)
		_code_edit.remove_theme_stylebox_override("focus")
		if _code_hint != null:
			_code_hint.text = "Edits update the code; paste a code to load a shield."
			_code_hint.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1))


func _rebuild_field_editors(division: int, keep_values: Array = []) -> void:
	while _fields_box.get_child_count() > 0:
		var ch := _fields_box.get_child(0)
		_fields_box.remove_child(ch)
		ch.free()
	_field_rows.clear()
	var labels := Heraldry.field_labels(division)
	var tincture_names: Array = _tincture_keys.map(func(k): return Heraldry.tincture_display_name(str(k)))
	# Side-by-side columns when multiple fields (wider dialog).
	var grid := GridContainer.new()
	grid.columns = 2 if labels.size() > 1 else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	_fields_box.add_child(grid)
	for i in labels.size():
		var wrap := VBoxContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_theme_constant_override("separation", 4)
		var title := Label.new()
		title.text = str(labels[i])
		title.add_theme_font_size_override("font_size", 14)
		wrap.add_child(title)
		var opts := GridContainer.new()
		opts.columns = 2
		opts.add_theme_constant_override("h_separation", 8)
		opts.add_theme_constant_override("v_separation", 4)
		var base_opt := _add_field_opt(opts, "Base", tincture_names)
		var ink_opt := _add_field_opt(opts, "Ink", tincture_names)
		var pattern_opt := _add_field_opt(opts, "Pattern", Heraldry.pattern_labels())
		var charge_opt := _add_field_opt(opts, "Charges", Heraldry.charge_layout_labels())
		var type_opt := _add_field_opt(opts, "Charge", Heraldry.charge_type_labels())
		wrap.add_child(opts)
		grid.add_child(wrap)
		if i < keep_values.size() and keep_values[i] is Dictionary:
			var f: Dictionary = keep_values[i]
			_select_key(base_opt, str(f.get("base", "azure")))
			_select_key(ink_opt, str(f.get("ink", "or")))
			pattern_opt.select(clampi(int(f.get("pattern", 0)), 0, pattern_opt.item_count - 1))
			charge_opt.select(clampi(int(f.get("charge", 0)), 0, charge_opt.item_count - 1))
			type_opt.select(clampi(int(f.get("charge_type", 0)), 0, type_opt.item_count - 1))
		_field_rows.append({
			"base": base_opt, "ink": ink_opt, "pattern": pattern_opt,
			"charge": charge_opt, "charge_type": type_opt,
		})
		base_opt.item_selected.connect(_on_draft_changed)
		ink_opt.item_selected.connect(_on_draft_changed)
		pattern_opt.item_selected.connect(_on_draft_changed)
		charge_opt.item_selected.connect(_on_draft_changed)
		type_opt.item_selected.connect(_on_draft_changed)


func _add_field_opt(parent: GridContainer, label_text: String, items: Variant) -> OptionButton:
	var lbl := Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		opt.add_item(str(item))
	parent.add_child(opt)
	return opt


func _select_key(opt: OptionButton, key: String) -> void:
	var i := _tincture_keys.find(key)
	if i < 0:
		i = 0
	opt.select(clampi(i, 0, opt.item_count - 1))


func _on_division_changed(_idx: int = 0) -> void:
	if _syncing:
		return
	var prev := _fields_from_editors()
	_syncing = true
	_rebuild_field_editors(_opt_division.selected, prev)
	_syncing = false
	_on_draft_changed()


func _fields_from_editors() -> Array:
	var fields: Array = []
	for row in _field_rows:
		var base := "azure"
		var ink := "or"
		if row["base"].selected >= 0 and row["base"].selected < _tincture_keys.size():
			base = str(_tincture_keys[row["base"].selected])
		if row["ink"].selected >= 0 and row["ink"].selected < _tincture_keys.size():
			ink = str(_tincture_keys[row["ink"].selected])
		fields.append({
			"base": base,
			"ink": ink,
			"pattern": int(row["pattern"].selected),
			"charge": int(row["charge"].selected),
			"charge_type": int(row["charge_type"].selected),
		})
	if fields.is_empty():
		fields.append(Heraldry.default_field())
	return fields


func _on_draft_changed(_idx: int = 0) -> void:
	if _syncing:
		return
	var fields := _fields_from_editors()
	var raw := {
		"primary": str(fields[0].get("base", "azure")),
		"division": _opt_division.selected,
		"fields": fields,
	}
	_draft = Heraldry.normalize(raw)
	_preview.texture = Heraldry.make_texture(_draft, SHIELD_SIZE)
	if _draft.has("fields") and _draft["fields"] is Array:
		_syncing = true
		var af: Array = _draft["fields"]
		for i in mini(_field_rows.size(), af.size()):
			var f: Dictionary = af[i]
			_select_key(_field_rows[i]["ink"], str(f.get("ink", "or")))
			_select_key(_field_rows[i]["base"], str(f.get("base", "azure")))
		_syncing = false
	_refresh_code_field()
