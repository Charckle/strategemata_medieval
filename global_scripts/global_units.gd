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

# LEVY = raised from the population, SELLSWORD = hired.
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

# Units stationed INSIDE a castle fight at this multiplier when listing garrisons
# (equals siege engines level 2). Battle uses siege_inside_bonus() instead.
const CASTLE_INSIDE_BONUS := 3.0
# Outside garrison multiplier used in battle resolution (not affected by siege engines).
const CASTLE_OUTSIDE_BATTLE_BONUS := 1.5
# Max siege-engine level an army can build while Sieging a castle.
const SIEGE_MAX_LEVEL := 3
# Inside bonus by attacker siege-engine level (0 = none … 3 = complete).
const SIEGE_INSIDE_BONUS := [5.0, 4.0, 3.0, 2.5]


func siege_inside_bonus(level: int) -> float:
	var i := clampi(level, 0, SIEGE_MAX_LEVEL)
	return float(SIEGE_INSIDE_BONUS[i])

# Minimum men that must remain in both the original and the split-off army.
const MIN_SPLIT_MEN := 20

# Levy recruitment: max fraction of season-start province population.
const LEVY_MAX_FRACTION := 0.80
# First this fraction of season-start pop can be levied with no happiness hit.
const LEVY_HAPPINESS_FREE_FRACTION := 0.10
# Happiness lost per percent levied above the free band (at 80% ≈ −35).
const LEVY_HAPPINESS_PER_PERCENT := 0.5
# Caravan movement points spent automatically each season.
const CARAVAN_MOVEMENT_POINTS := 10
# Notify owner once after this many consecutive seasons with no path.
const CARAVAN_PATH_FAIL_NOTIFY := 3
# Battle loot: fraction of dead men's kit recovered (rolled per weapon type).
const LOOT_FRAC_MIN := 0.20
const LOOT_FRAC_MAX := 0.40

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

# Sellsword hire price = unit strength * count * this (tweak later).
const SELLSWORD_PRICE_STRENGTH_MULT := 3
const SELLSWORD_STACK_MIN := 50
const SELLSWORD_STACK_MAX := 200
# Hireable types (no peasants).
const SELLSWORD_UNIT_POOL := [
	UNIT_TYPE.MACEMEN,
	UNIT_TYPE.PIKEMEN,
	UNIT_TYPE.ARCHER,
	UNIT_TYPE.SWORDSMEN,
	UNIT_TYPE.CROSSBOWMEN,
	UNIT_TYPE.KNIGHTS,
]

# Seasonal upkeep (marks per man). Player total is ceiled.
const UPKEEP_LEVY_PEASANT := 0.5
const UPKEEP_LEVY_KNIGHT := 2.0
const UPKEEP_LEVY_OTHER := 1.0
const UPKEEP_SELLSWORD_KNIGHT := 5.0
const UPKEEP_SELLSWORD_OTHER := 3.0
# Transport fleets: flat marks per ship; unpaid ships are not struck (v1).
const UPKEEP_TRANSPORT_SHIP := 20
const TRANSPORT_SHIP_CAPACITY := 100
const TRANSPORT_SHIP_MP := 20
const TRANSPORT_SHIP_WOOD_COST := 300
const TRANSPORT_SHIP_MARKS_COST := 500
const TRANSPORT_EMBARK_MP := 5
# Missed pays: strike 1 warn, 2 sellswords leave, 3+ levy desertion.
const UPKEEP_STRIKES_MAX := 3
const UPKEEP_CLEAR_PAYS := 10
# Fraction of each unpaid levy stack that deserts (ceil).
const UPKEEP_DESERT_FRACTION := 0.10
# Attacker wage loot: one roll per battle × next-season upkeep of wiped side.
const WAGE_CAPTURE_MIN := 0.60
const WAGE_CAPTURE_MAX := 0.80

# Campaign foraging: grain per man per season outside controller de jure.
const FOOD_GRAIN_PER_MAN_MOBILE := 1.0
const FOOD_GRAIN_PER_MAN_GARRISON := 0.5
# After one warning season, this fraction of each stack dies (ceil).
const FOOD_ATTRITION_FRACTION := 0.10

