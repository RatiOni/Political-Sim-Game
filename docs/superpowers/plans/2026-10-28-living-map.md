# The Living Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat dashboard map with a real-looking, Georgia-inspired 3D map of Ardenia built from real assets, driven by a new regional population/development model whose changes the map shows.

**Architecture:** A one-time baker turns the map canon into committed data (heightmap, region-id raster, Terrain3D control map, border polylines). At runtime `ArdeniaMap` hosts a SubViewport with a Terrain3D world seen by an orthographic camera, plus a 2D overlay for gilt borders, labels and selection. Pure `GrowthLayers` functions map each region's simulated population/development/pressure to visual targets that `MapWorld` tweens toward each month.

**Tech Stack:** Godot 4.7.2 GDScript (statically typed), `gl_compatibility` renderer, Terrain3D 1.0.2 (`godot/addons/terrain_3d`), Poly Haven CC0 textures, Kenney CC0 models, the project's own headless test harness (`res://scripts/native/testing/test_support.gd`).

**Spec:** `docs/superpowers/specs/2026-10-28-living-map-design.md`

## Global Constraints

- Godot executable: `/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe`; every test runs as `"$G" --headless --path godot --script res://<path>.gd` and must print `NATIVE TESTS: N passed, 0 failed` with no `SCRIPT ERROR` line.
- Full battery after every task: every `godot/tests/native/test_*.gd`, `godot/tests/ui/test_*.gd` and `godot/scripts/tests/vertical_slice_test.gd` (the slice exits 0). Baseline before this plan: 26 files, 4666 checks.
- Renderer stays `gl_compatibility`.
- No explanatory comments in new code (owner's rule): intent lives in names, constants, small functions and asserts.
- Persistence: every new state field round-trips through `to_dict`/`from_dict`, old saves load with defaults, and `StateValidator` rejects impossible values.
- `ArdeniaMap` keeps its public surface: signal `region_selected(region_id: String)`, `apply_snapshot(values: Array, selection: String)`, `select_region(region_id: String)`, `region_at(position: Vector2) -> String`, `polygons: Dictionary`, `hovered_id: String`.
- Assets only from the verified sources in the spec; `godot/assets/CREDITS.md` lists each with its licence.
- Map canon: inspired by Georgia, never traced; the ceasefire line is inside the national border and never drawn as an international boundary.
- Tests never touch the player's save slot (`godot_slice`).

---

### Task 1: Asset pipeline — packed terrain materials, models, credits

**Files:**
- Create: `godot/tools/pack_terrain_textures.gd`
- Create: `godot/assets/terrain/<material>_albedo_height.png`, `<material>_normal_rough.png` for grass, forest, farmland, rock, snow, sand, road
- Create: `godot/assets/models/towns/` (Kenney low-detail buildings and suburban houses, `.glb`)
- Create: `godot/assets/models/nature/` (Kenney trees and rocks, `.glb`)
- Create: `godot/assets/models/props/` (Kenney construction barrier, fence)
- Create: `godot/assets/CREDITS.md`
- Test: `godot/tests/map/test_assets.gd`

**Interfaces:**
- Produces: `MapAssets.MATERIALS: Array[String] = ["grass", "forest", "farmland", "rock", "snow", "sand", "road"]` (index = Terrain3D texture id), `MapAssets.texture_paths(material: String) -> Dictionary` with keys `albedo_height`, `normal_rough`, `MapAssets.TOWN_MODELS: Array[String]`, `MapAssets.TREE_MODELS: Array[String]`, `MapAssets.CHECKPOINT_MODEL: String` — in `godot/scripts/map/map_assets.gd`.

- [ ] **Step 1: Write the failing test** — `godot/tests/map/test_assets.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	var t = TestSupportScript.new()
	t.equal(MapAssets.MATERIALS.size(), 7, "seven terrain materials")
	for material in MapAssets.MATERIALS:
		var paths := MapAssets.texture_paths(material)
		for key in ["albedo_height", "normal_rough"]:
			t.truth(ResourceLoader.exists(paths[key]), "%s %s exists" % [material, key])
			var tex: Texture2D = load(paths[key])
			t.truth(tex != null and tex.get_width() == 1024, "%s %s is a 1K texture" % [material, key])
			t.truth(tex != null and tex.get_image().detect_alpha() != Image.ALPHA_NONE, "%s %s carries its packed alpha channel" % [material, key])
	for path in MapAssets.TOWN_MODELS + MapAssets.TREE_MODELS + [MapAssets.CHECKPOINT_MODEL]:
		t.truth(ResourceLoader.exists(path), "model %s exists" % path)
	t.truth(MapAssets.TOWN_MODELS.size() >= 10, "enough building variety for a town")
	t.truth(MapAssets.TREE_MODELS.size() >= 4, "enough tree variety for a forest")
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for needle in ["Poly Haven", "CC0", "Kenney", "Terrain3D", "MIT"]:
		t.truth(credits.contains(needle), "credits name %s" % needle)
	quit(t.finish())
```

- [ ] **Step 2: Run it — expect a parse error: `MapAssets` not declared.**

Run: `"$G" --headless --path godot --script res://tests/map/test_assets.gd`

- [ ] **Step 3: Write the packer** — `godot/tools/pack_terrain_textures.gd` (run once; reads the raw Poly Haven download, writes packed 1K PNGs):

```gdscript
extends SceneTree

const SOURCE := "D:/Political Sim Game/.worktrees/godot-native-sim/.scratch/downloads/polyhaven"
const TARGET := "res://assets/terrain"
const SIZE := 1024
const MATERIALS := ["grass", "forest", "farmland", "rock", "snow", "sand", "road"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TARGET)
	for material in MATERIALS:
		_write(material, "albedo_height", _pack(_load(material, "albedo"), _load(material, "height")))
		_write(material, "normal_rough", _pack(_load(material, "normal"), _load(material, "roughness")))
	quit(0)


func _load(material: String, map: String) -> Image:
	for ext in ["png", "jpg"]:
		var path := "%s/%s/%s.%s" % [SOURCE, material, map, ext]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			img.convert(Image.FORMAT_RGBA8)
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			return img
	push_error("missing %s %s" % [material, map])
	return Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)


func _pack(rgb: Image, alpha_source: Image) -> Image:
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var c := rgb.get_pixel(x, y)
			c.a = alpha_source.get_pixel(x, y).r
			out.set_pixel(x, y, c)
	return out


func _write(material: String, kind: String, img: Image) -> void:
	img.save_png("%s/%s_%s.png" % [TARGET, material, kind])
```

Run: `"$G" --headless --path godot --script res://tools/pack_terrain_textures.gd`, then `"$G" --headless --path godot --import`.

- [ ] **Step 4: Copy the models** from `.scratch/downloads/kenney/x/`:
  - towns: `city-kit-commercial/.../low-detail-building-a..n.glb`, `low-detail-building-wide-a.glb`, `city-kit-suburban/.../building-type-a..k.glb`
  - nature: `nature-kit/.../tree_default.glb`, `tree_oak.glb`, `tree_pineDefaultA.glb`, `tree_pineTallA.glb`, `tree_cone.glb`, `rock_largeA.glb`
  - props: `city-kit-roads/.../construction-barrier.glb`, `city-kit-suburban/.../fence.glb`
  Keep each pack's `License.txt` beside its models.

- [ ] **Step 5: Write `godot/scripts/map/map_assets.gd`:**

```gdscript
class_name MapAssets
extends RefCounted

const MATERIALS: Array[String] = ["grass", "forest", "farmland", "rock", "snow", "sand", "road"]
const TOWN_MODELS: Array[String] = [
	"res://assets/models/towns/low-detail-building-a.glb", "res://assets/models/towns/low-detail-building-b.glb",
	"res://assets/models/towns/low-detail-building-c.glb", "res://assets/models/towns/low-detail-building-d.glb",
	"res://assets/models/towns/low-detail-building-e.glb", "res://assets/models/towns/low-detail-building-f.glb",
	"res://assets/models/towns/low-detail-building-wide-a.glb", "res://assets/models/towns/building-type-a.glb",
	"res://assets/models/towns/building-type-b.glb", "res://assets/models/towns/building-type-c.glb",
	"res://assets/models/towns/building-type-d.glb", "res://assets/models/towns/building-type-e.glb",
]
const TREE_MODELS: Array[String] = [
	"res://assets/models/nature/tree_default.glb", "res://assets/models/nature/tree_oak.glb",
	"res://assets/models/nature/tree_pineDefaultA.glb", "res://assets/models/nature/tree_pineTallA.glb",
	"res://assets/models/nature/tree_cone.glb",
]
const CHECKPOINT_MODEL := "res://assets/models/props/construction-barrier.glb"


static func material_id(material: String) -> int:
	var id := MATERIALS.find(material)
	assert(id >= 0, "unknown terrain material %s" % material)
	return id


static func texture_paths(material: String) -> Dictionary:
	return {
		"albedo_height": "res://assets/terrain/%s_albedo_height.png" % material,
		"normal_rough": "res://assets/terrain/%s_normal_rough.png" % material,
	}
```

- [ ] **Step 6: Write `godot/assets/CREDITS.md`** listing: Terrain3D v1.0.2 (MIT, Cory Petkovsek, Roope Palmroos and contributors, github.com/TokisanGames/Terrain3D); each Poly Haven texture by id with its author(s) from `.scratch/downloads/polyhaven/manifest.json` and "CC0, polyhaven.com"; each Kenney pack by name and version with "CC0, kenney.nl".

- [ ] **Step 7: Run the test — expect PASS.** Then run the full battery.

- [ ] **Step 8: Commit** `feat(godot): packed CC0 terrain materials, Kenney models and credits`.

---

### Task 2: Regional population and development

**Files:**
- Modify: `godot/scripts/native/state/region.gd` (fields, persistence)
- Modify: `godot/scripts/native/sim/regions_sim.gd` (seeding, monthly growth, feedback, `population_weight`)
- Modify: `godot/scripts/native/sim/households_sim.gd:174`, `godot/scripts/native/sim/ministries_sim.gd:89`, `godot/scripts/native/sim/stability_sim.gd:43` (use live weight)
- Modify: `godot/scripts/native/state/state_validator.gd` (ranges)
- Modify: `godot/scripts/native/native_game.gd` (`_build_snapshot` regions rows gain `population`, `development`)
- Test: `godot/tests/native/test_population_development.gd`

**Interfaces:**
- Produces: `RegionState.population: float` (thousands), `RegionState.development: float` (0..1); `RegionsSim.population_weight(state: GameState, region_id: String) -> float` (share of national population, falls back to the profile's `population_weight` before seeding); snapshot region rows include `"population"` and `"development"`.
- Consumes: `MinistriesSim` delivery (`state.ministries[portfolio].delivery`), `state.regional_programs`, `state.country.economy.growth_rate`, `state.insurgency_pressure`, `state.civil_war`.

- [ ] **Step 1: Write the failing test** — `godot/tests/native/test_population_development.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242})
	BudgetSim.ensure_budget_state(state)
	return state


static func _national(state: GameState) -> float:
	var total := 0.0
	for r in state.regions.values():
		total += (r as RegionState).population
	return total


func _initialize() -> void:
	var t = TestSupportScript.new()

	var s := _state()
	t.near(_national(s), 8500.0, 1.0, "regions are seeded with Ardenia's 8.5 million people")
	t.near(RegionsSim.population_weight(s, "vashtera"), 0.22, 0.001, "seeded shares match the authored weights")
	for r in s.regions.values():
		t.truth((r as RegionState).development > 0.0 and (r as RegionState).development < 1.0, "%s starts partly developed" % (r as RegionState).id)
	t.truth((s.regions["vashtera"] as RegionState).development > (s.regions["anera"] as RegionState).development,
		"the capital starts more developed than the absent-state highlands")

	var natural := _state()
	var n0 := _national(natural)
	for _i in range(12):
		RegionsSim.simulate(natural)
	t.truth(_national(natural) > n0, "the country grows by natural increase")
	t.near(_national(natural), n0 * (1.0 + RegionsSim.NATURAL_GROWTH_PER_YEAR), n0 * 0.002,
		"and only by natural increase: migration moves people, it does not create them")

	var move := _state()
	(move.regions["zavost"] as RegionState).unemployment = 0.30
	(move.regions["sela"] as RegionState).unemployment = 0.04
	var z0 := RegionsSim.population_weight(move, "zavost")
	var se0 := RegionsSim.population_weight(move, "sela")
	for _i in range(24):
		RegionsSim.simulate(move)
		(move.regions["zavost"] as RegionState).unemployment = 0.30
		(move.regions["sela"] as RegionState).unemployment = 0.04
	t.truth(RegionsSim.population_weight(move, "zavost") < z0, "people leave a region without work")
	t.truth(RegionsSim.population_weight(move, "sela") > se0, "and move to one with jobs")

	var served := _state()
	var neglected := _state()
	for m in neglected.ministries.values():
		(m as MinistryState).delivery = 0.2
	for _i in range(60):
		RegionsSim.simulate(served)
		RegionsSim.simulate(neglected)
		for m in neglected.ministries.values():
			(m as MinistryState).delivery = 0.2
	t.truth((served.regions["sela"] as RegionState).development > (neglected.regions["sela"] as RegionState).development,
		"a state that delivers develops its regions; a failing one does not")

	var war := _state()
	var d0 := (war.regions["orvena"] as RegionState).development
	war.civil_war = true
	war.insurgency_pressure = 0.9
	for _i in range(36):
		RegionsSim.simulate(war)
	t.truth((war.regions["orvena"] as RegionState).development < d0, "war undoes development")

	var held := _state()
	var v0 := RegionsSim.population_weight(held, "vetrenka")
	(held.regions["vetrenka"] as RegionState).unemployment = 0.02
	for _i in range(24):
		RegionsSim.simulate(held)
		(held.regions["vetrenka"] as RegionState).unemployment = 0.02
	t.truth(RegionsSim.population_weight(held, "vetrenka") <= v0 + 1e-6, "nobody migrates across the ceasefire line toward opportunity")

	var feedback := _state()
	var reach0 := (feedback.regions["darev"] as RegionState).state_reach
	(feedback.regions["darev"] as RegionState).development = 0.95
	for _i in range(24):
		RegionsSim.simulate(feedback)
		(feedback.regions["darev"] as RegionState).development = 0.95
	var plain := _state()
	for _i in range(24):
		RegionsSim.simulate(plain)
	t.truth((feedback.regions["darev"] as RegionState).state_reach > (plain.regions["darev"] as RegionState).state_reach,
		"a developed region is easier for the state to reach")

	var long := _state()
	var ok := true
	for _i in range(480):
		RegionsSim.simulate(long)
		for r in long.regions.values():
			var region := r as RegionState
			if not is_finite(region.population) or region.population <= 0.0 or region.development < 0.0 or region.development > 1.0:
				ok = false
	t.truth(ok, "forty years keep population positive and development within 0..1")

	var saved := _state()
	(saved.regions["kelvet"] as RegionState).population = 612.5
	(saved.regions["kelvet"] as RegionState).development = 0.41
	var copy := GameState.from_dict(saved.to_dict())
	t.near((copy.regions["kelvet"] as RegionState).population, 612.5, 1e-9, "population round-trips")
	t.near((copy.regions["kelvet"] as RegionState).development, 0.41, 1e-9, "development round-trips")
	(saved.regions["kelvet"] as RegionState).development = 1.4
	t.truth(StateValidator.validate(saved).size() > 0, "an impossible development level is rejected")

	var game = load("res://scripts/native/native_game.gd").new()
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 7})
	var row: Dictionary = game.snapshot()["regions"][0]
	t.truth(row.has("population") and row.has("development"), "the snapshot carries population and development for the map")
	game.free()
	quit(t.finish())
```

- [ ] **Step 2: Run it — expect failures (`population` not a member).**

- [ ] **Step 3: Add the fields to `RegionState`:** `var population: float = 0.0` and `var development: float = 0.0`; in `to_dict()` add `"population": population, "development": development`; in `from_dict()` add `r.population = float(data.get("population", 0.0))` and `r.development = float(data.get("development", 0.0))`.

- [ ] **Step 4: Implement in `RegionsSim`:**

```gdscript
const NATURAL_GROWTH_PER_YEAR := 0.004
const MIGRATION_SHARE_PER_MONTH := 0.002
const DEVELOPMENT_CONVERGENCE := 0.015
const DEVELOPMENT_REACH_BONUS := 0.10
const SEPARATIST_DEVELOPMENT_CEILING := 0.25


static func population_weight(state: GameState, region_id: String) -> float:
	var total := 0.0
	for r in state.regions.values():
		total += (r as RegionState).population
	var region: RegionState = state.regions.get(region_id)
	if total <= 0.0 or region == null or region.population <= 0.0:
		return float(_region_profiles().get(region_id, {}).get("population_weight", 0.0))
	return region.population / total


static func _seed_growth_state(state: GameState, region: RegionState, profile: Dictionary) -> void:
	if region.population <= 0.0:
		region.population = float(profile.get("population_weight", 0.0)) * float(state.country.population) / 1000.0
	if region.development <= 0.0:
		region.development = clampf(0.15 + region.state_reach * 0.55 - region.unemployment * 0.8, 0.05, 0.9)


static func _attractiveness(region: RegionState) -> float:
	return (1.0 - region.unemployment * 3.0) + region.state_reach * 0.5 - region.pressure * 0.6


static func _update_population(state: GameState) -> void:
	var monthly_natural := pow(1.0 + NATURAL_GROWTH_PER_YEAR, 1.0 / 12.0) - 1.0
	var open: Array[RegionState] = []
	var mean := 0.0
	for r in state.regions.values():
		var region := r as RegionState
		region.population *= 1.0 + monthly_natural
		if region.control != "separatist":
			open.append(region)
			mean += _attractiveness(region)
	if open.size() < 2:
		return
	mean /= open.size()
	var flows := {}
	var net := 0.0
	for region in open:
		var flow := region.population * MIGRATION_SHARE_PER_MONTH * (_attractiveness(region) - mean)
		flows[region] = flow
		net += flow
	for region in open:
		region.population = maxf(1.0, region.population + float(flows[region]) - net / open.size())


static func _development_target(state: GameState, region: RegionState, region_id: String, profile: Dictionary) -> float:
	var portfolio := String(profile.get("development_portfolio", "Economy"))
	var ministry: MinistryState = state.ministries.get(portfolio)
	var delivery := 1.0 if ministry == null else ministry.delivery
	var programme := 0.15 if state.regional_programs.any(func(p): return p.region_id == region_id) else 0.0
	var growth := clampf(state.country.economy.growth_rate * 4.0, -0.2, 0.2)
	var crisis := (0.35 if state.civil_war else 0.0) + state.insurgency_pressure * 0.25 + region.pressure * 0.2
	var target := 0.2 + delivery * 0.35 + region.state_reach * 0.25 + programme + growth - crisis
	if region.control == "separatist":
		target = minf(target, SEPARATIST_DEVELOPMENT_CEILING)
	return clampf(target, 0.02, 0.98)
```

In `simulate()`: after `ensure_region_states(state)` call `_seed_growth_state(state, region, profile)` for each region inside the loop before `_tick_region`; after the region loop and `_advance_programs`, call `_update_population(state)`, then for each region `region.development += (_development_target(...) - region.development) * DEVELOPMENT_CONVERGENCE`. In `_tick_region`, add `+ (region.development - 0.5) * DEVELOPMENT_REACH_BONUS` to `reach_target` before its clamp.

- [ ] **Step 5: Replace the three authored-weight readers** with `RegionsSim.population_weight(state, region_id)`: `households_sim.gd:174` (`float(profiles.get(h.region_id, {}).get("population_weight", 0.0))` → `RegionsSim.population_weight(state, h.region_id)`), `ministries_sim.gd:89` and `stability_sim.gd:43` (`float((profile as Dictionary).get("population_weight", 1.0))` → `RegionsSim.population_weight(state, String(key))`).

- [ ] **Step 6: Validator:** in the region validation loop add, for each region, `population` finite and ≥ 0, `development` finite and within 0..1, with messages `"region '%s' population out of range"` / `"region '%s' development out of range"`.

- [ ] **Step 7: Snapshot:** in `NativeGame._build_snapshot`, each region row gains `"population": region.population, "development": region.development`.

- [ ] **Step 8: Run the test — expect PASS; run the full battery.** Tests that pinned regional weights through households/stability may shift by tiny amounts at month one only if seeding changes the weights; seeding reproduces the authored shares exactly, so none should. If a test fails, report the exact assertion before changing anything.

- [ ] **Step 9: Run `godot/tests/native/balance_probe.gd`** and record the five policies' approval/stability; the order must still be: steady and trim best; no budget, austerity and max spend clearly worse.

- [ ] **Step 10: Commit** `feat(godot): regional population and development`.

---

### Task 3: Map geometry — the world definition and one canonical transform

**Files:**
- Create: `godot/data/map/ardenia_world.json`
- Create: `godot/scripts/map/map_geometry.gd`
- Test: `godot/tests/map/test_map_geometry.gd`

**Interfaces:**
- Produces: `MapGeometry.load_world() -> MapGeometry` (null on malformed data, with `push_error`), properties `extent_m: Vector2` (world size in metres, x east, y south), `region_ids: Array[String]`, `seeds: Dictionary` (id → Vector2 map coords 0..1), `cities: Array[Dictionary]` (`{name, region, point: Vector2, capital: bool}`), `routes: Array[Dictionary]` (`{kind: "rail"|"road"|"pipeline", points: PackedVector2Array}`), `ceasefire: PackedVector2Array`; methods `map_to_world(p: Vector2) -> Vector3`, `world_to_map(w: Vector3) -> Vector2`.

`ardenia_world.json` content (map coordinates 0..1, x west→east, y north→south):

```json
{
  "extent_m": [16800, 10000],
  "regions": {
    "vetrenka": [0.13, 0.30], "anera": [0.27, 0.27], "karsen": [0.47, 0.24],
    "orvena": [0.25, 0.50], "vashtera": [0.56, 0.45], "kelvet": [0.17, 0.72],
    "sela": [0.42, 0.66], "zavost": [0.76, 0.36], "darev": [0.83, 0.55]
  },
  "cities": [
    {"name": "Vashtera", "region": "vashtera", "point": [0.585, 0.475], "capital": true},
    {"name": "Tavri", "region": "kelvet", "point": [0.19, 0.83], "capital": false},
    {"name": "Duvinsk", "region": "zavost", "point": [0.74, 0.40], "capital": false},
    {"name": "Selvara", "region": "orvena", "point": [0.27, 0.53], "capital": false},
    {"name": "Karsen", "region": "karsen", "point": [0.48, 0.28], "capital": false},
    {"name": "Anera", "region": "anera", "point": [0.29, 0.31], "capital": false},
    {"name": "Darev", "region": "darev", "point": [0.85, 0.58], "capital": false},
    {"name": "Sela", "region": "sela", "point": [0.42, 0.68], "capital": false},
    {"name": "Vetrenka", "region": "vetrenka", "point": [0.12, 0.33], "capital": false}
  ],
  "routes": [
    {"kind": "rail", "points": [[0.585, 0.475], [0.66, 0.43], [0.74, 0.40]]},
    {"kind": "road", "points": [[0.585, 0.475], [0.50, 0.58], [0.42, 0.68], [0.30, 0.78], [0.19, 0.83]]},
    {"kind": "rail", "points": [[0.585, 0.475], [0.50, 0.60], [0.35, 0.74], [0.19, 0.83]]},
    {"kind": "pipeline", "points": [[0.98, 0.45], [0.85, 0.58], [0.74, 0.40], [0.585, 0.475]]},
    {"kind": "road", "points": [[0.585, 0.475], [0.48, 0.28]]},
    {"kind": "road", "points": [[0.27, 0.53], [0.585, 0.475]]},
    {"kind": "road", "points": [[0.29, 0.31], [0.27, 0.53]]}
  ],
  "ceasefire": [[0.20, 0.17], [0.21, 0.24], [0.19, 0.31], [0.21, 0.37], [0.18, 0.44]],
  "kesla": [[0.50, 0.24], [0.54, 0.33], [0.585, 0.475], [0.50, 0.60], [0.42, 0.68], [0.30, 0.78], [0.19, 0.84], [0.15, 0.87]]
}
```

- [ ] **Step 1: Write the failing test** — `godot/tests/map/test_map_geometry.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SIM_REGIONS := ["vashtera", "zavost", "sela", "anera", "kelvet", "vetrenka", "karsen", "orvena", "darev"]


func _initialize() -> void:
	var t = TestSupportScript.new()
	var geo := MapGeometry.load_world()
	t.truth(geo != null, "the world definition loads")
	if geo == null:
		quit(t.finish())
		return
	var ids := geo.region_ids.duplicate()
	ids.sort()
	var expected := SIM_REGIONS.duplicate()
	expected.sort()
	t.equal(ids, expected, "the map defines exactly the nine simulated regions")
	t.truth(geo.extent_m.x > geo.extent_m.y * 1.5, "Ardenia is broad east-west and compressed north-south")
	for p in [Vector2(0, 0), Vector2(1, 1), Vector2(0.3, 0.7)]:
		t.truth(geo.world_to_map(geo.map_to_world(p)).distance_to(p) < 1e-6, "map and world coordinates invert exactly (%s)" % p)
	t.equal(geo.cities.filter(func(c): return c["capital"]).size(), 1, "exactly one capital")
	t.truth(geo.routes.any(func(r): return r["kind"] == "pipeline"), "the Zovar line is on the map")
	t.truth(geo.ceasefire.size() >= 3, "the ceasefire line has a course")
	for c in geo.cities:
		t.truth(String(c["region"]) in SIM_REGIONS, "%s belongs to a real region" % c["name"])
	quit(t.finish())
```

- [ ] **Step 2: Run it — expect a parse error (`MapGeometry` not declared).**

- [ ] **Step 3: Write `godot/data/map/ardenia_world.json`** with the content above, and `godot/scripts/map/map_geometry.gd`:

```gdscript
class_name MapGeometry
extends RefCounted

const WORLD_PATH := "res://data/map/ardenia_world.json"

var extent_m := Vector2.ZERO
var region_ids: Array[String] = []
var seeds: Dictionary = {}
var cities: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var ceasefire := PackedVector2Array()
var kesla := PackedVector2Array()


static func load_world(path: String = WORLD_PATH) -> MapGeometry:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("MapGeometry: %s is not a JSON object" % path)
		return null
	var data: Dictionary = parsed
	for key in ["extent_m", "regions", "cities", "routes", "ceasefire", "kesla"]:
		if not data.has(key):
			push_error("MapGeometry: %s is missing '%s'" % [path, key])
			return null
	var geo := MapGeometry.new()
	geo.extent_m = Vector2(float(data["extent_m"][0]), float(data["extent_m"][1]))
	for id in data["regions"]:
		geo.region_ids.append(String(id))
		geo.seeds[String(id)] = _vec(data["regions"][id])
	for c in data["cities"]:
		geo.cities.append({"name": String(c["name"]), "region": String(c["region"]),
			"point": _vec(c["point"]), "capital": bool(c.get("capital", false))})
	for r in data["routes"]:
		geo.routes.append({"kind": String(r["kind"]), "points": _line(r["points"])})
	geo.ceasefire = _line(data["ceasefire"])
	geo.kesla = _line(data["kesla"])
	return geo


func map_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - 0.5) * extent_m.x, 0.0, (p.y - 0.5) * extent_m.y)


func world_to_map(w: Vector3) -> Vector2:
	return Vector2(w.x / extent_m.x + 0.5, w.z / extent_m.y + 0.5)


static func _vec(v: Array) -> Vector2:
	return Vector2(float(v[0]), float(v[1]))


static func _line(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_vec(p))
	return out
```

- [ ] **Step 4: Run the test — expect PASS; full battery.**

- [ ] **Step 5: Commit** `feat(godot): map world definition and canonical transform`.

---

### Task 4: The baker — heightmap, region raster, control map, borders

**Files:**
- Create: `godot/scripts/map/map_baker.gd` (`class_name MapBaker`, pure functions on `Image`s)
- Create: `godot/tools/bake_map.gd` (writes the baked files)
- Create: `godot/data/map/baked/height.exr`, `region_ids.png`, `control.exr`, `borders.json`
- Test: `godot/tests/map/test_map_baker.gd`

**Interfaces:**
- Consumes: `MapGeometry` (Task 3), `MapAssets.material_id()` (Task 1).
- Produces:
  - `MapBaker.RESOLUTION := Vector2i(1344, 800)`, `MapBaker.MAX_HEIGHT_M := 1800.0`, `MapBaker.SEA_REGION := 255`, `MapBaker.FOREIGN_REGION := 254`
  - `MapBaker.bake_height(geo: MapGeometry) -> Image` (FORMAT_RF, metres; sea ≤ 0)
  - `MapBaker.bake_regions(geo: MapGeometry, height: Image) -> Image` (FORMAT_R8: region index in `geo.region_ids` order, 254 foreign land, 255 sea)
  - `MapBaker.bake_control(height: Image, regions: Image, geo: MapGeometry) -> Image` (Terrain3D control map)
  - `MapBaker.trace_borders(regions: Image, geo: MapGeometry) -> Dictionary` (`{"national": [PackedVector2Array…], "internal": […], "ceasefire": […]}` in map coords, smoothed)
  - `MapBaker.region_at_map(regions: Image, geo: MapGeometry, p: Vector2) -> String` ("" for sea/foreign)

- [ ] **Step 1: Confirm the Terrain3D control-map encoding** before writing `bake_control`: in a throwaway script, create a `Terrain3D`, import a height image, call `terrain.data.set_control_base_id(Vector3(0,0,0), 3)` and read back `terrain.data.get_control(Vector3(0,0,0))`, and print `Terrain3DUtil.enc_base(3)`, `Terrain3DUtil.enc_overlay(5)`, `Terrain3DUtil.enc_blend(128)`, `Terrain3DUtil.as_float(Terrain3DUtil.enc_base(3))`. Use exactly the encoding observed: the control image is FORMAT_RF whose pixels are `Terrain3DUtil.as_float(enc_base(base) | enc_overlay(overlay) | enc_blend(blend))`. Delete the throwaway script.

- [ ] **Step 2: Write the failing test** — `godot/tests/map/test_map_baker.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	var t = TestSupportScript.new()
	var geo := MapGeometry.load_world()
	var height := MapBaker.bake_height(geo)
	t.equal(Vector2i(height.get_width(), height.get_height()), MapBaker.RESOLUTION, "the heightmap is the baked resolution")
	t.equal(MapBaker.bake_height(geo).get_data(), height.get_data(), "baking is deterministic")

	var west_sea := height.get_pixel(5, MapBaker.RESOLUTION.y / 2).r
	t.truth(west_sea <= 0.0, "the far west is sea")
	var ridge := _max_row(height, int(MapBaker.RESOLUTION.y * 0.17))
	var plain := _max_row(height, int(MapBaker.RESOLUTION.y * 0.60))
	t.truth(ridge > plain * 2.0, "the northern wall stands far above the plains (%.0f m vs %.0f m)" % [ridge, plain])
	t.truth(ridge <= MapBaker.MAX_HEIGHT_M, "and never exceeds the height ceiling")

	var regions := MapBaker.bake_regions(geo, height)
	for id in geo.region_ids:
		t.equal(MapBaker.region_at_map(regions, geo, geo.seeds[id]), id, "%s's seed lies inside %s" % [id, id])
	for c in geo.cities:
		t.equal(MapBaker.region_at_map(regions, geo, c["point"]), c["region"], "%s lies in %s" % [c["name"], c["region"]])
	t.equal(MapBaker.region_at_map(regions, geo, Vector2(0.01, 0.5)), "", "the sea belongs to no region")
	for id in geo.region_ids:
		t.truth(_is_contiguous(regions, geo.region_ids.find(id)), "%s is one connected territory" % id)

	var control := MapBaker.bake_control(height, regions, geo)
	t.equal(Vector2i(control.get_width(), control.get_height()), MapBaker.RESOLUTION, "the control map matches the heightmap")
	t.equal(MapBaker.base_material_at(control, _highest(height)), MapAssets.material_id("snow"), "the highest peak is snow")
	t.equal(MapBaker.base_material_at(control, Vector2i(int(0.42 * MapBaker.RESOLUTION.x), int(0.66 * MapBaker.RESOLUTION.y))) in
		[MapAssets.material_id("grass"), MapAssets.material_id("farmland")], true, "the central plain is grassland or farmland")

	var borders := MapBaker.trace_borders(regions, geo)
	t.truth(borders["national"].size() >= 1, "the national border is traced")
	t.truth(borders["internal"].size() >= 8, "every internal border is traced")
	t.truth(borders["ceasefire"].size() >= 1, "the ceasefire line is traced separately from ordinary borders")
	var line: PackedVector2Array = borders["national"][0]
	t.truth(line[0].distance_to(line[line.size() - 1]) < 0.01, "the national border closes on itself")
	t.truth(_max_turn(line) < deg_to_rad(80.0), "borders are smooth curves, not pixel staircases")
	quit(t.finish())


static func _max_row(img: Image, y: int) -> float:
	var best := -INF
	for x in img.get_width():
		best = maxf(best, img.get_pixel(x, y).r)
	return best


static func _highest(img: Image) -> Vector2i:
	var best := Vector2i.ZERO
	var h := -INF
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r > h:
				h = img.get_pixel(x, y).r
				best = Vector2i(x, y)
	return best


static func _is_contiguous(img: Image, index: int) -> bool:
	var start := Vector2i(-1, -1)
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			if int(round(img.get_pixel(x, y).r * 255.0)) == index:
				count += 1
				if start.x < 0:
					start = Vector2i(x, y)
	if count == 0:
		return false
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height() or seen.has(q):
				continue
			if int(round(img.get_pixel(q.x, q.y).r * 255.0)) == index:
				seen[q] = true
				stack.append(q)
	return seen.size() == count


static func _max_turn(line: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(1, line.size() - 1):
		var a := (line[i] - line[i - 1]).normalized()
		var b := (line[i + 1] - line[i]).normalized()
		worst = maxf(worst, a.angle_to(b) if a != Vector2.ZERO and b != Vector2.ZERO else 0.0)
	return absf(worst)
```

- [ ] **Step 3: Run it — expect a parse error (`MapBaker` not declared).**

- [ ] **Step 4: Implement `godot/scripts/map/map_baker.gd`:**

```gdscript
class_name MapBaker
extends RefCounted

const RESOLUTION := Vector2i(1344, 800)
const MAX_HEIGHT_M := 1800.0
const SEA_REGION := 255
const FOREIGN_REGION := 254
const SEED := 1993
const BORDER_SMOOTHING_PASSES := 4
const SNOW_LINE := 0.78
const ROCK_SLOPE := 0.9
const FOREST_BAND := Vector2(0.28, 0.62)


static func _noise(frequency: float, octaves: int, seed_offset: int, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = SEED + seed_offset
	n.noise_type = type
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


static func northern_edge(u: float) -> float:
	return 0.13 + 0.04 * sin(u * 6.0) + 0.03 * sin(u * 13.0 + 1.3) + 0.04 * u


static func southern_edge(u: float) -> float:
	return (0.86 + 0.03 * sin(u * 9.0) if u < 0.55 else 0.86 - (u - 0.55) * 0.42) + 0.02 * sin(u * 23.0 + 2.0)


static func coastline(v: float) -> float:
	return 0.07 + (v - 0.15) * 0.16 + 0.025 * sin(v * 17.0)


static func eastern_edge(v: float) -> float:
	return 0.95 - absf(v - 0.42) * 0.25


static func is_sea(u: float, v: float, warp: float) -> bool:
	return u < coastline(v) + warp


static func is_ardenia(u: float, v: float, warp: float) -> bool:
	return v > northern_edge(u) + warp and v < southern_edge(u) + warp \
		and not is_sea(u, v, warp) and u < eastern_edge(v) + warp


static func bake_height(_geo: MapGeometry) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_RF)
	var ridged := _noise(0.012, 6, 1, FastNoiseLite.TYPE_PERLIN)
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var hills := _noise(0.006, 5, 2)
	var warp := _noise(0.02, 3, 3)
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		for x in RESOLUTION.x:
			var u := float(x) / RESOLUTION.x
			var w := warp.get_noise_2d(x, y) * 0.02
			if is_sea(u, v, w):
				img.set_pixel(x, y, Color(-40.0 - (coastline(v) - u) * 900.0, 0, 0))
				continue
			var crest := exp(-pow((v - northern_edge(u) - 0.01) / 0.075, 2.0))
			var lesser := exp(-pow((v - 0.84) / 0.07, 2.0)) * maxf(0.0, 1.0 - absf(u - 0.33) * 2.4)
			var lowland := exp(-pow(Vector2((u - 0.16) * 1.2, v - 0.55).length() / 0.16, 2.0))
			var plain := exp(-pow(Vector2((u - 0.58) * 0.9, v - 0.55).length() / 0.18, 2.0))
			var r := (ridged.get_noise_2d(x, y) + 1.0) * 0.5
			var h := 0.12 + crest * (0.18 + 0.82 * r) + lesser * 0.35 * r + hills.get_noise_2d(x, y) * 0.08 - lowland * 0.08 - plain * 0.06
			img.set_pixel(x, y, Color(clampf(h, 0.01, 1.0) * MAX_HEIGHT_M, 0, 0))
	return img


static func bake_regions(geo: MapGeometry, height: Image) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_R8)
	var warp_u := _noise(0.004, 3, 11)
	var warp_v := _noise(0.004, 3, 13)
	var warp := _noise(0.02, 3, 3)
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		for x in RESOLUTION.x:
			var u := float(x) / RESOLUTION.x
			var w := warp.get_noise_2d(x, y) * 0.02
			var index := SEA_REGION
			if not is_sea(u, v, w):
				index = FOREIGN_REGION
				if is_ardenia(u, v, w):
					index = _nearest_seed(geo, Vector2(u + warp_u.get_noise_2d(x, y) * 0.08, v + warp_v.get_noise_2d(x, y) * 0.08),
						height.get_pixel(x, y).r)
			img.set_pixel(x, y, Color8(index, 0, 0))
	return img


static func _nearest_seed(geo: MapGeometry, p: Vector2, elevation_m: float) -> int:
	var best := 0
	var best_d := INF
	for i in geo.region_ids.size():
		var s: Vector2 = geo.seeds[geo.region_ids[i]]
		var d := Vector2((p.x - s.x) * 1.25, p.y - s.y).length() * (1.0 + elevation_m / MAX_HEIGHT_M * 0.15)
		if d < best_d:
			best_d = d
			best = i
	return best


static func index_at(regions: Image, pixel: Vector2i) -> int:
	return int(round(regions.get_pixelv(pixel).r * 255.0))


static func region_at_map(regions: Image, geo: MapGeometry, p: Vector2) -> String:
	var px := Vector2i(clampi(int(p.x * RESOLUTION.x), 0, RESOLUTION.x - 1), clampi(int(p.y * RESOLUTION.y), 0, RESOLUTION.y - 1))
	var index := index_at(regions, px)
	return geo.region_ids[index] if index < geo.region_ids.size() else ""


static func encode_control(base: int, overlay: int, blend: int) -> float:
	return Terrain3DUtil.as_float(Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(overlay) | Terrain3DUtil.enc_blend(blend))


static func base_material_at(control: Image, pixel: Vector2i) -> int:
	return Terrain3DUtil.get_base(Terrain3DUtil.as_uint(control.get_pixelv(pixel).r))


static func bake_control(height: Image, regions: Image, geo: MapGeometry) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_RF)
	var moisture := _noise(0.01, 4, 21)
	var fields := _noise(0.06, 2, 31)
	for y in RESOLUTION.y:
		for x in RESOLUTION.x:
			var h := height.get_pixel(x, y).r / MAX_HEIGHT_M
			var slope := _slope(height, x, y)
			var material := "grass"
			if h <= 0.0:
				material = "sand"
			elif h < 0.03:
				material = "sand"
			elif h > SNOW_LINE:
				material = "snow"
			elif slope > ROCK_SLOPE:
				material = "rock"
			elif h > FOREST_BAND.x and h < FOREST_BAND.y and moisture.get_noise_2d(x, y) > -0.1:
				material = "forest"
			elif h < 0.25 and fields.get_noise_2d(x, y) > 0.15:
				material = "farmland"
			img.set_pixel(x, y, Color(encode_control(MapAssets.material_id(material), 0, 0), 0, 0))
	_paint_routes(img, geo)
	return img


static func _slope(height: Image, x: int, y: int) -> float:
	var x1 := mini(x + 1, height.get_width() - 1)
	var y1 := mini(y + 1, height.get_height() - 1)
	var metres_per_pixel := 12.5
	var dx := (height.get_pixel(x1, y).r - height.get_pixel(x, y).r) / metres_per_pixel
	var dy := (height.get_pixel(x, y1).r - height.get_pixel(x, y).r) / metres_per_pixel
	return Vector2(dx, dy).length()


static func _paint_routes(img: Image, geo: MapGeometry) -> void:
	var road := MapAssets.material_id("road")
	for route in geo.routes:
		if route["kind"] == "pipeline":
			continue
		var points: PackedVector2Array = route["points"]
		for i in range(points.size() - 1):
			var a := points[i] * Vector2(RESOLUTION)
			var b := points[i + 1] * Vector2(RESOLUTION)
			for s in range(int(a.distance_to(b)) + 1):
				var p := Vector2i(a.lerp(b, float(s) / maxf(1.0, a.distance_to(b))))
				for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
					var q: Vector2i = p + d
					if q.x < RESOLUTION.x and q.y < RESOLUTION.y:
						var current := Terrain3DUtil.as_uint(img.get_pixelv(q).r)
						img.set_pixelv(q, Color(encode_control(Terrain3DUtil.get_base(current), road, 180), 0, 0))


static func trace_borders(regions: Image, geo: MapGeometry) -> Dictionary:
	var vetrenka := geo.region_ids.find("vetrenka")
	var national: Array = []
	var internal: Array = []
	var ceasefire: Array = []
	var pairs := {}
	for y in RESOLUTION.y - 1:
		for x in RESOLUTION.x - 1:
			var a := index_at(regions, Vector2i(x, y))
			for q in [Vector2i(x + 1, y), Vector2i(x, y + 1)]:
				var b := index_at(regions, q)
				if a == b:
					continue
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not pairs.has(key):
					pairs[key] = PackedVector2Array()
				(pairs[key] as PackedVector2Array).append((Vector2(x, y) + Vector2(q) + Vector2.ONE) * 0.5 / Vector2(RESOLUTION))
	for key in pairs:
		var lines := _chain(pairs[key])
		var inside := key.x < geo.region_ids.size() and key.y < geo.region_ids.size()
		for line in lines:
			var smooth := _smooth(line)
			if not inside:
				if key.x != FOREIGN_REGION or key.y != SEA_REGION:
					national.append(smooth)
			elif key.x == vetrenka or key.y == vetrenka:
				ceasefire.append(smooth)
			else:
				internal.append(smooth)
	national = [_join_national(national)]
	return {"national": national, "internal": internal, "ceasefire": ceasefire}
```

`_chain(points)` orders an unordered set of edge midpoints into polylines by repeatedly walking to the nearest unvisited point within 1.5 pixels (starting a new polyline when none is near), dropping polylines shorter than 6 points. `_smooth(line)` applies `BORDER_SMOOTHING_PASSES` of Chaikin corner cutting (each segment `p,q` → `0.75p+0.25q, 0.25p+0.75q`), keeping the endpoints. `_join_national(lines)` concatenates the national segments into one ring by greedy nearest-endpoint joining and appends the first point at the end so it closes; then it smooths the joined ring once more with `_smooth`. Write all three as static functions in `map_baker.gd` with these exact names.

- [ ] **Step 5: Run the test — expect PASS.** If "is one connected territory" fails for a region, increase that region's seed weight by moving its seed in `ardenia_world.json` toward its city (not by loosening the test).

- [ ] **Step 6: Write `godot/tools/bake_map.gd`** — runs the bakers and writes `res://data/map/baked/height.exr` (`save_exr`, float), `region_ids.png`, `control.exr`, `borders.json` (`{"national": [[[x,y],…]], "internal": […], "ceasefire": […]}`), then quits. Run it once headless and commit the outputs.

- [ ] **Step 7: Full battery; commit** `feat(godot): bake Ardenia's terrain, regions, materials and borders`.

---

### Task 5: The 3D map world

**Files:**
- Create: `godot/scenes/map/map_world.tscn` (root `Node3D` named `MapWorld` with script)
- Create: `godot/scripts/map/map_world.gd`
- Test: `godot/tests/map/test_map_world.gd`

**Interfaces:**
- Consumes: baked files (Task 4), `MapAssets` (Task 1), `MapGeometry` (Task 3).
- Produces: `MapWorld.build(geo: MapGeometry) -> bool` (false + `push_error` if baked data missing), `MapWorld.camera: Camera3D` (orthographic, straight down, `size` = `geo.extent_m.y`), `MapWorld.terrain: Terrain3D`, `MapWorld.set_dusk(on: bool)`, `MapWorld.world_point_at(screen: Vector2, viewport_size: Vector2) -> Vector3`.

- [ ] **Step 1: Failing test** — `godot/tests/map/test_map_world.gd` instantiates `map_world.tscn` under a `SubViewport` (size 1344×800) added to `root`, awaits two frames, calls `build(MapGeometry.load_world())` and asserts: it returns true; `terrain.data.get_region_count() > 0`; `terrain.assets.get_texture_count() == 7`; `camera.projection == Camera3D.PROJECTION_ORTHOGONAL`; the height under the capital (`terrain.data.get_height(geo.map_to_world(capital))`) is above sea level and below the northern ridge height under `Vector2(0.48, 0.16)`; `world_point_at(Vector2(672, 400), Vector2(1344, 800))` maps (via `geo.world_to_map`) to within 0.01 of `Vector2(0.5, 0.5)`; `set_dusk(true)` lowers the sun energy below `set_dusk(false)`'s.

- [ ] **Step 2: Run — expect failure (scene missing).**

- [ ] **Step 3: Implement `map_world.gd`:** create `Terrain3D` in code (as the official demo does: `add_child` then `data.import_images([height, control, null], Vector3(-extent.x/2, 0, -extent.y/2), 0.0, 1.0)` with `vertex_spacing = extent.x / RESOLUTION.x`), set `terrain.assets` to a `Terrain3DAssets` holding one `Terrain3DTextureAsset` per `MapAssets.MATERIALS` (index order) with `albedo_texture`/`normal_texture` from `MapAssets.texture_paths` and `uv_scale = 0.08`; a sea `MeshInstance3D` (PlaneMesh sized to twice the extent at y = −2, `StandardMaterial3D` albedo `Color(0.08, 0.22, 0.32)`, roughness 0.15, metallic 0.3); a `DirectionalLight3D` (day: energy 1.2, rotation (−55°, 25°, 0); dusk: energy 0.35, warm colour `Color(1.0, 0.72, 0.5)`); a `WorldEnvironment` with ambient light and glow enabled; the orthographic `Camera3D` at `(0, 6000, 0)` looking straight down; `terrain.set_camera(camera)`. `world_point_at` uses `camera.project_ray_origin` (orthographic, so the ray is vertical) and returns the point at y = 0.

- [ ] **Step 4: Run — expect PASS. Then a real render:** write a throwaway capture script (non-headless, `--resolution 1344x800`) that builds the world and saves a PNG; look at it. Acceptance: snow on the northern ridge, rock on steep faces, forest bands, farmland/grass plains, sand coast, sea to the west. Delete the capture script.

- [ ] **Step 5: Full battery; commit** `feat(godot): Terrain3D map world with real materials and lighting`.

---

### Task 6: Overlay and integration into ArdeniaMap

**Files:**
- Modify: `godot/scripts/map/ardenia_map.gd` (rebuilt around the viewport + overlay)
- Modify: `godot/scenes/map/ardenia_map.tscn` (adds `SubViewportContainer/SubViewport` with `map_world.tscn`, and an `Overlay` Control)
- Create: `godot/scripts/map/map_overlay.gd`
- Modify: `godot/theme/ardenia_theme.tres` (ArdeniaMap tokens: `gilt`, `gilt_shadow`, `ceasefire`, `label`, `label_halo`, `selection`, `hover`)
- Test: `godot/tests/map/test_map_interaction.gd`; the existing `godot/scripts/tests/vertical_slice_test.gd` must pass unchanged

**Interfaces:**
- Consumes: `MapWorld` (Task 5), `MapBaker.region_at_map` and `borders.json` (Task 4).
- Produces (unchanged public surface): `region_selected`, `apply_snapshot(values, selection)`, `select_region(id)`, `region_at(position) -> String`, `polygons` (id → screen-space `PackedVector2Array` of the region's outline, derived from `borders.json`, recomputed on resize so the vertical slice's polygon/keyboard checks keep working), `hovered_id`.

- [ ] **Step 1: Failing test** — `test_map_interaction.gd` loads `main.tscn` (with `save_slot` set to `"test_map_interaction"`), awaits frames, then for each city in `MapGeometry.load_world().cities` converts its map point to the map control's local coordinates through `ArdeniaMap.map_to_local(p: Vector2) -> Vector2` and asserts `region_at(...) == city.region`; asserts `region_at` of a sea point is ""; simulates a click on Tavri's position and asserts `region_selected` fired with `"kelvet"`; asserts `polygons.size() == 9`; resizes the window to 1280×720 and re-asserts the capital still hit-tests to `"vashtera"`.

- [ ] **Step 2: Run — expect failure (`map_to_local` missing).**

- [ ] **Step 3: Implement.** `map_overlay.gd` draws, in this order, from `borders.json` mapped through the map control's transform: internal borders (2 px gilt `#F0BE6C` at 85% over a 4 px shadow `#140810` at 40%), the national border (3 px gilt over a 6 px shadow), the ceasefire line (dashed `#E63C3C`, 2.5 px, dash 10/6, never gilt), region labels (Georgia-like serif from the theme, uppercase, halo), city dots and names (capital always; others when the region is hovered/selected or the map is at least `ROOMY_LABEL_HEIGHT` tall), hover fill (region polygon at 10% light) and selection (gilt 4 px outline). `ardenia_map.gd` keeps the old public API; `region_at(position)` converts the local position to map coords and calls `MapBaker.region_at_map` on the loaded `region_ids.png`; `map_to_local` is its inverse used by tests and the overlay.

- [ ] **Step 4: Run the new test and the vertical slice — both PASS. Full battery.**

- [ ] **Step 5: Visual check at 1920×1080 and 1280×720** (throwaway capture of `main.tscn`): gilt borders visible over every terrain, labels legible, ceasefire distinct. Delete the capture script.

- [ ] **Step 6: Commit** `feat(godot): gilt overlay and the new map in the dashboard`.

---

### Task 7: Growth layers — towns and lights

**Files:**
- Create: `godot/scripts/map/growth_layers.gd` (`class_name GrowthLayers`, pure)
- Create: `godot/scripts/map/town_layer.gd` (MultiMesh towns + emissive lights)
- Modify: `godot/scripts/map/map_world.gd` (owns `TownLayer`, applies targets)
- Modify: `godot/scripts/map/ardenia_map.gd` (`apply_snapshot` passes rows to `MapWorld.apply_regions`; day/dusk toggle button in the map corner)
- Test: `godot/tests/map/test_growth_layers.gd`

**Interfaces:**
- Produces: `GrowthLayers.targets(row: Dictionary) -> Dictionary` with keys `buildings: int`, `town_radius_m: float`, `light: float` (0..1), `road_tier: int` (0..3), `farmland: float` (0..1), `trouble: float` (0..1); `GrowthLayers.MAX_BUILDINGS_PER_REGION := 320`; `MapWorld.apply_regions(rows: Array, animate: bool)`.

- [ ] **Step 1: Failing test** — `test_growth_layers.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _row(population: float, development: float, pressure := 0.2, control := "state") -> Dictionary:
	return {"id": "sela", "population": population, "development": development, "pressure": pressure, "control": control}


func _initialize() -> void:
	var t = TestSupportScript.new()
	var small := GrowthLayers.targets(_row(300.0, 0.3))
	var big := GrowthLayers.targets(_row(1800.0, 0.3))
	t.truth(big["buildings"] > small["buildings"], "more people, more buildings")
	t.truth(big["town_radius_m"] > small["town_radius_m"], "and the towns spread wider")
	t.truth(big["buildings"] <= GrowthLayers.MAX_BUILDINGS_PER_REGION, "but never beyond the budget")
	var poor := GrowthLayers.targets(_row(900.0, 0.1))
	var rich := GrowthLayers.targets(_row(900.0, 0.9))
	t.truth(rich["light"] > poor["light"], "development lights a region")
	t.truth(rich["road_tier"] > poor["road_tier"], "and builds its roads")
	t.truth(rich["farmland"] > poor["farmland"], "and its fields")
	t.near(GrowthLayers.targets(_row(900.0, 0.5, 0.1))["trouble"], 0.0, 1e-9, "a calm region shows no trouble")
	t.truth(GrowthLayers.targets(_row(900.0, 0.5, 0.9))["trouble"] > 0.5, "a region under heavy pressure shows it")
	var held := GrowthLayers.targets(_row(500.0, 0.6, 0.3, "separatist"))
	t.truth(held["light"] < GrowthLayers.targets(_row(500.0, 0.6, 0.3))["light"], "territory outside the state is darker")
	for key in ["light", "farmland", "trouble"]:
		var v: float = GrowthLayers.targets(_row(99999.0, 9.0, 9.0))[key]
		t.truth(v >= 0.0 and v <= 1.0, "%s stays within 0..1 for absurd input" % key)
	quit(t.finish())
```

- [ ] **Step 2: Run — expect parse error.**

- [ ] **Step 3: Implement `GrowthLayers`:**

```gdscript
class_name GrowthLayers
extends RefCounted

const MAX_BUILDINGS_PER_REGION := 320
const PEOPLE_PER_BUILDING_K := 6.0
const BASE_TOWN_RADIUS_M := 220.0
const RADIUS_PER_SQRT_K := 14.0
const TROUBLE_PRESSURE_FLOOR := 0.45
const OUTSIDE_STATE_LIGHT := 0.35


static func targets(row: Dictionary) -> Dictionary:
	var population := maxf(0.0, float(row.get("population", 0.0)))
	var development := clampf(float(row.get("development", 0.0)), 0.0, 1.0)
	var pressure := clampf(float(row.get("pressure", 0.0)), 0.0, 1.0)
	var outside := String(row.get("control", "state")) == "separatist"
	var light := clampf(development * 0.8 + minf(population / 2500.0, 0.2), 0.0, 1.0)
	if outside:
		light *= OUTSIDE_STATE_LIGHT
	return {
		"buildings": mini(MAX_BUILDINGS_PER_REGION, int(population / PEOPLE_PER_BUILDING_K * (0.5 + development))),
		"town_radius_m": BASE_TOWN_RADIUS_M + sqrt(population) * RADIUS_PER_SQRT_K,
		"light": light,
		"road_tier": clampi(int(development * 4.0), 0, 3),
		"farmland": clampf(0.15 + development * 0.6, 0.0, 1.0),
		"trouble": clampf((pressure - TROUBLE_PRESSURE_FLOOR) / (1.0 - TROUBLE_PRESSURE_FLOOR), 0.0, 1.0),
	}
```

- [ ] **Step 4: Implement `TownLayer`** (a `Node3D`): one `MultiMeshInstance3D` per entry in `MapAssets.TOWN_MODELS` (mesh = first `MeshInstance3D` found in the instantiated `.glb`), each sized to `MAX_BUILDINGS_PER_REGION * 9 / TOWN_MODELS.size()`; buildings for a region are placed around that region's cities in a deterministic golden-angle spiral (`angle = i * 2.39996`, `r = town_radius_m * sqrt(i / n)`), snapped to `terrain.data.get_height`, skipping sea and slopes over `MapBaker.ROCK_SLOPE`, scaled ×6 so they read at country scale; `visible_instance_count` is the target building count, so growth reveals more of the same spiral rather than reshuffling. Lights: an emissive overlay material on the town instances whose `emission_energy_multiplier = light * dusk_factor` (dusk_factor 1.6 at dusk, 0 by day), plus glow in the environment.

- [ ] **Step 5: `MapWorld.apply_regions(rows, animate)`** computes `GrowthLayers.targets` per row and tweens each layer's values over 3 s (`create_tween()`), or snaps when `animate` is false (first load). `ArdeniaMap.apply_snapshot` calls `apply_regions(values, has_previous_snapshot)`. Add a 44 px "Dusk"/"Day" toggle in the map's top-right that calls `MapWorld.set_dusk`.

- [ ] **Step 6: Run the test — PASS; full battery; visual capture day and dusk, before and after setting a region's population ×2 and development 0.9. Commit** `feat(godot): towns grow and light up with their regions`.

---

### Task 8: Growth layers — roads, fields and signs of trouble

**Files:**
- Create: `godot/scripts/map/land_layer.gd` (roads and fields via Terrain3D control-map overlay updates)
- Create: `godot/scripts/map/trouble_layer.gd` (smoke, checkpoints, dimming)
- Modify: `godot/scripts/map/map_world.gd`
- Test: extend `godot/tests/map/test_map_world.gd`

**Interfaces:**
- Consumes: `GrowthLayers.targets` (Task 7), `MapBaker.encode_control` / `base_material_at` (Task 4), `MapAssets.CHECKPOINT_MODEL`.
- Produces: `LandLayer.apply(region_id: String, road_tier: int, farmland: float)`, `TroubleLayer.apply(region_id: String, trouble: float)`, `TroubleLayer.smoke_count(region_id) -> int`, `TroubleLayer.has_checkpoints() -> bool`.

- [ ] **Step 1: Extend the failing test:** after `build`, call `world.apply_regions([{id "zavost", population 1200, development 0.2, pressure 0.9, control "state"}], false)` and assert `world.trouble.smoke_count("zavost") > 0`; then pressure 0.1 → `smoke_count == 0`; assert `world.trouble.has_checkpoints()` while `vetrenka` control is `"separatist"` and false after it becomes `"autonomous"`; assert that `road_tier` 3 vs 0 for `sela` changes the number of control-map pixels whose overlay is the road material within Sela by more than 20%; assert farmland 0.9 vs 0.1 changes Sela's farmland pixel share by more than 15 points.

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement.** `LandLayer` keeps the baked control map as the base and rewrites only overlay/blend inside each region: roads widen by `road_tier` pixels along `geo.routes` inside the region and new branch links from each non-capital city to its nearest route appear at `road_tier >= 2`; fields convert grass pixels within `town_radius_m * 3` of the region's towns to farmland in a stable noise order until the share matches `farmland`, with fallow tint (overlay `road` at blend 60) when development falls. After edits, call `terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL)`. `TroubleLayer`: one `GPUParticles3D` smoke plume (grey quad particles, 40 particles, lifetime 6 s, rising 300 m) per town at the region's three largest towns, emitting `round(trouble * 3)` plumes; town light multiplier × (1 − 0.7·trouble); checkpoint barriers (`CHECKPOINT_MODEL`, ×8 scale) every 400 m along `geo.ceasefire` while Vetrenka's control is `"separatist"`.

- [ ] **Step 4: Run — PASS; full battery; visual capture of a crisis region and of Vetrenka before/after settlement. Commit** `feat(godot): roads, fields and signs of trouble on the map`.

---

### Task 9: Resilience, performance and documentation

**Files:**
- Modify: `godot/scripts/map/ardenia_map.gd` (fallback image path, error state, frame cap)
- Create: `godot/data/map/baked/fallback.png` (rendered once by a tool)
- Create: `godot/tools/render_fallback.gd`
- Modify: `CLAUDE.md` (Godot map section), `docs/godot/LIVING_WORLD.md` (map status)
- Test: `godot/tests/map/test_map_resilience.gd`

**Interfaces:**
- Produces: `ArdeniaMap.mode: String` (`"terrain"`, `"fallback"`, `"unavailable"`).

- [ ] **Step 1: Failing test:** load `ArdeniaMap` with `MapGeometry.WORLD_PATH` pointed at a missing file (via an exported `world_path` property) and assert `mode == "unavailable"` and that `apply_snapshot` and `region_at` do not error; force the terrain path off (`use_terrain = false`) and assert `mode == "fallback"` and city hit tests still pass; with terrain on, assert the SubViewport's `render_target_update_mode` drops to `UPDATE_WHEN_VISIBLE` with `Engine.max_fps`-independent throttling: after `apply_regions(..., false)` and 2 s with no animation, the viewport stops re-rendering (`render_target_update_mode == SubViewport.UPDATE_DISABLED` until the next change).

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement** the three modes, `render_fallback.gd` (renders the day map at 2688×1600 once and saves `fallback.png`), the update-mode throttle (re-render on snapshot change, hover, selection, resize, and for the duration of tweens), and the docs.

- [ ] **Step 4: Performance check:** run the game windowed at 1280×720, play 24 months at speed 5, and record frame time with `Performance.get_monitor(Performance.TIME_PROCESS)` printed each second by a throwaway script; target under 16 ms per frame on this machine. Record the result in `docs/godot/LIVING_WORLD.md`.

- [ ] **Step 5: Full battery; final visual screenshots (1920×1080 and 1280×720, day and dusk); commit** `feat(godot): map fallback, throttled rendering and docs`.

---

## Self-review

- Spec coverage: assets (T1), population/development (T2), geometry (T3), baker incl. Georgia-inspired terrain, natural borders, materials (T4), 3D world and lighting (T5), gilt borders/ceasefire/labels/hit testing (T6), towns and lights (T7), roads, fields, trouble incl. Vetrenka checkpoints and tweening (T7–T8), error handling, fallback, performance budget, docs (T9). Out-of-scope items are not planned.
- Names are consistent across tasks: `MapAssets.material_id`, `MapGeometry.load_world/map_to_world/world_to_map`, `MapBaker.RESOLUTION/region_at_map/encode_control/base_material_at`, `MapWorld.build/apply_regions/set_dusk/world_point_at`, `GrowthLayers.targets/MAX_BUILDINGS_PER_REGION`, `ArdeniaMap.map_to_local`.
- The one external API not yet observed — Terrain3D's control-map encoding — is confirmed in Task 4 Step 1 before any code depends on it.
