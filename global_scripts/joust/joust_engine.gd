extends RefCounted
class_name JoustEngine

## Resolves a full match between two knight Dictionaries.
## Optional player_decision_cb(knight, ctx) -> decision dict for managed passes.

var rules: Dictionary = {}
var player_knight_name: String = ""
var pending_player_decision: Dictionary = {}


func _init(p_rules: Dictionary = {}) -> void:
	rules = p_rules


func run_match(knight_a: Dictionary, knight_b: Dictionary) -> Dictionary:
	JoustKnight.reset_for_match(knight_a)
	JoustKnight.reset_for_match(knight_b)
	var all_events: Array = []
	var pass_num := 0
	var num_passes := int(rules.get("num_passes", 3))

	while pass_num < num_passes:
		pass_num += 1
		var score_a_before := int(knight_a.get("score", 0))
		var score_b_before := int(knight_b.get("score", 0))
		var events := _resolve_pass(knight_a, knight_b, pass_num)
		all_events.append(events)

		if bool(rules.get("lance_tip_clash_voids_round", false)):
			var voided := false
			for e in events:
				if e is Dictionary and str(e.get("type", "")) == "lance_tip_clash":
					voided = true
					break
			if voided:
				knight_a["score"] = score_a_before
				knight_b["score"] = score_b_before
				pass_num -= 1
				continue

		if bool(knight_a.get("disqualified", false)) or bool(knight_b.get("disqualified", false)):
			break
		if not JoustKnight.can_fight(knight_a) or not JoustKnight.can_fight(knight_b):
			break

		var unhorsed_end := false
		if bool(rules.get("unhorse_wins_match", false)):
			for e in events:
				if e is Dictionary and str(e.get("type", "")) == "fall" and int(e.get("fall_type", -1)) == JoustTypes.FallType.UNHORSED:
					unhorsed_end = true
					break
		if unhorsed_end:
			break

	var outcome := _determine_winner(knight_a, knight_b)
	var final := {
		"type": "match_end",
		"winner": str(outcome["winner"].get("name", "")),
		"loser": str(outcome["loser"].get("name", "")),
		"final_score_winner": int(outcome["winner"].get("score", 0)),
		"final_score_loser": int(outcome["loser"].get("score", 0)),
		"reason": str(outcome["reason"]),
	}
	all_events.append([final])
	return {
		"events_per_pass": all_events,
		"winner": outcome["winner"],
		"loser": outcome["loser"],
		"final_event": final,
	}


## One pass with optional injected decisions (for Manage mode UI).
func resolve_single_pass(
	knight_a: Dictionary,
	knight_b: Dictionary,
	pass_number: int,
	decision_a: Dictionary = {},
	decision_b: Dictionary = {}
) -> Array:
	return _resolve_pass(knight_a, knight_b, pass_number, decision_a, decision_b)


func _resolve_pass(
	knight_a: Dictionary,
	knight_b: Dictionary,
	pass_number: int,
	override_a: Dictionary = {},
	override_b: Dictionary = {}
) -> Array:
	var events: Array = []
	var ctx_a := _build_context(knight_a, knight_b, pass_number)
	var ctx_b := _build_context(knight_b, knight_a, pass_number)
	var decision_a: Dictionary = override_a if not override_a.is_empty() else _decide(knight_a, ctx_a)
	var decision_b: Dictionary = override_b if not override_b.is_empty() else _decide(knight_b, ctx_b)

	var approach_a := _resolve_approach(knight_a, decision_a)
	var approach_b := _resolve_approach(knight_b, decision_b)
	events.append(approach_a["event"])
	events.append(approach_b["event"])
	var speed_a: float = approach_a["speed"]
	var speed_b: float = approach_b["speed"]

	var speed_check_a := _speed_check(knight_a, speed_a)
	var speed_check_b := _speed_check(knight_b, speed_b)
	events.append(speed_check_a)
	events.append(speed_check_b)
	if not bool(speed_check_a.get("passed", true)):
		knight_a["score"] = int(knight_a.get("score", 0)) - 5
	if not bool(speed_check_b.get("passed", true)):
		knight_b["score"] = int(knight_b.get("score", 0)) - 5

	if _check_lance_tip_clash(decision_a, decision_b):
		events.append({
			"type": "lance_tip_clash",
			"knight_a": str(knight_a.get("name", "")),
			"knight_b": str(knight_b.get("name", "")),
		})
		events.append(_pass_summary(pass_number, knight_a, knight_b))
		return events

	if not bool(knight_a.get("lance", {}).get("broken", false)):
		events.append_array(_resolve_impact(knight_a, knight_b, decision_a, decision_b, speed_a))
	if not bool(knight_b.get("lance", {}).get("broken", false)):
		events.append_array(_resolve_impact(knight_b, knight_a, decision_b, decision_a, speed_b))

	for k in [knight_a, knight_b]:
		var lance = k.get("lance", {})
		if lance is Dictionary and bool(lance.get("broken", false)):
			k["lance"] = JoustGenerator.generate_lance(int(rules.get("lance_type", 0)))
			events.append({
				"type": "new_lance",
				"knight_name": str(k.get("name", "")),
				"material": str(k["lance"].get("material", "ash")),
			})

	_drain_horses(knight_a, knight_b, decision_a, decision_b)
	events.append(_pass_summary(pass_number, knight_a, knight_b))
	return events


