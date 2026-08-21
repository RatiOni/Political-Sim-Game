"""
Ardenia's history — the backstory the existing data has always implied.

The faction ideologies, the seeded grievances, the authored relations and
the March 1993 start date already encode a specific past; this package says
it out loud, in one place, so events, dispatches and both front-ends can cite
the same canon instead of inventing their own.

Written in the game's register (see content/dispatches.py and
content/press.py): dry, literate, close to the political present. Not an
encyclopedia entry — a briefing you could plausibly hand a new minister.

Structure is deliberately plain data so the UI can render it without knowing
anything about history. Nothing here imports from engine/ or models/; it is
pure content.
"""

from .economy import (ECONOMIC_PICTURE, ENERGY, FOREIGN_OBLIGATIONS, KRON,
                      PRESENT_DAY, SECTORS)
from .figures import FIGURES
from .geography import CEASEFIRE_LINE, CITIES, COUNTRY_PROFILE, KESLA, REGIONS
from .institutions import (CONSTITUTIONAL_ORDER, INSTITUTIONS, LAW_AND_POWER,
                           MEDIA_AND_CIVIL_SOCIETY, OFFICEHOLDERS)
from .parties import BLOCS, BLOC_PROFILES, PARTY_ORIGINS
from .society import (DEMOGRAPHY, LANGUAGE_AND_SCRIPT, PEOPLES, RELIGION,
                      SOCIAL_ORDER)
from .timeline import TIMELINE


CAPITAL = "Vashtera"
UNION_NAME = "the Kolvenian Union"
UNION_DOCTRINE = "Dravism"
SEPARATIST_REGION = "Vetrenka"
CORE_SUCCESSOR_STATE = "krasova"      # country id — the Union's heir


OVERVIEW = (
    "Ardenia has been independent for eighteen months and at war with itself "
    "for most of them. The state that took office in March 1993 is the fourth "
    "government in three years, the first anyone voted for since the shooting "
    "stopped, and — on the evidence of the last three — not obviously the one "
    "that will still be there next spring."
)


def opening_briefing(player_name: str, title: str, *, party_id="liberal_democrats",
                     party_name="Liberal Democrats", in_government=True,
                     ruling_party="Liberal Democrats", coalition_names=None) -> list:
    """A contextual campaign opening for any party and either side of power."""
    coalition_names = coalition_names or []
    if in_government:
        partners = [name for name in coalition_names if name != party_name]
        arrangement = (f" with {' and '.join(partners)}" if partners else
                       " as a minority administration")
        first = (f"{title} {player_name} takes office this month leading the "
                 f"{party_name}{arrangement}, after the Reckoning — the first "
                 f"government since the Turn of the Year that anyone actually voted for.")
    else:
        first = (f"{title} {player_name} begins the new parliament at the head of the "
                 f"{party_name}. The Reckoning left {ruling_party} in power; your party "
                 f"must decide when to cooperate, when to obstruct, and how to replace it.")

    origin = PARTY_ORIGINS.get(
        party_id,
        "A party shaped by the same independence struggle, economic collapse and unfinished transition as its rivals.")
    return [
        first,
        f"{player_name}'s political inheritance: {origin}",
        f"The national inheritance is shared by government and opposition alike: an economy "
        f"still bleeding from the Union's collapse and a ceasefire line through "
        f"{SEPARATIST_REGION} that nobody in the chamber recognises.",
    ]


__all__ = [
    "CAPITAL", "UNION_NAME", "UNION_DOCTRINE", "SEPARATIST_REGION",
    "CORE_SUCCESSOR_STATE", "OVERVIEW", "TIMELINE", "PARTY_ORIGINS",
    "FIGURES", "opening_briefing", "COUNTRY_PROFILE", "REGIONS", "CITIES", "KESLA",
    "CEASEFIRE_LINE", "PEOPLES", "DEMOGRAPHY", "SOCIAL_ORDER",
    "LANGUAGE_AND_SCRIPT", "RELIGION", "CONSTITUTIONAL_ORDER",
    "INSTITUTIONS", "OFFICEHOLDERS", "LAW_AND_POWER",
    "MEDIA_AND_CIVIL_SOCIETY", "ECONOMIC_PICTURE", "SECTORS", "KRON",
    "ENERGY", "FOREIGN_OBLIGATIONS", "PRESENT_DAY", "BLOCS", "BLOC_PROFILES",
]
