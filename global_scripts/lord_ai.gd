extends RefCounted
class_name LordAI

## Seasonal AI-lord brain (host, season start). Councils stay on CouncilAI.
##
## Doctrine (`players[pid].game_data["ai_doctrine"]`):
##   "defense" (default) — Quad rations + stable tax, Concentric castle, garrisons.
##     Villages/economy fill only after Concentric. Always runs on every holding.
##   Knight conquest (automatic) — when every holding is fully fortified, raise/reuse a
##     knight field army (1.3× weakest adjacent council town), grain trip+4, capture,
##     leave knights in the field, fortify the new province (caravan arms), repeat.
##   "offense" — legacy Pass 1/2a (dormant unless doctrine forced); prefer knight conquest.

const THREAT_STRAIGHT_FILTER := 20
const WAR_STRENGTH_MARGIN := 1.3
const WAR_RETARGET_WAIT_SEASONS := 2
const WAR_DRIP_MEN_CAP := 80
const AI_WAR_KEY := "ai_war"
const AI_KNIGHT_WAR_KEY := "ai_knight_war"
const AI_DOCTRINE_KEY := "ai_doctrine"
const DOCTRINE_DEFENSE := "defense"
const DOCTRINE_OFFENSE := "offense"
## Highest CASTLE_TYPE (Concentric).
const DEFENSE_CASTLE_MAX := 5
## Concentric (5): unlock village + economy garrison fill / craft / weapon buys.
const DEFENSE_EXPAND_GARRISON_MIN := 5
## Max men levied into non-castle slots per season (castle fills without drip).
const DEFENSE_DRIP_OTHER := 25
## Happiness below this → ease tax for recovery (with Quad prefer Harsh at cap).
const DEFENSE_HAPPY_RECOVER_BELOW := 95.0
## Iron stock floor before buying from merchant for smithing.
const DEFENSE_IRON_BUY_FLOOR := 3
## Knight conquest: strength vs town defense; max knights levied per season.
const KNIGHT_STRENGTH_MARGIN := 1.3
const KNIGHT_LEVY_DRIP := 40
const AI_DEBUG_BUYS_KEY := "ai_debug_buys"


static func tick_all(base_map: Node) -> void:
	if base_map == null or base_map.get("players") == null:
		return
	var players: Dictionary = base_map.players
	# Snapshot — conquering a council erases that player mid-tick.
	var pids: Array = players.keys()
	for pid in pids:
		if not players.has(pid):
			continue
		var p = players[pid]
		if p == null:
			continue
		if not GlobalStuff.is_ai_lord(p.type):
			continue
		if int(p.status) != int(GlobalStuff.PLAYER_STATUS.PLAYING):
			continue
		_ensure_doctrine(base_map, int(pid))
		var holdings := _provinces_for_lord(base_map, int(pid))
		# Defense policy on every dejure holding; knight conquest when ready.
		for prov in holdings:
			tick_province_defense(base_map, prov, int(pid))
		tick_knight_conquest(base_map, int(pid), holdings)


static func _ensure_doctrine(base_map: Node, pid: int) -> void:
	if not base_map.players.has(pid):
		return
	var gd: Dictionary = base_map.players[pid].game_data
	if not gd.has(AI_DOCTRINE_KEY) or str(gd.get(AI_DOCTRINE_KEY, "")) == "":
		gd[AI_DOCTRINE_KEY] = DOCTRINE_DEFENSE


static func _doctrine(base_map: Node, pid: int) -> String:
	_ensure_doctrine(base_map, pid)
	var raw := str(base_map.players[pid].game_data.get(AI_DOCTRINE_KEY, DOCTRINE_DEFENSE))
	if raw == DOCTRINE_OFFENSE:
		return DOCTRINE_OFFENSE
	return DOCTRINE_DEFENSE


# =============================================================================
# Defense doctrine
# =============================================================================


static func tick_province_defense(base_map: Node, prov: Node, pid: int) -> void:
	if base_map == null or prov == null or pid < 0:
		return
	if not prov.has_method("has_dejure") or not prov.has_dejure(pid):
		return

	var province_id := String(prov.name)
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	var next_castle := _defense_next_castle_level(castle)
	var mat_short: Dictionary = _defense_castle_mat_shortfall(prov, pid, castle, next_castle)
	var need_castle_mats := (
		int(mat_short.get("wood", 0)) > 0 or int(mat_short.get("stone", 0)) > 0
	)
	_clear_debug_buys(base_map, pid, province_id)

	# 1) Food — Quadruple when affordable; tax paired for stable ~100 happiness.
	_set_defense_rations_and_tax(base_map, prov, pid)
	if base_map.has_method("apply_populate_idle_fields"):
		base_map.apply_populate_idle_fields(province_id, 1, pid)

	# 2) Economy pads.
	CouncilAI._try_build_open(base_map, prov, pid, 0) # WOODCUTTER
	CouncilAI._try_build_open(base_map, prov, pid, 5) # BLACKSMITH
	_try_build_deposit(base_map, prov, pid)

	# 3) Labor — grain first, then castle project / wood+stone, smith last.
	_assign_labor_defense(base_map, prov, pid, castle, need_castle_mats)

	# 4) Merchant: castle mats first, then iron/weapons, then grain for Quad.
	_try_buy_defense_castle_mats(base_map, prov, pid, mat_short)
	mat_short = _defense_castle_mat_shortfall(prov, pid, castle, next_castle)
	need_castle_mats = (
		int(mat_short.get("wood", 0)) > 0 or int(mat_short.get("stone", 0)) > 0
	)
	_set_craft_for_defense(base_map, prov, pid, need_castle_mats)
	_try_buy_defense_iron(base_map, prov, pid, mat_short)
	if not need_castle_mats:
		_try_buy_defense_weapons(base_map, prov, pid)
	_try_buy_defense_grain(base_map, prov, pid, mat_short)
	# Grain buy may unlock Quadruple — re-pair tax.
	_set_defense_rations_and_tax(base_map, prov, pid)

	# 5) Troop logistics — always absorb field stacks before any levy/upgrade.
	var keep_fid := _knight_force_id(base_map, pid)
	var starting_upgrade := _defense_can_start_castle_upgrade(
		base_map, prov, pid, castle, next_castle
	)

	_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
	_defense_redistribute_into_castle(base_map, prov, pid)
	_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)

	if starting_upgrade:
		# Free town/village room, start project — do NOT levy into the castle this season
		# (it would just get expelled again).
		_defense_evacuate_castle_for_upgrade(base_map, prov, pid, castle)
		_try_advance_castle(base_map, prov, pid, castle, next_castle)
		# Expel remnant (if any) → park again → disband whatever still can't fit.
		_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
		_defense_disband_unparked_field(base_map, pid, prov, keep_fid)
	else:
		_defense_fill_all_garrisons(base_map, prov, pid, false)
		# Mid-build: keep parking strays into town/villages.
		if castle != null and castle.has_method("is_under_construction") \
				and bool(castle.is_under_construction()):
			_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
		_defense_disband_unparked_field(base_map, pid, prov, keep_fid)

	_set_defense_rations_and_tax(base_map, prov, pid)


## Next CASTLE_TYPE to build (standing + 1), or -1 if at max / no plot.
static func _defense_next_castle_level(castle: Node) -> int:
	if castle == null:
		return -1
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		var pt := int(castle.get("project_target")) if castle.get("project_target") != null else -1
		return pt if pt >= 0 else -1
	var standing := int(castle.standing_level()) if castle.has_method("standing_level") else GlobalUnits.CASTLE_TARGET_EMPTY
	if standing < 0:
		return 0 # WOODEN_FORT
	if standing >= DEFENSE_CASTLE_MAX:
		return standing
	return standing + 1


## Target headcount mix for a full garrison of `cap` men.
static func _defense_mix_counts(cap: int) -> Dictionary:
	cap = maxi(0, cap)
	var archers := int(floor(float(cap) * 0.5))
	var swords := int(floor(float(cap) * 0.25))
	var pikes := maxi(0, cap - archers - swords)
	return {
		GlobalUnits.UNIT_TYPE.ARCHER: archers,
		GlobalUnits.UNIT_TYPE.SWORDSMEN: swords,
		GlobalUnits.UNIT_TYPE.PIKEMEN: pikes,
	}


static func _defense_garrison_slots(prov: Node) -> Array:
	var out: Array = []
	if prov == null:
		return out
	# Castle first — always keep at full capacity (post-siege refill).
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		out.append({"b": castle, "spot": GlobalUnits.SPOT.INSIDE, "prio": "castle"})
		out.append({"b": castle, "spot": GlobalUnits.SPOT.OUTSIDE, "prio": "castle"})
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		out.append({"b": town, "spot": GlobalUnits.SPOT.FLAT, "prio": "town"})
	if prov.get("settlements") != null:
		for s in prov.settlements.get_children():
			if s == town:
				continue
			if int(s.get("type_")) == int(GlobalStuff.BUILDING_TYPE.VILLAGE):
				out.append({"b": s, "spot": GlobalUnits.SPOT.FLAT, "prio": "village"})
	if prov.get("economy") != null:
		for b in prov.economy.get_children():
			out.append({"b": b, "spot": GlobalUnits.SPOT.FLAT, "prio": "economy"})
	return out


## Village + economy garrisons unlock once Concentric (lvl 5) is standing.
static func _defense_peripheral_unlocked(prov: Node) -> bool:
	var castle = prov.get_castle_plot() if prov != null and prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("standing_level"):
		return false
	return int(castle.standing_level()) >= DEFENSE_EXPAND_GARRISON_MIN


static func _defense_slots_for_pid(prov: Node, pid: int) -> Array:
	var out: Array = []
	for slot in _defense_garrison_slots(prov):
		var b = slot["b"]
		if b == null:
			continue
		if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.ECONOMY):
			if int(b.get("player_owner")) != pid:
				continue
			if b.has_method("is_built") and not b.is_built():
				continue
		out.append(slot)
	return out


## Slots the defense AI is currently filling (castle+town; +village/economy after Concentric).
static func _defense_active_slots_for_pid(prov: Node, pid: int) -> Array:
	var unlocked := _defense_peripheral_unlocked(prov)
	var out: Array = []
	for slot in _defense_slots_for_pid(prov, pid):
		var prio := str(slot.get("prio", ""))
		if prio == "village" or prio == "economy":
			if not unlocked:
				continue
		out.append(slot)
	return out


static func _spot_fighting_counts(base_map: Node, building: Node, spot: int, pid: int) -> Dictionary:
	var out := {
		GlobalUnits.UNIT_TYPE.ARCHER: 0,
		GlobalUnits.UNIT_TYPE.SWORDSMEN: 0,
		GlobalUnits.UNIT_TYPE.PIKEMEN: 0,
	}
	if base_map == null or not base_map.has_method("get_building_garrison"):
		return out
	for s in base_map.get_building_garrison(building, spot):
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		var t := int(s.get("type", -1))
		if out.has(t):
			out[t] = int(out[t]) + int(s.get("count", 0))
	return out


static func _set_craft_for_defense(
	base_map: Node, prov: Node, pid: int, reserve_wood_for_castle: bool
) -> void:
	if prov.get("economy") == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	# Only holes on slots we are actively filling.
	var need_bows := 0
	var need_swords := 0
	var need_pikes := 0
	for slot in _defense_active_slots_for_pid(prov, pid):
		var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
		var mix: Dictionary = _defense_mix_counts(cap)
		var have: Dictionary = _spot_fighting_counts(base_map, slot["b"], int(slot["spot"]), pid)
		need_bows += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)))
		need_swords += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)))
		need_pikes += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)))
	need_bows = maxi(0, need_bows - int(stock.get("bows", 0)))
	need_swords = maxi(0, need_swords - int(stock.get("swords", 0)))
	need_pikes = maxi(0, need_pikes - int(stock.get("pikes", 0)))
	if reserve_wood_for_castle:
		need_bows = 0
	var holes := {"bows": need_bows, "swords": need_swords, "pikes": need_pikes}
	var best_key := ""
	var best_n := 0
	for k in holes:
		if int(holes[k]) > best_n:
			best_n = int(holes[k])
			best_key = k
	if best_n <= 0 or best_key == "":
		return
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		if int(b.get("subtype")) != 5:
			continue
		if b.has_method("set_craft_weapon"):
			b.set_craft_weapon(best_key)
		elif b.get("craft_weapon") != null:
			b.craft_weapon = best_key


static func _defense_fill_all_garrisons(
	base_map: Node, prov: Node, pid: int, castle_only: bool = false
) -> void:
	# Never levy while unparked field troops could still fill holes.
	var keep_fid := _knight_force_id(base_map, pid)
	_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
	if _defense_has_stray_field(base_map, pid, prov, keep_fid):
		# Room is full everywhere we can park — don't add more mouths.
		return
	if _defense_grain_headroom_men(base_map, prov, pid) <= 0:
		return
	for slot in _defense_active_slots_for_pid(prov, pid):
		if castle_only and str(slot.get("prio", "")) != "castle":
			continue
		var drip := -1
		if str(slot.get("prio", "other")) != "castle":
			drip = DEFENSE_DRIP_OTHER
		_defense_fill_spot(base_map, prov, pid, slot["b"], int(slot["spot"]), drip)
		# After each slot, pull any new strays (shouldn't create any) and stop if blocked.
		_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)


## True when mats are ready and we would start a new castle project this season.
static func _defense_can_start_castle_upgrade(
	base_map: Node, prov: Node, pid: int, castle: Node, target_level: int
) -> bool:
	if castle == null or target_level < 0:
		return false
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		return false
	var standing := int(castle.standing_level()) if castle.has_method("standing_level") else GlobalUnits.CASTLE_TARGET_EMPTY
	if standing >= target_level:
		return false
	if not castle.has_method("preview_retarget"):
		return false
	var preview: Dictionary = castle.preview_retarget(target_level)
	if preview.is_empty():
		return false
	var pay: Dictionary = preview.get("pay", {})
	for key in ["wood", "stone"]:
		var need := int(pay.get(key, 0))
		if need > 0 and prov.get_player_material(pid, key) < need:
			return false
	return base_map != null and base_map.has_method("apply_retarget_castle")


## Extra garrison men we can raise while still affording Quad for civilians.
static func _defense_grain_headroom_men(base_map: Node, prov: Node, pid: int) -> int:
	if prov == null or not prov.has_method("preview_holding_rations"):
		return 999999
	var preview: Dictionary = prov.preview_holding_rations(pid)
	var pop := int(preview.get("population", 0))
	var stock := int(preview.get("stock", 0))
	var seed_r := int(preview.get("seed_reserve", 0))
	var army_need := int(preview.get("army_need", 0))
	var quad_need := GlobalUnits.ration_grain_need(pop, GlobalUnits.RATION.QUADRUPLE)
	var max_army_grain := maxi(0, stock - seed_r - quad_need)
	var extra_grain := maxi(0, max_army_grain - army_need)
	var per := float(GlobalUnits.FOOD_GRAIN_PER_MAN_GARRISON)
	if per <= 0.0:
		return 999999
	return int(floor(float(extra_grain) / per))


static func _defense_has_stray_field(
	base_map: Node, pid: int, prov: Node, keep_fid: String
) -> bool:
	if base_map.get("armies") == null:
		return false
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if fid == keep_fid or not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(fid) != prov:
			continue
		if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) > 0:
			return true
	return false


## Move town/village troops back into castle after an upgrade finishes.
static func _defense_redistribute_into_castle(base_map: Node, prov: Node, pid: int) -> void:
	if base_map == null or prov == null:
		return
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("is_operational") or not castle.is_operational():
		return
	if not base_map.has_method("apply_transfer_units"):
		return
	var sources: Array = []
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		sources.append({"b": town, "spot": GlobalUnits.SPOT.FLAT})
	if prov.get("settlements") != null:
		for s in prov.settlements.get_children():
			if s == town:
				continue
			if int(s.get("type_")) == int(GlobalStuff.BUILDING_TYPE.VILLAGE):
				sources.append({"b": s, "spot": GlobalUnits.SPOT.FLAT})
	for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
		var room := _garrison_room(base_map, castle, spot)
		if room <= 0:
			continue
		var dest_gid := _ensure_spot_garrison(base_map, castle, spot)
		if dest_gid == "":
			continue
		for src in sources:
			room = _garrison_room(base_map, castle, spot)
			if room <= 0:
				break
			var src_gid := _ensure_spot_garrison(base_map, src["b"], int(src["spot"]))
			if src_gid == "" or not base_map.forces.has(src_gid):
				continue
			var src_men := GlobalUnits.total_men(base_map.forces[src_gid].get("units", []))
			if src_men <= 0:
				continue
			var take_n := mini(room, src_men)
			if src_men - take_n > 0 and src_men - take_n < GlobalUnits.MIN_SPLIT_MEN:
				if room >= src_men:
					take_n = src_men
				else:
					take_n = maxi(0, src_men - GlobalUnits.MIN_SPLIT_MEN)
			if take_n <= 0:
				continue
			var out_units := _extract_any_stacks(
				base_map.forces[src_gid].get("units", []), pid, take_n
			)
			if out_units.is_empty():
				continue
			base_map.apply_transfer_units(src_gid, dest_gid, out_units, {})


## Disband leftover non-knight field stacks that could not be parked into any garrison.
static func _defense_disband_unparked_field(
	base_map: Node, pid: int, prov: Node, keep_fid: String
) -> void:
	if base_map.get("armies") == null or not base_map.has_method("request_disband_force"):
		return
	# One more absorb pass in case room opened.
	_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
	var to_cut: Array = []
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if fid == keep_fid or not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(fid) != prov:
			continue
		if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) <= 0:
			continue
		to_cut.append(fid)
	for fid in to_cut:
		if base_map.forces.has(fid):
			base_map.request_disband_force(fid)


## Legacy name — grain-crisis cull now always disbands unparked field.
static func _defense_cull_surplus_field(
	base_map: Node, pid: int, prov: Node, keep_fid: String
) -> void:
	_defense_disband_unparked_field(base_map, pid, prov, keep_fid)


static func _defense_fill_spot(
	base_map: Node,
	prov: Node,
	pid: int,
	building: Node,
	spot: int,
	drip_cap: int = -1
) -> void:
	if building == null or not building.has_method("get_garrison_capacity"):
		return
	var cap := int(building.get_garrison_capacity(spot))
	if cap <= 0:
		return
	var have_men := GlobalUnits.total_men(base_map.get_building_garrison(building, spot))
	var room := maxi(0, cap - have_men)
	if room <= 0:
		return
	if drip_cap >= 0:
		room = mini(room, drip_cap)
		if room <= 0:
			return
	var mix: Dictionary = _defense_mix_counts(cap)
	var have: Dictionary = _spot_fighting_counts(base_map, building, spot, pid)
	var want_comp: Array = []
	# Fill holes in archer → swords → pike order so 50% bias lands first.
	for t in [
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.SWORDSMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
	]:
		var short := maxi(0, int(mix.get(t, 0)) - int(have.get(t, 0)))
		if short > 0:
			want_comp.append({"type": t, "count": short})
	if want_comp.is_empty():
		return

	var total := GlobalUnits.composition_total_men(want_comp)
	var levy_left := int(prov.max_levy_remaining()) if prov.has_method("max_levy_remaining") else total
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var grain_need := int(prov.grain_labor_required(pid, int(base_map.season))) if prov.has_method("grain_labor_required") else 0
	var levy_cap := maxi(0, pop - grain_need)
	var happy_cap := _happiness_levy_budget(prov, pid)
	var allowed := mini(total, mini(room, mini(levy_left, mini(levy_cap, happy_cap))))
	if allowed <= 0:
		return

	want_comp = CouncilAI._trim_composition(want_comp, allowed)
	if GlobalUnits.composition_total_men(want_comp) <= 0:
		return
	var need := GlobalUnits.weapons_needed_for_composition(want_comp)
	if not prov.can_afford_weapons_for(pid, need):
		want_comp = CouncilAI._trim_to_weapons(prov, pid, want_comp)
		if GlobalUnits.composition_total_men(want_comp) <= 0:
			return
		need = GlobalUnits.weapons_needed_for_composition(want_comp)

	var men := GlobalUnits.composition_total_men(want_comp)
	if men <= 0:
		return
	# Never levy past what still leaves Quad affordable for civilians.
	var headroom := _defense_grain_headroom_men(base_map, prov, pid)
	if headroom <= 0:
		return
	if men > headroom:
		want_comp = CouncilAI._trim_composition(want_comp, headroom)
		men = GlobalUnits.composition_total_men(want_comp)
		if men <= 0:
			return
		need = GlobalUnits.weapons_needed_for_composition(want_comp)
		if not prov.can_afford_weapons_for(pid, need):
			want_comp = CouncilAI._trim_to_weapons(prov, pid, want_comp)
			men = GlobalUnits.composition_total_men(want_comp)
			if men <= 0:
				return
			need = GlobalUnits.weapons_needed_for_composition(want_comp)

	prov.subtract_weapons_for(pid, need)
	if not _add_units_to_garrison(base_map, prov, pid, building, spot, want_comp):
		prov.add_weapons_for(pid, need)


# =============================================================================
# Knight conquest (automatic after all holdings fully fortified)
# =============================================================================


