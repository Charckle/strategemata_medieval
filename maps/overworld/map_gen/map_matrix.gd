class_name MapMatrix
extends RefCounted

## Abstract overworld grid. Cell values are province ids (>= 0). Land-only for v1.
## Seat cells are province centers (one per province). Plots are building footprints.

const INVALID := -1

enum PlotKind {
	TOWN,
	VILLAGE,
	CASTLE,
	FIELD,
	ECONOMY_EMPTY,
	DEPOSIT_RANDOM,
}

## Ground cover (matches summer_set atlas usage).
enum Terrain {
	GRASS,
	HILLS,
	MOUNTAINS,
	TREES,
}

var width: int = 0
var height: int = 0
var province_count: int = 0
var seed_used: int = 0
## Row-major: index = y * width + x
var cells: PackedInt32Array = PackedInt32Array()
## Row-major road mask: 0 empty, 1 road
var roads: PackedByteArray = PackedByteArray()
## Row-major Terrain enum
var terrain: PackedByteArray = PackedByteArray()
## province_id -> Vector2i seat cell
var seats: Array[Vector2i] = []
## Each: { kind: PlotKind, province_id: int, origin: Vector2i, size: Vector2i }
var plots: Array[Dictionary] = []


static func plot_letter(kind: int) -> String:
	match kind:
		PlotKind.TOWN:
			return "T"
		PlotKind.VILLAGE:
			return "V"
		PlotKind.CASTLE:
			return "C"
		PlotKind.FIELD:
			return "F"
		PlotKind.ECONOMY_EMPTY:
			return "E"
		PlotKind.DEPOSIT_RANDOM:
			return "D"
		_:
			return "?"


static func plot_footprint_size(kind: int) -> Vector2i:
	match kind:
		PlotKind.TOWN, PlotKind.CASTLE:
			return Vector2i(2, 2)
		_:
			return Vector2i(1, 1)


func _init(w: int = 0, h: int = 0, provinces: int = 0) -> void:
	resize(w, h, provinces)


func resize(w: int, h: int, provinces: int) -> void:
	width = maxi(0, w)
	height = maxi(0, h)
	province_count = maxi(0, provinces)
	cells.resize(width * height)
	cells.fill(INVALID)
	roads.resize(width * height)
	roads.fill(0)
	terrain.resize(width * height)
	terrain.fill(Terrain.GRASS)
	seats.clear()
	seats.resize(province_count)
	for i in province_count:
		seats[i] = Vector2i(-1, -1)
	plots.clear()


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func index_of(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func get_cell(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return INVALID
	return cells[index_of(cell)]


func set_cell(cell: Vector2i, province_id: int) -> void:
	if not in_bounds(cell):
		return
	cells[index_of(cell)] = province_id


func is_seat(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var pid := get_cell(cell)
	if pid < 0 or pid >= seats.size():
		return false
	return seats[pid] == cell


func province_sizes() -> PackedInt32Array:
	var sizes := PackedInt32Array()
	sizes.resize(province_count)
	sizes.fill(0)
	for v in cells:
		if v >= 0 and v < province_count:
			sizes[v] += 1
	return sizes


func footprint_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in size.y:
		for dx in size.x:
			out.append(origin + Vector2i(dx, dy))
	return out


func plots_for_province(province_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in plots:
		if int(p.get("province_id", -1)) == province_id:
			out.append(p)
	return out


func has_road(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	return roads[index_of(cell)] != 0


func set_road(cell: Vector2i, enabled: bool = true) -> void:
	if not in_bounds(cell):
		return
	roads[index_of(cell)] = 1 if enabled else 0


func clear_roads() -> void:
	roads.fill(0)


func road_count() -> int:
	var n := 0
	for v in roads:
		if v != 0:
			n += 1
	return n


func get_terrain(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Terrain.GRASS
	return int(terrain[index_of(cell)])


func set_terrain(cell: Vector2i, kind: int) -> void:
	if not in_bounds(cell):
		return
	terrain[index_of(cell)] = kind


func clear_terrain() -> void:
	terrain.fill(Terrain.GRASS)


static func is_road_hub_kind(kind: int) -> bool:
	match kind:
		PlotKind.TOWN, PlotKind.VILLAGE, PlotKind.CASTLE:
			return true
		PlotKind.ECONOMY_EMPTY, PlotKind.DEPOSIT_RANDOM:
			return true
		_:
			return false
