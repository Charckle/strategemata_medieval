@tool
extends EditorPlugin

const DockScript := preload("res://addons/map_painter/map_painter_dock.gd")
const MapPainterOps := preload("res://addons/map_painter/map_painter_ops.gd")

var _dock: Control
var _painting := false
var _last_cell := Vector2i(999999, 999999)
var _hover_cell := Vector2i(999999, 999999)


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "MapPainter"
	_dock.custom_minimum_size = Vector2(280, 0)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_dock.setup(self)
	_dock.brush_changed.connect(_on_brush_changed)
	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _dock:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null


func _on_scene_changed(_scene_root: Node) -> void:
	if _dock:
		_dock.refresh_provinces()
	update_overlays()


func _on_brush_changed() -> void:
	# Re-evaluate _handles so canvas forwarding starts/stops with the brush.
	var map_root := get_map_root()
	var sel := EditorInterface.get_selection()
	var previous: Array[Node] = []
	for n in sel.get_selected_nodes():
		previous.append(n)
	sel.clear()
	if map_root != null and _dock.brush != _dock.Brush.OFF:
		if previous.is_empty():
			sel.add_node(map_root)
		else:
			for n in previous:
				if is_instance_valid(n):
					sel.add_node(n)
	elif not previous.is_empty():
		for n in previous:
			if is_instance_valid(n):
				sel.add_node(n)
	update_overlays()


func get_map_root() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if MapPainterOps.is_map_root(root):
		return root
	return null


