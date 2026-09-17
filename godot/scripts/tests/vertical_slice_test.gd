extends SceneTree

# Post-bridge journey test: drives the real menu/app scenes through the real
# NativeGame autoload (fixed seed 424242 — no FakeBridge, no Python worker)
# and asserts the same journey: startup, region selection, time advance,
# save, quit-equivalent state drop, reload restoration. The objective action
# has no native backend yet, so it must read as disabled-with-a-note, never
# as a working control and never as an error.

const APP_SLOT := "godot_slice"
const FIXED_SEED := 424242


static func _wipe_app_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [APP_SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
	return condition


func _autoload_checks() -> bool:
	if not _check(ProjectSettings.has_setting("autoload/NativeGame"),
			"NativeGame is registered as a production autoload"):
		return false
	if not _check(not ProjectSettings.has_setting("autoload/SimulationBridge"),
			"SimulationBridge is no longer a production autoload"):
		return false
	if not _check(root.get_node_or_null("NativeGame") != null,
			"NativeGame singleton is live in the autoload tree"):
		return false
	print("PASS: NativeGame autoload registered, SimulationBridge removed")
	return true


func _run() -> void:
	if not _autoload_checks():
		return
	_wipe_app_slot()
	var game_flow = root.get_node("GameFlow")
	var native_game = root.get_node("NativeGame")
	game_flow.start_mode = "new"
	game_flow.pending_seed = FIXED_SEED
	if not _check(ResourceLoader.exists("res://scenes/main.tscn"), "main.tscn exists"):
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for frame in range(3):
		await process_frame
	if not _check(not scene.snapshot.is_empty(), "Startup applies a native campaign snapshot"):
		return
	if not _check(str(scene.snapshot["date"]["text"]) == "1 Mar 1993",
			"Seed-424242 campaign opens on 1 Mar 1993"):
		return
	if not _check(scene.snapshot == native_game.snapshot(),
			"The displayed snapshot is the NativeGame snapshot"):
		return
	print("PASS: startup starts a native campaign through NativeGame directly")
	for required in ["DateLabel", "PlayButton", "SpeedControls", "DecisionQueue", "ArdeniaMap", "RegionBrief", "MonthlyReport"]:
		if not _check(scene.find_child(required, true, false) != null, "Required node: " + required):
			return
	# Continue-with-no-save starts fresh (the bridge-era recovery path,
	# preserved): with no save on disk, a starting load falls back to a
	# brand new campaign instead of surfacing an error.
	scene._starting = true
	scene._do_load()
	if not _check(scene.snapshot["date"]["day_index"] == 0,
			"A starting load with no save falls back to a fresh campaign"):
		return
	print("PASS: continue-with-no-save starts a fresh campaign")
	scene.apply_snapshot(native_game.snapshot())
	var map = scene.find_child("ArdeniaMap", true, false)
	var brief = scene.find_child("RegionBrief", true, false)
	map.select_region("vashtera")
	if not _check(brief.find_child("RegionId").text == "vashtera", "Selected region id is displayed"):
		return
	if not _check(brief.find_child("PressureValue").text == "—",
			"Pressure reads empty: the regional layer has no native backend yet"):
		return
	print("PASS: Vashtera selection displays through the native snapshot")
	var enriched: Dictionary = native_game.snapshot()
	enriched["regions"] = [{"id": "vashtera", "pressure": 0.77,
		"unemployment": 0.12, "state_reach": 0.5}]
	scene.apply_snapshot(enriched)
	if not _check(brief.find_child("PressureValue").text == "77%" and is_equal_approx(map.regions["vashtera"]["pressure"], 0.77), "Brief and map still refresh from a replacement snapshot"):
		return
	scene.apply_snapshot(native_game.snapshot())
	for action in ["pause", "speed_1", "speed_2", "speed_3", "speed_4", "speed_5", "back", "next_decision", "save", "load"]:
		if not _check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Keyboard binding: " + action):
			return
	print("PASS: snapshot replacement and all 10 configured keyboard actions")
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		for frame in range(4):
			await process_frame
		print("LAYOUT %s: %s" % [dimensions, scene.get_node("Margin/Layout").get_children().map(func(node): return "%s=%s" % [node.name, node.get_combined_minimum_size()])])
		if not _check(scene.size.is_equal_approx(Vector2(dimensions)), "Native-size layout at %s (window %s, scene %s, minimum %s)" % [dimensions, root.size, scene.size, scene.get_combined_minimum_size()]):
			return
		var map_rect: Rect2 = map.get_global_rect()
		for required in ["DateLabel", "PlayButton", "DecisionQueue", "ArdeniaMap", "RegionBrief", "MonthlyReport"]:
			var control = scene.find_child(required, true, false)
			if not _check(control.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(control.get_global_rect()), required + " stays in viewport at " + str(dimensions)):
				return
		for panel_name in ["RegionBrief", "MonthlyReport", "DecisionRail", "Header"]:
			if not _check(not map_rect.intersects(scene.find_child(panel_name, true, false).get_global_rect()), "Map does not overlap " + panel_name):
				return
		if not _check(map.region_at(map._point([55, 48])) == "vashtera" and map.region_at(Vector2.ZERO).is_empty(), "Shared map transform hit-tests land and sea"):
			return
		scene.find_child("NextDecision").grab_focus()
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		root.push_input(tab)
		await process_frame
		if not _check(map.has_focus(), "Tab reaches the map from the decision control"):
			return
		var key := InputEventKey.new()
		key.keycode = KEY_RIGHT
		key.pressed = true
		root.push_input(key)
		await process_frame
		if not _check(map.selected_id != "vashtera" and brief.find_child("RegionId").text == map.selected_id, "Keyboard region selection updates the brief"):
			return
		var motion := InputEventMouseMotion.new()
		motion.position = map.global_position + map._point([55, 48])
		root.push_input(motion)
		await process_frame
		if not _check(map.hovered_id == "vashtera", "Pointer hover uses the shared transform"):
			return
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = map.global_position + map._point([55, 48])
		root.push_input(click)
		click.pressed = false
		root.push_input(click)
		await process_frame
		if not _check(map.selected_id == "vashtera", "Pointer selects Vashtera through transformed geometry"):
			return
		map.select_region("anera")
		if not _check(scene.find_child("NextDecision").disabled,
				"Next decision is disabled while no native decisions exist"):
			return
		for button in scene.find_children("*", "Button", true, false):
			if not _check(button.size.y >= 44.0, "44 px target: " + button.name):
				return
		print("PASS: %dx%d viewport bounds, non-overlap, hit testing, Tab/arrow/pointer/hover, 44 px controls" % [dimensions.x, dimensions.y])
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-dir="):
				if not _check(DisplayServer.get_name() != "headless", "Screenshot requires a rendering display"):
					return
				await RenderingServer.frame_post_draw
				var path := argument.trim_prefix("--capture-dir=").path_join("ardenia-%dx%d.png" % [dimensions.x, dimensions.y])
				if not _check(root.get_texture().get_image().save_png(path) == OK, "Save screenshot " + path):
					return
				print("CAPTURE: " + path)
	# No native backend yet: the objective action must be visibly disabled
	# with its reason attached — never silently dead, never erroring.
	var action = brief.find_child("RegionAction")
	if not _check(action.disabled, "Objective action is disabled with no native backend"):
		return
	if not _check(str(action.tooltip_text).find("native backend") >= 0,
			"The disabled objective control carries its explanatory note"):
		return
	print("PASS: adopt control is disabled-with-note, not silently dead")
	var play = scene.find_child("PlayButton")
	play.pressed.emit()
	scene._process(2.0)
	if not _check(scene.snapshot["date"]["day_index"] == 1
			and str(scene.snapshot["date"]["text"]) == "2 Mar 1993",
			"Running clock advances one native day"):
		return
	print("PASS: pause/speed clock calls advance_day directly")
	var save_event := InputEventAction.new()
	save_event.action = "save"
	save_event.pressed = true
	scene._unhandled_key_input(save_event)
	if not _check(FileAccess.file_exists("user://saves/%s.json" % APP_SLOT),
			"Save shortcut writes the named slot"):
		return
	scene._process(2.0)
	if not _check(scene.snapshot["date"]["day_index"] == 2, "Campaign advances after save"):
		return
	var load_event := InputEventAction.new()
	load_event.action = "load"
	load_event.pressed = true
	scene._unhandled_key_input(load_event)
	if not _check(scene.snapshot["date"]["day_index"] == 1
			and str(scene.snapshot["date"]["text"]) == "2 Mar 1993",
			"Named-slot load restores the saved day"):
		return
	print("PASS: save shortcut, clock advance, and load restoration through NativeGame")
	# Quit-equivalent: drop the displayed state entirely, then reload from
	# disk — the relaunch restores the saved campaign, not a blank screen.
	scene.apply_snapshot({})
	if not _check(brief.find_child("PressureValue").text == "—" and scene.find_child("NextDecision").disabled and map.regions.is_empty(), "Missing data clears stale values and decisions"):
		return
	scene._do_load()
	if not _check(scene.snapshot["date"]["day_index"] == 1
			and str(scene.snapshot["date"]["text"]) == "2 Mar 1993"
			and brief.find_child("RegionId").text == map.selected_id,
			"Reload after a full state drop restores the saved campaign"):
		return
	print("PASS: empty snapshot clears stale state; reload restores the save")
	# Fatal native errors surface through the existing blocking-error path.
	native_game.fatal_error.emit("Journey-test fatal.")
	if not _check(scene.find_child("FatalError", true, false) != null
			and scene.find_child("PlayButton", true, false).disabled,
			"fatal_error shows a blocking error and halts the clock"):
		return
	print("PASS: fatal_error display via the blocking-error path")
	# Menu, last: button presses queue a scene change, so assert
	# synchronously and quit before it can run.
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	menu.find_child("NewCampaignButton", true, false).pressed.emit()
	if not _check(game_flow.start_mode == "new"
			and typeof(game_flow.pending_seed) == TYPE_INT
			and game_flow.pending_seed >= 0,
			"Menu New Campaign arms a fresh mode plus an explicit int seed"):
		return
	menu.find_child("ContinueButton", true, false).pressed.emit()
	if not _check(game_flow.start_mode == "continue",
			"Menu Continue arms continue mode"):
		return
	print("PASS: menu drives GameFlow with an explicit seed, no bridge involved")
	_wipe_app_slot()
	var residue := false
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists("user://saves/%s.json%s" % [APP_SLOT, suffix]):
			residue = true
	if not _check(not residue, "cleanup: no app slot residue remains in user://saves/"):
		return
	quit(0)
