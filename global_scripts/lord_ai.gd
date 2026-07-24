extends RefCounted
class_name LordAI

## Seasonal AI-lord brain (host, season start). Councils stay on CouncilAI.
##
## Doctrine (`players[pid].game_data["ai_doctrine"]`):
##   "defense" (default) — rations ≤ Quad if year+buffer grain allows; stable tax; Concentric.
##     Villages/economy fill only after Concentric (50% archer / 50% mace).
##     Castle/town garrisons: 50% archer / 25% sword / 25% pike.
##     Economy stage: Medium after Norman Keep, Big after Enclosed
##     (wood→iron→smith→stone→silver); spend freely but reserve castle-mat buys + army upkeep.
##     Merchant present: sell wood/iron above 1500 (keep wood if stocking castle wood;
##     stone above 500 unless any holding needs castle stone). Fill garrisons before next keep.
##   Conquest (automatic) — when every secure holding is Norman Keep+ with level garrisons
##     full and wood+smith (and iron mine if deposit) at Medium, raise a mixed field army
##     (25% archer / 20% mace / 15% sword / 10% pike / 30% peasant) to 1.3× harder of
##     castle vs town on weakest adjacent enemy (council/human/AI, never allies).
##     Arm first (wait/craft/buy; no peasant fill-in); peasants only after armed mix is done.
##     Dump keep surplus into the field, then march at ≥1.0× (prefer 1.3×). No iron deposit → buy iron.
##     Province threat = max(town, castle, strongest enemy field) — empty seats are not free.
##     Conquest targets need a town→town *army* path (road MP costs) that only crosses
##     own / ally / target land — not a cheap highway through neutrals/hostiles.
##   Home defense — enemy field army in borders → prep (arms/sellswords/tax 0), local
##     levy+castle sortie (keep 50 in castle) at 1.1×; wait 1 season unless siege engines≥1;
##     cascade neighbor levies; recall conquest army if still short. Hold 4 seasons then disband.
##     Lost province → reconquest target. Defense forces protected from peacetime disband.
##   "offense" — legacy Pass 1/2a (dormant unless doctrine forced); prefer conquest.
##   Early boost (≤2 dejure): half army upkeep + 1.5× wallet tax; Admin/AI Debug only.

const THREAT_STRAIGHT_FILTER := 20
const WAR_STRENGTH_MARGIN := 1.3
const WAR_RETARGET_WAIT_SEASONS := 2
const WAR_DRIP_MEN_CAP := 80
const AI_WAR_KEY := "ai_war"
const AI_INVASION_WAR_KEY := "ai_invasion_war"
const AI_DOCTRINE_KEY := "ai_doctrine"
const DOCTRINE_DEFENSE := "defense"
const DOCTRINE_OFFENSE := "offense"
## Highest CASTLE_TYPE (Concentric).
const DEFENSE_CASTLE_MAX := 5
## Concentric (5): unlock village + economy garrison fill / craft / weapon buys.
const DEFENSE_EXPAND_GARRISON_MIN := 5
## Norman Keep (2): minimum standing before a holding is conquest-ready.
const DEFENSE_CONQUEST_MIN_CASTLE := 2
## Norman Keep (2): economy → Medium; Enclosed (3): economy → Big.
const DEFENSE_ECON_MEDIUM_MIN_CASTLE := 2
const DEFENSE_ECON_BIG_MIN_CASTLE := 3
## Minimum economy STAGES value for conquest (MEDIUM=2).
const DEFENSE_ECON_CONQUEST_MIN_STAGE := 2
## Upgrade priority: wood, iron, blacksmith, stone, silver.
const DEFENSE_ECON_UPGRADE_ORDER := [0, 1, 5, 4, 3]
## Subtypes that must be Medium before invasion (iron only if deposit exists).
const DEFENSE_ECON_CONQUEST_REQUIRED := [0, 5] # WOODCUTTER, BLACKSMITH
const DEFENSE_ECON_IRON_SUBTYPE := 1 # IRONMINE
## Max men levied into non-castle slots per season (castle fills without drip).
const DEFENSE_DRIP_OTHER := 25
## Happiness below this → ease tax for recovery (with Quad prefer Harsh at cap).
const DEFENSE_HAPPY_RECOVER_BELOW := 95.0
## AI will spend levy happiness down to this floor (was effectively 100).
const DEFENSE_LEVY_HAPPINESS_FLOOR := 80.0
## Civilian ration runway: full year (4 seasons) + 1 buffer before choosing/buying Quad.
const DEFENSE_RATION_RUNWAY_SEASONS := 5
## Iron stock floor before buying from merchant for smithing (has mine).
const DEFENSE_IRON_BUY_FLOOR := 3
## Iron stock floor when no mine — buy for blacksmith craft.
const DEFENSE_IRON_BUY_FLOOR_NO_MINE := 30
## Per-province merchant sell floors (keep this much; dump the rest when a merchant camps).
const DEFENSE_SELL_KEEP_WOOD := 1500
const DEFENSE_SELL_KEEP_IRON := 1500
const DEFENSE_SELL_KEEP_STONE := 500
## Conquest: prefer 1.3× to raise; march from home at ≥1.0× once garrison is dumped.
const INVASION_STRENGTH_MARGIN := 1.3
const INVASION_MARCH_MIN_MARGIN := 1.0
const INVASION_FIELD_RATIO := 1.0
const INVASION_LEVY_DRIP := 40
## Field army mix (men fractions) for conquest raises.
const CONQUEST_MIX_ARCHER := 0.25
const CONQUEST_MIX_MACE := 0.20
const CONQUEST_MIX_SWORD := 0.15
const CONQUEST_MIX_PIKE := 0.10
const CONQUEST_MIX_PEASANT := 0.30
## Home defense (reactive): field odds vs invaders; hold force after clear.
const DEFENSE_WAR_STRENGTH_MARGIN := 1.1
const DEFENSE_WAR_HOLD_SEASONS := 4
const DEFENSE_WAR_CASTLE_RESERVE := 50
const AI_DEFENSE_WAR_KEY := "ai_defense_war"
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
		# Home defense first (protects field forces from peacetime park/disband).
		tick_home_defense(base_map, int(pid), holdings)
		# Defense policy on every dejure holding; invasion when ready.
		for prov in holdings:
			tick_province_defense(base_map, prov, int(pid))
		tick_invasion(base_map, int(pid), holdings)


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
	# No fortify / levy until full province flip (dejure + defacto).
	if not _invasion_province_full_control(prov, pid):
		return

	var province_id := String(prov.name)
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	var next_castle := _defense_next_castle_level(castle)
	var mat_short: Dictionary = _defense_castle_mat_shortfall(prov, pid, castle, next_castle)
	var need_castle_mats := (
		int(mat_short.get("wood", 0)) > 0 or int(mat_short.get("stone", 0)) > 0
	)
	# While parked at Norman+ waiting on Medium wood/smith/(iron), free labor for craft.
	var standing_now := int(castle.standing_level()) if castle != null and castle.has_method("standing_level") else -1
	if standing_now >= DEFENSE_CONQUEST_MIN_CASTLE and not _province_econ_ready_for_conquest(prov, pid):
		need_castle_mats = false
		mat_short = {"wood": 0, "stone": 0}
	# Active invasion: never starve the smith for the next castle tier.
	var arming_invasion := _invasion_arming_for_conquest(base_map, pid)
	if arming_invasion:
		need_castle_mats = false
		mat_short = {"wood": 0, "stone": 0}
	_clear_debug_buys(base_map, pid, province_id)

	# 1) Food — Quadruple when affordable; tax paired for stable ~100 happiness.
	_set_defense_rations_and_tax(base_map, prov, pid)
	if base_map.has_method("apply_populate_idle_fields"):
		base_map.apply_populate_idle_fields(province_id, 1, pid)

	# 2) Economy pads + stage upgrades (after Motte / Enclosed).
	CouncilAI._try_build_open(base_map, prov, pid, 0) # WOODCUTTER
	CouncilAI._try_build_open(base_map, prov, pid, 5) # BLACKSMITH
	_try_build_deposit(base_map, prov, pid)
	# Sell surplus mats first so marks can fund the same-season econ upgrade.
	_try_sell_surplus_mats(base_map, prov, pid, castle, next_castle, arming_invasion)
	_try_upgrade_economy(base_map, prov, pid, castle, mat_short)

	# 3) Labor — grain first; during invasion fill smith before mining more iron.
	_assign_labor_defense(base_map, prov, pid, castle, need_castle_mats, arming_invasion)

	# 4) Merchant: castle mats first, then iron/weapons, then grain for Quad.
	_try_buy_defense_castle_mats(base_map, prov, pid, mat_short)
	# Keep castle-mat shortfall suppressed while waiting on Medium econ or invading,
	# otherwise we re-reserve marks for stone and starve smith / craft.
	if arming_invasion \
			or (standing_now >= DEFENSE_CONQUEST_MIN_CASTLE and not _province_econ_ready_for_conquest(prov, pid)):
		mat_short = {"wood": 0, "stone": 0}
		need_castle_mats = false
	else:
		mat_short = _defense_castle_mat_shortfall(prov, pid, castle, next_castle)
		need_castle_mats = (
			int(mat_short.get("wood", 0)) > 0 or int(mat_short.get("stone", 0)) > 0
		)
	_set_craft_for_defense(base_map, prov, pid, need_castle_mats)
	_try_buy_defense_iron(base_map, prov, pid, mat_short)
	if not need_castle_mats:
		_try_buy_defense_weapons(base_map, prov, pid)
	# Stock arms for invasion: when garrisons were full, or while actively raising/marching
	# (garrison may be thin after sortie — still need smith output).
	if arming_invasion or (
		standing_now >= DEFENSE_CONQUEST_MIN_CASTLE
		and _defense_active_garrisons_full(base_map, prov, pid)
	):
		var stock_comp: Array = _composition_without_peasants(
			_conquest_composition_for_men(maxi(INVASION_LEVY_DRIP * 5, 100))
		)
		_set_craft_for_composition(base_map, prov, pid, stock_comp)
		_try_buy_iron_for_composition(base_map, prov, pid, stock_comp)
		_try_buy_war_weapons(base_map, prov, pid, stock_comp)
	_try_buy_defense_grain(base_map, prov, pid, mat_short)
	# Grain buy may unlock Quadruple — re-pair tax.
	_set_defense_rations_and_tax(base_map, prov, pid)

	# 5) Troop logistics — always absorb field stacks before any levy/upgrade.
	var keep_fid := _invasion_force_id(base_map, pid)
	var starting_upgrade := _defense_can_start_castle_upgrade(
		base_map, prov, pid, castle, next_castle
	)

	_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
	_defense_redistribute_into_castle(base_map, prov, pid)
	_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)

	if starting_upgrade:
		# Garrison stays in the castle worksite during upgrade (no expel).
		_try_advance_castle(base_map, prov, pid, castle, next_castle)
		_defense_fill_all_garrisons(base_map, prov, pid, false)
		_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)
		_defense_disband_unparked_field(base_map, pid, prov, keep_fid)
	else:
		_defense_fill_all_garrisons(base_map, prov, pid, false)
		# Empty-build / dismantle: castle offline — park strays into town/villages.
		# Mid-upgrade stays operational (old capacity), so absorb can refill the castle.
		if castle != null and castle.has_method("is_under_construction") \
				and bool(castle.is_under_construction()) \
				and not (castle.has_method("is_upgrade_project") and bool(castle.is_upgrade_project())):
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
## Castle/town: 50% archer / 25% sword / 25% pike.
## Village/economy: 50% archer / 50% macemen.
static func _defense_mix_is_peripheral(prio: String) -> bool:
	return prio == "village" or prio == "economy"


static func _defense_mix_counts(cap: int, prio: String = "town") -> Dictionary:
	cap = maxi(0, cap)
	if _defense_mix_is_peripheral(prio):
		var archers_p := int(floor(float(cap) * 0.5))
		var maces := maxi(0, cap - archers_p)
		return {
			GlobalUnits.UNIT_TYPE.ARCHER: archers_p,
			GlobalUnits.UNIT_TYPE.MACEMEN: maces,
			GlobalUnits.UNIT_TYPE.SWORDSMEN: 0,
			GlobalUnits.UNIT_TYPE.PIKEMEN: 0,
		}
	var archers := int(floor(float(cap) * 0.5))
	var swords := int(floor(float(cap) * 0.25))
	var pikes := maxi(0, cap - archers - swords)
	return {
		GlobalUnits.UNIT_TYPE.ARCHER: archers,
		GlobalUnits.UNIT_TYPE.SWORDSMEN: swords,
		GlobalUnits.UNIT_TYPE.PIKEMEN: pikes,
		GlobalUnits.UNIT_TYPE.MACEMEN: 0,
	}


static func _defense_mix_fill_types(prio: String) -> Array:
	if _defense_mix_is_peripheral(prio):
		return [GlobalUnits.UNIT_TYPE.ARCHER, GlobalUnits.UNIT_TYPE.MACEMEN]
	return [
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.SWORDSMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
	]


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
		# Never fill enemy / unowned settlements (town/village/castle), only ours.
		if b.get("player_owner") == null or int(b.player_owner) != pid:
			continue
		if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.ECONOMY):
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
		GlobalUnits.UNIT_TYPE.MACEMEN: 0,
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
	var need_maces := 0
	for slot in _defense_active_slots_for_pid(prov, pid):
		var prio := str(slot.get("prio", "town"))
		var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
		var mix: Dictionary = _defense_mix_counts(cap, prio)
		var have: Dictionary = _spot_fighting_counts(base_map, slot["b"], int(slot["spot"]), pid)
		need_bows += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)))
		need_swords += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)))
		need_pikes += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)))
		need_maces += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)))
	need_bows = maxi(0, need_bows - int(stock.get("bows", 0)))
	need_swords = maxi(0, need_swords - int(stock.get("swords", 0)))
	need_pikes = maxi(0, need_pikes - int(stock.get("pikes", 0)))
	need_maces = maxi(0, need_maces - int(stock.get("maces", 0)))
	if reserve_wood_for_castle:
		need_bows = 0
	var holes := {"bows": need_bows, "swords": need_swords, "pikes": need_pikes, "maces": need_maces}
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
	var keep_fid := _invasion_force_id(base_map, pid)
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
		_defense_fill_spot(
			base_map, prov, pid, slot["b"], int(slot["spot"]), drip, str(slot.get("prio", "town"))
		)
		# After each slot, pull any new strays (shouldn't create any) and stop if blocked.
		_absorb_other_field_into_garrison(base_map, pid, prov, keep_fid)


## Active slots full (or grain-capped so we cannot fill more).
static func _defense_active_garrisons_full(base_map: Node, prov: Node, pid: int) -> bool:
	if prov == null:
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


## True when mats are ready and we would start a new castle project this season.
## Standing castles must fill current-level garrisons before the next tier.
## After Norman Keep, finish Medium wood/smith/(iron) before climbing further —
## so the first invasion can arm from upgraded production.
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
	# Empty plot → first fort: no garrison gate. Else fill current level first.
	if standing >= 0 and not _defense_active_garrisons_full(base_map, prov, pid):
		return false
	# Hold the ladder at Norman+ until conquest econ (Medium wood/smith/iron) is ready.
	if standing >= DEFENSE_CONQUEST_MIN_CASTLE and not _province_econ_ready_for_conquest(prov, pid):
		return false
	# Don't climb the keep while raising/marching the invasion army.
	if _invasion_arming_for_conquest(base_map, pid):
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


## Per-season civilian grain budget after reserving year+buffer runway.
static func _defense_people_season_budget(people_budget: int) -> int:
	return int(floor(float(maxi(0, people_budget)) / float(DEFENSE_RATION_RUNWAY_SEASONS)))


## Extra garrison men we can raise while still affording Quad for civilians (year+buffer).
static func _defense_grain_headroom_men(_base_map: Node, prov: Node, pid: int) -> int:
	if prov == null or not prov.has_method("preview_holding_rations"):
		return 999999
	var preview: Dictionary = prov.preview_holding_rations(pid)
	var pop := int(preview.get("population", 0))
	var stock := int(preview.get("stock", 0))
	var seed_r := int(preview.get("seed_reserve", 0))
	var army_need := int(preview.get("army_need", 0))
	var quad_need := (
		GlobalUnits.ration_grain_need(pop, GlobalUnits.RATION.QUADRUPLE)
		* DEFENSE_RATION_RUNWAY_SEASONS
	)
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
		if _is_protected_field_force(base_map, pid, fid):
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


## Disband leftover leftover field stacks that could not be parked into any garrison.
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
		if _is_protected_field_force(base_map, pid, fid):
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
	drip_cap: int = -1,
	prio: String = "town"
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
	var mix: Dictionary = _defense_mix_counts(cap, prio)
	var have: Dictionary = _spot_fighting_counts(base_map, building, spot, pid)
	var want_comp: Array = []
	for t in _defense_mix_fill_types(prio):
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
# Home defense (reactive — parallel to fortify / invasion)
# =============================================================================


static func _defense_wars(base_map: Node, pid: int) -> Dictionary:
	if not base_map.players.has(pid):
		return {}
	var gd: Dictionary = base_map.players[pid].game_data
	if not gd.has(AI_DEFENSE_WAR_KEY) or typeof(gd[AI_DEFENSE_WAR_KEY]) != TYPE_DICTIONARY:
		gd[AI_DEFENSE_WAR_KEY] = {}
	return gd[AI_DEFENSE_WAR_KEY]


static func _defense_war_for(base_map: Node, pid: int, province_id: String) -> Dictionary:
	var wars: Dictionary = _defense_wars(base_map, pid)
	if not wars.has(province_id) or typeof(wars[province_id]) != TYPE_DICTIONARY:
		wars[province_id] = {
			"force_id": "",
			"phase": "", # prep | fight | hold | reconquest
			"prep_waited": false,
			"hold_left": 0,
			"halt_reason": "",
			"was_dejure": true,
			"recall_army": false,
		}
	return wars[province_id]


static func _clear_defense_war(base_map: Node, pid: int, province_id: String) -> void:
	var wars: Dictionary = _defense_wars(base_map, pid)
	wars.erase(province_id)


static func _is_protected_field_force(base_map: Node, pid: int, fid: String) -> bool:
	if fid == "" or not base_map.forces.has(fid):
		return false
	if fid == _invasion_force_id(base_map, pid):
		return true
	var kw: Dictionary = _invasion_war_state(base_map, pid)
	if fid == str(kw.get("reinforce_force_id", "")):
		return true
	var wars: Dictionary = _defense_wars(base_map, pid)
	for k in wars.keys():
		var w = wars[k]
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if fid == str(w.get("force_id", "")):
			return true
	return false


static func _home_defense_pauses_invasion(base_map: Node, pid: int) -> bool:
	var wars: Dictionary = _defense_wars(base_map, pid)
	for k in wars.keys():
		var w = wars[k]
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var prov = base_map._get_province_by_id(str(k)) if base_map.has_method("_get_province_by_id") else null
		var still_ours = prov != null and prov.has_method("has_dejure") and prov.has_dejure(pid)
		if bool(w.get("recall_army", false)) and still_ours:
			return true
		# Real siege on a holding we still own → pause conquest.
		if still_ours and _province_has_enemy_siege(base_map, pid, prov):
			return true
		# Lost province: clear recall so invasion reconquest can run.
		if bool(w.get("recall_army", false)) and not still_ours:
			w["recall_army"] = false
			wars[k] = w
	return false


## Enemy field army inside province borders → at risk.
static func _province_at_risk(base_map: Node, pid: int, prov: Node) -> bool:
	return _enemy_field_strength_in_province(base_map, pid, prov) > 0


static func _enemy_field_ids_in_province(base_map: Node, pid: int, prov: Node) -> Array:
	var out: Array = []
	if base_map.get("armies") == null or prov == null:
		return out
	for fig in base_map.armies.get_children():
		var other := String(fig.name)
		if not base_map.forces.has(other):
			continue
		var loc: Dictionary = base_map.forces[other].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
			continue
		var ctrl := int(base_map.get_force_controller(other))
		if ctrl == pid:
			continue
		if base_map.has_method("are_friendly_players") and base_map.are_friendly_players(pid, ctrl):
			continue
		if GlobalUnits.fighting_men(base_map.forces[other].get("units", [])) <= 0:
			continue
		out.append(other)
	return out


