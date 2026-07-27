"""Dwarf Fortress-style narration from structured engine events."""
from __future__ import annotations

import random
from typing import Any

from ..engine.events import (
    ApproachEvent,
    DisqualificationEvent,
    FallEvent,
    FallType,
    HitZone,
    ImpactEvent,
    InjuryEvent,
    LanceOutcome,
    LanceTipClashEvent,
    MatchEndEvent,
    NewLanceEvent,
    PassSummaryEvent,
    SpeedCheckEvent,
)


def _pick(*options: str) -> str:
    return random.choice(options)


class Narrator:
    """Converts engine events into DF-style prose."""

    def narrate_pass(self, events: list, verbose: bool = True) -> list[str]:
        lines: list[str] = []
        for event in events:
            result = self._narrate_event(event, verbose)
            if result:
                lines.extend(result if isinstance(result, list) else [result])
        return lines

    def narrate_match_brief(self, events_per_pass: list[list]) -> list[str]:
        """Short summary for off-screen matches."""
        lines: list[str] = []
        for pass_events in events_per_pass:
            for event in pass_events:
                if isinstance(event, FallEvent):
                    if event.fall_type == FallType.UNHORSED:
                        lines.append(f"  {event.knight_name} was unhorsed by {event.caused_by}!")
                    else:
                        lines.append(f"  {event.knight_name}'s horse went down beneath them!")
                elif isinstance(event, DisqualificationEvent):
                    lines.append(f"  {event.knight_name} was DISQUALIFIED — {event.reason}!")
                elif isinstance(event, MatchEndEvent):
                    lines.append(
                        f"  RESULT: {event.winner} defeats {event.loser} "
                        f"({event.final_score_winner}-{event.final_score_loser}, {event.reason})"
                    )
        return lines

    def _narrate_event(self, event: Any, verbose: bool) -> list[str] | str | None:
        if isinstance(event, ApproachEvent):
            return self._narrate_approach(event, verbose)
        elif isinstance(event, SpeedCheckEvent):
            return self._narrate_speed_check(event, verbose)
        elif isinstance(event, LanceTipClashEvent):
            return self._narrate_tip_clash(event)
        elif isinstance(event, ImpactEvent):
            return self._narrate_impact(event, verbose)
        elif isinstance(event, FallEvent):
            return self._narrate_fall(event)
        elif isinstance(event, InjuryEvent):
            return self._narrate_injury(event)
        elif isinstance(event, DisqualificationEvent):
            return self._narrate_disqualification(event)
        elif isinstance(event, NewLanceEvent):
            return self._narrate_new_lance(event, verbose)
        elif isinstance(event, PassSummaryEvent):
            return self._narrate_pass_summary(event)
        elif isinstance(event, MatchEndEvent):
            return self._narrate_match_end(event)
        return None

    def _narrate_approach(self, e: ApproachEvent, verbose: bool) -> list[str] | None:
        if not verbose:
            return None
        lines: list[str] = []
        if e.horse_shied:
            lines.append(
                f"{e.knight_name}'s mount, {e.horse_name}, "
                + _pick(
                    "balks and shies at the tilt!",
                    "tosses its head and slows!",
                    "breaks stride, fighting the reins!",
                )
            )
        else:
            if e.speed_factor > 0.8:
                lines.append(
                    f"{e.knight_name} "
                    + _pick(
                        f"spurs {e.horse_name} into a thundering gallop!",
                        f"leans forward as {e.horse_name} surges down the tilt!",
                        f"charges hard — {e.horse_name}'s hooves pound the packed earth!",
                    )
                )
            elif e.speed_factor > 0.5:
                lines.append(
                    f"{e.knight_name} "
                    + _pick(
                        f"rides steadily on {e.horse_name}.",
                        f"guides {e.horse_name} into a measured canter.",
                        f"advances at a solid pace aboard {e.horse_name}.",
                    )
                )
            else:
                lines.append(
                    f"{e.knight_name} "
                    + _pick(
                        f"struggles to coax speed from the tiring {e.horse_name}.",
                        f"plods forward — {e.horse_name} is flagging.",
                        f"manages only a sluggish trot on the exhausted {e.horse_name}.",
                    )
                )
        return lines

    def _narrate_speed_check(self, e: SpeedCheckEvent, verbose: bool) -> str | None:
        if e.passed:
            return None
        return (
            f"  *** {e.knight_name} fails to reach the required speed! "
            f"(-5 points penalty) ***"
        )

    def _narrate_tip_clash(self, e: LanceTipClashEvent) -> list[str]:
        return [
            "",
            _pick(
                f"The lance tips of {e.knight_a} and {e.knight_b} collide mid-tilt!",
                f"A crack rings out — both lances meet tip-to-tip!",
                f"The points of both lances clash together with a sharp crack!",
            ),
            "The marshals confer — the pass is VOIDED and must be re-run!",
            "",
        ]

    def _narrate_impact(self, e: ImpactEvent, verbose: bool) -> list[str]:
        lines: list[str] = []

        if e.hit_zone == HitZone.MISS:
            lines.append(
                f"{e.attacker}'s lance "
                + _pick(
                    f"finds only empty air as {e.defender} twists aside.",
                    f"sweeps wide — a clean miss!",
                    f"passes harmlessly past {e.defender}.",
                )
            )
            return lines

        if e.hit_zone == HitZone.HORSE:
            lines.append(
                f"*** {e.attacker}'s lance drops LOW and strikes {e.defender}'s horse! ***"
            )
            return lines

        zone_text = {
            HitZone.SHIELD: "shield",
            HitZone.ARMOR_CHEST: "breastplate",
            HitZone.ARMOR_SHOULDER: "pauldron",
            HitZone.HEAD: "helm",
        }[e.hit_zone]

        # Impact verb based on force
        if e.force > 7:
            verb = _pick("SLAMS into", "CRASHES against", "strikes with tremendous force upon")
        elif e.force > 4:
            verb = _pick("strikes", "connects solidly with", "hits")
        else:
            verb = _pick("glances off", "scrapes across", "brushes against")

        lines.append(f"{e.attacker}'s lance {verb} {e.defender}'s {zone_text}!")

        # Lance break narration
        if e.lance_outcome == LanceOutcome.FULL_BREAK:
            lines.append(
                _pick(
                    "The shaft SHATTERS into pieces! Splinters fly across the tilt!",
                    "The lance EXPLODES on impact! Fragments rain down!",
                    "With a tremendous crack, the lance breaks into three pieces!",
                )
            )
        elif e.lance_outcome == LanceOutcome.TIP_BREAK:
            lines.append(
                _pick(
                    "The lance tip snaps off on impact!",
                    "The point of the lance breaks away!",
                    "The tip splinters — a clean break of the point!",
                )
            )

        # Score narration
        if e.score_change > 0:
            lines.append(f"  [+{e.score_change} points to {e.attacker}]")
        if e.penalty < 0:
            zone_name = "head" if e.hit_zone == HitZone.HEAD else "body"
            lines.append(f"  *** PENALTY: Illegal hit to the {zone_name}! ({e.penalty} points) ***")

        return lines

    def _narrate_fall(self, e: FallEvent) -> list[str]:
        lines: list[str] = [""]
        if e.fall_type == FallType.UNHORSED:
            lines.append(
                _pick(
                    f"{e.knight_name} is KNOCKED CLEAN from the saddle!",
                    f"{e.knight_name} flies from the horse and crashes to the ground!",
                    f"The blow sends {e.knight_name} tumbling from the saddle!",
                )
            )
            lines.append(
                _pick(
                    "Armor clangs against the hard-packed earth!",
                    "A cloud of dust rises from the fall!",
                    "The crowd gasps as the knight hits the ground!",
                )
            )
            if e.score_awarded:
                lines.append(f"  [+{e.score_awarded} points to {e.caused_by} — UNHORSING!]")
        else:
            lines.append(
                _pick(
                    f"{e.knight_name}'s horse stumbles and goes DOWN!",
                    f"The legs of {e.knight_name}'s mount buckle — horse and rider crash together!",
                    f"{e.knight_name}'s horse collapses beneath them!",
                )
            )
            lines.append(
                "  The fall was the horse's fault — the rider bears no disgrace."
            )
        lines.append("")
        return lines

    def _narrate_injury(self, e: InjuryEvent) -> str:
        if e.worsened:
            return (
                f"  {e.knight_name}'s existing {e.zone} injury WORSENS — "
                f"{e.description}! [{e.severity}]"
            )
        severity_word = {
            "MINOR": "",
            "MODERATE": "  ** ",
            "SEVERE": "  *** ",
            "CRITICAL": "  **** ",
        }.get(e.severity, "  ")
        end = {
            "MINOR": "",
            "MODERATE": " **",
            "SEVERE": " ***",
            "CRITICAL": " ****",
        }.get(e.severity, "")
        return f"{severity_word}{e.knight_name} suffers {e.description}!{end}"

    def _narrate_disqualification(self, e: DisqualificationEvent) -> list[str]:
        return [
            "",
            f"*** {e.knight_name} is DISQUALIFIED — {e.reason}! ***",
            "The marshals raise the black flag. The crowd jeers!",
            "",
        ]

    def _narrate_new_lance(self, e: NewLanceEvent, verbose: bool) -> str | None:
        if not verbose:
            return None
        return f"{e.knight_name} is handed a fresh {e.material} lance."

    def _narrate_pass_summary(self, e: PassSummaryEvent) -> list[str]:
        return [
            "",
            f"═══ End of Pass {e.pass_number}: "
            f"{e.knight_a} [{e.score_a}] vs {e.knight_b} [{e.score_b}] ═══",
            "",
        ]

    def _narrate_match_end(self, e: MatchEndEvent) -> list[str]:
        lines = ["", "━" * 50]
        reason_text = {
            "points": "on points",
            "unhorsing": "by UNHORSING",
            "disqualification": "by DISQUALIFICATION of the opponent",
            "withdrawal": "as the opponent could not continue",
        }.get(e.reason, e.reason)

        lines.append(
            f"  VICTORY: {e.winner} defeats {e.loser} {reason_text}!"
        )
        lines.append(
            f"  Final score: {e.final_score_winner} - {e.final_score_loser}"
        )
        lines.append("━" * 50)
        lines.append("")
        return lines
