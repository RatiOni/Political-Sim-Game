class_name OrientationActions
extends RefCounted


const VERBS := ["isf_renegotiate"]
const COSTS := {"isf_renegotiate": 15.0}


static func act(state: GameState, verb: String) -> Dictionary:
	var reason := reason_for(state, verb)
	if reason != "":
		return {"ok": false, "error": reason}
	state.player.political_capital -= float(COSTS[verb])
	var message := _renegotiate(state)
	ForeignSim.update_spine(state)
	return {"ok": true, "message": message}


static func reason_for(state: GameState, verb: String) -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not COSTS.has(verb):
		return "Unknown orientation step."
	if not state.player.in_government:
		return "Foreign policy belongs to the government."
	if state.foreign == null or not state.foreign.seeded:
		return "The foreign ledger is not ready."
	if not bool(state.foreign.isf.get("suspended", false)):
		return "The ISF programme is not suspended; there is nothing to renegotiate."
	if state.player.political_capital < float(COSTS[verb]):
		return "Requires %.0f political capital." % float(COSTS[verb])
	return ""


static func _renegotiate(state: GameState) -> String:
	var isf := state.foreign.isf
	isf["renegotiations"] = int(isf.get("renegotiations", 0)) + 1
	isf["suspended"] = false
	OrientationSim.release_tranche(state, "ISF disbursement after renegotiation")
	var targets := OrientationSim.isf_targets(state)
	return "The ISF agrees new terms and releases the held tranche. From the next review it wants a deficit under %.1f%% and inflation under %.1f%%." % [
		float(targets["deficit"]) * 100.0, float(targets["inflation"]) * 100.0]
