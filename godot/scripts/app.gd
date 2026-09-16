extends PanelContainer

# This client formats a read model; it never advances or derives simulation state.
const SAVE_SLOT := "godot_slice"
const SPEED_DELAYS := [1.5, 1.0, 0.65, 0.4, 0.2]

var snapshot: Dictionary = {}
var selected_region_id := "vashtera"
var _decision_index := -1
var _bridge: Node
var _request_id := 0
var _bridge_dead := false
var _recovering := false
var _paused := true
var _speed := 1
var _clock_elapsed := 0.0
var _selected_objective_id := ""

func set_bridge(value: Node) -> void:
	_bridge = value

func _ready() -> void:
	%ArdeniaMap.region_selected.connect(_select_region)
	find_child("NextDecision").pressed.connect(_next_decision)
	%PlayButton.pressed.connect(_toggle_pause)
	for index in range(5):
		find_child("Speed%d" % (index + 1)).pressed.connect(_set_speed.bind(index + 1))
	%RegionBrief.find_child("RegionAction").pressed.connect(_adopt_selected_objective)
	get_window().size_changed.connect(_resize_layout)
	_resize_layout()
	if _bridge == null:
		_bridge = get_node("/root/SimulationBridge")
	_bridge.connect("response_received", _on_response_received)
	_bridge.connect("bridge_failed", _on_bridge_failed)
	_submit("new_campaign")

func _process(delta: float) -> void:
	if _paused or _request_id != 0 or _bridge_dead or snapshot.is_empty():
		return
	_clock_elapsed += delta
	if _clock_elapsed >= SPEED_DELAYS[_speed - 1]:
		_clock_elapsed = 0.0
		_submit("advance_day")

func _resize_layout() -> void:
	# Native-size UI keeps 44 px targets and readable type at both acceptance sizes.
	get_window().content_scale_size = get_window().size
	var compact := get_window().size.x < 1500 or get_window().size.y < 850
	find_child("NationalPanel").visible = not compact
	find_child("MapHint").visible = not compact
	%MonthlyReport.custom_minimum_size.y = 88 if compact else 192
	%RegionBrief.find_child("Details").custom_minimum_size.y = 48 if compact else 100
	find_child("Layout").add_theme_constant_override("separation", 12 if compact else 16)
	%MonthlyReport.find_child("DispatchColumn").visible = not compact

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
	%MonthlyReport.find_child("ReportText").text = _lines(snapshot.get("digest", []), "No monthly report yet. Advance to a month boundary once connected.")
	%MonthlyReport.find_child("DispatchText").text = _lines(snapshot.get("dispatches", []), "No dispatches this period.")
	%ArdeniaMap.apply_snapshot(snapshot.get("regions", []), selected_region_id)
	var reform: Dictionary = snapshot.get("reform", {})
	var objectives: Array = reform.get("objectives", [])
	_selected_objective_id = str(objectives[0].get("id", "")) if not objectives.is_empty() else ""
	var action = %RegionBrief.find_child("RegionAction")
	if reform.get("active") != null:
		action.text = "Objective adopted"
		_selected_objective_id = ""
	elif not objectives.is_empty():
		action.text = "Adopt: %s" % objectives[0].get("name", "objective")
	else:
		action.text = "No objective available"
	_refresh_region()
	_refresh_controls()

func _percent(row: Dictionary, key: String) -> String:
	return "%.1f%%" % (float(row[key]) * 100.0) if row.has(key) else "—"

func _lines(rows: Array, empty_text: String) -> String:
	var lines: Array[String] = []
	for row in rows:
		lines.append(str(row))
	return "\n\n".join(lines) if not lines.is_empty() else empty_text

func _select_region(region_id: String) -> void:
	selected_region_id = region_id
	_refresh_region()

func _refresh_region() -> void:
	%RegionBrief.find_child("RegionName").text = selected_region_id.capitalize()
	%RegionBrief.find_child("RegionId").text = selected_region_id
	%RegionBrief.find_child("PressureValue").text = "—"
	%RegionBrief.find_child("RegionMetrics").text = "No regional snapshot received."
	for region in snapshot.get("regions", []):
		if region.get("id") == selected_region_id:
			%RegionBrief.find_child("PressureValue").text = "%.0f%%" % (float(region["pressure"]) * 100.0) if region.has("pressure") else "—"
			%RegionBrief.find_child("RegionMetrics").text = "Unemployment    %s\n\nState reach    %s" % [_percent(region, "unemployment"), _percent(region, "state_reach")]
			break

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

func _submit(command: String, args: Dictionary = {}) -> void:
	if _bridge_dead or _request_id != 0:
		return
	_request_id = _bridge.request(command, args)
	_set_status("WORKING / %s" % command.replace("_", " ").to_upper())
	_refresh_controls()

