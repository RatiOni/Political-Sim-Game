# Baseline protocol: unassisted Ardenia sessions

Use this runbook with a fresh copy of [SESSION_TEMPLATE.md](SESSION_TEMPLATE.md) for every participant. It is written for a facilitator who does not know the codebase. Record what the participant does and says; do not supply the explanation you wish the game had supplied.

## 1. Recruit and schedule the sample

Recruit 5–8 external human participants: people outside the Ardenia project and its internal design/review process. Before scheduling, confirm that each person:

- has not read `EARLY_ACCESS_MISSION.md` or a summary of the product roadmap;
- has not received a tutorial, demonstration, action recommendation, or advance explanation of Ardenia from the team; and
- is willing to be observed under the consent arrangement below.

Assign the sample so that it includes both available campaign openings: government and opposition. Record the assigned opening and the opening actually used. A balanced split is useful when feasible, but the required standard is coverage of both openings, not an artificial quota. If a participant cannot or does not use the assigned opening, record the reason; do not coach them into it.

Set a common observation window before recruiting (for example, 45 minutes) and write it in every session record. A participant may stop earlier or continue only if your study arrangement permits it; record what happened rather than treating it as a pass or fail.

## 2. Consent, anonymity, and storage

Before opening the game, explain in plain language that you are observing an early game session to understand the experience, that participation is voluntary, and that the person may stop at any time. Ask separately for permission to retain anonymous notes and, if applicable, a screen or audio recording. Do not imply that recording is required.

Give the participant a non-identifying code (`P01`, `P02`, and so on). Record consent status, not a name or contact detail. Keep raw notes and any recordings outside this public repository unless the participant explicitly consents to inclusion. Store only a future product-level summary in project planning material.

## 3. Prepare a comparable session

Complete the session header before the participant arrives.

1. Use the intended baseline build and record its Git commit or other exact build identifier.
2. Record the device, display resolution, operating-system scaling, and any accessibility setup. Do not collect more personal device information than needed to understand a problem.
3. Record campaign settings, including the selected government/opposition opening, character or party choices, difficulty, and seed.
4. Choose seeds in advance and record them. Reuse a small predeclared set when comparison is useful, while leaving room to observe more than one situation. A seed is not representative of Ardenia; compare like settings and seeds cautiously and retain seed-specific variation in the notes.
5. Open a blank session template and a clock. If recording is consented to, check that it works before play begins.
6. Set up so the participant controls the game. The observer may take quiet notes but should not point at controls, hover over choices, or take over input.

## 4. Give the opening prompt

Read this, or use an equally neutral equivalent:

> Please begin when you are ready and play in whatever way makes sense to you. If you are comfortable, say aloud what you are thinking or expecting as you go. I will take notes, but I cannot help with game choices. Please tell me if you want to stop or if there is a technical, accessibility, or safety problem.

Do not mention regional inequality, purchasing power, comprehension, Suzerain, Paradox, the roadmap, or a preferred pacing model in the opening prompt. Do not describe a correct goal, a recommended action, or what the participant should notice.

## 5. Observe without intervening

Start the clock when the participant begins. Record timestamps, direct quotations, visible actions, and observable outcomes in the facts section of the template. Keep interpretation separate.

### Consistent observation definitions

- **Meaningful action:** an intentional in-game commitment that can affect the campaign, such as selecting a campaign choice, confirming a political or administrative action, committing resources, making a decision, or advancing time after deciding to proceed. Moving the pointer, opening and closing a screen without using it, and observer-directed recovery are not meaningful actions.
- **Time to first meaningful action:** the elapsed time from the opening prompt to the first meaningful action. Record `not reached` if it never occurs.
- **Stall:** either (a) 20 or more seconds without a purposeful game action while the participant appears to be deciding, searching, waiting, or disengaged, or (b) any shorter interval in which they explicitly say they do not know what to do, ask what to do, or say they are waiting. Record the start/end time and evidence. Do not record normal reading or an intentional pause as a stall unless the definition is met.
- **Passive interval:** a period in which the participant lets time pass or watches without stating a reason or taking a purposeful action. Record its duration and visible context; do not assume its cause.

Record every stall, passive interval, and spontaneous "what do I do?" moment. Capture any spontaneous statement of the participant's role, current goal, first objective, reasons, opponent, tradeoff, or consequence. Do not ask them to account for these while the observed session is under way.

For each stall, the observer may classify it after the session as **confusion**, **boredom**, **weak stakes**, **lack of agency**, **technical/accessibility**, or **uncertain**. The label must cite an observed action or quotation; it is a hypothesis, not a claim about the participant's private state. Use `uncertain` when the record does not support a classification.

### No-coaching rule

During the observed session, do not:

- explain a mechanic, label, screen, or outcome;
- suggest an action, goal, or strategy;
- point to a control or tell the participant where to click;
- interpret what an outcome means; or
- rescue a stalled participant by advancing, choosing, or narrating the game.

Intervene only for a hardware problem, crash, accessibility need, or participant safety issue. Log each intervention exactly: time, trigger, what was done, whether it altered the session, and whether observation resumed. An intervention does not invalidate a session automatically, but it must be visible in synthesis.

