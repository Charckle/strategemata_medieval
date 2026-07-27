extends RefCounted
class_name JoustInjury

const ZONE_PENALTY_MAP := {
	JoustTypes.BodyZone.HEAD: {"skill": -1, "courage": -1},
	JoustTypes.BodyZone.SHOULDER: {"strength": -1},
	JoustTypes.BodyZone.CHEST: {"strength": -1, "endurance": -1},
	JoustTypes.BodyZone.LANCE_ARM: {"skill": -1, "strength": -1},
	JoustTypes.BodyZone.SHIELD_ARM: {"endurance": -1},
	JoustTypes.BodyZone.HIP: {"endurance": -1},
}

const SEVERITY_MULT := {
	JoustTypes.Severity.MINOR: 0,
	JoustTypes.Severity.MODERATE: 1,
	JoustTypes.Severity.SEVERE: 2,
	JoustTypes.Severity.CRITICAL: 3,
}

const ZONE_DESCRIPTIONS := {
	JoustTypes.BodyZone.HEAD: {
		JoustTypes.Severity.MINOR: ["a ringing in the ears", "a rattled helm"],
		JoustTypes.Severity.MODERATE: ["a mild concussion", "blurred vision"],
		JoustTypes.Severity.SEVERE: ["a heavy concussion", "a cracked visor digs into the brow"],
		JoustTypes.Severity.CRITICAL: ["a devastating blow to the skull — consciousness fades"],
	},
	JoustTypes.BodyZone.SHOULDER: {
		JoustTypes.Severity.MINOR: ["a bruised shoulder"],
		JoustTypes.Severity.MODERATE: ["a strained shoulder", "a dented pauldron presses the joint"],
		JoustTypes.Severity.SEVERE: ["a dislocated shoulder"],
		JoustTypes.Severity.CRITICAL: ["a shattered shoulder — the arm hangs limp"],
	},
	JoustTypes.BodyZone.CHEST: {
		JoustTypes.Severity.MINOR: ["a bruise across the ribs"],
		JoustTypes.Severity.MODERATE: ["bruised ribs", "a winded feeling that won't pass"],
		JoustTypes.Severity.SEVERE: ["cracked ribs — every breath is agony"],
		JoustTypes.Severity.CRITICAL: ["broken ribs — a punctured lung is feared"],
	},
	JoustTypes.BodyZone.LANCE_ARM: {
		JoustTypes.Severity.MINOR: ["a sore wrist"],
		JoustTypes.Severity.MODERATE: ["a strained wrist", "numbness in the lance hand"],
		JoustTypes.Severity.SEVERE: ["a fractured forearm — gripping the lance is torment"],
		JoustTypes.Severity.CRITICAL: ["a shattered lance arm — it cannot hold a weapon"],
	},
	JoustTypes.BodyZone.SHIELD_ARM: {
		JoustTypes.Severity.MINOR: ["a bruised shield arm"],
		JoustTypes.Severity.MODERATE: ["a numbed shield arm from the repeated blows"],
		JoustTypes.Severity.SEVERE: ["the shield arm buckles — can barely hold the shield"],
		JoustTypes.Severity.CRITICAL: ["the shield arm is broken clean"],
	},
	JoustTypes.BodyZone.HIP: {
		JoustTypes.Severity.MINOR: ["a sore hip from the saddle"],
		JoustTypes.Severity.MODERATE: ["a bruised hip — sitting the saddle is painful"],
		JoustTypes.Severity.SEVERE: ["a cracked pelvis — staying mounted is desperate work"],
		JoustTypes.Severity.CRITICAL: ["the hip is shattered — cannot mount a horse"],
	},
}


static func create(zone: int, severity: int) -> Dictionary:
	var descs: Array = ZONE_DESCRIPTIONS.get(zone, {}).get(severity, ["an injury"])
	var description := str(descs[randi() % descs.size()]) if not descs.is_empty() else "an injury"
	var base: Dictionary = ZONE_PENALTY_MAP.get(zone, {})
	var mult := int(SEVERITY_MULT.get(severity, 0))
	var penalties := {}
	for stat in base.keys():
		penalties[stat] = int(base[stat]) * mult
	return {
		"zone": zone,
		"severity": severity,
		"description": description,
		"stat_penalties": penalties,
	}


static func worsen(inj: Dictionary) -> bool:
	var sev := int(inj.get("severity", 0))
	if sev >= JoustTypes.Severity.CRITICAL:
		return false
	if sev == JoustTypes.Severity.SEVERE and randf() < 0.3:
		inj["severity"] = JoustTypes.Severity.CRITICAL
		var zone := int(inj.get("zone", 0))
		var descs: Array = ZONE_DESCRIPTIONS.get(zone, {}).get(JoustTypes.Severity.CRITICAL, [inj.get("description", "")])
		if not descs.is_empty():
			inj["description"] = str(descs[randi() % descs.size()])
		var base: Dictionary = ZONE_PENALTY_MAP.get(zone, {})
		var penalties := {}
		for stat in base.keys():
			penalties[stat] = int(base[stat]) * int(SEVERITY_MULT[JoustTypes.Severity.CRITICAL])
		inj["stat_penalties"] = penalties
		return true
	return false
