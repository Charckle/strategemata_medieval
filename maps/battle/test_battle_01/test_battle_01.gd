@tool
extends "res://maps/battle/battle_board.gd"

## Sandbox battle map. Paint Terrain in the editor; drag BattleUnitMarker into Units.
## Toggle this in the inspector to regenerate the procedural sample terrain.
@export var repaint_sample_layout: bool = false:
	set(value):
		if value:
			if terrain_layer == null:
				terrain_layer = get_node_or_null("Terrain") as TileMapLayer
			if terrain_layer != null:
				paint_sample_layout()
				notify_property_list_changed()
		repaint_sample_layout = false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# Runtime convenience: empty boards get the sample layout automatically.
	if terrain_layer.get_used_cells().is_empty():
		paint_sample_layout()
