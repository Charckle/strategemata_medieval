class_name MapMatrixGenerator
extends RefCounted

## Builds a land-only province matrix. Grid side grows with province count.
## Uses spaced seed placement + multi-source BFS territory fill + plot kit.

## Target land cells per province (drives side length). Sized for spaced plot kit.
const CELLS_PER_PROVINCE := 240
const MIN_SIDE := 32
const MAX_SIDE := 140
## Fraction of side used as minimum seat spacing (clamped).
const MIN_SEAT_SPACING_FACTOR := 0.22
const MIN_SEAT_SPACING_FLOOR := 3
const SEED_PLACE_ATTEMPTS := 400
const FULL_MAP_RETRIES := 48


static func side_for_provinces(province_count: int) -> int:
	var n := clampi(province_count, 1, 64)
	var side := int(ceil(sqrt(float(n) * float(CELLS_PER_PROVINCE))))
	return clampi(side, MIN_SIDE, MAX_SIDE)


static func min_seat_spacing(side: int, province_count: int) -> int:
	var from_factor := int(floor(float(side) * MIN_SEAT_SPACING_FACTOR))
	## Soften spacing when many provinces so placement still succeeds.
	var density_cap := int(floor(float(side) / (sqrt(float(maxi(province_count, 1))) * 0.95)))
	return maxi(MIN_SEAT_SPACING_FLOOR, mini(from_factor, density_cap))


static func generate(province_count: int, seed_value: int = 0) -> MapMatrix:
	var n := clampi(province_count, 3, 20)
	var base_seed := seed_value if seed_value != 0 else randi()
	var want_plots := MapMatrixPlotPlacer.KIT.size() * n
	var last: MapMatrix = null
	for attempt in FULL_MAP_RETRIES:
		var matrix := _generate_once(n, base_seed + attempt * 9973)
		last = matrix
		if matrix.plots.size() != want_plots:
			continue
		if not MapMatrixRoadBuilder.build(matrix):
			continue
		if MapMatrixValidator.validate(matrix).is_empty():
			return matrix
	## Last resort: best effort on the last successful plot layout.
	if last != null and last.plots.size() == want_plots:
		MapMatrixRoadBuilder.build(last)
	return last


static func _generate_once(n: int, seed_value: int) -> MapMatrix:
	var side := side_for_provinces(n)
	var matrix := MapMatrix.new(side, side, n)
	matrix.seed_used = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var spacing := min_seat_spacing(side, n)
	var seed_cells := _place_seeds(rng, side, n, spacing)
	if seed_cells.size() < n:
		seed_cells = _place_seeds(rng, side, n, maxi(2, spacing / 2))
	if seed_cells.size() < n:
		seed_cells = _place_seeds_grid(side, n)

	for i in n:
		matrix.seats[i] = seed_cells[i]

	_assign_flood(matrix, seed_cells)
	if not MapMatrixPlotPlacer.place_all(matrix, rng):
		matrix.plots.clear()
	return matrix


static func _place_seeds(
	rng: RandomNumberGenerator, side: int, count: int, min_dist: int
) -> Array[Vector2i]:
	var placed: Array[Vector2i] = []
	var min_dist_sq := min_dist * min_dist
	var attempts := SEED_PLACE_ATTEMPTS * count
	for _i in attempts:
		if placed.size() >= count:
			break
		var c := Vector2i(rng.randi_range(0, side - 1), rng.randi_range(0, side - 1))
		var ok := true
		for other in placed:
			var d := c - other
			if d.x * d.x + d.y * d.y < min_dist_sq:
				ok = false
				break
		if ok:
			placed.append(c)
	return placed


static func _place_seeds_grid(side: int, count: int) -> Array[Vector2i]:
	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(cols)))
	var placed: Array[Vector2i] = []
	var i := 0
	for r in rows:
		for c in cols:
			if i >= count:
				break
			var x := int(round((float(c) + 0.5) * float(side) / float(cols)))
			var y := int(round((float(r) + 0.5) * float(side) / float(rows)))
			x = clampi(x, 0, side - 1)
			y = clampi(y, 0, side - 1)
			placed.append(Vector2i(x, y))
			i += 1
	return placed


static func _assign_flood(matrix: MapMatrix, seeds: Array[Vector2i]) -> void:
	matrix.cells.fill(MapMatrix.INVALID)
	var queue: Array[Vector2i] = []
	for i in seeds.size():
		var s: Vector2i = seeds[i]
		matrix.set_cell(s, i)
		queue.append(s)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		var owner := matrix.get_cell(c)
		for dir in dirs:
			var n: Vector2i = c + dir
			if not matrix.in_bounds(n):
				continue
			if matrix.get_cell(n) != MapMatrix.INVALID:
				continue
			matrix.set_cell(n, owner)
			queue.append(n)
