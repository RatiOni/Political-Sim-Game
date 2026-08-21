# ui package — the PySide6 (Qt) desktop interface.
#
# This layer sits entirely on top of the simulation: it imports GameState,
# TurnEngine, and the engine helpers, reads their public fields, and calls
# advance() — but never modifies simulation logic. The whole terminal
# interface (main.py's loop, display/terminal.py) still works untouched;
# this is an alternative front-end, not a replacement.
