class_name MapMatrixRoadBuilder
extends RefCounted

## Orthogonal roads on empty land only (not fields / building footprints).
## Build network with hub portals, then stitch real thin skirts so an army can
## walk road-to-road around T/C/V/E/D (no teleport through the building).
## Paths stay thin: never create a 2×2 block of road cells.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


static func build(matrix: MapMatrix) -> bool:
	if matrix == null or matrix.plots.is_empty():
		return false
	matrix.clear_roads()
	var blocked := _build_blocked(matrix)
	var ok := true
	for pid in matrix.province_count:
		if not _connect_province(matrix, pid, blocked):
			ok = false
	if not _connect_neighbor_provinces(matrix, blocked):
		ok = false
	if not _ensure_hub_skirts(matrix, blocked):
		ok = false
	_strip_road_squares(matrix)
	## Strip can nick a skirt corner — repair once more.
	if not _ensure_hub_skirts(matrix, blocked):
		ok = false
	_strip_road_squares(matrix)
	return ok


static func _build_blocked(matrix: MapMatrix) -> Dictionary:
	var blocked: Dictionary = {}
	for plot in matrix.plots:
		var origin: Vector2i = plot.get("origin", Vector2i.ZERO)
		var size: Vector2i = plot.get("size", Vector2i.ONE)
		for cell in matrix.footprint_cells(origin, size):
			blocked[cell] = true
	return blocked


static func _is_walkable(matrix: MapMatrix, cell: Vector2i, blocked: Dictionary) -> bool:
	return matrix.in_bounds(cell) and not blocked.has(cell)


