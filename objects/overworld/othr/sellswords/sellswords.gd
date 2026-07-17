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

const BANNER_YELLOW := Color(0.95, 0.85, 0.2)
const BANNER_GREEN := Color(0.25, 0.7, 0.25)
const BANNER_ORANGE := Color(1.0, 0.55, 0.1)
const BANNER_BLUE := Color(0.25, 0.45, 0.95)


func _ready() -> void:
	_setup_decorative_flags()


func shows_ownership_triangle() -> bool:
	return false


## Yellow+green always; +orange for 2 stacks; +blue for 3 stacks.
func _banner_colors_for_offer() -> Array:
	var colors: Array = [BANNER_YELLOW, BANNER_GREEN]
	var n := offer.size()
	if n >= 2:
		colors.append(BANNER_ORANGE)
	if n >= 3:
		colors.append(BANNER_BLUE)
	return colors


func _setup_decorative_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag != null and flag.has_method("setup_decorative_banners"):
		flag.setup_decorative_banners(_banner_colors_for_offer())


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
	_setup_decorative_flags()


func offer_total_cost() -> int:
	return GlobalUnits.sellsword_offer_mark_price(offer)
