extends CanvasLayer
class_name ScoreScreen

## End-of-campaign score overlay: AoE2-style metric graphs + Continue.

signal continue_pressed

const MAIN_MENU := "res://menus/main_menu/main_menu.tscn"

var _history: Array = []
var _meta: Dictionary = {}
var _outcome: String = "victory" # victory | defeat
var _subtitle: String = ""
var _winner_pids: Array = []
var _metric: String = "men"
var _show_unit_mix := false

var _title_lbl: Label
var _subtitle_lbl: Label
var _graph: Control
var _legend: VBoxContainer
var _mix_box: VBoxContainer
var _metric_btns: Dictionary = {}


func setup(
		history: Array,
		meta: Dictionary,
		outcome: String,
		subtitle: String = "",
		winner_pids: Array = []
	) -> void:
	_history = history.duplicate(true)
	_meta = meta.duplicate(true)
	_outcome = outcome
	_subtitle = subtitle
	_winner_pids = winner_pids.duplicate()
	if not is_inside_tree():
		await tree_entered
	_ensure_ui()
	_refresh_header()
	_rebuild_legend()
	_rebuild_unit_mix()
	if _graph:
		_graph.queue_redraw()


func _ready() -> void:
	layer = 100
	_ensure_ui()


func _ensure_ui() -> void:
	if has_node("root"):
		return

	var root := Control.new()
	root.name = "root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.82)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 560)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_subtitle_lbl)

	var metrics_row := HBoxContainer.new()
	metrics_row.alignment = BoxContainer.ALIGNMENT_CENTER
	metrics_row.add_theme_constant_override("separation", 6)
	vbox.add_child(metrics_row)

	for key in GameScore.METRICS:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = str(GameScore.METRIC_LABELS.get(key, key))
		btn.pressed.connect(_on_metric_pressed.bind(str(key)))
		metrics_row.add_child(btn)
		_metric_btns[str(key)] = btn

	var mix_btn := Button.new()
	mix_btn.toggle_mode = true
	mix_btn.text = "Army mix"
	mix_btn.pressed.connect(_on_mix_pressed)
	metrics_row.add_child(mix_btn)
	_metric_btns["units"] = mix_btn

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	vbox.add_child(body)

	_graph = Control.new()
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(640, 320)
	_graph.draw.connect(_on_graph_draw)
	body.add_child(_graph)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(200, 0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)

	var leg_title := Label.new()
	leg_title.text = "Lords"
	side.add_child(leg_title)

	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 4)
	side.add_child(_legend)

	_mix_box = VBoxContainer.new()
	_mix_box.visible = false
	_mix_box.add_theme_constant_override("separation", 4)
	side.add_child(_mix_box)

	var cont := Button.new()
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(0, 36)
	cont.pressed.connect(_on_continue)
	vbox.add_child(cont)

	_sync_metric_buttons()


func _refresh_header() -> void:
	if _title_lbl == null:
		return
	if _outcome == "defeat":
		_title_lbl.text = "Defeat"
	else:
		_title_lbl.text = "Victory"
	_subtitle_lbl.text = _subtitle


func _sync_metric_buttons() -> void:
	for key in _metric_btns.keys():
		var btn: Button = _metric_btns[key]
		if key == "units":
			btn.button_pressed = _show_unit_mix
		else:
			btn.button_pressed = (not _show_unit_mix and str(key) == _metric)


func _on_metric_pressed(key: String) -> void:
	_show_unit_mix = false
	_metric = key
	_mix_box.visible = false
	_graph.visible = true
	_sync_metric_buttons()
	_graph.queue_redraw()


func _on_mix_pressed() -> void:
	_show_unit_mix = true
	_mix_box.visible = true
	_sync_metric_buttons()
	_rebuild_unit_mix()
	_graph.queue_redraw()


func _rebuild_legend() -> void:
	if _legend == null:
		return
	for c in _legend.get_children():
		c.queue_free()
	var pids: Array = _meta.keys()
	pids.sort_custom(func(a, b): return int(a) < int(b))
	for pid_s in pids:
		var m: Dictionary = _meta[pid_s]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = GameScore.color_from_meta(m)
		row.add_child(swatch)
		var lbl := Label.new()
		var status := int(m.get("status", 0))
		var suffix := ""
		if status == int(GlobalStuff.PLAYER_STATUS.DEFEATED):
			suffix = " (defeated)"
		lbl.text = "%s%s" % [str(m.get("name", "Lord")), suffix]
		row.add_child(lbl)
		_legend.add_child(row)


func _rebuild_unit_mix() -> void:
	if _mix_box == null:
		return
	for c in _mix_box.get_children():
		c.queue_free()
	if _history.is_empty():
		return
	var last: Dictionary = _history[_history.size() - 1]
	var players: Dictionary = last.get("players", {})
	var focus: Array = _winner_pids
	if focus.is_empty():
		# Defeat / solo: show local-looking first meta entry with most men.
		var best_pid := -1
		var best_men := -1
		for pid_s in players.keys():
			var snap: Dictionary = players[pid_s]
			var men := int(snap.get("men", 0))
			if men > best_men:
				best_men = men
				best_pid = int(pid_s)
		if best_pid >= 0:
			focus = [best_pid]
	var title := Label.new()
	title.text = "Final army mix"
	_mix_box.add_child(title)
	for pid in focus:
		var pid_s := str(int(pid))
		if not players.has(pid_s):
			continue
		var name_ := str(_meta.get(pid_s, {}).get("name", "Lord"))
		var name_lbl := Label.new()
		name_lbl.text = name_
		_mix_box.add_child(name_lbl)
		var units: Dictionary = players[pid_s].get("units", {})
		var keys: Array = units.keys()
		keys.sort_custom(func(a, b): return int(a) < int(b))
		for uk in keys:
			var n := int(units[uk])
			if n <= 0:
				continue
			var line := Label.new()
			line.text = "  %s: %d" % [GlobalUnits.unit_name(int(uk)), n]
			_mix_box.add_child(line)


