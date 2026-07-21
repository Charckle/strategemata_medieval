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
#   { "units": Array[stack], "location": Dictionary, "controller": int,
#     "display_name": String (mobile armies — nickname),
#     "siege": optional { "building": key, "level": 0..3 } while Sieging a castle }
# location = {"kind": "cell"}  -> a mobile army; the figure node holds its position
#          | {"kind": "garrison", "building": <path String>, "spot": SPOT}
#          | {"kind": "aboard", "fleet": <fleet_id String>} -> embarked on a fleet
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

const ARMY_FIGURE_SCENE := preload("res://objects/overworld/army/army_map_unit/armiy_figure.tscn")
const CARAVAN_SCENE := preload("res://objects/overworld/othr/caravan/caravan.tscn")
const TRANSPORT_SHIP_SCENE := preload("res://objects/overworld/othr/transport_ship/transport_ship.tscn")
const MERCHANT_SCENE := preload("res://objects/overworld/othr/merchant/merchant.tscn")
const ArmyNames := preload("res://global_scripts/army_names.gd")
## One merchant per this many provinces (rounded up).
const MERCHANTS_PER_PROVINCES := 5
const MERCHANT_NAMES := [
	# English
	"Pipin", "Mery", "Aldric", "Godwin", "Eadric", "Wulfric",
	# German
	"Dietrich", "Gottfried", "Hartmann", "Wolfram", "Berthold", "Siegmund",
	# Italian
	"Cosimo", "Lorenzo", "Bartolo", "Niccolo", "Orlando", "Jacopo",
	# Spanish
	"Rodrigo", "Alvaro", "Diego", "Fernando", "Gonzalo", "Lope",
]
## Players who have raided any merchant (dejure provinces become forbidden camps).
var merchant_raiders: Dictionary = {}  # player_id -> true
var _merchant_remnants: Node2D = null
const SELLSWORDS_SCENE := preload("res://objects/overworld/othr/sellswords/sellswords.tscn")
const SELLSWORDS_SPAWN_CHANCE := 0.10
const SELLSWORDS_DOUBLE_CHANCE := 0.10
const SELLSWORDS_MAX_PER_PROVINCE := 2

@onready var provinces = $provinces
@onready var armies = $armies
@onready var caravans = $caravans
@onready var fleets = $fleets
@onready var merchants = $merchants
@onready var sellswords = $sellswords
var _next_caravan_id: int = 1
var _next_fleet_id: int = 1
@onready var camera: Camera2D = $Camera2D
@onready var pathfinding = $pathfinding
@onready var province_labels = $ProvinceLabels
@onready var army_labels = $ArmyLabels
@onready var province_borders = $ProvinceBorders

@onready var gui_node = $BasebottomGUI

# After a fleet move onto an own fleet's tile, prompt combine vs stack.
var _pending_fleet_combine_mover_name := ""
var _pending_fleet_combine_target: Node2D = null

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
	var start_marks := GlobalUnits.PROVINCE_START_MARKS
	players[0] = GlobalStuff.PlayerData.new(
		0, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 0, "Richard", {"marks": start_marks, "people": 0}
	)
	players[1] = GlobalStuff.PlayerData.new(
		1, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 1, "William", {"marks": start_marks, "people": 0}
	)
	players[0].color = {"red": 0, "green": 100, "blue": 255}
	players[1].color = {"red": 255, "green": 0, "blue": 0}


func _ready() -> void:
	dummy_player_data()
	spawn_local_councils()
	update_player_data.rpc(players)
	assign_players_home_provinces()
	initialize_map()
	# Councils act at season start; run once so winter plans exist before turn 1.
	CouncilAI.tick_all(self)
	mark_auto_turn_players_ended()
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
		if child.has_method("seed_default_holding_kit"):
			child.seed_default_holding_kit()
		elif child.has_method("seed_test_weapons"):
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
	_init_weather()


func _init_weather() -> void:
	var weather := get_node_or_null("WeatherObject")
	if weather != null and weather.has_method("setup_and_roll"):
		weather.setup_and_roll(int(season))


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
		var fid := String(fig.name)
		forces[fid] = {
			"units": units,
			"location": {"kind": "cell"},
			"controller": controller,
			"cargo": GlobalUnits.empty_caravan_cargo(),
		}
		_assign_force_display_name(fid)
		fig.base_map = self
		fig.bind_force(fid)
		fig.reset_movement()
	refresh_army_labels()


func _register_building_start_garrison(b: Node) -> void:
	if b.get("type_") == null:
		return
	if b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		if b.has_method("is_operational") and not b.is_operational():
			return
		var key := _building_key(b)
		_seed_garrison(key, GlobalUnits.SPOT.INSIDE, b.get("start_inside"))
		_seed_garrison(key, GlobalUnits.SPOT.OUTSIDE, b.get("start_outside"))
	else:
		_seed_garrison(_building_key(b), GlobalUnits.SPOT.FLAT, b.get("start_garrison"))