static func _enemy_field_strength_in_province(base_map: Node, pid: int, prov: Node) -> int:
	var total := 0
	for fid in _enemy_field_ids_in_province(base_map, pid, prov):
		total += _force_strength(base_map, str(fid))
	return total


static func _province_has_enemy_siege(base_map: Node, pid: int, prov: Node) -> bool:
	for fid in _enemy_field_ids_in_province(base_map, pid, prov):
		if base_map.has_method("is_force_sieging") and base_map.is_force_sieging(str(fid)):
			return true
	return false


static func _province_max_enemy_siege_level(base_map: Node, pid: int, prov: Node) -> int:
	var best := 0
	for fid in _enemy_field_ids_in_province(base_map, pid, prov):
		if not base_map.has_method("get_force_siege_level"):
			continue
		best = maxi(best, int(base_map.get_force_siege_level(str(fid))))
	return best


## Castle inside+outside fighting strength minus reserve floor (prefer keep archers).
static func _castle_sortieable_strength(base_map: Node, _pid: int, prov: Node) -> int:
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("is_operational") or not castle.is_operational():
		return 0
	var units: Array = []
	for spot in [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]:
		units = GlobalUnits.merge_units(units, base_map.get_building_garrison(castle, spot))
	var fighting := GlobalUnits.fighting_units(units)
	var men := GlobalUnits.fighting_men(fighting)
	var sortie_men := maxi(0, men - DEFENSE_WAR_CASTLE_RESERVE)
	if sortie_men <= 0:
		return 0
	# Approximate strength proportional to men (same mix).
	var full_str := GlobalUnits.fighting_strength(fighting)
	if men <= 0:
		return 0
	return int(floor(float(full_str) * float(sortie_men) / float(men)))


## Max levy field strength this season (threat may ignore happiness).
static func _home_max_levy_strength(
	base_map: Node, prov: Node, pid: int, ignore_happiness: bool
) -> int:
	var men := _clamp_levy_men(base_map, prov, pid, 99999, false, ignore_happiness)
	if men < GlobalUnits.MIN_SPLIT_MEN:
		return 0
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	# Arm with cheapest kit available from stock + what we could buy is handled in prep;
	# for capacity check, use stock only then fall back to peasant strength if unarmed.
	var by_type := _war_composition_for_strength(
		maxi(1, GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.ARCHER) * men)
	)
	# Scale composition down to `men` and weapon stock.
	var capped: Array = []
	var left := men
	for e in by_type:
		if left <= 0:
			break
		var t := int(e.get("type", -1))
		var want := mini(int(e.get("count", 0)), left)
		var wkey := _weapon_key_for_type(t)
		if wkey != "":
			want = mini(want, int(stock.get(wkey, 0)))
		if want > 0:
			capped.append({"type": t, "count": want})
			left -= want
	if GlobalUnits.composition_total_men(capped) < GlobalUnits.MIN_SPLIT_MEN:
		# Unarmed estimate: treat as macemen-equivalent peasants if we can levy.
		return GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.MACEMEN) * men
	return _composition_strength(capped)


