extends RefCounted
class_name JoustKnight

## Knights are plain Dictionaries so they serialize into game_data / RPC.


static func armor_total_weight(armor: Dictionary) -> float:
	var total := 0.0
	for key in ["helm", "pauldrons", "breastplate", "shield"]:
		var piece = armor.get(key, {})
		if piece is Dictionary:
			total += float(piece.get("weight", 0.0))
	return total


static func protection_for_zone(armor: Dictionary, zone: String) -> float:
	var mapping := {
		"head": "helm",
		"shoulder": "pauldrons",
		"chest": "breastplate",
		"shield": "shield",
	}
	var key := str(mapping.get(zone, ""))
	if key == "":
		return 0.0
	var piece = armor.get(key, {})
	if not (piece is Dictionary):
		return 0.0
	var prot := float(piece.get("protection", 0))
	var quality := float(piece.get("quality", 0))
	return prot * (0.5 + 0.05 * quality)


static func lance_break_threshold(lance: Dictionary) -> float:
	var quality := float(lance.get("quality", 5))
	var base := 4.0 + 0.6 * quality
	var material := str(lance.get("material", "ash"))
	var material_bonus: float = float({"pine": -1.0, "ash": 0.0, "oak": 1.5}.get(material, 0.0))
	var type_bonus: float = 2.0 if int(lance.get("lance_type", 0)) == JoustTypes.LanceType.WAR else 0.0
	return base + material_bonus + type_bonus


static func fatigue_factor(horse: Dictionary) -> float:
	var stamina := float(horse.get("stamina", 1))
	if stamina <= 0.0:
		return 0.0
	return maxf(0.0, float(horse.get("current_stamina", stamina)) / stamina)


static func drain_horse(horse: Dictionary, amount: float) -> void:
	horse["current_stamina"] = maxf(0.0, float(horse.get("current_stamina", 0.0)) - amount)


static func _penalty_sum(injuries: Array, stat: String) -> int:
	var total := 0
	for inj in injuries:
		if not (inj is Dictionary):
			continue
		var pens = inj.get("stat_penalties", {})
		if pens is Dictionary:
			total += int(pens.get(stat, 0))
	return total


static func effective_stat(knight: Dictionary, stat: String) -> int:
	var base := int(knight.get(stat, 1))
	return maxi(1, base + _penalty_sum(knight.get("injuries", []), stat))


static func can_fight(knight: Dictionary) -> bool:
	if bool(knight.get("disqualified", false)) or bool(knight.get("withdrawn", false)):
		return false
	for inj in knight.get("injuries", []):
		if inj is Dictionary and int(inj.get("severity", 0)) >= JoustTypes.Severity.CRITICAL:
			return false
	return true


static func reset_for_match(knight: Dictionary) -> void:
	knight["score"] = 0
	knight["disqualified"] = false
	var lance = knight.get("lance", {})
	if lance is Dictionary:
		lance["broken"] = false
	var horse = knight.get("horse", {})
	if horse is Dictionary:
		horse["current_stamina"] = float(horse.get("stamina", 5))


static func heal_between_matches(knight: Dictionary) -> Array:
	var healed: Array = []
	var remaining: Array = []
	var endurance := effective_stat(knight, "endurance")
	for inj in knight.get("injuries", []):
		if not (inj is Dictionary):
			continue
		var sev := int(inj.get("severity", 0))
		if sev == JoustTypes.Severity.MINOR:
			healed.append("%s has healed." % str(inj.get("description", "injury")))
		elif sev == JoustTypes.Severity.MODERATE:
			if randf() < 0.3 + 0.05 * endurance:
				inj["severity"] = JoustTypes.Severity.MINOR
				inj["stat_penalties"] = {}
				healed.append("%s has improved — no longer affecting performance." % str(inj.get("description", "injury")))
			else:
				remaining.append(inj)
		else:
			remaining.append(inj)
	knight["injuries"] = remaining
	return healed


static func duplicate_knight(knight: Dictionary) -> Dictionary:
	return knight.duplicate(true)


static func card_text(knight: Dictionary) -> String:
	var horse: Dictionary = knight.get("horse", {})
	var armor: Dictionary = knight.get("armor", {})
	var lance: Dictionary = knight.get("lance", {})
	var pers := int(knight.get("personality", 0))
	var pers_name: String = (
		str(JoustTypes.PERSONALITY_NAMES[pers])
		if pers >= 0 and pers < JoustTypes.PERSONALITY_NAMES.size()
		else "?"
	)
	var temp := int(horse.get("temperament", 0))
	var temp_name: String = (
		str(JoustTypes.TEMPERAMENT_NAMES[temp])
		if temp >= 0 and temp < JoustTypes.TEMPERAMENT_NAMES.size()
		else "?"
	)
	var lt := int(lance.get("lance_type", 0))
	var lt_name: String = (
		str(JoustTypes.LANCE_TYPE_NAMES[lt])
		if lt >= 0 and lt < JoustTypes.LANCE_TYPE_NAMES.size()
		else "?"
	)
	var lines: PackedStringArray = []
	lines.append(str(knight.get("name", "Knight")))
	var from_prov := str(knight.get("province_name", ""))
	if from_prov != "":
		lines.append("From: %s" % from_prov)
	lines.append("Personality: %s" % pers_name)
	lines.append(
		"STR %d  SKL %d  END %d  CRG %d"
		% [
			int(knight.get("strength", 0)),
			int(knight.get("skill", 0)),
			int(knight.get("endurance", 0)),
			int(knight.get("courage", 0)),
		]
	)
	lines.append("Horse: %s" % str(horse.get("name", "?")))
	lines.append(
		"SPD %d  STD %d  STA %d  [%s]"
		% [
			int(horse.get("speed", 0)),
			int(horse.get("steadiness", 0)),
			int(horse.get("stamina", 0)),
			temp_name,
		]
	)
	lines.append("Armor weight: %.1f" % armor_total_weight(armor))
	var helm: Dictionary = armor.get("helm", {})
	var paul: Dictionary = armor.get("pauldrons", {})
	var breast: Dictionary = armor.get("breastplate", {})
	var shield: Dictionary = armor.get("shield", {})
	lines.append(
		"Helm %dp/%dq  Pauldrons %dp/%dq"
		% [int(helm.get("protection", 0)), int(helm.get("quality", 0)), int(paul.get("protection", 0)), int(paul.get("quality", 0))]
	)
	lines.append(
		"Breast %dp/%dq  Shield %dp/%dq"
		% [int(breast.get("protection", 0)), int(breast.get("quality", 0)), int(shield.get("protection", 0)), int(shield.get("quality", 0))]
	)
	lines.append("Lance: %s (%s) q%d" % [str(lance.get("material", "?")), lt_name, int(lance.get("quality", 0))])
	return "\n".join(lines)
