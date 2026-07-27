extends RefCounted
class_name JoustTypes

## Shared enums / string constants for the joust minigame.

enum TOURNEY_TYPE { BORDER_MELEE, LORDS_CHALLENGE, CROWN_TOURNEY }

enum Personality { BOLD, CAUTIOUS, BALANCED, RECKLESS }
enum Temperament { BRAVE, NERVOUS, STEADY, FIERY }
enum LanceType { TOURNEY, WAR }

enum AimTarget { SHIELD_CENTER, SHIELD_EDGE, ARMOR, HIGH }
enum Aggression { CONSERVATIVE, NORMAL, AGGRESSIVE }
enum ShieldGuard { HIGH, CENTER, LOW }

enum HitZone { SHIELD, ARMOR_CHEST, ARMOR_SHOULDER, HEAD, HORSE, MISS }
enum LanceOutcome { INTACT, TIP_BREAK, FULL_BREAK }
enum FallType { UNHORSED, HORSE_FELL }

enum BodyZone { HEAD, SHOULDER, CHEST, LANCE_ARM, SHIELD_ARM, HIP }
enum Severity { MINOR, MODERATE, SEVERE, CRITICAL }

const PERSONALITY_NAMES := ["bold", "cautious", "balanced", "reckless"]
const TEMPERAMENT_NAMES := ["brave", "nervous", "steady", "fiery"]
const LANCE_TYPE_NAMES := ["tourney", "war"]
const AIM_NAMES := ["shield_center", "shield_edge", "armor", "high"]
const AGGRESSION_NAMES := ["conservative", "normal", "aggressive"]
const GUARD_NAMES := ["high", "center", "low"]
const HIT_ZONE_NAMES := ["shield", "armor_chest", "armor_shoulder", "head", "horse", "miss"]
const LANCE_OUTCOME_NAMES := ["intact", "tip_break", "full_break"]
const FALL_TYPE_NAMES := ["unhorsed", "horse_fell"]
const BODY_ZONE_NAMES := ["head", "shoulder", "chest", "lance_arm", "shield_arm", "hip"]
const SEVERITY_NAMES := ["MINOR", "MODERATE", "SEVERE", "CRITICAL"]

const TOURNEY_TYPE_NAMES := ["Border Melee", "Lord's Challenge", "Crown Tourney"]

const TOURNEY_DESCRIPTIONS := [
	"A rough frontier affair. Loose rules, war lances permitted, anything short of murder.",
	"A private challenge between noble houses. Moderate rules, three passes, high stakes.",
	"The grandest tournament in the realm. Strict rules, courtly conduct, tourney lances.",
]


static func type_name(t: int) -> String:
	if t >= 0 and t < TOURNEY_TYPE_NAMES.size():
		return TOURNEY_TYPE_NAMES[t]
	return "Tourney"


static func rules_for_type(t: int) -> Dictionary:
	match clampi(t, 0, 2):
		TOURNEY_TYPE.BORDER_MELEE:
			return {
				"name": TOURNEY_TYPE_NAMES[0],
				"description": TOURNEY_DESCRIPTIONS[0],
				"num_passes": 5,
				"armor_contact_allowed": true,
				"min_speed_threshold": 0.4,
				"lance_type": LanceType.WAR,
				"unhorse_points": 5,
				"unhorse_wins_match": false,
				"head_hit_penalty": -5,
				"torso_hit_penalty": 0,
				"horse_hit_disqualify": true,
				"lance_tip_clash_voids_round": false,
			}
		TOURNEY_TYPE.LORDS_CHALLENGE:
			return {
				"name": TOURNEY_TYPE_NAMES[1],
				"description": TOURNEY_DESCRIPTIONS[1],
				"num_passes": 3,
				"armor_contact_allowed": true,
				"min_speed_threshold": 0.5,
				"lance_type": LanceType.TOURNEY,
				"unhorse_points": 10,
				"unhorse_wins_match": true,
				"head_hit_penalty": -5,
				"torso_hit_penalty": -5,
				"horse_hit_disqualify": true,
				"lance_tip_clash_voids_round": true,
			}
		_:
			return {
				"name": TOURNEY_TYPE_NAMES[2],
				"description": TOURNEY_DESCRIPTIONS[2],
				"num_passes": 3,
				"armor_contact_allowed": false,
				"min_speed_threshold": 0.6,
				"lance_type": LanceType.TOURNEY,
				"unhorse_points": 8,
				"unhorse_wins_match": true,
				"head_hit_penalty": -5,
				"torso_hit_penalty": -5,
				"horse_hit_disqualify": true,
				"lance_tip_clash_voids_round": true,
			}
