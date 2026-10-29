# Prompt: the Ardenia world map (31 countries)

You are building the **world map** for Ardenia, a grand-strategy game written
natively in Godot 4.7.2 with statically typed GDScript. The worktree is
`D:\Political Sim Game\.worktrees\godot-native-sim`, on branch
`claude/godot-native-sim`.

The game already has a national map of Ardenia: `godot/scripts/map/`, plus
`docs/godot/PIXEL_MAP.md`. The world map must look like part of the same game.
It is a second map view, opened from the dashboard, that shows Ardenia's place
among 31 countries. The national map stays the main map.

## Art direction (binding)

- Retro DOS pixel art. Use a 2D tile map drawn in the same 32-colour
  `MapPalette`, the same day and dusk ramps, and the same pixel fonts (Kenney
  Pixel and Kenney Mini). Gold pixel borders: 2 px for national borders, and
  dashed lines for disputed or ceasefire lines.
- Pixels stay crisp: nearest filtering, integer scaling, two zoom levels and
  drag-to-pan, the same as the national map. Never blur.
- A deliberate distortion of the Black Sea and Caucasus region, with Europe to
  the north-west and the Middle East to the south. It must be inspired by real
  geography, never traced from it.
- The game is a grand strategy with DOS looks. It is not Victoria 3 or Hearts
  of Iron.

## Geography (binding canon; relative positions)

Ardenia sits on a mountainous isthmus. The **Aster Sea** lies to its **west and
south-west**. Ardenia has exactly **four land neighbours**:

| Direction from Ardenia | Country |
|---|---|
| North, beyond the mountain passes | **Veldoria** |
| East, past the Zavost and Darev regions (the Zovar gas line crosses here) | **Krasova** |
| South-east, beyond the lowlands | **Merova** |
| South, across the Kelvet–Sela frontier | **Ozmara** |

Vetrenka is Ardenia's separatist-held north-west coast. It lies **inside**
Ardenia's border. Draw the ceasefire line as a dashed red line inside
Ardenia, never as an international boundary.

The rest of the world, by cluster:

- **The Krasovan sphere: former Kolvenian Union states.** These lie north and
  east of Ardenia, around Krasova, which is the largest country in the region.
  - **Zelvany**: north-west of Krasova, beyond Veldoria.
  - **Kalvia**: a small coastal state on Krasova's far north-west edge.
  - **Borynia**: west of Krasova, north of the Aster Sea. It contains a
    breakaway region, drawn with a dashed ceasefire line inside its border.
  - **Temirsk**: a huge steppe state east of Krasova.
  - **Ulgar**: south of Temirsk.
  - **Haravan**: small and landlocked, south-east of Merova, between Ozmara
    and Turaz. It has a frozen border war with Turaz, drawn as a dashed
    contact line.
- **The eastern energy coast.** **Turaz** is a gas-rich state south-east of
  Krasova and east of Merova and Haravan, on the shore of a second, smaller
  inland sea to the east. Gas from Turaz can reach Ardenia through Ozmara (the
  "southern corridor") or across the Aster Sea.
- **The Aster Sea basin**, along the far western and north-western shores.
  - **Selenne**: a port state on the north-west shore.
  - **Drevnia**: west of Selenne.
  - **Valmora**: south-west of Drevnia. It is in a crisis state.
  - **Marisca**: a small island state in the Aster Sea itself.
- **The Western core**, far to the north-west beyond the Aster basin.
  - **Solheim**, **Aldermark** (the largest), **Valcourt** and **Nordhaven**
    (furthest north).
  - **Brisca**: an island off the western coast of the core.
- **The south**, beyond Ozmara.
  - **Ilmar**: a large oil state, south-east of Ozmara.
  - **Qadir**: south of Ozmara.
  - **Terand**: south-west of Qadir.
  - **Azhara**: on the southern coast.
  - **Sahrun**: between Ilmar and Qadir. It is fragile.
  - **Beyta**: small and coastal, between Qadir and Ilmar.
- **Distant powers.** These sit off the map's edges and are reached by sea.
  Show them as labelled edge markers or inset boxes, not as full land masses.
  - **Columbria** (west, over the ocean)
  - **Hanlin** (east)
  - **Nueva Costa** (far west, beyond the ocean)

The country ids are lowercase versions of the names. The nine that already
exist in `godot/data/native/countries/` are ardenia, krasova, veldoria,
merova, solheim, nueva_costa, qadir, terand and valmora. The other 22 are new
and need country data files, which the simulation workstream will add. Read
names and ids from that data, not from literals in the map code.

## What the map must show (live game state)

The map reads the game snapshot. It never computes simulation itself.
- **Relations with Ardenia**: a tint or border emphasis per country, from
  hostile to friendly. Use the pressure-style ramp, never the party palette.
- **Blocs**: Concert, Meridian and the Krasovan Economic Union, from
  `snapshot.foreign.map.memberships`. Show them as a border pattern or a small
  badge per member. They must still read clearly in the dusk palette.
- **Gas**: the Zovar line from Krasova into Ardenia, plus the southern corridor
  when it exists, drawn as pixel pipelines. When gas is cut or under threat,
  the line visibly breaks or dims. Per-region gas supply for the national map
  already exists at `snapshot.foreign.map.gas_supply`.
- **Crises**: civil war and coups in world countries, using the same
  smoke-and-fire pixel language as the national map's trouble layer, plus
  frozen-conflict lines.
- **Escalation**, which comes later: tension and incident markers against
  Ardenia. Leave a layer and a data hook for it.
- Clicking a country selects it and opens it on the Diplomacy desk.

## Engineering rules

- Follow the national map's code structure and its tests: the tile baker,
  palette, atlas and lines, and labels.
- Bake the world geometry once into data files. Rendering must be
  deterministic.
- Use test-first development with tests that fail when the code breaks. Run
  every test with `timeout 180`.
- No explanatory comments in code.
- Nothing on the dashboard resizes.
- Other chats commit to this branch, so stage only your own files.
