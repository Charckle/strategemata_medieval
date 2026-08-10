class_name MapMatrixValidator
extends RefCounted

## Topology + plot-kit checks for an abstract MapMatrix (before baking).

const MIN_PROVINCE_CELLS := 8

const EXPECTED_KIND_COUNTS := {
	MapMatrix.PlotKind.TOWN: 1,
	MapMatrix.PlotKind.CASTLE: 1,
	MapMatrix.PlotKind.VILLAGE: 3,
	MapMatrix.PlotKind.FIELD: 16,
	MapMatrix.PlotKind.ECONOMY_EMPTY: 2,
	MapMatrix.PlotKind.DEPOSIT_RANDOM: 1,
}


static func validate(matrix: MapMatrix) -> PackedStringArray:
	var issues: PackedStringArray = []
	if matrix == null:
		issues.append("Matrix is null.")
		return issues
	if matrix.width <= 0 or matrix.height <= 0:
		issues.append("Matrix has invalid size.")
		return issues
	if matrix.province_count < 3 or matrix.province_count > 20:
		issues.append("Province count %d outside 3–20." % matrix.province_count)

	var sizes := matrix.province_sizes()
	for pid in matrix.province_count:
		if sizes[pid] <= 0:
			issues.append("Province %d has no cells." % pid)
		elif sizes[pid] < MIN_PROVINCE_CELLS:
			issues.append("Province %d is too small (%d cells)." % [pid, sizes[pid]])

		var seat: Vector2i = matrix.seats[pid] if pid < matrix.seats.size() else Vector2i(-1, -1)
		if not matrix.in_bounds(seat):
			issues.append("Province %d has no valid seat." % pid)
		elif matrix.get_cell(seat) != pid:
			issues.append("Province %d seat is not inside its territory." % pid)
		elif not _is_connected(matrix, pid, seat):
			issues.append("Province %d territory is not connected." % pid)

	for v in matrix.cells:
		if v < 0 or v >= matrix.province_count:
			issues.append("Found unassigned / invalid cell value %d." % v)
			break

	issues.append_array(_validate_plots(matrix))
	issues.append_array(_validate_roads(matrix))
	return issues


static func _validate_plots(matrix: MapMatrix) -> PackedStringArray:
	var issues: PackedStringArray = []
	var occupied: Dictionary = {} ## Vector2i -> plot index

	for i in matrix.plots.size():
		var plot: Dictionary = matrix.plots[i]
		var kind := int(plot.get("kind", -1))
		var pid := int(plot.get("province_id", -1))
		var origin: Vector2i = plot.get("origin", Vector2i(-1, -1))
		var size: Vector2i = plot.get("size", Vector2i.ZERO)
		if pid < 0 or pid >= matrix.province_count:
			issues.append("Plot %d has invalid province_id." % i)
			continue
		if size != MapMatrix.plot_footprint_size(kind):
			issues.append("Plot %d has wrong footprint size." % i)
		var foot := matrix.footprint_cells(origin, size)
		for cell in foot:
			if not matrix.in_bounds(cell):
				issues.append("Plot %d footprint out of bounds." % i)
				break
			if matrix.get_cell(cell) != pid:
				issues.append("Plot %d footprint leaves province %d." % [i, pid])
				break
			if occupied.has(cell):
				issues.append("Plot overlap at %s." % str(cell))
			else:
				occupied[cell] = i

	## Kit counts per province.
	for pid in matrix.province_count:
		var counts := {}
		for k in EXPECTED_KIND_COUNTS.keys():
			counts[k] = 0
		for plot in matrix.plots_for_province(pid):
			var kind := int(plot.get("kind", -1))
			counts[kind] = int(counts.get(kind, 0)) + 1
		for k in EXPECTED_KIND_COUNTS.keys():
			var want: int = EXPECTED_KIND_COUNTS[k]
			var got: int = int(counts.get(k, 0))
			if got != want:
				issues.append(
					"Province %d: %s count %d (want %d)."
					% [pid, MapMatrix.plot_letter(k), got, want]
				)

	## Hard rule: no orthogonal adjacency between different plots (fields may touch fields).
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var reported := {}
	for cell in occupied.keys():
		var a: int = occupied[cell]
		var kind_a := int(matrix.plots[a].get("kind", -1))
		for dir in dirs:
			var n: Vector2i = cell + dir
			if not occupied.has(n):
				continue
			var b: int = occupied[n]
			if a == b:
				continue
			var kind_b := int(matrix.plots[b].get("kind", -1))
			if (
				kind_a == MapMatrix.PlotKind.FIELD
				and kind_b == MapMatrix.PlotKind.FIELD
			):
				continue
			var key := "%d-%d" % [mini(a, b), maxi(a, b)]
			if reported.has(key):
				continue
			reported[key] = true
			issues.append("Plots %d and %d are orthogonally adjacent." % [a, b])

	return issues


