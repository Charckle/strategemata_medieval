class_name MapMatrixBaker
extends RefCounted

## Turns a validated MapMatrix into a playable OBaseMap instance (in memory).

const Ops := preload("res://addons/map_painter/map_painter_ops.gd")
const ProvinceNames := preload("res://global_scripts/province_names.gd")
const LAND_ATLAS := Vector2i(0, 0)
const TREES_ATLAS := Vector2i(0, 6)
const MOUNTAINS_ATLAS := Vector2i(1, 6)
const HILLS_ATLAS := Vector2i(2, 6)
const UNOWNED := -1


static func bake(matrix: MapMatrix) -> Node:
	if matrix == null or matrix.width <= 0 or matrix.height <= 0:
		return null
	var packed: PackedScene = load(Ops.BLANK_MAP_SCENE)
	if packed == null:
		push_error("MapMatrixBaker: failed to load blank_map.tscn")
		return null
	var map_root: Node = packed.instantiate()
	Ops.ensure_tile_layers(map_root)
	var ground := Ops.get_ground_layer(map_root)
	var roads := Ops.get_roads_layer(map_root)
	if ground == null:
		push_error("MapMatrixBaker: missing ground layer")
		map_root.free()
		return null

	_paint_land(ground, matrix)
	if roads != null:
		_paint_roads(roads, matrix)

	var names := ProvinceNames.pick_names(matrix.province_count, matrix.seed_used)
	var provinces: Array[Node] = []
	provinces.resize(matrix.province_count)
	for pid in matrix.province_count:
		var pname := str(names[pid]) if pid < names.size() else "Province %d" % (pid + 1)
		var prov := Ops.create_province(map_root, pname, UNOWNED)
		provinces[pid] = prov

	for plot in matrix.plots:
		var pid := int(plot.get("province_id", -1))
		if pid < 0 or pid >= provinces.size():
			continue
		var origin: Vector2i = plot.get("origin", Vector2i.ZERO)
		_place_plot(map_root, provinces[pid], ground, int(plot.get("kind", -1)), origin)

	if map_root.get("world_seed") != null:
		map_root.set("world_seed", matrix.seed_used)

	var bake_issues := Ops.validate_map(map_root)
	if not bake_issues.is_empty():
		push_warning("MapMatrixBaker: validate_map issues: %s" % ", ".join(bake_issues))

	return map_root


static func _paint_land(ground: TileMapLayer, matrix: MapMatrix) -> void:
	for y in matrix.height:
		for x in matrix.width:
			var cell := Vector2i(x, y)
			Ops.paint_terrain(ground, cell, _atlas_for_terrain(matrix.get_terrain(cell)))


static func _atlas_for_terrain(kind: int) -> Vector2i:
	match kind:
		MapMatrix.Terrain.HILLS:
			return HILLS_ATLAS
		MapMatrix.Terrain.MOUNTAINS:
			return MOUNTAINS_ATLAS
		MapMatrix.Terrain.TREES:
			return TREES_ATLAS
		_:
			return LAND_ATLAS


static func _paint_roads(roads: TileMapLayer, matrix: MapMatrix) -> void:
	var cells: Array[Vector2i] = []
	for y in matrix.height:
		for x in matrix.width:
			var c := Vector2i(x, y)
			if matrix.has_road(c):
				cells.append(c)
	if cells.is_empty():
		return
	if roads.tile_set == null:
		roads.tile_set = load(Ops.ROAD_SET)
	roads.set_cells_terrain_connect(cells, 0, 0, true)


static func _place_plot(
	map_root: Node, province: Node, ground: TileMapLayer, kind: int, cell: Vector2i
) -> void:
	match kind:
		MapMatrix.PlotKind.TOWN:
			Ops.place_packed(
				map_root, province, "settlements", Ops.TOWN_SCENE, "Town",
				ground, cell, true, {"player_owner": UNOWNED}
			)
		MapMatrix.PlotKind.VILLAGE:
			Ops.place_packed(
				map_root, province, "settlements", Ops.VILLAGE_SCENE, "Village",
				ground, cell, false, {"player_owner": UNOWNED}
			)
		MapMatrix.PlotKind.CASTLE:
			Ops.place_packed(
				map_root, province, "defense", Ops.CASTLE_SCENE, "Castle",
				ground, cell, true, {"player_owner": UNOWNED, "has_castle": false}
			)
		MapMatrix.PlotKind.FIELD:
			Ops.place_packed(
				map_root, province, "fields", Ops.FIELD_SCENE, "Field",
				ground, cell, false, {}
			)
		MapMatrix.PlotKind.ECONOMY_EMPTY:
			Ops.place_packed(
				map_root, province, "economy", Ops.ECONOMY_SCENE, "EmptyPlot",
				ground, cell, false, {
					"slot_kind": 0, "deposit_type": 0, "stage": 0, "player_owner": UNOWNED
				}
			)
		MapMatrix.PlotKind.DEPOSIT_RANDOM:
			Ops.place_packed(
				map_root, province, "economy", Ops.ECONOMY_SCENE, "RandomDeposit",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 4, "stage": 0, "player_owner": UNOWNED
				}
			)
		_:
			push_warning("MapMatrixBaker: unknown plot kind %d" % kind)
