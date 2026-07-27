"""CLI interface for the Joust Manager."""
from __future__ import annotations

import sys
import time
from typing import Optional

from ..engine.joust import JoustEngine, MatchResult
from ..engine.strategy import AIStrategy
from ..generation.generator import format_knight_card, generate_field, generate_knight
from ..models.knight import Knight
from ..models.tournament import (
    TOURNAMENT_PRESETS,
    TournamentBracket,
    TournamentRules,
    TournamentType,
)
from ..narration.narrator import Narrator

BANNER = r"""
    ╔═══════════════════════════════════════════════╗
    ║        ⚔  JOUST MANAGER SIMULATOR  ⚔         ║
    ║     "For honour, glory, and a steady lance"   ║
    ╚═══════════════════════════════════════════════╝
"""


def clear_line() -> None:
    print()


def prompt(message: str, valid: Optional[list[str]] = None) -> str:
    while True:
        raw = input(f"  {message} > ").strip()
        if valid is None or raw.lower() in [v.lower() for v in valid]:
            return raw.lower()
        print(f"  Please enter one of: {', '.join(valid)}")


def pause(message: str = "Press Enter to continue...") -> None:
    input(f"\n  {message}")


class App:
    def __init__(self) -> None:
        self.narrator = Narrator()
        self.verbose_offscreen = False  # toggleable

    def _select_tournament(self) -> TournamentRules:
        print("  ╔═══ SELECT TOURNAMENT ═══╗")
        types = list(TournamentType)
        for i, t in enumerate(types, 1):
            preset = TOURNAMENT_PRESETS[t]
            print(f"  ║ [{i}] {t.value}")
            print(f"  ║     {preset['description']}")
            print(f"  ║     Passes: {preset['num_passes']}  |  "
                  f"Knights: {preset['num_knights']}  |  "
                  f"Lance: {preset['lance_type'].value}")
            print(f"  ║")
        print(f"  ╚{'═' * 27}╝")

        choice = prompt("Choose tournament", [str(i) for i in range(1, len(types) + 1)])
        selected = types[int(choice) - 1]
        rules = TournamentRules.from_preset(selected)

        print(f"\n  Selected: {rules.name}")
        self._print_rules_summary(rules)
        pause()
        return rules

    def _print_rules_summary(self, rules: TournamentRules) -> None:
        print(f"  ┌─ Rules ─────────────────────────────────┐")
        print(f"  │ Passes per match: {rules.num_passes:<22}│")
        print(f"  │ Armor contact: {'YES' if rules.armor_contact_allowed else 'NO':<24}│")
        print(f"  │ Min speed threshold: {rules.min_speed_threshold:<19}│")
        print(f"  │ Lance type: {rules.lance_type.value:<27}│")
        print(f"  │ Unhorse points: {rules.unhorse_points:<23}│")
        print(f"  │ Unhorse wins match: {'YES' if rules.unhorse_wins_match else 'NO':<19}│")
        print(f"  │ Head hit penalty: {rules.head_hit_penalty:<21}│")
        print(f"  │ Horse hit = DQ: {'YES' if rules.horse_hit_disqualify else 'NO':<22}│")
        print(f"  │ Tip clash voids pass: {'YES' if rules.lance_tip_clash_voids_round else 'NO':<17}│")
        print(f"  └─────────────────────────────────────────┘")

    def _generate_player_knight(self, rules: TournamentRules) -> Knight:
        print("\n  ╔═══ YOUR KNIGHT ═══╗")
        while True:
            knight = generate_knight(rules.lance_type)
            print()
            print(format_knight_card(knight))
            print()
            choice = prompt("[A]ccept, [R]egenerate, or [N]ame this knight", ["a", "r", "n"])
            if choice == "a":
                return knight
            elif choice == "n":
                name = input("  Enter name (e.g. 'Sir Aldric the Bold'): ").strip()
                if name:
                    knight.name = name
                return knight

    def _select_control_mode(self) -> str:
        print("\n  ╔═══ CONTROL MODE ═══╗")
        print("  ║ [W] Watch   — Full auto. Sit back and read the story.")
        print("  ║ [M] Manage  — Set strategy before each of YOUR passes.")
        print("  ╚═════════════════════╝")
        return prompt("Choose mode", ["w", "m"])

    def _run_tournament(self, bracket: TournamentBracket, player: Knight, mode: str) -> None:
        round_idx = 0
        while True:
            current_round = bracket.rounds[round_idx]
            round_name = bracket.round_name(round_idx)
            print(f"\n{'=' * 55}")
            print(f"  {round_name}")
            print(f"{'=' * 55}")

            self._print_bracket_round(current_round)
            pause(f"Press Enter to begin the {round_name}...")

            for match in current_round:
                is_player_match = (match.knight_a is player or match.knight_b is player)

                print(f"\n{'─' * 55}")
                print(f"  {match.knight_a.name}  vs  {match.knight_b.name}")
                if is_player_match:
                    print("  *** YOUR MATCH ***")
                print(f"{'─' * 55}")

                if is_player_match:
                    result = self._run_player_match(match, player, mode)
                else:
                    result = self._run_ai_match(match)

                match.winner = result.winner
                match.loser = result.loser
                match.finished = True

                if is_player_match and not player.can_fight:
                    print("\n  Your knight can no longer continue.")
                    print("  The tournament goes on without you...\n")

                pause()

            # Heal between rounds
            if player.can_fight:
                self._between_rounds(player)

            # Advance bracket
            next_round = bracket.advance_round()
            if next_round is None:
                break
            round_idx += 1

            # Toggle verbosity prompt
            self._offer_verbosity_toggle()

        self._tournament_conclusion(bracket, player)

    def _run_player_match(self, match, player: Knight, mode: str) -> MatchResult:
        engine = JoustEngine(rules=self._current_rules)
        if mode == "m":
            return self._run_managed_match(engine, match, player)
        else:
            result = engine.run_match(match.knight_a, match.knight_b)
            for pass_events in result.events_per_pass:
                lines = self.narrator.narrate_pass(pass_events, verbose=True)
                for line in lines:
                    print(f"  {line}")
                    time.sleep(0.05)
            return result

    def _run_managed_match(self, engine: JoustEngine, match, player: Knight) -> MatchResult:
        from ..engine.strategy import Aggression, AimTarget, PassDecision, ShieldGuard

        class PlayerManagedStrategy:
            def __init__(self, player_knight: Knight):
                self.player_knight = player_knight
                self.next_decision: Optional[PassDecision] = None

            def decide(self, knight, context):
                if knight is self.player_knight and self.next_decision:
                    dec = self.next_decision
                    self.next_decision = None
                    return dec
                return AIStrategy().decide(knight, context)

        managed = PlayerManagedStrategy(player)

        if match.knight_a is player:
            engine.strategy_a = managed
        else:
            engine.strategy_b = managed

        opponent = match.knight_b if match.knight_a is player else match.knight_a

        player.reset_for_match()
        opponent.reset_for_match()
        player.horse.current_stamina = float(player.horse.stamina)
        opponent.horse.current_stamina = float(opponent.horse.stamina)

        all_events: list[list] = []
        pass_num = 0

        while pass_num < engine.rules.num_passes:
            pass_num += 1

            print(f"\n  ┌─ Pass {pass_num} — Set Your Strategy ─────────┐")
            print(f"  │ Your score: {player.score}  |  Opponent score: {opponent.score}")
            print(f"  │ Horse fatigue: {1.0 - player.horse.fatigue_factor:.0%}")
            if player.injuries:
                for inj in player.injuries:
                    print(f"  │ Injury: {inj.description} [{inj.severity.name}]")
            print(f"  │")
            print(f"  │ AIM:  [1] Shield center  [2] Shield edge")
            print(f"  │       [3] Armor          [4] High (risky)")
            aim_choice = prompt("  │ Aim", ["1", "2", "3", "4"])
            aim_map = {"1": AimTarget.SHIELD_CENTER, "2": AimTarget.SHIELD_EDGE,
                       "3": AimTarget.ARMOR, "4": AimTarget.HIGH}

            print(f"  │ SPEED: [1] Conservative  [2] Normal  [3] Aggressive")
            agg_choice = prompt("  │ Speed", ["1", "2", "3"])
            agg_map = {"1": Aggression.CONSERVATIVE, "2": Aggression.NORMAL,
                       "3": Aggression.AGGRESSIVE}

            print(f"  │ GUARD: [1] High (protect head)  [2] Center  [3] Low")
            guard_choice = prompt("  │ Guard", ["1", "2", "3"])
            guard_map = {"1": ShieldGuard.HIGH, "2": ShieldGuard.CENTER,
                         "3": ShieldGuard.LOW}

            managed.next_decision = PassDecision(
                aim=aim_map[aim_choice],
                aggression=agg_map[agg_choice],
                shield_guard=guard_map[guard_choice],
            )
            print(f"  └──────────────────────────────────────┘")

            events = engine._resolve_pass(player if match.knight_a is player else match.knight_a,
                                          opponent if match.knight_a is player else match.knight_b,
                                          pass_num)
            all_events.append(events)

            lines = self.narrator.narrate_pass(events, verbose=True)
            for line in lines:
                print(f"  {line}")
                time.sleep(0.05)

            from ..engine.events import LanceTipClashEvent, FallEvent
            if engine.rules.lance_tip_clash_voids_round and any(
                isinstance(e, LanceTipClashEvent) for e in events
            ):
                pass_num -= 1
                continue

            if player.disqualified or opponent.disqualified:
                break
            if not player.can_fight or not opponent.can_fight:
                break
            for e in events:
                if isinstance(e, FallEvent) and engine.rules.unhorse_wins_match:
                    break
            else:
                continue
            break

        winner, loser, reason = engine._determine_winner(
            match.knight_a, match.knight_b
        )
        from ..engine.events import MatchEndEvent
        final = MatchEndEvent(
            winner=winner.name, loser=loser.name,
            final_score_winner=winner.score, final_score_loser=loser.score,
            reason=reason,
        )
        all_events.append([final])
        lines = self.narrator.narrate_pass([final], verbose=True)
        for line in lines:
            print(f"  {line}")

        return MatchResult(events_per_pass=all_events, winner=winner, loser=loser, final_event=final)

    def _run_ai_match(self, match) -> MatchResult:
        engine = JoustEngine(rules=self._current_rules)
        result = engine.run_match(match.knight_a, match.knight_b)

        if self.verbose_offscreen:
            for pass_events in result.events_per_pass:
                lines = self.narrator.narrate_pass(pass_events, verbose=True)
                for line in lines:
                    print(f"  {line}")
                    time.sleep(0.03)
        else:
            lines = self.narrator.narrate_match_brief(result.events_per_pass)
            for line in lines:
                print(f"  {line}")
        return result

    def _between_rounds(self, player: Knight) -> None:
        print(f"\n  ┌─ Between Rounds ─────────────────────────┐")
        healed = player.heal_between_matches()
        if healed:
            for line in healed:
                print(f"  │{line}")
        if player.injuries:
            print(f"  │ Remaining injuries:")
            for inj in player.injuries:
                print(f"  │   {inj.description} [{inj.severity.name}] "
                      f"({', '.join(f'{k}: {v}' for k, v in inj.stat_penalties.items())})")
        else:
            print(f"  │ No injuries — you are in fighting form!")
        player.horse.rest(2.0)
        print(f"  │ Your horse has rested. "
              f"(Stamina: {player.horse.current_stamina:.1f}/{player.horse.stamina})")
        print(f"  └─────────────────────────────────────────┘")

    def _offer_verbosity_toggle(self) -> None:
        current = "FULL" if self.verbose_offscreen else "BRIEF"
        print(f"\n  Off-screen match display is currently: {current}")
        choice = prompt("Toggle? [Y]es / [N]o", ["y", "n"])
        if choice == "y":
            self.verbose_offscreen = not self.verbose_offscreen
            new = "FULL" if self.verbose_offscreen else "BRIEF"
            print(f"  Off-screen matches will now show: {new}")

    def _print_bracket_round(self, matches: list) -> None:
        for m in matches:
            print(f"    {m.knight_a.name}  vs  {m.knight_b.name}")

    def _tournament_conclusion(self, bracket: TournamentBracket, player: Knight) -> None:
        champion = bracket.champion
        print(f"\n{'═' * 55}")
        print(f"  TOURNAMENT COMPLETE")
        print(f"{'═' * 55}")
        if champion:
            print(f"\n  THE CHAMPION: {champion.name}!")
            if champion is player:
                print("  *** YOU ARE THE CHAMPION! Glory and honour are yours! ***")
            else:
                print(f"  Your knight fell along the way. Better fortune next time.")
        print()

    # Store rules reference for engine creation
    _current_rules: TournamentRules = None  # type: ignore

    def _get_rules_from_match(self, match) -> TournamentRules:
        return self._current_rules

    def run(self) -> None:
        print(BANNER)
        rules = self._select_tournament()
        self._current_rules = rules
        player_knight = self._generate_player_knight(rules)
        control_mode = self._select_control_mode()

        knights = generate_field(rules.num_knights - 1, rules.lance_type)
        knights.insert(0, player_knight)

        bracket = TournamentBracket(rules=rules, knights=knights)
        bracket.generate_bracket()

        self._run_tournament(bracket, player_knight, control_mode)
