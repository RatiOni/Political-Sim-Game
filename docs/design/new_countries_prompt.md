# Prompt: create the 22 new countries for Ardenia

You are adding 22 new countries to Ardenia, a grand-strategy game written
natively in Godot 4.7.2 with statically typed GDScript. The world grows from 9
to 31 countries. Work in the worktree
`D:\Political Sim Game\.worktrees\godot-native-sim`, on branch
`claude/godot-native-sim`.

Other chats commit to this branch, including the map chat and a simulation
chat. Stage only your own files and check each commit with `git show HEAD:`.
Never push, merge or publish.

## Read first

- `docs/design/world_map_prompt.md`, which holds the binding geography and
  clusters for all 31 countries.
- The 9 existing country files in `godot/data/native/countries/`
  (`ardenia`, `krasova`, `veldoria`, `merova`, `solheim`, `nueva_costa`,
  `qadir`, `terand`, `valmora`). Copy their exact schema: government,
  factions/parties, economy, agenda (`type`, `rival`, `ally`, `backs`),
  stability, relations, leader and any other fields. Use
  `godot/scripts/native/state/` (the country loader and the StateValidator)
  to learn which fields are required and which values are valid.
- `godot/data/native/foreign_orientation.json` for the blocs: Concert,
  Meridian, the Krasovan Economic Union and their seed members, plus how
  anchors work. Also `godot/data/native/energy.json`.
- `docs/godot/LIVING_WORLD.md` for how the world AI reads agendas, rivals,
  allies, blocs and civil-war risk, and for the design rules.
- Root `CLAUDE.md`, the "Country-neutral content (roles)" section. Situations
  address factions by role (`@labour`, `@business`, `@nationalist`,
  `@agrarian`, `@reform`, `@establishment`) and countries by sentinel, so every
  country needs factions that let those roles resolve sensibly.

## The 22 new countries (owner-approved)

| Country | Cluster | Flavour (inspired, never copied) | Agenda | Notes |
|---|---|---|---|---|
| Ozmara | Ardenia's southern neighbour | Turkey-like | regional power | Courts the Concert while playing its own game. Gas transit route (the southern corridor). |
| Zelvany | Krasovan sphere | Belarus-like | survivor | Krasova's loyal client; Union member. |
| Borynia | Krasovan sphere | Moldova/Ukraine-like | reformer | Drifting West; contains a Krasova-backed breakaway region. |
| Kalvia | Krasovan sphere | Baltic-like | reformer | Broke free of Krasova; Concert member. |
| Haravan | Krasovan sphere | Armenia-like | survivor | Small and landlocked; allied to Krasova; frozen border war with Turaz. |
| Temirsk | Krasovan sphere | Kazakhstan-like | trader | Huge steppe state balancing Krasova against the East. |
| Ulgar | Krasovan sphere | Central-Asian autocracy | ideologue | Union member. |
| Turaz | Eastern energy coast | Azerbaijan/Turkmenistan-like | trader | Gas-rich autocracy; Ardenia's possible alternative supplier. |
| Selenne | Aster Sea basin | Romania/Bulgaria-like | reformer | Concert member; Western gateway port. |
| Marisca | Aster Sea basin | island port state | survivor | Transit hub; smuggling. |
| Drevnia | Aster Sea basin | nationalist | revanchist | Old claims across the sea. |
| Aldermark | Western core | Germany-like | trader | Concert heavyweight; main ISF funder. |
| Valcourt | Western core | France-like | ideologue | Founder of the Meridian; pushes the security guarantee. |
| Nordhaven | Western core | Nordic | reformer | Aid donor; hawkish on Krasova. |
| Brisca | Western core | island power, UK-like | trader | Finance centre; Meridian navy. |
| Ilmar | South | oil autocracy | hegemon | Ozmara's rival. |
| Sahrun | South | fragile state | survivor | Civil-war candidate (high starting risk); source of refugees. |
| Azhara | South | rich monarchy | trader | Funds factions across the region. |
| Beyta | South | small, mixed faiths | survivor | Squeezed between Qadir and Ilmar. |
| Columbria | Distant great power | Western superpower | hegemon | Behind the Meridian. |
| Hanlin | Distant great power | Eastern great power | trader | Buys influence through loans and infrastructure. |