static func _knight_war_state(base_map: Node, pid: int) -> Dictionary:
	if not base_map.players.has(pid):
		return {}
	var gd: Dictionary = base_map.players[pid].game_data
	if not gd.has(AI_KNIGHT_WAR_KEY) or typeof(gd[AI_KNIGHT_WAR_KEY]) != TYPE_DICTIONARY:
		gd[AI_KNIGHT_WAR_KEY] = {
			"target_province_id": "",
			"staging_province_id": "",
			"force_id": "",
			"marching": false,
			"halt_reason": "",
		}
	return gd[AI_KNIGHT_WAR_KEY]


static func _set_knight_war_state(base_map: Node, pid: int, war: Dictionary) -> void:
	if not base_map.players.has(pid):
		return
	base_map.players[pid].game_data[AI_KNIGHT_WAR_KEY] = war


static func _knight_force_id(base_map: Node, pid: int) -> String:
	var war: Dictionary = _knight_war_state(base_map, pid)
	var fid := str(war.get("force_id", ""))
	if fid != "" and base_map.forces.has(fid):
		return fid
	return ""


## Concentric standing + active slots full (or grain-capped so we can't fill more),
## and no stray non-knight field armies left from castle expels.
static func _province_defense_complete(base_map: Node, prov: Node, pid: int) -> bool:
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(pid):
		return false
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("standing_level"):
		return false
	if int(castle.standing_level()) < DEFENSE_CASTLE_MAX:
		return false
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		return false
	if _defense_has_stray_field(base_map, pid, prov, _knight_force_id(base_map, pid)):
		return false
	var headroom := _defense_grain_headroom_men(base_map, prov, pid)
	for slot in _defense_active_slots_for_pid(prov, pid):
		var b = slot["b"]
		var spot := int(slot["spot"])
		var cap := int(b.get_garrison_capacity(spot)) if b.has_method("get_garrison_capacity") else 0
		var have := GlobalUnits.total_men(base_map.get_building_garrison(b, spot))
		if have < cap and headroom > 0:
			return false
	return true


static func _all_holdings_defense_complete(base_map: Node, pid: int, holdings: Array) -> bool:
	if holdings.is_empty():
		return false
	for prov in holdings:
		if not _province_defense_complete(base_map, prov, pid):
			return false
	return true


static func tick_knight_conquest(base_map: Node, pid: int, holdings: Array) -> void:
	if base_map == null or pid < 0 or holdings.is_empty():
		return
	var war: Dictionary = _knight_war_state(base_map, pid)
	# Validate / rediscover knight force.
	var fid := str(war.get("force_id", ""))
	if fid != "" and not base_map.forces.has(fid):
		fid = ""
		war["force_id"] = ""
	if fid == "":
		fid = _find_knight_field_army(base_map, pid)
		if fid != "":
			war["force_id"] = fid

	# Always ship arms toward incomplete holdings.
	_knight_caravan_supply_arms(base_map, pid, holdings)

	var all_done := _all_holdings_defense_complete(base_map, pid, holdings)
	if not all_done:
		# Wait / fortify — park in place; only pull strays onto the knight stack.
		if fid == "":
			fid = _find_knight_field_army(base_map, pid)
			if fid == "":
				fid = _find_field_army(base_map, pid)
		if fid != "":
			fid = _merge_all_field_into_force(base_map, pid, fid)
			war["force_id"] = fid
		_set_knight_war_state(base_map, pid, war)
		return

	# Pick or keep a council target on our border.
	var target_id := str(war.get("target_province_id", ""))
	var target_prov = null
	if target_id != "" and base_map.has_method("_get_province_by_id"):
		target_prov = base_map._get_province_by_id(target_id)
	if target_prov == null or not _is_valid_council_target(base_map, target_prov):
		var pick: Dictionary = _pick_council_target(base_map, pid, holdings)
		if pick.is_empty():
			war["target_province_id"] = ""
			war["staging_province_id"] = ""
			war["marching"] = false
			war["halt_reason"] = "no council target on border"
			_set_knight_war_state(base_map, pid, war)
			return
		war["target_province_id"] = str(pick.get("province_id", ""))
		war["staging_province_id"] = str(pick.get("staging_id", ""))
		war["marching"] = false
		war["halt_reason"] = ""
		target_id = str(war["target_province_id"])
		target_prov = base_map._get_province_by_id(target_id) if base_map.has_method("_get_province_by_id") else null

	# Prefer staging where the knight army already sits (if owned).
	if fid != "" and base_map.has_method("province_under_force"):
		var under = base_map.province_under_force(fid)
		if under != null and under.has_method("has_dejure") and under.has_dejure(pid):
			war["staging_province_id"] = String(under.name)
	if str(war.get("staging_province_id", "")) == "":
		var pick2: Dictionary = _pick_council_target(base_map, pid, holdings)
		war["staging_province_id"] = str(pick2.get("staging_id", String(holdings[0].name)))

	_execute_knight_war_season(base_map, pid, war, holdings)
	_set_knight_war_state(base_map, pid, war)


static func _find_knight_field_army(base_map: Node, pid: int) -> String:
	if base_map.get("armies") == null or base_map.get("forces") == null:
		return ""
	var best := ""
	var best_k := 0
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		var k := 0
		for s in base_map.forces[fid].get("units", []):
			if int(s.get("owner", -1)) != pid:
				continue
			if int(s.get("type", -1)) == int(GlobalUnits.UNIT_TYPE.KNIGHTS):
				k += int(s.get("count", 0))
		if k > best_k:
			best_k = k
			best = fid
	return best


static func _knight_count_in_force(base_map: Node, fid: String, pid: int) -> int:
	if not base_map.forces.has(fid):
		return 0
	var n := 0
	for s in base_map.forces[fid].get("units", []):
		if int(s.get("owner", -1)) != pid:
			continue
		if int(s.get("type", -1)) == int(GlobalUnits.UNIT_TYPE.KNIGHTS):
			n += int(s.get("count", 0))
	return n


static func _knights_needed_for_strength(need_str: int) -> int:
	var per := maxi(1, GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.KNIGHTS))
	return maxi(GlobalUnits.MIN_SPLIT_MEN, int(ceil(float(maxi(need_str, 1)) / float(per))))


static func _set_craft_armour(base_map: Node, prov: Node, pid: int) -> void:
	if prov == null or prov.get("economy") == null:
		return
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		if int(b.get("subtype")) != 5:
			continue
		if b.has_method("set_craft_weapon"):
			b.set_craft_weapon("armour")
		elif b.get("craft_weapon") != null:
			b.craft_weapon = "armour"


static func _try_buy_knight_kit(base_map: Node, prov: Node, pid: int, want_knights: int) -> void:
	if want_knights <= 0 or prov == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var need_h := maxi(0, want_knights - int(stock.get("horses", 0)))
	var need_a := maxi(0, want_knights - int(stock.get("armour", 0)))
	if need_h <= 0 and need_a <= 0:
		return
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var spendable := _marks_spendable(base_map, pid)
	var buy: Dictionary = GlobalUnits.empty_weapon_stock()
	var cost := 0
	for e in [{"k": "horses", "n": need_h}, {"k": "armour", "n": need_a}]:
		var want := int(e["n"])
		if want <= 0:
			continue
		var unit_p := maxi(1, GlobalUnits.weapon_mark_price_discounted(str(e["k"]), competition))
		var can := mini(want, int(floor(float(spendable - cost) / float(unit_p))))
		if can > 0:
			buy[str(e["k"])] = can
			cost += unit_p * can
	if cost <= 0 or cost > spendable:
		return
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			String(merchant.name), buy, GlobalUnits.empty_material_stock(), pid, cost
		)


static func _execute_knight_war_season(
	base_map: Node, pid: int, war: Dictionary, holdings: Array
) -> void:
	war["halt_reason"] = ""
	var target_id := str(war.get("target_province_id", ""))
	var staging_id := str(war.get("staging_province_id", ""))
	var target_prov = base_map._get_province_by_id(target_id) if base_map.has_method("_get_province_by_id") else null
	var staging = base_map._get_province_by_id(staging_id) if base_map.has_method("_get_province_by_id") else null
	if target_prov == null or staging == null:
		war["halt_reason"] = "no target/staging"
		return
	var enemy_town = target_prov.get_town() if target_prov.has_method("get_town") else null
	if enemy_town == null:
		war["halt_reason"] = "target has no town"
		return

	var fid := str(war.get("force_id", ""))
	if fid != "" and not base_map.forces.has(fid):
		fid = ""
		war["force_id"] = ""
		war["marching"] = false

	var preview: Dictionary = {}
	if base_map.has_method("get_settlement_defense_preview"):
		preview = base_map.get_settlement_defense_preview(enemy_town, fid)
	var def_str := int(preview.get("strength", 0))
	var need_str := maxi(1, int(ceil(float(def_str) * KNIGHT_STRENGTH_MARGIN)))
	var need_knights := _knights_needed_for_strength(need_str)

	# Raise / reinforce only while still at home (dejure). Never levy into a foreign stack.
	var raise_prov = staging
	var at_home := false
	if fid != "" and base_map.has_method("province_under_force"):
		var under = base_map.province_under_force(fid)
		if under != null and under.has_method("has_dejure") and under.has_dejure(pid):
			raise_prov = under
			at_home = true
		elif under != null:
			at_home = false
	else:
		at_home = true

	if at_home and not bool(war.get("marching", false)):
		_set_craft_armour(base_map, raise_prov, pid)
		_try_buy_knight_kit(base_map, raise_prov, pid, need_knights)
		fid = _knight_reinforce_force(base_map, raise_prov, pid, fid, need_knights)
		war["force_id"] = fid
	if fid == "" or not base_map.forces.has(fid):
		war["halt_reason"] = "no knight force yet"
		return

	# Merge every other field stack onto the knight force (never move the main).
	fid = _merge_all_field_into_force(base_map, pid, fid)
	war["force_id"] = fid
	if fid == "" or not base_map.forces.has(fid):
		war["halt_reason"] = "force lost after merge"
		return

	# Mark campaign as underway once we've left home toward this target.
	if not at_home:
		war["marching"] = true

	var marching := bool(war.get("marching", false))
	var my_str := _force_strength(base_map, fid)
	var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
	var cargo_grain := int(base_map.get_force_cargo(fid).get("grain", 0)) if base_map.has_method("get_force_cargo") else 0
	var season_need := GlobalUnits.force_grain_need(men, false)

	# At the town — always assault (no 1.3× recheck once in contact).
	if _force_adjacent_to_building(base_map, fid, enemy_town):
		war["marching"] = true
		war["halt_reason"] = "assaulting (str %d vs need %d)" % [my_str, need_str]
		_try_knight_assault_and_capture(base_map, pid, fid, enemy_town, war)
		return

	# Still at home: need full strength + full trip grain before first march step.
	if not marching:
		_try_buy_war_grain(base_map, raise_prov, pid, enemy_town, fid)
		var grain_ready := _load_war_grain_partial(base_map, pid, raise_prov, fid, enemy_town)
		my_str = _force_strength(base_map, fid)
		if my_str < need_str:
			war["halt_reason"] = "raising — str %d / need %d (knights %d / %d)" % [
				my_str, need_str, _knight_count_in_force(base_map, fid, pid), need_knights
			]
			return
		if not grain_ready:
			cargo_grain = int(base_map.get_force_cargo(fid).get("grain", 0)) if base_map.has_method("get_force_cargo") else 0
			var want := _war_grain_wanted(base_map, fid, enemy_town)
			war["halt_reason"] = "waiting grain cargo %d / %d" % [cargo_grain, want]
			return
		if men < GlobalUnits.MIN_SPLIT_MEN:
			war["halt_reason"] = "force too small to march"
			return
		war["marching"] = true
		war["halt_reason"] = "marching out"
		_move_force_toward_building(base_map, fid, enemy_town)
		return

	# Already committed: keep advancing — do not re-gate on full trip grain or strength.
	if cargo_grain < season_need:
		war["halt_reason"] = "marching low cargo %d < season %d (committed — still advancing)" % [
			cargo_grain, season_need
		]
		if at_home:
			_try_buy_war_grain(base_map, raise_prov, pid, enemy_town, fid)
			_load_war_grain_partial(base_map, pid, raise_prov, fid, enemy_town)
	else:
		war["halt_reason"] = "marching (cargo=%d str=%d)" % [cargo_grain, my_str]
	if men < GlobalUnits.MIN_SPLIT_MEN:
		war["halt_reason"] = "halted — force too small"
		return
	_move_force_toward_building(base_map, fid, enemy_town)


## Levy knights into `fid` (or create a new field force). Returns force id.
static func _knight_reinforce_force(
	base_map: Node, prov: Node, pid: int, fid: String, need_knights: int
) -> String:
	if prov == null:
		return fid
	var have := _knight_count_in_force(base_map, fid, pid) if fid != "" else 0
	var short := maxi(0, need_knights - have)
	if short <= 0:
		return fid if fid != "" else _find_knight_field_army(base_map, pid)

	var raise := mini(short, KNIGHT_LEVY_DRIP)
	raise = _clamp_levy_men(base_map, prov, pid, raise, false)
	if raise < GlobalUnits.MIN_SPLIT_MEN:
		# Can't open a new legal field stack this season.
		if fid != "":
			return fid
		return ""

	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var by_kit := mini(int(stock.get("horses", 0)), int(stock.get("armour", 0)))
	raise = mini(raise, by_kit)
	if raise < GlobalUnits.MIN_SPLIT_MEN:
		return fid

	var comp: Array = [{"type": GlobalUnits.UNIT_TYPE.KNIGHTS, "count": raise}]
	var new_id := _levy_composition_field(base_map, prov, pid, comp)
	if new_id == "":
		return fid
	if fid == "" or not base_map.forces.has(fid):
		return new_id
	if new_id == fid:
		return fid
	# Fold the fresh levy into the campaign stack (snap beside it if needed).
	return _absorb_field_force_into(base_map, fid, new_id)


## Capture town; leave the knight army in the field (no occupation plant).
static func _try_knight_assault_and_capture(
	base_map: Node, pid: int, fid: String, town: Node, war: Dictionary
) -> void:
	var key := str(base_map._building_key(town)) if base_map.has_method("_building_key") else ""
	if key == "":
		return
	var def_men := GlobalUnits.fighting_men(base_map.get_all_building_garrison(town))
	var will_militia := false
	if base_map.has_method("settlement_should_raise_militia"):
		will_militia = bool(base_map.settlement_should_raise_militia(town, fid))
	if def_men > 0 or will_militia:
		if base_map.has_method("request_battle_attack"):
			base_map.request_battle_attack(fid, "", key)
		def_men = GlobalUnits.fighting_men(base_map.get_all_building_garrison(town))
		will_militia = false
		if base_map.has_method("settlement_should_raise_militia"):
			will_militia = bool(base_map.settlement_should_raise_militia(town, fid))
	if def_men > 0 or will_militia:
		return
	if not base_map.forces.has(fid):
		return
	if not base_map.has_method("force_has_movement") or not base_map.force_has_movement(fid, 2):
		return
	if base_map.has_method("request_capture_building"):
		base_map.request_capture_building(fid, key)
	# Knights stay in the field — clear target until the new holding is fortified.
	war["target_province_id"] = ""
	war["staging_province_id"] = ""
	war["force_id"] = fid if base_map.forces.has(fid) else ""
	war["marching"] = false
	war["halt_reason"] = "captured — fortifying"


## Caravan bows/swords/pikes from surplus holdings into incomplete ones.
static func _knight_caravan_supply_arms(base_map: Node, pid: int, holdings: Array) -> void:
	if not base_map.has_method("request_send_caravan"):
		return
	var incomplete: Array = []
	var complete: Array = []
	for prov in holdings:
		if _province_defense_complete(base_map, prov, pid):
			complete.append(prov)
		else:
			incomplete.append(prov)
	if incomplete.is_empty() or complete.is_empty():
		# Still craft toward active holes on incomplete sites.
		for prov in incomplete:
			_set_craft_for_defense(base_map, prov, pid, false)
		return

	for dest in incomplete:
		_set_craft_for_defense(base_map, dest, pid, false)
		var holes := _defense_weapon_holes(base_map, dest, pid)
		var stock: Dictionary = dest.get_weapons_for(pid) if dest.has_method("get_weapons_for") else {}
		var need: Dictionary = GlobalUnits.empty_weapon_stock()
		var any := false
		for k in ["bows", "swords", "pikes"]:
			var short := maxi(0, int(holes.get(k, 0)) - int(stock.get(k, 0)))
			if short > 0:
				need[k] = short
				any = true
		if not any:
			continue
		for src in complete:
			if String(src.name) == String(dest.name):
				continue
			if not base_map.has_method("can_spawn_caravan_at") or not base_map.can_spawn_caravan_at(String(src.name)):
				continue
			# Skip if a caravan already going to dest from this owner.
			if _has_caravan_to(base_map, pid, String(dest.name)):
				break
			var src_stock: Dictionary = src.get_weapons_for(pid) if src.has_method("get_weapons_for") else {}
			var cargo := GlobalUnits.empty_caravan_cargo()
			var sent := false
			for k in ["bows", "swords", "pikes"]:
				var want := int(need.get(k, 0))
				if want <= 0:
					continue
				# Keep a small reserve on the donor.
				var spare := maxi(0, int(src_stock.get(k, 0)) - 20)
				var give := mini(want, spare)
				if give > 0:
					cargo[k] = give
					need[k] = want - give
					sent = true
			if not sent:
				continue
			if not GlobalUnits.caravan_cargo_has_any(cargo):
				continue
			base_map.request_send_caravan(String(src.name), String(dest.name), cargo, pid)
			break


static func _defense_weapon_holes(base_map: Node, prov: Node, pid: int) -> Dictionary:
	var out := {"bows": 0, "swords": 0, "pikes": 0}
	for slot in _defense_active_slots_for_pid(prov, pid):
		var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
		var mix: Dictionary = _defense_mix_counts(cap)
		var have: Dictionary = _spot_fighting_counts(base_map, slot["b"], int(slot["spot"]), pid)
		out["bows"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)))
		out["swords"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)))
		out["pikes"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)))
	return out


static func _has_caravan_to(base_map: Node, pid: int, dest_id: String) -> bool:
	if base_map.get("caravans") == null:
		return false
	for c in base_map.caravans.get_children():
		if int(c.get("player_owner")) != pid:
			continue
		if str(c.get("dest_province_id")) == dest_id:
			return true
	return false


# =============================================================================
# Offense doctrine — Pass 1 province tick (legacy / dormant)
# =============================================================================


static func tick_province_offense(base_map: Node, prov: Node, pid: int, holding_n: int = -1) -> void:
	if base_map == null or prov == null or pid < 0:
		return
	if not prov.has_method("has_dejure") or not prov.has_dejure(pid):
		return
	if holding_n < 0:
		holding_n = _provinces_for_lord(base_map, pid).size()

	var province_id := String(prov.name)
	var arms_ready := _arms_ready(base_map, prov, pid)
	var threatened := _province_threatened(base_map, prov, pid)
	var castle_target := _castle_target_level_offense(holding_n)
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	var need_castle_mats := arms_ready and _needs_castle_materials(castle, castle_target)

	var war: Dictionary = _war_state(base_map, pid)
	var at_war := (
		str(war.get("target_province_id", "")) != ""
		or bool(war.get("pause_until_stable", false))
	)
	_set_rations_and_tax(base_map, prov, pid, at_war)
	if base_map.has_method("apply_populate_idle_fields"):
		base_map.apply_populate_idle_fields(province_id, 1, pid)

	CouncilAI._try_build_open(base_map, prov, pid, 0)
	CouncilAI._try_build_open(base_map, prov, pid, 5)
	_try_build_deposit(base_map, prov, pid)

	_assign_labor(base_map, prov, pid, castle, arms_ready, need_castle_mats)

	var staging_id := str(war.get("staging_province_id", ""))
	var staging_war := str(war.get("target_province_id", "")) != "" and staging_id == province_id
	if staging_war:
		_set_craft_for_war(base_map, prov, pid)
	else:
		_set_craft_for_garrison(base_map, prov, pid, need_castle_mats)

	if threatened and not _garrison_targets_met(base_map, prov, pid):
		_reinforce_town_garrison(base_map, prov, pid)
		arms_ready = _arms_ready(base_map, prov, pid)

	if arms_ready:
		_try_advance_castle(base_map, prov, pid, castle, castle_target)


static func _provinces_for_lord(base_map: Node, pid: int) -> Array:
	var out: Array = []
	if base_map.get("provinces") == null:
		return out
	for prov in base_map.provinces.get_children():
		if prov.has_method("has_dejure") and prov.has_dejure(pid):
			out.append(prov)
	return out


## Offense: 0 = WOODEN_FORT alone; 1 = MOTTE_AND_BAILEY with 2+ holdings.
static func _castle_target_level_offense(holding_n: int) -> int:
	if holding_n <= 1:
		return 0
	return 1


## Legacy alias used by offense stability checks.
static func _castle_target_level(holding_n: int) -> int:
	return _castle_target_level_offense(holding_n)