func _decide(knight: Dictionary, ctx: Dictionary) -> Dictionary:
	if player_knight_name != "" and str(knight.get("name", "")) == player_knight_name and not pending_player_decision.is_empty():
		var d := pending_player_decision.duplicate(true)
		pending_player_decision = {}
		return d
	return JoustStrategy.ai_decide(knight, ctx)


func _resolve_approach(knight: Dictionary, decision: Dictionary) -> Dictionary:
	var horse: Dictionary = knight.get("horse", {})
	var base_speed := float(horse.get("speed", 5)) / 10.0
	var fatigue_mod := JoustKnight.fatigue_factor(horse)
	var aggression := int(decision.get("aggression", JoustTypes.Aggression.NORMAL))
	var aggression_mod: float = float({0: 0.8, 1: 1.0, 2: 1.15}.get(aggression, 1.0))
	var weight_penalty := maxf(0.0, (JoustKnight.armor_total_weight(knight.get("armor", {})) - 20.0) / 80.0)
	var horse_shied := false
	var shy_mod := 1.0
	var temp := int(horse.get("temperament", 0))
	if temp == JoustTypes.Temperament.NERVOUS and randf() < 0.15:
		horse_shied = true
		shy_mod = 0.6
	elif temp == JoustTypes.Temperament.FIERY and randf() < 0.05:
		horse_shied = true
		shy_mod = 0.7
	var speed := clampf(base_speed * fatigue_mod * aggression_mod * shy_mod - weight_penalty, 0.1, 1.0)
	var threshold := float(rules.get("min_speed_threshold", 0.5))
	return {
		"speed": speed,
		"event": {
			"type": "approach",
			"knight_name": str(knight.get("name", "")),
			"horse_name": str(horse.get("name", "")),
			"speed_factor": speed,
			"speed_penalty": speed < threshold,
			"horse_shied": horse_shied,
		},
	}


func _speed_check(knight: Dictionary, speed: float) -> Dictionary:
	var threshold := float(rules.get("min_speed_threshold", 0.5))
	return {
		"type": "speed_check",
		"knight_name": str(knight.get("name", "")),
		"speed_factor": speed,
		"threshold": threshold,
		"passed": speed >= threshold,
	}


func _check_lance_tip_clash(dec_a: Dictionary, dec_b: Dictionary) -> bool:
	var both_center := (
		int(dec_a.get("aim", -1)) == JoustTypes.AimTarget.SHIELD_CENTER
		and int(dec_b.get("aim", -1)) == JoustTypes.AimTarget.SHIELD_CENTER
	)
	var base_chance := 0.08 if both_center else 0.02
	return randf() < base_chance


