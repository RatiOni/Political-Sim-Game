"""
Campaign generation: CampaignConfig (country, character, difficulty, seed) →
loader.build_state_for(country), then traits → difficulty → character nudges
on the starting position, then campaign metadata. Every step is a one-time
nudge at generation; nothing hooks into the turn loop. Seeded → reproducible.
"""

import random
from dataclasses import dataclass, field
from typing import Optional

from content import loader
from content import traits as traits_content
from content import campaign_content
from game_state import GameState


@dataclass
class CampaignConfig:
    country_id: str
    # Character (Priority 4). If any field is None, the country's default is used.
    leader_name: Optional[str] = None
    title: Optional[str] = None
    party_id: Optional[str] = None
    background_id: str = "career_politician"
    opening_role: str = "contextual"  # contextual | government | opposition
    ideology_economic: Optional[float] = None
    ideology_social: Optional[float] = None
    # Difficulty (Priority 5) and reproducibility.
    difficulty_id: str = "normal"
    seed: Optional[int] = None
    # The guided opening (engine/onboarding.py). Advisory only — it never
    # gates an action — so it defaults on and the wizard offers to skip it.
    guidance_enabled: bool = True

    def resolved_seed(self) -> int:
        if self.seed is not None:
            return self.seed
        # A stable default seed derived from the config, so "no seed given"
        # is still reproducible for the same choices.
        return abs(hash((self.country_id, self.leader_name, self.background_id,
                         self.difficulty_id))) % (2**31)


# ── Application steps ───────────────────────────────────────────────────────

def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def _apply_traits(state: GameState):
    """National traits nudge the starting canvas (Priority 7)."""
    country = state.country
    econ = country.economy
    for tid in country.national_traits:
        t = traits_content.get_trait(tid)
        if t is None:
            continue
        country.bureaucratic_capacity = _clamp(
            country.bureaucratic_capacity + t.bureaucratic_capacity_delta, 0.0, 1.0)
        state.stability.value = _clamp(state.stability.value + t.stability_delta, 0.05, 0.95)
        econ.growth_rate += t.growth_delta
        econ.inflation = max(0.0, econ.inflation + t.inflation_delta)
        econ.public_debt_pct = max(0.0, econ.public_debt_pct + t.debt_delta)
        state.player.approval = _clamp(state.player.approval + t.approval_delta, 0.05, 0.95)


def _apply_difficulty(state: GameState, difficulty_id: str):
    """Difficulty reshapes the opening position, not the rules (Priority 5)."""
    diff = campaign_content.get_difficulty(difficulty_id)
    if diff is None:
        return
    econ = state.country.economy
    state.player.approval = _clamp(state.player.approval + diff.approval_delta, 0.05, 0.95)
    state.player.political_capital = _clamp(
        state.player.political_capital + diff.political_capital_delta, 0.0, 100.0)
    econ.growth_rate += diff.growth_delta
    econ.inflation = max(0.0, econ.inflation + diff.inflation_delta)
    econ.public_debt_pct = max(0.0, econ.public_debt_pct + diff.debt_delta)
    econ.unemployment = _clamp(econ.unemployment + diff.unemployment_delta, 0.01, 0.60)
    state.stability.value = _clamp(state.stability.value + diff.stability_delta, 0.05, 0.95)

    for f in state.country.factions:
        if f.in_coalition:
            f.loyalty = _clamp(f.loyalty + diff.coalition_loyalty_delta, -1.0, 1.0)
        if f.is_hostile():
            f.power = _clamp(f.power + diff.opposition_power_delta, 0.0, 1.0)

    # Keep structural economic baselines consistent with the nudged headline
    # values, so the first turn doesn't immediately snap back toward the old
    # numbers. (The Economy seeds these from headline values on construction;
    # we re-seed after the nudge.)
    econ.structural_growth_rate = econ.growth_rate
    econ.structural_unemployment = econ.unemployment
    econ.structural_inflation = econ.inflation


def _apply_character(state: GameState, config: CampaignConfig):
    """Character identity + background (Priority 4)."""
    player = state.player
    original_party_id = player.faction_id
    if config.party_id:
        player.faction_id = config.party_id

    own_party = next((f for f in state.country.factions if f.id == player.faction_id), None)

    # A blank name means the selected party's existing leader when the player
    # deliberately changes party. The country's authored leader remains the
    # default when the default party is left unchanged.
    if config.leader_name:
        player.name = config.leader_name
    elif config.party_id and config.party_id != original_party_id and own_party and own_party.leader:
        player.name = own_party.leader
    if config.title:
        player.title = config.title

    # Party affiliation supplies the default ideology. The sliders represent
    # a real personal deviation rather than retaining the default party's view.
    if config.party_id and own_party is not None:
        player.ideology_economic = own_party.ideology.economic
        player.ideology_social = own_party.ideology.social
    if config.ideology_economic is not None:
        player.ideology_economic = config.ideology_economic
    if config.ideology_social is not None:
        player.ideology_social = config.ideology_social

    # The player IS their party's leader — keep the narrative layer in sync
    # with whatever identity the wizard chose.
    if own_party is not None:
        own_party.leader = player.name

    bg = campaign_content.get_background(config.background_id)
    if bg is not None:
        econ = state.country.economy
        player.approval = _clamp(player.approval + bg.approval_delta, 0.05, 0.95)
        player.political_capital = _clamp(
            player.political_capital + bg.political_capital_delta, 0.0, 100.0)
        econ.growth_rate += bg.growth_delta
        econ.inflation = max(0.0, econ.inflation + bg.inflation_delta)
        state.country.bureaucratic_capacity = _clamp(
            state.country.bureaucratic_capacity + bg.bureaucratic_capacity_delta, 0.0, 1.0)
        state.stability.value = _clamp(state.stability.value + bg.stability_delta, 0.05, 0.95)
        econ.structural_growth_rate = econ.growth_rate
        econ.structural_inflation = econ.inflation

        # Background loyalty leanings, matched by faction economic archetype.
        for f in state.country.factions:
            if f.ideology.economic < -0.2 and bg.labour_loyalty_delta:
                f.loyalty = _clamp(f.loyalty + bg.labour_loyalty_delta, -1.0, 1.0)
            if f.ideology.economic > 0.2 and bg.business_loyalty_delta:
                f.loyalty = _clamp(f.loyalty + bg.business_loyalty_delta, -1.0, 1.0)


