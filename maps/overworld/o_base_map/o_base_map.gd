extends Node2D

enum SEASONS { WINTER, SPRING, SUMMER, AUTUMN }

var season = SEASONS.WINTER
var turn = 0

var my_pl_id = 0

var players = {}

# Mutual alliances: alliances[pid] = Array of other player ids allied with pid.
# Kept bidirectional; mutated only via apply_set_alliance RPC.
var alliances := {}

# Authoritative force registry (rosters). Keyed by force_id:
#   { "units": Array[stack], "location": Dictionary, "controller": int }
# location = {"kind": "cell"}  -> a mobile army; the figure node holds its position
#          | {"kind": "garrison", "building": <path String>, "spot": SPOT}
# controller (mobile armies only): player who commands the army on the map.
# Built deterministically from the scene on every peer, then mutated only via
# the server-authoritative apply_* RPCs below so it stays in sync.
var forces := {}
var _next_runtime_force := 0

# VIP registry: vip_id -> { id, role, owner, force_id, alive }
var vips := {}
var _next_vip_id := 1
# Pending VIP trades: trade_id -> { from, to, offer_vip_ids, offer_marks, request_marks }
var vip_trades := {}
var _next_vip_trade_id := 1
# Set when a move click is processed; blocks army Area2D from opening the menu
# on the same frame after the army teleports under the cursor.
var _suppress_army_click_frame := -1
# Same-frame guard: after a garrison-intent move, the building Area2D must not
# open the empty info popup (pathfinding and Area2D can both see the click).
var _suppress_building_click_frame := -1
# After moving next to a building for garrison, open the transfer menu once the
# move RPC applies (set only on the peer that issued the move).
var _pending_garrison_army_name := ""
var _pending_garrison_force_id := ""
var _pending_garrison_building: Node = null
# After moving next to another army, open merge/attack once the move applies.
var _pending_army_interaction_mover_name := ""
var _pending_army_interaction_target: Node2D = null

# Global event log (kept for the whole game) + per-player message inboxes.
# game_events: event_id (String) -> event Dictionary
# player_inboxes: player_id -> Array of {"event_id": String} (newest first, capped)
# player_msg_unread: player_id -> bool
var game_events: Dictionary = {}
var _next_event_id: int = 1
var player_inboxes: Dictionary = {}
var player_msg_unread: Dictionary = {}

# In-transit weapon shipments between provinces.
# { from_id, to_id, cargo: Dictionary, seasons_left: int, shipper: int }
var weapon_shipments: Array = []

const ARMY_FIGURE_SCENE := preload("res://objects/overworld/army/army_map_unit/armiy_figure.tscn")
const MERCHANT_SCENE := preload("res://objects/overworld/othr/merchant/merchant.tscn")
const MERCHANT_COUNT := 2
const SELLSWORDS_SCENE := preload("res://objects/overworld/othr/sellswords/sellswords.tscn")
const SELLSWORDS_SPAWN_CHANCE := 0.10
const SELLSWORDS_DOUBLE_CHANCE := 0.10
const SELLSWORDS_MAX_PER_PROVINCE := 2

@onready var provinces = $provinces
@onready var armies = $armies
@onready var merchants = $merchants
@onready var sellswords = $sellswords
@onready var camera: Camera2D = $Camera2D
@onready var pathfinding = $pathfinding
@onready var province_labels = $ProvinceLabels
@onready var province_borders = $ProvinceBorders

@onready var gui_node = $BasebottomGUI

# province Node -> Array[Node] of bordering provinces (built once after borders).
var province_neighbors: Dictionary = {}
var _next_merchant_id: int = 1
var _next_sellswords_id: int = 1

# Building info popup: hover this long (seconds) before the transient popup shows.
const BUILDING_HOVER_DELAY := 2.0
var _hover_candidate: Node2D = null
var _hover_elapsed := 0.0

# Province focus: thick map border + economy Province tab context.
# sticky_province_id: last building/list pick (preferred when opening economy).
# focused_province_id: currently highlighted province (camera while menu closed).
var focused_province_id: String = ""
var sticky_province_id: String = ""
var _last_camera_focus_cell := Vector2i(999999, 999999)

func dummy_player_data():
	players[0] = GlobalStuff.PlayerData.new(0, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 0, "Richard", {"marks": 2500, "people": 0})
	players[1] = GlobalStuff.PlayerData.new(1, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 1, "William", {"marks": 2500, "people": 0})
	players[0].color = {"red": 0, "green": 100, "blue": 255}
	players[1].color = {"red": 255, "green": 0, "blue": 0}


func _ready() -> void:
	dummy_player_data()
	update_player_data.rpc(players)
	assign_players_home_provinces()
	initialize_map()
	set_players_turn()


func initialize_map() -> void:	
	for child in provinces.get_children():
		child.base_map = self
		child.sync_player_owner_to_children()
		child.recompute_control()
		child.set_flags()
		child.setup_map_label()
		if child.has_method("recalculate_marks_will_by_player"):
			child.recalculate_marks_will_by_player()
		if child.has_method("update_population_in_resources"):
			child.update_population_in_resources()
		if child.has_method("seed_test_weapons"):
			child.seed_test_weapons()
		if child.has_method("snapshot_season_start"):
			child.snapshot_season_start()
		if child.has_method("refresh_field_visuals"):
			child.refresh_field_visuals(int(season))
	
	for child in armies.get_children():
		child.base_map = self
		child.set_flags()
	# pathfinding
	pathfinding.initialize()
	build_forces_registry()
	seed_starting_vips()
	refresh_all_building_flags()
	province_borders.rebuild()
	build_province_neighbors()
	spawn_merchants()
	spawn_sellswords_initial()
	# Camps seed territory; refresh borders after placement.
	province_borders.rebuild()
	build_province_neighbors()
	_sync_initial_province_focus()
	refresh_all_vip_crowns()


# --- Province focus ---------------------------------------------------------

func _sync_initial_province_focus() -> void:
	var cam_prov := get_province_at_camera()
	if cam_prov != null:
		set_province_focus(String(cam_prov.name), false)
		return
	if players.has(my_pl_id):
		var home_id: String = str(players[my_pl_id].game_data.get("home_province_id", ""))
		if not home_id.is_empty() and _get_province_by_id(home_id) != null:
			set_province_focus(home_id, false)


func get_province_at_camera() -> Node:
	if pathfinding == null or pathfinding.map_layer == null or camera == null:
		return null
	var ml: TileMapLayer = pathfinding.map_layer
	var cell: Vector2i = ml.local_to_map(ml.to_local(camera.get_screen_center_position()))
	return find_province_for_cell(cell)


## Sticky (building/list) → camera → last focus → home.
func resolve_economy_province_focus() -> String:
	if sticky_province_id != "" and _get_province_by_id(sticky_province_id) != null:
		return sticky_province_id
	var cam_prov := get_province_at_camera()
	if cam_prov != null:
		return String(cam_prov.name)
	if focused_province_id != "" and _get_province_by_id(focused_province_id) != null:
		return focused_province_id
	if players.has(my_pl_id):
		var home_id: String = str(players[my_pl_id].game_data.get("home_province_id", ""))
		if not home_id.is_empty() and _get_province_by_id(home_id) != null:
			return home_id
	return ""


func set_province_focus(province_id: String, sticky: bool = false) -> void:
	if sticky and province_id != "":
		sticky_province_id = province_id
	if province_id == focused_province_id:
		return
	focused_province_id = province_id
	_notify_province_borders_focus()
	if is_instance_valid(gui_node) and gui_node.has_method("on_province_focused"):
		gui_node.on_province_focused(province_id)


func _notify_province_borders_focus() -> void:
	if province_borders == null or not province_borders.has_method("set_focused_province"):
		return
	var prov = _get_province_by_id(focused_province_id) if focused_province_id != "" else null
	province_borders.set_focused_province(prov)


func set_sticky_province_from_building(building: Node) -> void:
	if building == null:
		return
	var prov := find_province_for_building(building)
	if prov == null:
		prov = building.get("province")
	if prov == null or not is_instance_valid(prov):
		return
	set_province_focus(String(prov.name), true)


func _update_camera_province_focus() -> void:
	if is_instance_valid(gui_node) and gui_node.has_method("is_economy_menu_open") \
			and gui_node.is_economy_menu_open():
		return
	if pathfinding == null or pathfinding.map_layer == null or camera == null:
		return
	var ml: TileMapLayer = pathfinding.map_layer
	var cell: Vector2i = ml.local_to_map(ml.to_local(camera.get_screen_center_position()))
	if cell == _last_camera_focus_cell:
		return
	_last_camera_focus_cell = cell
	var prov := find_province_for_cell(cell)
	if prov == null:
		return  # contested / empty — keep last valid focus
	set_province_focus(String(prov.name), false)


# --- Force registry ---------------------------------------------------------

