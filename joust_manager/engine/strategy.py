"""Strategy system: decision points in the joust."""
from __future__ import annotations

import enum
import random
from dataclasses import dataclass
from typing import Protocol

from ..models.knight import Knight, Personality
from ..models.tournament import TournamentRules


class AimTarget(enum.Enum):
    SHIELD_CENTER = "shield_center"
    SHIELD_EDGE = "shield_edge"
    ARMOR = "armor"
    HIGH = "high"                   # risky, might hit head


class Aggression(enum.Enum):
    CONSERVATIVE = "conservative"   # safe speed, less force
    NORMAL = "normal"
    AGGRESSIVE = "aggressive"       # push horse hard, more force + fatigue


class ShieldGuard(enum.Enum):
    HIGH = "high"                   # protect head
    CENTER = "center"
    LOW = "low"                     # protect body, head exposed


@dataclass
class PassDecision:
    aim: AimTarget
    aggression: Aggression
    shield_guard: ShieldGuard


@dataclass
class PassContext:
    pass_number: int
    total_passes: int
    own_score: int
    opponent_score: int
    own_injuries: int               # count of moderate+ injuries
    opponent_injuries: int
    own_horse_fatigue: float        # 0.0 (fresh) to 1.0 (spent)
    opponent_horse_fatigue: float
    own_lance_broken: bool
    rules: TournamentRules


class Strategy(Protocol):
    def decide(self, knight: Knight, context: PassContext) -> PassDecision: ...


class AIStrategy:
    """Personality-driven AI decision-making."""

    def decide(self, knight: Knight, context: PassContext) -> PassDecision:
        personality = knight.personality
        courage = knight.effective_courage
        score_diff = context.own_score - context.opponent_score

        aim = self._choose_aim(personality, courage, score_diff, context)
        aggression = self._choose_aggression(personality, knight, context)
        guard = self._choose_guard(personality, courage, context)
        return PassDecision(aim=aim, aggression=aggression, shield_guard=guard)

    def _choose_aim(
        self, personality: Personality, courage: int, score_diff: int, ctx: PassContext
    ) -> AimTarget:
        if personality == Personality.RECKLESS:
            return random.choice([AimTarget.ARMOR, AimTarget.HIGH, AimTarget.SHIELD_CENTER])

        if personality == Personality.CAUTIOUS or score_diff > 3:
            return random.choice([AimTarget.SHIELD_CENTER, AimTarget.SHIELD_CENTER, AimTarget.SHIELD_EDGE])

        if personality == Personality.BOLD:
            if score_diff < -2 and courage >= 6:
                return random.choice([AimTarget.ARMOR, AimTarget.SHIELD_CENTER])
            return random.choice([AimTarget.SHIELD_CENTER, AimTarget.ARMOR, AimTarget.SHIELD_EDGE])

        # BALANCED
        if score_diff < -3:
            return random.choice([AimTarget.ARMOR, AimTarget.SHIELD_CENTER])
        return AimTarget.SHIELD_CENTER

    def _choose_aggression(
        self, personality: Personality, knight: Knight, ctx: PassContext
    ) -> Aggression:
        fatigue = ctx.own_horse_fatigue

        if fatigue > 0.7:
            return Aggression.CONSERVATIVE

        if personality == Personality.RECKLESS:
            return Aggression.AGGRESSIVE
        if personality == Personality.CAUTIOUS:
            return Aggression.CONSERVATIVE if fatigue > 0.4 else Aggression.NORMAL
        if personality == Personality.BOLD:
            return Aggression.AGGRESSIVE if knight.effective_courage >= 6 else Aggression.NORMAL

        return Aggression.NORMAL

    def _choose_guard(
        self, personality: Personality, courage: int, ctx: PassContext
    ) -> ShieldGuard:
        if personality == Personality.RECKLESS:
            return random.choice([ShieldGuard.CENTER, ShieldGuard.LOW])

        if personality == Personality.CAUTIOUS:
            return ShieldGuard.HIGH

        if ctx.own_injuries > 1:
            return ShieldGuard.HIGH

        return ShieldGuard.CENTER