static func _home_local_defense_strength(
	base_map: Node, prov: Node, pid: int, ignore_happiness: bool
) -> int:
	var fid := ""
	var wars: Dictionary = _defense_wars(base_map, pid)
	var wid := String(prov.name)
	if wars.has(wid) and typeof(wars[wid]) == TYPE_DICTIONARY:
		fid = str(wars[wid].get("force_id", ""))
	var field := 0
	if fid != "" and base_map.forces.has(fid):
		field = _force_strength(base_map, fid)
	# Other owned field in province (not invasion army abroad).
	for fig in base_map.armies.get_children() if base_map.get("armies") != null else []:
		var other := String(fig.name)
		if other == fid or not base_map.forces.has(other):
			continue
		if int(base_map.get_force_controller(other)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
			continue
		field += _force_strength(base_map, other)
	return field + _castle_sortieable_strength(base_map, pid, prov) \
		+ _home_max_levy_strength(base_map, prov, pid, ignore_happiness)


static func _home_need_strength(enemy_str: int) -> int:
	return maxi(1, int(ceil(float(maxi(enemy_str, 1)) * DEFENSE_WAR_STRENGTH_MARGIN)))


static func tick_home_defense(base_map: Node, pid: int, holdings: Array) -> void:
	if base_map == null or pid < 0:
		return
	var at_risk: Array = []
	for prov in holdings:
		if prov == null:
			continue
		# Track holdings that were ours / still contested under attack.
		if _province_at_risk(base_map, pid, prov):
			at_risk.append(prov)
		else:
			# Also check provinces we lost but still defending/reconquering.
			pass

	# Stale wars: hold countdown or clear; reconquest if we lost dejure.
	var wars: Dictionary = _defense_wars(base_map, pid)
	var stale_keys: Array = wars.keys()
	for k in stale_keys:
		var prov = base_map._get_province_by_id(str(k)) if base_map.has_method("_get_province_by_id") else null
		var w: Dictionary = wars[k] if typeof(wars[k]) == TYPE_DICTIONARY else {}
		if prov == null:
			_clear_defense_war(base_map, pid, str(k))
			continue
		var still_ours = prov.has_method("has_dejure") and prov.has_dejure(pid)
		var risk := _province_at_risk(base_map, pid, prov)
		var needs_mop := _home_province_needs_mop(base_map, pid, prov)
		if not still_ours and bool(w.get("was_dejure", true)):
			# Lost mid-defense → promote to reconquest / invasion target.
			w["phase"] = "reconquest"
			w["recall_army"] = true
			w["halt_reason"] = "lost province — reconquest"
			wars[k] = w
			_home_promote_reconquest(base_map, pid, prov)
			if not risk:
				# No enemies left but we don't own it — invasion war handles.
				continue
		if not risk and needs_mop and still_ours:
			# Field clear but foreign holdings remain — fold / recapture before hold.
			w["phase"] = "mop"
			w["recall_army"] = false
			_home_try_soft_fold(base_map, pid, prov, w)
			if _home_province_needs_mop(base_map, pid, prov):
				_home_engage_enemies(base_map, pid, prov, w)
				w["halt_reason"] = "mopping foreign holdings"
			else:
				w["phase"] = "hold"
				w["hold_left"] = DEFENSE_WAR_HOLD_SEASONS
				w["halt_reason"] = "province restored — holding"
				_home_post_clear_garrison(base_map, pid, prov, w)
			wars[k] = w
			continue
		if not risk and str(w.get("phase", "")) == "hold":
			w["hold_left"] = int(w.get("hold_left", 0)) - 1
			if int(w["hold_left"]) <= 0:
				_home_finish_hold(base_map, pid, prov, w)
				_clear_defense_war(base_map, pid, str(k))
			else:
				w["halt_reason"] = "holding field %d seasons left" % int(w["hold_left"])
				wars[k] = w
			continue
		if not risk and str(w.get("phase", "")) != "reconquest":
			# Fully clear — enter hold.
			if str(w.get("force_id", "")) != "" and base_map.forces.has(str(w.get("force_id", ""))):
				w["phase"] = "hold"
				w["hold_left"] = DEFENSE_WAR_HOLD_SEASONS
				w["recall_army"] = false
				w["halt_reason"] = "threat cleared — holding"
				wars[k] = w
				_home_post_clear_garrison(base_map, pid, prov, w)
			else:
				_clear_defense_war(base_map, pid, str(k))

	# Primary = first at-risk in holdings order (gets neighbor help).
	var primary_id := ""
	for prov in at_risk:
		primary_id = String(prov.name)
		break

	for prov in at_risk:
		var is_primary := String(prov.name) == primary_id
		_tick_home_defense_province(base_map, pid, prov, holdings, is_primary)

	# Continue defense/reconquest for war entries not in holdings (e.g. lost dejure).
	for k in wars.keys():
		var already := false
		for p in at_risk:
			if String(p.name) == str(k):
				already = true
				break
		if already:
			continue
		var prov2 = base_map._get_province_by_id(str(k)) if base_map.has_method("_get_province_by_id") else null
		if prov2 == null:
			continue
		if _province_at_risk(base_map, pid, prov2) \
				or str(wars[k].get("phase", "")) == "reconquest":
			_tick_home_defense_province(base_map, pid, prov2, holdings, primary_id == "" or primary_id == str(k))


static func _home_promote_reconquest(base_map: Node, pid: int, prov: Node) -> void:
	var war: Dictionary = _invasion_war_state(base_map, pid)
	war["target_province_id"] = String(prov.name)
	war["marching"] = true
	war["waiting_reinforce"] = false
	war["halt_reason"] = "reconquest after lost defense"
	# Staging = nearest full-control holding.
	for h in _provinces_for_lord(base_map, pid):
		if _invasion_province_full_control(h, pid):
			war["staging_province_id"] = String(h.name)
			break
	_set_invasion_war_state(base_map, pid, war)


static func _tick_home_defense_province(
	base_map: Node, pid: int, prov: Node, holdings: Array, is_primary: bool
) -> void:
	var wid := String(prov.name)
	var w: Dictionary = _defense_war_for(base_map, pid, wid)
	w["was_dejure"] = prov.has_method("has_dejure") and prov.has_dejure(pid)
	var enemy_str := _enemy_field_strength_in_province(base_map, pid, prov)
	var need := _home_need_strength(enemy_str)
	var siege_lvl := _province_max_enemy_siege_level(base_map, pid, prov)
	var skip_wait := siege_lvl >= 1

	# Always prep: tax relief, craft, buy arms, hire sellswords.
	_home_defense_prep(base_map, prov, pid, need)

	var local_str := _home_local_defense_strength(base_map, prov, pid, true)
	if local_str >= need:
		w["recall_army"] = false
		if not bool(w.get("prep_waited", false)) and not skip_wait:
			w["prep_waited"] = true
			w["phase"] = "prep"
			w["halt_reason"] = "prep season — local %d ≥ need %d" % [local_str, need]
			_defense_wars(base_map, pid)[wid] = w
			return
		# Commit: levy + always sortie castle (keep 50) + merge; only then fight.
		w["phase"] = "fight"
		var ready := _home_commit_local_force(base_map, pid, prov, w, need)
		if ready:
			_home_engage_enemies(base_map, pid, prov, w)
			w["halt_reason"] = "fighting str %d vs need %d" % [
				_force_strength(base_map, str(w.get("force_id", ""))), need
			]
		else:
			w["halt_reason"] = "commit not ready — holding walls (str %d < need %d)" % [
				_force_strength(base_map, str(w.get("force_id", ""))), need
			]
		_defense_wars(base_map, pid)[wid] = w
		return

	# Local insufficient — still prep; primary may cascade neighbors.
	w["phase"] = "prep"
	w["prep_waited"] = true # no luxury wait when already short
	if is_primary:
		var pooled := local_str
		var helpers: Array = _home_cascade_helper_provinces(base_map, pid, prov, holdings)
		for helper in helpers:
			if pooled >= need:
				break
			var add := _home_raise_helper_force(base_map, pid, helper, prov, w, need - pooled)
			pooled += add
		_home_merge_helpers_into_threatened(base_map, pid, prov, w)
		var now := _force_strength(base_map, str(w.get("force_id", ""))) + _castle_sortieable_strength(base_map, pid, prov)
		if now >= need:
			w["recall_army"] = false
			var ready2 := _home_commit_local_force(base_map, pid, prov, w, need)
			if ready2:
				_home_engage_enemies(base_map, pid, prov, w)
				w["phase"] = "fight"
				w["halt_reason"] = "fighting with neighbors str %d ≥ %d" % [
					_force_strength(base_map, str(w.get("force_id", ""))), need
				]
			else:
				w["halt_reason"] = "neighbors mustering — walls until merged"
		else:
			w["recall_army"] = true
			w["halt_reason"] = "recalling army — pooled %d < %d" % [now, need]
			_home_recall_army(base_map, pid, prov)
			# Prep levy only; do not send a stub without castle/army.
			_home_levy_for_defense(base_map, pid, prov, w, need)
			var fid := str(w.get("force_id", ""))
			if fid != "" and base_map.forces.has(fid) and _force_strength(base_map, fid) >= need:
				_home_engage_enemies(base_map, pid, prov, w)
			elif fid != "" and base_map.forces.has(fid):
				# Park stub until relief arrives.
				_defense_ingest_field_force(base_map, pid, prov, fid)
				if not base_map.forces.has(fid):
					w["force_id"] = ""
	else:
		w["halt_reason"] = "local short %d < %d — waiting primary slot" % [local_str, need]
	_defense_wars(base_map, pid)[wid] = w


static func _home_cascade_helper_provinces(
	base_map: Node, pid: int, threatened: Node, _holdings: Array
) -> Array:
	var out: Array = []
	var seen: Dictionary = {String(threatened.name): true}
	var frontier: Array = [threatened]
	var neighbors_map: Dictionary = base_map.province_neighbors if base_map.get("province_neighbors") != null else {}
	# BFS rings among our holdings.
	while not frontier.is_empty() and out.size() < 12:
		var next_front: Array = []
		for p in frontier:
			var nlist: Array = neighbors_map.get(p, [])
			for n in nlist:
				if n == null:
					continue
				var nid := String(n.name)
				if seen.has(nid):
					continue
				seen[nid] = true
				if not (n.has_method("has_dejure") and n.has_dejure(pid)):
					continue
				if _province_at_risk(base_map, pid, n):
					continue # don't strip another threatened province
				if not _invasion_province_full_control(n, pid):
					continue
				out.append(n)
				next_front.append(n)
		frontier = next_front
	return out


static func _home_defense_prep(base_map: Node, prov: Node, pid: int, need_str: int) -> void:
	# Tax to None for happiness recovery when threatened.
	if base_map.has_method("apply_set_holding_tax"):
		base_map.apply_set_holding_tax(String(prov.name), int(GlobalUnits.TAX.NONE), pid)
	# Wartime craft — don't reserve wood for castle.
	_set_craft_for_defense(base_map, prov, pid, false)
	var want := _cheapest_composition_for_strength(need_str)
	_try_buy_war_weapons(base_map, prov, pid, want)
	_try_buy_defense_weapons(base_map, prov, pid)
	_home_try_hire_sellswords(base_map, prov, pid, need_str)
	# Grain for hold period.
	_try_buy_defense_grain(base_map, prov, pid, {})


static func _home_try_hire_sellswords(
	base_map: Node, prov: Node, pid: int, need_str: int
) -> void:
	if base_map.get("sellswords") == null or not base_map.has_method("apply_hire_sellswords"):
		return
	var have := _home_local_defense_strength(base_map, prov, pid, true)
	var short := maxi(0, need_str - have)
	if short <= 0:
		return
	for s in base_map.sellswords.get_children():
		if s.get("province") != prov:
			continue
		var offer: Array = s.get("offer") if s.get("offer") != null else []
		if offer.is_empty():
			continue
		# Greedy cheapest strength from offer.
		var selection: Array = []
		var got_str := 0
		var remaining := GlobalUnits.sellsword_offer_copy(offer)
		while got_str < short:
			var best_i := -1
			var best_ratio := -1.0
			for i in remaining.size():
				var e = remaining[i]
				var cnt := int(e.get("count", 0))
				if cnt <= 0:
					continue
				var t := int(e.get("type", -1))
				var unit_p := maxi(1, GlobalUnits.sellsword_hire_mark_price(
					[{"type": t, "count": 1}], false
				))
				var ratio := float(GlobalUnits.unit_strength(t)) / float(unit_p)
				if ratio > best_ratio:
					best_ratio = ratio
					best_i = i
			if best_i < 0:
				break
			var pick = remaining[best_i]
			var pt := int(pick.get("type"))
			var per := maxi(1, GlobalUnits.unit_strength(pt))
			var need_n := int(ceil(float(short - got_str) / float(per)))
			var take := mini(need_n, int(pick.get("count", 0)))
			if take <= 0:
				break
			selection.append({"type": pt, "count": take})
			got_str += per * take
			pick["count"] = int(pick.get("count", 0)) - take
		if selection.is_empty():
			continue
		var cost := GlobalUnits.sellsword_hire_mark_price(selection, false)
		if cost > _marks_spendable(base_map, pid):
			# Shrink selection.
			while not selection.is_empty() and GlobalUnits.sellsword_hire_mark_price(selection, false) > _marks_spendable(base_map, pid):
				var last: Dictionary = selection[selection.size() - 1]
				last["count"] = int(last.get("count", 0)) - 1
				if int(last["count"]) <= 0:
					selection.pop_back()
			if selection.is_empty():
				continue
			cost = GlobalUnits.sellsword_hire_mark_price(selection, false)
		var band_id := String(s.name)
		var cell: Vector2i = s.cell if s.get("cell") != null else Vector2i.ZERO
		if base_map.get("_next_runtime_force") == null:
			continue
		base_map._next_runtime_force = int(base_map._next_runtime_force) + 1
		var new_id := "rt_%d" % int(base_map._next_runtime_force)
		base_map.apply_hire_sellswords(band_id, pid, selection, false, cost, new_id, cell.x, cell.y)
		var war: Dictionary = _defense_war_for(base_map, pid, String(prov.name))
		if str(war.get("force_id", "")) == "" and base_map.forces.has(new_id):
			war["force_id"] = new_id
			_defense_wars(base_map, pid)[String(prov.name)] = war
		elif base_map.forces.has(new_id) and str(war.get("force_id", "")) != "":
			_absorb_field_force_into(base_map, str(war.get("force_id")), new_id)
		break


## Levy + always sortie castle to reserve floor + merge.
## Returns true only when the field stack is actually ≥ need (safe to engage).
static func _home_commit_local_force(
	base_map: Node, pid: int, prov: Node, w: Dictionary, need: int
) -> bool:
	_home_levy_for_defense(base_map, pid, prov, w, need)
	var fid := str(w.get("force_id", ""))
	# Always pull castle down to reserve when committing a field fight.
	fid = _home_sortie_castle_to_reserve(base_map, pid, prov, fid)
	w["force_id"] = fid
	_home_merge_helpers_into_threatened(base_map, pid, prov, w)
	fid = str(w.get("force_id", ""))
	var have := _force_strength(base_map, fid) if fid != "" and base_map.forces.has(fid) else 0
	if have >= need:
		return true
	# Too weak in the field — don't suicide with a stub; park and wait.
	if fid != "" and base_map.forces.has(fid):
		_defense_ingest_field_force(base_map, pid, prov, fid)
		if not base_map.forces.has(fid):
			w["force_id"] = ""
	return false


## Raise / top up defense field levy (threat ignores happiness). Does not sortie.
static func _home_levy_for_defense(
	base_map: Node, pid: int, prov: Node, w: Dictionary, need: int
) -> void:
	var fid := str(w.get("force_id", ""))
	if fid != "" and not base_map.forces.has(fid):
		fid = ""
		w["force_id"] = ""
	var have := _force_strength(base_map, fid) if fid != "" else 0
	var short := maxi(0, need - have)
	if short <= 0:
		return
	var men := _clamp_levy_men(base_map, prov, pid, 99999, false, true)
	if men < GlobalUnits.MIN_SPLIT_MEN:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var fitted: Array = []
	var left := men
	for e in _cheapest_composition_for_strength(short):
		if left <= 0:
			break
		var t := int(e.get("type"))
		var n := mini(int(e.get("count", 0)), left)
		var wk := _weapon_key_for_type(t)
		if wk != "":
			n = mini(n, int(stock.get(wk, 0)))
		if n > 0:
			fitted.append({"type": t, "count": n})
			left -= n
	if GlobalUnits.composition_total_men(fitted) < GlobalUnits.MIN_SPLIT_MEN:
		return
	_try_buy_war_weapons(base_map, prov, pid, fitted)
	var new_id := _levy_composition_field(base_map, prov, pid, fitted)
	if new_id == "":
		return
	if fid == "":
		w["force_id"] = new_id
	else:
		w["force_id"] = _absorb_field_force_into(base_map, fid, new_id)


## Pull castle garrison into the field, leaving DEFENSE_WAR_CASTLE_RESERVE (prefer archers).
## Uses direct transfers (no MP/adjacency) so commit can't "forget" the garrison.
static func _home_sortie_castle_to_reserve(
	base_map: Node, pid: int, prov: Node, merge_into: String
) -> String:
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("is_operational") or not castle.is_operational():
		return merge_into
	var total := GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
	var can_take := maxi(0, total - DEFENSE_WAR_CASTLE_RESERVE)
	if can_take <= 0:
		return merge_into

	var fid := merge_into
	if fid != "" and not base_map.forces.has(fid):
		fid = ""

	# Prefer non-archers first so reserve stays archer-heavy.
	for spot in [GlobalUnits.SPOT.OUTSIDE, GlobalUnits.SPOT.INSIDE]:
		if can_take <= 0:
			break
		var still := GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
		var room_leave := maxi(0, still - DEFENSE_WAR_CASTLE_RESERVE)
		var take_n := mini(can_take, room_leave)
		if take_n <= 0:
			continue
		var gid := _ensure_spot_garrison(base_map, castle, spot)
		if gid == "" or not base_map.forces.has(gid):
			continue
		var out_units := _home_extract_non_archers_first(
			base_map.forces[gid].get("units", []), pid, take_n
		)
		if out_units.is_empty():
			continue
		var took := GlobalUnits.total_men(out_units)
		# Ensure destination field force exists.
		if fid == "" or not base_map.forces.has(fid):
			fid = _home_spawn_field_from_garrison(
				base_map, pid, castle, spot, gid, out_units
			)
			if fid == "":
				continue
		else:
			GlobalUnits.subtract_units(base_map.forces[gid]["units"], out_units)
			base_map.forces[fid]["units"] = GlobalUnits.merge_units(
				base_map.forces[fid].get("units", []),
				GlobalUnits.units_from_spec(out_units)
			)
			if base_map.has_method("_cleanup_force_if_empty"):
				base_map._cleanup_force_if_empty(gid)
		can_take -= took
	if base_map.has_method("_building_key") and base_map.has_method("refresh_building_flags"):
		base_map.refresh_building_flags(str(base_map._building_key(castle)))
	if base_map.has_method("update_all_army_visuals"):
		base_map.update_all_army_visuals()
	if base_map.get("pathfinding") != null and base_map.pathfinding.has_method("rebuild_occupancy"):
		base_map.pathfinding.rebuild_occupancy()
	return fid if fid != "" and base_map.forces.has(fid) else merge_into


static func _home_extract_non_archers_first(units: Array, pid: int, want_men: int) -> Array:
	if want_men <= 0:
		return []
	var pool: Array = GlobalUnits.clone_units(units) if GlobalUnits.has_method("clone_units") else units.duplicate(true)
	var out: Array = []
	var left := want_men
	for archers_pass in [false, true]:
		var filtered: Array = []
		for s in pool:
			if left <= 0:
				break
			if int(s.get("owner", -1)) != pid:
				continue
			if not GlobalUnits.is_fighting_stack(s):
				continue
			var is_ar := int(s.get("type", -1)) == int(GlobalUnits.UNIT_TYPE.ARCHER)
			if is_ar != archers_pass:
				continue
			var take := mini(left, int(s.get("count", 0)))
			if take <= 0:
				continue
			filtered.append(GlobalUnits.make_stack(
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
		if filtered.is_empty():
			continue
		GlobalUnits.subtract_units(pool, filtered)
		for s2 in filtered:
			out.append(s2)
	return out


static func _home_spawn_field_from_garrison(
	base_map: Node, _pid: int, castle: Node, _spot: int, gid: String, out_units: Array
) -> String:
	if out_units.is_empty() or not base_map.forces.has(gid):
		return ""
	var approach: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	if base_map.has_method("get_free_approach_cell_for"):
		approach = base_map.get_free_approach_cell_for(castle)
	if approach.x == 0x7FFFFFFF:
		# Fallback: any approach cell even if occupied.
		var pf = base_map.get("pathfinding")
		if pf != null and pf.has_method("get_approach_cells"):
			var cells: Array = pf.get_approach_cells(castle)
			if not cells.is_empty():
				approach = cells[0]
	if approach.x == 0x7FFFFFFF:
		return ""
	if base_map.get("_next_runtime_force") == null:
		return ""
	if not base_map.has_method("apply_sortie_units"):
		return ""
	base_map._next_runtime_force = int(base_map._next_runtime_force) + 1
	var new_id := "rt_%d" % int(base_map._next_runtime_force)
	base_map.apply_sortie_units(gid, new_id, out_units, approach.x, approach.y, {})
	return new_id if base_map.forces.has(new_id) else ""


static func _home_sortie_castle_spot(
	base_map: Node, pid: int, prov: Node, _castle: Node, _spot: int, merge_into: String
) -> String:
	# Legacy helper — prefer _home_sortie_castle_to_reserve.
	return _home_sortie_castle_to_reserve(base_map, pid, prov, merge_into)


static func _home_raise_helper_force(
	base_map: Node, pid: int, helper: Node, threatened: Node, w: Dictionary, short_str: int
) -> int:
	if short_str <= 0 or helper == null:
		return 0
	_home_defense_prep(base_map, helper, pid, short_str)
	# Levy only — do not empty helper castle.
	var men := _clamp_levy_men(base_map, helper, pid, 99999, false, true)
	if men < GlobalUnits.MIN_SPLIT_MEN:
		return 0
	var fitted: Array = []
	var stock: Dictionary = helper.get_weapons_for(pid) if helper.has_method("get_weapons_for") else {}
	var left := men
	for e in _cheapest_composition_for_strength(short_str):
		if left <= 0:
			break
		var t := int(e.get("type"))
		var n := mini(int(e.get("count", 0)), left)
		var wk := _weapon_key_for_type(t)
		if wk != "":
			n = mini(n, int(stock.get(wk, 0)))
		if n > 0:
			fitted.append({"type": t, "count": n})
			left -= n
	if GlobalUnits.composition_total_men(fitted) < GlobalUnits.MIN_SPLIT_MEN:
		return 0
	_try_buy_war_weapons(base_map, helper, pid, fitted)
	var new_id := _levy_composition_field(base_map, helper, pid, fitted)
	if new_id == "":
		return 0
	var added := _force_strength(base_map, new_id)
	# March toward threatened province town.
	var town = threatened.get_town() if threatened.has_method("get_town") else null
	if town != null:
		_move_force_toward_building(base_map, new_id, town)
	var main := str(w.get("force_id", ""))
	if main == "":
		w["force_id"] = new_id
	else:
		w["force_id"] = _absorb_field_force_into(base_map, main, new_id)
	return added


static func _home_merge_helpers_into_threatened(
	base_map: Node, pid: int, prov: Node, w: Dictionary
) -> void:
	var main := str(w.get("force_id", ""))
	if main == "" or not base_map.forces.has(main):
		main = _find_field_army(base_map, pid, prov)
		w["force_id"] = main
	if main == "" or not base_map.forces.has(main):
		return
	# Only merge other owned stacks already in this province (not the distant invasion army).
	if base_map.get("armies") == null:
		return
	for fig in base_map.armies.get_children():
		var other := String(fig.name)
		if other == main or not base_map.forces.has(other):
			continue
		if int(base_map.get_force_controller(other)) != pid:
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
			continue
		main = _absorb_field_force_into(base_map, main, other)
	w["force_id"] = main


static func _home_engage_enemies(
	base_map: Node, pid: int, prov: Node, w: Dictionary
) -> void:
	var fid := str(w.get("force_id", ""))
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, prov)
		w["force_id"] = fid
	if fid == "" or not base_map.forces.has(fid):
		return
	# Soft-fold empty foreign holdings whenever field is clear.
	if _enemy_field_ids_in_province(base_map, pid, prov).is_empty():
		_home_try_soft_fold(base_map, pid, prov, w)
		if not _home_province_needs_mop(base_map, pid, prov):
			return
	# Field enemies first.
	var enemies: Array = _enemy_field_ids_in_province(base_map, pid, prov)
	if not enemies.is_empty():
		var target := str(enemies[0])
		if _forces_same_or_adjacent_cell(base_map, fid, target):
			if base_map.has_method("request_battle_attack"):
				base_map.request_battle_attack(fid, target, "")
		else:
			_move_force_toward_force(base_map, fid, target)
		return
	# Recapture foreign buildings (including empty — fold may have failed).
	var mop: Array = _home_list_mop_buildings(base_map, pid, fid, prov)
	if mop.is_empty():
		_home_try_soft_fold(base_map, pid, prov, w)
		return
	var o: Dictionary = mop[0]
	var b = o.get("building")
	if b == null:
		return
	if _force_adjacent_to_building(base_map, fid, b):
		_try_invasion_assault_building(base_map, pid, fid, b, w)
		_home_try_soft_fold(base_map, pid, prov, w)
	else:
		_move_force_toward_building(base_map, fid, b)


## True while enemy field present or any non-owned holding remains (not full flip).
static func _home_province_needs_mop(base_map: Node, pid: int, prov: Node) -> bool:
	if prov == null:
		return false
	if _province_at_risk(base_map, pid, prov):
		return true
	if not _invasion_province_full_control(prov, pid):
		return true
	return not _home_list_mop_buildings(base_map, pid, "", prov).is_empty()


static func _home_try_soft_fold(
	base_map: Node, _pid: int, prov: Node, w: Dictionary
) -> void:
	if base_map == null or prov == null:
		return
	var fid := str(w.get("force_id", "")) if w != null else ""
	if base_map.has_method("try_fold_province_to_town_owner"):
		base_map.try_fold_province_to_town_owner(prov, fid)
	if prov.has_method("recompute_control"):
		prov.recompute_control()


## Foreign-owned buildings to retake (empty included — soft-fold should clear these).
static func _home_list_mop_buildings(
	base_map: Node, pid: int, fid: String, prov: Node
) -> Array:
	var out: Array = []
	if prov == null:
		return out
	var town = prov.get_town() if prov.has_method("get_town") else null
	var containers: Array = []
	if prov.get("settlements") != null:
		containers.append(prov.settlements)
	if prov.get("economy") != null:
		containers.append(prov.economy)
	if prov.get("defense") != null:
		containers.append(prov.defense)
	for container in containers:
		for b in container.get_children():
			if b == null:
				continue
			var is_castle := int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE)
			if is_castle and b.has_method("is_army_interactable") and not b.is_army_interactable():
				continue
			var friendly := false
			if base_map.has_method("is_building_friendly_to"):
				friendly = bool(base_map.is_building_friendly_to(b, pid))
			elif b.get("player_owner") != null:
				friendly = int(b.player_owner) == pid
			if friendly:
				continue
			if is_castle and GlobalUnits.fighting_men(base_map.get_all_building_garrison(b)) <= 0:
				if b.has_method("is_operational") and not b.is_operational():
					continue
			var def_str := _invasion_building_defense(base_map, b, fid)
			var bkey := str(base_map._building_key(b)) if base_map.has_method("_building_key") else String(b.name)
			out.append({
				"kind": "building",
				"id": bkey,
				"building": b,
				"defense": def_str,
				"label": _invasion_building_label(b),
				"is_town": b == town,
			})
	if out.is_empty():
		return out
	# Prefer town if foreign, else nearest / weaker.
	var best_i := 0
	var best_score := 0x7FFFFFFF
	for i in out.size():
		var score := int(out[i].get("defense", 0))
		if bool(out[i].get("is_town")):
			score -= 100000
		if fid != "" and base_map.forces.has(fid):
			score += _invasion_dist_to_objective(base_map, fid, out[i]) * 10
		if score < best_score:
			best_score = score
			best_i = i
	if best_i != 0:
		var tmp = out[0]
		out[0] = out[best_i]
		out[best_i] = tmp
	return out


static func _home_recall_army(base_map: Node, pid: int, prov: Node) -> void:
	var war: Dictionary = _invasion_war_state(base_map, pid)
	war["waiting_reinforce"] = false
	war["marching"] = true
	war["halt_reason"] = "recalling to defend %s" % String(prov.name)
	# If we still own it, move invasion army home; if lost, reconquest target is set elsewhere.
	if prov.has_method("has_dejure") and prov.has_dejure(pid):
		war["target_province_id"] = String(prov.name) # keep focus
	var fid := str(war.get("force_id", ""))
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_invasion_field_army(base_map, pid)
		war["force_id"] = fid
	if fid != "" and base_map.forces.has(fid):
		var town = prov.get_town() if prov.has_method("get_town") else null
		if town != null:
			_move_force_toward_building(base_map, fid, town)
	_set_invasion_war_state(base_map, pid, war)


static func _home_post_clear_garrison(
	base_map: Node, pid: int, prov: Node, w: Dictionary
) -> void:
	# Re-garrison castle to at least reserve floor from field if needed.
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	var fid := str(w.get("force_id", ""))
	if castle == null or fid == "" or not base_map.forces.has(fid):
		return
	var have := GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
	var need_men := maxi(0, DEFENSE_WAR_CASTLE_RESERVE - have)
	if need_men <= 0:
		return
	if not _force_adjacent_to_building(base_map, fid, castle):
		_move_force_toward_building(base_map, fid, castle)
		return
	var out_units := _extract_any_stacks(base_map.forces[fid].get("units", []), pid, need_men)
	if out_units.is_empty():
		return
	var spot := GlobalUnits.SPOT.INSIDE
	var dest := _ensure_spot_garrison(base_map, castle, spot)
	if dest == "":
		return
	if base_map.has_method("apply_transfer_units"):
		base_map.apply_transfer_units(fid, dest, out_units, {})


static func _home_finish_hold(
	base_map: Node, pid: int, prov: Node, w: Dictionary
) -> void:
	var fid := str(w.get("force_id", ""))
	if fid == "" or not base_map.forces.has(fid):
		return
	# Park then disband remainder.
	_defense_ingest_field_force(base_map, pid, prov, fid)
	if base_map.forces.has(fid) and GlobalUnits.total_men(base_map.forces[fid].get("units", [])) > 0:
		if base_map.has_method("request_disband_force"):
			base_map.request_disband_force(fid)


# =============================================================================
# Conquest (automatic after Norman Keep+ garrisons on all secure holdings)
# =============================================================================


static func _invasion_war_state(base_map: Node, pid: int) -> Dictionary:
	if not base_map.players.has(pid):
		return {}
	var gd: Dictionary = base_map.players[pid].game_data
	if not gd.has(AI_INVASION_WAR_KEY) or typeof(gd[AI_INVASION_WAR_KEY]) != TYPE_DICTIONARY:
		gd[AI_INVASION_WAR_KEY] = {
			"target_province_id": "",
			"staging_province_id": "",
			"force_id": "",
			"reinforce_force_id": "",
			"park_building_key": "",
			"marching": false,
			"waiting_reinforce": false,
			"halt_reason": "",
			"objective_kind": "", # "building" | "army" | ""
			"objective_id": "", # building key or force id
		}
	var w: Dictionary = gd[AI_INVASION_WAR_KEY]
	if not w.has("reinforce_force_id"):
		w["reinforce_force_id"] = ""
	if not w.has("park_building_key"):
		w["park_building_key"] = ""
	if not w.has("waiting_reinforce"):
		w["waiting_reinforce"] = false
	return w


static func _set_invasion_war_state(base_map: Node, pid: int, war: Dictionary) -> void:
	if not base_map.players.has(pid):
		return
	base_map.players[pid].game_data[AI_INVASION_WAR_KEY] = war


static func _invasion_force_id(base_map: Node, pid: int) -> String:
	var war: Dictionary = _invasion_war_state(base_map, pid)
	var fid := str(war.get("force_id", ""))
	if fid != "" and base_map.forces.has(fid):
		return fid
	return ""


## Conquest-ready: Norman Keep+ (or max Concentric), level garrisons full, no stray field,
## and wood+smith at Medium (iron mine Medium only if the province has an iron deposit).
## Mid-tier upgrades keep standing capacity — still ready. Empty-build/dismantle is not.
static func _province_defense_complete(base_map: Node, prov: Node, pid: int) -> bool:
	if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(pid):
		return false
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("standing_level"):
		return false
	var standing := int(castle.standing_level())
	if standing < DEFENSE_CONQUEST_MIN_CASTLE:
		return false
	if castle.has_method("is_under_construction") and castle.is_under_construction():
		var upgrading: bool = (
			castle.has_method("is_upgrade_project") and bool(castle.is_upgrade_project())
		)
		if not upgrading:
			return false
	if _defense_has_stray_field(base_map, pid, prov, _invasion_force_id(base_map, pid)):
		return false
	if not _defense_active_garrisons_full(base_map, prov, pid):
		return false
	return _province_econ_ready_for_conquest(prov, pid)


## Woodcutter + blacksmith at Medium. Iron mine Medium only when an iron deposit
## exists and arms stock is still too thin to start an invasion drip (so a piled
## sword stockpile is not blocked forever on a 1300-mark mine upgrade).
static func _province_econ_ready_for_conquest(prov: Node, pid: int) -> bool:
	if prov == null:
		return false
	for subtype in DEFENSE_ECON_CONQUEST_REQUIRED:
		if not _econ_owned_at_least_stage(prov, pid, int(subtype), DEFENSE_ECON_CONQUEST_MIN_STAGE):
			return false
	if _province_has_iron_deposit(prov):
		if not _econ_owned_at_least_stage(
			prov, pid, DEFENSE_ECON_IRON_SUBTYPE, DEFENSE_ECON_CONQUEST_MIN_STAGE
		):
			if not _province_arms_ready_for_invasion(prov, pid):
				return false
	return true


## True when weapon stock can already arm at least one conquest drip (no peasants).
static func _province_arms_ready_for_invasion(prov: Node, pid: int) -> bool:
	if prov == null:
		return false
	var armed: Array = _conquest_arm_from_stock(prov, pid, INVASION_LEVY_DRIP)
	return GlobalUnits.composition_total_men(armed) >= GlobalUnits.MIN_SPLIT_MEN


## True if this province has an iron deposit pad (built mine or iron/random-resolved deposit).
static func _province_has_iron_deposit(prov: Node) -> bool:
	if prov == null or prov.get("economy") == null:
		return false
	for b in prov.economy.get_children():
		if b == null:
			continue
		if b.has_method("is_built") and b.is_built() and int(b.get("subtype")) == DEFENSE_ECON_IRON_SUBTYPE:
			return true
		# Unbuilt deposit pad reserved for iron. (Object.get takes property name only.)
		if b.get("slot_kind") == null or b.get("deposit_type") == null:
			continue
		if int(b.slot_kind) == 1 and int(b.deposit_type) == 2: # DEPOSIT + IRON
			return true
	return false


## Owned built economy building of `subtype` at stage ≥ `min_stage` (not razed).
static func _econ_owned_at_least_stage(prov: Node, pid: int, subtype: int, min_stage: int) -> bool:
	if prov == null or prov.get("economy") == null:
		return false
	for b in prov.economy.get_children():
		if b == null or b.get("player_owner") == null:
			continue
		if int(b.player_owner) != pid:
			continue
		if not b.has_method("is_built") or not b.is_built():
			continue
		if int(b.get("subtype")) != subtype:
			continue
		var st := int(b.stage) if b.get("stage") != null else 0
		if st == 4: # RAZED
			continue
		if st >= min_stage:
			return true
	return false


static func _all_holdings_defense_complete(base_map: Node, pid: int, holdings: Array) -> bool:
	if holdings.is_empty():
		return false
	var any_full := false
	for prov in holdings:
		# Contested mop-up holdings don't block "ready to conquer" — they're war targets.
		if not _invasion_province_full_control(prov, pid):
			continue
		any_full = true
		if not _province_defense_complete(base_map, prov, pid):
			return false
	return any_full


static func tick_invasion(base_map: Node, pid: int, holdings: Array) -> void:
	if base_map == null or pid < 0 or holdings.is_empty():
		return
	# Home defense may pause conquest while recalling / under siege.
	if _home_defense_pauses_invasion(base_map, pid):
		var war_p: Dictionary = _invasion_war_state(base_map, pid)
		# Still move recalled army toward the threatened province.
		var tw := ""
		var wars: Dictionary = _defense_wars(base_map, pid)
		for k in wars.keys():
			var dw = wars[k]
			if typeof(dw) == TYPE_DICTIONARY and bool(dw.get("recall_army", false)):
				tw = str(k)
				break
		if tw != "":
			var tprov = base_map._get_province_by_id(tw) if base_map.has_method("_get_province_by_id") else null
			var fid := str(war_p.get("force_id", ""))
			if fid == "" or not base_map.forces.has(fid):
				fid = _find_invasion_field_army(base_map, pid)
				war_p["force_id"] = fid
			if fid != "" and tprov != null:
				var town = tprov.get_town() if tprov.has_method("get_town") else null
				if town != null:
					_move_force_toward_building(base_map, fid, town)
				# Merge with defense force on arrival.
				var dw2: Dictionary = _defense_war_for(base_map, pid, tw)
				var dfid := str(dw2.get("force_id", ""))
				if dfid != "" and base_map.forces.has(dfid) and base_map.forces.has(fid):
					if _forces_same_or_adjacent_cell(base_map, fid, dfid):
						fid = _absorb_field_force_into(base_map, fid, dfid)
						dw2["force_id"] = fid
						_defense_wars(base_map, pid)[tw] = dw2
						war_p["force_id"] = fid
			war_p["halt_reason"] = "paused — defending %s" % tw
			_set_invasion_war_state(base_map, pid, war_p)
		return
	# Validate tagged invasion force (do not adopt random field stacks while idle —
	# that would eat home-defense armies and re-tag leftovers forever).
	var war: Dictionary = _invasion_war_state(base_map, pid)
	var fid := str(war.get("force_id", ""))
	var had_tagged_force = fid != "" and base_map.forces.has(fid)
	if fid != "" and not base_map.forces.has(fid):
		fid = ""
		war["force_id"] = ""

	# Always ship arms toward incomplete holdings.
	_invasion_caravan_supply_arms(base_map, pid, holdings)

	# Active mop-up / campaign — keep going even if a new dejure holding is unfortified.
	var target_id := str(war.get("target_province_id", ""))
	var target_prov = null
	if target_id != "" and base_map.has_method("_get_province_by_id"):
		target_prov = base_map._get_province_by_id(target_id)
	if target_prov != null and _is_active_conquest_target(base_map, pid, target_prov):
		if fid == "":
			fid = _find_invasion_field_army(base_map, pid)
			if fid != "":
				war["force_id"] = fid
		_invasion_refresh_staging(base_map, pid, war, holdings, fid)
		_execute_invasion_war_season(base_map, pid, war, holdings)
		_set_invasion_war_state(base_map, pid, war)
		return

	# Contested dejure holding (town taken, flip incomplete) — finish it before new wars.
	for prov in holdings:
		if prov != null and _is_active_conquest_target(base_map, pid, prov):
			war["target_province_id"] = String(prov.name)
			war["marching"] = bool(war.get("marching", false))
			war["waiting_reinforce"] = bool(war.get("waiting_reinforce", false))
			if fid == "":
				fid = _find_invasion_field_army(base_map, pid)
				if fid != "":
					war["force_id"] = fid
			_invasion_refresh_staging(base_map, pid, war, holdings, fid)
			_execute_invasion_war_season(base_map, pid, war, holdings)
			_set_invasion_war_state(base_map, pid, war)
			return

	# Control folded after last capture: settle missed because target is no longer "active".
	if target_prov != null and _invasion_province_secured(base_map, pid, target_prov):
		_invasion_complete_campaign(base_map, pid, war, fid, target_prov, holdings)
		_set_invasion_war_state(base_map, pid, war)
		return

	# Orphan tagged invasion stack (stale force_id after fold) — demobilize into garrisons.
	if had_tagged_force and fid != "" and base_map.forces.has(fid):
		var under = null
		if base_map.has_method("province_under_force"):
			under = base_map.province_under_force(fid)
		if under == null or not _invasion_province_full_control(under, pid):
			under = null
			for h in holdings:
				if _invasion_province_full_control(h, pid):
					under = h
					break
			if under == null and not holdings.is_empty():
				under = holdings[0]
		_invasion_complete_campaign(base_map, pid, war, fid, under, holdings)
		_set_invasion_war_state(base_map, pid, war)
		return

	# Clear stale target / campaign fields.
	if target_id != "":
		war["target_province_id"] = ""
		war["staging_province_id"] = ""
		war["marching"] = false
		war["waiting_reinforce"] = false
		war["reinforce_force_id"] = ""
		war["park_building_key"] = ""
		war["objective_kind"] = ""
		war["objective_id"] = ""
		war["force_id"] = ""
		if str(war.get("halt_reason", "")).begins_with("captured"):
			war["halt_reason"] = "province secured — garrisoned & disbanded"

	var all_done := _all_holdings_defense_complete(base_map, pid, holdings)
	if not all_done:
		# Wait / fortify — no field invasion stack while rebuilding.
		_set_invasion_war_state(base_map, pid, war)
		return

	# Pick a new conquest target on our border (council / human / AI; not allies).
	var pick: Dictionary = _pick_conquest_target(base_map, pid, holdings)
	if pick.is_empty():
		war["target_province_id"] = ""
		war["staging_province_id"] = ""
		war["marching"] = false
		war["waiting_reinforce"] = false
		war["objective_kind"] = ""
		war["objective_id"] = ""
		war["halt_reason"] = "no conquest target on border"
		_set_invasion_war_state(base_map, pid, war)
		return
	war["target_province_id"] = str(pick.get("province_id", ""))
	war["staging_province_id"] = str(pick.get("staging_id", ""))
	war["marching"] = false
	war["waiting_reinforce"] = false
	war["reinforce_force_id"] = ""
	war["park_building_key"] = ""
	war["objective_kind"] = ""
	war["objective_id"] = ""
	war["halt_reason"] = ""
	_maybe_declare_war_for_conquest(base_map, pid, war["target_province_id"])
	_invasion_refresh_staging(base_map, pid, war, holdings, fid)
	_execute_invasion_war_season(base_map, pid, war, holdings)
	_set_invasion_war_state(base_map, pid, war)


static func _invasion_refresh_staging(
	base_map: Node, pid: int, war: Dictionary, holdings: Array, fid: String
) -> void:
	if fid != "" and base_map.has_method("province_under_force"):
		var under = base_map.province_under_force(fid)
		if under != null and under.has_method("has_dejure") and under.has_dejure(pid):
			# Don't overwrite staging with the contested conquest province.
			if _invasion_province_full_control(under, pid):
				war["staging_province_id"] = String(under.name)
	if str(war.get("staging_province_id", "")) == "":
		var pick2: Dictionary = _pick_conquest_target(base_map, pid, holdings)
		var fallback := String(holdings[0].name) if not holdings.is_empty() else ""
		for h in holdings:
			if _invasion_province_full_control(h, pid):
				fallback = String(h.name)
				break
		war["staging_province_id"] = str(pick2.get("staging_id", fallback))


## Dejure + defacto both this lord (province flip complete).
static func _invasion_province_full_control(prov: Node, pid: int) -> bool:
	if prov == null or pid < 0:
		return false
	if not prov.has_method("has_dejure") or not prov.has_dejure(pid):
		return false
	var df = prov.get("defacto")
	if df == null:
		return false
	var no_df := -1
	if prov.get("NO_DEFACTO") != null:
		no_df = int(prov.NO_DEFACTO)
	if int(df) == no_df:
		return false
	return int(df) == pid


## Enemy border target, or unfinished mop (dejure without defacto / leftover fighting).
static func _is_active_conquest_target(base_map: Node, pid: int, prov: Node) -> bool:
	if prov == null or not is_instance_valid(prov):
		return false
	if _invasion_province_full_control(prov, pid):
		return false
	if _is_valid_conquest_target(base_map, pid, prov):
		return true
	# We hold the seat / town but flip incomplete, or fighting presence remains.
	if prov.has_method("has_dejure") and prov.has_dejure(pid):
		return true
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		if base_map.has_method("is_building_friendly_to") and base_map.is_building_friendly_to(town, pid):
			return true
		elif town.get("player_owner") != null and int(town.player_owner) == pid:
			return true
	return not _invasion_list_objectives(base_map, pid, "", prov).is_empty()


## Largest owned field army (conquest stack rediscovery).
static func _find_invasion_field_army(base_map: Node, pid: int) -> String:
	if base_map.get("armies") == null or base_map.get("forces") == null:
		return ""
	var best := ""
	var best_men := 0
	for fig in base_map.armies.get_children():
		var fid := String(fig.name)
		if not base_map.forces.has(fid):
			continue
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if int(base_map.get_force_controller(fid)) != pid:
			continue
		var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
		if men > best_men:
			best_men = men
			best = fid
	return best


static func _invasion_count_in_force(base_map: Node, fid: String, pid: int) -> int:
	## Legacy name — total men in force (was invasion-army-only).
	if not base_map.forces.has(fid):
		return 0
	var n := 0
	for s in base_map.forces[fid].get("units", []):
		if int(s.get("owner", -1)) != pid:
			continue
		n += int(s.get("count", 0))
	return n


## Men needed at conquest mix to reach `need_str` fighting strength.
static func _conquest_men_for_strength(need_str: int) -> int:
	var avg := (
		float(GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.ARCHER)) * CONQUEST_MIX_ARCHER
		+ float(GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.MACEMEN)) * CONQUEST_MIX_MACE
		+ float(GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.SWORDSMEN)) * CONQUEST_MIX_SWORD
		+ float(GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.PIKEMEN)) * CONQUEST_MIX_PIKE
		+ float(GlobalUnits.unit_strength(GlobalUnits.UNIT_TYPE.PEASANT)) * CONQUEST_MIX_PEASANT
	)
	avg = maxf(avg, 1.0)
	var men := maxi(GlobalUnits.MIN_SPLIT_MEN, int(ceil(float(maxi(need_str, 1)) / avg)))
	var comp := _conquest_composition_for_men(men)
	var guard := 0
	while _composition_strength(comp) < need_str and guard < 40:
		men += GlobalUnits.MIN_SPLIT_MEN
		comp = _conquest_composition_for_men(men)
		guard += 1
	return men


