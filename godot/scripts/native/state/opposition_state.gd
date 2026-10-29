class_name OppositionState
extends RefCounted


const PLEDGE_STATUSES := ["pledged", "delivered", "attempted", "adopted", "undercut", "broken"]
const RESPONSES := ["", "support", "oppose", "amend"]
const FIRST_GOVERNMENT_BILL_TURN := 2

var credibility: float = 0.5
var pledges: Array[Dictionary] = []
var campaign_turns: Dictionary = {}
var shadow_cabinet: Array[Minister] = []
var mandate_start_turn: int = -1

var government_bill: Law = null
var bill_introduced_turn: int = -1
var response: String = ""
var next_bill_turn: int = FIRST_GOVERNMENT_BILL_TURN
var last_government_defeat_turn: int = -999


func pledge_for(bill_id: String) -> Dictionary:
	for p in pledges:
		if String(p.get("bill_id", "")) == bill_id:
			return p
	return {}


func shadow_for(portfolio: String) -> Minister:
	for m in shadow_cabinet:
		if m.portfolio == portfolio:
			return m
	return null


func to_dict() -> Dictionary:
	var shadows: Array = []
	for m in shadow_cabinet:
		shadows.append(m.to_dict())
	return {
		"credibility": credibility,
		"pledges": pledges.duplicate(true),
		"campaign_turns": campaign_turns.duplicate(),
		"shadow_cabinet": shadows,
		"mandate_start_turn": mandate_start_turn,
		"government_bill": null if government_bill == null else government_bill.to_dict(),
		"bill_introduced_turn": bill_introduced_turn,
		"response": response,
		"next_bill_turn": next_bill_turn,
		"last_government_defeat_turn": last_government_defeat_turn,
	}


static func from_dict(data: Variant) -> OppositionState:
	var out := OppositionState.new()
	if data == null:
		return out
	if not (data is Dictionary):
		push_error("OppositionState.from_dict: expected a Dictionary")
		return null
	out.credibility = float(data.get("credibility", 0.5))
	var pledge_rows: Variant = data.get("pledges", [])
	var shadow_rows: Variant = data.get("shadow_cabinet", [])
	var turns: Variant = data.get("campaign_turns", {})
	if not (pledge_rows is Array) or not (shadow_rows is Array) or not (turns is Dictionary):
		push_error("OppositionState.from_dict: malformed collections")
		return null
	for row in pledge_rows:
		if not (row is Dictionary):
			return null
		out.pledges.append({"bill_id": String(row.get("bill_id", "")), "status": String(row.get("status", "pledged")),
			"campaigns": GameState._int_field(row, "campaigns", 0)})
	for key in turns:
		out.campaign_turns[String(key)] = int(turns[key])
	for row in shadow_rows:
		var m := Minister.from_dict(row) if row is Dictionary else null
		if m == null:
			return null
		out.shadow_cabinet.append(m)
	out.mandate_start_turn = GameState._int_field(data, "mandate_start_turn", -1)
	var bill: Variant = data.get("government_bill", null)
	if bill != null:
		if not (bill is Dictionary):
			return null
		out.government_bill = Law.from_dict(bill)
		if out.government_bill == null:
			return null
	out.bill_introduced_turn = GameState._int_field(data, "bill_introduced_turn", -1)
	out.response = String(data.get("response", ""))
	out.next_bill_turn = GameState._int_field(data, "next_bill_turn", FIRST_GOVERNMENT_BILL_TURN)
	out.last_government_defeat_turn = GameState._int_field(data, "last_government_defeat_turn", -999)
	return out
