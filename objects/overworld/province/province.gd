extends Node2D

enum PROVINCE_STATUS { STABLE, DISPUTED, OCCUPIED, CONQUERED }

const NO_DEFACTO := -1

var resources

@export var p_name = "Gondor"
@export var player_owner = 1
@export var home_province = false
var dejure
var defacto

var status_ = PROVINCE_STATUS.STABLE

# Levy / happiness (0–100). Snapshot resets each season with levied_this_season.
var happiness: float = 100.0
var season_start_population: int = 0
var levied_this_season: int = 0

@onready var settlements = $settlements
@onready var fields = $fields
@onready var economy = $economy
@onready var defense = $defense
@onready var map_labels = $map_labels
@onready var _name_label: Label = $map_labels/name_label
@onready var _status_label: Label = $map_labels/status_label
@onready var _owner_label: Label = $map_labels/owner_label

# Reference to the overworld map (OBaseMap); set from parent hierarchy if not set.
@onready var base_map

const MAP_LABEL_LINE_HEIGHT := 18.0

var _label_center := Vector2.ZERO

func _ready() -> void:
	create_de_resorce_dict()
	dejure = player_owner
	defacto = player_owner
	status_ = PROVINCE_STATUS.STABLE
	allocate_fields_to_settlements()


func set_flags():
	for container in [settlements, economy, defense]:
		for child in container.get_children():
			if child.has_method("setup_building"):
				child.setup_building()


## Seat = castle if present and not destroyed, otherwise town.
func get_seat_building() -> Node:
	var castle := _find_building_of_type(defense, GlobalStuff.BUILDING_TYPE.CASTLE)
	if castle != null and not _is_seat_destroyed(castle):
		return castle
	return _find_building_of_type(settlements, GlobalStuff.BUILDING_TYPE.TOWN)


func _find_building_of_type(container: Node, btype: int) -> Node:
	if container == null:
		return null
	for child in container.get_children():
		if child.get("type_") != null and child.type_ == btype:
			return child
	return null


func _is_seat_destroyed(building: Node) -> bool:
	# Only the castle seat can be "destroyed" (future mechanic). Razed towns stay the seat.
	if building == null:
		return true
	return bool(building.get_meta("seat_destroyed", false))


func get_non_seat_buildings() -> Array:
	var seat := get_seat_building()
	var out: Array = []
	for container in [settlements, economy, defense]:
		if container == null:
			continue
		for child in container.get_children():
			if child == seat:
				continue
			if child.get("player_owner") == null:
				continue
			out.append(child)
	return out


## Derive dejure / defacto / player_owner / status_ from building ownership.
## Does not overwrite per-building player_owner.
func recompute_control() -> void:
	var seat := get_seat_building()
	if seat != null and seat.get("player_owner") != null:
		dejure = int(seat.player_owner)
	player_owner = dejure

	var non_seat := get_non_seat_buildings()
	if non_seat.is_empty():
		defacto = dejure
	else:
		var owner_id: int = int(non_seat[0].player_owner)
		var all_same := true
		for b in non_seat:
			if int(b.player_owner) != owner_id:
				all_same = false
				break
		defacto = owner_id if all_same else NO_DEFACTO

	status_ = compute_status()
	refresh_map_label()
	if base_map != null and base_map.has_method("try_restore_razed_in_province"):
		base_map.try_restore_razed_in_province(self)


## Juridical-frame status. Conquered is viewer-only (see get_status_name_for_viewer).
func compute_status() -> PROVINCE_STATUS:
	if defacto != NO_DEFACTO and int(defacto) != int(dejure):
		return PROVINCE_STATUS.OCCUPIED
	var not_yours := 0
	for b in get_non_seat_buildings():
		if int(b.player_owner) != int(dejure):
			not_yours += 1
	if not_yours > 1:
		return PROVINCE_STATUS.DISPUTED
	return PROVINCE_STATUS.STABLE


func get_status() -> PROVINCE_STATUS:
	return compute_status()


func has_dejure(player_id: int) -> bool:
	return int(dejure) == player_id


func can_rebuild_building(building: Node) -> bool:
	if building == null or building.get("player_owner") == null:
		return false
	return int(building.player_owner) == int(dejure)


func sync_player_owner_to_children() -> void:
	for container in [settlements, economy, defense]:
		for child in container.get_children():
			if child.get("player_owner") != null:
				child.player_owner = player_owner
			if child.base_map == null and base_map != null:
				child.base_map = base_map


