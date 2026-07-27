from __future__ import annotations

import enum
import random
from dataclasses import dataclass, field
from typing import Optional

from .knight import Knight, LanceType


class TournamentType(enum.Enum):
    CROWN_TOURNEY = "Crown Tourney"
    BORDER_MELEE = "Border Melee"
    LORDS_CHALLENGE = "Lord's Challenge"


TOURNAMENT_PRESETS: dict[TournamentType, dict] = {
    TournamentType.CROWN_TOURNEY: {
        "description": "The grandest tournament in the realm. Strict rules, courtly conduct, tourney lances.",
        "num_passes": 3,
        "armor_contact_allowed": False,
        "min_speed_threshold": 0.6,
        "lance_type": LanceType.TOURNEY,
        "unhorse_points": 8,
        "unhorse_wins_match": True,
        "head_hit_penalty": -5,
        "torso_hit_penalty": -5,
        "horse_hit_disqualify": True,
        "lance_tip_clash_voids_round": True,
        "num_knights": 16,
    },
    TournamentType.BORDER_MELEE: {
        "description": "A rough frontier affair. Loose rules, war lances permitted, anything short of murder.",
        "num_passes": 5,
        "armor_contact_allowed": True,
        "min_speed_threshold": 0.4,
        "lance_type": LanceType.WAR,
        "unhorse_points": 5,
        "unhorse_wins_match": False,
        "head_hit_penalty": -5,
        "torso_hit_penalty": 0,
        "horse_hit_disqualify": True,
        "lance_tip_clash_voids_round": False,
        "num_knights": 8,
    },
    TournamentType.LORDS_CHALLENGE: {
        "description": "A private challenge between noble houses. Moderate rules, three passes, high stakes.",
        "num_passes": 3,
        "armor_contact_allowed": True,
        "min_speed_threshold": 0.5,
        "lance_type": LanceType.TOURNEY,
        "unhorse_points": 10,
        "unhorse_wins_match": True,
        "head_hit_penalty": -5,
        "torso_hit_penalty": -5,
        "horse_hit_disqualify": True,
        "lance_tip_clash_voids_round": True,
        "num_knights": 8,
    },
}


@dataclass
class TournamentRules:
    name: str
    description: str
    num_passes: int
    armor_contact_allowed: bool
    min_speed_threshold: float
    lance_type: LanceType
    unhorse_points: int
    unhorse_wins_match: bool
    head_hit_penalty: int
    torso_hit_penalty: int
    horse_hit_disqualify: bool
    lance_tip_clash_voids_round: bool
    num_knights: int

    @classmethod
    def from_preset(cls, tournament_type: TournamentType) -> "TournamentRules":
        preset = TOURNAMENT_PRESETS[tournament_type]
        return cls(name=tournament_type.value, **preset)


@dataclass
class Match:
    knight_a: Knight
    knight_b: Knight
    round_number: int
    match_number: int
    winner: Optional[Knight] = None
    loser: Optional[Knight] = None
    finished: bool = False


@dataclass
class TournamentBracket:
    rules: TournamentRules
    knights: list[Knight]
    rounds: list[list[Match]] = field(default_factory=list)
    current_round: int = 0

    def __post_init__(self) -> None:
        n = len(self.knights)
        if n & (n - 1) != 0:
            raise ValueError(f"Number of knights must be a power of 2, got {n}")

    def generate_bracket(self) -> None:
        shuffled = list(self.knights)
        random.shuffle(shuffled)
        self.rounds = []
        self.current_round = 0
        first_round: list[Match] = []
        for i in range(0, len(shuffled), 2):
            first_round.append(
                Match(
                    knight_a=shuffled[i],
                    knight_b=shuffled[i + 1],
                    round_number=0,
                    match_number=i // 2,
                )
            )
        self.rounds.append(first_round)

    def advance_round(self) -> Optional[list[Match]]:
        current_matches = self.rounds[self.current_round]
        winners = []
        for m in current_matches:
            if m.winner is None:
                return None
            winners.append(m.winner)
        if len(winners) == 1:
            return None
        self.current_round += 1
        next_round: list[Match] = []
        for i in range(0, len(winners), 2):
            next_round.append(
                Match(
                    knight_a=winners[i],
                    knight_b=winners[i + 1],
                    round_number=self.current_round,
                    match_number=i // 2,
                )
            )
        self.rounds.append(next_round)
        return next_round

    @property
    def champion(self) -> Optional[Knight]:
        if not self.rounds:
            return None
        final = self.rounds[-1]
        if len(final) == 1 and final[0].winner is not None:
            return final[0].winner
        return None

    @property
    def total_rounds(self) -> int:
        n = len(self.knights)
        count = 0
        while n > 1:
            n //= 2
            count += 1
        return count

    def round_name(self, round_idx: int) -> str:
        remaining = self.total_rounds - round_idx
        names = {1: "FINAL", 2: "SEMI-FINAL", 3: "QUARTER-FINAL"}
        return names.get(remaining, f"ROUND {round_idx + 1}")
