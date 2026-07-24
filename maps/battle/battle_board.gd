class_name BattleBoard
extends Node2D

## Square battle board: TileMapLayer terrain + click/debug + walkability helpers.
const BOARD_WIDTH := 40
const BOARD_HEIGHT := 60
const TILE_SIZE := 32

## Atlas coords in battle_terrain_set.tres
const TERRAIN_GRASS := Vector2i(0, 0)
const TERRAIN_WATER := Vector2i(1, 0)
const TERRAIN_FOREST := Vector2i(2, 0)
const TERRAIN_ROCK := Vector2i(3, 0)
const TERRAIN_HILL := Vector2i(4, 0)

@onready var terrain_layer: TileMapLayer = $Terrain
@onready var highlight: Polygon2D = $Highlight
@onready var camera: Camera2D = $Camera2D
@onready var info_label: Label = $UI/InfoLabel

var selected_cell := Vector2i(-1, -1)


func _ready() -> void:
	_setup_highlight()
	_setup_camera()
	_update_info_label(Vector2i(-1, -1), "")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := world_to_cell(get_global_mouse_position())
		if not is_in_bounds(cell):
			return
		select_cell(cell)
		get_viewport().set_input_as_handled()


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return terrain_layer.local_to_map(terrain_layer.to_local(world_pos))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	return terrain_layer.to_global(terrain_layer.map_to_local(cell))


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BOARD_WIDTH and cell.y < BOARD_HEIGHT


func is_walkable(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	var data := terrain_layer.get_cell_tile_data(cell)
	if data == null:
		return false
	return bool(data.get_custom_data("walkable"))


func get_terrain_name(cell: Vector2i) -> String:
	var data := terrain_layer.get_cell_tile_data(cell)
	if data == null:
		return ""
	var value = data.get_custom_data("terrain")
	return String(value)


func select_cell(cell: Vector2i) -> void:
	selected_cell = cell
	highlight.position = cell_to_world_center(cell)
	highlight.visible = true
	var terrain_name := get_terrain_name(cell)
	var walk := "walkable" if is_walkable(cell) else "blocked"
	_update_info_label(cell, "%s (%s)" % [terrain_name, walk])
	print("BattleBoard cell %s — %s (%s)" % [cell, terrain_name, walk])


func get_board_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(BOARD_WIDTH * TILE_SIZE, BOARD_HEIGHT * TILE_SIZE))


func fill_rect(rect: Rect2i, atlas_coords: Vector2i, source_id: int = 0) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if is_in_bounds(cell):
				terrain_layer.set_cell(cell, source_id, atlas_coords)


func fill_all(atlas_coords: Vector2i = TERRAIN_GRASS) -> void:
	fill_rect(Rect2i(0, 0, BOARD_WIDTH, BOARD_HEIGHT), atlas_coords)


func paint_sample_layout() -> void:
	## Procedural sandbox layout for the test scene (safe to re-run).
	fill_all(TERRAIN_GRASS)

	# Lake (left-center)
	fill_rect(Rect2i(4, 18, 8, 10), TERRAIN_WATER)
	fill_rect(Rect2i(5, 17, 5, 1), TERRAIN_WATER)
	fill_rect(Rect2i(5, 28, 6, 1), TERRAIN_WATER)

	# River strip
	for y in range(8, 52):
		terrain_layer.set_cell(Vector2i(22, y), 0, TERRAIN_WATER)
		if y % 3 != 0:
			terrain_layer.set_cell(Vector2i(23, y), 0, TERRAIN_WATER)

	# Forests
	fill_rect(Rect2i(28, 8, 7, 6), TERRAIN_FOREST)
	fill_rect(Rect2i(30, 14, 5, 4), TERRAIN_FOREST)
	fill_rect(Rect2i(8, 40, 6, 5), TERRAIN_FOREST)

	# Rocky ridge
	fill_rect(Rect2i(14, 10, 4, 3), TERRAIN_ROCK)
	fill_rect(Rect2i(15, 13, 3, 2), TERRAIN_ROCK)
	terrain_layer.set_cell(Vector2i(16, 15), 0, TERRAIN_ROCK)

	# Hills
	fill_rect(Rect2i(32, 35, 5, 4), TERRAIN_HILL)
	fill_rect(Rect2i(3, 6, 4, 3), TERRAIN_HILL)
	fill_rect(Rect2i(18, 45, 6, 3), TERRAIN_HILL)


func _setup_highlight() -> void:
	var half := TILE_SIZE * 0.5
	highlight.polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	highlight.color = Color(1, 1, 0, 0.35)
	highlight.visible = false
	highlight.z_index = 10


func _setup_camera() -> void:
	var rect := get_board_rect()
	if camera.has_method("set_board_rect"):
		camera.call("set_board_rect", rect)
	camera.position = rect.get_center()
	camera.zoom = Vector2(0.55, 0.55)


func _update_info_label(cell: Vector2i, detail: String) -> void:
	if info_label == null:
		return
	if cell.x < 0:
		info_label.text = "LMB: select tile | RMB drag: pan | Wheel: zoom | Arrows: pan"
	else:
		info_label.text = "Cell %s — %s" % [cell, detail]
