class_name Elections
extends RefCounted


const TERM_MONTHS := 48
const SEAT_THRESHOLD := 0.03
const VOTING_AGE_SHARE := 0.72

const TURNOUT_BASELINE := 0.65
const TURNOUT_FLOOR := 0.35
const TURNOUT_CEILING := 0.92
const GOVERNMENT_JUDGEMENT := 0.6
const OPPOSITION_JUDGEMENT := 0.3
const STABILITY_IN_JUDGEMENT := 0.5
const LEADER_STANDING := 0.3
const PLATFORM_WEIGHT := 1.5
const GOVERNMENT_FATIGUE := 0.12
const FATIGUE_TERM_CAP := 3

const CONTROL_ACCESS := {"state": 1.0, "autonomous": 0.9, "limited": 0.55, "separatist": 0.0}
const REACH_IN_ACCESS := 0.3
const MANDATE_CAPITAL := 20.0


static func months_until(state: GameState) -> int:
	return maxi(0, TERM_MONTHS - (state.turn - state.last_election_turn))


static func monthly(state: GameState) -> Array[String]:
	if months_until(state) > 0:
		return [] as Array[String]
	return report(state, hold(state, false))


static func government_performance(state: GameState) -> float:
	var ordinary := PollsSim.ordinary_government(state)
	return (HouseholdsSim.national_confidence(state) - float(ordinary["confidence"])) \
		+ (state.stability_value - float(ordinary["stability"])) * STABILITY_IN_JUDGEMENT


static func enthusiasm(state: GameState, f: Faction) -> float:
	var performance := government_performance(state)
	var value := TURNOUT_BASELINE + (performance * GOVERNMENT_JUDGEMENT if f.in_coalition else -performance * OPPOSITION_JUDGEMENT)
	if f.id == state.ruling_faction_id:
		value -= GOVERNMENT_FATIGUE * (terms_in_office(state) - 1)
	if f.id == state.player.faction_id:
		value += (state.player.approval - float(PollsSim.ORDINARY_PLAYER_GOVERNMENT["approval"])) * LEADER_STANDING + OppositionSim.electoral_edge(state) * PLATFORM_WEIGHT
	return clampf(value, TURNOUT_FLOOR, TURNOUT_CEILING)


static func terms_in_office(state: GameState) -> int:
	var terms := 1
	for i in range(state.election_history.size() - 1, -1, -1):
		var r: ElectionResult = state.election_history[i]
		if r.ruling_faction_id != state.ruling_faction_id or r.previous_ruling_faction_id != state.ruling_faction_id:
			break
		terms += 1
	return mini(terms, FATIGUE_TERM_CAP)


static func access(region: RegionState) -> float:
	var base := float(CONTROL_ACCESS.get(region.control, 1.0))
	return base * (1.0 - REACH_IN_ACCESS + REACH_IN_ACCESS * clampf(region.state_reach, 0.0, 1.0))


static func local_support(state: GameState, region: RegionState) -> Dictionary:
	var raw := {}
	var total := 0.0
	for f in state.country.factions:
		var anchor := float(region.support_anchor.get(f.id, f.support))
		var swing := f.support / anchor if anchor > 0.0 else 1.0
		var value := maxf(0.0, float(region.party_support.get(f.id, f.support)) * swing)
		raw[f.id] = value
		total += value
	for id in raw:
		raw[id] = raw[id] / total if total > 0.0 else 0.0
	return raw


static func tally(state: GameState) -> Dictionary:
	var eligible := maxi(1, int(float(state.country.population) * VOTING_AGE_SHARE))
	var enthusiasm_of := {}
	var votes := {}
	for f in state.country.factions:
		enthusiasm_of[f.id] = enthusiasm(state, f)
		votes[f.id] = 0.0
	var regional_share := {}
	var regional_turnout := {}
	var regional_access := {}
	var region_ids: Array = state.regions.keys()
	region_ids.sort()
	if region_ids.is_empty():
		var total_support := 0.0
		for f in state.country.factions:
			total_support += maxf(0.0, f.support)
		for f in state.country.factions:
			votes[f.id] = maxf(0.0, f.support) / maxf(total_support, 1e-9) * float(enthusiasm_of[f.id]) * eligible
	for region_id in region_ids:
		var region: RegionState = state.regions[region_id]
		var potential := float(eligible) * RegionsSim.population_weight(state, region_id)
		var open := access(region)
		var support := local_support(state, region)
		var local := {}
		var cast := 0.0
		for f in state.country.factions:
			var v := float(support[f.id]) * float(enthusiasm_of[f.id]) * potential * open
			local[f.id] = v
			cast += v
			votes[f.id] = float(votes[f.id]) + v
		var shares := {}
		for id in local:
			shares[id] = local[id] / cast if cast > 0.0 else 0.0
		regional_share[region_id] = shares
		regional_turnout[region_id] = cast / potential if potential > 0.0 else 0.0
		regional_access[region_id] = open
	var total_cast := 0.0
	for v in votes.values():
		total_cast += float(v)
	var vote_share := {}
	for id in votes:
		vote_share[id] = float(votes[id]) / total_cast if total_cast > 0.0 else 0.0
	return {"eligible": eligible, "votes": votes, "vote_share": vote_share, "total_cast": total_cast,
		"turnout": clampf(total_cast / float(eligible), 0.0, 1.0), "regional_vote_share": regional_share,
		"regional_turnout": regional_turnout, "regional_access": regional_access}


