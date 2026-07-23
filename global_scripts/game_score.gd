extends RefCounted
class_name GameScore

## Campaign win/loss helpers + yearly score history samples.

const LANDLESS_SEASONS_TO_LOSE := 16

const METRICS := [
	"population",
	"men",
	"strength",
	"provinces",
	"gold",
	"grain",
]

const METRIC_LABELS := {
	"population": "Population",
	"men": "Men",
	"strength": "Strength",
	"provinces": "Provinces",
	"gold": "Gold",
	"grain": "Grain",
}


static func is_campaign_lord(p) -> bool:
	if p == null:
		return false
	return not GlobalStuff.is_local_council(p.type)


static func is_playing_lord(p) -> bool:
	return is_campaign_lord(p) and int(p.status) == int(GlobalStuff.PLAYER_STATUS.PLAYING)


static func count_campaign_lords(base_map: Node) -> int:
	var n := 0
	if base_map == null or base_map.get("players") == null:
		return 0
	for pid in base_map.players.keys():
		if is_campaign_lord(base_map.players[pid]):
			n += 1
	return n


static func dejure_count(base_map: Node, pid: int) -> int:
	return PlayerLadder._dejure_count(base_map, pid)


static func men_count(base_map: Node, pid: int) -> int:
	var forces = base_map.get("forces")
	if forces == null:
		return 0
	var total := 0
	for fid in forces.keys():
		var units: Array = forces[fid].get("units", [])
		total += GlobalUnits.men_of_owner(units, pid)
	return total


static func strength_count(base_map: Node, pid: int) -> int:
	return PlayerLadder._fighting(base_map, pid)


static func population_count(base_map: Node, pid: int) -> int:
	if base_map == null or not base_map.players.has(pid):
		return 0
	return int(base_map.players[pid].game_data.get("people", 0))


static func gold_count(base_map: Node, pid: int) -> int:
	return PlayerLadder._marks(base_map, pid)


static func grain_count(base_map: Node, pid: int) -> int:
	return PlayerLadder._grain(base_map, pid)


static func units_by_type(base_map: Node, pid: int) -> Dictionary:
	var out := {}
	for t in GlobalUnits.UNIT_TYPE.values():
		out[str(int(t))] = 0
	var forces = base_map.get("forces")
	if forces == null:
		return out
	for fid in forces.keys():
		for s in forces[fid].get("units", []):
			if int(s.get("owner", -1)) != pid:
				continue
			var key := str(int(s.get("type", GlobalUnits.UNIT_TYPE.PEASANT)))
			out[key] = int(out.get(key, 0)) + int(s.get("count", 0))
	return out


static func sample_player(base_map: Node, pid: int) -> Dictionary:
	return {
		"population": population_count(base_map, pid),
		"men": men_count(base_map, pid),
		"strength": strength_count(base_map, pid),
		"provinces": dejure_count(base_map, pid),
		"gold": gold_count(base_map, pid),
		"grain": grain_count(base_map, pid),
		"units": units_by_type(base_map, pid),
	}


## Snapshot all campaign lords (including defeated, so graphs go to zero).
static func sample_year(base_map: Node, year: int) -> Dictionary:
	var players_snap := {}
	if base_map != null and base_map.get("players") != null:
		for pid in base_map.players.keys():
			var p = base_map.players[pid]
			if not is_campaign_lord(p):
				continue
			players_snap[str(int(pid))] = sample_player(base_map, int(pid))
	return {"year": year, "players": players_snap}


static func player_meta(base_map: Node) -> Dictionary:
	var out := {}
	if base_map == null or base_map.get("players") == null:
		return out
	for pid in base_map.players.keys():
		var p = base_map.players[pid]
		if not is_campaign_lord(p):
			continue
		var col: Dictionary = p.color if p.get("color") != null else {}
		out[str(int(pid))] = {
			"name": str(p.name_),
			"status": int(p.status),
			"color": {
				"red": int(col.get("red", 128)),
				"green": int(col.get("green", 128)),
				"blue": int(col.get("blue", 128)),
			},
		}
	return out


static func is_wipeout(base_map: Node, pid: int) -> bool:
	return dejure_count(base_map, pid) <= 0 and men_count(base_map, pid) <= 0


static func is_landless(base_map: Node, pid: int) -> bool:
	return dejure_count(base_map, pid) <= 0


## Non-allied PLAYING campaign lords other than `pid`.
static func rival_lords(base_map: Node, pid: int) -> Array:
	var out: Array = []
	if base_map == null or not base_map.players.has(pid):
		return out
	for other_id in base_map.players.keys():
		var oid := int(other_id)
		if oid == pid:
			continue
		var op = base_map.players[oid]
		if not is_playing_lord(op):
			continue
		if base_map.has_method("are_allied") and base_map.are_allied(pid, oid):
			continue
		out.append(oid)
	out.sort()
	return out


static func has_won(base_map: Node, pid: int) -> bool:
	if base_map == null or not base_map.players.has(pid):
		return false
	if not is_playing_lord(base_map.players[pid]):
		return false
	return rival_lords(base_map, pid).is_empty()


## All PLAYING campaign lords who currently satisfy the win condition.
static func current_winners(base_map: Node) -> Array:
	var out: Array = []
	if base_map == null or base_map.get("players") == null:
		return out
	for pid in base_map.players.keys():
		if has_won(base_map, int(pid)):
			out.append(int(pid))
	out.sort()
	return out


static func color_from_meta(meta: Dictionary) -> Color:
	var c: Dictionary = meta.get("color", {})
	return Color(
		float(c.get("red", 128)) / 255.0,
		float(c.get("green", 128)) / 255.0,
		float(c.get("blue", 128)) / 255.0
	)