## Manual override for tooling/tests. Does not wipe per-building ownership.
func set_ownership(new_dejure: int, new_defacto: int) -> void:
	dejure = new_dejure
	defacto = new_defacto
	player_owner = new_dejure
	status_ = compute_status()
	refresh_map_label()


func setup_map_label() -> void:
	_label_center = get_geographic_center()
	map_labels.position = _label_center
	refresh_map_label()


func get_geographic_center() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for container in [settlements, fields, economy, defense]:
		for child in container.get_children():
			sum += child.position
			count += 1
	if count > 0:
		return sum / float(count)
	return Vector2.ZERO


func get_label_world_position() -> Vector2:
	return global_position + _label_center


func refresh_map_label() -> void:
	if base_map == null:
		return
	var players_dict: Dictionary = base_map.players if base_map.get("players") else {}
	var viewer_id := NO_DEFACTO
	if base_map.get("my_pl_id") != null:
		viewer_id = int(base_map.my_pl_id)
	var status_text := get_status_name_for_viewer(viewer_id)
	_name_label.text = p_name
	if status_text == "Stable":
		_status_label.visible = false
		_status_label.text = ""
	else:
		_status_label.visible = true
		_status_label.text = status_text
		_status_label.modulate = _get_status_color_for_name(status_text)
	_owner_label.text = _format_owner_line(players_dict)
	_layout_map_labels()


func set_map_label_alpha(alpha: float) -> void:
	var color = map_labels.modulate
	color.a = alpha
	map_labels.modulate = color
	map_labels.visible = alpha > 0.001


func set_map_label_scale(scale_factor: float) -> void:
	map_labels.scale = Vector2.ONE * scale_factor


func _format_owner_line(players_dict: Dictionary) -> String:
	var dejure_name := _player_name(players_dict, dejure)
	if defacto == NO_DEFACTO or defacto == null:
		return dejure_name
	var defacto_name := _player_name(players_dict, defacto)
	if int(dejure) == int(defacto):
		return dejure_name
	return "%s · %s" % [dejure_name, defacto_name]


func _player_name(players_dict: Dictionary, player_id: int) -> String:
	if player_id == null or int(player_id) < 0:
		return "—"
	if players_dict.has(player_id):
		return str(players_dict[player_id].name_)
	return "Unknown"


func _get_status_color() -> Color:
	return _get_status_color_for_name(get_status_name())


func _get_status_color_for_name(status_text: String) -> Color:
	match status_text:
		"Disputed":
			return Color(1.0, 0.85, 0.2)
		"Occupied":
			return Color(1.0, 0.55, 0.2)
		"Conquered":
			return Color(1.0, 0.3, 0.3)
		_:
			return Color.WHITE


func _layout_map_labels() -> void:
	var lines: Array[Label] = [_name_label]
	if _status_label.visible:
		lines.append(_status_label)
	lines.append(_owner_label)
	var total_h := MAP_LABEL_LINE_HEIGHT * lines.size()
	var y := -total_h / 2.0 + MAP_LABEL_LINE_HEIGHT / 2.0
	for lbl in lines:
		lbl.position = Vector2(0.0, y)
		y += MAP_LABEL_LINE_HEIGHT


func create_de_resorce_dict():
	var _resource = {
		"grain": {
			"has": 0,
			"will": 0
		},
		"population": {
			"has": {},  # player_id -> total; "all" -> sum
			"will": {}  # player_id -> predicted total; "all" -> sum
		},
		"wood": {
			"has": 0,
			"will": 0
		},
		"stone": {
			"has": 0,
			"will": 0
		},
		"iron": {
			"has": 0,
			"will": 0
		},
		"people": {
			"has": 0,
			"will": 0
		},
		"marks": {
			"will": {}  # player_id -> amount; "all" -> sum of all players
		},
		"weapons": GlobalUnits.empty_weapon_stock(),
	}
	resources = _resource


func get_weapons() -> Dictionary:
	if resources == null or not resources.has("weapons"):
		if resources == null:
			create_de_resorce_dict()
		else:
			resources["weapons"] = GlobalUnits.empty_weapon_stock()
	return resources["weapons"]


func seed_test_weapons() -> void:
	var w := get_weapons()
	w["maces"] = 40
	w["pikes"] = 30
	w["bows"] = 25
	w["swords"] = 20
	w["crossbows"] = 10
	w["horses"] = 15
	w["armour"] = 15


func snapshot_season_start() -> void:
	update_population_in_resources()
	season_start_population = int(resources["population"]["has"].get("all", 0))
	levied_this_season = 0


