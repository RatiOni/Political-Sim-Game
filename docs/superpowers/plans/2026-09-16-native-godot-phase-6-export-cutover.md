# Native Godot Phase 6 — Export and Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce and independently verify a downloadable native Windows Ardenia build with no Python runtime.

**Architecture:** Add native save import and versioning, reproducible Godot export presets, a PowerShell build/verifier, and a tag-gated GitHub release workflow. Inspect both archive contents and runtime process tree to prove the final game is native.

**Tech Stack:** Godot 4.7.2 export templates, PowerShell, GitHub Actions, SHA-256.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- N5 must be PASS.
- The public archive must run without Python, Godot editor, repository checkout, or network access.
- Saves/logs use `%LOCALAPPDATA%\Ardenia`; program files remain read-only.
- Existing tags and public assets are immutable; every replacement uses a new version/tag.

---

### Task 1: Native save versioning and Python-save import

**Files:**
- Create: `godot/scripts/native/state/legacy_save_importer.gd`
- Create: `godot/tests/native/test_legacy_import.gd`
- Create: `godot/data/native/fixtures/legacy_save_v1.json`
- Modify: `godot/scripts/native/state/state_codec.gd`

**Interfaces:**
- Produces: `LegacySaveImporter.import_v1(data: Dictionary) -> Dictionary` returning `{ok, state|error, warnings}`.

- [ ] Export a full Python save fixture containing government/opposition history, budgets, ministries, households, regions, modifiers, events, world plans, treaties, and calendar.
- [ ] Write failing import assertions for every persisted field plus deterministic native RNG derivation metadata.
- [ ] Implement one-way import; never overwrite source file, and save converted state under a new native slot only after validation.
- [ ] Test corrupt, partial, newer-version, and already-native files.
- [ ] Commit `feat(godot): import legacy Ardenia saves`.

### Task 2: Windows export preset and local build

**Files:**
- Create: `godot/export_presets.cfg`
- Create: `scripts/build_godot_windows.ps1`
- Create: `scripts/verify_godot_build.ps1`
- Create: `distribution/GODOT_PLAYTEST_README.txt`
- Modify: `distribution_test.py`

**Interfaces:**
- Produces: `dist/Ardenia-<version>-win64/Ardenia.exe`, data payload, ZIP, and `.sha256`.
- Verifier accepts `-Executable`, `-UserDataDir`, and `-ReportPath`.

- [ ] Write failing distribution checks for export preset, version alignment, archive allow-list, absence of `.py/.pyc/python*.dll/PySide/godot_bridge`, and verifier commands.
- [ ] Run distribution tests; expect the new checks to fail.
- [ ] Configure Windows Desktop export with console disabled, icon/version metadata, GL compatibility renderer, and only runtime Godot/data assets.
- [ ] Build into a clean staging directory, ZIP it, compute SHA-256, and fail if staging includes banned runtime files.
- [ ] Implement verifier to launch packaged game with isolated user data, execute a scripted native journey, close, restart, Continue, and write JSON evidence.
- [ ] Run local build and verify report exit `0`; commit `build(godot): add native Windows export`.

### Task 3: Process and clean-machine proof

**Files:**
- Create: `docs/playtests/GODOT_WINDOWS_RELEASE_CHECKLIST.md`
- Create: `scripts/audit_godot_process.ps1`
- Modify: `distribution_test.py`

**Interfaces:**
- Produces process audit proving Ardenia and OS children contain no Python executable.
- Produces checklist evidence for Windows 10/11 extraction, SmartScreen, scaling, save continuity, replacement, and uninstall.

- [ ] Write a failing test requiring every checklist gate to carry non-placeholder evidence or an explicit BLOCKED reason.
- [ ] Implement process audit: launch packaged build, capture descendant process names/paths, reject `python`, `py`, repository `.venv`, or external worker, then close cleanly.
- [ ] Run packaged journey at 100%, 125%, and 150% scaling on the development machine and record evidence.
- [ ] Test on a clean Windows machine with neither Python nor Godot installed; extract, launch, play one month, save, restart, Continue, and replace program folder while preserving save.
- [ ] Record exact build hash and clean-machine environment; commit `test(godot): verify native Windows package`.

### Task 4: Tag-gated release workflow

**Files:**
- Create: `.github/workflows/godot-playtest-release.yml`
- Modify: `distribution_test.py`
- Create: `docs/godot/native_port/RELEASE_REPORT.md`

**Interfaces:**
- Workflow builds only on manual dispatch and matching `v*-godot-playtest.*` tags; uploads ZIP and checksum from the same commit.

- [ ] Write failing workflow tests for immutable tag identity, pinned Godot version, artifact provenance, checksum publication, and no Python setup step in packaged runtime.
- [ ] Implement workflow using a pinned Godot/export-template setup and PowerShell build scripts.
- [ ] Run workflow syntax checks and local distribution suite.
- [ ] Push only after explicit authorization; download the public asset on an independent machine and recompute its hash.
- [ ] Write RELEASE_REPORT with workflow run, commit, tag, asset URL, hashes, clean-machine result, and rollback version.
- [ ] Commit `ci(godot): publish native playtest builds`.

### Task 5: Remove bridge from production and close N6

**Files:**
- Modify: `godot/project.godot`
- Delete from production export: `godot/scripts/bridge/simulation_bridge.gd`
- Exclude from production export: `godot_bridge/`, `scripts/run_godot_slice.ps1`
- Modify: `docs/godot/native_port/PARITY_MATRIX.md`
- Modify: `docs/godot/native_port/STATUS.md`

**Interfaces:** Final production autoload set contains `NativeGame` and presentation-only globals, never `SimulationBridge`.

- [ ] Write a failing exported-PCK audit rejecting bridge paths, Python strings, worker commands, and external-process launch calls.
- [ ] Remove SimulationBridge autoload and all production dependencies; keep oracle source outside export filters until archival decision.
- [ ] Run all native tests, Python oracle tests, distribution tests, build verification, process audit, archive audit, and clean-machine checklist.
- [ ] Obtain independent code, security, accessibility, and release reviews; fix every Critical/Important finding.
- [ ] Mark all parity rows PASS or attach an explicitly approved product-change record, record N6 PASS, and commit `build(godot): complete native runtime cutover`.
