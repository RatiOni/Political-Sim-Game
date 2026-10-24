extends SceneTree

var assertions := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sfx = root.get_node("UiSfx") as Node
	_check(sfx._voices.is_empty(), "headless runs keep the audio backend inert")
	var stream: AudioStreamWAV = sfx._make_stream(PackedFloat32Array([420.0, 630.0]), 0.055, 0.19, 34.0)
	_check(stream is AudioStreamWAV, "sound service generates a WAV stream without external assets")
	_check(stream.mix_rate == 22050 and stream.data.size() > 100, "generated cue has valid audible PCM data")
	sfx.enabled = false
	sfx.selection()
	_check(sfx._voices.is_empty(), "disabled headless sound service remains inert")
	print("UI SFX: %d assertions / %d FAIL" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)