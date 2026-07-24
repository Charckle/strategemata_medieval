extends RefCounted
class_name CouncilAI

## Seasonal local-council brain. Runs on the map host at season start.
## Scope: one province per LOCAL_COUNCIL — rations, grain, basic economy, town garrison.


static func tick_all(base_map: Node) -> void:
	if base_map == null or base_map.get("players") == null:
		return
	var players: Dictionary = base_map.players
	var pids: Array = players.keys()
	for pid in pids:
		if not players.has(pid):
			continue
		var p = players[pid]
		if p == null:
			continue
		if not GlobalStuff.is_local_council(p.type):
			continue
		var prov := _province_for_council(base_map, int(pid))
		if prov == null:
			continue
		tick_province(base_map, prov, int(pid))


static func tick_province(base_map: Node, prov: Node, pid: int) -> void:
	if base_map == null or prov == null or pid < 0:
		return
	if not prov.has_method("has_dejure") or not prov.has_dejure(pid):
		return

	var province_id := String(prov.name)
	# 1) Keep people fed at normal rations / tax.
	if base_map.has_method("apply_set_holding_ration"):
		base_map.apply_set_holding_ration(province_id, GlobalUnits.RATION_DEFAULT, pid)
	if base_map.has_method("apply_set_holding_tax"):
		base_map.apply_set_holding_tax(province_id, GlobalUnits.TAX_DEFAULT, pid)

	# 2) Plan grain on idle fields.
	if base_map.has_method("apply_populate_idle_fields"):
		base_map.apply_populate_idle_fields(province_id, 1, pid) # CROP.GRAIN

	# 3) Build woodcutter, iron mine (if deposit), then blacksmith.
	_try_build_open(base_map, prov, pid, 0) # WOODCUTTER
	_try_build_open(base_map, prov, pid, 1) # IRONMINE
	_try_build_open(base_map, prov, pid, 5) # BLACKSMITH

	# 4) Labor: grain, then wood/iron capped to craft needs, then smith if short.
	_assign_labor(base_map, prov, pid)

	# 5) Point smith at the weapon we need most, then reinforce town garrison.
	_set_craft_for_deficit(base_map, prov, pid)
	_reinforce_town_garrison(base_map, prov, pid)


static func _province_for_council(base_map: Node, pid: int) -> Node:
	if base_map.get("provinces") == null:
		return null
	for prov in base_map.provinces.get_children():
		if int(prov.get("player_owner")) == pid:
			return prov
		if prov.has_method("has_dejure") and prov.has_dejure(pid):
			return prov
	return null


static func has_iron_mine(prov: Node, pid: int) -> bool:
	if prov == null or not prov.has_method("economy_worker_cap"):
		return false
	return int(prov.economy_worker_cap(pid, "iron")) > 0


## Town garrison targets for this council (depends on built iron mine).
static func garrison_targets(prov: Node, pid: int) -> Dictionary:
	if has_iron_mine(prov, pid):
		return {
			GlobalUnits.UNIT_TYPE.MACEMEN: GlobalUnits.COUNCIL_TARGET_MACEMEN,
			GlobalUnits.UNIT_TYPE.PIKEMEN: GlobalUnits.COUNCIL_TARGET_PIKEMEN,
			GlobalUnits.UNIT_TYPE.ARCHER: GlobalUnits.COUNCIL_TARGET_ARCHERS,
		}
	return {
		GlobalUnits.UNIT_TYPE.MACEMEN: 0,
		GlobalUnits.UNIT_TYPE.PIKEMEN: 0,
		GlobalUnits.UNIT_TYPE.ARCHER: GlobalUnits.COUNCIL_TARGET_ARCHERS_NO_IRON,
	}


## Rebuild weapon stock floor (same counts as garrison targets).
static func weapon_stock_targets(prov: Node, pid: int) -> Dictionary:
	if has_iron_mine(prov, pid):
		return {
			"maces": GlobalUnits.COUNCIL_TARGET_MACEMEN,
			"pikes": GlobalUnits.COUNCIL_TARGET_PIKEMEN,
			"bows": GlobalUnits.COUNCIL_TARGET_ARCHERS,
		}
	return {
		"maces": 0,
		"pikes": 0,
		"bows": GlobalUnits.COUNCIL_TARGET_ARCHERS_NO_IRON,
	}


