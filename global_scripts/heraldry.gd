extends Node

## Procedural heraldic shields for players.
## Store a small recipe on PlayerData.heraldry; render to Texture2D on demand.
##
## When divided (halved / quartered), each field has its own pattern + charges.

enum DIVISION { SOLID, PER_PALE, QUARTERED }
enum PATTERN { SOLID, BENDS, BARS, CHEVRON, BENDS_SINISTER }
enum CHARGE_LAYOUT { NONE, ONE, THREE }
enum CHARGE_TYPE { STAR, HEART }

## Classical tinctures. Metals first so rule-of-tincture checks stay simple.
const TINCTURES := {
	"or": Color8(212, 175, 55),
	"argent": Color8(240, 240, 235),
	"gules": Color8(170, 20, 30),
	"azure": Color8(20, 60, 160),
	"vert": Color8(20, 110, 45),
	"sable": Color8(28, 28, 32),
	"purpure": Color8(110, 40, 120),
	## Local councils — not a classical tincture; keeps old gray borders.
	"council_gray": Color8(140, 140, 140),
}

const METALS := ["or", "argent"]
const COLOURS := ["gules", "azure", "vert", "sable", "purpure"]

## Non-classical gray for local councils (borders/flags stay as before).
const COUNCIL_GRAY_KEY := "council_gray"
const COUNCIL_COLOR_RGB := {"red": 140, "green": 140, "blue": 140}

const OUTLINE := Color8(18, 14, 10, 255)
const CACHE_MAX := 64
const MAX_FIELDS := 4

var _tex_cache: Dictionary = {}  # key -> ImageTexture


func is_metal(key: String) -> bool:
	return METALS.has(key)


func is_colour(key: String) -> bool:
	return COLOURS.has(key)


func color_of(key: String) -> Color:
	return TINCTURES.get(key, TINCTURES["argent"])


func rgb_dict_of(key: String) -> Dictionary:
	var c := color_of(key)
	return {"red": int(c.r * 255.0), "green": int(c.g * 255.0), "blue": int(c.b * 255.0)}


func field_count(division: int) -> int:
	match clampi(division, 0, 2):
		DIVISION.PER_PALE:
			return 2
		DIVISION.QUARTERED:
			return 4
		_:
			return 1


func default_field() -> Dictionary:
	return {
		"base": "azure",
		"ink": "or",
		"pattern": int(PATTERN.SOLID),
		"charge": int(CHARGE_LAYOUT.NONE),
		"charge_type": int(CHARGE_TYPE.STAR),
	}


func default_heraldry() -> Dictionary:
	var f := default_field()
	return {
		"primary": str(f["base"]),
		"division": int(DIVISION.SOLID),
		"fields": [f],
	}


func is_set(h: Variant) -> bool:
	if h == null or not (h is Dictionary):
		return false
	var d: Dictionary = h
	if d.is_empty():
		return false
	if d.get("fields") is Array and not d["fields"].is_empty():
		var f0: Dictionary = d["fields"][0]
		if TINCTURES.has(str(f0.get("base", ""))):
			return true
	var p := str(d.get("primary", ""))
	return TINCTURES.has(p)


func _contrast_ink(base: String) -> String:
	if base == COUNCIL_GRAY_KEY:
		return "argent"
	if is_colour(base):
		return "or"
	if is_metal(base):
		return "gules"
	return "or"


func _fix_field_colours(base: String, ink: String) -> Dictionary:
	if not TINCTURES.has(base):
		base = "azure"
	if not TINCTURES.has(ink):
		ink = _contrast_ink(base)
	if base == COUNCIL_GRAY_KEY:
		if ink == COUNCIL_GRAY_KEY:
			ink = "argent"
	elif is_metal(base) == is_metal(ink):
		ink = _contrast_ink(base)
	return {"base": base, "ink": ink}