# --- Civilian rations (holding setting; feeds settlement pop each season) -----
# Grain spend order from province stock: seed reserve → local armies → people.
enum RATION {
	NONE,
	QUARTER,
	HALF,
	NORMAL,
	DOUBLE,
	QUADRUPLE,
}
const RATION_DEFAULT := RATION.NORMAL
# Grain per person per season at each ration level.
const RATION_GRAIN_PER_PERSON := {
	RATION.NONE: 0.0,
	RATION.QUARTER: 0.125,
	RATION.HALF: 0.25,
	RATION.NORMAL: 0.5,
	RATION.DOUBLE: 1.0,
	RATION.QUADRUPLE: 2.0,
}
# Happiness delta applied to each owned settlement when that ration is effective.
const RATION_HAPPINESS_DELTA := {
	RATION.NONE: -15.0,
	RATION.QUARTER: -8.0,
	RATION.HALF: -4.0,
	RATION.NORMAL: 4.0,
	RATION.DOUBLE: 8.0,
	RATION.QUADRUPLE: 12.0,
}
# Population change fraction (ceil abs); replaces flat settlement growth.
const RATION_POP_DELTA := {
	RATION.NONE: -0.15,
	RATION.QUARTER: -0.08,
	RATION.HALF: -0.04,
	RATION.NORMAL: 0.04,
	RATION.DOUBLE: 0.08,
	RATION.QUADRUPLE: 0.12,
}
# First positive growth from an empty (0-pop) settlement.
const RATION_ZERO_POP_BOOTSTRAP := 10
# Descending order for "highest affordable ≤ requested" resolution.
const RATION_LEVELS_DESC := [
	RATION.QUADRUPLE,
	RATION.DOUBLE,
	RATION.NORMAL,
	RATION.HALF,
	RATION.QUARTER,
	RATION.NONE,
]

# --- Holding taxes (marks stored per settlement; collect with army) ----------
enum TAX {
	NONE,
	NORMAL,
	HEAVY,
	HARSH,
	BRUTAL,
}
const TAX_DEFAULT := TAX.NORMAL
const TAX_COLLECT_MP := 1
# Marks deposited into each settlement coffer per person (ceil).
const TAX_MARKS_PER_PERSON := {
	TAX.NONE: 0,
	TAX.NORMAL: 1,
	TAX.HEAVY: 2,
	TAX.HARSH: 3,
	TAX.BRUTAL: 4,
}
const TAX_HAPPINESS_DELTA := {
	TAX.NONE: 10.0,
	TAX.NORMAL: 5.0,
	TAX.HEAVY: -5.0,
	TAX.HARSH: -10.0,
	TAX.BRUTAL: -18.0,
}
const TAX_POP_DELTA := {
	TAX.NONE: 0.05,
	TAX.NORMAL: 0.025,
	TAX.HEAVY: -0.025,
	TAX.HARSH: -0.05,
	TAX.BRUTAL: -0.10,
}
const TAX_LEVELS := [
	TAX.NONE,
	TAX.NORMAL,
	TAX.HEAVY,
	TAX.HARSH,
	TAX.BRUTAL,
]

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
# Winter: plan grain fields (map looks sown). Seed (GRAIN_SEED_PER_FIELD) is spent
# when leaving winter. Labor scales with planted fields. Harvest when leaving autumn.
# Horses: each pasture hosts up to HORSES_PER_FIELD; labor need is per occupied
# pasture; foals scale with (horses/cap)×(workers/need) every season incl. winter.
const GRAIN_SEED_PER_FIELD := 5
const GRAIN_YIELD_PER_FIELD := 80
const PEOPLE_PER_GRAIN_FIELD := 8
const PEOPLE_PER_HORSE_FIELD := 10
const HORSES_PER_FIELD := 20
const FOAL_EFF_HIGH := 0.75
const FOAL_EFF_MID := 0.25
const FOAL_HIGH_MIN := 2
const FOAL_HIGH_MAX := 5
const FOAL_MID_MIN := 1
const FOAL_MID_MAX := 3
const STARTING_GRAIN := 40

# Labor category keys shared by fields + economy + castle construction.
const LABOR_CATEGORIES := ["grain", "horses", "wood", "stone", "iron", "silver", "blacksmith", "castle"]

