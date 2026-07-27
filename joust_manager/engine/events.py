"""Structured events emitted by the joust engine for narration."""
from __future__ import annotations

import enum
from dataclasses import dataclass, field
from typing import Optional


class HitZone(enum.Enum):
    SHIELD = "shield"
    ARMOR_CHEST = "armor_chest"
    ARMOR_SHOULDER = "armor_shoulder"
    HEAD = "head"
    HORSE = "horse"
    MISS = "miss"


class LanceOutcome(enum.Enum):
    INTACT = "intact"
    TIP_BREAK = "tip_break"
    FULL_BREAK = "full_break"


class FallType(enum.Enum):
    UNHORSED = "unhorsed"          # knight knocked off
    HORSE_FELL = "horse_fell"       # horse went down (knight falls with horse)


@dataclass
class ApproachEvent:
    knight_name: str
    horse_name: str
    speed_factor: float             # 0.0-1.0, effective charge speed
    speed_penalty: bool             # below minimum threshold?
    horse_shied: bool               # horse refused/slowed?


@dataclass
class LanceTipClashEvent:
    knight_a: str
    knight_b: str


@dataclass
class ImpactEvent:
    attacker: str
    defender: str
    hit_zone: HitZone
    force: float
    lance_outcome: LanceOutcome
    score_change: int
    penalty: int                    # negative points for illegal hits


@dataclass
class FallEvent:
    knight_name: str
    fall_type: FallType
    caused_by: str                  # name of knight whose strike caused it, or "horse stumble"
    score_awarded: int


@dataclass
class InjuryEvent:
    knight_name: str
    zone: str
    severity: str
    description: str
    worsened: bool                  # was this an existing injury that got worse?


@dataclass
class DisqualificationEvent:
    knight_name: str
    reason: str


@dataclass
class PassSummaryEvent:
    pass_number: int
    knight_a: str
    knight_b: str
    score_a: int
    score_b: int


@dataclass
class NewLanceEvent:
    knight_name: str
    material: str


@dataclass
class MatchEndEvent:
    winner: str
    loser: str
    final_score_winner: int
    final_score_loser: int
    reason: str                     # "points", "unhorsing", "disqualification", "withdrawal"


@dataclass
class SpeedCheckEvent:
    knight_name: str
    speed_factor: float
    threshold: float
    passed: bool


# A single pass produces a sequence of events
PassEvents = list
