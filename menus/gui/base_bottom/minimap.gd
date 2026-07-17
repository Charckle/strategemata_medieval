extends Control

## Static minimap: baked terrain + province borders. Click jumps the camera.
## Call rebuild(base_map) when the Map menu opens.

const BAKE_WIDTH := 640
const BORDER_WIDTH := 1.5
const BG_COLOR := Color(0.12, 0.14, 0.11, 1.0)

var _base_map: Node = null
var _terrain_tex: ImageTexture = null
var _world_rect := Rect2()
var _border_segments: Array = []
var _atlas_cache: Dictionary = {}  # Texture2D -> Image


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(400, 280)
	resized.connect(queue_redraw)


func rebuild(base_map: Node) -> void:
	_base_map = base_map
	_atlas_cache.clear()
	_border_segments.clear()
	_terrain_tex = null
	_world_rect = Rect2()

	if base_map == null:
		queue_redraw()
		return

	var tilemap: Node = base_map.get_node_or_null("tilemap")
	if tilemap == null:
		queue_redraw()
		return

	_world_rect = _compute_world_rect(tilemap)
	if _world_rect.size.x <= 0.0 or _world_rect.size.y <= 0.0:
		queue_redraw()
		return

	var aspect := _world_rect.size.y / _world_rect.size.x
	var bake_h := maxi(1, int(round(BAKE_WIDTH * aspect)))
	var img := Image.create(BAKE_WIDTH, bake_h, false, Image.FORMAT_RGBA8)
	img.fill(BG_COLOR)

	for child in tilemap.get_children():
		if child is TileMapLayer and (child as TileMapLayer).tile_set != null:
			_blit_layer(img, child as TileMapLayer)

	_terrain_tex = ImageTexture.create_from_image(img)

	var borders = base_map.get_node_or_null("ProvinceBorders")
	if borders != null and borders.has_method("get_minimap_border_segments"):
		for s in borders.get_minimap_border_segments():
			_border_segments.append({
				"a": borders.to_global(s["a"]),
				"b": borders.to_global(s["b"]),
				"color": s.get("color", Color.WHITE),
				"dashed": s.get("dashed", false),
				"width": s.get("width", 1.0),
			})

	queue_redraw()


func _compute_world_rect(tilemap: Node) -> Rect2:
	var rect := Rect2()
	var has_any := false
	for child in tilemap.get_children():
		if not (child is TileMapLayer):
			continue
		var layer := child as TileMapLayer
		if layer.tile_set == null:
			continue
		var used: Rect2i = layer.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		var tile_size := Vector2(layer.tile_set.tile_size)
		var pad := tile_size * 0.5
		var corners := [
			Vector2i(used.position.x, used.position.y),
			Vector2i(used.position.x + used.size.x, used.position.y),
			Vector2i(used.position.x, used.position.y + used.size.y),
			Vector2i(used.position.x + used.size.x, used.position.y + used.size.y),
		]
		for c in corners:
			var world: Vector2 = layer.to_global(layer.map_to_local(c))
			var cell_rect := Rect2(world - pad, tile_size)
			if not has_any:
				rect = cell_rect
				has_any = true
			else:
				rect = rect.merge(cell_rect)
	return rect


func _blit_layer(dst: Image, layer: TileMapLayer) -> void:
	var ts: TileSet = layer.tile_set
	var tile_size := Vector2(ts.tile_size)
	var bake_size := Vector2(dst.get_width(), dst.get_height())
	var cells: Array[Vector2i] = layer.get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	for cell in cells:
		var source_id := layer.get_cell_source_id(cell)
		if source_id < 0:
			continue
		var source = ts.get_source(source_id)
		if not (source is TileSetAtlasSource):
			continue
		var atlas_src := source as TileSetAtlasSource
		var atlas_coords := layer.get_cell_atlas_coords(cell)
		if not atlas_src.has_tile(atlas_coords):
			continue

		var atlas_img := _get_atlas_image(atlas_src.texture)
		if atlas_img == null:
			continue
		var region: Rect2i = atlas_src.get_tile_texture_region(atlas_coords)
		if region.size.x <= 0 or region.size.y <= 0:
			continue
		if region.position.x < 0 or region.position.y < 0:
			continue
		if region.end.x > atlas_img.get_width() or region.end.y > atlas_img.get_height():
			continue

		var tile_img := atlas_img.get_region(region)
		var world_center: Vector2 = layer.to_global(layer.map_to_local(cell))
		var dst_tile_w := maxi(1, int(round(tile_size.x * bake_size.x / _world_rect.size.x)))
		var dst_tile_h := maxi(1, int(round(tile_size.y * bake_size.y / _world_rect.size.y)))
		if tile_img.get_width() != dst_tile_w or tile_img.get_height() != dst_tile_h:
			tile_img.resize(dst_tile_w, dst_tile_h, Image.INTERPOLATE_BILINEAR)

		var uv := (world_center - _world_rect.position) / _world_rect.size
		var px := Vector2i(
			int(round(uv.x * bake_size.x)) - dst_tile_w / 2,
			int(round(uv.y * bake_size.y)) - dst_tile_h / 2
		)
		_blend_rect_clipped(dst, tile_img, px)


func _get_atlas_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	if _atlas_cache.has(tex):
		return _atlas_cache[tex]
	var img := tex.get_image()
	if img == null:
		return null
	_atlas_cache[tex] = img
	return img


func _blend_rect_clipped(dst: Image, src: Image, dest_pos: Vector2i) -> void:
	var src_rect := Rect2i(Vector2i.ZERO, src.get_size())
	var dst_rect := Rect2i(dest_pos, src.get_size())
	var clipped := dst_rect.intersection(Rect2i(Vector2i.ZERO, dst.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	var src_offset := clipped.position - dest_pos
	var src_clipped := Rect2i(src_rect.position + src_offset, clipped.size)
	dst.blend_rect(src, src_clipped, clipped.position)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _terrain_tex != null:
		draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)

	if _world_rect.size.x <= 0.0 or _world_rect.size.y <= 0.0:
		return
	for s in _border_segments:
		var a: Vector2 = _world_to_local(s["a"])
		var b: Vector2 = _world_to_local(s["b"])
		var col: Color = s.get("color", Color.WHITE)
		col.a = maxf(col.a, 0.75)
		var w: float = maxf(float(s.get("width", 1.0)) * 1.5, BORDER_WIDTH)
		if s.get("dashed", false):
			draw_dashed_line(a, b, col, w, 4.0, true)
		else:
			draw_line(a, b, col, w, true)


func _world_to_local(world: Vector2) -> Vector2:
	var uv := (world - _world_rect.position) / _world_rect.size
	return uv * size


func _local_to_world(local: Vector2) -> Vector2:
	var uv := local / size
	return _world_rect.position + uv * _world_rect.size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _base_map == null or _world_rect.size.x <= 0.0:
				return
			var world := _local_to_world(mb.position)
			if _base_map.has_method("jump_camera_to"):
				_base_map.jump_camera_to(world)
			elif _base_map.get("camera") != null:
				_base_map.camera.position = world
			accept_event()
