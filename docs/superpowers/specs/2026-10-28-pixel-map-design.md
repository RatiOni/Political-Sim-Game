# The pixel map — design

**Date:** 2026-10-28 · **Status:** approved by the owner in conversation
("this looks exactly right … this map is the way to go"). Supersedes the
rendering half of `2026-10-28-living-map-design.md`; its population and
development model, map geometry and region/border bake stay.

## Goal

Ardenia's dashboard map becomes a retro DOS-style 2D pixel map: a grand
strategy game in depth with DOS looks, not a realistic map. The map changes
visibly, tile by tile, when something real changes in a region.

Approved mockup: `.scratch/pixel_mock.html` (rendered from the real baked
data by the throwaway `godot/tools/_mock_pixel.gd`).

## Decisions taken with the owner

| Question | Decision |
|---|---|
| Look | 2D top-down pixel map, early-90s strategy feel |
| Scope | Map only; the rest of the UI keeps its current style for now |
| Pipeline | Tile grid derived from our baked data, not a painted image or a pixelated render |
| Growth layers | All five, expressed as tiles and sprites |

## The map

- Grid **168 × 100 tiles**, tiles **8 × 8 px** (a 1344 × 800 px native image),
  displayed with nearest-neighbour filtering and integer scaling, never blurred.
- One fixed **32-colour palette** (`MapPalette`), plus a dusk variant of the
  same palette.
- Tile kinds: deep sea, sea, shallows, sand, grass, farm, forest, hills,
  mountain, snow, river (the Kesla), town, road, rail. Foreign land is drawn in
  a greyed variant of the same tiles; it is not Ardenia.
- Borders: 1-px gold, dashed, between regions; a 2-px gold national border; the
  coast needs no border. The Vetrenka ceasefire is a dashed red line inside the
  national border, never an international boundary.
- Labels: region and city names in a bitmap pixel font with a 1-px black outline.
- Neighbouring countries are greyed out so Ardenia reads first.

## Units

- **`TileBaker`** (headless tool, run once) turns `height.exr`, `region_ids.png`
  and `ardenia_world.json` into `data/map/baked/tiles.json`: per-tile terrain
  kind and region index. Deterministic; the classification rules are the
  mockup's (height bands, low-frequency noise for forest and farm, shallows and
  sand by sea adjacency, farm pulled toward towns).
- **`MapPalette`** holds the palette and the day/dusk ramps.
- **`TileArt`** builds the tile atlas. The source is CC0 pixel art (Kenney:
  Micro Roguelike, 8×8, plus 1-Bit Pack for icons) recoloured to `MapPalette`.
  Any tile kind the packs don't cover is drawn by a deterministic generator in
  the mockup's style, and `godot/assets/CREDITS.md` records which is which.
- **`PixelMap`** (Godot `TileMapLayer`, one for terrain and one for overlays)
  draws the tiles, borders, routes, ceasefire, towns and trouble sprites.
- **`GrowthLayers`** are pure functions from a region's live state to tile
  targets: town footprint tiles per city, lit-window share, road tier per
  route segment, farm-tile share around towns, and trouble level.
- **`ArdeniaMap`** keeps its public surface (`region_selected`,
  `apply_snapshot`, `select_region`, `region_at`, `polygons`, `hovered_id`).
  Hit testing reads the tile's region index. `polygons` come from
  `borders.json` outlines, as before.

## Growth layers

| Layer | Input | Pixel expression |
|---|---|---|
| Towns spread | population | A city's town tiles grow outward ring by ring; hamlet tiles appear at population thresholds |
| Lights at dusk | development × population | In the dusk palette, town tiles light windows, more of them at higher development |
| Roads and rail | development, programmes | Route tiles upgrade from track to paved road; rail links unlock at thresholds |
| Fields | development | Grass tiles near towns turn to farm, and back to fallow in decline |
| Signs of trouble | pressure, insurgency, civil war, Vetrenka status | Animated smoke sprites, roadblock tiles, dimmed towns |

When a month closes, changed tiles flip in a short staggered sequence (about
one second) so growth visibly ticks in.

## Removed

The realistic rendering is dropped: the Terrain3D addon, the Poly Haven
textures, the Kenney 3D models, `MapWorld`, the control-map bake, the texture
packer and their tests. These were never pushed. They stay in local git
history only.

## Error handling

- Missing or malformed baked tile data: the map shows "map data unavailable"
  and the game continues; NativeGame never depends on the map.
- Snapshot region ids missing from the geometry are ignored, with a warning.

## Performance

`TileMapLayer` redraws only the cells that change. The month's tile flips
touch at most a few hundred cells. The target is a smooth dashboard at
1280×720 on integrated graphics.

## Testing

- `TileBaker` is deterministic, every kind is in range, and land-cover
  shares stay within bounds.
- `GrowthLayers` are monotonic in population and development, bounded, and
  show trouble only above thresholds.
- Hit testing returns each city's own region.
- The vertical slice's selection, hover and keyboard contracts still hold.
- Applying a snapshot changes tile targets.
- Visual check: screenshots at 1280×720 and 1920×1080, in day and dusk, before
  and after growth and after a crisis.

## Planned later (out of scope now)

- **City panel:** each city gets a clickable city icon that opens a panel. The
  panel shows background art of the city in the map's pixel style, and it
  changes gradually as the city grows, develops and modernizes.
- A DOS restyle of the rest of the interface.
