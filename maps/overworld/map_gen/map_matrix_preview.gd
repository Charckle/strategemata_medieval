class_name MapMatrixPreview
extends Control

## Draws a MapMatrix as colored squares with white plot letters.

var matrix: MapMatrix = null
var _palette: PackedColorArray = PackedColorArray()


func set_matrix(m: MapMatrix) -> void:
	matrix = m
	_rebuild_palette()
	queue_redraw()


func _rebuild_palette() -> void:
	_palette.clear()
	if matrix == null:
		return
	for i in matrix.province_count:
		var h := fmod(float(i) * 0.61803398875, 1.0)
		_palette.append(Color.from_hsv(h, 0.55, 0.92))


func _draw() -> void:
	var rect := get_rect()
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.12, 0.12, 0.14))
	if matrix == null or matrix.width <= 0 or matrix.height <= 0:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(12, 28),
			"No matrix yet — hit Reroll",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(0.75, 0.75, 0.78)
		)
		return

	var cell_w := rect.size.x / float(matrix.width)
	var cell_h := rect.size.y / float(matrix.height)
	var cell := mini(cell_w, cell_h)
	var origin := Vector2(
		(rect.size.x - cell * float(matrix.width)) * 0.5,
		(rect.size.y - cell * float(matrix.height)) * 0.5
	)

	for y in matrix.height:
		for x in matrix.width:
			var pos := Vector2i(x, y)
			var pid := matrix.get_cell(pos)
			var col := Color(0.25, 0.25, 0.28)
			if pid >= 0 and pid < _palette.size():
				col = _palette[pid]
			## Terrain tint on top of province color.
			match matrix.get_terrain(pos):
				MapMatrix.Terrain.HILLS:
					col = col.lerp(Color(0.55, 0.7, 0.35), 0.45)
				MapMatrix.Terrain.MOUNTAINS:
					col = col.lerp(Color(0.45, 0.45, 0.5), 0.7)
				MapMatrix.Terrain.TREES:
					col = col.lerp(Color(0.12, 0.45, 0.18), 0.55)
			var r := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			draw_rect(r, col)
			if matrix.has_road(pos):
				var inset := maxf(1.0, cell * 0.18)
				var rr := r.grow(-inset)
				draw_rect(rr, Color(0.45, 0.28, 0.12, 0.92))

	## Slightly darken occupied footprint cells, then letter at footprint center.
	var font := ThemeDB.fallback_font
	var font_size := clampi(int(cell * 0.72), 8, 22)
	for plot in matrix.plots:
		var kind := int(plot.get("kind", -1))
		var p_origin: Vector2i = plot.get("origin", Vector2i.ZERO)
		var p_size: Vector2i = plot.get("size", Vector2i.ONE)
		var letter := MapMatrix.plot_letter(kind)
		for cell_pos in matrix.footprint_cells(p_origin, p_size):
			var r := Rect2(origin + Vector2(cell_pos) * cell, Vector2(cell, cell))
			draw_rect(r, Color(0, 0, 0, 0.22))
		var center := origin + (Vector2(p_origin) + Vector2(p_size) * 0.5) * cell
		var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := center - text_size * 0.5 + Vector2(0, text_size.y * 0.35)
		draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))
