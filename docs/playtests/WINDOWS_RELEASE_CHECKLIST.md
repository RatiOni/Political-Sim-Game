# Windows Playtest Release Checklist

Use this owner checklist before the first immutable public playtest tag. Keep the
record private if its evidence contains machine names, user paths, or participant
details. Do not commit private feedback addresses, completed feedback, or other
participant material.

- [ ] **1. Confirm the candidate identity.** Record the candidate commit and
  confirm that `version.py` consistently declares `0.1.0-playtest.1`, Windows
  file version `0.1.0.1`, tag `v0.1.0-playtest.1`, and the expected archive
  filename.

  Evidence: ________________________________________________

- [ ] **2. Pass all source checks.** Run `distribution_test.py`, the full
  UTF-8 `smoke_test.py`, and the offscreen UI runner from the candidate commit;
  record their exit codes and confirm that the UI runner reports zero failures
  and zero skips.

  Evidence: ________________________________________________

- [ ] **3. Build and hash locally.** Run the local PowerShell Windows build,
  recompute the ZIP's SHA-256 with `Get-FileHash`, and compare it byte-for-byte
  with the generated `.sha256` file.

  Evidence: ________________________________________________

- [ ] **4. Test a clean Windows machine.** In a clean Windows 10 or Windows 11
  environment without Python installed, extract the candidate ZIP and launch
  `Ardenia.exe` from the extracted `Ardenia` folder.

  Evidence: ________________________________________________

- [ ] **5. Exercise both political roles.** Generate both a government campaign
  and an opposition campaign on that clean machine, and confirm each reaches
  playable state.

  Evidence: ________________________________________________

- [ ] **6. Exercise save continuity.** Advance time far enough to trigger an
  autosave, create a manual save, close the program, reopen it, and load both
  kinds of save successfully.

  Evidence: ________________________________________________

- [ ] **7. Test program replacement.** Close the game, replace the extracted
  program folder with a fresh extraction, relaunch it, and confirm the save
  remains available under `%LOCALAPPDATA%\Ardenia` rather than inside the
  program folder.

  Evidence: ________________________________________________

- [ ] **8. Cross-check the public identity.** Confirm the window title, tester
  packet, ZIP filename, SHA-256 checksum file, and release notes all say
  `0.1.0-playtest.1` and do not name a different build.

  Evidence: ________________________________________________

- [ ] **9. Confirm the unsigned launch experience.** Follow the documented
  unsigned SmartScreen path on clean Windows, confirm it matches the tester
  instructions, and record any materially different warning or blocking
  behavior.

  Evidence: ________________________________________________

- [ ] **10. Integrate before tagging.** Integrate the reviewed feature branch
  into `main`, then confirm the intended candidate commit is present on clean
  `main` before creating any public tag.

  Evidence: ________________________________________________

- [ ] **11. Publish and independently verify.** Push the immutable
  `v0.1.0-playtest.1` tag, watch the GitHub workflow finish successfully,
  download the public ZIP and checksum from the resulting release, independently
  recompute the ZIP hash, and confirm it matches the published SHA-256.

  Evidence: ________________________________________________

- [ ] **12. Freeze the baseline sample.** Freeze the build for the planned
  six-to-eight-session sample. Do not replace an asset after play begins; publish
  any emergency replacement as a new version and record which participant used
  which build.

  Evidence: ________________________________________________

## Rollback and failed-publication rule

If the public workflow fails, do not recreate or move the same tag against
different code. Fix forward on `main`, increment the playtest version, and
publish a new immutable tag (for example, `v0.1.0-playtest.2`). Do not delete or
replace a release asset once a session has used it.
