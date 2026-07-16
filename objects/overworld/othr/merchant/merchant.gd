extends Node2D

## Roaming merchant camp: occupies one walkable tile, sells weapons to the de jure owner.

var type_ = GlobalStuff.BUILDING_TYPE.MERCHANT

var base_map
var province: Node = null
var cell: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
## Seasons remaining in the current province (rolled 1–2 on arrival).
var seasons_left: int = 1

const CELL_CENTER_OFFSET := Vector2(32, 16)


func get_pathfinding_blocked_tile_centers() -> Array:
	return [global_position + CELL_CENTER_OFFSET]


func place_at_cell(new_cell: Vector2i, prov: Node) -> void:
	cell = new_cell
	province = prov
	if base_map != null and base_map.pathfinding != null:
		global_position = base_map.pathfinding.cell_center_global(new_cell) - CELL_CENTER_OFFSET


func roll_stay(rng: RandomNumberGenerator) -> void:
	seasons_left = rng.randi_range(1, 2)
