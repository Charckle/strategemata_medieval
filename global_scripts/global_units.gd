extends Node

## Central catalogue + helpers for military units.
##
## A "unit stack" is a plain Dictionary so it survives RPC serialization:
##     {
##       "type": UNIT_TYPE, "owner": <player_id>, "source": SOURCE, "count": int,
##       "status": STATUS (optional, default FIGHTING),
##       "recover_in": int (seasons until status advances),
##       "join_pending": bool (Captured offered join; resolves next season)
##     }
##
## A "force" is an Array of stacks. The same array can mix unit types AND
## owners (a combined army of several players), which is exactly what we want.
## Both mobile armies and building garrisons are represented as forces.

enum UNIT_TYPE { PEASANT, MACEMEN, PIKEMEN, ARCHER, SWORDSMEN, CROSSBOWMEN, KNIGHTS }

# LEVY = raised from the population, SELLSWORD = hired. Same strength for now;
# this flag is where pay/desertion rules will hook in later.
enum SOURCE { LEVY, SELLSWORD }

# Where inside a building a garrison force sits.
# FLAT is the single pool used by non-castle buildings.
enum SPOT { FLAT, INSIDE, OUTSIDE }

# FIGHTING = battle-ready. WOUNDED = recovering (2 seasons → FIGHTING).
# HOSTAGE = taken after battle (2 seasons → CAPTURED). CAPTURED = healed
# prisoners who may be offered to join (or put to the sword).
enum STATUS { FIGHTING, WOUNDED, HOSTAGE, CAPTURED }

const UNIT_STATS := {
	UNIT_TYPE.PEASANT:     {"name": "Peasant",     "strength": 2},
	UNIT_TYPE.MACEMEN:     {"name": "Macemen",     "strength": 8},
	UNIT_TYPE.PIKEMEN:     {"name": "Pikemen",     "strength": 9},
	UNIT_TYPE.ARCHER:      {"name": "Archer",      "strength": 13},
	UNIT_TYPE.SWORDSMEN:   {"name": "Swordsmen",   "strength": 13},
	UNIT_TYPE.CROSSBOWMEN: {"name": "Crossbowmen", "strength": 16},
	UNIT_TYPE.KNIGHTS:     {"name": "Knights",     "strength": 16},
}

# Units stationed INSIDE a castle fight at this multiplier; OUTSIDE units don't.
const CASTLE_INSIDE_BONUS := 3.0
# Outside garrison multiplier used in battle resolution.
const CASTLE_OUTSIDE_BATTLE_BONUS := 1.5

# Minimum men that must remain in both the original and the split-off army.
const MIN_SPLIT_MEN := 20

# Levy recruitment: max fraction of season-start province population.
const LEVY_MAX_FRACTION := 0.80
# First this fraction of season-start pop can be levied with no happiness hit.
const LEVY_HAPPINESS_FREE_FRACTION := 0.10
# Happiness lost per percent levied above the free band (at 80% ≈ −35).
const LEVY_HAPPINESS_PER_PERCENT := 0.5
const WEAPON_SHIP_SEASONS := 2

# Movement: all-knights armies get this multiplier on base MP.
const KNIGHT_ONLY_MP_MULT := 1.5
# Non-fighting share: ≤ free band = no MP penalty; at/above max share = max penalty.
const WOUND_MP_FREE_FRACTION := 0.10
const WOUND_MP_MAX_FRACTION := 0.50
const WOUND_MP_MAX_PENALTY := 0.50

# Weapon stockpile keys (province.resources["weapons"]).
const WEAPON_KEYS := ["maces", "pikes", "bows", "swords", "crossbows", "horses", "armour"]

# Unit type -> weapon costs (knights need horse + armour).
const UNIT_WEAPON_COST := {
	UNIT_TYPE.PEASANT: {},
	UNIT_TYPE.MACEMEN: {"maces": 1},
	UNIT_TYPE.PIKEMEN: {"pikes": 1},
	UNIT_TYPE.ARCHER: {"bows": 1},
	UNIT_TYPE.SWORDSMEN: {"swords": 1},
	UNIT_TYPE.CROSSBOWMEN: {"crossbows": 1},
	UNIT_TYPE.KNIGHTS: {"horses": 1, "armour": 1},
}

# Merchant buy price = matching unit strength * this (tweak later).
const WEAPON_PRICE_STRENGTH_MULT := 4
# When 2+ merchants share a province, prices drop by this fraction.
const MERCHANT_COMPETITION_DISCOUNT := 0.15