static func _conquest_composition_for_men(men: int) -> Array:
	men = maxi(0, men)
	var archers := int(floor(float(men) * CONQUEST_MIX_ARCHER))
	var maces := int(floor(float(men) * CONQUEST_MIX_MACE))
	var swords := int(floor(float(men) * CONQUEST_MIX_SWORD))
	var pikes := int(floor(float(men) * CONQUEST_MIX_PIKE))
	var peasants := maxi(0, men - archers - maces - swords - pikes)
	var out: Array = []
	if archers > 0:
		out.append({"type": GlobalUnits.UNIT_TYPE.ARCHER, "count": archers})
	if maces > 0:
		out.append({"type": GlobalUnits.UNIT_TYPE.MACEMEN, "count": maces})
	if swords > 0:
		out.append({"type": GlobalUnits.UNIT_TYPE.SWORDSMEN, "count": swords})
	if pikes > 0:
		out.append({"type": GlobalUnits.UNIT_TYPE.PIKEMEN, "count": pikes})
	if peasants > 0:
		out.append({"type": GlobalUnits.UNIT_TYPE.PEASANT, "count": peasants})
	return out


static func _conquest_composition_for_strength(need_str: int) -> Array:
	return _conquest_composition_for_men(_conquest_men_for_strength(need_str))


## Smith the scarcest weapon needed by `want_comp` vs stock.
static func _set_craft_for_composition(
	_base_map: Node, prov: Node, pid: int, want_comp: Array
) -> void:
	if prov == null or prov.get("economy") == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var need := GlobalUnits.weapons_needed_for_composition(want_comp)
	var holes := {
		"bows": maxi(0, int(need.get("bows", 0)) - int(stock.get("bows", 0))),
		"maces": maxi(0, int(need.get("maces", 0)) - int(stock.get("maces", 0))),
		"swords": maxi(0, int(need.get("swords", 0)) - int(stock.get("swords", 0))),
		"pikes": maxi(0, int(need.get("pikes", 0)) - int(stock.get("pikes", 0))),
	}
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


## Craft + buy iron/weapons so a conquest levy can be armed.
static func _conquest_prep_weapons(
	base_map: Node, prov: Node, pid: int, want_comp: Array
) -> void:
	if prov == null or want_comp.is_empty():
		return
	_set_craft_for_composition(base_map, prov, pid, want_comp)
	_try_buy_iron_for_composition(base_map, prov, pid, want_comp)
	_try_buy_defense_iron(base_map, prov, pid, {})
	_try_buy_war_weapons(base_map, prov, pid, want_comp)


static func _execute_invasion_war_season(
	base_map: Node, pid: int, war: Dictionary, holdings: Array
) -> void:
	war["halt_reason"] = ""
	if not war.has("retarget_wait"):
		war["retarget_wait"] = 0
	if not war.has("pending_weaker"):
		war["pending_weaker"] = ""
	# While still at home / raising, switch to a weaker neighbor if one appears
	# (e.g. current target parked a huge field army).
	if not bool(war.get("marching", false)) and not bool(war.get("waiting_reinforce", false)):
		_update_retarget_wait(base_map, pid, holdings, war)
	var target_id := str(war.get("target_province_id", ""))
	var staging_id := str(war.get("staging_province_id", ""))
	var target_prov = base_map._get_province_by_id(target_id) if base_map.has_method("_get_province_by_id") else null
	var staging = base_map._get_province_by_id(staging_id) if base_map.has_method("_get_province_by_id") else null
	if target_prov == null:
		war["halt_reason"] = "no target"
		return
	if staging == null or not _invasion_province_full_control(staging, pid):
		# Prefer any fully controlled holding as staging for reinforce raises.
		for h in holdings:
			if _invasion_province_full_control(h, pid):
				staging = h
				war["staging_province_id"] = String(h.name)
				break
	if staging == null:
		war["halt_reason"] = "no staging"
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

	var raise_need := _invasion_raise_need_strength(base_map, target_prov, pid, fid)

	var raise_prov = staging
	var at_home := true
	if fid != "" and base_map.has_method("province_under_force"):
		var under = base_map.province_under_force(fid)
		if under != null and _invasion_province_full_control(under, pid):
			raise_prov = under
			at_home = true
		elif under != null:
			at_home = false
	# Parked in target province garrison counts as in the field.
	if str(war.get("park_building_key", "")) != "":
		at_home = false

	# Drop stale wars whose cheapest army path would cut through foreign land.
	if at_home and not bool(war.get("marching", false)) \
			and not _conquest_path_is_friendly_corridor(base_map, pid, staging, target_prov):
		war["target_province_id"] = ""
		war["staging_province_id"] = ""
		war["marching"] = false
		war["waiting_reinforce"] = false
		war["objective_kind"] = ""
		war["objective_id"] = ""
		war["halt_reason"] = "target path crosses foreign land"
		return

	# Initial raise at home (not while waiting for reinforce in-province).
	if at_home and not bool(war.get("waiting_reinforce", false)) \
			and (not bool(war.get("marching", false))):
		fid = _invasion_reinforce_force(base_map, raise_prov, pid, fid, raise_need)
		war["force_id"] = fid

	# Recover main force from park / field.
	fid = _invasion_resolve_main_force(base_map, pid, war, fid)
	if fid == "" and str(war.get("park_building_key", "")) == "":
		# No field yet — try raise at staging.
		fid = _invasion_reinforce_force(base_map, staging, pid, "", raise_need)
		war["force_id"] = fid
	if fid == "" and str(war.get("park_building_key", "")) == "":
		var raise_at = staging if staging != null else raise_prov
		var stock_n := GlobalUnits.composition_total_men(
			_conquest_arm_from_stock(raise_at, pid, INVASION_LEVY_DRIP)
		)
		var castle = raise_at.get_castle_plot() if raise_at != null and raise_at.has_method("get_castle_plot") else null
		var garrison_n := 0
		if castle != null and base_map.has_method("get_all_building_garrison"):
			garrison_n = GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
		var sortieable := maxi(0, garrison_n - DEFENSE_WAR_CASTLE_RESERVE)
		if sortieable >= GlobalUnits.MIN_SPLIT_MEN:
			war["halt_reason"] = "mobilizing garrison (%d can sortie, keep %d)" % [
				sortieable, DEFENSE_WAR_CASTLE_RESERVE
			]
		elif stock_n < GlobalUnits.MIN_SPLIT_MEN:
			war["halt_reason"] = "waiting for arms to raise (stock arms %d < %d)" % [
				stock_n, GlobalUnits.MIN_SPLIT_MEN
			]
		else:
			war["halt_reason"] = "levy blocked (pop/grain/happy) and garrison thin (%d)" % garrison_n
		return

	if fid != "" and base_map.forces.has(fid) and not bool(war.get("waiting_reinforce", false)):
		fid = _merge_all_field_into_force(base_map, pid, fid)
		war["force_id"] = fid
	elif fid != "" and base_map.forces.has(fid) and bool(war.get("waiting_reinforce", false)):
		# Don't absorb the reinforce stack into main until tick_wait merges them.
		var rfid_skip := str(war.get("reinforce_force_id", ""))
		if rfid_skip == "" or rfid_skip == fid:
			fid = _merge_all_field_into_force(base_map, pid, fid)
			war["force_id"] = fid

	if not at_home:
		war["marching"] = true

	# Soft-fold empty leftovers once fighting presence is gone.
	if _invasion_list_objectives(base_map, pid, fid, target_prov).is_empty():
		if base_map.has_method("try_fold_province_to_town_owner"):
			base_map.try_fold_province_to_town_owner(target_prov, fid)
		if target_prov.has_method("recompute_control"):
			target_prov.recompute_control()

	# Victory: full dejure + defacto control — garrison the prize, then disband the stack.
	if _invasion_province_secured(base_map, pid, target_prov):
		_invasion_complete_campaign(base_map, pid, war, fid, target_prov, holdings)
		return

	var obj: Dictionary = _invasion_pick_next_objective(base_map, pid, fid, target_prov)
	if obj.is_empty():
		war["halt_reason"] = "no objective (waiting control fold)"
		return
	war["objective_kind"] = str(obj.get("kind", ""))
	war["objective_id"] = str(obj.get("id", ""))

	var obj_def := int(obj.get("defense", 0))
	var my_str := _invasion_main_strength(base_map, pid, war, fid)
	var men := 0
	if fid != "" and base_map.forces.has(fid):
		men = GlobalUnits.total_men(base_map.forces[fid].get("units", []))
	var marching := bool(war.get("marching", false))
	# Need beats the hardest fight in the province (seat OR enemy field), not just the
	# empty town — otherwise we suicide into an open seat while a stack waits nearby.
	var prov_threat := _invasion_target_hardest_strength(base_map, target_prov, pid, fid)
	var need_field := maxi(1, int(ceil(float(maxi(maxi(obj_def, prov_threat), 1)) * INVASION_FIELD_RATIO)))
	var park_slot: Dictionary = _invasion_wait_park_slot(base_map, pid, target_prov)

	# Below 1.0× next hardest + owned castle/town can hold → wait for reinforce (no local levy).
	if (marching or bool(war.get("waiting_reinforce", false)) or not at_home) \
			and my_str < need_field and not park_slot.is_empty():
		war["waiting_reinforce"] = true
		war["marching"] = false
		_invasion_park_main_for_wait(base_map, pid, war, fid, park_slot)
		fid = str(war.get("force_id", ""))
		_invasion_tick_wait_reinforce(base_map, pid, war, staging, need_field, enemy_town, park_slot)
		fid = _invasion_resolve_main_force(base_map, pid, war, str(war.get("force_id", "")))
		my_str = _invasion_main_strength(base_map, pid, war, fid)
		if my_str >= need_field:
			war["waiting_reinforce"] = false
			war["halt_reason"] = "reinforced — str %d ≥ %d" % [my_str, need_field]
			fid = _invasion_resolve_main_force(base_map, pid, war, str(war.get("force_id", "")))
			if fid == "" and str(war.get("park_building_key", "")) != "":
				fid = _invasion_sortie_parked(base_map, pid, war)
				war["force_id"] = fid
			# Fall through to engage.
		else:
			war["halt_reason"] = "waiting reinforce str %d < %d at %s" % [
				my_str, need_field, _invasion_building_label(park_slot.get("b"))
			]
			return

	# Strong enough — clear wait state.
	if my_str >= need_field:
		war["waiting_reinforce"] = false
		if fid == "" and str(war.get("park_building_key", "")) != "":
			fid = _invasion_sortie_parked(base_map, pid, war)
			war["force_id"] = fid

	# Engage if already in contact — never assault a seat while province field threat
	# outclasses us (empty town ≠ free capture).
	if fid != "" and base_map.forces.has(fid) and _invasion_objective_in_contact(base_map, fid, obj):
		war["marching"] = true
		if my_str < need_field:
			if str(obj.get("kind", "")) == "building":
				if not park_slot.is_empty():
					war["waiting_reinforce"] = true
					war["marching"] = false
					_invasion_park_main_for_wait(base_map, pid, war, fid, park_slot)
					war["halt_reason"] = "too weak vs province field/seat str %d < %d — waiting" % [
						my_str, need_field
					]
					return
				war["halt_reason"] = "too weak vs province (str %d < %d) — holding" % [
					my_str, need_field
				]
				return
			war["halt_reason"] = "attack anyway str %d < %d" % [my_str, need_field]
		_invasion_engage_objective(base_map, pid, fid, obj, war)
		return

	# Still at home: dump garrison, raise toward 1.3×, march at ≥1.0× once keep is drained.
	if not marching and at_home and not bool(war.get("waiting_reinforce", false)):
		# Empty the keep into the field (leave reserve) — don't drip 40 forever.
		fid = _invasion_dump_garrison_to_field(base_map, raise_prov, pid, fid)
		war["force_id"] = fid
		fid = _invasion_reinforce_force(base_map, raise_prov, pid, fid, raise_need)
		war["force_id"] = fid
		_try_buy_war_grain(base_map, raise_prov, pid, enemy_town, fid)
		var grain_ready := _load_war_grain_partial(base_map, pid, raise_prov, fid, enemy_town)
		my_str = _force_strength(base_map, fid) if fid != "" and base_map.forces.has(fid) else 0
		men = GlobalUnits.total_men(base_map.forces[fid].get("units", [])) if fid != "" and base_map.forces.has(fid) else 0
		var march_need := _invasion_march_need_strength(base_map, target_prov, pid, fid)
		var keep_drained := _invasion_home_garrison_drained(base_map, raise_prov)
		var strong_enough := my_str >= raise_need or (my_str >= march_need and keep_drained)
		if not strong_enough:
			war["halt_reason"] = "raising — str %d / need %d (march≥%d, men %d%s)" % [
				my_str, raise_need, march_need, _invasion_count_in_force(base_map, fid, pid),
				", keep drained" if keep_drained else ""
			]
			return
		if not grain_ready:
			var cargo_grain := int(base_map.get_force_cargo(fid).get("grain", 0)) if base_map.has_method("get_force_cargo") else 0
			var want := _war_grain_wanted(base_map, fid, enemy_town)
			war["halt_reason"] = "waiting grain cargo %d / %d" % [cargo_grain, want]
			return
		if men < GlobalUnits.MIN_SPLIT_MEN:
			war["halt_reason"] = "force too small to march"
			return
		war["marching"] = true
		if my_str < raise_need:
			war["halt_reason"] = "marching → %s (str %d ≥ %d, shy of 1.3× %d)" % [
				str(obj.get("label", obj.get("id", ""))), my_str, march_need, raise_need
			]
		else:
			war["halt_reason"] = "marching → %s" % str(obj.get("label", obj.get("id", "")))
		_invasion_move_to_objective(base_map, fid, obj)
		return

	# Committed: keep advancing (or attack anyway if weak with no park).
	if fid == "" or not base_map.forces.has(fid):
		# Sortie from park to continue.
		fid = _invasion_sortie_parked(base_map, pid, war)
		war["force_id"] = fid
	if fid == "" or not base_map.forces.has(fid):
		war["halt_reason"] = "no field force to advance"
		return
	var cargo_g := int(base_map.get_force_cargo(fid).get("grain", 0)) if base_map.has_method("get_force_cargo") else 0
	men = GlobalUnits.total_men(base_map.forces[fid].get("units", []))
	var season_need := GlobalUnits.force_grain_need(men, false)
	if cargo_g < season_need and at_home:
		_try_buy_war_grain(base_map, raise_prov, pid, enemy_town, fid)
		_load_war_grain_partial(base_map, pid, raise_prov, fid, enemy_town)
	if men < GlobalUnits.MIN_SPLIT_MEN:
		war["halt_reason"] = "halted — force too small"
		return
	if my_str < need_field and park_slot.is_empty():
		# Do not march on an empty seat while a stronger enemy field owns the province.
		if str(obj.get("kind", "")) == "building" and prov_threat > my_str:
			war["halt_reason"] = "too weak vs province (str %d < %d) — holding" % [
				my_str, need_field
			]
			return
		war["halt_reason"] = "attack anyway → %s (str %d vs %d)" % [
			str(obj.get("label", "")), my_str, need_field
		]
	else:
		war["halt_reason"] = "marching → %s (str %d vs %d)" % [
			str(obj.get("label", "")), my_str, need_field
		]
	war["marching"] = true
	_invasion_move_to_objective(base_map, fid, obj)