func build_forces_registry() -> void:
	forces.clear()
	for prov in provinces.get_children():
		for container_name in ["settlements", "economy", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				_register_building_start_garrison(b)
	for fig in armies.get_children():
		var units: Array = []
		if fig.get("start_units") != null:
			units = GlobalUnits.units_from_spec(fig.start_units)
		var controller := GlobalUnits.primary_owner(units)
		forces[String(fig.name)] = {"units": units, "location": {"kind": "cell"}, "controller": controller}
		fig.base_map = self
		fig.bind_force(String(fig.name))
		fig.reset_movement()


func _register_building_start_garrison(b: Node) -> void:
	if b.get("type_") == null:
		return
	var key := _building_key(b)
	if b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		_seed_garrison(key, GlobalUnits.SPOT.INSIDE, b.get("start_inside"))
		_seed_garrison(key, GlobalUnits.SPOT.OUTSIDE, b.get("start_outside"))
	else:
		_seed_garrison(key, GlobalUnits.SPOT.FLAT, b.get("start_garrison"))


func _seed_garrison(building_key: String, spot: int, spec) -> void:
	if spec == null or (spec is Array and spec.is_empty()):
		return
	forces[_garrison_force_id(building_key, spot)] = {
		"units": GlobalUnits.units_from_spec(spec),
		"location": {"kind": "garrison", "building": building_key, "spot": spot}
	}


func _building_key(b: Node) -> String:
	return String(get_path_to(b))


func _building_from_key(key: String) -> Node:
	return get_node_or_null(NodePath(key))


func _garrison_force_id(building_key: String, spot: int) -> String:
	return "g:%s#%d" % [building_key, spot]


func get_building_garrison(b: Node, spot: int) -> Array:
	var fid := _garrison_force_id(_building_key(b), spot)
	if forces.has(fid):
		return forces[fid]["units"]
	return []


func get_force_controller(fid: String) -> int:
	if forces.has(fid):
		return int(forces[fid].get("controller", -1))
	return -1


# --- VIP characters ---------------------------------------------------------

func seed_starting_vips() -> void:
	vips.clear()
	_next_vip_id = 1
	var pids: Array = players.keys()
	pids.sort()
	for pid in pids:
		if int(players[pid].status) != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue
		var town := _home_town_for_player(int(pid))
		if town == null:
			continue
		var fid := ensure_building_vip_force(town)
		for role in [GlobalVips.ROLE.KING, GlobalVips.ROLE.QUEEN, GlobalVips.ROLE.PRINCE]:
			_alloc_vip(role, int(pid), fid)
	refresh_all_vip_crowns()


func _alloc_vip(role: int, owner_pid: int, force_id: String) -> String:
	var vid := "vip_%d" % _next_vip_id
	_next_vip_id += 1
	vips[vid] = GlobalVips.make_vip(vid, role, owner_pid, force_id)
	return vid


func _home_town_for_player(pid: int) -> Node:
	if not players.has(pid):
		return null
	var home_id: String = str(players[pid].game_data.get("home_province_id", ""))
	var prov = _get_province_by_id(home_id) if home_id != "" else null
	if prov != null:
		var sett = prov.get_node_or_null("settlements")
		if sett != null:
			for s in sett.get_children():
				if s.get("type_") != null and s.type_ == GlobalStuff.BUILDING_TYPE.TOWN \
						and int(s.player_owner) == pid:
					return s
			for s in sett.get_children():
				if s.get("type_") != null and s.type_ == GlobalStuff.BUILDING_TYPE.TOWN:
					return s
	# Fallback: first owned town on the map.
	for p in provinces.get_children():
		var sett2 = p.get_node_or_null("settlements")
		if sett2 == null:
			continue
		for s in sett2.get_children():
			if s.get("type_") != null and s.type_ == GlobalStuff.BUILDING_TYPE.TOWN \
					and int(s.player_owner) == pid:
				return s
	return null


func vip_garrison_spot_for(building: Node) -> int:
	if building != null and building.get("type_") != null \
			and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		return GlobalUnits.SPOT.INSIDE
	return GlobalUnits.SPOT.FLAT


func ensure_building_vip_force(building: Node) -> String:
	var key := _building_key(building)
	var spot := vip_garrison_spot_for(building)
	var fid := _garrison_force_id(key, spot)
	if not forces.has(fid):
		forces[fid] = {
			"units": [],
			"location": {"kind": "garrison", "building": key, "spot": spot},
		}
	return fid


func get_vips_on_force(force_id: String) -> Array:
	return GlobalVips.vip_ids_on_force(vips, force_id)


func force_has_any_vip(force_id: String) -> bool:
	return GlobalVips.force_has_vip(vips, force_id)


func building_has_any_vip(building: Node) -> bool:
	if building == null:
		return false
	for fid in _building_garrison_force_ids(building):
		if force_has_any_vip(fid):
			return true
	return false


func get_building_vip_ids(building: Node) -> Array:
	var out: Array = []
	if building == null:
		return out
	for fid in _building_garrison_force_ids(building):
		for vid in get_vips_on_force(fid):
			if not out.has(vid):
				out.append(vid)
	return out


func _building_garrison_force_ids(building: Node) -> Array:
	var key := _building_key(building)
	var out: Array = []
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			out.append(_garrison_force_id(key, spot))
	else:
		out.append(_garrison_force_id(key, GlobalUnits.SPOT.FLAT))
	return out


func get_vip(vip_id: String) -> Dictionary:
	if vips.has(vip_id):
		return vips[vip_id]
	return {}


func vip_display_name(vip_id: String) -> String:
	var v := get_vip(vip_id)
	if v.is_empty():
		return "VIP"
	return GlobalVips.display_name(v, players)


func set_vip_force(vip_id: String, force_id: String) -> void:
	if not vips.has(vip_id):
		return
	if not bool(vips[vip_id].get("alive", false)):
		return
	vips[vip_id]["force_id"] = force_id


func move_vips_to_force(vip_ids: Array, dest_force_id: String) -> void:
	if dest_force_id == "" or not forces.has(dest_force_id):
		return
	for vid in vip_ids:
		set_vip_force(str(vid), dest_force_id)


func transfer_all_vips(from_force_id: String, to_force_id: String) -> void:
	move_vips_to_force(get_vips_on_force(from_force_id), to_force_id)


func kill_vip(vip_id: String) -> void:
	if not vips.has(vip_id):
		return
	vips[vip_id]["alive"] = false
	vips[vip_id]["force_id"] = ""


func holder_of_vip(vip_id: String) -> int:
	var v := get_vip(vip_id)
	if v.is_empty() or not bool(v.get("alive", false)):
		return -1
	var fid := str(v.get("force_id", ""))
	if not forces.has(fid):
		return -1
	var loc: Dictionary = forces[fid].get("location", {})
	if str(loc.get("kind", "")) == "garrison":
		var b := _building_from_key(str(loc.get("building", "")))
		if b != null and b.get("player_owner") != null:
			return int(b.player_owner)
		return -1
	return get_force_controller(fid)


func player_holds_vip(pid: int, vip_id: String) -> bool:
	return holder_of_vip(vip_id) == pid


func refresh_vip_crown_for_force(force_id: String) -> void:
	var fig = armies.get_node_or_null(force_id)
	if fig != null and fig.has_method("refresh_vip_crown"):
		fig.refresh_vip_crown()
	var bkey := _building_key_from_garrison_force_id(force_id)
	if bkey != "":
		var b := _building_from_key(bkey)
		if b != null and b.has_method("refresh_vip_crown"):
			b.refresh_vip_crown()


func refresh_all_vip_crowns() -> void:
	for fig in armies.get_children():
		if fig.has_method("refresh_vip_crown"):
			fig.refresh_vip_crown()
	for prov in provinces.get_children():
		for container_name in ["settlements", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				if b.has_method("refresh_vip_crown"):
					b.refresh_vip_crown()


func _force_anchor_cell(force_id: String) -> Vector2i:
	var invalid := Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	if not forces.has(force_id):
		return invalid
	var loc: Dictionary = forces[force_id].get("location", {})
	if str(loc.get("kind", "")) == "garrison":
		var b := _building_from_key(str(loc.get("building", "")))
		if b == null:
			return invalid
		var approach = pathfinding.get_approach_cells(b)
		if approach.is_empty():
			return invalid
		return approach[0]
	var fig = armies.get_node_or_null(force_id)
	if fig == null:
		return invalid
	return pathfinding.get_army_cell(fig)


func _path_dist(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var invalid := Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	if from_cell == invalid or to_cell == invalid:
		return 999999
	if from_cell == to_cell:
		return 0
	if pathfinding == null or pathfinding.astar_graph == null:
		return 999999
	if not pathfinding.cell_to_point_id.has(from_cell) or not pathfinding.cell_to_point_id.has(to_cell):
		return 999999
	var path: PackedInt64Array = pathfinding.astar_graph.get_id_path(
		pathfinding.cell_to_point_id[from_cell],
		pathfinding.cell_to_point_id[to_cell]
	)
	if path.is_empty():
		return 999999
	return path.size() - 1


func _pick_closest_vip_cand(cands: Array) -> String:
	var best_fid := ""
	var best_dist := 999999
	for c in cands:
		if bool(c.get("pathless", true)):
			continue
		var d := int(c["dist"])
		if best_fid == "" or d < best_dist:
			best_fid = str(c["fid"])
			best_dist = d
	return best_fid


func _building_approach_cell(building: Node) -> Vector2i:
	var invalid := Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	if building == null or pathfinding == null:
		return invalid
	var approach = pathfinding.get_approach_cells(building)
	if approach.is_empty():
		return invalid
	return approach[0]


## Closest owned town/castle garrison (preferred) or army for player_id from from_cell.
## Returns force_id or "" if none.
func find_closest_vip_destination(player_id: int, from_cell: Vector2i, prefer_garrison: bool = true) -> String:
	var garrison_cands: Array = []
	var army_cands: Array = []
	for prov in provinces.get_children():
		for container_name in ["settlements", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				if b.get("player_owner") == null or int(b.player_owner) != player_id:
					continue
				var type_ = b.get("type_")
				if type_ == null:
					continue
				if type_ != GlobalStuff.BUILDING_TYPE.TOWN and type_ != GlobalStuff.BUILDING_TYPE.CASTLE:
					continue
				var fid := garrison_force_id_for(b, vip_garrison_spot_for(b))
				var cell := _building_approach_cell(b)
				var dist := _path_dist(from_cell, cell)
				garrison_cands.append({"fid": fid, "dist": dist, "pathless": dist >= 999999, "building": b})
	for fig in armies.get_children():
		if not fig.has_method("get_controller") or fig.get_controller() != player_id:
			continue
		var fid2 := str(fig.force_id) if fig.get("force_id") != null else str(fig.name)
		if not forces.has(fid2):
			continue
		if GlobalUnits.total_men(forces[fid2]["units"]) < GlobalUnits.MIN_SPLIT_MEN:
			continue
		var cell2 := _force_anchor_cell(fid2)
		var dist2 := _path_dist(from_cell, cell2)
		army_cands.append({"fid": fid2, "dist": dist2, "pathless": dist2 >= 999999})

	var chosen := ""
	if prefer_garrison:
		chosen = _pick_closest_vip_cand(garrison_cands)
		if chosen == "":
			chosen = _pick_closest_vip_cand(army_cands)
	else:
		chosen = _pick_closest_vip_cand(army_cands)
		if chosen == "":
			chosen = _pick_closest_vip_cand(garrison_cands)

	if chosen != "":
		if chosen.begins_with("g:"):
			var bkey := _building_key_from_garrison_force_id(chosen)
			var b := _building_from_key(bkey)
			if b != null:
				return ensure_building_vip_force(b)
		return chosen

	# Fallback: first province (by name) town/castle of the player.
	var prov_list: Array = provinces.get_children()
	prov_list.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for prov in prov_list:
		for container_name in ["settlements", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				if b.get("player_owner") == null or int(b.player_owner) != player_id:
					continue
				var type_ = b.get("type_")
				if type_ == null:
					continue
				if type_ != GlobalStuff.BUILDING_TYPE.TOWN and type_ != GlobalStuff.BUILDING_TYPE.CASTLE:
					continue
				return ensure_building_vip_force(b)
	return ""


func relocate_vips_for_player(vip_ids: Array, player_id: int, from_cell: Vector2i) -> void:
	var dest := find_closest_vip_destination(player_id, from_cell, true)
	if dest == "":
		return  # edge case: nowhere to go — leave as-is / no-op
	move_vips_to_force(vip_ids, dest)
	refresh_vip_crown_for_force(dest)


func relocate_vips_from_disbanded_force(force_id: String, disbander: int) -> void:
	var vip_ids := get_vips_on_force(force_id)
	if vip_ids.is_empty():
		return
	var from_cell := _force_anchor_cell(force_id)
	var dest := find_closest_vip_destination(disbander, from_cell, true)
	if dest == "" or dest == force_id:
		# Fallback: original owners' closest (per VIP).
		for vid in vip_ids:
			var v := get_vip(str(vid))
			if v.is_empty():
				continue
			var owner_id := int(v.get("owner", -1))
			var odest := find_closest_vip_destination(owner_id, from_cell, true)
			if odest != "" and odest != force_id:
				set_vip_force(str(vid), odest)
				refresh_vip_crown_for_force(odest)
			# else: no-op, leave force_id (force is about to be erased — clear)
			elif dest == "":
				# Cannot place — leave alive but force cleared in kill path avoided; park on owner home if any
				var town := _home_town_for_player(owner_id)
				if town != null:
					var tfid := ensure_building_vip_force(town)
					set_vip_force(str(vid), tfid)
					refresh_vip_crown_for_force(tfid)
		return
	move_vips_to_force(vip_ids, dest)
	refresh_vip_crown_for_force(dest)


func _make_vip_message_event(kind_extra: String, text: String, recipient: int, actor_id: int = -1) -> String:
	var event := {
		"kind": GameEvents.KIND.VIP,
		"vip_kind": kind_extra,
		"text": text,
		"turn": turn,
		"season": int(season),
		"place_name": "",
		"world_x": 0.0,
		"world_y": 0.0,
		"participant_ids": [recipient],
		"actor_id": actor_id if actor_id >= 0 else recipient,
	}
	var eid := _register_event(event)
	_deliver_event_to_players(eid, [recipient], int(event["actor_id"]), false)
	return eid


func vip_combat_delta_for_sides(my_force_ids: Array, my_controller: int, enemy_force_ids: Array) -> float:
	return GlobalVips.combat_delta(vips, my_force_ids, my_controller, enemy_force_ids)


func get_force_battle_strength_with_vips(force_id: String, enemy_force_ids: Array) -> int:
	if not forces.has(force_id):
		return 0
	var base := GlobalUnits.fighting_strength(forces[force_id]["units"])
	var ctrl := get_force_controller(force_id)
	var delta := vip_combat_delta_for_sides([force_id], ctrl, enemy_force_ids)
	return GlobalVips.apply_strength_multiplier(base, delta)


func get_building_battle_strength_with_vips(building: Node, enemy_force_ids: Array) -> int:
	var base := get_building_battle_strength(building)
	if building == null:
		return base
	var ctrl := int(building.player_owner) if building.get("player_owner") != null else -1
	var my_fids := _building_garrison_force_ids(building)
	var delta := vip_combat_delta_for_sides(my_fids, ctrl, enemy_force_ids)
	return GlobalVips.apply_strength_multiplier(base, delta)


# --- Game events / message inbox --------------------------------------------

func export_events_state() -> Dictionary:
	return {
		"game_events": game_events.duplicate(true),
		"next_event_id": _next_event_id,
		"player_inboxes": player_inboxes.duplicate(true),
		"player_msg_unread": player_msg_unread.duplicate(true),
	}


func import_events_state(state: Dictionary) -> void:
	game_events = state.get("game_events", {}).duplicate(true)
	_next_event_id = int(state.get("next_event_id", 1))
	player_inboxes = state.get("player_inboxes", {}).duplicate(true)
	player_msg_unread = state.get("player_msg_unread", {}).duplicate(true)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_msg_button"):
		gui_node.refresh_msg_button()


func player_display_name(pid: int) -> String:
	if players.has(pid):
		return str(players[pid].name_)
	return "Unknown"


func has_msg_unread(pid: int = -1) -> bool:
	if pid < 0:
		pid = my_pl_id
	return bool(player_msg_unread.get(pid, false))


func clear_msg_unread(pid: int = -1) -> void:
	if pid < 0:
		pid = my_pl_id
	player_msg_unread[pid] = false


func get_inbox_entries(pid: int = -1) -> Array:
	if pid < 0:
		pid = my_pl_id
	return player_inboxes.get(pid, [])


func get_event(event_id: String) -> Dictionary:
	if game_events.has(event_id):
		return game_events[event_id]
	return {}


func center_camera_on_event(event_id: String) -> void:
	var event := get_event(event_id)
	if event.is_empty():
		return
	jump_camera_to(GameEvents.world_pos_of(event))


func jump_camera_to(world_pos: Vector2) -> void:
	camera.position = world_pos
	_last_camera_focus_cell = Vector2i(999999, 999999)


func _alloc_event_id() -> String:
	var eid := str(_next_event_id)
	_next_event_id += 1
	return eid


func _register_event(event: Dictionary) -> String:
	var eid := str(event.get("id", ""))
	if eid == "":
		eid = _alloc_event_id()
		event["id"] = eid
	else:
		var n := int(eid)
		if n >= _next_event_id:
			_next_event_id = n + 1
	game_events[eid] = event
	return eid


func _push_inbox(pid: int, event_id: String, mark_unread: bool) -> void:
	if not player_inboxes.has(pid):
		player_inboxes[pid] = []
	var inbox: Array = player_inboxes[pid]
	inbox.push_front({"event_id": event_id})
	while inbox.size() > GameEvents.INBOX_CAP:
		inbox.pop_back()
	player_inboxes[pid] = inbox
	if mark_unread:
		player_msg_unread[pid] = true


func _deliver_event_to_players(event_id: String, recipient_ids: Array, actor_id: int, auto_open_for_actor: bool = true) -> void:
	var i_am_recipient := false
	for pid in recipient_ids:
		var p := int(pid)
		_push_inbox(p, event_id, p != actor_id)
		if p == my_pl_id:
			i_am_recipient = true
	if not i_am_recipient or not is_instance_valid(gui_node):
		return
	if auto_open_for_actor and my_pl_id == actor_id and gui_node.has_method("open_event_report"):
		gui_node.open_event_report(self, event_id)
	if gui_node.has_method("refresh_msg_button"):
		gui_node.refresh_msg_button()
	if gui_node.has_method("refresh_msg_list_if_open"):
		gui_node.refresh_msg_list_if_open()


func _owners_array(units: Array) -> Array:
	var out: Array = []
	for pid in GlobalUnits.owners_in(units):
		out.append(int(pid))
	return out


func _force_world_pos(force_id: String) -> Vector2:
	if not forces.has(force_id):
		return Vector2.ZERO
	var loc: Dictionary = forces[force_id].get("location", {})
	if str(loc.get("kind", "")) == "garrison":
		var b := _building_from_key(str(loc.get("building", "")))
		if b != null and b is Node2D:
			return (b as Node2D).global_position
		return Vector2.ZERO
	var fig = armies.get_node_or_null(force_id)
	if fig != null:
		return fig.global_position + Vector2(32, 16)
	return Vector2.ZERO


func _building_place_name(building: Node) -> String:
	if building == null:
		return "Unknown"
	var bname := _building_display_name(building) if building is Node2D else "Building"
	var prov := building.get_parent()
	while prov != null and prov.get_parent() != provinces:
		prov = prov.get_parent()
	if prov != null:
		var pname := str(prov.p_name) if prov.get("p_name") != null else str(prov.name)
		return "%s (%s)" % [bname, pname]
	return bname


func _battle_place_name(building: Node, attacker_id: String, defender_army_id: String) -> String:
	if building != null:
		return _building_place_name(building)
	var fig = armies.get_node_or_null(defender_army_id)
	if fig == null:
		fig = armies.get_node_or_null(attacker_id)
	if fig != null:
		return "Field battle"
	return "Battle"


func _make_battle_event(
	attacker_id: String,
	defender_army_id: String,
	building: Node,
	attacker_won: bool,
	atk_units: Array,
	def_units: Array,
	atk_result: Dictionary,
	def_result: Dictionary,
	hostage_pool: Array
) -> Dictionary:
	var atk_side := _owners_array(atk_units)
	var def_side := _owners_array(def_units)
	var participants: Array = []
	for pid in atk_side:
		if not participants.has(pid):
			participants.append(pid)
	for pid in def_side:
		if not participants.has(pid):
			participants.append(pid)
	var pos := Vector2.ZERO
	if building != null and building is Node2D:
		pos = (building as Node2D).global_position
	else:
		pos = _force_world_pos(attacker_id)
		if pos == Vector2.ZERO:
			pos = _force_world_pos(defender_army_id)
	var hostage_men := GlobalUnits.total_men(hostage_pool) if attacker_won else 0
	var hostage_fate := "none"
	if hostage_men > 0:
		hostage_fate = "pending"
	return {
		"id": _alloc_event_id(),
		"kind": GameEvents.KIND.BATTLE,
		"turn": turn,
		"season": season,
		"attacker_id": attacker_id,
		"defender_id": defender_army_id,
		"building_key": _building_key(building) if building != null else "",
		"is_siege": building != null,
		"attacker_won": attacker_won,
		"attacker_dead": int(atk_result.get("dead", 0)),
		"attacker_wounded": int(atk_result.get("wounded_men", 0)),
		"defender_dead": int(def_result.get("dead", 0)),
		"defender_wounded": int(def_result.get("wounded_men", 0)),
		"hostage_men": hostage_men,
		"hostage_fate": hostage_fate,  # none | pending | taken | sword
		"attacker_side_ids": atk_side,
		"defender_side_ids": def_side,
		"participant_ids": participants,
		"place_name": _battle_place_name(building, attacker_id, defender_army_id),
		"world_x": pos.x,
		"world_y": pos.y,
		"actor_id": get_force_controller(attacker_id),
	}


func _make_join_event(force_id: String, offeror_id: int, result: Dictionary) -> Dictionary:
	var pos := _force_world_pos(force_id)
	var type_ := int(result.get("type", 0))
	var source_ := int(result.get("source", 0))
	var place := "Army"
	if forces.has(force_id):
		var loc: Dictionary = forces[force_id].get("location", {})
		if str(loc.get("kind", "")) == "garrison":
			var b := _building_from_key(str(loc.get("building", "")))
			if b != null:
				place = _building_place_name(b)
	return {
		"id": _alloc_event_id(),
		"kind": GameEvents.KIND.JOIN,
		"turn": turn,
		"season": season,
		"force_id": force_id,
		"offeror_id": offeror_id,
		"accepted": bool(result.get("accepted", false)),
		"count": int(result.get("count", 0)),
		"type": type_,
		"source": source_,
		"unit_name": GlobalUnits.unit_name(type_),
		"source_name": GlobalUnits.source_name(source_),
		"place_name": place,
		"world_x": pos.x,
		"world_y": pos.y,
		"actor_id": -1,  # season resolution — always unread for offeror
	}


func _make_building_capture_event(building: Node, previous_owner: int, capturer: int) -> Dictionary:
	var pos := (building as Node2D).global_position if building is Node2D else Vector2.ZERO
	return {
		"id": _alloc_event_id(),
		"kind": GameEvents.KIND.BUILDING_CAPTURE,
		"turn": turn,
		"season": season,
		"building_key": _building_key(building),
		"place_name": _building_place_name(building),
		"previous_owner": previous_owner,
		"new_owner": capturer,
		"world_x": pos.x,
		"world_y": pos.y,
		"actor_id": capturer,
	}


func get_all_building_garrison(b: Node) -> Array:
	var result: Array = []
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			result = GlobalUnits.merge_units(result, get_building_garrison(b, spot))
	else:
		result = GlobalUnits.merge_units(result, get_building_garrison(b, GlobalUnits.SPOT.FLAT))
	return result


func refresh_building_flags(building_key: String) -> void:
	var b := _building_from_key(building_key)
	if b != null and b.has_method("set_flags"):
		b.set_flags()


func refresh_all_building_flags() -> void:
	for prov in provinces.get_children():
		for container_name in ["settlements", "economy", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				if b.has_method("set_flags"):
					b.set_flags()


func _building_key_from_garrison_force_id(fid: String) -> String:
	# Force ids are "g:<building_key>#<spot>".
	if not fid.begins_with("g:"):
		return ""
	var rest := fid.substr(2)
	var hash_idx := rest.rfind("#")
	if hash_idx < 0:
		return ""
	return rest.substr(0, hash_idx)


# Frees the figure (if any) and drops the entry when a force is emptied.
# VIP-only garrisons are kept. VIP-only mobile armies relocate VIPs then erase.
func _cleanup_force_if_empty(fid: String) -> void:
	if not forces.has(fid):
		return
	if GlobalUnits.total_men(forces[fid]["units"]) > 0:
		return
	var vip_ids := get_vips_on_force(fid)
	var loc: Dictionary = forces[fid].get("location", {})
	var is_garrison := str(loc.get("kind", "")) == "garrison"
	if not vip_ids.is_empty() and is_garrison:
		return
	if not vip_ids.is_empty() and not is_garrison:
		var ctrl := get_force_controller(fid)
		relocate_vips_from_disbanded_force(fid, ctrl)
	forces.erase(fid)
	var fig = armies.get_node_or_null(fid)
	if fig != null:
		armies.remove_child(fig)
		fig.queue_free()
	refresh_all_vip_crowns()


func suppress_army_click_this_frame() -> void:
	_suppress_army_click_frame = Engine.get_process_frames()


func should_suppress_army_click() -> bool:
	return _suppress_army_click_frame == Engine.get_process_frames() or is_mouse_over_gui()


func suppress_building_click_this_frame() -> void:
	_suppress_building_click_frame = Engine.get_process_frames()


func should_suppress_building_click() -> bool:
	return _suppress_building_click_frame == Engine.get_process_frames() or is_mouse_over_gui()


## True when the cursor is over any Control (menus, bottom bar, popups).
## Area2D map picks ignore this otherwise and click "through" UI.
## Uses hover plus a geometry fallback: Labels often IGNORE, which can make
## gui_get_hovered_control() return null over filled menu panels.
func is_mouse_over_gui() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return true
	if is_instance_valid(gui_node) and gui_node.has_method("blocks_map_at_mouse"):
		return gui_node.blocks_map_at_mouse()
	return false


func on_army_clicked(army: Node2D) -> void:
	if is_mouse_over_gui():
		return
	var selected = pathfinding.selected_army if pathfinding != null else null
	# Clicking the army you're already moving: same spot → open its menu.
	if selected == army:
		open_selected_army_menu(army)
		return
	# A different army is selected: interact if adjacent, else move to approach.
	if selected != null and selected != army:
		if pathfinding.are_armies_adjacent(selected, army):
			pathfinding.open_army_interaction(selected, army)
		else:
			pathfinding.confirm_move_to_army(army)
		return
	if army.is_controllable_by(my_pl_id):
		gui_node.open_army_menu(self, army)
	elif army.has_units_of(my_pl_id):
		gui_node.open_withdraw_menu(self, army)
	else:
		show_army_owner_popup(army)


# Leave movement mode and open the normal army action menu for this force.
func open_selected_army_menu(army: Node2D) -> void:
	if army == null or not is_instance_valid(army):
		return
	pathfinding.deselect_army()
	if army.is_controllable_by(my_pl_id):
		gui_node.open_army_menu(self, army)
	elif army.has_units_of(my_pl_id):
		gui_node.open_withdraw_menu(self, army)
	else:
		show_army_owner_popup(army)


func _on_army_interaction(mover: Node2D, target: Node2D) -> void:
	if mover == null or target == null or not is_instance_valid(mover) or not is_instance_valid(target):
		return
	# Cannot transfer with yourself — treat as reopening the army menu.
	if mover == target or mover.force_id == target.force_id:
		open_selected_army_menu(mover)
		return
	if forces_are_friendly(mover.get_owner_set(), target.get_owner_set()):
		pathfinding.deselect_army()
		gui_node.open_force_menu(self, mover.force_id, target.force_id)
	else:
		pathfinding.deselect_army()
		gui_node.open_battle_menu(self, mover.force_id, target.force_id, null)


# --- Diplomacy (alliances) --------------------------------------------------

func are_allied(a: int, b: int) -> bool:
	if a == b:
		return false
	if not alliances.has(a):
		return false
	return b in alliances[a]


func are_friendly_players(a: int, b: int) -> bool:
	return a == b or are_allied(a, b)


# True when any owner on side A is the same player as, or allied with, any owner on side B.
func forces_are_friendly(owners_a, owners_b) -> bool:
	for a in owners_a:
		for b in owners_b:
			if are_friendly_players(int(a), int(b)):
				return true
	return false


func get_playing_players_except(except_id: int) -> Array:
	var out: Array = []
	for pid in players.keys():
		var p = players[pid]
		if int(pid) == except_id:
			continue
		if p.status != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue
		out.append(int(pid))
	out.sort()
	return out


func do_set_alliance(other_id: int, allied: bool) -> void:
	request_set_alliance.rpc_id(1, my_pl_id, other_id, allied)


@rpc("any_peer", "call_local", "reliable")
func request_set_alliance(player_a: int, player_b: int, allied: bool) -> void:
	if not multiplayer.is_server():
		return
	if player_a == player_b:
		return
	if not players.has(player_a) or not players.has(player_b):
		return
	apply_set_alliance.rpc(player_a, player_b, allied)


@rpc("authority", "call_local", "reliable")
func apply_set_alliance(player_a: int, player_b: int, allied: bool) -> void:
	if player_a == player_b:
		return
	if allied:
		_add_ally(player_a, player_b)
		_add_ally(player_b, player_a)
	else:
		_remove_ally(player_a, player_b)
		_remove_ally(player_b, player_a)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_alliances_list"):
		gui_node.refresh_alliances_list()


func _add_ally(a: int, b: int) -> void:
	if not alliances.has(a):
		alliances[a] = []
	if b not in alliances[a]:
		alliances[a].append(b)


func _remove_ally(a: int, b: int) -> void:
	if not alliances.has(a):
		return
	alliances[a].erase(b)
	if alliances[a].is_empty():
		alliances.erase(a)


# --- Battle / building conquest ---------------------------------------------

func is_building_friendly_to(building: Node, player_id: int) -> bool:
	if building == null or building.get("player_owner") == null:
		return false
	return are_friendly_players(player_id, int(building.player_owner))


func get_building_fighting_units(building: Node) -> Array:
	return GlobalUnits.fighting_units(get_all_building_garrison(building))


func get_building_battle_strength(building: Node) -> int:
	if building == null:
		return 0
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	if is_castle:
		var inside_str := GlobalUnits.fighting_strength(
			get_building_garrison(building, GlobalUnits.SPOT.INSIDE), GlobalUnits.CASTLE_INSIDE_BONUS
		)
		var outside_str := GlobalUnits.fighting_strength(
			get_building_garrison(building, GlobalUnits.SPOT.OUTSIDE), GlobalUnits.CASTLE_OUTSIDE_BATTLE_BONUS
		)
		return inside_str + outside_str
	return GlobalUnits.fighting_strength(
		get_building_garrison(building, GlobalUnits.SPOT.FLAT), GlobalUnits.CASTLE_OUTSIDE_BATTLE_BONUS
	)


func open_army_building_interaction(force_id: String, building: Node) -> void:
	if not forces.has(force_id) or building == null or not is_instance_valid(building):
		return
	var controller := get_force_controller(force_id)
	if is_building_friendly_to(building, controller):
		gui_node.open_garrison_menu(self, force_id, building)
		return
	if GlobalUnits.fighting_men(get_all_building_garrison(building)) <= 0:
		gui_node.open_building_actions_menu(self, force_id, building)
	else:
		gui_node.open_battle_menu(self, force_id, "", building)


func find_province_for_building(building: Node) -> Node:
	var n: Node = building
	while n != null:
		if n.get_parent() == provinces:
			return n
		n = n.get_parent()
	return null


func province_total_population(prov: Node) -> int:
	if prov == null:
		return 0
	return int(prov.resources.get("population", {}).get("has", {}).get("all", 0))


func province_predicted_marks_total(prov: Node) -> int:
	if prov == null:
		return 0
	var will: Dictionary = prov.resources.get("marks", {}).get("will", {})
	if will.has("all"):
		return int(will["all"])
	var total := 0
	for k in will:
		if str(k) == "all":
			continue
		total += int(will[k])
	return total


func compute_raid_loot(building: Node) -> int:
	var prov := find_province_for_building(building)
	if prov == null:
		return 0
	prov.recalculate_marks_will_by_player()
	prov.update_population_in_resources()
	var marks_will := province_predicted_marks_total(prov)
	var type_ = building.get("type_")
	if type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		return int(floor(float(marks_will) * 0.10))
	if type_ == GlobalStuff.BUILDING_TYPE.ECONOMY:
		return int(floor(float(marks_will) * 0.05))
	# Village / town: share of province output by settlement pop ratio.
	var sett_pop := int(building.get("population") if building.get("population") != null else 0)
	var prov_pop := province_total_population(prov)
	if prov_pop <= 0 or sett_pop <= 0:
		return 0
	return int(floor(float(marks_will) * float(sett_pop) / float(prov_pop)))


const RAZE_RECOVERY_SEASONS := 2
const RAID_SMOKE_INTENSITY := 0.35
const RAZE_SMOKE_INTENSITY_FULL := 1.0
const RAZE_SMOKE_INTENSITY_FADED := 0.45


func is_building_razed(building: Node) -> bool:
	if building == null or building.get("STAGES") == null:
		return false
	return building.stage == building.STAGES.RAZED


func can_raid_building(building: Node) -> bool:
	if building == null:
		return false
	if is_building_razed(building):
		return false
	var last_t := int(building.get_meta("last_raid_turn", -1))
	return last_t != turn


func can_raze_building(building: Node) -> bool:
	if building == null:
		return false
	var type_ = building.get("type_")
	if type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		return false
	if is_building_razed(building):
		return false
	return building.get("STAGES") != null


func do_battle_attack(attacker_id: String, defender_army_id: String, building: Node) -> void:
	var bkey := _building_key(building) if building != null else ""
	request_battle_attack.rpc_id(1, attacker_id, defender_army_id, bkey)


@rpc("any_peer", "call_local", "reliable")
func request_battle_attack(attacker_id: String, defender_army_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(attacker_id):
		return
	var building: Node = null
	if building_key != "":
		building = _building_from_key(building_key)
		if building == null:
			return
	elif defender_army_id == "" or not forces.has(defender_army_id):
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var atk_units: Array = forces[attacker_id]["units"]
	var def_units: Array = []
	var def_force_ids: Array = []
	if building != null:
		def_units = get_all_building_garrison(building)
		def_force_ids = _building_garrison_force_ids(building)
	else:
		def_units = forces[defender_army_id]["units"]
		def_force_ids = [defender_army_id]

	var atk_str := get_force_battle_strength_with_vips(attacker_id, def_force_ids)
	var def_str := 0
	if building != null:
		def_str = get_building_battle_strength_with_vips(building, [attacker_id])
	else:
		def_str = get_force_battle_strength_with_vips(defender_army_id, [attacker_id])

	if atk_str <= 0:
		return
	if def_str <= 0 and building != null:
		# Empty garrison — open actions instead (client should not request this).
		return

	var atk_eff := GlobalUnits.roll_effective_strength(atk_str, rng)
	var def_eff := GlobalUnits.roll_effective_strength(def_str, rng)
	var attacker_won := atk_eff >= def_eff

	var winner_str := atk_str if attacker_won else def_str
	var loser_str := def_str if attacker_won else atk_str
	# Winner takes fewer losses when dominating; loser takes more.
	var win_factor := GlobalUnits.casualty_factor(winner_str, loser_str)
	var lose_factor := GlobalUnits.loser_casualty_factor(winner_str, loser_str)
	var win_dead := GlobalUnits.BASE_DEAD_FRACTION * win_factor
	var win_wound := GlobalUnits.BASE_WOUND_FRACTION * win_factor
	var lose_dead := GlobalUnits.BASE_DEAD_FRACTION * lose_factor
	var lose_wound := GlobalUnits.BASE_WOUND_FRACTION * lose_factor

	var atk_result: Dictionary
	var def_result: Dictionary
	if attacker_won:
		atk_result = GlobalUnits.apply_side_casualties(atk_units, win_dead, win_wound)
		def_result = GlobalUnits.apply_side_casualties(def_units, lose_dead, lose_wound)
	else:
		def_result = GlobalUnits.apply_side_casualties(def_units, win_dead, win_wound)
		atk_result = GlobalUnits.apply_side_casualties(atk_units, lose_dead, lose_wound)

	var new_attacker: Array = []
	var new_defender: Array = []
	var hostage_pool: Array = []
	var destroy_attacker := false
	var destroy_defender_army := false
	var clear_garrison := false
	var captured_vip_ids: Array = []

	if attacker_won:
		new_attacker = GlobalUnits.merge_units(atk_result["remaining"], atk_result["wounded"])
		# Wipe defender: leftover fighters count as dead; wounded → hostage pool.
		hostage_pool = GlobalUnits.account_wiped_side(def_result, true)
		for fid in def_force_ids:
			for vid in get_vips_on_force(str(fid)):
				captured_vip_ids.append(vid)
		if building != null:
			clear_garrison = true
			new_defender = []
		else:
			destroy_defender_army = true
			new_defender = []
	else:
		# Attacker wiped; no one captures their wounded — count everyone lost as dead.
		GlobalUnits.account_wiped_side(atk_result, false)
		destroy_attacker = true
		new_attacker = []
		new_defender = GlobalUnits.merge_units(def_result["remaining"], def_result["wounded"])
		for vid in get_vips_on_force(attacker_id):
			captured_vip_ids.append(vid)

	var battle_event := _make_battle_event(
		attacker_id, defender_army_id, building, attacker_won,
		atk_units, def_units, atk_result, def_result, hostage_pool
	)
	battle_event["captured_vip_ids"] = captured_vip_ids.duplicate()

	apply_battle_result.rpc(
		attacker_id,
		defender_army_id,
		building_key,
		attacker_won,
		new_attacker,
		new_defender,
		destroy_attacker,
		destroy_defender_army,
		clear_garrison,
		hostage_pool,
		battle_event,
		captured_vip_ids
	)


@rpc("authority", "call_local", "reliable")
func apply_battle_result(
	attacker_id: String,
	defender_army_id: String,
	building_key: String,
	attacker_won: bool,
	new_attacker: Array,
	new_defender: Array,
	destroy_attacker: bool,
	destroy_defender_army: bool,
	clear_garrison: bool,
	hostage_pool: Array,
	battle_event: Dictionary,
	captured_vip_ids: Array = []
) -> void:
	var building: Node = _building_from_key(building_key) if building_key != "" else null

	# Move captured VIPs to the winner before wiping the loser, so cleanup does
	# not treat them as a normal disband relocation.
	if not captured_vip_ids.is_empty():
		if attacker_won and forces.has(attacker_id):
			move_vips_to_force(captured_vip_ids, attacker_id)
		elif not attacker_won:
			if building != null:
				move_vips_to_force(captured_vip_ids, ensure_building_vip_force(building))
			elif forces.has(defender_army_id):
				move_vips_to_force(captured_vip_ids, defender_army_id)

	if destroy_attacker:
		if forces.has(attacker_id):
			forces[attacker_id]["units"] = []
			_cleanup_force_if_empty(attacker_id)
	elif forces.has(attacker_id):
		forces[attacker_id]["units"] = GlobalUnits.units_from_spec(new_attacker)
		var afig = armies.get_node_or_null(attacker_id)
		if afig != null and afig.has_method("refresh_from_force"):
			afig.refresh_from_force()

	if building != null:
		if clear_garrison:
			_clear_building_garrison(building)
		elif attacker_won == false:
			_set_building_garrison_units(building, GlobalUnits.units_from_spec(new_defender))
	elif destroy_defender_army:
		if forces.has(defender_army_id):
			forces[defender_army_id]["units"] = []
			_cleanup_force_if_empty(defender_army_id)
	elif forces.has(defender_army_id):
		forces[defender_army_id]["units"] = GlobalUnits.units_from_spec(new_defender)
		var dfig = armies.get_node_or_null(defender_army_id)
		if dfig != null and dfig.has_method("refresh_from_force"):
			dfig.refresh_from_force()

	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	refresh_all_building_flags()
	refresh_all_vip_crowns()

	var event_id := _register_event(battle_event)
	var participants: Array = battle_event.get("participant_ids", [])
	var actor_id := int(battle_event.get("actor_id", -1))
	# Attacker opens the report after hostage fate is chosen (if any).
	var pending_hostages := str(battle_event.get("hostage_fate", "none")) == "pending"
	_deliver_event_to_players(event_id, participants, actor_id, not pending_hostages)

	if is_instance_valid(gui_node):
		gui_node.on_battle_resolved(
			self, attacker_id, building, attacker_won, hostage_pool, event_id
		)


func _clear_building_garrison(building: Node) -> void:
	var key := _building_key(building)
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	var spots: Array = [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE] if is_castle else [GlobalUnits.SPOT.FLAT]
	for spot in spots:
		var fid := _garrison_force_id(key, spot)
		if forces.has(fid):
			forces[fid]["units"] = []
			_cleanup_force_if_empty(fid)


func _set_building_garrison_units(building: Node, units: Array) -> void:
	_clear_building_garrison(building)
	var key := _building_key(building)
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	var spot := GlobalUnits.SPOT.OUTSIDE if is_castle else GlobalUnits.SPOT.FLAT
	var fid := _garrison_force_id(key, spot)
	forces[fid] = {
		"units": GlobalUnits.clone_units(units),
		"location": {"kind": "garrison", "building": key, "spot": spot},
	}


func do_take_hostages(attacker_id: String, hostage_pool: Array) -> void:
	request_take_hostages.rpc_id(1, attacker_id, hostage_pool)


func do_put_to_sword_pool(_hostage_pool: Array) -> void:
	# No state change beyond discarding the pool (already not in any force).
	pass


func resolve_battle_hostage_fate(event_id: String, fate: String) -> void:
	request_battle_hostage_fate.rpc_id(1, event_id, fate)


@rpc("any_peer", "call_local", "reliable")
func request_battle_hostage_fate(event_id: String, fate: String) -> void:
	if not multiplayer.is_server():
		return
	if fate != "taken" and fate != "sword":
		return
	if not game_events.has(event_id):
		return
	apply_battle_hostage_fate.rpc(event_id, fate)


@rpc("authority", "call_local", "reliable")
func apply_battle_hostage_fate(event_id: String, fate: String) -> void:
	if not game_events.has(event_id):
		return
	var event: Dictionary = game_events[event_id]
	if int(event.get("kind", -1)) != GameEvents.KIND.BATTLE:
		return
	event["hostage_fate"] = fate
	game_events[event_id] = event
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_msg_list_if_open"):
			gui_node.refresh_msg_list_if_open()
		var actor_id := int(event.get("actor_id", -1))
		if my_pl_id == actor_id and gui_node.has_method("open_event_report"):
			gui_node.open_event_report(self, event_id)


@rpc("any_peer", "call_local", "reliable")
func request_take_hostages(attacker_id: String, hostage_pool: Array) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(attacker_id):
		return
	apply_take_hostages.rpc(attacker_id, hostage_pool)


@rpc("authority", "call_local", "reliable")
func apply_take_hostages(attacker_id: String, hostage_pool: Array) -> void:
	if not forces.has(attacker_id):
		return
	var units: Array = forces[attacker_id]["units"]
	for s in GlobalUnits.units_from_spec(hostage_pool):
		var host := GlobalUnits.make_stack(
			int(s["type"]), int(s["owner"]), int(s["source"]), int(s["count"]),
			GlobalUnits.STATUS.HOSTAGE, GlobalUnits.HOSTAGE_RECOVER_SEASONS
		)
		GlobalUnits.add_stack(units, host)
	forces[attacker_id]["units"] = units
	var fig = armies.get_node_or_null(attacker_id)
	if fig != null and fig.has_method("refresh_from_force"):
		fig.refresh_from_force()


func do_put_stack_to_sword(force_id: String, stack_spec: Dictionary) -> void:
	request_put_stack_to_sword.rpc_id(1, force_id, stack_spec)


@rpc("any_peer", "call_local", "reliable")
func request_put_stack_to_sword(force_id: String, stack_spec: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	apply_put_stack_to_sword.rpc(force_id, stack_spec)


@rpc("authority", "call_local", "reliable")
func apply_put_stack_to_sword(force_id: String, stack_spec: Dictionary) -> void:
	if not forces.has(force_id):
		return
	var units: Array = forces[force_id]["units"]
	GlobalUnits.subtract_units(units, [stack_spec])
	forces[force_id]["units"] = units
	_cleanup_force_if_empty(force_id)
	var fig = armies.get_node_or_null(force_id)
	if fig != null and fig.has_method("refresh_from_force"):
		fig.refresh_from_force()
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


func do_offer_join(force_id: String, stack_spec: Dictionary) -> void:
	request_offer_join.rpc_id(1, force_id, stack_spec)


@rpc("any_peer", "call_local", "reliable")
func request_offer_join(force_id: String, stack_spec: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	apply_offer_join.rpc(force_id, stack_spec)


@rpc("authority", "call_local", "reliable")
func apply_offer_join(force_id: String, stack_spec: Dictionary) -> void:
	if not forces.has(force_id):
		return
	var units: Array = forces[force_id]["units"]
	for s in units:
		if int(s["type"]) != int(stack_spec["type"]):
			continue
		if int(s["owner"]) != int(stack_spec["owner"]):
			continue
		if int(s["source"]) != int(stack_spec["source"]):
			continue
		if GlobalUnits.stack_status(s) != GlobalUnits.STATUS.CAPTURED:
			continue
		if bool(s.get("join_pending", false)):
			continue
		s["join_pending"] = true
		break
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


func do_capture_building(force_id: String, building: Node) -> void:
	request_capture_building.rpc_id(1, force_id, _building_key(building))


func do_raid_building(force_id: String, building: Node) -> void:
	request_raid_building.rpc_id(1, force_id, _building_key(building))


func do_raze_building(force_id: String, building: Node) -> void:
	request_raze_building.rpc_id(1, force_id, _building_key(building))


@rpc("any_peer", "call_local", "reliable")
func request_capture_building(force_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	var building = _building_from_key(building_key)
	if building == null:
		return
	var capturer := get_force_controller(force_id)
	var previous_owner := int(building.player_owner) if building.get("player_owner") != null else -1
	var capture_event := _make_building_capture_event(building, previous_owner, capturer)
	apply_capture_building.rpc(building_key, capturer, capture_event)


@rpc("authority", "call_local", "reliable")
func apply_capture_building(building_key: String, capturer: int, capture_event: Dictionary = {}) -> void:
	var building = _building_from_key(building_key)
	if building == null:
		return
	var previous_owner := int(building.player_owner) if building.get("player_owner") != null else -1
	var prov := find_province_for_building(building)
	# Split grain/horse holding stock by field share before ownership flips.
	if prov != null and previous_owner >= 0 and capturer >= 0 and previous_owner != capturer:
		if building.get("fields") != null and prov.has_method("transfer_holding_stock_for_settlement"):
			prov.transfer_holding_stock_for_settlement(building, previous_owner, capturer)
	building.player_owner = capturer
	if building.has_method("set_flags"):
		building.set_flags()
	if prov != null:
		prov.recompute_control()
		if prov.has_method("update_population_in_resources"):
			prov.update_population_in_resources()
		if prov.has_method("recalculate_marks_will_by_player"):
			prov.recalculate_marks_will_by_player()
		if capturer >= 0 and prov.has_method("ensure_holding"):
			prov.ensure_holding(capturer)
	refresh_all_building_flags()
	if province_borders != null and province_borders.has_method("rebuild"):
		province_borders.rebuild()
	update_players_population()
	var event: Dictionary = capture_event
	if event.is_empty():
		event = _make_building_capture_event(building, previous_owner, capturer)
	var event_id := _register_event(event)
	var recipients: Array = []
	if capturer >= 0:
		recipients.append(capturer)
	var prev := int(event.get("previous_owner", previous_owner))
	if prev >= 0 and prev != capturer:
		recipients.append(prev)
	_deliver_event_to_players(event_id, recipients, capturer)
	# Holding appears in economy list immediately for capturer / previous owner.
	if my_pl_id == capturer or my_pl_id == prev:
		update_menus()


@rpc("any_peer", "call_local", "reliable")
func request_raid_building(force_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	var building = _building_from_key(building_key)
	if building == null or not can_raid_building(building):
		return
	var loot := compute_raid_loot(building)
	var raider := get_force_controller(force_id)
	apply_raid_building.rpc(building_key, raider, loot, turn)


@rpc("authority", "call_local", "reliable")
func apply_raid_building(building_key: String, raider: int, loot: int, raid_turn: int) -> void:
	var building = _building_from_key(building_key)
	if building == null or is_building_razed(building):
		return
	building.set_meta("last_raid_turn", raid_turn)
	if players.has(raider):
		players[raider].game_data["marks"] = int(players[raider].game_data.get("marks", 0)) + loot
	var type_ = building.get("type_")
	if type_ == GlobalStuff.BUILDING_TYPE.VILLAGE or type_ == GlobalStuff.BUILDING_TYPE.TOWN:
		if building.get("population") != null:
			building.population = int(floor(float(building.population) * 0.5))
			if building.has_method("calculate_predicted_marks"):
				building.calculate_predicted_marks()
			if building.has_method("calculate_predicted_growth"):
				building.calculate_predicted_growth()
		var prov := find_province_for_building(building)
		if prov != null:
			prov.update_population_in_resources()
			prov.recalculate_marks_will_by_player()
	# Light smoke for one season (cleared on next season tick if not razed).
	building.set_meta("smoke_kind", "raid")
	_attach_building_smoke(building, RAID_SMOKE_INTENSITY)
	if is_instance_valid(gui_node):
		gui_node.show_info_popup("Raid yielded %d marks" % loot)
		if players.has(my_pl_id):
			gui_node.update_money(players[my_pl_id].game_data["marks"])


@rpc("any_peer", "call_local", "reliable")
func request_raze_building(force_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	var building = _building_from_key(building_key)
	if building == null or not can_raze_building(building):
		return
	apply_raze_building.rpc(building_key)


@rpc("authority", "call_local", "reliable")
func apply_raze_building(building_key: String) -> void:
	var building = _building_from_key(building_key)
	if building == null or not can_raze_building(building):
		return
	building.stage = building.STAGES.RAZED
	building.set_meta("raze_seasons_left", RAZE_RECOVERY_SEASONS)
	building.set_meta("smoke_kind", "raze")
	if building.has_method("update_for_stage"):
		building.update_for_stage()
	if building.has_method("get_start_data"):
		building.get_start_data()
	elif building.get("population") != null:
		building.population = 0
	_clear_building_garrison(building)
	var prov := find_province_for_building(building)
	if prov != null:
		prov.update_population_in_resources()
		prov.recalculate_marks_will_by_player()
	_attach_building_smoke(building, RAZE_SMOKE_INTENSITY_FULL)
	if is_instance_valid(gui_node):
		gui_node.show_info_popup("Building razed")


const RAID_SMOKE_SCRIPT := preload("res://objects/overworld/othr/raid_smoke/raid_smoke.gd")


func _attach_building_smoke(building: Node, intensity: float) -> void:
	_clear_building_smoke(building)
	var smoke := Node2D.new()
	smoke.name = "RaidSmoke"
	smoke.set_script(RAID_SMOKE_SCRIPT)
	smoke.intensity = clampf(intensity, 0.0, 1.0)
	building.add_child(smoke)
	smoke.position = Vector2(32, 8)


func _clear_building_smoke(building: Node) -> void:
	if building == null:
		return
	var smoke = building.get_node_or_null("RaidSmoke")
	if smoke != null:
		building.remove_child(smoke)
		smoke.queue_free()


func _set_building_smoke_intensity(building: Node, intensity: float) -> void:
	var smoke = building.get_node_or_null("RaidSmoke")
	if smoke != null and smoke.has_method("set_intensity"):
		smoke.set_intensity(intensity)
	else:
		_attach_building_smoke(building, intensity)


func clear_expired_raid_smoke() -> void:
	for prov in provinces.get_children():
		for container_name in ["settlements", "economy", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				if str(b.get_meta("smoke_kind", "")) == "raze":
					continue  # razed smoke fades via tick_razed_buildings
				var last_t := int(b.get_meta("last_raid_turn", -1))
				if last_t >= 0 and last_t != turn:
					_clear_building_smoke(b)
					if b.has_meta("smoke_kind"):
						b.remove_meta("smoke_kind")


func tick_razed_buildings() -> void:
	for prov in provinces.get_children():
		var changed := false
		for container_name in ["settlements", "economy", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				if not is_building_razed(b):
					continue
				changed = true
				var left := int(b.get_meta("raze_seasons_left", 0))
				if left > 0:
					left -= 1
					b.set_meta("raze_seasons_left", left)
				if left <= 0:
					# Rebuild only if owner also holds de jure on this province.
					if can_restore_razed_building(b, prov):
						_restore_razed_building(b)
					else:
						# Ready to rebuild, waiting for de jure + ownership.
						b.set_meta("raze_seasons_left", 0)
						_set_building_smoke_intensity(b, RAZE_SMOKE_INTENSITY_FADED)
				else:
					var intensity := RAZE_SMOKE_INTENSITY_FADED if left <= 1 else RAZE_SMOKE_INTENSITY_FULL
					_set_building_smoke_intensity(b, intensity)
		if changed:
			if prov.has_method("update_population_in_resources"):
				prov.update_population_in_resources()
			if prov.has_method("recalculate_marks_will_by_player"):
				prov.recalculate_marks_will_by_player()


func can_restore_razed_building(building: Node, prov: Node = null) -> bool:
	if building == null or not is_building_razed(building):
		return false
	if prov == null:
		prov = find_province_for_building(building)
	if prov == null:
		return false
	if prov.has_method("can_rebuild_building"):
		return prov.can_rebuild_building(building)
	return false


## Called after control changes (e.g. capturing the seat) so eligible razed buildings recover immediately.
func try_restore_razed_in_province(prov: Node) -> void:
	if prov == null:
		return
	var changed := false
	for container_name in ["settlements", "economy", "defense"]:
		var container = prov.get_node_or_null(container_name)
		if container == null:
			continue
		for b in container.get_children():
			if not is_building_razed(b):
				continue
			if int(b.get_meta("raze_seasons_left", 0)) > 0:
				continue
			if can_restore_razed_building(b, prov):
				_restore_razed_building(b)
				changed = true
	if changed:
		if prov.has_method("update_population_in_resources"):
			prov.update_population_in_resources()
		if prov.has_method("recalculate_marks_will_by_player"):
			prov.recalculate_marks_will_by_player()


func _restore_razed_building(building: Node) -> void:
	if building == null or building.get("STAGES") == null:
		return
	var type_ = building.get("type_")
	if type_ == GlobalStuff.BUILDING_TYPE.ECONOMY:
		building.stage = building.STAGES.EMPTY
	else:
		building.stage = building.STAGES.SMALL
	if building.has_meta("raze_seasons_left"):
		building.remove_meta("raze_seasons_left")
	if building.has_meta("smoke_kind"):
		building.remove_meta("smoke_kind")
	_clear_building_smoke(building)
	if building.has_method("update_for_stage"):
		building.update_for_stage()
	if building.has_method("get_start_data"):
		building.get_start_data()
	elif building.get("population") != null:
		building.population = 0


func tick_all_force_seasons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for fid in forces.keys():
		var entry = forces[fid]
		var controller := int(entry.get("controller", -1))
		if controller < 0:
			controller = GlobalUnits.primary_owner(entry["units"])
		var join_results: Array = []
		entry["units"] = GlobalUnits.tick_stack_seasons(entry["units"], rng, controller, join_results)
		for jr in join_results:
			var event := _make_join_event(str(fid), controller, jr)
			var event_id := _register_event(event)
			if controller >= 0:
				_deliver_event_to_players(event_id, [controller], int(event.get("actor_id", -1)))
		_cleanup_force_if_empty(fid)
		var fig = armies.get_node_or_null(fid)
		if fig != null and fig.has_method("refresh_from_force"):
			fig.refresh_from_force()


func show_army_owner_popup(army: Node2D) -> void:
	gui_node.show_info_popup(army_roster_text(army))


# Multi-line summary of an army's roster, split per owning player.
func army_roster_text(army: Node2D) -> String:
	var units: Array = army.get_units()
	var lines: PackedStringArray = []
	for pid in GlobalUnits.owners_in(units):
		var owner_name := str(players[pid].name_) if players.has(pid) else "Unknown"
		var owner_units: Array = []
		for s in units:
			if int(s["owner"]) == pid:
				owner_units.append(s)
		lines.append("[%s] %d men, str %d" % [owner_name, GlobalUnits.total_men(owner_units), GlobalUnits.total_strength(owner_units)])
		for s in owner_units:
			lines.append("  %d %s (%s)" % [int(s["count"]), GlobalUnits.unit_name(s["type"]), GlobalUnits.source_name(s["source"])])
	if lines.is_empty():
		return "Empty army"
	return "\n".join(lines)


# --- Building info popups (hover 2s = transient; click = pinned) ---

func _is_army_selected() -> bool:
	return pathfinding != null and pathfinding.selected_army != null


func _process(delta: float) -> void:
	_update_camera_province_focus()
	if _hover_candidate == null:
		return
	# An army being selected reserves clicks/hover for movement/attack orders.
	if _is_army_selected() or gui_node.is_building_popup_pinned():
		_hover_candidate = null
		return
	_hover_elapsed += delta
	if _hover_elapsed >= BUILDING_HOVER_DELAY:
		var b := _hover_candidate
		_hover_candidate = null
		gui_node.show_building_popup(b, _building_display_name(b), _building_display_body(b), false)


func on_building_hover_start(building: Node2D) -> void:
	if is_mouse_over_gui():
		return
	if _is_army_selected() or gui_node.is_building_popup_pinned():
		return
	_hover_candidate = building
	_hover_elapsed = 0.0


func on_building_hover_end(building: Node2D) -> void:
	if _hover_candidate == building:
		_hover_candidate = null
	# Transient (unpinned) popup disappears the moment its building is unhovered.
	if gui_node.get_building_popup_node() == building and not gui_node.is_building_popup_pinned():
		gui_node.hide_building_popup()


# Returns true if the click was consumed (popup shown). If an army is selected,
# returns false so the click falls through to army movement/attack pathing.
func on_building_clicked(building: Node2D) -> bool:
	if should_suppress_building_click():
		return true
	if is_mouse_over_gui():
		return true
	if _is_army_selected():
		# Clicking a garrisonable building with an army selected either opens
		# the garrison/battle UI (when already adjacent) or moves the army
		# toward the building first (when too far away).
		if building.has_method("get_garrison_capacity"):
			var army = pathfinding.selected_army
			var army_cell = pathfinding.get_army_cell(army)
			var approach_cells = pathfinding.get_approach_cells(building)
			if army_cell in approach_cells:
				# Army is adjacent – check it has MP to spend.
				if army.movement_left <= 0:
					gui_node.show_info_popup("No movement points left")
					pathfinding.deselect_army()
					return true
				_hover_candidate = null
				gui_node.hide_building_popup()
				pathfinding.deselect_army()
				# Same click may also hit pathfinding; don't let a second pass
				# open the building info card after deselect.
				suppress_building_click_this_frame()
				open_army_building_interaction(army.force_id, building)
				return true
			# Not adjacent yet – move toward the building (opens interaction
			# on arrival when MP remains).
			return pathfinding.confirm_move_to_building(building)
		return false
	# Force transfer UI already up from this click's move — don't replace it
	# with the empty building info card.
	if gui_node.is_force_menu_open():
		return true
	_hover_candidate = null
	set_sticky_province_from_building(building)
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT:
		_on_merchant_clicked(building)
		return true
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.SELLSWORDS:
		_on_sellswords_clicked(building)
		return true
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.FIELD:
		if gui_node.has_method("show_field_popup"):
			gui_node.show_field_popup(self, building)
		else:
			gui_node.show_building_popup(building, _building_display_name(building), _building_display_body(building), true)
		return true
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.ECONOMY:
		if gui_node.has_method("show_economy_building_popup"):
			gui_node.show_economy_building_popup(self, building)
		else:
			gui_node.show_building_popup(building, _building_display_name(building), _building_display_body(building), true)
		return true
	var has_own_garrison := (building.has_method("get_garrison_capacity")
		and not get_player_garrison(building, my_pl_id).is_empty())
	var deploy_cb := Callable()
	if has_own_garrison:
		deploy_cb = func(): gui_node.open_deploy_menu(self, building, my_pl_id)
	gui_node.show_building_popup(building, _building_display_name(building), _building_display_body(building), true, deploy_cb)
	return true


func _on_merchant_clicked(merchant: Node2D) -> void:
	var prov = merchant.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(my_pl_id):
		gui_node.show_info_popup("Only the de jure owner can view the merchant")
		return
	gui_node.open_merchant_shop(self, merchant)


func _on_sellswords_clicked(band: Node2D) -> void:
	var prov = band.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(my_pl_id):
		gui_node.show_info_popup("Only the de jure owner can hire these sellswords")
		return
	gui_node.open_sellswords_hire(self, band)


func _building_display_name(b: Node2D) -> String:
	if b.get("type_") != null:
		match b.type_:
			GlobalStuff.BUILDING_TYPE.VILLAGE: return "Village"
			GlobalStuff.BUILDING_TYPE.TOWN: return "Town"
			GlobalStuff.BUILDING_TYPE.CASTLE: return "Castle"
			GlobalStuff.BUILDING_TYPE.FIELD: return "Field"
			GlobalStuff.BUILDING_TYPE.MERCHANT: return "Merchant"
			GlobalStuff.BUILDING_TYPE.SELLSWORDS: return "Sellswords"
			GlobalStuff.BUILDING_TYPE.ECONOMY:
				if b.has_method("get_subtype_name"):
					return b.get_subtype_name()
				return "Economy Building"
	return "Building"


func _building_display_body(b: Node2D) -> String:
	var lines := PackedStringArray()
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT:
		var prov = b.get("province")
		var pname := "Unknown"
		if prov != null and prov.get("p_name") != null:
			pname = str(prov.p_name)
		lines.append("Province: %s" % pname)
		lines.append("Staying: %d season(s)" % int(b.get("seasons_left")))
		if merchant_competition_in_province(prov):
			lines.append("Competition: 15% discount")
		return "\n".join(lines)
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.SELLSWORDS:
		var prov_ss = b.get("province")
		var pname_ss := "Unknown"
		if prov_ss != null and prov_ss.get("p_name") != null:
			pname_ss = str(prov_ss.p_name)
		lines.append("Province: %s" % pname_ss)
		lines.append("Staying: %d season(s)" % int(b.get("seasons_left")))
		var offer: Array = b.get("offer") if b.get("offer") != null else []
		for entry in offer:
			var ut := int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT))
			var cnt := int(entry.get("count", 0))
			var cost := GlobalUnits.sellsword_stack_mark_price(ut, cnt)
			lines.append("%d %s — %d marks" % [cnt, GlobalUnits.unit_name(ut), cost])
		lines.append("Total: %d marks" % GlobalUnits.sellsword_offer_mark_price(offer))
		return "\n".join(lines)
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.FIELD:
		var owner_name := "Unowned"
		var owner_building = b.get("owner_building")
		if owner_building != null and owner_building.get("player_owner") != null:
			if players.has(owner_building.player_owner):
				owner_name = str(players[owner_building.player_owner].name_)
		lines.append("Owner: %s" % owner_name)
		if b.has_method("get_crop_name"):
			lines.append("Use: %s" % b.get_crop_name())
		if b.get("crop") != null and int(b.crop) == 1: # GRAIN
			if bool(b.get("planted")):
				lines.append("Grain: growing (seed spent)")
			elif int(season) == 0:
				lines.append("Grain: needs %d seed to sow" % GlobalUnits.GRAIN_SEED_PER_FIELD)
			else:
				lines.append("Grain: waits for winter (needs %d seed)" % GlobalUnits.GRAIN_SEED_PER_FIELD)
			lines.append("Care: %d people/field · yield %d" % [
				GlobalUnits.PEOPLE_PER_GRAIN_FIELD,
				GlobalUnits.GRAIN_YIELD_PER_FIELD,
			])
		if bool(b.get("neglected")):
			lines.append("Neglected (underworked)")
	elif b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.ECONOMY:
		if b.has_method("get_slot_description"):
			lines.append(b.get_slot_description())
		var eowner := "Unowned"
		if b.get("player_owner") != null and players.has(b.player_owner):
			eowner = str(players[b.player_owner].name_)
		lines.append("Owner: %s" % eowner)
		if b.has_method("is_built") and b.is_built():
			lines.append("Workers cap: %d" % int(b.worker_cap()))
			var cat := str(b.labor_category())
			if cat == "blacksmith":
				var wkey := str(b.get_craft_weapon()) if b.has_method("get_craft_weapon") else ""
				if wkey == "":
					lines.append("Crafting: idle (no recipe)")
				else:
					lines.append("Crafting: %s" % GlobalUnits.blacksmith_recipe_label(wkey))
			elif cat != "":
				lines.append("Labor category: %s" % cat)
		else:
			lines.append("Empty — de jure can build here")
	elif b.get("player_owner") != null:
		var owner_name := "Unowned"
		if players.has(b.player_owner):
			owner_name = str(players[b.player_owner].name_)
		lines.append("Owner: %s" % owner_name)
	if b.has_method("get_stage_name"):
		var stage_name: String = b.get_stage_name()
		if stage_name != "":
			lines.append("Stage: %s" % stage_name)
	if b.get("population") != null:
		lines.append("Population: %s" % str(b.population))
	if b.get("predicted_marks") != null:
		lines.append("Income: %s marks" % str(b.predicted_marks))
	if b.has_method("get_garrison_capacity"):
		lines.append(_building_garrison_text(b))
	var vip_ids := get_building_vip_ids(b)
	if not vip_ids.is_empty():
		var vip_names: PackedStringArray = []
		for vid in vip_ids:
			vip_names.append(vip_display_name(str(vid)))
		lines.append("VIP: %s" % ", ".join(vip_names))
	if lines.is_empty():
		return "—"
	return "\n".join(lines)


func _building_garrison_text(b: Node) -> String:
	var out: PackedStringArray = []
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		out.append(_garrison_line("Inside", get_building_garrison(b, GlobalUnits.SPOT.INSIDE), b.get_inside_capacity(), GlobalUnits.CASTLE_INSIDE_BONUS))
		out.append(_garrison_line("Outside", get_building_garrison(b, GlobalUnits.SPOT.OUTSIDE), b.get_outside_capacity(), 1.0))
	else:
		out.append(_garrison_line("Garrison", get_building_garrison(b, GlobalUnits.SPOT.FLAT), b.get_garrison_capacity(), 1.0))
	return "\n".join(out)


func _garrison_line(label: String, units: Array, capacity: int, strength_mult: float) -> String:
	var men := GlobalUnits.total_men(units)
	if men == 0:
		return "%s: 0/%d" % [label, capacity]
	return "%s: %d/%d (str %d)" % [label, men, capacity, GlobalUnits.total_strength(units, strength_mult)]


@rpc("any_peer", "call_local", "reliable")
func request_army_move(army_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	if !multiplayer.is_server():
		return
	var army = armies.get_node_or_null(army_name)
	if army == null:
		return
	steps = clampi(steps, 0, army.movement_left)
	if steps <= 0:
		return
	# Two armies cannot share a cell — reject landing on another force.
	var dest := Vector2i(cell_x, cell_y)
	if pathfinding.occupancy.has(dest) and pathfinding.occupancy[dest] != army:
		return
	apply_army_move.rpc(army_name, cell_x, cell_y, steps)


func set_pending_garrison(army_name: String, force_id: String, building: Node) -> void:
	clear_pending_army_interaction()
	_pending_garrison_army_name = army_name
	_pending_garrison_force_id = force_id
	_pending_garrison_building = building


func clear_pending_garrison() -> void:
	_pending_garrison_army_name = ""
	_pending_garrison_force_id = ""
	_pending_garrison_building = null


func set_pending_army_interaction(mover_name: String, target: Node2D) -> void:
	clear_pending_garrison()
	_pending_army_interaction_mover_name = mover_name
	_pending_army_interaction_target = target


func clear_pending_army_interaction() -> void:
	_pending_army_interaction_mover_name = ""
	_pending_army_interaction_target = null


@rpc("authority", "call_local", "reliable")
func apply_army_move(army_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	var army = armies.get_node_or_null(army_name)
	if army == null:
		clear_pending_garrison()
		clear_pending_army_interaction()
		return
	pathfinding.place_army_at_cell(army, Vector2i(cell_x, cell_y))
	army.movement_left -= steps
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	_try_open_pending_garrison(army_name)
	_try_open_pending_army_interaction(army_name)


func _try_open_pending_garrison(army_name: String) -> void:
	if _pending_garrison_army_name != army_name:
		return
	var building := _pending_garrison_building
	var force_id := _pending_garrison_force_id
	clear_pending_garrison()
	if building == null or not is_instance_valid(building):
		return
	var army = armies.get_node_or_null(army_name)
	if army == null or not army.is_controllable_by(my_pl_id):
		return
	if army.movement_left <= 0:
		return
	var army_cell = pathfinding.get_army_cell(army)
	if army_cell not in pathfinding.get_approach_cells(building):
		return
	gui_node.hide_building_popup()
	# Defer so this opens after the current click finishes — otherwise the
	# building Area2D can still see the same click (army already deselected)
	# and replace the transfer UI with the empty info card.
	call_deferred("open_army_building_interaction", force_id, building)


func _try_open_pending_army_interaction(army_name: String) -> void:
	if _pending_army_interaction_mover_name != army_name:
		return
	var target := _pending_army_interaction_target
	clear_pending_army_interaction()
	if target == null or not is_instance_valid(target):
		return
	var army = armies.get_node_or_null(army_name)
	if army == null or not army.is_controllable_by(my_pl_id):
		return
	if army.movement_left <= 0:
		return
	if not pathfinding.are_armies_adjacent(army, target):
		return
	# Defer past the click that completed the move.
	call_deferred("_on_army_interaction", army, target)


# --- Force mutations (merge / split / garrison), server-authoritative --------

# Merge the whole of source_id into target_id; source figure is removed.
@rpc("any_peer", "call_local", "reliable")
func request_merge_forces(target_id: String, source_id: String) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(target_id) or not forces.has(source_id):
		return
	apply_merge_forces.rpc(target_id, source_id)


@rpc("authority", "call_local", "reliable")
func apply_merge_forces(target_id: String, source_id: String) -> void:
	if not forces.has(target_id) or not forces.has(source_id):
		return
	forces[target_id]["units"] = GlobalUnits.merge_units(forces[target_id]["units"], forces[source_id]["units"])
	transfer_all_vips(source_id, target_id)
	# Merged army gets the lower of the two MP values — can't refresh by merging.
	var sfig = armies.get_node_or_null(source_id)
	var tfig = armies.get_node_or_null(target_id)
	if sfig != null and tfig != null:
		tfig.movement_left = mini(tfig.movement_left, sfig.movement_left)
	forces.erase(source_id)
	if sfig != null:
		armies.remove_child(sfig)
		sfig.queue_free()
	if tfig != null:
		tfig.refresh_from_force()
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	refresh_all_vip_crowns()


# Split out_units off source_id into a NEW mobile army placed at (cell).
# withdraw=true: a guest player peels off only their troops (no MP cost).
@rpc("any_peer", "call_local", "reliable")
func request_split_force(source_id: String, out_units: Array, cell_x: int, cell_y: int, withdraw: bool = false, withdraw_player: int = -1) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(source_id):
		return
	var sfig = armies.get_node_or_null(source_id)
	if sfig == null:
		return
	var split_men := GlobalUnits.total_men(GlobalUnits.units_from_spec(out_units))
	if split_men <= 0:
		return

	var master_mp: int
	var spawned_mp: int
	if withdraw:
		if withdraw_player < 0 or not GlobalUnits.all_owned_by(out_units, withdraw_player):
			return
		master_mp = sfig.movement_left
		spawned_mp = 0
	else:
		# Server validation: need ≥1 MP to split; both halves must have ≥ MIN_SPLIT_MEN.
		if sfig.movement_left < 1:
			return
		var total_men := GlobalUnits.total_men(forces[source_id]["units"])
		var remainder := total_men - split_men
		if split_men < GlobalUnits.MIN_SPLIT_MEN or remainder < GlobalUnits.MIN_SPLIT_MEN:
			return
		# Proportional MP: 1 MP is "spent on the split step"; distribute the rest.
		var pool: int = sfig.movement_left - 1
		spawned_mp = int(floor(float(pool) * split_men / float(total_men)))
		master_mp = pool - spawned_mp

	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	var new_controller := withdraw_player if withdraw else GlobalUnits.primary_owner(GlobalUnits.units_from_spec(out_units))
	apply_split_force.rpc(source_id, new_id, out_units, cell_x, cell_y, master_mp, spawned_mp, new_controller)


@rpc("authority", "call_local", "reliable")
func apply_split_force(source_id: String, new_id: String, out_units: Array, cell_x: int, cell_y: int, master_mp: int, spawned_mp: int, new_controller: int = -1) -> void:
	if not forces.has(source_id):
		return
	GlobalUnits.subtract_units(forces[source_id]["units"], out_units)
	var sfig = armies.get_node_or_null(source_id)
	if sfig != null:
		sfig.movement_left = master_mp
		sfig.refresh_from_force()
	var controller := new_controller
	if controller < 0:
		controller = GlobalUnits.primary_owner(GlobalUnits.units_from_spec(out_units))
	_spawn_army_figure(new_id, GlobalUnits.units_from_spec(out_units), Vector2i(cell_x, cell_y), spawned_mp, controller)
	_cleanup_force_if_empty(source_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


# Transfer out_units between two EXISTING forces (army<->army, garrison->army).
@rpc("any_peer", "call_local", "reliable")
func request_transfer_units(source_id: String, dest_id: String, out_units: Array) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(source_id) or not forces.has(dest_id):
		return
	apply_transfer_units.rpc(source_id, dest_id, out_units)


@rpc("authority", "call_local", "reliable")
func apply_transfer_units(source_id: String, dest_id: String, out_units: Array) -> void:
	if not forces.has(source_id) or not forces.has(dest_id):
		return
	GlobalUnits.subtract_units(forces[source_id]["units"], out_units)
	forces[dest_id]["units"] = GlobalUnits.merge_units(forces[dest_id]["units"], GlobalUnits.units_from_spec(out_units))
	for fid in [source_id, dest_id]:
		var f = armies.get_node_or_null(fid)
		if f != null:
			f.refresh_from_force()
	_cleanup_force_if_empty(source_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


@rpc("any_peer", "call_local", "reliable")
func request_batch_transfer_units(left_id: String, right_id: String, left_to_right: Array, right_to_left: Array) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(left_id) or not forces.has(right_id):
		return
	var left_after := GlobalUnits.clone_units(forces[left_id]["units"])
	var right_after := GlobalUnits.clone_units(forces[right_id]["units"])
	GlobalUnits.subtract_units(left_after, left_to_right)
	GlobalUnits.subtract_units(right_after, right_to_left)
	left_after = GlobalUnits.merge_units(left_after, GlobalUnits.units_from_spec(right_to_left))
	right_after = GlobalUnits.merge_units(right_after, GlobalUnits.units_from_spec(left_to_right))
	var left_men := GlobalUnits.total_men(left_after)
	var right_men := GlobalUnits.total_men(right_after)
	if left_men > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
		return
	if right_men > 0 and right_men < GlobalUnits.MIN_SPLIT_MEN:
		return
	# Armies that keep VIPs must retain ≥ MIN_SPLIT_MEN.
	if force_has_any_vip(left_id) and left_men > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
		return
	if force_has_any_vip(left_id) and left_men == 0:
		return
	if force_has_any_vip(right_id) and right_men > 0 and right_men < GlobalUnits.MIN_SPLIT_MEN:
		return
	if force_has_any_vip(right_id) and right_men == 0:
		return
	apply_batch_transfer_units.rpc(left_id, right_id, left_to_right, right_to_left)


@rpc("authority", "call_local", "reliable")
func apply_batch_transfer_units(left_id: String, right_id: String, left_to_right: Array, right_to_left: Array) -> void:
	if not forces.has(left_id) or not forces.has(right_id):
		return
	if not left_to_right.is_empty():
		GlobalUnits.subtract_units(forces[left_id]["units"], left_to_right)
		forces[right_id]["units"] = GlobalUnits.merge_units(forces[right_id]["units"], GlobalUnits.units_from_spec(left_to_right))
	if not right_to_left.is_empty():
		GlobalUnits.subtract_units(forces[right_id]["units"], right_to_left)
		forces[left_id]["units"] = GlobalUnits.merge_units(forces[left_id]["units"], GlobalUnits.units_from_spec(right_to_left))
	for fid in [left_id, right_id]:
		var f = armies.get_node_or_null(fid)
		if f != null:
			f.refresh_from_force()
	_cleanup_force_if_empty(left_id)
	_cleanup_force_if_empty(right_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


@rpc("any_peer", "call_local", "reliable")
func request_batch_garrison_units(source_id: String, building_key: String, spot: int, to_garrison: Array, from_garrison: Array) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(source_id):
		return
	var sfig = armies.get_node_or_null(source_id)
	if sfig == null:
		return
	if to_garrison.is_empty() and from_garrison.is_empty():
		return
	if not to_garrison.is_empty() and sfig.movement_left < 1:
		return

	var gid := _garrison_force_id(building_key, spot)
	var garrison_units: Array = forces[gid]["units"] if forces.has(gid) else []
	var left_after := GlobalUnits.clone_units(forces[source_id]["units"])
	var garrison_after := GlobalUnits.clone_units(garrison_units)
	GlobalUnits.subtract_units(left_after, to_garrison)
	GlobalUnits.subtract_units(garrison_after, from_garrison)
	garrison_after = GlobalUnits.merge_units(garrison_after, GlobalUnits.units_from_spec(to_garrison))
	left_after = GlobalUnits.merge_units(left_after, GlobalUnits.units_from_spec(from_garrison))

	var left_men := GlobalUnits.total_men(left_after)
	if left_men > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
		return

	var b := _building_from_key(building_key)
	if b == null or not b.has_method("get_garrison_capacity"):
		return
	var cap: int = b.get_garrison_capacity(spot)
	if GlobalUnits.total_men(garrison_after) > cap:
		return

	apply_batch_garrison_units.rpc(source_id, building_key, spot, to_garrison, from_garrison)


@rpc("authority", "call_local", "reliable")
func apply_batch_garrison_units(source_id: String, building_key: String, spot: int, to_garrison: Array, from_garrison: Array) -> void:
	if not forces.has(source_id):
		return
	var gid := _garrison_force_id(building_key, spot)

	if not to_garrison.is_empty():
		GlobalUnits.subtract_units(forces[source_id]["units"], to_garrison)
		if forces.has(gid):
			forces[gid]["units"] = GlobalUnits.merge_units(forces[gid]["units"], GlobalUnits.units_from_spec(to_garrison))
		else:
			forces[gid] = {
				"units": GlobalUnits.units_from_spec(to_garrison),
				"location": {"kind": "garrison", "building": building_key, "spot": spot}
			}

	if not from_garrison.is_empty() and forces.has(gid):
		GlobalUnits.subtract_units(forces[gid]["units"], from_garrison)
		forces[source_id]["units"] = GlobalUnits.merge_units(forces[source_id]["units"], GlobalUnits.units_from_spec(from_garrison))

	var sfig = armies.get_node_or_null(source_id)
	if sfig != null:
		if not to_garrison.is_empty():
			sfig.movement_left = maxi(0, sfig.movement_left - 1)
		sfig.refresh_from_force()
	_cleanup_force_if_empty(source_id)
	_cleanup_force_if_empty(gid)
	pathfinding.rebuild_occupancy()
	refresh_building_flags(building_key)
	update_all_army_visuals()


# --- Public helpers the GUI force/garrison menu calls -----------------------

func get_building_key(b: Node) -> String:
	return _building_key(b)


func garrison_force_id_for(b: Node, spot: int) -> String:
	return _garrison_force_id(_building_key(b), spot)


func do_transfer(source_id: String, dest_id: String, out_units: Array) -> void:
	request_transfer_units.rpc_id(1, source_id, dest_id, out_units)


func do_merge_all(target_id: String, source_id: String) -> void:
	request_merge_forces.rpc_id(1, target_id, source_id)


func do_garrison_in(source_id: String, b: Node, spot: int, out_units: Array) -> void:
	request_garrison_units.rpc_id(1, source_id, _building_key(b), spot, out_units)


func do_deploy_all_garrison(b: Node) -> void:
	var approach := get_free_approach_cell_for(b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		gui_node.show_info_popup("No free tile adjacent to building")
		return
	request_deploy_all_garrison.rpc_id(1, _building_key(b), my_pl_id)


func do_sortie(b: Node, spot: int, out_units: Array) -> void:
	var approach := get_free_approach_cell_for(b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		gui_node.show_info_popup("No free tile adjacent to building")
		return
	request_sortie_units.rpc_id(1, _building_key(b), spot, out_units, approach.x, approach.y)


# Returns the nearest walkable, unoccupied approach cell next to a building node
# that is also pathfindably connected to the rest of the map (i.e. not a pocket).
# Returns Vector2i(0x7FFFFFFF, 0x7FFFFFFF) when none exists.
func get_free_approach_cell_for(b: Node) -> Vector2i:
	var approach_cells = pathfinding.get_approach_cells(b)
	var anchor := _get_any_connected_cell(b)
	for cell in approach_cells:
		if pathfinding.occupancy.has(cell):
			continue
		# If we found an anchor elsewhere on the map, verify this cell can
		# actually reach it through the AStar graph (not a boxed-in pocket).
		if anchor != Vector2i(0x7FFFFFFF, 0x7FFFFFFF) and cell != anchor:
			if not pathfinding.has_path_from(cell, anchor):
				continue
		return cell
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


# Finds any walkable cell that belongs to a settlement not associated with
# building b. Used as an anchor destination for connectivity checks.
func _get_any_connected_cell(exclude_building: Node) -> Vector2i:
	for prov in provinces.get_children():
		var sett_container = prov.get_node_or_null("settlements")
		if sett_container == null:
			continue
		for s in sett_container.get_children():
			if s == exclude_building:
				continue
			if not s.has_method("get_pathfinding_blocked_tile_centers"):
				continue
			for pos in s.get_pathfinding_blocked_tile_centers():
				var local_pos = pathfinding.map_layer.to_local(pos)
				var cell: Vector2i = pathfinding.map_layer.local_to_map(local_pos)
				# We want a walkable cell adjacent to this settlement, not the
				# building's own cell (which is blocked).
				for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nc: Vector2i = cell + dir
					if pathfinding.walkable_cells.has(nc):
						return nc
	# Fallback: pick any walkable cell from the graph.
	for cell in pathfinding.walkable_cells.keys():
		return cell
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


# Returns garrison units owned by player_id across all spots of building b.
func get_player_garrison(b: Node, player_id: int) -> Array:
	var result: Array = []
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			for s in get_building_garrison(b, spot):
				if int(s["owner"]) == player_id:
					result.append({"spot": spot, "stack": s})
	else:
		for s in get_building_garrison(b, GlobalUnits.SPOT.FLAT):
			if int(s["owner"]) == player_id:
				result.append({"spot": GlobalUnits.SPOT.FLAT, "stack": s})
	return result


# Move out_units from one force into a building garrison spot.
@rpc("any_peer", "call_local", "reliable")
func request_garrison_units(source_id: String, building_key: String, spot: int, out_units: Array) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(source_id):
		return
	# Server validation: garrisoning costs 1 MP.
	var sfig = armies.get_node_or_null(source_id)
	if sfig == null or sfig.movement_left < 1:
		return
	apply_garrison_units.rpc(source_id, building_key, spot, out_units)


@rpc("authority", "call_local", "reliable")
func apply_garrison_units(source_id: String, building_key: String, spot: int, out_units: Array) -> void:
	if not forces.has(source_id):
		return
	GlobalUnits.subtract_units(forces[source_id]["units"], out_units)
	var gid := _garrison_force_id(building_key, spot)
	if forces.has(gid):
		forces[gid]["units"] = GlobalUnits.merge_units(forces[gid]["units"], GlobalUnits.units_from_spec(out_units))
	else:
		forces[gid] = {
			"units": GlobalUnits.units_from_spec(out_units),
			"location": {"kind": "garrison", "building": building_key, "spot": spot}
		}
	var sfig = armies.get_node_or_null(source_id)
	if sfig != null:
		sfig.movement_left = maxi(0, sfig.movement_left - 1)
		sfig.refresh_from_force()
	_cleanup_force_if_empty(source_id)
	pathfinding.rebuild_occupancy()
	refresh_building_flags(building_key)
	update_all_army_visuals()


# Take out_units out of a garrison and place them as a new army at (cell).
@rpc("any_peer", "call_local", "reliable")
func request_sortie_units(building_key: String, spot: int, out_units: Array, cell_x: int, cell_y: int) -> void:
	if !multiplayer.is_server():
		return
	var gid := _garrison_force_id(building_key, spot)
	if not forces.has(gid):
		return
	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	apply_sortie_units.rpc(gid, new_id, out_units, cell_x, cell_y)


@rpc("authority", "call_local", "reliable")
func apply_sortie_units(garrison_id: String, new_id: String, out_units: Array, cell_x: int, cell_y: int) -> void:
	if not forces.has(garrison_id):
		return
	GlobalUnits.subtract_units(forces[garrison_id]["units"], out_units)
	# Sortie onto the map costs a full turn of preparation; army starts with 0 MP.
	var controller := GlobalUnits.primary_owner(GlobalUnits.units_from_spec(out_units))
	_spawn_army_figure(new_id, GlobalUnits.units_from_spec(out_units), Vector2i(cell_x, cell_y), 0, controller)
	var building_key := _building_key_from_garrison_force_id(garrison_id)
	_cleanup_force_if_empty(garrison_id)
	pathfinding.rebuild_occupancy()
	if not building_key.is_empty():
		refresh_building_flags(building_key)
	update_all_army_visuals()


# Building owner deploys the entire garrison (all spots, all owners) as one army.
@rpc("any_peer", "call_local", "reliable")
func request_deploy_all_garrison(building_key: String, controller_player: int) -> void:
	if !multiplayer.is_server():
		return
	var b := _building_from_key(building_key)
	if b == null or b.get("player_owner") == null or b.player_owner != controller_player:
		return
	var all_units: Array = get_all_building_garrison(b)
	if GlobalUnits.total_men(all_units) <= 0:
		return
	var approach := get_free_approach_cell_for(b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return
	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	apply_deploy_all_garrison.rpc(building_key, new_id, controller_player, approach.x, approach.y)


@rpc("authority", "call_local", "reliable")
func apply_deploy_all_garrison(building_key: String, new_id: String, controller_player: int, cell_x: int, cell_y: int) -> void:
	var b := _building_from_key(building_key)
	if b == null:
		return
	var all_units: Array = get_all_building_garrison(b)
	if GlobalUnits.total_men(all_units) <= 0:
		return
	var vip_ids: Array = []
	for fid in _building_garrison_force_ids(b):
		for vid in get_vips_on_force(fid):
			vip_ids.append(vid)
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			var gid := _garrison_force_id(building_key, spot)
			if forces.has(gid):
				forces.erase(gid)
	else:
		var gid := _garrison_force_id(building_key, GlobalUnits.SPOT.FLAT)
		if forces.has(gid):
			forces.erase(gid)
	_spawn_army_figure(new_id, all_units, Vector2i(cell_x, cell_y), 0, controller_player)
	move_vips_to_force(vip_ids, new_id)
	pathfinding.rebuild_occupancy()
	refresh_building_flags(building_key)
	update_all_army_visuals()
	refresh_all_vip_crowns()


# --- VIP actions (transfer / sword / trade) ---------------------------------

func do_transfer_vips(from_id: String, to_id: String, vip_ids: Array) -> void:
	request_transfer_vips.rpc_id(1, from_id, to_id, vip_ids)


func _ensure_force_exists(force_id: String) -> bool:
	if forces.has(force_id):
		return true
	if not force_id.begins_with("g:"):
		return false
	var bkey := _building_key_from_garrison_force_id(force_id)
	if bkey == "":
		return false
	var rest := force_id.substr(2)
	var hash_idx := rest.rfind("#")
	if hash_idx < 0:
		return false
	var spot := int(rest.substr(hash_idx + 1))
	var b := _building_from_key(bkey)
	if b == null:
		return false
	var type_ = b.get("type_")
	if type_ == null:
		return false
	if type_ != GlobalStuff.BUILDING_TYPE.TOWN and type_ != GlobalStuff.BUILDING_TYPE.CASTLE:
		return false
	forces[force_id] = {
		"units": [],
		"location": {"kind": "garrison", "building": bkey, "spot": spot},
	}
	return true


@rpc("any_peer", "call_local", "reliable")
func request_transfer_vips(from_id: String, to_id: String, vip_ids: Array) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(from_id):
		return
	if not _ensure_force_exists(to_id):
		return
	if vip_ids.is_empty():
		return
	# Validate each VIP is on from_id.
	for vid in vip_ids:
		var v := get_vip(str(vid))
		if v.is_empty() or not bool(v.get("alive", false)):
			return
		if str(v.get("force_id", "")) != from_id:
			return
	# Destination: mobile army needs ≥ MIN_SPLIT_MEN after transfer.
	var to_loc: Dictionary = forces[to_id].get("location", {})
	if str(to_loc.get("kind", "")) == "cell":
		if GlobalUnits.total_men(forces[to_id]["units"]) < GlobalUnits.MIN_SPLIT_MEN:
			return
	# Source army cannot be left with VIP and < MIN_SPLIT_MEN men.
	var from_loc: Dictionary = forces[from_id].get("location", {})
	if str(from_loc.get("kind", "")) == "cell":
		var remaining_vips := get_vips_on_force(from_id).size() - vip_ids.size()
		if remaining_vips > 0 and GlobalUnits.total_men(forces[from_id]["units"]) < GlobalUnits.MIN_SPLIT_MEN:
			return
	apply_transfer_vips.rpc(from_id, to_id, vip_ids)


@rpc("authority", "call_local", "reliable")
func apply_transfer_vips(from_id: String, to_id: String, vip_ids: Array) -> void:
	_ensure_force_exists(to_id)
	if not forces.has(to_id):
		return
	move_vips_to_force(vip_ids, to_id)
	refresh_vip_crown_for_force(from_id)
	refresh_vip_crown_for_force(to_id)
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_army_menu_if_force"):
			gui_node.refresh_army_menu_if_force(from_id)
			gui_node.refresh_army_menu_if_force(to_id)
		if gui_node.has_method("refresh_force_menu_if_open"):
			gui_node.refresh_force_menu_if_open()


func do_put_vip_to_sword(force_id: String, vip_id: String) -> void:
	request_put_vip_to_sword.rpc_id(1, force_id, vip_id)


@rpc("any_peer", "call_local", "reliable")
func request_put_vip_to_sword(force_id: String, vip_id: String) -> void:
	if not multiplayer.is_server():
		return
	var v := get_vip(vip_id)
	if v.is_empty() or not bool(v.get("alive", false)):
		return
	if str(v.get("force_id", "")) != force_id:
		return
	var owner_id := int(v.get("owner", -1))
	var holder := holder_of_vip(vip_id)
	if holder < 0 or holder == owner_id:
		return  # cannot sword your own VIP
	apply_put_vip_to_sword.rpc(force_id, vip_id)


@rpc("authority", "call_local", "reliable")
func apply_put_vip_to_sword(force_id: String, vip_id: String) -> void:
	var v := get_vip(vip_id)
	if v.is_empty():
		return
	var owner_id := int(v.get("owner", -1))
	var role_txt := GlobalVips.role_name(int(v.get("role", 0)))
	var actor := holder_of_vip(vip_id)
	kill_vip(vip_id)
	refresh_vip_crown_for_force(force_id)
	if owner_id >= 0:
		_make_vip_message_event(
			"sword",
			"Your %s was put to death." % role_txt,
			owner_id,
			actor
		)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


func do_propose_vip_trade(to_pid: int, offer_vip_ids: Array, offer_marks: int, request_marks: int) -> void:
	request_propose_vip_trade.rpc_id(1, my_pl_id, to_pid, offer_vip_ids, offer_marks, request_marks)


@rpc("any_peer", "call_local", "reliable")
func request_propose_vip_trade(from_pid: int, to_pid: int, offer_vip_ids: Array, offer_marks: int, request_marks: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(from_pid) or not players.has(to_pid):
		return
	if int(players[to_pid].status) != GlobalStuff.PLAYER_STATUS.PLAYING:
		return
	if offer_marks < 0 or request_marks < 0:
		return
	if offer_vip_ids.is_empty() and offer_marks <= 0:
		return
	if int(players[from_pid].game_data.get("marks", 0)) < offer_marks:
		return
	for vid in offer_vip_ids:
		if not player_holds_vip(from_pid, str(vid)):
			return
		var v := get_vip(str(vid))
		if v.is_empty() or not bool(v.get("alive", false)):
			return
	# Receiver must have somewhere to put VIPs if any are offered.
	if not offer_vip_ids.is_empty():
		var from_cell := Vector2i.ZERO
		var fv := get_vip(str(offer_vip_ids[0]))
		if not fv.is_empty():
			from_cell = _force_anchor_cell(str(fv.get("force_id", "")))
		var dest := find_closest_vip_destination(to_pid, from_cell, true)
		if dest == "":
			return
	apply_propose_vip_trade.rpc(from_pid, to_pid, offer_vip_ids, offer_marks, request_marks)


@rpc("authority", "call_local", "reliable")
func apply_propose_vip_trade(from_pid: int, to_pid: int, offer_vip_ids: Array, offer_marks: int, request_marks: int) -> void:
	var tid := "vt_%d" % _next_vip_trade_id
	_next_vip_trade_id += 1
	vip_trades[tid] = {
		"id": tid,
		"from": from_pid,
		"to": to_pid,
		"offer_vip_ids": offer_vip_ids.duplicate(),
		"offer_marks": offer_marks,
		"request_marks": request_marks,
	}
	var vip_txt := ""
	for vid in offer_vip_ids:
		if vip_txt != "":
			vip_txt += ", "
		vip_txt += vip_display_name(str(vid))
	if vip_txt == "":
		vip_txt = "no VIP"
	var msg := "%s offers you a trade: %s + %d marks, requesting %d marks. Open War → Diplomacy to respond." % [
		player_display_name(from_pid),
		vip_txt,
		offer_marks,
		request_marks,
	]
	_make_vip_message_event("trade_propose", msg, to_pid, from_pid)
	if is_instance_valid(gui_node) and gui_node.has_method("on_vip_trade_proposed"):
		gui_node.on_vip_trade_proposed(self, tid)


func do_respond_vip_trade(trade_id: String, accept: bool) -> void:
	request_respond_vip_trade.rpc_id(1, my_pl_id, trade_id, accept)


@rpc("any_peer", "call_local", "reliable")
func request_respond_vip_trade(responder: int, trade_id: String, accept: bool) -> void:
	if not multiplayer.is_server():
		return
	if not vip_trades.has(trade_id):
		return
	var t: Dictionary = vip_trades[trade_id]
	if int(t.get("to", -1)) != responder:
		return
	if not accept:
		apply_respond_vip_trade.rpc(trade_id, false, "ok")
		return
	# Validate still holds VIPs and marks.
	var from_pid := int(t.get("from", -1))
	var to_pid := int(t.get("to", -1))
	var offer_vips: Array = t.get("offer_vip_ids", [])
	var offer_marks := int(t.get("offer_marks", 0))
	var request_marks := int(t.get("request_marks", 0))
	for vid in offer_vips:
		if not player_holds_vip(from_pid, str(vid)):
			apply_respond_vip_trade.rpc(trade_id, false, "missing_vip")
			return
	if int(players[from_pid].game_data.get("marks", 0)) < offer_marks:
		apply_respond_vip_trade.rpc(trade_id, false, "missing_marks")
		return
	if int(players[to_pid].game_data.get("marks", 0)) < request_marks:
		apply_respond_vip_trade.rpc(trade_id, false, "missing_marks")
		return
	var dest := ""
	if not offer_vips.is_empty():
		var from_cell := Vector2i.ZERO
		var first_v := get_vip(str(offer_vips[0]))
		if not first_v.is_empty():
			from_cell = _force_anchor_cell(str(first_v.get("force_id", "")))
		dest = find_closest_vip_destination(to_pid, from_cell, true)
		if dest == "":
			apply_respond_vip_trade.rpc(trade_id, false, "no_dest")
			return
	apply_respond_vip_trade.rpc(trade_id, true, "ok")


@rpc("authority", "call_local", "reliable")
func apply_respond_vip_trade(trade_id: String, accepted: bool, reason: String = "ok") -> void:
	if not vip_trades.has(trade_id):
		return
	var t: Dictionary = vip_trades[trade_id]
	var from_pid := int(t.get("from", -1))
	var to_pid := int(t.get("to", -1))
	vip_trades.erase(trade_id)

	if not accepted:
		if reason == "missing_vip":
			# Receiver saw disabled accept — still notify sender on reject path from UI.
			pass
		_make_vip_message_event(
			"trade_reject",
			"Your trade offer to %s was rejected." % player_display_name(to_pid),
			from_pid,
			to_pid
		)
		if is_instance_valid(gui_node) and gui_node.has_method("on_vip_trade_resolved"):
			gui_node.on_vip_trade_resolved(self, trade_id, false, reason)
		return

	var offer_vips: Array = t.get("offer_vip_ids", [])
	var offer_marks := int(t.get("offer_marks", 0))
	var request_marks := int(t.get("request_marks", 0))

	if offer_marks > 0 and players.has(from_pid) and players.has(to_pid):
		players[from_pid].game_data["marks"] = int(players[from_pid].game_data.get("marks", 0)) - offer_marks
		players[to_pid].game_data["marks"] = int(players[to_pid].game_data.get("marks", 0)) + offer_marks
	if request_marks > 0 and players.has(from_pid) and players.has(to_pid):
		players[to_pid].game_data["marks"] = int(players[to_pid].game_data.get("marks", 0)) - request_marks
		players[from_pid].game_data["marks"] = int(players[from_pid].game_data.get("marks", 0)) + request_marks

	if not offer_vips.is_empty():
		var from_cell := Vector2i.ZERO
		var first_v := get_vip(str(offer_vips[0]))
		if not first_v.is_empty():
			from_cell = _force_anchor_cell(str(first_v.get("force_id", "")))
		var dest := find_closest_vip_destination(to_pid, from_cell, true)
		if dest != "":
			move_vips_to_force(offer_vips, dest)
			refresh_all_vip_crowns()

	_make_vip_message_event(
		"trade_accept",
		"Trade with %s completed." % player_display_name(to_pid),
		from_pid,
		to_pid
	)
	_make_vip_message_event(
		"trade_accept",
		"Trade with %s completed." % player_display_name(from_pid),
		to_pid,
		from_pid
	)
	update_player_data.rpc(players)
	if is_instance_valid(gui_node):
		if gui_node.has_method("on_vip_trade_resolved"):
			gui_node.on_vip_trade_resolved(self, trade_id, true, "ok")
		if gui_node.has_method("update_visuals_and_stats") == false and has_method("update_visuals_and_stats"):
			update_visuals_and_stats()


func get_pending_vip_trades_for(pid: int) -> Array:
	var out: Array = []
	for tid in vip_trades:
		var t: Dictionary = vip_trades[tid]
		if int(t.get("to", -1)) == pid or int(t.get("from", -1)) == pid:
			out.append(t)
	return out


func expire_vip_trades_for_player(pid: int) -> void:
	var to_expire: Array = []
	for tid in vip_trades:
		var t: Dictionary = vip_trades[tid]
		if int(t.get("to", -1)) == pid:
			to_expire.append(tid)
	for tid in to_expire:
		apply_respond_vip_trade.rpc(tid, false, "expired")


# --- Merchants --------------------------------------------------------------

func build_province_neighbors() -> void:
	province_neighbors.clear()
	for prov in provinces.get_children():
		province_neighbors[prov] = []
	if province_borders == null:
		return
	var owner_of: Dictionary = province_borders.owner_of
	var edge_dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for cell_variant in owner_of.keys():
		var cell: Vector2i = cell_variant
		var prov = owner_of[cell]
		if prov == null or not is_instance_valid(prov):
			continue
		for d in edge_dirs:
			var other = owner_of.get(cell + d, null)
			if other == null or other == prov or not is_instance_valid(other):
				continue
			var list: Array = province_neighbors[prov]
			if other not in list:
				list.append(other)
			var other_list: Array = province_neighbors[other]
			if prov not in other_list:
				other_list.append(prov)


func get_free_walkable_cells_in_province(prov: Node) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if prov == null or province_borders == null:
		return result
	var owner_of: Dictionary = province_borders.owner_of
	for cell_variant in owner_of.keys():
		var cell: Vector2i = cell_variant
		if owner_of[cell] != prov:
			continue
		if not pathfinding.walkable_cells.has(cell):
			continue
		if pathfinding.occupancy.has(cell):
			continue
		result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return result


func merchant_count_in_province(prov: Node) -> int:
	if prov == null or merchants == null:
		return 0
	var n := 0
	for m in merchants.get_children():
		if m.get("province") == prov:
			n += 1
	return n


func merchant_competition_in_province(prov: Node) -> bool:
	return merchant_count_in_province(prov) >= 2


func spawn_merchants() -> void:
	if merchants == null:
		return
	for child in merchants.get_children():
		child.queue_free()
	var prov_list: Array = provinces.get_children()
	if prov_list.is_empty():
		return
	prov_list.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4D455243  # "MERC"
	for i in MERCHANT_COUNT:
		var placed := false
		# Prefer a random province; fall back through a deterministic shuffle.
		var try_order: Array = []
		var pool: Array = prov_list.duplicate()
		while not pool.is_empty():
			var idx := rng.randi() % pool.size()
			try_order.append(pool[idx])
			pool.remove_at(idx)
		for prov in try_order:
			var cells := get_free_walkable_cells_in_province(prov)
			if cells.is_empty():
				continue
			_spawn_merchant_at(prov, cells[rng.randi() % cells.size()], rng)
			placed = true
			break
		if not placed:
			push_warning("Could not place merchant %d — no free cells" % i)


func _spawn_merchant_at(prov: Node, cell: Vector2i, rng: RandomNumberGenerator) -> Node:
	var m = MERCHANT_SCENE.instantiate()
	m.name = "merchant_%d" % _next_merchant_id
	_next_merchant_id += 1
	m.base_map = self
	merchants.add_child(m)
	m.place_at_cell(cell, prov)
	m.roll_stay(rng)
	if not pathfinding.block_cell_for_object(cell, m):
		push_warning("Failed to block cell for merchant at %s" % str(cell))
	return m


func tick_merchants() -> void:
	if merchants == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(turn) ^ 0x4D455243
	var ordered: Array = merchants.get_children()
	ordered.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	for m in ordered:
		if int(m.seasons_left) > 0:
			m.seasons_left = int(m.seasons_left) - 1
		if int(m.seasons_left) > 0:
			continue
		_try_move_merchant(m, rng)


func _try_move_merchant(m: Node, rng: RandomNumberGenerator) -> void:
	var current_prov = m.get("province")
	var neighbors: Array = province_neighbors.get(current_prov, [])
	if neighbors.is_empty():
		return
	var candidates: Array = neighbors.duplicate()
	# Deterministic random order.
	var ordered: Array = []
	while not candidates.is_empty():
		var idx := rng.randi() % candidates.size()
		ordered.append(candidates[idx])
		candidates.remove_at(idx)
	for dest in ordered:
		var cells := get_free_walkable_cells_in_province(dest)
		if cells.is_empty():
			continue
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		pathfinding.unblock_object(m)
		m.place_at_cell(cell, dest)
		m.roll_stay(rng)
		if not pathfinding.block_cell_for_object(cell, m):
			# Extremely unlikely race; stay unblocked and retry next season.
			m.seasons_left = 0
		return
	# No free cell in any neighbor — stay put, retry next season.
	m.seasons_left = 0


func get_merchant_by_id(merchant_id: String) -> Node:
	if merchants == null:
		return null
	return merchants.get_node_or_null(merchant_id)


func _merchant_cart_total_cost(weapons: Dictionary, materials: Dictionary, competition: bool) -> int:
	var total := 0
	for k in GlobalUnits.WEAPON_KEYS:
		var amt := int(weapons.get(k, 0))
		if amt > 0:
			total += GlobalUnits.weapon_mark_price_discounted(k, competition) * amt
	for k in GlobalUnits.MATERIAL_KEYS:
		var amt := int(materials.get(k, 0))
		if amt > 0:
			total += GlobalUnits.material_mark_price_discounted(k, competition) * amt
	return total


func do_buy_from_merchant(merchant_id: String, weapons: Dictionary, materials: Dictionary) -> void:
	var m := get_merchant_by_id(merchant_id)
	if m == null:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Merchant not found")
		return
	var prov = m.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Only the de jure owner can view the merchant")
		return
	var competition := merchant_competition_in_province(prov)
	var total_cost := _merchant_cart_total_cost(weapons, materials, competition)
	if total_cost <= 0:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Select items to buy")
		return
	var marks := int(players[my_pl_id].game_data.get("marks", 0))
	if marks < total_cost:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Not enough marks (need %d)" % total_cost)
		return
	request_buy_from_merchant.rpc_id(1, merchant_id, weapons, materials, my_pl_id)


## Back-compat wrapper (weapons-only cart).
func do_buy_weapons_from_merchant(merchant_id: String, cargo: Dictionary) -> void:
	do_buy_from_merchant(merchant_id, cargo, GlobalUnits.empty_material_stock())


@rpc("any_peer", "call_local", "reliable")
func request_buy_from_merchant(
	merchant_id: String,
	weapons: Dictionary,
	materials: Dictionary,
	player_id: int
) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(player_id):
		return
	var m := get_merchant_by_id(merchant_id)
	if m == null:
		return
	var prov = m.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(player_id):
		return
	var competition := merchant_competition_in_province(prov)
	var cleaned_w := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_KEYS:
		cleaned_w[k] = maxi(0, int(weapons.get(k, 0)))
	var cleaned_m := GlobalUnits.empty_material_stock()
	for k in GlobalUnits.MATERIAL_KEYS:
		cleaned_m[k] = maxi(0, int(materials.get(k, 0)))
	var total_cost := _merchant_cart_total_cost(cleaned_w, cleaned_m, competition)
	if total_cost <= 0:
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < total_cost:
		return
	apply_buy_from_merchant.rpc(merchant_id, cleaned_w, cleaned_m, player_id, total_cost)


@rpc("authority", "call_local", "reliable")
func apply_buy_from_merchant(
	merchant_id: String,
	weapons: Dictionary,
	materials: Dictionary,
	player_id: int,
	total_cost: int
) -> void:
	var m := get_merchant_by_id(merchant_id)
	if m == null:
		return
	var prov = m.get("province")
	if prov == null or not prov.has_method("get_weapons"):
		return
	if not players.has(player_id):
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < total_cost:
		return
	players[player_id].game_data["marks"] = marks - total_cost
	# Shared arsenal for non-horse weapons; horses go to the buyer's holding.
	var bought_horses := int(weapons.get("horses", 0))
	var arsenal := weapons.duplicate()
	arsenal["horses"] = 0
	GlobalUnits.add_weapons(prov.get_weapons(), arsenal)
	if bought_horses > 0 and prov.has_method("add_player_horses"):
		prov.add_player_horses(player_id, bought_horses)
	if prov.get("resources") != null:
		GlobalUnits.add_materials(prov.resources, materials, player_id)
	if is_instance_valid(gui_node):
		if player_id == my_pl_id:
			gui_node.update_money(players[my_pl_id].game_data["marks"])
		update_menus()


# --- Sellswords -------------------------------------------------------------

func sellswords_count_in_province(prov: Node) -> int:
	if prov == null or sellswords == null:
		return 0
	var n := 0
	for s in sellswords.get_children():
		if s.get("province") == prov:
			n += 1
	return n


func spawn_sellswords_initial() -> void:
	if sellswords == null:
		return
	while sellswords.get_child_count() > 0:
		var child = sellswords.get_child(0)
		sellswords.remove_child(child)
		child.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x53454C4C  # "SELL"
	_roll_sellswords_spawns(rng)


func tick_sellswords() -> void:
	if sellswords == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(turn) ^ 0x53454C4C
	# Expire first so a province can roll a new band the same season.
	var ordered: Array = sellswords.get_children()
	ordered.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	var to_remove: Array = []
	for s in ordered:
		if int(s.seasons_left) > 0:
			s.seasons_left = int(s.seasons_left) - 1
		if int(s.seasons_left) <= 0:
			to_remove.append(s)
	for s in to_remove:
		_remove_sellswords_band(s)
	_roll_sellswords_spawns(rng)


func _roll_sellswords_spawns(rng: RandomNumberGenerator) -> void:
	var prov_list: Array = provinces.get_children()
	prov_list.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	for prov in prov_list:
		if sellswords_count_in_province(prov) > 0:
			continue
		if rng.randf() >= SELLSWORDS_SPAWN_CHANCE:
			continue
		var want := SELLSWORDS_MAX_PER_PROVINCE if rng.randf() < SELLSWORDS_DOUBLE_CHANCE else 1
		for _i in want:
			var cells := get_free_walkable_cells_in_province(prov)
			if cells.is_empty():
				break
			_spawn_sellswords_at(prov, cells[rng.randi() % cells.size()], rng)


func _spawn_sellswords_at(prov: Node, cell: Vector2i, rng: RandomNumberGenerator) -> Node:
	var s = SELLSWORDS_SCENE.instantiate()
	s.name = "sellswords_%d" % _next_sellswords_id
	_next_sellswords_id += 1
	s.base_map = self
	sellswords.add_child(s)
	s.place_at_cell(cell, prov)
	s.roll_stay(rng)
	s.roll_offer(rng)
	if not pathfinding.block_cell_for_object(cell, s):
		push_warning("Failed to block cell for sellswords at %s" % str(cell))
	return s


func _remove_sellswords_band(s: Node) -> void:
	if s == null or not is_instance_valid(s):
		return
	pathfinding.unblock_object(s)
	var parent := s.get_parent()
	if parent != null:
		parent.remove_child(s)
	s.queue_free()


func get_sellswords_by_id(band_id: String) -> Node:
	if sellswords == null:
		return null
	return sellswords.get_node_or_null(band_id)


func do_hire_sellswords(band_id: String) -> void:
	var s := get_sellswords_by_id(band_id)
	if s == null:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Sellswords not found")
		return
	var prov = s.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Only the de jure owner can hire these sellswords")
		return
	var offer: Array = s.get("offer") if s.get("offer") != null else []
	var total_cost := GlobalUnits.sellsword_offer_mark_price(offer)
	if total_cost <= 0 or offer.is_empty():
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Nothing to hire")
		return
	var marks := int(players[my_pl_id].game_data.get("marks", 0))
	if marks < total_cost:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Not enough marks (need %d)" % total_cost)
		return
	request_hire_sellswords.rpc_id(1, band_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_hire_sellswords(band_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(player_id):
		return
	var s := get_sellswords_by_id(band_id)
	if s == null:
		return
	var prov = s.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(player_id):
		return
	var offer: Array = s.get("offer") if s.get("offer") != null else []
	if offer.is_empty():
		return
	var total_cost := GlobalUnits.sellsword_offer_mark_price(offer)
	if total_cost <= 0:
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < total_cost:
		return
	var cell: Vector2i = s.cell
	if cell.x == 0x7FFFFFFF:
		return
	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	# Deep-copy offer for the RPC payload.
	var offer_copy: Array = []
	for entry in offer:
		offer_copy.append({
			"type": int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT)),
			"count": int(entry.get("count", 0)),
		})
	apply_hire_sellswords.rpc(band_id, player_id, offer_copy, total_cost, new_id, cell.x, cell.y)


@rpc("authority", "call_local", "reliable")
func apply_hire_sellswords(
	band_id: String,
	player_id: int,
	offer: Array,
	total_cost: int,
	new_id: String,
	cell_x: int,
	cell_y: int
) -> void:
	var s := get_sellswords_by_id(band_id)
	if s == null:
		return
	if not players.has(player_id):
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < total_cost:
		return
	var units: Array = []
	for entry in offer:
		var cnt := int(entry.get("count", 0))
		if cnt <= 0:
			continue
		GlobalUnits.add_stack(units, GlobalUnits.make_stack(
			int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT)),
			player_id,
			GlobalUnits.SOURCE.SELLSWORD,
			cnt
		))
	if units.is_empty():
		return
	players[player_id].game_data["marks"] = marks - total_cost
	_remove_sellswords_band(s)
	# -1 = full effective MP for the hired band this turn.
	_spawn_army_figure(new_id, units, Vector2i(cell_x, cell_y), -1, player_id)
	if is_instance_valid(gui_node):
		if player_id == my_pl_id:
			gui_node.update_money(players[my_pl_id].game_data["marks"])
		update_menus()
	update_all_army_visuals()


# --- Province weapons / levy ------------------------------------------------

func find_province_for_cell(cell: Vector2i) -> Node:
	if province_borders == null:
		return null
	var owner_of: Dictionary = province_borders.owner_of
	if not owner_of.has(cell):
		return null
	var prov = owner_of[cell]
	if prov == null or not is_instance_valid(prov):
		return null
	return prov


func get_force_province(force_id: String) -> Node:
	var fig = armies.get_node_or_null(force_id)
	if fig == null:
		return null
	return find_province_for_cell(pathfinding.get_army_cell(fig))


## Client helper: true if disbanding here refunds weapons to province stock.
func disband_refunds_weapons(force_id: String, player_id: int) -> bool:
	var prov := get_force_province(force_id)
	if prov == null or not prov.has_method("has_dejure"):
		return false
	return prov.has_dejure(player_id)


func get_weapon_shipments_involving(province_id: String) -> Array:
	var out: Array = []
	for s in weapon_shipments:
		if str(s.get("from_id", "")) == province_id or str(s.get("to_id", "")) == province_id:
			out.append(s.duplicate(true))
	return out


func tick_weapon_shipments() -> void:
	if weapon_shipments.is_empty():
		return
	var remaining: Array = []
	for s in weapon_shipments:
		var left := int(s.get("seasons_left", 0)) - 1
		if left > 0:
			s["seasons_left"] = left
			remaining.append(s)
			continue
		var to_prov := _get_province_by_id(str(s.get("to_id", "")))
		if to_prov != null:
			var shipper := int(s.get("shipper", -1))
			if shipper < 0:
				shipper = int(to_prov.dejure) if to_prov.get("dejure") != null else -1
			if to_prov.has_method("add_weapons_for") and shipper >= 0:
				to_prov.add_weapons_for(shipper, s.get("cargo", {}))
			elif to_prov.has_method("get_weapons"):
				GlobalUnits.add_weapons(to_prov.get_weapons(), s.get("cargo", {}))
	weapon_shipments = remaining


func do_recruit_levy(province_id: String, composition: Array) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_dejure(my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("You need de jure ownership to recruit here")
		return
	var total := GlobalUnits.composition_total_men(composition)
	if total < GlobalUnits.MIN_SPLIT_MEN:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Need at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
		return
	if total > prov.max_levy_remaining() or total > prov.owned_settlement_population(my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Not enough levy capacity or population")
		return
	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if not prov.can_afford_weapons_for(my_pl_id, need):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Not enough weapons in this province")
		return
	var spawn_b: Node = prov.get_recruit_spawn_building(my_pl_id)
	if spawn_b == null:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("No seat/town to raise the army near")
		return
	var approach := get_free_approach_cell_for(spawn_b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("No free tile adjacent to building")
		return
	request_recruit_levy.rpc_id(1, province_id, composition, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_recruit_levy(province_id: String, composition: Array, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(player_id):
		return
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("has_dejure"):
		return
	if not prov.has_dejure(player_id):
		return

	var total := GlobalUnits.composition_total_men(composition)
	if total < GlobalUnits.MIN_SPLIT_MEN:
		return
	if total > prov.max_levy_remaining():
		return
	if total > prov.owned_settlement_population(player_id):
		return

	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if not prov.can_afford_weapons_for(player_id, need):
		return

	var spawn_b: Node = prov.get_recruit_spawn_building(player_id)
	if spawn_b == null:
		return
	var approach := get_free_approach_cell_for(spawn_b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return

	var units: Array = []
	for entry in composition:
		var cnt := int(entry.get("count", 0))
		if cnt <= 0:
			continue
		GlobalUnits.add_stack(units, GlobalUnits.make_stack(
			int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT)),
			player_id,
			GlobalUnits.SOURCE.LEVY,
			cnt
		))
	if GlobalUnits.total_men(units) < GlobalUnits.MIN_SPLIT_MEN:
		return

	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	apply_recruit_levy.rpc(
		province_id, player_id, composition, new_id, approach.x, approach.y
	)


@rpc("authority", "call_local", "reliable")
func apply_recruit_levy(
	province_id: String,
	player_id: int,
	composition: Array,
	new_id: String,
	cell_x: int,
	cell_y: int
) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null:
		return
	var total := GlobalUnits.composition_total_men(composition)
	var need := GlobalUnits.weapons_needed_for_composition(composition)
	prov.subtract_weapons_for(player_id, need)
	if not prov.deduct_population(player_id, total):
		# Should not happen after server validation; bail without spawning.
		prov.add_weapons_for(player_id, need)
		return
	var prev_levied := int(prov.levied_this_season)
	prov.levied_this_season = prev_levied + total
	prov.apply_levy_happiness(prev_levied, prov.levied_this_season)

	var units: Array = []
	for entry in composition:
		var cnt := int(entry.get("count", 0))
		if cnt <= 0:
			continue
		GlobalUnits.add_stack(units, GlobalUnits.make_stack(
			int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT)),
			player_id,
			GlobalUnits.SOURCE.LEVY,
			cnt
		))
	# -1 = full effective MP for the new levy this turn.
	_spawn_army_figure(new_id, units, Vector2i(cell_x, cell_y), -1, player_id)
	update_players_population()
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


func do_ship_weapons(from_id: String, to_id: String, cargo: Dictionary) -> void:
	request_ship_weapons.rpc_id(1, from_id, to_id, cargo, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_ship_weapons(from_id: String, to_id: String, cargo: Dictionary, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if from_id == to_id:
		return
	var from_prov := _get_province_by_id(from_id)
	var to_prov := _get_province_by_id(to_id)
	if from_prov == null or to_prov == null:
		return
	if not from_prov.has_dejure(player_id) or not to_prov.has_dejure(player_id):
		return
	var clean := GlobalUnits.empty_weapon_stock()
	var any := false
	for k in GlobalUnits.WEAPON_KEYS:
		var amt := maxi(0, int(cargo.get(k, 0)))
		clean[k] = amt
		if amt > 0:
			any = true
	if not any:
		return
	if not from_prov.can_afford_weapons_for(player_id, clean):
		return
	apply_ship_weapons.rpc(from_id, to_id, clean, player_id)


@rpc("authority", "call_local", "reliable")
func apply_ship_weapons(from_id: String, to_id: String, cargo: Dictionary, player_id: int) -> void:
	var from_prov := _get_province_by_id(from_id)
	if from_prov == null:
		return
	if not from_prov.can_afford_weapons_for(player_id, cargo):
		return
	from_prov.subtract_weapons_for(player_id, cargo)
	weapon_shipments.append({
		"from_id": from_id,
		"to_id": to_id,
		"cargo": cargo.duplicate(true),
		"seasons_left": GlobalUnits.WEAPON_SHIP_SEASONS,
		"shipper": player_id,
	})
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


# --- Disband ----------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_disband_force(force_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	var fig = armies.get_node_or_null(force_id)
	if fig == null:
		return

	var units: Array = forces[force_id]["units"]
	var disbanding_player: int = get_force_controller(force_id)
	if disbanding_player < 0:
		disbanding_player = GlobalUnits.primary_owner(units)
	var army_cell = pathfinding.get_army_cell(fig)

	# --- Build foreign-owner spawns -----------------------------------------
	var foreign_owners: Array = []
	for u in units:
		var o := int(u["owner"])
		if o != disbanding_player and o not in foreign_owners:
			foreign_owners.append(o)

	# Find free cells for foreign armies (BFS from army cell, avoiding already-
	# assigned cells so two foreign armies don't pile onto the same tile).
	var reserved: Dictionary = {}
	reserved[army_cell] = true
	var foreign_spawns: Array = []
	for fowner in foreign_owners:
		var fown_units: Array = []
		for u in units:
			if int(u["owner"]) == fowner:
				fown_units.append(u)
		if fown_units.is_empty():
			continue
		var free_cell := _bfs_free_cell_near(army_cell, reserved)
		if free_cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
			continue  # no room — those troops are lost
		reserved[free_cell] = true
		_next_runtime_force += 1
		var new_id := "rt_%d" % _next_runtime_force
		foreign_spawns.append({
			"new_id": new_id,
			"units": fown_units.duplicate(true),
			"cell_x": free_cell.x,
			"cell_y": free_cell.y
		})

	# --- Build settlement population additions --------------------------------
	var own_levy_men := 0
	for u in units:
		if int(u["owner"]) == disbanding_player and int(u["source"]) == GlobalUnits.SOURCE.LEVY:
			own_levy_men += int(u["count"])

	var settlement_additions: Array = []
	if own_levy_men > 0:
		var owned_settlements := _get_owned_settlements(disbanding_player)
		if not owned_settlements.is_empty():
			var n := owned_settlements.size()
			var base_add := own_levy_men / n
			var remainder := own_levy_men % n
			for i in range(n):
				var amount := base_add + (1 if i < remainder else 0)
				if amount > 0:
					settlement_additions.append({
						"path": str(owned_settlements[i].get_path()),
						"add": amount
					})

	# Weapons refund only inside a province where the disbander has de jure.
	var refund_province_id := ""
	var refund_weapons := GlobalUnits.empty_weapon_stock()
	var prov := find_province_for_cell(army_cell)
	if prov != null and prov.has_dejure(disbanding_player):
		refund_province_id = prov.name
		refund_weapons = GlobalUnits.weapons_from_units(units, disbanding_player)

	apply_disband_force.rpc(
		force_id, foreign_spawns, settlement_additions,
		refund_province_id, refund_weapons, disbanding_player
	)


@rpc("authority", "call_local", "reliable")
func apply_disband_force(
	force_id: String,
	foreign_spawns: Array,
	settlement_additions: Array,
	refund_province_id: String = "",
	refund_weapons: Dictionary = {},
	refund_player_id: int = -1
) -> void:
	var disbander := refund_player_id
	if disbander < 0 and forces.has(force_id):
		disbander = get_force_controller(force_id)
	if force_has_any_vip(force_id):
		relocate_vips_from_disbanded_force(force_id, disbander)

	# Remove the disbanding army.
	if forces.has(force_id):
		forces.erase(force_id)
	var fig = armies.get_node_or_null(force_id)
	if fig != null:
		armies.remove_child(fig)
		fig.queue_free()

	# Spawn one army per foreign owner.
	for sp in foreign_spawns:
		var controller := GlobalUnits.primary_owner(sp["units"])
		_spawn_army_figure(sp["new_id"], sp["units"], Vector2i(sp["cell_x"], sp["cell_y"]), 0, controller)

	# Add levy men to settlements.
	for entry in settlement_additions:
		var s: Node = get_node_or_null(entry["path"])
		if s != null and s.get("population") != null:
			s.population += int(entry["add"])

	if refund_province_id != "" and not refund_weapons.is_empty():
		var rprov := _get_province_by_id(refund_province_id)
		if rprov != null:
			if refund_player_id >= 0 and rprov.has_method("add_weapons_for"):
				rprov.add_weapons_for(refund_player_id, refund_weapons)
			elif rprov.has_method("get_weapons"):
				GlobalUnits.add_weapons(rprov.get_weapons(), refund_weapons)

	for prov in provinces.get_children():
		if prov.has_method("update_population_in_resources"):
			prov.update_population_in_resources()
	update_players_population()

	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	refresh_all_vip_crowns()
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


# BFS outward from `center`, skipping cells in `reserved`, to find the nearest
# walkable unoccupied cell. Returns Vector2i(0x7FFFFFFF, 0x7FFFFFFF) if none found.
func _bfs_free_cell_near(center: Vector2i, reserved: Dictionary) -> Vector2i:
	var visited: Dictionary = {}
	visited[center] = true
	var queue: Array = [center]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + dir
			if visited.has(nc):
				continue
			visited[nc] = true
			if pathfinding.walkable_cells.has(nc) and not pathfinding.occupancy.has(nc) and not reserved.has(nc):
				return nc
			queue.append(nc)
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


# Returns all settlement nodes (villages/towns) owned by `player_id`.
# A settlement is "owned" if its province has player_owner == player_id,
# or defacto/dejure == player_id.
func _get_owned_settlements(player_id: int) -> Array:
	var result: Array = []
	for prov in provinces.get_children():
		var is_owned = (prov.player_owner == player_id
			or prov.defacto == player_id
			or prov.dejure == player_id)
		if not is_owned:
			continue
		var sett_container = prov.get_node_or_null("settlements")
		if sett_container == null:
			continue
		for s in sett_container.get_children():
			if s.get("population") != null:
				result.append(s)
	return result


# starting_mp: MP the new figure starts with (split = proportional; sortie = 0).
# Pass -1 to refill to full effective max (recruit).
func _spawn_army_figure(new_id: String, units: Array, cell: Vector2i, starting_mp: int = 0, controller: int = -1) -> void:
	var fig = ARMY_FIGURE_SCENE.instantiate()
	fig.name = new_id
	armies.add_child(fig)
	fig.base_map = self
	if controller < 0:
		controller = GlobalUnits.primary_owner(units)
	forces[new_id] = {"units": units, "location": {"kind": "cell"}, "controller": controller}
	fig.bind_force(new_id)
	pathfinding.place_army_at_cell(fig, cell)
	if starting_mp < 0:
		fig.reset_movement()
	else:
		fig.movement_left = clampi(starting_mp, 0, fig.effective_max_mp())


func reset_all_army_movement() -> void:
	for army in armies.get_children():
		army.reset_movement()


func update_all_army_visuals() -> void:
	for army in armies.get_children():
		army.set_greyed(army.is_controllable_by(my_pl_id) and army.movement_left <= 0)


func get_objects_with_pathfinding_blocked_tiles() -> Array:
	var result: Array = []
	for prov in provinces.get_children():
		for key in ["settlements", "fields", "economy", "defense"]:
			var container = prov.get_node_or_null(key)
			if container:
				for node in container.get_children():
					if node.has_method("get_pathfinding_blocked_tile_centers"):
						result.append(node)
	if merchants != null:
		for m in merchants.get_children():
			if m.has_method("get_pathfinding_blocked_tile_centers"):
				result.append(m)
	if sellswords != null:
		for s in sellswords.get_children():
			if s.has_method("get_pathfinding_blocked_tile_centers"):
				result.append(s)
	return result


@rpc("any_peer", "call_local", "reliable")
func player_ended_turn(player_id):
	if !multiplayer.is_server():
		return
	players[player_id].ended_turn = true
	expire_vip_trades_for_player(int(player_id))
	
	# update player data
	update_player_data.rpc(players)
	
	# calculate if the client of the user has hotseat, and if it should switch to the next user
	var peer_id = players[player_id].owner_peer_id
	var remaining = get_unfinished_players_for_peer(peer_id)
	
	if not remaining.is_empty():
		# send the request to the peer to switch the player playing
		var r_player_id = remaining[0].player_id
		var new_peer_id = players[r_player_id].owner_peer_id
		switch_to_player.rpc_id(new_peer_id, r_player_id)
	
	if multiplayer.is_server():
		check_if_end_turn.rpc_id(1)

func restore_ended_turn_players():
	for p : GlobalStuff.PlayerData in players.values():
		p.ended_turn = false
	
	# update player data
	update_player_data.rpc(players)
	
func get_unfinished_players_for_peer(peer_id:int) -> Array:
	var result := []

	for p : GlobalStuff.PlayerData in players.values():
		if (p.owner_peer_id == peer_id and !p.ended_turn and p.type != GlobalStuff.PLAYER_TYPE.AI and 
					p.status == GlobalStuff.PLAYER_STATUS.PLAYING):
			result.append(p)

	return result

@rpc("authority", "call_remote", "reliable")
func update_player_data(player_data_):
	players = player_data_

@rpc("authority", "call_local", "reliable")
func switch_to_player(r_player_id):
	my_pl_id = r_player_id
	pathfinding.deselect_army()
	gui_node.close_all_popups()
	# recalculate everything
	update_visuals_and_stats()
	center_camera_on_current_player_home()
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_msg_button"):
		gui_node.refresh_msg_button()

@rpc("authority", "call_local", "reliable")
func check_if_end_turn():
	for player_id in players:
		if players[player_id].ended_turn == false:
			return
	end_turn()

func end_turn():
	restore_ended_turn_players()
	bump_season_i_turn.rpc()
	set_players_turn()
	calculate_new_turn_game_data.rpc()

@rpc("authority", "call_local", "reliable")
func calculate_new_turn_game_data():
	assign_players_home_provinces()
	reset_all_army_movement()
	tick_all_force_seasons()
	tick_weapon_shipments()
	tick_razed_buildings()
	clear_expired_raid_smoke()
	tick_merchants()
	tick_sellswords()
	# Season already bumped; apply agriculture for the season that just ended.
	tick_all_agriculture()
	#calculate and then display the new data
	add_resources()
	for prov in provinces.get_children():
		if prov.has_method("snapshot_season_start"):
			prov.snapshot_season_start()
	update_visuals_and_stats()
	province_borders.rebuild()
	build_province_neighbors()


func tick_all_agriculture() -> void:
	var ended_season := (int(season) + 3) % 4
	var new_season := int(season)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s-%s" % [turn, ended_season, new_season])
	for prov in provinces.get_children():
		if prov.has_method("tick_agriculture"):
			prov.tick_agriculture(ended_season, new_season, rng)

	
func set_players_turn():
	# set the first players for the turn on each client
	for p : GlobalStuff.PlayerData in players.values():
		var next_player_id = get_starting_player_for_peer(p.owner_peer_id).player_id
		switch_to_player.rpc_id(p.owner_peer_id, next_player_id)

func get_starting_player_for_peer(peer_id:int) -> GlobalStuff.PlayerData:
	var selected : GlobalStuff.PlayerData = null

	for p : GlobalStuff.PlayerData in players.values():
		if p.owner_peer_id != peer_id:
			continue
		if p.ended_turn:
			continue
		if p.type == GlobalStuff.PLAYER_TYPE.AI:
			continue
		if p.status != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue

		# choose lowest local_slot
		if selected == null or p.local_slot < selected.local_slot:
			selected = p

	return selected

@rpc("authority", "call_local", "reliable")
func bump_season_i_turn():
	turn += 1
	
	var new_season = season +1
	
	if new_season > 3:
		new_season = 0
	
	season = new_season as SEASONS

func update_visuals_and_stats():
	update_stats()
	update_gui()
	update_all_army_visuals()
	refresh_province_labels()


func refresh_province_labels() -> void:
	for prov in provinces.get_children():
		if prov.has_method("refresh_map_label"):
			prov.refresh_map_label()
	if province_labels:
		province_labels.refresh()
	
func update_gui():
	gui_node.update_season(season)
	gui_node.update_pname(players[my_pl_id].name_)
	gui_node.update_money(players[my_pl_id].game_data["marks"])
	update_menus()

func update_menus():
	gui_node.update_economy_menu(self)

func update_stats():
	recalculate_all_settlements_growth()
	recalculate_all_settlements_marks()
	update_players_population()


func recalculate_all_settlements_growth() -> void:
	for prov in provinces.get_children():
		prov.recalculate_settlements_growth()

func add_population():
	recalculate_all_settlements_growth()
	for prov in provinces.get_children():
		prov.apply_predicted_growth_to_settlements()
	update_players_population()

func update_players_population() -> void:
	for pid in players:
		players[pid].game_data["people"] = 0
	for prov in provinces.get_children():
		var has_by_player: Dictionary = prov.resources["population"]["has"]
		for player_id in has_by_player:
			if players.has(player_id):
				players[player_id].game_data["people"] +=  int(has_by_player[player_id])

func recalculate_all_settlements_marks() -> void:
	for prov in provinces.get_children():
		prov.recalculate_marks_will_by_player()


func add_marks_to_players() -> void:
	recalculate_all_settlements_marks()
	for prov in provinces.get_children():
		var will_by_player: Dictionary = prov.resources["marks"]["will"]
		for player_id in will_by_player:
			if players.has(player_id):
				players[player_id].game_data["marks"] += int(will_by_player[player_id])


func add_resources():
	add_marks_to_players()


# --- Field crop / labor -----------------------------------------------------

func do_set_field_crop(field: Node, crop: int) -> void:
	if field == null:
		return
	request_set_field_crop.rpc_id(1, _building_key(field), crop, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_set_field_crop(field_key: String, crop: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var field = _building_from_key(field_key)
	if field == null or field.get("type_") == null:
		return
	if int(field.type_) != GlobalStuff.BUILDING_TYPE.FIELD:
		return
	if field.get_controller_id() != player_id:
		return
	crop = clampi(crop, 0, 2)
	apply_set_field_crop.rpc(field_key, crop)


@rpc("authority", "call_local", "reliable")
func apply_set_field_crop(field_key: String, crop: int) -> void:
	var field = _building_from_key(field_key)
	if field == null or not field.has_method("set_crop"):
		return
	var prov := find_province_for_building(field)
	var pid = field.get_controller_id() if field.has_method("get_controller_id") else -1
	var was_sown := bool(field.get("planted")) and int(field.get("crop")) == 1
	var staying_grain := was_sown and crop == 1

	# Leaving a sown field: refund seed only in winter (before growth seasons).
	if was_sown and not staying_grain and prov != null and pid >= 0:
		if int(season) == 0 and prov.has_method("unsow_field"):
			prov.unsow_field(field, pid)
		else:
			field.planted = false
			field.neglected = false
			if prov.has_method("ensure_holding"):
				var h: Dictionary = prov.ensure_holding(pid)
				h["grain_potential"] = maxf(
					0.0,
					float(h.get("grain_potential", 0.0)) - float(GlobalUnits.GRAIN_YIELD_PER_FIELD)
				)

	field.set_crop(crop, int(season))

	# Winter: assign grain → sow if stock has seed.
	if crop == 1 and int(season) == 0 and prov != null and pid >= 0:
		if not bool(field.planted) and prov.has_method("try_sow_field"):
			prov.try_sow_field(field, pid)

	if prov != null and prov.has_method("_update_grain_will"):
		prov._update_grain_will()
	if prov != null and prov.has_method("refresh_field_visuals"):
		prov.refresh_field_visuals(int(season))

	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_field_popup_if"):
			gui_node.refresh_field_popup_if(self, field)
		update_menus()


func do_set_holding_labor(province_id: String, amount: int) -> void:
	# Legacy: treat as grain category.
	do_set_holding_labor_category(province_id, "grain", amount)


func do_set_holding_labor_category(province_id: String, category: String, amount: int) -> void:
	request_set_holding_labor_category.rpc_id(1, province_id, category, amount, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_set_holding_labor_category(
	province_id: String, category: String, amount: int, player_id: int
) -> void:
	if not multiplayer.is_server():
		return
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("set_labor_category"):
		return
	if not prov.player_has_holding(player_id):
		return
	if category not in GlobalUnits.LABOR_CATEGORIES:
		return
	apply_set_holding_labor_category.rpc(province_id, category, amount, player_id)


@rpc("authority", "call_local", "reliable")
func apply_set_holding_labor_category(
	province_id: String, category: String, amount: int, player_id: int
) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("set_labor_category"):
		return
	prov.set_labor_category(player_id, category, amount, int(season))
	if prov.has_method("_update_material_will"):
		prov._update_material_will()
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


func do_build_economy(building: Node, subtype: int) -> void:
	if building == null:
		return
	request_build_economy.rpc_id(1, _building_key(building), subtype, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_build_economy(building_key: String, subtype: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(player_id):
		return
	var building = _building_from_key(building_key)
	if building == null or building.get("type_") == null:
		return
	if int(building.type_) != GlobalStuff.BUILDING_TYPE.ECONOMY:
		return
	var prov := find_province_for_building(building)
	if prov == null or not prov.has_dejure(player_id):
		return
	if not building.has_method("can_build") or not building.can_build(subtype):
		return
	var cost := int(building.build_cost_for(subtype))
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < cost:
		return
	apply_build_economy.rpc(building_key, subtype, player_id, cost)


@rpc("authority", "call_local", "reliable")
func apply_build_economy(building_key: String, subtype: int, player_id: int, cost: int) -> void:
	var building = _building_from_key(building_key)
	if building == null or not building.has_method("apply_build"):
		return
	if not players.has(player_id):
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < cost:
		return
	players[player_id].game_data["marks"] = marks - cost
	building.apply_build(subtype, player_id)
	if player_id == my_pl_id and is_instance_valid(gui_node):
		gui_node.update_money(players[my_pl_id].game_data["marks"])
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_economy_building_popup_if"):
			gui_node.refresh_economy_building_popup_if(self, building)
		update_menus()


func do_set_blacksmith_recipe(building: Node, weapon_key: String) -> void:
	if building == null:
		return
	request_set_blacksmith_recipe.rpc_id(1, _building_key(building), weapon_key, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_set_blacksmith_recipe(building_key: String, weapon_key: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var building = _building_from_key(building_key)
	if building == null or building.get("type_") == null:
		return
	if int(building.type_) != GlobalStuff.BUILDING_TYPE.ECONOMY:
		return
	if not building.has_method("is_blacksmith") or not building.is_blacksmith():
		return
	if int(building.player_owner) != player_id:
		return
	var prov := find_province_for_building(building)
	if prov == null or not prov.has_dejure(player_id):
		return
	if weapon_key != "" and weapon_key not in GlobalUnits.BLACKSMITH_CRAFTABLE:
		return
	apply_set_blacksmith_recipe.rpc(building_key, weapon_key)


@rpc("authority", "call_local", "reliable")
func apply_set_blacksmith_recipe(building_key: String, weapon_key: String) -> void:
	var building = _building_from_key(building_key)
	if building == null or not building.has_method("set_craft_weapon"):
		return
	building.set_craft_weapon(weapon_key)
	var prov := find_province_for_building(building)
	if prov != null and prov.has_method("_update_material_will"):
		prov._update_material_will()
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_economy_building_popup_if"):
			gui_node.refresh_economy_building_popup_if(self, building)
		if gui_node.has_method("update_economy_menu"):
			gui_node.update_economy_menu(self)


func do_demolish_economy(building: Node) -> void:
	if building == null:
		return
	request_demolish_economy.rpc_id(1, _building_key(building), my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_demolish_economy(building_key: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var building = _building_from_key(building_key)
	if building == null or building.get("type_") == null:
		return
	if int(building.type_) != GlobalStuff.BUILDING_TYPE.ECONOMY:
		return
	var prov := find_province_for_building(building)
	if prov == null or not prov.has_dejure(player_id):
		return
	if not building.has_method("is_built") or not building.is_built():
		return
	apply_demolish_economy.rpc(building_key)


@rpc("authority", "call_local", "reliable")
func apply_demolish_economy(building_key: String) -> void:
	var building = _building_from_key(building_key)
	if building == null or not building.has_method("apply_demolish"):
		return
	building.apply_demolish()
	var prov := find_province_for_building(building)
	if prov != null:
		for pid in prov.get_holding_controllers():
			prov.clamp_all_labor(pid, int(season))
		if prov.has_method("_update_material_will"):
			prov._update_material_will()
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_economy_building_popup_if"):
			gui_node.refresh_economy_building_popup_if(self, building)
		update_menus()


func _provinces_for_player(player_id: int) -> Array:
	var owned := []
	var holdings := []
	var other_interest := []
	for prov in provinces.get_children():
		var has_holding = prov.has_method("player_has_holding") and prov.player_has_holding(player_id)
		if prov.player_owner == player_id:
			owned.append(prov)
		elif has_holding:
			holdings.append(prov)
		elif prov.defacto == player_id or prov.dejure == player_id:
			other_interest.append(prov)
	owned.append_array(holdings)
	owned.append_array(other_interest)
	return owned


func get_player_overview_data(player_id: int) -> Dictionary:
	if not players.has(player_id):
		return {}
	var pl = players[player_id]
	var prov_list = _provinces_for_player(player_id)
	var population := 0
	for prov in prov_list:
		population += prov.resources["population"]["has"]["all"]
	return {
		"num_provinces": prov_list.size(),
		"marks": pl.game_data.get("marks", 0),
		"population": population
	}


func get_all_provinces_list_data(player_id: int) -> Array:
	var owned := []
	var holdings := []
	var other := []
	for prov in provinces.get_children():
		var has_holding = prov.has_method("player_has_holding") and prov.player_has_holding(player_id)
		var sett_n := 0
		if has_holding:
			sett_n = prov.get_owned_settlements(player_id).size()
		var display_name := str(prov.p_name)
		if has_holding and int(prov.player_owner) != player_id:
			display_name = "%s (%d settlement%s)" % [
				prov.p_name, sett_n, "" if sett_n == 1 else "s"
			]
		var pop := int(prov.resources["population"]["has"].get(player_id, 0)) if has_holding \
			else int(prov.resources["population"]["has"].get("all", 0))
		var income := 0
		if int(prov.dejure) == player_id:
			income = int(prov.resources["marks"]["will"].get(player_id, 0))
		var entry = {
			"id": prov.name,
			"name": display_name,
			"population": pop,
			"predicted_income": income,
			"owned": prov.player_owner == player_id,
			"holding": has_holding and int(prov.player_owner) != player_id,
		}
		if prov.player_owner == player_id:
			owned.append(entry)
		elif has_holding:
			holdings.append(entry)
		elif prov.defacto == player_id or prov.dejure == player_id:
			other.append(entry)
	owned.append_array(holdings)
	owned.append_array(other)
	return owned


func _get_province_by_id(province_id: String) -> Node:
	for prov in provinces.get_children():
		if prov.name == province_id:
			return prov
	return null


func get_province_data(province_id: String) -> Dictionary:
	var prov = _get_province_by_id(province_id)
	if prov == null:
		return {}
	return prov.get_display_data(players, my_pl_id)


func assign_players_home_provinces() -> void:
	var prov_list: Array = provinces.get_children()
	prov_list.sort_custom(func(a, b): return a.name < b.name)
	var assigned := {}
	for prov in prov_list:
		var pid = prov.player_owner
		if not players.has(pid) or assigned.has(pid):
			continue
		players[pid].game_data["home_province_id"] = prov.name
		assigned[pid] = true
	# Override with any province marked as home_province for that player
	for prov in prov_list:
		if prov.home_province and players.has(prov.player_owner):
			players[prov.player_owner].game_data["home_province_id"] = prov.name


func center_camera_on_current_player_home() -> void:
	if not players.has(my_pl_id):
		return
	var home_id: String = players[my_pl_id].game_data.get("home_province_id", "")
	if home_id.is_empty():
		return
	var prov = _get_province_by_id(home_id)
	if prov == null:
		return
	for s in prov.settlements.get_children():
		if s.get("type_") != null and s.type_ == GlobalStuff.BUILDING_TYPE.TOWN:
			camera.position = s.global_position
			_last_camera_focus_cell = Vector2i(999999, 999999)
			set_province_focus(home_id, false)
			return