func _handles(_object: Object) -> bool:
	# Keep canvas forwarding active whenever a map is open and a brush is selected.
	if _dock == null or _dock.brush == _dock.Brush.OFF:
		return false
	return get_map_root() != null


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _dock == null or _dock.brush == _dock.Brush.OFF:
		return false
	var map_root := get_map_root()
	if map_root == null:
		return false

	if event is InputEventMouseMotion:
		var cell := _cell_at_mouse(map_root, event)
		if cell != _hover_cell:
			_hover_cell = cell
			update_overlays()
		if _painting and cell != _last_cell:
			_last_cell = cell
			_paint_at(map_root, cell, _erase_modifier(event))
		return _painting

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_painting = true
				_last_cell = Vector2i(999999, 999999)
				var cell := _cell_at_mouse(map_root, mb)
				_last_cell = cell
				var erase := mb.button_index == MOUSE_BUTTON_RIGHT or _erase_modifier(mb)
				_paint_at(map_root, cell, erase)
				return true
			else:
				_painting = false
				return true
	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _dock == null or _dock.brush == _dock.Brush.OFF:
		return
	var map_root := get_map_root()
	if map_root == null:
		return
	var ground := MapPainterOps.get_ground_layer(map_root)
	if ground == null:
		return
	if _hover_cell == Vector2i(999999, 999999):
		return
	var screen: Vector2 = _editor_layer_xform(ground) * ground.map_to_local(_hover_cell)
	var color := Color(0.2, 0.9, 0.4, 0.85)
	if _dock.brush == _dock.Brush.TERRAIN_ERASE or _dock.brush == _dock.Brush.ROAD_ERASE \
			or _dock.brush == _dock.Brush.ERASE_OBJECT:
		color = Color(0.95, 0.3, 0.25, 0.85)
	elif _is_object_brush(_dock.brush):
		color = Color(0.3, 0.65, 1.0, 0.9)
	overlay.draw_circle(screen, 6.0, color)
	var label := "%s  (%d, %d)" % [_brush_label(), _hover_cell.x, _hover_cell.y]
	overlay.draw_string(ThemeDB.fallback_font, screen + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

	var prov: Node = _dock.get_active_province(map_root)
	if prov and _is_object_brush(_dock.brush):
		overlay.draw_string(
			ThemeDB.fallback_font,
			screen + Vector2(10, 8),
			"→ %s" % str(prov.get("p_name")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			Color(1, 1, 1, 0.8)
		)


func _erase_modifier(event: InputEvent) -> bool:
	return event is InputEventWithModifiers and (event as InputEventWithModifiers).shift_pressed


## Exact equivalent of Godot's TileMapLayer editor:
##   xform = CanvasItemEditor.get_canvas_transform() * layer.get_global_transform_with_canvas()
## get_global_transform_with_canvas() = viewport.canvas_transform * global_transform
## (canvas_transform may include an active Camera2D). CIE pan/zoom is applied
## separately via get_canvas_transform() / scene_root global_canvas_transform.
func _editor_layer_xform(layer: CanvasItem) -> Transform2D:
	var editor_vp := EditorInterface.get_editor_viewport_2d()
	var view := _canvas_item_editor_view_xform(editor_vp)
	# Build with_canvas against the *editor* 2D viewport (layer.get_viewport() can
	# disagree in plugin context and skip the editor camera/canvas).
	var node_global := Transform2D.IDENTITY
	if layer is Node2D:
		node_global = (layer as Node2D).get_global_transform()
	var with_canvas := editor_vp.get_canvas_transform() * node_global
	return view * with_canvas


func _canvas_item_editor_view_xform(editor_vp: Viewport) -> Transform2D:
	# CanvasItemEditor::_draw_viewport() does:
	#   scene_root->set_global_canvas_transform(zoom/pan transform)
	# That is the view transform TileMapLayerEditor multiplies in C++.
	return editor_vp.get_global_canvas_transform()


func _mouse_screen_pos(event: InputEvent = null) -> Vector2:
	# _forward_canvas_gui_input positions match CIE viewport_control local space.
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	return EditorInterface.get_editor_viewport_2d().get_mouse_position()


func _mouse_local_on_layer(layer: CanvasItem, event: InputEvent = null) -> Vector2:
	return _editor_layer_xform(layer).affine_inverse() * _mouse_screen_pos(event)


func _cell_at_mouse(map_root: Node, event: InputEvent = null) -> Vector2i:
	var ground := MapPainterOps.get_ground_layer(map_root)
	if ground == null:
		MapPainterOps.ensure_tile_layers(map_root)
		ground = MapPainterOps.get_ground_layer(map_root)
	if ground == null:
		return Vector2i.ZERO
	return ground.local_to_map(_mouse_local_on_layer(ground, event))


func _paint_at(map_root: Node, cell: Vector2i, erase: bool) -> void:
	MapPainterOps.ensure_tile_layers(map_root)
	var ground := MapPainterOps.get_ground_layer(map_root)
	var roads := MapPainterOps.get_roads_layer(map_root)
	var brush: int = _dock.brush

	match brush:
		_dock.Brush.TERRAIN, _dock.Brush.TERRAIN_ERASE:
			if ground == null:
				return
			if erase or brush == _dock.Brush.TERRAIN_ERASE:
				MapPainterOps.erase_terrain(ground, cell)
			else:
				MapPainterOps.paint_terrain(ground, cell, _dock.terrain_atlas)
			EditorInterface.mark_scene_as_unsaved()
		_dock.Brush.ROAD, _dock.Brush.ROAD_ERASE:
			if roads == null:
				return
			if erase or brush == _dock.Brush.ROAD_ERASE:
				MapPainterOps.erase_road(roads, cell)
			else:
				MapPainterOps.paint_road(roads, cell)
			EditorInterface.mark_scene_as_unsaved()
		_dock.Brush.ERASE_OBJECT:
			var removed := MapPainterOps.erase_object_at_cell(map_root, ground, cell)
			if removed != "":
				_dock.set_status("Removed %s" % removed)
				EditorInterface.mark_scene_as_unsaved()
		_dock.Brush.SELECT_PROVINCE:
			_pick_province(map_root, ground, cell)
		_:
			if erase:
				var removed2 := MapPainterOps.erase_object_at_cell(map_root, ground, cell)
				if removed2 != "":
					_dock.set_status("Removed %s" % removed2)
					EditorInterface.mark_scene_as_unsaved()
				return
			_place_object(map_root, ground, cell, brush)
	update_overlays()


func _pick_province(map_root: Node, ground: TileMapLayer, cell: Vector2i) -> void:
	# Find nearest building and select its province.
	var center := MapPainterOps.cell_center_global(ground, cell)
	var best_prov: Node = null
	var best_d := INF
	for prov in MapPainterOps.list_provinces(map_root):
		for container_name in ["settlements", "fields", "economy", "defense"]:
			var container := prov.get_node_or_null(container_name)
			if container == null:
				continue
			for child in container.get_children():
				if child is Node2D:
					var d: float = (child as Node2D).global_position.distance_squared_to(center)
					if d < best_d:
						best_d = d
						best_prov = prov
	if best_prov:
		_dock.select_province_node(map_root, best_prov)
		_dock.set_status("Active province: %s" % str(best_prov.get("p_name")))


func _place_object(map_root: Node, ground: TileMapLayer, cell: Vector2i, brush: int) -> void:
	if not _is_object_brush(brush):
		return
	var prov: Node = _dock.get_active_province(map_root)
	if prov == null:
		_dock.set_status("Add/select a province first.")
		return
	if map_root.has_method("set_editable_instance"):
		map_root.set_editable_instance(prov, true)

	var owner_id: int = _dock.player_owner
	# Prefer province owner for buildings unless user changed spin after.
	if prov.get("player_owner") != null:
		owner_id = int(prov.get("player_owner"))

	var inst: Node = null
	match brush:
		_dock.Brush.FIELD:
			inst = MapPainterOps.place_packed(
				map_root, prov, "fields", MapPainterOps.FIELD_SCENE, "Field",
				ground, cell, false, {"crop": _dock.field_crop}
			)
		_dock.Brush.VILLAGE:
			inst = MapPainterOps.place_packed(
				map_root, prov, "settlements", MapPainterOps.VILLAGE_SCENE, "Village",
				ground, cell, false, {"player_owner": owner_id}
			)
		_dock.Brush.TOWN:
			inst = MapPainterOps.place_packed(
				map_root, prov, "settlements", MapPainterOps.TOWN_SCENE, "Town",
				ground, cell, true, {"player_owner": owner_id}
			)
		_dock.Brush.CASTLE:
			inst = MapPainterOps.place_packed(
				map_root, prov, "defense", MapPainterOps.CASTLE_SCENE, "Castle",
				ground, cell, true, {"player_owner": owner_id, "has_castle": false}
			)
		_dock.Brush.ECON_OPEN:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "EmptyPlot",
				ground, cell, false, {
					"slot_kind": 0, "deposit_type": 0, "stage": 0, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_STONE:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "StoneDeposit",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 1, "stage": 0, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_IRON:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "IronDeposit",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 2, "stage": 0, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_SILVER:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "SilverDeposit",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 3, "stage": 0, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_RANDOM:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "RandomDeposit",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 4, "stage": 0, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_WOODCUTTER:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "Woodcutter",
				ground, cell, false, {
					"slot_kind": 0, "deposit_type": 0, "subtype": 0, "stage": 1, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_STONEQUARRY:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "StoneQuarry",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 1, "subtype": 4, "stage": 1, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_IRONMINE:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "IronMine",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 2, "subtype": 1, "stage": 1, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_SILVERMINE:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "SilverMine",
				ground, cell, false, {
					"slot_kind": 1, "deposit_type": 3, "subtype": 3, "stage": 1, "player_owner": owner_id
				}
			)
		_dock.Brush.ECON_BLACKSMITH:
			inst = MapPainterOps.place_packed(
				map_root, prov, "economy", MapPainterOps.ECONOMY_SCENE, "Blacksmith",
				ground, cell, false, {
					"slot_kind": 0, "deposit_type": 0, "subtype": 5, "stage": 1, "player_owner": owner_id
				}
			)

	if inst:
		EditorInterface.mark_scene_as_unsaved()
		_dock.set_status("Placed %s in %s @ (%d,%d)" % [inst.name, str(prov.get("p_name")), cell.x, cell.y])
		_dock.refresh_provinces()


func _is_object_brush(brush: int) -> bool:
	return brush in [
		_dock.Brush.FIELD, _dock.Brush.VILLAGE, _dock.Brush.TOWN, _dock.Brush.CASTLE,
		_dock.Brush.ECON_OPEN, _dock.Brush.ECON_STONE, _dock.Brush.ECON_IRON, _dock.Brush.ECON_SILVER,
		_dock.Brush.ECON_RANDOM,
		_dock.Brush.ECON_WOODCUTTER, _dock.Brush.ECON_STONEQUARRY, _dock.Brush.ECON_IRONMINE,
		_dock.Brush.ECON_SILVERMINE, _dock.Brush.ECON_BLACKSMITH,
	]


func _brush_label() -> String:
	if _dock == null or _dock._brush_option == null:
		return ""
	var i: int = _dock._brush_option.selected
	if i < 0:
		return ""
	return _dock._brush_option.get_item_text(i)