# --- Economy buildings ------------------------------------------------------
# Subtype ints match basic_building.SUBTYPES:
# 0 woodcutter, 1 iron mine, 3 silver mine, 4 stone quarry, 5 blacksmith.
# Costs / workers arrays are [Small, Medium, Big]: build cost or worker cap at that stage;
# upgrade Small→Medium uses Medium cost, Medium→Big uses Big cost.
const ECONOMY_STAGE_COSTS := {
	0: [100, 400, 800],
	1: [500, 1300, 3000],
	3: [800, 3000, 13000],
	4: [500, 1500, 3500],
	5: [250, 750, 1500],
}
const ECONOMY_WORKERS_BY_SUBTYPE := {
	0: [100, 250, 500],
	1: [100, 250, 500],
	3: [50, 150, 300],
	4: [50, 150, 300],
	5: [50, 150, 300],
}
# Output per assigned worker per season.
const ECONOMY_WOOD_PER_WORKER := 1
const ECONOMY_STONE_PER_WORKER := 1
const ECONOMY_IRON_PER_WORKER := 1
const ECONOMY_SILVER_MARKS_PER_WORKER := 2

# --- Settlement marks (town / village) --------------------------------------
# Base tax from population; tier % applies only to that settlement's base.
const SETTLEMENT_MARKS_POP_RATE := 0.10
# Tier index: 0=Small, 1=Medium, 2=Big, 3=Very Big
const SETTLEMENT_TIER_MARKS_BONUS := [0.0, 0.10, 0.20, 0.30]
# Population ceilings for Small / Medium / Big (above last → Very Big).
const TOWN_TIER_POP_MAX := [300, 600, 900]
const VILLAGE_TIER_POP_MAX := [20, 60, 120]
# Soft population caps (growth may overshoot; overflow applies pressure next tick).
const TOWN_POPULATION_CAP := 2000
const VILLAGE_POPULATION_CAP := 300
# When over cap: at least −this fraction (ceil), or worse ration/tax delta if larger.
const SETTLEMENT_OVERFLOW_SHRINK_FRAC := 0.10
# Random jitter added to over-cap delta (inclusive), seeded per season.
const TOWN_OVERFLOW_JITTER := 50
const VILLAGE_OVERFLOW_JITTER := 10

# --- Castle construction (CASTLE_TYPE 0..5) ----------------------------------
# Materials paid upfront into the worksite; 1 labor = 1 work / season.
const CASTLE_COST_WOOD := [500, 1000, 1000, 1000, 1500, 2000]
const CASTLE_COST_STONE := [0, 0, 1000, 2500, 3200, 4500]
const CASTLE_WORK := [500, 1000, 2500, 3500, 4500, 6000]
## Holding-wide marks bonus on Σ settlement base (CASTLE_TYPE 0..5). Mid-build = 0.
const CASTLE_HOLDING_MARKS_BONUS := [0.10, 0.20, 0.30, 0.50, 0.80, 1.00]
## Target level for dismantle-to-empty projects.
const CASTLE_TARGET_EMPTY := -1


func economy_stage_cost(subtype: int, stage_index: int) -> int:
	## stage_index 0=Small, 1=Medium, 2=Big.
	var costs: Array = ECONOMY_STAGE_COSTS.get(subtype, [])
	if stage_index < 0 or stage_index >= costs.size():
		return 0
	return int(costs[stage_index])


func economy_workers_for(subtype: int, stage_index: int) -> int:
	## stage_index 0=Small, 1=Medium, 2=Big.
	var caps: Array = ECONOMY_WORKERS_BY_SUBTYPE.get(subtype, [50, 150, 300])
	if stage_index < 0 or stage_index >= caps.size():
		return int(caps[0]) if not caps.is_empty() else 50
	return int(caps[stage_index])


func settlement_base_marks(population: int) -> int:
	return int(ceil(float(maxi(0, population)) * SETTLEMENT_MARKS_POP_RATE))


## Adjust a settlement's pop delta when over its soft cap.
## Over cap: min(base_delta, −ceil(10% pop)), then optional ±jitter (rng null → no jitter).
func settlement_overflow_adjusted_delta(
	population: int,
	base_delta: int,
	pop_cap: int,
	jitter: int = 0,
	rng: RandomNumberGenerator = null
) -> int:
	if pop_cap <= 0 or population <= pop_cap:
		return base_delta
	var overflow := -int(ceili(float(population) * SETTLEMENT_OVERFLOW_SHRINK_FRAC))
	var delta := mini(base_delta, overflow)
	if rng != null and jitter > 0:
		delta += rng.randi_range(-jitter, jitter)
	return delta


