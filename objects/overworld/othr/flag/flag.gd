extends Node2D

const DEFAULT_GRAY := Vector3i(128, 128, 128)

# Vertical spacing between banners (banner height + gap).
const BANNER_STEP := 4
# Y coordinate of the top of the triangle flag in Flag-local space.
const TRIANGLE_TOP_Y := -27.0
# When only wavy banners are shown (no triangle), stack from this Y.
const BANNER_ONLY_BASE_Y := -12.0
# Y coordinate of the pole's foot in Flag-local space (stays fixed).
const POLE_BOTTOM_Y := -1.0
# Original pole height in pixels (matches pole.png which is 2×26).
const POLE_ORIGINAL_H := 26.0

# Banner Line2D geometry — matches the flag sprite's horizontal span.
# flag_spr is centered at x=18, texture is 32px wide → left edge x=2, right edge x=34.
const BANNER_X_START  := 2.0
const BANNER_X_END    := 34.0
const BANNER_POINTS   := 10      # subdivisions along the banner length
const BANNER_WIDTH_PX := 2.0     # Line2D stroke width

# Wave parameters — mirror the flag_wave shader feel.
const BANNER_WAVE_AMP   := 1.5   # max vertical displacement in pixels (free end)
const BANNER_WAVE_FREQ  := 5.0   # spatial frequency (radians across banner length)
const BANNER_WAVE_SPEED := 4.0   # temporal speed (radians/second)
const BANNER_PHASE_GAP  := 1.2   # phase offset between stacked banners

@onready var settlement = get_parent()
@onready var flag_sprite = $flag_spr
@onready var pole_spr = $pole_spr

# Tracked banners: Array of { node: Line2D, base_y: float, phase: float }
var _banner_data: Array = []


func _ready() -> void:
	# Non-town buildings only show flags when garrisoned; hide until setup_flag runs.
	if settlement != null and settlement.has_method("shows_ownership_triangle") \
			and not settlement.shows_ownership_triangle():
		visible = false
		flag_sprite.visible = false


func setup_flag() -> void:
	var map_node = settlement.get("base_map")
	var players_dict: Dictionary = {}
	if map_node != null and map_node.get("players"):
		players_dict = map_node.players

	var show_triangle := _shows_ownership_triangle()
	var banner_pids := _collect_banner_pids(players_dict)

	if not show_triangle:
		flag_sprite.visible = false
		if banner_pids.is_empty():
			visible = false
			_reset_banners_and_pole([], true)
			return
		visible = true
		pole_spr.visible = true
		_setup_banners(banner_pids, players_dict, false)
		return

	visible = true
	flag_sprite.visible = true
	pole_spr.visible = true

	var player_id: int = settlement.player_owner
	if players_dict.is_empty() or not players_dict.has(player_id):
		flag_sprite._set_flag_color_rgb(DEFAULT_GRAY.x, DEFAULT_GRAY.y, DEFAULT_GRAY.z)
		_reset_banners_and_pole([], true)
		return

	var c: Dictionary = players_dict[player_id].color
	flag_sprite._set_flag_color_rgb(
		c.get("red", DEFAULT_GRAY.x),
		c.get("green", DEFAULT_GRAY.y),
		c.get("blue", DEFAULT_GRAY.z)
	)
	_setup_banners(banner_pids, players_dict, true)


## Pole + stacked wavy banners in fixed colors (no ownership triangle).
func setup_decorative_banners(colors: Array) -> void:
	if flag_sprite != null:
		flag_sprite.visible = false
	visible = true
	if pole_spr != null:
		pole_spr.visible = true
	_reset_banners_and_pole(colors, false)
	var anchor := BANNER_ONLY_BASE_Y
	for i in colors.size():
		var color: Color = colors[i] if colors[i] is Color else Color.WHITE
		var base_y := anchor - i * BANNER_STEP
		var banner := _make_banner_line(color, base_y)
		_banner_data.append({ "node": banner, "base_y": base_y, "phase": i * BANNER_PHASE_GAP })
		add_child(banner)


