extends Node2D

enum SEASONS { WINTER, SPRING, SUMMER, AUTUMN }

var season = SEASONS.WINTER
var turn = 0

var my_pl_id = 0

var players = {}

# Authoritative force registry (rosters). Keyed by force_id:
#   { "units": Array[stack], "location": Dictionary, "controller": int }
# location = {"kind": "cell"}  -> a mobile army; the figure node holds its position
#          | {"kind": "garrison", "building": <path String>, "spot": SPOT}
# controller (mobile armies only): player who commands the army on the map.
# Built deterministically from the scene on every peer, then mutated only via
# the server-authoritative apply_* RPCs below so it stays in sync.
var forces := {}
var _next_runtime_force := 0
# Set when a move click is processed; blocks army Area2D from opening the menu
# on the same frame after the army teleports under the cursor.
var _suppress_army_click_frame := -1

const ARMY_FIGURE_SCENE := preload("res://objects/overworld/army/army_map_unit/armiy_figure.tscn")

@onready var provinces = $provinces
@onready var armies = $armies
@onready var camera: Camera2D = $Camera2D
@onready var pathfinding = $pathfinding
@onready var province_labels = $ProvinceLabels
@onready var province_borders = $ProvinceBorders

@onready var gui_node = $BasebottomGUI

# Building info popup: hover this long (seconds) before the transient popup shows.
const BUILDING_HOVER_DELAY := 2.0
var _hover_candidate: Node2D = null
var _hover_elapsed := 0.0

func dummy_player_data():
	players[0] = GlobalStuff.PlayerData.new(0, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 0, "Richard", {"marks": 100, "people": 0})
	players[1] = GlobalStuff.PlayerData.new(1, GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL, 1, 1, "William", {"marks": 2300, "people": 0})
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
		child.set_flags()
		child.setup_map_label()
	
	for child in armies.get_children():
		child.base_map = self
		child.set_flags()
	# pathfinding
	pathfinding.initialize()
	build_forces_registry()
	province_borders.rebuild()


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


func get_all_building_garrison(b: Node) -> Array:
	var result: Array = []
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			result = GlobalUnits.merge_units(result, get_building_garrison(b, spot))
	else:
		result = GlobalUnits.merge_units(result, get_building_garrison(b, GlobalUnits.SPOT.FLAT))
	return result


# Frees the figure (if any) and drops the entry when a force is emptied.
func _cleanup_force_if_empty(fid: String) -> void:
	if not forces.has(fid):
		return
	if GlobalUnits.total_men(forces[fid]["units"]) > 0:
		return
	forces.erase(fid)
	var fig = armies.get_node_or_null(fid)
	if fig != null:
		armies.remove_child(fig)
		fig.queue_free()


func suppress_army_click_this_frame() -> void:
	_suppress_army_click_frame = Engine.get_process_frames()


func should_suppress_army_click() -> bool:
	return _suppress_army_click_frame == Engine.get_process_frames()


func on_army_clicked(army: Node2D) -> void:
	var selected = pathfinding.selected_army if pathfinding != null else null
	# This army is in movement mode — clicks go to pathfinding, not the menu.
	if selected == army:
		return
	# A different army is selected: interaction (merge/split or battle).
	if selected != null and selected != army:
		_on_army_interaction(selected, army)
		return
	if army.is_controllable_by(my_pl_id):
		gui_node.open_army_menu(self, army)
	elif army.has_units_of(my_pl_id):
		gui_node.open_withdraw_menu(self, army)
	else:
		show_army_owner_popup(army)


