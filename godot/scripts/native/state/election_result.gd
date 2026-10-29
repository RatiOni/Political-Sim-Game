class_name ElectionResult
extends RefCounted


var turn: int = 0
var year: int = 0
var month: int = 1
var was_snap: bool = false
var eligible: int = 0
var total_cast: float = 0.0
var turnout: float = 0.0
var votes: Dictionary = {}
var vote_share: Dictionary = {}
var final_seats: Dictionary = {}
var seat_changes: Dictionary = {}
var regional_vote_share: Dictionary = {}
var regional_turnout: Dictionary = {}
var regional_access: Dictionary = {}
var ruling_faction_id: String = ""
var previous_ruling_faction_id: String = ""
var coalition_faction_ids: Array[String] = []
var player_in_government: bool = false
var player_lost_office: bool = false
var player_gained_office: bool = false
var mandate: Dictionary = {"delivered": 0, "broken": 0}
var incumbent_approval: float = 0.5


func to_dict() -> Dictionary:
	return {
		"turn": turn, "year": year, "month": month, "was_snap": was_snap,
		"eligible": eligible, "total_cast": total_cast, "turnout": turnout,
		"votes": votes.duplicate(), "vote_share": vote_share.duplicate(),
		"final_seats": final_seats.duplicate(), "seat_changes": seat_changes.duplicate(),
		"regional_vote_share": regional_vote_share.duplicate(true),
		"regional_turnout": regional_turnout.duplicate(), "regional_access": regional_access.duplicate(),
		"ruling_faction_id": ruling_faction_id, "previous_ruling_faction_id": previous_ruling_faction_id,
		"coalition_faction_ids": coalition_faction_ids.duplicate(),
		"player_in_government": player_in_government, "player_lost_office": player_lost_office,
		"player_gained_office": player_gained_office, "mandate": mandate.duplicate(),
		"incumbent_approval": incumbent_approval,
	}


static func from_dict(data: Variant) -> ElectionResult:
	if not (data is Dictionary):
		push_error("ElectionResult.from_dict: expected a Dictionary")
		return null
	var r := ElectionResult.new()
	r.turn = GameState._int_field(data, "turn", 0)
	r.year = GameState._int_field(data, "year", 0)
	r.month = GameState._int_field(data, "month", 1)
	r.was_snap = GameState._bool_field(data, "was_snap", false)
	r.eligible = GameState._int_field(data, "eligible", 0)
	r.total_cast = float(data.get("total_cast", 0.0))
	r.turnout = float(data.get("turnout", 0.0))
	for key in ["votes", "vote_share", "final_seats", "seat_changes", "regional_turnout", "regional_access", "mandate"]:
		var raw: Variant = data.get(key, {})
		if not (raw is Dictionary):
			push_error("ElectionResult.from_dict: malformed %s" % key)
			return null
		var clean := {}
		for k in raw:
			clean[String(k)] = int(raw[k]) if key in ["final_seats", "seat_changes", "mandate"] else float(raw[k])
		r.set(key, clean)
	var regional: Variant = data.get("regional_vote_share", {})
	if not (regional is Dictionary):
		return null
	for region_id in regional:
		if not (regional[region_id] is Dictionary):
			return null
		var shares := {}
		for k in regional[region_id]:
			shares[String(k)] = float(regional[region_id][k])
		r.regional_vote_share[String(region_id)] = shares
	r.ruling_faction_id = String(data.get("ruling_faction_id", ""))
	r.previous_ruling_faction_id = String(data.get("previous_ruling_faction_id", ""))
	var coalition: Variant = data.get("coalition_faction_ids", [])
	if not (coalition is Array):
		return null
	for id in coalition:
		r.coalition_faction_ids.append(String(id))
	r.player_in_government = GameState._bool_field(data, "player_in_government", false)
	r.player_lost_office = GameState._bool_field(data, "player_lost_office", false)
	r.player_gained_office = GameState._bool_field(data, "player_gained_office", false)
	r.incumbent_approval = float(data.get("incumbent_approval", 0.5))
	return r