func _normalize_field(f: Variant, fallback_base: String = "azure", fallback_ink: String = "or") -> Dictionary:
	var out := default_field()
	out["base"] = fallback_base
	out["ink"] = fallback_ink
	if f == null or not (f is Dictionary):
		var pair := _fix_field_colours(str(out["base"]), str(out["ink"]))
		out["base"] = pair["base"]
		out["ink"] = pair["ink"]
		return out
	var d: Dictionary = f
	var base := str(d.get("base", fallback_base))
	var ink := str(d.get("ink", fallback_ink))
	var pair2 := _fix_field_colours(base, ink)
	out["base"] = pair2["base"]
	out["ink"] = pair2["ink"]
	out["pattern"] = clampi(int(d.get("pattern", PATTERN.SOLID)), 0, 4)
	out["charge"] = clampi(int(d.get("charge", CHARGE_LAYOUT.NONE)), 0, 2)
	out["charge_type"] = clampi(int(d.get("charge_type", CHARGE_TYPE.STAR)), 0, 1)
	return out


func normalize(h: Dictionary) -> Dictionary:
	var out := default_heraldry()
	if h == null or h.is_empty():
		return out
	var legacy_primary := str(h.get("primary", out["primary"]))
	var legacy_secondary := str(h.get("secondary", "or"))
	if not TINCTURES.has(legacy_primary):
		legacy_primary = "azure"
	if not TINCTURES.has(legacy_secondary):
		legacy_secondary = "or"
	if legacy_primary != COUNCIL_GRAY_KEY and is_metal(legacy_primary) == is_metal(legacy_secondary):
		legacy_secondary = _contrast_ink(legacy_primary)
	var division := clampi(int(h.get("division", DIVISION.SOLID)), 0, 2)
	out["division"] = division
	var n := field_count(division)
	var raw_fields: Array = []
	if h.get("fields") is Array:
		raw_fields = h["fields"]
	# Migrate legacy single pattern/charge into field 0.
	if raw_fields.is_empty() and (h.has("pattern") or h.has("charge") or h.has("charge_type")):
		raw_fields = [{
			"base": legacy_primary,
			"ink": legacy_secondary,
			"pattern": int(h.get("pattern", PATTERN.SOLID)),
			"charge": int(h.get("charge", CHARGE_LAYOUT.NONE)),
			"charge_type": int(h.get("charge_type", CHARGE_TYPE.STAR)),
		}]
	var fields: Array = []
	for i in n:
		var fb := legacy_primary if _field_is_primary(i, division) else legacy_secondary
		var fi := legacy_secondary if _field_is_primary(i, division) else legacy_primary
		if i < raw_fields.size():
			var raw: Dictionary = raw_fields[i] if raw_fields[i] is Dictionary else {}
			if not raw.has("base"):
				raw = raw.duplicate()
				raw["base"] = fb
				raw["ink"] = raw.get("ink", fi)
			fields.append(_normalize_field(raw, fb, fi))
		elif raw_fields.size() > 0:
			var copy: Dictionary = _normalize_field(raw_fields[0], fb, fi).duplicate()
			# New slots inherit colours of first field when expanding division.
			fields.append(copy)
		else:
			fields.append(_normalize_field({}, fb, fi))
	out["fields"] = fields
	# Border / flag colour follows the first field's base.
	out["primary"] = str(fields[0]["base"])
	return out


func council_heraldry() -> Dictionary:
	return {
		"primary": COUNCIL_GRAY_KEY,
		"division": int(DIVISION.SOLID),
		"fields": [{
			"base": COUNCIL_GRAY_KEY,
			"ink": "argent",
			"pattern": int(PATTERN.SOLID),
			"charge": int(CHARGE_LAYOUT.NONE),
			"charge_type": int(CHARGE_TYPE.STAR),
		}],
	}


