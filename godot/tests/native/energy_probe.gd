extends SceneTree

const FiscalJourneys = preload("res://tests/native/test_fiscal_journeys.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


func _initialize() -> void:
	for seed in [919191, 31, 424242, 7]:
		var state := FiscalJourneys._state("government", seed)
		ForeignSim.ensure(state)
		var winter := 0.0
		var winters := 0
		var bill := 0.0
		for _m in range(240):
			FiscalJourneys.steady_budget(state)
			NativeGameScript.next_month(state)
			if GasSim.season_weight(state.month) > 1.0:
				winter += GasSim.national_shortfall(state)
				winters += 1
			bill += GasSim.budget_cost(state) / state.country.economy.gdp / 240.0
		var g := state.foreign.gas
		print("E seed=%d demands=%d threats=%d cuts=%d winter_short=%.4f bill_gdp=%.4f arrears=%.0f price=%.1f" % [
			seed, g.demands, g.threats, g.cuts, winter / maxf(1.0, winters), bill, g.arrears, g.price])
	quit()