def _apply_opening_position(state: GameState, config: CampaignConfig):
    """Turn party and opening-role choices into a coherent government."""
    from engine import elections

    own = next((f for f in state.country.factions if f.id == state.player.faction_id), None)
    if own is None:
        return
    state.campaign_meta["government_title"] = state.player.title

    role = config.opening_role if config.opening_role in {
        "contextual", "government", "opposition"
    } else "contextual"
    if role == "contextual":
        role = "government" if own.in_coalition else "opposition"

    if role == "government":
        if state.ruling_faction_id != own.id:
            elections.configure_government(state, own.id)
        else:
            state.player.in_government = True
    else:
        # Preserve the authored cabinet when it already excludes this party.
        # Otherwise build an alternative around the strongest rival.
        if own.in_coalition:
            rivals = [f for f in state.country.factions if f.id != own.id and f.seats > 0]
            if rivals:
                lead = max(rivals, key=lambda f: f.seats)
                elections.configure_government(state, lead.id, excluded_ids={own.id})
        state.player.in_government = False

    if config.title is None and not state.player.in_government:
        state.player.title = "Opposition Leader"


def _seed_metadata(state: GameState, config: CampaignConfig):
    """Record campaign metadata and initialise the legacy record."""
    government_title = state.campaign_meta.get("government_title", state.player.title)
    state.campaign_meta = {
        "country_id": config.country_id,
        "difficulty": config.difficulty_id,
        "background": config.background_id,
        "opening_role": ("government" if state.player.in_government else "opposition"),
        "government_title": government_title,
        "seed": config.resolved_seed(),
        "national_traits": list(state.country.national_traits),
        # engine/onboarding.py reads this; nothing new has to be persisted
        # because campaign_meta already round-trips.
        "guidance_enabled": bool(config.guidance_enabled),
    }
    # The legacy record was created in GameState.__post_init__ with the
    # default player; refresh its identity now that the character is applied.
    if state.legacy is not None:
        state.legacy.country_id = state.country.id
        state.legacy.leader_name = state.player.name
        state.legacy.party_id = state.player.faction_id
        state.legacy.start_date = state.date_string()
        opening_deed = ("takes office" if state.player.in_government
                        else "enters parliament in opposition")
        state.legacy.record_milestone(
            state.date_string(),
            f"{state.player.title} {state.player.name} {opening_deed} in "
            f"{state.country.name} ({config.difficulty_id} difficulty).")


# ── Public entry point ──────────────────────────────────────────────────────

def generate_campaign(config: CampaignConfig) -> GameState:
    """Build a complete, ready-to-play GameState from a CampaignConfig."""
    rng = random.Random(config.resolved_seed())  # reserved for future procedural gen

    state = loader.build_state_for(config.country_id)

    # Order matters: traits set the national baseline; identity selects the
    # party; that party determines the opening government; difficulty then
    # adjusts the coalition that actually exists in this campaign.
    _apply_traits(state)
    _apply_character(state, config)
    _apply_opening_position(state, config)
    _apply_difficulty(state, config.difficulty_id)
    _seed_metadata(state, config)
    _opening_briefing(state)

    # Re-activate law modifiers is NOT needed here — build_state_for already
    # did it, and our nudges don't add laws. (Kept as a note so a future
    # trait that seeds a starting law remembers to activate it.)
    return state


def _opening_briefing(state: GameState):
    """Seed the dispatch feed with a short who-is-the-new-prime-minister
    profile, so a campaign opens on its own situation rather than a blank
    log. Country-specific lore only exists for Ardenia (content/lore.py);
    anywhere else this is silently skipped."""
    if state.country.id != "ardenia":
        return
    from content import lore
    own = next((f for f in state.country.factions if f.id == state.player.faction_id), None)
    ruling = next((f for f in state.country.factions if f.id == state.ruling_faction_id), None)
    coalition = [f.name for f in state.country.factions if f.in_coalition]
    for line in lore.opening_briefing(
            state.player.name, state.player.title,
            party_id=own.id if own else state.player.faction_id,
            party_name=own.name if own else state.player.faction_id,
            in_government=state.player.in_government,
            ruling_party=ruling.name if ruling else "the governing coalition",
            coalition_names=coalition):
        state.log(line)


def default_config(country_id: str = "ardenia") -> CampaignConfig:
    """A zero-choices config — no character or difficulty nudge applied.
    NOT identical to loader.build_state_for(country_id): the country's own
    national traits still apply (they're part of how it's authored, not a
    player choice), and campaign_meta/legacy still get seeded."""
    return CampaignConfig(country_id=country_id, background_id="none",
                          difficulty_id="normal")
