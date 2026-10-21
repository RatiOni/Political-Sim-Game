extends PanelContainer

# This client formats a read model; it never advances or derives simulation state.
# Native build: the campaign lives in the NativeGame autoload (in-process), so
# every control below calls it directly and renders the returned snapshot —
# there is no request/response round trip and no worker process to recover.
const SAVE_SLOT := "godot_slice"
const SPEED_DELAYS := [1.5, 1.0, 0.65, 0.4, 0.2]


var snapshot: Dictionary = {}
var selected_region_id := "vashtera"
var _decision_index := -1
var _game: Node
var _fatal := false
var _starting := false
var _paused := true
var _speed := 1
var _clock_elapsed := 0.0
var _selected_program_id := ""
var _selected_program_option: Dictionary = {}

func _ready() -> void:
	%ArdeniaMap.region_selected.connect(_select_region)
	find_child("NextDecision").pressed.connect(_next_decision)
	%PlayButton.pressed.connect(_toggle_pause)
	for index in range(5):
		find_child("Speed%d" % (index + 1)).pressed.connect(_set_speed.bind(index + 1))
	%RegionBrief.find_child("RegionAction").pressed.connect(_start_selected_program)
	%RegionBrief.find_child("ProgramChoice").item_selected.connect(_on_program_selected)
	get_window().size_changed.connect(_resize_layout)
	_resize_layout()
	if _game == null:
		_game = get_node_or_null("/root/NativeGame")
	if _game == null:
		_on_fatal_error("NativeGame autoload is missing — cannot start a campaign.")
		return
	if not _game.is_connected("state_changed", _on_state_changed):
		_game.connect("state_changed", _on_state_changed)
	if not _game.is_connected("fatal_error", _on_fatal_error):
		_game.connect("fatal_error", _on_fatal_error)
	find_child("SaveButton").pressed.connect(_do_save)
	find_child("LoadButton").pressed.connect(_do_load)
	if GameFlow.start_mode == "continue":
		# Continue-with-no-save starts a fresh campaign: if this client has
		# no save under SAVE_SLOT, the load fails and _do_load falls back
		# to new_campaign instead of surfacing an error.
		_starting = true
		_do_load()
	else:
		_do_new_campaign()

func _process(delta: float) -> void:
	if _paused or _fatal or snapshot.is_empty():
		return
	_clock_elapsed += delta
	if _clock_elapsed >= SPEED_DELAYS[_speed - 1]:
		_clock_elapsed = 0.0
		var result: Dictionary = _game.advance_day()
		if not result.get("ok", false):
			_set_status("ADVANCE FAILED / %s" % result.get("error", "Unknown error"))
		else:
			var tick_snap: Dictionary = result.get("snapshot", {})
			if tick_snap.is_empty():
				tick_snap = _game.snapshot()
			apply_snapshot(tick_snap)
			_set_status("LIVE SIMULATION / READY")
		_refresh_controls()

func _resize_layout() -> void:
	# Native-size UI keeps 44 px targets and readable type at both acceptance sizes.
	get_window().content_scale_size = get_window().size
	var compact := get_window().size.x < 1500 or get_window().size.y < 850
	find_child("NationalPanel").visible = not compact
	find_child("MapHint").visible = not compact
	%MonthlyReport.custom_minimum_size.y = 88 if compact else 192
	%RegionBrief.find_child("Details").custom_minimum_size.y = 48 if compact else 84
	for name in ["Rule", "PressureHeading", "PressureValue", "Details"]:
		%RegionBrief.find_child(name).visible = not compact
	find_child("Layout").add_theme_constant_override("separation", 12 if compact else 16)
	%MonthlyReport.find_child("DispatchColumn").visible = not compact
	if not snapshot.is_empty():
		_refresh_region()

