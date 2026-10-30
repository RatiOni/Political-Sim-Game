extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const Relief = preload("res://tests/native/test_west_relief.gd")
const Journeys = preload("res://tests/native/test_orientation_journeys.gd")
const SEEDS := [919191, 31, 424242, 7]
const MONTHS := 240
const DEPENDENCE_GAIN := 0.2
const WEST_RELIEF_KRASOVA_COST := 0.029


static func _relief_journey(seed: int, accept: bool) -> Dictionary:
	var state := Relief._state(seed)
	var g := state.foreign.gas
	var offered := -1
	var severity := 0.0
	var share := []
	var monthly := []
	var leverage := []
	var lowest_stability := 1.0
	var approval := 0.0
	var invalid := 0
	for m in range(MONTHS):
		Journeys._play(state, "western")
		if g.second_line_started < 0 and g.second_line_volume <= 0.0:
			EnergyActions.act(state, "gas_second_line")
		if state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "concert_energy_offer"):
			offered = state.turn
			EventActions.resolve(state, "concert_energy_offer", "accept" if accept else "decline")
		if state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "concert_energy_conditions"):
			EventActions.resolve(state, "concert_energy_conditions", "meet")
		NativeGameScript.next_month(state)
		severity += GasSim.national_severity(state)
		monthly.append(GasSim.national_severity(state))
		leverage.append(ForeignSim.leverage_of(state, g.supplier_id))
		share.append(float(state.foreign.gas_share.get(g.supplier_id, 1.0)))
		lowest_stability = minf(lowest_stability, state.stability_value)
		approval += state.player.approval / float(MONTHS)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	return {"offered": offered, "started": g.second_line_started, "saved": g.second_line_months_saved,
		"open": g.second_line_volume > 0.0, "severity": severity, "share": share, "monthly": monthly, "leverage": leverage, "cuts": g.cuts,
		"approval": approval, "lowest_stability": lowest_stability, "invalid": invalid,
		"gdp": state.country.economy.gdp, "krasova": Relief._score(state, g.supplier_id)}


func _test_the_west_relief_pays(t) -> void:
	var accepted := 0
	var relief_severity := 0.0
	var control_severity := 0.0
	var relief_leverage := 0.0
	var control_leverage := 0.0
	for seed in SEEDS:
		var relief := _relief_journey(seed, true)
		var control := _relief_journey(seed, false)
		t.equal(int(relief["invalid"]) + int(control["invalid"]), 0, "seed %d: both journeys stay valid" % seed)
		t.truth(bool(relief["open"]) and bool(control["open"]), "seed %d: both journeys actually build the second line" % seed)
		t.truth(float(relief["approval"]) >= 0.25 and float(relief["lowest_stability"]) >= 0.15, "seed %d: the relief journey is viable" % seed)
		print("relief seed %d: offered %d started %d saved %d severity %.3f/%.3f cuts %d/%d gdp %.0f/%.0f krasova %.3f/%.3f approval %.3f/%.3f" % [
			seed, relief["offered"], relief["started"], relief["saved"], relief["severity"], control["severity"],
			relief["cuts"], control["cuts"], relief["gdp"], control["gdp"], relief["krasova"], control["krasova"],
			relief["approval"], control["approval"]])
		if int(relief["offered"]) < 0:
			continue
		accepted += 1
		var start := int(relief["started"])
		var fast := start + GasSim.SECOND_LINE_MONTHS - int(relief["saved"])
		var slow := start + GasSim.SECOND_LINE_MONTHS
		var gain := 0.0
		for turn in range(fast, slow):
			gain += (float(control["share"][turn - 1]) - float(relief["share"][turn - 1])) / float(maxi(1, slow - fast))
		var win_r := 0.0
		var win_c := 0.0
		for turn in range(fast, slow):
			win_r += float(relief["monthly"][turn - 1])
			win_c += float(control["monthly"][turn - 1])
			relief_leverage += float(relief["leverage"][turn - 1]) / float(maxi(1, slow - fast))
			control_leverage += float(control["leverage"][turn - 1]) / float(maxi(1, slow - fast))
		print("relief seed %d: opens %d vs %d, gain %.3f window %.3f/%.3f" % [seed, fast, slow, gain, win_r, win_c])
		t.truth(gain >= DEPENDENCE_GAIN, "seed %d: while only the relief has its line, Krasova's gas share is lower by %.2f" % [seed, gain])
		relief_severity += float(relief["severity"])
		control_severity += float(control["severity"])
	t.truth(accepted * 4 >= SEEDS.size() * 3, "the Concert makes its offer on most seeds (%d of %d)" % [accepted, SEEDS.size()])
	t.truth(relief_leverage < control_leverage, "summed over seeds, while only the relief has its line Krasova holds less leverage (%.3f vs %.3f)" % [relief_leverage, control_leverage])
	t.truth(relief_severity <= control_severity + WEST_RELIEF_KRASOVA_COST, "over twenty years the relief costs no more cold than Krasova's anger explains (%.3f vs %.3f)" % [relief_severity, control_severity])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_west_relief_pays(t)
	quit(t.finish())
