@tool
extends RefCounted

const BASE_MAP_SCENE := "res://maps/overworld/o_base_map/o_base_map.tscn"
const BLANK_MAP_SCENE := "res://maps/overworld/map_templates/blank_map.tscn"
const SUMMER_SET := "res://sprites/overworld/map_tiles/summer/summer_set.tres"
const ROAD_SET := "res://sprites/overworld/map_tiles/summer/road/road_set.tres"
const PROVINCE_SCENE := "res://objects/overworld/province/province.tscn"
const TOWN_SCENE := "res://objects/overworld/town/town.tscn"
const VILLAGE_SCENE := "res://objects/overworld/village/village.tscn"
const FIELD_SCENE := "res://objects/overworld/field/field.tscn"
const ECONOMY_SCENE := "res://objects/overworld/economy/basic_building/basic_building.tscn"
const CASTLE_SCENE := "res://objects/overworld/castle/castle.tscn"

const CELL_OFFSET_1X1 := Vector2(32, 16)
const CELL_OFFSET_2X2 := Vector2(64, 16)

## Atlas tiles available in summer_set.tres
const TERRAIN_TILES := [
	{"label": "Walkable ground", "atlas": Vector2i(0, 0), "walkable": true},
	{"label": "Water / shore A", "atlas": Vector2i(0, 1), "walkable": false},
	{"label": "Terrain 0:4", "atlas": Vector2i(0, 4), "walkable": false},
	{"label": "Terrain 0:5", "atlas": Vector2i(0, 5), "walkable": false},
	{"label": "Terrain 1:4", "atlas": Vector2i(1, 4), "walkable": false},
	{"label": "Terrain 1:5", "atlas": Vector2i(1, 5), "walkable": false},
	{"label": "Terrain 2:5", "atlas": Vector2i(2, 5), "walkable": false},
	{"label": "Terrain 3:5", "atlas": Vector2i(3, 5), "walkable": false},
]


static func is_map_root(node: Node) -> bool:
	if node == null:
		return false
	return node.get_node_or_null("tilemap") != null and node.get_node_or_null("provinces") != null


static func find_map_root(from: Node) -> Node:
	var n := from
	while n != null:
		if is_map_root(n):
			return n
		n = n.get_parent()
	return null


static func get_ground_layer(map_root: Node) -> TileMapLayer:
	if map_root == null:
		return null
	var layer := map_root.get_node_or_null("tilemap/ground_01")
	if layer is TileMapLayer:
		return layer as TileMapLayer
	var tilemap := map_root.get_node_or_null("tilemap")
	if tilemap == null:
		return null
	for child in tilemap.get_children():
		if child is TileMapLayer and child.name != "roads" and (child as TileMapLayer).tile_set != null:
			return child as TileMapLayer
	return null


static func get_roads_layer(map_root: Node) -> TileMapLayer:
	if map_root == null:
		return null
	var layer := map_root.get_node_or_null("tilemap/roads")
	if layer is TileMapLayer:
		return layer as TileMapLayer
	return null


static func ensure_tile_layers(map_root: Node) -> void:
	var tilemap := map_root.get_node_or_null("tilemap")
	if tilemap == null:
		return
	if tilemap.get_node_or_null("base_layer") == null:
		var base := TileMapLayer.new()
		base.name = "base_layer"
		tilemap.add_child(base)
		base.owner = map_root
		tilemap.move_child(base, 0)
	var ground := tilemap.get_node_or_null("ground_01")
	if ground == null:
		ground = TileMapLayer.new()
		ground.name = "ground_01"
		tilemap.add_child(ground)
		ground.owner = map_root
	if ground is TileMapLayer and (ground as TileMapLayer).tile_set == null:
		(ground as TileMapLayer).tile_set = load(SUMMER_SET)
	var roads := tilemap.get_node_or_null("roads")
	if roads == null:
		roads = TileMapLayer.new()
		roads.name = "roads"
		tilemap.add_child(roads)
		roads.owner = map_root
	if roads is TileMapLayer and (roads as TileMapLayer).tile_set == null:
		(roads as TileMapLayer).tile_set = load(ROAD_SET)


static func world_to_cell(layer: TileMapLayer, world: Vector2) -> Vector2i:
	return layer.local_to_map(layer.to_local(world))


static func cell_center_global(layer: TileMapLayer, cell: Vector2i) -> Vector2:
	return layer.to_global(layer.map_to_local(cell))