## Stock + town garrison kit covers 100/100/100.
static func _arms_ready(base_map: Node, prov: Node, pid: int) -> bool:
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town == null:
		return true
	var counts := CouncilAI._town_garrison_counts(base_map, town, pid)
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	return (
		int(counts.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)) + int(stock.get("maces", 0))
		>= GlobalUnits.COUNCIL_TARGET_MACEMEN
		and int(counts.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) + int(stock.get("pikes", 0))
		>= GlobalUnits.COUNCIL_TARGET_PIKEMEN
		and int(counts.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) + int(stock.get("bows", 0))
		>= GlobalUnits.COUNCIL_TARGET_ARCHERS
	)


static func _garrison_targets_met(base_map: Node, prov: Node, pid: int) -> bool:
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town == null:
		return true
	var counts := CouncilAI._town_garrison_counts(base_map, town, pid)
	return (
		int(counts.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)) >= GlobalUnits.COUNCIL_TARGET_MACEMEN
		and int(counts.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) >= GlobalUnits.COUNCIL_TARGET_PIKEMEN
		and int(counts.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) >= GlobalUnits.COUNCIL_TARGET_ARCHERS
	)


## Hostile human/AI field army within straight filter, path MP ≤ its max MP.
static func _province_threatened(base_map: Node, prov: Node, pid: int) -> bool:
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town == null or base_map.get("armies") == null or base_map.get("forces") == null:
		return false
	var pf = base_map.get("pathfinding")
	if pf == null:
		return false
	var approach: Array[Vector2i] = []
	if pf.has_method("get_approach_cells"):
		approach = pf.get_approach_cells(town)
	if approach.is_empty():
		return false
	var town_cell: Vector2i = approach[0]
	var players: Dictionary = base_map.players
	var invalid := Vector2i(0x7FFFFFFF, 0x7FFFFFFF)

	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) <= 0:
			continue
		var ctrl := int(base_map.get_force_controller(fid)) if base_map.has_method("get_force_controller") else -1
		if ctrl < 0 or not players.has(ctrl):
			continue
		if base_map.has_method("are_friendly_players") and base_map.are_friendly_players(pid, ctrl):
			continue
		var ptype = players[ctrl].type
		# Only human / AI lords — ignore local councils.
		if GlobalStuff.is_local_council(ptype):
			continue
		if not (
			int(ptype) == int(GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL)
			or GlobalStuff.is_ai_lord(ptype)
		):
			continue

		var from_cell: Vector2i = pf.get_army_cell(fig) if pf.has_method("get_army_cell") else invalid
		if from_cell == invalid:
			continue
		var dcell: Vector2i = from_cell - town_cell
		if maxi(absi(dcell.x), absi(dcell.y)) > THREAT_STRAIGHT_FILTER:
			continue

		var path: Array[Vector2i] = []
		if pf.has_method("find_path_for_mover"):
			path = pf.find_path_for_mover(fig, from_cell, approach)
		elif pf.has_method("_best_path_to_cells"):
			path = pf._best_path_to_cells(from_cell, approach, fig)
		if path.is_empty():
			continue
		var mp_need := int(pf.path_mp_cost(path, fig)) if pf.has_method("path_mp_cost") else path.size()
		var mp_max := int(fig.effective_max_mp()) if fig.has_method("effective_max_mp") else int(fig.get("movement_points"))
		if mp_need <= mp_max:
			return true
	return false


static func _needs_castle_materials(castle: Node, target_level: int) -> bool:
	if castle == null or target_level < 0:
		return false
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		return false
	var standing := int(castle.standing_level()) if castle.has_method("standing_level") else GlobalUnits.CASTLE_TARGET_EMPTY
	if standing >= target_level:
		return false
	var preview: Dictionary = castle.preview_retarget(target_level) if castle.has_method("preview_retarget") else {}
	if preview.is_empty():
		return false
	var pay: Dictionary = preview.get("pay", {})
	return int(pay.get("wood", 0)) > 0 or int(pay.get("stone", 0)) > 0


static func _set_rations_and_tax(
	base_map: Node, prov: Node, pid: int, prefer_normal: bool = false
) -> void:
	var province_id := String(prov.name)
	var ration := GlobalUnits.RATION_DEFAULT
	# While at war / saving for march: keep Normal so surplus can fill cargo.
	if not prefer_normal and prov.has_method("preview_holding_rations"):
		var preview: Dictionary = prov.preview_holding_rations(pid)
		var stock := int(preview.get("stock", 0))
		var seed_r := int(preview.get("seed_reserve", 0))
		var army_need := int(preview.get("army_need", 0))
		var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
		var people_budget := maxi(0, stock - seed_r - army_need)
		if GlobalUnits.affordable_ration(pop, GlobalUnits.RATION.DOUBLE, people_budget) >= GlobalUnits.RATION.DOUBLE:
			ration = GlobalUnits.RATION.DOUBLE
	if base_map.has_method("apply_set_holding_ration"):
		base_map.apply_set_holding_ration(province_id, ration, pid)
	if base_map.has_method("apply_set_holding_tax"):
		base_map.apply_set_holding_tax(province_id, GlobalUnits.TAX_DEFAULT, pid)


## Defense: highest affordable ration ≤ Quadruple; tax paired for stable ~100 happiness.
static func _set_defense_rations_and_tax(base_map: Node, prov: Node, pid: int) -> void:
	var province_id := String(prov.name)
	var ration := GlobalUnits.RATION_DEFAULT
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	if prov.has_method("preview_holding_rations"):
		var preview: Dictionary = prov.preview_holding_rations(pid)
		var stock := int(preview.get("stock", 0))
		var seed_r := int(preview.get("seed_reserve", 0))
		var army_need := int(preview.get("army_need", 0))
		var people_budget := maxi(0, stock - seed_r - army_need)
		ration = GlobalUnits.affordable_ration(pop, GlobalUnits.RATION.QUADRUPLE, people_budget)
	var avg_h := 100.0
	if prov.has_method("average_settlement_happiness"):
		avg_h = float(prov.average_settlement_happiness(pid))
	var tax := _defense_pick_stable_tax(ration, avg_h)
	if base_map.has_method("apply_set_holding_ration"):
		base_map.apply_set_holding_ration(province_id, ration, pid)
	if base_map.has_method("apply_set_holding_tax"):
		base_map.apply_set_holding_tax(province_id, tax, pid)


## Highest tax whose net seasonal happiness Δ stays ≥ min_net (0 at cap, 2 while recovering).
static func _defense_pick_stable_tax(ration: int, avg_h: float) -> int:
	var r_d := GlobalUnits.ration_happiness_delta(ration)
	var min_net := 2.0 if avg_h < DEFENSE_HAPPY_RECOVER_BELOW else 0.0
	# Prefer higher tax (Brutal → None) while keeping net ≥ min_net.
	var levels := [
		GlobalUnits.TAX.BRUTAL,
		GlobalUnits.TAX.HARSH,
		GlobalUnits.TAX.HEAVY,
		GlobalUnits.TAX.NORMAL,
		GlobalUnits.TAX.NONE,
	]
	for tax in levels:
		var net := r_d + GlobalUnits.tax_happiness_delta(int(tax))
		if net >= min_net:
			return int(tax)
	return GlobalUnits.TAX.NONE


static func _defense_castle_mat_shortfall(
	prov: Node, pid: int, castle: Node, next_level: int
) -> Dictionary:
	var out := {"wood": 0, "stone": 0}
	if castle == null or next_level < 0:
		return out
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		return out
	var standing := int(castle.standing_level()) if castle.has_method("standing_level") else GlobalUnits.CASTLE_TARGET_EMPTY
	if standing >= next_level:
		return out
	if not castle.has_method("preview_retarget"):
		return out
	var preview: Dictionary = castle.preview_retarget(next_level)
	if preview.is_empty():
		return out
	var pay: Dictionary = preview.get("pay", {})
	for key in ["wood", "stone"]:
		var need := int(pay.get(key, 0))
		var have := int(prov.get_player_material(pid, key)) if prov.has_method("get_player_material") else 0
		out[key] = maxi(0, need - have)
	return out


static func _defense_castle_marks_reserve(
	base_map: Node, prov: Node, shortfall: Dictionary
) -> int:
	if shortfall.is_empty():
		return 0
	var competition := false
	if base_map.has_method("merchant_competition_in_province"):
		competition = bool(base_map.merchant_competition_in_province(prov))
	var total := 0
	for key in ["wood", "stone"]:
		var n := int(shortfall.get(key, 0))
		if n <= 0:
			continue
		total += n * GlobalUnits.material_mark_price_discounted(key, competition)
	return total


static func _marks_spendable_defense(
	base_map: Node, pid: int, castle_reserve: int = 0
) -> int:
	return maxi(0, _marks_spendable(base_map, pid) - maxi(0, castle_reserve))


static func _clear_debug_buys(base_map: Node, pid: int, province_id: String) -> void:
	if base_map == null or not base_map.players.has(pid):
		return
	var gd: Dictionary = base_map.players[pid].game_data
	var buys: Dictionary = gd.get(AI_DEBUG_BUYS_KEY, {})
	if typeof(buys) != TYPE_DICTIONARY:
		buys = {}
	buys[province_id] = {}
	gd[AI_DEBUG_BUYS_KEY] = buys


static func _record_debug_buy(
	base_map: Node, pid: int, province_id: String, kind: String, amount: int
) -> void:
	if amount <= 0 or base_map == null or not base_map.players.has(pid):
		return
	var gd: Dictionary = base_map.players[pid].game_data
	var buys: Dictionary = gd.get(AI_DEBUG_BUYS_KEY, {})
	if typeof(buys) != TYPE_DICTIONARY:
		buys = {}
	var row: Dictionary = buys.get(province_id, {})
	if typeof(row) != TYPE_DICTIONARY:
		row = {}
	row[kind] = int(row.get(kind, 0)) + amount
	buys[province_id] = row
	gd[AI_DEBUG_BUYS_KEY] = buys


## Buy wood/stone shortfall for the next castle step (above upkeep).
static func _try_buy_defense_castle_mats(
	base_map: Node, prov: Node, pid: int, shortfall: Dictionary
) -> void:
	var want_wood := int(shortfall.get("wood", 0))
	var want_stone := int(shortfall.get("stone", 0))
	if want_wood <= 0 and want_stone <= 0:
		return
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var spendable := _marks_spendable(base_map, pid)
	var mats := GlobalUnits.empty_material_stock()
	var cost := 0
	# Stone first (usual bottleneck without a quarry), then wood.
	for key in ["stone", "wood"]:
		var want := int(shortfall.get(key, 0))
		if want <= 0:
			continue
		var unit_p := maxi(1, GlobalUnits.material_mark_price_discounted(key, competition))
		var can := mini(want, int(floor(float(spendable - cost) / float(unit_p))))
		if can > 0:
			mats[key] = can
			cost += unit_p * can
	if cost <= 0 or cost > spendable:
		return
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			String(merchant.name), GlobalUnits.empty_weapon_stock(), mats, pid, cost
		)
		var province_id := String(prov.name)
		for key in ["stone", "wood"]:
			_record_debug_buy(base_map, pid, province_id, key, int(mats.get(key, 0)))


## Buy iron when stock is low and craft needs metal weapons.
static func _try_buy_defense_iron(
	base_map: Node, prov: Node, pid: int, castle_short: Dictionary
) -> void:
	var have := int(prov.get_player_material(pid, "iron")) if prov.has_method("get_player_material") else 0
	if have >= DEFENSE_IRON_BUY_FLOOR:
		return
	var iron_cap := int(prov.economy_worker_cap(pid, "iron")) if prov.has_method("economy_worker_cap") else 0
	# If a mine is producing, skip unless completely empty.
	if iron_cap > 0 and have > 0:
		return
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var reserve := _defense_castle_marks_reserve(base_map, prov, castle_short)
	var spendable := _marks_spendable_defense(base_map, pid, reserve)
	var unit_p := maxi(1, GlobalUnits.material_mark_price_discounted("iron", competition))
	var want := DEFENSE_IRON_BUY_FLOOR - have
	var can := mini(want, int(floor(float(spendable) / float(unit_p))))
	if can <= 0:
		return
	var mats := GlobalUnits.empty_material_stock()
	mats["iron"] = can
	var cost := unit_p * can
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			String(merchant.name), GlobalUnits.empty_weapon_stock(), mats, pid, cost
		)
		_record_debug_buy(base_map, pid, String(prov.name), "iron", can)


## Buy bows/swords/pikes for garrison holes when craft can't keep up.
static func _try_buy_defense_weapons(base_map: Node, prov: Node, pid: int) -> void:
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var left := {
		"bows": int(stock.get("bows", 0)),
		"swords": int(stock.get("swords", 0)),
		"pikes": int(stock.get("pikes", 0)),
	}
	var castle_need := {"bows": 0, "swords": 0, "pikes": 0}
	var other_need := {"bows": 0, "swords": 0, "pikes": 0}
	for slot in _defense_active_slots_for_pid(prov, pid):
		var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
		var mix: Dictionary = _defense_mix_counts(cap)
		var have: Dictionary = _spot_fighting_counts(base_map, slot["b"], int(slot["spot"]), pid)
		var holes := {
			"bows": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.ARCHER, 0))),
			"swords": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0))),
			"pikes": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0))),
		}
		var dest: Dictionary = castle_need if str(slot.get("prio", "")) == "castle" else other_need
		for k in holes:
			dest[k] = int(dest[k]) + int(holes[k])
	# Cover castle from stock first.
	for k in left:
		var use := mini(int(left[k]), int(castle_need[k]))
		castle_need[k] = int(castle_need[k]) - use
		left[k] = int(left[k]) - use
	var buy_need := {
		"bows": int(castle_need["bows"]),
		"swords": int(castle_need["swords"]),
		"pikes": int(castle_need["pikes"]),
	}
	# If castle kit is covered, drip-buy for other active slots from remaining stock.
	if int(buy_need["bows"]) + int(buy_need["swords"]) + int(buy_need["pikes"]) <= 0:
		for k in left:
			var hole := maxi(0, int(other_need[k]) - int(left[k]))
			buy_need[k] = mini(hole, DEFENSE_DRIP_OTHER)
	if int(buy_need["bows"]) + int(buy_need["swords"]) + int(buy_need["pikes"]) <= 0:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var spendable := _marks_spendable(base_map, pid)
	var buy: Dictionary = GlobalUnits.empty_weapon_stock()
	var cost := 0
	for k in ["bows", "swords", "pikes"]:
		var want := int(buy_need[k])
		if want <= 0:
			continue
		var unit_p := maxi(1, GlobalUnits.weapon_mark_price_discounted(k, competition))
		var can := mini(want, int(floor(float(spendable - cost) / float(unit_p))))
		if can > 0:
			buy[k] = can
			cost += unit_p * can
	if cost <= 0 or cost > spendable:
		return
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			String(merchant.name), buy, GlobalUnits.empty_material_stock(), pid, cost
		)
		var province_id := String(prov.name)
		for k in ["bows", "swords", "pikes"]:
			_record_debug_buy(base_map, pid, province_id, k, int(buy.get(k, 0)))


## Buy grain so Quadruple stays affordable (after castle mat reserve).
static func _try_buy_defense_grain(
	base_map: Node, prov: Node, pid: int, castle_short: Dictionary
) -> void:
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	if not prov.has_method("preview_holding_rations"):
		return
	var preview: Dictionary = prov.preview_holding_rations(pid)
	var stock := int(preview.get("stock", 0))
	var seed_r := int(preview.get("seed_reserve", 0))
	var army_need := int(preview.get("army_need", 0))
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var people_budget := maxi(0, stock - seed_r - army_need)
	if GlobalUnits.affordable_ration(pop, GlobalUnits.RATION.QUADRUPLE, people_budget) >= GlobalUnits.RATION.QUADRUPLE:
		return
	var need_for_quad := GlobalUnits.ration_grain_need(pop, GlobalUnits.RATION.QUADRUPLE)
	var short := maxi(0, need_for_quad - people_budget)
	if short <= 0:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var reserve := _defense_castle_marks_reserve(base_map, prov, castle_short)
	var spendable := _marks_spendable_defense(base_map, pid, reserve)
	var unit_p := maxi(1, GlobalUnits.material_mark_price_discounted("grain", competition))
	var can := mini(short, int(floor(float(spendable) / float(unit_p))))
	if can <= 0:
		return
	var mats := GlobalUnits.empty_material_stock()
	mats["grain"] = can
	var cost := unit_p * can
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			String(merchant.name), GlobalUnits.empty_weapon_stock(), mats, pid, cost
		)
		_record_debug_buy(base_map, pid, String(prov.name), "grain", can)


static func _try_build_deposit(base_map: Node, prov: Node, pid: int) -> void:
	if prov.get("economy") == null:
		return
	var prefer := [1, 4, 3] # IRONMINE, STONEQUARRY, SILVERMINE
	for subtype in prefer:
		var have := false
		for b in prov.economy.get_children():
			if int(b.get("player_owner")) != pid:
				continue
			if b.has_method("is_built") and b.is_built() and int(b.get("subtype")) == int(subtype):
				have = true
				break
		if have:
			continue
		if CouncilAI._try_build_open(base_map, prov, pid, int(subtype)):
			return


static func _assign_labor(
	base_map: Node, prov: Node, pid: int, castle: Node, arms_ready: bool, stockpile_castle: bool
) -> void:
	var season := int(base_map.season) if base_map.get("season") != null else 0
	var province_id := String(prov.name)
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var grain_need := 0
	if prov.has_method("grain_labor_required"):
		grain_need = int(prov.grain_labor_required(pid, season))
	var grain_n := mini(grain_need, pop)
	var remaining := maxi(0, pop - grain_n)

	var castle_n := 0
	var building_castle: bool = (
		castle != null
		and castle.has_method("is_under_construction")
		and bool(castle.is_under_construction())
	)
	if building_castle and prov.has_method("castle_construction_cap"):
		var ccap := int(prov.castle_construction_cap(pid))
		castle_n = mini(ccap, remaining)
		remaining = maxi(0, remaining - castle_n)

	var wood_cap := int(prov.economy_worker_cap(pid, "wood")) if prov.has_method("economy_worker_cap") else 0
	# Prefer wood when stockpiling castle mats or still arming (bows need wood).
	var wood_n := mini(wood_cap, remaining)
	remaining = maxi(0, remaining - wood_n)

	var iron_cap := int(prov.economy_worker_cap(pid, "iron")) if prov.has_method("economy_worker_cap") else 0
	var iron_n := mini(iron_cap, remaining)
	remaining = maxi(0, remaining - iron_n)

	var stone_cap := int(prov.economy_worker_cap(pid, "stone")) if prov.has_method("economy_worker_cap") else 0
	var stone_n := 0
	if stockpile_castle or not arms_ready:
		stone_n = mini(stone_cap, remaining)
		remaining = maxi(0, remaining - stone_n)

	var silver_cap := int(prov.economy_worker_cap(pid, "silver")) if prov.has_method("economy_worker_cap") else 0
	var silver_n := mini(silver_cap, remaining)
	remaining = maxi(0, remaining - silver_n)

	var smith_cap := int(prov.economy_worker_cap(pid, "blacksmith")) if prov.has_method("economy_worker_cap") else 0
	var smith_n := 0
	# Don't burn smith labor on wood weapons while stockpiling castle wood.
	if not stockpile_castle:
		smith_n = mini(smith_cap, remaining)
		remaining = maxi(0, remaining - smith_n)

	# If we still have people and a castle project, dump leftovers into castle.
	if building_castle and prov.has_method("castle_construction_cap"):
		var ccap2 := int(prov.castle_construction_cap(pid))
		var more := mini(maxi(0, ccap2 - castle_n), remaining)
		castle_n += more

	if base_map.has_method("apply_set_holding_labor_category"):
		for cat in GlobalUnits.LABOR_CATEGORIES:
			base_map.apply_set_holding_labor_category(province_id, cat, 0, pid)
		base_map.apply_set_holding_labor_category(province_id, "grain", grain_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "castle", castle_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "wood", wood_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "iron", iron_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "stone", stone_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "silver", silver_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "blacksmith", smith_n, pid)
		return

	if not prov.has_method("set_labor_category"):
		return
	for cat in GlobalUnits.LABOR_CATEGORIES:
		prov.set_labor_category(pid, cat, 0, season)
	prov.set_labor_category(pid, "grain", grain_n, season)
	prov.set_labor_category(pid, "castle", castle_n, season)
	prov.set_labor_category(pid, "wood", wood_n, season)
	prov.set_labor_category(pid, "iron", iron_n, season)
	prov.set_labor_category(pid, "stone", stone_n, season)
	prov.set_labor_category(pid, "silver", silver_n, season)
	prov.set_labor_category(pid, "blacksmith", smith_n, season)


