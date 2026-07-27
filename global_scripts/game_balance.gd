class_name GameBalance
extends RefCounted

## Tunable economy + military-economy balance. Edit numbers here, then run the game.
## GlobalUnits re-exports these so the rest of the code keeps working.
##
## Ration grain costs are derived from POP_GRAIN_PER_PERSON (Normal = 1×).
## Levels: None 0×, Quarter 0.25×, Half 0.5×, Normal 1×, Double 2×, Quadruple 4×.
##
## Tax / ration effect tables use int keys matching GlobalUnits enums:
##   RATION: 0 NONE … 5 QUADRUPLE
##   TAX:    0 NONE … 4 BRUTAL

# =============================================================================
# Civilian eating (per person / season)
# =============================================================================
## Grain one person eats at Normal rations. Other ration levels scale from this.
const POP_GRAIN_PER_PERSON := 0.1

# =============================================================================
# Army eating (per man / season) — absolute, not tied to pop base
# =============================================================================
const FOOD_GRAIN_PER_MAN_MOBILE := 0.25
const FOOD_GRAIN_PER_MAN_GARRISON := 0.1
## After one warning season without enough grain, this fraction of each stack dies (ceil).
const FOOD_ATTRITION_FRACTION := 0.10

# =============================================================================
# Ration effects (happiness / population)
# =============================================================================
const RATION_HAPPINESS_DELTA := {
	0: -15.0,
	1: -8.0,
	2: -4.0,
	3: 4.0,
	4: 8.0,
	5: 12.0,
}
## Population change fraction per season (ceil abs).
const RATION_POP_DELTA := {
	0: -0.15,
	1: -0.08,
	2: -0.04,
	3: 0.04,
	4: 0.08,
	5: 0.12,
}
## First positive growth from an empty (0-pop) settlement.
const RATION_ZERO_POP_BOOTSTRAP := 10

# =============================================================================
# Holding taxes (marks into settlement coffers; collect with army)
# =============================================================================
## Movement points to collect tax from a settlement.
const TAX_COLLECT_MP := 1
## Marks deposited into each settlement coffer per person (ceil).
const TAX_MARKS_PER_PERSON := {
	0: 0,
	1: 0.1,
	2: 0.4,
	3: 1,
	4: 2,
}
const TAX_HAPPINESS_DELTA := {
	0: 10.0,
	1: 5.0,
	2: -10.0,
	3: -20.0,
	4: -40.0,
}
const TAX_POP_DELTA := {
	0: 0.05,
	1: 0.025,
	2: -0.025,
	3: -0.05,
	4: -0.10,
}

# =============================================================================
# Merchant prices
# =============================================================================
## Placeholder merchant prices (marks each).
const MATERIAL_MARK_PRICES := {
	"grain": 2,
	"wood": 2,
	"stone": 4,
	"iron": 3,
}
## Weapon buy price = matching unit strength × this.
const WEAPON_PRICE_STRENGTH_MULT := 4
## When 2+ merchants share a province, buy prices drop by this fraction.
const MERCHANT_COMPETITION_DISCOUNT := 0.15

# =============================================================================
# Military economy — arm / levy / sellswords / upkeep / ships / wage loot
# =============================================================================
## Marks to arm one peasant levy into a non-knight kit type.
const ARM_TRAIN_MARKS := 1
## Marks to arm one peasant levy into knights.
const ARM_TRAIN_MARKS_KNIGHT := 3

## Hire price = unit strength × count × this.
const SELLSWORD_PRICE_STRENGTH_MULT := 3
const SELLSWORD_STACK_MIN := 50
const SELLSWORD_STACK_MAX := 200
## Minimum men in one hire action (unless fewer remain at the camp).
const SELLSWORD_HIRE_MIN := 20
## Discount when hiring the untouched full original offer in one go (ceil of price × (1 − this)).
const SELLSWORD_FULL_OFFER_DISCOUNT := 0.20

