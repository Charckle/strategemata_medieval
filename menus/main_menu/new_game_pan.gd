extends PanelContainer

## New Game setup: add Human/AI slots, edit human name + heraldry, pick AI doctrine.
## Shield editing is a draft popup (Accept / Cancel); row has quick Random.

const SHIELD_SIZE := 72
const ROW_SHIELD_SIZE := 36
const TYPE_HUMAN := 0
const TYPE_AI := 1

var _slots: Array = []  # Array[Dictionary]
var _rebuild_busy := false

var _slots_box: VBoxContainer
var _add_btn: Button

## Shield draft popup state
var _shield_overlay: Control
var _shield_dialog: PanelContainer
var _edit_slot_idx := -1
var _draft_heraldry: Dictionary = {}
var _heraldry_preview: TextureRect
var _opt_division: OptionButton
var _fields_box: VBoxContainer
var _field_rows: Array = []
var _tincture_keys: Array = []
var _heraldry_syncing := false
var _heraldry_editors_built := false


func _ready() -> void:
	_build_ui()
	reset_to_defaults()


func reset_to_defaults() -> void:
	_close_shield_editor(false)
	_slots = [GlobalSet.make_default_human_slot()]
	_rebuild_slot_list()


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
	title.text = "New Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Up to %d lords. Leftover provinces become councils." % GlobalSet.MAX_SETUP_PLAYERS
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	root.add_child(scroll)

	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_slots_box)

	_add_btn = Button.new()
	_add_btn.text = "Add player"
	_add_btn.pressed.connect(_on_add_pressed)
	root.add_child(_add_btn)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(btns)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(100, 40)
	back.pressed.connect(_on_back_pressed)
	btns.add_child(back)

	var start_btn := Button.new()
	start_btn.text = "Start"
	start_btn.custom_minimum_size = Vector2(120, 40)
	start_btn.pressed.connect(_on_start_pressed)
	btns.add_child(start_btn)

	_build_shield_overlay()