That table has 21 rows. Add a **22nd** of your own: a second small state in
whichever cluster is thinnest, in keeping with the canon. State your choice
and the reason in the report.

The 9 existing countries keep their ids and their core facts. You may add
relations to new countries in their files and adjust their bloc seeding if
the clusters need it, for example Solheim in the Western core and Valmora in
the Aster basin. Never change Ardenia's canon and never change Krasova's
antagonist role.

## Requirements

1. Each new country gets a data file in the existing schema with real
   content: a name, a short description in canon voice, government type,
   leader, 3 to 5 factions/parties with ideology vectors, economy figures
   scaled plausibly to its size and flavour, stability, civil-war risk, an
   agenda (type plus rival/ally/backs where the table implies them), and
   starting relations.
2. **Relations** must be consistent in both directions and match the clusters
   and story. Examples: Zelvany warm with Krasova, Kalvia cold with Krasova,
   Haravan and Turaz hostile, Ilmar and Ozmara rivals.
3. **Bloc memberships** go in foreign_orientation.json:
   - Concert: Kalvia, Selenne, Aldermark, Valcourt, Nordhaven, Brisca, plus
     the existing Western members.
   - Meridian: Valcourt, Brisca, Nordhaven, Aldermark, Columbria, plus the
     existing members.
   - Union: Zelvany, Ulgar, plus Krasova.
   - Ozmara is a Concert candidate, not a member.

   Keep the hard locks valid: no state may be in both the Union and the
   Concert or Meridian.
4. **Roles** must resolve sensibly in every new country. Section T of the old
   Python suite enforced this for the original 9. Write a native test that
   asserts every role resolves in every country, or is listed as a justified
   exception, and that no situation option becomes a silent no-op anywhere.
5. **Map hand-off.** Every new country must appear in whatever snapshot or
   world data the map reads, so the map chat can draw all 31 countries. Do
   not draw anything yourself.
6. **The world AI must stay sound** with 31 countries. Write a 20-year
   calendar-true journey test over at least 6 seeds that checks:
   - no NaN and no runaway values
   - every country stays bounded
   - plans and hostile moves happen, and pacing is not flooded
   - the dispatch volume per month stays readable

   Use a fixed cap you justify in the report.
7. **Every existing test must stay green.** That includes the election,
   ISF, fiscal, orientation and energy calibration bands, and the canon
   invariants: the Krasova feud forms, courted harm ≤ neglected harm, and
   Krasova presses. More countries add RNG draws, so if a band flips, find the
   cause with the established method: zero out the new content and see
   whether the band returns. If the cause is stream noise, follow the existing
   rulings, which use more seeds or a summed form. Never widen a band. If a
   band truly moves, stop and report it.

## Rules

- Write tests first. Mutation-check every new test: break the code it guards,
  confirm the test fails, then restore the code.
- Run every Godot test as
  `timeout 180 "/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script res://<test>`.
  A script that fails to compile never quits headless.
- Run `--import` after adding files.
- The full battery covers `godot/tests/native`, `godot/tests/ui`,
  `godot/tests/map` and `godot/scripts/tests/vertical_slice_test.gd`. It must
  be green with 0 pending before every commit.
- No explanatory comments in code. Prose in data descriptions is fine.
- `state_validator.gd` stays under 800 lines. Put new validation in its own
  file.
- Tests never use the save slot `godot_slice`.
- Leave no background processes running.
- Use conventional commits, each ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Add a short world-roster section to `docs/godot/LIVING_WORLD.md` in house
  style, player-facing first.

When you finish, report the 22nd country you chose, the bloc rosters, the
role-coverage exceptions, the journey results, and the test totals.
