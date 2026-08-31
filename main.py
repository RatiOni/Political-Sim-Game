"""
Terminal entry point: builds the plain Ardenia scenario and runs the text
menu loop. The full game (menu, campaign wizard, map) lives in gui.py; this
front-end shares the same engine and is what smoke_test.py drives.
"""

import sys
import os
import textwrap

# Allow running from the game/ directory directly
sys.path.insert(0, os.path.dirname(__file__))

# The dispatch feed and menus use box-drawing/arrow characters (—, ↳, ⚠, …).
# Windows' legacy console codepage (cp1252/cp437) can't encode them, and
# that's the DEFAULT whenever stdout isn't a UTF-8-capable terminal — e.g.
# piped/redirected output, which is exactly how smoke_test.py and CI run
# this front-end. Force UTF-8 so a random dispatch doesn't crash the game.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

from content.loader     import build_state_for
from game_state         import GameState
from engine.turn        import TurnEngine
from engine.actions     import run_action_menu
from display.terminal   import print_dashboard, print_digest, print_guidance, print_briefing


def build_sample_game() -> GameState:
    """The default Ardenia start, loaded from content/countries/ardenia.json —
    the same single source of truth the real game uses."""
    return build_state_for("ardenia")


def print_history(state: GameState):
    """Terminal rendering of the same pure lore data as the GUI Codex."""
    if state.country.id != "ardenia":
        print(f"\n  No history has been written for {state.country.name} yet.\n")
        return

    from content import lore

    width = 74

    def heading(text):
        print(f"\n  {text}")
        print("  " + "─" * min(len(text), width))

    def entry(name, body):
        print(f"\n  {name}")
        print(textwrap.fill(body, width=width, initial_indent="    ",
                            subsequent_indent="    "))

    print("\n" + "═" * width)
    print(f"  {state.country.name.upper()} CODEX  ·  Capital: {lore.CAPITAL}")
    print("═" * width)
    print(textwrap.fill(lore.OVERVIEW, width=width, initial_indent="  ",
                        subsequent_indent="  "))

    heading("HOW WE GOT HERE")
    for period, title, body in lore.TIMELINE:
        entry(f"{title}  ·  {period}", body)

    heading("WHERE THE PARTIES CAME FROM")
    for party in sorted(state.country.factions, key=lambda f: -f.seats):
        origin = lore.PARTY_ORIGINS.get(party.id)
        if origin:
            entry(party.name, origin)

    heading("NAMES THAT STILL MATTER")
    for blurb in lore.FIGURES.values():
        print(textwrap.fill(f"• {blurb}", width=width, initial_indent="  ",
                            subsequent_indent="    "))

    heading("THE COUNTRY")
    for item in [lore.COUNTRY_PROFILE, lore.KESLA, lore.CEASEFIRE_LINE,
                 *lore.REGIONS, *lore.CITIES]:
        entry(item["name"], item["body"])

    heading("THE PEOPLE")
    people_entries = [lore.DEMOGRAPHY, *lore.PEOPLES, *lore.SOCIAL_ORDER,
                      lore.LANGUAGE_AND_SCRIPT, *lore.RELIGION]
    for item in people_entries:
        entry(item["name"], item["body"])

    heading("HOW ARDENIA IS GOVERNED")
    government_entries = [lore.CONSTITUTIONAL_ORDER, *lore.OFFICEHOLDERS,
                          *lore.INSTITUTIONS, *lore.LAW_AND_POWER,
                          *lore.MEDIA_AND_CIVIL_SOCIETY]
    for item in government_entries:
        entry(item["name"], item["body"])

    heading("THE ECONOMY")
    economy_entries = [lore.ECONOMIC_PICTURE, *lore.SECTORS, lore.KRON,
                       lore.ENERGY, *lore.FOREIGN_OBLIGATIONS, lore.PRESENT_DAY]
    for item in economy_entries:
        entry(item["name"], item["body"])

    heading("INSIDE THE PARTIES")
    for party in sorted(state.country.factions, key=lambda f: -f.seats):
        blocs = [item for item in lore.BLOCS if item["parent_id"] == party.id]
        if not blocs:
            continue
        print(f"\n  {party.name.upper()}")
        for bloc in blocs:
            entry(bloc["name"], bloc["body"])
    print()


if __name__ == "__main__":
    state  = build_sample_game()
    engine = TurnEngine()

    print_dashboard(state)
    print_guidance(state)

    while True:
        try:
            print("  [1] Take action   [2] Advance one month   [3] View dashboard")
            print("  [4] History       [5] Briefing & calendar   [6] Quit")
            choice = input("  > ").strip()

            if choice == "1":
                run_action_menu(state)
            elif choice == "2":
                state = engine.advance(state)
                print_digest(state)
                print_dashboard(state)
                print_guidance(state)
            elif choice == "3":
                print_dashboard(state)
            elif choice in ("4", "h", "history"):
                print_history(state)
            elif choice in ("5", "b", "briefing", "calendar"):
                print_briefing(state)
            elif choice in ("6", "q", "quit"):
                print("\n  Session ended.\n")
                break
            else:
                print("  Invalid choice.")
        except KeyboardInterrupt:
            print("\n  Session ended.\n")
            break
