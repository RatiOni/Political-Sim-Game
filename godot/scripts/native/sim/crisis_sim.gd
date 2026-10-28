class_name CrisisSim
extends RefCounted


const WAR_THRESHOLD := 0.75
const PEACE_THRESHOLD := 0.40
const RISK_CATCH_UP := 0.12
const INSURGENCY_WEIGHT := 0.12
const INSURGENCY_DECAY := 0.03

const WAR_STABILITY_COST := 0.03
const WAR_APPROVAL_COST := 0.02
const WAR_PC_COST := 5.0
const WAR_OUTPUT_LOSS := 0.01
const WAR_STABILITY_FLOOR := 0.03


static func breakdown(state: GameState) -> Dictionary:
	var factions := state.country.factions
	var coalition_seats := 0
	var total_seats := 0
	for f in factions:
		total_seats += f.seats
		if f.in_coalition:
			coalition_seats += f.seats
	var majority := total_seats / 2 + 1
	var majority_gap := 1.0 if coalition_seats == 0 \
		else maxf(0.0, float(majority - coalition_seats) / float(maxi(1, majority)))
	return {
		"State breakdown (stability)": maxf(0.0, (0.45 - state.stability_value) / 0.45) * 0.35,
		"Armed / hostile factions": _hostile_pressure(factions) * 0.30,
		"Civil unrest": StabilitySim._unrest(state) * 0.15,
		"No governing majority": majority_gap * 0.10,
		"Unresolved grievances": _worst_grievance(factions) * 0.10,
		"Active insurgency": state.insurgency_pressure * INSURGENCY_WEIGHT,
	}


static func target_risk(state: GameState) -> float:
	var total := 0.0
	for v in breakdown(state).values():
		total += float(v)
	return minf(1.0, total)


static func country_target_risk(c: Country) -> float:
	var econ_pressure := 0.0
	if c.economy != null:
		econ_pressure = clampf((c.economy.unemployment - 0.10) * 2.0, 0.0, 1.0)
	return minf(1.0, maxf(0.0, (0.45 - c.stability) / 0.45) * 0.40
		+ _hostile_pressure(c.factions) * 0.35
		+ _worst_grievance(c.factions) * 0.15
		+ econ_pressure * 0.10)


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_player_month(state, notes)
	for c in state.world:
		_world_month(c, notes)
	return notes


static func _player_month(state: GameState, notes: Array[String]) -> void:
	state.civil_war_risk = clampf(
		state.civil_war_risk + (target_risk(state) - state.civil_war_risk) * RISK_CATCH_UP, 0.0, 1.0)
	state.insurgency_pressure = maxf(0.0, state.insurgency_pressure - INSURGENCY_DECAY)
	if not state.civil_war:
		if state.civil_war_risk >= WAR_THRESHOLD:
			state.civil_war = true
			state.country.in_civil_war = true
			notes.append("%s has fallen into civil war." % state.country.name)
		return
	if state.civil_war_risk < PEACE_THRESHOLD:
		state.civil_war = false
		state.country.in_civil_war = false
		notes.append("The civil war in %s is over." % state.country.name)
		return
	state.stability_value = maxf(WAR_STABILITY_FLOOR, state.stability_value - WAR_STABILITY_COST)
	state.player.approval = maxf(0.0, state.player.approval - WAR_APPROVAL_COST)
	state.player.political_capital = maxf(0.0, state.player.political_capital - WAR_PC_COST)
	state.country.economy.gdp *= (1.0 - WAR_OUTPUT_LOSS)
	notes.append("The civil war goes on, at a cost to the economy and the government.")


static func _world_month(c: Country, notes: Array[String]) -> void:
	c.civil_war_risk = clampf(
		c.civil_war_risk + (country_target_risk(c) - c.civil_war_risk) * RISK_CATCH_UP, 0.0, 1.0)
	if not c.in_civil_war:
		if c.civil_war_risk >= WAR_THRESHOLD:
			c.in_civil_war = true
			notes.append("%s has fallen into civil war." % c.name)
		return
	if c.civil_war_risk < PEACE_THRESHOLD:
		c.in_civil_war = false
		notes.append("The civil war in %s is over." % c.name)
		return
	c.stability = maxf(WAR_STABILITY_FLOOR, c.stability - WAR_STABILITY_COST)
	if c.economy != null:
		c.economy.gdp *= (1.0 - WAR_OUTPUT_LOSS)


static func _hostile_pressure(factions: Array) -> float:
	var total := 0.0
	for f in factions:
		total += (f as Faction).opposition_strength()
	return minf(1.0, total)


static func _worst_grievance(factions: Array) -> float:
	var worst := 0.0
	for f in factions:
		for g in (f as Faction).grievances:
			worst = maxf(worst, g.severity)
	return worst