## 6. Conduct the exit interview

Stop the observation window, then ask the following in order. Invite the participant to skip any question. Write their words before interpreting them.

1. "In your own words, what happened in this session?"
2. "What, if anything, felt important while you were playing?"
3. "What did you want to do that you could not do?"
4. "What did you expect to happen next?"
5. "Who or what, if anything, seemed to be pulling the campaign in a different direction from you?"
6. "What choice involved giving something up, if any?"
7. "What result do you think followed from one of your choices, if any?"
8. "What role did you think you had, and what was your goal when you stopped?"
9. "What was the first objective you chose, if any, and why did you choose it?"
10. "Did anything make the game seem unfinished or unavailable? What gave you that impression?"
11. "How did the passage of time feel while you played?"
12. "If you could choose how time advanced, what would you want?"

Only after the open time question, offer these named choices if the participant wants help naming a preference: daily real-time, advance to the next meaningful decision or date, monthly advancement, or no preference. Record both the open answer and any named choice. Do not treat an inability to name an opponent, tradeoff, or consequence as an error; record it as missing evidence.

## 7. Close and store the session

Record completion, abandonment, duration, missing observations, and any technical or accessibility issue. Separate factual notes and quotations from the observer's interpretation before closing the template. Store the anonymized raw record outside the public repository according to the consent decision.

Do not synthesize after a single memorable session. Once all 5–8 eligible human sessions have raw notes, make a copy of the following section and complete it. Automated checks, agent cold reads, and expert reviews may be listed as supplementary context, but they never count toward or replace the human sample.

## Post-sample synthesis and evidence decision (copy after all sessions)

**Evidence gate status**

- Date completed:
- Facilitator:
- Eligible external human sessions completed: `__/5–8`
- Government openings represented (participant codes only):
- Opposition openings represented (participant codes only):
- Excluded or incomplete sessions and reason:
- Build commits, settings, and seeds represented:
- Raw anonymous notes stored outside the public repository: yes / no
- Supplementary automated, agent, or expert material (not counted as human sessions):

### Evidence inventory

- First meaningful-action times and relevant context:
- Stall/passive-interval patterns, with quotations or observations:
- Participants' stated roles and goals:
- Named opponents, tradeoffs, and consequences, including missing evidence:
- First objectives and stated reasons:
- Time reactions and open-ended pacing preferences:
- Perceived missing or unavailable product scope:
- Technical/accessibility findings and logged interventions:
- Differences by government/opposition, settings, seed, or build (not general claims from one seed):
- Disconfirming evidence:
- Unresolved uncertainty and missing data:

### Interpretation: what kind of problem was observed?

Record evidence before choosing a conclusion. Information-hierarchy or comprehension problems are supported when participants can state a desired purpose or choice but cannot find, prioritize, or understand the information/control needed to act. Missing-stakes, opposition, consequences, or agency problems are supported when participants can locate and understand the information but report or show that choices lack a meaningful conflict, cost, result, or available route. Both, neither, or unresolved are valid outcomes.

| Candidate explanation | Evidence supporting it | Evidence against it | Confidence / uncertainty | Next question or check |
| --- | --- | --- | --- | --- |
| Information hierarchy / comprehension |  |  |  |  |
| Missing stakes |  |  |  |  |
| Missing identifiable opposition |  |  |  |  |
| Missing consequences |  |  |  |  |
| Lack of agency |  |  |  |  |
| Technical or accessibility barrier |  |  |  |  |

### Required evidence decisions

These are decisions to justify from the inventory, not a vote-counting exercise. Record alternatives and disconfirming evidence; do not select the most common answer merely because it has the largest raw count.

1. **Pacing:** retain daily real-time pacing, or replace it with which model (next meaningful decision/date, monthly advancement, another model, or defer)?
   - Decision:
   - Behavioral evidence and quotations:
   - Disconfirming evidence / uncertainty:

2. **First reform family:** confirm regional inequality, or select another first reform family.
   - Decision:
   - Observed first objectives and stated reasons:
   - Why this evidence supports or challenges the decision:
   - Disconfirming evidence / uncertainty:

3. **Political counterparty and consequential choice:** identify one named political counterparty, its demand, and a concession or rejection that should matter later.
   - Named counterparty:
   - Demand:
   - Consequential concession or rejection:
   - What must persist or be judged later:
   - Evidence and uncertainty:

4. **Smallest prototype loop:** specify the smallest diagnosis-to-judgment loop justified by this sample.
   - Diagnosis the player encounters:
   - Objective and choice the player authors:
   - Opposition / negotiation:
   - Delivery or consequence:
   - Later political judgment:
   - What is deliberately out of scope:
   - Evidence and uncertainty:

5. **Checkpoint outcome:** proceed to a new, evidence-based prototype plan; gather more sessions; or revise the baseline question.
   - Decision:
   - Rationale:
   - What must exist before development begins:

No thin reform prototype, time-model implementation, or generic decision-stop framework begins until this completed synthesis and the required human-session notes exist.
