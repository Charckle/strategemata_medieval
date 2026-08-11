class_name MapMatrixTerrain
extends RefCounted

## Fills MapMatrix.terrain: mountain ridges with hill flanks, plus scattered trees.
## Never overwrites plot footprints or road cells (roads need walkable ground).

const TREE_CHANCE := 0.09
const TREE_CLUSTER_BONUS := 0.18
const HILL_RADIUS := 2


static func apply(matrix: MapMatrix, rng: RandomNumberGenerator) -> void:
	if matrix == null or matrix.width <= 0:
		return
	matrix.clear_terrain()
	var reserved := _reserved_cells(matrix)
	_paint_ridges(matrix, rng, reserved)
	_scatter_trees(matrix, rng, reserved)


static func _reserved_cells(matrix: MapMatrix) -> Dictionary:
	var reserved: Dictionary = {}
	for plot in matrix.plots:
		var origin: Vector2i = plot.get("origin", Vector2i.ZERO)
		var size: Vector2i = plot.get("size", Vector2i.ONE)
		for cell in matrix.footprint_cells(origin, size):
			reserved[cell] = true
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if matrix.has_road(c):
				reserved[c] = true
	return reserved


static func _paint_ridges(
	matrix: MapMatrix, rng: RandomNumberGenerator, reserved: Dictionary
) -> void:
	var side := maxi(matrix.width, matrix.height)
	var ridge_count := clampi(1 + side / 28, 1, 4)
	var mountains: Dictionary = {}
	for _r in ridge_count:
		for cell in _trace_ridge(matrix, rng):
			if reserved.has(cell):
				continue
			mountains[cell] = true
			matrix.set_terrain(cell, MapMatrix.Terrain.MOUNTAINS)

	## Hill flanks around mountain spine.
	for cell in mountains.keys():
		for dy in range(-HILL_RADIUS, HILL_RADIUS + 1):
			for dx in range(-HILL_RADIUS, HILL_RADIUS + 1):
				if dx == 0 and dy == 0:
					continue
				var n: Vector2i = cell + Vector2i(dx, dy)
				if not matrix.in_bounds(n) or reserved.has(n):
					continue
				if matrix.get_terrain(n) == MapMatrix.Terrain.MOUNTAINS:
					continue
				## Soft falloff: outer ring less often.
				var dist := maxi(absi(dx), absi(dy))
				if dist == 1 or rng.randf() < 0.65:
					matrix.set_terrain(n, MapMatrix.Terrain.HILLS)


static func _trace_ridge(matrix: MapMatrix, rng: RandomNumberGenerator) -> Array[Vector2i]:
	## Random walk from one map edge toward the opposite side.
	var w := matrix.width
	var h := matrix.height
	var horizontal := rng.randf() < 0.5
	var path: Array[Vector2i] = []
	var seen: Dictionary = {}
	var x: int
	var y: int
	var dir: int
	var steps: int
	if horizontal:
		var from_left := rng.randf() < 0.5
		x = 0 if from_left else w - 1
		y = rng.randi_range(maxi(1, h / 5), maxi(1, (h * 4) / 5))
		dir = 1 if from_left else -1
		steps = w + rng.randi_range(0, h / 3)
	else:
		var from_top := rng.randf() < 0.5
		y = 0 if from_top else h - 1
		x = rng.randi_range(maxi(1, w / 5), maxi(1, (w * 4) / 5))
		dir = 1 if from_top else -1
		steps = h + rng.randi_range(0, w / 3)

	for _s in steps:
		var c := Vector2i(x, y)
		if not seen.has(c):
			seen[c] = true
			path.append(c)
			if rng.randf() < 0.35:
				var side := Vector2i(0, 1) if horizontal else Vector2i(1, 0)
				if rng.randf() < 0.5:
					side = -side
				var c2: Vector2i = c + side
				if matrix.in_bounds(c2) and not seen.has(c2):
					seen[c2] = true
					path.append(c2)
		if horizontal:
			x += dir
			if rng.randf() < 0.75:
				y += rng.randi_range(-1, 1)
		else:
			y += dir
			if rng.randf() < 0.75:
				x += rng.randi_range(-1, 1)
		if x < 0 or x >= w or y < 0 or y >= h:
			break
		x = clampi(x, 0, w - 1)
		y = clampi(y, 0, h - 1)
	return path


static func _scatter_trees(
	matrix: MapMatrix, rng: RandomNumberGenerator, reserved: Dictionary
) -> void:
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if reserved.has(c):
				continue
			if matrix.get_terrain(c) != MapMatrix.Terrain.GRASS:
				continue
			var chance := TREE_CHANCE
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + dir
				if matrix.in_bounds(n) and matrix.get_terrain(n) == MapMatrix.Terrain.TREES:
					chance += TREE_CLUSTER_BONUS
					break
			if rng.randf() < chance:
				matrix.set_terrain(c, MapMatrix.Terrain.TREES)
