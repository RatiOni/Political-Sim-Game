extends SceneTree

# Deliberately synthetic presentation data. Never a campaign or engine substitute.
static func fixture() -> Dictionary:
	return {
		"date": {"text": "1 March 1993", "year": 1993, "month": 3, "day": 1, "day_index": 0, "turn": 0},
		"player": {"name": "Alexei Varen", "title": "Prime Minister", "party_id": "liberal_democrats", "in_government": true, "approval": 0.54, "political_capital": 42.0},
		"headline": {"stability": "Fragile", "attention_spent": 0},
		"economy": {"growth": -0.024, "unemployment": 0.137, "inflation": 0.186, "debt": 0.64, "revenue": 1200, "expenditure": 1380},
		"regions": [
			{"id": "anera", "pressure": 0.32, "unemployment": 0.11, "state_reach": 0.55},
			{"id": "darev", "pressure": 0.61, "unemployment": 0.14, "state_reach": 0.43},
			{"id": "karsen", "pressure": 0.46, "unemployment": 0.12, "state_reach": 0.56},
			{"id": "kelvet", "pressure": 0.28, "unemployment": 0.09, "state_reach": 0.68},
			{"id": "orvena", "pressure": 0.44, "unemployment": 0.13, "state_reach": 0.61},
			{"id": "sela", "pressure": 0.38, "unemployment": 0.12, "state_reach": 0.48},
			{"id": "vashtera", "pressure": 0.62, "unemployment": 0.15, "state_reach": 0.72},
			{"id": "vetrenka", "pressure": 0.84, "unemployment": 0.24, "state_reach": 0.18},
			{"id": "zavost", "pressure": 0.57, "unemployment": 0.17, "state_reach": 0.59}],
		"factions": [
			{"id": "liberal_democrats", "name": "Liberal Democrats", "seats": 92, "support": 0.31, "loyalty": 0.7, "in_coalition": true, "color": "#b9a16e"},
			{"id": "agrarians", "name": "Agrarian Union", "seats": 64, "support": 0.21, "loyalty": 0.6, "in_coalition": true, "color": "#829582"},
			{"id": "workers", "name": "Workers' Front", "seats": 88, "support": 0.29, "loyalty": 0.4, "in_coalition": false, "color": "#b86b5b"}],
		"decisions": [{"id": "fixture_review", "priority": 1, "tag": "REVIEW", "title": "Regional pressure: Vashtera", "detail": "Review the selected region before choosing an intervention.", "page": "regions", "authority": "Prime Minister", "days_remaining": 3, "due_text": "3 days remaining", "region_id": "vashtera"}],
		"calendar": [], "digest": ["Static report preview. Monthly causes and consequences will be supplied by the Python engine."],
		"reform": {"active": null, "objectives": []},
		"dispatches": ["PRESENTATION FIXTURE — figures and briefing text are synthetic, not a campaign.", "Select a region on the map or use the arrow keys while the map has focus."]}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
	return condition

func _run() -> void:
	if not _check(ResourceLoader.exists("res://scenes/main.tscn"), "main.tscn exists"):
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for required in ["DateLabel", "PlayButton", "SpeedControls", "DecisionQueue", "ArdeniaMap", "RegionBrief", "MonthlyReport"]:
		if not _check(scene.find_child(required, true, false) != null, "Required node: " + required):
			return
	scene.apply_snapshot(fixture())
	var map = scene.find_child("ArdeniaMap", true, false)
	map.select_region("vashtera")
	var brief = scene.find_child("RegionBrief", true, false)
	if not _check(brief.find_child("RegionId").text == "vashtera", "Selected region id is displayed"):
		return
	if not _check(brief.find_child("PressureValue").text == "62%", "Selected region pressure comes from snapshot"):
		return
	print("PASS: required scene nodes, static snapshot, Vashtera selection and pressure")
	var updated := fixture()
	updated["regions"][6]["pressure"] = 0.77
	scene.apply_snapshot(updated)
	if not _check(brief.find_child("PressureValue").text == "77%" and is_equal_approx(map.regions["vashtera"]["pressure"], 0.77), "Brief and map refresh from a replacement snapshot"):
		return
	scene.apply_snapshot(fixture())
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
		scene.find_child("NextDecision").pressed.emit()
		if not _check(map.selected_id == "vashtera", "Next decision selects its associated region"):
			return
		for button in scene.find_children("*", "Button", true, false):
			if not _check(button.size.y >= 44.0, "44 px target: " + button.name):
				return
		print("PASS: %dx%d viewport bounds, non-overlap, hit testing, Tab/arrow/pointer/hover/decision selection, 44 px controls" % [dimensions.x, dimensions.y])
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-dir="):
				if not _check(DisplayServer.get_name() != "headless", "Screenshot requires a rendering display"):
					return
				await RenderingServer.frame_post_draw
				var path := argument.trim_prefix("--capture-dir=").path_join("ardenia-%dx%d.png" % [dimensions.x, dimensions.y])
				if not _check(root.get_texture().get_image().save_png(path) == OK, "Save screenshot " + path):
					return
				print("CAPTURE: " + path)
	scene.apply_snapshot({})
	if not _check(brief.find_child("PressureValue").text == "—" and scene.find_child("NextDecision").disabled and map.regions.is_empty(), "Missing data clears stale values and decisions"):
		return
	print("PASS: empty snapshot clears stale state; no simulation worker started")
	quit(0)