## Weapons still to forge: garrison gaps + stock floor (so wipe can be rebuilt).
static func weapon_craft_deficits(base_map: Node, prov: Node, pid: int) -> Dictionary:
	var out := {"maces": 0, "pikes": 0, "bows": 0}
	if prov == null:
		return out
	var g_want := garrison_targets(prov, pid)
	var s_want := weapon_stock_targets(prov, pid)
	var town = prov.get_town() if prov.has_method("get_town") else null
	var counts := _town_garrison_counts(base_map, town, pid)
	var stock: Dictionary = (
		prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else GlobalUnits.empty_weapon_stock()
	)
	var unit_to_wep := {
		GlobalUnits.UNIT_TYPE.MACEMEN: "maces",
		GlobalUnits.UNIT_TYPE.PIKEMEN: "pikes",
		GlobalUnits.UNIT_TYPE.ARCHER: "bows",
	}
	for ut in unit_to_wep:
		var wkey: String = unit_to_wep[ut]
		var g_gap := maxi(0, int(g_want.get(ut, 0)) - int(counts.get(ut, 0)))
		var s_gap := maxi(0, int(s_want.get(wkey, 0)) - int(stock.get(wkey, 0)))
		# Craft enough that after recruiting the garrison gap, stock floor remains.
		out[wkey] = g_gap + s_gap
	return out


static func _materials_for_weapon_deficits(deficits: Dictionary) -> Dictionary:
	var need := {"wood": 0, "iron": 0}
	for wkey in deficits:
		var n := int(deficits[wkey])
		if n <= 0:
			continue
		var recipe: Dictionary = GlobalUnits.blacksmith_recipe(str(wkey))
		need["wood"] = int(need["wood"]) + n * int(recipe.get("wood", 0))
		need["iron"] = int(need["iron"]) + n * int(recipe.get("iron", 0))
	return need


static func _try_build_open(base_map: Node, prov: Node, pid: int, subtype: int) -> bool:
	if prov.get("economy") == null:
		return false
	# Already have this subtype?
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if b.has_method("is_built") and b.is_built() and int(b.get("subtype")) == subtype:
			return false
	var plot: Node = null
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if not b.has_method("can_build") or not b.can_build(subtype):
			continue
		plot = b
		break
	if plot == null:
		return false
	var cost := int(plot.build_cost_for(subtype)) if plot.has_method("build_cost_for") else 0
	var marks := int(base_map.players[pid].game_data.get("marks", 0))
	if marks < cost:
		return false
	if base_map.has_method("apply_build_economy"):
		base_map.apply_build_economy(base_map._building_key(plot), subtype, pid, cost)
		return true
	return false


static func _assign_labor(base_map: Node, prov: Node, pid: int) -> void:
	var season := int(base_map.season) if base_map.get("season") != null else 0
	var province_id := String(prov.name)
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var grain_need := 0
	if prov.has_method("grain_labor_required"):
		grain_need = int(prov.grain_labor_required(pid, season))
	var grain_n := mini(grain_need, pop)
	var remaining := maxi(0, pop - grain_n)

	var craft := weapon_craft_deficits(base_map, prov, pid)
	var mat_need := _materials_for_weapon_deficits(craft)
	var have_wood := int(prov.get_player_material(pid, "wood")) if prov.has_method("get_player_material") else 0
	var have_iron := int(prov.get_player_material(pid, "iron")) if prov.has_method("get_player_material") else 0
	var wood_short := maxi(0, int(mat_need.get("wood", 0)) - have_wood)
	var iron_short := maxi(0, int(mat_need.get("iron", 0)) - have_iron)
	# 1 material per worker per season.
	var wood_want := int(ceil(float(wood_short) / float(maxi(1, GlobalUnits.ECONOMY_WOOD_PER_WORKER))))
	var iron_want := int(ceil(float(iron_short) / float(maxi(1, GlobalUnits.ECONOMY_IRON_PER_WORKER))))

	var wood_cap := int(prov.economy_worker_cap(pid, "wood")) if prov.has_method("economy_worker_cap") else 0
	var wood_n := mini(wood_cap, mini(remaining, wood_want))
	remaining = maxi(0, remaining - wood_n)

	var iron_cap := int(prov.economy_worker_cap(pid, "iron")) if prov.has_method("economy_worker_cap") else 0
	var iron_n := mini(iron_cap, mini(remaining, iron_want))
	remaining = maxi(0, remaining - iron_n)

	var smith_cap := int(prov.economy_worker_cap(pid, "blacksmith")) if prov.has_method("economy_worker_cap") else 0
	var craft_left := int(craft.get("maces", 0)) + int(craft.get("pikes", 0)) + int(craft.get("bows", 0))
	var smith_n := mini(smith_cap, remaining) if craft_left > 0 else 0

	# Clear all labor first so grain isn't squeezed by leftover assignments.
	if base_map.has_method("apply_set_holding_labor_category"):
		for cat in GlobalUnits.LABOR_CATEGORIES:
			base_map.apply_set_holding_labor_category(province_id, cat, 0, pid)
		base_map.apply_set_holding_labor_category(province_id, "grain", grain_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "wood", wood_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "iron", iron_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "blacksmith", smith_n, pid)
		return

	if not prov.has_method("set_labor_category"):
		return
	for cat in GlobalUnits.LABOR_CATEGORIES:
		prov.set_labor_category(pid, cat, 0, season)
	prov.set_labor_category(pid, "grain", grain_n, season)
	prov.set_labor_category(pid, "wood", wood_n, season)
	prov.set_labor_category(pid, "iron", iron_n, season)
	prov.set_labor_category(pid, "blacksmith", smith_n, season)


