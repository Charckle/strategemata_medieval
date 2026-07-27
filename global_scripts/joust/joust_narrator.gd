extends RefCounted
class_name JoustNarrator


static func _pick(options: Array) -> String:
	if options.is_empty():
		return ""
	return str(options[randi() % options.size()])


static func narrate_pass(events: Array, verbose: bool = true) -> PackedStringArray:
	var lines: PackedStringArray = []
	for event in events:
		if not (event is Dictionary):
			continue
		var result = _narrate_event(event, verbose)
		if result is PackedStringArray:
			lines.append_array(result)
		elif result is Array:
			for r in result:
				lines.append(str(r))
		elif typeof(result) == TYPE_STRING and str(result) != "":
			lines.append(str(result))
	return lines


static func narrate_match_brief(events_per_pass: Array) -> PackedStringArray:
	var lines: PackedStringArray = []
	for pass_events in events_per_pass:
		if not (pass_events is Array):
			continue
		for event in pass_events:
			if not (event is Dictionary):
				continue
			var t := str(event.get("type", ""))
			if t == "fall":
				if int(event.get("fall_type", -1)) == JoustTypes.FallType.UNHORSED:
					lines.append("%s was unhorsed by %s!" % [event.get("knight_name", ""), event.get("caused_by", "")])
				else:
					lines.append("%s's horse went down beneath them!" % event.get("knight_name", ""))
			elif t == "disqualification":
				lines.append("%s was DISQUALIFIED — %s!" % [event.get("knight_name", ""), event.get("reason", "")])
			elif t == "match_end":
				lines.append(
					"RESULT: %s defeats %s (%d-%d, %s)"
					% [
						event.get("winner", ""),
						event.get("loser", ""),
						int(event.get("final_score_winner", 0)),
						int(event.get("final_score_loser", 0)),
						event.get("reason", ""),
					]
				)
	return lines


static func _narrate_event(event: Dictionary, verbose: bool):
	match str(event.get("type", "")):
		"approach":
			return _narrate_approach(event, verbose)
		"speed_check":
			return _narrate_speed_check(event)
		"lance_tip_clash":
			return _narrate_tip_clash(event)
		"impact":
			return _narrate_impact(event)
		"fall":
			return _narrate_fall(event)
		"injury":
			return _narrate_injury(event)
		"disqualification":
			return _narrate_disqualification(event)
		"new_lance":
			return _narrate_new_lance(event, verbose)
		"pass_summary":
			return _narrate_pass_summary(event)
		"match_end":
			return _narrate_match_end(event)
	return null


static func _narrate_approach(e: Dictionary, verbose: bool):
	if not verbose:
		return null
	var lines: PackedStringArray = []
	var kn := str(e.get("knight_name", ""))
	var hn := str(e.get("horse_name", ""))
	if bool(e.get("horse_shied", false)):
		lines.append("%s's mount, %s, %s" % [kn, hn, _pick([
			"balks and shies at the tilt!",
			"tosses its head and slows!",
			"breaks stride, fighting the reins!",
		])])
	else:
		var sf := float(e.get("speed_factor", 0.5))
		if sf > 0.8:
			lines.append("%s %s" % [kn, _pick([
				"spurs %s into a thundering gallop!" % hn,
				"leans forward as %s surges down the tilt!" % hn,
				"charges hard — %s's hooves pound the packed earth!" % hn,
			])])
		elif sf > 0.5:
			lines.append("%s %s" % [kn, _pick([
				"rides steadily on %s." % hn,
				"guides %s into a measured canter." % hn,
				"advances at a solid pace aboard %s." % hn,
			])])
		else:
			lines.append("%s %s" % [kn, _pick([
				"struggles to coax speed from the tiring %s." % hn,
				"plods forward — %s is flagging." % hn,
				"manages only a sluggish trot on the exhausted %s." % hn,
			])])
	return lines


static func _narrate_speed_check(e: Dictionary):
	if bool(e.get("passed", true)):
		return null
	return "*** %s fails to reach the required speed! (-5 points penalty) ***" % e.get("knight_name", "")


static func _narrate_tip_clash(e: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		_pick([
			"The lance tips of %s and %s collide mid-tilt!" % [e.get("knight_a", ""), e.get("knight_b", "")],
			"A crack rings out — both lances meet tip-to-tip!",
			"The points of both lances clash together with a sharp crack!",
		]),
		"The marshals confer — the pass is VOIDED and must be re-run!",
	])


