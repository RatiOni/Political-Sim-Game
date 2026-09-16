# Godot migration toolchain baseline

## Verified toolchain

- **Godot executable:** `D:\Godot\Godot_v4.7.2-stable_win64_console.exe`
- **Godot version:** `4.7.2.stable.official.ed1daf0bf`
- **Renderer:** `gl_compatibility`, selected for the broadest Windows playtest
  compatibility.
- **Simulation runtime:** `D:\Political Sim Game\.venv\Scripts\python.exe`
- **Language boundary:** GDScript presents the game; the existing Python engine
  remains authoritative behind a local bridge. G1 uses the standard Godot editor
  and has no .NET SDK dependency.

## Reference baseline

The isolated Godot worktree began at `4d792df26972d292f4951d5f93724d4c43dea215`.
The original checkout was known to contain protected user work; it was not
staged or modified here.

All checks below exited `0` before migration code was added:

| Command | Result |
| --- | --- |
| `smoke_test.py` | 259 emitted `PASS:` lines |
| `distribution_test.py` | 15 checks passed |
| `scripts/run_ui_smoke_offscreen.py` | 21 passed, 0 failed, 0 skipped |
| `godot_bridge_test.py` | 1 Godot bridge check passed |

The bridge fixture is generated from `generate_campaign(default_config())`,
`serialize_state()`, and `digest.snapshot()` in `godot_bridge_test.py`. It is
not copied from a save file, so it remains tied to the public simulation API.
