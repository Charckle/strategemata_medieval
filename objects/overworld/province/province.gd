extends Node2D

enum PROVINCE_STATUS { STABLE, DISPUTED, OCCUPIED, CONQUERED }

const NO_DEFACTO := -1

## Labor category → basic_building SUBTYPES int.
const ECON_SUBTYPE_FOR_LABOR := {
	"wood": 0, # WOODCUTTER
	"iron": 1, # IRONMINE
	"silver": 3, # SILVERMINE
	"stone": 4, # STONEQUARRY
	"blacksmith": 5, # BLACKSMITH
}

var resources

@export var p_name = "noname"
@export var player_owner = 1
@export var home_province = false
var dejure
var defacto

var status_ = PROVINCE_STATUS.STABLE

# Levy / happiness (0–100). Snapshot resets each season with levied_this_season.
var happiness: float = 100.0
var season_start_population: int = 0
var levied_this_season: int = 0

# Per-player holding economy: labor slider, running grain potential, horse stock.
# grain also lives in resources["grain"]["has"][pid]; horses here + mirrored in weapons for totals.
var holdings: Dictionary = {}

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


## First town in settlements (provinces are authored with one town).
func get_town() -> Node:
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
			"has": GlobalUnits.empty_per_player_amount(),
			"will": GlobalUnits.empty_per_player_amount(),
		},
		"population": {
			"has": {},  # player_id -> total; "all" -> sum
			"will": {}  # player_id -> predicted total; "all" -> sum
		},
		"wood": {
			"has": GlobalUnits.empty_per_player_amount(),
			"will": GlobalUnits.empty_per_player_amount(),
		},
		"stone": {
			"has": GlobalUnits.empty_per_player_amount(),
			"will": GlobalUnits.empty_per_player_amount(),
		},
		"iron": {
			"has": GlobalUnits.empty_per_player_amount(),
			"will": GlobalUnits.empty_per_player_amount(),
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
	holdings = {}


func get_weapons() -> Dictionary:
	if resources == null or not resources.has("weapons"):
		if resources == null:
			create_de_resorce_dict()
		else:
			resources["weapons"] = GlobalUnits.empty_weapon_stock()
	return resources["weapons"]


## Weapons stock for a player: shared arsenal, but horses are per-holding.
func get_weapons_for(player_id: int) -> Dictionary:
	var w := get_weapons().duplicate()
	w["horses"] = get_player_horses(player_id)
	return w


func ensure_holding(player_id: int) -> Dictionary:
	if player_id < 0:
		return {}
	if not holdings.has(player_id):
		var labor := {}
		for cat in GlobalUnits.LABOR_CATEGORIES:
			labor[cat] = 0
		holdings[player_id] = {
			"labor": labor,
			"labor_assigned": 0, # legacy total; kept in sync
			"grain_potential": 0.0,
			"horses": 0,
			"pending_marks": 0, # silver preview → applied next tick to global treasury
		}
	else:
		var h: Dictionary = holdings[player_id]
		if not h.has("labor") or not (h["labor"] is Dictionary):
			var labor2 := {}
			for cat in GlobalUnits.LABOR_CATEGORIES:
				labor2[cat] = 0
			# Migrate old single slider into grain.
			labor2["grain"] = int(h.get("labor_assigned", 0))
			h["labor"] = labor2
		else:
			var labor_exist: Dictionary = h["labor"]
			for cat in GlobalUnits.LABOR_CATEGORIES:
				if not labor_exist.has(cat):
					labor_exist[cat] = 0
		if not h.has("pending_marks"):
			h["pending_marks"] = 0
	return holdings[player_id]


func get_player_material(player_id: int, key: String) -> int:
	GlobalUnits.ensure_material_has(resources, key)
	return int(resources[key]["has"].get(player_id, 0))


func add_player_material(player_id: int, key: String, amount: int) -> void:
	if player_id < 0 or amount == 0:
		return
	GlobalUnits.ensure_material_has(resources, key)
	var has: Dictionary = resources[key]["has"]
	has[player_id] = maxi(0, int(has.get(player_id, 0)) + amount)
	GlobalUnits.recompute_per_player_all(has)


func get_player_grain(player_id: int) -> int:
	return get_player_material(player_id, "grain")


func add_player_grain(player_id: int, amount: int) -> void:
	add_player_material(player_id, "grain", amount)


func get_player_horses(player_id: int) -> int:
	return int(ensure_holding(player_id).get("horses", 0))


func add_player_horses(player_id: int, amount: int) -> void:
	if player_id < 0 or amount == 0:
		return
	var h := ensure_holding(player_id)
	h["horses"] = maxi(0, int(h.get("horses", 0)) + amount)
	_sync_weapons_horses_total()
	_refresh_horse_field_visuals()


func _sync_weapons_horses_total() -> void:
	var total := 0
	for pid in holdings:
		total += int(holdings[pid].get("horses", 0))
	get_weapons()["horses"] = total


func can_afford_weapons_for(player_id: int, need: Dictionary) -> bool:
	return GlobalUnits.can_afford_weapons(get_weapons_for(player_id), need)


func subtract_weapons_for(player_id: int, need: Dictionary) -> void:
	var horses := int(need.get("horses", 0))
	var rest := need.duplicate()
	rest["horses"] = 0
	GlobalUnits.subtract_weapons(get_weapons(), rest)
	if horses != 0:
		add_player_horses(player_id, -horses)


func add_weapons_for(player_id: int, add: Dictionary) -> void:
	var horses := int(add.get("horses", 0))
	var rest := add.duplicate()
	rest["horses"] = 0
	GlobalUnits.add_weapons(get_weapons(), rest)
	if horses != 0:
		add_player_horses(player_id, horses)


## Caravan cargo affordability for `player_id` (weapons + materials).
func can_afford_caravan_cargo(player_id: int, cargo: Dictionary) -> bool:
	var need_w := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_KEYS:
		need_w[k] = maxi(0, int(cargo.get(k, 0)))
	if not can_afford_weapons_for(player_id, need_w):
		return false
	for k in GlobalUnits.MATERIAL_KEYS:
		if get_player_material(player_id, k) < maxi(0, int(cargo.get(k, 0))):
			return false
	return true


func subtract_caravan_cargo(player_id: int, cargo: Dictionary) -> void:
	var need_w := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_KEYS:
		need_w[k] = maxi(0, int(cargo.get(k, 0)))
	subtract_weapons_for(player_id, need_w)
	for k in GlobalUnits.MATERIAL_KEYS:
		var amt := maxi(0, int(cargo.get(k, 0)))
		if amt > 0:
			add_player_material(player_id, k, -amt)


## Deliver caravan cargo to whoever holds the town (`receiver_id`).
func add_caravan_cargo_for(receiver_id: int, cargo: Dictionary) -> void:
	if receiver_id < 0:
		return
	var add_w := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_KEYS:
		add_w[k] = maxi(0, int(cargo.get(k, 0)))
	add_weapons_for(receiver_id, add_w)
	for k in GlobalUnits.MATERIAL_KEYS:
		var amt := maxi(0, int(cargo.get(k, 0)))
		if amt > 0:
			add_player_material(receiver_id, k, amt)


func get_labor_map(player_id: int) -> Dictionary:
	return ensure_holding(player_id)["labor"]


func get_labor_category(player_id: int, category: String) -> int:
	return int(get_labor_map(player_id).get(category, 0))


func total_labor_assigned(player_id: int) -> int:
	var total := 0
	for cat in GlobalUnits.LABOR_CATEGORIES:
		total += get_labor_category(player_id, cat)
	return total


## Max workers this category can usefully take (building caps / field needs).
func labor_category_cap(player_id: int, category: String, season: int) -> int:
	match category:
		"grain":
			return grain_labor_required(player_id, season)
		"horses":
			return horse_labor_required(player_id, season)
		"wood", "stone", "iron", "silver", "blacksmith":
			return economy_worker_cap(player_id, category)
		_:
			return 0


func economy_worker_cap(player_id: int, category: String) -> int:
	var want_sub := int(ECON_SUBTYPE_FOR_LABOR.get(category, -1))
	if want_sub < 0:
		return 0
	var cap := 0
	for b in economy.get_children():
		if b.get("player_owner") == null:
			continue
		if int(b.player_owner) != player_id:
			continue
		var st := int(b.get("stage"))
		# STAGES: EMPTY=0, SMALL=1, MEDIUM=2, BIG=3, RAZED=4
		if st == 0 or st == 4:
			continue
		if int(b.get("subtype")) != want_sub:
			continue
		match st:
			1: cap += GlobalUnits.ECONOMY_WORKERS_SMALL
			2: cap += GlobalUnits.ECONOMY_WORKERS_MEDIUM
			3: cap += GlobalUnits.ECONOMY_WORKERS_BIG
			_: cap += GlobalUnits.ECONOMY_WORKERS_SMALL
	return cap


func get_economy_buildings_for(player_id: int, category: String = "") -> Array:
	var out: Array = []
	var want_sub := int(ECON_SUBTYPE_FOR_LABOR.get(category, -1)) if category != "" else -1
	for b in economy.get_children():
		if b.get("player_owner") == null:
			continue
		if int(b.player_owner) != player_id:
			continue
		var st := int(b.get("stage"))
		if st == 0 or st == 4:
			continue
		if want_sub >= 0 and int(b.get("subtype")) != want_sub:
			continue
		out.append(b)
	return out


## Set one labor category; clamps to remaining population and category cap.
func set_labor_category(player_id: int, category: String, amount: int, season: int) -> void:
	if category not in GlobalUnits.LABOR_CATEGORIES:
		return
	var h := ensure_holding(player_id)
	var labor: Dictionary = h["labor"]
	var pop := owned_settlement_population(player_id)
	var others := 0
	for cat in GlobalUnits.LABOR_CATEGORIES:
		if cat == category:
			continue
		others += int(labor.get(cat, 0))
	var remaining := maxi(0, pop - others)
	var cap := labor_category_cap(player_id, category, season)
	# Grain fields idle in winter (cap 0). Horse pastures stay workable year-round.
	var max_v := remaining
	if category == "grain":
		max_v = mini(remaining, cap) if season != 0 else 0
	else:
		max_v = mini(remaining, cap)
	labor[category] = clampi(amount, 0, max_v)
	h["labor_assigned"] = total_labor_assigned(player_id)


## Legacy single-slider API → grain category.
func set_labor_assigned(player_id: int, amount: int) -> void:
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	set_labor_category(player_id, "grain", amount, season)


func get_labor_assigned(player_id: int) -> int:
	return total_labor_assigned(player_id)


func clamp_all_labor(player_id: int, season: int) -> void:
	for cat in GlobalUnits.LABOR_CATEGORIES:
		set_labor_category(player_id, cat, get_labor_category(player_id, cat), season)


func seed_test_weapons() -> void:
	var w := get_weapons()
	w["maces"] = 40
	w["pikes"] = 30
	w["bows"] = 25
	w["swords"] = 20
	w["crossbows"] = 10
	w["armour"] = 15
	# Horses + starter grain belong to the de jure holding.
	var pid := int(dejure) if dejure != null else int(player_owner)
	ensure_holding(pid)
	holdings[pid]["horses"] = 15
	_sync_weapons_horses_total()
	if get_player_grain(pid) <= 0:
		add_player_grain(pid, GlobalUnits.STARTING_GRAIN)


func snapshot_season_start() -> void:
	update_population_in_resources()
	season_start_population = int(resources["population"]["has"].get("all", 0))
	levied_this_season = 0
	# Re-clamp category labor to current holding population / caps.
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	for pid in get_holding_controllers():
		clamp_all_labor(pid, season)
	_update_material_will()


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


func get_fields_for_player(player_id: int) -> Array:
	var out: Array = []
	for f in fields.get_children():
		if f.get_controller_id() == player_id:
			out.append(f)
	return out


func count_fields_by_crop(player_id: int, crop: int) -> int:
	var n := 0
	for f in get_fields_for_player(player_id):
		if int(f.crop) == crop:
			n += 1
	return n


func count_planted_grain_fields(player_id: int) -> int:
	var n := 0
	for f in get_fields_for_player(player_id):
		if int(f.crop) == 1 and bool(f.planted): # CROP.GRAIN
			n += 1
	return n


## Expected harvest share for one planted grain field (labor-adjusted).
func grain_share_for_field(field: Node) -> float:
	if field == null or int(field.crop) != 1 or not bool(field.planted):
		return 0.0
	var pid = field.get_controller_id() if field.has_method("get_controller_id") else -1
	if pid < 0:
		return 0.0
	var n := count_planted_grain_fields(pid)
	if n <= 0:
		return 0.0
	return float(ensure_holding(pid).get("grain_potential", 0.0)) / float(n)


func remove_grain_potential(player_id: int, amount: float) -> void:
	if player_id < 0 or amount <= 0.0:
		return
	var h := ensure_holding(player_id)
	h["grain_potential"] = maxf(0.0, float(h.get("grain_potential", 0.0)) - amount)


## Horses currently attributed to this pasture via distribute order.
func horses_on_field(field: Node) -> int:
	if field == null or int(field.crop) != 2:
		return 0
	var pid = field.get_controller_id() if field.has_method("get_controller_id") else -1
	if pid < 0:
		return 0
	for entry in distribute_horses_to_pastures(pid):
		if entry.get("field") == field:
			return int(entry.get("horses", 0))
	return 0


func player_has_holding(player_id: int) -> bool:
	return not get_owned_settlements(player_id).is_empty()


func get_holding_controllers() -> Array:
	var seen := {}
	var out: Array = []
	for s in settlements.get_children():
		if s.get("player_owner") == null:
			continue
		var pid := int(s.player_owner)
		if seen.has(pid):
			continue
		seen[pid] = true
		out.append(pid)
	return out


## Labor needed this season for full grain care (0 in winter). Scales with sown fields.
func grain_labor_required(player_id: int, season: int) -> int:
	if season == 0: # WINTER
		return 0
	return count_planted_grain_fields(player_id) * GlobalUnits.PEOPLE_PER_GRAIN_FIELD


func get_horse_pasture_fields(player_id: int) -> Array:
	var out: Array = []
	for f in get_fields_for_player(player_id):
		if int(f.crop) == 2: # CROP.HORSES
			out.append(f)
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return out


## Fill pastures in order up to HORSES_PER_FIELD; leftover stock stays off-field.
## Returns Array of {"field": Node, "horses": int} for every horse pasture.
func distribute_horses_to_pastures(player_id: int) -> Array:
	var pastures := get_horse_pasture_fields(player_id)
	var remaining := get_player_horses(player_id)
	var cap := GlobalUnits.HORSES_PER_FIELD
	var out: Array = []
	for f in pastures:
		var put := mini(remaining, cap)
		out.append({"field": f, "horses": put})
		remaining -= put
	return out


func count_occupied_horse_fields(player_id: int) -> int:
	var n := 0
	for entry in distribute_horses_to_pastures(player_id):
		if int(entry.get("horses", 0)) > 0:
			n += 1
	return n


func horse_labor_required(player_id: int, _season: int) -> int:
	# Labor scales with pastures that actually host horses (not empty designations).
	return count_occupied_horse_fields(player_id) * GlobalUnits.PEOPLE_PER_HORSE_FIELD


func total_labor_required(player_id: int, season: int) -> int:
	return grain_labor_required(player_id, season) + horse_labor_required(player_id, season)


func _allocate_labor(player_id: int, season: int) -> Dictionary:
	var grain_need := grain_labor_required(player_id, season)
	var horse_need := horse_labor_required(player_id, season)
	var grain_workers := get_labor_category(player_id, "grain")
	var horse_workers := get_labor_category(player_id, "horses")
	return {
		"horse_workers": horse_workers,
		"horse_need": horse_need,
		"grain_workers": grain_workers,
		"grain_need": grain_need,
	}


func get_holding_summary(player_id: int, season: int) -> Dictionary:
	ensure_holding(player_id)
	var h: Dictionary = holdings[player_id]
	var alloc := _allocate_labor(player_id, season)
	var grain_need: int = alloc["grain_need"]
	var grain_workers: int = alloc["grain_workers"]
	var coverage := 1.0
	if grain_need > 0:
		coverage = clampf(float(grain_workers) / float(grain_need), 0.0, 1.0)
	var labor := {}
	var caps := {}
	for cat in GlobalUnits.LABOR_CATEGORIES:
		labor[cat] = get_labor_category(player_id, cat)
		caps[cat] = labor_category_cap(player_id, cat, season)
	var preview := preview_economy_output(player_id)
	return {
		"population": owned_settlement_population(player_id),
		"labor_assigned": total_labor_assigned(player_id),
		"labor_required": total_labor_required(player_id, season),
		"labor": labor,
		"labor_caps": caps,
		"grain_fields": count_fields_by_crop(player_id, 1),
		"planted_grain": count_planted_grain_fields(player_id),
		"horse_fields": count_fields_by_crop(player_id, 2),
		"idle_fields": count_fields_by_crop(player_id, 0),
		"grain_stock": get_player_grain(player_id),
		"wood_stock": get_player_material(player_id, "wood"),
		"stone_stock": get_player_material(player_id, "stone"),
		"iron_stock": get_player_material(player_id, "iron"),
		"horses": get_player_horses(player_id),
		"grain_potential": float(h.get("grain_potential", 0.0)),
		"grain_coverage": coverage,
		"grain_labor_need": grain_need,
		"horse_labor_need": int(alloc["horse_need"]),
		"seed_per_field": GlobalUnits.GRAIN_SEED_PER_FIELD,
		"people_per_grain_field": GlobalUnits.PEOPLE_PER_GRAIN_FIELD,
		"yield_per_field": GlobalUnits.GRAIN_YIELD_PER_FIELD,
		"economy_preview": preview,
		"has_wood": economy_worker_cap(player_id, "wood") > 0,
		"has_stone": economy_worker_cap(player_id, "stone") > 0,
		"has_iron": economy_worker_cap(player_id, "iron") > 0,
		"has_silver": economy_worker_cap(player_id, "silver") > 0,
		"has_blacksmith": economy_worker_cap(player_id, "blacksmith") > 0,
		"has_grain_work": count_planted_grain_fields(player_id) > 0 or count_fields_by_crop(player_id, 1) > 0,
		"has_horse_work": count_occupied_horse_fields(player_id) > 0,
	}


## Call while settlement still owned by from_pid (before flipping player_owner).
func transfer_holding_stock_for_settlement(settlement: Node, from_pid: int, to_pid: int) -> void:
	if settlement == null or from_pid < 0 or to_pid < 0 or from_pid == to_pid:
		return
	ensure_holding(from_pid)
	ensure_holding(to_pid)

	var from_grain_fields := count_fields_by_crop(from_pid, 1)
	var from_horse_fields := count_fields_by_crop(from_pid, 2)
	var sett_grain := 0
	var sett_horse := 0
	var sett_fields: Array = settlement.fields if settlement.get("fields") != null else []
	for f in sett_fields:
		if int(f.crop) == 1:
			sett_grain += 1
		elif int(f.crop) == 2:
			sett_horse += 1

	if from_grain_fields > 0 and sett_grain > 0:
		var grain_share := float(sett_grain) / float(from_grain_fields)
		var move_g := int(floor(float(get_player_grain(from_pid)) * grain_share))
		if move_g > 0:
			add_player_grain(from_pid, -move_g)
			add_player_grain(to_pid, move_g)
		# Split running crop potential too.
		var pot := float(holdings[from_pid].get("grain_potential", 0.0))
		var move_pot := pot * grain_share
		holdings[from_pid]["grain_potential"] = pot - move_pot
		holdings[to_pid]["grain_potential"] = float(holdings[to_pid].get("grain_potential", 0.0)) + move_pot

	if from_horse_fields > 0 and sett_horse > 0:
		var horse_share := float(sett_horse) / float(from_horse_fields)
		var move_h := int(floor(float(get_player_horses(from_pid)) * horse_share))
		if move_h > 0:
			add_player_horses(from_pid, -move_h)
			add_player_horses(to_pid, move_h)


## Season that just ended (before bump, season was this). Apply labor → harvest/foals.
## `ended_season`: season players just finished acting in.
## `new_season`: season after bump.
func tick_agriculture(ended_season: int, new_season: int, rng: RandomNumberGenerator) -> void:
	for pid in get_holding_controllers():
		ensure_holding(pid)
		_tick_holding_agriculture(pid, ended_season, new_season, rng)
	# Confirm winter grain plan: spend seed when leaving winter (end of winter turn).
	if ended_season == 0:
		for pid in get_holding_controllers():
			_plant_grain_for_holding(pid)
	# Economy produces every season (based on labor assigned during ended season).
	for pid in _economy_controllers():
		_tick_holding_economy(pid)
	refresh_field_visuals(new_season)
	for pid in get_holding_controllers():
		clamp_all_labor(pid, new_season)
	_update_grain_will()
	_update_material_will()


func _economy_controllers() -> Array:
	var seen := {}
	var out: Array = []
	for b in economy.get_children():
		if b.get("player_owner") == null:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		var pid := int(b.player_owner)
		if seen.has(pid):
			continue
		seen[pid] = true
		out.append(pid)
	for pid in get_holding_controllers():
		if not seen.has(pid):
			out.append(pid)
			seen[pid] = true
	return out


func preview_economy_output(player_id: int) -> Dictionary:
	var wood_prod := get_labor_category(player_id, "wood") * GlobalUnits.ECONOMY_WOOD_PER_WORKER
	var stone_prod := get_labor_category(player_id, "stone") * GlobalUnits.ECONOMY_STONE_PER_WORKER
	var iron_prod := get_labor_category(player_id, "iron") * GlobalUnits.ECONOMY_IRON_PER_WORKER
	var marks := get_labor_category(player_id, "silver") * GlobalUnits.ECONOMY_SILVER_MARKS_PER_WORKER
	# Simulate craft after production (same order as the season tick).
	var sim_wood := get_player_material(player_id, "wood") + wood_prod
	var sim_iron := get_player_material(player_id, "iron") + iron_prod
	var craft := _simulate_blacksmith_crafts(player_id, sim_wood, sim_iron)
	return {
		"wood": wood_prod - int(craft.get("wood_cost", 0)),
		"stone": stone_prod,
		"iron": iron_prod - int(craft.get("iron_cost", 0)),
		"marks": marks,
		"weapons": craft.get("weapons", {}),
		"weapon_crafts": int(craft.get("crafts", 0)),
		"wood_cost": int(craft.get("wood_cost", 0)),
		"iron_cost": int(craft.get("iron_cost", 0)),
		"blacksmith": craft,
	}


func _max_crafts_for_recipe(wood_have: int, iron_have: int, recipe: Dictionary) -> int:
	if recipe.is_empty():
		return 0
	var max_n := 999999
	var need_wood := int(recipe.get("wood", 0))
	var need_iron := int(recipe.get("iron", 0))
	if need_wood > 0:
		max_n = mini(max_n, int(wood_have / need_wood))
	if need_iron > 0:
		max_n = mini(max_n, int(iron_have / need_iron))
	if max_n >= 999999:
		return 0
	return maxi(0, max_n)


## Distribute blacksmith labor across owned smiths; returns weapons/costs (no mutation).
func _simulate_blacksmith_crafts(player_id: int, wood_have: int, iron_have: int) -> Dictionary:
	var worker_cap := economy_worker_cap(player_id, "blacksmith")
	var workers_raw := get_labor_category(player_id, "blacksmith")
	var workers := mini(workers_raw, worker_cap)
	var weapons := GlobalUnits.empty_weapon_stock()
	var wood_cost := 0
	var iron_cost := 0
	var crafts := 0
	var labor_crafts := 0
	var idle_workers := 0
	var has_recipe := false
	var people_per := 1
	var remainder_workers := 0
	var wood_left := wood_have
	var iron_left := iron_have
	var workers_left := workers
	for b in get_economy_buildings_for(player_id, "blacksmith"):
		if workers_left <= 0:
			break
		var assigned := mini(workers_left, int(b.worker_cap()))
		workers_left -= assigned
		var wkey := str(b.get_craft_weapon()) if b.has_method("get_craft_weapon") else ""
		if wkey == "" or wkey not in GlobalUnits.BLACKSMITH_CRAFTABLE:
			idle_workers += assigned
			continue
		has_recipe = true
		var pp := GlobalUnits.blacksmith_people_per(wkey)
		people_per = pp
		var recipe: Dictionary = GlobalUnits.blacksmith_recipe(wkey)
		var by_labor := int(assigned / pp)
		remainder_workers = assigned % pp
		labor_crafts += by_labor
		var by_mat := _max_crafts_for_recipe(wood_left, iron_left, recipe)
		var n := mini(by_labor, by_mat)
		if n <= 0:
			continue
		var use_wood := int(recipe.get("wood", 0)) * n
		var use_iron := int(recipe.get("iron", 0)) * n
		wood_left -= use_wood
		iron_left -= use_iron
		wood_cost += use_wood
		iron_cost += use_iron
		weapons[wkey] = int(weapons.get(wkey, 0)) + n
		crafts += n
	var free_slots := maxi(0, worker_cap - workers)
	var people_to_next := (people_per - remainder_workers) if remainder_workers > 0 else people_per
	var bottleneck := "ok"
	if worker_cap <= 0:
		bottleneck = "none"
	elif workers <= 0:
		bottleneck = "no_workers"
	elif not has_recipe or idle_workers >= workers:
		bottleneck = "idle_recipe"
	elif crafts < labor_crafts:
		bottleneck = "materials"
	elif free_slots >= people_per:
		bottleneck = "can_expand"
	elif remainder_workers > 0 and free_slots > 0:
		bottleneck = "partial_team"
	elif free_slots == 0 and crafts == labor_crafts:
		bottleneck = "full"
	return {
		"weapons": weapons,
		"wood_cost": wood_cost,
		"iron_cost": iron_cost,
		"crafts": crafts,
		"labor_crafts": labor_crafts,
		"workers": workers,
		"worker_cap": worker_cap,
		"free_slots": free_slots,
		"idle_workers": idle_workers,
		"has_recipe": has_recipe,
		"bottleneck": bottleneck,
		"people_per_weapon": people_per,
		"people_to_next": people_to_next,
	}


func _tick_holding_economy(player_id: int) -> void:
	ensure_holding(player_id)
	var wood_w := get_labor_category(player_id, "wood")
	var stone_w := get_labor_category(player_id, "stone")
	var iron_w := get_labor_category(player_id, "iron")
	var silver_w := get_labor_category(player_id, "silver")
	# Clamp to actual building caps (in case buildings were lost).
	wood_w = mini(wood_w, economy_worker_cap(player_id, "wood"))
	stone_w = mini(stone_w, economy_worker_cap(player_id, "stone"))
	iron_w = mini(iron_w, economy_worker_cap(player_id, "iron"))
	silver_w = mini(silver_w, economy_worker_cap(player_id, "silver"))
	if wood_w > 0:
		add_player_material(player_id, "wood", wood_w * GlobalUnits.ECONOMY_WOOD_PER_WORKER)
	if stone_w > 0:
		add_player_material(player_id, "stone", stone_w * GlobalUnits.ECONOMY_STONE_PER_WORKER)
	if iron_w > 0:
		add_player_material(player_id, "iron", iron_w * GlobalUnits.ECONOMY_IRON_PER_WORKER)
	var marks_gain := silver_w * GlobalUnits.ECONOMY_SILVER_MARKS_PER_WORKER
	if marks_gain > 0 and base_map != null and base_map.get("players") != null:
		var players: Dictionary = base_map.players
		if players.has(player_id):
			players[player_id].game_data["marks"] = int(players[player_id].game_data.get("marks", 0)) + marks_gain
	# Craft after materials land this season.
	_tick_blacksmith_crafts(player_id)


func _tick_blacksmith_crafts(player_id: int) -> void:
	var result := _simulate_blacksmith_crafts(
		player_id,
		get_player_material(player_id, "wood"),
		get_player_material(player_id, "iron")
	)
	var wood_cost := int(result.get("wood_cost", 0))
	var iron_cost := int(result.get("iron_cost", 0))
	if wood_cost > 0:
		add_player_material(player_id, "wood", -wood_cost)
	if iron_cost > 0:
		add_player_material(player_id, "iron", -iron_cost)
	var weapons: Dictionary = result.get("weapons", {})
	if not weapons.is_empty():
		add_weapons_for(player_id, weapons)


func _update_material_will() -> void:
	for key in ["wood", "stone", "iron"]:
		GlobalUnits.ensure_material_has(resources, key)
		var will: Dictionary = {}
		for pid in _economy_controllers():
			var preview := preview_economy_output(pid)
			will[pid] = int(preview.get(key, 0))
		GlobalUnits.recompute_per_player_all(will)
		resources[key]["will"] = will


## Sow planned grain fields when leaving winter (spends seed until stock runs out).
func _plant_grain_for_holding(player_id: int) -> void:
	for f in get_fields_for_player(player_id):
		if int(f.crop) == 1 and not bool(f.planted):
			try_sow_field(f, player_id)


## Spend seed and mark field sown. Returns false if not grain, already sown, or no seed.
func try_sow_field(field: Node, player_id: int) -> bool:
	if field == null or player_id < 0:
		return false
	if int(field.crop) != 1: # GRAIN
		return false
	if bool(field.planted):
		return false
	var seed_cost := GlobalUnits.GRAIN_SEED_PER_FIELD
	if get_player_grain(player_id) < seed_cost:
		return false
	add_player_grain(player_id, -seed_cost)
	field.mark_sown()
	var h := ensure_holding(player_id)
	h["grain_potential"] = float(h.get("grain_potential", 0.0)) + float(GlobalUnits.GRAIN_YIELD_PER_FIELD)
	return true


## Refund seed when unsowing a field that already had seed spent.
func unsow_field(field: Node, player_id: int) -> void:
	if field == null or player_id < 0:
		return
	if not bool(field.planted):
		return
	add_player_grain(player_id, GlobalUnits.GRAIN_SEED_PER_FIELD)
	var h := ensure_holding(player_id)
	h["grain_potential"] = maxf(0.0, float(h.get("grain_potential", 0.0)) - float(GlobalUnits.GRAIN_YIELD_PER_FIELD))
	field.planted = false
	field.neglected = false


func _tick_holding_agriculture(player_id: int, ended_season: int, new_season: int, rng: RandomNumberGenerator) -> void:
	var h := ensure_holding(player_id)
	var alloc := _allocate_labor(player_id, ended_season)

	# Grain labor decay (winter: no work expected).
	var grain_need: int = alloc["grain_need"]
	if grain_need > 0:
		var grain_workers: int = alloc["grain_workers"]
		var coverage := clampf(float(grain_workers) / float(grain_need), 0.0, 1.0)
		if coverage < 1.0:
			var shortfall := 1.0 - coverage
			h["grain_potential"] = float(h.get("grain_potential", 0.0)) * (1.0 - shortfall)
		_apply_neglect_visuals(player_id, coverage)
	elif ended_season != 0:
		_apply_neglect_visuals(player_id, 1.0)

	# Foals every season (incl. winter): per occupied pasture from fill × labor.
	var foals := _roll_foals_for_holding(player_id, int(alloc["horse_workers"]), rng)
	if foals > 0:
		add_player_horses(player_id, foals)

	# Harvest when leaving autumn → entering winter.
	if ended_season == 3 and new_season == 0: # AUTUMN → WINTER
		var yield_amt := int(floor(float(h.get("grain_potential", 0.0))))
		if yield_amt > 0:
			add_player_grain(player_id, yield_amt)
		h["grain_potential"] = 0.0
		for f in get_fields_for_player(player_id):
			if int(f.crop) == 1:
				f.clear_after_harvest()


func _apply_neglect_visuals(player_id: int, coverage: float) -> void:
	var planted: Array = []
	for f in get_fields_for_player(player_id):
		if int(f.crop) == 1 and bool(f.planted):
			planted.append(f)
	if planted.is_empty():
		return
	var active_n := int(round(float(planted.size()) * clampf(coverage, 0.0, 1.0)))
	for i in planted.size():
		planted[i].neglected = i >= active_n


func _roll_foals_for_holding(player_id: int, horse_workers: int, rng: RandomNumberGenerator) -> int:
	var occupied: Array = []
	for entry in distribute_horses_to_pastures(player_id):
		if int(entry.get("horses", 0)) > 0:
			occupied.append(entry)
	if occupied.is_empty():
		return 0
	var people_per := float(horse_workers) / float(occupied.size())
	var foals := 0
	var cap := float(GlobalUnits.HORSES_PER_FIELD)
	var need := float(GlobalUnits.PEOPLE_PER_HORSE_FIELD)
	for entry in occupied:
		var fill := clampf(float(entry["horses"]) / cap, 0.0, 1.0)
		var labor := clampf(people_per / need, 0.0, 1.0)
		var eff := fill * labor
		if eff >= GlobalUnits.FOAL_EFF_HIGH:
			foals += rng.randi_range(GlobalUnits.FOAL_HIGH_MIN, GlobalUnits.FOAL_HIGH_MAX)
		elif eff >= GlobalUnits.FOAL_EFF_MID:
			foals += rng.randi_range(GlobalUnits.FOAL_MID_MIN, GlobalUnits.FOAL_MID_MAX)
	return foals


func _apply_horse_display_counts() -> void:
	for f in fields.get_children():
		if f.get("display_horses") != null:
			f.display_horses = 0
	for pid in get_holding_controllers():
		for entry in distribute_horses_to_pastures(pid):
			var f = entry.get("field")
			if f != null and is_instance_valid(f):
				f.display_horses = int(entry.get("horses", 0))


func _refresh_horse_field_visuals() -> void:
	_apply_horse_display_counts()
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	for f in fields.get_children():
		if int(f.get("crop")) == 2 and f.has_method("update_visuals_for_season"):
			f.update_visuals_for_season(season)


func refresh_field_visuals(season: int) -> void:
	_apply_horse_display_counts()
	for f in fields.get_children():
		if f.has_method("update_visuals_for_season"):
			f.update_visuals_for_season(season)


func _update_grain_will() -> void:
	GlobalUnits.ensure_material_has(resources, "grain")
	var will: Dictionary = {}
	for pid in get_holding_controllers():
		ensure_holding(pid)
		will[pid] = int(floor(float(holdings[pid].get("grain_potential", 0.0))))
	GlobalUnits.recompute_per_player_all(will)
	resources["grain"]["will"] = will


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
	var weapons_copy: Dictionary = get_weapons_for(viewer_id).duplicate() if viewer_id >= 0 else get_weapons().duplicate()
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	var holding := {}
	var viewer_has_holding := viewer_id >= 0 and player_has_holding(viewer_id)
	if viewer_has_holding:
		holding = get_holding_summary(viewer_id, season)
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
		"viewer_has_holding": viewer_has_holding,
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
		"holding": holding,
		"grain_stock": get_player_grain(viewer_id) if viewer_id >= 0 else 0,
	}
