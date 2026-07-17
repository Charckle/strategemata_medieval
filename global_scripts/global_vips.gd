extends Node

## VIP characters (King / Queen / Prince). Plain Dictionaries for RPC safety.
## Authoritative instances live on the map: base_map.vips[vip_id].

enum ROLE { KING, QUEEN, PRINCE }

const BONUS := {
	ROLE.KING: 0.3,
	ROLE.QUEEN: 0.2,
	ROLE.PRINCE: 0.1,
}

const ROLE_NAMES := {
	ROLE.KING: "King",
	ROLE.QUEEN: "Queen",
	ROLE.PRINCE: "Prince",
}


func role_name(role: int) -> String:
	return str(ROLE_NAMES.get(role, "VIP"))


func role_bonus(role: int) -> float:
	return float(BONUS.get(role, 0.0))


func display_name(vip: Dictionary, players: Dictionary) -> String:
	var role := int(vip.get("role", ROLE.KING))
	var owner_id := int(vip.get("owner", -1))
	var pname := "?"
	if players.has(owner_id):
		pname = str(players[owner_id].name_)
	return "%s - %s" % [role_name(role), pname]


func make_vip(id: String, role: int, owner_pid: int, force_id: String) -> Dictionary:
	return {
		"id": id,
		"role": role,
		"owner": owner_pid,
		"force_id": force_id,
		"alive": true,
	}


## Highest bonus among alive VIPs on force_id whose owner == controller_pid.
func buff_for_force(vips: Dictionary, force_id: String, controller_pid: int) -> float:
	if force_id == "" or controller_pid < 0:
		return 0.0
	var best := 0.0
	for vid in vips:
		var v: Dictionary = vips[vid]
		if not bool(v.get("alive", false)):
			continue
		if str(v.get("force_id", "")) != force_id:
			continue
		if int(v.get("owner", -1)) != controller_pid:
			continue
		best = maxf(best, role_bonus(int(v.get("role", -1))))
	return best


## Highest bonus among VIPs owned by victim_pid that sit on enemy_force_id.
func debuff_from_enemy_force(vips: Dictionary, enemy_force_id: String, victim_pid: int) -> float:
	if enemy_force_id == "" or victim_pid < 0:
		return 0.0
	var best := 0.0
	for vid in vips:
		var v: Dictionary = vips[vid]
		if not bool(v.get("alive", false)):
			continue
		if str(v.get("force_id", "")) != enemy_force_id:
			continue
		if int(v.get("owner", -1)) != victim_pid:
			continue
		best = maxf(best, role_bonus(int(v.get("role", -1))))
	return best


## Net fighting-strength multiplier delta: buff - debuff (e.g. 0.3 means ×1.3).
func combat_delta(
	vips: Dictionary,
	my_force_ids: Array,
	my_controller: int,
	enemy_force_ids: Array
) -> float:
	var buff := 0.0
	for fid in my_force_ids:
		buff = maxf(buff, buff_for_force(vips, str(fid), my_controller))
	var debuff := 0.0
	for efid in enemy_force_ids:
		debuff = maxf(debuff, debuff_from_enemy_force(vips, str(efid), my_controller))
	return buff - debuff


func apply_strength_multiplier(base_strength: int, delta: float) -> int:
	if base_strength <= 0:
		return 0
	return maxi(0, int(round(float(base_strength) * (1.0 + delta))))


func vip_ids_on_force(vips: Dictionary, force_id: String) -> Array:
	var out: Array = []
	if force_id == "":
		return out
	for vid in vips:
		var v: Dictionary = vips[vid]
		if bool(v.get("alive", false)) and str(v.get("force_id", "")) == force_id:
			out.append(str(vid))
	return out


func force_has_vip(vips: Dictionary, force_id: String) -> bool:
	return not vip_ids_on_force(vips, force_id).is_empty()
