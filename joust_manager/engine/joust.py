"""Core joust engine: resolves passes, scoring, injuries, and match outcomes."""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Optional

from ..models.injury import BodyZone, Injury, Severity
from ..models.knight import Knight, Lance, LanceType
from ..models.tournament import Match, TournamentRules
from .events import (
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
from .strategy import AIStrategy, Aggression, AimTarget, PassContext, PassDecision, ShieldGuard, Strategy

HITZONE_TO_BODYZONE: dict[HitZone, BodyZone] = {
    HitZone.SHIELD: BodyZone.SHIELD_ARM,
    HitZone.ARMOR_CHEST: BodyZone.CHEST,
    HitZone.ARMOR_SHOULDER: BodyZone.SHOULDER,
    HitZone.HEAD: BodyZone.HEAD,
}

HITZONE_TO_ARMOR_ZONE: dict[HitZone, str] = {
    HitZone.SHIELD: "shield",
    HitZone.ARMOR_CHEST: "chest",
    HitZone.ARMOR_SHOULDER: "shoulder",
    HitZone.HEAD: "head",
}


@dataclass
class MatchResult:
    events_per_pass: list[list]     # list of pass event-lists
    winner: Knight
    loser: Knight
    final_event: MatchEndEvent


class JoustEngine:
    """Resolves a full match between two knights."""

    def __init__(self, rules: TournamentRules, strategy_a: Strategy | None = None, strategy_b: Strategy | None = None):
        self.rules = rules
        self.strategy_a = strategy_a or AIStrategy()
        self.strategy_b = strategy_b or AIStrategy()

    def run_match(self, knight_a: Knight, knight_b: Knight) -> MatchResult:
        knight_a.reset_for_match()
        knight_b.reset_for_match()
        knight_a.horse.current_stamina = float(knight_a.horse.stamina)
        knight_b.horse.current_stamina = float(knight_b.horse.stamina)

        all_events: list[list] = []
        pass_num = 0

        while pass_num < self.rules.num_passes:
            pass_num += 1
            score_a_before = knight_a.score
            score_b_before = knight_b.score
            events = self._resolve_pass(knight_a, knight_b, pass_num)
            all_events.append(events)

            if self.rules.lance_tip_clash_voids_round and any(
                isinstance(e, LanceTipClashEvent) for e in events
            ):
                knight_a.score = score_a_before
                knight_b.score = score_b_before
                pass_num -= 1
                continue

            if knight_a.disqualified or knight_b.disqualified:
                break
            if not knight_a.can_fight or not knight_b.can_fight:
                break

            # Check for unhorsing ending the match
            for e in events:
                if isinstance(e, FallEvent) and self.rules.unhorse_wins_match:
                    break
            else:
                continue
            break

        winner, loser, reason = self._determine_winner(knight_a, knight_b)

        final = MatchEndEvent(
            winner=winner.name,
            loser=loser.name,
            final_score_winner=winner.score,
            final_score_loser=loser.score,
            reason=reason,
        )
        all_events.append([final])

        return MatchResult(
            events_per_pass=all_events,
            winner=winner,
            loser=loser,
            final_event=final,
        )

    def _resolve_pass(self, knight_a: Knight, knight_b: Knight, pass_number: int) -> list:
        events: list = []

        ctx_a = self._build_context(knight_a, knight_b, pass_number)
        ctx_b = self._build_context(knight_b, knight_a, pass_number)
        decision_a = self.strategy_a.decide(knight_a, ctx_a)
        decision_b = self.strategy_b.decide(knight_b, ctx_b)

        # --- Approach phase ---
        speed_a, approach_a = self._resolve_approach(knight_a, decision_a)
        speed_b, approach_b = self._resolve_approach(knight_b, decision_b)
        events.append(approach_a)
        events.append(approach_b)

        # --- Speed checks ---
        speed_check_a = self._speed_check(knight_a, speed_a)
        speed_check_b = self._speed_check(knight_b, speed_b)
        events.append(speed_check_a)
        events.append(speed_check_b)
        if not speed_check_a.passed:
            knight_a.score -= 5
        if not speed_check_b.passed:
            knight_b.score -= 5

        # --- Lance tip clash check ---
        if self._check_lance_tip_clash(decision_a, decision_b):
            events.append(LanceTipClashEvent(knight_a.name, knight_b.name))
            events.append(PassSummaryEvent(pass_number, knight_a.name, knight_b.name, knight_a.score, knight_b.score))
            return events

        # --- Impact: A strikes B ---
        if not knight_a.lance.broken:
            impact_events_a = self._resolve_impact(knight_a, knight_b, decision_a, decision_b, speed_a)
            events.extend(impact_events_a)

        # --- Impact: B strikes A ---
        if not knight_b.lance.broken:
            impact_events_b = self._resolve_impact(knight_b, knight_a, decision_b, decision_a, speed_b)
            events.extend(impact_events_b)

        # --- Replace broken lances ---
        if knight_a.lance.broken:
            knight_a.lance = self._fresh_lance()
            events.append(NewLanceEvent(knight_a.name, knight_a.lance.material))
        if knight_b.lance.broken:
            knight_b.lance = self._fresh_lance()
            events.append(NewLanceEvent(knight_b.name, knight_b.lance.material))

        # --- Drain horse stamina ---
        self._drain_horses(knight_a, knight_b, decision_a, decision_b)

        events.append(PassSummaryEvent(pass_number, knight_a.name, knight_b.name, knight_a.score, knight_b.score))
        return events

    def _resolve_approach(self, knight: Knight, decision: PassDecision) -> tuple[float, ApproachEvent]:
        horse = knight.horse
        base_speed = horse.speed / 10.0
        fatigue_mod = horse.fatigue_factor

        aggression_mod = {
            Aggression.CONSERVATIVE: 0.8,
            Aggression.NORMAL: 1.0,
            Aggression.AGGRESSIVE: 1.15,
        }[decision.aggression]

        weight_penalty = max(0.0, (knight.armor.total_weight - 20.0) / 80.0)

        horse_shied = False
        shy_mod = 1.0
        if horse.temperament.value == "nervous" and random.random() < 0.15:
            horse_shied = True
            shy_mod = 0.6
        elif horse.temperament.value == "fiery" and random.random() < 0.05:
            horse_shied = True
            shy_mod = 0.7

        speed = base_speed * fatigue_mod * aggression_mod * shy_mod - weight_penalty
        speed = max(0.1, min(1.0, speed))

        speed_penalty = speed < self.rules.min_speed_threshold

        event = ApproachEvent(
            knight_name=knight.name,
            horse_name=knight.horse.name,
            speed_factor=speed,
            speed_penalty=speed_penalty,
            horse_shied=horse_shied,
        )
        return speed, event

    def _speed_check(self, knight: Knight, speed: float) -> SpeedCheckEvent:
        passed = speed >= self.rules.min_speed_threshold
        return SpeedCheckEvent(
            knight_name=knight.name,
            speed_factor=speed,
            threshold=self.rules.min_speed_threshold,
            passed=passed,
        )

    def _check_lance_tip_clash(self, dec_a: PassDecision, dec_b: PassDecision) -> bool:
        both_center = (
            dec_a.aim == AimTarget.SHIELD_CENTER and dec_b.aim == AimTarget.SHIELD_CENTER
        )
        base_chance = 0.08 if both_center else 0.02
        return random.random() < base_chance

    def _resolve_impact(
        self,
        attacker: Knight,
        defender: Knight,
        att_decision: PassDecision,
        def_decision: PassDecision,
        speed: float,
    ) -> list:
        events: list = []
        hit_zone = self._determine_hit_zone(attacker, att_decision, def_decision)

        if hit_zone == HitZone.MISS:
            events.append(ImpactEvent(
                attacker=attacker.name, defender=defender.name,
                hit_zone=HitZone.MISS, force=0.0,
                lance_outcome=LanceOutcome.INTACT, score_change=0, penalty=0,
            ))
            return events

        if hit_zone == HitZone.HORSE:
            events.append(ImpactEvent(
                attacker=attacker.name, defender=defender.name,
                hit_zone=HitZone.HORSE, force=0.0,
                lance_outcome=LanceOutcome.INTACT, score_change=0, penalty=0,
            ))
            if self.rules.horse_hit_disqualify:
                attacker.disqualified = True
                events.append(DisqualificationEvent(attacker.name, "struck the opponent's horse"))
            return events

        # --- Calculate force ---
        force = (
            attacker.effective_strength * 0.4
            + speed * 8.0
            + attacker.effective_skill * 0.2
            + random.uniform(-1.0, 1.0)
        )

        # --- Armor absorption ---
        armor_zone = HITZONE_TO_ARMOR_ZONE.get(hit_zone, "shield")
        protection = defender.armor.protection_for_zone(armor_zone)
        residual = force - protection * 0.5

        # --- Score + penalties ---
        score, penalty = self._calc_score(hit_zone, force, attacker.lance)
        attacker.score += score + penalty

        # --- Lance break check ---
        lance_outcome = self._check_lance_break(attacker.lance, force, hit_zone)

        events.append(ImpactEvent(
            attacker=attacker.name, defender=defender.name,
            hit_zone=hit_zone, force=force,
            lance_outcome=lance_outcome, score_change=score, penalty=penalty,
        ))

        # --- Injury check ---
        if residual > 0 and hit_zone != HitZone.SHIELD:
            injury_events = self._check_injury(defender, hit_zone, residual)
            events.extend(injury_events)

        # --- Fall check ---
        fall_event = self._check_fall(defender, force, residual)
        if fall_event:
            if fall_event.fall_type == FallType.UNHORSED:
                attacker.score += self.rules.unhorse_points
                fall_event = FallEvent(
                    knight_name=fall_event.knight_name,
                    fall_type=fall_event.fall_type,
                    caused_by=attacker.name,
                    score_awarded=self.rules.unhorse_points,
                )
            events.append(fall_event)

        return events

    def _determine_hit_zone(
        self, attacker: Knight, att_dec: PassDecision, def_dec: PassDecision
    ) -> HitZone:
        skill = attacker.effective_skill
        accuracy = skill / 10.0 + random.uniform(-0.2, 0.2)

        if accuracy < 0.2:
            return HitZone.MISS

        # Horse hit — rare, based on poor skill or bad luck
        if random.random() < max(0.0, 0.05 - skill * 0.005):
            return HitZone.HORSE

        aim = att_dec.aim
        guard = def_dec.shield_guard

        if aim == AimTarget.SHIELD_CENTER:
            return HitZone.SHIELD
        elif aim == AimTarget.SHIELD_EDGE:
            drift = random.random()
            if drift < 0.6:
                return HitZone.SHIELD
            elif drift < 0.85:
                return HitZone.ARMOR_SHOULDER
            else:
                return HitZone.MISS
        elif aim == AimTarget.ARMOR:
            if not self.rules.armor_contact_allowed:
                drift = random.random()
                if drift < 0.5:
                    return HitZone.SHIELD
                return HitZone.ARMOR_CHEST
            drift = random.random()
            if drift < 0.5:
                return HitZone.ARMOR_CHEST
            elif drift < 0.75:
                return HitZone.ARMOR_SHOULDER
            elif drift < 0.9:
                return HitZone.SHIELD
            else:
                return HitZone.MISS
        elif aim == AimTarget.HIGH:
            drift = random.random()
            guard_bonus = 0.3 if guard == ShieldGuard.HIGH else 0.0
            if drift < 0.3 - guard_bonus:
                return HitZone.HEAD
            elif drift < 0.6:
                return HitZone.SHIELD
            elif drift < 0.8:
                return HitZone.ARMOR_SHOULDER
            else:
                return HitZone.MISS

        return HitZone.SHIELD

    def _calc_score(self, hit_zone: HitZone, force: float, lance: Lance) -> tuple[int, int]:
        """Returns (base_score, penalty). Penalty is negative."""
        penalty = 0
        if hit_zone == HitZone.HEAD:
            penalty = self.rules.head_hit_penalty
        elif hit_zone in (HitZone.ARMOR_CHEST, HitZone.ARMOR_SHOULDER):
            if not self.rules.armor_contact_allowed:
                penalty = self.rules.torso_hit_penalty

        if hit_zone == HitZone.SHIELD:
            if force > lance.break_threshold * 1.3:
                return 3, penalty    # full break
            elif force > lance.break_threshold * 0.9:
                return 2, penalty    # tip break
            else:
                return 1, penalty    # contact
        elif hit_zone in (HitZone.ARMOR_CHEST, HitZone.ARMOR_SHOULDER):
            if force > lance.break_threshold * 1.2:
                return 2, penalty
            else:
                return 1, penalty
        elif hit_zone == HitZone.HEAD:
            return 0, penalty

        return 0, 0

    def _check_lance_break(self, lance: Lance, force: float, hit_zone: HitZone) -> LanceOutcome:
        if hit_zone == HitZone.MISS:
            return LanceOutcome.INTACT

        threshold = lance.break_threshold
        if force > threshold * 1.3:
            lance.broken = True
            return LanceOutcome.FULL_BREAK
        elif force > threshold * 0.9:
            lance.broken = True
            return LanceOutcome.TIP_BREAK
        return LanceOutcome.INTACT

    def _check_injury(self, defender: Knight, hit_zone: HitZone, residual: float) -> list:
        events: list = []
        body_zone = HITZONE_TO_BODYZONE.get(hit_zone)
        if body_zone is None:
            return events

        # Check if existing injury worsens
        for inj in defender.injuries:
            if inj.zone == body_zone and inj.severity == Severity.SEVERE:
                if inj.worsen():
                    events.append(InjuryEvent(
                        knight_name=defender.name,
                        zone=body_zone.value,
                        severity=inj.severity.name,
                        description=inj.description,
                        worsened=True,
                    ))
                    return events

        # New injury based on residual force
        if residual < 2.0:
            severity = Severity.MINOR
        elif residual < 4.0:
            severity = Severity.MODERATE
        elif residual < 6.5:
            severity = Severity.SEVERE
        else:
            severity = Severity.CRITICAL

        # Endurance can reduce severity
        if severity.value > 1 and random.random() < defender.effective_endurance * 0.07:
            severity = Severity(severity.value - 1)

        if severity == Severity.MINOR and random.random() < 0.5:
            return events

        injury = Injury.create(body_zone, severity)
        defender.injuries.append(injury)
        events.append(InjuryEvent(
            knight_name=defender.name,
            zone=body_zone.value,
            severity=severity.name,
            description=injury.description,
            worsened=False,
        ))
        return events

    def _check_fall(self, defender: Knight, force: float, residual: float) -> Optional[FallEvent]:
        # Unhorsing: based on force vs. rider stability
        stability = (
            defender.effective_strength * 0.3
            + defender.effective_endurance * 0.2
            + defender.horse.steadiness * 0.3
            + random.uniform(0, 2)
        )
        unhorse_threshold = 10.0 + stability * 0.6

        if force > unhorse_threshold:
            return FallEvent(
                knight_name=defender.name,
                fall_type=FallType.UNHORSED,
                caused_by="",
                score_awarded=0,
            )

        horse = defender.horse
        stumble_chance = 0.0
        if horse.fatigue_factor < 0.2:
            stumble_chance += 0.06
        if horse.temperament.value == "nervous":
            stumble_chance += 0.03
        if force > 8.0:
            stumble_chance += 0.03

        if random.random() < stumble_chance:
            return FallEvent(
                knight_name=defender.name,
                fall_type=FallType.HORSE_FELL,
                caused_by="horse stumble",
                score_awarded=0,
            )

        return None

    def _drain_horses(
        self, ka: Knight, kb: Knight, dec_a: PassDecision, dec_b: PassDecision
    ) -> None:
        drain_map = {
            Aggression.CONSERVATIVE: 0.5,
            Aggression.NORMAL: 0.8,
            Aggression.AGGRESSIVE: 1.3,
        }
        ka.horse.drain(drain_map[dec_a.aggression])
        kb.horse.drain(drain_map[dec_b.aggression])

    def _fresh_lance(self) -> Lance:
        from ..generation.generator import generate_lance
        return generate_lance(self.rules.lance_type)

    def _determine_winner(self, ka: Knight, kb: Knight) -> tuple[Knight, Knight, str]:
        if ka.disqualified:
            return kb, ka, "disqualification"
        if kb.disqualified:
            return ka, kb, "disqualification"

        if not ka.can_fight and kb.can_fight:
            return kb, ka, "withdrawal"
        if not kb.can_fight and ka.can_fight:
            return ka, kb, "withdrawal"

        # Check for unhorsing — handled by score already, but note the reason
        # Compare scores
        if ka.score > kb.score:
            return ka, kb, "points"
        elif kb.score > ka.score:
            return kb, ka, "points"

        # Tiebreak: fewer injuries, then random
        if len(ka.injuries) < len(kb.injuries):
            return ka, kb, "points"
        elif len(kb.injuries) < len(ka.injuries):
            return kb, ka, "points"

        return (ka, kb, "points") if random.random() < 0.5 else (kb, ka, "points")

    def _build_context(self, knight: Knight, opponent: Knight, pass_number: int) -> PassContext:
        moderate_plus = sum(
            1 for inj in knight.injuries if inj.severity.value >= Severity.MODERATE.value
        )
        opp_moderate_plus = sum(
            1 for inj in opponent.injuries if inj.severity.value >= Severity.MODERATE.value
        )
        return PassContext(
            pass_number=pass_number,
            total_passes=self.rules.num_passes,
            own_score=knight.score,
            opponent_score=opponent.score,
            own_injuries=moderate_plus,
            opponent_injuries=opp_moderate_plus,
            own_horse_fatigue=1.0 - knight.horse.fatigue_factor,
            opponent_horse_fatigue=1.0 - opponent.horse.fatigue_factor,
            own_lance_broken=knight.lance.broken,
            rules=self.rules,
        )
