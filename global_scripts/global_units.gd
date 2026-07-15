extends Node

## Central catalogue + helpers for military units.
##
## A "unit stack" is a plain Dictionary so it survives RPC serialization:
##     { "type": UNIT_TYPE, "owner": <player_id>, "source": SOURCE, "count": int }
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

# Minimum men that must remain in both the original and the split-off army.
const MIN_SPLIT_MEN := 20


func unit_name(type_: int) -> String:
	return UNIT_STATS.get(type_, {}).get("name", "Unknown")


func unit_strength(type_: int) -> int:
	return UNIT_STATS.get(type_, {}).get("strength", 0)


func source_name(source_: int) -> String:
	match source_:
		SOURCE.LEVY: return "Levy"
		SOURCE.SELLSWORD: return "Sellsword"
	return "Unknown"


func make_stack(type_: int, owner: int, source_: int, count: int) -> Dictionary:
	return {"type": type_, "owner": owner, "source": source_, "count": count}


# Deep copy so callers can mutate freely without touching the registry.
func clone_units(units: Array) -> Array:
	var out: Array = []
	for s in units:
		out.append({"type": s["type"], "owner": s["owner"], "source": s["source"], "count": s["count"]})
	return out


func total_men(units: Array) -> int:
	var total := 0
	for s in units:
		total += int(s["count"])
	return total


func total_strength(units: Array, multiplier: float = 1.0) -> int:
	var total := 0.0
	for s in units:
		total += unit_strength(s["type"]) * int(s["count"])
	return int(round(total * multiplier))


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


# Adds a stack into a units array, folding it into an identical
# (same type + owner + source) stack when one already exists.
func add_stack(units: Array, stack: Dictionary) -> void:
	if int(stack["count"]) <= 0:
		return
	for s in units:
		if s["type"] == stack["type"] and s["owner"] == stack["owner"] and s["source"] == stack["source"]:
			s["count"] = int(s["count"]) + int(stack["count"])
			return
	units.append({"type": stack["type"], "owner": stack["owner"], "source": stack["source"], "count": int(stack["count"])})


# Removes `to_remove` (Array of stacks) from `units` in place, dropping any
# stack whose count reaches zero. Counts are clamped so we never go negative.
func subtract_units(units: Array, to_remove: Array) -> void:
	for r in to_remove:
		var remaining := int(r["count"])
		for s in units:
			if remaining <= 0:
				break
			if s["type"] == r["type"] and s["owner"] == r["owner"] and s["source"] == r["source"]:
				var take: int = min(int(s["count"]), remaining)
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
			int(entry.get("count", 0))
		)
		add_stack(out, stack)
	return out


# Human-readable multi-line breakdown for popups/menus.
func describe_units(units: Array) -> String:
	if units.is_empty():
		return "empty"
	var lines: PackedStringArray = []
	for s in units:
		lines.append("%d %s (%s)" % [int(s["count"]), unit_name(s["type"]), source_name(s["source"])])
	return "\n".join(lines)