## 1.3× hardest seat/field threat for preferred raise size.
static func _invasion_raise_need_strength(
	base_map: Node, target_prov: Node, pid: int, fid: String = ""
) -> int:
	return maxi(1, int(ceil(float(_invasion_target_hardest_strength(base_map, target_prov, pid, fid)) * INVASION_STRENGTH_MARGIN)))


## 1.0× hardest — minimum to leave home after dumping the keep.
static func _invasion_march_need_strength(
	base_map: Node, target_prov: Node, pid: int, fid: String = ""
) -> int:
	return maxi(1, int(ceil(float(_invasion_target_hardest_strength(base_map, target_prov, pid, fid)) * INVASION_MARCH_MIN_MARGIN)))


## Hardest single fight in the province: town, operational castle, or strongest enemy field army.
static func _invasion_target_hardest_strength(
	base_map: Node, target_prov: Node, pid: int, fid: String = ""
) -> int:
	var town = target_prov.get_town() if target_prov != null and target_prov.has_method("get_town") else null
	var castle = target_prov.get_castle_plot() if target_prov != null and target_prov.has_method("get_castle_plot") else null
	var town_str := 0
	if town != null and base_map.has_method("get_settlement_defense_preview"):
		town_str = int(base_map.get_settlement_defense_preview(town, fid).get("strength", 0))
	var castle_str := 0
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		if base_map.has_method("get_building_battle_strength"):
			castle_str = int(base_map.get_building_battle_strength(castle, ""))
	var field_str := _invasion_strongest_enemy_field_strength(base_map, target_prov, pid, fid)
	return maxi(maxi(town_str, castle_str), field_str)


## Strongest hostile field army fighting strength inside `prov` (excludes `fid`).
static func _invasion_strongest_enemy_field_strength(
	base_map: Node, prov: Node, pid: int, exclude_fid: String = ""
) -> int:
	if base_map == null or prov == null or base_map.get("armies") == null or pid < 0:
		return 0
	var best := 0
	for fig in base_map.armies.get_children():
		var other := String(fig.name)
		if other == exclude_fid or not base_map.forces.has(other):
			continue
		var loc: Dictionary = base_map.forces[other].get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
			continue
		var ctrl := int(base_map.get_force_controller(other)) if base_map.has_method("get_force_controller") else -1
		if ctrl == pid:
			continue
		if base_map.has_method("are_friendly_players") and base_map.are_friendly_players(pid, ctrl):
			continue
		best = maxi(best, _force_strength(base_map, other))
	return best


## True when home castle fighting men are at/under the reserve floor.
static func _invasion_home_garrison_drained(base_map: Node, prov: Node) -> bool:
	if prov == null or base_map == null:
		return true
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle == null or not castle.has_method("is_operational") or not castle.is_operational():
		return true
	var total := GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
	return total <= DEFENSE_WAR_CASTLE_RESERVE


## Pull ALL surplus castle/town garrison into `fid` (leave reserve). One shot, not a drip.
static func _invasion_dump_garrison_to_field(
	base_map: Node, prov: Node, pid: int, fid: String
) -> String:
	if base_map == null or prov == null:
		return fid
	# Huge need_str so the pull takes everyone above reserve.
	return _invasion_pull_garrison_drip(base_map, prov, pid, fid, 999999)


## Full dejure + defacto control (province flip complete).
static func _invasion_province_secured(_base_map: Node, pid: int, prov: Node) -> bool:
	return _invasion_province_full_control(prov, pid)


## End campaign: fill active garrisons from the field stack, park leftovers, disband rest.
static func _invasion_complete_campaign(
	base_map: Node,
	pid: int,
	war: Dictionary,
	fid: String,
	conquered: Node,
	holdings: Array = []
) -> void:
	var staging = null
	var sid := str(war.get("staging_province_id", ""))
	if sid != "" and base_map.has_method("_get_province_by_id"):
		staging = base_map._get_province_by_id(sid)
	var rfid := str(war.get("reinforce_force_id", ""))
	fid = _invasion_settle_after_conquest(base_map, pid, fid, conquered, staging, holdings)
	if rfid != "" and rfid != fid and base_map.forces.has(rfid):
		var park_at = staging if staging != null else conquered
		if park_at != null:
			_defense_ingest_field_force(base_map, pid, park_at, rfid)
		if base_map.forces.has(rfid) \
				and GlobalUnits.total_men(base_map.forces[rfid].get("units", [])) > 0:
			if base_map.has_method("request_disband_force"):
				base_map.request_disband_force(rfid)
	war["target_province_id"] = ""
	war["staging_province_id"] = ""
	war["marching"] = false
	war["waiting_reinforce"] = false
	war["reinforce_force_id"] = ""
	war["park_building_key"] = ""
	war["objective_kind"] = ""
	war["objective_id"] = ""
	war["force_id"] = ""
	war["halt_reason"] = "province secured — garrisoned & disbanded"


## After conquest: fill required garrisons in the new holding (then staging / other holdings), disband rest.
static func _invasion_settle_after_conquest(
	base_map: Node,
	pid: int,
	fid: String,
	conquered: Node,
	staging: Node,
	holdings: Array = []
) -> String:
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, conquered)
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_field_army(base_map, pid, staging)
	if fid == "" or not base_map.forces.has(fid):
		fid = _find_invasion_field_army(base_map, pid)
	if fid == "" or not base_map.forces.has(fid):
		return ""

	# 1) Fill conquered province active slots toward defense mix from the field stack.
	_invasion_fill_garrisons_from_force(base_map, pid, conquered, fid)
	# 2) Leftovers refill staging / home keep that was dumped for the war.
	if staging != null and staging != conquered and base_map.forces.has(fid):
		_invasion_fill_garrisons_from_force(base_map, pid, staging, fid)
	# 3) Any other secured holdings (e.g. home keep drained for the war).
	for h in holdings:
		if not base_map.forces.has(fid):
			break
		if h == null or h == conquered or h == staging:
			continue
		if not _invasion_province_full_control(h, pid):
			continue
		_invasion_fill_garrisons_from_force(base_map, pid, h, fid)
	# 4) Any still-field troops: park into any room, then disband.
	if base_map.forces.has(fid):
		if conquered != null:
			_defense_ingest_field_force(base_map, pid, conquered, fid)
		if staging != null and base_map.forces.has(fid):
			_defense_ingest_field_force(base_map, pid, staging, fid)
		for h in holdings:
			if not base_map.forces.has(fid):
				break
			if h == null or h == conquered or h == staging:
				continue
			if not _invasion_province_full_control(h, pid):
				continue
			_defense_ingest_field_force(base_map, pid, h, fid)
	if base_map.forces.has(fid) and GlobalUnits.total_men(base_map.forces[fid].get("units", [])) > 0:
		if base_map.has_method("request_disband_force"):
			base_map.request_disband_force(fid)
	return ""


## Pour `fid` into active defense slots using each slot's defense mix.
static func _invasion_fill_garrisons_from_force(
	base_map: Node, pid: int, prov: Node, fid: String
) -> void:
	if base_map == null or prov == null or fid == "" or not base_map.forces.has(fid):
		return
	for slot in _defense_active_slots_for_pid(prov, pid):
		if not base_map.forces.has(fid):
			return
		var b = slot["b"]
		var spot := int(slot["spot"])
		var prio := str(slot.get("prio", "town"))
		if b == null or not b.has_method("get_garrison_capacity"):
			continue
		var cap := int(b.get_garrison_capacity(spot))
		if cap <= 0:
			continue
		var have: Dictionary = _spot_fighting_counts(base_map, b, spot, pid)
		var mix: Dictionary = _defense_mix_counts(cap, prio)
		for t in _defense_mix_fill_types(prio):
			if not base_map.forces.has(fid):
				return
			var short := maxi(0, int(mix.get(t, 0)) - int(have.get(t, 0)))
			if short <= 0:
				continue
			var room := _garrison_room(base_map, b, spot)
			if room <= 0:
				break
			var take_n := mini(short, room)
			var out_units := _extract_type_stacks(
				base_map.forces[fid].get("units", []), pid, t, take_n
			)
			if out_units.is_empty():
				continue
			var dest_gid := _ensure_spot_garrison(base_map, b, spot)
			if dest_gid == "":
				continue
			GlobalUnits.subtract_units(base_map.forces[fid]["units"], out_units)
			base_map.forces[dest_gid]["units"] = GlobalUnits.merge_units(
				base_map.forces[dest_gid].get("units", []),
				GlobalUnits.units_from_spec(out_units)
			)
			have[t] = int(have.get(t, 0)) + GlobalUnits.total_men(out_units)
			if base_map.has_method("_building_key") and base_map.has_method("refresh_building_flags"):
				base_map.refresh_building_flags(str(base_map._building_key(b)))
		# Top up remaining capacity with any fighting types.
		if not base_map.forces.has(fid):
			return
		var room2 := _garrison_room(base_map, b, spot)
		if room2 <= 0:
			continue
		var any_out := _extract_any_stacks(base_map.forces[fid].get("units", []), pid, room2)
		if any_out.is_empty():
			continue
		var dest2 := _ensure_spot_garrison(base_map, b, spot)
		if dest2 == "":
			continue
		GlobalUnits.subtract_units(base_map.forces[fid]["units"], any_out)
		base_map.forces[dest2]["units"] = GlobalUnits.merge_units(
			base_map.forces[dest2].get("units", []),
			GlobalUnits.units_from_spec(any_out)
		)
		if base_map.has_method("_building_key") and base_map.has_method("refresh_building_flags"):
			base_map.refresh_building_flags(str(base_map._building_key(b)))
	if base_map.get("pathfinding") != null and base_map.pathfinding.has_method("rebuild_occupancy"):
		base_map.pathfinding.rebuild_occupancy()
	if base_map.has_method("update_all_army_visuals"):
		base_map.update_all_army_visuals()


static func _invasion_list_objectives(base_map: Node, pid: int, fid: String, prov: Node) -> Array:
	var out: Array = []
	if prov == null:
		return out
	# Buildings: enemy-owned with garrison, plus unowned town (must capture even if empty).
	var town = prov.get_town() if prov.has_method("get_town") else null
	var containers: Array = []
	if prov.get("settlements") != null:
		containers.append(prov.settlements)
	if prov.get("economy") != null:
		containers.append(prov.economy)
	if prov.get("defense") != null:
		containers.append(prov.defense)
	for container in containers:
		for b in container.get_children():
			if b == null:
				continue
			var is_castle := int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE)
			if is_castle and b.has_method("is_army_interactable") and not b.is_army_interactable():
				continue
			var friendly := false
			if base_map.has_method("is_building_friendly_to"):
				friendly = bool(base_map.is_building_friendly_to(b, pid))
			else:
				friendly = int(b.get("player_owner")) == pid
			if friendly:
				continue
			var men := GlobalUnits.fighting_men(base_map.get_all_building_garrison(b))
			var is_town = b == town
			# Skip empty buildings except the town (must take it to secure).
			if men <= 0 and not is_town:
				continue
			# Empty castle: never a stop.
			if is_castle and men <= 0:
				continue
			var def_str := _invasion_building_defense(base_map, b, fid)
			var bkey := str(base_map._building_key(b)) if base_map.has_method("_building_key") else String(b.name)
			out.append({
				"kind": "building",
				"id": bkey,
				"building": b,
				"defense": def_str,
				"label": _invasion_building_label(b),
				"is_castle": is_castle,
				"is_town": is_town,
			})
	# Enemy field armies in province.
	if base_map.get("armies") != null:
		for fig in base_map.armies.get_children():
			var other := String(fig.name)
			if other == fid or not base_map.forces.has(other):
				continue
			var loc: Dictionary = base_map.forces[other].get("location", {})
			if str(loc.get("kind", "")) != "cell":
				continue
			if base_map.has_method("province_under_force") and base_map.province_under_force(other) != prov:
				continue
			var ctrl := int(base_map.get_force_controller(other))
			if ctrl == pid:
				continue
			if base_map.has_method("are_friendly_players") and base_map.are_friendly_players(pid, ctrl):
				continue
			var omen := GlobalUnits.fighting_men(base_map.forces[other].get("units", []))
			if omen <= 0:
				continue
			out.append({
				"kind": "army",
				"id": other,
				"defense": _force_strength(base_map, other),
				"label": "army %s" % other,
			})
	return out


static func _invasion_building_label(b: Node) -> String:
	if b == null:
		return "?"
	if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE):
		return "castle"
	if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.TOWN):
		return "town"
	if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.VILLAGE):
		return "village"
	if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.ECONOMY):
		return "economy"
	return String(b.name)


static func _invasion_building_defense(base_map: Node, building: Node, fid: String) -> int:
	if building == null:
		return 0
	var is_castle := int(building.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE)
	if is_castle and base_map.has_method("get_building_battle_strength"):
		return int(base_map.get_building_battle_strength(building, fid))
	if base_map.has_method("get_settlement_defense_preview"):
		return int(base_map.get_settlement_defense_preview(building, fid).get("strength", 0))
	return GlobalUnits.fighting_strength(base_map.get_all_building_garrison(building))


## Nearest peripheral garrison, else easier of castle vs town, else nearest remaining.
static func _invasion_pick_next_objective(
	base_map: Node, pid: int, fid: String, prov: Node
) -> Dictionary:
	var objs: Array = _invasion_list_objectives(base_map, pid, fid, prov)
	if objs.is_empty():
		return {}
	# Refresh defense with current siege level for castles.
	for o in objs:
		if str(o.get("kind")) == "building" and o.get("building") != null:
			o["defense"] = _invasion_building_defense(base_map, o["building"], fid)

	var d_castle := 0x7FFFFFFF
	var d_town := 0x7FFFFFFF
	var castle_obj = null
	var town_obj = null
	for o in objs:
		var d := _invasion_dist_to_objective(base_map, fid, o)
		o["dist"] = d
		if bool(o.get("is_castle", false)):
			d_castle = mini(d_castle, d)
			castle_obj = o
		if bool(o.get("is_town", false)):
			d_town = mini(d_town, d)
			town_obj = o

	var gate := mini(d_castle, d_town)
	var peripherals: Array = []
	for o in objs:
		if bool(o.get("is_castle", false)) or bool(o.get("is_town", false)):
			continue
		if int(o.get("dist", 0x7FFFFFFF)) < gate:
			peripherals.append(o)
	if not peripherals.is_empty():
		return _invasion_nearest_objective(peripherals)

	# No closer peripherals — pick easier of castle vs town if both present.
	if castle_obj != null and town_obj != null:
		if int(castle_obj.get("defense", 0)) <= int(town_obj.get("defense", 0)):
			return castle_obj
		return town_obj
	if castle_obj != null:
		return castle_obj
	if town_obj != null:
		return town_obj
	return _invasion_nearest_objective(objs)


