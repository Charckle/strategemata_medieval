extends RefCounted
class_name Tourney

## Overworld tourney orchestration helpers. State lives on OBaseMap.active_tourney.

const PHASE_NONE := ""
const PHASE_INVITING := "inviting"
const PHASE_PLAYING := "playing"

const INVITE_PENDING := "pending"
const INVITE_ACCEPTED := "accepted"
const INVITE_REFUSED := "refused"

## Temporary AI cheat: entry fee is counted in the pot but not deducted (gated by GlobalStuff.ai_cheats_enabled).
const AI_TOURNEY_FREE_ENTRY_CHEAT := true


static func host_cost(t: int) -> int:
	match clampi(t, 0, 2):
		0:
			return GameBalance.TOURNEY_HOST_COST_BORDER
		1:
			return GameBalance.TOURNEY_HOST_COST_LORDS
		_:
			return GameBalance.TOURNEY_HOST_COST_CROWN


static func entry_fee(t: int) -> int:
	match clampi(t, 0, 2):
		0:
			return GameBalance.TOURNEY_ENTRY_BORDER
		1:
			return GameBalance.TOURNEY_ENTRY_LORDS
		_:
			return GameBalance.TOURNEY_ENTRY_CROWN


static func is_active(base_map: Node) -> bool:
	var t = base_map.get("active_tourney")
	return t is Dictionary and not t.is_empty() and str(t.get("phase", "")) != PHASE_NONE


static func is_playing(base_map: Node) -> bool:
	var t = base_map.get("active_tourney")
	return t is Dictionary and str(t.get("phase", "")) == PHASE_PLAYING


static func is_inviting(base_map: Node) -> bool:
	var t = base_map.get("active_tourney")
	return t is Dictionary and str(t.get("phase", "")) == PHASE_INVITING


static func get_roster(base_map: Node, pid: int) -> Array:
	if not base_map.players.has(pid):
		return []
	var gd: Dictionary = base_map.players[pid].game_data
	var roster = gd.get("tourney_knights", [])
	return roster if roster is Array else []


static func set_roster(base_map: Node, pid: int, roster: Array) -> void:
	if not base_map.players.has(pid):
		return
	base_map.players[pid].game_data["tourney_knights"] = roster


static func add_knight_to_roster(base_map: Node, pid: int, knight: Dictionary) -> void:
	if pid < 0 or not base_map.players.has(pid):
		return
	if GlobalStuff.is_ai_lord(base_map.players[pid].type):
		return
	var owned := int(knight.get("owner_pid", pid))
	if owned != pid:
		return
	if bool(knight.get("is_npc_knight", false)):
		return
	var roster := get_roster(base_map, pid)
	var kname := str(knight.get("name", ""))
	# Entering a tourney saves the knight; winning used to save again — skip dupes.
	if kname != "":
		for existing in roster:
			if existing is Dictionary and str(existing.get("name", "")) == kname:
				return
	var copy := JoustKnight.duplicate_knight(knight)
	copy["owner_pid"] = pid
	copy["is_npc_knight"] = false
	roster.append(copy)
	set_roster(base_map, pid, roster)


static func stamp_knight_owner(knight: Dictionary, pid: int, is_npc: bool = false) -> Dictionary:
	knight["owner_pid"] = pid
	knight["is_npc_knight"] = is_npc
	return knight


static func remove_knight_from_roster(base_map: Node, pid: int, index: int) -> void:
	var roster := get_roster(base_map, pid)
	if index < 0 or index >= roster.size():
		return
	roster.remove_at(index)
	set_roster(base_map, pid, roster)


static func owned_province_names(base_map: Node, pid: int) -> Array:
	var names: Array = []
	if base_map.get("provinces") == null:
		return names
	for prov in base_map.provinces.get_children():
		if int(prov.dejure) == pid:
			names.append(str(prov.p_name))
	return names


static func all_province_names(base_map: Node) -> Array:
	var names: Array = []
	if base_map.get("provinces") == null:
		return names
	for prov in base_map.provinces.get_children():
		names.append(str(prov.p_name))
	return names


static func ai_can_afford_entry(base_map: Node, ai_pid: int, fee: int) -> bool:
	## Temporary cheat: always true while AI tourney free-entry cheat is on.
	if AI_TOURNEY_FREE_ENTRY_CHEAT and bool(GlobalStuff.ai_cheats_enabled):
		return true
	if not base_map.players.has(ai_pid):
		return false
	return int(base_map.players[ai_pid].game_data.get("marks", 0)) >= fee


static func ai_should_accept(base_map: Node, ai_pid: int, host_id: int) -> bool:
	if Diplomacy.are_at_war(base_map, ai_pid, host_id):
		return false
	if Diplomacy.get_opinion(base_map, ai_pid, host_id) < GameBalance.TOURNEY_AI_MIN_OPINION:
		return false
	var ttype := int(base_map.active_tourney.get("type", 0))
	if not ai_can_afford_entry(base_map, ai_pid, entry_fee(ttype)):
		return false
	return true


static func make_invite_state(host_id: int, ttype: int, host_knight: Dictionary) -> Dictionary:
	return {
		"id": "tourney_%d_%d" % [Time.get_ticks_msec(), host_id],
		"phase": PHASE_INVITING,
		"type": ttype,
		"host_id": host_id,
		"host_cost": host_cost(ttype),
		"entry_fee": entry_fee(ttype),
		"prize_pool": host_cost(ttype),
		"invites": {},
		"entrants": [
			{
				"pid": host_id,
				"knight": JoustKnight.duplicate_knight(host_knight),
				"is_npc": false,
			}
		],
		"control_mode": {}, # pid -> "watch"|"manage"
	}


static func heraldry_for_player(base_map: Node, pid: int) -> Dictionary:
	if base_map == null or not base_map.players.has(pid):
		return Heraldry.random_heraldry()
	var p = base_map.players[pid]
	var h = p.heraldry if p.get("heraldry") != null else {}
	if h is Dictionary and Heraldry.is_set(h):
		return Heraldry.normalize(h)
	return Heraldry.default_heraldry()


static func stamp_entrant_heraldry(base_map: Node, entrant: Dictionary) -> void:
	if bool(entrant.get("is_npc", false)) or int(entrant.get("pid", -1)) < 0:
		if not (entrant.get("heraldry") is Dictionary and Heraldry.is_set(entrant.get("heraldry", {}))):
			entrant["heraldry"] = Heraldry.random_heraldry()
	else:
		entrant["heraldry"] = heraldry_for_player(base_map, int(entrant.get("pid", -1)))


static func texture_for_entrant(entrant: Dictionary, size: int = 28) -> Texture2D:
	var h = entrant.get("heraldry", {})
	if h is Dictionary and Heraldry.is_set(h):
		return Heraldry.make_texture(Heraldry.normalize(h), size)
	return Heraldry.make_texture(Heraldry.default_heraldry(), size)