static func _set_craft_for_deficit(base_map: Node, prov: Node, pid: int) -> void:
	var deficits := weapon_craft_deficits(base_map, prov, pid)
	var best_key := "bows"
	var best_n := -1
	for k in deficits:
		if int(deficits[k]) > best_n:
			best_n = int(deficits[k])
			best_key = str(k)
	if best_n <= 0:
		return
	if prov.get("economy") == null:
		return
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		if int(b.get("subtype")) != 5: # BLACKSMITH
			continue
		if b.has_method("set_craft_weapon"):
			b.set_craft_weapon(best_key)
		elif b.get("craft_weapon") != null:
			b.craft_weapon = best_key


static func _town_garrison_counts(base_map: Node, town: Node, pid: int) -> Dictionary:
	var out := {
		GlobalUnits.UNIT_TYPE.MACEMEN: 0,
		GlobalUnits.UNIT_TYPE.PIKEMEN: 0,
		GlobalUnits.UNIT_TYPE.ARCHER: 0,
	}
	if town == null or base_map == null or not base_map.has_method("get_all_building_garrison"):
		return out
	for s in base_map.get_all_building_garrison(town):
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		var t := int(s.get("type", -1))
		if out.has(t):
			out[t] = int(out[t]) + int(s.get("count", 0))
	return out