func _build_shield_overlay() -> void:
	_shield_overlay = Control.new()
	_shield_overlay.name = "shield_overlay"
	_shield_overlay.visible = false
	_shield_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shield_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.gui_input.connect(_on_shield_dim_input)
	_shield_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_overlay.add_child(center)

	_shield_dialog = PanelContainer.new()
	_shield_dialog.custom_minimum_size = Vector2(360, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.07, 0.98)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.05, 0.03, 0.015, 1)
	sb.set_corner_radius_all(4)
	_shield_dialog.add_theme_stylebox_override("panel", sb)
	center.add_child(_shield_dialog)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_bottom", 14)
	_shield_dialog.add_child(m)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)

	var h_title := Label.new()
	h_title.name = "shield_title"
	h_title.text = "Edit shield"
	h_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_title.add_theme_font_size_override("font_size", 18)
	col.add_child(h_title)

	_heraldry_preview = TextureRect.new()
	_heraldry_preview.custom_minimum_size = Vector2(SHIELD_SIZE, SHIELD_SIZE)
	_heraldry_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heraldry_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_heraldry_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_heraldry_preview)

	var roll_btn := Button.new()
	roll_btn.text = "Random"
	roll_btn.pressed.connect(_on_draft_random_pressed)
	col.add_child(roll_btn)

	_tincture_keys = Heraldry.field_tincture_options()

	var div_row := HBoxContainer.new()
	div_row.add_theme_constant_override("separation", 8)
	col.add_child(div_row)
	var div_lbl := Label.new()
	div_lbl.text = "Division"
	div_lbl.custom_minimum_size = Vector2(70, 0)
	div_row.add_child(div_lbl)
	_opt_division = OptionButton.new()
	_opt_division.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in Heraldry.division_labels():
		_opt_division.add_item(str(item))
	_opt_division.item_selected.connect(_on_division_changed)
	div_row.add_child(_opt_division)

	_fields_box = VBoxContainer.new()
	_fields_box.add_theme_constant_override("separation", 6)
	col.add_child(_fields_box)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(action_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(90, 36)
	cancel_btn.pressed.connect(_on_shield_cancel)
	action_row.add_child(cancel_btn)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(90, 36)
	accept_btn.pressed.connect(_on_shield_accept)
	action_row.add_child(accept_btn)

	_heraldry_editors_built = true


func _on_shield_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_shield_cancel()


func _rebuild_slot_list() -> void:
	_rebuild_busy = true
	while _slots_box.get_child_count() > 0:
		var ch := _slots_box.get_child(0)
		_slots_box.remove_child(ch)
		ch.free()

	for i in _slots.size():
		_slots_box.add_child(_make_slot_row(i))

	_add_btn.disabled = _slots.size() >= GlobalSet.MAX_SETUP_PLAYERS
	_add_btn.text = "Add player" if _slots.size() < GlobalSet.MAX_SETUP_PLAYERS else "Max players"
	_rebuild_busy = false


func _make_slot_row(idx: int) -> PanelContainer:
	var slot: Dictionary = _slots[idx]
	var is_human := str(slot.get("type", "human")) == "human"
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)

	var type_opt := OptionButton.new()
	type_opt.add_item("Human", TYPE_HUMAN)
	type_opt.add_item("AI", TYPE_AI)
	type_opt.select(TYPE_HUMAN if is_human else TYPE_AI)
	type_opt.custom_minimum_size = Vector2(90, 0)
	type_opt.item_selected.connect(func(i): _on_type_changed(idx, i))
	top.add_child(type_opt)

	var name_edit := LineEdit.new()
	name_edit.text = str(slot.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.editable = is_human
	name_edit.placeholder_text = "Lord name"
	name_edit.text_changed.connect(func(t): _on_name_changed(idx, t))
	top.add_child(name_edit)

	if is_human:
		var roll_name := Button.new()
		roll_name.text = "Name"
		roll_name.tooltip_text = "Random name"
		roll_name.pressed.connect(func(): _on_reroll_name(idx))
		top.add_child(roll_name)

	var shield := TextureRect.new()
	shield.name = "slot_shield"
	shield.custom_minimum_size = Vector2(ROW_SHIELD_SIZE, ROW_SHIELD_SIZE)
	shield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shield.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var h: Dictionary = slot.get("heraldry", {})
	if h is Dictionary and Heraldry.is_set(h):
		shield.texture = Heraldry.make_texture(Heraldry.normalize(h), ROW_SHIELD_SIZE)
	top.add_child(shield)

	var roll_shield := Button.new()
	roll_shield.text = "Random"
	roll_shield.tooltip_text = "Random shield"
	roll_shield.pressed.connect(func(): _on_quick_random_shield(idx))
	top.add_child(roll_shield)

	if is_human:
		var edit_btn := Button.new()
		edit_btn.text = "Edit"
		edit_btn.tooltip_text = "Edit shield"
		edit_btn.pressed.connect(func(): _open_shield_editor(idx))
		top.add_child(edit_btn)

	if not is_human:
		var doc := OptionButton.new()
		doc.add_item("Defensive", 0)
		doc.add_item("Offensive", 1)
		var d := str(slot.get("ai_doctrine", LordAI.DOCTRINE_DEFENSE))
		doc.select(1 if d == LordAI.DOCTRINE_OFFENSE else 0)
		doc.item_selected.connect(func(i): _on_doctrine_changed(idx, i))
		top.add_child(doc)

	if _slots.size() > 1 and (not is_human or _human_count() > 1):
		var rem := Button.new()
		rem.text = "X"
		rem.tooltip_text = "Remove"
		rem.pressed.connect(func(): _on_remove(idx))
		top.add_child(rem)

	return panel


func _human_count() -> int:
	var n := 0
	for s in _slots:
		if str(s.get("type", "")) == "human":
			n += 1
	return n


func _on_add_pressed() -> void:
	if _slots.size() >= GlobalSet.MAX_SETUP_PLAYERS:
		return
	var used := _used_names()
	var slot := GlobalSet.make_default_ai_slot()
	while used.has(str(slot["name"])):
		slot["name"] = GlobalSet.random_lord_name(used)
	_slots.append(slot)
	_rebuild_slot_list()


func _used_names() -> Dictionary:
	var used := {}
	for s in _slots:
		used[str(s.get("name", ""))] = true
	return used


func _on_remove(idx: int) -> void:
	if idx < 0 or idx >= _slots.size() or _slots.size() <= 1:
		return
	var was_human := str(_slots[idx].get("type", "")) == "human"
	if was_human and _human_count() <= 1:
		return
	if _edit_slot_idx == idx:
		_close_shield_editor(false)
	_slots.remove_at(idx)
	if _edit_slot_idx > idx:
		_edit_slot_idx -= 1
	_rebuild_slot_list()


func _on_type_changed(idx: int, type_idx: int) -> void:
	if idx < 0 or idx >= _slots.size() or _rebuild_busy:
		return
	var want_human := type_idx == TYPE_HUMAN
	var cur_human := str(_slots[idx].get("type", "")) == "human"
	if want_human == cur_human:
		return
	if not want_human and _human_count() <= 1:
		_rebuild_slot_list()
		return
	if _edit_slot_idx == idx:
		_close_shield_editor(false)
	if want_human:
		_slots[idx] = {
			"type": "human",
			"name": str(_slots[idx].get("name", GlobalSet.random_lord_name())),
			"heraldry": _slots[idx].get("heraldry", Heraldry.random_heraldry()),
		}
	else:
		var doctrine := LordAI.DOCTRINE_OFFENSE if randf() < 0.5 else LordAI.DOCTRINE_DEFENSE
		_slots[idx] = {
			"type": "ai",
			"name": str(_slots[idx].get("name", GlobalSet.random_lord_name())),
			"heraldry": _slots[idx].get("heraldry", Heraldry.random_heraldry()),
			"ai_doctrine": doctrine,
		}
	_rebuild_slot_list()


func _on_name_changed(idx: int, text: String) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	if str(_slots[idx].get("type", "")) != "human":
		return
	_slots[idx]["name"] = text


func _on_reroll_name(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	if str(_slots[idx].get("type", "")) != "human":
		return
	var used := _used_names()
	used.erase(str(_slots[idx].get("name", "")))
	_slots[idx]["name"] = GlobalSet.random_lord_name(used)
	_rebuild_slot_list()


func _on_doctrine_changed(idx: int, item_idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	if str(_slots[idx].get("type", "")) != "ai":
		return
	_slots[idx]["ai_doctrine"] = (
		LordAI.DOCTRINE_OFFENSE if item_idx == 1 else LordAI.DOCTRINE_DEFENSE
	)


func _on_quick_random_shield(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	_slots[idx]["heraldry"] = Heraldry.random_heraldry()
	_refresh_slot_shield(idx)
	# If this slot's editor is open, cancel draft (committed shield already changed).
	if _edit_slot_idx == idx and _shield_overlay != null and _shield_overlay.visible:
		_close_shield_editor(false)


func _open_shield_editor(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	if str(_slots[idx].get("type", "")) != "human":
		return
	_edit_slot_idx = idx
	var src = _slots[idx].get("heraldry", {})
	_draft_heraldry = Heraldry.normalize(src if src is Dictionary else {})
	var title := _shield_dialog.find_child("shield_title", true, false)
	if title != null:
		title.text = "Edit shield — %s" % str(_slots[idx].get("name", "Lord"))
	_sync_draft_editors()
	_shield_overlay.visible = true
	_shield_overlay.move_to_front()


func _close_shield_editor(_apply: bool) -> void:
	_edit_slot_idx = -1
	_draft_heraldry = {}
	if _shield_overlay != null:
		_shield_overlay.visible = false


func _on_shield_cancel() -> void:
	_close_shield_editor(false)


func _on_shield_accept() -> void:
	if _edit_slot_idx < 0 or _edit_slot_idx >= _slots.size():
		_close_shield_editor(false)
		return
	_slots[_edit_slot_idx]["heraldry"] = Heraldry.normalize(_draft_heraldry)
	var idx := _edit_slot_idx
	_close_shield_editor(true)
	_refresh_slot_shield(idx)


func _on_draft_random_pressed() -> void:
	_draft_heraldry = Heraldry.random_heraldry()
	_sync_draft_editors()


func _sync_draft_editors() -> void:
	if not _heraldry_editors_built:
		return
	_draft_heraldry = Heraldry.normalize(_draft_heraldry)
	_heraldry_preview.texture = Heraldry.make_texture(_draft_heraldry, SHIELD_SIZE)
	_heraldry_syncing = true
	var division := clampi(int(_draft_heraldry.get("division", 0)), 0, 2)
	_opt_division.select(division)
	_rebuild_field_editors(division, _draft_heraldry.get("fields", []))
	_heraldry_syncing = false


func _rebuild_field_editors(division: int, keep_values: Array = []) -> void:
	while _fields_box.get_child_count() > 0:
		var ch := _fields_box.get_child(0)
		_fields_box.remove_child(ch)
		ch.free()
	_field_rows.clear()
	var labels := Heraldry.field_labels(division)
	var tincture_names: Array = _tincture_keys.map(func(k): return Heraldry.tincture_display_name(str(k)))
	for i in labels.size():
		var wrap := VBoxContainer.new()
		wrap.add_theme_constant_override("separation", 2)
		var title := Label.new()
		title.text = str(labels[i])
		title.add_theme_font_size_override("font_size", 12)
		wrap.add_child(title)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 2)
		var base_opt := _add_field_opt(grid, "Base", tincture_names)
		var ink_opt := _add_field_opt(grid, "Ink", tincture_names)
		var pattern_opt := _add_field_opt(grid, "Pattern", Heraldry.pattern_labels())
		var charge_opt := _add_field_opt(grid, "Charges", Heraldry.charge_layout_labels())
		var type_opt := _add_field_opt(grid, "Charge", Heraldry.charge_type_labels())
		wrap.add_child(grid)
		_fields_box.add_child(wrap)
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
	if _heraldry_syncing:
		return
	var prev := _fields_from_editors()
	_heraldry_syncing = true
	_rebuild_field_editors(_opt_division.selected, prev)
	_heraldry_syncing = false
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
	if _heraldry_syncing:
		return
	var fields := _fields_from_editors()
	var raw := {
		"primary": str(fields[0].get("base", "azure")),
		"division": _opt_division.selected,
		"fields": fields,
	}
	_draft_heraldry = Heraldry.normalize(raw)
	_heraldry_preview.texture = Heraldry.make_texture(_draft_heraldry, SHIELD_SIZE)
	if _draft_heraldry.has("fields") and _draft_heraldry["fields"] is Array:
		_heraldry_syncing = true
		var af: Array = _draft_heraldry["fields"]
		for i in mini(_field_rows.size(), af.size()):
			var f: Dictionary = af[i]
			_select_key(_field_rows[i]["ink"], str(f.get("ink", "or")))
			_select_key(_field_rows[i]["base"], str(f.get("base", "azure")))
		_heraldry_syncing = false


func _refresh_slot_shield(idx: int) -> void:
	if idx < 0 or idx >= _slots_box.get_child_count() or idx >= _slots.size():
		return
	var panel := _slots_box.get_child(idx)
	var shield := panel.find_child("slot_shield", true, false)
	if shield == null or not (shield is TextureRect):
		return
	var h: Dictionary = _slots[idx].get("heraldry", {})
	if h is Dictionary and Heraldry.is_set(h):
		shield.texture = Heraldry.make_texture(Heraldry.normalize(h), ROW_SHIELD_SIZE)


func _on_back_pressed() -> void:
	_close_shield_editor(false)
	visible = false


func _on_start_pressed() -> void:
	if _human_count() < 1:
		return
	_close_shield_editor(false)
	var clean_slots: Array = []
	for s in _slots:
		var entry := {
			"type": str(s.get("type", "human")),
			"name": str(s.get("name", "")).strip_edges(),
			"heraldry": Heraldry.normalize(s.get("heraldry", {})),
		}
		if entry["name"] == "":
			entry["name"] = GlobalSet.random_lord_name()
		if entry["type"] == "ai":
			var d := str(s.get("ai_doctrine", LordAI.DOCTRINE_DEFENSE))
			if d != LordAI.DOCTRINE_OFFENSE:
				d = LordAI.DOCTRINE_DEFENSE
			entry["ai_doctrine"] = d
		clean_slots.append(entry)
	GlobalSet.pending_game_setup = {
		"map_path": GlobalSet.TEST_MAP_01,
		"slots": clean_slots,
	}
	get_tree().change_scene_to_file(GlobalSet.TEST_MAP_01)