static func _invasion_nearest_objective(objs: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 0x7FFFFFFF
	for o in objs:
		var d := int(o.get("dist", 0x7FFFFFFF))
		if d < best_d:
			best_d = d
			best = o
	return best


static func _invasion_dist_to_objective(base_map: Node, fid: String, obj: Dictionary) -> int:
	if str(obj.get("kind")) == "army":
		return _invasion_path_mp_to_force(base_map, fid, str(obj.get("id", "")))
	var b = obj.get("building")
	if b == null and base_map.has_method("_building_from_key"):
		b = base_map._building_from_key(str(obj.get("id", "")))
	return _invasion_path_mp_to_building(base_map, fid, b)


static func _invasion_path_mp_to_building(base_map: Node, fid: String, building: Node) -> int:
	var pf = base_map.get("pathfinding")
	var fig = base_map.armies.get_node_or_null(fid) if base_map.get("armies") != null else null
	if pf == null or fig == null or building == null:
		return 0x7FFFFFFF
	if _force_adjacent_to_building(base_map, fid, building):
		return 0
	var from_cell: Vector2i = pf.get_army_cell(fig)
	var approach: Array[Vector2i] = pf.get_approach_cells(building) if pf.has_method("get_approach_cells") else []
	if approach.is_empty():
		return 0x7FFFFFFF
	var path: Array[Vector2i] = pf.find_path_for_mover(fig, from_cell, approach)
	if path.size() < 2:
		return 0x7FFFFFFF
	if pf.has_method("path_mp_cost"):
		return int(pf.path_mp_cost(path, fig))
	return path.size() - 1


static func _invasion_path_mp_to_force(base_map: Node, fid: String, other_id: String) -> int:
	var pf = base_map.get("pathfinding")
	var fig = base_map.armies.get_node_or_null(fid) if base_map.get("armies") != null else null
	var other = base_map.armies.get_node_or_null(other_id) if base_map.get("armies") != null else null
	if pf == null or fig == null or other == null:
		return 0x7FFFFFFF
	if _forces_same_or_adjacent_cell(base_map, fid, other_id):
		return 0
	var from_cell: Vector2i = pf.get_army_cell(fig)
	var to_cell: Vector2i = pf.get_army_cell(other)
	var goals: Array[Vector2i] = [to_cell]
	# Adjacent cells to enemy also count as contact goals.
	var dirs: Array = pf.EDGE_DIRS if pf.get("EDGE_DIRS") != null else [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for dir_variant in dirs:
		goals.append(to_cell + dir_variant)
	var path: Array[Vector2i] = pf.find_path_for_mover(fig, from_cell, goals)
	if path.size() < 2:
		return 0x7FFFFFFF
	if pf.has_method("path_mp_cost"):
		return int(pf.path_mp_cost(path, fig))
	return path.size() - 1


static func _invasion_objective_in_contact(base_map: Node, fid: String, obj: Dictionary) -> bool:
	if str(obj.get("kind")) == "army":
		return _forces_same_or_adjacent_cell(base_map, fid, str(obj.get("id", "")))
	var b = obj.get("building")
	if b == null and base_map.has_method("_building_from_key"):
		b = base_map._building_from_key(str(obj.get("id", "")))
	return _force_adjacent_to_building(base_map, fid, b)


static func _invasion_move_to_objective(base_map: Node, fid: String, obj: Dictionary) -> void:
	if str(obj.get("kind")) == "army":
		_move_force_toward_force(base_map, fid, str(obj.get("id", "")))
		return
	var b = obj.get("building")
	if b == null and base_map.has_method("_building_from_key"):
		b = base_map._building_from_key(str(obj.get("id", "")))
	_move_force_toward_building(base_map, fid, b)


static func _invasion_move_toward_home(
	base_map: Node, pid: int, fid: String, holdings: Array, prefer: Node
) -> void:
	if fid == "" or not base_map.forces.has(fid):
		return
	var best_town = null
	var best_d := 0x7FFFFFFF
	var candidates: Array = []
	if prefer != null:
		candidates.append(prefer)
	for h in holdings:
		if h != null and h not in candidates:
			candidates.append(h)
	for prov in candidates:
		if prov == null or not prov.has_method("has_dejure") or not prov.has_dejure(pid):
			continue
		var town = prov.get_town() if prov.has_method("get_town") else null
		if town == null:
			continue
		var d := _invasion_path_mp_to_building(base_map, fid, town)
		if d < best_d:
			best_d = d
			best_town = town
	if best_town != null:
		_move_force_toward_building(base_map, fid, best_town)


static func _invasion_engage_objective(
	base_map: Node, pid: int, fid: String, obj: Dictionary, war: Dictionary
) -> void:
	if str(obj.get("kind")) == "army":
		var enemy_id := str(obj.get("id", ""))
		if enemy_id == "" or not base_map.forces.has(enemy_id):
			war["halt_reason"] = "enemy army gone"
			return
		war["halt_reason"] = "field battle vs %s" % enemy_id
		if base_map.has_method("request_battle_attack"):
			base_map.request_battle_attack(fid, enemy_id, "")
		return

	var b = obj.get("building")
	if b == null and base_map.has_method("_building_from_key"):
		b = base_map._building_from_key(str(obj.get("id", "")))
	if b == null:
		war["halt_reason"] = "objective building gone"
		return

	var is_castle := int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE)
	var men := GlobalUnits.fighting_men(base_map.get_all_building_garrison(b))
	if is_castle and men > 0:
		# Siege until projected fight ≥ 1.0× with current engines, then assault.
		# Assault requires engines ≥ SIEGE_ASSAULT_MIN_LEVEL (no same-season take).
		if base_map.has_method("is_force_sieging_building") \
				and not base_map.is_force_sieging_building(fid, b):
			if base_map.has_method("apply_start_siege") and base_map.has_method("_building_key"):
				base_map.apply_start_siege(fid, str(base_map._building_key(b)))
				war["halt_reason"] = "started siege"
				return
		var lvl := 0
		if base_map.has_method("get_force_siege_level_vs"):
			lvl = int(base_map.get_force_siege_level_vs(fid, b))
		if lvl < GlobalUnits.SIEGE_ASSAULT_MIN_LEVEL:
			war["halt_reason"] = "sieging castle engines=%d (need %d)" % [
				lvl, GlobalUnits.SIEGE_ASSAULT_MIN_LEVEL
			]
			return
		var def_str := _invasion_building_defense(base_map, b, fid)
		var my_str := _force_strength(base_map, fid)
		var need := maxi(1, int(ceil(float(def_str) * INVASION_FIELD_RATIO)))
		if my_str < need:
			war["halt_reason"] = "sieging castle engines=%d str %d < %d" % [lvl, my_str, need]
			return
		war["halt_reason"] = "assaulting castle"
		_try_invasion_assault_building(base_map, pid, fid, b, war)
		return

	war["halt_reason"] = "assaulting %s" % _invasion_building_label(b)
	_try_invasion_assault_building(base_map, pid, fid, b, war)


## Owned castle (prefer) or town in province that can hold waiting troops.
static func _invasion_wait_park_slot(base_map: Node, pid: int, prov: Node) -> Dictionary:
	if prov == null:
		return {}
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle != null and castle.get("player_owner") != null and int(castle.player_owner) == pid:
		if castle.has_method("is_operational") and castle.is_operational():
			if _garrison_room(base_map, castle, GlobalUnits.SPOT.INSIDE) > 0:
				return {"b": castle, "spot": GlobalUnits.SPOT.INSIDE}
			if _garrison_room(base_map, castle, GlobalUnits.SPOT.OUTSIDE) > 0:
				return {"b": castle, "spot": GlobalUnits.SPOT.OUTSIDE}
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null and town.get("player_owner") != null and int(town.player_owner) == pid:
		if _garrison_room(base_map, town, GlobalUnits.SPOT.FLAT) > 0:
			return {"b": town, "spot": GlobalUnits.SPOT.FLAT}
	return {}


static func _invasion_resolve_main_force(
	base_map: Node, pid: int, war: Dictionary, fid: String
) -> String:
	if fid != "" and base_map.forces.has(fid):
		var loc: Dictionary = base_map.forces[fid].get("location", {})
		if str(loc.get("kind", "")) == "cell":
			return fid
	var park_key := str(war.get("park_building_key", ""))
	if park_key != "":
		# Main is garrisoned — no field id until sortie/merge.
		return ""
	var found := _find_invasion_field_army(base_map, pid)
	if found != "":
		war["force_id"] = found
		return found
	return ""


static func _invasion_main_strength(
	base_map: Node, _pid: int, war: Dictionary, fid: String
) -> int:
	var total := 0
	if fid != "" and base_map.forces.has(fid):
		total += _force_strength(base_map, fid)
	var park_key := str(war.get("park_building_key", ""))
	if park_key != "" and base_map.has_method("_building_from_key"):
		var b = base_map._building_from_key(park_key)
		if b != null:
			total += GlobalUnits.fighting_strength(base_map.get_all_building_garrison(b))
	var rfid := str(war.get("reinforce_force_id", ""))
	if rfid != "" and rfid != fid and base_map.forces.has(rfid):
		# Count reinforce only once merged / for wait progress toward need.
		# For "are we strong enough" while waiting, include reinforce in-province.
		if base_map.has_method("province_under_force"):
			var under = base_map.province_under_force(rfid)
			var tid := str(war.get("target_province_id", ""))
			var tprov = base_map._get_province_by_id(tid) if base_map.has_method("_get_province_by_id") else null
			if under != null and under == tprov:
				total += _force_strength(base_map, rfid)
	return total


## Move into park building if adjacent and room holds; else march toward park.
static func _invasion_park_main_for_wait(
	base_map: Node, pid: int, war: Dictionary, fid: String, park_slot: Dictionary
) -> void:
	var b = park_slot.get("b")
	if b == null:
		return
	var spot := int(park_slot.get("spot", GlobalUnits.SPOT.FLAT))
	var bkey := str(base_map._building_key(b)) if base_map.has_method("_building_key") else ""
	if fid == "" or not base_map.forces.has(fid):
		if bkey != "":
			war["park_building_key"] = bkey
		return
	if not _force_adjacent_to_building(base_map, fid, b):
		_move_force_toward_building(base_map, fid, b)
		return
	var men := GlobalUnits.total_men(base_map.forces[fid].get("units", []))
	var room := _garrison_room(base_map, b, spot)
	if room < men or men <= 0:
		# Stay in field beside park — still "waiting".
		if bkey != "":
			war["park_building_key"] = bkey
		return
	# Ingest into garrison (no MP / adjacency beyond already adjacent).
	var out_units := _extract_any_stacks(base_map.forces[fid].get("units", []), pid, men)
	if out_units.is_empty():
		return
	var dest_gid := _ensure_spot_garrison(base_map, b, spot)
	if dest_gid == "":
		return
	GlobalUnits.subtract_units(base_map.forces[fid]["units"], out_units)
	base_map.forces[dest_gid]["units"] = GlobalUnits.merge_units(
		base_map.forces[dest_gid].get("units", []),
		GlobalUnits.units_from_spec(out_units)
	)
	if base_map.has_method("_flush_cargo_if_force_empty"):
		base_map._flush_cargo_if_force_empty(fid, dest_gid)
	if base_map.has_method("_cleanup_force_if_empty"):
		base_map._cleanup_force_if_empty(fid)
	if base_map.get("pathfinding") != null and base_map.pathfinding.has_method("rebuild_occupancy"):
		base_map.pathfinding.rebuild_occupancy()
	if base_map.has_method("update_all_army_visuals"):
		base_map.update_all_army_visuals()
	if base_map.has_method("refresh_building_flags") and bkey != "":
		base_map.refresh_building_flags(bkey)
	war["park_building_key"] = bkey
	war["force_id"] = ""


## Raise reinforce at staging to cover shortfall; march to merge with parked/main.
static func _invasion_tick_wait_reinforce(
	base_map: Node,
	pid: int,
	war: Dictionary,
	staging: Node,
	need_field: int,
	enemy_town: Node,
	park_slot: Dictionary
) -> void:
	var fid := str(war.get("force_id", ""))
	var main_str := 0
	if fid != "" and base_map.forces.has(fid):
		main_str = _force_strength(base_map, fid)
	var park_key := str(war.get("park_building_key", ""))
	if park_key != "" and base_map.has_method("_building_from_key"):
		var pb = base_map._building_from_key(park_key)
		if pb != null:
			main_str = maxi(main_str, GlobalUnits.fighting_strength(base_map.get_all_building_garrison(pb)))
			# Prefer garrison strength alone when parked (field empty).
			if fid == "" or not base_map.forces.has(fid):
				main_str = GlobalUnits.fighting_strength(base_map.get_all_building_garrison(pb))

	var short_str := maxi(0, need_field - main_str)

	var rfid := str(war.get("reinforce_force_id", ""))
	if rfid != "" and not base_map.forces.has(rfid):
		rfid = ""
		war["reinforce_force_id"] = ""

	if short_str > 0 and staging != null:
		# Raise a separate reinforce stack (never levy into the parked main from staging).
		if rfid == "":
			rfid = _invasion_reinforce_force(base_map, staging, pid, "", short_str)
		else:
			rfid = _invasion_reinforce_force(base_map, staging, pid, rfid, short_str)
		war["reinforce_force_id"] = rfid
		if rfid != "" and base_map.forces.has(rfid):
			_try_buy_war_grain(base_map, staging, pid, enemy_town, rfid)
			_load_war_grain_partial(base_map, pid, staging, rfid, enemy_town)

	if rfid == "" or not base_map.forces.has(rfid):
		return

	var park_b = park_slot.get("b")
	if park_b == null and park_key != "" and base_map.has_method("_building_from_key"):
		park_b = base_map._building_from_key(park_key)

	# March reinforce to park / main.
	if fid != "" and base_map.forces.has(fid):
		_move_force_toward_force(base_map, rfid, fid)
		if _forces_same_or_adjacent_cell(base_map, fid, rfid):
			fid = _absorb_field_force_into(base_map, fid, rfid)
			war["force_id"] = fid
			war["reinforce_force_id"] = ""
			war["park_building_key"] = ""
		return

	# Main is garrisoned — march to park building and pull garrison into reinforce.
	if park_b != null:
		if not _force_adjacent_to_building(base_map, rfid, park_b):
			_move_force_toward_building(base_map, rfid, park_b)
			return
		_invasion_pull_park_into_force(base_map, pid, war, rfid, park_slot)
		war["force_id"] = rfid if base_map.forces.has(rfid) else ""
		war["reinforce_force_id"] = ""
		war["park_building_key"] = ""


static func _invasion_pull_park_into_force(
	base_map: Node, pid: int, _war: Dictionary, dest_fid: String, park_slot: Dictionary
) -> void:
	var b = park_slot.get("b")
	if b == null or dest_fid == "" or not base_map.forces.has(dest_fid):
		return
	var spot := int(park_slot.get("spot", GlobalUnits.SPOT.FLAT))
	var spots: Array = [spot]
	if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE):
		spots = [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]
	for sp in spots:
		var gid := _ensure_spot_garrison(base_map, b, int(sp))
		if gid == "" or not base_map.forces.has(gid):
			continue
		var have := GlobalUnits.total_men(base_map.forces[gid].get("units", []))
		if have <= 0:
			continue
		var out_units := _extract_any_stacks(base_map.forces[gid].get("units", []), pid, have)
		if out_units.is_empty():
			continue
		if base_map.has_method("apply_transfer_units"):
			base_map.apply_transfer_units(gid, dest_fid, out_units, {})
		else:
			GlobalUnits.subtract_units(base_map.forces[gid]["units"], out_units)
			base_map.forces[dest_fid]["units"] = GlobalUnits.merge_units(
				base_map.forces[dest_fid].get("units", []),
				GlobalUnits.units_from_spec(out_units)
			)
	if base_map.has_method("_building_key") and base_map.has_method("refresh_building_flags"):
		base_map.refresh_building_flags(str(base_map._building_key(b)))
	if base_map.has_method("update_all_army_visuals"):
		base_map.update_all_army_visuals()


static func _invasion_sortie_parked(base_map: Node, pid: int, war: Dictionary) -> String:
	var park_key := str(war.get("park_building_key", ""))
	if park_key == "" or not base_map.has_method("_building_from_key"):
		return str(war.get("force_id", ""))
	var b = base_map._building_from_key(park_key)
	if b == null:
		war["park_building_key"] = ""
		return ""
	var slot := {"b": b, "spot": GlobalUnits.SPOT.FLAT}
	if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE):
		slot["spot"] = GlobalUnits.SPOT.INSIDE
	# Deploy via existing reinforce raise path: create empty field then pull.
	var near := _find_field_army_near_building(base_map, pid, b)
	if near == "":
		# Use apply_deploy if available — fall back to transferring into a new levy of 0.
		if base_map.has_method("apply_deploy_all_garrison") and base_map.has_method("_building_key"):
			# Prefer manual pull into a new force by spawning at approach cell.
			pass
	if near != "":
		_invasion_pull_park_into_force(base_map, pid, war, near, slot)
		war["park_building_key"] = ""
		war["force_id"] = near
		return near
	# Create a tiny invasion force at staging is wrong — spawn by transferring to new field.
	# Walk approach cell and sortie via apply_sortie if present.
	if base_map.has_method("apply_sortie_units") and base_map.get("pathfinding") != null:
		var pf = base_map.pathfinding
		var approach: Array = pf.get_approach_cells(b) if pf.has_method("get_approach_cells") else []
		if not approach.is_empty():
			var cell: Vector2i = approach[0]
			var spots2: Array = [GlobalUnits.SPOT.FLAT]
			if int(b.get("type_")) == int(GlobalStuff.BUILDING_TYPE.CASTLE):
				spots2 = [GlobalUnits.SPOT.INSIDE, GlobalUnits.SPOT.OUTSIDE]
			var new_id := ""
			for sp in spots2:
				var gid := _ensure_spot_garrison(base_map, b, int(sp))
				if gid == "" or not base_map.forces.has(gid):
					continue
				var units: Array = base_map.forces[gid].get("units", []).duplicate(true)
				if GlobalUnits.total_men(units) <= 0:
					continue
				if base_map.get("_next_runtime_force") != null:
					base_map._next_runtime_force += 1
					new_id = "rt_%d" % int(base_map._next_runtime_force)
				else:
					new_id = "rt_ai_%d_%d" % [pid, Time.get_ticks_msec()]
				base_map.apply_sortie_units(gid, new_id, units, cell.x, cell.y, {})
				break
			if new_id != "" and base_map.forces.has(new_id):
				war["park_building_key"] = ""
				war["force_id"] = new_id
				return new_id
	return ""


## Assault / capture any building; war clears only when province is secured (checked next tick).
static func _try_invasion_assault_building(
	base_map: Node, _pid: int, fid: String, building: Node, war: Dictionary
) -> void:
	var key := str(base_map._building_key(building)) if base_map.has_method("_building_key") else ""
	if key == "":
		return
	var def_men := GlobalUnits.fighting_men(base_map.get_all_building_garrison(building))
	var will_militia := false
	if base_map.has_method("settlement_should_raise_militia"):
		will_militia = bool(base_map.settlement_should_raise_militia(building, fid))
	var fought := false
	if def_men > 0 or will_militia:
		fought = true
		if base_map.has_method("request_battle_attack"):
			base_map.request_battle_attack(fid, "", key)
		def_men = GlobalUnits.fighting_men(base_map.get_all_building_garrison(building))
		will_militia = false
		if base_map.has_method("settlement_should_raise_militia"):
			will_militia = bool(base_map.settlement_should_raise_militia(building, fid))
	if def_men > 0 or will_militia:
		war["halt_reason"] = "battle unresolved at %s" % _invasion_building_label(building)
		return
	if not base_map.forces.has(fid):
		return
	# Post-battle capture is free; otherwise need normal capture MP.
	if not fought:
		if not base_map.has_method("force_has_movement") or not base_map.force_has_movement(fid, 2):
			war["halt_reason"] = "no MP to capture"
			return
	if base_map.has_method("request_capture_building"):
		base_map.request_capture_building(fid, key, fought)
	war["halt_reason"] = "captured %s" % _invasion_building_label(building)
	war["force_id"] = fid if base_map.forces.has(fid) else ""


