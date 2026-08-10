extends Control

## Compact status icons for map labels and the all-provinces list:
## idle free labor, civilian leave last season, cannot afford set ration.

const SLOT_SIZE := 14.0
const SLOT_GAP := 4.0
const DOT_R := 2.2
const PAD_X := 2.0

const COLOR_IDLE := Color(0.45, 0.78, 1.0, 0.95)
const COLOR_LEAVE := Color(1.0, 0.55, 0.2, 0.95)
const COLOR_HUNGER := Color(0.95, 0.2, 0.18, 0.95)

var show_idle: bool = false
var show_leave: bool = false
var show_hunger: bool = false

var _phase: float = 0.0
var _hunger_drops: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild_hunger()
	_apply_size()
	_sync_process()
	queue_redraw()


func set_flags(idle: bool, leave: bool, hunger: bool) -> void:
	show_idle = idle
	show_leave = leave
	show_hunger = hunger
	visible = idle or leave or hunger
	if show_hunger and _hunger_drops.is_empty():
		_rebuild_hunger()
	_apply_size()
	_sync_process()
	queue_redraw()


func has_active() -> bool:
	return show_idle or show_leave or show_hunger


func row_width() -> float:
	var n := _slot_count()
	if n <= 0:
		return 0.0
	return float(n) * SLOT_SIZE + float(n - 1) * SLOT_GAP + PAD_X * 2.0


func row_height() -> float:
	return SLOT_SIZE if has_active() else 0.0


func _slot_count() -> int:
	var n := 0
	if show_idle:
		n += 1
	if show_leave:
		n += 1
	if show_hunger:
		n += 1
	return n


func _apply_size() -> void:
	var w := maxf(row_width(), 1.0)
	var h := maxf(row_height(), SLOT_SIZE)
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)


func _sync_process() -> void:
	set_process(has_active() and visible)


func _rebuild_hunger() -> void:
	_hunger_drops.clear()
	for i in 5:
		_hunger_drops.append({
			"x": randf_range(-4.0, 4.0),
			"y": randf_range(-5.0, 5.0),
			"speed": randf_range(10.0, 18.0),
			"life": randf_range(0.0, 0.7),
			"max_life": randf_range(0.45, 0.85),
			"size": randf_range(1.6, 2.6),
			"alpha": randf_range(0.45, 0.9),
		})


func _process(delta: float) -> void:
	_phase += delta
	if show_hunger:
		for p in _hunger_drops:
			p["life"] = float(p["life"]) + delta
			p["y"] = float(p["y"]) + float(p["speed"]) * delta
			if float(p["life"]) >= float(p["max_life"]):
				p["x"] = randf_range(-4.0, 4.0)
				p["y"] = randf_range(-5.0, -2.0)
				p["speed"] = randf_range(10.0, 18.0)
				p["life"] = 0.0
				p["max_life"] = randf_range(0.45, 0.85)
				p["size"] = randf_range(1.6, 2.6)
				p["alpha"] = randf_range(0.45, 0.9)
	queue_redraw()


func _draw() -> void:
	var slots: Array[int] = []
	if show_idle:
		slots.append(0)
	if show_leave:
		slots.append(1)
	if show_hunger:
		slots.append(2)
	if slots.is_empty():
		return
	var content_w := float(slots.size()) * SLOT_SIZE + float(slots.size() - 1) * SLOT_GAP
	var x := (size.x - content_w) * 0.5 + SLOT_SIZE * 0.5
	var cy := size.y * 0.5
	for kind in slots:
		var origin := Vector2(x, cy)
		match kind:
			0:
				_draw_idle(origin)
			1:
				_draw_leave(origin)
			2:
				_draw_hunger(origin)
		x += SLOT_SIZE + SLOT_GAP


func _draw_idle(origin: Vector2) -> void:
	# Three light-blue dots chase each other on a shared circle.
	var radius := 4.5
	var speed := 2.4
	for i in 3:
		var ang := _phase * speed + float(i) * TAU / 3.0
		var p := origin + Vector2(cos(ang), sin(ang)) * radius
		draw_circle(p, DOT_R, COLOR_IDLE)


func _draw_leave(origin: Vector2) -> void:
	# Three orange dots expand outward from center, then loop.
	var cycle := fmod(_phase * 0.9, 1.0)
	var dist := cycle * 5.5
	var a := COLOR_LEAVE
	a.a = COLOR_LEAVE.a * clampf(1.0 - cycle, 0.15, 1.0)
	for i in 3:
		var ang := float(i) * TAU / 3.0 - PI * 0.5
		var p := origin + Vector2(cos(ang), sin(ang)) * dist
		draw_circle(p, DOT_R, a)


func _draw_hunger(origin: Vector2) -> void:
	for p in _hunger_drops:
		var t: float = float(p["life"]) / maxf(0.001, float(p["max_life"]))
		var col := COLOR_HUNGER
		col.a = float(p["alpha"]) * clampf(1.0 - t, 0.0, 1.0)
		var s: float = float(p["size"])
		var pos := origin + Vector2(float(p["x"]), float(p["y"]))
		draw_rect(Rect2(pos - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), col, true)
