extends PanelContainer

## New Game setup: map pick, Human/AI slots, heraldry, order colour + AI doctrine.
## Shield editing uses the shared heraldry modal (Accept / Cancel); row has quick Random.

const HeraldryEditorScene = preload("res://menus/gui/heraldry_editor/heraldry_editor.gd")
const MapMatrixPreviewScript = preload("res://maps/overworld/map_gen/map_matrix_preview.gd")

const ROW_SHIELD_SIZE := 36
const SWATCH_SIZE := 28
const TYPE_HUMAN := 0
const TYPE_AI := 1
const MAP_ID_RANDOM := 0
const MAP_ID_TEST_01 := 1
const AUTO_REROLL_TRIES := 16

var _slots: Array = []  # Array[Dictionary]
var _rebuild_busy := false

var _slots_box: VBoxContainer
var _add_btn: Button
var _map_opt: OptionButton
var _province_row: HBoxContainer
var _province_spin: SpinBox
var _reroll_map_btn: Button
var _preview: Control
var _preview_status: Label
var _start_btn: Button

var _preview_matrix: MapMatrix = null
var _gen_thread: Thread = null
var _gen_token: int = 0
var _gen_loading: bool = false

## Shield draft popup state
var _heraldry_editor: Control
var _edit_slot_idx := -1


func _ready() -> void:
	_build_ui()
	reset_to_defaults()


func _exit_tree() -> void:
	_cancel_generation()
	_join_gen_thread()


func reset_to_defaults() -> void:
	_close_shield_editor()
	_cancel_generation()
	_slots = [GlobalSet.make_default_human_slot()]
	_rebuild_slot_list()
	if _province_spin != null:
		_province_spin.value = 6
	if _map_opt != null:
		## Default: Test Map 01 (fast open). Random generates on demand.
		_map_opt.select(1)
	_preview_matrix = null
	_refresh_map_controls()
	_apply_fixed_map_ui()


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
	hint.text = "Up to %d lords. Pick a unique order colour (borders / flags). Leftover provinces become councils." % GlobalSet.MAX_SETUP_PLAYERS
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 8)
	root.add_child(map_row)

	var map_lbl := Label.new()
	map_lbl.text = "Map"
	map_lbl.custom_minimum_size = Vector2(80, 0)
	map_row.add_child(map_lbl)

	_map_opt = OptionButton.new()
	_map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_opt.add_item("Random", MAP_ID_RANDOM)
	_map_opt.add_item("Test Map 01", MAP_ID_TEST_01)
	_map_opt.item_selected.connect(_on_map_selected)
	map_row.add_child(_map_opt)

	_province_row = HBoxContainer.new()
	_province_row.add_theme_constant_override("separation", 8)
	root.add_child(_province_row)

	var prov_lbl := Label.new()
	prov_lbl.text = "Provinces"
	prov_lbl.custom_minimum_size = Vector2(80, 0)
	_province_row.add_child(prov_lbl)

	_province_spin = SpinBox.new()
	_province_spin.min_value = 3
	_province_spin.max_value = 20
	_province_spin.value = 6
	_province_spin.rounded = true
	_province_spin.value_changed.connect(_on_province_count_changed)
	_province_row.add_child(_province_spin)

	_reroll_map_btn = Button.new()
	_reroll_map_btn.text = "Reroll map"
	_reroll_map_btn.pressed.connect(_on_reroll_map)
	_province_row.add_child(_reroll_map_btn)

	_preview_status = Label.new()
	_preview_status.text = ""
	root.add_child(_preview_status)

	_preview = MapMatrixPreviewScript.new()
	_preview.custom_minimum_size = Vector2(0, 180)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_preview)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
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

	_start_btn = Button.new()
	_start_btn.text = "Start"
	_start_btn.custom_minimum_size = Vector2(120, 40)
	_start_btn.pressed.connect(_on_start_pressed)
	btns.add_child(_start_btn)


func _ensure_heraldry_editor() -> void:
	if _heraldry_editor != null and is_instance_valid(_heraldry_editor):
		return
	_heraldry_editor = HeraldryEditorScene.new()
	_heraldry_editor.name = "heraldry_editor"
	_heraldry_editor.accepted.connect(_on_heraldry_accepted)
	_heraldry_editor.cancelled.connect(_on_heraldry_cancelled)
	# Parent to fullscreen overlays so the larger modal is not clipped by this panel.
	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(_heraldry_editor)


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

	var swatch := ColorRect.new()
	swatch.name = "slot_swatch"
	swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
	swatch.color = GlobalStuff.order_color_to_color(
		GlobalStuff.normalize_order_color(slot.get("color", {}))
	)
	swatch.tooltip_text = "Order colour (borders / flags)"
	swatch.gui_input.connect(func(ev): _on_swatch_gui_input(idx, ev))
	top.add_child(swatch)

	var colour_btn := Button.new()
	colour_btn.text = "Colour"
	colour_btn.tooltip_text = "Cycle order colour"
	colour_btn.pressed.connect(func(): _on_cycle_color(idx))
	top.add_child(colour_btn)

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
	var used_cols := GlobalStuff.used_order_color_keys_from_slots(_slots)
	var slot := GlobalSet.make_default_ai_slot(used_cols)
	while used.has(str(slot["name"])):
		slot["name"] = GlobalSet.random_lord_name(used)
	_slots.append(slot)
	_rebuild_slot_list()