## Defense labor: grain → castle project → wood+stone (before iron/smith) when stocking mats.
static func _assign_labor_defense(
	base_map: Node, prov: Node, pid: int, castle: Node, stockpile_castle: bool
) -> void:
	var season := int(base_map.season) if base_map.get("season") != null else 0
	var province_id := String(prov.name)
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var grain_need := 0
	if prov.has_method("grain_labor_required"):
		grain_need = int(prov.grain_labor_required(pid, season))
	var grain_n := mini(grain_need, pop)
	var remaining := maxi(0, pop - grain_n)

	var castle_n := 0
	var building_castle: bool = (
		castle != null
		and castle.has_method("is_under_construction")
		and bool(castle.is_under_construction())
	)
	if building_castle and prov.has_method("castle_construction_cap"):
		var ccap := int(prov.castle_construction_cap(pid))
		castle_n = mini(ccap, remaining)
		remaining = maxi(0, remaining - castle_n)

	var wood_cap := int(prov.economy_worker_cap(pid, "wood")) if prov.has_method("economy_worker_cap") else 0
	var stone_cap := int(prov.economy_worker_cap(pid, "stone")) if prov.has_method("economy_worker_cap") else 0
	var iron_cap := int(prov.economy_worker_cap(pid, "iron")) if prov.has_method("economy_worker_cap") else 0
	var silver_cap := int(prov.economy_worker_cap(pid, "silver")) if prov.has_method("economy_worker_cap") else 0
	var smith_cap := int(prov.economy_worker_cap(pid, "blacksmith")) if prov.has_method("economy_worker_cap") else 0

	var wood_n := mini(wood_cap, remaining)
	remaining = maxi(0, remaining - wood_n)

	var stone_n := 0
	if stockpile_castle or stone_cap > 0:
		stone_n = mini(stone_cap, remaining)
		remaining = maxi(0, remaining - stone_n)

	var iron_n := 0
	var silver_n := 0
	var smith_n := 0
	if stockpile_castle:
		# Don't starve the ladder — iron/smith only after wood+stone caps filled.
		iron_n = mini(iron_cap, remaining)
		remaining = maxi(0, remaining - iron_n)
		silver_n = mini(silver_cap, remaining)
		remaining = maxi(0, remaining - silver_n)
		# Skip smith while still needing castle mats.
	else:
		iron_n = mini(iron_cap, remaining)
		remaining = maxi(0, remaining - iron_n)
		silver_n = mini(silver_cap, remaining)
		remaining = maxi(0, remaining - silver_n)
		smith_n = mini(smith_cap, remaining)
		remaining = maxi(0, remaining - smith_n)

	if building_castle and prov.has_method("castle_construction_cap"):
		var ccap2 := int(prov.castle_construction_cap(pid))
		var more := mini(maxi(0, ccap2 - castle_n), remaining)
		castle_n += more

	if base_map.has_method("apply_set_holding_labor_category"):
		for cat in GlobalUnits.LABOR_CATEGORIES:
			base_map.apply_set_holding_labor_category(province_id, cat, 0, pid)
		base_map.apply_set_holding_labor_category(province_id, "grain", grain_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "castle", castle_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "wood", wood_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "stone", stone_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "iron", iron_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "silver", silver_n, pid)
		base_map.apply_set_holding_labor_category(province_id, "blacksmith", smith_n, pid)
		return

	if not prov.has_method("set_labor_category"):
		return
	for cat in GlobalUnits.LABOR_CATEGORIES:
		prov.set_labor_category(pid, cat, 0, season)
	prov.set_labor_category(pid, "grain", grain_n, season)
	prov.set_labor_category(pid, "castle", castle_n, season)
	prov.set_labor_category(pid, "wood", wood_n, season)
	prov.set_labor_category(pid, "stone", stone_n, season)
	prov.set_labor_category(pid, "iron", iron_n, season)
	prov.set_labor_category(pid, "silver", silver_n, season)
	prov.set_labor_category(pid, "blacksmith", smith_n, season)


## Craft kit still needed for garrison (stock + town counts vs targets).
static func _set_craft_for_garrison(
	base_map: Node, prov: Node, pid: int, reserve_wood_for_castle: bool
) -> void:
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town == null:
		return
	var counts := CouncilAI._town_garrison_counts(base_map, town, pid)
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var deficits := {
		"maces": maxi(
			0,
			GlobalUnits.COUNCIL_TARGET_MACEMEN
			- int(counts.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0))
			- int(stock.get("maces", 0))
		),
		"pikes": maxi(
			0,
			GlobalUnits.COUNCIL_TARGET_PIKEMEN
			- int(counts.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0))
			- int(stock.get("pikes", 0))
		),
		"bows": maxi(
			0,
			GlobalUnits.COUNCIL_TARGET_ARCHERS
			- int(counts.get(GlobalUnits.UNIT_TYPE.ARCHER, 0))
			- int(stock.get("bows", 0))
		),
	}
	if reserve_wood_for_castle:
		deficits["bows"] = 0
	var iron := int(prov.get_player_material(pid, "iron")) if prov.has_method("get_player_material") else 0
	var best_key := ""
	var best_n := 0
	if iron < 3:
		if int(deficits["bows"]) > 0 and not reserve_wood_for_castle:
			best_key = "bows"
			best_n = int(deficits["bows"])
	else:
		for k in deficits:
			if int(deficits[k]) > best_n:
				best_n = int(deficits[k])
				best_key = k
	if best_n <= 0 or best_key == "":
		return
	if prov.get("economy") == null:
		return
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		if int(b.get("subtype")) != 5:
			continue
		if b.has_method("set_craft_weapon"):
			b.set_craft_weapon(best_key)
		elif b.get("craft_weapon") != null:
			b.craft_weapon = best_key


static func _try_advance_castle(
	base_map: Node, prov: Node, pid: int, castle: Node, target_level: int
) -> void:
	if castle == null or target_level < 0:
		return
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		# Already building — labor assigned in _assign_labor.
		return
	var standing := int(castle.standing_level()) if castle.has_method("standing_level") else GlobalUnits.CASTLE_TARGET_EMPTY
	if standing >= target_level:
		return
	if not castle.has_method("preview_retarget"):
		return
	var preview: Dictionary = castle.preview_retarget(target_level)
	if preview.is_empty():
		return
	var pay: Dictionary = preview.get("pay", {})
	for key in ["wood", "stone"]:
		var need := int(pay.get(key, 0))
		if need > 0 and prov.get_player_material(pid, key) < need:
			return
	if base_map.has_method("apply_retarget_castle"):
		base_map.apply_retarget_castle(base_map._building_key(castle), target_level, pid)


static func _happiness_levy_budget(prov: Node, pid: int) -> int:
	var season_start := int(prov.season_start_population) if prov.get("season_start_population") != null else 0
	if season_start <= 0:
		season_start = int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	if season_start <= 0:
		return 0
	var avg_h := 100.0
	if prov.has_method("average_settlement_happiness"):
		avg_h = float(prov.average_settlement_happiness(pid))
	var ration := GlobalUnits.RATION_DEFAULT
	var tax := GlobalUnits.TAX_DEFAULT
	if prov.has_method("get_holding_ration"):
		ration = int(prov.get_holding_ration(pid))
	if prov.has_method("get_holding_tax"):
		tax = int(prov.get_holding_tax(pid))
	var recovery := (
		GlobalUnits.ration_happiness_delta(ration)
		+ GlobalUnits.tax_happiness_delta(tax)
	)
	var affordable_penalty := maxf(0.0, avg_h + recovery - 100.0)
	var max_pct := (
		GlobalUnits.LEVY_HAPPINESS_FREE_FRACTION * 100.0
		+ affordable_penalty / GlobalUnits.LEVY_HAPPINESS_PER_PERCENT
	)
	var max_total := int(floor(float(season_start) * max_pct / 100.0))
	var already := int(prov.levied_this_season) if prov.get("levied_this_season") != null else 0
	return maxi(0, max_total - already)


static func _reinforce_town_garrison(base_map: Node, prov: Node, pid: int) -> void:
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town == null or base_map == null:
		return
	var counts := CouncilAI._town_garrison_counts(base_map, town, pid)
	var want := {
		GlobalUnits.UNIT_TYPE.MACEMEN: maxi(
			0, GlobalUnits.COUNCIL_TARGET_MACEMEN - int(counts.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0))
		),
		GlobalUnits.UNIT_TYPE.PIKEMEN: maxi(
			0, GlobalUnits.COUNCIL_TARGET_PIKEMEN - int(counts.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0))
		),
		GlobalUnits.UNIT_TYPE.ARCHER: maxi(
			0, GlobalUnits.COUNCIL_TARGET_ARCHERS - int(counts.get(GlobalUnits.UNIT_TYPE.ARCHER, 0))
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
	var grain_need := int(prov.grain_labor_required(pid, int(base_map.season))) if prov.has_method("grain_labor_required") else 0
	var levy_cap := maxi(0, pop - grain_need)
	var happy_cap := _happiness_levy_budget(prov, pid)
	var allowed := mini(total, mini(room, mini(levy_left, mini(levy_cap, happy_cap))))
	if allowed <= 0:
		return

	composition = CouncilAI._trim_composition(composition, allowed)
	if GlobalUnits.composition_total_men(composition) <= 0:
		return

	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if not prov.can_afford_weapons_for(pid, need):
		composition = CouncilAI._trim_to_weapons(prov, pid, composition)
		if GlobalUnits.composition_total_men(composition) <= 0:
			return
		need = GlobalUnits.weapons_needed_for_composition(composition)

	var men := GlobalUnits.composition_total_men(composition)
	if men <= 0:
		return

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


# =============================================================================
# Pass 2a — world offense
# =============================================================================


static func tick_world(base_map: Node, pid: int, holdings: Array) -> void:
	if holdings.is_empty():
		return
	var war: Dictionary = _war_state(base_map, pid)

	# After conquest: wait until every holding is stable again.
	# Keep force_id so the leftover occupation army joins the next offensive.
	if bool(war.get("pause_until_stable", false)):
		if _all_holdings_stable(base_map, pid, holdings):
			war["pause_until_stable"] = false
			war["target_province_id"] = ""
			war["staging_province_id"] = ""
			war["retarget_wait"] = 0
			war["pending_weaker"] = ""
			var keep_fid := str(war.get("force_id", ""))
			if keep_fid == "" or not base_map.forces.has(keep_fid):
				war["force_id"] = _find_field_army(base_map, pid)
			_set_war_state(base_map, pid, war)
		else:
			# Stay garrisoned while paused in the new holding.
			var hold_fid := str(war.get("force_id", ""))
			var under = null
			if hold_fid != "" and base_map.forces.has(hold_fid) and base_map.has_method("province_under_force"):
				under = base_map.province_under_force(hold_fid)
			if under == null and not holdings.is_empty():
				under = holdings[holdings.size() - 1]
			if under != null:
				_merge_province_field_armies(base_map, pid, under, war)
				_absorb_field_into_garrison(base_map, pid, under, str(war.get("force_id", "")))
			_set_war_state(base_map, pid, war)
		return

	if not _has_operational_wooden_fort(holdings):
		return

	var target_id := str(war.get("target_province_id", ""))
	if target_id != "":
		var target_prov = base_map._get_province_by_id(target_id) if base_map.has_method("_get_province_by_id") else null
		if not _is_valid_council_target(base_map, target_prov):
			war["target_province_id"] = ""
			war["staging_province_id"] = ""
			war["force_id"] = ""
			war["retarget_wait"] = 0
			war["pending_weaker"] = ""
			_set_war_state(base_map, pid, war)
			target_id = ""

	if target_id == "":
		var pick: Dictionary = _pick_council_target(base_map, pid, holdings)
		if pick.is_empty():
			return
		war["target_province_id"] = str(pick.get("province_id", ""))
		war["staging_province_id"] = str(pick.get("staging_id", ""))
		war["force_id"] = ""
		war["retarget_wait"] = 0
		war["pending_weaker"] = ""
		_set_war_state(base_map, pid, war)
		target_id = str(war["target_province_id"])

	# Retarget wait: weaker adjacent council for 2 seasons → switch.
	_update_retarget_wait(base_map, pid, holdings, war)
	_set_war_state(base_map, pid, war)
	if str(war.get("target_province_id", "")) == "":
		return

	_execute_war_season(base_map, pid, war)
	_set_war_state(base_map, pid, war)


static func _war_state(base_map: Node, pid: int) -> Dictionary:
	if not base_map.players.has(pid):
		return {}
	var gd: Dictionary = base_map.players[pid].game_data
	var raw = gd.get(AI_WAR_KEY, {})
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
	var war: Dictionary = raw
	if not war.has("target_province_id"):
		war["target_province_id"] = ""
	if not war.has("staging_province_id"):
		war["staging_province_id"] = ""
	if not war.has("force_id"):
		war["force_id"] = ""
	if not war.has("retarget_wait"):
		war["retarget_wait"] = 0
	if not war.has("pending_weaker"):
		war["pending_weaker"] = ""
	if not war.has("pause_until_stable"):
		war["pause_until_stable"] = false
	return war


static func _set_war_state(base_map: Node, pid: int, war: Dictionary) -> void:
	if not base_map.players.has(pid):
		return
	base_map.players[pid].game_data[AI_WAR_KEY] = war


static func _has_operational_wooden_fort(holdings: Array) -> bool:
	for prov in holdings:
		var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
		if castle == null:
			continue
		if castle.has_method("is_operational") and castle.is_operational():
			if int(castle.standing_level()) >= 0:
				return true
	return false


static func _province_food_ok(base_map: Node, prov: Node, pid: int) -> bool:
	if not prov.has_method("preview_holding_rations"):
		return true
	var preview: Dictionary = prov.preview_holding_rations(pid)
	var stock := int(preview.get("stock", 0))
	var seed_r := int(preview.get("seed_reserve", 0))
	var army_need := int(preview.get("army_need", 0))
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var people_budget := maxi(0, stock - seed_r - army_need)
	return GlobalUnits.affordable_ration(pop, GlobalUnits.RATION_DEFAULT, people_budget) >= GlobalUnits.RATION_DEFAULT


static func _province_castle_ok(prov: Node, holding_n: int) -> bool:
	var target := _castle_target_level(holding_n)
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null:
		return target < 0
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		return false
	var standing := int(castle.standing_level()) if castle.has_method("standing_level") else -1
	return standing >= target


static func _province_stable(base_map: Node, prov: Node, pid: int, holding_n: int) -> bool:
	return (
		_province_food_ok(base_map, prov, pid)
		and _arms_ready(base_map, prov, pid)
		and _province_castle_ok(prov, holding_n)
	)


static func _all_holdings_stable(base_map: Node, pid: int, holdings: Array) -> bool:
	var n := holdings.size()
	for prov in holdings:
		if not _province_stable(base_map, prov, pid, n):
			return false
	return true


static func _is_valid_council_target(base_map: Node, prov: Node) -> bool:
	if prov == null or not is_instance_valid(prov):
		return false
	var dejure := int(prov.dejure) if prov.get("dejure") != null else int(prov.get("player_owner"))
	if dejure < 0 or not base_map.players.has(dejure):
		return false
	var holder = base_map.players[dejure]
	if holder == null:
		return false
	if not GlobalStuff.is_local_council(holder.type):
		return false
	var town = prov.get_town() if prov.has_method("get_town") else null
	return town != null


static func _pick_council_target(base_map: Node, pid: int, holdings: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_str := 0x7FFFFFFF
	var neighbors_map: Dictionary = base_map.province_neighbors if base_map.get("province_neighbors") != null else {}
	for home in holdings:
		var nlist: Array = neighbors_map.get(home, [])
		for other in nlist:
			if not _is_valid_council_target(base_map, other):
				continue
			var town = other.get_town()
			var preview: Dictionary = {}
			if base_map.has_method("get_settlement_defense_preview"):
				preview = base_map.get_settlement_defense_preview(town, "")
			var dstr := int(preview.get("strength", 0))
			if dstr < best_str or best.is_empty():
				best_str = dstr
				best = {
					"province_id": String(other.name),
					"staging_id": String(home.name),
					"defense_strength": dstr,
				}
	return best


static func _update_retarget_wait(base_map: Node, pid: int, holdings: Array, war: Dictionary) -> void:
	var current := str(war.get("target_province_id", ""))
	if current == "":
		return
	var pick: Dictionary = _pick_council_target(base_map, pid, holdings)
	if pick.is_empty():
		war["retarget_wait"] = 0
		war["pending_weaker"] = ""
		return
	var cand := str(pick.get("province_id", ""))
	if cand == "" or cand == current:
		war["retarget_wait"] = 0
		war["pending_weaker"] = ""
		return
	# Candidate must be strictly weaker than current target.
	var cur_prov = base_map._get_province_by_id(current) if base_map.has_method("_get_province_by_id") else null
	var cur_str := 0x7FFFFFFF
	if cur_prov != null and cur_prov.has_method("get_town"):
		var ct = cur_prov.get_town()
		if ct != null and base_map.has_method("get_settlement_defense_preview"):
			cur_str = int(base_map.get_settlement_defense_preview(ct, "").get("strength", 0))
	var cand_str := int(pick.get("defense_strength", 0))
	if cand_str >= cur_str:
		war["retarget_wait"] = 0
		war["pending_weaker"] = ""
		return
	if str(war.get("pending_weaker", "")) != cand:
		war["pending_weaker"] = cand
		war["retarget_wait"] = 1
		return
	war["retarget_wait"] = int(war.get("retarget_wait", 0)) + 1
	if int(war["retarget_wait"]) >= WAR_RETARGET_WAIT_SEASONS:
		war["target_province_id"] = cand
		war["staging_province_id"] = str(pick.get("staging_id", ""))
		war["force_id"] = ""
		war["retarget_wait"] = 0
		war["pending_weaker"] = ""


static func _execute_war_season(base_map: Node, pid: int, war: Dictionary) -> void:
	var target_id := str(war.get("target_province_id", ""))
	var staging_id := str(war.get("staging_province_id", ""))
	var target_prov = base_map._get_province_by_id(target_id) if base_map.has_method("_get_province_by_id") else null
	var staging = base_map._get_province_by_id(staging_id) if base_map.has_method("_get_province_by_id") else null
	if target_prov == null or staging == null:
		return
	var enemy_town = target_prov.get_town() if target_prov.has_method("get_town") else null
	if enemy_town == null:
		return

	var preview: Dictionary = {}
	if base_map.has_method("get_settlement_defense_preview"):
		preview = base_map.get_settlement_defense_preview(enemy_town, str(war.get("force_id", "")))
	var def_str := int(preview.get("strength", 0))
	var need_str := maxi(1, int(ceil(float(def_str) * WAR_STRENGTH_MARGIN)))
	var want_comp: Array = _war_composition_for_strength(need_str)

	_try_buy_war_weapons(base_map, staging, pid, want_comp)
	_try_buy_war_grain(base_map, staging, pid, enemy_town, str(war.get("force_id", "")))
	_set_craft_for_war(base_map, staging, pid, want_comp)

	# Consolidate any stray field stacks in staging, then park them in garrison.
	_merge_province_field_armies(base_map, pid, staging, war)
	_absorb_field_into_garrison(base_map, pid, staging, str(war.get("force_id", "")))

	# Raise / arm inside castle+town (overflow stays beside town).
	_war_reinforce_into_garrisons(base_map, staging, pid, want_comp)
	_arm_staging_war_forces(base_map, staging, pid, want_comp)
	_merge_province_field_armies(base_map, pid, staging, war)
	_absorb_field_into_garrison(base_map, pid, staging, str(war.get("force_id", "")))

	var pool: Dictionary = _staging_offensive_pool(base_map, staging, pid, "")
	var my_str := int(pool.get("strength", 0))
	if base_map.has_method("get_settlement_defense_preview"):
		preview = base_map.get_settlement_defense_preview(enemy_town, str(pool.get("field_id", "")))
	def_str = int(preview.get("strength", 0))
	need_str = maxi(1, int(ceil(float(def_str) * WAR_STRENGTH_MARGIN)))
	var ready := my_str >= need_str

	# Already in the field next to the enemy (mid-campaign).
	var fid := _find_field_army_near_building(base_map, pid, enemy_town)
	if fid != "" and _force_adjacent_to_building(base_map, fid, enemy_town):
		war["force_id"] = fid
		if _force_strength(base_map, fid) >= need_str:
			_try_assault_and_capture(base_map, pid, fid, enemy_town, war)
		return

	if not ready:
		# Stay garrisoned while still raising.
		_merge_province_field_armies(base_map, pid, staging, war)
		_absorb_field_into_garrison(base_map, pid, staging, str(war.get("force_id", "")))
		war["force_id"] = str(pool.get("field_id", ""))
		return

	# Strength ready: drip-feed soldiers + grain onto one field stack by town.
	# Do not empty the castle in one season.
	fid = _drip_feed_march_force(base_map, staging, pid, war, need_str)
	war["force_id"] = fid
	if fid == "" or not base_map.forces.has(fid):
		return

	var grain_ready := _load_war_grain_partial(base_map, pid, staging, fid, enemy_town)
	var field_str := _force_strength(base_map, fid)
	if field_str >= need_str and grain_ready:
		if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) >= GlobalUnits.MIN_SPLIT_MEN:
			_move_force_toward_building(base_map, fid, enemy_town)
		return

	# Not leaving yet — merge strays onto the drip stack; keep rest garrisoned.
	_merge_province_field_armies(base_map, pid, staging, war)
	war["force_id"] = fid if base_map.forces.has(fid) else str(war.get("force_id", ""))
	# Absorb any field stacks that are NOT the march force.
	_absorb_other_field_into_garrison(base_map, pid, staging, str(war.get("force_id", "")))


## Seasons of civilian/garrison draw until harvest lands (leaving autumn → winter).
static func _seasons_until_next_harvest(season: int) -> int:
	match clampi(season, 0, 3):
		0:
			return 4 # Winter → Sp → Su → Au
		1:
			return 3
		2:
			return 2
		_:
			return 1 # Autumn (harvest when leaving)


## Grain the staging province must keep until next harvest.
static func _province_grain_floor(base_map: Node, prov: Node, pid: int) -> int:
	var seed_r := int(prov.seed_grain_reserve(pid)) if prov.has_method("seed_grain_reserve") else 0
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var civ := GlobalUnits.ration_grain_need(pop, GlobalUnits.RATION_DEFAULT)
	var garrison_need := 0
	# Only standing garrisons in this province (field armies carry their own cargo).
	if base_map.get("forces") != null:
		for fid in base_map.forces.keys():
			if not base_map.force_is_garrison(str(fid)):
				continue
			if int(base_map.get_force_grain_payer(str(fid))) != pid:
				continue
			if base_map.province_under_force(str(fid)) != prov:
				continue
			var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
			garrison_need += GlobalUnits.force_grain_need(men, true)
	var seasons := _seasons_until_next_harvest(int(base_map.season) if base_map.get("season") != null else 0)
	return seed_r + (civ + garrison_need) * seasons


## Trip seasons ≈ ceil(path MP / army max MP), at least 1.
static func _estimate_trip_seasons(base_map: Node, fid: String, building: Node) -> int:
	var pf = base_map.get("pathfinding")
	var fig = base_map.armies.get_node_or_null(fid) if base_map.get("armies") != null else null
	if pf == null or fig == null or building == null:
		return 1
	var from_cell: Vector2i = pf.get_army_cell(fig)
	var approach: Array[Vector2i] = pf.get_approach_cells(building) if pf.has_method("get_approach_cells") else []
	if approach.is_empty():
		return 1
	if from_cell in approach:
		return 1
	var path: Array[Vector2i] = pf.find_path_for_mover(fig, from_cell, approach)
	if path.size() < 2:
		return 1
	var mp_need := 0
	for i in range(1, path.size()):
		mp_need += int(pf.enter_cost(path[i], fig)) if pf.has_method("enter_cost") else 1
	var mp_max := int(fig.effective_max_mp()) if fig.has_method("effective_max_mp") else 10
	mp_max = maxi(mp_max, 1)
	return maxi(1, int(ceil(float(mp_need) / float(mp_max))))


## Wanted cargo grain: men × mobile rate × (trip + 4).
static func _war_grain_wanted(base_map: Node, fid: String, town: Node) -> int:
	if not base_map.forces.has(fid):
		return 0
	var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
	if men <= 0:
		return 0
	var per := GlobalUnits.force_grain_need(men, false)
	var trip := _estimate_trip_seasons(base_map, fid, town)
	return per * (trip + 4)


## Grain spare above province floor (0 if none).
static func _province_grain_spare(base_map: Node, staging: Node, pid: int) -> int:
	var stock := int(staging.get_player_grain(pid)) if staging.has_method("get_player_grain") else 0
	var floor_g := _province_grain_floor(base_map, staging, pid)
	return maxi(0, stock - floor_g)


## Load as much grain as spare allows; true only when cargo ≥ full want.
static func _load_war_grain_partial(
	base_map: Node, pid: int, staging: Node, fid: String, town: Node
) -> bool:
	if not base_map.forces.has(fid) or staging == null:
		return false
	var want := _war_grain_wanted(base_map, fid, town)
	if want <= 0:
		return true
	var have := int(base_map.get_force_cargo(fid).get("grain", 0)) if base_map.has_method("get_force_cargo") else 0
	if have >= want:
		base_map.forces[fid]["feed_from_province"] = false
		return true

	var under = base_map.province_under_force(fid) if base_map.has_method("province_under_force") else null
	if under != staging or not staging.has_dejure(pid):
		return false

	var short := want - have
	var spare := _province_grain_spare(base_map, staging, pid)
	var take := mini(short, spare)
	if take <= 0:
		return false

	var cargo := GlobalUnits.empty_caravan_cargo()
	cargo["grain"] = take
	if staging.has_method("can_afford_caravan_cargo") and not staging.can_afford_caravan_cargo(pid, cargo):
		return false
	if not base_map.has_method("apply_force_withdraw_cargo"):
		return false
	base_map.apply_force_withdraw_cargo(fid, cargo, pid, String(staging.name))
	have = int(base_map.get_force_cargo(fid).get("grain", 0))
	if have >= want:
		base_map.forces[fid]["feed_from_province"] = false
		return true
	return false


## Legacy name — full load only (kept for callers).
static func _ensure_war_grain_for_march(
	base_map: Node, pid: int, staging: Node, fid: String, town: Node
) -> bool:
	return _load_war_grain_partial(base_map, pid, staging, fid, town)


static func _weapon_key_for_type(unit_type: int) -> String:
	match unit_type:
		GlobalUnits.UNIT_TYPE.MACEMEN:
			return "maces"
		GlobalUnits.UNIT_TYPE.PIKEMEN:
			return "pikes"
		GlobalUnits.UNIT_TYPE.ARCHER:
			return "bows"
		GlobalUnits.UNIT_TYPE.SWORDSMEN:
			return "swords"
		GlobalUnits.UNIT_TYPE.CROSSBOWMEN:
			return "crossbows"
		_:
			return ""


## Baseline home / occupation kit: 100 mace + 100 pike + 100 archer.
static func _home_kit_composition() -> Array:
	return [
		{"type": GlobalUnits.UNIT_TYPE.MACEMEN, "count": GlobalUnits.COUNCIL_TARGET_MACEMEN},
		{"type": GlobalUnits.UNIT_TYPE.PIKEMEN, "count": GlobalUnits.COUNCIL_TARGET_PIKEMEN},
		{"type": GlobalUnits.UNIT_TYPE.ARCHER, "count": GlobalUnits.COUNCIL_TARGET_ARCHERS},
	]


## Home kit (stays behind on march) + extras totaling need_str offensive strength.
static func _war_composition_for_strength(need_str: int) -> Array:
	var comp: Array = _home_kit_composition()
	var options: Array = [
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
	]
	var best_type := GlobalUnits.UNIT_TYPE.ARCHER
	var best_ratio := -1.0
	for t in options:
		var wkey := _weapon_key_for_type(int(t))
		if wkey == "":
			continue
		var cost := GlobalUnits.weapon_mark_price(wkey) + GlobalUnits.arm_training_marks_for_type(int(t))
		cost = maxi(cost, 1)
		var ratio := float(GlobalUnits.unit_strength(int(t))) / float(cost)
		if ratio > best_ratio:
			best_ratio = ratio
			best_type = int(t)
	var per := maxi(1, GlobalUnits.unit_strength(best_type))
	var extra := int(ceil(float(maxi(need_str, 1)) / float(per)))
	extra = maxi(extra, GlobalUnits.MIN_SPLIT_MEN)
	comp.append({"type": best_type, "count": extra})
	return comp


## Legacy alias used nowhere critical — keep for clarity if referenced.
static func _cheapest_composition_for_strength(need_str: int) -> Array:
	return _war_composition_for_strength(need_str)


static func _composition_strength(composition: Array) -> int:
	var total := 0
	for e in composition:
		total += GlobalUnits.unit_strength(int(e.get("type", 0))) * int(e.get("count", 0))
	return total


static func _weapons_for_composition(composition: Array) -> Dictionary:
	return GlobalUnits.weapons_needed_for_composition(composition)


static func _upkeep_reserve(base_map: Node, pid: int) -> int:
	if base_map.has_method("get_player_upkeep_preview"):
		return int(base_map.get_player_upkeep_preview(pid).get("total", 0))
	return 0


static func _marks_spendable(base_map: Node, pid: int) -> int:
	if not base_map.players.has(pid):
		return 0
	var marks := int(base_map.players[pid].game_data.get("marks", 0))
	return maxi(0, marks - _upkeep_reserve(base_map, pid))


static func _merchant_in_province(base_map: Node, prov: Node):
	if base_map.get("merchants") == null or prov == null:
		return null
	for m in base_map.merchants.get_children():
		if bool(m.get("camp_hidden")):
			continue
		if m.get("province") == prov:
			return m
	return null


static func _try_buy_war_weapons(base_map: Node, prov: Node, pid: int, want_comp: Array) -> void:
	if base_map.get("merchants") == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var need := _weapons_for_composition(want_comp)
	var buy: Dictionary = GlobalUnits.empty_weapon_stock()
	var any := false
	for k in need:
		var short := maxi(0, int(need[k]) - int(stock.get(k, 0)))
		if short > 0:
			buy[k] = short
			any = true
	if not any:
		return
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null or not prov.has_dejure(pid):
		return
	var mid := String(merchant.name)
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var spendable := _marks_spendable(base_map, pid)
	var affordable: Dictionary = GlobalUnits.empty_weapon_stock()
	var cost := 0
	for k in buy:
		var unit_p := GlobalUnits.weapon_mark_price_discounted(str(k), competition)
		var can := int(buy[k])
		if unit_p > 0:
			can = mini(can, int(floor(float(spendable - cost) / float(unit_p))))
		if can > 0:
			affordable[k] = can
			cost += unit_p * can
	if cost <= 0 or cost > spendable:
		return
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			mid, affordable, GlobalUnits.empty_material_stock(), pid, cost
		)


