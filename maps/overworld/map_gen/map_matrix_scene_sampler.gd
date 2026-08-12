class_name MapMatrixSceneSampler
extends RefCounted

## Builds a MapMatrix preview from an authored map .tscn without adding it to the tree
## (no _ready / pathfinding / GUI). Results are cached per path for the session.

const Ops := preload("res://addons/map_painter/map_painter_ops.gd")

static var _cache: Dictionary = {} ## path -> MapMatrix


static func clear_cache() -> void:
	_cache.clear()


static func sample_cached(scene_path: String) -> MapMatrix:
	var path := scene_path.strip_edges()
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as MapMatrix
	var matrix := sample(path)
	if matrix != null:
		_cache[path] = matrix
	return matrix


static func sample(scene_path: String) -> MapMatrix:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("MapMatrixSceneSampler: failed to load %s" % scene_path)
		return null
	var map_root: Node = packed.instantiate()
	var matrix := _from_instance(map_root)
	map_root.free()
	return matrix


static func _from_instance(map_root: Node) -> MapMatrix:
	if not Ops.is_map_root(map_root):
		push_error("MapMatrixSceneSampler: not a map root")
		return null
	var ground := Ops.get_ground_layer(map_root)
	var roads := Ops.get_roads_layer(map_root)
	if ground == null:
		return null

	var used: Array[Vector2i] = ground.get_used_cells()
	if used.is_empty():
		return null
	var min_c := used[0]
	var max_c := used[0]
	for c in used:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var width := max_c.x - min_c.x + 1
	var height := max_c.y - min_c.y + 1

	var provinces := Ops.list_provinces(map_root)
	var matrix := MapMatrix.new(width, height, provinces.size())
	matrix.seed_used = 0

	## Terrain + land mask (exclude sea — stays gray INVALID in preview).
	var land: Dictionary = {}
	for c in used:
		var local := c - min_c
		var atlas := ground.get_cell_atlas_coords(c)
		matrix.set_terrain(local, _terrain_from_atlas(atlas))
		if atlas == Vector2i(0, 1):
			continue
		land[local] = true

	if roads != null:
		for c in roads.get_used_cells():
			var local := c - min_c
			if matrix.in_bounds(local):
				matrix.set_road(local, true)

	## Plots + province seeds from buildings.
	var seeds: Array = [] ## Array of {pid, cell}
	for pid in provinces.size():
		var prov: Node = provinces[pid]
		var seat := Vector2i(-1, -1)
		for container_name in ["settlements", "fields", "economy", "defense"]:
			var container := prov.get_node_or_null(container_name)
			if container == null:
				continue
			for child in container.get_children():
				if not (child is Node2D):
					continue
				var kind := _plot_kind_for(child)
				if kind < 0:
					continue
				var origin := _building_origin_cell(ground, child as Node2D, min_c)
				if not matrix.in_bounds(origin):
					continue
				var size := MapMatrix.plot_footprint_size(kind)
				matrix.plots.append({
					"kind": kind,
					"province_id": pid,
					"origin": origin,
					"size": size,
				})
				for foot in matrix.footprint_cells(origin, size):
					if matrix.in_bounds(foot):
						seeds.append({"pid": pid, "cell": foot})
				if kind == MapMatrix.PlotKind.TOWN or kind == MapMatrix.PlotKind.CASTLE:
					if seat.x < 0:
						seat = origin
		if seat.x < 0 and not seeds.is_empty():
			## Fallback: first seed of this province.
			for s in seeds:
				if int(s["pid"]) == pid:
					seat = s["cell"]
					break
		if pid < matrix.seats.size():
			matrix.seats[pid] = seat

	_assign_provinces_flood(matrix, seeds, land)
	return matrix


static func _terrain_from_atlas(atlas: Vector2i) -> int:
	match atlas:
		Vector2i(2, 6):
			return MapMatrix.Terrain.HILLS
		Vector2i(1, 6):
			return MapMatrix.Terrain.MOUNTAINS
		Vector2i(0, 6):
			return MapMatrix.Terrain.TREES
		_:
			return MapMatrix.Terrain.GRASS


static func _plot_kind_for(node: Node) -> int:
	var script_path := ""
	if node.get_script():
		script_path = str(node.get_script().resource_path)
	if script_path.ends_with("town.gd"):
		return MapMatrix.PlotKind.TOWN
	if script_path.ends_with("village.gd"):
		return MapMatrix.PlotKind.VILLAGE
	if script_path.ends_with("castle.gd"):
		return MapMatrix.PlotKind.CASTLE
	if script_path.ends_with("field.gd"):
		return MapMatrix.PlotKind.FIELD
	if script_path.ends_with("basic_building.gd"):
		var slot := int(node.get("slot_kind")) if node.get("slot_kind") != null else 0
		## Preview treats any deposit pad as DEPOSIT_RANDOM (same letter).
		if slot == 1:
			return MapMatrix.PlotKind.DEPOSIT_RANDOM
		return MapMatrix.PlotKind.ECONOMY_EMPTY
	return -1


static func _is_2x2_script(node: Node) -> bool:
	## Prefer script path — avoid pathfinding helpers that expect a live tree.
	if node.get_script():
		var script_path := str(node.get_script().resource_path)
		return script_path.ends_with("town.gd") or script_path.ends_with("castle.gd")
	return false


static func _building_origin_cell(
	ground: TileMapLayer, building: Node2D, min_c: Vector2i
) -> Vector2i:
	var is_2x2 := _is_2x2_script(building)
	var offset := Ops.CELL_OFFSET_2X2 if is_2x2 else Ops.CELL_OFFSET_1X1
	var center: Vector2 = building.global_position + offset
	var cell := Ops.world_to_cell(ground, center)
	return cell - min_c


static func _assign_provinces_flood(
	matrix: MapMatrix, seeds: Array, land: Dictionary
) -> void:
	if matrix.province_count <= 0:
		return
	## Clear non-land / reset, then multi-source BFS from building footprints.
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if land.has(c):
				matrix.set_cell(c, MapMatrix.INVALID)
			else:
				matrix.set_cell(c, MapMatrix.INVALID)

	var queue: Array[Vector2i] = []
	var seen: Dictionary = {}
	for s in seeds:
		var cell: Vector2i = s["cell"]
		var pid: int = int(s["pid"])
		if not matrix.in_bounds(cell) or not land.has(cell):
			continue
		if seen.has(cell):
			continue
		seen[cell] = true
		matrix.set_cell(cell, pid)
		queue.append(cell)

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
			if seen.has(n) or not land.has(n):
				continue
			seen[n] = true
			matrix.set_cell(n, owner)
			queue.append(n)

	## Any leftover land (no buildings reached) → nearest province by seat, else 0.
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if not land.has(c):
				continue
			if matrix.get_cell(c) != MapMatrix.INVALID:
				continue
			var best := 0
			var best_d := 0x7fffffff
			for pid in matrix.province_count:
				var seat: Vector2i = matrix.seats[pid]
				if seat.x < 0:
					continue
				var d := c - seat
				var dist := d.x * d.x + d.y * d.y
				if dist < best_d:
					best_d = dist
					best = pid
			matrix.set_cell(c, best)