func apply_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	%DateLabel.text = str(snapshot.get("date", {}).get("text", "Awaiting snapshot"))
	var player: Dictionary = snapshot.get("player", {})
	find_child("OfficeLabel").text = "%s / %s" % [player.get("title", "Office of government"), player.get("name", "—")]
	find_child("StabilityLabel").text = str(snapshot.get("headline", {}).get("stability", "—"))
	var economy: Dictionary = snapshot.get("economy", {})
	var vitals := ["Approval     %s" % _percent(player, "approval"), "Political capital     %s" % str(player.get("political_capital", "—")), ""]
	for metric in [["Growth", "growth"], ["Unemployment", "unemployment"], ["Inflation", "inflation"], ["Debt / GDP", "debt"]]:
		vitals.append("%s     %s" % [metric[0], _percent(economy, metric[1])])
	vitals.append("\nRevenue     %s M\nExpenditure     %s M" % [economy.get("revenue", "—"), economy.get("expenditure", "—")])
	find_child("VitalsText").text = "\n".join(vitals)
	var assembly: Array[String] = []
	for faction in snapshot.get("factions", []):
		assembly.append("%s\n%s seats · %s" % [faction.get("name", "—"), faction.get("seats", "—"), "Coalition" if faction.get("in_coalition", false) else "Opposition"])
	find_child("AssemblyText").text = "\n\n".join(assembly) if not assembly.is_empty() else "No assembly figures received."
	var items = find_child("DecisionItems")
	for child in items.get_children():
		items.remove_child(child)
		child.queue_free()
	var decisions: Array = snapshot.get("decisions", [])
	for decision in decisions:
		var label := Label.new()
		label.text = "%s / %s — %s" % [str(decision.get("tag", "REVIEW")).to_upper(), decision.get("title", "Decision"), decision.get("due_text", "")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		items.add_child(label)
	if decisions.is_empty():
		var label := Label.new()
		label.text = "No decisions waiting."
		items.add_child(label)
	find_child("NextDecision").disabled = decisions.is_empty()
	_decision_index = -1
	%MonthlyReport.find_child("ReportText").text = _lines(snapshot.get("digest", []), "No monthly report yet. Advance a day once connected.")
	%MonthlyReport.find_child("DispatchText").text = _lines(snapshot.get("dispatches", []), "No dispatches this period.")
	%ArdeniaMap.apply_snapshot(snapshot.get("regions", []), selected_region_id)

	_refresh_region()
	_refresh_controls()

func _percent(row: Dictionary, key: String) -> String:
	return "%.1f%%" % (float(row[key]) * 100.0) if row.has(key) else "—"

func _compact_region_status(region: Dictionary) -> String:
	return "P %.0f%% · U %.1f%% · Reach %.0f%%" % [
		float(region.get("pressure", 0.0)) * 100.0,
		float(region.get("unemployment", 0.0)) * 100.0,
		float(region.get("state_reach", 0.0)) * 100.0,
	]

func _lines(rows: Array, empty_text: String) -> String:
	var lines: Array[String] = []
	for row in rows:
		lines.append(str(row))
	return "\n\n".join(lines) if not lines.is_empty() else empty_text

func _select_region(region_id: String) -> void:
	selected_region_id = region_id
	_refresh_region()

func _refresh_region() -> void:
	var choice: OptionButton = %RegionBrief.find_child("ProgramChoice")
	choice.clear()
	_selected_program_id = ""
	_selected_program_option = {}
	%RegionBrief.find_child("RegionName").text = selected_region_id.capitalize()
	%RegionBrief.find_child("RegionId").text = selected_region_id
	%RegionBrief.find_child("PressureValue").text = "—"
	%RegionBrief.find_child("RegionMetrics").text = "No regional snapshot received."
	%RegionBrief.find_child("ProgrammeStatus").text = "Select a region to review available programmes."
	for region in snapshot.get("regions", []):
		if region.get("id") != selected_region_id:
			continue
		%RegionBrief.find_child("RegionName").text = str(region.get("name", selected_region_id.capitalize()))
		%RegionBrief.find_child("PressureValue").text = "%.0f%%" % (float(region["pressure"]) * 100.0) if region.has("pressure") else "—"
		%RegionBrief.find_child("RegionMetrics").text = "Unemployment    %s\n\nState reach    %s" % [_percent(region, "unemployment"), _percent(region, "state_reach")]
		var active: Variant = region.get("active_program")
		if active is Dictionary:
			var active_text := "%s\nMonth %d of %d · %.0f M/month" % [active.get("name", "Active programme"), int(active.get("months_active", 0)) + 1, active.get("duration", 0), active.get("monthly_cost", 0.0)]
			if get_window().size.x < 1500 or get_window().size.y < 850:
				active_text = "%s\n%s" % [_compact_region_status(region), active_text]
			%RegionBrief.find_child("ProgrammeStatus").text = active_text
			break
		var first_eligible := -1
		for option in region.get("program_options", []):
			var index := choice.item_count
			choice.add_item("%s — %.0f PC" % [option.get("short_name", option.get("name", "Programme")), option.get("pc_cost", 0.0)])
			choice.set_item_metadata(index, option.get("id", ""))
			choice.get_popup().set_item_tooltip(index, str(option.get("disabled_reason", option.get("body", ""))))
			if first_eligible < 0 and option.get("eligible", false):
				first_eligible = index
		if first_eligible >= 0:
			choice.select(first_eligible)
			_on_program_selected(first_eligible)
		elif choice.item_count > 0:
			choice.select(0)
			_on_program_selected(0)
		break
	_update_program_controls(not snapshot.is_empty() and not _fatal)


func _on_program_selected(index: int) -> void:
	_selected_program_id = ""
	_selected_program_option = {}
	var choice: OptionButton = %RegionBrief.find_child("ProgramChoice")
	if index < 0 or index >= choice.item_count:
		_update_program_controls(not snapshot.is_empty() and not _fatal)
		return
	var program_id := str(choice.get_item_metadata(index))
	for region in snapshot.get("regions", []):
		if region.get("id") != selected_region_id:
			continue
		for option in region.get("program_options", []):
			if option.get("id") == program_id:
				_selected_program_id = program_id
				_selected_program_option = option
				var reason := str(option.get("disabled_reason", ""))
				var option_text := reason if not reason.is_empty() else "%s · %d months · %.0f M/month" % [option.get("portfolio", ""), option.get("duration", 0), option.get("monthly_cost", 0.0)]
				if get_window().size.x < 1500 or get_window().size.y < 850:
					option_text = "%s\n%s" % [_compact_region_status(region), option_text]
				%RegionBrief.find_child("ProgrammeStatus").text = option_text
				break
	_update_program_controls(not snapshot.is_empty() and not _fatal)


func _update_program_controls(ready: bool) -> void:
	var choice: OptionButton = %RegionBrief.find_child("ProgramChoice")
	var action: Button = %RegionBrief.find_child("RegionAction")
	var eligible: bool = ready and not _selected_program_option.is_empty() and bool(_selected_program_option.get("eligible", false))
	choice.disabled = not ready or choice.item_count == 0
	action.disabled = not eligible
	action.text = "Launch — %.0f PC" % _selected_program_option.get("pc_cost", 0.0) if eligible else "Launch programme"
	action.tooltip_text = str(_selected_program_option.get("disabled_reason", ""))

func _next_decision() -> void:
	var decisions: Array = snapshot.get("decisions", [])
	if decisions.is_empty():
		return
	_decision_index = (_decision_index + 1) % decisions.size()
	var region_id := str(decisions[_decision_index].get("region_id", ""))
	if not region_id.is_empty():
		%ArdeniaMap.select_region(region_id)
	var item = find_child("DecisionItems").get_child(_decision_index)
	%DecisionQueue.ensure_control_visible(item)

func _campaign_config() -> Dictionary:
	var seed := GameFlow.pending_seed
	if seed < 0:
		seed = randi()
		GameFlow.pending_seed = seed
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": seed,
	}