## Recruit deficit into the town FLAT garrison (no field army).
static func _reinforce_town_garrison(base_map: Node, prov: Node, pid: int) -> void:
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town == null or base_map == null:
		return
	var counts := _town_garrison_counts(base_map, town, pid)
	var targets := garrison_targets(prov, pid)
	var want := {
		GlobalUnits.UNIT_TYPE.MACEMEN: maxi(
			0, int(targets.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)) - int(counts.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0))
		),
		GlobalUnits.UNIT_TYPE.PIKEMEN: maxi(
			0, int(targets.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(counts.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0))
		),
		GlobalUnits.UNIT_TYPE.ARCHER: maxi(
			0, int(targets.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(counts.get(GlobalUnits.UNIT_TYPE.ARCHER, 0))
		),
	}
	var composition: Array = []
	for t in want:
		var n := int(want[t])
		if n > 0:
			composition.append({"type": t, "count": n})
	var total := GlobalUnits.composition_total_men(composition)
	if total <= 0:
		return

	var cap := int(town.get_garrison_capacity()) if town.has_method("get_garrison_capacity") else 300
	var have_men := GlobalUnits.total_men(base_map.get_all_building_garrison(town))
	var room := maxi(0, cap - have_men)
	if room <= 0:
		return

	var levy_left := int(prov.max_levy_remaining()) if prov.has_method("max_levy_remaining") else total
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	# Keep enough people for grain labor; never levy the province empty.
	var grain_need := int(prov.grain_labor_required(pid, int(base_map.season))) if prov.has_method("grain_labor_required") else 0
	var pop_floor := maxi(grain_need, int(ceil(float(pop) * 0.5)))
	var levy_cap := maxi(0, pop - pop_floor)
	var allowed := mini(total, mini(room, mini(levy_left, levy_cap)))
	if allowed <= 0:
		return

	# Shrink composition to `allowed`, preferring equal progress toward targets.
	composition = _trim_composition(composition, allowed)
	if GlobalUnits.composition_total_men(composition) <= 0:
		return

	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if not prov.can_afford_weapons_for(pid, need):
		composition = _trim_to_weapons(prov, pid, composition)
		if GlobalUnits.composition_total_men(composition) <= 0:
			return
		need = GlobalUnits.weapons_needed_for_composition(composition)

	var men := GlobalUnits.composition_total_men(composition)
	if men <= 0:
		return

	# Don't levy if it would force civilian rations below Normal this season.
	if prov.has_method("preview_holding_rations"):
		var preview: Dictionary = prov.preview_holding_rations(pid)
		var stock := int(preview.get("stock", 0))
		var seed_r := int(preview.get("seed_reserve", 0))
		var army_need := int(preview.get("army_need", 0)) + GlobalUnits.force_grain_need(men, true)
		var civ_pop := maxi(0, pop - men)
		var people_budget := maxi(0, stock - seed_r - army_need)
		if GlobalUnits.affordable_ration(civ_pop, GlobalUnits.RATION_DEFAULT, people_budget) < GlobalUnits.RATION_DEFAULT:
			return

	prov.subtract_weapons_for(pid, need)
	if not prov.deduct_population(pid, men):
		prov.add_weapons_for(pid, need)
		return
	var prev_levied := int(prov.levied_this_season)
	prov.levied_this_season = prev_levied + men
	if prov.has_method("apply_levy_happiness"):
		prov.apply_levy_happiness(prev_levied, prov.levied_this_season)

	var fid := ""
	if base_map.has_method("_ensure_flat_garrison_force"):
		fid = base_map._ensure_flat_garrison_force(town)
	if fid == "" or not base_map.forces.has(fid):
		return
	var units: Array = base_map.forces[fid]["units"]
	for entry in composition:
		var cnt := int(entry.get("count", 0))
		if cnt <= 0:
			continue
		GlobalUnits.add_stack(
			units,
			GlobalUnits.make_stack(
				int(entry.get("type")),
				pid,
				GlobalUnits.SOURCE.LEVY,
				cnt
			)
		)
	base_map.forces[fid]["units"] = units
	base_map.forces[fid]["controller"] = pid
	if town.has_method("set_flags"):
		town.set_flags()
	if base_map.has_method("update_players_population"):
		base_map.update_players_population()


static func _trim_composition(composition: Array, max_men: int) -> Array:
	var total := GlobalUnits.composition_total_men(composition)
	if total <= max_men or max_men <= 0:
		return composition if max_men > 0 else []
	# Round-robin so macemen/pikemen/archers stay balanced.
	var bags: Dictionary = {}
	var order: Array = []
	for e in composition:
		var t := int(e.get("type"))
		if not bags.has(t):
			bags[t] = 0
			order.append(t)
		bags[t] = int(bags[t]) + int(e.get("count", 0))
	var taken: Dictionary = {}
	for t in order:
		taken[t] = 0
	var left := max_men
	while left > 0:
		var progressed := false
		for t in order:
			if left <= 0:
				break
			if int(taken[t]) >= int(bags[t]):
				continue
			taken[t] = int(taken[t]) + 1
			left -= 1
			progressed = true
		if not progressed:
			break
	var out: Array = []
	for t in order:
		if int(taken[t]) > 0:
			out.append({"type": t, "count": int(taken[t])})
	return out


static func _trim_to_weapons(prov: Node, pid: int, composition: Array) -> Array:
	var out: Array = []
	for entry in composition:
		var t := int(entry.get("type"))
		var want := int(entry.get("count", 0))
		if want <= 0:
			continue
		var recipe: Dictionary = GlobalUnits.UNIT_WEAPON_COST.get(t, {})
		var can := want
		for wkey in recipe:
			var need_each := int(recipe[wkey])
			if need_each <= 0:
				continue
			var have := int(prov.get_weapons_for(pid).get(wkey, 0)) if prov.has_method("get_weapons_for") else 0
			can = mini(can, int(floor(float(have) / float(need_each))))
		if can > 0:
			out.append({"type": t, "count": can})
	return out
