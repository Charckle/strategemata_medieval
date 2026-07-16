extends Node2D

## Dynamically generated province borders.
##
## Solid lines: province territory grown from every building via multi-source
## BFS (MAX_RANGE), colored by province.player_owner.
##
## Dashed lines: within a province, all buildings compete by player owner
## (same multi-source BFS as solid borders). Only claims by players other than
## province.player_owner are drawn, dashed, and clipped to solid province tiles.

const MAX_RANGE := 5
const LINE_WIDTH := 2.0
const LINE_ALPHA := 0.5
const DASH_LEN := 5.0
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
# Vector2i -> settled BFS distance (province pass)
var _dist: Dictionary = {}
# [{a: Vector2, b: Vector2, color: Color, dashed: bool}]
var _segments: Array = []

# Occupation pass: Vector2i -> player_id (null = contested)
var _occ_owner: Dictionary = {}
var _occ_dist: Dictionary = {}


func rebuild() -> void:
	owner_of.clear()
	_dist.clear()
	_occ_owner.clear()
	_occ_dist.clear()
	_segments.clear()

	var pathfinding = base_map.get_node_or_null("pathfinding")
	var provinces = base_map.get_node_or_null("provinces")
	if pathfinding == null or provinces == null or pathfinding.map_layer == null:
		queue_redraw()
		return

	var ml: TileMapLayer = pathfinding.map_layer
	var walkable: Dictionary = pathfinding.walkable_cells

	_rebuild_province_territory(provinces, ml, walkable)
	_rebuild_occupation_territory(provinces, ml, walkable)
	_build_segments(ml)
	queue_redraw()


func _rebuild_province_territory(provinces: Node, ml: TileMapLayer, walkable: Dictionary) -> void:
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
	# Merchants also claim their tile so blocked camps don't punch territory holes.
	var merchants = base_map.get_node_or_null("merchants")
	if merchants != null:
		for m in merchants.get_children():
			var prov = m.get("province")
			if prov == null or not is_instance_valid(prov):
				continue
			if not m.has_method("get_pathfinding_blocked_tile_centers"):
				continue
			for gpos in m.get_pathfinding_blocked_tile_centers():
				var cell: Vector2i = ml.local_to_map(ml.to_local(gpos))
				if _dist.has(cell) and owner_of.get(cell) != prov:
					owner_of[cell] = null
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
					continue
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


func _effective_owner(building: Node) -> int:
	# Fields inherit ownership from their linked settlement.
	if building.get("owner_building") != null and building.owner_building != null:
		var ob = building.owner_building
		if ob.get("player_owner") != null:
			return int(ob.player_owner)
	if building.get("player_owner") != null:
		return int(building.player_owner)
	return -1


func _rebuild_occupation_territory(provinces: Node, ml: TileMapLayer, walkable: Dictionary) -> void:
	# All buildings compete by player. Dashed drawing later keeps only foreign claims.
	# cell -> province for each occupation claim (stay inside that province).
	var occ_province: Dictionary = {}
	var frontier: Array[Vector2i] = []

	for prov in provinces.get_children():
		for key in ["settlements", "fields", "economy", "defense"]:
			var container = prov.get_node_or_null(key)
			if container == null:
				continue
			for b in container.get_children():
				if not b.has_method("get_pathfinding_blocked_tile_centers"):
					continue
				var b_owner := _effective_owner(b)
				if b_owner < 0:
					continue
				for gpos in b.get_pathfinding_blocked_tile_centers():
					var cell: Vector2i = ml.local_to_map(ml.to_local(gpos))
					# Seed every building; rival owners on the same cell → contested.
					if _occ_dist.has(cell) and _occ_owner.get(cell) != b_owner:
						_occ_owner[cell] = null
						occ_province.erase(cell)
					elif not _occ_dist.has(cell):
						_occ_owner[cell] = b_owner
						occ_province[cell] = prov
						frontier.append(cell)
					_occ_dist[cell] = 0

	var dist := 0
	while not frontier.is_empty() and dist < MAX_RANGE:
		dist += 1
		var claims: Dictionary = {}  # Vector2i -> {pid, prov} or null if contested
		for cell in frontier:
			var pid = _occ_owner[cell]
			if pid == null:
				continue
			var seed_prov = occ_province.get(cell)
			if seed_prov == null:
				continue
			for d in EDGE_DIRS:
				var n: Vector2i = cell + d
				if _occ_dist.has(n):
					continue
				if not walkable.has(n):
					continue
				# Never bleed outside the solid province territory.
				if owner_of.get(n) != seed_prov:
					continue
				if claims.has(n):
					var existing = claims[n]
					if existing == null:
						continue
					if existing["pid"] != pid or existing["prov"] != seed_prov:
						claims[n] = null
				else:
					claims[n] = {"pid": pid, "prov": seed_prov}
		var next_frontier: Array[Vector2i] = []
		for n in claims:
			var claim = claims[n]
			if claim == null:
				_occ_owner[n] = null
				_occ_dist[n] = dist
				continue
			_occ_owner[n] = claim["pid"]
			occ_province[n] = claim["prov"]
			_occ_dist[n] = dist
			next_frontier.append(n)
		frontier = next_frontier