func _do_new_campaign() -> void:
	if _fatal:
		return
	_set_status("WORKING / NEW CAMPAIGN")
	var result: Dictionary = _game.new_campaign(_campaign_config())
	if not result.get("ok", false):
		_set_status("NEW CAMPAIGN FAILED / %s" % result.get("error", "Unknown error"))
		_refresh_controls()
		return
	var new_snap: Dictionary = result.get("snapshot", {})
	if new_snap.is_empty():
		new_snap = _game.snapshot()
	apply_snapshot(new_snap)
	_set_status("LIVE SIMULATION / READY")
	_refresh_controls()

func _do_save() -> void:
	if _fatal or snapshot.is_empty():
		return
	var result: Dictionary = _game.save(SAVE_SLOT)
	if not result.get("ok", false):
		_set_status("SAVE FAILED / %s" % result.get("error", "Unknown error"))
	else:
		_set_status("SAVED / READY")
	_refresh_controls()

func _do_load() -> void:
	if _fatal:
		return
	var was_starting := _starting
	var result: Dictionary = _game.load(SAVE_SLOT)
	if not result.get("ok", false):
		if was_starting:
			# The last known save could not be loaded (most likely: this
			# client never saved one). Fall back to a fresh campaign —
			# a second, different known state — rather than retrying the
			# same failing load or falling through to a stale snapshot.
			_starting = false
			_do_new_campaign()
			return
		_set_status("LOAD FAILED / %s" % result.get("error", "Unknown error"))
		_refresh_controls()
		return
	_starting = false
	var load_snap: Dictionary = result.get("snapshot", {})
	if load_snap.is_empty():
		load_snap = _game.snapshot()
	apply_snapshot(load_snap)
	_set_status("LOADED / READY")
	_refresh_controls()

