extends RefCounted
class_name PlayerLadder

## Shared player standings for UI + AI.
## Raw totals always available; ranks use competition ranking (ties share, next skips).

const METRICS := ["marks", "fighting", "grain", "dejure", "defacto"]


## Full ladder snapshot from a live base map.
## Returns:
##   {
##     "entries": Array[{ pid, name, marks, fighting, grain, dejure, defacto, ranks }],
##     "by_pid": Dictionary[pid -> entry],
##   }
static func compute(base_map: Node) -> Dictionary:
	var empty := {"entries": [], "by_pid": {}}
	if base_map == null or base_map.get("players") == null:
		return empty
	var players: Dictionary = base_map.players
	var entries: Array = []
	for pid in players.keys():
		var p = players[pid]
		if int(p.status) != GlobalStuff.PLAYER_STATUS.PLAYING:
			continue
		var id := int(pid)
		entries.append({
			"pid": id,
			"name": str(p.name_),
			"marks": _marks(base_map, id),
			"fighting": _fighting(base_map, id),
			"grain": _grain(base_map, id),
			"dejure": _dejure_count(base_map, id),
			"defacto": _defacto_count(base_map, id),
			"ranks": {},
		})
	_assign_ranks(entries)
	var by_pid := {}
	for e in entries:
		by_pid[int(e["pid"])] = e
	return {"entries": entries, "by_pid": by_pid}


## Competition ranks for one metric (1-based; ties share, next skips).
static func ranks_for(entries: Array, metric: String) -> Dictionary:
	var out := {}
	if entries.is_empty() or not METRICS.has(metric):
		return out
	var order: Array = entries.duplicate()
	order.sort_custom(func(a, b):
		var sa := int(a.get(metric, 0))
		var sb := int(b.get(metric, 0))
		if sa != sb:
			return sa > sb
		return int(a.get("pid", 0)) < int(b.get("pid", 0))
	)
	var rank := 1
	for i in range(order.size()):
		if i > 0 and int(order[i].get(metric, 0)) < int(order[i - 1].get(metric, 0)):
			rank = i + 1
		out[int(order[i]["pid"])] = rank
	return out


static func rank_of(ladder: Dictionary, pid: int, metric: String) -> int:
	var by_pid: Dictionary = ladder.get("by_pid", {})
	if not by_pid.has(pid):
		return 0
	var ranks: Dictionary = by_pid[pid].get("ranks", {})
	return int(ranks.get(metric, 0))


static func raw_of(ladder: Dictionary, pid: int, metric: String) -> int:
	var by_pid: Dictionary = ladder.get("by_pid", {})
	if not by_pid.has(pid):
		return 0
	return int(by_pid[pid].get(metric, 0))


static func _assign_ranks(entries: Array) -> void:
	for metric in METRICS:
		var ranked := ranks_for(entries, metric)
		for e in entries:
			e["ranks"][metric] = int(ranked.get(int(e["pid"]), 0))


static func _marks(base_map: Node, pid: int) -> int:
	if not base_map.players.has(pid):
		return 0
	return int(base_map.players[pid].game_data.get("marks", 0))


static func _fighting(base_map: Node, pid: int) -> int:
	var forces = base_map.get("forces")
	if forces == null:
		return 0
	var total := 0
	for fid in forces.keys():
		var units: Array = forces[fid].get("units", [])
		if units.is_empty():
			continue
		total += GlobalUnits.fighting_strength(GlobalUnits.units_of_owner(units, pid))
	return total


static func _grain(base_map: Node, pid: int) -> int:
	var provinces = base_map.get("provinces")
	if provinces == null:
		return 0
	var total := 0
	for prov in provinces.get_children():
		if prov.has_method("get_player_grain"):
			total += int(prov.get_player_grain(pid))
	return total


static func _dejure_count(base_map: Node, pid: int) -> int:
	var provinces = base_map.get("provinces")
	if provinces == null:
		return 0
	var n := 0
	for prov in provinces.get_children():
		if prov.get("dejure") != null and int(prov.dejure) == pid:
			n += 1
	return n


static func _defacto_count(base_map: Node, pid: int) -> int:
	var provinces = base_map.get("provinces")
	if provinces == null:
		return 0
	var n := 0
	for prov in provinces.get_children():
		var df = prov.get("defacto")
		if df == null:
			continue
		# Contested / empty defacto does not count for anyone.
		if int(df) < 0:
			continue
		if int(df) == pid:
			n += 1
	return n