## Seasonal upkeep (marks per man). Player total is ceiled.
## Levy peasants: free (0) — they are unpaid levies until armed.
const UPKEEP_LEVY_PEASANT := 0.0
const UPKEEP_LEVY_KNIGHT := 1.0
const UPKEEP_LEVY_OTHER := 1.0
const UPKEEP_SELLSWORD_KNIGHT := 3.0
const UPKEEP_SELLSWORD_OTHER := 3.0
## Flat marks per transport ship per season (unpaid ships not struck, v1).
const UPKEEP_TRANSPORT_SHIP := 20
## Missed pays: strike 1 warn, 2 sellswords leave, 3+ levy desertion.
const UPKEEP_STRIKES_MAX := 3
const UPKEEP_CLEAR_PAYS := 10
## Fraction of each unpaid levy stack that deserts (ceil).
const UPKEEP_DESERT_FRACTION := 0.10
## Attacker wage loot: one roll per battle × next-season upkeep of wiped side.
const WAGE_CAPTURE_MIN := 0.60
const WAGE_CAPTURE_MAX := 0.80

## Secret early-game AI lord boost (hidden in normal UI; Admin / AI Debug show real).
## Master gate (session): GlobalStuff.ai_cheats_enabled — default ON; Admin toggles.
## Active while AI lord has ≤ this many de jure holdings (ends at holdings_max+1).
const AI_CHEATS_DEFAULT := true
const AI_EARLY_HOLDINGS_MAX := 2
const AI_EARLY_UPKEEP_MULT := 0.5
const AI_EARLY_WALLET_INCOME_MULT := 1.5

## Levy recruitment: max fraction of season-start province population.
const LEVY_MAX_FRACTION := 0.80
## First this fraction of season-start pop can be levied with no happiness hit.
const LEVY_HAPPINESS_FREE_FRACTION := 0.10
## Happiness lost per percent levied above the free band (at 80% ≈ −35).
const LEVY_HAPPINESS_PER_PERCENT := 0.5

const TRANSPORT_SHIP_CAPACITY := 100
const TRANSPORT_SHIP_MP := 20
const TRANSPORT_SHIP_WOOD_COST := 300
const TRANSPORT_SHIP_MARKS_COST := 500
## Army embarks onto an adjacent own fleet (army spends + fleet spends).
const TRANSPORT_EMBARK_ARMY_MP := 4
const TRANSPORT_EMBARK_FLEET_MP := 3
## Disembark / landing merge / landing attack from a fleet onto shore.
const TRANSPORT_LANDING_MP := 8

# =============================================================================
# Fields / agriculture
# =============================================================================
const GRAIN_SEED_PER_FIELD := 5
const GRAIN_YIELD_PER_FIELD := 200
## People per grain field in winter (sow) and autumn (harvest).
const PEOPLE_PER_GRAIN_FIELD_PEAK := 40
## People per grain field in spring and summer (tend).
const PEOPLE_PER_GRAIN_FIELD_TEND := 20
const PEOPLE_PER_HORSE_FIELD := 10
const HORSES_PER_FIELD := 20
const FOAL_EFF_HIGH := 0.75
const FOAL_EFF_MID := 0.25
const FOAL_HIGH_MIN := 4
const FOAL_HIGH_MAX := 8
const FOAL_MID_MIN := 1
const FOAL_MID_MAX := 3

# =============================================================================
# Starting stock (per province owner at map start)
# =============================================================================
const PROVINCE_START_GRAIN := 1000
const PROVINCE_START_WOOD := 200
const PROVINCE_START_IRON := 200
const PROVINCE_START_MARKS := 400
const PROVINCE_START_MACES := 50
const PROVINCE_START_PIKES := 50
const PROVINCE_START_BOWS := 50
## Legacy single-grain seed kit (prefer PROVINCE_START_GRAIN).
const STARTING_GRAIN := 40

# =============================================================================
# Economy buildings
# Subtype ints: 0 woodcutter, 1 iron mine, 3 silver mine, 4 stone quarry, 5 blacksmith.
# Arrays are [Small, Medium, Big]: build/upgrade cost or worker cap at that stage.
# =============================================================================
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
	5: [100, 250, 350],
}
## Output per assigned worker per season.
const ECONOMY_WOOD_PER_WORKER := 1
const ECONOMY_STONE_PER_WORKER := 1
const ECONOMY_IRON_PER_WORKER := 1
const ECONOMY_SILVER_MARKS_PER_WORKER := 2

