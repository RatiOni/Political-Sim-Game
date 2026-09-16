extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")

func _initialize() -> void:
	var t = TestSupportScript.new()
	t.equal("Ardenia", "Ardenia", "equal compares exact values")
	t.near(1.0, 1.001, 0.01, "near accepts values within tolerance")
	t.truth(true, "truth accepts true")
	quit(t.finish())
