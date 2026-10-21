extends SceneTree

# Post-bridge journey test: drives the real menu/app scenes through the real
# NativeGame autoload (fixed seed 424242 — no FakeBridge, no Python worker)
# and asserts the same journey: startup, region selection, time advance,
# save, quit-equivalent state drop, reload restoration, and a real regional
# programme from launch through monthly delivery and continued post-load work.

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
	var live_pressure := 0.0
	for r in (native_game.snapshot()["regions"] as Array):
		if (r as Dictionary).get("id") == "vashtera":
			live_pressure = float((r as Dictionary).get("pressure", 0.0))
	if not _check(brief.find_child("PressureValue").text == "%d%%" % int(round(live_pressure * 100.0)),
			"Pressure reads the live seeded value (regional layer is native since Task 8)"):
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
	var choice: OptionButton = brief.find_child("ProgramChoice")
	var action: Button = brief.find_child("RegionAction")
	var security_index := -1
	var customs_index := -1
	for index in range(choice.item_count):
		if str(choice.get_item_metadata(index)) == "security_stabilisation":
			security_index = index
		if str(choice.get_item_metadata(index)) == "customs_enforcement":
			customs_index = index
	if not _check(customs_index >= 0, "Incompatible programmes remain inspectable"):
		return
	choice.select(customs_index)
	choice.item_selected.emit(customs_index)
	if not _check(action.disabled and "not available" in brief.find_child("ProgrammeStatus").text,
			"An ineligible choice shows the engine-supplied reason and cannot launch"):
		return
	if not _check(security_index >= 0, "Security stabilisation appears in the engine-supplied programme choices"):
		return
	choice.select(security_index)
	choice.item_selected.emit(security_index)
	if not _check(not action.disabled, "An eligible programme enables the 44 px launch action"):
		return
	var pc_before := float(scene.snapshot["player"]["political_capital"])
	action.pressed.emit()
	var anera: Dictionary = {}
	for region in scene.snapshot["regions"]:
		if region.get("id") == "anera":
			anera = region
			break
	if not _check(float(scene.snapshot["player"]["political_capital"]) == pc_before - 11.0
			and anera.get("active_program") is Dictionary
			and anera["active_program"].get("program_id") == "security_stabilisation"
			and action.disabled,
			"Launching through the real panel spends PC once and shows the active commitment"):
		return
	print("PASS: regional programme launches through the real NativeGame action")
	var play = scene.find_child("PlayButton")
	play.pressed.emit()
	scene._process(2.0)
	if not _check(scene.snapshot["date"]["day_index"] == 1
			and str(scene.snapshot["date"]["text"]) == "2 Mar 1993",
			"Running clock advances one native day"):
		return
	play.pressed.emit()
	print("PASS: pause/speed clock calls advance_day directly")
	var before_delivery := anera.duplicate(true)
	var first_month_rolled := false
	for day in range(32):
		if native_game.advance_day().get("month_rolled", false):
			first_month_rolled = true
			break
	if not _check(first_month_rolled, "The public daily loop reaches the first programme month"):
		return
	scene.apply_snapshot(native_game.snapshot())
	for region in scene.snapshot["regions"]:
		if region.get("id") == "anera":
			anera = region
			break
	if not _check(anera["active_program"].get("months_active") == 1
			and (not is_equal_approx(float(anera["pressure"]), float(before_delivery["pressure"]))
				or not is_equal_approx(float(anera["unemployment"]), float(before_delivery["unemployment"]))
				or not is_equal_approx(float(anera["state_reach"]), float(before_delivery["state_reach"]))),
			"The real scene shows one delivered month and a changed regional metric"):
		return
	print("PASS: programme delivery is visible through the real scene snapshot")
	var save_event := InputEventAction.new()
	save_event.action = "save"
	save_event.pressed = true
	scene._unhandled_key_input(save_event)
	if not _check(FileAccess.file_exists("user://saves/%s.json" % APP_SLOT),
			"Save shortcut writes the named slot"):
		return
	var saved_date: Dictionary = scene.snapshot["date"].duplicate(true)
	var second_month_rolled := false
	for day in range(32):
		if native_game.advance_day().get("month_rolled", false):
			second_month_rolled = true
			break
	if not _check(second_month_rolled, "Campaign reaches another monthly pulse after save"):
		return
	scene.apply_snapshot(native_game.snapshot())
	for region in scene.snapshot["regions"]:
		if region.get("id") == "anera":
			anera = region
			break
	if not _check(anera["active_program"].get("months_active") == 2,
			"Programme reaches month two after save"):
		return
	var load_event := InputEventAction.new()
	load_event.action = "load"
	load_event.pressed = true
	scene._unhandled_key_input(load_event)
	for region in scene.snapshot["regions"]:
		if region.get("id") == "anera":
			anera = region
			break
	if not _check(scene.snapshot["date"] == saved_date
			and anera["active_program"].get("months_active") == 1,
			"Named-slot load restores the saved programme month"):
		return
	for day in range(32):
		if native_game.advance_day().get("month_rolled", false):
			break
	scene.apply_snapshot(native_game.snapshot())
	for region in scene.snapshot["regions"]:
		if region.get("id") == "anera":
			anera = region
			break
	if not _check(anera["active_program"].get("months_active") == 2,
			"Programme delivery continues after reload"):
		return
	print("PASS: save, load, and continued programme delivery through NativeGame")
	# Quit-equivalent: drop the displayed state entirely, then reload from
	# disk — the relaunch restores the saved campaign, not a blank screen.
	scene.apply_snapshot({})
	if not _check(brief.find_child("PressureValue").text == "—" and scene.find_child("NextDecision").disabled and map.regions.is_empty(), "Missing data clears stale values and decisions"):
		return
	scene._do_load()
	for region in scene.snapshot["regions"]:
		if region.get("id") == "anera":
			anera = region
			break
	if not _check(scene.snapshot["date"] == saved_date
			and anera["active_program"].get("months_active") == 1
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
