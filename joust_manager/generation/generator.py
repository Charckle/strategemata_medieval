"""Procedural generation for knights, horses, armor, and lances."""
from __future__ import annotations

import random
from typing import Optional

from ..data.names import (
    ARMOR_STYLES,
    HORSE_COLORS,
    HORSE_NAMES,
    KNIGHT_EPITHETS,
    KNIGHT_FIRST_NAMES,
    KNIGHT_ORIGINS,
    LANCE_MATERIALS,
    SHIELD_DEVICES,
)
from ..models.knight import (
    Armor,
    ArmorPiece,
    Horse,
    Knight,
    Lance,
    LanceType,
    Personality,
    Shield,
    Temperament,
)


def _stat(low: int = 3, high: int = 9) -> int:
    """Bell-curve-ish stat generation: roll 2d5 mapped to range."""
    roll = random.randint(1, 5) + random.randint(1, 5)  # 2-10
    return max(low, min(high, roll))


def _used_names() -> set[str]:
    """Track used names to avoid duplicates within a generation batch."""
    if not hasattr(_used_names, "_names"):
        _used_names._names: set[str] = set()
    return _used_names._names


def reset_name_pool() -> None:
    _used_names._names = set()


def generate_horse() -> Horse:
    name = random.choice(HORSE_NAMES)
    color = random.choice(HORSE_COLORS)
    return Horse(
        name=f"{name} the {color} {'stallion' if random.random() > 0.3 else 'mare'}",
        speed=_stat(3, 9),
        steadiness=_stat(3, 9),
        stamina=_stat(3, 9),
        temperament=random.choice(list(Temperament)),
    )


def generate_armor_piece(base_protection: int = 5, weight_range: tuple[float, float] = (2.0, 6.0)) -> ArmorPiece:
    protection = max(1, min(10, base_protection + random.randint(-2, 2)))
    quality = _stat(3, 9)
    weight = round(random.uniform(*weight_range), 1)
    return ArmorPiece(protection=protection, quality=quality, weight=weight)


def generate_shield() -> Shield:
    return Shield(
        protection=_stat(4, 9),
        quality=_stat(3, 9),
        weight=round(random.uniform(3.0, 7.0), 1),
    )


def generate_armor() -> Armor:
    return Armor(
        helm=generate_armor_piece(base_protection=6, weight_range=(3.0, 6.0)),
        pauldrons=generate_armor_piece(base_protection=5, weight_range=(2.0, 5.0)),
        breastplate=generate_armor_piece(base_protection=7, weight_range=(5.0, 10.0)),
        shield=generate_shield(),
    )


def generate_lance(lance_type: LanceType) -> Lance:
    return Lance(
        lance_type=lance_type,
        quality=_stat(3, 8),
        material=random.choice(LANCE_MATERIALS),
    )


def generate_knight_name() -> str:
    used = _used_names()
    for _ in range(100):
        first = random.choice(KNIGHT_FIRST_NAMES)
        origin = random.choice(KNIGHT_ORIGINS)
        name = f"Sir {first} of {origin}"
        if random.random() < 0.3:
            name = f"Sir {first} {random.choice(KNIGHT_EPITHETS)}"
        if name not in used:
            used.add(name)
            return name
    return f"Sir {random.choice(KNIGHT_FIRST_NAMES)} of {random.choice(KNIGHT_ORIGINS)}"


def generate_knight(lance_type: LanceType, name: Optional[str] = None) -> Knight:
    if name is None:
        name = generate_knight_name()
    return Knight(
        name=name,
        strength=_stat(3, 9),
        skill=_stat(3, 9),
        endurance=_stat(3, 9),
        courage=_stat(3, 9),
        personality=random.choice(list(Personality)),
        horse=generate_horse(),
        armor=generate_armor(),
        lance=generate_lance(lance_type),
    )


def generate_field(n: int, lance_type: LanceType) -> list[Knight]:
    reset_name_pool()
    return [generate_knight(lance_type) for _ in range(n)]


def format_knight_card(knight: Knight) -> str:
    """Return a text summary card for display."""
    W = 44
    horse = knight.horse
    armor = knight.armor

    def row(text: str) -> str:
        inner = f"  {text}"
        return f"║{inner:<{W}}║"

    bar = f"╠{'═' * W}╣"
    lines = [
        f"╔{'═' * W}╗",
        f"║{knight.name:^{W}}║",
        bar,
        row(f"Personality: {knight.personality.value}"),
        row(f"STR: {knight.strength}  SKL: {knight.skill}  END: {knight.endurance}  CRG: {knight.courage}"),
        bar,
        row(f"Horse: {horse.name}"),
        row(f"SPD: {horse.speed}  STD: {horse.steadiness}  STA: {horse.stamina}  [{horse.temperament.value}]"),
        bar,
        row(f"Armor weight: {armor.total_weight:.1f}"),
        row(f"Helm: {armor.helm.protection}p/{armor.helm.quality}q  Pauldrons: {armor.pauldrons.protection}p/{armor.pauldrons.quality}q"),
        row(f"Breast: {armor.breastplate.protection}p/{armor.breastplate.quality}q  Shield: {armor.shield.protection}p/{armor.shield.quality}q"),
        bar,
        row(f"Lance: {knight.lance.material} ({knight.lance.lance_type.value}) quality {knight.lance.quality}"),
        f"╚{'═' * W}╝",
    ]
    return "\n".join(lines)
