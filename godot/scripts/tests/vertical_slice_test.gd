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
		"reform": {"active": null, "objectives": [{"id": "reduce_regional_inequality", "name": "Reduce regional inequality", "portfolio": "Interior", "body": "Close the pressure gap.", "score": 0.72, "urgency": "Urgent"}]},
		"dispatches": ["PRESENTATION FIXTURE — figures and briefing text are synthetic, not a campaign.", "Select a region on the map or use the arrow keys while the map has focus."]}

class FakeBridge:
	extends Node
	signal response_received(request_id: int, payload: Dictionary)
	signal bridge_failed(message: String)

	const MAX_RECONNECT_ATTEMPTS := 3

	var requests: Array[Dictionary] = []
	var _initial: Dictionary
	var _state: Dictionary
	var _saved: Dictionary = {}
	var _next_id := 1
	# Test-scripted respawn behaviour, mirroring simulation_bridge.gd's real
	# process-restart contract without spawning Python.
	var _reconnect_attempts := 0
	var scripted_reconnect_failures := 0

	func _init(value: Dictionary) -> void:
		_initial = value.duplicate(true)
		_state = _initial.duplicate(true)

	func can_reconnect() -> bool:
		return _reconnect_attempts < MAX_RECONNECT_ATTEMPTS

	func reconnect() -> bool:
		if not can_reconnect():
			return false
		_reconnect_attempts += 1
		if scripted_reconnect_failures > 0:
			scripted_reconnect_failures -= 1
			bridge_failed.emit.call_deferred("Fake worker failed to restart.")
			return false
		return true

	func request(command: String, args: Dictionary = {}) -> int:
		var request_id := _next_id
		_next_id += 1
		requests.append({"id": request_id, "command": command, "args": args.duplicate(true)})
		var payload: Dictionary = {}
		var ok := true
		match command:
			"new_campaign":
				_state = _initial.duplicate(true)
				payload = {"state": _state.duplicate(true)}
			"advance_day":
				_state["date"]["day_index"] += 1
				_state["date"]["day"] += 1
				_state["date"]["text"] = "%d March 1993" % _state["date"]["day"]
				payload = {"state": _state.duplicate(true)}
			"adopt_objective":
				_state["reform"]["active"] = {"objective_id": args.get("objective_id", ""), "name": "Reduce regional inequality"}
				payload = {"result": {"success": true, "message": "Objective adopted."}, "state": _state.duplicate(true)}
			"save":
				_saved = _state.duplicate(true)
				payload = {"state": _state.duplicate(true)}
			"load":
				if _saved.is_empty():
					ok = false
				else:
					_state = _saved.duplicate(true)
					payload = {"state": _state.duplicate(true)}
			"shutdown":
				payload = {"shutdown": true}
			_:
				ok = false
		var response := {"version": 1, "id": request_id, "ok": ok}
		if ok:
			response["payload"] = payload
		else:
			response["error"] = {"code": "bad_request", "message": "Fake rejected command."}
		_reply.call_deferred(request_id, response)
		return request_id

	func _reply(request_id: int, response: Dictionary) -> void:
		_reconnect_attempts = 0
		response_received.emit(request_id, response)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
	return condition

func _bridge_contract_checks() -> bool:
	var bridge_script = load("res://scripts/bridge/simulation_bridge.gd")
	var resolver = bridge_script.new()
	var prior_override := OS.get_environment("ARDENIA_PYTHON_EXECUTABLE")
	OS.set_environment("ARDENIA_PYTHON_EXECUTABLE", "")
	var executable: String = resolver._resolve_python(ProjectSettings.globalize_path("res://..").simplify_path())
	OS.set_environment("ARDENIA_PYTHON_EXECUTABLE", prior_override)
	resolver.free()
	if not _check(executable.is_absolute_path() and FileAccess.file_exists(executable), "Default Python resolver finds an absolute worktree-compatible executable"):
		return false

	var malformed := [
		{"version": 1, "id": 1, "payload": {}},
		{"version": 1, "id": 1, "ok": "yes", "payload": {}},
		{"version": 1, "id": 1, "ok": true},
		{"version": 1, "id": 1, "ok": true, "payload": []},
		{"version": 1, "id": 1, "ok": false, "error": []},
		{"version": 1, "id": 1, "ok": false, "error": {"code": 4, "message": "bad"}},
		{"version": 1, "id": 1, "ok": false, "error": {"code": "bad"}},
		{"version": 1, "id": 1, "ok": true, "payload": {}, "extra": true},
	]
	for response in malformed:
		var bridge = bridge_script.new()
		var failures: Array[String] = []
		var replies: Array[Dictionary] = []
		bridge.bridge_failed.connect(func(message: String): failures.append(message))
		bridge.response_received.connect(func(_id: int, reply: Dictionary): replies.append(reply))
		bridge._pending[1] = "snapshot"
		bridge._parse_response(JSON.stringify(response))
		if not _check(bridge._failed and failures.size() == 1 and replies.is_empty(), "Malformed response fails before emission: " + JSON.stringify(response)):
			bridge.free()
			return false
		bridge.free()
	var bridge = bridge_script.new()
	var replies: Array[Dictionary] = []
	bridge.response_received.connect(func(_id: int, reply: Dictionary): replies.append(reply))
	bridge._pending[2] = "snapshot"
	bridge._parse_response(JSON.stringify({"version": 1, "id": 2, "ok": true, "payload": {"state": {}}}))
	if not _check(replies.size() == 1 and not bridge._failed, "Complete protocol response emits once"):
		bridge.free()
		return false
	bridge.free()
	bridge = bridge_script.new()
	replies = []
	bridge.response_received.connect(func(_id: int, reply: Dictionary): replies.append(reply))
	bridge._pending[3] = "load"
	bridge._parse_response(JSON.stringify({"version": 1, "id": 3, "ok": false, "error": {"code": "bad_request", "message": "No save."}}))
	if not _check(replies.size() == 1 and not bridge._failed, "Complete protocol failure envelope emits once"):
		bridge.free()
		return false
	bridge.free()
	print("PASS: default Python resolution and strict response-envelope validation")
	return true

