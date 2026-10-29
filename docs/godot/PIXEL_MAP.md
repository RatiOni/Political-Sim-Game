# Ardenia Godot — the pixel map

**Status:** built (2026-10-29). The dashboard map is a retro DOS 2D pixel map
of Ardenia. The city panel (below) is planned, not built.

**Art direction (the owner's):** retro DOS pixel art, not realistic. Flat
colours from one 32-colour palette, hard pixel edges, chunky sprites. Nothing
photographic, nothing smoothed. New art follows this, always.

## What the player sees

- Ardenia as a grid of tiles: sea, sand, grass, farmland, forest, hills,
  mountains, snow, rivers. Foreign land is drawn in dim grey.
- **Towns spread.** As a region grows, its towns put up more houses and spill
  past the administrative lines; the capital claims its ground first. Towers
  appear in developed towns. Hamlets of one to three houses rise in the
  countryside as a region's population passes thresholds. At dusk the
  developed share of houses is lit.
- **Farms and fallow.** Farmland spreads with development. Pressure leaves
  fields fallow.
- **Roads follow development.** Dirt roads, then paved roads, run along the
  authored routes, with the right sprite for each direction. A regional
  programme gives a small push up a tier. A rail link is laid only once every
  region it crosses is developed enough; until then nothing marks it.
- **Trouble is visible.** A region in trouble dims its towns, sends smoke
  up from them (3-cell plumes: fire, then two smoke cells, animated), and past
  higher thresholds puts barricades on its roads. Separatist land gets no
  barricades or routes.
- Click a region to select it, drag to pan, `+`/`-` or the wheel to zoom.
  The `NITE`/`DAY` button under the zoom buttons switches to dusk: the same
  map in a night palette, with lit windows. The choice holds across zoom.

## The grid

- 168 x 100 tiles, from the baked height and region rasters
  (`TileBaker`, `data/map/baked/tiles.json`).
- Two zoom levels. **Overview** draws 4 px tiles, **detail** draws 8 px
  tiles. The map picks the largest level that fits the panel and falls back to
  the overview, then scales by whole numbers only (`ArdeniaMap.level_zoom`).
  Detail usually overflows the panel, so dragging pans it.
- Drawing uses physical pixels: the map counter-scales for the window's
  content scale so a tile always covers a whole number of screen pixels
  and is never blurred (`TEXTURE_FILTER_NEAREST`).
- Native image at detail: 1344 x 800.

## The borders

Both the silhouette and the internal lines are baked in `MapBaker`, and both
are deliberately *not* one smooth family of curves — that is what made the
earlier map read as a generated blob.

- **The silhouette** gives each frontier its own hand, because each has its
  own history. The north is a folded mountain wall with three passes pushed
  out as salients and one lost valley notched back in. The east is the
  Krasovan line, surveyed under the Union: two genuinely straight segments
  meeting at one corner, and the only edge that takes **no** warp — a surveyed
  border is straight or it is not a surveyed border. The south wanders until
  `MEROVA_SURVEY_U`, where the Merova settlement rules it dead straight. The
  west is a worked coast: a headland, the Orvena bay (deep enough to leave a
  waist behind it) and the Kesla estuary.
- **The internal borders are not drawn.** Each region *grows* outward from its
  seed across the country it can actually administer (`_grow_regions`, a
  multi-source Dijkstra over a quarter-resolution cost field). Crossing a
  ridge costs `RIDGE_COST` scaled by elevation, crossing the Kesla costs
  `RIVER_COST`, crossing the ceasefire line costs `FRONT_COST`, and a broad
  low-frequency `WANDER` field gives cheap valleys and expensive country. The
  border is wherever two growths meet, so it lands on ridgelines, on the river
  and on the front. Growth from a single seed is connected by construction, so
  no region can fragment.
  Travel is eight-way: four-way growth meets along axis-aligned staircases
  (the L1 equidistance locus) and looks gridded. The wander field is low
  frequency on purpose — high-frequency noise averages out along a Dijkstra
  path and leaves the line straight.
- **`_crook`** then displaces the coarse ownership map by a domain warp, which
  adds the small jogs a real line has, and majority passes remove anything it
  strands, so no boundary speckles at tile size. `_absorb_fragments` returns
  any islet the coast cut loose to the sea.
- **Nothing finer than a tile may be authored into a border**, because the
  border is drawn on the tile grid and anything smaller can only alias into
  raster noise — one-cell zigzags, jaggies and notches that read as a bad
  scan rather than a frontier. Three things are kept above that floor:
  `MASK_WARP_FREQUENCY` (the land mask's domain warp — two tiles of amplitude,
  so a wavelength near the tile size serrates the whole frontier),
  `CROOK_FREQUENCY` (a jog every twenty tiles is a jog; every five is jitter),
  and the fine `_fold`/`sin` terms in `northern_edge`, `southern_edge` and
  `coastline`. **Count a `_fold`'s octaves, not its scale:** lacunarity is 2,
  so a third octave creases at four times `scale`, and the fold itself doubles
  that again — three octaves at scale 9 crease every eighth of a `scale` unit.
  The coast is the edge that cannot afford them, because it runs along the
  *short* axis of a hundred tiles: its pair of three-octave folds creased
  roughly every row and a half and the grid drew that as a ±1 tile stutter in
  and out of the sea. It is now one single-octave fold at scale 6, which
  creases every eight rows. `_fold` takes an `octaves` argument for this.
  The Gaussian features — the passes, the lost valley, the
  headland, the Orvena bay, the Kesla estuary — are all far above the floor
  and are untouched by any of this.
- **`_majority` is the de-staircase**, and its radius is set in tiles, not in
  coarse cells: a coarse cell is half a tile, so a 3x3 kernel cannot see a
  one-tile step at all. `MAJORITY_RADIUS` 2 spans two and a half tiles, which
  shaves single-cell spurs and notches and collapses runs of alternating
  single steps into one longer, regular step. It runs on the internal
  ownership grid only, which is masked to Ardenia afterwards, so it can
  lengthen a provincial line but can never touch the silhouette. Measured on
  the tile grid, it took the partition from 1232 boundary edges and 72
  one-tile spurs to 1095 and 27, with the canon adjacency table, the nine
  cities and the ceasefire line all unmoved.
- Everything is seeded from `MapBaker.SEED` (1993). Two bakes produce
  byte-identical `height.exr`, `region_ids.png`, `borders.json` and
  `tiles.json`.

`ardenia_world.json`'s `regions` seeds and `weights` are the tuning knobs:
they are presentation data, and the canon adjacency table in
`tests/map/test_map_baker.gd` is what keeps them honest.

## The palette

`MapPalette` holds three sets and nothing on the map is coloured from
anywhere else:

- `DAY` — the 32 colours.
- `DUSK` — derived from `DAY` by a tint; lit windows, gold and the ceasefire
  red stay bright.
- `FOREIGN` — 10 greys for land outside Ardenia (with its own dusk).

## The atlases

`TileArt` builds two atlases, one per tile size:
`data/map/tile_atlas.png` (8 px) and `tile_atlas_4.png` (4 px), each with a
JSON index (`tile_atlas.json`, `tile_atlas_4.json`). The index is cached after
first load. Every pixel is recoloured to `MapPalette.DAY`.

Where the art comes from (full detail in `godot/assets/CREDITS.md`):

- **Kenney (CC0), recoloured:** `house`, `house_lit`, `tower`,
  `barricade`, from Micro Roguelike. The Kenney fonts draw the map labels.
- **Generated in the project's own style:** every ground tile and variant,
  the redrawn `farm`, `fallow`, `mountain` and `snow`, `capital`, the road,
  paved and rail tiles in all four orientations, fire and smoke frames.

## Re-baking the data

Run these in this order, from the repo root, with
`G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"`:

1. `"$G" --headless --path godot --script res://tools/bake_map.gd`
   rewrites `height.exr`, `region_ids.png`, `borders.json` and `tiles.json`.
2. `"$G" --headless --path godot --script res://tools/build_tile_atlas.gd`
   rewrites both atlas PNGs and their JSON indexes.
3. `"$G" --headless --path godot --import`

**Do not skip the import.** Without it Godot keeps its old cached copy of the
atlas and the game shows scrambled terrain: tiles point at the wrong sprites.
Then run the full battery.

## The layers

`ArdeniaMap` stacks, bottom to top:

| Layer | What it holds |
|-------|---------------|
| `terrain_layer` | The baked ground, filled once. |
| `growth_layer` | Everything the state changes: farm, fallow, houses, towers, capital, route tiles, barricades. |
| `smoke_layer` | Animated plumes above troubled towns. |
| `routes_rect` | Dotted roads and open rail where no route tile covers them. A small image updated in place when the covered cells or open rail links change. |
| `lines_rect` | Borders and the ceasefire line. Built once per tile size and palette, then cached. |
| `map_labels` | Region and city names in pixel fonts, drawn crisp. |

Selection and hover outlines are drawn on top and never rebuild the lines.

## What each growth rule reads

All of it is in `GrowthLayers`, pure functions of the monthly region
snapshot. A row carries `population`, `development`, `pressure`, `control`,
`insurgency`, `civil_war`, `vetrenka_status` and `active_program`; the
trouble fields are filled in `native_game.gd`.

- **Houses:** `town_tiles` from population, capital larger. Cities claim
  cells in order, the capital first, so towns spill past region lines
  without overlapping.
- **Hamlets:** `hamlet_count` gives one hamlet at `HAMLET_FIRST_POPULATION`
  (500k) and one more every `HAMLET_POPULATION_STEP` (250k), up to
  `MAX_HAMLETS`. Each grows from one to `HAMLET_HOUSES` houses across its
  step. Sites (`hamlet_sites`) are buildable cells of the region beyond every
  city's town reach, in a stable hash order from the tile data and at least
  `HAMLET_SPACING` apart, so a hamlet never moves once it stands.
- **Lit houses:** `lit_share` from development and population.
- **Farm and fallow:** `farm_share` and `farm_reach` from development;
  `fallow_share` from development and pressure.
- **Road tier:** `road_tier` from development, plus a bonus while a regional
  programme runs. Each route cell picks its sprite from the route's direction
  (`route_suffix`).
- **Rail:** `locked_rails` closes a rail link while any non-separatist
  region it crosses is below `RAIL_DEVELOPMENT` (0.5). A closed link draws
  nothing at all, not a track: rail usually runs beside a road, so a track
  there would only double the road, and an empty corridor makes the opening
  a visible event.
- **Trouble:** `trouble` is pressure once it passes 0.5, plus insurgency,
  civil war and the Vetrenka status. Above 0.5 towns dim and smoke; above 0.7
  one barricade, above 0.85 two.

`GrowthPainter` applies the result: cells that differ flip in a staggered
one-second tween, in a stable pseudo-random order. Smoke steps on a timer.

## Resilience and speed

- A snapshot row with an unknown region id is ignored with a `push_warning`;
  the known regions still apply.
- A month flips few cells. Measured over 24 synthetic months of growth and a
  civil war, the worst month flips under 300 growth cells (mean about 210);
  the test caps it at 600 (`ArdeniaMap.last_changed_cells`).
- Redraws allocate no image. The border image is built once per tile size
  and palette (`lines_builds` counts builds) and reused; a month that moves
  barricades or opens rail only rewrites the route image (`routes_builds`).
  The test holds `lines_builds` flat over 12 crisis months at both levels.
- Town, farm and hamlet candidates depend only on the tiles and cities, so
  `GrowthLayers` memoises them; the first snapshot pays for them once.
- An unknown region id is warned about once (`unknown_warnings`).
- Test: `godot/tests/map/test_map_resilience.gd`.

## Planned: the city panel

Not built yet. Each city gets a clickable city icon on the map. Clicking it
opens a panel with pixel-art city background art, in the map's own retro DOS
style and palette. The art changes gradually as the city grows, develops and
modernizes: a small, shabby town early, then more buildings, paved streets,
towers and lit windows, following the same development and population the
growth layers already read. Nothing here changes the region-level map above.