func _seed_garrison(building_key: String, spot: int, spec) -> void:
	if spec == null or (spec is Array and spec.is_empty()):
		return
	forces[_garrison_force_id(building_key, spot)] = {
		"units": GlobalUnits.units_from_spec(spec),
		"location": {"kind": "garrison", "building": building_key, "spot": spot},
		"cargo": GlobalUnits.empty_caravan_cargo(),
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


# --- Force cargo (battle loot / army stockpile: weapons + materials) --------

func get_force_cargo(fid: String) -> Dictionary:
	if not forces.has(fid):
		return GlobalUnits.empty_caravan_cargo()
	return GlobalUnits.sanitize_caravan_cargo(forces[fid].get("cargo", {}))


func set_force_cargo(fid: String, cargo: Dictionary, check_hunger_relief: bool = true) -> void:
	if not forces.has(fid):
		return
	forces[fid]["cargo"] = GlobalUnits.sanitize_caravan_cargo(cargo)
	if check_hunger_relief:
		clear_force_hunger_if_relieved(fid)


func add_force_cargo(fid: String, add: Dictionary) -> void:
	if not forces.has(fid):
		return
	set_force_cargo(fid, GlobalUnits.add_caravan_stocks(get_force_cargo(fid), add))


func take_force_cargo(fid: String, want: Dictionary) -> Dictionary:
	if not forces.has(fid):
		return GlobalUnits.empty_caravan_cargo()
	var have := get_force_cargo(fid)
	var taken := GlobalUnits.clamp_caravan_stock(have, want)
	var left := GlobalUnits.sanitize_caravan_cargo(have)
	GlobalUnits.subtract_caravan_stock(left, taken)
	set_force_cargo(fid, left)
	return taken


func move_all_force_cargo(from_id: String, to_id: String) -> void:
	if from_id == to_id or not forces.has(from_id) or not forces.has(to_id):
		return
	var cargo := get_force_cargo(from_id)
	if not GlobalUnits.caravan_cargo_has_any(cargo):
		set_force_cargo(from_id, GlobalUnits.empty_caravan_cargo())
		return
	add_force_cargo(to_id, cargo)
	set_force_cargo(from_id, GlobalUnits.empty_caravan_cargo())


## After a unit transfer: if source has no men left, flush remaining cargo to dest.
func _flush_cargo_if_force_empty(from_id: String, to_id: String) -> void:
	if not forces.has(from_id) or not forces.has(to_id):
		return
	if GlobalUnits.total_men(forces[from_id]["units"]) > 0:
		return
	move_all_force_cargo(from_id, to_id)


func _collect_forces_cargo(force_ids: Array) -> Dictionary:
	var total := GlobalUnits.empty_caravan_cargo()
	for fid in force_ids:
		total = GlobalUnits.add_caravan_stocks(total, get_force_cargo(str(fid)))
	return total


func _clear_forces_cargo(force_ids: Array) -> void:
	for fid in force_ids:
		if forces.has(str(fid)):
			set_force_cargo(str(fid), GlobalUnits.empty_caravan_cargo())


func list_dejure_province_ids(player_id: int) -> Array:
	var out: Array = []
	for prov in provinces.get_children():
		if prov.has_method("has_dejure") and prov.has_dejure(player_id):
			out.append(str(prov.name))
	return out


func find_closest_dejure_province_id(player_id: int, from_cell: Vector2i) -> String:
	var best_id := ""
	var best_dist := 999999
	for pid in list_dejure_province_ids(player_id):
		var prov := _get_province_by_id(str(pid))
		if prov == null:
			continue
		var town = prov.get_town() if prov.has_method("get_town") else null
		if town == null:
			continue
		var approach := get_free_approach_cell_for(town)
		if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
			var cells = pathfinding.get_approach_cells(town) if pathfinding != null else []
			if cells.is_empty():
				continue
			approach = cells[0]
		var d := _path_dist(from_cell, approach)
		if d < best_dist:
			best_dist = d
			best_id = str(pid)
	return best_id


func province_under_force(force_id: String):
	var cell := _force_anchor_cell(force_id)
	if cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return null
	return find_province_for_cell(cell)


# --- VIP characters ---------------------------------------------------------

func seed_starting_vips() -> void:
	vips.clear()
	_next_vip_id = 1
	var pids: Array = players.keys()
	pids.sort()
	for pid in pids:
		if int(players[pid].status) != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue
		# Local councils are pocket managers — no royal household.
		if GlobalStuff.is_local_council(players[pid].type):
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
			"cargo": GlobalUnits.empty_caravan_cargo(),
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


func get_force_anchor_cell(force_id: String) -> Vector2i:
	return _force_anchor_cell(force_id)


func _force_anchor_cell(force_id: String) -> Vector2i:
	var invalid := Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	if not forces.has(force_id):
		return invalid
	var loc: Dictionary = forces[force_id].get("location", {})
	var kind := str(loc.get("kind", ""))
	if kind == "garrison":
		var b := _building_from_key(str(loc.get("building", "")))
		if b == null:
			return invalid
		var approach = pathfinding.get_approach_cells(b)
		if approach.is_empty():
			return invalid
		return approach[0]
	if kind == "aboard":
		var fleet := get_fleet_by_id(str(loc.get("fleet", "")))
		if fleet == null:
			return invalid
		return pathfinding.get_army_cell(fleet)
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
	var attacker_id := str(enemy_force_ids[0]) if not enemy_force_ids.is_empty() else ""
	var base := get_building_battle_strength(building, attacker_id)
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
	var kind := str(loc.get("kind", ""))
	if kind == "garrison":
		var b := _building_from_key(str(loc.get("building", "")))
		if b != null and b is Node2D:
			return (b as Node2D).global_position
		return Vector2.ZERO
	if kind == "aboard":
		var fleet := get_fleet_by_id(str(loc.get("fleet", "")))
		if fleet != null:
			return fleet.global_position + Vector2(32, 16)
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
	hostage_pool: Array,
	loot: Dictionary = {},
	loot_force_id: String = "",
	hostage_units: Array = []
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
		"hostage_units": GlobalUnits.clone_units(hostage_units if not hostage_units.is_empty() else hostage_pool),
		"loot": GlobalUnits.sanitize_weapon_stock(loot),
		"loot_force_id": loot_force_id,
		"attacker_side_ids": atk_side,
		"defender_side_ids": def_side,
		"participant_ids": participants,
		"place_name": _battle_place_name(building, attacker_id, defender_army_id),
		"world_x": pos.x,
		"world_y": pos.y,
		"actor_id": get_force_controller(attacker_id),
		"captured_wages": 0,
		"wage_transfers": [],
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
	var kind := str(loc.get("kind", ""))
	var is_garrison := kind == "garrison"
	if not vip_ids.is_empty() and is_garrison:
		return
	if not vip_ids.is_empty() and not is_garrison:
		var ctrl := get_force_controller(fid)
		relocate_vips_from_disbanded_force(fid, ctrl)
	if kind == "aboard":
		var fleet := get_fleet_by_id(str(loc.get("fleet", "")))
		if fleet != null:
			fleet.aboard_force_ids.erase(fid)
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
	# Fleet selected → landing UI on the shore army's cell.
	if selected != null and selected.has_method("is_fleet") and selected.is_fleet():
		if pathfinding.are_armies_adjacent(selected, army):
			pathfinding.deselect_army()
			open_fleet_disembark_prompt(selected, pathfinding.get_army_cell(army))
		return
	# A different army is selected: interact if adjacent, else move to approach.
	if selected != null and selected != army:
		if pathfinding.are_armies_adjacent(selected, army):
			pathfinding.open_army_interaction(selected, army)
		else:
			pathfinding.confirm_move_to_army(army)
		return
	if army.is_controllable_by(my_pl_id):
		# First click selects for movement; second click (selected == army) opens menu.
		# No MP left → open menu with Move disabled.
		if army.movement_left > 0:
			pathfinding.select_army(army)
		else:
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
	if army.has_method("is_fleet") and army.is_fleet():
		var cell = pathfinding.get_army_cell(army)
		var stack: Array = pathfinding.fleets_at_cell(cell)
		if stack.size() > 1 and is_instance_valid(gui_node) and gui_node.has_method("open_fleet_stack_picker"):
			gui_node.open_fleet_stack_picker(self, stack)
			return
		if army.is_controllable_by(my_pl_id) and is_instance_valid(gui_node) \
				and gui_node.has_method("open_fleet_menu"):
			gui_node.open_fleet_menu(self, army)
		return
	if army.is_controllable_by(my_pl_id):
		gui_node.open_army_menu(self, army)
	elif army.has_units_of(my_pl_id):
		gui_node.open_withdraw_menu(self, army)
	else:
		show_army_owner_popup(army)


func _on_army_interaction(mover: Node2D, target: Node2D) -> void:
	if mover == null or target == null or not is_instance_valid(mover) or not is_instance_valid(target):
		return
	# Fleets land via the shore prompt, not army↔army interaction.
	if mover.has_method("is_fleet") and mover.is_fleet():
		if pathfinding.are_armies_adjacent(mover, target) \
				and not (target.has_method("is_caravan") and target.is_caravan()) \
				and not (target.has_method("is_fleet") and target.is_fleet()):
			pathfinding.deselect_army()
			open_fleet_disembark_prompt(mover, pathfinding.get_army_cell(target))
		return
	# Land army → adjacent fleet: embark (picker if stacked).
	if target.has_method("is_fleet") and target.is_fleet():
		pathfinding.deselect_army()
		_try_open_army_embark(mover, target)
		return
	# Army approaching a caravan: capture menu for enemies; own/ally → inspect.
	if target.has_method("is_caravan") and target.is_caravan():
		pathfinding.deselect_army()
		if are_friendly_players(mover.get_controller(), target.get_controller()):
			if target.is_controllable_by(my_pl_id) and is_instance_valid(gui_node) \
					and gui_node.has_method("open_caravan_menu"):
				gui_node.open_caravan_menu(self, target)
			elif is_instance_valid(gui_node):
				gui_node.show_info_popup("Friendly caravan")
			return
		if is_instance_valid(gui_node) and gui_node.has_method("open_caravan_capture_menu"):
			gui_node.open_caravan_capture_menu(self, mover, target)
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


func on_caravan_clicked(caravan: Node2D) -> void:
	if is_mouse_over_gui():
		return
	var selected = pathfinding.selected_army if pathfinding != null else null
	# Army selected: interact if adjacent, else approach (capture for enemies).
	if selected != null and not (selected.has_method("is_caravan") and selected.is_caravan()):
		if selected.has_method("is_fleet") and selected.is_fleet():
			return
		if pathfinding.are_armies_adjacent(selected, caravan):
			pathfinding.open_army_interaction(selected, caravan)
		else:
			pathfinding.confirm_move_to_army(caravan)
		return
	if caravan.is_controllable_by(my_pl_id):
		if is_instance_valid(gui_node) and gui_node.has_method("open_caravan_menu"):
			gui_node.open_caravan_menu(self, caravan)
	else:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Enemy caravan — move an army next to it to capture")


func get_fleet_by_id(fleet_id: String) -> Node2D:
	if fleets == null or fleet_id == "":
		return null
	return fleets.get_node_or_null(fleet_id) as Node2D


func on_fleet_clicked(fleet: Node2D) -> void:
	if is_mouse_over_gui() or fleet == null:
		return
	var selected = pathfinding.selected_army if pathfinding != null else null
	# Fleet selected: combine / move via confirm_move.
	if selected != null and selected.has_method("is_fleet") and selected.is_fleet():
		if selected == fleet:
			open_selected_army_menu(fleet)
			return
		if pathfinding.are_armies_adjacent(selected, fleet):
			if selected.get_controller() == fleet.get_controller():
				pathfinding.deselect_army()
				open_fleet_combine_prompt(selected, fleet, pathfinding.get_army_cell(fleet))
			return
		# Move toward that sea tile.
		pathfinding.confirm_move_to_army(fleet)
		return
	# Land army selected: click fleet to embark (or approach if not adjacent).
	if selected != null and not (selected.has_method("is_fleet") and selected.is_fleet()) \
			and not (selected.has_method("is_caravan") and selected.is_caravan()):
		if not fleet.is_controllable_by(my_pl_id):
			if is_instance_valid(gui_node):
				gui_node.show_info_popup("Enemy transport fleet")
			return
		if pathfinding.are_armies_adjacent(selected, fleet):
			pathfinding.deselect_army()
			_try_open_army_embark(selected, fleet)
		else:
			pathfinding.confirm_move_to_army(fleet)
		return

	var cell = pathfinding.get_army_cell(fleet)
	var stack: Array = pathfinding.fleets_at_cell(cell)
	if stack.size() > 1:
		if is_instance_valid(gui_node) and gui_node.has_method("open_fleet_stack_picker"):
			gui_node.open_fleet_stack_picker(self, stack)
		return
	if fleet.is_controllable_by(my_pl_id):
		if is_instance_valid(gui_node) and gui_node.has_method("open_fleet_menu"):
			gui_node.open_fleet_menu(self, fleet)
	else:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Enemy transport fleet")


## Own fleets on the same sea tile as `fleet`, for embark choice.
func own_fleets_at_fleet_tile(fleet: Node2D) -> Array:
	var out: Array = []
	if fleet == null or pathfinding == null:
		return out
	for f in pathfinding.fleets_at_cell(pathfinding.get_army_cell(fleet)):
		if f != null and is_instance_valid(f) and f.is_controllable_by(my_pl_id):
			out.append(f)
	return out


func _try_open_army_embark(army: Node2D, fleet: Node2D) -> void:
	if army == null or fleet == null:
		return
	if not fleet.is_controllable_by(my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Enemy transport fleet")
		return
	var stack: Array = own_fleets_at_fleet_tile(fleet)
	if stack.is_empty():
		return
	if stack.size() > 1 and is_instance_valid(gui_node) \
			and gui_node.has_method("open_fleet_embark_picker"):
		gui_node.open_fleet_embark_picker(self, army, stack)
		return
	open_fleet_embark_prompt(stack[0] if stack.size() == 1 else fleet, army)


func open_fleet_embark_prompt(fleet: Node2D, army: Node2D) -> void:
	if not is_instance_valid(gui_node) or not gui_node.has_method("open_fleet_embark_prompt"):
		return
	gui_node.open_fleet_embark_prompt(self, fleet, army)


func open_fleet_disembark_prompt(fleet: Node2D, land_cell: Vector2i) -> void:
	if not is_instance_valid(gui_node) or not gui_node.has_method("open_fleet_disembark_prompt"):
		return
	gui_node.open_fleet_disembark_prompt(self, fleet, land_cell)


func open_fleet_combine_prompt(mover: Node2D, target: Node2D, dest_cell: Vector2i) -> void:
	if not is_instance_valid(gui_node) or not gui_node.has_method("open_fleet_combine_prompt"):
		return
	gui_node.open_fleet_combine_prompt(self, mover, target, dest_cell)


func set_pending_fleet_combine(mover_name: String, target: Node2D) -> void:
	clear_pending_garrison()
	clear_pending_army_interaction()
	_pending_fleet_combine_mover_name = mover_name
	_pending_fleet_combine_target = target


func clear_pending_fleet_combine() -> void:
	_pending_fleet_combine_mover_name = ""
	_pending_fleet_combine_target = null


func refresh_fleet_stack_visuals() -> void:
	if fleets == null or pathfinding == null:
		return
	for cell in pathfinding.fleet_occupancy.keys():
		var stack: Array = pathfinding.fleet_occupancy[cell]
		var owner_pids: Array = []
		for f in stack:
			var pid := int(f.get_controller()) if f.has_method("get_controller") else int(f.player_owner)
			if not owner_pids.has(pid):
				owner_pids.append(pid)
		owner_pids.sort()
		# Stable primary: lowest name.
		var primary: Node2D = null
		for f in stack:
			if primary == null or String(f.name) < String(primary.name):
				primary = f
		for f in stack:
			if f.has_method("set_stack_display"):
				f.set_stack_display(f == primary, owner_pids)


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
	if building == null:
		return false
	if building.has_method("get_controller_id"):
		var cid := int(building.get_controller_id())
		if cid < 0:
			return false
		return are_friendly_players(player_id, cid)
	if building.get("player_owner") == null:
		return false
	return are_friendly_players(player_id, int(building.player_owner))


func get_building_fighting_units(building: Node) -> Array:
	return GlobalUnits.fighting_units(get_all_building_garrison(building))


func get_building_battle_strength(building: Node, attacker_id: String = "") -> int:
	if building == null:
		return 0
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	if is_castle:
		var inside_bonus := GlobalUnits.CASTLE_INSIDE_BONUS
		if attacker_id != "":
			inside_bonus = GlobalUnits.siege_inside_bonus(get_force_siege_level_vs(attacker_id, building))
		var inside_str := GlobalUnits.fighting_strength(
			get_building_garrison(building, GlobalUnits.SPOT.INSIDE), inside_bonus
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
	# Empty / under-construction castle plots are non-interactable worksites.
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		if building.has_method("is_army_interactable") and not building.is_army_interactable():
			gui_node.show_info_popup("Castle worksite — armies cannot interact here")
			return
	var controller := get_force_controller(force_id)
	if is_building_friendly_to(building, controller):
		gui_node.open_garrison_menu(self, force_id, building)
		return
	var has_garrison := GlobalUnits.fighting_men(get_all_building_garrison(building)) > 0
	var needs_settlement_fight := settlement_requires_battle(building, force_id)
	if not has_garrison and not needs_settlement_fight:
		gui_node.open_building_actions_menu(self, force_id, building)
		return
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	if is_castle and not is_force_sieging_building(force_id, building):
		gui_node.open_siege_prompt(self, force_id, building)
		return
	gui_node.open_battle_menu(self, force_id, "", building)


# --- Siege engines (castle assaults) ----------------------------------------

func get_force_siege(force_id: String) -> Dictionary:
	if not forces.has(force_id):
		return {}
	var s = forces[force_id].get("siege", null)
	if s == null or typeof(s) != TYPE_DICTIONARY:
		return {}
	return s


func is_force_sieging(force_id: String) -> bool:
	return not get_force_siege(force_id).is_empty()


func is_force_sieging_building(force_id: String, building: Node) -> bool:
	if building == null:
		return false
	var s := get_force_siege(force_id)
	if s.is_empty():
		return false
	return str(s.get("building", "")) == _building_key(building)


func get_force_siege_level(force_id: String) -> int:
	var s := get_force_siege(force_id)
	if s.is_empty():
		return 0
	return clampi(int(s.get("level", 0)), 0, GlobalUnits.SIEGE_MAX_LEVEL)


## Level used vs this castle: real engines if sieging it, else 0 (worst bonus).
func get_force_siege_level_vs(force_id: String, building: Node) -> int:
	if is_force_sieging_building(force_id, building):
		return get_force_siege_level(force_id)
	return 0


func force_siege_status_text(force_id: String) -> String:
	var s := get_force_siege(force_id)
	if s.is_empty():
		return ""
	var lvl := clampi(int(s.get("level", 0)), 0, GlobalUnits.SIEGE_MAX_LEVEL)
	var b := _building_from_key(str(s.get("building", "")))
	var place := _building_display_name(b) if b is Node2D else "castle"
	return "Sieging %s — engines %d/%d" % [place, lvl, GlobalUnits.SIEGE_MAX_LEVEL]


func clear_force_siege(force_id: String) -> void:
	if not forces.has(force_id):
		return
	if forces[force_id].has("siege"):
		forces[force_id].erase("siege")
	_sync_force_siege_fx(force_id)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


## Client entry when a synced apply_* path is not available (e.g. caravan seize).
func do_clear_force_siege(force_id: String) -> void:
	request_clear_force_siege.rpc_id(1, force_id)


@rpc("any_peer", "call_local", "reliable")
func request_clear_force_siege(force_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not is_force_sieging(force_id):
		return
	apply_clear_force_siege.rpc(force_id)


@rpc("authority", "call_local", "reliable")
func apply_clear_force_siege(force_id: String) -> void:
	clear_force_siege(force_id)


func do_start_siege(force_id: String, building: Node) -> void:
	if building == null:
		return
	request_start_siege.rpc_id(1, force_id, _building_key(building))


@rpc("any_peer", "call_local", "reliable")
func request_start_siege(force_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	var building := _building_from_key(building_key)
	if building == null:
		return
	if building.get("type_") == null or building.type_ != GlobalStuff.BUILDING_TYPE.CASTLE:
		return
	if is_building_friendly_to(building, get_force_controller(force_id)):
		return
	if GlobalUnits.fighting_men(get_all_building_garrison(building)) <= 0:
		return
	var army = armies.get_node_or_null(force_id)
	if army == null:
		return
	var army_cell = pathfinding.get_army_cell(army)
	if army_cell not in pathfinding.get_approach_cells(building):
		return
	apply_start_siege.rpc(force_id, building_key)


@rpc("authority", "call_local", "reliable")
func apply_start_siege(force_id: String, building_key: String) -> void:
	if not forces.has(force_id):
		return
	forces[force_id]["siege"] = {
		"building": building_key,
		"level": 0,
	}
	_sync_force_siege_fx(force_id)
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_army_menu_if_force"):
			gui_node.refresh_army_menu_if_force(force_id)
		if get_force_controller(force_id) == my_pl_id:
			gui_node.show_info_popup("Siege begun — engines will improve each season")


func tick_all_sieges() -> void:
	var fids: Array = forces.keys()
	for fid in fids:
		if not forces.has(fid):
			continue
		var s := get_force_siege(str(fid))
		if s.is_empty():
			continue
		var bkey := str(s.get("building", ""))
		var building := _building_from_key(bkey)
		# Drop invalid sieges (razed / gone / friendly / empty).
		if building == null or is_building_razed(building) \
				or is_building_friendly_to(building, get_force_controller(str(fid))) \
				or GlobalUnits.fighting_men(get_all_building_garrison(building)) <= 0:
			clear_force_siege(str(fid))
			continue
		var army = armies.get_node_or_null(str(fid))
		if army == null:
			clear_force_siege(str(fid))
			continue
		var army_cell = pathfinding.get_army_cell(army)
		if army_cell not in pathfinding.get_approach_cells(building):
			clear_force_siege(str(fid))
			continue
		var lvl := clampi(int(s.get("level", 0)), 0, GlobalUnits.SIEGE_MAX_LEVEL)
		if lvl >= GlobalUnits.SIEGE_MAX_LEVEL:
			continue
		lvl += 1
		forces[fid]["siege"]["level"] = lvl
		_sync_force_siege_fx(str(fid))
		if lvl >= GlobalUnits.SIEGE_MAX_LEVEL:
			_make_siege_complete_event(str(fid), building)


func _make_siege_complete_event(force_id: String, building: Node) -> void:
	var controller := get_force_controller(force_id)
	if controller < 0:
		return
	var place := _building_display_name(building) if building is Node2D else "castle"
	var pos := _force_world_pos(force_id)
	var event := {
		"kind": GameEvents.KIND.SIEGE,
		"text": "An army has completed all its siege engines at %s." % place,
		"turn": turn,
		"season": int(season),
		"place_name": place,
		"world_x": pos.x,
		"world_y": pos.y,
		"participant_ids": [controller],
		"force_id": force_id,
		"actor_id": -1,
	}
	var eid := _register_event(event)
	_deliver_event_to_players(eid, [controller], -1, false)


const SIEGE_HAMMER_SCRIPT := preload("res://objects/overworld/othr/siege_hammer/siege_hammer.gd")


func _set_siege_hammer_on(host: Node2D, on: bool) -> void:
	if host == null:
		return
	var existing = host.get_node_or_null("SiegeHammer")
	if on:
		if existing != null:
			return
		var hammer := Node2D.new()
		hammer.name = "SiegeHammer"
		hammer.set_script(SIEGE_HAMMER_SCRIPT)
		host.add_child(hammer)
		hammer.position = Vector2(40, 4)
	elif existing != null:
		host.remove_child(existing)
		existing.queue_free()


func _sync_force_siege_fx(fid: String) -> void:
	var fig := armies.get_node_or_null(fid) as Node2D
	if fig == null:
		return
	_set_siege_hammer_on(fig, is_force_sieging(fid))


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


func settlement_tax_marks(building: Node) -> int:
	if building == null or building.get("tax_marks") == null:
		return 0
	return maxi(0, int(building.tax_marks))


func compute_raid_loot(building: Node) -> int:
	var prov := find_province_for_building(building)
	if prov == null:
		return 0
	# Empty settlements cannot be looted.
	if is_settlement_building(building) and not settlement_has_population(building):
		return 0
	prov.recalculate_marks_will_by_player()
	prov.update_population_in_resources()
	var marks_will := province_predicted_marks_total(prov)
	var type_ = building.get("type_")
	var base_loot := 0
	if type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		base_loot = int(floor(float(marks_will) * 0.10))
	elif type_ == GlobalStuff.BUILDING_TYPE.ECONOMY:
		base_loot = int(floor(float(marks_will) * 0.05))
	else:
		# Village / town: share of province tax forecast by settlement pop ratio.
		var sett_pop := int(building.get("population") if building.get("population") != null else 0)
		var prov_pop := province_total_population(prov)
		if prov_pop > 0 and sett_pop > 0:
			base_loot = int(floor(float(marks_will) * float(sett_pop) / float(prov_pop)))
	# Plus any uncollected tax sitting in the settlement coffer.
	return base_loot + settlement_tax_marks(building)


func compute_raze_loot(building: Node) -> int:
	return int(floor(float(compute_raid_loot(building)) * RAZE_LOOT_MULT))


func is_settlement_building(building: Node) -> bool:
	if building == null or building.get("type_") == null:
		return false
	var type_ := int(building.type_)
	return type_ == GlobalStuff.BUILDING_TYPE.TOWN or type_ == GlobalStuff.BUILDING_TYPE.VILLAGE


func settlement_has_population(building: Node) -> bool:
	if not is_settlement_building(building):
		return false
	return int(building.get("population") if building.get("population") != null else 0) > 0


const RAZE_RECOVERY_SEASONS := 2
const RAID_SMOKE_INTENSITY := 0.35
const RAZE_SMOKE_INTENSITY_FULL := 1.0
const RAZE_SMOKE_INTENSITY_FADED := 0.45
const RAID_MP_COST := 4
const FIELD_RAID_MP_COST := 2
const CAPTURE_MP_COST := 2
const RAZE_MP_COST := 8
const SETTLEMENT_BATTLE_MP_COST := 1
const RAID_POP_KEEP := 0.8 ## lose 20%
const RAZE_POP_KEEP := 0.5 ## lose 50%
const RAZE_LOOT_MULT := 1.5
const MILITIA_POP_FRACTION := 0.5
const MILITIA_ARM_FRACTION := 0.5
## Only these weapons arm militia (round-robin).
const MILITIA_ARM_WEAPONS := ["maces", "pikes", "bows"]


func settlement_militia_fights(building: Node) -> bool:
	if building == null:
		return true
	return bool(building.get_meta("militia_fights", true))


func set_settlement_militia_fights(building: Node, enabled: bool) -> void:
	if building == null or not is_settlement_building(building):
		return
	request_set_militia_fights.rpc_id(1, _building_key(building), enabled)


@rpc("any_peer", "call_local", "reliable")
func request_set_militia_fights(building_key: String, enabled: bool) -> void:
	if not multiplayer.is_server():
		return
	var building := _building_from_key(building_key)
	if building == null or not is_settlement_building(building):
		return
	apply_set_militia_fights.rpc(building_key, enabled)


@rpc("authority", "call_local", "reliable")
func apply_set_militia_fights(building_key: String, enabled: bool) -> void:
	var building := _building_from_key(building_key)
	if building == null:
		return
	building.set_meta("militia_fights", enabled)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_force_menu_if_open"):
		gui_node.refresh_force_menu_if_open()


func settlement_militia_beaten_this_season(building: Node) -> bool:
	if building == null:
		return false
	return int(building.get_meta("last_militia_battle_turn", -1)) == turn


func eligible_militia_size(building: Node) -> int:
	if not is_settlement_building(building) or not settlement_has_population(building):
		return 0
	return int(floor(float(int(building.population)) * MILITIA_POP_FRACTION))


## Preview militia roster without mutating stock / population.
func compose_settlement_militia(building: Node) -> Dictionary:
	var out := {
		"units": [],
		"men": 0,
		"armed": 0,
		"peasants": 0,
		"weapons_used": GlobalUnits.empty_weapon_stock(),
	}
	var men := eligible_militia_size(building)
	if men <= 0:
		return out
	var owner_id := int(building.player_owner) if building.get("player_owner") != null else -1
	if owner_id < 0:
		return out
	var prov := find_province_for_building(building)
	var stock := GlobalUnits.empty_weapon_stock()
	if prov != null and prov.has_method("get_weapons_for"):
		stock = prov.get_weapons_for(owner_id)
	var arm_target := int(floor(float(men) * MILITIA_ARM_FRACTION))
	var armed_counts := {"maces": 0, "pikes": 0, "bows": 0}
	var armed := 0
	var guard := arm_target + 4
	while armed < arm_target and guard > 0:
		guard -= 1
		var progressed := false
		for wk in MILITIA_ARM_WEAPONS:
			if armed >= arm_target:
				break
			if int(stock.get(wk, 0)) <= 0:
				continue
			stock[wk] = int(stock[wk]) - 1
			armed_counts[wk] = int(armed_counts[wk]) + 1
			out["weapons_used"][wk] = int(out["weapons_used"].get(wk, 0)) + 1
			armed += 1
			progressed = true
		if not progressed:
			break
	var units: Array = []
	var weapon_unit := {
		"maces": GlobalUnits.UNIT_TYPE.MACEMEN,
		"pikes": GlobalUnits.UNIT_TYPE.PIKEMEN,
		"bows": GlobalUnits.UNIT_TYPE.ARCHER,
	}
	for wk in MILITIA_ARM_WEAPONS:
		var n := int(armed_counts.get(wk, 0))
		if n > 0:
			GlobalUnits.add_stack(units, GlobalUnits.make_stack(
				int(weapon_unit[wk]), owner_id, GlobalUnits.SOURCE.LEVY, n,
				GlobalUnits.STATUS.FIGHTING, 0, false, true
			))
	var peasants := men - armed
	if peasants > 0:
		GlobalUnits.add_stack(units, GlobalUnits.make_stack(
			GlobalUnits.UNIT_TYPE.PEASANT, owner_id, GlobalUnits.SOURCE.LEVY, peasants,
			GlobalUnits.STATUS.FIGHTING, 0, false, true
		))
	out["units"] = units
	out["men"] = men
	out["armed"] = armed
	out["peasants"] = peasants
	return out


## True when militia should join / form for this attacker (toggle + season + odds).
func settlement_should_raise_militia(building: Node, attacker_force_id: String) -> bool:
	if not is_settlement_building(building):
		return false
	if not settlement_militia_fights(building):
		return false
	if settlement_militia_beaten_this_season(building):
		return false
	if eligible_militia_size(building) <= 0:
		return false
	# Population will not rise against their previous lord (or that lord's allies).
	var atk := get_force_controller(attacker_force_id)
	var loyal_to := settlement_militia_loyal_to(building)
	if loyal_to >= 0 and atk >= 0 and are_friendly_players(atk, loyal_to):
		return false
	var has_garrison := GlobalUnits.fighting_men(get_all_building_garrison(building)) > 0
	if has_garrison:
		return true
	# No garrison: fight only if attacker does not outnumber militia 2×.
	var atk_men := 0
	if forces.has(attacker_force_id):
		atk_men = GlobalUnits.fighting_men(forces[attacker_force_id]["units"])
	var militia_men := eligible_militia_size(building)
	return atk_men <= militia_men * 2


func settlement_militia_loyal_to(building: Node) -> int:
	if building == null:
		return -1
	return int(building.get_meta("militia_loyal_to", -1))


func set_settlement_militia_loyal_to(building: Node, player_id: int) -> void:
	if building == null or not is_settlement_building(building):
		return
	if player_id < 0:
		if building.has_meta("militia_loyal_to"):
			building.remove_meta("militia_loyal_to")
		return
	building.set_meta("militia_loyal_to", player_id)


## Clear loyalty on settlements owned by `owner_id` once they hold both dejure and defacto.
func try_clear_militia_loyalty_for_province(prov: Node, owner_id: int) -> void:
	if prov == null or owner_id < 0:
		return
	var no_defacto := -1
	if prov.get("NO_DEFACTO") != null:
		no_defacto = int(prov.NO_DEFACTO)
	var dejure := int(prov.dejure) if prov.get("dejure") != null else -1
	var defacto = prov.get("defacto")
	if defacto == null or int(defacto) == no_defacto:
		return
	if dejure != owner_id or int(defacto) != owner_id:
		return
	var owned: Array = []
	if prov.has_method("get_owned_settlements"):
		owned = prov.get_owned_settlements(owner_id)
	else:
		return
	for s in owned:
		if s != null and s.has_meta("militia_loyal_to"):
			s.remove_meta("militia_loyal_to")


## Hostile settlement needs a battle before Capture/Raid/Raze.
func settlement_requires_battle(building: Node, attacker_force_id: String) -> bool:
	if not is_settlement_building(building):
		return false
	if GlobalUnits.fighting_men(get_all_building_garrison(building)) > 0:
		return true
	return settlement_should_raise_militia(building, attacker_force_id)


## Garrison + pending militia for battle preview (does not mutate).
func get_settlement_defense_preview(building: Node, attacker_force_id: String) -> Dictionary:
	var garrison := GlobalUnits.clone_units(get_all_building_garrison(building))
	var militia_men := 0
	if bool(building.get_meta("militia_in_field", false)):
		var split: Dictionary = GlobalUnits.split_militia_units(garrison)
		militia_men = GlobalUnits.total_men(split.get("militia", []))
	elif settlement_should_raise_militia(building, attacker_force_id):
		var composed := compose_settlement_militia(building)
		militia_men = int(composed.get("men", 0))
		garrison = GlobalUnits.merge_units(garrison, composed.get("units", []))
	return {
		"units": garrison,
		"men": GlobalUnits.fighting_men(garrison),
		"strength": GlobalUnits.fighting_strength(garrison, GlobalUnits.CASTLE_OUTSIDE_BATTLE_BONUS),
		"militia_men": militia_men,
	}


func _ensure_flat_garrison_force(building: Node) -> String:
	var key := _building_key(building)
	var fid := _garrison_force_id(key, GlobalUnits.SPOT.FLAT)
	if not forces.has(fid):
		forces[fid] = {
			"units": [],
			"location": {"kind": "garrison", "building": key, "spot": GlobalUnits.SPOT.FLAT},
			"cargo": GlobalUnits.empty_caravan_cargo(),
			"controller": int(building.player_owner) if building.get("player_owner") != null else -1,
		}
	return fid


## Raise militia into the FLAT garrison: deduct pop + weapons immediately.
## Prefer apply_settlement_militia_raise on all peers via battle events for sync.
func raise_settlement_militia(building: Node) -> Dictionary:
	var empty := {
		"ok": false,
		"units": [],
		"men": 0,
		"weapons_used": GlobalUnits.empty_weapon_stock(),
	}
	if building == null or not is_settlement_building(building):
		return empty
	if bool(building.get_meta("militia_in_field", false)):
		var split: Dictionary = GlobalUnits.split_militia_units(get_all_building_garrison(building))
		return {
			"ok": true,
			"units": split.get("militia", []),
			"men": GlobalUnits.total_men(split.get("militia", [])),
			"weapons_used": GlobalUnits.empty_weapon_stock(),
			"already_raised": true,
		}
	var composed := compose_settlement_militia(building)
	var men := int(composed.get("men", 0))
	if men <= 0:
		return empty
	return {
		"ok": true,
		"units": composed.get("units", []),
		"men": men,
		"weapons_used": composed.get("weapons_used", GlobalUnits.empty_weapon_stock()),
		"already_raised": false,
	}


func apply_settlement_militia_raise(building: Node, men: int, weapons_used: Dictionary, units: Array) -> void:
	if building == null or men <= 0:
		return
	if bool(building.get_meta("militia_in_field", false)):
		return
	var owner_id := int(building.player_owner) if building.get("player_owner") != null else -1
	var prov := find_province_for_building(building)
	if prov != null and GlobalUnits.weapon_stock_has_any(weapons_used):
		prov.subtract_weapons_for(owner_id, weapons_used)
	building.population = maxi(0, int(building.population) - men)
	if building.has_method("refresh_visuals"):
		building.refresh_visuals()
	var fid := _ensure_flat_garrison_force(building)
	forces[fid]["units"] = GlobalUnits.merge_units(forces[fid]["units"], units)
	building.set_meta("militia_in_field", true)
	building.set_meta("militia_raised_men", men)


func _return_militia_to_settlement(building: Node, militia_units: Array) -> void:
	if building == null or militia_units.is_empty():
		return
	var men := GlobalUnits.total_men(militia_units)
	if men > 0:
		building.population = int(building.population) + men
		if building.has_method("refresh_visuals"):
			building.refresh_visuals()
	var owner_id := int(building.player_owner) if building.get("player_owner") != null else -1
	var prov := find_province_for_building(building)
	if prov != null and owner_id >= 0:
		var refund := GlobalUnits.weapons_from_units(militia_units, owner_id)
		if GlobalUnits.weapon_stock_has_any(refund):
			prov.add_weapons_for(owner_id, refund)


func _deposit_battle_loot_to_province(building: Node, loot: Dictionary) -> void:
	if building == null:
		return
	var owner_id := int(building.player_owner) if building.get("player_owner") != null else -1
	if owner_id < 0:
		return
	var prov := find_province_for_building(building)
	if prov == null:
		return
	var cargo := GlobalUnits.sanitize_caravan_cargo(loot)
	var weapons := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_KEYS:
		weapons[k] = int(cargo.get(k, 0))
	if GlobalUnits.weapon_stock_has_any(weapons) and prov.has_method("add_weapons_for"):
		prov.add_weapons_for(owner_id, weapons)
	for mk in GlobalUnits.MATERIAL_KEYS:
		var amt := int(cargo.get(mk, 0))
		if amt > 0 and prov.has_method("add_player_material"):
			prov.add_player_material(owner_id, mk, amt)


func mark_settlement_militia_beaten(building: Node) -> void:
	if building == null:
		return
	building.set_meta("last_militia_battle_turn", turn)
	building.set_meta("militia_in_field", false)
	building.set_meta("militia_raised_men", 0)


func clear_settlement_militia_field_flag(building: Node) -> void:
	if building == null:
		return
	building.set_meta("militia_in_field", false)
	building.set_meta("militia_raised_men", 0)


func is_building_razed(building: Node) -> bool:
	if building == null or building.get("STAGES") == null:
		return false
	return building.stage == building.STAGES.RAZED


func get_force_army(force_id: String) -> Node:
	if force_id == "" or armies == null:
		return null
	return armies.get_node_or_null(force_id)


func force_has_movement(force_id: String, cost: int) -> bool:
	var army = get_force_army(force_id)
	return army != null and int(army.movement_left) >= cost


func spend_force_movement(force_id: String, cost: int) -> bool:
	var army = get_force_army(force_id)
	if army == null or int(army.movement_left) < cost:
		return false
	army.movement_left = maxi(0, int(army.movement_left) - cost)
	update_all_army_visuals()
	return true


func can_raid_building(building: Node) -> bool:
	if building == null:
		return false
	if building.get("type_") != null and int(building.type_) == GlobalStuff.BUILDING_TYPE.FIELD:
		return can_raid_field(building)
	if is_building_razed(building):
		return false
	if is_settlement_building(building) and not settlement_has_population(building):
		return false
	var last_t := int(building.get_meta("last_raid_turn", -1))
	return last_t != turn


func can_raid_field(field: Node) -> bool:
	if field == null or field.get("type_") == null:
		return false
	if int(field.type_) != GlobalStuff.BUILDING_TYPE.FIELD:
		return false
	var last_t := int(field.get_meta("last_raid_turn", -1))
	if last_t == turn:
		return false
	var crop := int(field.get("crop"))
	if crop == 1: # GRAIN
		# Winter / unplanted / idle grain cannot be raided.
		if int(season) == 0:
			return false
		return bool(field.get("planted"))
	if crop == 2: # HORSES
		var prov := find_province_for_building(field)
		if prov == null or not prov.has_method("horses_on_field"):
			return false
		return int(prov.horses_on_field(field)) > 0
	return false


func field_raid_preview(field: Node) -> Dictionary:
	## {ok, reason, grain, horses, burn_only, summary}
	var out := {
		"ok": false,
		"reason": "",
		"grain": 0,
		"horses": 0,
		"burn_only": false,
		"summary": "",
	}
	if field == null or not can_raid_field(field):
		out["reason"] = "Cannot raid this field"
		return out
	var prov := find_province_for_building(field)
	var crop := int(field.get("crop"))
	if crop == 1: # GRAIN
		var share := 0.0
		if prov != null and prov.has_method("grain_share_for_field"):
			share = float(prov.grain_share_for_field(field))
		var loot := 0
		var burn_only := int(season) != 3
		if not burn_only:
			loot = int(floor(share * 0.5))
		out["ok"] = true
		out["grain"] = loot
		out["burn_only"] = burn_only
		if burn_only:
			out["summary"] = "Burn the crop (no loot)"
		else:
			out["summary"] = "Steal %d grain" % loot
		return out
	if crop == 2: # HORSES
		var horses := 0
		if prov != null and prov.has_method("horses_on_field"):
			horses = int(prov.horses_on_field(field))
		out["ok"] = horses > 0
		out["horses"] = horses
		out["summary"] = "Take %d horses" % horses
		if horses <= 0:
			out["reason"] = "No horses on this field"
		return out
	out["reason"] = "Field is empty"
	return out


func can_raze_building(building: Node) -> bool:
	if building == null:
		return false
	var type_ = building.get("type_")
	if type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		return false
	if type_ == GlobalStuff.BUILDING_TYPE.FIELD:
		return false
	if is_building_razed(building):
		return false
	if building.get("STAGES") == null:
		return false
	# Settlements: soft raze (−50% pop), once per season, needs living population.
	if is_settlement_building(building):
		if not settlement_has_population(building):
			return false
		return int(building.get_meta("last_raze_turn", -1)) != turn
	# Economy (and any other staged building): full RAZED wipe.
	return true


func do_battle_attack(
	attacker_id: String, defender_army_id: String, building: Node, landing_fleet_id: String = ""
) -> void:
	var bkey := _building_key(building) if building != null else ""
	request_battle_attack.rpc_id(1, attacker_id, defender_army_id, bkey, landing_fleet_id)


func get_landing_defender_battle_strength(defender_army_id: String, attacker_id: String) -> int:
	if not forces.has(defender_army_id):
		return 0
	var base := GlobalUnits.fighting_strength(
		forces[defender_army_id]["units"], GlobalUnits.LANDING_DEFENDER_BONUS
	)
	var ctrl := get_force_controller(defender_army_id)
	var delta := vip_combat_delta_for_sides([defender_army_id], ctrl, [attacker_id])
	return GlobalVips.apply_strength_multiplier(base, delta)


@rpc("any_peer", "call_local", "reliable")
func request_battle_attack(
	attacker_id: String,
	defender_army_id: String,
	building_key: String,
	landing_fleet_id: String = ""
) -> void:
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

	var landing_cell := Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	var is_landing := landing_fleet_id != ""
	if is_landing:
		if building != null:
			return
		var fleet = get_fleet_by_id(landing_fleet_id)
		if fleet == null:
			return
		if not fleet.aboard_force_ids.has(attacker_id):
			return
		if fleet.movement_left < GlobalUnits.TRANSPORT_LANDING_MP:
			return
		var def_fig = armies.get_node_or_null(defender_army_id)
		if def_fig == null:
			return
		landing_cell = pathfinding.get_army_cell(def_fig)
		var fleet_cell = pathfinding.get_army_cell(fleet)
		if not pathfinding._cells_edge_adjacent(fleet_cell, landing_cell):
			return
		if not pathfinding.walkable_cells.has(landing_cell):
			return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var atk_units: Array = forces[attacker_id]["units"]
	var def_units: Array = []
	var def_force_ids: Array = []
	var had_militia := false
	var militia_men := 0
	var militia_units: Array = []
	var militia_weapons := GlobalUnits.empty_weapon_stock()
	var militia_already_raised := false
	if building != null:
		if is_settlement_building(building):
			if not force_has_movement(attacker_id, SETTLEMENT_BATTLE_MP_COST):
				return
			if settlement_should_raise_militia(building, attacker_id):
				var raised: Dictionary = raise_settlement_militia(building)
				if bool(raised.get("ok", false)):
					had_militia = true
					militia_men = int(raised.get("men", 0))
					militia_units = raised.get("units", [])
					militia_weapons = raised.get("weapons_used", GlobalUnits.empty_weapon_stock())
					militia_already_raised = bool(raised.get("already_raised", false))
					if not militia_already_raised:
						# Merge for this resolve only; apply_* syncs the raise to all peers.
						def_units = GlobalUnits.merge_units(
							get_all_building_garrison(building), militia_units
						)
					else:
						def_units = get_all_building_garrison(building)
			if def_units.is_empty():
				def_units = get_all_building_garrison(building)
			had_militia = had_militia or bool(building.get_meta("militia_in_field", false))
		else:
			def_units = get_all_building_garrison(building)
		def_force_ids = _building_garrison_force_ids(building)
		if def_force_ids.is_empty() and had_militia and not militia_already_raised:
			# Ensure a force id exists for loot routing even before apply raises.
			def_force_ids = [_ensure_flat_garrison_force(building)]
	else:
		def_units = forces[defender_army_id]["units"]
		def_force_ids = [defender_army_id]

	var atk_str := get_force_battle_strength_with_vips(attacker_id, def_force_ids)
	# When militia not yet in garrison force, strength from merged def_units.
	var def_str := 0
	if building != null:
		if had_militia and not militia_already_raised:
			def_str = GlobalUnits.fighting_strength(def_units, GlobalUnits.CASTLE_OUTSIDE_BATTLE_BONUS)
			var ctrl := int(building.player_owner) if building.get("player_owner") != null else -1
			var delta := vip_combat_delta_for_sides(def_force_ids, ctrl, [attacker_id])
			def_str = GlobalVips.apply_strength_multiplier(def_str, delta)
		else:
			def_str = get_building_battle_strength_with_vips(building, [attacker_id])
	elif is_landing:
		def_str = get_landing_defender_battle_strength(defender_army_id, attacker_id)
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

	var loot_force_id := ""
	var captured_cargo := GlobalUnits.empty_caravan_cargo()
	var loser_force_ids: Array = []
	if attacker_won:
		new_attacker = GlobalUnits.merge_units(atk_result["remaining"], atk_result["wounded"])
		# Wipe defender: leftover fighters count as dead; wounded → hostage pool.
		hostage_pool = GlobalUnits.account_wiped_side(def_result, true)
		for fid in def_force_ids:
			for vid in get_vips_on_force(str(fid)):
				captured_vip_ids.append(vid)
		captured_cargo = _collect_forces_cargo(def_force_ids)
		loot_force_id = attacker_id
		loser_force_ids = def_force_ids.duplicate()
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
		captured_cargo = get_force_cargo(attacker_id)
		loser_force_ids = [attacker_id]
		if building != null:
			var gids := _building_garrison_force_ids(building)
			loot_force_id = str(gids[0]) if not gids.is_empty() else ""
		else:
			loot_force_id = defender_army_id

	var dead_stacks: Array = []
	for s in atk_result.get("dead_stacks", []):
		GlobalUnits.add_stack(dead_stacks, s)
	for s in def_result.get("dead_stacks", []):
		GlobalUnits.add_stack(dead_stacks, s)
	var death_loot := GlobalUnits.roll_loot_from_kit(
		GlobalUnits.kit_weapons_from_units(dead_stacks), rng
	)
	var battle_loot := GlobalUnits.add_caravan_stocks(death_loot, captured_cargo)

	var battle_event := _make_battle_event(
		attacker_id, defender_army_id, building, attacker_won,
		atk_units, def_units, atk_result, def_result, hostage_pool,
		battle_loot, loot_force_id, hostage_pool
	)
	battle_event["captured_vip_ids"] = captured_vip_ids.duplicate()
	battle_event["had_militia"] = had_militia
	battle_event["militia_men"] = militia_men
	battle_event["militia_units"] = militia_units
	battle_event["militia_weapons"] = militia_weapons
	battle_event["militia_already_raised"] = militia_already_raised
	battle_event["settlement_battle_mp"] = (
		SETTLEMENT_BATTLE_MP_COST if building != null and is_settlement_building(building) else 0
	)
	battle_event["settlement_loot_to_province"] = (
		building != null and is_settlement_building(building) and not attacker_won
	)
	if is_landing:
		battle_event["place_name"] = "Landing"
		battle_event["is_landing"] = true
	if attacker_won:
		var wage_plan := _plan_wage_capture(def_units, get_force_controller(attacker_id), rng)
		battle_event["captured_wages"] = int(wage_plan["total"])
		battle_event["wage_transfers"] = wage_plan["transfers"]

	var land_x := landing_cell.x if is_landing else 0
	var land_y := landing_cell.y if is_landing else 0
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
		captured_vip_ids,
		battle_loot,
		loot_force_id,
		loser_force_ids,
		landing_fleet_id,
		land_x,
		land_y
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
	captured_vip_ids: Array = [],
	battle_loot: Dictionary = {},
	loot_force_id: String = "",
	loser_force_ids: Array = [],
	landing_fleet_id: String = "",
	landing_cell_x: int = 0,
	landing_cell_y: int = 0
) -> void:
	var building: Node = _building_from_key(building_key) if building_key != "" else null
	var loot := GlobalUnits.sanitize_caravan_cargo(battle_loot)
	if loot_force_id == "":
		loot_force_id = str(battle_event.get("loot_force_id", ""))
	var is_landing := landing_fleet_id != ""
	var landing_cell := Vector2i(landing_cell_x, landing_cell_y)

	# Sync militia raise (pop + weapons + garrison stacks) to all peers before aftermath.
	if building != null and bool(battle_event.get("had_militia", false)) \
			and not bool(battle_event.get("militia_already_raised", false)):
		apply_settlement_militia_raise(
			building,
			int(battle_event.get("militia_men", 0)),
			battle_event.get("militia_weapons", GlobalUnits.empty_weapon_stock()),
			battle_event.get("militia_units", [])
		)

	# Settlement assault MP (all peers).
	var settle_mp := int(battle_event.get("settlement_battle_mp", 0))
	if settle_mp > 0 and forces.has(attacker_id):
		spend_force_movement(attacker_id, settle_mp)

	# Landing attack: spend fleet MP on confirm even if the landing force loses.
	if is_landing:
		var land_fleet = get_fleet_by_id(landing_fleet_id)
		if land_fleet != null:
			land_fleet.movement_left = maxi(
				0, land_fleet.movement_left - GlobalUnits.TRANSPORT_LANDING_MP
			)

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

	# Strip cargo from wiped forces before they are erased (loot already counted in battle_loot).
	if not loser_force_ids.is_empty():
		_clear_forces_cargo(loser_force_ids)
	elif destroy_attacker:
		_clear_forces_cargo([attacker_id])
	elif destroy_defender_army or clear_garrison:
		var wipe_ids: Array = loser_force_ids.duplicate() if not loser_force_ids.is_empty() else []
		if wipe_ids.is_empty() and defender_army_id != "":
			wipe_ids.append(defender_army_id)
		_clear_forces_cargo(wipe_ids)

	if destroy_attacker:
		if forces.has(attacker_id):
			forces[attacker_id]["units"] = []
			_cleanup_force_if_empty(attacker_id)
	elif forces.has(attacker_id):
		forces[attacker_id]["units"] = GlobalUnits.units_from_spec(new_attacker)
		var afig = armies.get_node_or_null(attacker_id)
		if afig != null and afig.has_method("refresh_from_force"):
			afig.refresh_from_force()

	# Attacking ends siege work: field fight = abandoned; castle assault = engines used.
	if forces.has(attacker_id) and is_force_sieging(attacker_id):
		clear_force_siege(attacker_id)

	if building != null:
		var had_militia := bool(battle_event.get("had_militia", false))
		if clear_garrison:
			_clear_building_garrison(building)
			if had_militia:
				# Militia defeated — they will not rise again this season.
				# Pop was already deducted; dead/hostages stay out of the settlement.
				mark_settlement_militia_beaten(building)
			elif is_settlement_building(building):
				clear_settlement_militia_field_flag(building)
		elif attacker_won == false:
			# Rebuild collapses multi-spot garrisons; keep their cargo on the new force.
			var kept_garrison_cargo := _collect_forces_cargo(_building_garrison_force_ids(building))
			var rebuilt := GlobalUnits.units_from_spec(new_defender)
			if had_militia and is_settlement_building(building):
				var split: Dictionary = GlobalUnits.split_militia_units(rebuilt)
				_return_militia_to_settlement(building, split.get("militia", []))
				rebuilt = split.get("regular", [])
				clear_settlement_militia_field_flag(building)
			_set_building_garrison_units(building, rebuilt)
			var gids := _building_garrison_force_ids(building)
			if not gids.is_empty():
				loot_force_id = str(gids[0])
				set_force_cargo(loot_force_id, kept_garrison_cargo)
	elif destroy_defender_army:
		if forces.has(defender_army_id):
			forces[defender_army_id]["units"] = []
			_cleanup_force_if_empty(defender_army_id)
	elif forces.has(defender_army_id):
		forces[defender_army_id]["units"] = GlobalUnits.units_from_spec(new_defender)
		var dfig = armies.get_node_or_null(defender_army_id)
		if dfig != null and dfig.has_method("refresh_from_force"):
			dfig.refresh_from_force()

	# Winning a landing assault: survivors leave the ship onto the cleared shore cell.
	if is_landing and attacker_won and forces.has(attacker_id) \
			and GlobalUnits.total_men(forces[attacker_id]["units"]) > 0:
		_land_force_from_fleet(landing_fleet_id, attacker_id, landing_cell, 0, false)

	# Award battle loot (death kit + captured stock) to the surviving winner force.
	# Settlement defense win: loot goes to the province stock of the settlement owner.
	var loot_to_province := bool(battle_event.get("settlement_loot_to_province", false))
	if GlobalUnits.weapon_stock_has_any(loot) or GlobalUnits.caravan_cargo_has_any(loot):
		if loot_to_province and building != null:
			_deposit_battle_loot_to_province(building, loot)
			battle_event["loot_to_province"] = true
		elif loot_force_id != "":
			if not forces.has(loot_force_id) and building != null and not attacker_won:
				loot_force_id = ensure_building_vip_force(building)
			if forces.has(loot_force_id):
				add_force_cargo(loot_force_id, loot)
				battle_event["loot_force_id"] = loot_force_id

	if attacker_won:
		_apply_wage_capture(battle_event)

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


## Plan wage loot from wiped defender stacks (server-side; amounts go on the event).
func _plan_wage_capture(loser_units: Array, winner_pid: int, rng: RandomNumberGenerator) -> Dictionary:
	var transfers: Array = []
	var total := 0
	if winner_pid < 0 or not players.has(winner_pid) or loser_units.is_empty():
		return {"total": 0, "transfers": transfers}
	var fraction := rng.randf_range(GlobalUnits.WAGE_CAPTURE_MIN, GlobalUnits.WAGE_CAPTURE_MAX)
	for owner in GlobalUnits.owners_in(loser_units):
		var oid := int(owner)
		if oid == winner_pid or not players.has(oid):
			continue
		var claim := GlobalUnits.wage_capture_claim(loser_units, oid, fraction)
		if claim <= 0:
			continue
		var have := int(players[oid].game_data.get("marks", 0))
		var taken := mini(claim, have)
		if taken <= 0:
			continue
		transfers.append({"pid": oid, "amount": taken})
		total += taken
	return {"total": total, "transfers": transfers}


func _apply_wage_capture(battle_event: Dictionary) -> void:
	var transfers: Array = battle_event.get("wage_transfers", [])
	var total := int(battle_event.get("captured_wages", 0))
	if transfers.is_empty() or total <= 0:
		return
	var winner_pid := int(battle_event.get("actor_id", -1))
	for t in transfers:
		var pid := int(t.get("pid", -1))
		var amt := int(t.get("amount", 0))
		if amt <= 0 or not players.has(pid):
			continue
		var have := int(players[pid].game_data.get("marks", 0))
		players[pid].game_data["marks"] = maxi(0, have - amt)
	if winner_pid >= 0 and players.has(winner_pid):
		players[winner_pid].game_data["marks"] = int(players[winner_pid].game_data.get("marks", 0)) + total
	if is_instance_valid(gui_node) and players.has(my_pl_id) and gui_node.has_method("update_money"):
		gui_node.update_money(players[my_pl_id].game_data["marks"])


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
		"cargo": GlobalUnits.empty_caravan_cargo(),
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
	var sword_loot := GlobalUnits.empty_weapon_stock()
	if fate == "sword":
		var ev: Dictionary = game_events[event_id]
		var hostages: Array = ev.get("hostage_units", [])
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		sword_loot = GlobalUnits.roll_loot_from_kit(
			GlobalUnits.kit_weapons_from_units(hostages), rng
		)
	apply_battle_hostage_fate.rpc(event_id, fate, sword_loot)


@rpc("authority", "call_local", "reliable")
func apply_battle_hostage_fate(event_id: String, fate: String, sword_loot: Dictionary = {}) -> void:
	if not game_events.has(event_id):
		return
	var event: Dictionary = game_events[event_id]
	if int(event.get("kind", -1)) != GameEvents.KIND.BATTLE:
		return
	event["hostage_fate"] = fate
	if fate == "sword":
		var extra := GlobalUnits.sanitize_weapon_stock(sword_loot)
		if GlobalUnits.weapon_stock_has_any(extra):
			var loot_fid := str(event.get("loot_force_id", ""))
			if loot_fid != "" and forces.has(loot_fid):
				add_force_cargo(loot_fid, extra)
			event["loot"] = GlobalUnits.add_weapon_stocks(
				GlobalUnits.sanitize_weapon_stock(event.get("loot", {})), extra
			)
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
	if building != null and building.get("type_") != null \
			and int(building.type_) == GlobalStuff.BUILDING_TYPE.FIELD:
		do_raid_field(force_id, building)
		return
	request_raid_building.rpc_id(1, force_id, _building_key(building))


func do_raze_building(force_id: String, building: Node) -> void:
	request_raze_building.rpc_id(1, force_id, _building_key(building))


@rpc("any_peer", "call_local", "reliable")
func request_capture_building(force_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if not force_has_movement(force_id, CAPTURE_MP_COST):
		return
	var building = _building_from_key(building_key)
	if building == null:
		return
	if building.get("type_") != null and int(building.type_) == GlobalStuff.BUILDING_TYPE.FIELD:
		return
	var capturer := get_force_controller(force_id)
	var previous_owner := int(building.player_owner) if building.get("player_owner") != null else -1
	var capture_event := _make_building_capture_event(building, previous_owner, capturer)
	apply_capture_building.rpc(force_id, building_key, capturer, capture_event)


@rpc("authority", "call_local", "reliable")
func apply_capture_building(
	force_id: String,
	building_key: String,
	capturer: int,
	capture_event: Dictionary = {}
) -> void:
	var building = _building_from_key(building_key)
	if building == null:
		return
	if not spend_force_movement(force_id, CAPTURE_MP_COST):
		return
	var previous_owner := int(building.player_owner) if building.get("player_owner") != null else -1
	var prov := find_province_for_building(building)
	# Split grain/horse holding stock by field share before ownership flips.
	if prov != null and previous_owner >= 0 and capturer >= 0 and previous_owner != capturer:
		if building.get("fields") != null and prov.has_method("transfer_holding_stock_for_settlement"):
			prov.transfer_holding_stock_for_settlement(building, previous_owner, capturer)
	building.player_owner = capturer
	# Population remembers the lord they lost — will not rise against them later.
	if is_settlement_building(building) and previous_owner >= 0 and previous_owner != capturer:
		set_settlement_militia_loyal_to(building, previous_owner)
	if building.has_method("set_flags"):
		building.set_flags()
	# Local council folds when its town falls (remaining holdings transfer).
	var folded_council := false
	if (
		prov != null
		and previous_owner >= 0
		and previous_owner != capturer
		and building.get("type_") != null
		and int(building.type_) == GlobalStuff.BUILDING_TYPE.TOWN
		and is_local_council_player(previous_owner)
	):
		fold_local_council_on_town_capture(prov, previous_owner, capturer)
		folded_council = true
	if prov != null and not folded_council:
		# Last settlement lost → conqueror takes remaining province stock.
		if (
			previous_owner >= 0 and capturer >= 0 and previous_owner != capturer
			and prov.has_method("player_has_holding")
			and not prov.player_has_holding(previous_owner)
			and prov.has_method("transfer_remaining_holding_stock")
		):
			prov.transfer_remaining_holding_stock(previous_owner, capturer)
		prov.recompute_control()
		# Full dejure+defacto control → province accepts the new lord; clear loyalty tags.
		if capturer >= 0:
			try_clear_militia_loyalty_for_province(prov, capturer)
		if prov.has_method("update_population_in_resources"):
			prov.update_population_in_resources()
		if prov.has_method("recalculate_marks_will_by_player"):
			prov.recalculate_marks_will_by_player()
		if capturer >= 0 and prov.has_method("ensure_holding"):
			prov.ensure_holding(capturer)
	elif prov != null and folded_council:
		if capturer >= 0:
			try_clear_militia_loyalty_for_province(prov, capturer)
		if prov.has_method("update_population_in_resources"):
			prov.update_population_in_resources()
		if prov.has_method("recalculate_marks_will_by_player"):
			prov.recalculate_marks_will_by_player()
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
	if not force_has_movement(force_id, RAID_MP_COST):
		return
	var building = _building_from_key(building_key)
	if building == null or not can_raid_building(building):
		return
	if building.get("type_") != null and int(building.type_) == GlobalStuff.BUILDING_TYPE.FIELD:
		return
	var loot := compute_raid_loot(building)
	if loot <= 0:
		return
	var raider := get_force_controller(force_id)
	apply_raid_building.rpc(force_id, building_key, raider, loot, turn)


@rpc("authority", "call_local", "reliable")
func apply_raid_building(
	force_id: String,
	building_key: String,
	raider: int,
	loot: int,
	raid_turn: int
) -> void:
	var building = _building_from_key(building_key)
	if building == null or is_building_razed(building):
		return
	if not spend_force_movement(force_id, RAID_MP_COST):
		return
	building.set_meta("last_raid_turn", raid_turn)
	clear_force_siege(force_id)
	if players.has(raider):
		players[raider].game_data["marks"] = int(players[raider].game_data.get("marks", 0)) + loot
	var type_ = building.get("type_")
	if type_ == GlobalStuff.BUILDING_TYPE.VILLAGE or type_ == GlobalStuff.BUILDING_TYPE.TOWN:
		if building.get("tax_marks") != null:
			building.tax_marks = 0
		if building.get("population") != null:
			building.population = int(floor(float(building.population) * RAID_POP_KEEP))
			if building.has_method("calculate_predicted_marks"):
				building.calculate_predicted_marks()
			if building.has_method("calculate_predicted_growth"):
				building.calculate_predicted_growth()
			if building.has_method("refresh_visual_stage"):
				building.refresh_visual_stage()
		var prov := find_province_for_building(building)
		if prov != null:
			prov.update_population_in_resources()
			prov.recalculate_marks_will_by_player()
	# Light smoke for one season (cleared on next season tick).
	building.set_meta("smoke_kind", "raid")
	building.set_meta("smoke_turn", raid_turn)
	_attach_building_smoke(building, RAID_SMOKE_INTENSITY, false)
	if is_instance_valid(gui_node):
		gui_node.show_info_popup("Raid yielded %d marks" % loot)
		if players.has(my_pl_id):
			gui_node.update_money(players[my_pl_id].game_data["marks"])
		if gui_node.has_method("refresh_army_menu_if_force"):
			gui_node.refresh_army_menu_if_force(force_id)


func do_raid_field(force_id: String, field: Node) -> void:
	request_raid_field.rpc_id(1, force_id, _building_key(field))


@rpc("any_peer", "call_local", "reliable")
func request_raid_field(force_id: String, field_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if not force_has_movement(force_id, FIELD_RAID_MP_COST):
		return
	var field = _building_from_key(field_key)
	if field == null or not can_raid_field(field):
		return
	var controller := get_force_controller(force_id)
	if is_building_friendly_to(field, controller):
		return
	var army = get_force_army(force_id)
	if army == null:
		return
	var army_cell = pathfinding.get_army_cell(army)
	if army_cell not in pathfinding.get_approach_cells(field):
		return
	var prov := find_province_for_building(field)
	var owner_pid = field.get_controller_id() if field.has_method("get_controller_id") else -1
	var crop := int(field.get("crop"))
	var grain_loot := 0
	var horse_loot := 0
	var potential_removed := 0.0
	var to_empty := false
	if crop == 1: # GRAIN
		var share := 0.0
		if prov != null and prov.has_method("grain_share_for_field"):
			share = float(prov.grain_share_for_field(field))
		potential_removed = share
		if int(season) == 3:
			grain_loot = int(floor(share * 0.5))
	elif crop == 2: # HORSES
		if prov != null and prov.has_method("horses_on_field"):
			horse_loot = int(prov.horses_on_field(field))
		if horse_loot <= 0:
			return
		to_empty = true
	else:
		return
	apply_raid_field.rpc(
		force_id,
		field_key,
		owner_pid,
		grain_loot,
		horse_loot,
		potential_removed,
		to_empty,
		turn
	)


@rpc("authority", "call_local", "reliable")
func apply_raid_field(
	force_id: String,
	field_key: String,
	owner_pid: int,
	grain_loot: int,
	horse_loot: int,
	potential_removed: float,
	to_empty: bool,
	raid_turn: int
) -> void:
	var field = _building_from_key(field_key)
	if field == null:
		return
	if not spend_force_movement(force_id, FIELD_RAID_MP_COST):
		return
	field.set_meta("last_raid_turn", raid_turn)
	clear_force_siege(force_id)
	var prov := find_province_for_building(field)
	if potential_removed > 0.0 and prov != null and owner_pid >= 0 and prov.has_method("remove_grain_potential"):
		prov.remove_grain_potential(owner_pid, potential_removed)
	if horse_loot > 0 and prov != null and owner_pid >= 0 and prov.has_method("add_player_horses"):
		prov.add_player_horses(owner_pid, -horse_loot)
	if to_empty and field.has_method("set_crop"):
		field.set_crop(0, int(season)) # CROP.EMPTY
	elif int(field.get("crop")) == 1:
		field.planted = false
		field.neglected = false
		if field.has_method("update_visuals_for_season"):
			field.update_visuals_for_season(int(season))
	var cargo_add := GlobalUnits.empty_caravan_cargo()
	if grain_loot > 0:
		cargo_add["grain"] = grain_loot
	if horse_loot > 0:
		cargo_add["horses"] = horse_loot
	if GlobalUnits.caravan_cargo_has_any(cargo_add):
		add_force_cargo(force_id, cargo_add)
	if prov != null:
		if prov.has_method("_update_grain_will"):
			prov._update_grain_will()
		if prov.has_method("refresh_field_visuals"):
			prov.refresh_field_visuals(int(season))
		if owner_pid >= 0 and prov.has_method("clamp_all_labor"):
			prov.clamp_all_labor(owner_pid, int(season))
	field.set_meta("smoke_kind", "raid")
	field.set_meta("smoke_turn", raid_turn)
	_attach_building_smoke(field, RAID_SMOKE_INTENSITY, false)
	if is_instance_valid(gui_node):
		var bits: PackedStringArray = []
		if grain_loot > 0:
			bits.append("%d grain" % grain_loot)
		if horse_loot > 0:
			bits.append("%d horses" % horse_loot)
		if bits.is_empty():
			gui_node.show_info_popup("Field burned")
		else:
			gui_node.show_info_popup("Field raid: %s" % ", ".join(bits))
		if gui_node.has_method("refresh_army_menu_if_force"):
			gui_node.refresh_army_menu_if_force(force_id)
		if gui_node.has_method("refresh_field_popup_if"):
			gui_node.refresh_field_popup_if(self, field)


@rpc("any_peer", "call_local", "reliable")
func request_raze_building(force_id: String, building_key: String) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if not force_has_movement(force_id, RAZE_MP_COST):
		return
	var building = _building_from_key(building_key)
	if building == null or not can_raze_building(building):
		return
	var loot := compute_raze_loot(building)
	var razer := get_force_controller(force_id)
	apply_raze_building.rpc(force_id, building_key, razer, loot, turn)


@rpc("authority", "call_local", "reliable")
func apply_raze_building(
	force_id: String,
	building_key: String,
	razer: int = -1,
	loot: int = -1,
	raze_turn: int = -1
) -> void:
	var building = _building_from_key(building_key)
	if building == null or not can_raze_building(building):
		return
	if not spend_force_movement(force_id, RAZE_MP_COST):
		return
	if razer < 0:
		razer = get_force_controller(force_id)
	if loot < 0:
		loot = compute_raze_loot(building)
	if raze_turn < 0:
		raze_turn = turn
	clear_force_siege(force_id)
	if loot > 0 and players.has(razer):
		players[razer].game_data["marks"] = int(players[razer].game_data.get("marks", 0)) + loot
	if building.get("tax_marks") != null:
		building.tax_marks = 0
	building.set_meta("last_raze_turn", raze_turn)
	building.set_meta("smoke_kind", "raze")
	building.set_meta("smoke_turn", raze_turn)

	if is_settlement_building(building):
		# Soft raze: −50% pop, once/season; smoke clears next season.
		if building.get("population") != null:
			building.population = int(floor(float(building.population) * RAZE_POP_KEEP))
		if building.has_method("calculate_predicted_marks"):
			building.calculate_predicted_marks()
		if building.has_method("calculate_predicted_growth"):
			building.calculate_predicted_growth()
		if building.has_method("refresh_visual_stage"):
			building.refresh_visual_stage()
		elif building.has_method("update_for_stage"):
			building.update_for_stage()
	else:
		# Economy (legacy): full RAZED wipe + recovery seasons.
		building.stage = building.STAGES.RAZED
		building.set_meta("raze_seasons_left", RAZE_RECOVERY_SEASONS)
		if building.get("population") != null:
			building.population = 0
		if building.has_method("update_for_stage"):
			building.update_for_stage()
		if building.has_method("get_start_data"):
			building.get_start_data()
		if building.get("tax_marks") != null:
			building.tax_marks = 0
		_clear_building_garrison(building)

	var prov := find_province_for_building(building)
	if prov != null:
		prov.update_population_in_resources()
		prov.recalculate_marks_will_by_player()
	_attach_building_smoke(building, RAZE_SMOKE_INTENSITY_FULL, true)

	if is_instance_valid(gui_node):
		if loot > 0:
			gui_node.show_info_popup("Building razed — took %d marks" % loot)
		else:
			gui_node.show_info_popup("Building razed")
		if players.has(my_pl_id):
			gui_node.update_money(players[my_pl_id].game_data["marks"])
		if gui_node.has_method("refresh_army_menu_if_force"):
			gui_node.refresh_army_menu_if_force(force_id)


const RAID_SMOKE_SCRIPT := preload("res://objects/overworld/othr/raid_smoke/raid_smoke.gd")


func _attach_building_smoke(building: Node, intensity: float, tall_plume: bool = false) -> void:
	_clear_building_smoke(building)
	var smoke := Node2D.new()
	smoke.name = "RaidSmoke"
	smoke.set_script(RAID_SMOKE_SCRIPT)
	smoke.intensity = clampf(intensity, 0.0, 1.0)
	smoke.tall_plume = tall_plume
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
		if smoke.has_method("set_tall_plume"):
			smoke.set_tall_plume(true)
	else:
		_attach_building_smoke(building, intensity, true)


func clear_expired_raid_smoke() -> void:
	for prov in provinces.get_children():
		for container_name in ["settlements", "fields", "economy", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				# Full RAZED economy smoke fades via tick_razed_buildings.
				if is_building_razed(b) and str(b.get_meta("smoke_kind", "")) == "raze":
					continue
				var smoke_turn := int(b.get_meta("smoke_turn", -1))
				if smoke_turn < 0:
					smoke_turn = int(b.get_meta("last_raid_turn", -1))
				if smoke_turn < 0:
					smoke_turn = int(b.get_meta("last_raze_turn", -1))
				if smoke_turn >= 0 and smoke_turn != turn:
					_clear_building_smoke(b)
					if b.has_meta("smoke_kind"):
						b.remove_meta("smoke_kind")
					if b.has_meta("smoke_turn"):
						b.remove_meta("smoke_turn")


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
	# Towns / villages recover empty and grow back via rations.
	if type_ == GlobalStuff.BUILDING_TYPE.TOWN or type_ == GlobalStuff.BUILDING_TYPE.VILLAGE:
		if building.get("population") != null:
			building.population = 0
	if building.has_meta("raze_seasons_left"):
		building.remove_meta("raze_seasons_left")
	if building.has_meta("smoke_kind"):
		building.remove_meta("smoke_kind")
	_clear_building_smoke(building)
	if building.has_method("refresh_visual_stage"):
		building.refresh_visual_stage()
	elif building.has_method("update_for_stage"):
		building.update_for_stage()
	if building.has_method("get_start_data"):
		building.get_start_data()


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
		# Garrisonable buildings, merchants, or fields: interact when adjacent, else approach.
		var is_garrisonable := building.has_method("get_garrison_capacity")
		if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
			if building.has_method("is_army_interactable") and not building.is_army_interactable():
				gui_node.show_info_popup("Castle worksite — armies cannot interact here")
				pathfinding.deselect_army()
				return true
		var is_merchant = building.get("type_") != null \
				and building.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT \
				and not bool(building.get("camp_hidden"))
		var is_field = building.get("type_") != null \
				and building.type_ == GlobalStuff.BUILDING_TYPE.FIELD
		if is_garrisonable or is_merchant or is_field:
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
				if is_merchant:
					open_army_merchant_raid(army.force_id, building)
				elif is_field:
					open_army_field_interaction(army.force_id, building)
				else:
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
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		if gui_node.has_method("show_castle_popup"):
			gui_node.show_castle_popup(self, building)
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
	if bool(merchant.get("camp_hidden")):
		return
	var prov = merchant.get("province")
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(my_pl_id):
		gui_node.show_info_popup("Only the de jure owner can view the merchant")
		return
	gui_node.open_merchant_shop(self, merchant)


func open_army_merchant_raid(force_id: String, merchant: Node) -> void:
	if not forces.has(force_id) or merchant == null or not is_instance_valid(merchant):
		return
	if bool(merchant.get("camp_hidden")):
		return
	if get_force_controller(force_id) != my_pl_id:
		return
	if not force_has_movement(force_id, RAID_MP_COST):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Need %d movement points to raid" % RAID_MP_COST)
		return
	if is_instance_valid(gui_node) and gui_node.has_method("open_merchant_raid_menu"):
		gui_node.open_merchant_raid_menu(self, force_id, merchant)


func open_army_field_interaction(force_id: String, field: Node) -> void:
	if not forces.has(force_id) or field == null or not is_instance_valid(field):
		return
	if get_force_controller(force_id) != my_pl_id:
		return
	if is_building_friendly_to(field, my_pl_id):
		if is_instance_valid(gui_node) and gui_node.has_method("show_field_popup"):
			gui_node.show_field_popup(self, field)
		return
	if not can_raid_field(field):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Cannot raid this field")
		return
	if not force_has_movement(force_id, FIELD_RAID_MP_COST):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Need %d movement points to raid" % FIELD_RAID_MP_COST)
		return
	if is_instance_valid(gui_node) and gui_node.has_method("open_field_raid_menu"):
		gui_node.open_field_raid_menu(self, force_id, field)


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
			GlobalStuff.BUILDING_TYPE.CASTLE:
				if b.has_method("get_stage_name"):
					return str(b.get_stage_name())
				return "Castle"
			GlobalStuff.BUILDING_TYPE.FIELD: return "Field"
			GlobalStuff.BUILDING_TYPE.MERCHANT:
				var mname := str(b.get("display_name") if b.get("display_name") != null else "")
				return mname if mname != "" else "Merchant"
			GlobalStuff.BUILDING_TYPE.SELLSWORDS: return "Sellswords"
			GlobalStuff.BUILDING_TYPE.ECONOMY:
				if b.has_method("get_subtype_name"):
					return b.get_subtype_name()
				return "Economy Building"
	return "Building"


func _building_owner_pid(b: Node) -> int:
	if b == null:
		return -1
	if b.get("type_") != null and int(b.type_) == GlobalStuff.BUILDING_TYPE.FIELD:
		var owner_building = b.get("owner_building")
		if owner_building != null and owner_building.get("player_owner") != null:
			return int(owner_building.player_owner)
		if b.has_method("get_controller_id"):
			return int(b.get_controller_id())
		return -1
	if b.get("player_owner") != null:
		return int(b.player_owner)
	return -1


## Own holdings: full intel. Foreign/ally: limited public facts.
func viewer_has_full_building_intel(b: Node) -> bool:
	var oid := _building_owner_pid(b)
	return oid >= 0 and oid == my_pl_id


## Full garrison when you own the building, or your men share that garrison (allies only in practice).
func viewer_can_see_building_garrison(b: Node) -> bool:
	if viewer_has_full_building_intel(b):
		return true
	return viewer_has_men_in_building_garrison(b)


func viewer_has_men_in_building_garrison(b: Node) -> bool:
	if b == null or not b.has_method("get_garrison_capacity"):
		return false
	for fid in _building_garrison_force_ids(b):
		if not forces.has(fid):
			continue
		for s in forces[fid].get("units", []):
			if int(s.get("owner", -1)) == my_pl_id and int(s.get("count", 0)) > 0:
				return true
	return false


func _owner_control_claim_line(b: Node, owner_pid: int) -> String:
	var owner_name := "Unowned"
	if owner_pid >= 0 and players.has(owner_pid):
		owner_name = str(players[owner_pid].name_)
	elif owner_pid < 0:
		return "Owner: Unowned"
	var prov := find_province_for_building(b)
	if prov == null:
		return "Owner: %s" % owner_name
	var claim := "holding"
	if prov.has_method("has_dejure") and prov.has_dejure(owner_pid):
		claim = "de jure"
	elif prov.get("defacto") != null and int(prov.defacto) == owner_pid:
		claim = "de facto"
	var line := "Owner: %s · %s" % [owner_name, claim]
	if claim != "de jure" and prov.get("dejure") != null and players.has(int(prov.dejure)):
		line += " (dejure: %s)" % str(players[int(prov.dejure)].name_)
	return line


func _building_display_body(b: Node2D) -> String:
	var lines := PackedStringArray()
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT:
		var prov = b.get("province")
		var pname := "Unknown"
		if prov != null and prov.get("p_name") != null:
			pname = str(prov.p_name)
		var mname := str(b.get("display_name") if b.get("display_name") != null else "Merchant")
		lines.append(mname)
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

	var full := viewer_has_full_building_intel(b)
	var show_garrison := viewer_can_see_building_garrison(b)
	var owner_pid := _building_owner_pid(b)

	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.FIELD:
		lines.append(_owner_control_claim_line(b, owner_pid))
		if b.has_method("get_crop_name"):
			lines.append("Use: %s" % b.get_crop_name())
		if full and b.get("crop") != null and int(b.crop) == 1: # GRAIN
			if bool(b.get("planted")):
				lines.append("Grain: growing (seed spent)")
			elif int(season) == 0:
				lines.append(
					"Grain: planned (seed %d + %d people when leaving winter)"
					% [GlobalUnits.GRAIN_SEED_PER_FIELD, GlobalUnits.PEOPLE_PER_GRAIN_FIELD_PEAK]
				)
			else:
				lines.append(
					"Grain: assigned, not sown (winter sprite) — needs %d seed + sow labor next winter"
					% GlobalUnits.GRAIN_SEED_PER_FIELD
				)
			lines.append("Labor: sow/harvest %d · tend %d people/field · yield %d" % [
				GlobalUnits.PEOPLE_PER_GRAIN_FIELD_PEAK,
				GlobalUnits.PEOPLE_PER_GRAIN_FIELD_TEND,
				GlobalUnits.GRAIN_YIELD_PER_FIELD,
			])
		elif not full and b.get("crop") != null and int(b.crop) == 1:
			if bool(b.get("planted")):
				lines.append("Grain: growing")
			elif int(season) == 0:
				lines.append("Grain: planned")
			else:
				lines.append("Grain: assigned (not sown)")
		if full and bool(b.get("neglected")):
			lines.append("Neglected (underworked)")
		elif not full and bool(b.get("neglected")):
			lines.append("Looks neglected")
	elif b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.ECONOMY:
		if b.has_method("get_slot_description"):
			lines.append(b.get_slot_description())
		lines.append(_owner_control_claim_line(b, owner_pid))
		if b.has_method("is_built") and b.is_built():
			if b.has_method("get_stage_name"):
				lines.append("Stage: %s" % b.get_stage_name())
			if full:
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
			lines.append("Empty plot")
	elif b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		lines.append(_owner_control_claim_line(b, owner_pid))
		if b.has_method("get_castle_type_name") and b.has_method("is_built") and b.is_built():
			lines.append("Type: %s" % b.get_castle_type_name())
		elif b.has_method("get_stage_name"):
			var st: String = b.get_stage_name()
			if st != "":
				lines.append("Stage: %s" % st)
		if full and b.has_method("construction_summary"):
			lines.append(str(b.construction_summary()))
		if b.has_method("is_under_construction") and b.is_under_construction():
			if full:
				lines.append("Offline — assign Castle labor in the province menu")
				lines.append("Armies cannot interact with this worksite")
			else:
				lines.append("Under construction")
		elif b.has_method("is_built") and not b.is_built():
			lines.append("Empty plot")
	else:
		# Town / village / other settlements.
		lines.append(_owner_control_claim_line(b, owner_pid))
		if b.has_method("get_stage_name"):
			var stage_name: String = b.get_stage_name()
			if stage_name != "":
				lines.append("Stage: %s" % stage_name)

	# Full-intel-only details.
	if full:
		if b.get("population") != null:
			lines.append("Population: %s" % str(b.population))
		if b.get("happiness") != null:
			lines.append("Happiness: %.0f" % float(b.happiness))
		if b.get("predicted_marks") != null:
			var prov := find_province_for_building(b)
			var to_wallet = prov != null and prov.has_method("has_dejure") and prov.has_dejure(my_pl_id)
			if to_wallet:
				lines.append("Tax next season: %s marks → wallet" % str(b.predicted_marks))
			else:
				lines.append("Tax next season: %s marks → coffer" % str(b.predicted_marks))
		if b.has_method("settlement_marks_bonus_fraction"):
			var pct := float(b.settlement_marks_bonus_fraction()) * 100.0
			if pct > 0.0:
				lines.append("Tier bonus: +%.0f%%" % pct)
		if b.get("tax_marks") != null:
			lines.append("Tax stored: %d marks" % int(b.tax_marks))
		var vip_ids := get_building_vip_ids(b)
		if not vip_ids.is_empty():
			var vip_names: PackedStringArray = []
			for vid in vip_ids:
				vip_names.append(vip_display_name(str(vid)))
			lines.append("VIP: %s" % ", ".join(vip_names))

	if show_garrison and b.has_method("get_garrison_capacity"):
		lines.append(_building_garrison_text(b))

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
	for fid in _building_garrison_force_ids(b):
		if not forces.has(fid):
			continue
		if GlobalUnits.total_men(forces[fid]["units"]) <= 0:
			continue
		out.append(force_food_status_text(fid))
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
	# Never end on an occupied cell (friendly pass-through is mid-path only).
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
	if army.get("force_id") != null and str(army.force_id) != "":
		clear_force_hunger_if_relieved(str(army.force_id))
		if steps > 0:
			clear_force_siege(str(army.force_id))
	_try_open_pending_garrison(army_name)
	_try_open_pending_army_interaction(army_name)


func _try_open_pending_garrison(army_name: String) -> void:
	if _pending_garrison_army_name != army_name:
		return
	var building := _pending_garrison_building
	var force_id := _pending_garrison_force_id
	clear_pending_garrison()
	if building != null and building.has_method("is_army_interactable") \
			and not building.is_army_interactable():
		return
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
	if building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.MERCHANT:
		call_deferred("open_army_merchant_raid", force_id, building)
	elif building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.FIELD:
		call_deferred("open_army_field_interaction", force_id, building)
	else:
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


func _try_open_pending_fleet_combine(fleet_name: String) -> void:
	if _pending_fleet_combine_mover_name != fleet_name:
		return
	var target := _pending_fleet_combine_target
	clear_pending_fleet_combine()
	if target == null or not is_instance_valid(target):
		return
	var fleet = get_fleet_by_id(fleet_name)
	if fleet == null or not fleet.is_controllable_by(my_pl_id):
		return
	var cell = pathfinding.get_army_cell(fleet)
	if pathfinding.get_army_cell(target) != cell:
		return
	call_deferred("open_fleet_combine_prompt", fleet, target, cell)


# --- Transport fleets -------------------------------------------------------

func town_has_sea_access(town: Node) -> bool:
	return not get_sea_cells_adjacent_to_building(town).is_empty()


func get_sea_cells_adjacent_to_building(building: Node) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if building == null or pathfinding == null:
		return result
	var footprint: Array = pathfinding.object_to_footprint.get(building, [])
	if footprint.is_empty() and building.has_method("get_pathfinding_blocked_tile_centers"):
		for pos in building.get_pathfinding_blocked_tile_centers():
			var cell: Vector2i = pathfinding.map_layer.local_to_map(
				pathfinding.map_layer.to_local(pos)
			)
			footprint.append(cell)
	for cell in footprint:
		for dir in pathfinding.EDGE_DIRS:
			var n: Vector2i = cell + dir
			if pathfinding.is_sea_cell(n) and n not in result:
				result.append(n)
	return result


func get_fleet_spawn_sea_cell(town: Node) -> Vector2i:
	var cells := get_sea_cells_adjacent_to_building(town)
	if cells.is_empty():
		return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	return cells[0]


func province_coastal_towns_for(player_id: int, province_id: String) -> Array:
	var out: Array = []
	var prov := _get_province_by_id(province_id)
	if prov == null:
		return out
	var sett = prov.get_node_or_null("settlements")
	if sett == null:
		return out
	for b in sett.get_children():
		if b.get("type_") == null or b.type_ != GlobalStuff.BUILDING_TYPE.TOWN:
			continue
		if int(b.player_owner) != player_id:
			continue
		if town_has_sea_access(b):
			out.append(b)
	return out


func do_build_transport_ships(province_id: String, ship_count: int) -> void:
	ship_count = clampi(ship_count, 1, 200)
	var towns := province_coastal_towns_for(my_pl_id, province_id)
	if towns.is_empty():
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Need an owned town bordering the sea")
		return
	var wood_need := ship_count * GlobalUnits.TRANSPORT_SHIP_WOOD_COST
	var marks_need := ship_count * GlobalUnits.TRANSPORT_SHIP_MARKS_COST
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_dejure(my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("You need de jure ownership to build ships here")
		return
	if prov.get_player_material(my_pl_id, "wood") < wood_need:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Need %d wood" % wood_need)
		return
	var marks := int(players[my_pl_id].game_data.get("marks", 0))
	if marks < marks_need:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Need %d marks" % marks_need)
		return
	var spawn := get_fleet_spawn_sea_cell(towns[0])
	if spawn == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("No sea tile next to the town")
		return
	request_build_transport_ships.rpc_id(1, province_id, ship_count, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_build_transport_ships(province_id: String, ship_count: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	ship_count = clampi(ship_count, 1, 200)
	if not players.has(player_id):
		return
	var towns := province_coastal_towns_for(player_id, province_id)
	if towns.is_empty():
		return
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_dejure(player_id):
		return
	var wood_need := ship_count * GlobalUnits.TRANSPORT_SHIP_WOOD_COST
	var marks_need := ship_count * GlobalUnits.TRANSPORT_SHIP_MARKS_COST
	if prov.get_player_material(player_id, "wood") < wood_need:
		return
	if int(players[player_id].game_data.get("marks", 0)) < marks_need:
		return
	var spawn := get_fleet_spawn_sea_cell(towns[0])
	if spawn == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return
	_next_fleet_id += 1
	var new_id := "fl_%d" % _next_fleet_id
	apply_build_transport_ships.rpc(
		province_id, player_id, ship_count, new_id, spawn.x, spawn.y
	)


@rpc("authority", "call_local", "reliable")
func apply_build_transport_ships(
	province_id: String,
	player_id: int,
	ship_count: int,
	fleet_id: String,
	cell_x: int,
	cell_y: int
) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null or not players.has(player_id):
		return
	var wood_need := ship_count * GlobalUnits.TRANSPORT_SHIP_WOOD_COST
	var marks_need := ship_count * GlobalUnits.TRANSPORT_SHIP_MARKS_COST
	if prov.get_player_material(player_id, "wood") < wood_need:
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < marks_need:
		return
	prov.add_player_material(player_id, "wood", -wood_need)
	players[player_id].game_data["marks"] = marks - marks_need
	_spawn_fleet(fleet_id, player_id, ship_count, Vector2i(cell_x, cell_y), -1)
	if player_id == my_pl_id and is_instance_valid(gui_node):
		gui_node.update_money(players[my_pl_id].game_data["marks"])
		if gui_node.has_method("update_economy_menu"):
			gui_node.update_economy_menu(self)
		if gui_node.has_method("refresh_military_tab_if_open"):
			gui_node.refresh_military_tab_if_open()


func _spawn_fleet(
	fleet_id: String,
	player_id: int,
	ship_count: int,
	cell: Vector2i,
	starting_mp: int = -1
) -> Node2D:
	var fig = TRANSPORT_SHIP_SCENE.instantiate()
	fig.name = fleet_id
	fleets.add_child(fig)
	fig.base_map = self
	fig.fleet_id = fleet_id
	fig.player_owner = player_id
	fig.ship_count = maxi(1, ship_count)
	fig.movement_points = GlobalUnits.TRANSPORT_SHIP_MP
	fig.aboard_force_ids = []
	if starting_mp < 0:
		fig.reset_movement()
	else:
		fig.movement_left = clampi(starting_mp, 0, fig.effective_max_mp())
	pathfinding.place_fleet_at_cell(fig, cell)
	fig.set_flags()
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	return fig


@rpc("any_peer", "call_local", "reliable")
func request_fleet_move(fleet_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	if not multiplayer.is_server():
		return
	var fleet = get_fleet_by_id(fleet_name)
	if fleet == null:
		return
	steps = clampi(steps, 0, fleet.movement_left)
	if steps <= 0:
		return
	var dest := Vector2i(cell_x, cell_y)
	if not pathfinding.is_sea_cell(dest):
		return
	apply_fleet_move.rpc(fleet_name, cell_x, cell_y, steps)


@rpc("authority", "call_local", "reliable")
func apply_fleet_move(fleet_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	var fleet = get_fleet_by_id(fleet_name)
	if fleet == null:
		clear_pending_fleet_combine()
		return
	pathfinding.place_fleet_at_cell(fleet, Vector2i(cell_x, cell_y))
	fleet.movement_left -= steps
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	for fid in fleet.aboard_force_ids:
		clear_force_hunger_if_relieved(str(fid))
	_try_open_pending_fleet_combine(fleet_name)


func do_fleet_embark(fleet_id: String, army_force_id: String) -> void:
	request_fleet_embark.rpc_id(1, fleet_id, army_force_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_fleet_embark(fleet_id: String, army_force_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or int(fleet.player_owner) != player_id:
		return
	if fleet.movement_left < GlobalUnits.TRANSPORT_EMBARK_FLEET_MP:
		return
	if not forces.has(army_force_id):
		return
	var loc: Dictionary = forces[army_force_id].get("location", {})
	if str(loc.get("kind", "")) != "cell":
		return
	var army = armies.get_node_or_null(army_force_id)
	if army == null:
		return
	if int(army.movement_left) < GlobalUnits.TRANSPORT_EMBARK_ARMY_MP:
		return
	if not pathfinding.are_armies_adjacent(fleet, army):
		return
	# Own fleet + own army only (army-initiated embark).
	if get_force_controller(army_force_id) != player_id:
		return
	var men := GlobalUnits.total_men(forces[army_force_id]["units"])
	if men <= 0 or men > fleet.free_capacity():
		return
	apply_fleet_embark.rpc(fleet_id, army_force_id)


@rpc("authority", "call_local", "reliable")
func apply_fleet_embark(fleet_id: String, army_force_id: String) -> void:
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or not forces.has(army_force_id):
		return
	var fig = armies.get_node_or_null(army_force_id)
	if fig != null:
		fig.movement_left = maxi(0, int(fig.movement_left) - GlobalUnits.TRANSPORT_EMBARK_ARMY_MP)
		armies.remove_child(fig)
		fig.queue_free()
	forces[army_force_id]["location"] = {"kind": "aboard", "fleet": fleet_id}
	if not fleet.aboard_force_ids.has(army_force_id):
		fleet.aboard_force_ids.append(army_force_id)
	fleet.movement_left = maxi(0, fleet.movement_left - GlobalUnits.TRANSPORT_EMBARK_FLEET_MP)
	clear_force_siege(army_force_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	_sync_force_hunger_fx(army_force_id)
	refresh_all_vip_crowns()


func do_fleet_disembark(fleet_id: String, army_force_id: String, cell: Vector2i) -> void:
	request_fleet_disembark.rpc_id(1, fleet_id, army_force_id, cell.x, cell.y, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_fleet_disembark(
	fleet_id: String, army_force_id: String, cell_x: int, cell_y: int, player_id: int
) -> void:
	if not multiplayer.is_server():
		return
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or int(fleet.player_owner) != player_id:
		return
	if fleet.movement_left < GlobalUnits.TRANSPORT_LANDING_MP:
		return
	if not forces.has(army_force_id):
		return
	if not fleet.aboard_force_ids.has(army_force_id):
		return
	var dest := Vector2i(cell_x, cell_y)
	if not pathfinding.walkable_cells.has(dest) or pathfinding.occupancy.has(dest):
		return
	var fleet_cell = pathfinding.get_army_cell(fleet)
	if not pathfinding._cells_edge_adjacent(fleet_cell, dest):
		return
	var ctrl := get_force_controller(army_force_id)
	var mp_left := 0
	apply_fleet_disembark.rpc(fleet_id, army_force_id, cell_x, cell_y, ctrl, mp_left)


@rpc("authority", "call_local", "reliable")
func apply_fleet_disembark(
	fleet_id: String,
	army_force_id: String,
	cell_x: int,
	cell_y: int,
	controller: int,
	starting_mp: int
) -> void:
	_land_force_from_fleet(
		fleet_id, army_force_id, Vector2i(cell_x, cell_y), starting_mp, true, controller
	)


## Place an aboard force onto a shore cell. `spend_mp` charges TRANSPORT_LANDING_MP.
func _land_force_from_fleet(
	fleet_id: String,
	army_force_id: String,
	cell: Vector2i,
	starting_mp: int,
	spend_mp: bool,
	controller: int = -1
) -> void:
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or not forces.has(army_force_id):
		return
	if str(forces[army_force_id].get("location", {}).get("kind", "")) != "aboard":
		return
	fleet.aboard_force_ids.erase(army_force_id)
	if spend_mp:
		fleet.movement_left = maxi(0, fleet.movement_left - GlobalUnits.TRANSPORT_LANDING_MP)
	var cargo: Dictionary = forces[army_force_id].get("cargo", GlobalUnits.empty_caravan_cargo())
	if controller < 0:
		controller = get_force_controller(army_force_id)
	# Re-spawn land figure; keep same force_id and cargo/VIPs.
	var existing = armies.get_node_or_null(army_force_id)
	if existing != null:
		armies.remove_child(existing)
		existing.queue_free()
	var fig = ARMY_FIGURE_SCENE.instantiate()
	fig.name = army_force_id
	armies.add_child(fig)
	fig.base_map = self
	forces[army_force_id]["location"] = {"kind": "cell"}
	forces[army_force_id]["controller"] = controller
	forces[army_force_id]["cargo"] = cargo
	fig.bind_force(army_force_id)
	pathfinding.place_army_at_cell(fig, cell)
	fig.movement_left = clampi(starting_mp, 0, fig.effective_max_mp())
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	_sync_force_hunger_fx(army_force_id)
	refresh_all_vip_crowns()
	refresh_army_labels()


func do_fleet_landing_merge(fleet_id: String, army_force_id: String, shore_force_id: String) -> void:
	request_fleet_landing_merge.rpc_id(1, fleet_id, army_force_id, shore_force_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_fleet_landing_merge(
	fleet_id: String, army_force_id: String, shore_force_id: String, player_id: int
) -> void:
	if not multiplayer.is_server():
		return
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or int(fleet.player_owner) != player_id:
		return
	if fleet.movement_left < GlobalUnits.TRANSPORT_LANDING_MP:
		return
	if not forces.has(army_force_id) or not forces.has(shore_force_id):
		return
	if not fleet.aboard_force_ids.has(army_force_id):
		return
	var shore_fig = armies.get_node_or_null(shore_force_id)
	if shore_fig == null:
		return
	var shore_cell = pathfinding.get_army_cell(shore_fig)
	var fleet_cell = pathfinding.get_army_cell(fleet)
	if not pathfinding._cells_edge_adjacent(fleet_cell, shore_cell):
		return
	if not are_friendly_players(player_id, get_force_controller(shore_force_id)):
		return
	if not are_friendly_players(player_id, get_force_controller(army_force_id)):
		return
	apply_fleet_landing_merge.rpc(fleet_id, army_force_id, shore_force_id)


@rpc("authority", "call_local", "reliable")
func apply_fleet_landing_merge(
	fleet_id: String, army_force_id: String, shore_force_id: String
) -> void:
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or not forces.has(army_force_id) or not forces.has(shore_force_id):
		return
	fleet.aboard_force_ids.erase(army_force_id)
	fleet.movement_left = maxi(0, fleet.movement_left - GlobalUnits.TRANSPORT_LANDING_MP)
	forces[shore_force_id]["units"] = GlobalUnits.merge_units(
		forces[shore_force_id]["units"], forces[army_force_id]["units"]
	)
	move_all_force_cargo(army_force_id, shore_force_id)
	transfer_all_vips(army_force_id, shore_force_id)
	forces.erase(army_force_id)
	var tfig = armies.get_node_or_null(shore_force_id)
	if tfig != null:
		tfig.movement_left = 0
		tfig.refresh_from_force()
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	refresh_all_vip_crowns()


func do_fleet_combine(keep_id: String, absorb_id: String) -> void:
	request_fleet_combine.rpc_id(1, keep_id, absorb_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_fleet_combine(keep_id: String, absorb_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if keep_id == absorb_id:
		return
	var keep = get_fleet_by_id(keep_id)
	var absorb = get_fleet_by_id(absorb_id)
	if keep == null or absorb == null:
		return
	if int(keep.player_owner) != player_id or int(absorb.player_owner) != player_id:
		return
	if pathfinding.get_army_cell(keep) != pathfinding.get_army_cell(absorb):
		# Allow combine when adjacent: move absorb onto keep first via apply.
		if not pathfinding.are_armies_adjacent(keep, absorb):
			return
	apply_fleet_combine.rpc(keep_id, absorb_id)


@rpc("authority", "call_local", "reliable")
func apply_fleet_combine(keep_id: String, absorb_id: String) -> void:
	var keep = get_fleet_by_id(keep_id)
	var absorb = get_fleet_by_id(absorb_id)
	if keep == null or absorb == null or keep_id == absorb_id:
		return
	var keep_cell = pathfinding.get_army_cell(keep)
	pathfinding.place_fleet_at_cell(absorb, keep_cell)
	keep.ship_count += absorb.ship_count
	for fid in absorb.aboard_force_ids:
		if not keep.aboard_force_ids.has(fid):
			keep.aboard_force_ids.append(fid)
		if forces.has(fid):
			forces[fid]["location"] = {"kind": "aboard", "fleet": keep_id}
	keep.movement_left = mini(keep.movement_left, absorb.movement_left)
	fleets.remove_child(absorb)
	absorb.queue_free()
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


func do_fleet_stack_move(mover_id: String, dest: Vector2i) -> void:
	var fleet = get_fleet_by_id(mover_id)
	if fleet == null:
		return
	var from_cell = pathfinding.get_army_cell(fleet)
	if from_cell == dest:
		return
	if not pathfinding._cells_edge_adjacent(from_cell, dest):
		return
	if not pathfinding.is_sea_cell(dest):
		return
	var cost = pathfinding.enter_cost(dest, fleet)
	if fleet.movement_left < cost:
		return
	request_fleet_move.rpc_id(1, mover_id, dest.x, dest.y, cost)


func do_fleet_split(fleet_id: String, ships_off: int) -> void:
	request_fleet_split.rpc_id(1, fleet_id, ships_off, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_fleet_split(fleet_id: String, ships_off: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or int(fleet.player_owner) != player_id:
		return
	if fleet.has_army_aboard():
		return
	ships_off = clampi(ships_off, 1, fleet.ship_count - 1)
	if ships_off <= 0 or fleet.ship_count - ships_off < 1:
		return
	_next_fleet_id += 1
	var new_id := "fl_%d" % _next_fleet_id
	var cell = pathfinding.get_army_cell(fleet)
	apply_fleet_split.rpc(fleet_id, new_id, ships_off, cell.x, cell.y, fleet.movement_left)


@rpc("authority", "call_local", "reliable")
func apply_fleet_split(
	fleet_id: String,
	new_id: String,
	ships_off: int,
	cell_x: int,
	cell_y: int,
	mp_left: int
) -> void:
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or fleet.has_army_aboard():
		return
	if ships_off <= 0 or ships_off >= fleet.ship_count:
		return
	fleet.ship_count -= ships_off
	_spawn_fleet(new_id, fleet.player_owner, ships_off, Vector2i(cell_x, cell_y), mp_left)


func do_fleet_disband(fleet_id: String) -> void:
	request_fleet_disband.rpc_id(1, fleet_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_fleet_disband(fleet_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null or int(fleet.player_owner) != player_id:
		return
	if fleet.has_army_aboard():
		return
	apply_fleet_disband.rpc(fleet_id)


@rpc("authority", "call_local", "reliable")
func apply_fleet_disband(fleet_id: String) -> void:
	var fleet = get_fleet_by_id(fleet_id)
	if fleet == null:
		return
	if fleet.has_army_aboard():
		return
	fleets.remove_child(fleet)
	fleet.queue_free()
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_military_tab_if_open"):
		gui_node.refresh_military_tab_if_open()


func force_is_aboard(fid: String) -> bool:
	if not forces.has(fid):
		return false
	return str(forces[fid].get("location", {}).get("kind", "")) == "aboard"


func get_force_fleet_id(fid: String) -> String:
	if not force_is_aboard(fid):
		return ""
	return str(forces[fid].get("location", {}).get("fleet", ""))


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
	move_all_force_cargo(source_id, target_id)
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
	refresh_army_labels()


# Split out_units off source_id into a NEW mobile army placed at (cell).
# withdraw=true: a guest player peels off only their troops (no MP cost).
@rpc("any_peer", "call_local", "reliable")
func request_split_force(
	source_id: String,
	out_units: Array,
	cell_x: int,
	cell_y: int,
	withdraw: bool = false,
	withdraw_player: int = -1,
	cargo_out: Dictionary = {}
) -> void:
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
	var clean_cargo := GlobalUnits.clamp_caravan_stock(get_force_cargo(source_id), cargo_out)
	apply_split_force.rpc(source_id, new_id, out_units, cell_x, cell_y, master_mp, spawned_mp, new_controller, clean_cargo)


@rpc("authority", "call_local", "reliable")
func apply_split_force(
	source_id: String,
	new_id: String,
	out_units: Array,
	cell_x: int,
	cell_y: int,
	master_mp: int,
	spawned_mp: int,
	new_controller: int = -1,
	cargo_out: Dictionary = {}
) -> void:
	if not forces.has(source_id):
		return
	GlobalUnits.subtract_units(forces[source_id]["units"], out_units)
	clear_force_siege(source_id)
	var sfig = armies.get_node_or_null(source_id)
	if sfig != null:
		sfig.movement_left = master_mp
		sfig.refresh_from_force()
	var controller := new_controller
	if controller < 0:
		controller = GlobalUnits.primary_owner(GlobalUnits.units_from_spec(out_units))
	_spawn_army_figure(new_id, GlobalUnits.units_from_spec(out_units), Vector2i(cell_x, cell_y), spawned_mp, controller)
	var moved := take_force_cargo(source_id, cargo_out)
	add_force_cargo(new_id, moved)
	_flush_cargo_if_force_empty(source_id, new_id)
	_cleanup_force_if_empty(source_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


# Transfer out_units between two EXISTING forces (army<->army, garrison->army).
@rpc("any_peer", "call_local", "reliable")
func request_transfer_units(source_id: String, dest_id: String, out_units: Array, cargo: Dictionary = {}) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(source_id) or not forces.has(dest_id):
		return
	apply_transfer_units.rpc(source_id, dest_id, out_units, GlobalUnits.clamp_caravan_stock(get_force_cargo(source_id), cargo))


@rpc("authority", "call_local", "reliable")
func apply_transfer_units(source_id: String, dest_id: String, out_units: Array, cargo: Dictionary = {}) -> void:
	if not forces.has(source_id) or not forces.has(dest_id):
		return
	GlobalUnits.subtract_units(forces[source_id]["units"], out_units)
	forces[dest_id]["units"] = GlobalUnits.merge_units(forces[dest_id]["units"], GlobalUnits.units_from_spec(out_units))
	var moved := take_force_cargo(source_id, cargo)
	add_force_cargo(dest_id, moved)
	_flush_cargo_if_force_empty(source_id, dest_id)
	for fid in [source_id, dest_id]:
		var f = armies.get_node_or_null(fid)
		if f != null:
			f.refresh_from_force()
	_cleanup_force_if_empty(source_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


@rpc("any_peer", "call_local", "reliable")
func request_batch_transfer_units(
	left_id: String,
	right_id: String,
	left_to_right: Array,
	right_to_left: Array,
	cargo_l2r: Dictionary = {},
	cargo_r2l: Dictionary = {}
) -> void:
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
	var clean_l2r := GlobalUnits.clamp_caravan_stock(get_force_cargo(left_id), cargo_l2r)
	var clean_r2l := GlobalUnits.clamp_caravan_stock(get_force_cargo(right_id), cargo_r2l)
	apply_batch_transfer_units.rpc(left_id, right_id, left_to_right, right_to_left, clean_l2r, clean_r2l)


@rpc("authority", "call_local", "reliable")
func apply_batch_transfer_units(
	left_id: String,
	right_id: String,
	left_to_right: Array,
	right_to_left: Array,
	cargo_l2r: Dictionary = {},
	cargo_r2l: Dictionary = {}
) -> void:
	if not forces.has(left_id) or not forces.has(right_id):
		return
	if not left_to_right.is_empty():
		GlobalUnits.subtract_units(forces[left_id]["units"], left_to_right)
		forces[right_id]["units"] = GlobalUnits.merge_units(forces[right_id]["units"], GlobalUnits.units_from_spec(left_to_right))
	if not right_to_left.is_empty():
		GlobalUnits.subtract_units(forces[right_id]["units"], right_to_left)
		forces[left_id]["units"] = GlobalUnits.merge_units(forces[left_id]["units"], GlobalUnits.units_from_spec(right_to_left))
	var moved_l2r := take_force_cargo(left_id, cargo_l2r)
	add_force_cargo(right_id, moved_l2r)
	var moved_r2l := take_force_cargo(right_id, cargo_r2l)
	add_force_cargo(left_id, moved_r2l)
	_flush_cargo_if_force_empty(left_id, right_id)
	_flush_cargo_if_force_empty(right_id, left_id)
	for fid in [left_id, right_id]:
		var f = armies.get_node_or_null(fid)
		if f != null:
			f.refresh_from_force()
	_cleanup_force_if_empty(left_id)
	_cleanup_force_if_empty(right_id)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


@rpc("any_peer", "call_local", "reliable")
func request_batch_garrison_units(
	source_id: String,
	building_key: String,
	spot: int,
	to_garrison: Array,
	from_garrison: Array,
	cargo_to_g: Dictionary = {},
	cargo_from_g: Dictionary = {}
) -> void:
	if !multiplayer.is_server():
		return
	if not forces.has(source_id):
		return
	var sfig = armies.get_node_or_null(source_id)
	if sfig == null:
		return
	if to_garrison.is_empty() and from_garrison.is_empty() \
			and not GlobalUnits.caravan_cargo_has_any(cargo_to_g) \
			and not GlobalUnits.caravan_cargo_has_any(cargo_from_g):
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

	var clean_to := GlobalUnits.clamp_caravan_stock(get_force_cargo(source_id), cargo_to_g)
	var clean_from := GlobalUnits.clamp_caravan_stock(get_force_cargo(gid) if forces.has(gid) else {}, cargo_from_g)
	apply_batch_garrison_units.rpc(source_id, building_key, spot, to_garrison, from_garrison, clean_to, clean_from)


@rpc("authority", "call_local", "reliable")
func apply_batch_garrison_units(
	source_id: String,
	building_key: String,
	spot: int,
	to_garrison: Array,
	from_garrison: Array,
	cargo_to_g: Dictionary = {},
	cargo_from_g: Dictionary = {}
) -> void:
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
				"location": {"kind": "garrison", "building": building_key, "spot": spot},
				"cargo": GlobalUnits.empty_caravan_cargo(),
			}

	if not from_garrison.is_empty() and forces.has(gid):
		GlobalUnits.subtract_units(forces[gid]["units"], from_garrison)
		forces[source_id]["units"] = GlobalUnits.merge_units(forces[source_id]["units"], GlobalUnits.units_from_spec(from_garrison))

	# Cargo only moves if both sides still exist as forces (no loot-only empty garrison).
	if forces.has(gid):
		var moved_to := take_force_cargo(source_id, cargo_to_g)
		add_force_cargo(gid, moved_to)
		var moved_from := take_force_cargo(gid, cargo_from_g)
		add_force_cargo(source_id, moved_from)
		_flush_cargo_if_force_empty(source_id, gid)
		_flush_cargo_if_force_empty(gid, source_id)

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


## BFS from a building's footprint for any free walkable cell (levy / emergency spawn).
func _free_cell_near_building(b: Node) -> Vector2i:
	if b == null or pathfinding == null:
		return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	var footprint: Array = pathfinding.object_to_footprint.get(b, [])
	if footprint.is_empty() and b.has_method("get_pathfinding_blocked_tile_centers"):
		for pos in b.get_pathfinding_blocked_tile_centers():
			var local_pos = pathfinding.map_layer.to_local(pos)
			footprint.append(pathfinding.map_layer.local_to_map(local_pos))
	if footprint.is_empty() and b is Node2D:
		var local_pos = pathfinding.map_layer.to_local((b as Node2D).global_position)
		footprint.append(pathfinding.map_layer.local_to_map(local_pos))
	if footprint.is_empty():
		return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	var reserved: Dictionary = {}
	return _bfs_free_cell_near(footprint[0], reserved)


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
	var building = _building_from_key(building_key)
	if building != null and building.has_method("is_army_interactable") and not building.is_army_interactable():
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
			"location": {"kind": "garrison", "building": building_key, "spot": spot},
			"cargo": GlobalUnits.empty_caravan_cargo(),
		}
	_flush_cargo_if_force_empty(source_id, gid)
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
func request_sortie_units(
	building_key: String,
	spot: int,
	out_units: Array,
	cell_x: int,
	cell_y: int,
	cargo_out: Dictionary = {}
) -> void:
	if !multiplayer.is_server():
		return
	var gid := _garrison_force_id(building_key, spot)
	if not forces.has(gid):
		return
	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	var clean := GlobalUnits.clamp_caravan_stock(get_force_cargo(gid), cargo_out)
	apply_sortie_units.rpc(gid, new_id, out_units, cell_x, cell_y, clean)


@rpc("authority", "call_local", "reliable")
func apply_sortie_units(
	garrison_id: String,
	new_id: String,
	out_units: Array,
	cell_x: int,
	cell_y: int,
	cargo_out: Dictionary = {}
) -> void:
	if not forces.has(garrison_id):
		return
	GlobalUnits.subtract_units(forces[garrison_id]["units"], out_units)
	# Sortie onto the map costs a full turn of preparation; army starts with 0 MP.
	var controller := GlobalUnits.primary_owner(GlobalUnits.units_from_spec(out_units))
	_spawn_army_figure(new_id, GlobalUnits.units_from_spec(out_units), Vector2i(cell_x, cell_y), 0, controller)
	var moved := take_force_cargo(garrison_id, cargo_out)
	add_force_cargo(new_id, moved)
	_flush_cargo_if_force_empty(garrison_id, new_id)
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
	var merged_cargo := GlobalUnits.empty_caravan_cargo()
	for fid in _building_garrison_force_ids(b):
		for vid in get_vips_on_force(fid):
			vip_ids.append(vid)
		merged_cargo = GlobalUnits.add_caravan_stocks(merged_cargo, get_force_cargo(str(fid)))
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
	set_force_cargo(new_id, merged_cargo)
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
		"cargo": GlobalUnits.empty_caravan_cargo(),
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


## Prefer free tiles orthogonally adjacent to a road (not on a road). Fallback: any free walkable.
func get_camp_placement_cells_in_province(prov: Node) -> Array[Vector2i]:
	var free := get_free_walkable_cells_in_province(prov)
	if free.is_empty():
		return free
	var roadside: Array[Vector2i] = []
	var ortho := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for cell in free:
		if pathfinding.is_road_cell(cell):
			continue
		var beside_road := false
		for d in ortho:
			if pathfinding.is_road_cell(cell + d):
				beside_road = true
				break
		if beside_road:
			roadside.append(cell)
	if roadside.is_empty():
		return free
	return roadside


func merchant_count_in_province(prov: Node) -> int:
	if prov == null or merchants == null:
		return 0
	var n := 0
	for m in merchants.get_children():
		if bool(m.get("camp_hidden")):
			continue
		if m.get("province") == prov:
			n += 1
	return n


func merchant_competition_in_province(prov: Node) -> bool:
	return merchant_count_in_province(prov) >= 2


func player_has_raided_merchants(player_id: int) -> bool:
	return bool(merchant_raiders.get(player_id, false))


func is_province_forbidden_for_merchants(prov: Node) -> bool:
	if prov == null:
		return true
	var dejure_id := int(prov.dejure) if prov.get("dejure") != null else -1
	return player_has_raided_merchants(dejure_id)


func spawn_merchants() -> void:
	if merchants == null:
		return
	for child in merchants.get_children():
		child.free()
	_clear_all_merchant_remnants()
	merchant_raiders.clear()
	_next_merchant_id = 1
	var prov_list: Array = provinces.get_children()
	if prov_list.is_empty():
		return
	prov_list.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4D455243  # "MERC"
	var count := int(ceili(float(prov_list.size()) / float(MERCHANTS_PER_PROVINCES)))
	var name_pool: Array = MERCHANT_NAMES.duplicate()
	for i in count:
		var display := "Merchant"
		if not name_pool.is_empty():
			var nidx := rng.randi() % name_pool.size()
			display = str(name_pool[nidx])
			name_pool.remove_at(nidx)
		var placed := false
		# Prefer empty provinces first; then any valid province (deterministic shuffle).
		var empty_first: Array = []
		var occupied: Array = []
		var pool: Array = prov_list.duplicate()
		while not pool.is_empty():
			var idx := rng.randi() % pool.size()
			var p = pool[idx]
			pool.remove_at(idx)
			if merchant_count_in_province(p) == 0:
				empty_first.append(p)
			else:
				occupied.append(p)
		var try_order: Array = empty_first + occupied
		for prov in try_order:
			if is_province_forbidden_for_merchants(prov):
				continue
			var cells := get_camp_placement_cells_in_province(prov)
			if cells.is_empty():
				continue
			_spawn_merchant_at(prov, cells[rng.randi() % cells.size()], rng, display)
			placed = true
			break
		if not placed:
			push_warning("Could not place merchant %d — no free cells" % i)


func _spawn_merchant_at(prov: Node, cell: Vector2i, rng: RandomNumberGenerator, display: String = "") -> Node:
	var m = MERCHANT_SCENE.instantiate()
	m.name = "merchant_%d" % _next_merchant_id
	_next_merchant_id += 1
	if display != "":
		m.display_name = display
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
	clear_expired_merchant_remnants()
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


func _merchant_move_candidates(m: Node, exclude_current: bool) -> Array:
	var current_prov = m.get("province")
	var candidates: Array = []
	for prov in provinces.get_children():
		if exclude_current and prov == current_prov:
			continue
		if is_province_forbidden_for_merchants(prov):
			continue
		candidates.append(prov)
	return candidates


func _try_move_merchant(m: Node, rng: RandomNumberGenerator) -> void:
	var was_hidden := bool(m.get("camp_hidden"))
	var candidates := _merchant_move_candidates(m, not was_hidden)
	if candidates.is_empty():
		_hide_merchant(m)
		m.seasons_left = 0
		return
	# Deterministic random order.
	var ordered: Array = []
	while not candidates.is_empty():
		var idx := rng.randi() % candidates.size()
		ordered.append(candidates[idx])
		candidates.remove_at(idx)
	for dest in ordered:
		var cells := get_camp_placement_cells_in_province(dest)
		if cells.is_empty():
			continue
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		pathfinding.unblock_object(m)
		m.place_at_cell(cell, dest)
		m.roll_stay(rng)
		if not pathfinding.block_cell_for_object(cell, m):
			# Extremely unlikely race; stay unblocked / hidden and retry next season.
			_hide_merchant(m)
			m.seasons_left = 0
		return
	# No free cell in any allowed province — hide and retry next season.
	_hide_merchant(m)
	m.seasons_left = 0


func _hide_merchant(m: Node) -> void:
	if m == null or not is_instance_valid(m):
		return
	pathfinding.unblock_object(m)
	if m.has_method("hide_camp"):
		m.hide_camp()
	else:
		m.visible = false


func get_merchant_by_id(merchant_id: String) -> Node:
	if merchants == null:
		return null
	return merchants.get_node_or_null(merchant_id)


func _evict_merchants_from_raider_provinces(raider: int, skip: Node = null) -> void:
	if merchants == null:
		return
	for other in merchants.get_children():
		if other == skip or not is_instance_valid(other):
			continue
		if bool(other.get("camp_hidden")):
			continue
		var prov = other.get("province")
		if prov == null:
			continue
		if int(prov.dejure) != raider:
			continue
		# Hide until next season (same as the raided merchant).
		_hide_merchant(other)
		other.seasons_left = 0


func _ensure_merchant_remnants() -> Node2D:
	if _merchant_remnants != null and is_instance_valid(_merchant_remnants):
		return _merchant_remnants
	_merchant_remnants = get_node_or_null("merchant_remnants") as Node2D
	if _merchant_remnants == null:
		_merchant_remnants = Node2D.new()
		_merchant_remnants.name = "merchant_remnants"
		add_child(_merchant_remnants)
	return _merchant_remnants


func _clear_all_merchant_remnants() -> void:
	var root := _ensure_merchant_remnants()
	for child in root.get_children():
		child.queue_free()


func clear_expired_merchant_remnants() -> void:
	var root := _ensure_merchant_remnants()
	for child in root.get_children():
		var spawn_t := int(child.get_meta("spawn_turn", -1))
		if spawn_t >= 0 and spawn_t != turn:
			root.remove_child(child)
			child.queue_free()


func _spawn_merchant_raid_remnant(at_cell: Vector2i, global_pos: Vector2) -> void:
	var root := _ensure_merchant_remnants()
	var remnant := Node2D.new()
	remnant.name = "raid_remnant_%d_%d" % [at_cell.x, at_cell.y]
	remnant.global_position = global_pos
	remnant.set_meta("spawn_turn", turn)
	var ground := Sprite2D.new()
	ground.name = "ground"
	ground.position = Vector2(32, 16)
	ground.modulate = Color(0.85, 0.75, 0.45, 1)
	ground.texture = preload("res://sprites/overworld/objects/province/economy/base_ground_economy.png")
	remnant.add_child(ground)
	var spr := Sprite2D.new()
	spr.name = "building_spr"
	spr.position = Vector2(32, 12)
	spr.texture = preload("res://sprites/overworld/objects/province/merchant/merchant.png")
	remnant.add_child(spr)
	root.add_child(remnant)
	_attach_building_smoke(remnant, RAID_SMOKE_INTENSITY)


const MERCHANT_RAID_MARKS := 15000
const MERCHANT_RAID_FIRST_MATERIALS := {
	"grain": 10000,
	"iron": 5000,
	"wood": 5000,
	"stone": 5000,
}
const MERCHANT_RAID_FIRST_WEAPONS := {
	"bows": 200,
	"maces": 200,
	"pikes": 200,
	"swords": 200,
	"horses": 50,
	"armour": 50,
	"crossbows": 100,
}


func compute_merchant_raid_loot(raider: int, rng: RandomNumberGenerator) -> Dictionary:
	var cargo := GlobalUnits.empty_caravan_cargo()
	var marks := 0
	var depleted := player_has_raided_merchants(raider)
	if depleted:
		for k in ["stone", "iron", "wood"]:
			cargo[k] = rng.randi_range(100, 300)
	else:
		marks = MERCHANT_RAID_MARKS
		for k in MERCHANT_RAID_FIRST_MATERIALS:
			cargo[k] = int(MERCHANT_RAID_FIRST_MATERIALS[k])
		for k in MERCHANT_RAID_FIRST_WEAPONS:
			cargo[k] = int(MERCHANT_RAID_FIRST_WEAPONS[k])
	return {"marks": marks, "cargo": cargo, "depleted": depleted}


func do_raid_merchant(force_id: String, merchant_id: String) -> void:
	request_raid_merchant.rpc_id(1, force_id, merchant_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_raid_merchant(force_id: String, merchant_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if get_force_controller(force_id) != player_id:
		return
	var m := get_merchant_by_id(merchant_id)
	if m == null or bool(m.get("camp_hidden")):
		return
	var army = armies.get_node_or_null(force_id)
	if army == null or not force_has_movement(force_id, RAID_MP_COST):
		return
	var army_cell = pathfinding.get_army_cell(army)
	if army_cell not in pathfinding.get_approach_cells(m):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(turn) ^ hash(merchant_id) ^ hash(player_id) ^ 0x52414944
	var loot := compute_merchant_raid_loot(player_id, rng)
	var rem_cell: Vector2i = m.cell
	var rem_pos: Vector2 = m.global_position
	apply_raid_merchant.rpc(
		force_id,
		merchant_id,
		player_id,
		int(loot["marks"]),
		loot["cargo"],
		bool(loot["depleted"]),
		rem_cell.x,
		rem_cell.y,
		rem_pos.x,
		rem_pos.y
	)


@rpc("authority", "call_local", "reliable")
func apply_raid_merchant(
	force_id: String,
	merchant_id: String,
	raider: int,
	marks: int,
	cargo: Dictionary,
	depleted: bool,
	rem_cell_x: int,
	rem_cell_y: int,
	rem_pos_x: float,
	rem_pos_y: float
) -> void:
	var m := get_merchant_by_id(merchant_id)
	if m == null:
		return
	if not spend_force_movement(force_id, RAID_MP_COST):
		return
	clear_force_siege(force_id)
	var clean := GlobalUnits.sanitize_caravan_cargo(cargo)
	if players.has(raider) and marks > 0:
		players[raider].game_data["marks"] = int(players[raider].game_data.get("marks", 0)) + marks
	if forces.has(force_id) and GlobalUnits.caravan_cargo_has_any(clean):
		add_force_cargo(force_id, clean)
	merchant_raiders[raider] = true
	_spawn_merchant_raid_remnant(Vector2i(rem_cell_x, rem_cell_y), Vector2(rem_pos_x, rem_pos_y))
	# Hide until next season — do not place on the map again this turn.
	_hide_merchant(m)
	m.seasons_left = 0
	# Evict any other merchants already camping in the raider's de jure lands.
	_evict_merchants_from_raider_provinces(raider, m)
	if is_instance_valid(gui_node):
		if raider == my_pl_id:
			gui_node.update_money(players[my_pl_id].game_data["marks"])
			if gui_node.has_method("refresh_army_menu_if_force"):
				gui_node.refresh_army_menu_if_force(force_id)
		var mname := str(m.get("display_name") if m.get("display_name") != null else "Merchant")
		if depleted:
			gui_node.show_info_popup(
				"%s heard of your presence in advance — most of the stock was already gone.\nLoot: %s"
				% [mname, GlobalUnits.caravan_cargo_summary(clean)]
			)
		else:
			var bits: PackedStringArray = []
			if marks > 0:
				bits.append("%d marks" % marks)
			var cargo_s := GlobalUnits.caravan_cargo_summary(clean)
			if cargo_s != "(empty)":
				bits.append(cargo_s)
			gui_node.show_info_popup("Raided %s.\nLoot: %s" % [mname, ", ".join(bits)])
	update_all_army_visuals()


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
	# Per-player arsenal; horses go to the buyer's holding via add_weapons_for.
	if prov.has_method("add_weapons_for"):
		prov.add_weapons_for(player_id, weapons)
	if prov.get("resources") != null:
		GlobalUnits.add_materials(prov.resources, materials, player_id)
	if is_instance_valid(gui_node):
		if player_id == my_pl_id:
			gui_node.update_money(players[my_pl_id].game_data["marks"])
			if gui_node.has_method("refresh_merchant_shop_if_open"):
				gui_node.refresh_merchant_shop_if_open()
		update_menus()


func _merchant_cart_total_sell(weapons: Dictionary, materials: Dictionary, competition: bool) -> int:
	var total := 0
	for k in GlobalUnits.WEAPON_KEYS:
		var amt := int(weapons.get(k, 0))
		if amt > 0:
			total += GlobalUnits.weapon_mark_sell_price(k, competition) * amt
	for k in GlobalUnits.MATERIAL_KEYS:
		var amt := int(materials.get(k, 0))
		if amt > 0:
			total += GlobalUnits.material_mark_sell_price(k, competition) * amt
	return total


func do_sell_to_merchant(merchant_id: String, weapons: Dictionary, materials: Dictionary) -> void:
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
	var total_payout := _merchant_cart_total_sell(weapons, materials, competition)
	if total_payout <= 0:
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Select items to sell")
		return
	if not prov.has_method("can_afford_caravan_cargo") or not prov.can_afford_caravan_cargo(my_pl_id, _merchant_sell_cargo(weapons, materials)):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup("Not enough stock to sell")
		return
	request_sell_to_merchant.rpc_id(1, merchant_id, weapons, materials, my_pl_id)


func _merchant_sell_cargo(weapons: Dictionary, materials: Dictionary) -> Dictionary:
	var cargo := {}
	for k in GlobalUnits.WEAPON_KEYS:
		cargo[k] = maxi(0, int(weapons.get(k, 0)))
	for k in GlobalUnits.MATERIAL_KEYS:
		cargo[k] = maxi(0, int(materials.get(k, 0)))
	return cargo


@rpc("any_peer", "call_local", "reliable")
func request_sell_to_merchant(
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
	if not prov.has_method("can_afford_caravan_cargo") or not prov.has_method("subtract_caravan_cargo"):
		return
	var competition := merchant_competition_in_province(prov)
	var cleaned_w := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_KEYS:
		cleaned_w[k] = maxi(0, int(weapons.get(k, 0)))
	var cleaned_m := GlobalUnits.empty_material_stock()
	for k in GlobalUnits.MATERIAL_KEYS:
		cleaned_m[k] = maxi(0, int(materials.get(k, 0)))
	# Clamp to available stock.
	if prov.has_method("get_weapons_for"):
		var avail_w: Dictionary = prov.get_weapons_for(player_id)
		for k in GlobalUnits.WEAPON_KEYS:
			cleaned_w[k] = mini(cleaned_w[k], maxi(0, int(avail_w.get(k, 0))))
	for k in GlobalUnits.MATERIAL_KEYS:
		if prov.has_method("get_player_material"):
			cleaned_m[k] = mini(cleaned_m[k], maxi(0, prov.get_player_material(player_id, k)))
	var total_payout := _merchant_cart_total_sell(cleaned_w, cleaned_m, competition)
	if total_payout <= 0:
		return
	var cargo := _merchant_sell_cargo(cleaned_w, cleaned_m)
	if not prov.can_afford_caravan_cargo(player_id, cargo):
		return
	apply_sell_to_merchant.rpc(merchant_id, cleaned_w, cleaned_m, player_id, total_payout)


@rpc("authority", "call_local", "reliable")
func apply_sell_to_merchant(
	merchant_id: String,
	weapons: Dictionary,
	materials: Dictionary,
	player_id: int,
	total_payout: int
) -> void:
	var m := get_merchant_by_id(merchant_id)
	if m == null:
		return
	var prov = m.get("province")
	if prov == null or not prov.has_method("subtract_caravan_cargo"):
		return
	if not players.has(player_id):
		return
	if total_payout <= 0:
		return
	var cargo := _merchant_sell_cargo(weapons, materials)
	if not prov.can_afford_caravan_cargo(player_id, cargo):
		return
	prov.subtract_caravan_cargo(player_id, cargo)
	var marks := int(players[player_id].game_data.get("marks", 0))
	players[player_id].game_data["marks"] = marks + total_payout
	if is_instance_valid(gui_node):
		if player_id == my_pl_id:
			gui_node.update_money(players[my_pl_id].game_data["marks"])
			if gui_node.has_method("refresh_merchant_shop_if_open"):
				gui_node.refresh_merchant_shop_if_open()
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
			var cells := get_camp_placement_cells_in_province(prov)
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
	var cell := _force_anchor_cell(force_id)
	if cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return null
	return find_province_for_cell(cell)


## Client helper: true if disbanding here refunds weapons to province stock.
func disband_refunds_weapons(force_id: String, player_id: int) -> bool:
	var prov := get_force_province(force_id)
	if prov == null or not prov.has_method("has_dejure"):
		return false
	return prov.has_dejure(player_id)


func do_recruit_levy(province_id: String, composition: Array) -> bool:
	var err := _try_recruit_levy(province_id, composition, my_pl_id)
	if err != "":
		if is_instance_valid(gui_node):
			gui_node.show_info_popup(err)
		return false
	return true


## Flatten composition to a typed int array for reliable RPC: [type, count, type, count, ...]
func _composition_to_packed(composition: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for entry in composition:
		var cnt := int(entry.get("count", 0))
		if cnt <= 0:
			continue
		out.append(int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT)))
		out.append(cnt)
	return out


func _composition_from_packed(packed: PackedInt32Array) -> Array:
	var out: Array = []
	var i := 0
	while i + 1 < packed.size():
		var cnt := int(packed[i + 1])
		if cnt > 0:
			out.append({"type": int(packed[i]), "count": cnt})
		i += 2
	return out


## Returns "" on success, or a human-readable error.
func _try_recruit_levy(province_id: String, composition: Array, player_id: int) -> String:
	player_id = int(player_id)
	if not players.has(player_id):
		return "Unknown player"
	var prov := _get_province_by_id(province_id)
	if prov == null:
		return "Province not found"
	if not prov.has_method("has_dejure") or not prov.has_dejure(player_id):
		return "You need de jure ownership to recruit here"

	var total := GlobalUnits.composition_total_men(composition)
	if total < GlobalUnits.MIN_SPLIT_MEN:
		return "Need at least %d men (got %d)" % [GlobalUnits.MIN_SPLIT_MEN, total]
	var levy_left := int(prov.max_levy_remaining())
	var owned_pop := int(prov.owned_settlement_population(player_id))
	if total > levy_left:
		return "Not enough levy capacity (left %d, need %d)" % [levy_left, total]
	if total > owned_pop:
		return "Not enough population (have %d, need %d)" % [owned_pop, total]

	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if not prov.can_afford_weapons_for(player_id, need):
		return "Not enough weapons in this province"

	var spawn_b: Node = prov.get_recruit_spawn_building(player_id)
	if spawn_b == null:
		return "No seat/town to raise the army near"
	var approach := get_free_approach_cell_for(spawn_b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		# Soft fallback: any free walkable cell near the building footprint.
		approach = _free_cell_near_building(spawn_b)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return "No free tile adjacent to town/seat"

	var units: Array = []
	for entry in composition:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
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
		return "Could not build unit stacks"

	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force

	# Apply inline (no RPC). Nested dict RPCs were silently no-oping before.
	prov.subtract_weapons_for(player_id, need)
	if not prov.deduct_population(player_id, total):
		prov.add_weapons_for(player_id, need)
		return "Not enough settlement population to raise %d men" % total
	var prev_levied := int(prov.levied_this_season)
	prov.levied_this_season = prev_levied + total
	prov.apply_levy_happiness(prev_levied, prov.levied_this_season)

	_spawn_army_figure(new_id, units, approach, -1, player_id)
	if not forces.has(new_id):
		return "Army spawn failed"
	if pathfinding != null:
		pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	update_players_population()
	if prov.has_method("recalculate_marks_will_by_player"):
		prov.recalculate_marks_will_by_player()
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)

	# Sync remotes with a packed (RPC-safe) payload when peers exist.
	var packed := _composition_to_packed(composition)
	for peer_id in multiplayer.get_peers():
		apply_recruit_levy_packed.rpc_id(
			peer_id, province_id, player_id, packed, new_id, approach.x, approach.y
		)
	return ""


@rpc("any_peer", "call_local", "reliable")
func request_recruit_levy(province_id: String, composition: Array, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	_try_recruit_levy(province_id, composition, player_id)


@rpc("authority", "call_remote", "reliable")
func apply_recruit_levy_packed(
	province_id: String,
	player_id: int,
	packed: PackedInt32Array,
	new_id: String,
	cell_x: int,
	cell_y: int
) -> void:
	if forces.has(new_id):
		return
	var composition := _composition_from_packed(packed)
	var prov := _get_province_by_id(province_id)
	if prov == null:
		return
	var total := GlobalUnits.composition_total_men(composition)
	if total <= 0:
		return
	var need := GlobalUnits.weapons_needed_for_composition(composition)
	prov.subtract_weapons_for(player_id, need)
	if not prov.deduct_population(player_id, total):
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
	_spawn_army_figure(new_id, units, Vector2i(cell_x, cell_y), -1, player_id)
	if pathfinding != null:
		pathfinding.rebuild_occupancy()
	update_all_army_visuals()
	update_players_population()


# Kept for save/compat callers; prefer _try_recruit_levy.
@rpc("authority", "call_local", "reliable")
func apply_recruit_levy(
	province_id: String,
	player_id: int,
	composition: Array,
	new_id: String,
	cell_x: int,
	cell_y: int
) -> void:
	if forces.has(new_id):
		return
	var packed := _composition_to_packed(composition)
	apply_recruit_levy_packed(province_id, player_id, packed, new_id, cell_x, cell_y)


# --- Caravans ---------------------------------------------------------------

func get_province_town(province_id: String) -> Node:
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("get_town"):
		return null
	return prov.get_town()


func can_spawn_caravan_at(province_id: String) -> bool:
	var town := get_province_town(province_id)
	if town == null:
		return false
	return get_free_approach_cell_for(town) != Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


func get_caravan_spawn_blocked_reason(province_id: String) -> String:
	var town := get_province_town(province_id)
	if town == null:
		return "No town in this province"
	if get_free_approach_cell_for(town) == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return "No free tile next to the town (another army or caravan is blocking)"
	return ""


func list_caravans_for_player(player_id: int) -> Array:
	var out: Array = []
	if caravans == null:
		return out
	for c in caravans.get_children():
		if int(c.player_owner) == player_id:
			out.append(c)
	return out


func do_send_caravan(from_id: String, to_id: String, cargo: Dictionary) -> void:
	var reason := get_caravan_spawn_blocked_reason(from_id)
	if reason != "":
		if is_instance_valid(gui_node):
			gui_node.show_info_popup(reason)
		return
	request_send_caravan.rpc_id(1, from_id, to_id, cargo, my_pl_id)


## True if this force may deposit cargo into the province underfoot (de jure or holding).
func can_force_deposit_cargo(force_id: String, player_id: int = -1) -> bool:
	var pid = player_id if player_id >= 0 else my_pl_id
	var prov = province_under_force(force_id)
	if prov == null:
		return false
	var has_dejure = prov.has_method("has_dejure") and prov.has_dejure(pid)
	var has_holding = prov.has_method("player_has_holding") and prov.player_has_holding(pid)
	return has_dejure or has_holding


## Deposit force cargo into the province underfoot (caller's per-player stock).
func do_force_deposit_cargo(force_id: String, cargo: Dictionary) -> void:
	if not can_force_deposit_cargo(force_id, my_pl_id):
		if is_instance_valid(gui_node):
			gui_node.show_info_popup(
				"Need de jure ownership or a holding here to deposit. Send a caravan home instead."
			)
		return
	request_force_deposit_cargo.rpc_id(1, force_id, cargo, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_force_deposit_cargo(force_id: String, cargo: Dictionary, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if get_force_controller(force_id) != player_id:
		return
	var prov = province_under_force(force_id)
	if prov == null:
		return
	if not can_force_deposit_cargo(force_id, player_id):
		return
	var taken := GlobalUnits.clamp_caravan_stock(get_force_cargo(force_id), cargo)
	if not GlobalUnits.caravan_cargo_has_any(taken):
		return
	apply_force_deposit_cargo.rpc(force_id, taken, player_id, str(prov.name))


@rpc("authority", "call_local", "reliable")
func apply_force_deposit_cargo(force_id: String, cargo: Dictionary, player_id: int, province_id: String) -> void:
	if not forces.has(force_id):
		return
	var prov := _get_province_by_id(province_id)
	if prov == null:
		return
	var has_dejure = prov.has_method("has_dejure") and prov.has_dejure(player_id)
	var has_holding = prov.has_method("player_has_holding") and prov.player_has_holding(player_id)
	if not has_dejure and not has_holding:
		return
	var taken := take_force_cargo(force_id, cargo)
	if not GlobalUnits.caravan_cargo_has_any(taken):
		return
	if prov.has_method("add_caravan_cargo_for"):
		prov.add_caravan_cargo_for(player_id, taken)
	elif prov.has_method("add_weapons_for"):
		prov.add_weapons_for(player_id, taken)
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


## Withdraw weapons/materials from a de jure province under the force into army cargo.
func do_force_withdraw_cargo(force_id: String, cargo: Dictionary) -> void:
	request_force_withdraw_cargo.rpc_id(1, force_id, cargo, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_force_withdraw_cargo(force_id: String, cargo: Dictionary, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if get_force_controller(force_id) != player_id:
		return
	var prov = province_under_force(force_id)
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(player_id):
		return
	var want := GlobalUnits.sanitize_caravan_cargo(cargo)
	if not GlobalUnits.caravan_cargo_has_any(want):
		return
	if not prov.can_afford_caravan_cargo(player_id, want):
		return
	apply_force_withdraw_cargo.rpc(force_id, want, player_id, str(prov.name))


@rpc("authority", "call_local", "reliable")
func apply_force_withdraw_cargo(force_id: String, cargo: Dictionary, player_id: int, province_id: String) -> void:
	if not forces.has(force_id):
		return
	var prov := _get_province_by_id(province_id)
	if prov == null:
		return
	var want := GlobalUnits.sanitize_caravan_cargo(cargo)
	if not prov.can_afford_caravan_cargo(player_id, want):
		return
	prov.subtract_caravan_cargo(player_id, want)
	add_force_cargo(force_id, want)
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


## Spawn a caravan from a force's cargo to a de jure destination (no province debit).
func do_force_send_caravan(force_id: String, dest_id: String, cargo: Dictionary) -> void:
	request_force_send_caravan.rpc_id(1, force_id, dest_id, cargo, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_force_send_caravan(force_id: String, dest_id: String, cargo: Dictionary, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if get_force_controller(force_id) != player_id:
		return
	var to_prov := _get_province_by_id(dest_id)
	if to_prov == null or not to_prov.has_dejure(player_id):
		return
	var taken := GlobalUnits.clamp_caravan_stock(get_force_cargo(force_id), cargo)
	if not GlobalUnits.caravan_cargo_has_any(taken):
		return
	var from_cell := _force_anchor_cell(force_id)
	if from_cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return
	var free_cell := _bfs_free_cell_near(from_cell, {from_cell: true})
	if free_cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return
	_next_caravan_id += 1
	var new_id := "cv_%d" % _next_caravan_id
	apply_force_send_caravan.rpc(force_id, new_id, dest_id, taken, player_id, free_cell.x, free_cell.y)


@rpc("authority", "call_local", "reliable")
func apply_force_send_caravan(
	force_id: String,
	caravan_id: String,
	dest_id: String,
	cargo: Dictionary,
	player_id: int,
	cell_x: int,
	cell_y: int
) -> void:
	if not forces.has(force_id):
		return
	var taken := take_force_cargo(force_id, cargo)
	if not GlobalUnits.caravan_cargo_has_any(taken):
		return
	_spawn_caravan(caravan_id, player_id, dest_id, taken, Vector2i(cell_x, cell_y))
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


@rpc("any_peer", "call_local", "reliable")
func request_send_caravan(from_id: String, to_id: String, cargo: Dictionary, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if from_id == to_id:
		return
	if not players.has(player_id):
		return
	var from_prov := _get_province_by_id(from_id)
	var to_prov := _get_province_by_id(to_id)
	if from_prov == null or to_prov == null:
		return
	if not from_prov.has_dejure(player_id):
		return
	var town = from_prov.get_town() if from_prov.has_method("get_town") else null
	if town == null:
		return
	var approach := get_free_approach_cell_for(town)
	if approach == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return
	var clean := GlobalUnits.sanitize_caravan_cargo(cargo)
	if not GlobalUnits.caravan_cargo_has_any(clean):
		return
	if not from_prov.can_afford_caravan_cargo(player_id, clean):
		return
	_next_caravan_id += 1
	var new_id := "cv_%d" % _next_caravan_id
	apply_send_caravan.rpc(new_id, from_id, to_id, clean, player_id, approach.x, approach.y)


@rpc("authority", "call_local", "reliable")
func apply_send_caravan(
	caravan_id: String,
	from_id: String,
	to_id: String,
	cargo: Dictionary,
	player_id: int,
	cell_x: int,
	cell_y: int
) -> void:
	var from_prov := _get_province_by_id(from_id)
	if from_prov == null:
		return
	var clean := GlobalUnits.sanitize_caravan_cargo(cargo)
	if not from_prov.can_afford_caravan_cargo(player_id, clean):
		return
	from_prov.subtract_caravan_cargo(player_id, clean)
	_spawn_caravan(caravan_id, player_id, to_id, clean, Vector2i(cell_x, cell_y))
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


func _spawn_caravan(
	caravan_id: String,
	owner_id: int,
	dest_id: String,
	cargo: Dictionary,
	cell: Vector2i
) -> void:
	var fig = CARAVAN_SCENE.instantiate()
	fig.name = caravan_id
	caravans.add_child(fig)
	fig.base_map = self
	fig.caravan_id = caravan_id
	fig.player_owner = owner_id
	fig.dest_province_id = dest_id
	fig.cargo = GlobalUnits.sanitize_caravan_cargo(cargo)
	fig.movement_points = GlobalUnits.CARAVAN_MOVEMENT_POINTS
	fig.reset_movement()
	fig.set_flags()
	pathfinding.place_caravan_at_cell(fig, cell)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


func do_redirect_caravan(caravan_id: String, dest_id: String) -> void:
	request_redirect_caravan.rpc_id(1, caravan_id, dest_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_redirect_caravan(caravan_id: String, dest_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var c = caravans.get_node_or_null(caravan_id) if caravans != null else null
	if c == null:
		return
	if int(c.player_owner) != player_id:
		return
	if _get_province_by_id(dest_id) == null:
		return
	apply_redirect_caravan.rpc(caravan_id, dest_id)


@rpc("authority", "call_local", "reliable")
func apply_redirect_caravan(caravan_id: String, dest_id: String) -> void:
	var c = caravans.get_node_or_null(caravan_id) if caravans != null else null
	if c == null:
		return
	c.dest_province_id = dest_id
	c.path_fail_streak = 0
	c.path_fail_notified = false
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_caravan_menu_if"):
		gui_node.refresh_caravan_menu_if(self, c)


func do_capture_caravan(caravan_id: String) -> void:
	request_capture_caravan.rpc_id(1, caravan_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_capture_caravan(caravan_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var c = caravans.get_node_or_null(caravan_id) if caravans != null else null
	if c == null:
		return
	if int(c.player_owner) == player_id:
		return
	if are_friendly_players(int(c.player_owner), player_id):
		return
	# Must have a controllable army adjacent.
	if not _player_has_army_adjacent_to(player_id, c):
		return
	apply_capture_caravan.rpc(caravan_id, player_id)


@rpc("authority", "call_local", "reliable")
func apply_capture_caravan(caravan_id: String, player_id: int) -> void:
	var c = caravans.get_node_or_null(caravan_id) if caravans != null else null
	if c == null:
		return
	c.player_owner = player_id
	c.path_fail_streak = 0
	c.path_fail_notified = false
	c.set_flags()
	update_all_army_visuals()
	if player_id == my_pl_id and is_instance_valid(gui_node):
		if gui_node.has_method("open_caravan_menu"):
			gui_node.open_caravan_menu(self, c)
		else:
			gui_node.show_info_popup("Caravan captured")


func do_destroy_caravan(caravan_id: String) -> void:
	request_destroy_caravan.rpc_id(1, caravan_id, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_destroy_caravan(caravan_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var c = caravans.get_node_or_null(caravan_id) if caravans != null else null
	if c == null:
		return
	# Owner cannot scuttle; only an adjacent enemy army may destroy.
	if int(c.player_owner) == player_id:
		return
	if are_friendly_players(int(c.player_owner), player_id):
		return
	if not _player_has_army_adjacent_to(player_id, c):
		return
	apply_destroy_caravan.rpc(caravan_id, player_id)


@rpc("authority", "call_local", "reliable")
func apply_destroy_caravan(caravan_id: String, player_id: int = -1) -> void:
	var c = caravans.get_node_or_null(caravan_id) if caravans != null else null
	if c == null:
		return
	c.queue_free()
	call_deferred("_rebuild_occupancy_after_caravan_removed")
	if player_id == my_pl_id and is_instance_valid(gui_node):
		if gui_node.has_method("close_caravan_menus"):
			gui_node.close_caravan_menus()
		gui_node.show_info_popup("Caravan destroyed")


func _rebuild_occupancy_after_caravan_removed() -> void:
	if pathfinding != null:
		pathfinding.rebuild_occupancy()
	update_all_army_visuals()


func _player_has_army_adjacent_to(player_id: int, target: Node2D) -> bool:
	if pathfinding == null or target == null:
		return false
	for army in armies.get_children():
		if not army.is_controllable_by(player_id):
			continue
		if pathfinding.are_armies_adjacent(army, target):
			return true
	return false


func tick_all_caravans() -> void:
	if caravans == null:
		return
	# Snapshot ids — delivery removes nodes mid-loop.
	var ids: Array = []
	for c in caravans.get_children():
		ids.append(String(c.name))
	for cid in ids:
		var c = caravans.get_node_or_null(cid)
		if c == null:
			continue
		c.reset_movement()
		_advance_caravan_one_season(c)
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


func _advance_caravan_one_season(c: Node2D) -> void:
	var dest_town := get_province_town(str(c.dest_province_id))
	if dest_town == null:
		_note_caravan_path_fail(c)
		return
	var from_cell: Vector2i = pathfinding.get_army_cell(c)
	var approach: Array[Vector2i] = pathfinding.get_approach_cells(dest_town)
	if from_cell in approach:
		_deliver_caravan(c)
		return
	if approach.is_empty():
		_note_caravan_path_fail(c)
		return
	var path: Array[Vector2i] = pathfinding.find_path_for_mover(c, from_cell, approach)
	if path.size() < 2:
		_note_caravan_path_fail(c)
		return
	# Successful path found — clear fail streak (movement may still be 0 MP edge).
	c.path_fail_streak = 0
	var stop_i: int = pathfinding.farthest_affordable_index(path, c.movement_left)
	while stop_i > 0:
		if pathfinding.cell_blocked_for_stop(c, path[stop_i]):
			stop_i -= 1
			continue
		break
	if stop_i <= 0:
		_note_caravan_path_fail(c)
		return
	var end_cell: Vector2i = path[stop_i]
	var spent := 0
	for i in range(1, stop_i + 1):
		spent += pathfinding.enter_cost(path[i])
	pathfinding.place_caravan_at_cell(c, end_cell)
	c.movement_left = maxi(0, c.movement_left - spent)
	if end_cell in approach:
		_deliver_caravan(c)


func _note_caravan_path_fail(c: Node2D) -> void:
	c.path_fail_streak = int(c.path_fail_streak) + 1
	if int(c.path_fail_streak) < GlobalUnits.CARAVAN_PATH_FAIL_NOTIFY:
		return
	if bool(c.path_fail_notified):
		return
	c.path_fail_notified = true
	if int(c.player_owner) != my_pl_id:
		return
	if is_instance_valid(gui_node):
		gui_node.show_info_popup(
			"Your caravan is stuck — no path to its destination. Go check its location."
		)


func _deliver_caravan(c: Node2D) -> void:
	var dest_id := str(c.dest_province_id)
	var prov := _get_province_by_id(dest_id)
	var town := get_province_town(dest_id)
	if prov == null or town == null:
		# Stay put until a town exists again.
		return
	var receiver := int(town.player_owner) if town.get("player_owner") != null else -1
	if receiver < 0:
		return
	if prov.has_method("add_caravan_cargo_for"):
		prov.add_caravan_cargo_for(receiver, c.cargo)
	var owner_id := int(c.player_owner)
	c.queue_free()
	call_deferred("_rebuild_occupancy_after_caravan_removed")
	if owner_id == my_pl_id and is_instance_valid(gui_node):
		var pname := str(get_province_data(dest_id).get("name", dest_id))
		gui_node.show_info_popup("Caravan arrived in %s" % pname)
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
	var army_cell: Vector2i
	if fig != null:
		army_cell = pathfinding.get_army_cell(fig)
	elif force_is_aboard(force_id):
		# Disbanding while at sea: place foreign remnants on nearby land if any.
		var fleet_cell := _force_anchor_cell(force_id)
		army_cell = pathfinding.get_free_adjacent_cell(fleet_cell)
		if army_cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
			army_cell = fleet_cell
	else:
		return

	var units: Array = forces[force_id]["units"]
	var disbanding_player: int = get_force_controller(force_id)
	if disbanding_player < 0:
		disbanding_player = GlobalUnits.primary_owner(units)

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
		var loc: Dictionary = forces[force_id].get("location", {})
		if str(loc.get("kind", "")) == "aboard":
			var fleet := get_fleet_by_id(str(loc.get("fleet", "")))
			if fleet != null:
				fleet.aboard_force_ids.erase(force_id)
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
		if rprov != null and refund_player_id >= 0 and rprov.has_method("add_weapons_for"):
			rprov.add_weapons_for(refund_player_id, refund_weapons)

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
	forces[new_id] = {
		"units": units,
		"location": {"kind": "cell"},
		"controller": controller,
		"cargo": GlobalUnits.empty_caravan_cargo(),
	}
	_assign_force_display_name(new_id)
	fig.bind_force(new_id)
	pathfinding.place_army_at_cell(fig, cell)
	if starting_mp < 0:
		fig.reset_movement()
	else:
		fig.movement_left = clampi(starting_mp, 0, fig.effective_max_mp())
	refresh_army_labels()


func reset_all_army_movement() -> void:
	for army in armies.get_children():
		army.reset_movement()
	if fleets != null:
		for f in fleets.get_children():
			f.reset_movement()


func update_all_army_visuals() -> void:
	for army in armies.get_children():
		army.set_greyed(army.is_controllable_by(my_pl_id) and army.movement_left <= 0)
	if caravans != null:
		for c in caravans.get_children():
			c.set_greyed(c.is_controllable_by(my_pl_id) and c.movement_left <= 0)
	if fleets != null:
		for f in fleets.get_children():
			f.set_greyed(f.is_controllable_by(my_pl_id) and f.movement_left <= 0)


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
		if GlobalStuff.is_auto_turn_player(p.type):
			p.ended_turn = true
		else:
			p.ended_turn = false
	
	# update player data
	update_player_data.rpc(players)
	
func get_unfinished_players_for_peer(peer_id:int) -> Array:
	var result := []

	for p : GlobalStuff.PlayerData in players.values():
		if (p.owner_peer_id == peer_id and !p.ended_turn and not GlobalStuff.is_auto_turn_player(p.type) and
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
	tick_all_sieges()
	tick_all_caravans()
	tick_razed_buildings()
	clear_expired_raid_smoke()
	tick_merchants()
	tick_sellswords()
	# Season already bumped; apply agriculture for the season that just ended.
	tick_all_agriculture()
	# Councils act after plant/harvest so grain labor matches the new season's fields.
	CouncilAI.tick_all(self)
	#calculate and then display the new data
	add_resources()
	tick_army_upkeep()
	# Clear province-fed flags, feed local armies + civilians from granaries, then cargo food.
	_clear_province_fed_flags()
	tick_all_province_rations()
	tick_army_food()
	for prov in provinces.get_children():
		if prov.has_method("snapshot_season_start"):
			prov.snapshot_season_start()
	# Settlement sprites lag one turn behind live population tiers.
	refresh_all_settlement_visual_stages()
	update_visuals_and_stats()
	province_borders.rebuild()
	build_province_neighbors()


## Spawn a LOCAL_COUNCIL player for every map-authored unowned province (`player_owner == -1`).
func spawn_local_councils() -> void:
	var next_id := 0
	for pid in players.keys():
		next_id = maxi(next_id, int(pid) + 1)
	var prov_list: Array = provinces.get_children()
	prov_list.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for prov in prov_list:
		if int(prov.player_owner) != GlobalStuff.UNOWNED_PLAYER:
			continue
		var pname := str(prov.get("p_name")) if prov.get("p_name") != null else String(prov.name)
		var p := GlobalStuff.PlayerData.new(
			next_id,
			GlobalStuff.PLAYER_TYPE.LOCAL_COUNCIL,
			1,
			0,
			"Council of %s" % pname,
			{"marks": GlobalUnits.PROVINCE_START_MARKS, "people": 0, "home_province_id": String(prov.name)}
		)
		p.color = {"red": 140, "green": 140, "blue": 140}
		p.ended_turn = true
		players[next_id] = p
		prov.player_owner = next_id
		prov.home_province = false
		next_id += 1


func mark_auto_turn_players_ended() -> void:
	for p: GlobalStuff.PlayerData in players.values():
		if GlobalStuff.is_auto_turn_player(p.type):
			p.ended_turn = true


func is_local_council_player(player_id: int) -> bool:
	if not players.has(player_id):
		return false
	return GlobalStuff.is_local_council(players[player_id].type)


## Town fell to a lord: flip remaining council buildings, transfer stock/treasury, remove council.
func fold_local_council_on_town_capture(prov: Node, council_pid: int, capturer: int) -> void:
	if prov == null or not is_local_council_player(council_pid):
		return
	if capturer < 0 or capturer == council_pid:
		return
	for container_name in ["settlements", "economy", "defense"]:
		var container = prov.get_node_or_null(container_name)
		if container == null:
			continue
		for b in container.get_children():
			if b.get("player_owner") == null:
				continue
			if int(b.player_owner) != council_pid:
				continue
			b.player_owner = capturer
			if b.has_method("set_flags"):
				b.set_flags()
			_reassign_building_garrison_owner(b, council_pid, capturer)
	# Field armies / other forces still commanded by the council.
	for fid in forces.keys():
		if get_force_controller(str(fid)) != council_pid:
			continue
		forces[fid]["controller"] = capturer
		var units: Array = forces[fid].get("units", [])
		for s in units:
			if int(s.get("owner", -1)) == council_pid:
				s["owner"] = capturer
		forces[fid]["units"] = units
	# Absorb province stockpile before removing the council holder.
	if prov.has_method("transfer_remaining_holding_stock"):
		prov.transfer_remaining_holding_stock(council_pid, capturer)
	# Absorb leftover treasury.
	if players.has(council_pid) and players.has(capturer):
		var loot := int(players[council_pid].game_data.get("marks", 0))
		if loot > 0:
			players[capturer].game_data["marks"] = int(players[capturer].game_data.get("marks", 0)) + loot
			players[council_pid].game_data["marks"] = 0
			if capturer == my_pl_id and is_instance_valid(gui_node):
				gui_node.update_money(players[my_pl_id].game_data["marks"])
	prov.recompute_control()
	if capturer >= 0 and prov.has_method("ensure_holding"):
		prov.ensure_holding(capturer)
	remove_local_council_player(council_pid)


func _reassign_building_garrison_owner(building: Node, from_pid: int, to_pid: int) -> void:
	for fid in _building_garrison_force_ids(building):
		if not forces.has(fid):
			continue
		if int(forces[fid].get("controller", -1)) == from_pid:
			forces[fid]["controller"] = to_pid
		var units: Array = forces[fid].get("units", [])
		for s in units:
			if int(s.get("owner", -1)) == from_pid:
				s["owner"] = to_pid
		forces[fid]["units"] = units


func remove_local_council_player(pid: int) -> void:
	if not is_local_council_player(pid):
		return
	_remove_ally_everywhere(pid)
	alliances.erase(pid)
	players.erase(pid)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_alliances_list"):
		gui_node.refresh_alliances_list()


func _remove_ally_everywhere(pid: int) -> void:
	if alliances.has(pid):
		for other in alliances[pid].duplicate():
			_remove_ally(pid, int(other))
			_remove_ally(int(other), pid)
	for a in alliances.keys():
		if int(a) == pid:
			continue
		_remove_ally(int(a), pid)


func tick_all_agriculture() -> void:
	var ended_season := (int(season) + 3) % 4
	var new_season := int(season)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s-%s" % [turn, ended_season, new_season])
	for prov in provinces.get_children():
		if prov.has_method("tick_agriculture"):
			prov.tick_agriculture(ended_season, new_season, rng)


func _clear_province_fed_flags() -> void:
	for fid in forces:
		if forces[fid].has("province_fed"):
			forces[fid]["province_fed"] = false


## Seasonal grain need for this player's forces currently in `prov`.
func province_army_grain_need(prov: Node, player_id: int) -> int:
	var total := 0
	for fid in forces:
		if get_force_controller(fid) != player_id:
			continue
		if province_under_force(fid) != prov:
			continue
		var men := GlobalUnits.total_men(forces[fid]["units"])
		if men <= 0:
			continue
		total += GlobalUnits.force_grain_need(men, force_is_garrison(fid))
	return total


## Spend up to `budget` grain feeding this player's forces in `prov` (full need each).
## Marks fed forces with province_fed. Returns grain spent (caller debits stock).
func feed_province_armies_from_stock(prov: Node, player_id: int, budget: int) -> int:
	var left := maxi(0, budget)
	var spent := 0
	var fids: Array = forces.keys()
	fids.sort() # stable order across peers
	for fid in fids:
		if not forces.has(fid):
			continue
		if get_force_controller(fid) != player_id:
			continue
		if province_under_force(fid) != prov:
			continue
		var men := GlobalUnits.total_men(forces[fid]["units"])
		if men <= 0:
			continue
		var need := GlobalUnits.force_grain_need(men, force_is_garrison(fid))
		if need <= 0:
			forces[fid]["province_fed"] = true
			forces[fid]["food_shortfall_streak"] = 0
			continue
		if need > left:
			continue
		left -= need
		spent += need
		forces[fid]["province_fed"] = true
		forces[fid]["food_shortfall_streak"] = 0
		_sync_force_hunger_fx(fid)
	return spent


func tick_all_province_rations() -> void:
	var shrinks_by_player: Dictionary = {}
	# Seeded so over-cap pop jitter stays in sync across peers.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%s-rations" % [turn, int(season)])
	var prov_list: Array = provinces.get_children()
	prov_list.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	for prov in prov_list:
		if not prov.has_method("tick_rations"):
			continue
		var reports: Dictionary = prov.tick_rations(rng)
		for pid in reports:
			var key := int(pid)
			if not shrinks_by_player.has(key):
				shrinks_by_player[key] = []
			for entry in reports[pid]:
				shrinks_by_player[key].append(entry)
	for pid in shrinks_by_player:
		_make_civilian_food_event(int(pid), shrinks_by_player[pid])


func _make_civilian_food_event(player_id: int, entries: Array) -> void:
	if entries.is_empty():
		return
	var lines: PackedStringArray = []
	lines.append("Population fell in your holdings after last season's rations:")
	lines.append("")
	var world_pos := Vector2.ZERO
	for entry in entries:
		var req_name := str(entry.get("ration_name", GlobalUnits.ration_name(int(entry.get("ration", 0)))))
		var eff_name := str(entry.get("ration_effective_name", req_name))
		var ration_txt := req_name
		if eff_name != req_name:
			ration_txt = "%s (fed as %s)" % [req_name, eff_name]
		lines.append(
			"%s: %d → %d (−%d) · grain stock %d · rations %s"
			% [
				str(entry.get("province_name", "Province")),
				int(entry.get("old_pop", 0)),
				int(entry.get("new_pop", 0)),
				int(entry.get("dropped", 0)),
				int(entry.get("grain_stock", 0)),
				ration_txt,
			]
		)
		if world_pos == Vector2.ZERO:
			var prov := _get_province_by_id(str(entry.get("province_id", "")))
			if prov != null and prov is Node2D:
				world_pos = (prov as Node2D).global_position
	var event := {
		"kind": GameEvents.KIND.FOOD,
		"food_kind": "civilian_shrink",
		"text": "\n".join(lines),
		"turn": turn,
		"season": int(season),
		"place_name": "",
		"world_x": world_pos.x,
		"world_y": world_pos.y,
		"participant_ids": [player_id],
		"actor_id": -1,
	}
	var eid := _register_event(event)
	_deliver_event_to_players(eid, [player_id], -1, false)

	
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
		if GlobalStuff.is_auto_turn_player(p.type):
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
	var weather := get_node_or_null("WeatherObject")
	if weather != null and weather.has_method("roll_weather_for_season"):
		weather.roll_weather_for_season(int(season))

func refresh_all_settlement_visual_stages() -> void:
	for prov in provinces.get_children():
		var container = prov.get_node_or_null("settlements")
		if container == null:
			continue
		for b in container.get_children():
			if b.has_method("refresh_visual_stage"):
				b.refresh_visual_stage()


func update_visuals_and_stats():
	update_stats()
	update_gui()
	update_all_army_visuals()
	refresh_province_labels()
	refresh_army_labels()


func refresh_province_labels() -> void:
	for prov in provinces.get_children():
		if prov.has_method("refresh_map_label"):
			prov.refresh_map_label()
	if province_labels:
		province_labels.refresh()


func refresh_army_labels() -> void:
	for army in armies.get_children():
		if army.has_method("refresh_name_label"):
			army.refresh_name_label()
	if army_labels:
		army_labels.refresh()


func update_gui():
	gui_node.update_season(season)
	gui_node.update_pname(players[my_pl_id].name_)
	gui_node.update_money(players[my_pl_id].game_data["marks"])
	update_menus()

func update_menus():
	gui_node.update_economy_menu(self)
	if is_instance_valid(gui_node) and gui_node.has_method("refresh_military_tab_if_open"):
		gui_node.refresh_military_tab_if_open()

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
	# Settlement tax no longer pays the wallet — it fills settlement coffers in
	# tick_holding_rations. Refresh forecast only (silver mines pay via agriculture).
	recalculate_all_settlements_marks()


func add_resources():
	add_marks_to_players()


# --- Army upkeep / strikes / desertion --------------------------------------

func _ensure_upkeep_game_data(pid: int) -> void:
	if not players.has(pid):
		return
	var gd: Dictionary = players[pid].game_data
	if not gd.has("upkeep_strikes"):
		gd["upkeep_strikes"] = 0
	if not gd.has("upkeep_pay_streak"):
		gd["upkeep_pay_streak"] = 0


func get_upkeep_strikes(pid: int) -> int:
	_ensure_upkeep_game_data(pid)
	return int(players[pid].game_data.get("upkeep_strikes", 0))


func get_upkeep_pay_streak(pid: int) -> int:
	_ensure_upkeep_game_data(pid)
	return int(players[pid].game_data.get("upkeep_pay_streak", 0))


func force_nickname(fid: String) -> String:
	if not forces.has(fid):
		return ""
	return str(forces[fid].get("display_name", ""))


func _used_army_display_names(except_fid: String = "") -> Dictionary:
	var used := {}
	for fid in forces.keys():
		if str(fid) == except_fid:
			continue
		var n := str(forces[fid].get("display_name", ""))
		if n != "":
			used[n] = true
	return used


## Deterministic mint from force_id so every peer agrees without syncing the string.
func _assign_force_display_name(fid: String) -> void:
	if not forces.has(fid):
		return
	if str(forces[fid].get("display_name", "")) != "":
		return
	var used := _used_army_display_names(fid)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(fid)
	rng.state = used.size()
	forces[fid]["display_name"] = ArmyNames.mint_unique(used, rng) as String


func do_rename_force(force_id: String, new_name: String) -> void:
	request_rename_force.rpc_id(1, force_id, new_name, my_pl_id)


func do_reroll_force_name(force_id: String) -> String:
	## Client-side preview only (Confirm still goes through do_rename_force).
	var used := _used_army_display_names(force_id)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return ArmyNames.mint_unique(used, rng) as String


@rpc("any_peer", "call_local", "reliable")
func request_rename_force(force_id: String, new_name: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	var loc: Dictionary = forces[force_id].get("location", {})
	var kind := str(loc.get("kind", ""))
	if kind != "cell" and kind != "aboard":
		return
	if get_force_controller(force_id) != player_id:
		return
	var cleaned: String = ArmyNames.sanitize(new_name)
	if cleaned == "":
		return
	var used := _used_army_display_names(force_id)
	var final_name: String = ArmyNames.uniquify_with_suffix(cleaned, used)
	apply_rename_force.rpc(force_id, final_name)


@rpc("authority", "call_local", "reliable")
func apply_rename_force(force_id: String, new_name: String) -> void:
	if not forces.has(force_id):
		return
	forces[force_id]["display_name"] = new_name
	var fig = armies.get_node_or_null(force_id)
	if fig != null and fig.has_method("refresh_name_label"):
		fig.refresh_name_label()
	refresh_army_labels()
	if gui_node != null and gui_node.has_method("refresh_army_menu_if_force"):
		gui_node.refresh_army_menu_if_force(force_id)


func force_display_name(fid: String) -> String:
	if not forces.has(fid):
		return "Army"
	var loc: Dictionary = forces[fid].get("location", {})
	var kind := str(loc.get("kind", ""))
	if kind == "garrison":
		var b := _building_from_key(str(loc.get("building", "")))
		var bname := _building_display_name(b) if b is Node2D else "Building"
		var spot := int(loc.get("spot", GlobalUnits.SPOT.FLAT))
		var spot_txt := ""
		match spot:
			GlobalUnits.SPOT.INSIDE: spot_txt = " (inside)"
			GlobalUnits.SPOT.OUTSIDE: spot_txt = " (outside)"
		var prov_name := ""
		if b != null and b.get("province") != null and b.province.get("p_name") != null:
			prov_name = str(b.province.p_name)
		if prov_name != "":
			return "%s garrison — %s%s" % [bname, prov_name, spot_txt]
		return "%s garrison%s" % [bname, spot_txt]
	var nick := force_nickname(fid)
	if nick == "":
		nick = "Army"
	if kind == "aboard":
		return "%s (aboard)" % nick
	if is_force_sieging(fid):
		return "%s — siege %d/%d" % [nick, get_force_siege_level(fid), GlobalUnits.SIEGE_MAX_LEVEL]
	return nick


## Projected upkeep for current troops owned by pid (includes all forces with your men).
func get_player_upkeep_preview(pid: int) -> Dictionary:
	var levy_raw := 0.0
	var ss_raw := 0.0
	var ship_raw := 0.0
	var rows: Array = []
	for fid in forces.keys():
		var units: Array = forces[fid]["units"]
		var my_men := GlobalUnits.men_of_owner(units, pid)
		if my_men <= 0:
			continue
		var raw := GlobalUnits.upkeep_raw_for_owner(units, pid)
		levy_raw += float(raw["levy"])
		ss_raw += float(raw["sellsword"])
		var food := get_force_food_info(fid)
		rows.append({
			"force_id": fid,
			"name": force_display_name(fid),
			"levy": int(ceili(float(raw["levy"]))),
			"sellsword": int(ceili(float(raw["sellsword"]))),
			"total": int(ceili(float(raw["total"]))),
			"men": my_men,
			"is_garrison": bool(food.get("is_garrison", false)),
			"grain": int(food.get("grain", 0)),
			"grain_need": int(food.get("need", 0)),
			"food_seasons": int(food.get("seasons_left", -1)),
			"in_dejure": bool(food.get("in_dejure", false)),
			"starving": bool(food.get("starving", false)),
			"food_warning": bool(food.get("warning", false)),
		})
	if fleets != null:
		for f in fleets.get_children():
			if int(f.player_owner) != pid:
				continue
			var ships := int(f.ship_count)
			var cost := ships * GlobalUnits.UPKEEP_TRANSPORT_SHIP
			ship_raw += float(cost)
			rows.append({
				"force_id": "",
				"fleet_id": String(f.name),
				"name": "Fleet %s (%d ships)" % [String(f.name), ships],
				"levy": 0,
				"sellsword": 0,
				"ships": cost,
				"total": cost,
				"men": f.men_aboard() if f.has_method("men_aboard") else 0,
				"is_garrison": false,
				"grain": 0,
				"grain_need": 0,
				"food_seasons": -1,
				"in_dejure": false,
				"starving": false,
				"food_warning": false,
			})
	rows.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return {
		"levy": int(ceili(levy_raw)),
		"sellsword": int(ceili(ss_raw)),
		"ships": int(ceili(ship_raw)),
		"total": int(ceili(levy_raw + ss_raw + ship_raw)),
		"forces": rows,
		"strikes": get_upkeep_strikes(pid),
		"pay_streak": get_upkeep_pay_streak(pid),
	}


func _make_upkeep_event(pid: int, upkeep_kind: String, text: String) -> void:
	var event := {
		"kind": GameEvents.KIND.UPKEEP,
		"upkeep_kind": upkeep_kind,
		"text": text,
		"turn": turn,
		"season": int(season),
		"place_name": "",
		"world_x": 0.0,
		"world_y": 0.0,
		"participant_ids": [pid],
		"actor_id": pid,
	}
	var eid := _register_event(event)
	_deliver_event_to_players(eid, [pid], pid, false)
	if pid == my_pl_id and is_instance_valid(gui_node) and gui_node.has_method("show_info_popup"):
		gui_node.show_info_popup(text)


func _disband_player_sellswords(pid: int) -> int:
	var removed := 0
	var fids: Array = forces.keys()
	for fid in fids:
		if not forces.has(fid):
			continue
		var units: Array = forces[fid]["units"]
		var kept: Array = []
		var changed := false
		for s in units:
			if int(s.get("owner", -1)) == pid and int(s.get("source", GlobalUnits.SOURCE.LEVY)) == GlobalUnits.SOURCE.SELLSWORD:
				removed += int(s.get("count", 0))
				changed = true
			else:
				kept.append(s)
		if changed:
			forces[fid]["units"] = kept
			_cleanup_force_if_empty(fid)
	return removed


func _desert_player_levies(pid: int) -> int:
	var deserted := 0
	var fids: Array = forces.keys()
	for fid in fids:
		if not forces.has(fid):
			continue
		var units: Array = forces[fid]["units"]
		var changed := false
		for s in units:
			if int(s.get("owner", -1)) != pid:
				continue
			var lose := GlobalUnits.desertion_from_stack(s)
			if lose <= 0:
				continue
			s["count"] = int(s["count"]) - lose
			deserted += lose
			changed = true
		if changed:
			var i := units.size() - 1
			while i >= 0:
				if int(units[i]["count"]) <= 0:
					units.remove_at(i)
				i -= 1
			forces[fid]["units"] = units
			_cleanup_force_if_empty(fid)
	return deserted


func tick_army_upkeep() -> void:
	for pid in players.keys():
		var player_id := int(pid)
		if int(players[player_id].status) != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue
		_ensure_upkeep_game_data(player_id)
		var preview := get_player_upkeep_preview(player_id)
		var owed: int = int(preview["total"])
		var marks := int(players[player_id].game_data.get("marks", 0))
		var strikes := int(players[player_id].game_data.get("upkeep_strikes", 0))
		var streak := int(players[player_id].game_data.get("upkeep_pay_streak", 0))

		if owed <= 0 or marks >= owed:
			if owed > 0:
				players[player_id].game_data["marks"] = marks - owed
			if strikes > 0:
				streak += 1
				if streak >= GlobalUnits.UPKEEP_CLEAR_PAYS:
					players[player_id].game_data["upkeep_strikes"] = 0
					players[player_id].game_data["upkeep_pay_streak"] = 0
					_make_upkeep_event(
						player_id,
						"cleared",
						"Army pay restored — all strikes cleared after %d seasons of full pay." % GlobalUnits.UPKEEP_CLEAR_PAYS
					)
				else:
					players[player_id].game_data["upkeep_pay_streak"] = streak
			else:
				players[player_id].game_data["upkeep_pay_streak"] = 0
			continue

		# Miss: pay nothing, reset streak, add a strike (cap at max).
		players[player_id].game_data["upkeep_pay_streak"] = 0
		var prev_strikes := strikes
		if strikes < GlobalUnits.UPKEEP_STRIKES_MAX:
			strikes += 1
		players[player_id].game_data["upkeep_strikes"] = strikes

		var lines: PackedStringArray = []
		lines.append(
			"Could not pay army upkeep (%d marks owed, %d available). Strike %d/%d."
			% [owed, marks, strikes, GlobalUnits.UPKEEP_STRIKES_MAX]
		)

		if strikes >= 2:
			var ss_gone := _disband_player_sellswords(player_id)
			if ss_gone > 0:
				lines.append("%d sellswords disbanded." % ss_gone)
			elif prev_strikes < 2:
				lines.append("Your sellswords will leave if you fail to pay again.")

		if strikes >= 3:
			var lev_gone := _desert_player_levies(player_id)
			if lev_gone > 0:
				lines.append("%d levies deserted (10%% per stack)." % lev_gone)
			else:
				lines.append("Levies desert each unpaid season until pay is restored.")
		elif strikes == 1:
			lines.append("Next unpaid season: sellswords disband. Third: levies desert.")

		var kind := "strike_%d" % strikes
		if strikes >= 3 and prev_strikes >= 3:
			kind = "desertion"
		elif strikes >= 2:
			kind = "sellswords"
		_make_upkeep_event(player_id, kind, "\n".join(lines))


func jump_camera_to_force(fid: String) -> void:
	if not forces.has(fid):
		return
	jump_camera_to(_force_world_pos(fid))


# --- Army food / foraging / attrition ---------------------------------------

const HUNGER_DRIP_SCRIPT := preload("res://objects/overworld/othr/hunger_drip/hunger_drip.gd")


func force_is_garrison(fid: String) -> bool:
	if not forces.has(fid):
		return false
	return str(forces[fid].get("location", {}).get("kind", "")) == "garrison"


func get_force_supply_owner(fid: String) -> int:
	if not forces.has(fid):
		return -1
	if force_is_garrison(fid):
		var loc: Dictionary = forces[fid].get("location", {})
		var b := _building_from_key(str(loc.get("building", "")))
		if b != null and b.get("player_owner") != null:
			return int(b.player_owner)
		return GlobalUnits.primary_owner(forces[fid]["units"])
	var ctrl := get_force_controller(fid)
	if ctrl >= 0:
		return ctrl
	return GlobalUnits.primary_owner(forces[fid]["units"])


func force_in_supply_dejure(fid: String) -> bool:
	var owner_id := get_force_supply_owner(fid)
	if owner_id < 0:
		return false
	var prov = province_under_force(fid)
	if prov == null or not prov.has_method("has_dejure"):
		return false
	return prov.has_dejure(owner_id)


func get_force_food_info(fid: String) -> Dictionary:
	if not forces.has(fid):
		return {
			"grain": 0, "need": 0, "men": 0, "is_garrison": false,
			"in_dejure": true, "seasons_left": -1,
			"shortfall_streak": 0, "warning": false, "starving": false,
		}
	var units: Array = forces[fid]["units"]
	var men := GlobalUnits.total_men(units)
	var is_g := force_is_garrison(fid)
	var need := GlobalUnits.force_grain_need(men, is_g)
	var grain := int(get_force_cargo(fid).get("grain", 0))
	var in_dejure := force_in_supply_dejure(fid)
	var streak := int(forces[fid].get("food_shortfall_streak", 0))
	var seasons_left := -1
	if not in_dejure and need > 0:
		seasons_left = int(grain / need)
	return {
		"grain": grain,
		"need": need,
		"men": men,
		"is_garrison": is_g,
		"in_dejure": in_dejure,
		"seasons_left": seasons_left,
		"shortfall_streak": streak,
		"warning": streak == 1,
		"starving": streak >= 2,
	}


func force_uses_province_granary(fid: String) -> bool:
	if not force_in_supply_dejure(fid):
		return false
	var prov = province_under_force(fid)
	var ctrl := get_force_controller(fid)
	return (
		prov != null
		and prov.has_method("player_has_holding")
		and prov.player_has_holding(ctrl)
	)


func force_food_status_text(fid: String) -> String:
	var info := get_force_food_info(fid)
	if int(info["men"]) <= 0:
		return "Food: —"
	if bool(info["in_dejure"]) and not force_uses_province_granary(fid):
		return "Food: supplied (de jure) · grain held %d" % int(info["grain"])
	if force_uses_province_granary(fid):
		return "Food: provincial granary · need %d/season · cargo %d" % [
			int(info["need"]), int(info["grain"])
		]
	var seasons := int(info["seasons_left"])
	var status := "ok"
	if bool(info["starving"]):
		status = "STARVING"
	elif bool(info["warning"]):
		status = "warning"
	elif seasons <= 0 and int(info["need"]) > 0:
		status = "no reserves"
	return "Food: %d grain · need %d/season · %s season(s) left [%s]" % [
		int(info["grain"]), int(info["need"]),
		str(seasons) if seasons >= 0 else "—",
		status,
	]


func clear_force_hunger_if_relieved(fid: String) -> void:
	if not forces.has(fid):
		return
	var info := get_force_food_info(fid)
	var relieved := bool(info["in_dejure"]) or int(info["men"]) <= 0
	if not relieved and int(info["need"]) > 0:
		relieved = int(info["grain"]) >= int(info["need"])
	if not relieved:
		return
	if int(forces[fid].get("food_shortfall_streak", 0)) != 0:
		forces[fid]["food_shortfall_streak"] = 0
	_sync_force_hunger_fx(fid)


func _make_food_event(recipient_ids: Array, food_kind: String, text: String, world_pos: Vector2) -> void:
	if recipient_ids.is_empty():
		return
	var event := {
		"kind": GameEvents.KIND.FOOD,
		"food_kind": food_kind,
		"text": text,
		"turn": turn,
		"season": int(season),
		"place_name": "",
		"world_x": world_pos.x,
		"world_y": world_pos.y,
		"participant_ids": recipient_ids.duplicate(),
		"actor_id": -1,
	}
	var eid := _register_event(event)
	# actor_id -1 so every recipient gets an unread inbox mark (no popup).
	_deliver_event_to_players(eid, recipient_ids, -1, false)


func _attrition_force_stacks(fid: String) -> int:
	if not forces.has(fid):
		return 0
	var units: Array = forces[fid]["units"]
	var lost := 0
	for s in units:
		var lose := GlobalUnits.starvation_from_stack(s)
		if lose <= 0:
			continue
		s["count"] = int(s["count"]) - lose
		lost += lose
	var i := units.size() - 1
	while i >= 0:
		if int(units[i]["count"]) <= 0:
			units.remove_at(i)
		i -= 1
	forces[fid]["units"] = units
	_cleanup_force_if_empty(fid)
	return lost


func _hunger_fx_host_for_force(fid: String) -> Node2D:
	if not forces.has(fid):
		return null
	if force_is_garrison(fid):
		var loc: Dictionary = forces[fid].get("location", {})
		var b := _building_from_key(str(loc.get("building", "")))
		return b as Node2D
	if force_is_aboard(fid):
		return get_fleet_by_id(get_force_fleet_id(fid))
	return armies.get_node_or_null(fid) as Node2D


func _building_any_force_starving(building: Node) -> bool:
	for fid in _building_garrison_force_ids(building):
		if not forces.has(fid):
			continue
		if int(forces[fid].get("food_shortfall_streak", 0)) >= 2:
			return true
	return false


func _set_hunger_drip_on(host: Node2D, on: bool) -> void:
	if host == null:
		return
	var existing = host.get_node_or_null("HungerDrip")
	if on:
		if existing != null:
			return
		var drip := Node2D.new()
		drip.name = "HungerDrip"
		drip.set_script(HUNGER_DRIP_SCRIPT)
		host.add_child(drip)
		drip.position = Vector2(32, 20)
	elif existing != null:
		host.remove_child(existing)
		existing.queue_free()


func _sync_force_hunger_fx(fid: String) -> void:
	if not forces.has(fid):
		return
	if force_is_garrison(fid):
		var loc: Dictionary = forces[fid].get("location", {})
		var b := _building_from_key(str(loc.get("building", "")))
		if b is Node2D:
			_set_hunger_drip_on(b as Node2D, _building_any_force_starving(b))
		return
	if force_is_aboard(fid):
		var fleet := get_fleet_by_id(get_force_fleet_id(fid))
		if fleet != null:
			_set_hunger_drip_on(fleet, _fleet_any_force_starving(fleet))
		return
	var starving := int(forces[fid].get("food_shortfall_streak", 0)) >= 2
	var fig := armies.get_node_or_null(fid) as Node2D
	_set_hunger_drip_on(fig, starving)


func _fleet_any_force_starving(fleet: Node2D) -> bool:
	if fleet == null:
		return false
	for afid in fleet.aboard_force_ids:
		if not forces.has(afid):
			continue
		if int(forces[afid].get("food_shortfall_streak", 0)) >= 2:
			return true
	return false


func tick_army_food() -> void:
	var fids: Array = forces.keys()
	for fid in fids:
		if not forces.has(fid):
			continue
		var units: Array = forces[fid]["units"]
		var men := GlobalUnits.total_men(units)
		if men <= 0:
			forces[fid]["food_shortfall_streak"] = 0
			_sync_force_hunger_fx(fid)
			continue
		# Already fed from the provincial granary this season.
		if bool(forces[fid].get("province_fed", false)):
			forces[fid]["food_shortfall_streak"] = 0
			_sync_force_hunger_fx(fid)
			continue
		# De jure supply is free only when the controller has no holding granary here
		# (otherwise armies eat from stock before civilians — see tick_holding_rations).
		if force_in_supply_dejure(fid):
			var home_prov = province_under_force(fid)
			var ctrl := get_force_controller(fid)
			var has_granary = (
				home_prov != null
				and home_prov.has_method("player_has_holding")
				and home_prov.player_has_holding(ctrl)
			)
			if not has_granary:
				forces[fid]["food_shortfall_streak"] = 0
				_sync_force_hunger_fx(fid)
				continue

		var is_g := force_is_garrison(fid)
		var bkey := ""
		if is_g:
			bkey = str(forces[fid].get("location", {}).get("building", ""))
		var need := GlobalUnits.force_grain_need(men, is_g)
		var cargo := get_force_cargo(fid)
		var have := int(cargo.get("grain", 0))
		var wpos := _force_world_pos(fid)
		var owners := _owners_array(units)
		var prev_streak := int(forces[fid].get("food_shortfall_streak", 0))

		if need <= 0 or have >= need:
			if need > 0:
				cargo["grain"] = have - need
				set_force_cargo(fid, cargo, false)
			forces[fid]["food_shortfall_streak"] = 0
			_sync_force_hunger_fx(fid)
			continue

		# Shortfall: eat all remaining grain, still count as unpaid.
		if have > 0:
			cargo["grain"] = 0
			set_force_cargo(fid, cargo, false)
		var streak := prev_streak + 1
		forces[fid]["food_shortfall_streak"] = streak

		if streak == 1:
			_make_food_event(
				owners,
				"warning",
				"One of your armies is out of food. Next season your men will begin starving.",
				wpos
			)
		elif streak >= 2:
			var lost := _attrition_force_stacks(fid)
			if prev_streak < 2:
				_make_food_event(
					owners,
					"starving",
					"One of your armies is starving! %d men died this season." % lost,
					wpos
				)

		if forces.has(fid):
			_sync_force_hunger_fx(fid)
		elif is_g and bkey != "":
			var b := _building_from_key(bkey)
			if b is Node2D:
				_set_hunger_drip_on(b as Node2D, _building_any_force_starving(b))


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


## Core crop change for one field (no menu refresh). Returns owning province or null.
func _apply_field_crop_change(field: Node, crop: int) -> Node:
	if field == null or not field.has_method("set_crop"):
		return null
	var prov := find_province_for_building(field)
	var pid = field.get_controller_id() if field.has_method("get_controller_id") else -1
	var was_sown := bool(field.get("planted")) and int(field.get("crop")) == 1
	var staying_grain := was_sown and crop == 1

	# Leaving a field that already had seed spent: refund in winter; else drop potential.
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
	# Winter plans grain; seed + sow labor spent when leaving winter (tick_agriculture).
	return prov


@rpc("authority", "call_local", "reliable")
func apply_set_field_crop(field_key: String, crop: int) -> void:
	var field = _building_from_key(field_key)
	var prov := _apply_field_crop_change(field, crop)
	if field == null:
		return

	if prov != null and prov.has_method("_update_grain_will"):
		prov._update_grain_will()
	if prov != null and prov.has_method("refresh_field_visuals"):
		prov.refresh_field_visuals(int(season))

	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_field_popup_if"):
			gui_node.refresh_field_popup_if(self, field)
		update_menus()


func do_populate_idle_fields(province_id: String, crop: int) -> void:
	request_populate_idle_fields.rpc_id(1, province_id, crop, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_populate_idle_fields(province_id: String, crop: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("get_fields_for_player"):
		return
	if not prov.player_has_holding(player_id):
		return
	# Grain or horses only — not idle.
	crop = clampi(crop, 1, 2)
	apply_populate_idle_fields.rpc(province_id, crop, player_id)


@rpc("authority", "call_local", "reliable")
func apply_populate_idle_fields(province_id: String, crop: int, player_id: int) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("get_fields_for_player"):
		return
	crop = clampi(crop, 1, 2)
	var touched := false
	for f in prov.get_fields_for_player(player_id):
		if int(f.get("crop")) != 0: # CROP.EMPTY / idle
			continue
		_apply_field_crop_change(f, crop)
		touched = true
	if not touched:
		return
	if prov.has_method("_update_grain_will"):
		prov._update_grain_will()
	if prov.has_method("refresh_field_visuals"):
		prov.refresh_field_visuals(int(season))
	if is_instance_valid(gui_node):
		update_menus()


func do_set_holding_tax(province_id: String, level: int) -> void:
	request_set_holding_tax.rpc_id(1, province_id, level, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_set_holding_tax(province_id: String, level: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("set_holding_tax"):
		return
	if not prov.player_has_holding(player_id):
		return
	apply_set_holding_tax.rpc(province_id, GlobalUnits.clamp_tax(level), player_id)


@rpc("authority", "call_local", "reliable")
func apply_set_holding_tax(province_id: String, level: int, player_id: int) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("set_holding_tax"):
		return
	prov.set_holding_tax(player_id, level)
	if prov.has_method("recalculate_marks_will_by_player"):
		prov.recalculate_marks_will_by_player()
	if prov.has_method("recalculate_settlements_growth"):
		prov.recalculate_settlements_growth()
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


func can_collect_settlement_tax(force_id: String, building: Node) -> bool:
	if not forces.has(force_id) or building == null:
		return false
	if force_is_garrison(force_id) or force_is_aboard(force_id):
		return false
	var type_ = building.get("type_")
	if type_ != GlobalStuff.BUILDING_TYPE.TOWN and type_ != GlobalStuff.BUILDING_TYPE.VILLAGE:
		return false
	if is_building_razed(building):
		return false
	var ctrl := get_force_controller(force_id)
	if building.get("player_owner") == null or int(building.player_owner) != ctrl:
		return false
	if settlement_tax_marks(building) <= 0:
		return false
	return force_has_movement(force_id, GlobalUnits.TAX_COLLECT_MP)


func do_collect_settlement_tax(force_id: String, building: Node) -> void:
	if building == null:
		return
	request_collect_settlement_tax.rpc_id(1, force_id, _building_key(building), my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_collect_settlement_tax(force_id: String, building_key: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not forces.has(force_id):
		return
	if get_force_controller(force_id) != player_id:
		return
	var building = _building_from_key(building_key)
	if building == null or not can_collect_settlement_tax(force_id, building):
		return
	var amount := settlement_tax_marks(building)
	if amount <= 0:
		return
	apply_collect_settlement_tax.rpc(force_id, building_key, player_id, amount)


@rpc("authority", "call_local", "reliable")
func apply_collect_settlement_tax(
	force_id: String, building_key: String, player_id: int, amount: int
) -> void:
	var building = _building_from_key(building_key)
	if building == null or not forces.has(force_id):
		return
	if get_force_controller(force_id) != player_id:
		return
	if building.get("player_owner") == null or int(building.player_owner) != player_id:
		return
	var have := settlement_tax_marks(building)
	var take := mini(have, maxi(0, amount))
	if take <= 0:
		return
	if not spend_force_movement(force_id, GlobalUnits.TAX_COLLECT_MP):
		return
	building.tax_marks = have - take
	if players.has(player_id):
		players[player_id].game_data["marks"] = int(players[player_id].game_data.get("marks", 0)) + take
	if is_instance_valid(gui_node):
		gui_node.show_info_popup("Collected %d marks in tax" % take)
		if players.has(my_pl_id):
			gui_node.update_money(players[my_pl_id].game_data["marks"])
		if gui_node.has_method("refresh_army_menu_if_force"):
			gui_node.refresh_army_menu_if_force(force_id)
		if gui_node.has_method("update_economy_menu"):
			gui_node.update_economy_menu(self)


func do_set_holding_ration(province_id: String, level: int) -> void:
	request_set_holding_ration.rpc_id(1, province_id, level, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_set_holding_ration(province_id: String, level: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("set_holding_ration"):
		return
	if not prov.player_has_holding(player_id):
		return
	apply_set_holding_ration.rpc(province_id, GlobalUnits.clamp_ration(level), player_id)


@rpc("authority", "call_local", "reliable")
func apply_set_holding_ration(province_id: String, level: int, player_id: int) -> void:
	var prov := _get_province_by_id(province_id)
	if prov == null or not prov.has_method("set_holding_ration"):
		return
	prov.set_holding_ration(player_id, level)
	if prov.has_method("recalculate_settlements_growth"):
		prov.recalculate_settlements_growth()
	if is_instance_valid(gui_node) and gui_node.has_method("update_economy_menu"):
		gui_node.update_economy_menu(self)


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


func do_upgrade_economy(building: Node) -> void:
	if building == null:
		return
	request_upgrade_economy.rpc_id(1, _building_key(building), my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_upgrade_economy(building_key: String, player_id: int) -> void:
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
	if int(building.get("player_owner")) != player_id:
		return
	if not building.has_method("can_upgrade") or not building.can_upgrade():
		return
	var cost := int(building.upgrade_cost())
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < cost:
		return
	apply_upgrade_economy.rpc(building_key, player_id, cost)


@rpc("authority", "call_local", "reliable")
func apply_upgrade_economy(building_key: String, player_id: int, cost: int) -> void:
	var building = _building_from_key(building_key)
	if building == null or not building.has_method("apply_upgrade"):
		return
	if not players.has(player_id):
		return
	var marks := int(players[player_id].game_data.get("marks", 0))
	if marks < cost:
		return
	players[player_id].game_data["marks"] = marks - cost
	building.apply_upgrade()
	var prov := find_province_for_building(building)
	if prov != null and prov.has_method("_update_material_will"):
		prov._update_material_will()
	if player_id == my_pl_id and is_instance_valid(gui_node):
		gui_node.update_money(players[my_pl_id].game_data["marks"])
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_economy_building_popup_if"):
			gui_node.refresh_economy_building_popup_if(self, building)
		if gui_node.has_method("update_economy_menu"):
			gui_node.update_economy_menu(self)
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


# --- Castle construction ----------------------------------------------------

func do_retarget_castle(building: Node, target_level: int) -> void:
	if building == null:
		return
	request_retarget_castle.rpc_id(1, _building_key(building), target_level, my_pl_id)


@rpc("any_peer", "call_local", "reliable")
func request_retarget_castle(building_key: String, target_level: int, player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(player_id):
		return
	var building = _building_from_key(building_key)
	if building == null or building.get("type_") == null:
		return
	if int(building.type_) != GlobalStuff.BUILDING_TYPE.CASTLE:
		return
	if not building.has_method("preview_retarget"):
		return
	var prov := find_province_for_building(building)
	if prov == null or not prov.has_dejure(player_id):
		return
	var preview: Dictionary = building.preview_retarget(target_level)
	if preview.is_empty():
		return
	var pay: Dictionary = preview.get("pay", {})
	for key in ["wood", "stone"]:
		var need := int(pay.get(key, 0))
		if need > 0 and prov.get_player_material(player_id, key) < need:
			return
	apply_retarget_castle.rpc(building_key, target_level, player_id)


@rpc("authority", "call_local", "reliable")
func apply_retarget_castle(building_key: String, target_level: int, player_id: int) -> void:
	var building = _building_from_key(building_key)
	if building == null or not building.has_method("preview_retarget"):
		return
	var prov := find_province_for_building(building)
	if prov == null:
		return
	var preview: Dictionary = building.preview_retarget(target_level)
	if preview.is_empty():
		return
	var pay: Dictionary = preview.get("pay", {})
	for key in ["wood", "stone"]:
		var need := int(pay.get(key, 0))
		if need > 0:
			if prov.get_player_material(player_id, key) < need:
				return
	for key in ["wood", "stone"]:
		var need := int(pay.get(key, 0))
		if need > 0:
			prov.add_player_material(player_id, key, -need)
	var expel := bool(preview.get("expel", false))
	if expel:
		_expel_all_castle_garrison(building, player_id)
	building.apply_retarget_state(target_level, preview)
	if bool(preview.get("complete_immediately", false)):
		var refund: Dictionary = building.take_completion_refund()
		for key in ["wood", "stone"]:
			var amt := int(refund.get(key, 0))
			if amt > 0:
				prov.add_player_material(player_id, key, amt)
	for pid in prov.get_holding_controllers():
		prov.clamp_all_labor(pid, int(season))
	if prov.has_method("_update_material_will"):
		prov._update_material_will()
	building.player_owner = player_id
	if building.has_method("set_flags"):
		building.set_flags()
	if is_instance_valid(gui_node):
		if gui_node.has_method("refresh_castle_popup_if"):
			gui_node.refresh_castle_popup_if(self, building)
		update_menus()


## Dump every garrison stack onto the nearest free map tiles (BFS from approach).
func _expel_all_castle_garrison(building: Node, fallback_controller: int) -> void:
	if building == null:
		return
	var all_units: Array = get_all_building_garrison(building)
	if GlobalUnits.total_men(all_units) <= 0:
		return
	var cell := get_nearest_free_cell_for_building(building)
	if cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		return
	var building_key := _building_key(building)
	var vip_ids: Array = []
	var merged_cargo := GlobalUnits.empty_caravan_cargo()
	for fid in _building_garrison_force_ids(building):
		for vid in get_vips_on_force(fid):
			vip_ids.append(vid)
		merged_cargo = GlobalUnits.add_caravan_stocks(merged_cargo, get_force_cargo(str(fid)))
	for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
		var gid := _garrison_force_id(building_key, spot)
		if forces.has(gid):
			forces.erase(gid)
	_next_runtime_force += 1
	var new_id := "rt_%d" % _next_runtime_force
	var controller := GlobalUnits.primary_owner(all_units)
	if controller < 0:
		controller = fallback_controller
	_spawn_army_figure(new_id, all_units, cell, 0, controller)
	set_force_cargo(new_id, merged_cargo)
	move_vips_to_force(vip_ids, new_id)
	pathfinding.rebuild_occupancy()
	refresh_building_flags(building_key)
	update_all_army_visuals()
	refresh_all_vip_crowns()


## Nearest walkable unoccupied cell, searching outward from approach cells.
func get_nearest_free_cell_for_building(b: Node) -> Vector2i:
	var approach_cells = pathfinding.get_approach_cells(b)
	var queue: Array[Vector2i] = []
	var seen := {}
	for c in approach_cells:
		queue.append(c)
		seen[c] = true
	var i := 0
	while i < queue.size():
		var cell: Vector2i = queue[i]
		i += 1
		if pathfinding.walkable_cells.has(cell) and not pathfinding.occupancy.has(cell):
			return cell
		for dir in pathfinding.EDGE_DIRS:
			var n: Vector2i = cell + dir
			if seen.has(n):
				continue
			if not pathfinding.walkable_cells.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


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


## Standings for UI + AI. Ranks only for display; entries also carry raw totals.
func get_player_ladder() -> Dictionary:
	return PlayerLadder.compute(self)


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


func get_admin_province_report(province_id: String) -> String:
	var prov = _get_province_by_id(province_id)
	if prov == null:
		return "Province not found: %s" % province_id
	if prov.has_method("get_admin_report"):
		return prov.get_admin_report(players)
	return "No admin report for %s" % province_id


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