func _run() -> void:
	if not _bridge_contract_checks():
		return
	if not _check(ResourceLoader.exists("res://scenes/main.tscn"), "main.tscn exists"):
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	var fake_bridge := FakeBridge.new(fixture())
	root.add_child(fake_bridge)
	scene.set_bridge(fake_bridge)
	root.add_child(scene)
	for frame in range(3):
		await process_frame
	if not _check(fake_bridge.requests.size() == 1 and fake_bridge.requests[0]["command"] == "new_campaign", "Startup requests a live campaign through the injected bridge"):
		return
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
	print("PASS: required scene nodes, fake-bridge startup, Vashtera selection and pressure")
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
	var action = brief.find_child("RegionAction")
	if not _check(not action.disabled, "Live objective action is enabled when idle"):
		return
	action.pressed.emit()
	if not _check(action.disabled and fake_bridge.requests[-1]["command"] == "adopt_objective", "Objective command disables mutating controls in flight"):
		return
	await process_frame
	await process_frame
	if not _check(scene.snapshot["reform"]["active"]["objective_id"] == "reduce_regional_inequality", "Objective response replaces the displayed snapshot"):
		return
	var play = scene.find_child("PlayButton")
	play.pressed.emit()
	scene._process(2.0)
	if not _check(play.disabled and fake_bridge.requests[-1]["command"] == "advance_day", "Running clock submits one advance_day request"):
		return
	await process_frame
	await process_frame
	if not _check(scene.snapshot["date"]["day_index"] == 1, "Clock response advances the displayed day"):
		return
	var save_event := InputEventAction.new()
	save_event.action = "save"
	save_event.pressed = true
	scene._unhandled_key_input(save_event)
	await process_frame
	await process_frame
	scene._process(2.0)
	await process_frame
	await process_frame
	if not _check(scene.snapshot["date"]["day_index"] == 2, "Campaign advances after save"):
		return
	var load_event := InputEventAction.new()
	load_event.action = "load"
	load_event.pressed = true
	scene._unhandled_key_input(load_event)
	await process_frame
	await process_frame
	if not _check(fake_bridge.requests[-1]["command"] == "load" and scene.snapshot["date"]["day_index"] == 1 and scene.snapshot["reform"]["active"]["objective_id"] == "reduce_regional_inequality", "Named-slot load restores date and objective"):
		return
	print("PASS: fake bridge exercises objective, clock, save and load without spawning Python")
	scene.apply_snapshot({})
	if not _check(brief.find_child("PressureValue").text == "—" and scene.find_child("NextDecision").disabled and map.regions.is_empty(), "Missing data clears stale values and decisions"):
		return
	print("PASS: empty snapshot clears stale state; fake bridge only")

	# --- Bounded bridge-failure recovery (G1 finding: no path back except
	# a full app restart) ---
	scene.apply_snapshot(fixture())
	fake_bridge._saved = fixture()
	fake_bridge.scripted_reconnect_failures = 1
	fake_bridge.bridge_failed.emit("Fake worker crashed.")
	await process_frame
	if not _check(scene.find_child("BridgeFailure", true, false) != null
			and scene.find_child("ReconnectButton", true, false) != null,
			"Recoverable failure shows a blocking error with a Reconnect control"):
		return
	scene.find_child("ReconnectButton", true, false).pressed.emit()
	await process_frame
	if not _check(scene.find_child("BridgeFailure", true, false) != null
			and scene.find_child("ReconnectButton", true, false) != null,
			"A failed respawn attempt re-shows the recoverable error, not a crash"):
		return
	scene.find_child("ReconnectButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	if not _check(scene.find_child("BridgeFailure", true, false) == null
			and fake_bridge.requests[-1]["command"] == "load",
			"A successful respawn clears the error and resumes via load, not the stale cache"):
		return
	if not _check(scene.snapshot == fake_bridge._saved,
			"Recovered state is the client's own last save, not whatever was on screen when the worker died"):
		return
	print("PASS: one failed respawn then a successful one recovers through a known save")

	fake_bridge._reconnect_attempts = FakeBridge.MAX_RECONNECT_ATTEMPTS
	fake_bridge.bridge_failed.emit("Fake worker crashed again.")
	await process_frame
	if not _check(scene.find_child("BridgeFailure", true, false) != null
			and scene.find_child("ReconnectButton", true, false) == null,
			"Exhausted reconnect attempts show a permanent failure with no retry control"):
		return
	print("PASS: bounded reconnect attempts stop retrying and surface a permanent failure")
	quit(0)
