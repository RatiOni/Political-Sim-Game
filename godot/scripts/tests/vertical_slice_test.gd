extends SceneTree

const APP_SLOT := "test_vertical_slice"
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
	scene.save_slot = APP_SLOT
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
	for required in ["DateLabel", "PlayButton", "SpeedControls", "DecisionQueue", "ArdeniaMap", "RegionBrief", "MonthlyReport", "BudgetButton", "BudgetPanel", "BudgetRows", "BudgetSummary", "BudgetProjection", "LobbyChoice", "LobbyButton", "ProposeBudgetButton", "VoteBudgetButton", "WithdrawBudgetButton", "CloseBudgetButton", "LegislationButton", "LegislationPanel", "BillChoice", "BillTitle", "BillDescription", "BillEffects", "BillProjection", "ProposeBillButton", "VoteBillButton", "WithdrawBillButton", "CloseLegislationButton"]:
		if not _check(scene.find_child(required, true, false) != null, "Required node: " + required):
			return
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
		var budget_panel: Control = scene.find_child("BudgetPanel", true, false)
		scene.find_child("BudgetButton", true, false).pressed.emit()
		await process_frame
		if not _check(budget_panel.is_visible_in_tree()
				and not scene.find_child("NationalPanel", true, false).visible
				and not scene.find_child("MapPanel", true, false).visible
				and not brief.visible,
				"Budget view replaces the national/map/region body at " + str(dimensions)):
			return
		if not _check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(budget_panel.get_global_rect()),
				"Budget panel stays in viewport at " + str(dimensions)):
			return
		var budget_rows: VBoxContainer = scene.find_child("BudgetRows", true, false)
		var envelope_choices := budget_rows.find_children("Adjustment_*", "HSlider", true, false)
		if not _check(budget_rows.get_child_count() == 8 and envelope_choices.size() == 8,
				"Budget panel renders all eight backend envelope controls at " + str(dimensions)):
			return
		for budget_control_name in ["CloseBudgetButton", "LobbyChoice", "LobbyButton",
				"ProposeBudgetButton", "VoteBudgetButton", "WithdrawBudgetButton"]:
			var budget_control: Control = scene.find_child(budget_control_name, true, false)
			if not _check(budget_control.size.y >= 44.0
					and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(budget_control.get_global_rect()),
					"Budget control is a bounded 44 px target: " + budget_control_name + " at " + str(dimensions)):
				return
		for envelope_choice in envelope_choices:
			if not _check((envelope_choice as HSlider).size.y >= 44.0,
					"Envelope adjustment is a 44 px target at " + str(dimensions)):
				return
		if dimensions == Vector2i(1920, 1080):
			var first_choice := envelope_choices[0] as HSlider
			if not _check(first_choice.max_value > first_choice.min_value, "Budget envelope exposes backend adjustment steps"):
				return
			var original_index := first_choice.value
			var preview_index := first_choice.max_value
			var native_before_preview: Dictionary = native_game.snapshot()
			var summary_before_preview := str(scene.find_child("BudgetSummary", true, false).text)
			var preview_signals := [0]
			var on_preview_signal := func(_value: Dictionary) -> void: preview_signals[0] += 1
			native_game.state_changed.connect(on_preview_signal)
			first_choice.value = preview_index
			await process_frame
			if not _check(native_game.snapshot() == native_before_preview
					and scene.snapshot == native_before_preview
					and preview_signals[0] == 0,
					"UI adjustment requests a non-mutating, non-signalling engine preview"):
				native_game.state_changed.disconnect(on_preview_signal)
				return
			if not _check(str(scene.find_child("BudgetSummary", true, false).text) != summary_before_preview,
					"Engine preview refreshes the displayed fiscal summary"):
				native_game.state_changed.disconnect(on_preview_signal)
				return
			scene._budget_preview["plan"]["year"] = 9999
			scene.apply_snapshot(native_game.snapshot())
			await process_frame
			if not _check(not str(scene.find_child("BudgetSummary", true, false).text).contains("FY 9999"),
					"Snapshot replacement invalidates a stale cached budget preview"):
				native_game.state_changed.disconnect(on_preview_signal)
				return
			first_choice = scene.find_child("BudgetRows", true, false).find_children("Adjustment_*", "HSlider", true, false)[0] as HSlider
			first_choice.value = original_index
			await process_frame
			native_game.state_changed.disconnect(on_preview_signal)
			if not _check(native_game.snapshot() == native_before_preview and preview_signals[0] == 0,
					"Restoring the adjustment is also preview-only"):
				return
		scene.find_child("CloseBudgetButton", true, false).pressed.emit()
		await process_frame
		if not _check(not budget_panel.visible
				and scene.find_child("MapPanel", true, false).is_visible_in_tree()
				and brief.is_visible_in_tree(),
				"Closing the budget restores the regional body at " + str(dimensions)):
			return
		scene.find_child("LegislationButton", true, false).pressed.emit()
		await process_frame
		var legislation_panel: Control = scene.find_child("LegislationPanel", true, false)
		if not _check(legislation_panel.is_visible_in_tree()
				and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(legislation_panel.get_global_rect()),
				"Legislation panel replaces the body and stays in viewport at " + str(dimensions)):
			return
		var bill_choice: OptionButton = scene.find_child("BillChoice", true, false)
		if not _check(bill_choice.item_count == 10 and bill_choice.size.y >= 44.0,
				"Legislation panel renders all ten authored bills at " + str(dimensions)):
			return
		for control_name in ["CloseLegislationButton", "BillChoice", "LobbyButton",
				"ProposeBillButton", "VoteBillButton", "WithdrawBillButton"]:
			var law_control: Control = scene.find_child(control_name, true, false)
			if not _check(law_control.size.y >= 44.0
					and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(law_control.get_global_rect()),
					"Legislation control is a bounded 44 px target: " + control_name + " at " + str(dimensions)):
				return
		scene.find_child("CloseLegislationButton", true, false).pressed.emit()
		await process_frame
		if not _check(not legislation_panel.visible and scene.find_child("MapPanel", true, false).is_visible_in_tree(),
				"Closing legislation restores the regional body at " + str(dimensions)):
			return
		if dimensions == Vector2i(1280, 720):
			var compact_region: Dictionary = {}
			for region in scene.snapshot["regions"]:
				if region.get("id") == map.selected_id:
					compact_region = region
					break
			var compact_status := str(brief.find_child("ProgrammeStatus").text)
			if not _check(compact_status.contains("P %.0f%%" % (float(compact_region["pressure"]) * 100.0))
					and compact_status.contains("U %.1f%%" % (float(compact_region["unemployment"]) * 100.0))
					and compact_status.contains("Reach %.0f%%" % (float(compact_region["state_reach"]) * 100.0)),
					"1920-to-1280 resize preserves live regional metrics in the compact status"):
				return
		# A status line must never widen the dashboard. A Label without
		# clip_text reports its full text width as a minimum and propagates it
		# up to the window, so resolving a decision with a wordy message grew
		# the scene past the viewport and clipped the UI off both edges. This
		# only reproduces at 1920, because compact mode hides the status.
		var width_before: float = scene.get_combined_minimum_size().x
		scene._set_status("DECIDED / " + "Respond in kind. Another incident on the Vetrenka line. ".repeat(4))
		await process_frame
		await process_frame
		if not _check(is_equal_approx(scene.get_combined_minimum_size().x, width_before)
				and scene.size.is_equal_approx(Vector2(dimensions)),
				"A wordy status does not widen the dashboard at %s (minimum %s -> %s, scene %s)"
				% [dimensions, width_before, scene.get_combined_minimum_size().x, scene.size]):
			return
		scene._set_status("LIVE SIMULATION / READY")
		await process_frame
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
		if not _check(map.region_at(map.map_to_local(Vector2(0.55, 0.48))) == "vashtera" and map.region_at(Vector2.ZERO).is_empty(), "Shared map transform hit-tests land and sea"):
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
		motion.position = map.global_position + map.map_to_local(Vector2(0.55, 0.48))
		root.push_input(motion)
		await process_frame
		if not _check(map.hovered_id == "vashtera", "Pointer hover uses the shared transform"):
			return
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = map.global_position + map.map_to_local(Vector2(0.55, 0.48))
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
	scene.find_child("LegislationButton", true, false).pressed.emit()
	await process_frame
	var real_bill_choice: OptionButton = scene.find_child("BillChoice", true, false)
	var telecom_bill_index := -1
	for index in range(real_bill_choice.item_count):
		var bill_meta: Variant = real_bill_choice.get_item_metadata(index)
		if bill_meta is Dictionary and bill_meta.get("id") == "telecom_privatization_act":
			telecom_bill_index = index
			break
	if not _check(telecom_bill_index >= 0, "A non-first telecom bill appears in the real legislation catalogue"):
		return
	var before_law_preview: Dictionary = native_game.snapshot()
	real_bill_choice.select(telecom_bill_index)
	real_bill_choice.item_selected.emit(telecom_bill_index)
	await process_frame
	if not _check(native_game.snapshot() == before_law_preview
			and not str(scene.find_child("BillProjection", true, false).text).contains("No parliamentary"),
			"Selecting a bill displays an engine preview without mutating campaign state"):
		return
	var law_pc_before := float(scene.snapshot["player"]["political_capital"])
	var propose_law_button: Button = scene.find_child("ProposeBillButton", true, false)
	if not _check(not propose_law_button.disabled, "Fresh government campaign can table legislation"):
		return
	propose_law_button.pressed.emit()
	await process_frame
	var pending_law: Variant = scene.snapshot.get("legislation", {}).get("pending")
	if not _check(pending_law is Dictionary and pending_law.get("id") == "telecom_privatization_act"
			and float(scene.snapshot["player"]["political_capital"]) < law_pc_before,
			"Real legislation panel tables a bill and spends engine-owned political capital"):
		return
	scene.find_child("SaveButton", true, false).pressed.emit()
	await process_frame
	var pending_replacement: Dictionary = native_game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": FIXED_SEED + 7})
	if not _check(pending_replacement.get("ok", false), "A replacement campaign clears memory before pending-law reload"):
		return
	scene.find_child("LoadButton", true, false).pressed.emit()
	await process_frame
	var loaded_choice: OptionButton = scene.find_child("BillChoice", true, false)
	var loaded_meta: Variant = loaded_choice.get_item_metadata(loaded_choice.selected)
	if not _check(loaded_meta is Dictionary
			and loaded_meta.get("id") == "telecom_privatization_act"
			and "Telecom" in str(scene.find_child("BillTitle", true, false).text)
			and not str(scene.find_child("BillProjection", true, false).text).is_empty(),
			"Reloaded pending motion selects and displays the exact non-first bill"):
		return
	var vote_law_button: Button = scene.find_child("VoteBillButton", true, false)
	if not _check(not vote_law_button.disabled, "Tabled legislation can be called to a vote"):
		return
	vote_law_button.pressed.emit()
	await process_frame
	var law_model: Dictionary = scene.snapshot.get("legislation", {})
	if not _check(law_model.get("pending") == null and law_model.get("history", []).size() == 1,
			"Real vote reaches one terminal legislation outcome"):
		return
	var terminal_status := str(law_model.get("history", [])[0].get("status", ""))
	if not _check(terminal_status in ["enacted", "rejected"], "Vote visibly records enacted or rejected"):
		return
	scene.find_child("SaveButton", true, false).pressed.emit()
	await process_frame
	var saved_law_history: Array = law_model.get("history", []).duplicate(true)
	var replacement_result: Dictionary = native_game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": FIXED_SEED + 9})
	if not _check(replacement_result.get("ok", false), "A different native campaign replaces memory before law save reload"):
		return
	scene.find_child("LoadButton", true, false).pressed.emit()
	await process_frame
	if not _check(scene.snapshot.get("legislation", {}).get("history", []) == saved_law_history,
			"Terminal law outcome survives real Save and Load controls"):
		return
	scene.find_child("CloseLegislationButton", true, false).pressed.emit()
	await process_frame
	print("PASS: legislation preview, proposal, vote and save/load run through the real scene")
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
	scene.apply_snapshot({})
	if not _check(brief.find_child("PressureValue").text == "—" and scene.find_child("NextDecision").disabled and map.regions.is_empty(), "Missing data clears stale values and decisions"):
		return
	scene._do_load()
	if not _check(not scene.snapshot.is_empty(), "Reload after state drop succeeds: %s" % scene.find_child("PreviewStatus", true, false).text):
		return
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
	scene.find_child("BudgetButton", true, false).pressed.emit()
	await process_frame
	var proposal_model: Dictionary = scene.snapshot.get("budget", {})
	if not _check(proposal_model.get("default_preview", {}).get("passed", false),
			"The backend projects passage for the unchanged real-scene draft"):
		return
	var propose_button: Button = scene.find_child("ProposeBudgetButton", true, false)
	if not _check(not propose_button.disabled, "Fresh government campaign can table its budget"):
		return
	var proposal_pc_before := float(scene.snapshot["player"]["political_capital"])
	propose_button.pressed.emit()
	await process_frame
	var proposed_budget: Variant = scene.snapshot.get("budget", {}).get("pending")
	if not _check(proposed_budget is Dictionary
			and proposed_budget.get("status") == "proposed"
			and float(scene.snapshot["player"]["political_capital"]) < proposal_pc_before,
			"Real budget panel tables one proposal and spends engine-owned political capital"):
		return
	var tabled_choices: Array = scene.find_child("BudgetRows", true, false).find_children("Adjustment_*", "HSlider", true, false)
	if not _check(tabled_choices.all(func(control): return not (control as HSlider).editable),
			"Tabled settlement locks every draft control before the vote"):
		return
	var lobby_choice: OptionButton = scene.find_child("LobbyChoice", true, false)
	var lobby_button: Button = scene.find_child("LobbyButton", true, false)
	if not _check(lobby_choice.item_count > 0 and not lobby_button.disabled,
			"Pending budget exposes an eligible real faction to lobby"):
		return
	var lobbied_faction_id := str((lobby_choice.get_item_metadata(lobby_choice.selected) as Dictionary).get("id", ""))
	var lobby_pc_before := float(scene.snapshot["player"]["political_capital"])
	lobby_button.pressed.emit()
	await process_frame
	proposed_budget = scene.snapshot.get("budget", {}).get("pending")
	if not _check(proposed_budget is Dictionary
			and float(proposed_budget.get("lobbying_bonus", {}).get(lobbied_faction_id, 0.0)) > 0.0
			and float(scene.snapshot["player"]["political_capital"]) < lobby_pc_before,
			"Lobby action mutates the pending plan through NativeGame once"):
		return
	var vote_button: Button = scene.find_child("VoteBudgetButton", true, false)
	if not _check(not vote_button.disabled, "Lobbied proposal can be put to a vote"):
		return
	vote_button.pressed.emit()
	await process_frame
	var approved_budget: Variant = scene.snapshot.get("budget", {}).get("pending")
	if not _check(approved_budget is Dictionary and approved_budget.get("status") == "approved",
			"Real panel vote approves the deterministic settlement"):
		return
	var approved_allocations: Dictionary = approved_budget.get("allocations", {}).duplicate(true)
	var approved_year := int(approved_budget.get("year", 0))
	scene.find_child("SaveButton", true, false).pressed.emit()
	if not _check(FileAccess.file_exists("user://saves/%s.json" % APP_SLOT),
			"Approved pending budget is written through the real save control"):
		return
	native_game.advance_day()
	scene.find_child("LoadButton", true, false).pressed.emit()
	var loaded_pending: Variant = scene.snapshot.get("budget", {}).get("pending")
	if not _check(loaded_pending is Dictionary
			and loaded_pending.get("status") == "approved"
			and loaded_pending.get("allocations", {}) == approved_allocations,
			"Load restores the exact approved pending settlement"):
		return
	scene.find_child("CloseBudgetButton", true, false).pressed.emit()
	var reached_budget_january := false
	for day in range(370):
		var advance_result: Dictionary = native_game.advance_day()
		if not _check(advance_result.get("ok", false),
				"Public daily loop remains valid while advancing approved budget to January"):
			return
		var live_date: Dictionary = advance_result.get("snapshot", {}).get("date", {})
		if int(live_date.get("year", 0)) == approved_year and int(live_date.get("month", 0)) == 1:
			reached_budget_january = true
			break
		if day % 30 == 29:
			await process_frame
	if not _check(reached_budget_january, "Approved settlement reaches its target January"):
		return
	await process_frame
	var january_budget: Dictionary = native_game.snapshot().get("budget", {})
	var active_allocations: Dictionary = january_budget.get("active", {}).get("allocations", {})
	var approved_total := 0.0
	var active_total := 0.0
	for amount in approved_allocations.values():
		approved_total += float(amount)
	for amount in active_allocations.values():
		active_total += float(amount)
	var shares_preserved := active_allocations.keys().size() == approved_allocations.keys().size()
	for key in approved_allocations:
		shares_preserved = shares_preserved and active_allocations.has(key) \
			and is_equal_approx(float(active_allocations[key]) / active_total,
				float(approved_allocations[key]) / approved_total)
	var history: Array = january_budget.get("history", [])
	if not _check(january_budget.get("pending") == null
			and int(january_budget.get("active", {}).get("year", 0)) == approved_year
			and january_budget.get("active", {}).get("source") == "player"
			and shares_preserved
			and not history.is_empty()
			and history[-1].get("allocations", {}) == approved_allocations,
			"January archives the exact settlement and activates its shares before ordinary monthly rescaling"):
		return
	print("PASS: budget preview, proposal, lobby, vote, approved save/load, and January activation")
	native_game.fatal_error.emit("Journey-test fatal.")
	if not _check(scene.find_child("FatalError", true, false) != null
			and scene.find_child("PlayButton", true, false).disabled,
			"fatal_error shows a blocking error and halts the clock"):
		return
	print("PASS: fatal_error display via the blocking-error path")
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