func _on_state_changed(value: Dictionary) -> void:
	apply_snapshot(value)
	_refresh_controls()

func _on_fatal_error(message: String) -> void:
	_fatal = true
	_paused = true
	_starting = false
	_show_blocking_error(message)
	_refresh_controls()

func _toggle_pause() -> void:
	if _fatal:
		return
	_paused = not _paused
	_clock_elapsed = 0.0
	_refresh_controls()

func _set_speed(value: int) -> void:
	if _fatal:
		return
	_speed = clampi(value, 1, 5)
	_refresh_controls()

func _start_selected_program() -> void:
	if _selected_program_id.is_empty():
		return
	var result: Dictionary = _game.start_regional_program(selected_region_id, _selected_program_id)
	if not result.get("ok", false):
		_set_status("PROGRAMME REFUSED / %s" % result.get("error", "Unknown error"))
	else:
		_set_status("PROGRAMME LAUNCHED / READY")
	_refresh_controls()

func _refresh_controls() -> void:
	var ready := not snapshot.is_empty() and not _fatal
	%PlayButton.disabled = not ready
	%PlayButton.text = "Paused" if _paused else "Playing ×%d" % _speed
	for index in range(5):
		var button = find_child("Speed%d" % (index + 1))
		button.disabled = not ready
		button.button_pressed = index + 1 == _speed
	_update_program_controls(ready)
	find_child("SaveButton").disabled = not ready
	find_child("LoadButton").disabled = not ready

func _set_status(message: String) -> void:
	find_child("PreviewStatus").text = message
	find_child("Footer").text = "MINISTERIAL WIRE  /  %s" % message

func _show_blocking_error(message: String) -> void:
	_remove_blocking_error()
	_set_status("NATIVE SIMULATION FAILED")
	var blocker := ColorRect.new()
	blocker.name = "FatalError"
	blocker.color = Color(0.05, 0.06, 0.06, 0.96)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.name = "FatalErrorBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 48)
	var label := Label.new()
	label.name = "FatalErrorLabel"
	label.text = "SIMULATION UNAVAILABLE\n\n%s\n\nThis is a native-state failure with no worker to retry. Restart the application." % message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	blocker.add_child(box)
	add_child(blocker)

func _remove_blocking_error() -> void:
	var existing := find_child("FatalError", true, false)
	if existing == null:
		return
	existing.get_parent().remove_child(existing)
	existing.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("next_decision"):
		_next_decision()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("save"):
		_do_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("load"):
		_do_load()
		get_viewport().set_input_as_handled()
	else:
		for index in range(5):
			if event.is_action_pressed("speed_%d" % (index + 1)):
				_set_speed(index + 1)
				get_viewport().set_input_as_handled()
				return