# Weapon key -> unit type whose strength sets the mark price.
const WEAPON_PRICE_UNIT := {
	"maces": UNIT_TYPE.MACEMEN,
	"pikes": UNIT_TYPE.PIKEMEN,
	"bows": UNIT_TYPE.ARCHER,
	"swords": UNIT_TYPE.SWORDSMEN,
	"crossbows": UNIT_TYPE.CROSSBOWMEN,
	"horses": UNIT_TYPE.KNIGHTS,
	"armour": UNIT_TYPE.KNIGHTS,
}

# Province material stockpile keys (resources[key]["has"]).
# Note: grain "has"/"will" are per-player Dictionaries ({pid: n, "all": n}).
const MATERIAL_KEYS := ["grain", "wood", "stone", "iron"]

# Placeholder merchant prices (marks each); tweak later.
const MATERIAL_MARK_PRICES := {
	"grain": 2,
	"wood": 3,
	"stone": 4,
	"iron": 5,
}

# --- Fields / agriculture ---------------------------------------------------
# Plant winter (costs GRAIN_SEED_PER_FIELD from holding stock). Labor scales with
# planted fields. Harvest when leaving autumn. Horses: pasture + stock + labor → foals.
const GRAIN_SEED_PER_FIELD := 5
const GRAIN_YIELD_PER_FIELD := 80
const PEOPLE_PER_GRAIN_FIELD := 8
const PEOPLE_PER_HORSE_FIELD := 5
const FOAL_MIN := 1
const FOAL_MAX := 3
const STARTING_GRAIN := 40

# Labor category keys shared by fields + economy (blacksmith production later).
const LABOR_CATEGORIES := ["grain", "horses", "wood", "stone", "iron", "silver"]

# --- Economy buildings ------------------------------------------------------
const ECONOMY_COST_WOODCUTTER := 100
const ECONOMY_COST_BLACKSMITH := 250
const ECONOMY_COST_MINE := 500
const ECONOMY_WORKERS_SMALL := 50
const ECONOMY_WORKERS_MEDIUM := 150
const ECONOMY_WORKERS_BIG := 300
# Output per assigned worker per season.
const ECONOMY_WOOD_PER_WORKER := 1
const ECONOMY_STONE_PER_WORKER := 1
const ECONOMY_IRON_PER_WORKER := 1
const ECONOMY_SILVER_MARKS_PER_WORKER := 2

const WOUND_RECOVER_SEASONS := 2
const HOSTAGE_RECOVER_SEASONS := 2
const BASE_DEAD_FRACTION := 0.10
const BASE_WOUND_FRACTION := 0.20
const STRENGTH_LUCK_FRACTION := 0.20
const JOIN_CHANCE_SELLSWORD := 0.80
const JOIN_CHANCE_LEVY := 0.50


func empty_weapon_stock() -> Dictionary:
	var out := {}
	for k in WEAPON_KEYS:
		out[k] = 0
	return out


func weapon_name(key: String) -> String:
	match key:
		"maces": return "Maces"
		"pikes": return "Pikes"
		"bows": return "Bows"
		"swords": return "Swords"
		"crossbows": return "Crossbows"
		"horses": return "Horses"
		"armour": return "Armour"
	return key.capitalize()


## Base marks price for one weapon (strength × mult). Horses/armour use knight strength.
func weapon_mark_price(key: String) -> int:
	var ut: int = int(WEAPON_PRICE_UNIT.get(key, UNIT_TYPE.PEASANT))
	return unit_strength(ut) * WEAPON_PRICE_STRENGTH_MULT


## Marks price with optional competition discount (floor).
func weapon_mark_price_discounted(key: String, competition: bool) -> int:
	var base := weapon_mark_price(key)
	if not competition:
		return base
	return int(floor(float(base) * (1.0 - MERCHANT_COMPETITION_DISCOUNT)))


func empty_material_stock() -> Dictionary:
	var out := {}
	for k in MATERIAL_KEYS:
		out[k] = 0
	return out


func material_name(key: String) -> String:
	match key:
		"grain": return "Grain"
		"wood": return "Wood"
		"stone": return "Stone"
		"iron": return "Iron"
	return key.capitalize()


func material_mark_price(key: String) -> int:
	return int(MATERIAL_MARK_PRICES.get(key, 0))


func material_mark_price_discounted(key: String, competition: bool) -> int:
	var base := material_mark_price(key)
	if not competition:
		return base
	return int(floor(float(base) * (1.0 - MERCHANT_COMPETITION_DISCOUNT)))