func _resolve_impact(
	attacker: Dictionary,
	defender: Dictionary,
	att_decision: Dictionary,
	def_decision: Dictionary,
	speed: float
) -> Array:
	var events: Array = []
	var hit_zone := _determine_hit_zone(attacker, att_decision, def_decision)

	if hit_zone == JoustTypes.HitZone.MISS:
		events.append({
			"type": "impact",
			"attacker": str(attacker.get("name", "")),
			"defender": str(defender.get("name", "")),
			"hit_zone": hit_zone,
			"force": 0.0,
			"lance_outcome": JoustTypes.LanceOutcome.INTACT,
			"score_change": 0,
			"penalty": 0,
		})
		return events

	if hit_zone == JoustTypes.HitZone.HORSE:
		events.append({
			"type": "impact",
			"attacker": str(attacker.get("name", "")),
			"defender": str(defender.get("name", "")),
			"hit_zone": hit_zone,
			"force": 0.0,
			"lance_outcome": JoustTypes.LanceOutcome.INTACT,
			"score_change": 0,
			"penalty": 0,
		})
		if bool(rules.get("horse_hit_disqualify", true)):
			attacker["disqualified"] = true
			events.append({
				"type": "disqualification",
				"knight_name": str(attacker.get("name", "")),
				"reason": "struck the opponent's horse",
			})
		return events

	var force := (
		JoustKnight.effective_stat(attacker, "strength") * 0.4
		+ speed * 8.0
		+ JoustKnight.effective_stat(attacker, "skill") * 0.2
		+ randf_range(-1.0, 1.0)
	)
	var armor_zone: String = str({
		JoustTypes.HitZone.SHIELD: "shield",
		JoustTypes.HitZone.ARMOR_CHEST: "chest",
		JoustTypes.HitZone.ARMOR_SHOULDER: "shoulder",
		JoustTypes.HitZone.HEAD: "head",
	}.get(hit_zone, "shield"))
	var protection := JoustKnight.protection_for_zone(defender.get("armor", {}), armor_zone)
	var residual := force - protection * 0.5
	var score_pair := _calc_score(hit_zone, force, attacker.get("lance", {}))
	var score: int = score_pair[0]
	var penalty: int = score_pair[1]
	attacker["score"] = int(attacker.get("score", 0)) + score + penalty
	var lance_outcome := _check_lance_break(attacker.get("lance", {}), force, hit_zone)
	events.append({
		"type": "impact",
		"attacker": str(attacker.get("name", "")),
		"defender": str(defender.get("name", "")),
		"hit_zone": hit_zone,
		"force": force,
		"lance_outcome": lance_outcome,
		"score_change": score,
		"penalty": penalty,
	})

	if residual > 0.0 and hit_zone != JoustTypes.HitZone.SHIELD:
		events.append_array(_check_injury(defender, hit_zone, residual))

	var fall_event := _check_fall(defender, force)
	if not fall_event.is_empty():
		if int(fall_event.get("fall_type", -1)) == JoustTypes.FallType.UNHORSED:
			var pts := int(rules.get("unhorse_points", 5))
			attacker["score"] = int(attacker.get("score", 0)) + pts
			fall_event["caused_by"] = str(attacker.get("name", ""))
			fall_event["score_awarded"] = pts
		events.append(fall_event)
	return events


func _determine_hit_zone(attacker: Dictionary, att_dec: Dictionary, def_dec: Dictionary) -> int:
	var skill := JoustKnight.effective_stat(attacker, "skill")
	var accuracy := skill / 10.0 + randf_range(-0.2, 0.2)
	if accuracy < 0.2:
		return JoustTypes.HitZone.MISS
	if randf() < maxf(0.0, 0.05 - skill * 0.005):
		return JoustTypes.HitZone.HORSE
	var aim := int(att_dec.get("aim", 0))
	var guard := int(def_dec.get("shield_guard", 1))
	match aim:
		JoustTypes.AimTarget.SHIELD_CENTER:
			return JoustTypes.HitZone.SHIELD
		JoustTypes.AimTarget.SHIELD_EDGE:
			var drift := randf()
			if drift < 0.6:
				return JoustTypes.HitZone.SHIELD
			elif drift < 0.85:
				return JoustTypes.HitZone.ARMOR_SHOULDER
			return JoustTypes.HitZone.MISS
		JoustTypes.AimTarget.ARMOR:
			if not bool(rules.get("armor_contact_allowed", true)):
				return JoustTypes.HitZone.SHIELD if randf() < 0.5 else JoustTypes.HitZone.ARMOR_CHEST
			var d2 := randf()
			if d2 < 0.5:
				return JoustTypes.HitZone.ARMOR_CHEST
			elif d2 < 0.75:
				return JoustTypes.HitZone.ARMOR_SHOULDER
			elif d2 < 0.9:
				return JoustTypes.HitZone.SHIELD
			return JoustTypes.HitZone.MISS
		JoustTypes.AimTarget.HIGH:
			var d3 := randf()
			var guard_bonus := 0.3 if guard == JoustTypes.ShieldGuard.HIGH else 0.0
			if d3 < 0.3 - guard_bonus:
				return JoustTypes.HitZone.HEAD
			elif d3 < 0.6:
				return JoustTypes.HitZone.SHIELD
			elif d3 < 0.8:
				return JoustTypes.HitZone.ARMOR_SHOULDER
			return JoustTypes.HitZone.MISS
	return JoustTypes.HitZone.SHIELD