## Levy mixed conquest troops into `fid` toward `need_str` fighting strength.
## Prefer sortying surplus castle/town garrison first (pop/levy caps are often already
## spent filling those garrisons). Then arm-first field levy; peasants last.
static func _invasion_reinforce_force(
	base_map: Node, prov: Node, pid: int, fid: String, need_str: int
) -> String:
	if prov == null:
		return fid

	# 1) Mobilize men already paid for — sitting in the castle/town.
	fid = _invasion_pull_garrison_drip(base_map, prov, pid, fid, need_str)
	var have_str := _force_strength(base_map, fid) if fid != "" and base_map.forces.has(fid) else 0
	var short_str := maxi(0, need_str - have_str)
	if short_str <= 0:
		return fid if fid != "" else _find_invasion_field_army(base_map, pid)

	var want: Array = _conquest_remaining_levy(base_map, fid, pid, need_str)
	if want.is_empty():
		# Count mix already filled but strength still short — raise pure armed top-up.
		want = _conquest_composition_for_strength(short_str)
		want = _composition_without_peasants(want)
	if want.is_empty():
		return fid

	# Arms first: ignore peasants until the armed share of the target mix is filled.
	var armed_want: Array = _composition_without_peasants(want)
	var peasant_want: Array = _composition_only_peasants(want)
	if not armed_want.is_empty():
		want = armed_want
	elif not peasant_want.is_empty():
		want = peasant_want
	else:
		return fid

	var want_men := GlobalUnits.composition_total_men(want)
	var raise := mini(want_men, INVASION_LEVY_DRIP)
	raise = _clamp_levy_men(base_map, prov, pid, raise, false)
	if raise < GlobalUnits.MIN_SPLIT_MEN:
		if fid != "":
			return fid
		return ""
	want = CouncilAI._trim_composition(want, raise)
	if GlobalUnits.composition_total_men(want) < GlobalUnits.MIN_SPLIT_MEN:
		return fid

	var is_peasant_drip := (
		GlobalUnits.composition_total_men(_composition_without_peasants(want)) <= 0
	)
	if not is_peasant_drip:
		_conquest_prep_weapons(base_map, prov, pid, want)
		var levy_comp: Array = CouncilAI._trim_to_weapons(prov, pid, want)
		# Ideal mix may be bow/pike starved while swords/maces sit unused — fill from stock.
		if GlobalUnits.composition_total_men(levy_comp) < GlobalUnits.MIN_SPLIT_MEN:
			levy_comp = _conquest_arm_from_stock(prov, pid, raise)
		if GlobalUnits.composition_total_men(levy_comp) < GlobalUnits.MIN_SPLIT_MEN:
			return fid
		levy_comp = CouncilAI._trim_composition(levy_comp, raise)
		if GlobalUnits.composition_total_men(levy_comp) < GlobalUnits.MIN_SPLIT_MEN:
			return fid
		return _invasion_absorb_levy(base_map, prov, pid, fid, levy_comp)

	# Armed mix done — drip peasants last.
	return _invasion_absorb_levy(base_map, prov, pid, fid, want)


## Pull surplus castle (then town) into `fid`, leaving a home reserve.
## Caps at INVASION_LEVY_DRIP unless `need_str` is huge (dump-all from `_invasion_dump_garrison_to_field`).
static func _invasion_pull_garrison_drip(
	base_map: Node, prov: Node, pid: int, fid: String, need_str: int
) -> String:
	if base_map == null or prov == null:
		return fid
	var have_str := _force_strength(base_map, fid) if fid != "" and base_map.forces.has(fid) else 0
	var short_str := maxi(0, need_str - have_str)
	if short_str <= 0:
		return fid
	var dump_all := need_str >= 999999
	var want_men := 999999 if dump_all else mini(INVASION_LEVY_DRIP, _conquest_men_for_strength(short_str))
	if not dump_all:
		want_men = maxi(want_men, GlobalUnits.MIN_SPLIT_MEN)

	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		var total := GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
		var can_take := maxi(0, total - DEFENSE_WAR_CASTLE_RESERVE)
		var take_n := mini(want_men, can_take)
		if take_n >= GlobalUnits.MIN_SPLIT_MEN:
			# Prefer non-archers first so the reserve stays archer-heavy (same as home defense).
			for spot in [GlobalUnits.SPOT.OUTSIDE, GlobalUnits.SPOT.INSIDE]:
				if take_n < GlobalUnits.MIN_SPLIT_MEN and (
					fid == "" or not base_map.forces.has(fid)
				):
					break
				if take_n <= 0:
					break
				var still := GlobalUnits.fighting_men(base_map.get_all_building_garrison(castle))
				var room_leave := maxi(0, still - DEFENSE_WAR_CASTLE_RESERVE)
				var n := mini(take_n, room_leave)
				if n <= 0:
					continue
				var gid := _ensure_spot_garrison(base_map, castle, spot)
				if gid == "" or not base_map.forces.has(gid):
					continue
				var out_units := _home_extract_non_archers_first(
					base_map.forces[gid].get("units", []), pid, n
				)
				if out_units.is_empty():
					continue
				var took := GlobalUnits.total_men(out_units)
				if took < GlobalUnits.MIN_SPLIT_MEN and (fid == "" or not base_map.forces.has(fid)):
					# Can't spawn a legal field stack yet — leave them for next spot/season.
					continue
				if fid == "" or not base_map.forces.has(fid):
					fid = _home_spawn_field_from_garrison(
						base_map, pid, castle, spot, gid, out_units
					)
				else:
					GlobalUnits.subtract_units(base_map.forces[gid]["units"], out_units)
					base_map.forces[fid]["units"] = GlobalUnits.merge_units(
						base_map.forces[fid].get("units", []),
						GlobalUnits.units_from_spec(out_units)
					)
					if base_map.has_method("_cleanup_force_if_empty"):
						base_map._cleanup_force_if_empty(gid)
				if fid != "" and base_map.forces.has(fid):
					take_n -= took
			if base_map.has_method("_building_key") and base_map.has_method("refresh_building_flags"):
				base_map.refresh_building_flags(str(base_map._building_key(castle)))
			if base_map.has_method("update_all_army_visuals"):
				base_map.update_all_army_visuals()
			if base_map.get("pathfinding") != null and base_map.pathfinding.has_method("rebuild_occupancy"):
				base_map.pathfinding.rebuild_occupancy()

	have_str = _force_strength(base_map, fid) if fid != "" and base_map.forces.has(fid) else 0
	if have_str >= need_str:
		return fid if fid != "" else ""

	# Town excess above council kit (if any).
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		var still_need := maxi(0, need_str - have_str)
		var still_men := mini(INVASION_LEVY_DRIP, _conquest_men_for_strength(still_need))
		if still_men >= GlobalUnits.MIN_SPLIT_MEN or (fid != "" and base_map.forces.has(fid)):
			fid = _sortie_building_owned(
				base_map, prov, pid, town, GlobalUnits.SPOT.FLAT, fid, true, still_men
			)
	return fid if fid != "" and base_map.forces.has(fid) else ""


## Arm up to `raise` men from whatever weapons are in stock (mix preference order).
static func _conquest_arm_from_stock(prov: Node, pid: int, raise: int) -> Array:
	raise = maxi(0, raise)
	if raise <= 0 or prov == null or not prov.has_method("get_weapons_for"):
		return []
	var stock: Dictionary = prov.get_weapons_for(pid).duplicate()
	var order: Array = [
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.SWORDSMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
	]
	var out: Array = []
	var left := raise
	for t in order:
		if left <= 0:
			break
		var recipe: Dictionary = GlobalUnits.UNIT_WEAPON_COST.get(t, {})
		var can := left
		for wkey in recipe:
			var need_each := int(recipe[wkey])
			if need_each <= 0:
				continue
			can = mini(can, int(floor(float(int(stock.get(wkey, 0))) / float(need_each))))
		if can <= 0:
			continue
		out.append({"type": t, "count": can})
		left -= can
		for wkey in recipe:
			var need_each := int(recipe[wkey])
			if need_each > 0:
				stock[wkey] = int(stock.get(wkey, 0)) - need_each * can
	return out


static func _invasion_absorb_levy(
	base_map: Node, prov: Node, pid: int, fid: String, levy_comp: Array
) -> String:
	var new_id := _levy_composition_field(base_map, prov, pid, levy_comp)
	if new_id == "":
		return fid
	if fid == "" or not base_map.forces.has(fid):
		return new_id
	if new_id == fid:
		return fid
	return _absorb_field_force_into(base_map, fid, new_id)


## Remaining men by type vs full conquest mix for `need_str` (have already in `fid`).
static func _conquest_remaining_levy(
	base_map: Node, fid: String, pid: int, need_str: int
) -> Array:
	var target_men := _conquest_men_for_strength(need_str)
	var target: Array = _conquest_composition_for_men(target_men)
	var have: Dictionary = _force_fighting_type_counts(base_map, fid, pid)
	var out: Array = []
	for e in target:
		var t := int(e.get("type", -1))
		var short := maxi(0, int(e.get("count", 0)) - int(have.get(t, 0)))
		if short > 0:
			out.append({"type": t, "count": short})
	return out


static func _force_fighting_type_counts(base_map: Node, fid: String, pid: int) -> Dictionary:
	var out := {}
	if base_map == null or fid == "" or not base_map.forces.has(fid):
		return out
	for s in base_map.forces[fid].get("units", []):
		if int(s.get("owner", -1)) != pid:
			continue
		if not GlobalUnits.is_fighting_stack(s):
			continue
		var t := int(s.get("type", -1))
		out[t] = int(out.get(t, 0)) + int(s.get("count", 0))
	return out


static func _composition_without_peasants(composition: Array) -> Array:
	var out: Array = []
	for e in composition:
		if int(e.get("type", -1)) == GlobalUnits.UNIT_TYPE.PEASANT:
			continue
		var n := int(e.get("count", 0))
		if n > 0:
			out.append({"type": int(e.get("type")), "count": n})
	return out


static func _composition_only_peasants(composition: Array) -> Array:
	var n := 0
	for e in composition:
		if int(e.get("type", -1)) == GlobalUnits.UNIT_TYPE.PEASANT:
			n += int(e.get("count", 0))
	if n <= 0:
		return []
	return [{"type": GlobalUnits.UNIT_TYPE.PEASANT, "count": n}]


## Legacy name — town capture used by older callers.
static func _try_invasion_assault_and_capture(
	base_map: Node, pid: int, fid: String, town: Node, war: Dictionary
) -> void:
	_try_invasion_assault_building(base_map, pid, fid, town, war)


## Caravan bows/swords/pikes/maces from surplus holdings into incomplete ones.
static func _invasion_caravan_supply_arms(base_map: Node, pid: int, holdings: Array) -> void:
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
		for k in ["bows", "swords", "pikes", "maces"]:
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
			# Don't route supply wagons through hostile / unowned land.
			if not _conquest_path_is_friendly_corridor(base_map, pid, src, dest):
				continue
			# Skip if a caravan already going to dest from this owner.
			if _has_caravan_to(base_map, pid, String(dest.name)):
				break
			var src_stock: Dictionary = src.get_weapons_for(pid) if src.has_method("get_weapons_for") else {}
			var cargo := GlobalUnits.empty_caravan_cargo()
			var sent := false
			for k in ["bows", "swords", "pikes", "maces"]:
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
	var out := {"bows": 0, "swords": 0, "pikes": 0, "maces": 0}
	for slot in _defense_active_slots_for_pid(prov, pid):
		var prio := str(slot.get("prio", "town"))
		var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
		var mix: Dictionary = _defense_mix_counts(cap, prio)
		var have: Dictionary = _spot_fighting_counts(base_map, slot["b"], int(slot["spot"]), pid)
		out["bows"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)))
		out["swords"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)))
		out["pikes"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)))
		out["maces"] += maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)))
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


## Defense: highest ration ≤ Quad sustainable for year+buffer; tax paired for ~100 happiness.
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
		var season_budget := _defense_people_season_budget(people_budget)
		ration = GlobalUnits.affordable_ration(pop, GlobalUnits.RATION.QUADRUPLE, season_budget)
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


## True while this holding is actively stocking wood/stone for the next castle step
## (not suppressed by Medium-econ wait or active invasion arming).
static func _defense_stocking_castle_mats(
	base_map: Node, prov: Node, pid: int, castle: Node, arming_invasion: bool
) -> bool:
	if arming_invasion or castle == null or not castle.has_method("standing_level"):
		return false
	var standing := int(castle.standing_level())
	if standing >= DEFENSE_CONQUEST_MIN_CASTLE and not _province_econ_ready_for_conquest(prov, pid):
		return false
	return true


## Any secure holding currently stocking stone for a castle climb.
static func _lord_waiting_for_castle_stone(base_map: Node, pid: int) -> bool:
	for h in _provinces_for_lord(base_map, pid):
		if h == null or not _invasion_province_full_control(h, pid):
			continue
		var c = h.get_castle_plot() if h.has_method("get_castle_plot") else null
		if not _defense_stocking_castle_mats(
			base_map, h, pid, c, _invasion_arming_for_conquest(base_map, pid)
		):
			continue
		var next_c := _defense_next_castle_level(c)
		var short: Dictionary = _defense_castle_mat_shortfall(h, pid, c, next_c)
		if int(short.get("stone", 0)) > 0:
			return true
	return false


## Dump wood/iron/stone above keep floors when a merchant is in the province.
## Wood: keep all while this province is waiting on castle wood.
## Stone: sell none if any holding is waiting on castle stone; else keep 500.
static func _try_sell_surplus_mats(
	base_map: Node,
	prov: Node,
	pid: int,
	castle: Node,
	next_castle: int,
	arming_invasion: bool
) -> void:
	if base_map == null or prov == null or pid < 0:
		return
	if not base_map.has_method("apply_sell_to_merchant"):
		return
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	if not prov.has_method("get_player_material"):
		return

	var stocking := _defense_stocking_castle_mats(base_map, prov, pid, castle, arming_invasion)
	var short: Dictionary = {"wood": 0, "stone": 0}
	if stocking:
		short = _defense_castle_mat_shortfall(prov, pid, castle, next_castle)

	var mats := GlobalUnits.empty_material_stock()
	var have_wood := int(prov.get_player_material(pid, "wood"))
	var have_iron := int(prov.get_player_material(pid, "iron"))
	var have_stone := int(prov.get_player_material(pid, "stone"))

	# Wood: floor 1500, but sell nothing while waiting for castle wood.
	if int(short.get("wood", 0)) <= 0:
		mats["wood"] = maxi(0, have_wood - DEFENSE_SELL_KEEP_WOOD)
	# Iron: always dump above floor.
	mats["iron"] = maxi(0, have_iron - DEFENSE_SELL_KEEP_IRON)
	# Stone: hold everything if any province needs castle stone; else floor 500.
	if not _lord_waiting_for_castle_stone(base_map, pid):
		mats["stone"] = maxi(0, have_stone - DEFENSE_SELL_KEEP_STONE)

	var any := false
	for k in ["wood", "iron", "stone"]:
		if int(mats.get(k, 0)) > 0:
			any = true
			break
	if not any:
		return

	var competition := bool(base_map.merchant_competition_in_province(prov)) \
			if base_map.has_method("merchant_competition_in_province") else false
	var payout := 0
	if base_map.has_method("_merchant_cart_total_sell"):
		payout = int(base_map._merchant_cart_total_sell(
			GlobalUnits.empty_weapon_stock(), mats, competition
		))
	else:
		for k in ["wood", "iron", "stone"]:
			var amt := int(mats.get(k, 0))
			if amt > 0:
				payout += GlobalUnits.material_mark_sell_price(k, competition) * amt
	if payout <= 0:
		return

	base_map.apply_sell_to_merchant(
		String(merchant.name),
		GlobalUnits.empty_weapon_stock(),
		mats,
		pid,
		payout
	)
	var province_id := String(prov.name)
	for k in ["wood", "iron", "stone"]:
		var sold := int(mats.get(k, 0))
		if sold > 0:
			_record_debug_buy(base_map, pid, province_id, "sell_%s" % k, sold)


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
## No mine → stock up to DEFENSE_IRON_BUY_FLOOR_NO_MINE for smithing.
static func _try_buy_defense_iron(
	base_map: Node, prov: Node, pid: int, castle_short: Dictionary
) -> void:
	var have := int(prov.get_player_material(pid, "iron")) if prov.has_method("get_player_material") else 0
	var iron_cap := int(prov.economy_worker_cap(pid, "iron")) if prov.has_method("economy_worker_cap") else 0
	var floor_n := DEFENSE_IRON_BUY_FLOOR_NO_MINE if iron_cap <= 0 else DEFENSE_IRON_BUY_FLOOR
	if have >= floor_n:
		return
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
	var want := floor_n - have
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


## Buy iron needed to craft the weapons shortfall in `want_comp` (no-mine / low stock).
static func _try_buy_iron_for_composition(
	base_map: Node, prov: Node, pid: int, want_comp: Array
) -> void:
	if prov == null or want_comp.is_empty():
		return
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var need_w: Dictionary = GlobalUnits.weapons_needed_for_composition(want_comp)
	var iron_need := 0
	for wkey in need_w:
		var short := maxi(0, int(need_w.get(wkey, 0)) - int(stock.get(wkey, 0)))
		if short <= 0:
			continue
		var recipe: Dictionary = GlobalUnits.blacksmith_recipe(str(wkey))
		iron_need += int(recipe.get("iron", 0)) * short
	var have := int(prov.get_player_material(pid, "iron")) if prov.has_method("get_player_material") else 0
	var buy_n := maxi(0, iron_need - have)
	if buy_n <= 0:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var spendable := _marks_spendable(base_map, pid)
	var unit_p := maxi(1, GlobalUnits.material_mark_price_discounted("iron", competition))
	var can := mini(buy_n, int(floor(float(spendable) / float(unit_p))))
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


## Buy bows/swords/pikes/maces for garrison holes when craft can't keep up.
static func _try_buy_defense_weapons(base_map: Node, prov: Node, pid: int) -> void:
	var merchant = _merchant_in_province(base_map, prov)
	if merchant == null:
		return
	var stock: Dictionary = prov.get_weapons_for(pid) if prov.has_method("get_weapons_for") else {}
	var left := {
		"bows": int(stock.get("bows", 0)),
		"swords": int(stock.get("swords", 0)),
		"pikes": int(stock.get("pikes", 0)),
		"maces": int(stock.get("maces", 0)),
	}
	var castle_need := {"bows": 0, "swords": 0, "pikes": 0, "maces": 0}
	var other_need := {"bows": 0, "swords": 0, "pikes": 0, "maces": 0}
	for slot in _defense_active_slots_for_pid(prov, pid):
		var prio := str(slot.get("prio", "town"))
		var cap := int(slot["b"].get_garrison_capacity(int(slot["spot"]))) if slot["b"].has_method("get_garrison_capacity") else 0
		var mix: Dictionary = _defense_mix_counts(cap, prio)
		var have: Dictionary = _spot_fighting_counts(base_map, slot["b"], int(slot["spot"]), pid)
		var holes := {
			"bows": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.ARCHER, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.ARCHER, 0))),
			"swords": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.SWORDSMEN, 0))),
			"pikes": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.PIKEMEN, 0))),
			"maces": maxi(0, int(mix.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0)) - int(have.get(GlobalUnits.UNIT_TYPE.MACEMEN, 0))),
		}
		var dest: Dictionary = castle_need if prio == "castle" else other_need
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
		"maces": int(castle_need["maces"]),
	}
	# If castle kit is covered, drip-buy for other active slots from remaining stock.
	var castle_left := (
		int(buy_need["bows"]) + int(buy_need["swords"])
		+ int(buy_need["pikes"]) + int(buy_need["maces"])
	)
	if castle_left <= 0:
		for k in left:
			var hole := maxi(0, int(other_need[k]) - int(left[k]))
			buy_need[k] = mini(hole, DEFENSE_DRIP_OTHER)
	if (
		int(buy_need["bows"]) + int(buy_need["swords"])
		+ int(buy_need["pikes"]) + int(buy_need["maces"])
	) <= 0:
		return
	var competition := bool(base_map.merchant_competition_in_province(prov)) if base_map.has_method("merchant_competition_in_province") else false
	var spendable := _marks_spendable(base_map, pid)
	var buy: Dictionary = GlobalUnits.empty_weapon_stock()
	var cost := 0
	for k in ["bows", "swords", "pikes", "maces"]:
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
		for k in ["bows", "swords", "pikes", "maces"]:
			_record_debug_buy(base_map, pid, province_id, k, int(buy.get(k, 0)))


