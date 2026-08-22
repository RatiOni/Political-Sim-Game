# Windows Playtest Distribution Design

**Status:** Approved design
**Date:** 22 August 2026
**Target:** First publicly downloadable Ardenia playtest build for Windows 10/11

## 1. Purpose

Ardenia currently runs from `gui.py` inside a configured Python environment. That is suitable for development but not for the Early Access mission's external evidence gate: testers should be able to download the game, extract it, and launch it without installing Python, cloning the repository, or understanding the source tree.

The first distribution milestone will publish a self-contained Windows build through GitHub Releases. Its purpose is to support six to eight asynchronous, uncoached baseline sessions. It is not yet a public demo, installer, updater, or commercial release pipeline.

## 2. Success condition

A tester using a clean 64-bit Windows 10 or Windows 11 machine can:

1. download one versioned ZIP from the official GitHub Release;
2. extract the complete archive;
3. launch `Ardenia.exe` without Python or Git;
4. create either a government or opposition campaign;
5. advance the game, save, close, reopen, and load the campaign;
6. find a readable crash log if the game fails; and
7. complete the bundled feedback form after an independently recorded 45-minute session.

Replacing the extracted program folder with a later build must not remove packaged-build saves.

## 3. Deliberate scope

### Included

- A PyInstaller one-folder Windows build packaged as a ZIP.
- A deterministic version and archive naming scheme.
- A local Windows build command and an equivalent clean GitHub Actions workflow.
- Public GitHub Release publication from an immutable version tag.
- A packaged-build verification mode.
- Packaged-build save and log directories under the current user's local application data.
- A local crash log and a clear fatal-error message.
- Neutral tester instructions and a plain-text feedback template.
- A SHA-256 checksum and concise release notes.

### Not included

- macOS or Linux builds.
- A single-file self-extracting executable.
- An installer, Start Menu shortcut, uninstaller, launcher, or automatic updater.
- Code signing for the first baseline build.
- Telemetry, analytics, automatic crash submission, accounts, or network services.
- A public feedback backend or a repository-owned recording upload service.
- Simulation, content, balance, persistence-schema, onboarding, pacing, or dashboard changes.
- Any reform prototype or other work prohibited before the human evidence checkpoint.

## 4. Distribution format

The build will use PyInstaller's one-folder, windowed mode. The release asset will be named from the authoritative version:

```text
Ardenia-0.1.0-playtest.1-win64.zip
└── Ardenia/
    ├── Ardenia.exe
    ├── PLAYTEST_README.txt
    ├── FEEDBACK_TEMPLATE.txt
    └── bundled Python, Qt, content, and runtime files
```

One-folder packaging is preferred over a single executable because it starts faster, avoids unpacking itself on every launch, is easier to inspect when a dependency or data file is missing, and is less prone to antivirus heuristics. A ZIP is sufficient for the baseline sample and does not create installer or update commitments prematurely.

The archive must be extracted before launch. The tester guide will warn against running `Ardenia.exe` from inside the compressed archive or moving the executable away from its bundled runtime files.

## 5. Runtime architecture

### 5.1 Application entry point

`gui.py` remains the real application entry point. PyInstaller targets that file and produces a windowed executable named `Ardenia.exe`; normal packaged launches do not show a console window.

Packaging behavior is confined to small infrastructure modules. The game engine and front ends must not acquire PyInstaller-specific branches or packaging knowledge beyond asking the shared path/version helpers for values.

### 5.2 Authoritative version

A root-level version module will expose:

- the human version string, initially `0.1.0-playtest.1`;
- a Windows-compatible numeric file-version tuple;
- the matching Git tag `v0.1.0-playtest.1`; and
- the display/archive form used by the title bar, crash log, tester files, workflow, and ZIP.

The release workflow must reject publication when the tag and source version disagree. The release name, archive, checksum file, log header, and tester instructions must all identify the same version.

### 5.3 Application paths

A root-level, engine-independent application-path helper will own program-data locations.

In source mode:

