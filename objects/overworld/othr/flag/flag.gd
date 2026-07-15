extends Node2D

const DEFAULT_GRAY := Vector3i(128, 128, 128)

# Vertical spacing between banners (banner height + gap).
const BANNER_STEP := 4
# Y coordinate of the top of the triangle flag in Flag-local space.
const TRIANGLE_TOP_Y := -27.0
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

# Tracked banners: Array of { node: Line2D, base_y: float, phase: float }
var _banner_data: Array = []


func setup_flag() -> void:
	var player_id: int = settlement.player_owner
	var map_node = settlement.get("base_map")
	if map_node == null or not map_node.get("players"):
		flag_sprite._set_flag_color_rgb(DEFAULT_GRAY.x, DEFAULT_GRAY.y, DEFAULT_GRAY.z)
		_reset_banners_and_pole([])
		return
	var players_dict: Dictionary = map_node.players
	if not players_dict.has(player_id):
		flag_sprite._set_flag_color_rgb(DEFAULT_GRAY.x, DEFAULT_GRAY.y, DEFAULT_GRAY.z)
		_reset_banners_and_pole([])
		return
	var pl = players_dict[player_id]
	var c: Dictionary = pl.color
	var r: int = c.get("red", DEFAULT_GRAY.x)
	var g: int = c.get("green", DEFAULT_GRAY.y)
	var b: int = c.get("blue", DEFAULT_GRAY.z)
	flag_sprite._set_flag_color_rgb(r, g, b)

	if settlement.has_method("get_owner_set") and settlement.has_method("get_controller"):
		_setup_banners(settlement.get_owner_set(), settlement.get_controller(), players_dict)
	else:
		_reset_banners_and_pole([])


func _setup_banners(owners: Array, controller: int, players_dict: Dictionary) -> void:
	var extras: Array = []
	for pid in owners:
		if pid != controller and players_dict.has(pid):
			extras.append(pid)
	extras.sort()
	_reset_banners_and_pole(extras)

	for i in extras.size():
		var pid: int = extras[i]
		var col: Dictionary = players_dict[pid].color
		var color := Color(
			col.get("red",   DEFAULT_GRAY.x) / 255.0,
			col.get("green", DEFAULT_GRAY.y) / 255.0,
			col.get("blue",  DEFAULT_GRAY.z) / 255.0
		)
		var base_y := TRIANGLE_TOP_Y - 2.0 - i * BANNER_STEP
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


func _reset_banners_and_pole(extras: Array) -> void:
	_banner_data.clear()
	for ch in get_children():
		if ch.is_in_group("army_banner"):
			ch.queue_free()

	var pole := $pole_spr
	var top_y: float = TRIANGLE_TOP_Y - 2.0 - max(0, extras.size() - 1) * BANNER_STEP - 1.0
	var new_h: float = POLE_BOTTOM_Y - top_y if extras.size() > 0 else POLE_ORIGINAL_H
	pole.scale.y = new_h / POLE_ORIGINAL_H
	pole.position.y = POLE_BOTTOM_Y - new_h / 2.0


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
