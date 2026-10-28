# The living map — design

**Date:** 2026-10-28 · **Status:** approved by the owner in conversation
(style, borders, approach A, all five growth layers, "install and approved").

## Goal

Replace the flat polygon dashboard map with a genuine, real-looking map of
Ardenia built natively in Godot from real assets, and make the map change
visibly when something real changes in a region — population growth,
development, programmes, decline and crisis.

## Decisions taken with the owner

| Question | Decision |
|---|---|
| Tool | Godot itself (no external map tool) |
| Look | Natural / satellite (option B of the style study) |
| Borders | Gilt: warm gold lines with a soft shadow; national border heaviest; borders follow the land, not straight cuts |
| Geography | A deliberate distortion of Georgia: Greater Caucasus as the northern wall with the crest on the border, sea to the west and south-west, Vetrenka on the north-western coast behind the ceasefire line, coastal lowlands, the Kesla from the northern passes through Vashtera to the sea at Tavri, the land narrowing eastward. Inspired by, never traced from, the real border (map bible rule). |
| Assets | Real assets, not procedural imitations: Terrain3D, Poly Haven CC0 photo-scanned materials, Kenney CC0 models |
| Approach | A: real 3D terrain viewed from above, rendered into the map panel |
| Growth layers | All five: towns spread, lights at dusk, roads and rail, fields, signs of trouble |
| Simulation | Add per-region population and development so the layers show real change |

## Assets (all verified licences)

| Asset | Source | Licence | Use |
|---|---|---|---|
| Terrain3D v1.0.2-stable | github.com/TokisanGames/Terrain3D | MIT | heightmap terrain, texturing, instancing |
| aerial_grass_rock, aerial_rocks_02, snow_field_aerial, aerial_beach_01, dirt_aerial_02, aerial_mud_1, forrest_ground_01 | polyhaven.com | CC0 | grassland, rock, snow, coast, farmland/fallow, roads, forest floor |
| City Kit Commercial 2.1, City Kit Suburban 2.0, City Kit Roads 2.2, Nature Kit 2.1 | kenney.nl | CC0 | town buildings, houses, checkpoints/props, trees and rocks |

Assets live under `godot/assets/` with `godot/assets/CREDITS.md`. Textures are
packed for Terrain3D (albedo+height, normal+roughness) and downsampled to 1K
— the map is seen at country scale — keeping the repository addition near
25 MB. Terrain3D's binaries are trimmed to the platforms we ship (Windows
x86_64 debug/release; Linux for CI).

Terrain3D 1.0.2 was proven to load, import a heightmap and render lit terrain
in Godot 4.7.2 under the `gl_compatibility` renderer before this spec.

## Architecture

```
ArdeniaMap (Control, replaces scripts/map/ardenia_map.gd internals)
 ├─ SubViewportContainer ─ SubViewport (own World3D)
 │    ├─ MapWorld (Node3D)
 │    │    ├─ Terrain3D           baked heightmap + control map (data/map/terrain/)
 │    │    ├─ Sea (MeshInstance3D water plane)
 │    │    ├─ Towns (one MultiMeshInstance3D per building kind)
 │    │    ├─ Lights (emissive town material + glow)
 │    │    ├─ Trouble (GPUParticles3D smoke per region, checkpoint props)
 │    │    ├─ Sun (DirectionalLight3D) + WorldEnvironment (day / dusk)
 │    │    └─ MapCamera (Camera3D, orthographic, straight down)
 │    └─
 └─ Overlay (Control drawn over the viewport)
      gilt borders, ceasefire line, region/city labels, selection, hover
```

### Units

- **`MapGeometry`** (pure data, no rendering) — loads `data/map/ardenia_world.json`:
  map extent, region seeds, cities, routes, ceasefire line, and the
  region-id raster path. Converts between map coordinates (0..1), world
  coordinates (metres) and screen coordinates. One canonical transform, so
  drawing and hit tests can never disagree.
- **`MapBaker`** (editor/headless tool script, run once) — generates the
  Georgia-inspired heightmap from the map canon and the region-id raster
  (domain-warped growth from the nine seeds, biased to follow ridges and
  rivers), bakes the Terrain3D control map from height/slope/moisture
  rules, traces region and national borders into smoothed polylines, and
  writes everything under `data/map/`. Deterministic: same inputs, same
  bytes. The game never regenerates terrain at runtime.
