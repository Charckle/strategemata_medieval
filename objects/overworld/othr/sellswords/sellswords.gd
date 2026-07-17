extends Node2D

## Hireable sellsword camp: occupies one walkable tile; de jure owner can hire the offer.

var type_ = GlobalStuff.BUILDING_TYPE.SELLSWORDS

var base_map
var province: Node = null
var cell: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
## Seasons remaining before the band leaves (rolled 1–3 on arrival).
var seasons_left: int = 1
## Array of { "type": UNIT_TYPE, "count": int } — the all-or-nothing hire offer.
var offer: Array = []

const CELL_CENTER_OFFSET := Vector2(32, 16)


func get_pathfinding_blocked_tile_centers() -> Array:
	return [global_position + CELL_CENTER_OFFSET]


func place_at_cell(new_cell: Vector2i, prov: Node) -> void:
	cell = new_cell
	province = prov
	if base_map != null and base_map.pathfinding != null:
		global_position = base_map.pathfinding.cell_center_global(new_cell) - CELL_CENTER_OFFSET


func roll_stay(rng: RandomNumberGenerator) -> void:
	seasons_left = rng.randi_range(1, 3)


func roll_offer(rng: RandomNumberGenerator) -> void:
	offer = GlobalUnits.roll_sellsword_offer(rng)


func offer_total_cost() -> int:
	return GlobalUnits.sellsword_offer_mark_price(offer)