## Holding materials use per-player Dictionaries ({pid: n, "all": n}).
func is_holding_material(key: String) -> bool:
	return key in MATERIAL_KEYS


## Ensure province.resources[key] has a per-player "has"/"will" dict.
func ensure_material_has(resources: Dictionary, key: String) -> void:
	if not resources.has(key) or not (resources[key] is Dictionary):
		resources[key] = {"has": empty_per_player_amount(), "will": empty_per_player_amount()}
		return
	if not resources[key].has("has"):
		resources[key]["has"] = empty_per_player_amount()
	elif resources[key]["has"] is int:
		var n := int(resources[key]["has"])
		resources[key]["has"] = {"all": n}
	if not resources[key].has("will"):
		resources[key]["will"] = empty_per_player_amount()
	elif resources[key]["will"] is int:
		resources[key]["will"] = {"all": int(resources[key]["will"])}


## Add materials into a holding (player_id). Marks are not materials.
func add_materials(resources: Dictionary, add: Dictionary, player_id: int = -1) -> void:
	for k in MATERIAL_KEYS:
		var amt := int(add.get(k, 0))
		if amt == 0:
			continue
		ensure_material_has(resources, k)
		var has: Dictionary = resources[k]["has"]
		if player_id >= 0:
			has[player_id] = int(has.get(player_id, 0)) + amt
		else:
			has["all"] = int(has.get("all", 0)) + amt
		recompute_per_player_all(has)


func recompute_per_player_all(bucket: Dictionary) -> void:
	var total := 0
	for k in bucket.keys():
		if str(k) == "all":
			continue
		total += int(bucket[k])
	bucket["all"] = total


func empty_per_player_amount() -> Dictionary:
	return {"all": 0}


func weapon_cost_for_type(type_: int) -> Dictionary:
	return UNIT_WEAPON_COST.get(type_, {}).duplicate()


## Aggregate weapon costs for a composition: Array of {type, count}.
func weapons_needed_for_composition(composition: Array) -> Dictionary:
	var need := empty_weapon_stock()
	for entry in composition:
		var costs: Dictionary = weapon_cost_for_type(int(entry.get("type", UNIT_TYPE.PEASANT)))
		var n := int(entry.get("count", 0))
		if n <= 0:
			continue
		for k in costs:
			need[k] = int(need.get(k, 0)) + int(costs[k]) * n
	return need


## Weapons refunded when disbanding stacks (levy only — sellswords keep no kit).
func weapons_from_units(units: Array, owner_filter: int = -1) -> Dictionary:
	var refund := empty_weapon_stock()
	for s in units:
		if owner_filter >= 0 and int(s.get("owner", -1)) != owner_filter:
			continue
		if int(s.get("source", SOURCE.LEVY)) != SOURCE.LEVY:
			continue
		var costs: Dictionary = weapon_cost_for_type(int(s.get("type", UNIT_TYPE.PEASANT)))
		var n := int(s.get("count", 0))
		for k in costs:
			refund[k] = int(refund.get(k, 0)) + int(costs[k]) * n
	return refund


func can_afford_weapons(stock: Dictionary, need: Dictionary) -> bool:
	for k in need:
		if int(need[k]) <= 0:
			continue
		if int(stock.get(k, 0)) < int(need[k]):
			return false
	return true


func subtract_weapons(stock: Dictionary, need: Dictionary) -> void:
	for k in need:
		var amt := int(need[k])
		if amt <= 0:
			continue
		stock[k] = maxi(0, int(stock.get(k, 0)) - amt)


func add_weapons(stock: Dictionary, add: Dictionary) -> void:
	for k in WEAPON_KEYS:
		var amt := int(add.get(k, 0))
		if amt != 0:
			stock[k] = int(stock.get(k, 0)) + amt


func composition_total_men(composition: Array) -> int:
	var total := 0
	for entry in composition:
		total += maxi(0, int(entry.get("count", 0)))
	return total


func levy_happiness_penalty(levied_total: int, season_start_pop: int) -> float:
	if season_start_pop <= 0 or levied_total <= 0:
		return 0.0
	var pct := float(levied_total) / float(season_start_pop) * 100.0
	var free_pct := LEVY_HAPPINESS_FREE_FRACTION * 100.0
	return maxf(0.0, (pct - free_pct) * LEVY_HAPPINESS_PER_PERCENT)


