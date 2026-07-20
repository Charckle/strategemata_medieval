extends Node2D

## Roaming merchant camp: occupies one walkable tile; de jure owner can buy/sell weapons & materials.

var type_ = GlobalStuff.BUILDING_TYPE.MERCHANT

var base_map
var province: Node = null
var cell: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
## Seasons remaining in the current province (rolled 1–2 on arrival).
var seasons_left: int = 1
## Display name shown in shop / raid UI (e.g. Pipin, Mery).
var display_name: String = "Merchant"
## True while off-map because no safe province remains.
var camp_hidden: bool = false

const CELL_CENTER_OFFSET := Vector2(32, 16)


func get_pathfinding_blocked_tile_centers() -> Array:
	if camp_hidden:
		return []
	return [global_position + CELL_CENTER_OFFSET]


func place_at_cell(new_cell: Vector2i, prov: Node) -> void:
	cell = new_cell
	province = prov
	camp_hidden = false
	visible = true
	_set_clickable(true)
	if base_map != null and base_map.pathfinding != null:
		global_position = base_map.pathfinding.cell_center_global(new_cell) - CELL_CENTER_OFFSET


func hide_camp() -> void:
	camp_hidden = true
	province = null
	cell = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	visible = false
	_set_clickable(false)


func roll_stay(rng: RandomNumberGenerator) -> void:
	seasons_left = rng.randi_range(1, 2)


func _set_clickable(enabled: bool) -> void:
	var area = get_node_or_null("Area2D")
	if area != null:
		area.monitoring = enabled
		area.monitorable = enabled
		area.input_pickable = enabled