func _shows_ownership_triangle() -> bool:
	if settlement.has_method("shows_ownership_triangle"):
		return settlement.shows_ownership_triangle()
	return true


func _collect_banner_pids(players_dict: Dictionary) -> Array:
	var raw: Array = []
	if settlement.has_method("get_banner_pids"):
		raw = settlement.get_banner_pids()
	elif settlement.has_method("get_owner_set") and settlement.has_method("get_controller"):
		var controller: int = settlement.get_controller()
		for pid in settlement.get_owner_set():
			if int(pid) != controller:
				raw.append(int(pid))
	var out: Array = []
	for pid in raw:
		var id := int(pid)
		if players_dict.is_empty() or players_dict.has(id):
			if not out.has(id):
				out.append(id)
	out.sort()
	return out


func _setup_banners(pids: Array, players_dict: Dictionary, stack_from_triangle: bool) -> void:
	_reset_banners_and_pole(pids, stack_from_triangle)
	var anchor: float = TRIANGLE_TOP_Y - 2.0 if stack_from_triangle else BANNER_ONLY_BASE_Y
	for i in pids.size():
		var pid: int = pids[i]
		var color := Color(
			DEFAULT_GRAY.x / 255.0,
			DEFAULT_GRAY.y / 255.0,
			DEFAULT_GRAY.z / 255.0
		)
		if players_dict.has(pid):
			var col: Dictionary = players_dict[pid].color
			color = Color(
				col.get("red",   DEFAULT_GRAY.x) / 255.0,
				col.get("green", DEFAULT_GRAY.y) / 255.0,
				col.get("blue",  DEFAULT_GRAY.z) / 255.0
			)
		var base_y := anchor - i * BANNER_STEP
		var banner := _make_banner_line(color, base_y)
		_banner_data.append({ "node": banner, "base_y": base_y, "phase": i * BANNER_PHASE_GAP })
		add_child(banner)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for d in _banner_data:
		if not is_instance_valid(d.node):
			continue
		var line: Line2D = d.node
		for i in BANNER_POINTS:
			var frac := i / float(BANNER_POINTS - 1)          # 0 (pole) → 1 (free end)
			var x := BANNER_X_START + frac * (BANNER_X_END - BANNER_X_START)
			var y := sin(frac * BANNER_WAVE_FREQ + t * BANNER_WAVE_SPEED + d.phase) \
					 * BANNER_WAVE_AMP * frac                  # anchored at pole (frac=0)
			line.set_point_position(i, Vector2(x, y))


func _reset_banners_and_pole(extras: Array, stack_from_triangle: bool = true) -> void:
	_banner_data.clear()
	for ch in get_children():
		if ch.is_in_group("army_banner"):
			ch.queue_free()

	if extras.is_empty():
		pole_spr.scale.y = 1.0
		pole_spr.position.y = POLE_BOTTOM_Y - POLE_ORIGINAL_H / 2.0
		return

	var anchor: float = TRIANGLE_TOP_Y - 2.0 if stack_from_triangle else BANNER_ONLY_BASE_Y
	var top_y: float = anchor - max(0, extras.size() - 1) * BANNER_STEP - 1.0
	var new_h: float = POLE_BOTTOM_Y - top_y
	pole_spr.scale.y = new_h / POLE_ORIGINAL_H
	pole_spr.position.y = POLE_BOTTOM_Y - new_h / 2.0


func _make_banner_line(color: Color, base_y: float) -> Line2D:
	var line := Line2D.new()
	line.width = BANNER_WIDTH_PX
	line.default_color = color
	line.add_to_group("army_banner")
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Pre-populate points; _process will animate them every frame.
	for i in BANNER_POINTS:
		var frac := i / float(BANNER_POINTS - 1)
		var x := BANNER_X_START + frac * (BANNER_X_END - BANNER_X_START)
		line.add_point(Vector2(x, 0.0))
	line.position = Vector2(0.0, base_y)
	return line