func _edge_corners(ml: TileMapLayer) -> Dictionary:
	var tile_size: Vector2 = Vector2(ml.tile_set.tile_size)
	var hw := tile_size.x * 0.5
	var hh := tile_size.y * 0.5
	return {
		Vector2i(1, 0): [Vector2(hw, 0), Vector2(0, hh)],
		Vector2i(0, 1): [Vector2(0, hh), Vector2(-hw, 0)],
		Vector2i(-1, 0): [Vector2(-hw, 0), Vector2(0, -hh)],
		Vector2i(0, -1): [Vector2(0, -hh), Vector2(hw, 0)],
	}


func _build_segments(ml: TileMapLayer) -> void:
	var edge_corners := _edge_corners(ml)

	# Solid province borders.
	for cell in owner_of:
		var prov = owner_of[cell]
		if prov == null:
			continue
		var center: Vector2 = to_local(ml.to_global(ml.map_to_local(cell)))
		var col := _player_color(int(prov.player_owner))
		for d in EDGE_DIRS:
			if owner_of.get(cell + d, null) == prov:
				continue
			var pair = edge_corners[d]
			var a: Vector2 = center + pair[0]
			var b: Vector2 = center + pair[1]
			var edge_mid := (a + b) * 0.5
			var inward := (center - edge_mid).normalized() * INSET
			_segments.append({
				"a": a + inward,
				"b": b + inward,
				"color": col,
				"dashed": false,
			})

	# Dashed occupation borders: only foreign claims (not province.player_owner).
	# Rival buildings compete in the BFS above, so the dashed edge sits between them.
	var occ_inset := INSET + 2.0
	for cell in _occ_owner:
		var pid = _occ_owner[cell]
		if pid == null:
			continue
		var prov = owner_of.get(cell)
		if prov == null:
			continue
		if int(pid) == int(prov.player_owner):
			continue  # province owner's share stays solid-only
		var center2: Vector2 = to_local(ml.to_global(ml.map_to_local(cell)))
		var col2 := _player_color(int(pid))
		for d in EDGE_DIRS:
			if _occ_owner.get(cell + d, null) == pid:
				continue
			var pair2 = edge_corners[d]
			var a2: Vector2 = center2 + pair2[0]
			var b2: Vector2 = center2 + pair2[1]
			var edge_mid2 := (a2 + b2) * 0.5
			var inward2 := (center2 - edge_mid2).normalized() * occ_inset
			_segments.append({
				"a": a2 + inward2,
				"b": b2 + inward2,
				"color": col2,
				"dashed": true,
			})


func _player_color(player_id: int) -> Color:
	var col := DEFAULT_GRAY
	var players = base_map.get("players")
	if players != null and players.has(player_id):
		var c: Dictionary = players[player_id].color
		col = Color8(
			int(c.get("red", 128)),
			int(c.get("green", 128)),
			int(c.get("blue", 128))
		)
	col.a = LINE_ALPHA
	return col


func _province_color(prov) -> Color:
	return _player_color(int(prov.player_owner))


func _draw() -> void:
	for s in _segments:
		if s.get("dashed", false):
			draw_dashed_line(s["a"], s["b"], s["color"], LINE_WIDTH, DASH_LEN, true)
		else:
			draw_line(s["a"], s["b"], s["color"], LINE_WIDTH, true)
