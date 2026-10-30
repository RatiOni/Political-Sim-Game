extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SIM_REGIONS := ["vashtera", "zavost", "sela", "anera", "kelvet", "vetrenka", "karsen", "orvena", "darev", "kostrel"]


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
	t.equal(ids, expected, "the map defines exactly the ten simulated regions")
	t.truth(geo.extent_m.x > geo.extent_m.y * 1.5, "Ardenia is broad east-west and compressed north-south")
	for p in [Vector2(0, 0), Vector2(1, 1), Vector2(0.3, 0.7)]:
		t.truth(geo.world_to_map(geo.map_to_world(p)).distance_to(p) < 1e-6, "map and world coordinates invert exactly (%s)" % p)
	t.equal(geo.cities.filter(func(c): return c["capital"]).size(), 1, "exactly one capital")
	t.truth(geo.routes.any(func(r): return r["kind"] == "pipeline"), "the Zovar line is on the map")
	t.truth(geo.ceasefire.size() >= 3, "the ceasefire line has a course")
	for c in geo.cities:
		t.truth(String(c["region"]) in SIM_REGIONS, "%s belongs to a real region" % c["name"])
	quit(t.finish())
