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

# Levy counter (happiness lives per settlement). Snapshot resets each season.
var season_start_population: int = 0
var levied_this_season: int = 0

# Per-player holding economy: labor slider, running grain potential, horse stock, rations.
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
const MAP_SHIELD_SIZE := 18

var _label_center := Vector2.ZERO
var _owner_shield: Sprite2D = null

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
	# Empty / empty-build / dismantle plots are not a usable seat (mid-upgrade still is).
	if building == null:
		return true
	if bool(building.get_meta("seat_destroyed", false)):
		return true
	if building.has_method("is_operational") and not building.is_operational():
		return true
	return false


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
	_refresh_owner_shield(players_dict)
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


func _ensure_owner_shield() -> void:
	if _owner_shield != null and is_instance_valid(_owner_shield):
		return
	_owner_shield = Sprite2D.new()
	_owner_shield.name = "owner_shield"
	_owner_shield.centered = true
	_owner_shield.z_index = 1
	map_labels.add_child(_owner_shield)


func _refresh_owner_shield(players_dict: Dictionary) -> void:
	_ensure_owner_shield()
	var pid := int(dejure) if dejure != null else NO_DEFACTO
	if pid < 0 or not players_dict.has(pid):
		_owner_shield.visible = false
		_owner_shield.texture = null
		return
	_owner_shield.texture = Heraldry.texture_for_player(players_dict[pid], MAP_SHIELD_SIZE)
	_owner_shield.visible = true


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
	# Shield left of province name; status / owner lines below. Group centered on origin.
	var lines: Array[Label] = [_name_label]
	if _status_label.visible:
		lines.append(_status_label)
	lines.append(_owner_label)
	var total_h := MAP_LABEL_LINE_HEIGHT * lines.size()
	var y := -total_h / 2.0
	var name_y := y
	var name_w := maxf(_name_label.get_minimum_size().x, float(_name_label.text.length()) * 7.0)
	var shield_w := float(MAP_SHIELD_SIZE) if (_owner_shield != null and _owner_shield.visible) else 0.0
	var gap := 4.0 if shield_w > 0.0 else 0.0
	var row_w := shield_w + gap + name_w
	var row_left := -row_w * 0.5
	if _owner_shield != null and _owner_shield.visible and _owner_shield.texture != null:
		_owner_shield.position = Vector2(row_left + shield_w * 0.5, name_y + MAP_LABEL_LINE_HEIGHT * 0.5)
	elif _owner_shield != null:
		_owner_shield.position = Vector2.ZERO
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.position = Vector2(row_left + shield_w + gap, name_y)
	y += MAP_LABEL_LINE_HEIGHT
	for i in range(1, lines.size()):
		var lbl: Label = lines[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var lw := maxf(lbl.get_minimum_size().x, float(lbl.text.length()) * 6.5)
		lbl.position = Vector2(-lw * 0.5, y)
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
		# Per-player forged kit: weapons[key]["has"][pid]. Horses stay on holdings.
		"weapons": GlobalUnits.empty_per_player_weapon_buckets(),
	}
	resources = _resource
	holdings = {}


## Province-wide forged totals (+ sum of holding horses). Prefer get_weapons_for.
func get_weapons() -> Dictionary:
	if resources == null:
		create_de_resorce_dict()
	GlobalUnits.ensure_weapons_resources(resources)
	var w := GlobalUnits.weapons_province_totals(resources)
	w["horses"] = _total_holding_horses()
	return w


## Weapons stock for a player: per-player forged kit; horses are per-holding.
func get_weapons_for(player_id: int) -> Dictionary:
	if resources == null:
		create_de_resorce_dict()
	GlobalUnits.ensure_weapons_resources(resources)
	var w := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_STOCK_KEYS:
		w[k] = GlobalUnits.get_player_weapon_amount(resources, player_id, k)
	w["horses"] = get_player_horses(player_id)
	return w