## Buy grain for the campaign, never spending below army upkeep reserve.
static func _try_buy_war_grain(
	base_map: Node, prov: Node, pid: int, town: Node, fid: String
) -> void:
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null or not prov.has_dejure(pid):
		return
	var want := 0
	if fid != "" and base_map.forces.has(fid):
		want = _war_grain_wanted(base_map, fid, town)
	else:
		# Rough estimate from staging offensive pool size.
		var pool: Dictionary = _staging_offensive_pool(base_map, prov, pid, "")
		var men := int(pool.get("men", 0))
		if men <= 0:
			men = GlobalUnits.composition_total_men(_home_kit_composition())
		want = GlobalUnits.force_grain_need(men, false) * 5
	var have_cargo := 0
	if fid != "" and base_map.forces.has(fid) and base_map.has_method("get_force_cargo"):
		have_cargo = int(base_map.get_force_cargo(fid).get("grain", 0))
	var stock := int(prov.get_player_grain(pid)) if prov.has_method("get_player_grain") else 0
	var floor_g := _province_grain_floor(base_map, prov, pid)
	var spare := maxi(0, stock - floor_g)
	var short := maxi(0, want - have_cargo - spare)
	if short <= 0:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var unit_p := GlobalUnits.material_mark_price_discounted("grain", competition)
	unit_p = maxi(unit_p, 1)
	var spendable := _marks_spendable(base_map, pid)
	var can := mini(short, int(floor(float(spendable) / float(unit_p))))
	if can <= 0:
		return
	var mats := GlobalUnits.empty_material_stock()
	mats["grain"] = can
	var cost := unit_p * can
	if base_map.has_method("apply_buy_from_merchant"):
		base_map.apply_buy_from_merchant(
			String(merchant.name), GlobalUnits.empty_weapon_stock(), mats, pid, cost
		)


## Craft toward home-kit stock rebuild, then war extras.
static func _set_craft_for_war(base_map: Node, prov: Node, pid: int, want_comp: Array = []) -> void:
	if prov.get("economy") == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var holes := {
		"maces": maxi(0, GlobalUnits.COUNCIL_TARGET_MACEMEN - int(stock.get("maces", 0))),
		"pikes": maxi(0, GlobalUnits.COUNCIL_TARGET_PIKEMEN - int(stock.get("pikes", 0))),
		"bows": maxi(0, GlobalUnits.COUNCIL_TARGET_ARCHERS - int(stock.get("bows", 0))),
	}
	# Also craft war extras beyond home kit if composition asks for more.
	if not want_comp.is_empty():
		var need := _weapons_for_composition(want_comp)
		for k in ["maces", "pikes", "bows"]:
			holes[k] = maxi(int(holes[k]), maxi(0, int(need.get(k, 0)) - int(stock.get(k, 0))))
	var best_key := "maces"
	var bn := -1
	for k in holes:
		if int(holes[k]) > bn:
			bn = int(holes[k])
			best_key = k
	for b in prov.economy.get_children():
		if int(b.get("player_owner")) != pid:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		if int(b.get("subtype")) != 5:
			continue
		if b.has_method("set_craft_weapon"):
			b.set_craft_weapon(best_key)
		elif b.get("craft_weapon") != null:
			b.craft_weapon = best_key


static func _force_strength(base_map: Node, fid: String) -> int:
	if fid == "" or not base_map.forces.has(fid):
		return 0
	if base_map.has_method("get_force_battle_strength_with_vips"):
		return int(base_map.get_force_battle_strength_with_vips(fid, []))
	return GlobalUnits.fighting_strength(base_map.forces[fid].get("units", []))


static func _find_field_army_near_building(base_map: Node, pid: int, building: Node) -> String:
	if building == null or base_map.get("armies") == null:
		return ""
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if _force_adjacent_to_building(base_map, fid, building):
			return fid
	return ""


## Castle inside → outside → town slots for war prep.
static func _staging_garrison_slots(staging: Node) -> Array:
	var out: Array = []
	if staging == null:
		return out
	var castle = staging.get_castle_plot() if staging.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		out.append({"b": castle, "spot": GlobalUnits.SPOT.INSIDE})
		out.append({"b": castle, "spot": GlobalUnits.SPOT.OUTSIDE})
	var town = staging.get_town() if staging.has_method("get_town") else null
	if town != null:
		out.append({"b": town, "spot": GlobalUnits.SPOT.FLAT})
	return out


static func _ensure_spot_garrison(base_map: Node, building: Node, spot: int) -> String:
	if building == null or not base_map.has_method("_building_key"):
		return ""
	var key := str(base_map._building_key(building))
	var fid := ""
	if base_map.has_method("garrison_force_id_for"):
		fid = base_map.garrison_force_id_for(building, spot)
	else:
		fid = "%s_g%d" % [key, spot]
	if not base_map.forces.has(fid):
		base_map.forces[fid] = {
			"units": [],
			"location": {"kind": "garrison", "building": key, "spot": spot},
			"cargo": GlobalUnits.empty_caravan_cargo(),
			"controller": int(building.player_owner) if building.get("player_owner") != null else -1,
		}
	return fid


## All fighting units owned by pid in staging garrisons + field armies in province.
static func _staging_all_units(base_map: Node, staging: Node, pid: int) -> Array:
	var units: Array = _province_garrison_units(base_map, staging, pid)
	if base_map.get("armies") == null:
		return units
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(fid) != staging:
			continue
		units = GlobalUnits.merge_units(units, base_map.forces[fid].get("units", []))
	return units


static func _type_counts_for_pid(units: Array, pid: int) -> Dictionary:
	var out: Dictionary = {}
	for s in units:
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		var t := int(s.get("type", -1))
		out[t] = int(out.get(t, 0)) + int(s.get("count", 0))
	return out


## Levy armed men (or peasants) straight into castle/town; overflow field by town.
static func _war_reinforce_into_garrisons(
	base_map: Node, staging: Node, pid: int, want_comp: Array
) -> void:
	if staging == null or want_comp.is_empty():
		return
	var want_by_type: Dictionary = {}
	for e in want_comp:
		var t := int(e.get("type", -1))
		if t < 0:
			continue
		# Offensive want includes kit + extras; home kit stays on march via reserve.
		want_by_type[t] = int(want_by_type.get(t, 0)) + int(e.get("count", 0))
	# Also ensure kit baseline is in the province pool (counts toward want).
	for e in _home_kit_composition():
		var t := int(e.get("type", -1))
		want_by_type[t] = maxi(int(want_by_type.get(t, 0)), int(e.get("count", 0)))

	var have := _type_counts_for_pid(_staging_all_units(base_map, staging, pid), pid)
	var order: Array = [
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.SWORDSMEN,
		GlobalUnits.UNIT_TYPE.CROSSBOWMEN,
		GlobalUnits.UNIT_TYPE.PEASANT,
	]
	for t in order:
		if not want_by_type.has(t):
			continue
		var short := int(want_by_type[t]) - int(have.get(t, 0))
		if short <= 0:
			continue
		_levy_type_into_staging(base_map, staging, pid, int(t), short)
		have = _type_counts_for_pid(_staging_all_units(base_map, staging, pid), pid)
	for t in want_by_type.keys():
		if int(t) in order:
			continue
		var short2 := int(want_by_type[t]) - int(have.get(t, 0))
		if short2 > 0:
			_levy_type_into_staging(base_map, staging, pid, int(t), short2)


static func _levy_type_into_staging(
	base_map: Node, staging: Node, pid: int, unit_type: int, want: int
) -> void:
	var left := want
	if left <= 0:
		return
	# Prefer armed levy into garrison spots; peasants if no weapons / for arming later.
	var wkey := _weapon_key_for_type(unit_type)
	var stock: Dictionary = staging.get_weapons_for(pid) if staging.has_method("get_weapons_for") else {}
	var weapons_have := int(stock.get(wkey, 0)) if wkey != "" else 0
	var levy_armed := unit_type != GlobalUnits.UNIT_TYPE.PEASANT and wkey != ""

	for slot in _staging_garrison_slots(staging):
		if left <= 0:
			return
		var room := _garrison_room(base_map, slot["b"], int(slot["spot"]))
		if room <= 0:
			continue
		var n := mini(left, room)
		n = _clamp_levy_men(base_map, staging, pid, n, true)
		if n <= 0:
			continue
		if levy_armed:
			n = mini(n, weapons_have)
			if n <= 0:
				# Fall back to peasants into this spot for later arming.
				n = mini(left, room)
				n = _clamp_levy_men(base_map, staging, pid, n, true)
				if n <= 0:
					continue
				if not _add_units_to_garrison(
					base_map, staging, pid, slot["b"], int(slot["spot"]),
					[{"type": GlobalUnits.UNIT_TYPE.PEASANT, "count": n}]
				):
					continue
				left -= n
				continue
			var need := GlobalUnits.weapons_needed_for_composition(
				[{"type": unit_type, "count": n}]
			)
			if not staging.can_afford_weapons_for(pid, need):
				continue
			if not _add_units_to_garrison(
				base_map, staging, pid, slot["b"], int(slot["spot"]),
				[{"type": unit_type, "count": n}]
			):
				continue
			staging.subtract_weapons_for(pid, need)
			weapons_have = maxi(0, weapons_have - n)
			left -= n
		else:
			if not _add_units_to_garrison(
				base_map, staging, pid, slot["b"], int(slot["spot"]),
				[{"type": GlobalUnits.UNIT_TYPE.PEASANT, "count": n}]
			):
				continue
			left -= n

	# Overflow: field army next to town (only if enough for a legal field stack).
	if left >= GlobalUnits.MIN_SPLIT_MEN:
		var raise_n := _clamp_levy_men(base_map, staging, pid, left, false)
		if raise_n >= GlobalUnits.MIN_SPLIT_MEN:
			var fid := ""
			if levy_armed and weapons_have > 0:
				raise_n = mini(raise_n, weapons_have)
				if raise_n >= GlobalUnits.MIN_SPLIT_MEN:
					fid = _levy_composition_field(
						base_map, staging, pid,
						[{"type": unit_type, "count": raise_n}]
					)
			else:
				fid = _levy_peasants(base_map, staging, pid, raise_n)
			if fid != "":
				left -= raise_n


static func _clamp_levy_men(
	base_map: Node, prov: Node, pid: int, want: int, as_garrison: bool
) -> int:
	if want <= 0:
		return 0
	var happy := _happiness_levy_budget(prov, pid)
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var grain_need := 0
	if prov.has_method("grain_labor_required"):
		grain_need = int(prov.grain_labor_required(pid, int(base_map.season)))
	var levy_left := int(prov.max_levy_remaining()) if prov.has_method("max_levy_remaining") else want
	var allowed := mini(want, mini(happy, mini(levy_left, maxi(0, pop - grain_need))))
	if allowed <= 0:
		return 0
	if prov.has_method("preview_holding_rations"):
		var preview: Dictionary = prov.preview_holding_rations(pid)
		var stock := int(preview.get("stock", 0))
		var seed_r := int(preview.get("seed_reserve", 0))
		var army_need := int(preview.get("army_need", 0)) + GlobalUnits.force_grain_need(
			allowed, as_garrison
		)
		var civ_pop := maxi(0, pop - allowed)
		var people_budget := maxi(0, stock - seed_r - army_need)
		if GlobalUnits.affordable_ration(civ_pop, GlobalUnits.RATION_DEFAULT, people_budget) < GlobalUnits.RATION_DEFAULT:
			# Binary shrink.
			while allowed > 0:
				allowed = int(allowed / 2)
				if allowed <= 0:
					return 0
				army_need = int(preview.get("army_need", 0)) + GlobalUnits.force_grain_need(
					allowed, as_garrison
				)
				civ_pop = maxi(0, pop - allowed)
				people_budget = maxi(0, stock - seed_r - army_need)
				if GlobalUnits.affordable_ration(civ_pop, GlobalUnits.RATION_DEFAULT, people_budget) >= GlobalUnits.RATION_DEFAULT:
					break
	return allowed


