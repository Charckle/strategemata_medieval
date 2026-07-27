extends RefCounted
class_name JoustStrategy


static func ai_decide(knight: Dictionary, ctx: Dictionary) -> Dictionary:
	var personality := int(knight.get("personality", JoustTypes.Personality.BALANCED))
	var courage := JoustKnight.effective_stat(knight, "courage")
	var score_diff := int(ctx.get("own_score", 0)) - int(ctx.get("opponent_score", 0))
	return {
		"aim": _choose_aim(personality, courage, score_diff, ctx),
		"aggression": _choose_aggression(personality, knight, ctx),
		"shield_guard": _choose_guard(personality, ctx),
	}


static func _choose_aim(personality: int, courage: int, score_diff: int, _ctx: Dictionary) -> int:
	if personality == JoustTypes.Personality.RECKLESS:
		return [JoustTypes.AimTarget.ARMOR, JoustTypes.AimTarget.HIGH, JoustTypes.AimTarget.SHIELD_CENTER][randi() % 3]
	if personality == JoustTypes.Personality.CAUTIOUS or score_diff > 3:
		return [JoustTypes.AimTarget.SHIELD_CENTER, JoustTypes.AimTarget.SHIELD_CENTER, JoustTypes.AimTarget.SHIELD_EDGE][randi() % 3]
	if personality == JoustTypes.Personality.BOLD:
		if score_diff < -2 and courage >= 6:
			return [JoustTypes.AimTarget.ARMOR, JoustTypes.AimTarget.SHIELD_CENTER][randi() % 2]
		return [JoustTypes.AimTarget.SHIELD_CENTER, JoustTypes.AimTarget.ARMOR, JoustTypes.AimTarget.SHIELD_EDGE][randi() % 3]
	if score_diff < -3:
		return [JoustTypes.AimTarget.ARMOR, JoustTypes.AimTarget.SHIELD_CENTER][randi() % 2]
	return JoustTypes.AimTarget.SHIELD_CENTER


static func _choose_aggression(personality: int, knight: Dictionary, ctx: Dictionary) -> int:
	var fatigue := float(ctx.get("own_horse_fatigue", 0.0))
	if fatigue > 0.7:
		return JoustTypes.Aggression.CONSERVATIVE
	if personality == JoustTypes.Personality.RECKLESS:
		return JoustTypes.Aggression.AGGRESSIVE
	if personality == JoustTypes.Personality.CAUTIOUS:
		return JoustTypes.Aggression.CONSERVATIVE if fatigue > 0.4 else JoustTypes.Aggression.NORMAL
	if personality == JoustTypes.Personality.BOLD:
		return JoustTypes.Aggression.AGGRESSIVE if JoustKnight.effective_stat(knight, "courage") >= 6 else JoustTypes.Aggression.NORMAL
	return JoustTypes.Aggression.NORMAL


static func _choose_guard(personality: int, ctx: Dictionary) -> int:
	if personality == JoustTypes.Personality.RECKLESS:
		return [JoustTypes.ShieldGuard.CENTER, JoustTypes.ShieldGuard.LOW][randi() % 2]
	if personality == JoustTypes.Personality.CAUTIOUS:
		return JoustTypes.ShieldGuard.HIGH
	if int(ctx.get("own_injuries", 0)) > 1:
		return JoustTypes.ShieldGuard.HIGH
	return JoustTypes.ShieldGuard.CENTER