static func _hub_plots(matrix: MapMatrix, pid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plot in matrix.plots_for_province(pid):
		if MapMatrix.is_road_hub_kind(int(plot.get("kind", -1))):
			out.append(plot)
	return out


static func _access_cells(
	matrix: MapMatrix, plot: Dictionary, blocked: Dictionary
) -> Array[Vector2i]:
	var origin: Vector2i = plot.get("origin", Vector2i.ZERO)
	var size: Vector2i = plot.get("size", Vector2i.ONE)
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	for cell in matrix.footprint_cells(origin, size):
		for dir in DIRS:
			var n: Vector2i = cell + dir
			if seen.has(n):
				continue
			if not _is_walkable(matrix, n, blocked):
				continue
			seen[n] = true
			out.append(n)
	return out


static func _connect_province(matrix: MapMatrix, pid: int, blocked: Dictionary) -> bool:
	var hubs := _hub_plots(matrix, pid)
	if hubs.is_empty():
		return true
	var access_sets: Array = []
	for plot in hubs:
		var acc := _access_cells(matrix, plot, blocked)
		if acc.is_empty():
			return false
		access_sets.append(acc)

	var connected: Dictionary = {0: true}

	while connected.size() < hubs.size():
		var sources := _portal_sources(matrix, hubs, access_sets, connected)
		var best_path: Array[Vector2i] = []
		var best_hub := -1
		for i in hubs.size():
			if connected.has(i):
				continue
			var path := _route(matrix, sources, access_sets[i], blocked)
			if path.is_empty():
				continue
			if best_path.is_empty() or path.size() < best_path.size():
				best_path = path
				best_hub = i
		if best_hub < 0:
			return false
		_paint_path(matrix, best_path)
		connected[best_hub] = true
	return true


static func _portal_sources(
	matrix: MapMatrix,
	hubs: Array[Dictionary],
	access_sets: Array,
	connected: Dictionary
) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	for i in hubs.size():
		if not connected.has(i):
			continue
		for cell in access_sets[i]:
			if seen.has(cell):
				continue
			seen[cell] = true
			out.append(cell)

	var queue: Array[Vector2i] = []
	for cell in out:
		if matrix.has_road(cell):
			queue.append(cell)
	for cell in out.duplicate():
		for dir in DIRS:
			var n: Vector2i = cell + dir
			if matrix.has_road(n) and not seen.has(n):
				seen[n] = true
				out.append(n)
				queue.append(n)

	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		for dir in DIRS:
			var n: Vector2i = c + dir
			if seen.has(n) or not matrix.has_road(n):
				continue
			seen[n] = true
			out.append(n)
			queue.append(n)
	return out


static func province_neighbor_pairs(matrix: MapMatrix) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			var a := matrix.get_cell(c)
			if a < 0:
				continue
			for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + dir
				if not matrix.in_bounds(n):
					continue
				var b := matrix.get_cell(n)
				if b < 0 or b == a:
					continue
				var lo := mini(a, b)
				var hi := maxi(a, b)
				var key := lo * 1024 + hi
				if seen.has(key):
					continue
				seen[key] = true
				out.append(Vector2i(lo, hi))
	return out


static func _network_cells_for_province(
	matrix: MapMatrix, pid: int, blocked: Dictionary
) -> Array[Vector2i]:
	var hubs := _hub_plots(matrix, pid)
	var access_sets: Array = []
	var connected: Dictionary = {}
	for i in hubs.size():
		access_sets.append(_access_cells(matrix, hubs[i], blocked))
		connected[i] = true
	if hubs.is_empty():
		return []
	return _portal_sources(matrix, hubs, access_sets, connected)


## Link every road contact around each hub with real pavement (army-walkable).
static func _ensure_hub_skirts(matrix: MapMatrix, blocked: Dictionary) -> bool:
	var ok := true
	for plot in matrix.plots:
		if not MapMatrix.is_road_hub_kind(int(plot.get("kind", -1))):
			continue
		if not _stitch_hub_road_contacts(matrix, plot, blocked):
			ok = false
	return ok


static func _road_contacts(
	matrix: MapMatrix, plot: Dictionary, blocked: Dictionary
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _access_cells(matrix, plot, blocked):
		if matrix.has_road(cell):
			out.append(cell)
	return out


static func _stitch_hub_road_contacts(
	matrix: MapMatrix, plot: Dictionary, blocked: Dictionary
) -> bool:
	var contacts := _road_contacts(matrix, plot, blocked)
	if contacts.size() <= 1:
		return true
	var guard := 0
	while guard < 24:
		guard += 1
		var comps := _road_components_of(matrix, contacts)
		if comps.size() <= 1:
			return true
		var best_path: Array[Vector2i] = []
		for j in range(1, comps.size()):
			var path := _route(matrix, comps[0], comps[j], blocked)
			if path.is_empty():
				continue
			if best_path.is_empty() or path.size() < best_path.size():
				best_path = path
		if best_path.is_empty():
			return false
		_paint_path(matrix, best_path)
	return false


static func _road_components_of(
	matrix: MapMatrix, cells: Array[Vector2i]
) -> Array:
	var remaining: Dictionary = {}
	for c in cells:
		remaining[c] = true
	var comps: Array = []
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var comp: Array[Vector2i] = []
		var seen: Dictionary = {}
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		var q_i := 0
		while q_i < queue.size():
			var c: Vector2i = queue[q_i]
			q_i += 1
			if remaining.has(c):
				comp.append(c)
				remaining.erase(c)
			for dir in DIRS:
				var n: Vector2i = c + dir
				if seen.has(n) or not matrix.has_road(n):
					continue
				seen[n] = true
				queue.append(n)
		comps.append(comp)
	return comps


static func _connect_neighbor_provinces(matrix: MapMatrix, blocked: Dictionary) -> bool:
	var ok := true
	for pair in province_neighbor_pairs(matrix):
		var a: int = pair.x
		var b: int = pair.y
		var sources := _network_cells_for_province(matrix, a, blocked)
		var goals := _network_cells_for_province(matrix, b, blocked)
		if sources.is_empty() or goals.is_empty():
			ok = false
			continue
		## Already linked?
		if _road_reaches(matrix, sources, goals):
			continue
		var path := _route(matrix, sources, goals, blocked)
		if path.is_empty():
			ok = false
			continue
		_paint_path(matrix, path)
	return ok


## Thin path first; if blocked by 2×2 rule, take shortest then paint only non-squaring cells
## with a second thin repair pass from the carved corridor.
static func _route(
	matrix: MapMatrix,
	sources: Array[Vector2i],
	goals: Array[Vector2i],
	blocked: Dictionary
) -> Array[Vector2i]:
	var thin := _thin_path(matrix, sources, goals, blocked)
	if not thin.is_empty():
		return thin
	var fat := _shortest_path(matrix, sources, goals, blocked)
	if fat.is_empty():
		return []
	## Temporarily stage non-squaring cells along the fat corridor, then thin-route again.
	var staged: Array[Vector2i] = []
	for cell in fat:
		if matrix.has_road(cell):
			continue
		if _would_make_road_square(matrix, cell):
			continue
		staged.append(cell)
		matrix.set_road(cell, true)
	var repaired := _thin_path(matrix, sources, goals, blocked)
	for cell in staged:
		matrix.set_road(cell, false)
	if not repaired.is_empty():
		return repaired
	## Last resort: safe non-squaring subset of the fat path (must still touch both ends).
	var safe: Array[Vector2i] = []
	for cell in fat:
		if matrix.has_road(cell) or not _would_make_road_square_with(matrix, cell, safe):
			safe.append(cell)
	if _path_connects_ends(safe, sources, goals):
		return safe
	return []


static func _path_connects_ends(
	path: Array[Vector2i], sources: Array[Vector2i], goals: Array[Vector2i]
) -> bool:
	if path.is_empty():
		return false
	var src: Dictionary = {}
	var dst: Dictionary = {}
	for s in sources:
		src[s] = true
	for g in goals:
		dst[g] = true
	var has_s := false
	var has_g := false
	for c in path:
		if src.has(c):
			has_s = true
		if dst.has(c):
			has_g = true
	return has_s and has_g


static func _road_reaches(
	matrix: MapMatrix, sources: Array[Vector2i], goals: Array[Vector2i]
) -> bool:
	var goal_set: Dictionary = {}
	for g in goals:
		goal_set[g] = true
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for s in sources:
		if goal_set.has(s):
			return true
		if matrix.has_road(s) and not seen.has(s):
			seen[s] = true
			queue.append(s)
		for dir in DIRS:
			var n: Vector2i = s + dir
			if not matrix.has_road(n) or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
			if goal_set.has(n):
				return true
	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		if goal_set.has(c):
			return true
		for dir in DIRS:
			var n: Vector2i = c + dir
			if seen.has(n):
				continue
			if matrix.has_road(n) or goal_set.has(n):
				seen[n] = true
				queue.append(n)
	return false


static func _paint_path(matrix: MapMatrix, path: Array[Vector2i]) -> void:
	for cell in path:
		matrix.set_road(cell, true)


static func _thin_path(
	matrix: MapMatrix,
	sources: Array[Vector2i],
	goals: Array[Vector2i],
	blocked: Dictionary
) -> Array[Vector2i]:
	if sources.is_empty() or goals.is_empty():
		return []
	var goal_set: Dictionary = {}
	for g in goals:
		goal_set[g] = true

	var came_from: Dictionary = {}
	var head: Array[Vector2i] = []
	var tail: Array[Vector2i] = []

	for s in sources:
		if not _is_walkable(matrix, s, blocked):
			continue
		if came_from.has(s):
			continue
		came_from[s] = Vector2i(-9999, -9999)
		head.append(s)
		if goal_set.has(s):
			return [s]

	while not head.is_empty() or not tail.is_empty():
		if head.is_empty():
			head = tail
			tail = [] as Array[Vector2i]
		var c: Vector2i = head.pop_front()
		for dir in DIRS:
			var n: Vector2i = c + dir
			if came_from.has(n):
				continue
			if not _is_walkable(matrix, n, blocked):
				continue
			if not matrix.has_road(n) and not goal_set.has(n) and _would_make_road_square(matrix, n):
				continue
			came_from[n] = c
			if goal_set.has(n):
				return _reconstruct(came_from, n)
			if matrix.has_road(n):
				head.append(n)
			else:
				tail.append(n)
	return []


static func _shortest_path(
	matrix: MapMatrix,
	sources: Array[Vector2i],
	goals: Array[Vector2i],
	blocked: Dictionary
) -> Array[Vector2i]:
	if sources.is_empty() or goals.is_empty():
		return []
	var goal_set: Dictionary = {}
	for g in goals:
		goal_set[g] = true
	var came_from: Dictionary = {}
	var queue: Array[Vector2i] = []
	for s in sources:
		if not _is_walkable(matrix, s, blocked) or came_from.has(s):
			continue
		came_from[s] = Vector2i(-9999, -9999)
		queue.append(s)
		if goal_set.has(s):
			return [s]
	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		for dir in DIRS:
			var n: Vector2i = c + dir
			if came_from.has(n) or not _is_walkable(matrix, n, blocked):
				continue
			came_from[n] = c
			if goal_set.has(n):
				return _reconstruct(came_from, n)
			queue.append(n)
	return []


static func _would_make_road_square(matrix: MapMatrix, cell: Vector2i) -> bool:
	return _would_make_road_square_with(matrix, cell, [])


static func _would_make_road_square_with(
	matrix: MapMatrix, cell: Vector2i, pending: Array[Vector2i]
) -> bool:
	var pending_set: Dictionary = {}
	for p in pending:
		pending_set[p] = true
	for dy in [-1, 0]:
		for dx in [-1, 0]:
			var ox: int = cell.x + dx
			var oy: int = cell.y + dy
			if ox < 0 or oy < 0 or ox + 1 >= matrix.width or oy + 1 >= matrix.height:
				continue
			var count := 0
			for yy in 2:
				for xx in 2:
					var c := Vector2i(ox + xx, oy + yy)
					if c == cell or matrix.has_road(c) or pending_set.has(c):
						count += 1
			if count >= 4:
				return true
	return false


## Remove non-bridge cells from any remaining 2×2 road blocks.
static func _strip_road_squares(matrix: MapMatrix) -> void:
	var guard := 0
	while guard < 64:
		guard += 1
		var victim := Vector2i(-1, -1)
		for y in matrix.height - 1:
			for x in matrix.width - 1:
				var cells: Array[Vector2i] = [
					Vector2i(x, y),
					Vector2i(x + 1, y),
					Vector2i(x, y + 1),
					Vector2i(x + 1, y + 1),
				]
				var all_road := true
				for c in cells:
					if not matrix.has_road(c):
						all_road = false
						break
				if not all_road:
					continue
				for c in cells:
					if _is_road_bridge(matrix, c):
						continue
					victim = c
					break
				if victim.x == -1:
					victim = cells[0]
				break
			if victim.x != -1:
				break
		if victim.x == -1:
			return
		matrix.set_road(victim, false)


static func _is_road_bridge(matrix: MapMatrix, cell: Vector2i) -> bool:
	if not matrix.has_road(cell):
		return false
	var neighbors: Array[Vector2i] = []
	for dir in DIRS:
		var n: Vector2i = cell + dir
		if matrix.has_road(n):
			neighbors.append(n)
	if neighbors.size() <= 1:
		return false
	## Temporarily remove and see if neighbors stay connected.
	matrix.set_road(cell, false)
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [neighbors[0]]
	seen[neighbors[0]] = true
	var q_i := 0
	while q_i < queue.size():
		var c: Vector2i = queue[q_i]
		q_i += 1
		for dir in DIRS:
			var n: Vector2i = c + dir
			if seen.has(n) or not matrix.has_road(n):
				continue
			seen[n] = true
			queue.append(n)
	var connected := true
	for n in neighbors:
		if not seen.has(n):
			connected = false
			break
	matrix.set_road(cell, true)
	return not connected


static func _reconstruct(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur := end
	while true:
		path.append(cur)
		var prev: Vector2i = came_from[cur]
		if prev.x == -9999:
			break
		cur = prev
	path.reverse()
	return path
