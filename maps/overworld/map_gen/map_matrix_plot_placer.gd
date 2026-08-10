class_name MapMatrixPlotPlacer
extends RefCounted

## Places the standard province kit into an existing MapMatrix.
## Preferred: no 8-neighbor touch between plots. Hard: no orthogonal adjacency.
## Exception: fields may touch other fields.

const KIT: Array[int] = [
	MapMatrix.PlotKind.TOWN,
	MapMatrix.PlotKind.CASTLE,
	MapMatrix.PlotKind.VILLAGE,
	MapMatrix.PlotKind.VILLAGE,
	MapMatrix.PlotKind.VILLAGE,
	MapMatrix.PlotKind.DEPOSIT_RANDOM,
	MapMatrix.PlotKind.ECONOMY_EMPTY,
	MapMatrix.PlotKind.ECONOMY_EMPTY,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
	MapMatrix.PlotKind.FIELD,
]

const ATTEMPTS_PER_PLOT := 300
const PROVINCE_RETRY := 10


static func place_all(matrix: MapMatrix, rng: RandomNumberGenerator) -> bool:
	matrix.plots.clear()
	## Global occupancy so border plots in neighboring provinces cannot touch.
	var global_occupied: Dictionary = {}
	for pid in matrix.province_count:
		if not _place_province(matrix, rng, pid, global_occupied):
			matrix.plots.clear()
			return false
	return true


static func _place_province(
	matrix: MapMatrix, rng: RandomNumberGenerator, pid: int, global_occupied: Dictionary
) -> bool:
	var candidates := _province_cells(matrix, pid)
	if candidates.is_empty():
		return false

	for _retry in PROVINCE_RETRY:
		## Start from plots already placed in other provinces.
		var occupied: Dictionary = global_occupied.duplicate()
		var placed_local: Array[Dictionary] = []
		var ok := true
		for kind in KIT:
			var plot := _try_place_one(matrix, rng, pid, kind, candidates, occupied, true)
			if plot.is_empty():
				plot = _try_place_one(matrix, rng, pid, kind, candidates, occupied, false)
			if plot.is_empty():
				ok = false
				break
			placed_local.append(plot)
			for cell in matrix.footprint_cells(plot["origin"], plot["size"]):
				occupied[cell] = int(plot["kind"])
		if not ok:
			continue
		for plot in placed_local:
			matrix.plots.append(plot)
			for cell in matrix.footprint_cells(plot["origin"], plot["size"]):
				global_occupied[cell] = int(plot["kind"])
		for plot in placed_local:
			if int(plot["kind"]) == MapMatrix.PlotKind.TOWN:
				matrix.seats[pid] = plot["origin"]
				break
		return true
	return false


static func _try_place_one(
	matrix: MapMatrix,
	rng: RandomNumberGenerator,
	pid: int,
	kind: int,
	candidates: Array[Vector2i],
	occupied: Dictionary,
	prefer_wide_gap: bool
) -> Dictionary:
	var size := MapMatrix.plot_footprint_size(kind)
	var origins := _valid_origins(matrix, pid, size, candidates)
	if origins.is_empty():
		return {}
	## Sample without replacement first, then random retries.
	var order: Array[Vector2i] = origins.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2i = order[i]
		order[i] = order[j]
		order[j] = tmp
	var limit := mini(order.size(), ATTEMPTS_PER_PLOT)
	for i in limit:
		var origin: Vector2i = order[i]
		var foot := matrix.footprint_cells(origin, size)
		if not _fits(kind, foot, occupied, prefer_wide_gap):
			continue
		return {
			"kind": kind,
			"province_id": pid,
			"origin": origin,
			"size": size,
		}
	return {}


static func _province_cells(matrix: MapMatrix, pid: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if matrix.get_cell(c) == pid:
				out.append(c)
	return out


static func _valid_origins(
	matrix: MapMatrix, pid: int, size: Vector2i, candidates: Array[Vector2i]
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in candidates:
		if c.x + size.x > matrix.width or c.y + size.y > matrix.height:
			continue
		var ok := true
		for dy in size.y:
			for dx in size.x:
				if matrix.get_cell(c + Vector2i(dx, dy)) != pid:
					ok = false
					break
			if not ok:
				break
		if ok:
			out.append(c)
	return out


static func _neighbor_blocked(kind: int, neighbor_kind: int) -> bool:
	## Fields may touch other fields.
	if kind == MapMatrix.PlotKind.FIELD and neighbor_kind == MapMatrix.PlotKind.FIELD:
		return false
	return true


static func _fits(
	kind: int, foot: Array[Vector2i], occupied: Dictionary, prefer_wide_gap: bool
) -> bool:
	var foot_set: Dictionary = {}
	for cell in foot:
		if occupied.has(cell):
			return false
		foot_set[cell] = true

	if prefer_wide_gap:
		## No 8-neighbor contact with incompatible plots.
		for cell in foot:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var n := cell + Vector2i(dx, dy)
					if foot_set.has(n):
						continue
					if not occupied.has(n):
						continue
					if _neighbor_blocked(kind, int(occupied[n])):
						return false
	else:
		## Hard rule: never orthogonally adjacent (except field–field).
		for cell in foot:
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cell + dir
				if foot_set.has(n):
					continue
				if not occupied.has(n):
					continue
				if _neighbor_blocked(kind, int(occupied[n])):
					return false
	return true
