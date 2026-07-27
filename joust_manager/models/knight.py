from __future__ import annotations

import enum
from dataclasses import dataclass, field


class Personality(enum.Enum):
    BOLD = "bold"
    CAUTIOUS = "cautious"
    BALANCED = "balanced"
    RECKLESS = "reckless"


class Temperament(enum.Enum):
    BRAVE = "brave"
    NERVOUS = "nervous"
    STEADY = "steady"
    FIERY = "fiery"


class LanceType(enum.Enum):
    TOURNEY = "tourney"
    WAR = "war"


@dataclass
class Horse:
    name: str
    speed: int          # 1-10, charge momentum
    steadiness: int     # 1-10, how straight the line
    stamina: int        # 1-10, max stamina
    temperament: Temperament
    current_stamina: float = 0.0

    def __post_init__(self) -> None:
        if self.current_stamina == 0.0:
            self.current_stamina = float(self.stamina)

    @property
    def fatigue_factor(self) -> float:
        """1.0 when fresh, drops toward 0.0 as stamina drains."""
        return max(0.0, self.current_stamina / self.stamina)

    def drain(self, amount: float) -> None:
        self.current_stamina = max(0.0, self.current_stamina - amount)

    def rest(self, amount: float) -> None:
        self.current_stamina = min(float(self.stamina), self.current_stamina + amount)


@dataclass
class ArmorPiece:
    protection: int     # 1-10
    quality: int        # 1-10
    weight: float       # kg-ish abstract units

    @property
    def effective_protection(self) -> float:
        return self.protection * (0.5 + 0.05 * self.quality)


@dataclass
class Shield:
    protection: int
    quality: int
    weight: float

    @property
    def effective_protection(self) -> float:
        return self.protection * (0.5 + 0.05 * self.quality)


@dataclass
class Armor:
    helm: ArmorPiece
    pauldrons: ArmorPiece
    breastplate: ArmorPiece
    shield: Shield

    @property
    def total_weight(self) -> float:
        return (
            self.helm.weight
            + self.pauldrons.weight
            + self.breastplate.weight
            + self.shield.weight
        )

    def protection_for_zone(self, zone: str) -> float:
        mapping = {
            "head": self.helm,
            "shoulder": self.pauldrons,
            "chest": self.breastplate,
            "shield": self.shield,
        }
        piece = mapping.get(zone)
        if piece is None:
            return 0.0
        return piece.effective_protection


@dataclass
class Lance:
    lance_type: LanceType
    quality: int        # 1-10
    material: str       # "ash", "pine", "oak"
    broken: bool = False

    @property
    def break_threshold(self) -> float:
        """Higher = harder to break. War lances are sturdier."""
        base = 4.0 + 0.6 * self.quality
        material_bonus = {"pine": -1.0, "ash": 0.0, "oak": 1.5}.get(self.material, 0.0)
        type_bonus = 2.0 if self.lance_type == LanceType.WAR else 0.0
        return base + material_bonus + type_bonus


@dataclass
class Knight:
    name: str
    strength: int       # 1-10
    skill: int          # 1-10
    endurance: int      # 1-10
    courage: int        # 1-10
    personality: Personality
    horse: Horse
    armor: Armor
    lance: Lance
    injuries: list = field(default_factory=list)
    score: int = 0
    disqualified: bool = False
    withdrawn: bool = False

    @property
    def effective_strength(self) -> int:
        penalty = sum(
            inj.stat_penalties.get("strength", 0) for inj in self.injuries
        )
        return max(1, self.strength + penalty)

    @property
    def effective_skill(self) -> int:
        penalty = sum(
            inj.stat_penalties.get("skill", 0) for inj in self.injuries
        )
        return max(1, self.skill + penalty)

    @property
    def effective_endurance(self) -> int:
        penalty = sum(
            inj.stat_penalties.get("endurance", 0) for inj in self.injuries
        )
        return max(1, self.endurance + penalty)

    @property
    def effective_courage(self) -> int:
        penalty = sum(
            inj.stat_penalties.get("courage", 0) for inj in self.injuries
        )
        return max(1, self.courage + penalty)

    @property
    def can_fight(self) -> bool:
        if self.disqualified or self.withdrawn:
            return False
        from .injury import Severity
        return not any(inj.severity == Severity.CRITICAL for inj in self.injuries)

    def reset_for_match(self) -> None:
        self.score = 0
        self.disqualified = False
        self.lance.broken = False

    def heal_between_matches(self) -> list[str]:
        """Minor injuries heal; moderate may improve. Returns narration lines."""
        from .injury import Severity
        import random

        healed: list[str] = []
        remaining: list = []
        for inj in self.injuries:
            if inj.severity == Severity.MINOR:
                healed.append(f"  {inj.description} has healed.")
            elif inj.severity == Severity.MODERATE:
                if random.random() < 0.3 + 0.05 * self.endurance:
                    inj.severity = Severity.MINOR
                    inj.stat_penalties = {}
                    healed.append(f"  {inj.description} has improved — no longer affecting performance.")
                else:
                    remaining.append(inj)
            else:
                remaining.append(inj)
        self.injuries = remaining
        return healed
