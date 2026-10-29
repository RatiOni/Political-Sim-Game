extends SceneTree

const Polls = preload("res://tests/native/test_polls.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const GOVERNMENT_WEIGHT := 0.9


static func _periods(role: String) -> Dictionary:
	var periods := {}
	for seed in Polls.CALIBRATION_SEEDS:
		var state := Polls._state(role, seed)
		for _m in range(240):
			Polls.budget_policy(state, -0.05)
			Polls.ordinary_programme(state)
			NativeGameScript.next_month(state)
			var k := state.turn / 24
			if not periods.has(k):
				periods[k] = [0.0, 0.0, 0.0, 0.0, 0]
			periods[k][0] += PollsSim.government_approval(state)
			periods[k][1] += HouseholdsSim.national_confidence(state)
			periods[k][2] += PollsSim.misery_gap(state)
			periods[k][3] += state.stability_value
			periods[k][4] += 1
	return periods


func _initialize() -> void:
	var government := _periods("government")
	var opposition := _periods("opposition")
	var keys: Array = government.keys()
	keys.sort()
	for k in keys:
		var g: Array = government[k]
		var o: Array = opposition.get(k, g)
		var row: Array[float] = []
		for i in range(4):
			row.append(GOVERNMENT_WEIGHT * g[i] / g[4] + (1.0 - GOVERNMENT_WEIGHT) * o[i] / o[4])
		print('\t{"approval": %.3f, "confidence": %.3f, "misery": %.4f, "stability": %.3f},' % row)
	quit()