static func _add_units_to_garrison(
	base_map: Node,
	prov: Node,
	pid: int,
	building: Node,
	spot: int,
	composition: Array
) -> bool:
	var men := GlobalUnits.composition_total_men(composition)
	if men <= 0 or building == null:
		return false
	var room := _garrison_room(base_map, building, spot)
	if men > room:
		return false
	var fid := _ensure_spot_garrison(base_map, building, spot)
	if fid == "" or not base_map.forces.has(fid):
		return false
	if not prov.deduct_population(pid, men):
		return false
	var prev_levied := int(prov.levied_this_season)
	prov.levied_this_season = prev_levied + men
	if prov.has_method("apply_levy_happiness"):
		prov.apply_levy_happiness(prev_levied, prov.levied_this_season)
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
	if building.has_method("set_flags"):
		building.set_flags()
	if base_map.has_method("update_players_population"):
		base_map.update_players_population()
	return true


static func _levy_composition_field(
	base_map: Node, prov: Node, pid: int, composition: Array
) -> String:
	var men := GlobalUnits.composition_total_men(composition)
	if men < GlobalUnits.MIN_SPLIT_MEN:
		return ""
	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if GlobalUnits.weapon_stock_has_any(need) and not prov.can_afford_weapons_for(pid, need):
		return ""
	if not base_map.has_method("_try_recruit_levy"):
		return ""
	var before: Dictionary = {}
	for existing_fid in base_map.forces.keys():
		before[str(existing_fid)] = true
	var err := String(base_map._try_recruit_levy(String(prov.name), composition, pid))
	if err != "":
		return ""
	for existing_fid in base_map.forces.keys():
		var fid := str(existing_fid)
		if before.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) == pid:
			return fid
	return _find_field_army(base_map, pid, prov)


static func _arm_staging_war_forces(
	base_map: Node, staging: Node, pid: int, want_comp: Array
) -> void:
	var want_by_type: Dictionary = {}
	for e in want_comp:
		var t := int(e.get("type", -1))
		if t < 0:
			continue
		want_by_type[t] = int(want_by_type.get(t, 0)) + int(e.get("count", 0))
	var fids: Array = []
	for slot in _staging_garrison_slots(staging):
		var gid := _ensure_spot_garrison(base_map, slot["b"], int(slot["spot"]))
		if gid != "":
			fids.append(gid)
	var field := _find_field_army(base_map, pid, staging)
	if field != "":
		fids.append(field)
	for fid in fids:
		if not base_map.forces.has(fid):
			continue
		var have := _type_counts_for_pid(_staging_all_units(base_map, staging, pid), pid)
		var residual: Array = []
		for t in want_by_type.keys():
			var short := int(want_by_type[t]) - int(have.get(t, 0))
			if short > 0:
				residual.append({"type": int(t), "count": short})
		if residual.is_empty():
			return
		_arm_war_force(base_map, fid, pid, residual)


## Merge every owned field army in the province onto one stack (move via town if needed).
static func _merge_province_field_armies(
	base_map: Node, pid: int, prov: Node, war: Dictionary
) -> void:
	if prov == null or base_map.get("armies") == null:
		return
	var ids: Array = []
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(fid) != prov:
			continue
		if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) <= 0:
			continue
		ids.append(fid)
	if ids.size() <= 1:
		if ids.size() == 1:
			war["force_id"] = str(ids[0])
		return
	var main := str(war.get("force_id", ""))
	if main == "" or not (main in ids):
		main = str(ids[0])
		var best_men := GlobalUnits.total_men(base_map.forces[main].get("units", []))
		for fid in ids:
			var m := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
			if m > best_men:
				best_men = m
				main = str(fid)
	war["force_id"] = main
	var town = prov.get_town() if prov.has_method("get_town") else null
	for fid in ids:
		if fid == main or not base_map.forces.has(fid) or not base_map.forces.has(main):
			continue
		if _forces_same_or_adjacent_cell(base_map, main, fid):
			if base_map.has_method("apply_merge_forces"):
				base_map.apply_merge_forces(main, fid)
			continue
		# Pull both toward town so they meet.
		if town != null:
			_move_force_toward_building(base_map, fid, town)
			_move_force_toward_building(base_map, main, town)
		if base_map.forces.has(fid) and base_map.forces.has(main) \
				and _forces_same_or_adjacent_cell(base_map, main, fid) \
				and base_map.has_method("apply_merge_forces"):
			base_map.apply_merge_forces(main, fid)


## Park field army into castle/town; overflow stays beside town.
static func _absorb_field_into_garrison(
	base_map: Node, pid: int, prov: Node, prefer_fid: String
) -> void:
	var fid := prefer_fid
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, prov)
	if fid != "":
		_garrison_force_while_waiting(base_map, pid, prov, fid)
	if base_map.get("armies") == null:
		return
	for fig in base_map.armies.get_children():
		var other := String(fig.name)
		if other == fid or not base_map.forces.has(other):
			continue
		var loc: Dictionary = base_map.forces[other].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(other)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
			continue
		_garrison_force_while_waiting(base_map, pid, prov, other)


## Absorb every staging field army except the march drip stack.
static func _absorb_other_field_into_garrison(
	base_map: Node, pid: int, prov: Node, keep_fid: String
) -> void:
	if base_map.get("armies") == null:
		return
	var ids: Array = []
	for fig in base_map.armies.get_children():
		var other := String(fig.name)
		if other == keep_fid or not base_map.forces.has(other):
			continue
		var loc: Dictionary = base_map.forces[other].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(other)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
			continue
		ids.append(other)
	for other in ids:
		_defense_ingest_field_force(base_map, pid, prov, other)


## Slots used to park expelled / stray field troops.
## Always include town + villages so overflow has somewhere to go during upgrades.
static func _defense_park_slots(prov: Node) -> Array:
	var out: Array = []
	if prov == null:
		return out
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		out.append({"b": castle, "spot": GlobalUnits.SPOT.INSIDE})
		out.append({"b": castle, "spot": GlobalUnits.SPOT.OUTSIDE})
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		out.append({"b": town, "spot": GlobalUnits.SPOT.FLAT})
	if prov.get("settlements") != null:
		for s in prov.settlements.get_children():
			if s == town:
				continue
			if int(s.get("type_")) == int(GlobalStuff.BUILDING_TYPE.VILLAGE):
				out.append({"b": s, "spot": GlobalUnits.SPOT.FLAT})
	return out


## Park a field force into holding garrisons with no adjacency / MP checks.
## Castle upgrades expel onto arbitrary free tiles; normal garrison rules can't reach them.
static func _defense_ingest_field_force(
	base_map: Node, pid: int, prov: Node, fid: String
) -> void:
	if not base_map.forces.has(fid) or prov == null:
		return
	var loc: Dictionary = base_map.forces[fid].get("location", {})
	if str(loc.get("kind", "")) != "cell":
		return
	var targets: Array = _defense_park_slots(prov)
	if targets.is_empty():
		return
	var last_dest := ""
	for t in targets:
		if not base_map.forces.has(fid):
			return
		var room := _garrison_room(base_map, t["b"], int(t["spot"]))
		if room <= 0:
			continue
		var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
		if men <= 0:
			break
		var take_n := mini(room, men)
		var out_units := _extract_any_stacks(base_map.forces[fid].get("units", []), pid, take_n)
		if out_units.is_empty():
			continue
		var dest_gid := _ensure_spot_garrison(base_map, t["b"], int(t["spot"]))
		if dest_gid == "":
			continue
		GlobalUnits.subtract_units(base_map.forces[fid]["units"], out_units)
		base_map.forces[dest_gid]["units"] = GlobalUnits.merge_units(
			base_map.forces[dest_gid].get("units", []),
			GlobalUnits.units_from_spec(out_units)
		)
		last_dest = dest_gid
		if base_map.has_method("_building_key") and base_map.has_method("refresh_building_flags"):
			base_map.refresh_building_flags(str(base_map._building_key(t["b"])))
	if not base_map.forces.has(fid):
		return
	if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) <= 0:
		if last_dest != "" and base_map.has_method("_flush_cargo_if_force_empty"):
			base_map._flush_cargo_if_force_empty(fid, last_dest)
		if base_map.has_method("_cleanup_force_if_empty"):
			base_map._cleanup_force_if_empty(fid)
		if base_map.get("pathfinding") != null and base_map.pathfinding.has_method("rebuild_occupancy"):
			base_map.pathfinding.rebuild_occupancy()
		if base_map.has_method("update_all_army_visuals"):
			base_map.update_all_army_visuals()


## Before starting an upgrade, move castle troops into town/villages so expel is a no-op.
static func _defense_evacuate_castle_for_upgrade(
	base_map: Node, prov: Node, pid: int, castle: Node
) -> void:
	if castle == null or not castle.has_method("is_operational") or not castle.is_operational():
		return
	if not base_map.has_method("apply_transfer_units"):
		return
	var sinks: Array = []
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		sinks.append({"b": town, "spot": GlobalUnits.SPOT.FLAT})
	if prov.get("settlements") != null:
		for s in prov.settlements.get_children():
			if s == town:
				continue
			if int(s.get("type_")) == int(GlobalStuff.BUILDING_TYPE.VILLAGE):
				sinks.append({"b": s, "spot": GlobalUnits.SPOT.FLAT})
	for src_spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
		var src_gid := _ensure_spot_garrison(base_map, castle, src_spot)
		if src_gid == "" or not base_map.forces.has(src_gid):
			continue
		for sink in sinks:
			if not base_map.forces.has(src_gid):
				break
			var have := GlobalUnits.total_men(base_map.forces[src_gid].get("units", []))
			if have <= 0:
				break
			var room := _garrison_room(base_map, sink["b"], int(sink["spot"]))
			if room <= 0:
				continue
			var take_n := mini(room, have)
			var out_units := _extract_any_stacks(
				base_map.forces[src_gid].get("units", []), pid, take_n
			)
			if out_units.is_empty():
				continue
			var dest_gid := _ensure_spot_garrison(base_map, sink["b"], int(sink["spot"]))
			if dest_gid == "":
				continue
			base_map.apply_transfer_units(src_gid, dest_gid, out_units, {})


static func _ensure_war_force(
	base_map: Node, pid: int, staging: Node, war: Dictionary, want_comp: Array
) -> String:
	# Legacy path — prefer garrison prep. Keep for callers / overflow.
	var fid := str(war.get("force_id", ""))
	if fid != "" and base_map.forces.has(fid):
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) == "cell":
			var ctrl := int(base_map.get_force_controller(fid)) if base_map.has_method("get_force_controller") else -1
			if ctrl == pid:
				return fid
	fid = _find_field_army(base_map, pid, staging)
	if fid != "":
		return fid
	return _find_field_army(base_map, pid)


static func _find_field_army(base_map: Node, pid: int, prefer_prov: Node = null) -> String:
	if base_map.get("armies") == null:
		return ""
	var fallback := ""
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if GlobalUnits.total_men(base_map.forces[fid].get("units", [])) <= 0:
			continue
		if prefer_prov != null and base_map.has_method("province_under_force"):
			if base_map.province_under_force(fid) == prefer_prov:
				return fid
		if fallback == "":
			fallback = fid
	return fallback


static func _levy_peasants(base_map: Node, prov: Node, pid: int, want_men: int) -> String:
	var happy := _happiness_levy_budget(prov, pid)
	var pop := int(prov.owned_settlement_population(pid)) if prov.has_method("owned_settlement_population") else 0
	var grain_need := 0
	if prov.has_method("grain_labor_required"):
		grain_need = int(prov.grain_labor_required(pid, int(base_map.season)))
	var levy_left := int(prov.max_levy_remaining()) if prov.has_method("max_levy_remaining") else want_men
	var allowed := mini(want_men, mini(happy, mini(levy_left, maxi(0, pop - grain_need))))
	if allowed < GlobalUnits.MIN_SPLIT_MEN:
		return ""
	# Don't break Normal rations.
	if prov.has_method("preview_holding_rations"):
		var preview: Dictionary = prov.preview_holding_rations(pid)
		var stock := int(preview.get("stock", 0))
		var seed_r := int(preview.get("seed_reserve", 0))
		var army_need := int(preview.get("army_need", 0)) + GlobalUnits.force_grain_need(allowed, false)
		var civ_pop := maxi(0, pop - allowed)
		var people_budget := maxi(0, stock - seed_r - army_need)
		if GlobalUnits.affordable_ration(civ_pop, GlobalUnits.RATION_DEFAULT, people_budget) < GlobalUnits.RATION_DEFAULT:
			return ""
	var composition: Array = [{"type": GlobalUnits.UNIT_TYPE.PEASANT, "count": allowed}]
	if not base_map.has_method("_try_recruit_levy"):
		return ""
	var before: Dictionary = {}
	for existing_fid in base_map.forces.keys():
		before[str(existing_fid)] = true
	var err := String(base_map._try_recruit_levy(String(prov.name), composition, pid))
	if err != "":
		return ""
	for existing_fid in base_map.forces.keys():
		var fid := str(existing_fid)
		if before.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) == pid:
			return fid
	return _find_field_army(base_map, pid, prov)


static func _maybe_levy_peasants_for_war(
	base_map: Node, staging: Node, pid: int, fid: String, want_comp: Array
) -> void:
	if not base_map.forces.has(fid):
		return
	var pool: Dictionary = _staging_offensive_pool(base_map, staging, pid, fid)
	var have_str := int(pool.get("strength", 0))
	var need_str := _composition_strength(want_comp)
	if have_str >= need_str:
		return
	var peasants := GlobalUnits.count_armable_peasants(base_map.forces[fid].get("units", []), pid)
	var stock: Dictionary = staging.get_weapons_for(pid) if staging.has_method("get_weapons_for") else {}
	var weapons_have := 0
	for e in want_comp:
		var wkey := _weapon_key_for_type(int(e.get("type", 0)))
		if wkey != "":
			weapons_have += int(stock.get(wkey, 0))
	var short_men := maxi(
		0,
		GlobalUnits.composition_total_men(want_comp) - int(pool.get("men", 0))
	)
	var can_arm := weapons_have + peasants
	if can_arm >= short_men and peasants >= mini(short_men, weapons_have):
		return
	var raise_n := maxi(GlobalUnits.MIN_SPLIT_MEN, mini(short_men, weapons_have + 50))
	var new_id := _levy_peasants(base_map, staging, pid, raise_n)
	if new_id != "" and new_id != fid and base_map.has_method("apply_merge_forces"):
		if _forces_same_or_adjacent_cell(base_map, fid, new_id):
			base_map.apply_merge_forces(fid, new_id)


## Arm kit holes first (mace→pike→archer), then remaining want_comp entries.
static func _arm_war_force(base_map: Node, fid: String, pid: int, want_comp: Array) -> void:
	if not base_map.forces.has(fid) or want_comp.is_empty():
		return
	if not base_map.has_method("apply_arm_peasants") or not base_map.has_method("_composition_to_packed"):
		return
	# Collapse want_comp to type → count.
	var want_by_type: Dictionary = {}
	for e in want_comp:
		var t := int(e.get("type", -1))
		if t < 0:
			continue
		want_by_type[t] = int(want_by_type.get(t, 0)) + int(e.get("count", 0))
	var order: Array = [
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.SWORDSMEN,
		GlobalUnits.UNIT_TYPE.CROSSBOWMEN,
	]
	for t in order:
		if not want_by_type.has(t):
			continue
		_arm_force_toward_type(base_map, fid, pid, int(t), int(want_by_type[t]))
	for t in want_by_type.keys():
		if int(t) in order:
			continue
		_arm_force_toward_type(base_map, fid, pid, int(t), int(want_by_type[t]))


static func _arm_force_toward_type(
	base_map: Node, fid: String, pid: int, unit_type: int, want_count: int
) -> void:
	if not base_map.forces.has(fid) or want_count <= 0:
		return
	var have := 0
	for s in base_map.forces[fid].get("units", []):
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		if int(s.get("type", -1)) == unit_type:
			have += int(s.get("count", 0))
	var short := want_count - have
	if short <= 0:
		return
	var peasants := GlobalUnits.count_armable_peasants(base_map.forces[fid].get("units", []), pid)
	if peasants <= 0:
		return
	var pool: Dictionary = {}
	if base_map.has_method("arm_weapon_pool_for"):
		pool = base_map.arm_weapon_pool_for(fid, pid)
	var wkey := _weapon_key_for_type(unit_type)
	if wkey == "":
		return
	var can := mini(short, mini(peasants, int(pool.get(wkey, 0))))
	if can <= 0:
		return
	var marks := int(base_map.players[pid].game_data.get("marks", 0))
	var reserve := _upkeep_reserve(base_map, pid)
	var spendable := maxi(0, marks - reserve)
	var train := GlobalUnits.arm_training_marks_for_type(unit_type)
	if train > 0:
		can = mini(can, int(floor(float(spendable) / float(train))))
	if can <= 0:
		return
	var composition: Array = [{"type": unit_type, "count": can}]
	var packed: PackedInt32Array = base_map._composition_to_packed(composition)
	base_map.apply_arm_peasants(fid, packed, pid)


static func _count_type_in_units(units: Array, pid: int, unit_type: int) -> int:
	var n := 0
	for s in units:
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		if int(s.get("type", -1)) == unit_type:
			n += int(s.get("count", 0))
	return n


## Pull up to home-kit counts from town garrison into the field army.
static func _pull_kit_from_town_garrison(
	base_map: Node, staging: Node, pid: int, fid: String
) -> void:
	if not base_map.forces.has(fid) or staging == null:
		return
	var town = staging.get_town() if staging.has_method("get_town") else null
	if town == null:
		return
	if not _force_adjacent_to_building(base_map, fid, town):
		_move_force_toward_building(base_map, fid, town)
		if not _force_adjacent_to_building(base_map, fid, town):
			return
	var key := str(base_map._building_key(town)) if base_map.has_method("_building_key") else ""
	if key == "" or not base_map.has_method("apply_batch_garrison_units"):
		return
	var gid = base_map.garrison_force_id_for(town, GlobalUnits.SPOT.FLAT) if base_map.has_method("garrison_force_id_for") else ""
	if gid == "" or not base_map.forces.has(gid):
		return
	var from_g: Array = []
	for t in [
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
		GlobalUnits.UNIT_TYPE.ARCHER,
	]:
		var want := 0
		match t:
			GlobalUnits.UNIT_TYPE.MACEMEN:
				want = GlobalUnits.COUNCIL_TARGET_MACEMEN
			GlobalUnits.UNIT_TYPE.PIKEMEN:
				want = GlobalUnits.COUNCIL_TARGET_PIKEMEN
			_:
				want = GlobalUnits.COUNCIL_TARGET_ARCHERS
		var have_field := _count_type_in_units(base_map.forces[fid].get("units", []), pid, t)
		var short := want - have_field
		if short <= 0:
			continue
		var taken := _extract_type_stacks(base_map.forces[gid].get("units", []), pid, t, short)
		for s in taken:
			from_g.append(s)
	if from_g.is_empty():
		return
	base_map.apply_batch_garrison_units(
		fid, key, GlobalUnits.SPOT.FLAT, [], from_g,
		GlobalUnits.empty_caravan_cargo(), GlobalUnits.empty_caravan_cargo()
	)


static func _extract_type_stacks(
	units: Array, pid: int, unit_type: int, want: int
) -> Array:
	var out: Array = []
	var left := want
	for s in units:
		if left <= 0:
			break
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		if int(s.get("type", -1)) != unit_type:
			continue
		var take := mini(left, int(s.get("count", 0)))
		if take <= 0:
			continue
		out.append(GlobalUnits.make_stack(
			unit_type,
			pid,
			int(s.get("source", GlobalUnits.SOURCE.LEVY)),
			take,
			int(s.get("status", GlobalUnits.STATUS.FIGHTING)),
			int(s.get("recover_in", 0)),
			bool(s.get("join_pending", false)),
			bool(s.get("militia", false))
		))
		left -= take
	return out


## Field + staging garrisons; strength after reserving home kit for defense.
static func _staging_offensive_pool(
	base_map: Node, staging: Node, pid: int, fid: String
) -> Dictionary:
	var units: Array = _staging_all_units(base_map, staging, pid)
	var field_id := fid
	if field_id == "" or not base_map.forces.has(field_id):
		field_id = _find_field_army(base_map, pid, staging)
	var offensive: Array = _units_after_kit_reserve(units, pid)
	return {
		"units": offensive,
		"men": GlobalUnits.fighting_men(offensive),
		"strength": GlobalUnits.fighting_strength(offensive),
		"field_id": field_id,
	}


static func _province_garrison_units(base_map: Node, prov: Node, pid: int) -> Array:
	var out: Array = []
	if prov == null or not base_map.has_method("get_building_garrison"):
		return out
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		for s in base_map.get_building_garrison(town, GlobalUnits.SPOT.FLAT):
			if int(s.get("owner", -1)) == pid:
				GlobalUnits.add_stack(out, GlobalUnits.make_stack(
					int(s.get("type", 0)), pid,
					int(s.get("source", GlobalUnits.SOURCE.LEVY)),
					int(s.get("count", 0)),
					int(s.get("status", GlobalUnits.STATUS.FIGHTING)),
					int(s.get("recover_in", 0)),
					bool(s.get("join_pending", false)),
					bool(s.get("militia", false))
				))
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			for s in base_map.get_building_garrison(castle, spot):
				if int(s.get("owner", -1)) == pid:
					GlobalUnits.add_stack(out, GlobalUnits.make_stack(
						int(s.get("type", 0)), pid,
						int(s.get("source", GlobalUnits.SOURCE.LEVY)),
						int(s.get("count", 0)),
						int(s.get("status", GlobalUnits.STATUS.FIGHTING)),
						int(s.get("recover_in", 0)),
						bool(s.get("join_pending", false)),
						bool(s.get("militia", false))
					))
	return out


