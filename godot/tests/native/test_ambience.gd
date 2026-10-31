extends SceneTree

var assertions := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ambience = root.get_node("Ambience") as Node
	_check(ambience._beds.is_empty(), "headless runs keep the ambience players inert")
	ambience.set_scene("parliament")
	_check(ambience._scene == "", "headless set_scene is a no-op")
	for id in ["music", "crowd"] + ambience.SCENES:
		var started := Time.get_ticks_msec()
		var b: PackedFloat32Array = ambience.render(id)
		var seconds: float = ambience.MUSIC_SECONDS if id == "music" else ambience.BED_SECONDS
		_check(b.size() == int(seconds * ambience.MIX_RATE), "%s renders a full loop (%d ms)" % [id, Time.get_ticks_msec() - started])
		var steps := 0.0
		var finite := true
		for i in range(1, b.size()):
			steps += absf(b[i] - b[i - 1])
			finite = finite and is_finite(b[i])
		var typical := steps / (b.size() - 1)
		_check(finite and typical > 0.0, "%s is audible and finite" % id)
		_check(absf(b[0] - b[b.size() - 1]) < typical * 6.0, "%s loops without a click at the seam" % id)
	_check(ambience.render("menu").is_empty(), "the menu has no bed, only music")
	var stream: AudioStreamWAV = ambience.to_stream(ambience.render("desk"))
	_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end * 2 == stream.data.size(), "beds become looping WAV streams")
	_check(ambience.scene_for_region(0.2, false) == "town", "a small region is a town")
	_check(ambience.scene_for_region(0.6, false) == "city", "a mid region is a city")
	_check(ambience.scene_for_region(1.1, true) == "metropolis_harbour", "a large port is a metropolis with a harbour")
	var bus := AudioServer.get_bus_index(&"Master")
	var before: Array = [ambience.volume, ambience.muted]
	ambience.set_volume(0.5)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)), "volume drives the master bus")
	ambience.set_muted(true)
	_check(AudioServer.is_bus_mute(bus), "mute silences the master bus")
	var saved := ConfigFile.new()
	_check(saved.load(ambience.SETTINGS_PATH) == OK and saved.get_value("audio", "muted") == true \
		and is_equal_approx(saved.get_value("audio", "volume"), 0.5), "audio settings persist")
	var control := SoundControl.new()
	root.add_child(control)
	_check(control.mute_button.button_pressed and control.mute_button.text == "MUTED", "the control reflects mute")
	ambience.set_muted(false)
	_check(not control.mute_button.button_pressed and is_equal_approx(control.slider.value, 0.5), "controls follow settings changes")
	control.slider.value = 0.3
	_check(is_equal_approx(ambience.volume, 0.3), "the slider sets the volume")
	control.free()
	ambience.set_volume(before[0])
	ambience.set_muted(before[1])
	print("AMBIENCE: %d assertions / %d FAIL" % [assertions, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
