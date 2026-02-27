extends Node2D

@export var enabled := true:
	set(value):
		enabled = value
		visible = value
		queue_redraw()

@export var text_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var shadow_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var shadow_offset := Vector2(1, 1)

@onready var _tilemap_root: Node = get_parent().get_node_or_null("tilemap")


func _ready() -> void:
	visible = enabled
	queue_redraw()


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var map_layer := _get_map_layer()
	if map_layer == null:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := ThemeDB.fallback_font_size
	for cell_variant in map_layer.get_used_cells():
		var cell: Vector2i = cell_variant
		var world := map_layer.global_position + map_layer.map_to_local(cell)
		var local_pos := to_local(world)
		var label := "%d,%d" % [cell.x, cell.y]
		draw_string(font, local_pos + shadow_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
		draw_string(font, local_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _get_map_layer() -> TileMapLayer:
	if _tilemap_root == null:
		return null
	for child in _tilemap_root.get_children():
		if child is TileMapLayer and child.tile_set != null:
			return child as TileMapLayer
	return null