func _on_army_interaction(mover: Node2D, target: Node2D) -> void:
	var shared := false
	for o in target.get_owner_set():
		if mover.get_owner_set().has(o):
			shared = true
			break
	if shared:
		pathfinding.deselect_army()
		gui_node.open_force_menu(self, mover.force_id, target.force_id)
	else:
		# Enemy encounter -> battle resolution comes in part two.
		gui_node.show_info_popup("Enemy army — battle comes in part two")


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
	if _is_army_selected():
		# Clicking a garrisonable building with an army selected either opens
		# the garrison transfer menu (when already adjacent) or moves the army
		# toward the building first (when too far away).
		if building.has_method("get_garrison_capacity"):
			var army = pathfinding.selected_army
			var army_cell = pathfinding.get_army_cell(army)
			var approach_cells = pathfinding.get_approach_cells(building)
			# If the army is not yet adjacent, fall through to normal pathfinding
			# which will move the army as close as possible.
			if army_cell not in approach_cells:
				return false
			# Army is adjacent – check it has MP to spend.
			if army.movement_left <= 0:
				gui_node.show_info_popup("No movement points left")
				pathfinding.deselect_army()
				return true
			_hover_candidate = null
			gui_node.hide_building_popup()
			pathfinding.deselect_army()
			gui_node.open_garrison_menu(self, army.force_id, building)
			return true
		return false
	_hover_candidate = null
	var has_own_garrison := (building.has_method("get_garrison_capacity")
		and not get_player_garrison(building, my_pl_id).is_empty())
	var is_building_owner = building.get("player_owner") != null and building.player_owner == my_pl_id
	var has_any_garrison = (building.has_method("get_garrison_capacity")
		and GlobalUnits.total_men(get_all_building_garrison(building)) > 0)
	var deploy_cb := Callable()
	var deploy_all_cb := Callable()
	if has_own_garrison:
		deploy_cb = func(): gui_node.open_deploy_menu(self, building, my_pl_id)
	if is_building_owner and has_any_garrison:
		deploy_all_cb = func(): gui_node.open_deploy_all_confirm(self, building)
	gui_node.show_building_popup(building, _building_display_name(building), _building_display_body(building), true, deploy_cb, deploy_all_cb)
	return true


func _building_display_name(b: Node2D) -> String:
	if b.get("type_") != null:
		match b.type_:
			GlobalStuff.BUILDING_TYPE.VILLAGE: return "Village"
			GlobalStuff.BUILDING_TYPE.TOWN: return "Town"
			GlobalStuff.BUILDING_TYPE.CASTLE: return "Castle"
			GlobalStuff.BUILDING_TYPE.FIELD: return "Field"
			GlobalStuff.BUILDING_TYPE.ECONOMY:
				if b.has_method("get_subtype_name"):
					return b.get_subtype_name()
				return "Economy Building"
	return "Building"


func _building_display_body(b: Node2D) -> String:
	var lines := PackedStringArray()
	if b.get("type_") != null and b.type_ == GlobalStuff.BUILDING_TYPE.FIELD:
		var owner_name := "Unowned"
		var owner_building = b.get("owner_building")
		if owner_building != null and owner_building.get("player_owner") != null:
			if players.has(owner_building.player_owner):
				owner_name = str(players[owner_building.player_owner].name_)
		lines.append("Owner: %s" % owner_name)
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
	apply_army_move.rpc(army_name, cell_x, cell_y, steps)


@rpc("authority", "call_local", "reliable")
func apply_army_move(army_name: String, cell_x: int, cell_y: int, steps: int) -> void:
	var army = armies.get_node_or_null(army_name)
	if army == null:
		return
	pathfinding.place_army_at_cell(army, Vector2i(cell_x, cell_y))
	army.movement_left -= steps
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


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
	_cleanup_force_if_empty(garrison_id)
	pathfinding.rebuild_occupancy()
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
	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


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

	apply_disband_force.rpc(force_id, foreign_spawns, settlement_additions)


@rpc("authority", "call_local", "reliable")
func apply_disband_force(force_id: String, foreign_spawns: Array, settlement_additions: Array) -> void:
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

	pathfinding.rebuild_occupancy()
	update_all_army_visuals()


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
	fig.movement_left = starting_mp


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
	return result


@rpc("any_peer", "call_local", "reliable")
func player_ended_turn(player_id):
	if !multiplayer.is_server():
		return
	players[player_id].ended_turn = true
	
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
	#calculate and then display the new data
	add_resources()
	update_visuals_and_stats()
	province_borders.rebuild()
	
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


func _provinces_for_player(player_id: int) -> Array:
	var owned := []
	var other_interest := []
	for prov in provinces.get_children():
		if prov.player_owner == player_id:
			owned.append(prov)
		elif prov.defacto == player_id or prov.dejure == player_id:
			other_interest.append(prov)
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
	var other := []
	for prov in provinces.get_children():
		var entry = {
			"id": prov.name,
			"name": prov.p_name,
			"population": prov.resources["population"]["has"]["all"],
			"predicted_income": prov.resources["marks"]["will"]["all"],
			"owned": prov.player_owner == player_id
		}
		if prov.player_owner == player_id:
			owned.append(entry)
		elif prov.defacto == player_id or prov.dejure == player_id:
			other.append(entry)
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
	return prov.get_display_data(players)


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
			return