## Remove up to 100/100/100 of each kit type (home reserve) from a units clone.
static func _units_after_kit_reserve(units: Array, pid: int) -> Array:
	var clone: Array = GlobalUnits.clone_units(units)
	var reserve := {
		GlobalUnits.UNIT_TYPE.MACEMEN: GlobalUnits.COUNCIL_TARGET_MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN: GlobalUnits.COUNCIL_TARGET_PIKEMEN,
		GlobalUnits.UNIT_TYPE.ARCHER: GlobalUnits.COUNCIL_TARGET_ARCHERS,
	}
	for t in reserve.keys():
		var left := int(reserve[t])
		for s in clone:
			if left <= 0:
				break
			if int(s.get("owner", -1)) != pid:
				continue
			if not GlobalUnits.is_fighting_stack(s):
				continue
			if int(s.get("type", -1)) != int(t):
				continue
			var take := mini(left, int(s.get("count", 0)))
			s["count"] = int(s["count"]) - take
			left -= take
	var cleaned: Array = []
	for s in clone:
		if int(s.get("count", 0)) > 0:
			cleaned.append(s)
	return cleaned


## Fill castle inside → outside → town; overflow stays in the field.
static func _garrison_force_while_waiting(
	base_map: Node, pid: int, prov: Node, fid: String
) -> void:
	if not base_map.forces.has(fid) or prov == null:
		return
	var loc: Dictionary = base_map.forces[fid].get("location", {})
	if str(loc.get("kind", "")) != "cell":
		return
	if not base_map.has_method("apply_garrison_units"):
		return
	var targets: Array = _staging_garrison_slots(prov)
	# Mid-upgrade: castle is offline — park into town.
	if targets.is_empty():
		var town_only = prov.get_town() if prov.has_method("get_town") else null
		if town_only != null:
			targets = [{"b": town_only, "spot": GlobalUnits.SPOT.FLAT}]
	if targets.is_empty():
		return

	# Prefer castle approach first so inside/outside actually fill.
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	var town = prov.get_town() if prov.has_method("get_town") else null
	var anchor = null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		if _garrison_room(base_map, castle, GlobalUnits.SPOT.INSIDE) > 0 \
				or _garrison_room(base_map, castle, GlobalUnits.SPOT.OUTSIDE) > 0:
			anchor = castle
	if anchor == null and town != null and _garrison_room(base_map, town, GlobalUnits.SPOT.FLAT) > 0:
		anchor = town
	if anchor == null:
		# Still try town even if "full" — remnant may fit after MIN_SPLIT rules.
		anchor = town if town != null else castle
	if anchor == null:
		return
	if not _force_adjacent_to_building(base_map, fid, anchor):
		# Expelled stacks spawn with 0 MP — snap onto a free approach tile.
		if not _snap_force_to_building_approach(base_map, fid, anchor):
			_move_force_toward_building(base_map, fid, anchor)
			if not _force_adjacent_to_building(base_map, fid, anchor):
				var alt = town if anchor == castle else castle
				if alt != null and (
					_force_adjacent_to_building(base_map, fid, alt)
					or _snap_force_to_building_approach(base_map, fid, alt)
				):
					anchor = alt
				else:
					if alt != null:
						_move_force_toward_building(base_map, fid, alt)
					return

	for t in targets:
		if not base_map.forces.has(fid):
			return
		# Must be adjacent to this building to garrison into it.
		if not _force_adjacent_to_building(base_map, fid, t["b"]):
			if not _snap_force_to_building_approach(base_map, fid, t["b"]):
				_move_force_toward_building(base_map, fid, t["b"])
				if not _force_adjacent_to_building(base_map, fid, t["b"]):
					continue
		var room := _garrison_room(base_map, t["b"], int(t["spot"]))
		if room <= 0:
			continue
		var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
		var max_in := men
		if men > GlobalUnits.MIN_SPLIT_MEN:
			max_in = men - GlobalUnits.MIN_SPLIT_MEN
		if men <= room:
			max_in = men
		var take_n := mini(room, max_in)
		if take_n <= 0:
			continue
		if men - take_n > 0 and men - take_n < GlobalUnits.MIN_SPLIT_MEN:
			if room >= men:
				take_n = men
			else:
				take_n = maxi(0, men - GlobalUnits.MIN_SPLIT_MEN)
		if take_n <= 0:
			continue
		var out_units := _extract_any_stacks(base_map.forces[fid].get("units", []), pid, take_n)
		if out_units.is_empty():
			continue
		var bkey := str(base_map._building_key(t["b"])) if base_map.has_method("_building_key") else ""
		if bkey == "":
			continue
		base_map.apply_garrison_units(fid, bkey, int(t["spot"]), out_units)


## Place a field force on a free approach cell of `building` (for 0-MP expels).
static func _snap_force_to_building_approach(base_map: Node, fid: String, building: Node) -> bool:
	var pf = base_map.get("pathfinding")
	if pf == null or building == null or not base_map.forces.has(fid):
		return false
	var fig = base_map.armies.get_node_or_null(fid)
	if fig == null:
		return false
	if _force_adjacent_to_building(base_map, fid, building):
		return true
	var approach: Array[Vector2i] = pf.get_approach_cells(building) if pf.has_method("get_approach_cells") else []
	for cell in approach:
		if pf.get("walkable_cells") != null and not pf.walkable_cells.has(cell):
			continue
		if pf.occupancy.has(cell) and pf.occupancy[cell] != fig:
			continue
		if pf.has_method("place_army_at_cell"):
			pf.place_army_at_cell(fig, cell)
		if pf.has_method("rebuild_occupancy"):
			pf.rebuild_occupancy()
		return _force_adjacent_to_building(base_map, fid, building)
	# Last resort: nearest free cell from map helper (may still be approach).
	if base_map.has_method("get_nearest_free_cell_for_building"):
		var cell2: Vector2i = base_map.get_nearest_free_cell_for_building(building)
		if cell2 != Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
			if pf.has_method("place_army_at_cell"):
				pf.place_army_at_cell(fig, cell2)
			if pf.has_method("rebuild_occupancy"):
				pf.rebuild_occupancy()
			return _force_adjacent_to_building(base_map, fid, building)
	return false


static func _garrison_room(base_map: Node, building: Node, spot: int) -> int:
	if building == null or not building.has_method("get_garrison_capacity"):
		return 0
	var cap := int(building.get_garrison_capacity(spot))
	var have := GlobalUnits.total_men(base_map.get_building_garrison(building, spot))
	return maxi(0, cap - have)


static func _extract_any_stacks(units: Array, pid: int, want_men: int) -> Array:
	var out: Array = []
	var left := want_men
	for s in units:
		if left <= 0:
			break
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		var take := mini(left, int(s.get("count", 0)))
		if take <= 0:
			continue
		out.append(GlobalUnits.make_stack(
			int(s.get("type", 0)),
			pid,
			int(s.get("source", GlobalUnits.SOURCE.LEVY)),
			take,
			int(s.get("status", GlobalUnits.STATUS.FIGHTING)),
			int(s.get("recover_in", 0)),
			bool(s.get("join_pending", false)),
			bool(s.get("militia", false))
		))
		left -= take
	return out


## Sortie staging garrisons (leave home kit), merge into war field force.
static func _mobilize_war_force_for_march(
	base_map: Node, staging: Node, pid: int, war: Dictionary
) -> String:
	var fid := str(war.get("force_id", ""))
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, staging)
	var castle = staging.get_castle_plot() if staging.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			fid = _sortie_building_owned(base_map, staging, pid, castle, spot, fid, false, -1)
	var town = staging.get_town() if staging.has_method("get_town") else null
	if town != null:
		fid = _sortie_building_owned(base_map, staging, pid, town, GlobalUnits.SPOT.FLAT, fid, true, -1)
	if fid != "":
		_merge_other_field_armies(base_map, pid, fid, staging)
	return fid


## Drip a chunk of offensive men onto one field stack by the town; load happens separately.
static func _drip_feed_march_force(
	base_map: Node, staging: Node, pid: int, war: Dictionary, need_str: int
) -> String:
	var fid := str(war.get("force_id", ""))
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, staging)
	var town = staging.get_town() if staging.has_method("get_town") else null
	# How many offensive men still sitting in garrisons?
	var pool: Dictionary = _staging_offensive_pool(base_map, staging, pid, fid)
	var field_men := 0
	if fid != "" and base_map.forces.has(fid):
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) == "cell":
			field_men = GlobalUnits.fighting_men(base_map.forces[fid].get("units", []))
	var field_str := _force_strength(base_map, fid) if fid != "" else 0
	# Still need more in the field for 1.3×?
	var need_more_str := field_str < need_str
	if not need_more_str and field_men >= GlobalUnits.MIN_SPLIT_MEN:
		# Already strong enough in field — just park by town for grain.
		if town != null and fid != "" and base_map.forces.has(fid):
			if not _force_adjacent_to_building(base_map, fid, town):
				_move_force_toward_building(base_map, fid, town)
		return fid

	var remaining_men := maxi(0, int(pool.get("men", 0)) - field_men)
	if remaining_men < GlobalUnits.MIN_SPLIT_MEN and field_men <= 0:
		# Nothing to drip yet.
		return fid
	var chunk := remaining_men
	if remaining_men > GlobalUnits.MIN_SPLIT_MEN:
		chunk = clampi(
			int(ceil(float(remaining_men) / 4.0)),
			GlobalUnits.MIN_SPLIT_MEN,
			WAR_DRIP_MEN_CAP
		)
		chunk = mini(chunk, remaining_men)

	# Castle first (no kit reserve), then town excess above kit.
	var left := chunk
	var castle = staging.get_castle_plot() if staging.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational() and left > 0:
		for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
			if left <= 0:
				break
			var before_men := 0
			if fid != "" and base_map.forces.has(fid):
				before_men = GlobalUnits.total_men(base_map.forces[fid].get("units", []))
			fid = _sortie_building_owned(
				base_map, staging, pid, castle, spot, fid, false, left
			)
			var after_men := 0
			if fid != "" and base_map.forces.has(fid):
				after_men = GlobalUnits.total_men(base_map.forces[fid].get("units", []))
			left = maxi(0, left - maxi(0, after_men - before_men))
	if town != null and left > 0:
		var before2 := 0
		if fid != "" and base_map.forces.has(fid):
			before2 = GlobalUnits.total_men(base_map.forces[fid].get("units", []))
		fid = _sortie_building_owned(
			base_map, staging, pid, town, GlobalUnits.SPOT.FLAT, fid, true, left
		)
		var after2 := 0
		if fid != "" and base_map.forces.has(fid):
			after2 = GlobalUnits.total_men(base_map.forces[fid].get("units", []))
		left = maxi(0, left - maxi(0, after2 - before2))

	if fid != "":
		_merge_province_field_armies(base_map, pid, staging, war)
		fid = str(war.get("force_id", fid))
		if not base_map.forces.has(fid):
			fid = _find_field_army(base_map, pid, staging)
		if town != null and fid != "" and base_map.forces.has(fid):
			if not _force_adjacent_to_building(base_map, fid, town):
				_move_force_toward_building(base_map, fid, town)
	return fid


## Sortie owned men from a spot. If keep_kit, leave up to 100/100/100 behind.
## max_men < 0 → all eligible; else cap how many leave this call.
static func _sortie_building_owned(
	base_map: Node,
	staging: Node,
	pid: int,
	building: Node,
	spot: int,
	merge_into: String,
	keep_kit: bool,
	max_men: int = -1
) -> String:
	if building == null or not base_map.has_method("apply_sortie_units"):
		return merge_into
	var gid = base_map.garrison_force_id_for(building, spot) if base_map.has_method("garrison_force_id_for") else ""
	if gid == "" or not base_map.forces.has(gid):
		return merge_into
	var units: Array = GlobalUnits.clone_units(base_map.forces[gid].get("units", []))
	var out_units: Array = []
	if keep_kit:
		var reserve := {
			GlobalUnits.UNIT_TYPE.MACEMEN: GlobalUnits.COUNCIL_TARGET_MACEMEN,
			GlobalUnits.UNIT_TYPE.PIKEMEN: GlobalUnits.COUNCIL_TARGET_PIKEMEN,
			GlobalUnits.UNIT_TYPE.ARCHER: GlobalUnits.COUNCIL_TARGET_ARCHERS,
		}
		for s in units:
			if int(s.get("owner", -1)) != pid:
				continue
			if not GlobalUnits.is_fighting_stack(s):
				continue
			var t := int(s.get("type", -1))
			var cnt := int(s.get("count", 0))
			var keep := 0
			if reserve.has(t):
				keep = mini(cnt, int(reserve[t]))
				reserve[t] = int(reserve[t]) - keep
			var take := cnt - keep
			if take <= 0:
				continue
			out_units.append(GlobalUnits.make_stack(
				t, pid,
				int(s.get("source", GlobalUnits.SOURCE.LEVY)),
				take,
				int(s.get("status", GlobalUnits.STATUS.FIGHTING)),
				int(s.get("recover_in", 0)),
				bool(s.get("join_pending", false)),
				bool(s.get("militia", false))
			))
	else:
		out_units = _extract_any_stacks(units, pid, GlobalUnits.total_men(units))
	if max_men >= 0:
		var capped: Array = _extract_any_stacks(out_units, pid, max_men)
		out_units = capped
	if GlobalUnits.total_men(out_units) < GlobalUnits.MIN_SPLIT_MEN and merge_into == "":
		return merge_into
	if out_units.is_empty():
		return merge_into
	# Move merge target next to building if needed.
	if merge_into != "" and base_map.forces.has(merge_into):
		if not _force_adjacent_to_building(base_map, merge_into, building):
			_move_force_toward_building(base_map, merge_into, building)
	var approach: Vector2i = base_map.get_free_approach_cell_for(building) if base_map.has_method("get_free_approach_cell_for") else Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	if approach.x == 0x7FFFFFFF:
		return merge_into
	if merge_into != "" and base_map.forces.has(merge_into) and _force_adjacent_to_building(base_map, merge_into, building):
		var bkey := str(base_map._building_key(building)) if base_map.has_method("_building_key") else ""
		if bkey != "" and base_map.has_method("apply_batch_garrison_units"):
			base_map.apply_batch_garrison_units(
				merge_into, bkey, spot, [], out_units,
				GlobalUnits.empty_caravan_cargo(), GlobalUnits.empty_caravan_cargo()
			)
			return merge_into
	var before: Dictionary = {}
	for existing_fid in base_map.forces.keys():
		before[str(existing_fid)] = true
	if base_map.get("_next_runtime_force") == null:
		return merge_into
	base_map._next_runtime_force = int(base_map._next_runtime_force) + 1
	var spawned_id := "rt_%d" % int(base_map._next_runtime_force)
	base_map.apply_sortie_units(gid, spawned_id, out_units, approach.x, approach.y, {})
	var new_id := spawned_id if base_map.forces.has(spawned_id) else ""
	if new_id == "":
		for existing_fid in base_map.forces.keys():
			var nf := str(existing_fid)
			if before.has(nf):
				continue
			var loc: Dictionary = base_map.forces[nf].get("location", {})
			if str(loc.get("kind", "")) == "cell":
				new_id = nf
				break
	if new_id == "":
		return merge_into
	if merge_into != "" and base_map.forces.has(merge_into) and base_map.has_method("apply_merge_forces"):
		if _forces_same_or_adjacent_cell(base_map, merge_into, new_id):
			base_map.apply_merge_forces(merge_into, new_id)
			return merge_into
		# Nudge both toward town so they can merge next season.
		var town = staging.get_town() if staging.has_method("get_town") else null
		if town != null:
			_move_force_toward_building(base_map, merge_into, town)
			_move_force_toward_building(base_map, new_id, town)
	return new_id if merge_into == "" or not base_map.forces.has(merge_into) else merge_into


static func _merge_other_field_armies(
	base_map: Node, pid: int, main_id: String, prefer_prov: Node = null
) -> void:
	var war := {"force_id": main_id}
	if prefer_prov != null:
		_merge_province_field_armies(base_map, pid, prefer_prov, war)
		return
	if base_map.get("armies") == null or not base_map.has_method("apply_merge_forces"):
		return
	if not base_map.forces.has(main_id):
		return
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if fid == main_id or not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		if _forces_same_or_adjacent_cell(base_map, main_id, fid):
			base_map.apply_merge_forces(main_id, fid)


static func _forces_same_or_adjacent_cell(base_map: Node, a: String, b: String) -> bool:
	var pf = base_map.get("pathfinding")
	if pf == null:
		return false
	var fa = base_map.armies.get_node_or_null(a)
	var fb = base_map.armies.get_node_or_null(b)
	if fa == null or fb == null:
		return false
	var ca: Vector2i = pf.get_army_cell(fa)
	var cb: Vector2i = pf.get_army_cell(fb)
	if ca == cb:
		return true
	if pf.has_method("_cells_edge_adjacent"):
		return bool(pf._cells_edge_adjacent(ca, cb))
	return (absi(ca.x - cb.x) + absi(ca.y - cb.y)) == 1


static func _force_adjacent_to_building(base_map: Node, fid: String, building: Node) -> bool:
	var pf = base_map.get("pathfinding")
	if pf == null or building == null:
		return false
	var fig = base_map.armies.get_node_or_null(fid)
	if fig == null:
		return false
	var cell: Vector2i = pf.get_army_cell(fig)
	var approach: Array[Vector2i] = pf.get_approach_cells(building) if pf.has_method("get_approach_cells") else []
	return cell in approach


static func _move_force_toward_building(base_map: Node, fid: String, building: Node) -> void:
	var pf = base_map.get("pathfinding")
	if pf == null or building == null:
		return
	var approach: Array[Vector2i] = pf.get_approach_cells(building) if pf.has_method("get_approach_cells") else []
	if approach.is_empty():
		return
	_move_force_toward_cells(base_map, fid, approach)


## March `mover_fid` toward free tiles beside `target_fid` (can't path onto occupied cells).
static func _move_force_toward_force(base_map: Node, mover_fid: String, target_fid: String) -> void:
	var goals := _free_cells_adjacent_to_force(base_map, target_fid, mover_fid)
	if goals.is_empty():
		return
	_move_force_toward_cells(base_map, mover_fid, goals)


static func _move_force_toward_cells(base_map: Node, fid: String, goals: Array[Vector2i]) -> void:
	var pf = base_map.get("pathfinding")
	if pf == null or goals.is_empty():
		return
	var fig = base_map.armies.get_node_or_null(fid)
	if fig == null:
		return
	var from_cell: Vector2i = pf.get_army_cell(fig)
	var path: Array[Vector2i] = pf.find_path_for_mover(fig, from_cell, goals)
	if path.size() < 2:
		return
	var mp_left := int(fig.movement_left) if fig.get("movement_left") != null else 0
	var stop_i := int(pf.farthest_affordable_index(path, mp_left, fig))
	if stop_i <= 0:
		return
	# Prefer not to stop on blocked tiles.
	while stop_i > 0 and pf.has_method("cell_blocked_for_stop") and pf.cell_blocked_for_stop(fig, path[stop_i]):
		stop_i -= 1
	if stop_i <= 0:
		return
	var end: Vector2i = path[stop_i]
	var spent := 0
	for i in range(1, stop_i + 1):
		spent += int(pf.enter_cost(path[i], fig)) if pf.has_method("enter_cost") else 1
	if base_map.has_method("apply_army_move"):
		base_map.apply_army_move(fid, end.x, end.y, spent)