func ensure_holding(player_id: int) -> Dictionary:
	if player_id < 0:
		return {}
	if not holdings.has(player_id):
		var labor := {}
		var labor_priority := {}
		for cat in GlobalUnits.LABOR_CATEGORIES:
			labor[cat] = 0
			labor_priority[cat] = GlobalUnits.LABOR_PRIORITY_MANUAL
		holdings[player_id] = {
			"labor": labor,
			"labor_priority": labor_priority,
			"labor_assigned": 0, # legacy total; kept in sync
			"grain_potential": 0.0,
			"horses": 0,
			"pending_marks": 0, # silver preview → applied next tick to global treasury
			"ration": GlobalUnits.RATION_DEFAULT,
			"tax": GlobalUnits.TAX_DEFAULT,
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
		if not h.has("labor_priority") or not (h["labor_priority"] is Dictionary):
			var pri := {}
			for cat in GlobalUnits.LABOR_CATEGORIES:
				pri[cat] = GlobalUnits.LABOR_PRIORITY_MANUAL
			h["labor_priority"] = pri
		else:
			var pri_exist: Dictionary = h["labor_priority"]
			for cat in GlobalUnits.LABOR_CATEGORIES:
				if not pri_exist.has(cat):
					pri_exist[cat] = GlobalUnits.LABOR_PRIORITY_MANUAL
				else:
					pri_exist[cat] = clampi(
						int(pri_exist[cat]),
						GlobalUnits.LABOR_PRIORITY_MANUAL,
						GlobalUnits.LABOR_PRIORITY_MAX
					)
		if not h.has("pending_marks"):
			h["pending_marks"] = 0
		if not h.has("ration"):
			h["ration"] = GlobalUnits.RATION_DEFAULT
		if not h.has("tax"):
			h["tax"] = GlobalUnits.TAX_DEFAULT
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
	_refresh_horse_field_visuals()


func _total_holding_horses() -> int:
	var total := 0
	for pid in holdings:
		total += int(holdings[pid].get("horses", 0))
	return total


func can_afford_weapons_for(player_id: int, need: Dictionary) -> bool:
	return GlobalUnits.can_afford_weapons(get_weapons_for(player_id), need)


func subtract_weapons_for(player_id: int, need: Dictionary) -> void:
	if player_id < 0:
		return
	var horses := int(need.get("horses", 0))
	if resources == null:
		create_de_resorce_dict()
	for k in GlobalUnits.WEAPON_STOCK_KEYS:
		var amt := int(need.get(k, 0))
		if amt > 0:
			GlobalUnits.add_player_weapon_amount(resources, player_id, k, -amt)
	if horses != 0:
		add_player_horses(player_id, -horses)


func add_weapons_for(player_id: int, add: Dictionary) -> void:
	if player_id < 0:
		return
	var horses := int(add.get("horses", 0))
	if resources == null:
		create_de_resorce_dict()
	GlobalUnits.add_player_weapon_stock(resources, player_id, add)
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
		"castle":
			return castle_construction_cap(player_id)
		_:
			return 0


## Castle labor is uncapped by buildings; limited only by population via set_labor.
## Only the de jure controller may assign workers to their castle project.
func castle_construction_cap(player_id: int) -> int:
	if not has_dejure(player_id):
		return 0
	var castle := _find_building_of_type(defense, GlobalStuff.BUILDING_TYPE.CASTLE)
	if castle == null or not castle.has_method("is_under_construction"):
		return 0
	if not castle.is_under_construction():
		return 0
	# Large soft cap; set_labor_category still clamps to remaining population.
	return owned_settlement_population(player_id)


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
		if b.has_method("worker_cap"):
			cap += int(b.worker_cap())
		else:
			cap += GlobalUnits.economy_workers_for(want_sub, 0)
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


func get_labor_priority_map(player_id: int) -> Dictionary:
	return ensure_holding(player_id)["labor_priority"]


func get_labor_priority(player_id: int, category: String) -> int:
	return clampi(
		int(get_labor_priority_map(player_id).get(category, GlobalUnits.LABOR_PRIORITY_MANUAL)),
		GlobalUnits.LABOR_PRIORITY_MANUAL,
		GlobalUnits.LABOR_PRIORITY_MAX
	)


## Set auto-fill priority for one category (`0` = manual). Reallocates the holding.
func set_labor_priority(player_id: int, category: String, priority: int, season: int) -> void:
	if category not in GlobalUnits.LABOR_CATEGORIES:
		return
	var h := ensure_holding(player_id)
	var pri: Dictionary = h["labor_priority"]
	pri[category] = clampi(priority, GlobalUnits.LABOR_PRIORITY_MANUAL, GlobalUnits.LABOR_PRIORITY_MAX)
	reallocate_labor_by_priority(player_id, season)


## Set one labor category; clamps to remaining population and category cap.
## Slider / manual edits mark the category as manual (keeps this amount as target).
func set_labor_category(player_id: int, category: String, amount: int, season: int) -> void:
	if category not in GlobalUnits.LABOR_CATEGORIES:
		return
	var h := ensure_holding(player_id)
	var labor: Dictionary = h["labor"]
	var pri: Dictionary = h["labor_priority"]
	pri[category] = GlobalUnits.LABOR_PRIORITY_MANUAL
	var pop := owned_settlement_population(player_id)
	var others := 0
	for cat in GlobalUnits.LABOR_CATEGORIES:
		if cat == category:
			continue
		others += int(labor.get(cat, 0))
	var remaining := maxi(0, pop - others)
	var cap := labor_category_cap(player_id, category, season)
	var max_v := mini(remaining, cap)
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


## Re-apply labor from priorities after population or category-cap changes.
## Manual categories keep their current assignment (clamped); numbered priorities
## fill to category cap in ascending order. Tie-break: LABOR_CATEGORIES order.
func reallocate_labor_by_priority(player_id: int, season: int) -> void:
	var h := ensure_holding(player_id)
	var labor: Dictionary = h["labor"]
	var pri: Dictionary = h["labor_priority"]
	var pop := owned_settlement_population(player_id)
	var targets := {}
	for cat in GlobalUnits.LABOR_CATEGORIES:
		targets[cat] = int(labor.get(cat, 0))
		labor[cat] = 0
	var remaining := pop
	# Phase 1: manual targets first (fixed category order if they compete).
	for cat in GlobalUnits.LABOR_CATEGORIES:
		if int(pri.get(cat, GlobalUnits.LABOR_PRIORITY_MANUAL)) != GlobalUnits.LABOR_PRIORITY_MANUAL:
			continue
		var cap := labor_category_cap(player_id, str(cat), season)
		var want := mini(mini(int(targets[cat]), cap), remaining)
		labor[cat] = maxi(0, want)
		remaining -= int(labor[cat])
	# Phase 2: numeric priorities ascending; same priority → LABOR_CATEGORIES order.
	var levels: Array = []
	for cat2 in GlobalUnits.LABOR_CATEGORIES:
		var p := int(pri.get(cat2, GlobalUnits.LABOR_PRIORITY_MANUAL))
		if p > GlobalUnits.LABOR_PRIORITY_MANUAL and p not in levels:
			levels.append(p)
	levels.sort()
	for level in levels:
		for cat3 in GlobalUnits.LABOR_CATEGORIES:
			if int(pri.get(cat3, GlobalUnits.LABOR_PRIORITY_MANUAL)) != int(level):
				continue
			var cap2 := labor_category_cap(player_id, str(cat3), season)
			var fill := mini(cap2, remaining)
			labor[cat3] = maxi(0, fill)
			remaining -= int(labor[cat3])
	h["labor_assigned"] = total_labor_assigned(player_id)


## Compatibility name used across the map — priority-aware reallocation.
func clamp_all_labor(player_id: int, season: int) -> void:
	reallocate_labor_by_priority(player_id, season)


## Default province kit for the de jure holder (materials + weapon stock).
## Marks are applied on the player treasury at map setup.
func seed_default_holding_kit() -> void:
	var pid := int(dejure) if dejure != null else int(player_owner)
	if pid < 0:
		return
	ensure_holding(pid)
	if resources == null:
		create_de_resorce_dict()
	GlobalUnits.ensure_weapons_resources(resources)
	if get_player_grain(pid) <= 0:
		add_player_grain(pid, GlobalUnits.PROVINCE_START_GRAIN)
	if get_player_material(pid, "wood") <= 0:
		add_player_material(pid, "wood", GlobalUnits.PROVINCE_START_WOOD)
	if get_player_material(pid, "iron") <= 0:
		add_player_material(pid, "iron", GlobalUnits.PROVINCE_START_IRON)
	# Starter forged kit in the province inventory (not garrison).
	var seed_kit := {
		"maces": GlobalUnits.PROVINCE_START_MACES,
		"pikes": GlobalUnits.PROVINCE_START_PIKES,
		"bows": GlobalUnits.PROVINCE_START_BOWS,
	}
	for k in seed_kit:
		var has: Dictionary = resources["weapons"][k]["has"]
		if int(has.get(pid, 0)) <= 0:
			has[pid] = int(seed_kit[k])
			GlobalUnits.recompute_per_player_all(has)


## Designer / test alias.
func seed_test_weapons() -> void:
	seed_default_holding_kit()


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
## Same delta on every settlement in the province (all owners' settlements equally).
func apply_levy_happiness(prev_levied: int, new_levied: int) -> void:
	var old_p := GlobalUnits.levy_happiness_penalty(prev_levied, season_start_population)
	var new_p := GlobalUnits.levy_happiness_penalty(new_levied, season_start_population)
	var delta := new_p - old_p
	if delta <= 0.0:
		return
	for s in settlements.get_children():
		if s.get("happiness") == null:
			continue
		s.happiness = clampf(float(s.happiness) - delta, 0.0, 100.0)


func get_holding_ration(player_id: int) -> int:
	return GlobalUnits.clamp_ration(int(ensure_holding(player_id).get("ration", GlobalUnits.RATION_DEFAULT)))


func set_holding_ration(player_id: int, level: int) -> void:
	if player_id < 0:
		return
	ensure_holding(player_id)["ration"] = GlobalUnits.clamp_ration(level)


func get_holding_tax(player_id: int) -> int:
	return GlobalUnits.clamp_tax(int(ensure_holding(player_id).get("tax", GlobalUnits.TAX_DEFAULT)))


func set_holding_tax(player_id: int, level: int) -> void:
	if player_id < 0:
		return
	ensure_holding(player_id)["tax"] = GlobalUnits.clamp_tax(level)


## Total uncollected tax marks in settlements owned by `player_id`.
func holding_tax_marks_stored(player_id: int) -> int:
	var total := 0
	for s in get_owned_settlements(player_id):
		if s.get("tax_marks") == null:
			continue
		total += int(s.tax_marks)
	return total


## Seed grain reserved for unsown grain fields (winter plan / default priority).
## In winter, reserve only for fields current sow labor can cover.
func seed_grain_reserve(player_id: int) -> int:
	var unsown := count_unsown_grain_fields(player_id)
	if unsown <= 0:
		return 0
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	var reserve_fields := unsown
	if season == 0:
		reserve_fields = mini(unsown, max_sowable_grain_fields(player_id))
	return reserve_fields * GlobalUnits.GRAIN_SEED_PER_FIELD


## Average happiness of settlements owned by `player_id` (or all if pid < 0).
func average_settlement_happiness(player_id: int = -1) -> float:
	var total := 0.0
	var n := 0
	for s in settlements.get_children():
		if s.get("happiness") == null:
			continue
		if player_id >= 0 and (s.get("player_owner") == null or int(s.player_owner) != player_id):
			continue
		total += float(s.happiness)
		n += 1
	if n <= 0:
		return 100.0
	return total / float(n)


## Remove `amount` people from owned settlements. Returns false if not enough.
## Takes from largest settlements first (greedy) so the full amount is always
## removed whenever total owned population is sufficient.
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
	# Largest first — avoid wiping small villages when a big town can cover it.
	owned.sort_custom(func(a, b): return int(a.population) > int(b.population))
	for s in owned:
		if remaining <= 0:
			break
		var take := mini(int(s.population), remaining)
		s.population -= take
		remaining -= take
	update_population_in_resources()
	if remaining <= 0:
		var season := 0
		if base_map != null and base_map.get("season") != null:
			season = int(base_map.season)
		clamp_all_labor(player_id, season)
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


func count_unsown_grain_fields(player_id: int) -> int:
	var n := 0
	for f in get_fields_for_player(player_id):
		if int(f.crop) == 1 and not bool(f.planted):
			n += 1
	return n


## How many unsown grain fields current grain labor can sow (ignores seed stock).
func max_sowable_grain_fields(player_id: int) -> int:
	var per := GlobalUnits.PEOPLE_PER_GRAIN_FIELD_PEAK
	if per <= 0:
		return 0
	return int(get_labor_category(player_id, "grain") / per)


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


## Labor needed this season for full grain work.
## Winter: sow planned (unsown) grain fields. Other seasons: tend/harvest planted fields.
func grain_labor_required(player_id: int, season: int) -> int:
	var per := GlobalUnits.people_per_grain_field(season)
	if season == 0: # WINTER — sow labor on planned fields
		return count_unsown_grain_fields(player_id) * per
	return count_planted_grain_fields(player_id) * per


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
	var labor_priority := {}
	for cat in GlobalUnits.LABOR_CATEGORIES:
		labor[cat] = get_labor_category(player_id, cat)
		caps[cat] = labor_category_cap(player_id, cat, season)
		labor_priority[cat] = get_labor_priority(player_id, cat)
	var preview := preview_economy_output(player_id)
	var ration_info := preview_holding_rations(player_id)
	var tax_prev := _preview_holding_tax(player_id)
	var foals_prev := preview_foals_for_holding(player_id)
	var harvest_forecast := preview_grain_until_harvest(player_id, season, ration_info)
	var effective_ration := int(ration_info.get("effective", GlobalUnits.RATION_DEFAULT))
	var happy_delta := (
		GlobalUnits.ration_happiness_delta(effective_ration)
		+ GlobalUnits.tax_happiness_delta(get_holding_tax(player_id))
	)
	return {
		"population": owned_settlement_population(player_id),
		"labor_assigned": total_labor_assigned(player_id),
		"labor_required": total_labor_required(player_id, season),
		"labor": labor,
		"labor_caps": caps,
		"labor_priority": labor_priority,
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
		"people_per_grain_field": GlobalUnits.people_per_grain_field(season),
		"sowable_by_labor": max_sowable_grain_fields(player_id),
		"unsown_grain": count_unsown_grain_fields(player_id),
		"yield_per_field": GlobalUnits.GRAIN_YIELD_PER_FIELD,
		"economy_preview": preview,
		"has_wood": economy_worker_cap(player_id, "wood") > 0,
		"has_stone": economy_worker_cap(player_id, "stone") > 0,
		"has_iron": economy_worker_cap(player_id, "iron") > 0,
		"has_silver": economy_worker_cap(player_id, "silver") > 0,
		"has_blacksmith": economy_worker_cap(player_id, "blacksmith") > 0,
		"has_castle_work": castle_construction_cap(player_id) > 0,
		"castle_work_remaining": _castle_work_remaining(),
		"has_grain_work": count_planted_grain_fields(player_id) > 0 or count_fields_by_crop(player_id, 1) > 0,
		"has_horse_work": count_occupied_horse_fields(player_id) > 0,
		"ration": int(ration_info.get("requested", GlobalUnits.RATION_DEFAULT)),
		"ration_effective": int(ration_info.get("effective", GlobalUnits.RATION_DEFAULT)),
		"ration_affordable": bool(ration_info.get("affordable", true)),
		"ration_grain_need": int(ration_info.get("civilian_need", 0)),
		"ration_grain_available": int(ration_info.get("available_for_people", 0)),
		"seed_reserve": int(ration_info.get("seed_reserve", 0)),
		"army_grain_need": int(ration_info.get("army_need", 0)),
		"grain_need_until_harvest": int(harvest_forecast.get("need", 0)),
		"grain_until_harvest_ok": bool(harvest_forecast.get("ok", true)),
		"seasons_until_harvest": int(harvest_forecast.get("seasons", 1)),
		"happiness": average_settlement_happiness(player_id),
		"happiness_delta_next": happy_delta,
		"tax": get_holding_tax(player_id),
		"tax_marks_stored": holding_tax_marks_stored(player_id),
		"tax_marks_next": int(tax_prev.get("total", 0)),
		"tax_marks_next_wallet": int(tax_prev.get("wallet", 0)),
		"tax_marks_next_coffer": int(tax_prev.get("coffer", 0)),
		"tax_castle_bonus_next": int(tax_prev.get("castle_bonus", 0)),
		"tax_auto_wallet": bool(tax_prev.get("auto_wallet", false)),
		"foals_next_min": int(foals_prev.get("min", 0)),
		"foals_next_max": int(foals_prev.get("max", 0)),
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


## After last settlement lost: remaining stock goes to the conqueror.
func transfer_remaining_holding_stock(from_pid: int, to_pid: int) -> void:
	if from_pid < 0 or to_pid < 0 or from_pid == to_pid:
		return
	ensure_holding(from_pid)
	ensure_holding(to_pid)
	if resources == null:
		create_de_resorce_dict()
	# Forged weapons.
	var kit := GlobalUnits.empty_weapon_stock()
	for k in GlobalUnits.WEAPON_STOCK_KEYS:
		kit[k] = GlobalUnits.get_player_weapon_amount(resources, from_pid, k)
	if GlobalUnits.weapon_stock_has_any(kit):
		subtract_weapons_for(from_pid, kit)
		add_weapons_for(to_pid, kit)
	# Materials (grain/wood/stone/iron).
	for k in GlobalUnits.MATERIAL_KEYS:
		var amt := get_player_material(from_pid, k)
		if amt > 0:
			add_player_material(from_pid, k, -amt)
			add_player_material(to_pid, k, amt)
	# Leftover horses + grain potential on the holding.
	var horses := get_player_horses(from_pid)
	if horses > 0:
		add_player_horses(from_pid, -horses)
		add_player_horses(to_pid, horses)
	var pot := float(holdings[from_pid].get("grain_potential", 0.0))
	if pot != 0.0:
		holdings[from_pid]["grain_potential"] = 0.0
		holdings[to_pid]["grain_potential"] = float(holdings[to_pid].get("grain_potential", 0.0)) + pot


## Grain needed to hold requested rations + current army draw until harvest,
## plus seed for currently planted grain fields (next sow). Compared to stock.
func preview_grain_until_harvest(
	player_id: int, season: int, ration_info: Dictionary = {}
) -> Dictionary:
	var info := ration_info
	if info.is_empty():
		info = preview_holding_rations(player_id)
	var seasons := GlobalUnits.seasons_until_next_harvest(season)
	var promised := int(info.get("promised_need", 0))
	var army := int(info.get("army_need", 0))
	var seed := count_planted_grain_fields(player_id) * GlobalUnits.GRAIN_SEED_PER_FIELD
	var need := (promised + army) * seasons + seed
	var stock := int(info.get("stock", get_player_grain(player_id)))
	return {
		"seasons": seasons,
		"promised_per_season": promised,
		"army_per_season": army,
		"seed": seed,
		"need": need,
		"stock": stock,
		"ok": need <= stock,
	}


## Forecast grain split: seed reserve → local forces → civilians at requested ration.
## `army_need` comes from base_map when available (0 otherwise; cargo-first forces
## only count province shortfall).
func preview_holding_rations(player_id: int, army_need: int = -1) -> Dictionary:
	ensure_holding(player_id)
	var requested := get_holding_ration(player_id)
	var pop := owned_settlement_population(player_id)
	var stock := get_player_grain(player_id)
	var seed_r := seed_grain_reserve(player_id)
	var army_n := army_need
	if army_n < 0:
		army_n = 0
		if base_map != null and base_map.has_method("province_army_grain_need"):
			army_n = int(base_map.province_army_grain_need(self, player_id))
	var after_seed := maxi(0, stock - seed_r)
	var available_for_people := maxi(0, after_seed - maxi(0, army_n))
	var effective := GlobalUnits.affordable_ration(pop, requested, available_for_people)
	var civilian_need := GlobalUnits.ration_grain_need(pop, effective)
	var promised_need := GlobalUnits.ration_grain_need(pop, requested)
	return {
		"requested": requested,
		"effective": effective,
		"affordable": promised_need <= available_for_people,
		"population": pop,
		"stock": stock,
		"seed_reserve": seed_r,
		"army_need": maxi(0, army_n),
		"available_for_people": available_for_people,
		"civilian_need": civilian_need,
		"promised_need": promised_need,
	}


## Feed armies/civilians, apply ration+tax happiness/pop, deposit tax into settlement coffers.
## Returns shrink report for inbox, or empty if no losses.
## `rng` seeds over-cap population jitter (null → no jitter).
func tick_holding_rations(player_id: int, rng: RandomNumberGenerator = null) -> Dictionary:
	ensure_holding(player_id)
	var requested := get_holding_ration(player_id)
	var tax_level := get_holding_tax(player_id)
	var seed_r := seed_grain_reserve(player_id)
	var stock := get_player_grain(player_id)
	var spendable := maxi(0, stock - seed_r)

	# Armies before people: pay local forces from granary first, then civilians.
	var army_spent := 0
	if spendable > 0 and base_map != null and base_map.has_method("feed_province_armies_from_stock"):
		army_spent = int(base_map.feed_province_armies_from_stock(self, player_id, spendable))
		if army_spent > 0:
			add_player_grain(player_id, -army_spent)
	var people_budget := maxi(0, spendable - army_spent)

	var owned := get_owned_settlements(player_id)
	# Stable order so over-cap jitter consumes RNG the same on all peers.
	owned.sort_custom(func(a, b) -> bool: return String(a.name) < String(b.name))
	var old_pop := 0
	for s in owned:
		old_pop += int(s.population)

	var effective := GlobalUnits.affordable_ration(old_pop, requested, people_budget)
	var civilian_need := GlobalUnits.ration_grain_need(old_pop, effective)
	if civilian_need > 0:
		add_player_grain(player_id, -civilian_need)

	var happy_delta := (
		GlobalUnits.ration_happiness_delta(effective) + GlobalUnits.tax_happiness_delta(tax_level)
	)
	var pop_frac := (
		GlobalUnits.ration_pop_fraction(effective) + GlobalUnits.tax_pop_fraction(tax_level)
	)
	var auto_wallet := has_dejure(player_id)
	var wallet_pay := 0
	var raw_base_sum := 0
	var new_pop := 0
	# Ration/tax deltas before overflow pressure (inbox only for player-caused shrink).
	var base_delta_sum := 0
	for s in owned:
		var can_grow = (
			not s.has_method("can_receive_ration_growth") or s.can_receive_ration_growth()
		)
		# Tax on current (pre-growth) population: tier % always; delivery by de jure.
		if can_grow:
			var base := GlobalUnits.tax_marks_for_settlement(int(s.population), tax_level)
			var tier_frac := 0.0
			if s.has_method("settlement_marks_bonus_fraction"):
				tier_frac = float(s.settlement_marks_bonus_fraction())
			var due := GlobalUnits.tax_marks_with_tier_bonus(base, tier_frac)
			raw_base_sum += base
			if due > 0:
				if auto_wallet:
					wallet_pay += due
				elif s.get("tax_marks") != null:
					s.tax_marks = int(s.tax_marks) + due
		if can_grow and s.get("happiness") != null:
			s.happiness = clampf(float(s.happiness) + happy_delta, 0.0, 100.0)
		if not can_grow:
			s.predicted_growth = 0
			new_pop += int(s.population)
			continue
		var pop_now := int(s.population)
		var base_delta := GlobalUnits.population_delta_from_fraction(pop_now, pop_frac)
		base_delta_sum += base_delta
		var cap_jit: Vector2i = GlobalUnits.settlement_pop_cap_and_jitter(s)
		var delta := GlobalUnits.settlement_overflow_adjusted_delta(
			pop_now, base_delta, int(cap_jit.x), int(cap_jit.y), rng
		)
		s.predicted_growth = delta
		s.population = maxi(0, pop_now + delta)
		new_pop += int(s.population)

	if auto_wallet:
		wallet_pay += _castle_tax_bonus(player_id, raw_base_sum)
		var paid := wallet_pay
		if (
			base_map != null
			and base_map.has_method("get_player_wallet_income_paid")
		):
			paid = int(base_map.get_player_wallet_income_paid(player_id, wallet_pay))
		_add_player_marks(player_id, paid)

	update_population_in_resources()
	# Pop grew or shrank — refill by labor priorities.
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	reallocate_labor_by_priority(player_id, season)

	var dropped := old_pop - new_pop
	# Overflow soft-cap flux is normal — only inbox when ration/tax alone would shrink.
	if dropped <= 0 or base_delta_sum >= 0:
		return {}
	return {
		"province_name": str(p_name),
		"province_id": str(name),
		"old_pop": old_pop,
		"new_pop": new_pop,
		"dropped": dropped,
		"grain_stock": get_player_grain(player_id),
		"ration": requested,
		"ration_effective": effective,
		"ration_name": GlobalUnits.ration_name(requested),
		"ration_effective_name": GlobalUnits.ration_name(effective),
	}


## Tick rations for every holding controller. Returns { player_id: [shrink_entries...] }.
func tick_rations(rng: RandomNumberGenerator = null) -> Dictionary:
	var by_player: Dictionary = {}
	var pids: Array = get_holding_controllers()
	pids.sort()
	for pid in pids:
		var report := tick_holding_rations(int(pid), rng)
		if report.is_empty():
			continue
		var key := int(pid)
		if not by_player.has(key):
			by_player[key] = []
		by_player[key].append(report)
	return by_player


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
	_tick_castle_construction()
	refresh_field_visuals(new_season)
	for pid in get_holding_controllers():
		clamp_all_labor(pid, new_season)
	_update_grain_will()
	_update_material_will()


func get_castle_plot() -> Node:
	return _find_building_of_type(defense, GlobalStuff.BUILDING_TYPE.CASTLE)


func _castle_work_remaining() -> int:
	var castle := get_castle_plot()
	if castle == null or not castle.has_method("is_under_construction"):
		return 0
	if not castle.is_under_construction():
		return 0
	return maxi(0, int(castle.project_work_needed) - int(castle.project_progress))


func _tick_castle_construction() -> void:
	var castle := get_castle_plot()
	if castle == null or not castle.has_method("is_under_construction"):
		return
	if not castle.is_under_construction():
		return
	# Only de jure labor advances the worksite.
	var pid := int(dejure) if dejure != null else -1
	if pid < 0:
		return
	var work := get_labor_category(pid, "castle")
	if work <= 0:
		return
	if not castle.add_construction_work(work):
		return
	var refund: Dictionary = castle.complete_project()
	_apply_material_dict(refund, true)
	if base_map != null and base_map.has_method("grant_castle_peak_archers"):
		base_map.grant_castle_peak_archers(castle, pid)
	if castle.has_method("set_flags"):
		castle.set_flags()
	if base_map != null and base_map.has_method("update_menus"):
		base_map.update_menus()
	if base_map != null and is_instance_valid(base_map.gui_node) \
			and base_map.gui_node.has_method("refresh_castle_popup_if"):
		base_map.gui_node.refresh_castle_popup_if(base_map, castle)


func _apply_material_dict(amounts: Dictionary, as_refund: bool) -> void:
	if amounts == null or amounts.is_empty():
		return
	# Refund / pay against de jure holding (construction controller).
	var pid := int(dejure) if dejure != null else int(player_owner)
	if pid < 0:
		return
	for key in ["wood", "stone"]:
		var amt := int(amounts.get(key, 0))
		if amt == 0:
			continue
		if as_refund:
			add_player_material(pid, key, amt)
		else:
			add_player_material(pid, key, -amt)


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


## Sow planned grain fields when leaving winter.
## Limited by sow labor (PEAK people/field) and seed stock; unplanted plans stay grain.
func _plant_grain_for_holding(player_id: int) -> void:
	var can_plant := max_sowable_grain_fields(player_id)
	if can_plant <= 0:
		return
	var candidates: Array = []
	for f in get_fields_for_player(player_id):
		if int(f.crop) == 1 and not bool(f.planted):
			candidates.append(f)
	candidates.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var sown := 0
	for f in candidates:
		if sown >= can_plant:
			break
		if try_sow_field(f, player_id):
			sown += 1


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

	# Grain labor decay on growing crops (skip winter sow — potential is granted at plant).
	var grain_need: int = alloc["grain_need"]
	if ended_season != 0 and grain_need > 0:
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


## Expected foal range for current (or overridden) horse labor. No RNG.
func preview_foals_for_holding(player_id: int, horse_workers: int = -1) -> Dictionary:
	if horse_workers < 0:
		horse_workers = get_labor_category(player_id, "horses")
	var occupied: Array = []
	for entry in distribute_horses_to_pastures(player_id):
		if int(entry.get("horses", 0)) > 0:
			occupied.append(entry)
	if occupied.is_empty():
		return {"min": 0, "max": 0, "occupied": 0}
	var people_per := float(horse_workers) / float(occupied.size())
	var foal_min := 0
	var foal_max := 0
	var cap := float(GlobalUnits.HORSES_PER_FIELD)
	var need := float(GlobalUnits.PEOPLE_PER_HORSE_FIELD)
	for entry in occupied:
		var fill := clampf(float(entry["horses"]) / cap, 0.0, 1.0)
		var labor := clampf(people_per / need, 0.0, 1.0)
		var eff := fill * labor
		if eff >= GlobalUnits.FOAL_EFF_HIGH:
			foal_min += GlobalUnits.FOAL_HIGH_MIN
			foal_max += GlobalUnits.FOAL_HIGH_MAX
		elif eff >= GlobalUnits.FOAL_EFF_MID:
			foal_min += GlobalUnits.FOAL_MID_MIN
			foal_max += GlobalUnits.FOAL_MID_MAX
	return {"min": foal_min, "max": foal_max, "occupied": occupied.size()}


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


## Crafts for one smith after holding blacksmith labor is poured in list order.
func preview_blacksmith_building_output(player_id: int, building: Node) -> Dictionary:
	var empty := {
		"weapon": "",
		"crafts": 0,
		"workers": 0,
		"wood_cost": 0,
		"iron_cost": 0,
	}
	if building == null or not is_instance_valid(building):
		return empty
	if not building.has_method("is_blacksmith") or not building.is_blacksmith():
		return empty
	var wood_have := (
		get_player_material(player_id, "wood")
		+ get_labor_category(player_id, "wood") * GlobalUnits.ECONOMY_WOOD_PER_WORKER
	)
	var iron_have := (
		get_player_material(player_id, "iron")
		+ get_labor_category(player_id, "iron") * GlobalUnits.ECONOMY_IRON_PER_WORKER
	)
	var workers_raw := get_labor_category(player_id, "blacksmith")
	var workers := mini(workers_raw, economy_worker_cap(player_id, "blacksmith"))
	var workers_left := workers
	var wood_left := wood_have
	var iron_left := iron_have
	for b in get_economy_buildings_for(player_id, "blacksmith"):
		if workers_left <= 0:
			break
		var assigned := mini(workers_left, int(b.worker_cap()))
		workers_left -= assigned
		var wkey := str(b.get_craft_weapon()) if b.has_method("get_craft_weapon") else ""
		var n := 0
		var use_wood := 0
		var use_iron := 0
		if wkey != "" and wkey in GlobalUnits.BLACKSMITH_CRAFTABLE:
			var pp := GlobalUnits.blacksmith_people_per(wkey)
			var recipe: Dictionary = GlobalUnits.blacksmith_recipe(wkey)
			var by_labor := int(assigned / pp)
			var by_mat := _max_crafts_for_recipe(wood_left, iron_left, recipe)
			n = mini(by_labor, by_mat)
			use_wood = int(recipe.get("wood", 0)) * n
			use_iron = int(recipe.get("iron", 0)) * n
			wood_left -= use_wood
			iron_left -= use_iron
		if b == building:
			return {
				"weapon": wkey,
				"crafts": n,
				"workers": assigned,
				"wood_cost": use_wood,
				"iron_cost": use_iron,
			}
	return empty


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


## Settlement tax total (raw base + town/village tier %) for current pop / tax level.
func settlement_tax_due(settlement: Node, tax_level: int = -1) -> Dictionary:
	## {base, tier_frac, total}
	if settlement == null:
		return {"base": 0, "tier_frac": 0.0, "total": 0}
	if settlement.has_method("can_receive_ration_growth") and not settlement.can_receive_ration_growth():
		return {"base": 0, "tier_frac": 0.0, "total": 0}
	if tax_level < 0:
		var owner_pid := int(settlement.player_owner) if settlement.get("player_owner") != null else -1
		tax_level = get_holding_tax(owner_pid) if owner_pid >= 0 else GlobalUnits.TAX_DEFAULT
	var base := GlobalUnits.tax_marks_for_settlement(int(settlement.population), tax_level)
	var tier_frac := 0.0
	if settlement.has_method("settlement_marks_bonus_fraction"):
		tier_frac = float(settlement.settlement_marks_bonus_fraction())
	var total := GlobalUnits.tax_marks_with_tier_bonus(base, tier_frac)
	return {"base": base, "tier_frac": tier_frac, "total": total}


## Castle holding bonus on Σ raw tax bases. Requires de jure + owned operational castle.
func _castle_tax_bonus(player_id: int, raw_base_sum: int) -> int:
	if raw_base_sum <= 0 or not has_dejure(player_id):
		return 0
	var castle := get_castle_plot()
	if castle == null or castle.get("player_owner") == null:
		return 0
	if int(castle.player_owner) != player_id:
		return 0
	if not castle.has_method("is_operational") or not castle.is_operational():
		return 0
	if not castle.has_method("holding_marks_bonus_fraction"):
		return 0
	var frac := float(castle.holding_marks_bonus_fraction())
	if frac <= 0.0:
		return 0
	return int(floor(float(raw_base_sum) * frac))


func _add_player_marks(player_id: int, amount: int) -> void:
	if player_id < 0 or amount <= 0:
		return
	if base_map == null or base_map.get("players") == null:
		return
	var players: Dictionary = base_map.players
	if not players.has(player_id):
		return
	players[player_id].game_data["marks"] = int(players[player_id].game_data.get("marks", 0)) + amount


## Forecast next season tax: {total, wallet, coffer, castle_bonus, raw_base, auto_wallet}.
func _preview_holding_tax(player_id: int) -> Dictionary:
	var tax_level := get_holding_tax(player_id)
	var auto_wallet := has_dejure(player_id)
	var raw_base := 0
	var settlements_total := 0
	for s in get_owned_settlements(player_id):
		var due: Dictionary = settlement_tax_due(s, tax_level)
		raw_base += int(due.get("base", 0))
		settlements_total += int(due.get("total", 0))
	var castle_bonus := _castle_tax_bonus(player_id, raw_base) if auto_wallet else 0
	var total := settlements_total + castle_bonus
	return {
		"total": total,
		"wallet": total if auto_wallet else 0,
		"coffer": 0 if auto_wallet else settlements_total,
		"castle_bonus": castle_bonus,
		"raw_base": raw_base,
		"settlements_total": settlements_total,
		"auto_wallet": auto_wallet,
	}


func recalculate_settlements_growth() -> void:
	# Clear, then assign ration+tax forecast per holding (affordable ration level).
	# Over-cap forecast uses overflow pressure without random jitter.
	for settlement in settlements.get_children():
		if settlement.has_method("calculate_predicted_growth"):
			settlement.calculate_predicted_growth()
	for pid in get_holding_controllers():
		var info := preview_holding_rations(int(pid))
		var effective := int(info.get("effective", GlobalUnits.RATION.NORMAL))
		var tax_level := get_holding_tax(int(pid))
		var pop_frac := (
			GlobalUnits.ration_pop_fraction(effective) + GlobalUnits.tax_pop_fraction(tax_level)
		)
		for s in get_owned_settlements(int(pid)):
			if s.has_method("can_receive_ration_growth") and not s.can_receive_ration_growth():
				s.predicted_growth = 0
				continue
			var pop_now := int(s.population)
			var delta := GlobalUnits.population_delta_from_fraction(pop_now, pop_frac)
			var cap_jit: Vector2i = GlobalUnits.settlement_pop_cap_and_jitter(s)
			s.predicted_growth = GlobalUnits.settlement_overflow_adjusted_delta(
				pop_now, delta, int(cap_jit.x), 0, null
			)
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
	# Population changes are applied in tick_holding_rations (ration system).
	# predicted_growth is forecast-only for the UI.
	update_population_in_resources()


func recalculate_marks_will_by_player() -> void:
	# Forecast: next season tax (tier % included; castle bonus if de jure).
	var will_by_player: Dictionary = {}
	for pid in get_holding_controllers():
		var tax_level := get_holding_tax(int(pid))
		for s in get_owned_settlements(int(pid)):
			var due: Dictionary = settlement_tax_due(s, tax_level)
			s.predicted_marks = int(due.get("total", 0))
		var prev := _preview_holding_tax(int(pid))
		will_by_player[int(pid)] = int(prev.get("total", 0))
	var total := 0
	for pid in will_by_player:
		total += will_by_player[pid]
	will_by_player["all"] = total
	resources["marks"]["will"] = will_by_player


func _count_buildings_in_node(node: Node, control_player_id: int) -> Dictionary:
	var control := 0
	var all_count := 0
	for child in node.get_children():
		# Empty castle plots do not count as standing castles.
		if child.has_method("is_built") and not child.is_built():
			continue
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


## Dev/admin: split `amount` evenly across all settlements (may exceed tier caps; floor at 0).
func admin_add_population(amount: int) -> void:
	if amount == 0 or settlements == null:
		return
	var list: Array = []
	for s in settlements.get_children():
		if s.get("population") != null:
			list.append(s)
	var n := list.size()
	if n <= 0:
		return
	var remaining := amount
	for i in n:
		var s: Node = list[i]
		var share := remaining / (n - i)
		remaining -= share
		s.population = maxi(0, int(s.population) + share)
		if s.has_method("refresh_visual_stage"):
			s.refresh_visual_stage()
	update_population_in_resources()
	season_start_population = int(resources["population"]["has"].get("all", 0))
	var dej := int(dejure) if dejure != null else -1
	if dej >= 0:
		var season := 0
		if base_map != null and base_map.get("season") != null:
			season = int(base_map.season)
		clamp_all_labor(dej, season)


## Dev/admin dump: rations, grain, labor, pop, garrison for every holding controller.
func get_admin_report(players_dict: Dictionary = {}) -> String:
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	var lines: PackedStringArray = []
	lines.append("=== %s (%s) ===" % [str(p_name), String(name)])
	lines.append(
		"status=%s  dejure=%s  defacto=%s  player_owner=%s"
		% [
			get_status_name(),
			_player_name(players_dict, dejure),
			_player_name(players_dict, defacto) if defacto != NO_DEFACTO else "—",
			_player_name(players_dict, player_owner),
		]
	)
	lines.append(
		"season=%s  pop_all=%d  happiness_avg=%.1f"
		% [
			GlobalStuff.get_season_name(season) if GlobalStuff.has_method("get_season_name") else str(season),
			int(resources["population"]["has"].get("all", 0)) if resources != null else 0,
			average_settlement_happiness(-1),
		]
	)
	lines.append("")
	lines.append_array(_admin_troops_lines(players_dict))
	lines.append("")
	var pids: Array = get_holding_controllers()
	pids.sort()
	if pids.is_empty():
		lines.append("(no holding controllers)")
	for pid in pids:
		var ipid := int(pid)
		var pname := _player_name(players_dict, ipid)
		var ptype := "?"
		if players_dict.has(ipid):
			var pd = players_dict[ipid]
			if pd is Object and pd.get("type") != null:
				match int(pd.type):
					GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL:
						ptype = "HUMAN"
					GlobalStuff.PLAYER_TYPE.AI:
						ptype = "AI"
					GlobalStuff.PLAYER_TYPE.LOCAL_COUNCIL:
						ptype = "COUNCIL"
					_:
						ptype = str(pd.type)
		lines.append("--- holder %d %s [%s] ---" % [ipid, pname, ptype])
		var ration_info := preview_holding_rations(ipid)
		lines.append(
			"ration requested=%s  effective=%s  affordable=%s"
			% [
				GlobalUnits.ration_name(int(ration_info.get("requested", 0))),
				GlobalUnits.ration_name(int(ration_info.get("effective", 0))),
				str(bool(ration_info.get("affordable", false))),
			]
		)
		lines.append(
			"grain stock=%d  seed_reserve=%d  army_need=%d  people_budget=%d  civilian_need=%d (promised=%d)"
			% [
				int(ration_info.get("stock", 0)),
				int(ration_info.get("seed_reserve", 0)),
				int(ration_info.get("army_need", 0)),
				int(ration_info.get("available_for_people", 0)),
				int(ration_info.get("civilian_need", 0)),
				int(ration_info.get("promised_need", 0)),
			]
		)
		var tax_prev_admin := _preview_holding_tax(ipid)
		var wallet_face := int(tax_prev_admin.get("wallet", 0))
		var wallet_line := "tax next wallet=%d" % wallet_face
		if (
			wallet_face > 0
			and base_map != null
			and base_map.has_method("player_ai_early_boost_active")
			and base_map.player_ai_early_boost_active(ipid)
			and base_map.has_method("get_player_wallet_income_paid")
		):
			var wallet_real := int(base_map.get_player_wallet_income_paid(ipid, wallet_face))
			wallet_line += " (cheat real: %d)" % wallet_real
		lines.append(
			"tax=%s  holding_pop=%d  marks_treasury=%s  %s"
			% [
				GlobalUnits.tax_name(get_holding_tax(ipid)),
				owned_settlement_population(ipid),
				str(int(players_dict[ipid].game_data.get("marks", 0))) if players_dict.has(ipid) else "?",
				wallet_line,
			]
		)
		if (
			base_map != null
			and base_map.has_method("get_player_upkeep_preview")
			and base_map.has_method("get_player_upkeep_owed")
			and base_map.has_method("player_ai_early_boost_active")
			and base_map.player_ai_early_boost_active(ipid)
		):
			var up_face := int(base_map.get_player_upkeep_preview(ipid).get("total", 0))
			var up_real := int(base_map.get_player_upkeep_owed(ipid))
			if up_face != up_real:
				lines.append(
					"army upkeep projected=%d (cheat real: %d)" % [up_face, up_real]
				)
		var labor_bits: PackedStringArray = []
		for cat in GlobalUnits.LABOR_CATEGORIES:
			var n := get_labor_category(ipid, cat)
			if n > 0:
				labor_bits.append("%s=%d" % [cat, n])
		lines.append("labor: " + (", ".join(labor_bits) if not labor_bits.is_empty() else "(none)"))
		lines.append(
			"fields grain_planted=%d unsown=%d"
			% [count_planted_grain_fields(ipid), count_unsown_grain_fields(ipid)]
		)
		lines.append_array(admin_stock_lines(ipid))
		lines.append_array(admin_building_lines(ipid))
		# Per-settlement pop / happiness.
		for s in get_owned_settlements(ipid):
			var stype := "?"
			if s.get("type_") != null:
				match int(s.type_):
					GlobalStuff.BUILDING_TYPE.TOWN:
						stype = "town"
					GlobalStuff.BUILDING_TYPE.VILLAGE:
						stype = "village"
					_:
						stype = str(s.type_)
			lines.append(
				"  %s %s: pop=%d happy=%.0f"
				% [stype, String(s.name), int(s.population), float(s.get("happiness"))]
			)
		lines.append("")
	return "\n".join(lines)


## Full material + arms stock for one holding (admin / AI debug).
func admin_stock_lines(player_id: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	var mat_bits: PackedStringArray = []
	for k in GlobalUnits.MATERIAL_KEYS:
		mat_bits.append("%s=%d" % [k, get_player_material(player_id, k)])
	lines.append("materials: " + ", ".join(mat_bits))
	var w := get_weapons_for(player_id)
	var arm_bits: PackedStringArray = []
	for k in GlobalUnits.WEAPON_KEYS:
		arm_bits.append("%s=%d" % [k, int(w.get(k, 0))])
	lines.append("arms: " + ", ".join(arm_bits))
	return lines


## Castle works + economy pads + blacksmith craft preview for one holding.
func admin_building_lines(player_id: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	# Castle works are driven by de jure labor / materials.
	if int(dejure) == player_id:
		var castle = get_castle_plot()
		if castle == null:
			lines.append("castle: (no plot)")
		elif castle.has_method("construction_summary"):
			lines.append("castle: " + str(castle.construction_summary()))
		elif castle.has_method("is_under_construction") and castle.is_under_construction():
			lines.append("castle: under construction")
		elif castle.has_method("get_castle_type_name"):
			lines.append("castle: %s" % str(castle.get_castle_type_name()))

	var econ_bits: PackedStringArray = []
	if economy != null:
		var pads: Array = economy.get_children()
		pads.sort_custom(func(a, b): return String(a.name) < String(b.name))
		for b in pads:
			if b.get("type_") == null or int(b.type_) != GlobalStuff.BUILDING_TYPE.ECONOMY:
				continue
			if b.get("player_owner") == null or int(b.player_owner) != player_id:
				continue
			var label := str(b.name)
			if b.has_method("is_built") and b.is_built():
				if b.has_method("get_subtype_name"):
					var stage_n = b.get_stage_name() if b.has_method("get_stage_name") else "?"
					label = "%s (%s)" % [b.get_subtype_name(), stage_n]
				if b.has_method("is_blacksmith") and b.is_blacksmith() and b.has_method("get_craft_weapon"):
					var wkey := str(b.get_craft_weapon())
					if wkey != "":
						label += " → %s" % GlobalUnits.weapon_name(wkey)
			elif b.has_method("get_slot_description"):
				label = str(b.get_slot_description())
			else:
				label = "empty pad"
			econ_bits.append(label)
	if econ_bits.is_empty():
		lines.append("economy: (none owned)")
	else:
		lines.append("economy: " + "; ".join(econ_bits))

	var preview := preview_economy_output(player_id)
	var craft_w: Dictionary = preview.get("weapons", {})
	if GlobalUnits.weapon_stock_has_any(craft_w):
		lines.append(
			"crafting next season: %s (wood_cost=%d iron_cost=%d)"
			% [
				GlobalUnits.weapon_stock_summary(craft_w),
				int(preview.get("wood_cost", 0)),
				int(preview.get("iron_cost", 0)),
			]
		)
	elif get_labor_category(player_id, "blacksmith") > 0:
		var bottleneck := str(preview.get("blacksmith", {}).get("bottleneck", ""))
		if bottleneck != "":
			lines.append("crafting next season: (none) bottleneck=%s" % bottleneck)
		else:
			lines.append("crafting next season: (none)")
	return lines


func _admin_troops_lines(players_dict: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("--- troops in province ---")
	if base_map == null:
		lines.append("(no base_map)")
		return lines
	var any := false
	for container_name in ["settlements", "defense", "economy"]:
		var container = get_node_or_null(container_name)
		if container == null:
			continue
		var buildings: Array = container.get_children()
		buildings.sort_custom(func(a, b): return String(a.name) < String(b.name))
		for b in buildings:
			if not b.has_method("get_garrison_capacity"):
				continue
			var kind := _admin_building_kind(b)
			if b.get("type_") != null and int(b.type_) == GlobalStuff.BUILDING_TYPE.CASTLE:
				var inside: Array = base_map.get_building_garrison(b, GlobalUnits.SPOT.INSIDE) \
					if base_map.has_method("get_building_garrison") else []
				var outside: Array = base_map.get_building_garrison(b, GlobalUnits.SPOT.OUTSIDE) \
					if base_map.has_method("get_building_garrison") else []
				var in_n := GlobalUnits.total_men(inside)
				var out_n := GlobalUnits.total_men(outside)
				if in_n <= 0 and out_n <= 0:
					lines.append("  %s %s: empty" % [kind, String(b.name)])
				else:
					if in_n > 0:
						lines.append(
							"  %s %s inside: %d — %s"
							% [kind, String(b.name), in_n, _admin_units_summary(inside, players_dict)]
						)
					else:
						lines.append("  %s %s inside: 0" % [kind, String(b.name)])
					if out_n > 0:
						lines.append(
							"  %s %s outside: %d — %s"
							% [kind, String(b.name), out_n, _admin_units_summary(outside, players_dict)]
						)
					else:
						lines.append("  %s %s outside: 0" % [kind, String(b.name)])
				any = true
			else:
				var units: Array = base_map.get_all_building_garrison(b) \
					if base_map.has_method("get_all_building_garrison") else []
				var men := GlobalUnits.total_men(units)
				if men <= 0:
					lines.append("  %s %s: empty" % [kind, String(b.name)])
				else:
					lines.append(
						"  %s %s: %d — %s"
						% [kind, String(b.name), men, _admin_units_summary(units, players_dict)]
					)
				any = true
	# Mobile armies / fleets whose anchor cell is in this province.
	if base_map.get("forces") != null and base_map.has_method("province_under_force"):
		var fids: Array = base_map.forces.keys()
		fids.sort()
		for fid in fids:
			if base_map.has_method("force_is_garrison") and base_map.force_is_garrison(str(fid)):
				continue
			var under = base_map.province_under_force(str(fid))
			if under != self:
				continue
			var entry: Dictionary = base_map.forces[fid]
			var units2: Array = entry.get("units", [])
			var men2 := GlobalUnits.total_men(units2)
			if men2 <= 0:
				continue
			var ctrl := int(entry.get("controller", -1))
			if base_map.has_method("get_force_controller"):
				ctrl = int(base_map.get_force_controller(str(fid)))
			var ctrl_name := _player_name(players_dict, ctrl)
			lines.append(
				"  field %s (ctrl=%s): %d — %s"
				% [str(fid), ctrl_name, men2, _admin_units_summary(units2, players_dict)]
			)
			any = true
	if not any:
		lines.append("(no garrison capacity buildings / empty)")
	return lines


func _admin_building_kind(b: Node) -> String:
	if b.get("type_") == null:
		return "building"
	match int(b.type_):
		GlobalStuff.BUILDING_TYPE.TOWN:
			return "town"
		GlobalStuff.BUILDING_TYPE.VILLAGE:
			return "village"
		GlobalStuff.BUILDING_TYPE.CASTLE:
			return "castle"
		GlobalStuff.BUILDING_TYPE.ECONOMY:
			return "economy"
		_:
			return "building"


func _admin_units_summary(units: Array, players_dict: Dictionary) -> String:
	if units.is_empty():
		return "—"
	var by_type: Dictionary = {}
	var order: Array = []
	for s in units:
		if not GlobalUnits.is_fighting_stack(s):
			continue
		var t := int(s.get("type", -1))
		var n := int(s.get("count", 0))
		if n <= 0:
			continue
		if not by_type.has(t):
			by_type[t] = 0
			order.append(t)
		by_type[t] = int(by_type[t]) + n
	if order.is_empty():
		return GlobalUnits.describe_units(units).replace("\n", "; ")
	var bits: PackedStringArray = []
	for t in order:
		bits.append("%d %s" % [int(by_type[t]), GlobalUnits.unit_name(t)])
	# Note owners if mixed.
	var owners := GlobalUnits.owners_in(units)
	if owners.size() > 1:
		var onames: PackedStringArray = []
		for oid in owners:
			onames.append(_player_name(players_dict, int(oid)))
		bits.append("owners=[%s]" % ", ".join(onames))
	return ", ".join(bits)


func get_display_data(players_dict: Dictionary, viewer_id: int = NO_DEFACTO) -> Dictionary:
	var owner_name := _player_name(players_dict, player_owner)
	var defacto_name := _player_name(players_dict, defacto) if defacto != NO_DEFACTO else "—"
	var dejure_name := _player_name(players_dict, dejure)
	var counts = get_building_counts()
	var status_name := get_status_name_for_viewer(viewer_id)
	var viewer_has_dejure := viewer_id >= 0 and has_dejure(viewer_id)
	var marks_all: int = int(resources["marks"]["will"].get("all", 0))
	var weapons_copy: Dictionary = get_weapons_for(viewer_id).duplicate() if viewer_id >= 0 else get_weapons().duplicate()
	var season := 0
	if base_map != null and base_map.get("season") != null:
		season = int(base_map.season)
	var holding := {}
	var viewer_has_holding := viewer_id >= 0 and player_has_holding(viewer_id)
	if viewer_has_holding:
		holding = get_holding_summary(viewer_id, season)
	var marks_for_viewer := 0
	if viewer_has_holding:
		marks_for_viewer = int(holding.get("tax_marks_next", 0))
	elif viewer_has_dejure:
		marks_for_viewer = int(resources["marks"]["will"].get(viewer_id, 0))
	return {
		"name": p_name,
		"status": status_,
		"status_name": status_name,
		"owner_id": int(player_owner) if player_owner != null else -1,
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
		"happiness": average_settlement_happiness(viewer_id) if viewer_id >= 0 else average_settlement_happiness(),
		"season_start_population": season_start_population,
		"levied_this_season": levied_this_season,
		"levy_remaining": max_levy_remaining(),
		"weapons": weapons_copy,
		"owned_population": owned_settlement_population(viewer_id) if viewer_id >= 0 else 0,
		"holding": holding,
		"grain_stock": get_player_grain(viewer_id) if viewer_id >= 0 else 0,
		"ration": int(holding.get("ration", GlobalUnits.RATION_DEFAULT)) if viewer_has_holding else GlobalUnits.RATION_DEFAULT,
		"ration_effective": int(holding.get("ration_effective", GlobalUnits.RATION_DEFAULT)) if viewer_has_holding else GlobalUnits.RATION_DEFAULT,
		"ration_affordable": bool(holding.get("ration_affordable", true)) if viewer_has_holding else true,
		"tax": int(holding.get("tax", GlobalUnits.TAX_DEFAULT)) if viewer_has_holding else GlobalUnits.TAX_DEFAULT,
		"tax_marks_stored": int(holding.get("tax_marks_stored", 0)) if viewer_has_holding else 0,
		"tax_marks_next": int(holding.get("tax_marks_next", 0)) if viewer_has_holding else 0,
		"tax_marks_next_wallet": int(holding.get("tax_marks_next_wallet", 0)) if viewer_has_holding else 0,
		"tax_marks_next_coffer": int(holding.get("tax_marks_next_coffer", 0)) if viewer_has_holding else 0,
		"tax_castle_bonus_next": int(holding.get("tax_castle_bonus_next", 0)) if viewer_has_holding else 0,
		"tax_auto_wallet": bool(holding.get("tax_auto_wallet", false)) if viewer_has_holding else false,
	}