## True when the force is non-empty and every stack is knights.
func is_knights_only(units: Array) -> bool:
	if units.is_empty():
		return false
	for s in units:
		if int(s.get("type", UNIT_TYPE.PEASANT)) != UNIT_TYPE.KNIGHTS:
			return false
	return true


## Fraction of men that are not FIGHTING (wounded / hostage / captured).
func non_fighting_fraction(units: Array) -> float:
	var total := total_men(units)
	if total <= 0:
		return 0.0
	return float(total_men(non_fighting_units(units))) / float(total)


## 0..WOUND_MP_MAX_PENALTY from non-fighting share (free below 10%, max at 50%+).
func wound_mp_penalty(units: Array) -> float:
	var frac := non_fighting_fraction(units)
	if frac <= WOUND_MP_FREE_FRACTION:
		return 0.0
	if frac >= WOUND_MP_MAX_FRACTION:
		return WOUND_MP_MAX_PENALTY
	var t := (frac - WOUND_MP_FREE_FRACTION) / (WOUND_MP_MAX_FRACTION - WOUND_MP_FREE_FRACTION)
	return t * WOUND_MP_MAX_PENALTY


## Effective max MP for a force this turn from base + knights bonus − wound drag.
func effective_movement_points(units: Array, base_mp: int) -> int:
	if base_mp <= 0:
		return 0
	var mult := KNIGHT_ONLY_MP_MULT if is_knights_only(units) else 1.0
	var penalty := wound_mp_penalty(units)
	return maxi(0, int(floor(float(base_mp) * mult * (1.0 - penalty))))


func unit_name(type_: int) -> String:
	return UNIT_STATS.get(type_, {}).get("name", "Unknown")


func unit_strength(type_: int) -> int:
	return UNIT_STATS.get(type_, {}).get("strength", 0)


func source_name(source_: int) -> String:
	match source_:
		SOURCE.LEVY: return "Levy"
		SOURCE.SELLSWORD: return "Sellsword"
	return "Unknown"


func status_name(status_: int) -> String:
	match status_:
		STATUS.FIGHTING: return "Fighting"
		STATUS.WOUNDED: return "Wounded"
		STATUS.HOSTAGE: return "Hostage"
		STATUS.CAPTURED: return "Captured"
	return "Unknown"


func stack_status(stack: Dictionary) -> int:
	return int(stack.get("status", STATUS.FIGHTING))


func is_fighting_stack(stack: Dictionary) -> bool:
	return stack_status(stack) == STATUS.FIGHTING


func make_stack(type_: int, owner: int, source_: int, count: int, status_: int = STATUS.FIGHTING, recover_in: int = 0, join_pending: bool = false) -> Dictionary:
	var s := {"type": type_, "owner": owner, "source": source_, "count": count}
	if status_ != STATUS.FIGHTING:
		s["status"] = status_
	if recover_in > 0:
		s["recover_in"] = recover_in
	if join_pending:
		s["join_pending"] = true
	return s


func _copy_stack(s: Dictionary) -> Dictionary:
	var out := {
		"type": s["type"],
		"owner": s["owner"],
		"source": s["source"],
		"count": s["count"],
	}
	if s.has("status"):
		out["status"] = s["status"]
	if s.has("recover_in"):
		out["recover_in"] = s["recover_in"]
	if s.has("join_pending"):
		out["join_pending"] = s["join_pending"]
	return out


# Deep copy so callers can mutate freely without touching the registry.
func clone_units(units: Array) -> Array:
	var out: Array = []
	for s in units:
		out.append(_copy_stack(s))
	return out


func _stacks_mergeable(a: Dictionary, b: Dictionary) -> bool:
	return (
		a["type"] == b["type"]
		and a["owner"] == b["owner"]
		and a["source"] == b["source"]
		and stack_status(a) == stack_status(b)
		and int(a.get("recover_in", 0)) == int(b.get("recover_in", 0))
		and bool(a.get("join_pending", false)) == bool(b.get("join_pending", false))
	)


func total_men(units: Array) -> int:
	var total := 0
	for s in units:
		total += int(s["count"])
	return total


func fighting_units(units: Array) -> Array:
	var out: Array = []
	for s in units:
		if is_fighting_stack(s):
			out.append(s)
	return out


func non_fighting_units(units: Array) -> Array:
	var out: Array = []
	for s in units:
		if not is_fighting_stack(s):
			out.append(s)
	return out


func fighting_men(units: Array) -> int:
	return total_men(fighting_units(units))


