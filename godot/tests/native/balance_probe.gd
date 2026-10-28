extends SceneTree

## Balance probe (not a pass/fail test): plays five 20-year fiscal policies
## through the real monthly close and prints where each ends up. Use it to
## check any retune of the economy, budget, ministries or approval:
##   Godot --headless --path godot --script res://tests/native/balance_probe.gd
## The intended ordering (Oct 2026): a government that trims the opening gap
## once and then governs steadily ends best; steady-but-unfixed next; heavy
## austerity, no budget at all, and runaway spending all end clearly worse.

const NativeGameScript = preload("res://scripts/native/native_game.gd")
const ENVELOPES := ["state_administration", "foreign_affairs", "justice_and_policing", "national_defense",
	"infrastructure", "industry_and_jobs", "education", "health_and_welfare"]


func _run(label: String, step: float, pass_budget: bool, trace := false) -> void:
	var game = NativeGameScript.new()
	root.add_child(game)
	var r: Dictionary = game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242})
	if not r.get("ok", false):
		print("campaign failed: ", r)
		return
	var s: GameState = game._state
	var start_unemp := s.country.economy.unemployment
	var votes_lost := 0
	var emergency_months := 0
	while s.year < 2013:
		_tick(s)
		if trace and s.month == 1 and s.day == 1:
			var x := s.country.economy
			print("  %d debt %.3f rev %7.0f primary %7.0f mods %6.0f int %5.0f gdp %7.0f g %.4f sg %.4f imp %.4f infl %.3f" % [s.year, x.public_debt_pct, x.budget.revenue, x.structural_expenditure, EconomySim._modifiers_sum(s, "budget_expenditure"), x.debt_service, x.gdp, x.growth_rate, x.structural_growth_rate, x.fiscal_impulse, x.inflation])
		if BudgetSim.is_emergency(s):
			if s.day == 1:
				emergency_months += 1
		if pass_budget and s.month == 10 and s.day == 1 and s.pending_budget == null:
			var adj := {}
			for e in ENVELOPES:
				adj[e] = step if (s.year == 1993 or step != -0.05) else 0.0
			var p: Dictionary = game.propose_budget(adj)
			if p.get("ok", false):
				for f in s.country.factions:
					if not f.in_coalition:
						game.lobby_budget(f.id)
						break
				var v: Dictionary = game.call_budget_vote()
				if not v.get("passed", false):
					votes_lost += 1
	var e := s.country.economy
	print("%-22s infl %.3f  unemp %.3f (nat %.3f, start %.3f)  debt %.2f  rate %.3f  interest %7.0f  primary %8.0f  growth %.3f  appr %.2f  stab %.2f  PC %.0f  emerg_mo %d  lost %d" % [
		label, e.inflation, e.unemployment, e.natural_unemployment, start_unemp, e.public_debt_pct,
		e.effective_interest_rate, e.debt_service, e.structural_expenditure, e.growth_rate,
		s.player.approval, s.stability_value, s.player.political_capital, emergency_months, votes_lost])
	print("      crisis: civil-war risk %.2f (war=%s) insurgency %.2f vasca=%s vetrenka=%s situations=%d" % [s.civil_war_risk, s.civil_war, s.insurgency_pressure, s.campaign_meta.get("vasca_status", "-"), s.campaign_meta.get("vetrenka_status", "-"), s.event_history.size()])
	print("      households: conf %.3f hardship %.3f services %.3f real_income %.3f | welfare_delivery %.2f | econ_signal %.3f | Interior delivery %.2f" % [
		HouseholdsSim.national_confidence(s), HouseholdsSim.national_hardship(s), HouseholdsSim.national_service_access(s),
		HouseholdsSim.national_real_income(s), HouseholdsSim.welfare_delivery(s), StabilitySim.economic_signal(s),
		(s.ministries["Interior"] as MinistryState).delivery])
	game.queue_free()


## The same monthly close NativeGame runs, without building a UI snapshot
## every simulated day.
func _tick(s: GameState) -> void:
	if Calendar.advance_day(s):
		s.turn += 1
		BudgetSim.process_fiscal_year(s)
		PoliticalCapital.regenerate(s)
		MinistriesSim.simulate(s)
		EconomySim.update(s)
		RegionsSim.simulate(s)
		HouseholdsSim.simulate(s)
		CabinetSim.monthly(s)
		StabilitySim.update_approval(s)
		StabilitySim.update_stability(s)
		CrisisSim.monthly(s)
		Modifiers.age_all(s)
		EventsSim.monthly(s)


func _initialize() -> void:
	_run("neutral budget", 0.0, true)
	_run("one -5% trim, then neutral", -0.05, true)
	_run("no budget ever", 0.0, false)
	_run("austerity -15%/yr", -0.15, true)
	_run("max spend +15%/yr", 0.15, true)
	quit(0)