func _calc_score(hit_zone: int, force: float, lance: Dictionary) -> Array:
	var penalty := 0
	if hit_zone == JoustTypes.HitZone.HEAD:
		penalty = int(rules.get("head_hit_penalty", -5))
	elif hit_zone in [JoustTypes.HitZone.ARMOR_CHEST, JoustTypes.HitZone.ARMOR_SHOULDER]:
		if not bool(rules.get("armor_contact_allowed", true)):
			penalty = int(rules.get("torso_hit_penalty", -5))
	var threshold := JoustKnight.lance_break_threshold(lance)
	if hit_zone == JoustTypes.HitZone.SHIELD:
		if force > threshold * 1.3:
			return [3, penalty]
		elif force > threshold * 0.9:
			return [2, penalty]
		return [1, penalty]
	elif hit_zone in [JoustTypes.HitZone.ARMOR_CHEST, JoustTypes.HitZone.ARMOR_SHOULDER]:
		if force > threshold * 1.2:
			return [2, penalty]
		return [1, penalty]
	elif hit_zone == JoustTypes.HitZone.HEAD:
		return [0, penalty]
	return [0, 0]


func _check_lance_break(lance: Dictionary, force: float, hit_zone: int) -> int:
	if hit_zone == JoustTypes.HitZone.MISS or not (lance is Dictionary):
		return JoustTypes.LanceOutcome.INTACT
	var threshold := JoustKnight.lance_break_threshold(lance)
	if force > threshold * 1.3:
		lance["broken"] = true
		return JoustTypes.LanceOutcome.FULL_BREAK
	elif force > threshold * 0.9:
		lance["broken"] = true
		return JoustTypes.LanceOutcome.TIP_BREAK
	return JoustTypes.LanceOutcome.INTACT


func _check_injury(defender: Dictionary, hit_zone: int, residual: float) -> Array:
	var events: Array = []
	var body_zone: int = int({
		JoustTypes.HitZone.SHIELD: JoustTypes.BodyZone.SHIELD_ARM,
		JoustTypes.HitZone.ARMOR_CHEST: JoustTypes.BodyZone.CHEST,
		JoustTypes.HitZone.ARMOR_SHOULDER: JoustTypes.BodyZone.SHOULDER,
		JoustTypes.HitZone.HEAD: JoustTypes.BodyZone.HEAD,
	}.get(hit_zone, -1))
	if body_zone < 0:
		return events
	var injuries: Array = defender.get("injuries", [])
	for inj in injuries:
		if inj is Dictionary and int(inj.get("zone", -1)) == body_zone and int(inj.get("severity", 0)) == JoustTypes.Severity.SEVERE:
			if JoustInjury.worsen(inj):
				events.append({
					"type": "injury",
					"knight_name": str(defender.get("name", "")),
					"zone": JoustTypes.BODY_ZONE_NAMES[body_zone],
					"severity": JoustTypes.SEVERITY_NAMES[int(inj.get("severity", 0))],
					"description": str(inj.get("description", "")),
					"worsened": true,
				})
				return events
	var severity := JoustTypes.Severity.MINOR
	if residual < 2.0:
		severity = JoustTypes.Severity.MINOR
	elif residual < 4.0:
		severity = JoustTypes.Severity.MODERATE
	elif residual < 6.5:
		severity = JoustTypes.Severity.SEVERE
	else:
		severity = JoustTypes.Severity.CRITICAL
	if severity > JoustTypes.Severity.MINOR and randf() < JoustKnight.effective_stat(defender, "endurance") * 0.07:
		severity -= 1
	if severity == JoustTypes.Severity.MINOR and randf() < 0.5:
		return events
	var injury := JoustInjury.create(body_zone, severity)
	injuries.append(injury)
	defender["injuries"] = injuries
	events.append({
		"type": "injury",
		"knight_name": str(defender.get("name", "")),
		"zone": JoustTypes.BODY_ZONE_NAMES[body_zone],
		"severity": JoustTypes.SEVERITY_NAMES[severity],
		"description": str(injury.get("description", "")),
		"worsened": false,
	})
	return events