func _on_response_received(request_id: int, response: Dictionary) -> void:
	if request_id != _request_id:
		return
	_request_id = 0
	if not response.get("ok", false):
		if _recovering:
			# The last known save could not be loaded (most likely: this
			# client never saved one). Fall back to a fresh campaign — a
			# second, different known state — rather than retrying the
			# same failing load or falling through to the stale snapshot.
			_recovering = false
			_submit("new_campaign")
			return
		var error: Dictionary = response.get("error", {})
		_set_status("REQUEST FAILED / %s" % error.get("message", "Unknown error"))
		_refresh_controls()
		return
	_recovering = false
	var payload: Dictionary = response.get("payload", {})
	if payload.has("state"):
		apply_snapshot(payload["state"])
	var result: Dictionary = payload.get("result", {})
	_set_status(str(result.get("message", "LIVE SIMULATION / READY")))
	_refresh_controls()

func _on_bridge_failed(message: String) -> void:
	_bridge_dead = true
	_paused = true
	_request_id = 0
	_recovering = false  # explicit: a new failure abandons any recovery in flight
	_show_blocking_error(message, _bridge.can_reconnect())
	_refresh_controls()

## Retry the worker once, bounded by the bridge's own attempt cap. On a
## fresh worker, the old in-memory campaign is gone — it lived only in the
## dead process — so recovery resumes from a known state: this client's own
## last save, or (if none) a brand new campaign. It never keeps showing the
## stale cached snapshot as if nothing happened.
func _attempt_recovery() -> void:
	if not _bridge.reconnect():
		return  # Reconnect failed; bridge_failed already re-fired above us.
	_remove_blocking_error()
	_bridge_dead = false
	# apply_snapshot({}), not a bare assignment: this must clear every
	# rendered widget (date, vitals, map, decisions...), not just the data
	# dict, or the pre-crash dashboard keeps showing on screen — silently
	# stale — for the length of the load round trip.
	apply_snapshot({})
	_recovering = true
	_submit("load", {"slot": SAVE_SLOT})

func _toggle_pause() -> void:
	if _request_id != 0 or _bridge_dead:
		return
	_paused = not _paused
	_clock_elapsed = 0.0
	_refresh_controls()

func _set_speed(value: int) -> void:
	if _request_id != 0 or _bridge_dead:
		return
	_speed = clampi(value, 1, 5)
	_refresh_controls()

func _adopt_selected_objective() -> void:
	if not _selected_objective_id.is_empty():
		_submit("adopt_objective", {"objective_id": _selected_objective_id})

func _refresh_controls() -> void:
	var ready := not snapshot.is_empty() and not _bridge_dead and _request_id == 0
	%PlayButton.disabled = not ready
	%PlayButton.text = "Paused" if _paused else "Playing ×%d" % _speed
	for index in range(5):
		var button = find_child("Speed%d" % (index + 1))
		button.disabled = not ready
		button.button_pressed = index + 1 == _speed
	%RegionBrief.find_child("RegionAction").disabled = not ready or _selected_objective_id.is_empty()

func _set_status(message: String) -> void:
	find_child("PreviewStatus").text = message
	find_child("Footer").text = "MINISTERIAL WIRE  /  %s" % message

func _show_blocking_error(message: String, recoverable: bool) -> void:
	_remove_blocking_error()
	_set_status("SIMULATION BRIDGE FAILED")
	var blocker := ColorRect.new()
	blocker.name = "BridgeFailure"
	blocker.color = Color(0.05, 0.06, 0.06, 0.96)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.name = "BridgeFailureBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 48)
	var label := Label.new()
	label.name = "BridgeFailureLabel"
	var closing := "The application can retry the simulation worker." if recoverable \
		else "No retries remain. Restart the application."
	label.text = "SIMULATION UNAVAILABLE\n\n%s\n\n%s\n\nLog: user://logs/godot_bridge.log" % [message, closing]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	if recoverable:
		var button := Button.new()
		button.name = "ReconnectButton"
		button.text = "Reconnect"
		button.custom_minimum_size = Vector2(160, 44)
		button.pressed.connect(_attempt_recovery)
		box.add_child(button)
	blocker.add_child(box)
	add_child(blocker)

func _remove_blocking_error() -> void:
	var existing := find_child("BridgeFailure", true, false)
	if existing == null:
		return
	existing.get_parent().remove_child(existing)
	existing.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _bridge != null and _bridge.has_method("shutdown"):
			_bridge.shutdown()
		elif _bridge != null:
			_bridge.request("shutdown", {})
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("next_decision"):
		_next_decision()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("save"):
		_submit("save", {"slot": SAVE_SLOT})
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("load"):
		_submit("load", {"slot": SAVE_SLOT})
		get_viewport().set_input_as_handled()
	else:
		for index in range(5):
			if event.is_action_pressed("speed_%d" % (index + 1)):
				_set_speed(index + 1)
				get_viewport().set_input_as_handled()
				return