## Free walkable cells edge-adjacent to `fid` (optionally treating `ignore_fid` as non-blocking).
static func _free_cells_adjacent_to_force(
	base_map: Node, fid: String, ignore_fid: String = ""
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pf = base_map.get("pathfinding")
	if pf == null or not base_map.forces.has(fid):
		return out
	var fig = base_map.armies.get_node_or_null(fid)
	if fig == null:
		return out
	var cell: Vector2i = pf.get_army_cell(fig)
	var ignore = base_map.armies.get_node_or_null(ignore_fid) if ignore_fid != "" else null
	var dirs: Array = pf.EDGE_DIRS if pf.get("EDGE_DIRS") != null else [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for dir_variant in dirs:
		var n: Vector2i = cell + dir_variant
		if pf.has_method("_is_walkable_cell") and not bool(pf._is_walkable_cell(n)):
			continue
		elif pf.get("walkable_cells") != null and not pf.walkable_cells.has(n):
			continue
		if pf.occupancy.has(n):
			var occ = pf.occupancy[n]
			if occ != fig and occ != ignore:
				continue
		out.append(n)
	return out


## Place `mover_fid` on a free cell beside `main_fid` (for immediate merge). Returns success.
static func _snap_force_beside(base_map: Node, mover_fid: String, main_fid: String) -> bool:
	var pf = base_map.get("pathfinding")
	if pf == null:
		return false
	var mover = base_map.armies.get_node_or_null(mover_fid)
	if mover == null or not base_map.forces.has(main_fid):
		return false
	var goals := _free_cells_adjacent_to_force(base_map, main_fid, mover_fid)
	if goals.is_empty():
		return false
	var dest: Vector2i = goals[0]
	if pf.has_method("place_army_at_cell"):
		pf.place_army_at_cell(mover, dest)
	if pf.has_method("rebuild_occupancy"):
		pf.rebuild_occupancy()
	return _forces_same_or_adjacent_cell(base_map, main_fid, mover_fid)


## Merge `source_fid` into `main_fid`. Snap beside if needed; else march toward. Never moves main.
static func _absorb_field_force_into(base_map: Node, main_fid: String, source_fid: String) -> String:
	if main_fid == "" or not base_map.forces.has(main_fid):
		return source_fid if base_map.forces.has(source_fid) else ""
	if source_fid == "" or source_fid == main_fid or not base_map.forces.has(source_fid):
		return main_fid
	if not base_map.has_method("apply_merge_forces"):
		return main_fid
	if _forces_same_or_adjacent_cell(base_map, main_fid, source_fid):
		base_map.apply_merge_forces(main_fid, source_fid)
		return main_fid if base_map.forces.has(main_fid) else ""
	# Same province: snap beside the main stack and merge this season.
	var same_prov := false
	if base_map.has_method("province_under_force"):
		var a = base_map.province_under_force(main_fid)
		var b = base_map.province_under_force(source_fid)
		same_prov = a != null and a == b
	if same_prov and _snap_force_beside(base_map, source_fid, main_fid):
		if _forces_same_or_adjacent_cell(base_map, main_fid, source_fid):
			base_map.apply_merge_forces(main_fid, source_fid)
			return main_fid if base_map.forces.has(main_fid) else ""
	_move_force_toward_force(base_map, source_fid, main_fid)
	if base_map.forces.has(main_fid) and base_map.forces.has(source_fid) \
			and _forces_same_or_adjacent_cell(base_map, main_fid, source_fid):
		base_map.apply_merge_forces(main_fid, source_fid)
	return main_fid if base_map.forces.has(main_fid) else (
		source_fid if base_map.forces.has(source_fid) else ""
	)


## Pull every other owned field army onto `main_fid`. Never relocates the main stack.
static func _merge_all_field_into_force(base_map: Node, pid: int, main_fid: String) -> String:
	if base_map.get("armies") == null or base_map.get("forces") == null:
		return main_fid
	if main_fid == "" or not base_map.forces.has(main_fid):
		main_fid = _find_knight_field_army(base_map, pid)
		if main_fid == "":
			main_fid = _find_field_army(base_map, pid)
	if main_fid == "" or not base_map.forces.has(main_fid):
		return ""
	# Multi-pass: snap/merge clears a ring of strays that block each other.
	for _pass in range(8):
		var others: Array = []
		for fig in base_map.armies.get_children():
			var other := String(fig.name)
			if other == main_fid or not base_map.forces.has(other):
				continue
			var loc: Dictionary = base_map.forces[other].get("location", {})
			if str(loc.get("kind", "")) != "cell":
				continue
			if int(base_map.get_force_controller(other)) != pid:
				continue
			if GlobalUnits.total_men(base_map.forces[other].get("units", [])) <= 0:
				continue
			others.append(other)
		if others.is_empty():
			break
		var before := others.size()
		for other in others:
			if not base_map.forces.has(main_fid):
				break
			if not base_map.forces.has(other):
				continue
			main_fid = _absorb_field_force_into(base_map, main_fid, other)
		var left := 0
		for fig2 in base_map.armies.get_children():
			var oid := String(fig2.name)
			if oid == main_fid or not base_map.forces.has(oid):
				continue
			if int(base_map.get_force_controller(oid)) != pid:
				continue
			var loc2: Dictionary = base_map.forces[oid].get("location", {})
			if str(loc2.get("kind", "")) != "cell":
				continue
			left += 1
		if left >= before:
			break
	return main_fid if base_map.forces.has(main_fid) else ""


static func _try_assault_and_capture(
	base_map: Node, pid: int, fid: String, town: Node, war: Dictionary
) -> void:
	var key := str(base_map._building_key(town)) if base_map.has_method("_building_key") else ""
	if key == "":
		return
	var def_men := GlobalUnits.fighting_men(base_map.get_all_building_garrison(town))
	var will_militia := false
	if base_map.has_method("settlement_should_raise_militia"):
		will_militia = bool(base_map.settlement_should_raise_militia(town, fid))
	if def_men > 0 or will_militia:
		if base_map.has_method("request_battle_attack"):
			base_map.request_battle_attack(fid, "", key)
		# Refresh after battle.
		def_men = GlobalUnits.fighting_men(base_map.get_all_building_garrison(town))
		will_militia = false
		if base_map.has_method("settlement_should_raise_militia"):
			will_militia = bool(base_map.settlement_should_raise_militia(town, fid))
	if def_men > 0 or will_militia:
		return
	if not base_map.forces.has(fid):
		return
	if not base_map.has_method("force_has_movement") or not base_map.force_has_movement(fid, 2):
		return
	if base_map.has_method("request_capture_building"):
		base_map.request_capture_building(fid, key)
	# Occupation: plant 100/100/100 from this army, keep the rest in-province.
	if base_map.forces.has(fid):
		_plant_occupation_from_army(base_map, pid, fid, town)
	war["pause_until_stable"] = true
	war["target_province_id"] = ""
	war["staging_province_id"] = ""
	war["force_id"] = fid if base_map.forces.has(fid) else _find_field_army(base_map, pid)
	war["retarget_wait"] = 0
	war["pending_weaker"] = ""


## Leave home kit in the captured town from the conquering army; garrison overflow if room.
static func _plant_occupation_from_army(
	base_map: Node, pid: int, fid: String, town: Node
) -> void:
	if not base_map.forces.has(fid) or town == null:
		return
	if not base_map.has_method("apply_garrison_units"):
		return
	if not _force_adjacent_to_building(base_map, fid, town):
		return
	var bkey := str(base_map._building_key(town)) if base_map.has_method("_building_key") else ""
	if bkey == "":
		return
	var room := _garrison_room(base_map, town, GlobalUnits.SPOT.FLAT)
	var kit_out: Array = []
	for t in [
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
		GlobalUnits.UNIT_TYPE.ARCHER,
	]:
		if room <= 0:
			break
		var want := 0
		match t:
			GlobalUnits.UNIT_TYPE.MACEMEN:
				want = GlobalUnits.COUNCIL_TARGET_MACEMEN
			GlobalUnits.UNIT_TYPE.PIKEMEN:
				want = GlobalUnits.COUNCIL_TARGET_PIKEMEN
			_:
				want = GlobalUnits.COUNCIL_TARGET_ARCHERS
		want = mini(want, room)
		var taken := _extract_type_stacks(base_map.forces[fid].get("units", []), pid, t, want)
		for s in taken:
			kit_out.append(s)
			room -= int(s.get("count", 0))
	if not kit_out.is_empty():
		base_map.apply_garrison_units(fid, bkey, GlobalUnits.SPOT.FLAT, kit_out)
	# Garrison leftover into town/castle while waiting for next war.
	var prov = base_map.find_province_for_building(town) if base_map.has_method("find_province_for_building") else null
	if prov != null and base_map.forces.has(fid):
		_garrison_force_while_waiting(base_map, pid, prov, fid)


## UI / admin: snapshot of what one AI lord is doing.
static func debug_status(base_map: Node, pid: int) -> Dictionary:
	var out := {
		"pid": pid,
		"name": "",
		"phase": "idle",
		"blocker": "",
		"goal": "",
		"holdings": 0,
		"wooden_fort": false,
		"pause_until_stable": false,
		"target_province": "",
		"staging_province": "",
		"force_id": "",
		"army_men": 0,
		"army_strength": 0,
		"defense_strength": 0,
		"prep_need": 0,
		"assault_need": 0,
		"adjacent": false,
		"retarget_wait": 0,
		"pending_weaker": "",
		"lines": [],
	}
	if base_map == null or not base_map.players.has(pid):
		out["blocker"] = "unknown player"
		return out
	var p = base_map.players[pid]
	out["name"] = str(p.name_)
	if not GlobalStuff.is_ai_lord(p.type):
		out["phase"] = "not_ai"
		out["blocker"] = "not an AI lord"
		return out

	var holdings := _provinces_for_lord(base_map, pid)
	out["holdings"] = holdings.size()
	var doctrine := _doctrine(base_map, pid)
	out["doctrine"] = doctrine
	var war: Dictionary = _war_state(base_map, pid)
	out["pause_until_stable"] = bool(war.get("pause_until_stable", false))
	out["target_province"] = str(war.get("target_province_id", ""))
	out["staging_province"] = str(war.get("staging_province_id", ""))
	out["force_id"] = str(war.get("force_id", ""))
	out["retarget_wait"] = int(war.get("retarget_wait", 0))
	out["pending_weaker"] = str(war.get("pending_weaker", ""))
	out["wooden_fort"] = _has_operational_wooden_fort(holdings)

	var lines: Array = []
	lines.append(
		"Lord %s (id %d) — %d holding(s) — doctrine=%s" % [
			out["name"], pid, holdings.size(), doctrine
		]
	)

	if true:
		# Defense holdings + knight conquest status (primary AI path).
		out["phase"] = "defense"
		out["goal"] = "Fortify holdings, then knight-conquer adjacent councils"
		var blockers: Array = []
		var buys_all: Dictionary = {}
		if typeof(base_map.players[pid].game_data.get(AI_DEBUG_BUYS_KEY, {})) == TYPE_DICTIONARY:
			buys_all = base_map.players[pid].game_data.get(AI_DEBUG_BUYS_KEY, {})
		var all_done := _all_holdings_defense_complete(base_map, pid, holdings)
		for prov in holdings:
			var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
			var next_c := _defense_next_castle_level(castle)
			var standing := -1
			if castle != null and castle.has_method("standing_level"):
				standing = int(castle.standing_level())
			var cstat := "no plot"
			if castle != null:
				if castle.has_method("is_under_construction") and castle.is_under_construction():
					cstat = "building → %d" % next_c
				elif standing >= DEFENSE_CASTLE_MAX:
					cstat = "Concentric"
				else:
					cstat = "lvl %d → next %d" % [standing, next_c]
			var short: Dictionary = _defense_castle_mat_shortfall(prov, pid, castle, next_c)
			var room_left := 0
			var castle_room := 0
			var men_g := 0
			var peri := _defense_peripheral_unlocked(prov)
			for slot in _defense_active_slots_for_pid(prov, pid):
				var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
				var have := GlobalUnits.total_men(base_map.get_building_garrison(slot["b"], int(slot["spot"])))
				men_g += have
				var hole := maxi(0, cap - have)
				room_left += hole
				if str(slot.get("prio", "")) == "castle":
					castle_room += hole
			var ration := GlobalUnits.RATION_DEFAULT
			var tax := GlobalUnits.TAX_DEFAULT
			var happy := 100.0
			if prov.has_method("get_holding_ration"):
				ration = int(prov.get_holding_ration(pid))
			if prov.has_method("get_holding_tax"):
				tax = int(prov.get_holding_tax(pid))
			if prov.has_method("average_settlement_happiness"):
				happy = float(prov.average_settlement_happiness(pid))
			var merchant = _merchant_in_province(base_map, prov)
			var buy_row: Dictionary = buys_all.get(String(prov.name), {})
			var buy_bits: Array = []
			if typeof(buy_row) == TYPE_DICTIONARY:
				for k in buy_row.keys():
					if int(buy_row[k]) > 0:
						buy_bits.append("%s=%d" % [str(k), int(buy_row[k])])
			var done := _province_defense_complete(base_map, prov, pid)
			lines.append(
				"%s — castle=%s need_w/s=%d/%d garrison=%d castle_room=%d room=%d peri=%s done=%s"
				% [
					String(prov.name),
					cstat,
					int(short.get("wood", 0)),
					int(short.get("stone", 0)),
					men_g,
					castle_room,
					room_left,
					"yes" if peri else "no",
					"yes" if done else "no",
				]
			)
			lines.append(
				"  ration=%s tax=%s happy=%.0f merchant=%s buys=[%s]"
				% [
					GlobalUnits.ration_name(ration),
					GlobalUnits.tax_name(tax),
					happy,
					"yes" if merchant != null else "no",
					", ".join(PackedStringArray(buy_bits)),
				]
			)
			if not done:
				if standing < DEFENSE_CASTLE_MAX:
					blockers.append("%s castle" % String(prov.name))
				if int(short.get("wood", 0)) > 0 or int(short.get("stone", 0)) > 0:
					blockers.append(
						"%s mats +%dwood +%dstone" % [
							String(prov.name), int(short.get("wood", 0)), int(short.get("stone", 0))
						]
					)
				if castle_room > 0:
					blockers.append("%s castle garrison (+%d)" % [String(prov.name), castle_room])
				elif room_left > 0:
					blockers.append("%s garrison drip (+%d)" % [String(prov.name), room_left])

		var kw: Dictionary = _knight_war_state(base_map, pid)
		var kfid := str(kw.get("force_id", ""))
		var kmen := 0
		var kstr := 0
		var cargo_g := 0
		if kfid != "" and base_map.forces.has(kfid):
			kmen = _knight_count_in_force(base_map, kfid, pid)
			kstr = _force_strength(base_map, kfid)
			if base_map.has_method("get_force_cargo"):
				cargo_g = int(base_map.get_force_cargo(kfid).get("grain", 0))
		var halt := str(kw.get("halt_reason", ""))
		lines.append(
			"Knight war — ready=%s target=%s staging=%s force=%s knights=%d str=%d cargo=%d marching=%s"
			% [
				"yes" if all_done else "no",
				str(kw.get("target_province_id", "")),
				str(kw.get("staging_province_id", "")),
				kfid,
				kmen,
				kstr,
				cargo_g,
				"yes" if bool(kw.get("marching", false)) else "no",
			]
		)
		if halt != "":
			lines.append("  halt: " + halt)
		if all_done:
			out["phase"] = "knight_conquest"
			if str(kw.get("target_province_id", "")) == "":
				out["blocker"] = "ready — picking council target"
			elif halt != "":
				out["blocker"] = halt
			else:
				out["blocker"] = "knight campaign → %s" % str(kw.get("target_province_id", ""))
		elif blockers.is_empty():
			out["blocker"] = "fortifying"
		else:
			out["blocker"] = ", ".join(PackedStringArray(blockers))
		lines.append("Phase: " + str(out["phase"]))
		lines.append("Goal: " + str(out["goal"]))
		lines.append("Blocker: " + str(out["blocker"]))
		out["lines"] = lines
		out["target_province"] = str(kw.get("target_province_id", ""))
		out["staging_province"] = str(kw.get("staging_province_id", ""))
		out["force_id"] = kfid
		out["army_men"] = kmen
		out["army_strength"] = kstr
		out["halt_reason"] = halt
		return out

	# Legacy offense debug (unreachable while `or true` above — kept for reference).
	if bool(out["pause_until_stable"]):
		out["phase"] = "pause_stabilize"
		out["goal"] = "Stabilize all holdings (food + arms stock + castle ladder)"
		var unstable: Array = []
		for prov in holdings:
			if not _province_stable(base_map, prov, pid, holdings.size()):
				unstable.append(String(prov.name))
		if unstable.is_empty():
			out["blocker"] = "should clear pause next tick"
		else:
			out["blocker"] = "unstable: " + ", ".join(PackedStringArray(unstable))
		lines.append("Phase: pause until stable")
		lines.append("Blocker: " + str(out["blocker"]))
		out["lines"] = lines
		return out

	if not bool(out["wooden_fort"]):
		out["phase"] = "build_castle"
		out["goal"] = "Finish wooden fort (lvl1) to unlock offense"
		out["blocker"] = "no operational wooden fort"
		for prov in holdings:
			var arms := _arms_ready(base_map, prov, pid)
			var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
			var cstat := "no plot"
			if castle != null:
				if castle.has_method("is_under_construction") and castle.is_under_construction():
					cstat = "building"
				elif castle.has_method("is_operational") and castle.is_operational():
					cstat = "lvl %d" % int(castle.standing_level())
				else:
					cstat = "empty"
			lines.append(
				"%s — arms_ready=%s castle=%s" % [String(prov.name), str(arms), cstat]
			)
		lines.append("Phase: build castle / stock arms")
		out["lines"] = lines
		return out

	var target_id := str(out["target_province"])
	if target_id == "":
		var pick: Dictionary = _pick_council_target(base_map, pid, holdings)
		out["phase"] = "seek_target"
		out["goal"] = "Find weakest adjacent council town"
		if pick.is_empty():
			out["blocker"] = "no adjacent council town"
		else:
			out["blocker"] = "will open war on %s next tick" % str(pick.get("province_id", ""))
		lines.append("Phase: seek target")
		lines.append("Blocker: " + str(out["blocker"]))
		out["lines"] = lines
		return out

	out["goal"] = "Conquer council town in %s" % target_id
	var target_prov = base_map._get_province_by_id(target_id) if base_map.has_method("_get_province_by_id") else null
	var town = target_prov.get_town() if target_prov != null and target_prov.has_method("get_town") else null
	var staging = null
	var staging_id := str(out["staging_province"])
	if staging_id != "" and base_map.has_method("_get_province_by_id"):
		staging = base_map._get_province_by_id(staging_id)
	var fid := str(out["force_id"])
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, staging)
		out["force_id"] = fid

	var def_str := 0
	if town != null and base_map.has_method("get_settlement_defense_preview"):
		def_str = int(base_map.get_settlement_defense_preview(town, fid).get("strength", 0))
	out["defense_strength"] = def_str
	out["prep_need"] = maxi(1, int(ceil(float(def_str) * WAR_STRENGTH_MARGIN)))
	out["assault_need"] = int(out["prep_need"])

	var pool: Dictionary = {}
	if staging != null:
		pool = _staging_offensive_pool(base_map, staging, pid, fid)
	var my_str := int(pool.get("strength", 0))
	var men := int(pool.get("men", 0))
	out["army_men"] = men
	out["army_strength"] = my_str

	var adjacent = town != null and fid != "" and base_map.forces.has(fid) and _force_adjacent_to_building(base_map, fid, town)
	out["adjacent"] = adjacent

	if men <= 0 and my_str <= 0:
		out["phase"] = "raise_army"
		out["blocker"] = "raising into garrison toward ×%.1f (%d str); kit stays home on march" % [
			WAR_STRENGTH_MARGIN, int(out["prep_need"])
		]
	elif my_str < int(out["prep_need"]):
		out["phase"] = "prep_garrison"
		out["blocker"] = "garrison prep %d / %d offensive str (stay garrisoned until march)" % [
			my_str, int(out["prep_need"])
		]
	elif not adjacent:
		var grain_have := 0
		if fid != "" and base_map.forces.has(fid) and base_map.has_method("get_force_cargo"):
			grain_have = int(base_map.get_force_cargo(fid).get("grain", 0))
		var grain_want := 0
		if fid != "" and base_map.forces.has(fid):
			grain_want = _war_grain_wanted(base_map, fid, town)
		elif men > 0:
			grain_want = GlobalUnits.force_grain_need(men, false) * 5
		out["cargo_grain"] = grain_have
		out["cargo_grain_want"] = grain_want
		var field_str := _force_strength(base_map, fid) if fid != "" else 0
		if field_str < int(out["prep_need"]) or (grain_want > 0 and grain_have < grain_want):
			out["phase"] = "drip_feed"
			out["blocker"] = (
				"drip-feed sortie+grain — field str %d / %d, cargo %d / %d (rest stay garrisoned)"
				% [field_str, int(out["prep_need"]), grain_have, grain_want]
			)
		else:
			out["phase"] = "march"
			out["blocker"] = "march — field ready (%d str, grain %d)" % [field_str, grain_have]
	else:
		out["phase"] = "assault"
		out["blocker"] = "ready to assault (%d >= %d)" % [my_str, int(out["prep_need"])]

	lines.append("Phase: %s" % out["phase"])
	lines.append("Goal: %s" % out["goal"])
	lines.append(
		"Offensive pool — %d men, strength %d (home kit reserved)" % [men, my_str]
	)
	lines.append(
		"Defense %d | leave/assault at ×%.1f → %d" % [
			def_str, WAR_STRENGTH_MARGIN, int(out["prep_need"]),
		]
	)
	lines.append("Adjacent: %s | staging: %s | field: %s" % [
		str(adjacent), str(out["staging_province"]), fid if fid != "" else "(garrisoned)"
	])
	if out.has("cargo_grain_want"):
		lines.append(
			"Cargo grain %d / want %d" % [int(out.get("cargo_grain", 0)), int(out.get("cargo_grain_want", 0))]
		)
	if int(out["retarget_wait"]) > 0:
		lines.append(
			"Retarget wait %d/%d (pending %s)" % [
				int(out["retarget_wait"]), WAR_RETARGET_WAIT_SEASONS, str(out["pending_weaker"])
			]
		)
	lines.append("Blocker: " + str(out["blocker"]))
	out["lines"] = lines
	return out


static func debug_all_lords(base_map: Node) -> Array:
	var out: Array = []
	if base_map == null or base_map.get("players") == null:
		return out
	var pids: Array = base_map.players.keys()
	pids.sort()
	for pid in pids:
		if GlobalStuff.is_ai_lord(base_map.players[pid].type):
			out.append(debug_status(base_map, int(pid)))
	return out
