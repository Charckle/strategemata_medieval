from __future__ import annotations

import enum
from dataclasses import dataclass, field


class BodyZone(enum.Enum):
    HEAD = "head"
    SHOULDER = "shoulder"
    CHEST = "chest"
    LANCE_ARM = "lance_arm"
    SHIELD_ARM = "shield_arm"
    HIP = "hip"


class Severity(enum.Enum):
    MINOR = 1
    MODERATE = 2
    SEVERE = 3
    CRITICAL = 4

    def __lt__(self, other: "Severity") -> bool:
        return self.value < other.value

    def __le__(self, other: "Severity") -> bool:
        return self.value <= other.value


ZONE_PENALTY_MAP: dict[BodyZone, dict[str, int]] = {
    BodyZone.HEAD: {"skill": -1, "courage": -1},
    BodyZone.SHOULDER: {"strength": -1},
    BodyZone.CHEST: {"strength": -1, "endurance": -1},
    BodyZone.LANCE_ARM: {"skill": -1, "strength": -1},
    BodyZone.SHIELD_ARM: {"endurance": -1},
    BodyZone.HIP: {"endurance": -1},
}

SEVERITY_MULTIPLIER: dict[Severity, int] = {
    Severity.MINOR: 0,
    Severity.MODERATE: 1,
    Severity.SEVERE: 2,
    Severity.CRITICAL: 3,
}

ZONE_DESCRIPTIONS: dict[BodyZone, dict[Severity, list[str]]] = {
    BodyZone.HEAD: {
        Severity.MINOR: ["a ringing in the ears", "a rattled helm"],
        Severity.MODERATE: ["a mild concussion", "blurred vision"],
        Severity.SEVERE: ["a heavy concussion", "a cracked visor digs into the brow"],
        Severity.CRITICAL: ["a devastating blow to the skull — consciousness fades"],
    },
    BodyZone.SHOULDER: {
        Severity.MINOR: ["a bruised shoulder"],
        Severity.MODERATE: ["a strained shoulder", "a dented pauldron presses the joint"],
        Severity.SEVERE: ["a dislocated shoulder"],
        Severity.CRITICAL: ["a shattered shoulder — the arm hangs limp"],
    },
    BodyZone.CHEST: {
        Severity.MINOR: ["a bruise across the ribs"],
        Severity.MODERATE: ["bruised ribs", "a winded feeling that won't pass"],
        Severity.SEVERE: ["cracked ribs — every breath is agony"],
        Severity.CRITICAL: ["broken ribs — a punctured lung is feared"],
    },
    BodyZone.LANCE_ARM: {
        Severity.MINOR: ["a sore wrist"],
        Severity.MODERATE: ["a strained wrist", "numbness in the lance hand"],
        Severity.SEVERE: ["a fractured forearm — gripping the lance is torment"],
        Severity.CRITICAL: ["a shattered lance arm — it cannot hold a weapon"],
    },
    BodyZone.SHIELD_ARM: {
        Severity.MINOR: ["a bruised shield arm"],
        Severity.MODERATE: ["a numbed shield arm from the repeated blows"],
        Severity.SEVERE: ["the shield arm buckles — can barely hold the shield"],
        Severity.CRITICAL: ["the shield arm is broken clean"],
    },
    BodyZone.HIP: {
        Severity.MINOR: ["a sore hip from the saddle"],
        Severity.MODERATE: ["a bruised hip — sitting the saddle is painful"],
        Severity.SEVERE: ["a cracked pelvis — staying mounted is desperate work"],
        Severity.CRITICAL: ["the hip is shattered — cannot mount a horse"],
    },
}


@dataclass
class Injury:
    zone: BodyZone
    severity: Severity
    description: str
    stat_penalties: dict[str, int] = field(default_factory=dict)

    @classmethod
    def create(cls, zone: BodyZone, severity: Severity) -> "Injury":
        import random

        descriptions = ZONE_DESCRIPTIONS.get(zone, {}).get(severity, ["an injury"])
        description = random.choice(descriptions)
        base_penalties = ZONE_PENALTY_MAP.get(zone, {})
        multiplier = SEVERITY_MULTIPLIER[severity]
        penalties = {stat: val * multiplier for stat, val in base_penalties.items()}
        return cls(zone=zone, severity=severity, description=description, stat_penalties=penalties)

    def worsen(self) -> bool:
        """Attempt to worsen the injury. Returns True if it worsened."""
        import random

        if self.severity == Severity.CRITICAL:
            return False
        if self.severity == Severity.SEVERE and random.random() < 0.3:
            self.severity = Severity.CRITICAL
            descs = ZONE_DESCRIPTIONS.get(self.zone, {}).get(Severity.CRITICAL, [self.description])
            self.description = random.choice(descs)
            base_penalties = ZONE_PENALTY_MAP.get(self.zone, {})
            self.stat_penalties = {
                stat: val * SEVERITY_MULTIPLIER[Severity.CRITICAL]
                for stat, val in base_penalties.items()
            }
            return True
        return False