func _used_names() -> Dictionary:
	var used := {}
	for s in _slots:
		used[str(s.get("name", ""))] = true
	return used


func _on_swatch_gui_input(idx: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_cycle_color(idx)


func _on_cycle_color(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	var used := GlobalStuff.used_order_color_keys_from_slots(_slots, idx)
	var cur: Dictionary = GlobalStuff.normalize_order_color(_slots[idx].get("color", {}))
	_slots[idx]["color"] = GlobalStuff.cycle_order_color(used, cur)
	_refresh_slot_swatch(idx)


func _refresh_slot_swatch(idx: int) -> void:
	if idx < 0 or idx >= _slots_box.get_child_count() or idx >= _slots.size():
		return
	var panel := _slots_box.get_child(idx)
	var swatch := panel.find_child("slot_swatch", true, false)
	if swatch == null or not (swatch is ColorRect):
		return
	swatch.color = GlobalStuff.order_color_to_color(
		GlobalStuff.normalize_order_color(_slots[idx].get("color", {}))
	)


func _on_remove(idx: int) -> void:
	if idx < 0 or idx >= _slots.size() or _slots.size() <= 1:
		return
	var was_human := str(_slots[idx].get("type", "")) == "human"
	if was_human and _human_count() <= 1:
		return
	if _edit_slot_idx == idx:
		_close_shield_editor()
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
		_close_shield_editor()
	if want_human:
		_slots[idx] = {
			"type": "human",
			"name": str(_slots[idx].get("name", GlobalSet.random_lord_name())),
			"heraldry": _slots[idx].get("heraldry", Heraldry.random_heraldry()),
			"color": GlobalStuff.normalize_order_color(_slots[idx].get("color", {})),
		}
	else:
		var doctrine := LordAI.DOCTRINE_OFFENSE if randf() < 0.5 else LordAI.DOCTRINE_DEFENSE
		_slots[idx] = {
			"type": "ai",
			"name": str(_slots[idx].get("name", GlobalSet.random_lord_name())),
			"heraldry": _slots[idx].get("heraldry", Heraldry.random_heraldry()),
			"ai_doctrine": doctrine,
			"color": GlobalStuff.normalize_order_color(_slots[idx].get("color", {})),
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
	if _edit_slot_idx == idx and _heraldry_editor != null and _heraldry_editor.is_open():
		_close_shield_editor()


func _open_shield_editor(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	if str(_slots[idx].get("type", "")) != "human":
		return
	_ensure_heraldry_editor()
	_edit_slot_idx = idx
	var src = _slots[idx].get("heraldry", {})
	var title := "Edit shield — %s" % str(_slots[idx].get("name", "Lord"))
	_heraldry_editor.open(src if src is Dictionary else {}, title)


func _close_shield_editor() -> void:
	_edit_slot_idx = -1
	if _heraldry_editor != null and is_instance_valid(_heraldry_editor):
		_heraldry_editor.close()


func _on_heraldry_accepted(heraldry: Dictionary) -> void:
	if _edit_slot_idx < 0 or _edit_slot_idx >= _slots.size():
		_edit_slot_idx = -1
		return
	var idx := _edit_slot_idx
	_slots[idx]["heraldry"] = Heraldry.normalize(heraldry)
	_edit_slot_idx = -1
	_refresh_slot_shield(idx)


func _on_heraldry_cancelled() -> void:
	_edit_slot_idx = -1


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
	_cancel_generation()
	_close_shield_editor()
	visible = false


func _is_random_map() -> bool:
	return _map_opt != null and _map_opt.get_selected_id() == MAP_ID_RANDOM


func _on_map_selected(_idx: int) -> void:
	_refresh_map_controls()
	if _is_random_map():
		_regenerate_preview()
	else:
		## Leaving Random cancels any in-flight generation.
		_cancel_generation()
		_apply_fixed_map_ui()


func _on_province_count_changed(_v: float) -> void:
	if _is_random_map() and not _gen_loading:
		_regenerate_preview()


func _on_reroll_map() -> void:
	if _is_random_map() and not _gen_loading:
		_regenerate_preview()


func _refresh_map_controls() -> void:
	var random := _is_random_map()
	if _province_row != null:
		_province_row.visible = random
	## Preview stays visible for authored maps too (square cache).
	if _preview != null:
		_preview.visible = true
	if _reroll_map_btn != null:
		_reroll_map_btn.visible = random


func _apply_fixed_map_ui() -> void:
	_gen_loading = false
	_set_gen_controls_enabled(true)
	var matrix := MapMatrixSceneSampler.sample_cached(GlobalSet.TEST_MAP_01)
	_preview_matrix = matrix
	if _preview != null and _preview.has_method("set_matrix"):
		_preview.set_matrix(matrix)
	if matrix != null:
		_preview_status.text = "Test Map 01 — %d provinces" % matrix.province_count
		_preview_status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		_start_btn.disabled = false
	else:
		_preview_status.text = "Test Map 01 — preview unavailable"
		_preview_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))
		_start_btn.disabled = false


func _set_gen_controls_enabled(enabled: bool) -> void:
	## Map dropdown stays enabled so the player can cancel by picking Test Map 01.
	if _province_spin != null:
		_province_spin.editable = enabled
	if _reroll_map_btn != null:
		_reroll_map_btn.disabled = not enabled
	if _add_btn != null:
		_add_btn.disabled = not enabled or _slots.size() >= GlobalSet.MAX_SETUP_PLAYERS
	if _slots_box != null:
		_slots_box.modulate = Color(1, 1, 1, 1.0 if enabled else 0.55)
		_slots_box.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _cancel_generation() -> void:
	_gen_token += 1
	_gen_loading = false


func _join_gen_thread() -> void:
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
		_gen_thread = null


func _regenerate_preview() -> void:
	if not _is_random_map():
		return
	_cancel_generation()
	_join_gen_thread()
	var token := _gen_token
	_gen_loading = true
	_preview_matrix = null
	if _preview != null and _preview.has_method("set_matrix"):
		_preview.set_matrix(null)
	_start_btn.disabled = true
	_set_gen_controls_enabled(false)
	_preview_status.text = "Loading…"
	_preview_status.add_theme_color_override("font_color", Color(0.85, 0.8, 0.45))
	var n := int(_province_spin.value) if _province_spin else 6
	var seed_base := randi()
	_gen_thread = Thread.new()
	_gen_thread.start(_gen_worker.bind(token, n, seed_base))


func _gen_worker(token: int, province_count: int, seed_base: int) -> void:
	var matrix: MapMatrix = null
	var ok := false
	for attempt in AUTO_REROLL_TRIES:
		matrix = MapMatrixGenerator.generate(province_count, seed_base + attempt * 9973)
		if matrix != null and MapMatrixValidator.validate(matrix).is_empty():
			ok = true
			break
	call_deferred("_on_gen_finished", token, matrix, ok)


func _on_gen_finished(token: int, matrix: MapMatrix, ok: bool) -> void:
	_join_gen_thread()
	if token != _gen_token:
		return
	if not _is_random_map():
		_gen_loading = false
		return
	_gen_loading = false
	_set_gen_controls_enabled(true)
	_preview_matrix = matrix if ok else null
	if _preview != null and _preview.has_method("set_matrix"):
		_preview.set_matrix(_preview_matrix)
	if ok and matrix != null:
		_preview_status.text = "VALID — %d provinces, seed %d" % [
			matrix.province_count, matrix.seed_used
		]
		_preview_status.add_theme_color_override("font_color", Color(0.35, 0.85, 0.45))
		_start_btn.disabled = false
	else:
		_preview_status.text = "INVALID map — hit Reroll map"
		_preview_status.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
		_start_btn.disabled = true


func _collect_slots() -> Array:
	var clean_slots: Array = []
	for s in _slots:
		var entry := {
			"type": str(s.get("type", "human")),
			"name": str(s.get("name", "")).strip_edges(),
			"heraldry": Heraldry.normalize(s.get("heraldry", {})),
			"color": GlobalStuff.normalize_order_color(s.get("color", {})),
		}
		if entry["name"] == "":
			entry["name"] = GlobalSet.random_lord_name()
		if entry["type"] == "ai":
			var d := str(s.get("ai_doctrine", LordAI.DOCTRINE_DEFENSE))
			if d != LordAI.DOCTRINE_OFFENSE:
				d = LordAI.DOCTRINE_DEFENSE
			entry["ai_doctrine"] = d
		clean_slots.append(entry)
	return clean_slots


func _on_start_pressed() -> void:
	if _human_count() < 1:
		return
	if _gen_loading:
		return
	_close_shield_editor()
	var clean_slots := _collect_slots()
	SaveGame.clear_session()

	if _is_random_map():
		if _preview_matrix == null:
			return
		if not MapMatrixValidator.validate(_preview_matrix).is_empty():
			return
		_start_btn.disabled = true
		_preview_status.text = "Baking map…"
		var map_root := MapMatrixBaker.bake(_preview_matrix)
		if map_root == null:
			_preview_status.text = "Bake failed — reroll"
			_start_btn.disabled = false
			return
		GlobalSet.pending_game_setup = {
			"map_path": GlobalSet.MAP_RANDOM,
			"slots": clean_slots,
			"world_seed": _preview_matrix.seed_used,
		}
		var tree := get_tree()
		var old := tree.current_scene
		tree.root.add_child(map_root)
		tree.current_scene = map_root
		if old != null:
			old.queue_free()
		return

	GlobalSet.pending_game_setup = {
		"map_path": GlobalSet.TEST_MAP_01,
		"slots": clean_slots,
		"world_seed": randi(),
	}
	get_tree().change_scene_to_file(GlobalSet.TEST_MAP_01)
