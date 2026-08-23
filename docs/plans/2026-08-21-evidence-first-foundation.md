# Evidence-First Early Access Foundation

**Status:** Approved for execution
**Branch:** `feature/evidence-first-foundation`
**Baseline:** `1f14604`
**Decision:** The user selected the revised evidence-first premises and authorized a new Git repository.

## Objective

Move Ardenia from an architecture-first roadmap to an evidence-first product sequence. The immediate goal is to learn whether new players are blocked by comprehension, weak political stakes, passive pacing, or insufficient agency before committing to the generic reform and pause frameworks.

The product target is **legible political authorship**: the player diagnoses a real problem, chooses a response, bargains with identifiable political actors, sees the state deliver it imperfectly, and faces judgment for the result.

## Global Constraints

- Ardenia remains the only player country. Other countries remain complete world actors and must continue to load through `build_state_for(id)`.
- Do not implement reform instruments, lifecycle/history, targeted incidence, generic forecasts, queue acknowledgements, new persistence fields, or balance changes in this tranche.
- Do not treat agent review as a substitute for unassisted human playtesting.
- Do not redesign the main dashboard yet. Its hierarchy must be informed by observed play.
- Preserve GUI and CLI behavior outside the explicitly changed Ardenia campaign entry.
- Preserve save compatibility and the country-neutral engine.
- Run tests with `PYTHONUTF8=1` on Windows because the smoke suite prints Unicode symbols.
- Each task receives an implementation review for specification compliance and code quality before the next task begins.

## Task 1: Rebase the canonical Early Access mission

**Files:**

- Modify `docs/EARLY_ACCESS_MISSION.md`

**Requirements:**

1. Make political authorship, rather than comprehension alone, the product-level bottleneck and outcome.
2. Preserve comprehension as a required quality, but state that explanation cannot compensate for choices without stakes, opposition, or consequences.
3. Replace the immediate sequence with:
   - protected Git baseline;
   - unassisted baseline playtests of the current build;
   - one deliberately narrow diagnosis-to-judgment prototype;
   - time-model comparison;
   - productionization only after evidence identifies the winning loop.
4. Name regional inequality as the default first canonical prototype because the live opening diagnosis ranks it first. Purchasing power remains a valid later family or shock-driven objective, not the default opening crisis.
5. Replace the hard four-family Early Access quota with an evidence gate:
   - family one proves the complete loop is enjoyable;
   - family two proves the architecture generalizes;
   - observed replay needs determine whether three or four are required before Early Access.
6. Add the requirement that the reference reform include one persistent named negotiating counterparty whose demand, concession or rejection, memory, and later judgment survive the project.
7. Record that real-time-with-pause, advance-to-next-decision, and monthly advancement must be compared before deep generic stop infrastructure is built.
8. Keep all existing Early Access safety, stability, save, accessibility, and honesty gates unless they directly contradict the accepted premises.

**Verification:**

- Search the mission for stale claims that purchasing power is necessarily first or that exactly four families are an unconditional release gate.
- Confirm the immediate milestone explicitly ends at the external evidence checkpoint.

## Task 2: Make the opening confidently Ardenia-only

**Files:**

- Modify `ui/menu.py`
- Modify or add focused GUI tests using the project's existing headless style
- Update `AGENTS.md` and `CLAUDE.md` only where their campaign-wizard descriptions become false

**Requirements:**

1. The country step must present Ardenia as the campaign, not display eight disabled `Coming Soon` rows.
2. Use direct language equivalent to `Begin the Ardenia campaign` and explain that neighboring states remain simulated world actors.
3. Preserve `PLAYABLE_COUNTRY_IDS` or an equally small future expansion seam. Do not delete foreign country data, world simulation, diplomacy targets, map relationships, or country-neutral loader support.
4. `CountrySelectStep.collect()` must still reject a non-playable injected country ID defensively.
5. Preserve wizard navigation, default selection, character setup, party/opening-role choices, difficulty, and seed behavior.
6. Add focused assertions that:
   - Ardenia is the only visible campaign country;
   - no `Coming Soon` country rows are rendered;
   - collection returns `ardenia`;
   - foreign `build_state_for(id)` behavior remains untouched.

**Verification:**

- Run the focused wizard/UI test with modal execution patched for offscreen mode.
- Run `python smoke_test.py` with UTF-8 enabled.

## Task 3: Create the unassisted baseline playtest packet

**Files:**

- Add `docs/playtests/README.md`
- Add `docs/playtests/BASELINE_PROTOCOL.md`
- Add `docs/playtests/SESSION_TEMPLATE.md`

**Requirements:**

1. Define a 5–8 person baseline using people who have not read the mission or received prior coaching.
2. Cover both government and opposition openings. Use recorded campaign settings and seeds so sessions can be compared without pretending one seed is representative.
3. The observer must not explain mechanics or suggest actions during the session.
4. Record at minimum:
   - time to first meaningful action;
   - where the player pauses, becomes passive, or asks what to do;
   - what they believe their role and current goal are;
   - whether they can name one opponent, one tradeoff, and one consequence;
   - whether confusion, boredom, weak stakes, or lack of agency caused each stall;
   - reactions to daily time and whether they want next-event or monthly advancement;
   - the first objective they choose and why;
   - whether disabled or unavailable content appears to be missing product scope.
5. Include neutral exit-interview questions that do not lead players toward the roadmap's preferred answer.
6. Define the evidence decision after the sessions:
   - retain or replace daily real-time pacing;
   - confirm regional inequality or choose another first reform family;
   - identify the named political counterparty and consequential concession;
   - specify the smallest prototype loop;
   - distinguish information-hierarchy problems from missing gameplay stakes.
7. State plainly that development stops at this checkpoint until session notes exist. Agent cold reads may supplement, not replace, human sessions.

**Verification:**

- A person unfamiliar with the code can run a session using only the protocol and template.
- Every accepted evidence-first premise has a corresponding observation or decision field.

## External Evidence Checkpoint

After Tasks 1–3 are merged, recruit and observe 5–8 unassisted players. Store anonymized session notes outside the public repository unless participants consent to inclusion. Summarize only product findings in a future planning document.

Do not begin the thin reform prototype, time-model implementation, or generic decision-stop contract until this evidence is available. The next implementation plan must be written from those findings.

## Completion Criteria for This Tranche

- Git baseline and isolated feature branch exist.
- The canonical mission reflects the accepted evidence-first premises without contradictory quotas or sequencing.
- The wizard presents one confident Ardenia campaign and no disabled-country catalog.
- A complete, neutral playtest packet exists.
- Focused UI checks and the full engine suite exit 0.
- No reform mechanics, balance values, persistence schema, or dashboard hierarchy were changed.
