extends SceneTree


const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const RegionsSimScript = preload("res://scripts/native/sim/regions_sim.gd")

const FIXED_SEED := 424242
const SELF_PATH := "res://tests/native/test_regions_sim.gd"


static func _base_config() -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": FIXED_SEED,
	}


static func _catalogue_region_profiles(content: Dictionary) -> Dictionary:
	var catalogs_raw: Variant = content.get("catalogs", {})
	if not (catalogs_raw is Dictionary):
		return {}
	var regions_raw: Variant = (catalogs_raw as Dictionary).get("regions_and_programs", {})
	if not (regions_raw is Dictionary):
		return {}
	var profiles_raw: Variant = (regions_raw as Dictionary).get("region_profiles", {})
	if not (profiles_raw is Dictionary):
		return {}
	return profiles_raw as Dictionary


static func _catalogue_program_definitions(content: Dictionary) -> Dictionary:
	var catalogs_raw: Variant = content.get("catalogs", {})
	if not (catalogs_raw is Dictionary):
		return {}
	var regions_raw: Variant = (catalogs_raw as Dictionary).get("regions_and_programs", {})
	if not (regions_raw is Dictionary):
		return {}
	var programs_raw: Variant = (regions_raw as Dictionary).get("regional_programs", {})
	if not (programs_raw is Dictionary):
		return {}
	return programs_raw as Dictionary


