# Plan Review Log: Rebuild Ardenia as a native Godot game

Phases 0-1 (recon + interrogation) complete — plan locked with the user in
`PLAN.md`. MAX_ROUNDS=3.

## Phase 0 — Recon (Claude)

Terrain: brownfield. No `CONTEXT.md` or `docs/adr/`, so docs-aware mode off;
`CLAUDE.md`, `AGENTS.md`, and `docs/EARLY_ACCESS_MISSION.md` carry the project
vocabulary. Research tier chosen by the user: `web`.

Measured: ~16,090 lines of Python to serve as reference (engine 9,693;
content+lore 6,297; models and `game_state.py`), 9 country JSONs, a 5,982-line
`smoke_test.py` defining current behaviour. Native code at the time: 8 files,
all infrastructure, zero simulation ported.

Skill inventory scanned on both benches (`~/.claude/skills`, `~/.agents/skills`):
near-identical packs; **no Godot, GDScript, or game-engine skill on either**.

Web research findings (4):

1. Godot documents that float math "is not guaranteed to be exact or
   deterministic" and varies across CPUs, operating systems, and versions.
   Teams needing determinism use fixed-point or soft floats. — directly
   undermined the superseded spec's `1e-9` cross-language parity target.
2. GDScript `int` is signed 64-bit with silent wraparound and no unsigned
   64-bit type — a sharp edge for any PCG/xorshift RNG, which assume uint64.
3. Untyped code is GDScript's single largest performance cost, and Dictionary
   operations are reported slower than Python's — while the superseded spec
   mandated nested untyped `Dictionary` state specifically to serve the
   comparator.
4. `JSON.stringify()` defaults `sort_keys` to `true`, so Godot JSON output is
   deterministic by default. Python's `json.dumps` needs explicit
   `sort_keys=True` to match.

Ledger presented as one batch; user confirmed.

## Phase 1 — Interrogation (user ↔ Claude)

Decision map resolved:

- **D1 — Does the native rewrite proceed, or does the bridge ship first?**
  Claude recommended shipping the bridge with a PyInstaller-packaged worker,
  on the grounds that `dist\Ardenia\Ardenia.exe` already proves players never
  install Python. **User rejected the recommendation:** the goal is a Godot
  game, not a packaging workaround. Native rebuild proceeds. Recorded and not
  re-asked.
- **D2 — Bit-parity with Python, or the same game?** Design-port. Python is a
  design reference to read; Godot decides how it computes. The `1e-9` contract,
  `PARITY_MATRIX.md` as a gate, the oracle fixtures, the comparator, and the
  dual-maintenance rule are all cancelled. User: *"with what we build in python
  we already have a reference of what we should be aiming at creating in godot
  engine. not copy paste the code… we are remaking the game but instead of it
  being in python, its now in godot engine as a legitimate game with assets,
  mechanics, ui, and whatever else the video game consists of."*
- **D3 — Float-parity strategy.** Dissolved by D2. Cross-language float
  equality stops mattering once it is not asserted. RNG determinism still
  required *within* the Godot build so saves reload coherently.
- **D4 — State representation.** Decided, not asked: typed GDScript classes and
  `Resource`s, not nested untyped dictionaries. The dictionary mandate existed
  only to serve the cancelled comparator, and finding 3 makes it the slow path.
- **D5 — Worktree ownership.** No contention. Codex is out of credits;
  OpenCode is a third reserve used only when Claude and Codex hourly limits are
  exhausted. The five files modified at 22:18 were Codex's last act before
  running dry, preserved verbatim in `63eebea`.

Cosmetic batch accepted without veto: preserve Codex's work before branching;
branch `godot-native/rebuild`; retire rather than delete; rewrite master plan
and spec around the game build; Ministry Wire art direction settled, not
re-explored; Python freezes as reference; skip `CONTEXT.md`; one independent
review per phase.

## Phase 2 — Adversarial review (Codex) — PARKED, not skipped

Cross-model review could not run: Codex has no credits. Substituting a Claude
subagent was considered and **rejected** — same model family grading its own
reasoning is the echo chamber this phase exists to prevent, and logging it as a
cross-model review would be false.

Agreed disposition: the user will point Codex at `PLAN.md` once its credits
reset, so it can course-correct from the cancelled parity programme and attack
the new plan in the same pass. To make that redirect reliable regardless of
what a cold session reads first, superseded banners were added to every
document in the old required-reading order:

- `docs/godot/NATIVE_REWRITE_AGENT_GUIDE.md` (reading order rewritten)
- `docs/godot/native_port/STATUS.md` (banner + dated handoff entry)
- `docs/godot/native_port/PARITY_MATRIX.md`
- `docs/superpowers/plans/2026-09-16-native-godot-rewrite-master.md`
- `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`
- all six `2026-09-16-native-godot-phase-*.md` plans

**Round 1 awaiting Codex.** Append its critique below when it runs.