## Random coat: each field gets its own colour base + metal ink.
func random_heraldry(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var division := r.randi_range(0, 2)
	var fields: Array = []
	for _i in field_count(division):
		var base: String = COLOURS[r.randi() % COLOURS.size()]
		var ink: String = METALS[r.randi() % METALS.size()]
		fields.append({
			"base": base,
			"ink": ink,
			"pattern": r.randi_range(0, 4),
			"charge": r.randi_range(0, 2),
			"charge_type": r.randi_range(0, 1),
		})
	return {
		"primary": str(fields[0]["base"]),
		"division": division,
		"fields": fields,
	}


## Write heraldry onto a player. Map order colour is separate (see GlobalStuff.ORDER_PALETTE).
## Councils still force gray heraldry + gray order colour.
func apply_to_player(player, h: Dictionary) -> Dictionary:
	if player == null:
		return {}
	if GlobalStuff.is_local_council(player.type):
		var ch := council_heraldry()
		player.heraldry = ch
		player.color = COUNCIL_COLOR_RGB.duplicate()
		return ch
	var n := normalize(h)
	player.heraldry = n
	return n


## If heraldry unset, roll one. Councils always keep gray.
func ensure_player(player) -> void:
	if player == null:
		return
	if GlobalStuff.is_local_council(player.type):
		apply_to_player(player, council_heraldry())
		return
	var h: Dictionary = player.heraldry if player.get("heraldry") != null else {}
	if not is_set(h):
		h = random_heraldry()
	apply_to_player(player, h)


func ensure_all(players: Dictionary) -> void:
	for pid in players.keys():
		ensure_player(players[pid])


## Reroll arms for a non-council player. Returns the new recipe (empty if refused).
func reroll_player(player) -> Dictionary:
	if player == null:
		return {}
	if GlobalStuff.is_local_council(player.type):
		return apply_to_player(player, council_heraldry())
	return apply_to_player(player, random_heraldry())


func cache_key(h: Dictionary, size: int) -> String:
	var n := normalize(h)
	var parts: PackedStringArray = PackedStringArray([
		str(n["primary"]), str(n["division"]), str(size)
	])
	for f in n["fields"]:
		parts.append("%s.%s.%d.%d.%d" % [
			str(f["base"]), str(f["ink"]),
			int(f["pattern"]), int(f["charge"]), int(f["charge_type"])
		])
	return "|".join(parts)


func make_texture(h: Dictionary, size: int = 32) -> Texture2D:
	var key := cache_key(h, size)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := render_image(normalize(h), size)
	var tex := ImageTexture.create_from_image(img)
	if _tex_cache.size() >= CACHE_MAX:
		_tex_cache.clear()
	_tex_cache[key] = tex
	return tex


func texture_for_player(player, size: int = 32) -> Texture2D:
	if player == null:
		return make_texture(default_heraldry(), size)
	var h: Dictionary = player.heraldry if player.get("heraldry") != null else {}
	if not is_set(h):
		h = default_heraldry()
	return make_texture(h, size)


func render_image(h: Dictionary, size: int) -> Image:
	var w := maxi(size, 8)
	var ht := maxi(size, 8)
	var img := Image.create(w, ht, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var division := int(h["division"])
	var fields: Array = h["fields"]

	for y in ht:
		for x in w:
			if not _in_heater(x, y, w, ht):
				continue
			var field_i := _field_at(x, y, w, ht, division)
			var field: Dictionary = fields[field_i] if field_i < fields.size() else default_field()
			var base := color_of(str(field.get("base", "azure")))
			var ink := color_of(str(field.get("ink", "or")))
			var pattern := int(field.get("pattern", PATTERN.SOLID))
			var col := base
			if pattern != PATTERN.SOLID and _pattern_mark(x, y, w, ht, pattern, field_i, division):
				col = ink
			if _near_heater_edge(x, y, w, ht):
				col = OUTLINE
			img.set_pixel(x, y, col)

	for field_i in fields.size():
		var field: Dictionary = fields[field_i]
		var layout := int(field.get("charge", CHARGE_LAYOUT.NONE))
		if layout == CHARGE_LAYOUT.NONE:
			continue
		var charge_type := int(field.get("charge_type", CHARGE_TYPE.STAR))
		var ink_col := color_of(str(field.get("ink", "or")))
		_draw_field_charges(img, w, ht, field_i, division, layout, charge_type, ink_col)

	return img


## Classic heater: straight top, rounded sides into a soft bottom tip.
func _in_heater(x: int, y: int, w: int, ht: int) -> bool:
	var fx := (float(x) + 0.5) / float(w)
	var fy := (float(y) + 0.5) / float(ht)
	var left := 0.08
	var right := 0.92
	var top := 0.08
	var bottom := 0.94
	if fy < top or fy > bottom or fx < left or fx > right:
		return false
	var waist_y := 0.48
	if fy <= waist_y:
		return true
	var t := (fy - waist_y) / (bottom - waist_y)
	t = clampf(t, 0.0, 1.0)
	var full := 0.5 * (right - left)
	var half_w := full * (1.0 - t * t)
	return absf(fx - 0.5) <= half_w + 0.001


## Labels for the in-game arms editor (exclude council gray).
func field_tincture_options() -> Array:
	var out: Array = []
	out.append_array(COLOURS)
	out.append_array(METALS)
	return out


func primary_options() -> Array:
	return COLOURS.duplicate()


func secondary_options() -> Array:
	return METALS.duplicate()


func division_labels() -> PackedStringArray:
	return PackedStringArray(["Solid", "Halved", "Quartered"])


func pattern_labels() -> PackedStringArray:
	return PackedStringArray(["Solid", "Bends \\", "Bars", "Chevron", "Bends /"])


func charge_layout_labels() -> PackedStringArray:
	return PackedStringArray(["None", "One", "Three (2+1)"])


func charge_type_labels() -> PackedStringArray:
	return PackedStringArray(["Star", "Heart"])


func field_labels(division: int) -> PackedStringArray:
	match clampi(division, 0, 2):
		DIVISION.PER_PALE:
			return PackedStringArray(["Left", "Right"])
		DIVISION.QUARTERED:
			return PackedStringArray(["Top-left", "Top-right", "Bottom-left", "Bottom-right"])
		_:
			return PackedStringArray(["Field"])


func tincture_display_name(key: String) -> String:
	match key:
		"or": return "Or (gold)"
		"argent": return "Argent (silver)"
		"gules": return "Gules (red)"
		"azure": return "Azure (blue)"
		"vert": return "Vert (green)"
		"sable": return "Sable (black)"
		"purpure": return "Purpure (purple)"
		"council_gray": return "Gray"
		_: return key.capitalize()


func _near_heater_edge(x: int, y: int, w: int, ht: int) -> bool:
	if not _in_heater(x, y, w, ht):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if not _in_heater(x + dx, y + dy, w, ht):
				return true
	return false


## Field index: 0 for solid; 0/1 for pale; 0..3 for quarters (TL, TR, BL, BR).
func _field_at(x: int, y: int, w: int, ht: int, division: int) -> int:
	var fx := (float(x) + 0.5) / float(w)
	var fy := (float(y) + 0.5) / float(ht)
	match division:
		DIVISION.PER_PALE:
			return 0 if fx < 0.5 else 1
		DIVISION.QUARTERED:
			var left := fx < 0.5
			var top := fy < 0.52
			if top and left:
				return 0
			if top and not left:
				return 1
			if not top and left:
				return 2
			return 3
		_:
			return 0


## Which fields use the primary tincture (others use secondary).
func _field_is_primary(field_i: int, division: int) -> bool:
	match division:
		DIVISION.PER_PALE:
			return field_i == 0
		DIVISION.QUARTERED:
			# Standard: TL + BR primary, TR + BL secondary.
			return field_i == 0 or field_i == 3
		_:
			return true


func _field_center(field_i: int, division: int) -> Vector2:
	match division:
		DIVISION.PER_PALE:
			return Vector2(0.28, 0.42) if field_i == 0 else Vector2(0.72, 0.42)
		DIVISION.QUARTERED:
			match field_i:
				0: return Vector2(0.28, 0.30)
				1: return Vector2(0.72, 0.30)
				2: return Vector2(0.30, 0.62)
				_: return Vector2(0.70, 0.62)
		_:
			return Vector2(0.5, 0.42)


func _pattern_mark(x: int, y: int, w: int, ht: int, pattern: int, field_i: int, division: int) -> bool:
	var step := maxi(3, int(round(float(mini(w, ht)) / 8.0)))
	# Localize pattern origin to the field so halves/quarters look distinct.
	var origin := _field_center(field_i, division)
	var lx := x - int(origin.x * w)
	var ly := y - int(origin.y * ht)
	match pattern:
		PATTERN.BENDS:
			return posmod(lx + ly + 64, step * 2) < step / 2 + 1
		PATTERN.BENDS_SINISTER:
			return posmod(lx - ly + 128, step * 2) < step / 2 + 1
		PATTERN.BARS:
			return posmod(ly + 64, step * 2) < step / 2 + 1
		PATTERN.CHEVRON:
			var mid := int(origin.x * w)
			var band := maxi(2, step / 2)
			var chev_y := int(abs(x - mid) * 0.9) + int(origin.y * ht) - ht / 10
			return abs(y - chev_y) <= band or abs(y - (chev_y + step)) <= band
		_:
			return false


func _draw_field_charges(
		img: Image, w: int, ht: int,
		field_i: int, division: int,
		layout: int, charge_type: int,
		ink: Color
	) -> void:
	var center := _field_center(field_i, division)
	var positions: Array[Vector2] = []
	var scale := 1.0 if division == DIVISION.SOLID else (0.85 if division == DIVISION.PER_PALE else 0.7)
	if layout == CHARGE_LAYOUT.ONE:
		positions.append(center)
	else:
		var dx := 0.10 * scale
		var dy := 0.10 * scale
		positions.append(center + Vector2(-dx, -dy))
		positions.append(center + Vector2(dx, -dy))
		positions.append(center + Vector2(0.0, dy * 1.1))
	var radius := float(mini(w, ht)) * (0.14 if layout == CHARGE_LAYOUT.ONE else 0.09) * scale
	for p in positions:
		var cx := int(clampf(p.x, 0.08, 0.92) * w)
		var cy := int(clampf(p.y, 0.10, 0.88) * ht)
		if charge_type == CHARGE_TYPE.HEART:
			_stamp_heart(img, cx, cy, radius, ink, w, ht)
		else:
			_stamp_star(img, cx, cy, radius, ink, w, ht)


func _stamp_star(img: Image, cx: int, cy: int, radius: float, col: Color, w: int, ht: int) -> void:
	var outer := radius
	var inner := radius * 0.42
	var points: PackedVector2Array = PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + float(i) * PI / 5.0
		var r := outer if i % 2 == 0 else inner
		points.append(Vector2(cx + cos(ang) * r, cy + sin(ang) * r))
	_fill_polygon(img, points, col, w, ht)


func _stamp_heart(img: Image, cx: int, cy: int, radius: float, col: Color, w: int, ht: int) -> void:
	var r := radius
	var min_x := int(cx - r - 1)
	var max_x := int(cx + r + 1)
	var min_y := int(cy - r - 1)
	var max_y := int(cy + r * 1.15 + 1)
	for y in range(maxi(0, min_y), mini(ht, max_y + 1)):
		for x in range(maxi(0, min_x), mini(w, max_x + 1)):
			if not _in_heater(x, y, w, ht):
				continue
			var nx := (float(x) - float(cx)) / r
			var ny := (float(y) - float(cy)) / r
			var left := (nx + 0.35) * (nx + 0.35) + (ny + 0.2) * (ny + 0.2) <= 0.22
			var right := (nx - 0.35) * (nx - 0.35) + (ny + 0.2) * (ny + 0.2) <= 0.22
			var point := ny > -0.05 and ny < 1.05 and absf(nx) <= (1.0 - ny) * 0.55
			if left or right or point:
				img.set_pixel(x, y, col)


func _fill_polygon(img: Image, points: PackedVector2Array, col: Color, w: int, ht: int) -> void:
	if points.size() < 3:
		return
	var min_x := int(points[0].x)
	var max_x := min_x
	var min_y := int(points[0].y)
	var max_y := min_y
	for p in points:
		min_x = mini(min_x, int(p.x))
		max_x = maxi(max_x, int(p.x))
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))
	for y in range(maxi(0, min_y), mini(ht, max_y + 1)):
		for x in range(maxi(0, min_x), mini(w, max_x + 1)):
			if not _in_heater(x, y, w, ht):
				continue
			if _point_in_poly(Vector2(x + 0.5, y + 0.5), points):
				img.set_pixel(x, y, col)


func _point_in_poly(pt: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var pi := poly[i]
		var pj := poly[j]
		if ((pi.y > pt.y) != (pj.y > pt.y)) and \
				(pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y + 0.00001) + pi.x):
			inside = not inside
		j = i
	return inside