- saves continue to use the repository's existing `saves/` directory;
- developer behavior and current test assumptions remain unchanged; and
- fatal crash logs use a repository-local ignored `logs/` directory while ordinary developer diagnostics remain available in the console.

In packaged mode:

- user data root: `%LOCALAPPDATA%\Ardenia\`;
- saves: `%LOCALAPPDATA%\Ardenia\saves\`;
- logs: `%LOCALAPPDATA%\Ardenia\logs\`; and
- directories are created on demand with clear errors when Windows refuses access.

The environment variable `ARDENIA_USER_DATA_DIR` will override the user-data root for automated tests and the packaged self-check. Normal releases will not document that override to testers. The helper must resolve it to an absolute path before use and must never derive writable save paths from PyInstaller's temporary/runtime bundle directory.

Source-tree saves are not silently copied into the packaged user-data folder. The development and public playtest environments remain intentionally separate.

### 5.4 Bundled read-only resources

The PyInstaller specification will explicitly include all non-Python data loaded at runtime, especially `content/countries/*.json`, plus any current UI or content resources that are accessed by path. Python modules under `content/`, including the lore package, are collected through ordinary imports unless inspection identifies a dynamic import that requires an explicit hidden import.

Read-only bundled resources and writable user data must use different helpers. No save, log, or generated file may be written into the packaged resource tree.

### 5.5 Crash handling

The graphical entry point will install a top-level uncaught-exception handler before constructing the main menu. On a fatal Python exception it will:

1. create a timestamped UTF-8 text log under the packaged log directory;
2. record the Ardenia version, Python/runtime information, operating-system version, and traceback;
3. avoid recording names, save contents, recordings, or unrelated personal data;
4. show a plain fatal-error dialog containing the log path; and
5. exit unsuccessfully after the user closes the dialog.

Failure to create a log must not hide the original error. The fallback dialog will show a concise error and state that the log could not be written. No log or crash detail is transmitted automatically.

## 6. Tester experience

### 6.1 `PLAYTEST_README.txt`

The bundled tester guide will use neutral, non-technical language. It will instruct a tester to:

1. confirm the download came from the official GitHub repository;
2. extract the entire ZIP;
3. start screen recording before launching the game;
4. run `Ardenia.exe` and handle the documented unsigned SmartScreen prompt;
5. play independently for 45 minutes without consulting development documents or receiving strategy help;
6. stop early if they naturally want to stop and record that fact rather than forcing completion;
7. complete `FEEDBACK_TEMPLATE.txt` only after play; and
8. return the recording and form through the private channel supplied separately by the organizer.

The guide will state that webcam recording is unnecessary and microphone commentary is optional. It will not name a correct party, objective, policy, pacing model, political opponent, or intended interpretation. It will not mention the mission, regional inequality, purchasing power, Suzerain, Paradox, or the preferred prototype.

### 6.2 `FEEDBACK_TEMPLATE.txt`

The public template will adapt the existing session record for an asynchronous tester. It will remain answerable in plain text and capture:

- release version and Windows/display information relevant to defects;
- actual session length and whether the tester stopped early;
- what the tester believed their role and goal were;
- their first meaningful action and approximate time to it;
- places where they searched, waited, became passive, or did not know what to do;
- the first objective chosen and the tester's reason;
- any identifiable opponent, tradeoff, and consequence;
- what felt important;
- what the tester wanted to do but could not;
- what they expected to happen next;
- open reactions to the passage of time before any named pacing choices;
- anything that made the game appear unfinished or unavailable;
- technical/accessibility problems; and
- permission status for retaining the submitted recording and answers as anonymized research material.

The form will collect no name, email address, account identifier, or unnecessary personal data. The organizer controls the private return channel outside the repository. A blank template is public; completed forms and recordings stay outside the public repository unless a tester explicitly consents otherwise.

An asynchronous session counts toward the mission's human evidence gate only when the eligible external human tester submits both the screen recording and completed form with consent to retain anonymized research notes. Unrecorded downloads and casual comments remain useful informal feedback but do not count toward the required six-to-eight-session sample.

## 7. Build definition

The repository will gain `requirements.txt` for runtime dependencies and `requirements-build.txt` for packaging dependencies. The initial supported toolchain is 64-bit Python 3.14.6 and `PySide6==6.11.1`. The build definition will pin a PyInstaller release that explicitly supports Python 3.14 before implementation is accepted. Packaging must fail clearly if the selected Python, PySide6, or PyInstaller versions do not match the committed definitions.

The packaging work is divided into these bounded components:

- `version.py`: authoritative human and Windows file-version values;
- `app_paths.py`: source/packaged resource and writable user-data paths;
- `runtime_logging.py`: crash-log setup and fatal-error reporting;
- `packaging/ardenia.spec`: PyInstaller analysis and one-folder definition;
- `scripts/build_windows.ps1`: safe local build, verification, ZIP, and checksum orchestration;
- `distribution/PLAYTEST_README.txt` and `distribution/FEEDBACK_TEMPLATE.txt`: source copies of the tester-facing files;
- `.github/workflows/windows-playtest-release.yml`: clean verification and release publication; and
- focused tests for paths, versions, crash logging, packaged verification, and artifact contents.

`engine/persistence.py` will stop treating its import-time repository path as the universal saves directory and will ask `app_paths` for the save directory when performing file operations. Serialization, filenames, slots, save version, and save data remain unchanged. Resolving the directory at operation time allows the packaged executable and isolated tests to select the correct writable root without changing the simulation.

A committed PyInstaller specification will define:

- `gui.py` as the entry point;
- the executable name and Windows metadata;
- one-folder and windowed behavior;
- included JSON/resources and any proven hidden imports;
- deliberate exclusions only when verified safe; and
- the deterministic distribution directory layout.

A PowerShell build script will:

1. validate the supported interpreter and dependencies;
2. clean only the repository's explicit packaging output directories;
3. run PyInstaller from the committed specification;
4. copy the tester guide and feedback template into the distribution folder;
5. invoke packaged verification;
6. create the versioned ZIP; and
7. generate its SHA-256 checksum.

The script must resolve and verify its repository/output paths before any cleanup. It must never delete arbitrary caller-provided paths or user-data directories.

## 8. Packaged verification mode

`Ardenia.exe` will accept an internal `--verify-build` argument before entering the normal Qt event loop. The release workflow supplies a temporary application-data root and invokes this mode after packaging.

Verification will:

- import the complete GUI entry path;
- construct the main menu in an offscreen Qt application;
- load canonical Ardenia content and at least one foreign world actor;
- construct one government and one opposition campaign;
- serialize and reload a temporary campaign through the packaged save path;
- confirm required tester files and bundled country data are accessible;
- write and read a temporary log marker; and
- exit zero without opening a persistent game window.

It will not use or alter normal tester saves. Any missing import, Qt plugin, JSON resource, writable path, or round-trip failure exits non-zero and prevents release publication.

## 9. GitHub release workflow

The repository will contain one Windows playtest release workflow. It runs only when:

- a tag matching `v*-playtest.*` is pushed; or
- the owner manually dispatches a non-publishing verification build.

Ordinary pushes and pull requests do not publish releases. The workflow uses a clean 64-bit Windows runner and performs these gates in order:

1. check out the exact commit;
2. configure the supported Python toolchain;
3. install pinned runtime and build dependencies;
4. validate tag/version agreement;
5. run the full UTF-8 engine smoke suite;
6. run the patched offscreen GUI smoke suite;
7. build the one-folder package;
8. run `Ardenia.exe --verify-build` against a temporary data root;
9. produce the versioned ZIP and SHA-256 file; and
10. publish a public GitHub Release only for the matching tag trigger.

A manually dispatched run uploads a temporary workflow artifact for owner inspection but does not create a public GitHub Release. A failed job publishes nothing. Release assets are immutable for a given version: corrections require a new playtest version rather than silently replacing a previously tested archive.

Release notes will identify the version, exact commit, Windows-only status, unsigned/SmartScreen limitation, checksum, extraction instructions, save/log locations, known issues, and organizer-controlled private feedback return process.

## 10. Security and privacy

The first build is intentionally unsigned. The GitHub Release will state this clearly, link to the official repository, and publish the archive checksum. Instructions may explain the ordinary SmartScreen `More info` / `Run anyway` path but must not imply that arbitrary unsigned downloads are safe.

The application makes no new network requests. It does not upload saves, logs, recordings, or feedback. Crash logs contain diagnostic runtime information and tracebacks only. Tester recordings and completed forms are returned privately and stored outside the public repository according to consent.

No secret, access token, certificate, or private return-channel address is committed to the repository or bundled into the executable. GitHub publication uses the workflow's scoped repository token.

## 11. Test strategy

### Automated source checks

- Existing full `smoke_test.py` remains green with UTF-8 output.
- Existing patched offscreen `ui_smoke_test.py` remains green.
- Unit-level path tests cover source mode, packaged mode, environment override, directory creation, and denied/unavailable paths.
- Version tests cover tag/display/archive consistency and invalid version input.
- Crash-log tests verify file creation and safe fallback without transmitting data.

### Packaged checks

- The build script and GitHub workflow both run the packaged `--verify-build` path.
- A packaging manifest check confirms required tester files and content JSON are present.
- ZIP extraction followed by verification succeeds from a path containing spaces.
- Packaged saves remain outside the extracted program folder.

### Manual release-candidate checks

Before publishing the first tag, test the generated ZIP on a clean Windows 10 or 11 environment without Python installed:

- extract and launch;
- generate one government and one opposition campaign;
- advance time and exercise autosave;
- make and load a manual save;
- close, reopen, and load the campaign;
- replace the extracted build folder and confirm the save remains;
- confirm the version and tester instructions match the release;
- confirm the SmartScreen instructions are accurate; and
- deliberately run verification against an isolated temporary data root.

At least one clean-machine manual run is mandatory for the first public playtest release. Automated verification supplements rather than replaces it.

## 12. Failure behavior

- A source-test failure blocks packaging.
- A PyInstaller or packaged-verification failure blocks ZIP creation/publication.
- A tag/version mismatch blocks publication.
- A missing runtime resource is a build failure, not a tester-facing degraded mode.
- A normal save/log directory creation failure shows a clear actionable error and does not redirect writes into the program folder.
- A GitHub workflow failure leaves the prior release untouched and creates no partial new release.
- A defect found after publication receives a new versioned release; the original asset remains associated with its recorded sessions.

## 13. First release acceptance checklist

The first public playtest release is ready only when:

- all source and GUI smoke tests pass on the tagged commit;
- the package builds from a clean Windows environment using committed definitions;
- packaged verification exits zero;
- a clean Windows machine without Python completes the manual campaign/save/load checks;
- `Ardenia.exe`, tester guide, feedback template, version, checksum, and release notes agree;
- packaged saves/logs use `%LOCALAPPDATA%\Ardenia\`;
- the archive contains no source-only caches, existing saves, private feedback channel, credentials, or participant material;
- the public release honestly identifies the build as Windows-only, unsigned, and intended for early playtesting; and
- no simulation, balance, save-schema, pacing, or pre-evidence feature work has entered the packaging change.

## 14. Rollout

The first intended tag is `v0.1.0-playtest.1`. After publication, the owner distributes the public GitHub Release URL to six to eight eligible external human testers and separately supplies the private return channel. The build remains frozen during the baseline sample. If a release-blocking defect requires correction, the replacement receives a new playtest version and the evidence synthesis keeps sessions separated by build.

After the six-to-eight-session evidence synthesis, distribution work may be expanded only where observed needs justify it. An installer, code signing, automatic updates, macOS/Linux support, telemetry, and public-demo polish remain later decisions rather than implicit commitments of this design.