func _on_graph_draw() -> void:
	if _graph == null:
		return
	var rect := Rect2(Vector2.ZERO, _graph.size)
	# Mid gray so both dark and light lord colors stay readable.
	_graph.draw_rect(rect, Color(0.55, 0.54, 0.52, 1.0))
	var pad := 28.0
	var plot := Rect2(pad, pad, maxf(10.0, rect.size.x - pad * 2.0), maxf(10.0, rect.size.y - pad * 2.0))
	_graph.draw_rect(plot, Color(0.62, 0.61, 0.58, 1.0))

	if _show_unit_mix:
		_draw_unit_bars(plot)
		return

	if _history.size() < 1:
		return

	var max_v := 1.0
	for entry in _history:
		var players: Dictionary = entry.get("players", {})
		for pid_s in players.keys():
			max_v = maxf(max_v, float(players[pid_s].get(_metric, 0)))

	# Axes
	var axis_col := Color(0.22, 0.2, 0.18)
	_graph.draw_line(plot.position + Vector2(0, plot.size.y), plot.position + Vector2(plot.size.x, plot.size.y), axis_col, 2.0)
	_graph.draw_line(plot.position, plot.position + Vector2(0, plot.size.y), axis_col, 2.0)

	var years: Array = []
	for entry in _history:
		years.append(int(entry.get("year", 0)))
	var n := _history.size()
	var pids: Array = _meta.keys()
	pids.sort_custom(func(a, b): return int(a) < int(b))

	for pid_s in pids:
		var col := GameScore.color_from_meta(_meta.get(pid_s, {}))
		var points: PackedVector2Array = []
		for i in n:
			var players: Dictionary = _history[i].get("players", {})
			var v := 0.0
			if players.has(pid_s):
				v = float(players[pid_s].get(_metric, 0))
			var x := plot.position.x
			if n > 1:
				x += plot.size.x * (float(i) / float(n - 1))
			else:
				x += plot.size.x * 0.5
			var y := plot.position.y + plot.size.y - (v / max_v) * plot.size.y
			points.append(Vector2(x, y))
		if points.size() == 1:
			_graph.draw_circle(points[0], 4.0, col)
		else:
			for i in range(points.size() - 1):
				_graph.draw_line(points[i], points[i + 1], col, 2.5, true)
			_graph.draw_circle(points[points.size() - 1], 3.5, col)

	# Year labels
	if n >= 1:
		var font := ThemeDB.fallback_font
		var fs := 12
		var label_col := Color(0.18, 0.16, 0.14)
		_graph.draw_string(font, plot.position + Vector2(0, plot.size.y + 16), str(years[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)
		if n > 1:
			var last_s := str(years[n - 1])
			_graph.draw_string(font, plot.position + Vector2(plot.size.x - 40, plot.size.y + 16), last_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)
		var metric_name := str(GameScore.METRIC_LABELS.get(_metric, _metric))
		_graph.draw_string(font, plot.position + Vector2(8, -8), metric_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, label_col)
		_graph.draw_string(font, plot.position + Vector2(8, 14), str(int(max_v)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)


func _draw_unit_bars(plot: Rect2) -> void:
	if _history.is_empty():
		return
	var last: Dictionary = _history[_history.size() - 1]
	var players: Dictionary = last.get("players", {})
	var focus: Array = _winner_pids
	if focus.is_empty():
		for pid_s in players.keys():
			focus.append(int(pid_s))
			break
	if focus.is_empty():
		return
	var pid_s := str(int(focus[0]))
	var units: Dictionary = players.get(pid_s, {}).get("units", {})
	var entries: Array = []
	var total := 0
	for uk in units.keys():
		var n := int(units[uk])
		if n <= 0:
			continue
		entries.append({"type": int(uk), "n": n})
		total += n
	if entries.is_empty() or total <= 0:
		return
	entries.sort_custom(func(a, b): return int(a["type"]) < int(b["type"]))
	var bar_w := plot.size.x / float(entries.size())
	var i := 0
	var font := ThemeDB.fallback_font
	for e in entries:
		var h := plot.size.y * (float(e["n"]) / float(total))
		var x := plot.position.x + bar_w * float(i)
		var y := plot.position.y + plot.size.y - h
		var col := Color(0.55, 0.4, 0.2).lerp(Color(0.85, 0.7, 0.35), float(i) / float(maxi(entries.size() - 1, 1)))
		_graph.draw_rect(Rect2(x + 4, y, maxf(8.0, bar_w - 8), h), col)
		var label := GlobalUnits.unit_name(int(e["type"]))
		_graph.draw_string(font, Vector2(x + 2, plot.position.y + plot.size.y + 14), label.left(4), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.18, 0.16, 0.14))
		i += 1


func _on_continue() -> void:
	continue_pressed.emit()
	GlobalSet.return_to_new_game = true
	get_tree().change_scene_to_file(MAIN_MENU)