static func _national_support(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for f in state.country.factions:
		out[f.id] = f.support
	return out


static func _support_total(support: Dictionary) -> float:
	var total: float = 0.0
	for v in support.values():
		total += float(v)
	return total


static func _make_program(region_id: String, program_id: String, duration: int,
		months_active: int = 0) -> RegionState.RegionalProgram:
	var p: RegionState.RegionalProgram = RegionState.RegionalProgram.new()
	p.id = program_id + ":" + region_id + ":0"
	p.program_id = program_id
	p.region_id = region_id
	p.started_turn = 0
	p.duration = duration
	p.monthly_cost = 10.0
	p.months_active = months_active
	return p


static func _add_modifier(state: GameState, source_id: String) -> Modifier:
	var m: Modifier = Modifier.new()
	m.id = "test-mod-" + source_id
	m.source = "test"
	m.target = "budget_expenditure"
	m.magnitude = 5.0
	m.onset_delay = 0
	m.ramp_duration = 1
	m.hold_duration = 12
	m.decay_duration = 0
	m.age = 0
	m.institutional = false
	m.source_id = source_id
	state.modifiers.append(m)
	return m


static func _modifier_source_ids(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for m in state.modifiers:
		out.append((m as Modifier).source_id)
	return out


static func _active_program_ids(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for item in state.regional_programs:
		var p: RegionState.RegionalProgram = item as RegionState.RegionalProgram
		if p != null:
			out.append(p.id)
	return out


static func _assign_minister(state: GameState, portfolio: String, competence: float,
		loyalty: float) -> void:
	var m: Minister = Minister.new()
	m.id = "test-" + portfolio
	m.name = "Test Minister"
	m.portfolio = portfolio
	m.faction_id = "liberal_democrats"
	m.competence = competence
	m.loyalty = loyalty
	m.ambition = 0.0
	state.ministers.append(m)



func _test_seed_matches_catalogue(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var profiles: Dictionary = _catalogue_region_profiles(content)
	t.truth(not profiles.is_empty(), "catalogue has region profiles to compare against")
	t.equal(profiles.keys().size(), 9, "catalogue holds nine authored region profiles")
	var seeded_keys: Array = state.regions.keys()
	seeded_keys.sort()
	var profile_keys: Array = profiles.keys()
	profile_keys.sort()
	t.equal(seeded_keys, profile_keys, "seeded region ids match the catalogue exactly (no second copy)")
	for region_id in profile_keys:
		var rid: String = String(region_id)
		var profile: Dictionary = profiles[rid]
		var region: RegionState = state.regions.get(rid) as RegionState
		t.truth(region != null, "region %s seeded" % rid)
		if region == null:
			continue
		t.equal(region.id, rid, "%s id matches" % rid)
		t.equal(region.unemployment, float(profile["initial_unemployment"]),
			"%s unemployment matches catalogue" % rid)
		t.equal(region.state_reach, float(profile["initial_state_reach"]),
			"%s state_reach matches catalogue" % rid)
		t.equal(region.pressure, float(profile["initial_pressure"]),
			"%s pressure matches catalogue" % rid)
		t.equal(region.control, String(profile["control"]), "%s control matches catalogue" % rid)
		t.equal(region.issue_id, String(profile["issue_id"]), "%s issue_id matches catalogue" % rid)
		t.equal(region.party_support, profile["party_support"],
			"%s party_support matches catalogue" % rid)
		t.equal(region.support_anchor, _national_support(state),
			"%s support_anchor matches national support" % rid)
		t.truth(not region.party_support.is_empty(), "%s party_support non-empty" % rid)
		t.truth(not region.support_anchor.is_empty(), "%s support_anchor non-empty" % rid)
		var bounded := true
		for v in region.party_support.values():
			if float(v) < 0.0 or float(v) > 1.0:
				bounded = false
		t.truth(bounded, "%s party_support stays bounded" % rid)
		t.near(_support_total(region.party_support), 1.0, 0.000001,
			"%s party_support stays normalised" % rid)
		t.near(_support_total(region.support_anchor), 1.0, 0.000001,
			"%s support_anchor stays normalised" % rid)


func _test_reensure_preserves_live_values(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var profiles: Dictionary = _catalogue_region_profiles(content)
	var vashtera: RegionState = state.regions["vashtera"]
	vashtera.unemployment = 0.42
	vashtera.pressure = 0.11
	state.regions.erase("sela")
	t.truth(not state.regions.has("sela"), "sanity: sela removed")
	RegionsSimScript.ensure_region_states(state)
	var kept: RegionState = state.regions["vashtera"]
	t.equal(kept.unemployment, 0.42, "re-ensure never clobbers live unemployment")
	t.equal(kept.pressure, 0.11, "re-ensure never clobbers live pressure")
	t.truth(state.regions.has("sela"), "re-ensure backfills only the missing id")
	var refilled: RegionState = state.regions["sela"]
	var sela_profile: Dictionary = profiles["sela"]
	t.equal(refilled.unemployment, float(sela_profile["initial_unemployment"]),
		"backfilled region receives authored starting conditions")


func _test_factory_seeds_regions(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.equal(state.regions.keys().size(), 9, "GameFactory.new_campaign seeds all nine regions")


func _test_non_ardenia_stays_empty(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var krasova: Country = null
	for c in state.world:
		if c.id == "krasova":
			krasova = c
	t.truth(krasova != null, "sanity: krasova exists in the world")
	if krasova == null:
		return
	state.country = krasova
	state.regions = {}
	RegionsSimScript.ensure_region_states(state)
	t.truth(state.regions.is_empty(), "ensure seeds nothing for a non-Ardenia country")
	RegionsSimScript.simulate(state)
	t.truth(state.regions.is_empty(), "simulate keeps non-Ardenia regions empty without crashing")


func _test_simulate_on_empty_ardenia_seeds_then_ticks(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.regions = {}
	state.country.economy.unemployment = 0.40
	RegionsSimScript.simulate(state)
	t.equal(state.regions.keys().size(), 9, "simulate on empty Ardenia seeds first, never bare-returns")
	var vashtera: RegionState = state.regions["vashtera"]
	var first_tick: float = vashtera.unemployment
	RegionsSimScript.simulate(state)
	t.truth((state.regions["vashtera"] as RegionState).unemployment > first_tick,
		"a second tick moves unemployment further toward the high national target")


func _test_unknown_profile_id_skips_only_that_region(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var bogus: RegionState = RegionState.new()
	bogus.id = "made_up_region"
	bogus.unemployment = 0.20
	bogus.state_reach = 0.50
	bogus.pressure = 0.50
	bogus.control = "state"
	state.regions["made_up_region"] = bogus
	state.country.economy.unemployment = 0.40
	RegionsSimScript.simulate(state)
	var kept: RegionState = state.regions["made_up_region"]
	t.equal(kept.unemployment, 0.20, "unknown profile id leaves that region untouched")
	t.equal(kept.pressure, 0.50, "unknown profile id leaves that region's pressure untouched")
	var vashtera: RegionState = state.regions["vashtera"]
	t.truth(vashtera.unemployment > 0.075, "known regions still tick around the skipped one")


func _test_missing_minister_and_ministry_fallback(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.ministers = []
	state.ministries = {}
	var program: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	state.regional_programs.append(program)
	RegionsSimScript.simulate(state)
	t.equal(program.months_active, 1, "programme advances with no minister and no ministry entry")
	t.equal(_active_program_ids(state).count(program.id), 1, "active programme occurs exactly once")



func _test_single_month_advancement(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var program: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	state.regional_programs.append(program)
	RegionsSimScript.simulate(state)
	t.equal(program.months_active, 1, "first simulate() advances exactly one month")
	t.equal(_active_program_ids(state).count(program.id), 1, "no duplicate active entries after one tick")
	RegionsSimScript.simulate(state)
	t.equal(program.months_active, 2, "second simulate() advances exactly one more month")
	t.equal(_active_program_ids(state).count(program.id), 1, "no duplicate active entries after two ticks")


func _test_control_never_flips(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var before: Dictionary = {}
	for region_id in state.regions.keys():
		var region: RegionState = state.regions[region_id]
		before[String(region_id)] = region.control
	for _i in range(3):
		RegionsSimScript.simulate(state)
	for region_id in state.regions.keys():
		var region: RegionState = state.regions[region_id]
		t.equal(region.control, String(before[String(region_id)]),
			"control never flips in the passive tick (%s)" % String(region_id))



func _test_unemployment_follows_national(t: TestSupport, content: Dictionary) -> void:
	var slack: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var boomless: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(slack != null and boomless != null, "both campaigns build")
	if slack == null or boomless == null:
		return
	slack.country.economy.unemployment = 0.02
	boomless.country.economy.unemployment = 0.40
	RegionsSimScript.simulate(slack)
	RegionsSimScript.simulate(boomless)
	var low_region: RegionState = slack.regions["vashtera"]
	var high_region: RegionState = boomless.regions["vashtera"]
	t.truth(high_region.unemployment > low_region.unemployment,
		"local unemployment moves with national unemployment")


func _test_reach_follows_capacity(t: TestSupport, content: Dictionary) -> void:
	var weak: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var strong: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(weak != null and strong != null, "both campaigns build")
	if weak == null or strong == null:
		return
	weak.country.bureaucratic_capacity = 0.10
	strong.country.bureaucratic_capacity = 1.00
	RegionsSimScript.simulate(weak)
	RegionsSimScript.simulate(strong)
	var weak_region: RegionState = weak.regions["vashtera"]
	var strong_region: RegionState = strong.regions["vashtera"]
	t.truth(strong_region.state_reach > weak_region.state_reach,
		"state reach moves with bureaucratic capacity")


func _test_pressure_follows_stability(t: TestSupport, content: Dictionary) -> void:
	var calm: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var crisis: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(calm != null and crisis != null, "both campaigns build")
	if calm == null or crisis == null:
		return
	calm.stability_value = 1.0
	crisis.stability_value = 0.0
	RegionsSimScript.simulate(calm)
	RegionsSimScript.simulate(crisis)
	var calm_region: RegionState = calm.regions["vashtera"]
	var crisis_region: RegionState = crisis.regions["vashtera"]
	t.truth(crisis_region.pressure > calm_region.pressure,
		"pressure moves against stability")


func _test_delivery_follows_minister_quality(t: TestSupport, content: Dictionary) -> void:
	var vacant: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var led: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(vacant != null and led != null, "both campaigns build")
	if vacant == null or led == null:
		return
	vacant.ministers = []
	_assign_minister(led, "Economy", 1.0, 1.0)
	var program_a: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	var program_b: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	vacant.regional_programs.append(program_a)
	led.regional_programs.append(program_b)
	RegionsSimScript.simulate(vacant)
	RegionsSimScript.simulate(led)
	var vacant_region: RegionState = vacant.regions["zavost"]
	var led_region: RegionState = led.regions["zavost"]
	t.truth(led_region.unemployment < vacant_region.unemployment,
		"a competent loyal minister delivers a larger unemployment reduction")



func _test_unknown_ids_clean_up_modifiers_and_drop(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var bad_program: RegionState.RegionalProgram = _make_program(
		"zavost", "no_such_programme", 12)
	var bad_region: RegionState.RegionalProgram = _make_program(
		"no_such_region", "industrial_recovery", 12)
	var good: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	good.id = "industrial_recovery:zavost:keeper"
	for p in [bad_program, bad_region, good]:
		state.regional_programs.append(p)
		_add_modifier(state, (p as RegionState.RegionalProgram).id)
	_add_modifier(state, "unrelated-source")
	RegionsSimScript.simulate(state)
	var active: Array[String] = _active_program_ids(state)
	t.truth(not active.has(bad_program.id), "unknown programme id drops silently")
	t.truth(not active.has(bad_region.id), "unknown region id drops silently")
	t.truth(active.has(good.id), "valid sibling programme stays active")
	t.equal(active.count(good.id), 1, "valid sibling occurs exactly once")
	var sources: Array[String] = _modifier_source_ids(state)
	t.truth(not sources.has(bad_program.id), "unknown programme's modifiers are stripped")
	t.truth(not sources.has(bad_region.id), "unknown region's modifiers are stripped")
	t.truth(sources.has(good.id), "sibling programme's modifiers are kept")
	t.truth(sources.has("unrelated-source"), "unrelated modifiers are kept")


func _test_separatist_freeze(t: TestSupport, content: Dictionary) -> void:
	var frozen: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var governed: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(frozen != null and governed != null, "both campaigns build")
	if frozen == null or governed == null:
		return
	var frozen_region: RegionState = frozen.regions["zavost"]
	frozen_region.control = "separatist"
	var program_f: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	var program_g: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12)
	frozen.regional_programs.append(program_f)
	governed.regional_programs.append(program_g)
	var frozen_modifier := _add_modifier(frozen, program_f.id)
	RegionsSimScript.simulate(frozen)
	RegionsSimScript.simulate(governed)
	t.equal(program_f.months_active, 0, "separatist region gets no months_active increment")
	t.equal(program_g.months_active, 1, "governed twin advances normally")
	t.equal(_active_program_ids(frozen).count(program_f.id), 1,
		"frozen programme stays active, exactly once")
	t.truth(_modifier_source_ids(frozen).has(program_f.id),
		"frozen programme's booked treasury modifier remains active")
	t.equal(frozen_modifier.hold_duration, 13, "a separatist freeze extends the matching finite treasury hold by one month")
	var frozen_unemp: float = (frozen.regions["zavost"] as RegionState).unemployment
	var governed_unemp: float = (governed.regions["zavost"] as RegionState).unemployment
	t.truth(frozen_unemp > governed_unemp, "frozen region receives no delivered reduction")


func _test_mid_programme_flip_freezes(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var program: RegionState.RegionalProgram = _make_program("sela", "industrial_recovery", 12)
	state.regional_programs.append(program)
	var flipped_modifier := _add_modifier(state, program.id)
	RegionsSimScript.simulate(state)
	t.equal(program.months_active, 1, "sanity: programme advances while governed")
	var region: RegionState = state.regions["sela"]
	region.control = "separatist"
	RegionsSimScript.simulate(state)
	t.equal(program.months_active, 1, "mid-programme flip to separatist freezes advancement")
	t.equal(_active_program_ids(state).count(program.id), 1, "flipped programme stays active")
	t.truth(_modifier_source_ids(state).has(program.id),
		"flipped programme's booked treasury modifier remains active")
	t.equal(flipped_modifier.hold_duration, 13, "mid-programme freeze extends the matching finite treasury hold by one month")


func _test_frozen_programme_only_extends_its_matching_finite_cost(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var region: RegionState = state.regions["zavost"]
	region.control = "separatist"
	var programme := _make_program("zavost", "industrial_recovery", 12)
	state.regional_programs.append(programme)
	var matching := _add_modifier(state, programme.id)
	matching.hold_duration = 1
	var unrelated := _add_modifier(state, "another-programme")
	var wrong_target := _add_modifier(state, programme.id)
	wrong_target.target = "gdp_growth"
	var indefinite := _add_modifier(state, programme.id)
	indefinite.hold_duration = -1
	RegionsSimScript.simulate(state)
	t.equal(matching.hold_duration, 2, "first frozen month extends matching finite budget cost once")
	t.equal(unrelated.hold_duration, 12, "unrelated programme funding is unchanged")
	t.equal(wrong_target.hold_duration, 12, "non-budget modifier is unchanged")
	t.equal(indefinite.hold_duration, -1, "indefinite modifier is unchanged")
	RegionsSimScript.simulate(state)
	t.equal(matching.hold_duration, 3, "each additional frozen month adds one hold month")
	t.equal(programme.months_active, 0, "freeze never advances programme delivery")
	region.control = "state"
	RegionsSimScript.simulate(state)
	t.equal(programme.months_active, 1, "recovered territory resumes delivery exactly once")

func _test_duration_boundaries(t: TestSupport, content: Dictionary) -> void:
	var finishing: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var ongoing: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var instant: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(finishing != null and ongoing != null and instant != null, "all campaigns build")
	if finishing == null or ongoing == null or instant == null:
		return
	var definitions: Dictionary = _catalogue_program_definitions(content)
	var definition: Dictionary = definitions["security_stabilisation"]
	var authored_duration: int = int(float(definition["duration"]))
	t.truth(authored_duration > 2, "sanity: authored duration allows both boundary probes")
	var done_program: RegionState.RegionalProgram = _make_program(
		"anera", "security_stabilisation", authored_duration, authored_duration - 1)
	var live_program: RegionState.RegionalProgram = _make_program(
		"anera", "security_stabilisation", authored_duration, authored_duration - 2)
	var flash_program: RegionState.RegionalProgram = _make_program(
		"anera", "security_stabilisation", 1, 0)
	finishing.regional_programs.append(done_program)
	ongoing.regional_programs.append(live_program)
	instant.regional_programs.append(flash_program)
	_add_modifier(finishing, done_program.id)
	_add_modifier(finishing, "unrelated-source")
	_add_modifier(ongoing, live_program.id)
	_add_modifier(instant, flash_program.id)
	RegionsSimScript.simulate(finishing)
	RegionsSimScript.simulate(ongoing)
	RegionsSimScript.simulate(instant)
	t.truth(not _active_program_ids(finishing).has(done_program.id),
		"months_active == duration-1 + 1 tick completes and removes the programme")
	t.truth(not _modifier_source_ids(finishing).has(done_program.id),
		"completed programme's modifiers are cleaned up")
	t.truth(_modifier_source_ids(finishing).has("unrelated-source"),
		"completion keeps unrelated modifiers")
	t.truth(_active_program_ids(ongoing).has(live_program.id),
		"months_active == duration-2 + 1 tick stays active")
	t.equal(live_program.months_active, authored_duration - 1,
		"months_active == duration-2 + 1 tick sits at duration-1")
	t.truth(_modifier_source_ids(ongoing).has(live_program.id),
		"ongoing programme's modifiers are kept")
	t.truth(not _active_program_ids(instant).has(flash_program.id),
		"duration == 1 completes in a single tick")
	t.truth(not _modifier_source_ids(instant).has(flash_program.id),
		"single-tick programme's modifiers are cleaned up")



func _test_vetrenka_status_overrides(t: TestSupport, content: Dictionary) -> void:
	var authored: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var settled: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var unknown: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(authored != null and settled != null and unknown != null, "all campaigns build")
	if authored == null or settled == null or unknown == null:
		return
	settled.campaign_meta["vetrenka_status"] = "settled"
	unknown.campaign_meta["vetrenka_status"] = "something_unheard_of"
	RegionsSimScript.simulate(authored)
	RegionsSimScript.simulate(settled)
	RegionsSimScript.simulate(unknown)
	var authored_vet: RegionState = authored.regions["vetrenka"]
	var settled_vet: RegionState = settled.regions["vetrenka"]
	var unknown_vet: RegionState = unknown.regions["vetrenka"]
	t.truth(settled_vet.pressure < authored_vet.pressure,
		"settled status lowers Vetrenka pressure against the authored bias")
	t.equal(unknown_vet.pressure, authored_vet.pressure,
		"unknown status falls back to the authored bias")
	var authored_sela: RegionState = authored.regions["sela"]
	var settled_sela: RegionState = settled.regions["sela"]
	var unknown_sela: RegionState = unknown.regions["sela"]
	t.equal(settled_sela.pressure, authored_sela.pressure,
		"vetrenka_status never leaks into other regions (settled)")
	t.equal(unknown_sela.pressure, authored_sela.pressure,
		"vetrenka_status never leaks into other regions (unknown)")



func _test_save_reload_round_trip(t: TestSupport, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	RegionsSimScript.ensure_region_states(state)
	var vashtera: RegionState = state.regions["vashtera"]
	vashtera.unemployment = 0.123
	vashtera.state_reach = 0.81
	vashtera.pressure = 0.37
	var program: RegionState.RegionalProgram = _make_program("zavost", "industrial_recovery", 12, 3)
	state.regional_programs.append(program)
	var flipped_modifier := _add_modifier(state, program.id)
	var snapshot: Dictionary = state.to_dict()
	var restored: GameState = GameState.from_dict(snapshot)
	t.truth(restored != null, "state survives a to_dict/from_dict round trip")
	if restored == null:
		return
	t.equal(restored.regions.keys().size(), 9, "all nine regions survive the round trip")
	var kept: RegionState = restored.regions["vashtera"]
	t.near(kept.unemployment, 0.123, 0.0000001, "live unemployment survives the round trip")
	t.near(kept.state_reach, 0.81, 0.0000001, "live state_reach survives the round trip")
	t.near(kept.pressure, 0.37, 0.0000001, "live pressure survives the round trip")
	t.equal(kept.control, vashtera.control, "control survives the round trip")
	t.equal(kept.party_support, vashtera.party_support, "party_support survives the round trip")
	t.equal(restored.regional_programs.size(), 1, "active programmes survive the round trip")
	var kept_program: RegionState.RegionalProgram = restored.regional_programs[0]
	t.equal(kept_program.id, program.id, "programme id survives the round trip")
	t.equal(kept_program.program_id, program.program_id, "programme program_id survives the round trip")
	t.equal(kept_program.region_id, program.region_id, "programme region_id survives the round trip")
	t.equal(kept_program.duration, program.duration, "programme duration survives the round trip")
	t.equal(kept_program.months_active, 3, "programme months_active survives the round trip")
	t.truth(_modifier_source_ids(restored).has(program.id),
		"programme modifiers survive the round trip")



func _test_no_formula_constants_in_test_source(t: TestSupport) -> void:
	var text: String = FileAccess.get_file_as_string(SELF_PATH)
	t.truth(text != "", "own test source is readable for the structural check")
	if text == "":
		return
	var forbidden: Array[String] = [
		"PRESSURE_" + "JOBS_WEIGHT",
		"PRESSURE_" + "CAPACITY_WEIGHT",
		"PRESSURE_" + "NATIONAL_WEIGHT",
		"UNEMPLOYMENT_" + "CONVERGENCE",
		"REACH_" + "CONVERGENCE",
		"PRESSURE_" + "CONVERGENCE",
		"DELIVERY_" + "MIN",
		"DELIVERY_" + "MAX",
		"DELIVERY_" + "BASE",
		"DELIVERY_" + "INSTITUTIONAL",
		"CONTROL_" + "LIMITED_MAX",
		"CONTROL_" + "AUTONOMOUS",
		"CONTROL_" + "VETRENKA",
		"CONTROL_" + "SEPARATIST",
		"MISSING_" + "MINISTER",
		"policy_" + "delivery_factor",
		"implementation_" + "quality",
	]
	for token in forbidden:
		t.truth(not text.contains(token),
			"test defines no production formula token '%s'" % token)


func _initialize() -> void:
	var t: TestSupport = TestSupport.new()

	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for the regions tests")

	if not content.has("error"):
		_test_seed_matches_catalogue(t, content)
		_test_reensure_preserves_live_values(t, content)
		_test_factory_seeds_regions(t, content)
		_test_non_ardenia_stays_empty(t, content)
		_test_simulate_on_empty_ardenia_seeds_then_ticks(t, content)
		_test_unknown_profile_id_skips_only_that_region(t, content)
		_test_missing_minister_and_ministry_fallback(t, content)

		_test_single_month_advancement(t, content)
		_test_control_never_flips(t, content)

		_test_unemployment_follows_national(t, content)
		_test_reach_follows_capacity(t, content)
		_test_pressure_follows_stability(t, content)
		_test_delivery_follows_minister_quality(t, content)

		_test_unknown_ids_clean_up_modifiers_and_drop(t, content)
		_test_separatist_freeze(t, content)
		_test_mid_programme_flip_freezes(t, content)
		_test_frozen_programme_only_extends_its_matching_finite_cost(t, content)
		_test_duration_boundaries(t, content)

		_test_vetrenka_status_overrides(t, content)

		_test_save_reload_round_trip(t, content)

		_test_no_formula_constants_in_test_source(t)

	quit(t.finish())