static func object_position_for_cell(layer: TileMapLayer, cell: Vector2i, parent: Node2D, footprint_2x2: bool) -> Vector2:
	var offset := CELL_OFFSET_2X2 if footprint_2x2 else CELL_OFFSET_1X1
	var desired_global := cell_center_global(layer, cell) - offset
	return parent.to_local(desired_global)


static func unique_child_name(parent: Node, base: String) -> String:
	if not parent.has_node(NodePath(base)):
		return base
	var i := 2
	while parent.has_node(NodePath("%s%d" % [base, i])) or parent.has_node(NodePath("%s_%d" % [base, i])):
		i += 1
	return "%s%d" % [base, i]


static func set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		# Keep packed-scene internals owned by their instance root when nested.
		if child.owner == null or child.owner == node or child.owner == owner:
			set_owner_recursive(child, owner)


static func list_provinces(map_root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var provinces := map_root.get_node_or_null("provinces")
	if provinces == null:
		return out
	for child in provinces.get_children():
		out.append(child)
	return out


static func create_province(map_root: Node, p_name: String, player_owner: int) -> Node:
	var provinces := map_root.get_node("provinces")
	var scene: PackedScene = load(PROVINCE_SCENE)
	var prov: Node = scene.instantiate()
	prov.name = unique_child_name(provinces, "Province")
	prov.set("p_name", p_name)
	prov.set("player_owner", player_owner)
	provinces.add_child(prov)
	prov.owner = map_root
	if map_root.has_method("set_editable_instance"):
		map_root.set_editable_instance(prov, true)
	return prov


static func place_packed(
	map_root: Node,
	province: Node,
	container_name: String,
	scene_path: String,
	node_base_name: String,
	layer: TileMapLayer,
	cell: Vector2i,
	footprint_2x2: bool,
	props: Dictionary = {}
) -> Node:
	var container: Node2D = province.get_node(container_name) as Node2D
	var scene: PackedScene = load(scene_path)
	var inst: Node2D = scene.instantiate() as Node2D
	inst.name = unique_child_name(container, node_base_name)
	for key in props:
		inst.set(key, props[key])
	container.add_child(inst)
	inst.owner = map_root
	# Province must be editable so containers can hold new instances, but keep the
	# building PackedScene closed (no Area2D/sprites cluttering the scene tree).
	if map_root.has_method("set_editable_instance"):
		map_root.set_editable_instance(province, true)
		map_root.set_editable_instance(inst, false)
	inst.position = object_position_for_cell(layer, cell, container, footprint_2x2)
	return inst


## Returns the removed node name, or "" if nothing was erased.
static func erase_object_at_cell(map_root: Node, layer: TileMapLayer, cell: Vector2i) -> String:
	var best: Node = null
	var best_dist := INF
	var center := cell_center_global(layer, cell)
	for prov in list_provinces(map_root):
		for container_name in ["settlements", "fields", "economy", "defense"]:
			var container := prov.get_node_or_null(container_name)
			if container == null:
				continue
			for child in container.get_children():
				if not (child is Node2D):
					continue
				var is_2x2 := is_2x2_building(child)
				if is_2x2:
					for extra in [
						Vector2(32, 32), Vector2(64, 16), Vector2(64, 48), Vector2(96, 32)
					]:
						var c2: Vector2 = (child as Node2D).global_position + extra
						var d2 := c2.distance_squared_to(center)
						if d2 < best_dist and d2 < 24.0 * 24.0:
							best_dist = d2
							best = child
				else:
					var child_center: Vector2 = (child as Node2D).global_position + CELL_OFFSET_1X1
					var d := child_center.distance_squared_to(center)
					if d < best_dist and d < 24.0 * 24.0:
						best_dist = d
						best = child
	if best == null:
		return ""
	var removed_name := String(best.name)
	best.get_parent().remove_child(best)
	best.free()
	return removed_name


static func is_2x2_building(node: Node) -> bool:
	if node.has_method("get_pathfinding_blocked_tile_centers"):
		var centers: Array = node.get_pathfinding_blocked_tile_centers()
		return centers.size() >= 4
	var script_path := ""
	if node.get_script():
		script_path = str(node.get_script().resource_path)
	return script_path.ends_with("town.gd") or script_path.ends_with("castle.gd")


static func paint_terrain(layer: TileMapLayer, cell: Vector2i, atlas: Vector2i) -> void:
	layer.set_cell(cell, 0, atlas)


static func erase_terrain(layer: TileMapLayer, cell: Vector2i) -> void:
	layer.erase_cell(cell)


static func paint_road(layer: TileMapLayer, cell: Vector2i) -> void:
	if layer.tile_set == null:
		layer.tile_set = load(ROAD_SET)
	layer.set_cells_terrain_connect([cell], 0, 0, true)


static func erase_road(layer: TileMapLayer, cell: Vector2i) -> void:
	layer.erase_cell(cell)
	# Refresh neighbors so auto-tile reconnects.
	var neighbors: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if layer.get_cell_source_id(n) != -1:
			neighbors.append(n)
	if not neighbors.is_empty():
		layer.set_cells_terrain_connect(neighbors, 0, 0, true)


static func sync_province_ownership(province: Node) -> void:
	var owner_id = province.get("player_owner")
	if owner_id == null:
		return
	for container_name in ["settlements", "economy", "defense"]:
		var container := province.get_node_or_null(container_name)
		if container == null:
			continue
		for child in container.get_children():
			if child.get("player_owner") != null:
				child.set("player_owner", owner_id)


static func validate_map(map_root: Node) -> PackedStringArray:
	var issues: PackedStringArray = []
	var ground := get_ground_layer(map_root)
	if ground == null or ground.tile_set == null:
		issues.append("Missing ground_01 TileMapLayer with a TileSet.")
	var roads := get_roads_layer(map_root)
	if roads == null:
		issues.append("Missing roads TileMapLayer (optional but recommended).")
	var seen_cells: Dictionary = {}
	var provinces := list_provinces(map_root)
	if provinces.is_empty():
		issues.append("No provinces placed.")
	for prov in provinces:
		var pname := str(prov.get("p_name"))
		var settlements := prov.get_node_or_null("settlements")
		var defense := prov.get_node_or_null("defense")
		var has_town := false
		var has_castle := false
		if settlements:
			for s in settlements.get_children():
				var sp := s.get_script()
				if sp and str(sp.resource_path).ends_with("town.gd"):
					has_town = true
		if defense:
			for d in defense.get_children():
				var dsp := d.get_script()
				if dsp and str(dsp.resource_path).ends_with("castle.gd"):
					has_castle = true
		if not has_town and not has_castle:
			issues.append("Province '%s' has no town or castle seat." % pname)
		var fields := prov.get_node_or_null("fields")
		if fields and fields.get_child_count() > 0:
			if settlements == null or settlements.get_child_count() == 0:
				issues.append("Province '%s' has fields but no settlements." % pname)
		for container_name in ["settlements", "fields", "economy", "defense"]:
			var container := prov.get_node_or_null(container_name)
			if container == null or ground == null:
				continue
			for child in container.get_children():
				if not (child is Node2D):
					continue
				var is_2x2 := is_2x2_building(child)
				var offset := CELL_OFFSET_2X2 if is_2x2 else CELL_OFFSET_1X1
				var center: Vector2 = (child as Node2D).global_position + offset
				var cell := world_to_cell(ground, center)
				var key := "%d,%d" % [cell.x, cell.y]
				if seen_cells.has(key):
					issues.append("Overlap at cell %s: %s and %s" % [key, seen_cells[key], child.name])
				else:
					seen_cells[key] = "%s/%s" % [pname, child.name]
	return issues


static func create_new_map_scene(folder: String, map_name: String) -> String:
	var safe := map_name.strip_edges().to_snake_case()
	if safe.is_empty():
		safe = "new_map"
	var dir_path := folder.path_join(safe)
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var dest := dir_path.path_join(safe + ".tscn")
	var abs_src := ProjectSettings.globalize_path(BLANK_MAP_SCENE)
	var abs_dest := ProjectSettings.globalize_path(dest)
	var err := _copy_file(abs_src, abs_dest)
	if err != OK:
		var packed: PackedScene = load(BLANK_MAP_SCENE)
		var inst: Node = packed.instantiate()
		inst.name = safe
		var save_packed := PackedScene.new()
		_set_owner_for_pack(inst, inst)
		err = save_packed.pack(inst)
		if err == OK:
			err = ResourceSaver.save(save_packed, dest)
		inst.queue_free()
		if err != OK:
			push_error("MapPainter: failed to create map at %s (error %s)" % [dest, err])
			return ""
	return dest


static func _copy_file(abs_from: String, abs_to: String) -> Error:
	var bytes := FileAccess.get_file_as_bytes(abs_from)
	if bytes.is_empty() and not FileAccess.file_exists(abs_from):
		return ERR_FILE_NOT_FOUND
	var out := FileAccess.open(abs_to, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	out.store_buffer(bytes)
	return OK


static func _set_owner_for_pack(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for child in node.get_children():
		_set_owner_for_pack(child, owner)