static func _validate_roads(matrix: MapMatrix) -> PackedStringArray:
	var issues: PackedStringArray = []
	var blocked: Dictionary = {}
	for plot in matrix.plots:
		var origin: Vector2i = plot.get("origin", Vector2i.ZERO)
		var size: Vector2i = plot.get("size", Vector2i.ONE)
		for cell in matrix.footprint_cells(origin, size):
			blocked[cell] = true

	var road_n := 0
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if not matrix.has_road(c):
				continue
			road_n += 1
			if blocked.has(c):
				issues.append("Road on blocked cell %s." % str(c))

	if matrix.plots.is_empty():
		return issues
	if road_n == 0:
		issues.append("No roads generated.")
		return issues

	## Each hub's road contacts must be walkable around the building (no portal).
	for plot in matrix.plots:
		if not MapMatrix.is_road_hub_kind(int(plot.get("kind", -1))):
			continue
		if not _hub_skirt_connected(matrix, plot, blocked):
			var pname := MapMatrix.plot_letter(int(plot.get("kind", -1)))
			issues.append(
				"Hub %s at %s has split roads (cannot walk around)."
				% [pname, str(plot.get("origin", Vector2i.ZERO))]
			)

	## Intra-province hubs should share one real road network.
	for pid in matrix.province_count:
		var hubs: Array[Dictionary] = []
		for plot in matrix.plots_for_province(pid):
			if MapMatrix.is_road_hub_kind(int(plot.get("kind", -1))):
				hubs.append(plot)
		if hubs.size() <= 1:
			continue
		if not _hubs_road_connected(matrix, hubs, blocked):
			issues.append("Province %d hubs are not fully road-connected." % pid)

	## Neighbor provinces should have a road link.
	for pair in MapMatrixRoadBuilder.province_neighbor_pairs(matrix):
		var a = pair.x
		var b = pair.y
		if not _provinces_road_linked(matrix, a, b, blocked):
			issues.append("No road link between provinces %d and %d." % [a, b])

	## No 2×2 road blocks (stacked / double-wide pavement).
	var stack_reports := 0
	for y in matrix.height - 1:
		for x in matrix.width - 1:
			var c00 := Vector2i(x, y)
			var c10 := Vector2i(x + 1, y)
			var c01 := Vector2i(x, y + 1)
			var c11 := Vector2i(x + 1, y + 1)
			if (
				matrix.has_road(c00)
				and matrix.has_road(c10)
				and matrix.has_road(c01)
				and matrix.has_road(c11)
			):
				stack_reports += 1
				if stack_reports <= 5:
					issues.append("Stacked roads (2×2) at %s." % str(c00))
	if stack_reports > 5:
		issues.append("…and %d more stacked 2×2 road blocks." % (stack_reports - 5))

	return issues


static func _access_cells(
	matrix: MapMatrix, plot: Dictionary, blocked: Dictionary
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var origin: Vector2i = plot.get("origin", Vector2i.ZERO)
	var size: Vector2i = plot.get("size", Vector2i.ONE)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for cell in matrix.footprint_cells(origin, size):
		for dir in dirs:
			var n: Vector2i = cell + dir
			if seen.has(n) or not matrix.in_bounds(n) or blocked.has(n):
				continue
			seen[n] = true
			out.append(n)
	return out


static func _hub_skirt_connected(
	matrix: MapMatrix, plot: Dictionary, blocked: Dictionary
) -> bool:
	var contacts: Array[Vector2i] = []
	for cell in _access_cells(matrix, plot, blocked):
		if matrix.has_road(cell):
			contacts.append(cell)
	if contacts.size() <= 1:
		return true
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [contacts[0]]
	seen[contacts[0]] = true
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		for dir in dirs:
			var n: Vector2i = c + dir
			if seen.has(n) or not matrix.has_road(n):
				continue
			seen[n] = true
			queue.append(n)
	for cell in contacts:
		if not seen.has(cell):
			return false
	return true


static func _hubs_road_connected(
	matrix: MapMatrix, hubs: Array[Dictionary], blocked: Dictionary
) -> bool:
	## Real roads only — walk around buildings, never teleport through them.
	var seen_road: Dictionary = {}
	var queue: Array[Vector2i] = []
	for cell in _access_cells(matrix, hubs[0], blocked):
		if matrix.has_road(cell):
			seen_road[cell] = true
			queue.append(cell)
	if queue.is_empty():
		return false

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		for dir in dirs:
			var n: Vector2i = c + dir
			if seen_road.has(n) or not matrix.has_road(n):
				continue
			seen_road[n] = true
			queue.append(n)

	for plot in hubs:
		var touched := false
		for cell in _access_cells(matrix, plot, blocked):
			if seen_road.has(cell):
				touched = true
				break
		if not touched:
			return false
	return true


static func _provinces_road_linked(
	matrix: MapMatrix, a: int, b: int, _blocked: Dictionary
) -> bool:
	## Follow road cells only: any road in A reachable to any road in B.
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if matrix.get_cell(c) != a or not matrix.has_road(c):
				continue
			seen[c] = true
			queue.append(c)

	if queue.is_empty():
		return false

	var q_i := 0
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		if matrix.get_cell(c) == b:
			return true
		for dir in dirs:
			var n: Vector2i = c + dir
			if seen.has(n) or not matrix.has_road(n):
				continue
			seen[n] = true
			queue.append(n)
	return false


static func _is_connected(matrix: MapMatrix, province_id: int, start: Vector2i) -> bool:
	var target := 0
	for v in matrix.cells:
		if v == province_id:
			target += 1
	if target <= 0:
		return false
	if matrix.get_cell(start) != province_id:
		return false

	var seen := {}
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var reached := 0
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		reached += 1
		for dir in dirs:
			var n: Vector2i = c + dir
			if seen.has(n):
				continue
			if matrix.get_cell(n) != province_id:
				continue
			seen[n] = true
			queue.append(n)
	return reached == target