func max_levy_remaining() -> int:
	var cap := int(floor(float(season_start_population) * GlobalUnits.LEVY_MAX_FRACTION))
	return maxi(0, cap - levied_this_season)


func owned_settlement_population(player_id: int) -> int:
	var total := 0
	for s in settlements.get_children():
		if s.get("player_owner") == null or s.get("population") == null:
			continue
		if int(s.player_owner) != player_id:
			continue
		total += int(s.population)
	return total


func get_owned_settlements(player_id: int) -> Array:
	var out: Array = []
	for s in settlements.get_children():
		if s.get("player_owner") == null or s.get("population") == null:
			continue
		if int(s.player_owner) != player_id:
			continue
		out.append(s)
	return out


## Prefer a town the player owns; otherwise the seat (castle/town).
func get_recruit_spawn_building(player_id: int) -> Node:
	for s in settlements.get_children():
		if s.get("type_") == null or s.get("player_owner") == null:
			continue
		if int(s.type_) == GlobalStuff.BUILDING_TYPE.TOWN and int(s.player_owner) == player_id:
			return s
	return get_seat_building()


## Apply incremental happiness loss when levied_this_season grows within a season.
func apply_levy_happiness(prev_levied: int, new_levied: int) -> void:
	var old_p := GlobalUnits.levy_happiness_penalty(prev_levied, season_start_population)
	var new_p := GlobalUnits.levy_happiness_penalty(new_levied, season_start_population)
	happiness = clampf(happiness - (new_p - old_p), 0.0, 100.0)