## Cap / jitter for a town or village node (0 / 0 if unknown).
func settlement_pop_cap_and_jitter(settlement: Node) -> Vector2i:
	if settlement == null:
		return Vector2i(0, 0)
	if settlement.has_method("get_population_cap"):
		var cap := int(settlement.get_population_cap())
		var jit := 0
		if settlement.has_method("get_overflow_jitter"):
			jit = int(settlement.get_overflow_jitter())
		return Vector2i(cap, jit)
	return Vector2i(0, 0)


## Returns tier index 0..3 from population and [small_max, medium_max, big_max].
func settlement_tier_index(population: int, tier_max: Array) -> int:
	var p := maxi(0, population)
	if tier_max.size() < 3:
		return 0
	if p <= int(tier_max[0]):
		return 0
	if p <= int(tier_max[1]):
		return 1
	if p <= int(tier_max[2]):
		return 2
	return 3


func settlement_tier_marks_bonus(tier_index: int) -> float:
	if tier_index < 0 or tier_index >= SETTLEMENT_TIER_MARKS_BONUS.size():
		return 0.0
	return float(SETTLEMENT_TIER_MARKS_BONUS[tier_index])


## Base marks plus that settlement's tier bonus (bonus is % of base only).
func settlement_marks_with_tier_bonus(base_marks: int, tier_index: int) -> int:
	var base := maxi(0, base_marks)
	var bonus := settlement_tier_marks_bonus(tier_index)
	return base + int(floor(float(base) * bonus))


func castle_holding_marks_bonus(castle_type: int) -> float:
	if castle_type < 0 or castle_type >= CASTLE_HOLDING_MARKS_BONUS.size():
		return 0.0
	return float(CASTLE_HOLDING_MARKS_BONUS[castle_type])


func castle_material_cost(level: int) -> Dictionary:
	if level < 0 or level >= CASTLE_COST_WOOD.size():
		return {"wood": 0, "stone": 0}
	return {"wood": int(CASTLE_COST_WOOD[level]), "stone": int(CASTLE_COST_STONE[level])}


func castle_work_required(level: int) -> int:
	if level < 0 or level >= CASTLE_WORK.size():
		return 0
	return int(CASTLE_WORK[level])


## Element-wise max(0, to - from) material delta.
func castle_material_delta(from_level: int, to_level: int) -> Dictionary:
	var a := castle_material_cost(from_level)
	var b := castle_material_cost(to_level)
	return {
		"wood": maxi(0, int(b["wood"]) - int(a["wood"])),
		"stone": maxi(0, int(b["stone"]) - int(a["stone"])),
	}


func castle_material_refund(from_level: int, to_level: int) -> Dictionary:
	var a := castle_material_cost(from_level)
	var b := castle_material_cost(to_level)
	return {
		"wood": maxi(0, int(a["wood"]) - int(b["wood"])),
		"stone": maxi(0, int(a["stone"]) - int(b["stone"])),
	}

# Blacksmith: one recipe per smith. Labor + materials per finished weapon.
const BLACKSMITH_CRAFTABLE := ["maces", "pikes", "bows", "swords", "crossbows", "armour"]
const BLACKSMITH_LABOR := {
	"bows": 1,
	"maces": 2,
	"pikes": 2,
	"swords": 3,
	"crossbows": 6,
	"armour": 10,
}
# Materials consumed per weapon crafted.
const BLACKSMITH_RECIPES := {
	"bows": {"wood": 10},
	"pikes": {"wood": 3, "iron": 7},
	"armour": {"iron": 28},
	"maces": {"wood": 3, "iron": 3},
	"swords": {"wood": 10, "iron": 3},
	"crossbows": {"wood": 10, "iron": 15},
}

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


func sanitize_weapon_stock(stock: Dictionary) -> Dictionary:
	var clean := empty_weapon_stock()
	for k in WEAPON_KEYS:
		clean[k] = maxi(0, int(stock.get(k, 0)))
	return clean


func weapon_stock_has_any(stock: Dictionary) -> bool:
	for k in WEAPON_KEYS:
		if int(stock.get(k, 0)) > 0:
			return true
	return false


func weapon_stock_summary(stock: Dictionary) -> String:
	var bits: PackedStringArray = []
	for k in WEAPON_KEYS:
		var amt := int(stock.get(k, 0))
		if amt > 0:
			bits.append("%d %s" % [amt, weapon_name(k)])
	if bits.is_empty():
		return "(none)"
	return ", ".join(bits)