static func allocate_seats(weights: Dictionary, total_seats: int) -> Dictionary:
	var ids: Array = weights.keys()
	ids.sort()
	var total := 0.0
	for id in ids:
		total += maxf(0.0, float(weights[id]))
	var qualifying: Array = ids.filter(func(id) -> bool: return total > 0.0 and maxf(0.0, float(weights[id])) / total >= SEAT_THRESHOLD)
	if qualifying.is_empty():
		qualifying = ids.duplicate()
	var qualifying_total := 0.0
	for id in qualifying:
		qualifying_total += maxf(0.0, float(weights[id]))
	var seats := {}
	for id in ids:
		seats[id] = 0
	var remainders: Array = []
	var assigned := 0
	for id in qualifying:
		var exact := maxf(0.0, float(weights[id])) / qualifying_total * total_seats if qualifying_total > 0.0 \
			else float(total_seats) / qualifying.size()
		seats[id] = floori(exact)
		assigned += floori(exact)
		remainders.append([exact - floorf(exact), id])
	remainders.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and String(a[1]) < String(b[1])))
	for i in range(total_seats - assigned):
		var id: String = remainders[i % remainders.size()][1]
		seats[id] = int(seats[id]) + 1
	return seats


static func form_government(state: GameState) -> Array[Faction]:
	var seated: Array[Faction] = []
	var total := 0
	for f in state.country.factions:
		total += f.seats
		if f.seats > 0:
			seated.append(f)
	seated.sort_custom(func(a: Faction, b: Faction) -> bool: return a.seats > b.seats or (a.seats == b.seats and a.id < b.id))
	var coalition: Array[Faction] = []
	for seed in seated:
		var partners := seated if seed.id == state.player.faction_id \
			else seated.filter(func(f: Faction) -> bool: return f.id != state.player.faction_id)
		coalition = GameFactory.build_coalition_around(seed, partners, total / 2 + 1)
		if not coalition.is_empty():
			break
	if coalition.is_empty() and not seated.is_empty():
		coalition = [seated[0]]
	for f in state.country.factions:
		f.in_coalition = coalition.has(f)
	if not coalition.is_empty():
		state.ruling_faction_id = coalition[0].id
	return coalition


static func staff_cabinet(state: GameState, preferred: Array[Minister]) -> Array[String]:
	var notes: Array[String] = []
	var coalition: Array[Faction] = []
	for f in state.country.factions:
		if f.in_coalition:
			coalition.append(f)
	coalition.sort_custom(func(a: Faction, b: Faction) -> bool: return a.seats > b.seats or (a.seats == b.seats and a.id < b.id))
	var cabinet: Array[Minister] = []
	for i in range(CabinetActions.CORE_PORTFOLIOS.size()):
		var portfolio := CabinetActions.CORE_PORTFOLIOS[i]
		var nominee: Minister = null
		for m in preferred:
			if m.portfolio == portfolio:
				nominee = m
		if nominee == null and not coalition.is_empty():
			nominee = CabinetActions.generate_candidate(state, portfolio, coalition[i % coalition.size()], false)
		if nominee != null:
			cabinet.append(nominee)
			notes.append("%s takes office at %s." % [nominee.name, portfolio])
	state.ministers = cabinet
	state.cabinet_shortlists.clear()
	return notes