## Remove `amount` people from owned settlements (proportional). Returns false if not enough.
func deduct_population(player_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var owned := get_owned_settlements(player_id)
	var available := 0
	for s in owned:
		available += int(s.population)
	if available < amount:
		return false
	var remaining := amount
	# Largest settlements first so small villages aren't wiped unevenly.
	owned.sort_custom(func(a, b): return int(a.population) > int(b.population))
	for i in range(owned.size()):
		if remaining <= 0:
			break
		var s = owned[i]
		var left_settlements := owned.size() - i
		var share := int(ceil(float(remaining) / float(left_settlements)))
		var take := mini(int(s.population), share)
		s.population -= take
		remaining -= take
	update_population_in_resources()
	return remaining <= 0

func allocate_fields_to_settlements() -> void:
	var field_list: Array = fields.get_children()
	var settlement_list: Array = settlements.get_children()

	if settlement_list.is_empty() or field_list.is_empty():
		return

	var num_fields := field_list.size()
	var num_settlements := settlement_list.size()
	var fields_per_settlement := int(ceil(num_fields / float(num_settlements)))

	for settlement in settlement_list:
		settlement.fields.clear()
	for f in field_list:
		f.owner_building = null

	for settlement in settlement_list:
		var needed := fields_per_settlement
		while needed > 0:
			var best_field = null
			var best_dist := INF
			for f in field_list:
				if f.owner_building != null:
					continue
				var d = settlement.global_position.distance_squared_to(f.global_position)
				if d < best_dist:
					best_dist = d
					best_field = f
			if best_field == null:
				break
			best_field.owner_building = settlement
			settlement.fields.append(best_field)
			needed -= 1


func recalculate_settlements_growth() -> void:
	var settlement_list: Array = settlements.get_children()
	for settlement in settlement_list:
		if settlement.has_method("calculate_predicted_growth"):
			settlement.calculate_predicted_growth()
	update_population_in_resources()


func update_population_in_resources() -> void:
	var settlement_list: Array = settlements.get_children()
	var has_by_player: Dictionary = {}
	var will_by_player: Dictionary = {}
	for s in settlement_list:
		if s.get("player_owner") == null:
			continue
		var pid = s.player_owner
		var pop = s.population if s.get("population") != null else 0
		var pred = s.predicted_growth if s.get("predicted_growth") != null else 0
		has_by_player[pid] = has_by_player.get(pid, 0) + pop
		will_by_player[pid] = will_by_player.get(pid, 0) + pop + pred
	var has_total := 0
	var will_total := 0
	for pid in has_by_player:
		has_total += has_by_player[pid]
		will_total += will_by_player[pid]
	has_by_player["all"] = has_total
	will_by_player["all"] = will_total
	resources["population"]["has"] = has_by_player
	resources["population"]["will"] = will_by_player


func apply_predicted_growth_to_settlements() -> void:
	var settlement_list: Array = settlements.get_children()
	for settlement in settlement_list:
		settlement.population += settlement.predicted_growth
	update_population_in_resources()


func recalculate_marks_will_by_player() -> void:
	var settlement_list: Array = settlements.get_children()
	for s in settlement_list:
		if s.has_method("calculate_predicted_marks"):
			s.calculate_predicted_marks()
	# Only the de jure holder earns marks, and only from settlements they own.
	var will_by_player: Dictionary = {}
	for s in settlement_list:
		if s.get("player_owner") == null or s.get("predicted_marks") == null:
			continue
		if int(s.player_owner) != int(dejure):
			continue
		var pid = int(s.player_owner)
		will_by_player[pid] = will_by_player.get(pid, 0) + s.predicted_marks
	var total := 0
	for pid in will_by_player:
		total += will_by_player[pid]
	will_by_player["all"] = total
	resources["marks"]["will"] = will_by_player


func _count_buildings_in_node(node: Node, control_player_id: int) -> Dictionary:
	var control := 0
	var all_count := 0
	for child in node.get_children():
		all_count += 1
		if child.get("player_owner") != null and child.player_owner == control_player_id:
			control += 1
	return {"control": control, "all": all_count}


func get_building_counts() -> Dictionary:
	# Control ratio vs juridical owner (de jure).
	var ctrl = dejure
	var villages := _count_by_type(settlements, GlobalStuff.BUILDING_TYPE.VILLAGE, ctrl)
	var towns := _count_by_type(settlements, GlobalStuff.BUILDING_TYPE.TOWN, ctrl)
	var castles := _count_buildings_in_node(defense, ctrl)
	var economy_buildings := _count_buildings_in_node(economy, ctrl)
	return {
		"villages": villages,
		"towns": towns,
		"castles": castles,
		"economy": economy_buildings
	}


func _count_by_type(node: Node, btype: int, control_player_id: int) -> Dictionary:
	var control := 0
	var all_count := 0
	for child in node.get_children():
		if child.get("type_") != null and child.type_ == btype:
			if child.get("player_owner") != null:
				all_count += 1
			if child.player_owner == control_player_id:
				control += 1
	return {"control": control, "all": all_count}


func get_status_name() -> String:
	match status_:
		PROVINCE_STATUS.STABLE: return "Stable"
		PROVINCE_STATUS.DISPUTED: return "Disputed"
		PROVINCE_STATUS.OCCUPIED: return "Occupied"
		PROVINCE_STATUS.CONQUERED: return "Conquered"
		_: return "Unknown"


## Conquered is only shown to the de facto holder who lacks de jure.
func get_status_name_for_viewer(viewer_id: int = NO_DEFACTO) -> String:
	if viewer_id >= 0 and defacto != NO_DEFACTO \
			and int(defacto) == viewer_id and int(dejure) != viewer_id:
		return "Conquered"
	return get_status_name()


func get_display_data(players_dict: Dictionary, viewer_id: int = NO_DEFACTO) -> Dictionary:
	var owner_name := _player_name(players_dict, player_owner)
	var defacto_name := _player_name(players_dict, defacto) if defacto != NO_DEFACTO else "—"
	var dejure_name := _player_name(players_dict, dejure)
	var counts = get_building_counts()
	var status_name := get_status_name_for_viewer(viewer_id)
	var viewer_has_dejure := viewer_id >= 0 and has_dejure(viewer_id)
	var marks_all: int = int(resources["marks"]["will"].get("all", 0))
	var marks_for_viewer := marks_all if viewer_has_dejure else 0
	var weapons_copy: Dictionary = get_weapons().duplicate()
	return {
		"name": p_name,
		"status": status_,
		"status_name": status_name,
		"owner_name": owner_name,
		"defacto_name": defacto_name,
		"dejure_name": dejure_name,
		"population_has": resources["population"]["has"].get("all", 0),
		"population_will": resources["population"]["will"].get("all", 0),
		"marks_will": marks_for_viewer,
		"marks_will_province": marks_all,
		"viewer_has_dejure": viewer_has_dejure,
		"villages": counts["villages"],
		"towns": counts["towns"],
		"castles": counts["castles"],
		"economy": counts["economy"],
		"happiness": happiness,
		"season_start_population": season_start_population,
		"levied_this_season": levied_this_season,
		"levy_remaining": max_levy_remaining(),
		"weapons": weapons_copy,
		"owned_population": owned_settlement_population(viewer_id) if viewer_id >= 0 else 0,
	}
