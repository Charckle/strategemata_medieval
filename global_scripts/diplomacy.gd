extends RefCounted
class_name Diplomacy

## Opinion, wars, move permits, and pending diplomatic messages.
## State lives on the map; this class holds helpers + AI resolve logic.

const MSG_PRAISE := "praise"
const MSG_INSULT := "insult"
const MSG_ALLIANCE_ASK := "alliance_ask"
const MSG_ALLIANCE_BREAK := "alliance_break"
const MSG_WAR_DECLARE := "war_declare"
const MSG_PEACE_ASK := "peace_ask"
const MSG_PERMIT_ASK_TEMP := "permit_ask_temp"
const MSG_PERMIT_ASK_PERM := "permit_ask_perm"
const MSG_PERMIT_REVOKE := "permit_revoke"
const MSG_WAR_ANGRY := "war_angry" ## AI notify after combat auto-war (no slot; instant)

const PERMIT_TEMP := "temp"
const PERMIT_PERM := "perm"


static func pair_key(a: int, b: int) -> String:
	return "%d_%d" % [a, b]


static func war_key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]


static func is_diplomable(base_map: Node, pid: int) -> bool:
	if base_map == null or not base_map.players.has(pid):
		return false
	var p = base_map.players[pid]
	if p == null:
		return false
	if GlobalStuff.is_local_council(p.type):
		return false
	return int(p.status) == int(GlobalStuff.PLAYER_STATUS.PLAYING)


static func diplomable_lords(base_map: Node, except_id: int = -1) -> Array:
	var out: Array = []
	for pid in base_map.players.keys():
		var id := int(pid)
		if id == except_id:
			continue
		if is_diplomable(base_map, id):
			out.append(id)
	out.sort()
	return out


static func ensure_opinion_maps(base_map: Node) -> void:
	if base_map.get("opinions") == null:
		base_map.opinions = {}
	for pid in diplomable_lords(base_map):
		_ensure_viewer(base_map, int(pid))


static func _ensure_viewer(base_map: Node, viewer: int) -> void:
	if not base_map.opinions.has(viewer):
		base_map.opinions[viewer] = {}
	var row: Dictionary = base_map.opinions[viewer]
	for other in diplomable_lords(base_map, viewer):
		if not row.has(other):
			row[other] = GameBalance.DIPLO_OPINION_DEFAULT


static func get_opinion(base_map: Node, viewer: int, target: int) -> int:
	if viewer == target:
		return GameBalance.DIPLO_OPINION_DEFAULT
	ensure_opinion_maps(base_map)
	_ensure_viewer(base_map, viewer)
	return int(base_map.opinions[viewer].get(target, GameBalance.DIPLO_OPINION_DEFAULT))


static func set_opinion(base_map: Node, viewer: int, target: int, value: int) -> void:
	if viewer == target or not is_diplomable(base_map, viewer) or not is_diplomable(base_map, target):
		return
	ensure_opinion_maps(base_map)
	_ensure_viewer(base_map, viewer)
	base_map.opinions[viewer][target] = clampi(
		value, GameBalance.DIPLO_OPINION_MIN, GameBalance.DIPLO_OPINION_MAX
	)


static func adjust_opinion(base_map: Node, viewer: int, target: int, delta: int) -> void:
	set_opinion(base_map, viewer, target, get_opinion(base_map, viewer, target) + delta)


static func are_at_war(base_map: Node, a: int, b: int) -> bool:
	if a == b:
		return false
	var wars: Dictionary = base_map.wars if base_map.get("wars") != null else {}
	return wars.has(war_key(a, b))


static func war_started_by(base_map: Node, a: int, b: int) -> int:
	var wars: Dictionary = base_map.wars if base_map.get("wars") != null else {}
	var w = wars.get(war_key(a, b), {})
	if w is Dictionary:
		return int(w.get("started_by", -1))
	return -1


static func has_move_permit(base_map: Node, mover: int, land_owner: int) -> bool:
	if mover == land_owner:
		return true
	var permits: Dictionary = base_map.move_permits if base_map.get("move_permits") != null else {}
	var key := pair_key(mover, land_owner)
	if not permits.has(key):
		return false
	var p: Dictionary = permits[key]
	var kind := str(p.get("kind", ""))
	if kind == PERMIT_PERM:
		return true
	if kind == PERMIT_TEMP:
		return int(p.get("expires_turn", -1)) > int(base_map.turn)
	return false