func total_strength(units: Array, multiplier: float = 1.0) -> int:
	var total := 0.0
	for s in units:
		total += unit_strength(s["type"]) * int(s["count"])
	return int(round(total * multiplier))


func fighting_strength(units: Array, multiplier: float = 1.0) -> int:
	return total_strength(fighting_units(units), multiplier)


func men_of_owner(units: Array, owner: int) -> int:
	var total := 0
	for s in units:
		if int(s["owner"]) == owner:
			total += int(s["count"])
	return total


func units_of_owner(units: Array, owner: int) -> Array:
	var out: Array = []
	for s in units:
		if int(s["owner"]) == owner:
			out.append(s)
	return out


func all_owned_by(stacks: Array, owner: int) -> bool:
	if stacks.is_empty():
		return false
	for s in stacks:
		if int(s["owner"]) != owner:
			return false
	return true


func owners_in(units: Array) -> Array:
	var seen: Array = []
	for s in units:
		if not seen.has(int(s["owner"])):
			seen.append(int(s["owner"]))
	return seen


# Owner contributing the most men; used as a fallback when no controller is set.
func primary_owner(units: Array) -> int:
	var by_owner: Dictionary = {}
	for s in units:
		var o := int(s["owner"])
		by_owner[o] = by_owner.get(o, 0) + int(s["count"])
	var best := -1
	var best_count := -1
	for o in by_owner:
		if by_owner[o] > best_count:
			best_count = by_owner[o]
			best = o
	return best


# Adds a stack into a units array, folding it into an identical stack when one exists.
func add_stack(units: Array, stack: Dictionary) -> void:
	if int(stack["count"]) <= 0:
		return
	for s in units:
		if _stacks_mergeable(s, stack):
			s["count"] = int(s["count"]) + int(stack["count"])
			return
	units.append(_copy_stack(stack))


# Removes `to_remove` from `units` in place. Matches type+owner+source+status(+recover/join).
func subtract_units(units: Array, to_remove: Array) -> void:
	for r in to_remove:
		var remaining := int(r["count"])
		for s in units:
			if remaining <= 0:
				break
			if not _stacks_mergeable(s, r):
				continue
			var take: int = mini(int(s["count"]), remaining)
			s["count"] = int(s["count"]) - take
			remaining -= take
	var i := units.size() - 1
	while i >= 0:
		if int(units[i]["count"]) <= 0:
			units.remove_at(i)
		i -= 1


# Returns a new units array combining a and b (folding identical stacks).
func merge_units(a: Array, b: Array) -> Array:
	var out := clone_units(a)
	for s in b:
		add_stack(out, s)
	return out


# Builds a units array from a designer-authored spec (Array of Dictionaries as
# set in a scene/inspector). Missing fields fall back to sensible defaults.
func units_from_spec(spec: Array) -> Array:
	var out: Array = []
	for entry in spec:
		var stack := make_stack(
			int(entry.get("type", UNIT_TYPE.PEASANT)),
			int(entry.get("owner", 0)),
			int(entry.get("source", SOURCE.LEVY)),
			int(entry.get("count", 0)),
			int(entry.get("status", STATUS.FIGHTING)),
			int(entry.get("recover_in", 0)),
			bool(entry.get("join_pending", false))
		)
		add_stack(out, stack)
	return out


# Human-readable multi-line breakdown for popups/menus.
func describe_units(units: Array) -> String:
	if units.is_empty():
		return "empty"
	var lines: PackedStringArray = []
	for s in units:
		var line := "%d %s (%s)" % [int(s["count"]), unit_name(s["type"]), source_name(s["source"])]
		var st := stack_status(s)
		if st != STATUS.FIGHTING:
			line += " [%s]" % status_name(st)
			var rec := int(s.get("recover_in", 0))
			if rec > 0:
				line += " (%d seasons)" % rec
		if bool(s.get("join_pending", false)):
			line += " (join pending)"
		lines.append(line)
	return "\n".join(lines)


# --- Combat helpers ---------------------------------------------------------

# Winner casualty scale: 1.0 at even strength, shrinks as they dominate (fewer own losses).
func casualty_factor(winner_str: int, loser_str: int) -> float:
	var adv := float(maxi(winner_str, 1)) / float(maxi(loser_str, 1))
	return 1.0 / (1.0 + maxf(0.0, adv - 1.0))


# Loser casualty scale: 1.0 at even strength, rises when crushed (cap 2.5×).
func loser_casualty_factor(winner_str: int, loser_str: int) -> float:
	var adv := float(maxi(winner_str, 1)) / float(maxi(loser_str, 1))
	return clampf(1.0 + (adv - 1.0) * 0.5, 1.0, 2.5)


