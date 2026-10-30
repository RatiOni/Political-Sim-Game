extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Calibration = preload("res://tests/native/test_election_calibration.gd")


func _test_the_record_moves_the_result(t) -> void:
	var austere_on := Calibration.ruling_share(-0.15, false, 1.0)
	var austere_off := Calibration.ruling_share(-0.15, false, 0.0)
	t.truth(austere_on < austere_off, "austerity's party polls worse when the record counts (%.3f vs %.3f)" % [austere_on, austere_off])
	var strong_on := Calibration.ruling_share(0.0, true, 1.0)
	var strong_off := Calibration.ruling_share(0.0, true, 0.0)
	t.truth(strong_on > strong_off, "a strong government's party polls better when the record counts (%.3f vs %.3f)" % [strong_on, strong_off])


func _test_a_strong_record_never_hurts(t) -> void:
	for seed in [11, 22, 33, 44, 55, 66]:
		var on := Calibration.ruling_share(0.0, true, 1.0, [seed])
		var off := Calibration.ruling_share(0.0, true, 0.0, [seed])
		t.truth(on > off, "seed %d: a strong government's record raises its party's share (%.3f vs %.3f)" % [seed, on, off])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_record_moves_the_result(t)
	_test_a_strong_record_never_hurts(t)
	quit(t.finish())