func add_weapon_stocks(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := sanitize_weapon_stock(a)
	for k in WEAPON_KEYS:
		out[k] = int(out.get(k, 0)) + maxi(0, int(b.get(k, 0)))
	return out


## Clamp `want` so each key is at most what `available` holds.
func clamp_weapon_stock(available: Dictionary, want: Dictionary) -> Dictionary:
	var out := empty_weapon_stock()
	for k in WEAPON_KEYS:
		out[k] = mini(maxi(0, int(want.get(k, 0))), maxi(0, int(available.get(k, 0))))
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


func blacksmith_recipe(weapon_key: String) -> Dictionary:
	return BLACKSMITH_RECIPES.get(weapon_key, {}).duplicate()


func blacksmith_people_per(weapon_key: String) -> int:
	return maxi(1, int(BLACKSMITH_LABOR.get(weapon_key, 1)))


func blacksmith_recipe_label(weapon_key: String) -> String:
	var recipe: Dictionary = BLACKSMITH_RECIPES.get(weapon_key, {})
	if recipe.is_empty() and weapon_key not in BLACKSMITH_LABOR:
		return weapon_name(weapon_key)
	var parts: PackedStringArray = []
	for mat in MATERIAL_KEYS:
		var amt := int(recipe.get(mat, 0))
		if amt > 0:
			parts.append("%d %s" % [amt, material_name(mat)])
	var people := blacksmith_people_per(weapon_key)
	parts.append("%d %s" % [people, "person" if people == 1 else "people"])
	return "%s (%s)" % [weapon_name(weapon_key), ", ".join(parts)]


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


## Sell payout: half base buy price; +competition bonus when 2+ merchants (floor).
func weapon_mark_sell_price(key: String, competition: bool) -> int:
	var half := int(floor(float(weapon_mark_price(key)) * 0.5))
	if not competition:
		return half
	return int(floor(float(half) * (1.0 + MERCHANT_COMPETITION_DISCOUNT)))


## Marks to hire one sellsword stack (strength × mult × count).
func sellsword_stack_mark_price(type_: int, count: int) -> int:
	if count <= 0:
		return 0
	return unit_strength(type_) * SELLSWORD_PRICE_STRENGTH_MULT * count


## Total marks for a sellsword offer Array of { "type", "count" }.
func sellsword_offer_mark_price(offer: Array) -> int:
	var total := 0
	for entry in offer:
		total += sellsword_stack_mark_price(
			int(entry.get("type", UNIT_TYPE.PEASANT)),
			int(entry.get("count", 0))
		)
	return total


## Fighting and wounded need pay; hostages / captured / join_pending do not.
func stack_needs_upkeep(stack: Dictionary) -> bool:
	if bool(stack.get("join_pending", false)):
		return false
	var st := stack_status(stack)
	return st == STATUS.FIGHTING or st == STATUS.WOUNDED


## Marks per man for a payable stack (0.0 if unpaid status).
func stack_upkeep_per_man(stack: Dictionary) -> float:
	if not stack_needs_upkeep(stack):
		return 0.0
	var type_ := int(stack.get("type", UNIT_TYPE.PEASANT))
	var source_ := int(stack.get("source", SOURCE.LEVY))
	if source_ == SOURCE.SELLSWORD:
		if type_ == UNIT_TYPE.KNIGHTS:
			return UPKEEP_SELLSWORD_KNIGHT
		return UPKEEP_SELLSWORD_OTHER
	if type_ == UNIT_TYPE.PEASANT:
		return UPKEEP_LEVY_PEASANT
	if type_ == UNIT_TYPE.KNIGHTS:
		return UPKEEP_LEVY_KNIGHT
	return UPKEEP_LEVY_OTHER


## Raw (uncapped) upkeep marks for stacks owned by owner.
func upkeep_raw_for_owner(units: Array, owner: int) -> Dictionary:
	var levy := 0.0
	var sellsword := 0.0
	for s in units:
		if int(s.get("owner", -1)) != owner:
			continue
		var per := stack_upkeep_per_man(s)
		if per <= 0.0:
			continue
		var cost := per * float(int(s.get("count", 0)))
		if int(s.get("source", SOURCE.LEVY)) == SOURCE.SELLSWORD:
			sellsword += cost
		else:
			levy += cost
	return {"levy": levy, "sellsword": sellsword, "total": levy + sellsword}


## Ceil of player-total upkeep (and breakdown ceils for display).
func upkeep_marks_for_owner(units: Array, owner: int) -> Dictionary:
	var raw := upkeep_raw_for_owner(units, owner)
	return {
		"levy": int(ceili(float(raw["levy"]))),
		"sellsword": int(ceili(float(raw["sellsword"]))),
		"total": int(ceili(float(raw["total"]))),
		"levy_raw": float(raw["levy"]),
		"sellsword_raw": float(raw["sellsword"]),
		"total_raw": float(raw["total"]),
	}


## Ceil of (raw upkeep × fraction) for owner's stacks in units.
func wage_capture_claim(units: Array, owner: int, fraction: float) -> int:
	var raw := float(upkeep_raw_for_owner(units, owner)["total"])
	if raw <= 0.0 or fraction <= 0.0:
		return 0
	return int(ceili(raw * fraction))


## Men that desert from one unpaid levy stack (10% ceil).
func desertion_from_stack(stack: Dictionary) -> int:
	if int(stack.get("source", SOURCE.LEVY)) != SOURCE.LEVY:
		return 0
	if not stack_needs_upkeep(stack):
		return 0
	var n := int(stack.get("count", 0))
	if n <= 0:
		return 0
	return int(ceili(float(n) * UPKEEP_DESERT_FRACTION))


## Grain needed to feed `men` for one season (garrison half-rate, ceil).
func force_grain_need(men: int, is_garrison: bool) -> int:
	if men <= 0:
		return 0
	if is_garrison:
		return int(ceili(float(men) * FOOD_GRAIN_PER_MAN_GARRISON))
	return int(ceili(float(men) * FOOD_GRAIN_PER_MAN_MOBILE))


## Men lost to starvation from one stack (10% ceil). Applies to every status.
func starvation_from_stack(stack: Dictionary) -> int:
	var n := int(stack.get("count", 0))
	if n <= 0:
		return 0
	return int(ceili(float(n) * FOOD_ATTRITION_FRACTION))


## Roll a hire offer: 50%/30%/20% → 1/2/3 unique types; each stack 50–200 men.
func roll_sellsword_offer(rng: RandomNumberGenerator) -> Array:
	var roll := rng.randf()
	var n_types := 1
	if roll < 0.50:
		n_types = 1
	elif roll < 0.80:
		n_types = 2
	else:
		n_types = 3
	n_types = mini(n_types, SELLSWORD_UNIT_POOL.size())
	var pool: Array = SELLSWORD_UNIT_POOL.duplicate()
	var ordered: Array = []
	while not pool.is_empty():
		var idx := rng.randi() % pool.size()
		ordered.append(pool[idx])
		pool.remove_at(idx)
	var offer: Array = []
	for i in n_types:
		offer.append({
			"type": int(ordered[i]),
			"count": rng.randi_range(SELLSWORD_STACK_MIN, SELLSWORD_STACK_MAX),
		})
	return offer


func empty_material_stock() -> Dictionary:
	var out := {}
	for k in MATERIAL_KEYS:
		out[k] = 0
	return out


## Flat cargo dict for caravans: weapon keys + material keys, all zeroed.
func empty_caravan_cargo() -> Dictionary:
	var out := empty_weapon_stock()
	for k in MATERIAL_KEYS:
		out[k] = 0
	return out


func sanitize_caravan_cargo(cargo: Dictionary) -> Dictionary:
	var clean := empty_caravan_cargo()
	for k in WEAPON_KEYS:
		clean[k] = maxi(0, int(cargo.get(k, 0)))
	for k in MATERIAL_KEYS:
		clean[k] = maxi(0, int(cargo.get(k, 0)))
	return clean


func caravan_cargo_has_any(cargo: Dictionary) -> bool:
	for k in WEAPON_KEYS:
		if int(cargo.get(k, 0)) > 0:
			return true
	for k in MATERIAL_KEYS:
		if int(cargo.get(k, 0)) > 0:
			return true
	return false


func caravan_cargo_summary(cargo: Dictionary) -> String:
	var bits: PackedStringArray = []
	for k in WEAPON_KEYS:
		var amt := int(cargo.get(k, 0))
		if amt > 0:
			bits.append("%d %s" % [amt, weapon_name(k)])
	for k in MATERIAL_KEYS:
		var amt := int(cargo.get(k, 0))
		if amt > 0:
			bits.append("%d %s" % [amt, material_name(k)])
	if bits.is_empty():
		return "(empty)"
	return ", ".join(bits)


func add_caravan_stocks(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := sanitize_caravan_cargo(a)
	for k in WEAPON_KEYS:
		out[k] = int(out.get(k, 0)) + maxi(0, int(b.get(k, 0)))
	for k in MATERIAL_KEYS:
		out[k] = int(out.get(k, 0)) + maxi(0, int(b.get(k, 0)))
	return out


## Clamp `want` so each key is at most what `available` holds (weapons + materials).
func clamp_caravan_stock(available: Dictionary, want: Dictionary) -> Dictionary:
	var out := empty_caravan_cargo()
	for k in WEAPON_KEYS:
		out[k] = mini(maxi(0, int(want.get(k, 0))), maxi(0, int(available.get(k, 0))))
	for k in MATERIAL_KEYS:
		out[k] = mini(maxi(0, int(want.get(k, 0))), maxi(0, int(available.get(k, 0))))
	return out


func subtract_caravan_stock(stock: Dictionary, need: Dictionary) -> void:
	for k in WEAPON_KEYS:
		stock[k] = maxi(0, int(stock.get(k, 0)) - maxi(0, int(need.get(k, 0))))
	for k in MATERIAL_KEYS:
		stock[k] = maxi(0, int(stock.get(k, 0)) - maxi(0, int(need.get(k, 0))))


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


## Sell payout: half base buy price; +competition bonus when 2+ merchants (floor).
func material_mark_sell_price(key: String, competition: bool) -> int:
	var half := int(floor(float(material_mark_price(key)) * 0.5))
	if not competition:
		return half
	return int(floor(float(half) * (1.0 + MERCHANT_COMPETITION_DISCOUNT)))


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


## Full kit implied by stacks for battle loot (levy + sellswords; peasants → nothing).
func kit_weapons_from_units(units: Array) -> Dictionary:
	var kit := empty_weapon_stock()
	for s in units:
		var costs: Dictionary = weapon_cost_for_type(int(s.get("type", UNIT_TYPE.PEASANT)))
		var n := int(s.get("count", 0))
		if n <= 0:
			continue
		for k in costs:
			kit[k] = int(kit.get(k, 0)) + int(costs[k]) * n
	return kit


## Roll recovered loot from a full dead kit. Separate fraction per weapon; floor.
func roll_loot_from_kit(full_kit: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var loot := empty_weapon_stock()
	for k in WEAPON_KEYS:
		var n := maxi(0, int(full_kit.get(k, 0)))
		if n <= 0:
			continue
		var frac := rng.randf_range(LOOT_FRAC_MIN, LOOT_FRAC_MAX)
		loot[k] = int(floor(float(n) * frac))
	return loot


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


func clamp_ration(level: int) -> int:
	return clampi(level, RATION.NONE, RATION.QUADRUPLE)


func ration_name(level: int) -> String:
	match clamp_ration(level):
		RATION.NONE: return "None"
		RATION.QUARTER: return "Quarter"
		RATION.HALF: return "Half"
		RATION.NORMAL: return "Normal"
		RATION.DOUBLE: return "Double"
		RATION.QUADRUPLE: return "Quadruple"
	return "Normal"


func ration_grain_per_person(level: int) -> float:
	return float(RATION_GRAIN_PER_PERSON.get(clamp_ration(level), 0.5))


func ration_happiness_delta(level: int) -> float:
	return float(RATION_HAPPINESS_DELTA.get(clamp_ration(level), 0.0))


func ration_pop_fraction(level: int) -> float:
	return float(RATION_POP_DELTA.get(clamp_ration(level), 0.0))


## Grain needed to feed `pop` at `level` for one season (ceil).
func ration_grain_need(pop: int, level: int) -> int:
	if pop <= 0:
		return 0
	var rate := ration_grain_per_person(level)
	if rate <= 0.0:
		return 0
	return int(ceili(float(pop) * rate))


## Highest ration ≤ `requested` whose grain need fits in `available` grain.
func affordable_ration(pop: int, requested: int, available: int) -> int:
	var req := clamp_ration(requested)
	var have := maxi(0, available)
	for level in RATION_LEVELS_DESC:
		var lv := int(level)
		if lv > req:
			continue
		if ration_grain_need(pop, lv) <= have:
			return lv
	return RATION.NONE


## Population change from a signed fraction (ceil abs).
## 0-pop + positive growth → RATION_ZERO_POP_BOOTSTRAP.
func population_delta_from_fraction(population: int, frac: float) -> int:
	if frac == 0.0:
		return 0
	if population <= 0:
		return RATION_ZERO_POP_BOOTSTRAP if frac > 0.0 else 0
	var n := int(ceili(float(population) * absf(frac)))
	return n if frac > 0.0 else -n


## Population change for one settlement at an effective ration (ceil abs).
func ration_population_delta(population: int, level: int) -> int:
	return population_delta_from_fraction(population, ration_pop_fraction(level))


func clamp_tax(level: int) -> int:
	return clampi(level, TAX.NONE, TAX.BRUTAL)


func tax_name(level: int) -> String:
	match clamp_tax(level):
		TAX.NONE: return "None"
		TAX.NORMAL: return "Normal"
		TAX.HEAVY: return "Heavy"
		TAX.HARSH: return "Harsh"
		TAX.BRUTAL: return "Brutal"
	return "Normal"


func tax_marks_per_person(level: int) -> int:
	return int(TAX_MARKS_PER_PERSON.get(clamp_tax(level), 1))


func tax_happiness_delta(level: int) -> float:
	return float(TAX_HAPPINESS_DELTA.get(clamp_tax(level), 0.0))


func tax_pop_fraction(level: int) -> float:
	return float(TAX_POP_DELTA.get(clamp_tax(level), 0.0))


## Raw tax marks for one settlement this season at `level` (ceil), before tier %.
func tax_marks_for_settlement(population: int, level: int) -> int:
	var rate := tax_marks_per_person(level)
	if rate <= 0 or population <= 0:
		return 0
	return int(ceili(float(population) * float(rate)))


## Raw tax base + floor(base × tier_bonus_fraction).
func tax_marks_with_tier_bonus(base_marks: int, tier_bonus_fraction: float) -> int:
	var base := maxi(0, base_marks)
	if base <= 0 or tier_bonus_fraction <= 0.0:
		return base
	return base + int(floor(float(base) * tier_bonus_fraction))


func tax_population_delta(population: int, level: int) -> int:
	return population_delta_from_fraction(population, tax_pop_fraction(level))


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
# Also returns `dead_stacks` (by type/owner/source) for loot accounting.
func apply_side_casualties(units: Array, dead_frac: float, wound_frac: float) -> Dictionary:
	var remaining: Array = []
	var wounded_out: Array = []
	var dead_stacks: Array = []
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
		if dead_n > 0:
			add_stack(dead_stacks, make_stack(int(s["type"]), int(s["owner"]), int(s["source"]), dead_n))
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
		"dead_stacks": dead_stacks,
		"dead": dead_total,
		"wounded_men": wound_total,
	}


## After a side is wiped from the map: leftover fighters → dead; wounded + other
## non-fighting leftovers → hostage pool. Mutates `result` dead/wounded_men
## and appends wiped fighters to `dead_stacks`. Returns the hostage pool array.
func account_wiped_side(result: Dictionary, capture_wounded: bool = true) -> Array:
	var hostages: Array = []
	var extra_dead := 0
	var dead_stacks: Array = result.get("dead_stacks", [])
	if dead_stacks == null:
		dead_stacks = []
	else:
		dead_stacks = dead_stacks.duplicate(true)
	for s in result.get("remaining", []):
		var n := int(s.get("count", 0))
		if n <= 0:
			continue
		if is_fighting_stack(s):
			extra_dead += n
			add_stack(dead_stacks, make_stack(int(s["type"]), int(s["owner"]), int(s["source"]), n))
		elif capture_wounded:
			add_stack(hostages, s)
		else:
			extra_dead += n
			add_stack(dead_stacks, make_stack(int(s["type"]), int(s["owner"]), int(s["source"]), n))
	if capture_wounded:
		for s in result.get("wounded", []):
			add_stack(hostages, s)
	else:
		for s in result.get("wounded", []):
			var wn := int(s.get("count", 0))
			if wn <= 0:
				continue
			extra_dead += wn
			add_stack(dead_stacks, make_stack(int(s["type"]), int(s["owner"]), int(s["source"]), wn))
	result["dead"] = int(result.get("dead", 0)) + extra_dead
	result["dead_stacks"] = dead_stacks
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
