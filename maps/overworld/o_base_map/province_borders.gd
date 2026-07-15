extends Node2D

## Dynamically generated province borders.
## Territory is grown from each building's tile(s) via a simultaneous
## multi-source BFS over walkable tiles, capped at MAX_RANGE. Every tile is
## claimed by the nearest province; tiles equidistant from two provinces stay
## neutral, so a contested border naturally settles halfway between rivals.
## The boundary is drawn as crisp diamond-edge lines in each owner's color,
## inset slightly toward the owning tile so both sides show on shared edges.

const MAX_RANGE := 5
const LINE_WIDTH := 2.0
const LINE_ALPHA := 0.5
# Pixels each border segment is nudged toward its own tile's center so that a
# shared edge between two provinces shows both colors instead of overlapping.
const INSET := 3.0
const DEFAULT_GRAY := Color8(128, 128, 128)

const EDGE_DIRS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

@onready var base_map: Node = get_parent()

# Vector2i -> province node (null = contested/neutral)
var owner_of: Dictionary = {}
# Vector2i -> settled BFS distance
var _dist: Dictionary = {}
# [{a: Vector2, b: Vector2, color: Color}]
var _segments: Array = []


func rebuild() -> void:
	owner_of.clear()
	_dist.clear()
	_segments.clear()

	var pathfinding = base_map.get_node_or_null("pathfinding")
	var provinces = base_map.get_node_or_null("provinces")
	if pathfinding == null or provinces == null or pathfinding.map_layer == null:
		queue_redraw()
		return

	var ml: TileMapLayer = pathfinding.map_layer
	var walkable: Dictionary = pathfinding.walkable_cells

	# 1) Seed every building's footprint tile(s), tagged with its province.
	var frontier: Array[Vector2i] = []
	for prov in provinces.get_children():
		for key in ["settlements", "fields", "economy", "defense"]:
			var container = prov.get_node_or_null(key)
			if container == null:
				continue
			for b in container.get_children():
				if not b.has_method("get_pathfinding_blocked_tile_centers"):
					continue
				for gpos in b.get_pathfinding_blocked_tile_centers():
					var cell: Vector2i = ml.local_to_map(ml.to_local(gpos))
					if _dist.has(cell) and owner_of.get(cell) != prov:
						owner_of[cell] = null  # two provinces seed the same tile
					elif not _dist.has(cell):
						owner_of[cell] = prov
						frontier.append(cell)
					_dist[cell] = 0

	# 2) Grow ring by ring; first arrival wins, equidistant rivals go neutral.
	var dist := 0
	while not frontier.is_empty() and dist < MAX_RANGE:
		dist += 1
		var claims: Dictionary = {}  # Vector2i -> province (null once contested)
		for cell in frontier:
			var prov = owner_of[cell]
			if prov == null:
				continue
			for d in EDGE_DIRS:
				var n: Vector2i = cell + d
				if _dist.has(n):
					continue
				if not walkable.has(n):
					continue  # borders stop at non-walkable tiles
				if claims.has(n) and claims[n] != prov:
					claims[n] = null
				elif not claims.has(n):
					claims[n] = prov
		var next_frontier: Array[Vector2i] = []
		for n in claims:
			owner_of[n] = claims[n]
			_dist[n] = dist
			next_frontier.append(n)
		frontier = next_frontier

	_build_segments(ml)
	queue_redraw()


func _build_segments(ml: TileMapLayer) -> void:
	var tile_size: Vector2 = Vector2(ml.tile_set.tile_size)
	var hw := tile_size.x * 0.5
	var hh := tile_size.y * 0.5
	# Diamond corners (relative to cell center) that bound the edge toward a
	# given cardinal neighbor in isometric space.
	var edge_corners := {
		Vector2i(1, 0): [Vector2(hw, 0), Vector2(0, hh)],
		Vector2i(0, 1): [Vector2(0, hh), Vector2(-hw, 0)],
		Vector2i(-1, 0): [Vector2(-hw, 0), Vector2(0, -hh)],
		Vector2i(0, -1): [Vector2(0, -hh), Vector2(hw, 0)],
	}

	for cell in owner_of:
		var prov = owner_of[cell]
		if prov == null:
			continue
		var center: Vector2 = to_local(ml.to_global(ml.map_to_local(cell)))
		var col := _province_color(prov)
		for d in EDGE_DIRS:
			if owner_of.get(cell + d, null) == prov:
				continue  # same owner across this edge -> interior, no line
			var pair = edge_corners[d]
			var a: Vector2 = center + pair[0]
			var b: Vector2 = center + pair[1]
			# Nudge the segment inward (toward this tile's center) so a shared
			# edge with a rival shows both colors as parallel lines.
			var edge_mid := (a + b) * 0.5
			var inward := (center - edge_mid).normalized() * INSET
			_segments.append({"a": a + inward, "b": b + inward, "color": col})


func _province_color(prov) -> Color:
	var col := DEFAULT_GRAY
	var players = base_map.get("players")
	if players != null and players.has(prov.player_owner):
		var c: Dictionary = players[prov.player_owner].color
		col = Color8(
			int(c.get("red", 128)),
			int(c.get("green", 128)),
			int(c.get("blue", 128))
		)
	col.a = LINE_ALPHA
	return col


func _draw() -> void:
	for s in _segments:
		draw_line(s["a"], s["b"], s["color"], LINE_WIDTH, true)
