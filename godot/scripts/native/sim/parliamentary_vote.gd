class_name ParliamentaryVote
extends RefCounted


const SALIENCE := 4.0
const WING_SALIENCE := 2.0
const BLOC_POLICY_SALIENCE := 1.0
const MAX_DISTANCE := 2.83


static func project(factions: Array, motion: Dictionary) -> Dictionary:
	var resolved_motion := motion.duplicate(false)
	resolved_motion["factions"] = factions
	var votes_for := 0
	var votes_against := 0
	var breakdown: Array = []
	var rebellions: Array = []
	for value in factions:
		var faction: Faction = value
		if faction == null or faction.seats <= 0:
			continue
		var wing_rows := _wing_votes(faction, resolved_motion)
		if wing_rows.is_empty():
			var lean := _predicted_support(faction, resolved_motion)
			var supports := lean >= 0.0
			votes_for += faction.seats if supports else 0
			votes_against += 0 if supports else faction.seats
			breakdown.append({
				"faction_id": faction.id,
				"name": faction.name,
				"seats": faction.seats,
				"votes_for": faction.seats if supports else 0,
				"votes_against": 0 if supports else faction.seats,
				"lean": lean,
				"wings": [],
			})
			continue

		var faction_for := 0
		var net := 0.0
		for row in wing_rows:
			if float(row["lean"]) >= 0.0:
				faction_for += int(row["seats"])
			net += float(row["lean"]) * int(row["seats"])
		var faction_against := faction.seats - faction_for
		votes_for += faction_for
		votes_against += faction_against
		var party_for := faction_for >= faction_against
		for row in wing_rows:
			var wing_for := float(row["lean"]) >= 0.0
			if int(row["seats"]) > 0 and wing_for != party_for:
				rebellions.append({
					"faction_id": faction.id,
					"wing_id": String(row["wing_id"]),
					"seats": int(row["seats"]),
					"direction": "for" if wing_for else "against",
				})
		breakdown.append({
			"faction_id": faction.id,
			"name": faction.name,
			"seats": faction.seats,
			"votes_for": faction_for,
			"votes_against": faction_against,
			"lean": net / maxf(1.0, float(faction.seats)),
			"wings": wing_rows,
		})

	var seats := votes_for + votes_against
	var required_fraction := clampf(float(motion.get("required_fraction", 0.5)), 0.5, 1.0)
	var threshold := floori(float(seats) / 2.0) + 1
	if required_fraction > 0.5:
		threshold = ceili(float(seats) * required_fraction)
	return {
		"votes_for": votes_for,
		"votes_against": votes_against,
		"threshold": threshold,
		"passed": votes_for >= threshold,
		"breakdown": breakdown,
		"rebellions": rebellions,
	}


static func _predicted_support(faction: Faction, motion: Dictionary) -> float:
	var stakes: Dictionary = motion.get("stakes", {})
	var lobbying: Dictionary = motion.get("lobbying_bonus", {})
	var policy_lean := clampf(float(stakes.get(faction.id, 0.0)) * SALIENCE, -1.0, 1.0)
	var trust := _government_trust(faction, motion)
	return clampf(trust * 0.5 + policy_lean * 0.5 + float(lobbying.get(faction.id, 0.0)), -1.0, 1.0)


static func _government_trust(faction: Faction, motion: Dictionary) -> float:
	var sponsor_id := String(motion.get("sponsor_id", ""))
	var player_faction_id := String(motion.get("player_faction_id", ""))
	if sponsor_id == "" or sponsor_id == "player" or sponsor_id == player_faction_id:
		return faction.loyalty
	if faction.id == sponsor_id:
		return 1.0
	if faction.in_coalition:
		return 0.6
	var sponsor: Faction = null
	var factions: Array = motion.get("factions", [])
	for value in factions:
		var candidate: Faction = value
		if candidate != null and candidate.id == sponsor_id:
			sponsor = candidate
			break
	if sponsor == null:
		return faction.loyalty
	return 2.0 * _affinity(faction.effective_ideology(), sponsor.effective_ideology()) - 1.0


static func _affinity(ideology: Faction.Ideology, target: Faction.Ideology) -> float:
	return 1.0 - ideology.distance_to(target) / MAX_DISTANCE


static func _wing_votes(faction: Faction, motion: Dictionary) -> Array:
	var motion_ideology: Variant = motion.get("ideology", null)
	if faction.wings.size() < 2 or not (motion_ideology is Faction.Ideology):
		return []
	var ideology: Faction.Ideology = motion_ideology
	var stakes: Dictionary = motion.get("stakes", {})
	var lobbying: Dictionary = motion.get("lobbying_bonus", {})
	var policy_lean := clampf(float(stakes.get(faction.id, 0.0)) * SALIENCE, -1.0, 1.0)
	var trust := _government_trust(faction, motion)
	var party_affinity := _affinity(faction.effective_ideology(), ideology)
	var seat_split := _split_seats(faction.wings, faction.seats)
	var rows: Array = []
	for wing in faction.wings:
		var discipline := 0.5 + 0.5 * wing.loyalty
		var bias := clampf(float(wing.policy_biases.get(String(motion.get("id", "")), 0.0)), -1.0, 1.0)
		var lean := (
			trust * 0.5 * discipline
			+ policy_lean * 0.5
			+ float(lobbying.get(faction.id, 0.0))
			+ (_affinity(wing.ideology, ideology) - party_affinity) * WING_SALIENCE
			+ bias * BLOC_POLICY_SALIENCE
		)
		rows.append({
			"wing_id": wing.id,
			"name": wing.name,
			"seats": int(seat_split[wing.id]),
			"lean": clampf(lean, -1.0, 1.0),
		})
	return rows


static func _split_seats(wings: Array[Faction.Wing], total_seats: int) -> Dictionary:
	var total_strength := 0.0
	for wing in wings:
		total_strength += maxf(0.0, wing.strength)
	if total_strength <= 0.0:
		total_strength = 1.0
	var exact: Array = []
	var seats := {}
	var assigned := 0
	for i in range(wings.size()):
		var wing := wings[i]
		var value := maxf(0.0, wing.strength) / total_strength * total_seats
		var whole := floori(value)
		seats[wing.id] = whole
		assigned += whole
		exact.append({"wing": wing, "fraction": value - whole, "index": i})
	exact.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["fraction"]), float(b["fraction"])):
			return int(a["index"]) < int(b["index"])
		return float(a["fraction"]) > float(b["fraction"])
	)
	for i in range(total_seats - assigned):
		var row: Dictionary = exact[i % exact.size()]
		var wing: Faction.Wing = row["wing"]
		seats[wing.id] = int(seats[wing.id]) + 1
	return seats