func _check_fall(defender: Dictionary, force: float) -> Dictionary:
	var stability := (
		JoustKnight.effective_stat(defender, "strength") * 0.3
		+ JoustKnight.effective_stat(defender, "endurance") * 0.2
		+ float(defender.get("horse", {}).get("steadiness", 5)) * 0.3
		+ randf_range(0.0, 2.0)
	)
	var unhorse_threshold := 10.0 + stability * 0.6
	if force > unhorse_threshold:
		return {
			"type": "fall",
			"knight_name": str(defender.get("name", "")),
			"fall_type": JoustTypes.FallType.UNHORSED,
			"caused_by": "",
			"score_awarded": 0,
		}
	var horse: Dictionary = defender.get("horse", {})
	var stumble := 0.0
	if JoustKnight.fatigue_factor(horse) < 0.2:
		stumble += 0.06
	if int(horse.get("temperament", 0)) == JoustTypes.Temperament.NERVOUS:
		stumble += 0.03
	if force > 8.0:
		stumble += 0.03
	if randf() < stumble:
		return {
			"type": "fall",
			"knight_name": str(defender.get("name", "")),
			"fall_type": JoustTypes.FallType.HORSE_FELL,
			"caused_by": "horse stumble",
			"score_awarded": 0,
		}
	return {}


func _drain_horses(ka: Dictionary, kb: Dictionary, dec_a: Dictionary, dec_b: Dictionary) -> void:
	var drain_map := {0: 0.5, 1: 0.8, 2: 1.3}
	JoustKnight.drain_horse(ka.get("horse", {}), float(drain_map.get(int(dec_a.get("aggression", 1)), 0.8)))
	JoustKnight.drain_horse(kb.get("horse", {}), float(drain_map.get(int(dec_b.get("aggression", 1)), 0.8)))


func _pass_summary(pass_number: int, ka: Dictionary, kb: Dictionary) -> Dictionary:
	return {
		"type": "pass_summary",
		"pass_number": pass_number,
		"knight_a": str(ka.get("name", "")),
		"knight_b": str(kb.get("name", "")),
		"score_a": int(ka.get("score", 0)),
		"score_b": int(kb.get("score", 0)),
	}


func _determine_winner(ka: Dictionary, kb: Dictionary) -> Dictionary:
	if bool(ka.get("disqualified", false)):
		return {"winner": kb, "loser": ka, "reason": "disqualification"}
	if bool(kb.get("disqualified", false)):
		return {"winner": ka, "loser": kb, "reason": "disqualification"}
	if not JoustKnight.can_fight(ka) and JoustKnight.can_fight(kb):
		return {"winner": kb, "loser": ka, "reason": "withdrawal"}
	if not JoustKnight.can_fight(kb) and JoustKnight.can_fight(ka):
		return {"winner": ka, "loser": kb, "reason": "withdrawal"}
	if int(ka.get("score", 0)) > int(kb.get("score", 0)):
		return {"winner": ka, "loser": kb, "reason": "points"}
	if int(kb.get("score", 0)) > int(ka.get("score", 0)):
		return {"winner": kb, "loser": ka, "reason": "points"}
	var ia: Array = ka.get("injuries", [])
	var ib: Array = kb.get("injuries", [])
	if ia.size() < ib.size():
		return {"winner": ka, "loser": kb, "reason": "points"}
	if ib.size() < ia.size():
		return {"winner": kb, "loser": ka, "reason": "points"}
	if randf() < 0.5:
		return {"winner": ka, "loser": kb, "reason": "points"}
	return {"winner": kb, "loser": ka, "reason": "points"}


func build_context(knight: Dictionary, opponent: Dictionary, pass_number: int) -> Dictionary:
	return _build_context(knight, opponent, pass_number)


func determine_winner(ka: Dictionary, kb: Dictionary) -> Dictionary:
	return _determine_winner(ka, kb)


func _build_context(knight: Dictionary, opponent: Dictionary, pass_number: int) -> Dictionary:
	var moderate_plus := 0
	for inj in knight.get("injuries", []):
		if inj is Dictionary and int(inj.get("severity", 0)) >= JoustTypes.Severity.MODERATE:
			moderate_plus += 1
	var opp_mod := 0
	for inj in opponent.get("injuries", []):
		if inj is Dictionary and int(inj.get("severity", 0)) >= JoustTypes.Severity.MODERATE:
			opp_mod += 1
	return {
		"pass_number": pass_number,
		"total_passes": int(rules.get("num_passes", 3)),
		"own_score": int(knight.get("score", 0)),
		"opponent_score": int(opponent.get("score", 0)),
		"own_injuries": moderate_plus,
		"opponent_injuries": opp_mod,
		"own_horse_fatigue": 1.0 - JoustKnight.fatigue_factor(knight.get("horse", {})),
		"opponent_horse_fatigue": 1.0 - JoustKnight.fatigue_factor(opponent.get("horse", {})),
		"own_lance_broken": bool(knight.get("lance", {}).get("broken", false)),
	}