static func can_send_message(base_map: Node, from_id: int, to_id: int) -> bool:
	if from_id == to_id:
		return false
	if not is_diplomable(base_map, from_id) or not is_diplomable(base_map, to_id):
		return false
	var sent: Dictionary = base_map.diplo_sent_turn if base_map.get("diplo_sent_turn") != null else {}
	return int(sent.get(pair_key(from_id, to_id), -999999)) != int(base_map.turn)


static func mark_message_sent(base_map: Node, from_id: int, to_id: int) -> void:
	if base_map.get("diplo_sent_turn") == null:
		base_map.diplo_sent_turn = {}
	base_map.diplo_sent_turn[pair_key(from_id, to_id)] = int(base_map.turn)


static func pending_message(base_map: Node, from_id: int, to_id: int) -> Dictionary:
	var msgs: Dictionary = base_map.diplo_messages if base_map.get("diplo_messages") != null else {}
	var m = msgs.get(pair_key(from_id, to_id), {})
	return m if m is Dictionary else {}


static func pending_to(base_map: Node, to_id: int) -> Array:
	var out: Array = []
	var msgs: Dictionary = base_map.diplo_messages if base_map.get("diplo_messages") != null else {}
	for k in msgs.keys():
		var m: Dictionary = msgs[k]
		if int(m.get("to", -1)) == to_id:
			out.append(m)
	return out


static func clear_pending(base_map: Node, from_id: int, to_id: int) -> void:
	if base_map.get("diplo_messages") == null:
		return
	base_map.diplo_messages.erase(pair_key(from_id, to_id))


static func lord_military_strength(base_map: Node, pid: int) -> int:
	var total := 0
	if base_map.get("forces") == null:
		return 0
	for fid in base_map.forces.keys():
		if int(base_map.get_force_controller(str(fid))) != pid:
			continue
		var units: Array = base_map.forces[fid].get("units", [])
		total += GlobalUnits.fighting_strength(units)
	return total


static func is_outnumbered(base_map: Node, pid: int, by_pid: int) -> bool:
	## True when `by_pid` strength >= `pid` strength (1.0×).
	return lord_military_strength(base_map, by_pid) >= lord_military_strength(base_map, pid)


static func ai_should_accept_peace(base_map: Node, ai_pid: int, other_pid: int) -> bool:
	if not are_at_war(base_map, ai_pid, other_pid):
		return false
	return is_outnumbered(base_map, ai_pid, other_pid)


static func ai_should_accept_alliance(base_map: Node, ai_pid: int, other_pid: int) -> bool:
	if are_at_war(base_map, ai_pid, other_pid):
		return false
	return get_opinion(base_map, ai_pid, other_pid) > GameBalance.DIPLO_ALLIANCE_ACCEPT_OPINION


static func ai_should_grant_permit(base_map: Node, ai_pid: int, other_pid: int, permanent: bool) -> bool:
	if are_at_war(base_map, ai_pid, other_pid):
		return false
	var op := get_opinion(base_map, ai_pid, other_pid)
	if permanent:
		return op >= GameBalance.DIPLO_PERMIT_PERM_OPINION
	return op >= GameBalance.DIPLO_PERMIT_TEMP_OPINION


static func conquest_excludes_holder(base_map: Node, ai_pid: int, holder_id: int) -> bool:
	if not is_diplomable(base_map, holder_id):
		return false
	if base_map.are_allied(ai_pid, holder_id):
		return true
	return get_opinion(base_map, ai_pid, holder_id) > GameBalance.DIPLO_CONQUEST_EXCLUDE_OPINION


static func province_land_owner(prov: Node) -> int:
	if prov == null:
		return -1
	if prov.get("dejure") != null and int(prov.dejure) >= 0:
		return int(prov.dejure)
	if prov.get("player_owner") != null:
		return int(prov.player_owner)
	return -1


static func msg_label(kind: String) -> String:
	match kind:
		MSG_PRAISE: return "Praise"
		MSG_INSULT: return "Insult"
		MSG_ALLIANCE_ASK: return "Alliance offer"
		MSG_ALLIANCE_BREAK: return "Alliance broken"
		MSG_WAR_DECLARE: return "War declared"
		MSG_WAR_ANGRY: return "War declared"
		MSG_PEACE_ASK: return "Peace offer"
		MSG_PERMIT_ASK_TEMP: return "Passage permit (4 seasons)"
		MSG_PERMIT_ASK_PERM: return "Passage permit (permanent)"
		MSG_PERMIT_REVOKE: return "Permit revoked"
	return "Diplomacy"


static func stance_text(base_map: Node, a: int, b: int) -> String:
	if base_map.are_allied(a, b):
		return "Allied"
	if are_at_war(base_map, a, b):
		return "At war"
	return "Neutral"
