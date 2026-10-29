class_name TestSupport
extends RefCounted

var passed := 0
var failed := 0

func equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		push_error("FAIL  %s\n  expected=%s\n  actual=%s" % [label, expected, actual])

func near(actual: float, expected: float, tolerance: float, label: String) -> void:
	truth(absf(actual - expected) <= tolerance, label)

func truth(value: bool, label: String) -> void:
	equal(value, true, label)

var pending_count := 0

func pending(label: String, reason: String) -> void:
	pending_count += 1
	print("PENDING  %s (%s)" % [label, reason])

func finish() -> int:
	print("NATIVE TESTS: %d passed, %d failed" % [passed, failed])
	return 0 if failed == 0 else 1