## Buy grain so Quadruple is sustainable for year+buffer (after castle mat reserve).
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
	var season_budget := _defense_people_season_budget(people_budget)
	if GlobalUnits.affordable_ration(pop, GlobalUnits.RATION.QUADRUPLE, season_budget) >= GlobalUnits.RATION.QUADRUPLE:
		return
	var need_for_quad := (
		GlobalUnits.ration_grain_need(pop, GlobalUnits.RATION.QUADRUPLE)
		* DEFENSE_RATION_RUNWAY_SEASONS
	)
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


## Max economy STAGES enum value allowed by castle standing (−1 = none).
static func _defense_econ_max_stage(castle: Node) -> int:
	if castle == null or not castle.has_method("standing_level"):
		return -1
	var standing := int(castle.standing_level())
	if standing < DEFENSE_ECON_MEDIUM_MIN_CASTLE:
		return -1
	# STAGES: SMALL=1, MEDIUM=2, BIG=3
	if standing >= DEFENSE_ECON_BIG_MIN_CASTLE:
		return 3 # BIG
	return 2 # MEDIUM


## Upgrade owned economy buildings toward castle-gated stage cap.
## Priority wood → iron → blacksmith → stone → silver; spend freely above
## castle-mat reserve + army upkeep (via _marks_spendable_defense).
static func _try_upgrade_economy(
	base_map: Node, prov: Node, pid: int, castle: Node, castle_short: Dictionary
) -> void:
	if base_map == null or prov == null or prov.get("economy") == null:
		return
	if not base_map.has_method("apply_upgrade_economy") or not base_map.has_method("_building_key"):
		return
	var max_stage := _defense_econ_max_stage(castle)
	if max_stage < 0:
		return
	var reserve := _defense_castle_marks_reserve(base_map, prov, castle_short)
	# Keep upgrading while we can afford the next pick in priority order.
	for _i in range(16):
		var spendable := _marks_spendable_defense(base_map, pid, reserve)
		if spendable <= 0:
			return
		var picked: Node = null
		var picked_cost := 0
		for subtype in DEFENSE_ECON_UPGRADE_ORDER:
			for b in prov.economy.get_children():
				if b == null or int(b.get("player_owner")) != pid:
					continue
				if not b.has_method("is_built") or not b.is_built():
					continue
				if int(b.get("subtype")) != int(subtype):
					continue
				if not b.has_method("can_upgrade") or not b.can_upgrade():
					continue
				var next_st := int(b.next_stage()) if b.has_method("next_stage") else -1
				if next_st < 0 or next_st > max_stage:
					continue
				var cost := int(b.upgrade_cost()) if b.has_method("upgrade_cost") else 0
				if cost <= 0 or cost > spendable:
					continue
				picked = b
				picked_cost = cost
				break
			if picked != null:
				break
		if picked == null:
			return
		base_map.apply_upgrade_economy(str(base_map._building_key(picked)), pid, picked_cost)


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
## When `prioritize_smith`, fill blacksmith before iron/stone so invasion craft isn't starved.
static func _assign_labor_defense(
	base_map: Node, prov: Node, pid: int, castle: Node, stockpile_castle: bool,
	prioritize_smith: bool = false
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

	var wood_n := 0
	var stone_n := 0
	var iron_n := 0
	var silver_n := 0
	var smith_n := 0

	if prioritize_smith and not stockpile_castle:
		# Invasion raise: smith first, then wood (bows), then iron.
		smith_n = mini(smith_cap, remaining)
		remaining = maxi(0, remaining - smith_n)
		wood_n = mini(wood_cap, remaining)
		remaining = maxi(0, remaining - wood_n)
		iron_n = mini(iron_cap, remaining)
		remaining = maxi(0, remaining - iron_n)
		silver_n = mini(silver_cap, remaining)
		remaining = maxi(0, remaining - silver_n)
		stone_n = mini(stone_cap, remaining)
		remaining = maxi(0, remaining - stone_n)
	else:
		wood_n = mini(wood_cap, remaining)
		remaining = maxi(0, remaining - wood_n)

		if stockpile_castle or stone_cap > 0:
			stone_n = mini(stone_cap, remaining)
			remaining = maxi(0, remaining - stone_n)

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


## True while an invasion target/force is active — arm the field, not the next keep.
static func _invasion_arming_for_conquest(base_map: Node, pid: int) -> bool:
	if base_map == null or pid < 0:
		return false
	var war: Dictionary = _invasion_war_state(base_map, pid)
	if str(war.get("target_province_id", "")) != "":
		return true
	var fid := str(war.get("force_id", ""))
	if fid != "" and base_map.forces.has(fid):
		return true
	return false


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
	# Spend happiness down to DEFENSE_LEVY_HAPPINESS_FLOOR after this season's recovery.
	var affordable_penalty := maxf(0.0, avg_h + recovery - DEFENSE_LEVY_HAPPINESS_FLOOR)
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


static func _province_food_ok(_base_map: Node, prov: Node, pid: int) -> bool:
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
	# Legacy offense helper — councils only.
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


## Adjacent province held by a non-allied council / human / AI (has a town).
static func _is_valid_conquest_target(base_map: Node, pid: int, prov: Node) -> bool:
	if prov == null or not is_instance_valid(prov):
		return false
	var holder_id := int(prov.dejure) if prov.get("dejure") != null else int(prov.get("player_owner"))
	if holder_id < 0 or holder_id == pid or not base_map.players.has(holder_id):
		return false
	var holder = base_map.players[holder_id]
	if holder == null:
		return false
	if int(holder.status) != int(GlobalStuff.PLAYER_STATUS.PLAYING):
		return false
	if base_map.has_method("are_friendly_players") and base_map.are_friendly_players(pid, holder_id):
		return false
	if Diplomacy.conquest_excludes_holder(base_map, pid, holder_id):
		return false
	var town = prov.get_town() if prov.has_method("get_town") else null
	return town != null


## When conquering a diplomable lord at opinion 0 (or already hostile), open formal war.
static func _maybe_declare_war_for_conquest(base_map: Node, pid: int, province_id: String) -> void:
	if province_id == "" or not base_map.has_method("_get_province_by_id"):
		return
	var prov = base_map._get_province_by_id(province_id)
	if prov == null:
		return
	var holder_id := int(prov.dejure) if prov.get("dejure") != null else int(prov.get("player_owner"))
	if not Diplomacy.is_diplomable(base_map, holder_id):
		return
	if Diplomacy.are_at_war(base_map, pid, holder_id):
		return
	var op := Diplomacy.get_opinion(base_map, pid, holder_id)
	# Declare when opinion is 0 and we chose them as a conquest target.
	if op > GameBalance.DIPLO_OPINION_MIN:
		return
	if base_map.has_method("ensure_war_from_hostility"):
		base_map.ensure_war_from_hostility(pid, holder_id)
	elif base_map.has_method("_set_war"):
		base_map._set_war(pid, holder_id, pid)
		if base_map.has_method("_make_diplo_message_event"):
			base_map._make_diplo_message_event(
				Diplomacy.MSG_WAR_DECLARE,
				"%s declares war!" % base_map.player_display_name(pid),
				holder_id,
				pid
			)


## Weakest adjacent enemy province by total garrison + field strength.
## Only if the army-preferred (road MP) town→town path stays on own / ally / target land.
static func _pick_conquest_target(base_map: Node, pid: int, holdings: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_power := 0x7FFFFFFF
	var neighbors_map: Dictionary = base_map.province_neighbors if base_map.get("province_neighbors") != null else {}
	for home in holdings:
		if home == null or not _invasion_province_full_control(home, pid):
			continue
		var nlist: Array = neighbors_map.get(home, [])
		for other in nlist:
			if not _is_valid_conquest_target(base_map, pid, other):
				continue
			if not _conquest_path_is_friendly_corridor(base_map, pid, home, other):
				continue
			var power := _province_military_power(base_map, pid, other)
			if power < best_power or best.is_empty():
				best_power = power
				best = {
					"province_id": String(other.name),
					"staging_id": String(home.name),
					"defense_strength": power,
				}
	return best


## True when the army-preferred path home-town → target-town only crosses own, allied, or target land.
static func _conquest_path_is_friendly_corridor(
	base_map: Node, pid: int, home: Node, target: Node
) -> bool:
	if base_map == null or home == null or target == null or pid < 0:
		return false
	var path: Array = _conquest_town_to_town_path(base_map, home, target)
	if path.is_empty():
		return false
	if not base_map.has_method("find_province_for_cell"):
		return false
	for cell_variant in path:
		var cell: Vector2i = cell_variant
		var prov = base_map.find_province_for_cell(cell)
		if not _conquest_path_province_allowed(base_map, pid, prov, home, target):
			return false
	return true


static func _conquest_path_province_allowed(
	base_map: Node, pid: int, prov: Node, home: Node, target: Node
) -> bool:
	# Non-province tiles (gaps / unpainted) are fine.
	if prov == null:
		return true
	if prov == home or prov == target:
		return true
	if prov.has_method("has_dejure") and prov.has_dejure(pid):
		return true
	var holder_id := int(prov.dejure) if prov.get("dejure") != null else int(prov.get("player_owner"))
	if holder_id == pid:
		return true
	if base_map.has_method("are_friendly_players") and base_map.are_friendly_players(pid, holder_id):
		return true
	return false


## Cheapest army-style (road MP) path between town approach rings.
static func _conquest_town_to_town_path(base_map: Node, home: Node, target: Node) -> Array:
	var out: Array = []
	var pf = base_map.get("pathfinding") if base_map != null else null
	if pf == null or not pf.has_method("get_approach_cells"):
		return out
	if not pf.has_method("find_strategic_land_path"):
		return out
	var home_town = home.get_town() if home.has_method("get_town") else null
	var target_town = target.get_town() if target.has_method("get_town") else null
	if home_town == null or target_town == null:
		return out
	var from_cells: Array[Vector2i] = pf.get_approach_cells(home_town)
	var to_cells: Array[Vector2i] = pf.get_approach_cells(target_town)
	if from_cells.is_empty() or to_cells.is_empty():
		return out
	var best: Array = []
	var best_cost := 0x7FFFFFFF
	# Sample approach starts; each call already picks the cheapest end among to_cells.
	var from_n := mini(from_cells.size(), 12)
	for i in range(from_n):
		var path: Array = pf.find_strategic_land_path(from_cells[i], to_cells)
		if path.is_empty():
			continue
		var cost := int(pf.strategic_land_mp_cost(path)) if pf.has_method("strategic_land_mp_cost") else path.size()
		if cost < best_cost:
			best_cost = cost
			best = path
	return best


static func _province_military_power(base_map: Node, pid: int, prov: Node) -> int:
	var total := 0
	for o in _invasion_list_objectives(base_map, pid, "", prov):
		total += int(o.get("defense", 0))
	# Also count empty-castle garrison already included; add any missed field via list.
	return total


static func _pick_council_target(base_map: Node, pid: int, holdings: Array) -> Dictionary:
	# Invasion conquest uses all valid enemies now.
	return _pick_conquest_target(base_map, pid, holdings)


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
	# Candidate must be strictly weaker than current target (full province power).
	var cur_prov = base_map._get_province_by_id(current) if base_map.has_method("_get_province_by_id") else null
	var cur_str := 0x7FFFFFFF
	if cur_prov != null:
		cur_str = _province_military_power(base_map, pid, cur_prov)
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
	# Use charged upkeep (includes early-AI half-pay) so spendable marks match reality.
	if base_map.has_method("get_player_upkeep_owed"):
		return int(base_map.get_player_upkeep_owed(pid))
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
static func _set_craft_for_war(_base_map: Node, prov: Node, pid: int, want_comp: Array = []) -> void:
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
	base_map: Node, prov: Node, pid: int, want: int, as_garrison: bool,
	ignore_happiness: bool = false
) -> int:
	if want <= 0:
		return 0
	var happy := want if ignore_happiness else _happiness_levy_budget(prov, pid)
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


## Absorb every staging field army except protected war stacks.
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
		if _is_protected_field_force(base_map, pid, other):
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


## Slots used to park stray field troops (owned town/villages; owned castle when operational).
static func _defense_park_slots(prov: Node, pid: int = -1) -> Array:
	var out: Array = []
	if prov == null:
		return out
	var castle = prov.get_castle_plot() if prov.has_method("get_castle_plot") else null
	if castle != null and castle.has_method("is_operational") and castle.is_operational():
		if pid < 0 or (castle.get("player_owner") != null and int(castle.player_owner) == pid):
			out.append({"b": castle, "spot": GlobalUnits.SPOT.INSIDE})
			out.append({"b": castle, "spot": GlobalUnits.SPOT.OUTSIDE})
	var town = prov.get_town() if prov.has_method("get_town") else null
	if town != null:
		if pid < 0 or (town.get("player_owner") != null and int(town.player_owner) == pid):
			out.append({"b": town, "spot": GlobalUnits.SPOT.FLAT})
	if prov.get("settlements") != null:
		for s in prov.settlements.get_children():
			if s == town:
				continue
			if int(s.get("type_")) != int(GlobalStuff.BUILDING_TYPE.VILLAGE):
				continue
			if pid >= 0 and (s.get("player_owner") == null or int(s.player_owner) != pid):
				continue
			out.append({"b": s, "spot": GlobalUnits.SPOT.FLAT})
	return out


## Park a field force into holding garrisons with no adjacency / MP checks.
static func _defense_ingest_field_force(
	base_map: Node, pid: int, prov: Node, fid: String
) -> void:
	if not base_map.forces.has(fid) or prov == null:
		return
	var loc: Dictionary = base_map.forces[fid].get("location", {})
	if str(loc.get("kind", "")) != "cell":
		return
	var targets: Array = _defense_park_slots(prov, pid)
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


static func _ensure_war_force(
	base_map: Node, pid: int, staging: Node, war: Dictionary, _want_comp: Array
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
	# Empty-build / dismantle: castle offline — park into town.
	if targets.is_empty():
		var town_only = prov.get_town() if prov.has_method("get_town") else null
		if town_only != null:
			targets = [{"b": town_only, "spot": GlobalUnits.SPOT.FLAT}]
	if targets.is_empty():
		return

	# Prefer castle approach first so inside/outside actually fill (incl. mid-upgrade).
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
		# 0-MP field stacks can't path — snap onto a free approach tile.
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


## Place a field force on a free approach cell of `building` (for 0-MP parking).
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
		main_fid = _find_invasion_field_army(base_map, pid)
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
	var fought := false
	if def_men > 0 or will_militia:
		fought = true
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
	if not fought:
		if not base_map.has_method("force_has_movement") or not base_map.force_has_movement(fid, 2):
			return
	if base_map.has_method("request_capture_building"):
		base_map.request_capture_building(fid, key, fought)
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
	var marks_now := int(p.game_data.get("marks", 0))
	var up_face := 0
	var up_owed := 0
	if base_map.has_method("get_player_upkeep_preview"):
		up_face = int(base_map.get_player_upkeep_preview(pid).get("total", 0))
	if base_map.has_method("get_player_upkeep_owed"):
		up_owed = int(base_map.get_player_upkeep_owed(pid))
	else:
		up_owed = up_face
	var early := (
		base_map.has_method("player_ai_early_boost_active")
		and bool(base_map.player_ai_early_boost_active(pid))
	)
	if early and up_face != up_owed:
		lines.append(
			"marks=%d  upkeep=%d (cheat real: %d)  early_boost=on"
			% [marks_now, up_face, up_owed]
		)
	else:
		lines.append(
			"marks=%d  upkeep=%d%s"
			% [marks_now, up_face, "  early_boost=on" if early else ""]
		)

	if true:
		# Defense holdings + invasion status (primary AI path).
		out["phase"] = "defense"
		out["goal"] = "Fortify holdings, then invade adjacent councils"
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
			if prov.has_method("admin_stock_lines"):
				for stock_line in prov.admin_stock_lines(pid):
					lines.append("  " + str(stock_line))
			if prov.has_method("admin_building_lines"):
				for build_line in prov.admin_building_lines(pid):
					lines.append("  " + str(build_line))
			if not done:
				if standing < DEFENSE_CONQUEST_MIN_CASTLE:
					blockers.append("%s castle→Norman" % String(prov.name))
				elif not _defense_active_garrisons_full(base_map, prov, pid):
					if castle_room > 0:
						blockers.append("%s castle garrison (+%d)" % [String(prov.name), castle_room])
					elif room_left > 0:
						blockers.append("%s garrison drip (+%d)" % [String(prov.name), room_left])
				elif not _province_econ_ready_for_conquest(prov, pid):
					var econ_bits: Array = []
					if not _econ_owned_at_least_stage(prov, pid, 0, DEFENSE_ECON_CONQUEST_MIN_STAGE):
						econ_bits.append("wood→Med")
					if not _econ_owned_at_least_stage(prov, pid, 5, DEFENSE_ECON_CONQUEST_MIN_STAGE):
						econ_bits.append("smith→Med")
					if _province_has_iron_deposit(prov) \
							and not _econ_owned_at_least_stage(
								prov, pid, DEFENSE_ECON_IRON_SUBTYPE, DEFENSE_ECON_CONQUEST_MIN_STAGE
							) \
							and not _province_arms_ready_for_invasion(prov, pid):
						econ_bits.append("iron→Med")
					if not econ_bits.is_empty():
						blockers.append(
							"%s econ [%s]" % [String(prov.name), ", ".join(PackedStringArray(econ_bits))]
						)
				# Only show castle-mat shortfall when we are actually stocking for a climb.
				var show_mats := true
				if standing >= DEFENSE_CONQUEST_MIN_CASTLE and not _province_econ_ready_for_conquest(prov, pid):
					show_mats = false
				if show_mats and (int(short.get("wood", 0)) > 0 or int(short.get("stone", 0)) > 0):
					blockers.append(
						"%s mats +%dwood +%dstone" % [
							String(prov.name), int(short.get("wood", 0)), int(short.get("stone", 0))
						]
					)
				if standing < DEFENSE_CONQUEST_MIN_CASTLE:
					if castle_room > 0:
						blockers.append("%s castle garrison (+%d)" % [String(prov.name), castle_room])
					elif room_left > 0:
						blockers.append("%s garrison drip (+%d)" % [String(prov.name), room_left])

		var kw: Dictionary = _invasion_war_state(base_map, pid)
		var kfid := str(kw.get("force_id", ""))
		var kmen := 0
		var kstr := 0
		var cargo_g := 0
		if kfid != "" and base_map.forces.has(kfid):
			kmen = _invasion_count_in_force(base_map, kfid, pid)
			kstr = _force_strength(base_map, kfid)
			if base_map.has_method("get_force_cargo"):
				cargo_g = int(base_map.get_force_cargo(kfid).get("grain", 0))
		var halt := str(kw.get("halt_reason", ""))
		var obj_lbl := str(kw.get("objective_id", ""))
		if str(kw.get("objective_kind", "")) != "":
			obj_lbl = "%s:%s" % [str(kw.get("objective_kind")), obj_lbl]
		lines.append(
			"Conquest — ready=%s target=%s staging=%s force=%s men=%d str=%d cargo=%d marching=%s wait_rf=%s park=%s obj=%s"
			% [
				"yes" if all_done else "no",
				str(kw.get("target_province_id", "")),
				str(kw.get("staging_province_id", "")),
				kfid,
				kmen,
				kstr,
				cargo_g,
				"yes" if bool(kw.get("marching", false)) else "no",
				"yes" if bool(kw.get("waiting_reinforce", false)) else "no",
				str(kw.get("park_building_key", "")),
				obj_lbl,
			]
		)
		var rfid_dbg := str(kw.get("reinforce_force_id", ""))
		if rfid_dbg != "":
			lines.append("  reinforce_force=%s" % rfid_dbg)
		if halt != "":
			lines.append("  halt: " + halt)
		if all_done:
			out["phase"] = "invasion"
			if str(kw.get("target_province_id", "")) == "":
				out["blocker"] = "ready — picking council target"
			elif halt != "":
				out["blocker"] = halt
			else:
				out["blocker"] = "invasion → %s" % str(kw.get("target_province_id", ""))
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