static func _narrate_impact(e: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var hz := int(e.get("hit_zone", -1))
	var attacker := str(e.get("attacker", ""))
	var defender := str(e.get("defender", ""))
	if hz == JoustTypes.HitZone.MISS:
		lines.append("%s's lance %s" % [attacker, _pick([
			"finds only empty air as %s twists aside." % defender,
			"sweeps wide — a clean miss!",
			"passes harmlessly past %s." % defender,
		])])
		return lines
	if hz == JoustTypes.HitZone.HORSE:
		lines.append("*** %s's lance drops LOW and strikes %s's horse! ***" % [attacker, defender])
		return lines
	var zone_text: String = str({
		JoustTypes.HitZone.SHIELD: "shield",
		JoustTypes.HitZone.ARMOR_CHEST: "breastplate",
		JoustTypes.HitZone.ARMOR_SHOULDER: "pauldron",
		JoustTypes.HitZone.HEAD: "helm",
	}.get(hz, "armor"))
	var force := float(e.get("force", 0))
	var verb: String
	if force > 7.0:
		verb = _pick(["SLAMS into", "CRASHES against", "strikes with tremendous force upon"])
	elif force > 4.0:
		verb = _pick(["strikes", "connects solidly with", "hits"])
	else:
		verb = _pick(["glances off", "scrapes across", "brushes against"])
	lines.append("%s's lance %s %s's %s!" % [attacker, verb, defender, zone_text])
	var lo := int(e.get("lance_outcome", 0))
	if lo == JoustTypes.LanceOutcome.FULL_BREAK:
		lines.append(_pick([
			"The shaft SHATTERS into pieces! Splinters fly across the tilt!",
			"The lance EXPLODES on impact! Fragments rain down!",
			"With a tremendous crack, the lance breaks into three pieces!",
		]))
	elif lo == JoustTypes.LanceOutcome.TIP_BREAK:
		lines.append(_pick([
			"The lance tip snaps off on impact!",
			"The point of the lance breaks away!",
			"The tip splinters — a clean break of the point!",
		]))
	var sc := int(e.get("score_change", 0))
	if sc > 0:
		lines.append("[+%d points to %s]" % [sc, attacker])
	var penalty := int(e.get("penalty", 0))
	if penalty < 0:
		var zone_name := "head" if hz == JoustTypes.HitZone.HEAD else "body"
		lines.append("*** PENALTY: Illegal hit to the %s! (%d points) ***" % [zone_name, penalty])
	return lines


static func _narrate_fall(e: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var kn := str(e.get("knight_name", ""))
	if int(e.get("fall_type", -1)) == JoustTypes.FallType.UNHORSED:
		lines.append(_pick([
			"%s is KNOCKED CLEAN from the saddle!" % kn,
			"%s flies from the horse and crashes to the ground!" % kn,
			"The blow sends %s tumbling from the saddle!" % kn,
		]))
		lines.append(_pick([
			"Armor clangs against the hard-packed earth!",
			"A cloud of dust rises from the fall!",
			"The crowd gasps as the knight hits the ground!",
		]))
		var awarded := int(e.get("score_awarded", 0))
		if awarded > 0:
			lines.append("[+%d points to %s — UNHORSING!]" % [awarded, e.get("caused_by", "")])
	else:
		lines.append(_pick([
			"%s's horse stumbles and goes DOWN!" % kn,
			"The legs of %s's mount buckle — horse and rider crash together!" % kn,
			"%s's horse collapses beneath them!" % kn,
		]))
		lines.append("The fall was the horse's fault — the rider bears no disgrace.")
	return lines


static func _narrate_injury(e: Dictionary) -> String:
	if bool(e.get("worsened", false)):
		return "%s's existing %s injury WORSENS — %s! [%s]" % [
			e.get("knight_name", ""), e.get("zone", ""), e.get("description", ""), e.get("severity", "")
		]
	var sev := str(e.get("severity", ""))
	var prefix: String = str({"MODERATE": "** ", "SEVERE": "*** ", "CRITICAL": "**** "}.get(sev, ""))
	var suffix: String = str({"MODERATE": " **", "SEVERE": " ***", "CRITICAL": " ****"}.get(sev, ""))
	return "%s%s suffers %s!%s" % [prefix, e.get("knight_name", ""), e.get("description", ""), suffix]


static func _narrate_disqualification(e: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"*** %s is DISQUALIFIED — %s! ***" % [e.get("knight_name", ""), e.get("reason", "")],
		"The marshals raise the black flag. The crowd jeers!",
	])


static func _narrate_new_lance(e: Dictionary, verbose: bool):
	if not verbose:
		return null
	return "%s is handed a fresh %s lance." % [e.get("knight_name", ""), e.get("material", "ash")]


static func _narrate_pass_summary(e: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"═══ End of Pass %d: %s [%d] vs %s [%d] ═══"
		% [
			int(e.get("pass_number", 0)),
			e.get("knight_a", ""),
			int(e.get("score_a", 0)),
			e.get("knight_b", ""),
			int(e.get("score_b", 0)),
		]
	])


static func _narrate_match_end(e: Dictionary) -> PackedStringArray:
	var reason_text: String = str({
		"points": "on points",
		"unhorsing": "by UNHORSING",
		"disqualification": "by DISQUALIFICATION of the opponent",
		"withdrawal": "as the opponent could not continue",
	}.get(str(e.get("reason", "")), str(e.get("reason", ""))))
	return PackedStringArray([
		"VICTORY: %s defeats %s %s!" % [e.get("winner", ""), e.get("loser", ""), reason_text],
		"Final score: %d - %d" % [int(e.get("final_score_winner", 0)), int(e.get("final_score_loser", 0))],
	])