# =============================================================================
# Settlement marks / population
# =============================================================================
## Tier index: 0=Small, 1=Medium, 2=Big, 3=Very Big (bonus % of tax base).
const SETTLEMENT_TIER_MARKS_BONUS := [0.0, 0.10, 0.20, 0.30]
## Population ceilings for Small / Medium / Big (above last → Very Big).
const TOWN_TIER_POP_MAX := [300, 600, 900]
const VILLAGE_TIER_POP_MAX := [20, 60, 120]
## Soft population caps (growth may overshoot; overflow applies pressure next tick).
const TOWN_POPULATION_CAP := 2000
const VILLAGE_POPULATION_CAP := 300
## When over cap: at least −this fraction (ceil), or worse ration/tax delta if larger.
const SETTLEMENT_OVERFLOW_SHRINK_FRAC := 0.10
## Random jitter added to over-cap delta (inclusive), seeded per season.
const TOWN_OVERFLOW_JITTER := 50
const VILLAGE_OVERFLOW_JITTER := 10

# =============================================================================
# Castle construction (CASTLE_TYPE 0..5)
# Materials paid upfront into the worksite; 1 labor = 1 work / season.
# =============================================================================
const CASTLE_COST_WOOD := [500, 1000, 1000, 1000, 1500, 2000]
const CASTLE_COST_STONE := [0, 0, 1000, 2500, 3200, 4500]
const CASTLE_WORK := [500, 1000, 2500, 3500, 4500, 6000]
## Holding-wide marks bonus on Σ settlement base (CASTLE_TYPE 0..5).
## Mid-upgrade uses half the old level; empty-build / dismantle = 0.
const CASTLE_HOLDING_MARKS_BONUS := [0.10, 0.20, 0.30, 0.50, 0.80, 1.00]

# =============================================================================
# Blacksmith forge (labor + materials per finished weapon)
# =============================================================================
const BLACKSMITH_CRAFTABLE := ["maces", "pikes", "bows", "swords", "crossbows", "armour"]
const BLACKSMITH_LABOR := {
	"bows": 1,
	"maces": 2,
	"pikes": 2,
	"swords": 2,
	"crossbows": 3,
	"armour": 3,
}
const BLACKSMITH_RECIPES := {
	"bows": {"wood": 10},
	"pikes": {"wood": 3, "iron": 7},
	"armour": {"iron": 15},
	"maces": {"wood": 3, "iron": 3},
	"swords": {"wood": 3, "iron": 10},
	"crossbows": {"wood": 10, "iron": 10},
}


# === Diplomacy ==============================================================

const DIPLO_OPINION_MIN := 0
const DIPLO_OPINION_MAX := 100
const DIPLO_OPINION_DEFAULT := 50
const DIPLO_PRAISE_DELTA := 10
const DIPLO_INSULT_DELTA := -15
const DIPLO_TRESPASS_DELTA := -20
const DIPLO_ALLIANCE_ACCEPT_OPINION := 90 ## AI accepts if opinion strictly greater
const DIPLO_CONQUEST_EXCLUDE_OPINION := 80 ## AI skips holder provinces if opinion > this
const DIPLO_PERMIT_TEMP_OPINION := 70
const DIPLO_PERMIT_PERM_OPINION := 90
const DIPLO_PERMIT_TEMP_SEASONS := 4


## Grain per person at a ration level (0–5). Built from POP_GRAIN_PER_PERSON.
static func ration_grain_per_person(level: int) -> float:
	match clampi(level, 0, 5):
		0:
			return 0.0
		1:
			return POP_GRAIN_PER_PERSON * 0.25
		2:
			return POP_GRAIN_PER_PERSON * 0.5
		3:
			return POP_GRAIN_PER_PERSON
		4:
			return POP_GRAIN_PER_PERSON * 2.0
		5:
			return POP_GRAIN_PER_PERSON * 4.0
		_:
			return POP_GRAIN_PER_PERSON


## Full table for callers that want a Dictionary (keys = RATION enum ints).
static func ration_grain_table() -> Dictionary:
	return {
		0: ration_grain_per_person(0),
		1: ration_grain_per_person(1),
		2: ration_grain_per_person(2),
		3: ration_grain_per_person(3),
		4: ration_grain_per_person(4),
		5: ration_grain_per_person(5),
	}
