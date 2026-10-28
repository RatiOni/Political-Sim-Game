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
  appear in developed towns. At dusk the developed share of houses is lit.
- **Farms and fallow.** Farmland spreads with development. Pressure leaves
  fields fallow.
- **Roads follow development.** Dirt roads, then paved roads, run along the
  authored routes, with the right sprite for each direction. A regional
  programme gives a small push up a tier. Rail is always drawn.
- **Trouble is visible.** A region in trouble dims its towns, sends smoke
  up from them (3-cell plumes: fire, then two smoke cells, animated), and past
  higher thresholds puts barricades on its roads. Separatist land gets no
  barricades or routes.
- Click a region to select it, drag to pan, `+`/`-` or the wheel to zoom.
  Dusk shows the same map in a night palette.

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

- **Kenney (CC0), recoloured:** `house`, `house_lit`, `tower`, `tree`,
  `crops`, `barricade`, from Micro Roguelike. The 1-Bit Pack and the
  Kenney fonts ship too; the fonts draw the map labels.
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
| `map_lines` | Borders, routes under their tiles, the ceasefire line. Built per tile size and palette, then cached. |
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
- **Lit houses:** `lit_share` from development and population.
- **Farm and fallow:** `farm_share` and `farm_reach` from development;
  `fallow_share` from development and pressure.
- **Road tier:** `road_tier` from development, plus a bonus while a regional
  programme runs. Each route cell picks its sprite from the route's direction
  (`route_suffix`).
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
- Redraws allocate no image. The line image is built once per tile size and
  palette (`lines_builds` counts builds) and reused.
- Test: `godot/tests/map/test_map_resilience.gd`.

## Planned: the city panel

Not built yet. Each city gets a clickable city icon on the map. Clicking it
opens a panel with pixel-art city background art, in the map's own retro DOS
style and palette. The art changes gradually as the city grows, develops and
modernizes: a small, shabby town early, then more buildings, paved streets,
towers and lit windows, following the same development and population the
growth layers already read. Nothing here changes the region-level map above.