func roll_effective_strength(base_str: int, rng: RandomNumberGenerator) -> float:
	return float(base_str) * (1.0 + rng.randf() * STRENGTH_LUCK_FRACTION)


# Split fighting men into remaining fighting + wounded stacks using dead/wound %.
# Non-fighting stacks in `units` are preserved unchanged in `remaining`.
func apply_side_casualties(units: Array, dead_frac: float, wound_frac: float) -> Dictionary:
	var remaining: Array = []
	var wounded_out: Array = []
	var dead_total := 0
	var wound_total := 0
	for s in units:
		if not is_fighting_stack(s):
			add_stack(remaining, s)
			continue
		var n := int(s["count"])
		var dead_n := int(floor(float(n) * dead_frac))
		var wound_n := int(floor(float(n) * wound_frac))
		if dead_n + wound_n > n:
			wound_n = n - dead_n
		var live_n := n - dead_n - wound_n
		dead_total += dead_n
		wound_total += wound_n
		if live_n > 0:
			add_stack(remaining, make_stack(int(s["type"]), int(s["owner"]), int(s["source"]), live_n))
		if wound_n > 0:
			add_stack(wounded_out, make_stack(
				int(s["type"]), int(s["owner"]), int(s["source"]), wound_n,
				STATUS.WOUNDED, WOUND_RECOVER_SEASONS
			))
	return {
		"remaining": remaining,
		"wounded": wounded_out,
		"dead": dead_total,
		"wounded_men": wound_total,
	}


## After a side is wiped from the map: leftover fighters → dead; wounded + other
## non-fighting leftovers → hostage pool. Mutates `result` dead/wounded_men.
## Returns the hostage pool array.
func account_wiped_side(result: Dictionary, capture_wounded: bool = true) -> Array:
	var hostages: Array = []
	var extra_dead := 0
	for s in result.get("remaining", []):
		var n := int(s.get("count", 0))
		if n <= 0:
			continue
		if is_fighting_stack(s):
			extra_dead += n
		elif capture_wounded:
			add_stack(hostages, s)
		else:
			extra_dead += n
	if capture_wounded:
		for s in result.get("wounded", []):
			add_stack(hostages, s)
	else:
		extra_dead += total_men(result.get("wounded", []))
	result["dead"] = int(result.get("dead", 0)) + extra_dead
	result["wounded_men"] = total_men(hostages) if capture_wounded else 0
	result["remaining"] = []
	result["wounded"] = hostages.duplicate(true) if capture_wounded else []
	return hostages


# Tick recover_in / status / join_pending for every stack in a force.
# `join_rng` used when resolving pending join offers. `new_owner_on_join` = controller.
# Optional `join_results` collects {accepted, count, type, source, prev_owner} entries.
func tick_stack_seasons(units: Array, join_rng: RandomNumberGenerator, new_owner_on_join: int, join_results: Array = []) -> Array:
	var out: Array = []
	for s in clone_units(units):
		# Resolve join offers before recovery tick.
		if bool(s.get("join_pending", false)):
			s.erase("join_pending")
			var chance := JOIN_CHANCE_SELLSWORD if int(s["source"]) == SOURCE.SELLSWORD else JOIN_CHANCE_LEVY
			var accepted := join_rng.randf() < chance
			join_results.append({
				"accepted": accepted,
				"count": int(s["count"]),
				"type": int(s["type"]),
				"source": int(s["source"]),
				"prev_owner": int(s["owner"]),
			})
			if accepted:
				s["owner"] = new_owner_on_join
				s["status"] = STATUS.FIGHTING
				s.erase("recover_in")
				add_stack(out, s)
				continue
		var st := stack_status(s)
		var rec := int(s.get("recover_in", 0))
		if rec > 0:
			rec -= 1
			if rec <= 0:
				s.erase("recover_in")
				if st == STATUS.WOUNDED:
					s["status"] = STATUS.FIGHTING
					s.erase("status")
				elif st == STATUS.HOSTAGE:
					s["status"] = STATUS.CAPTURED
			else:
				s["recover_in"] = rec
		add_stack(out, s)
	return out


func join_chance_for_stack(stack: Dictionary) -> float:
	if int(stack.get("source", SOURCE.LEVY)) == SOURCE.SELLSWORD:
		return JOIN_CHANCE_SELLSWORD
	return JOIN_CHANCE_LEVY