static func hold(state: GameState, snap: bool) -> ElectionResult:
	var was_governing := state.player.in_government
	var old_ruling := state.ruling_faction_id
	var incumbent_approval := PollsSim.government_approval(state)
	var old_seats := {}
	var total_seats := 0
	for f in state.country.factions:
		old_seats[f.id] = f.seats
		total_seats += f.seats
	var verdict := OppositionSim.judge_mandate(state)
	var count := tally(state)
	var seats := allocate_seats(count["votes"], total_seats)
	for f in state.country.factions:
		f.seats = int(seats.get(f.id, 0))
	var coalition := form_government(state)
	var governing := state.ruling_faction_id == state.player.faction_id
	if governing and not was_governing:
		OppositionSim.take_office(state)
	elif was_governing and not governing:
		OppositionSim.leave_office(state)
	elif was_governing and governing:
		state.player.in_government = true
		OppositionSim.renew_mandate(state)
	elif state.ruling_faction_id != old_ruling:
		OppositionSim.hand_over(state)
	if governing:
		state.player.elections_won += 1
		state.player.political_capital = minf(PoliticalCapital.ABSOLUTE_LIMIT, state.player.political_capital + MANDATE_CAPITAL)
	var result := ElectionResult.new()
	result.turn = state.turn
	result.year = state.year
	result.month = state.month
	result.was_snap = snap
	result.eligible = int(count["eligible"])
	result.total_cast = float(count["total_cast"])
	result.turnout = float(count["turnout"])
	result.votes = count["votes"]
	result.vote_share = count["vote_share"]
	result.final_seats = seats
	for id in seats:
		result.seat_changes[id] = int(seats[id]) - int(old_seats.get(id, 0))
	result.regional_vote_share = count["regional_vote_share"]
	result.regional_turnout = count["regional_turnout"]
	result.regional_access = count["regional_access"]
	result.ruling_faction_id = state.ruling_faction_id
	result.previous_ruling_faction_id = old_ruling
	for f in coalition:
		result.coalition_faction_ids.append(f.id)
	result.player_in_government = state.player.in_government
	result.player_lost_office = was_governing and not state.player.in_government
	result.player_gained_office = not was_governing and state.player.in_government
	result.mandate = verdict
	result.incumbent_approval = incumbent_approval
	state.election_history.append(result)
	state.last_election_turn = state.turn
	return result


static func report(state: GameState, result: ElectionResult) -> Array[String]:
	var notes: Array[String] = []
	var tag := "SNAP ELECTION" if result.was_snap else "GENERAL ELECTION"
	var parties: Array[String] = []
	var ranked := state.country.factions.duplicate()
	ranked.sort_custom(func(a: Faction, b: Faction) -> bool: return a.seats > b.seats or (a.seats == b.seats and a.id < b.id))
	for f in ranked:
		if f.seats > 0:
			parties.append("%s %d (%+d)" % [f.name, f.seats, int(result.seat_changes.get(f.id, 0))])
	var headline := "%s — turnout %.1f%%. Seats: %s." % [tag, result.turnout * 100.0, ", ".join(parties)]
	notes.append(headline)
	notes.append("Regions:\n%s" % "\n".join(_regional_lines(state, result)))
	var winner := _faction(state, result.ruling_faction_id)
	var winner_name := "a new coalition" if winner == null else winner.name
	var leader := "its leadership" if winner == null or winner.leader == "" else winner.leader
	Voice.record(state, "election", {"tag": tag, "winner_party": winner_name, "winner_leader": leader,
		"turnout": "%.1f" % (result.turnout * 100.0), "player_won": result.player_in_government,
		"lost_office": result.player_lost_office, "gained_office": result.player_gained_office}, headline)
	if result.player_lost_office:
		notes.append("You have lost office. %s forms the new government." % winner_name)
		notes.append(Voice.say(state, "election_winner_quote", {"leader": leader, "party": winner_name}))
	elif result.player_gained_office:
		notes.append("You return to office at the head of a new government.")
	elif result.player_in_government:
		notes.append("Your government is returned to power.")
	else:
		notes.append("You remain in opposition.")
	if int(result.mandate.get("broken", 0)) > 0:
		notes.append("Manifesto verdict: %d pledge%s went undelivered." % [result.mandate["broken"], "" if int(result.mandate["broken"]) == 1 else "s"])
	return notes


static func _regional_lines(state: GameState, result: ElectionResult) -> Array[String]:
	var profiles: Dictionary = ContentRepository.load_all().get("catalogs", {}).get("regions_and_programs", {}).get("region_profiles", {})
	var lines: Array[String] = []
	var ids: Array = result.regional_vote_share.keys()
	ids.sort()
	for region_id in ids:
		var name := String(profiles.get(region_id, {}).get("name", String(region_id).capitalize()))
		var shares: Dictionary = result.regional_vote_share[region_id]
		if float(result.regional_access.get(region_id, 0.0)) <= 0.0:
			lines.append("  %s — no poll" % name)
			continue
		var best := ""
		for id in shares:
			if best == "" or float(shares[id]) > float(shares[best]):
				best = id
		var party := _faction(state, best)
		lines.append("  %s — %s %.0f%%" % [name, best if party == null else party.name, float(shares.get(best, 0.0)) * 100.0])
	return lines


static func _faction(state: GameState, id: String) -> Faction:
	for f in state.country.factions:
		if f.id == id:
			return f
	return null