- **`MapWorld`** — owns the 3D scene, applies a regional snapshot to the
  growth layers, and animates changes over a few seconds.
- **`GrowthLayers`** — pure functions from a region's live state to visual
  targets (building count and spread radius, light intensity, road width
  tier, farmland share, trouble level). Pure so they are unit-testable
  without rendering.
- **`ArdeniaMap`** keeps its public surface (`region_selected` signal,
  `apply_snapshot(regions, selection)`, `select_region(id)`, `region_at(pos)`,
  `polygons`, `hovered_id`) so app.gd and the vertical slice keep working.
  Hit testing samples the region-id raster at the unprojected point.

### Data flow

NativeGame snapshot `regions[]` → `ArdeniaMap.apply_snapshot` →
`GrowthLayers.targets(region)` per region → `MapWorld` tweens each layer
from its current to its target value → Overlay redraws borders/labels.

## Population and development (simulation)

New fields on `RegionState`, persisted and validated:

- `population` (thousands; seeded from the authored regional population
  weights × Ardenia's population) and `development` (0..1; seeded from the
  authored profile — reach, unemployment and the region's character).

Monthly, in `RegionsSim` after regional conditions:

- **Population** grows by a natural rate and by migration toward
  opportunity: regions with lower unemployment, higher state reach and less
  pressure than the national average gain people; others lose them.
  Migration is a small share of the gap per month; total national
  population changes only by natural growth.
- **Development** moves toward a target set by ministry delivery in the
  region's portfolio, an active regional programme, national growth and
  state reach; it falls toward a lower target under high pressure,
  insurgency or war. Slow: years, not months.
- **Feedback, modest:** development nudges state reach up and structural
  unemployment down; live population replaces the authored population
  weights in elections, households and national pressure.

Separatist-held territory develops only by its own slow drift and receives
no state migration benefit; control changes from the arcs alter this.

## Growth layers

| Layer | Input | Rendering |
|---|---|---|
| Towns spread | population | Kenney buildings instanced around each city within a radius that grows with population; new villages appear at population thresholds |
| Lights at dusk | development × population | emissive window material on town instances plus glow; a day/dusk toggle on the map |
| Roads and rail | development, programmes | road-texture width and brightness along route polylines in the control map overlay; new links unlock at development thresholds |
| Fields | development and the agricultural share | farmland material share around lowland towns; fallow tint in decline |
| Signs of trouble | pressure, insurgency, civil war, Vetrenka status | smoke particles over the hardest-hit towns, dimmed lights, Kenney barriers at checkpoints, the ceasefire line physical while the conflict is frozen |

All layer changes tween over ~3 seconds when the month closes.

## Error handling

- Missing or malformed `data/map/` files: the map shows a clear "map data
  unavailable" state and the rest of the game continues; NativeGame never
  depends on the map.
- Terrain3D failing to load (unsupported GPU/driver): fall back to a
  pre-rendered top-down image of the same terrain with the same overlay,
  so the map remains usable.
- Region snapshot ids not in the geometry are ignored with a logged warning.

## Performance budget

- Map viewport renders at panel size, not window size; capped at 30 fps
  while the game is paused and nothing animates.
- Buildings via MultiMesh: at most ~3,000 instances nationally.
- Target: a smooth dashboard at 1280×720 on integrated graphics.

## Testing

- Unit: `GrowthLayers` (monotonic in population/development, bounded,
  trouble only above thresholds); population/development model (natural
  growth, migration toward opportunity conserving national population,
  development responds to delivery/programmes and decays under crisis,
  separatist rules, persistence and validation, long-run bounds).
- Baker determinism: two bakes produce identical files; every region id
  covers a contiguous area; borders are closed polylines.
- Map behaviour: hit testing returns the right region for each city
  position; selection/hover/keyboard contracts used by the vertical slice;
  snapshot application changes layer targets.
- Visual verification: screenshots at 1920×1080 and 1280×720, day and
  dusk, before/after a programme and a crisis.

## Out of scope

Weather, seasons, a zoomable/rotatable camera, the foreign-intelligence world
map, and sound design for the map.
