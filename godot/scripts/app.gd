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
var _sfx: Node
var _fatal := false
var _starting := false
var _paused := true
var _speed := 1
var _clock_elapsed := 0.0
var _selected_program_id := ""
var _selected_program_option: Dictionary = {}
var _budget_open := false
var _budget_adjustments := {}
var _budget_preview: Dictionary = {}
var _legislation_open := false
var _situation_open := false
var _selected_event_id := ""
## Situations already seen, so only a genuinely new one pauses the clock.
var _known_situations := {}
var _selected_bill_id := ""
var _bill_preview: Dictionary = {}

func _ready() -> void:
	%ArdeniaMap.region_selected.connect(_select_region)
	find_child("NextDecision").pressed.connect(_next_decision)
	%PlayButton.pressed.connect(_toggle_pause)
	for index in range(5):
		find_child("Speed%d" % (index + 1)).pressed.connect(_set_speed.bind(index + 1))
	%RegionBrief.find_child("RegionAction").pressed.connect(_start_selected_program)
	%RegionBrief.find_child("ProgramChoice").item_selected.connect(_on_program_choice_selected)
	%BudgetButton.pressed.connect(_open_budget)
	%BudgetPanel.find_child("CloseBudgetButton").pressed.connect(_close_budget)
	%BudgetPanel.find_child("ProposeBudgetButton").pressed.connect(_propose_budget)
	%BudgetPanel.find_child("VoteBudgetButton").pressed.connect(_call_budget_vote)
	%BudgetPanel.find_child("WithdrawBudgetButton").pressed.connect(_withdraw_budget)
	%BudgetPanel.find_child("LobbyButton").pressed.connect(_lobby_budget)
	%BudgetPanel.find_child("LobbyChoice").item_selected.connect(_on_budget_lobby_selected)
	%LegislationButton.pressed.connect(_open_legislation)
	%LegislationPanel.find_child("CloseLegislationButton").pressed.connect(_close_legislation)
	%LegislationPanel.find_child("BillChoice").item_selected.connect(_on_bill_choice_selected)
	%LegislationPanel.find_child("ProposeBillButton").pressed.connect(_propose_bill)
	%LegislationPanel.find_child("VoteBillButton").pressed.connect(_call_bill_vote)
	%LegislationPanel.find_child("WithdrawBillButton").pressed.connect(_withdraw_bill)
	%LegislationPanel.find_child("LobbyButton").pressed.connect(_lobby_bill)
	%LegislationPanel.find_child("LobbyChoice").item_selected.connect(_on_bill_lobby_selected)
	%SituationPanel.find_child("CloseSituationButton").pressed.connect(_close_situation)
	get_window().size_changed.connect(_resize_layout)
	_resize_layout()
	_sfx = get_node_or_null("/root/UiSfx")
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
			if bool(result.get("month_rolled", false)):
				_sfx_cue("month_rollover")
		_refresh_controls()

func _resize_layout() -> void:
	# Native-size UI keeps 44 px targets and readable type at both acceptance sizes.
	get_window().content_scale_size = get_window().size
	var compact := get_window().size.x < 1500 or get_window().size.y < 850
	find_child("OfficeLabel").visible = not compact
	find_child("PreviewStatus").visible = not compact
	find_child("NationalPanel").visible = not compact and not _desk_open()
	find_child("MapPanel").visible = not _desk_open()
	%RegionBrief.visible = not _desk_open()
	%BudgetPanel.visible = _budget_open
	%LegislationPanel.visible = _legislation_open
	%SituationPanel.visible = _situation_open
	find_child("MapHint").visible = not compact and not _desk_open()
	%MonthlyReport.custom_minimum_size.y = 88 if compact else 192
	%RegionBrief.find_child("Details").custom_minimum_size.y = 48 if compact else 84
	for name in ["Rule", "PressureHeading", "PressureValue", "Details"]:
		%RegionBrief.find_child(name).visible = not compact
	find_child("Layout").add_theme_constant_override("separation", 12 if compact else 16)
	%MonthlyReport.find_child("DispatchColumn").visible = not compact
	if not snapshot.is_empty():
		if _budget_open:
			_refresh_budget()
		elif _legislation_open:
			_refresh_legislation()
		elif _situation_open:
			_refresh_situation()
		else:
			_refresh_region()

func apply_snapshot(value: Dictionary) -> void:
	var incoming_budget: Dictionary = value.get("budget", {})
	var incoming_pending: Variant = incoming_budget.get("pending")
	var incoming_proposal_year := int(incoming_budget.get("proposal_year", 0))
	var cached_plan: Dictionary = _budget_preview.get("plan", {})
	if incoming_pending is Dictionary or (not cached_plan.is_empty() \
			and int(cached_plan.get("year", 0)) != incoming_proposal_year):
		_reset_budget_draft()
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
	if _budget_open:
		_refresh_budget()
	elif _legislation_open:
		_refresh_legislation()
	elif _situation_open:
		_refresh_situation()
	_notice_new_situations()
	_refresh_controls()

func _sfx_cue(cue: String) -> void:
	if _sfx != null and _sfx.has_method(cue):
		_sfx.call(cue)


func _sfx_result(result: Dictionary, resolve_vote: bool = false) -> void:
	if not bool(result.get("ok", false)):
		_sfx_cue("deny")
		return
	if resolve_vote and not bool(result.get("passed", false)):
		_sfx_cue("deny")
	else:
		_sfx_cue("confirm")

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

func _open_budget() -> void:
	if snapshot.is_empty() or _fatal:
		return
	_sfx_cue("navigation")
	_legislation_open = false
	_situation_open = false
	_budget_open = true
	_budget_adjustments.clear()
	_budget_preview.clear()
	_resize_layout()


func _close_budget() -> void:
	_sfx_cue("navigation")
	_budget_open = false
	_resize_layout()


func _reset_budget_draft() -> void:
	_budget_adjustments.clear()
	_budget_preview.clear()


func _refresh_budget() -> void:
	var model: Dictionary = snapshot.get("budget", {})
	var actions: Dictionary = model.get("actions", {})
	var preview_action: Dictionary = actions.get("preview", {})
	var rows: VBoxContainer = %BudgetPanel.find_child("BudgetRows")
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if not model.get("ok", false):
		var unavailable := Label.new()
		unavailable.text = str(model.get("error", "Budget data is unavailable."))
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(unavailable)
		_set_budget_status(unavailable.text)
		_apply_budget_actions({})
		return

	for envelope in model.get("envelopes", []):
		var envelope_id := str(envelope.get("id", ""))
		var row := VBoxContainer.new()
		row.name = "BudgetRow_%s" % envelope_id
		var top := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  ·  %.0f M" % [envelope.get("name", envelope_id.capitalize()), envelope.get("current", 0.0)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var choice := OptionButton.new()
		choice.name = "Adjustment_%s" % envelope_id
		choice.custom_minimum_size = Vector2(168, 44)
		var selected_index := 0
		var selected_step := float(_budget_adjustments.get(envelope_id, 0.0))
		for step_value in envelope.get("allowed_adjustments", []):
			var step := float(step_value)
			var index := choice.item_count
			choice.add_item(_signed_adjustment(step))
			choice.set_item_metadata(index, step)
			if is_equal_approx(step, selected_step):
				selected_index = index
		choice.select(selected_index)
		choice.disabled = not bool(preview_action.get("eligible", false))
		choice.tooltip_text = str(preview_action.get("disabled_reason", ""))
		choice.item_selected.connect(_on_budget_adjustment.bind(envelope_id, choice))
		top.add_child(label)
		top.add_child(choice)
		row.add_child(top)
		var body := Label.new()
		body.text = str(envelope.get("body", ""))
		body.theme_type_variation = &"Muted"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(body)
		rows.add_child(row)

	var lobby_choice: OptionButton = %BudgetPanel.find_child("LobbyChoice")
	lobby_choice.clear()
	var first_eligible := -1
	for faction in model.get("lobby_factions", []):
		var index := lobby_choice.item_count
		lobby_choice.add_item("%s — %.0f PC" % [faction.get("name", "Faction"), faction.get("cost", 0.0)])
		lobby_choice.set_item_metadata(index, faction)
		var eligible := bool(faction.get("eligible", false))
		lobby_choice.set_item_disabled(index, not eligible)
		lobby_choice.get_popup().set_item_tooltip(index, str(faction.get("disabled_reason", "")))
		if first_eligible < 0 and eligible:
			first_eligible = index
	if lobby_choice.item_count > 0:
		lobby_choice.select(first_eligible if first_eligible >= 0 else 0)

	var preview: Variant = model.get("pending_preview")
	if not (preview is Dictionary):
		preview = _budget_preview if not _budget_preview.is_empty() else model.get("default_preview", {})
	_display_budget_preview(preview as Dictionary)
	_apply_budget_actions(actions)
	_update_budget_lobby_control()
	var pending: Variant = model.get("pending")
	if pending is Dictionary and pending.get("status") == "approved":
		_set_budget_status("Approved for %s; takes effect on 1 January." % pending.get("year", "the next fiscal year"))
	elif pending is Dictionary:
		_set_budget_status("The %s budget is before parliament." % pending.get("year", "next"))
	else:
		_set_budget_status("Adjust the authorised envelopes, then table the plan.")


func _on_budget_adjustment_selected(index: int, envelope_id: String, choice: OptionButton) -> void:
	_sfx_cue("selection")
	_on_budget_adjustment(index, envelope_id, choice)

func _on_budget_adjustment(index: int, envelope_id: String, choice: OptionButton) -> void:
	if index < 0 or index >= choice.item_count:
		return
	var step := float(choice.get_item_metadata(index))
	if is_zero_approx(step):
		_budget_adjustments.erase(envelope_id)
	else:
		_budget_adjustments[envelope_id] = step
	var result: Dictionary = _game.preview_budget(_budget_adjustments)
	if not result.get("ok", false):
		_set_budget_status(str(result.get("error", "The draft could not be previewed.")))
		return
	_budget_preview = result.get("preview", {}).duplicate(true)
	_display_budget_preview(_budget_preview)


func _display_budget_preview(preview: Dictionary) -> void:
	if preview.is_empty():
		%BudgetPanel.find_child("BudgetSummary").text = "No fiscal preview available."
		%BudgetPanel.find_child("BudgetProjection").text = "No parliamentary projection available."
		return
	var plan: Dictionary = preview.get("plan", {})
	%BudgetPanel.find_child("BudgetSummary").text = "FY %s  ·  active %.0f M  ·  proposed %.0f M  ·  revenue %.0f M  ·  balance %+.0f M  ·  %.0f PC" % [
		plan.get("year", "—"), preview.get("active_total", 0.0), preview.get("total", 0.0),
		preview.get("forecast_revenue", 0.0), preview.get("forecast_balance", 0.0),
		preview.get("political_capital_cost", 0.0),
	]
	var faction_lines: Array[String] = []
	for faction in preview.get("breakdown", []):
		faction_lines.append("%s %s/%s" % [faction.get("name", "Faction"), faction.get("votes_for", 0), faction.get("seats", 0)])
	var verdict := "LIKELY PASS" if preview.get("passed", false) else "LIKELY DEFEAT"
	%BudgetPanel.find_child("BudgetProjection").text = "%s  ·  %s for / %s against  ·  %s needed\n%s" % [
		verdict, preview.get("votes_for", 0), preview.get("votes_against", 0),
		preview.get("threshold", 0), "  ·  ".join(faction_lines),
	]
	%BudgetPanel.find_child("ProposeBudgetButton").text = "Table — %.0f PC" % preview.get("political_capital_cost", 0.0)


func _apply_budget_actions(actions: Dictionary) -> void:
	for pair in [["ProposeBudgetButton", "propose"], ["VoteBudgetButton", "vote"], ["WithdrawBudgetButton", "withdraw"]]:
		var button: Button = %BudgetPanel.find_child(pair[0])
		var action: Dictionary = actions.get(pair[1], {})
		button.disabled = not bool(action.get("eligible", false))
		button.tooltip_text = str(action.get("disabled_reason", ""))


func _on_budget_lobby_selected(index: int) -> void:
	_sfx_cue("selection")
	_update_budget_lobby_control(index)

func _update_budget_lobby_control(_index: int = -1) -> void:
	var choice: OptionButton = %BudgetPanel.find_child("LobbyChoice")
	var button: Button = %BudgetPanel.find_child("LobbyButton")
	if choice.item_count == 0 or choice.selected < 0:
		choice.disabled = true
		button.disabled = true
		button.tooltip_text = "No parliamentary faction is available to lobby."
		return
	var faction: Variant = choice.get_item_metadata(choice.selected)
	var eligible := faction is Dictionary and bool(faction.get("eligible", false))
	choice.disabled = false
	button.disabled = not eligible
	button.tooltip_text = "" if eligible else str(faction.get("disabled_reason", ""))


func _propose_budget() -> void:
	var result: Dictionary = _game.propose_budget(_budget_adjustments)
	_set_budget_status(str(result.get("message", "Budget refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _lobby_budget() -> void:
	var choice: OptionButton = %BudgetPanel.find_child("LobbyChoice")
	if choice.selected < 0:
		return
	var faction: Variant = choice.get_item_metadata(choice.selected)
	if not (faction is Dictionary):
		return
	var result: Dictionary = _game.lobby_budget(str(faction.get("id", "")))
	_set_budget_status(str(result.get("message", "Lobbying refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _call_budget_vote() -> void:
	var result: Dictionary = _game.call_budget_vote()
	if result.get("ok", false):
		_set_budget_status("Budget approved." if result.get("passed", false) else "Budget defeated.")
	else:
		_set_budget_status("Vote refused: %s" % result.get("error", "Unknown error"))
	_sfx_result(result, true)


func _withdraw_budget() -> void:
	var result: Dictionary = _game.withdraw_budget()
	_set_budget_status(str(result.get("message", "Withdrawal refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _set_budget_status(message: String) -> void:
	%BudgetPanel.find_child("BudgetActionStatus").text = message


func _signed_adjustment(value: float) -> String:
	if is_zero_approx(value):
		return "No change"
	return "%s%.0f%%" % ["+" if value > 0.0 else "", value * 100.0]

func _open_legislation() -> void:
	if snapshot.is_empty() or _fatal:
		return
	_sfx_cue("navigation")
	_budget_open = false
	_situation_open = false
	_legislation_open = true
	_bill_preview.clear()
	_resize_layout()


func _desk_open() -> bool:
	return _budget_open or _legislation_open or _situation_open


## A situation the player has not yet seen pauses the clock and is
## announced, so it cannot slip past at high speed and lapse unseen.
func _notice_new_situations() -> void:
	var fresh := false
	var live := {}
	for row in snapshot.get("situations", []):
		var id := str(row.get("event_id", ""))
		live[id] = true
		if not _known_situations.has(id):
			fresh = true
	_known_situations = live
	if fresh:
		_paused = true
		_sfx_cue("alert")


func _open_situation(event_id: String) -> void:
	if snapshot.is_empty() or _fatal:
		return
	_sfx_cue("navigation")
	_budget_open = false
	_legislation_open = false
	_situation_open = true
	_selected_event_id = event_id
	_set_situation_status("")
	_resize_layout()


func _close_situation() -> void:
	_sfx_cue("navigation")
	_situation_open = false
	_resize_layout()


func _situation_row() -> Dictionary:
	for row in snapshot.get("situations", []):
		if str(row.get("event_id", "")) == _selected_event_id:
			return row
	return {}


func _refresh_situation() -> void:
	var row := _situation_row()
	var panel = %SituationPanel
	var options_box: VBoxContainer = panel.find_child("Options")
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()
	if row.is_empty():
		panel.find_child("SituationTitle").text = "This situation has been settled."
		panel.find_child("SituationDescription").text = ""
		panel.find_child("SituationMeta").text = ""
		return
	panel.find_child("SituationTitle").text = str(row.get("title", "Situation"))
	panel.find_child("SituationDescription").text = str(row.get("description", ""))
	var months := int(row.get("months_left", 0))
	var deadline := "decide this month or it is decided for you" if months <= 0 \
		else "decide within %d month%s" % [months, "" if months == 1 else "s"]
	var meta := "%s / %s" % [str(row.get("category", "")).to_upper(), deadline]
	if str(row.get("target_country", "")) != "":
		meta += " / concerns %s" % row["target_country"]
	panel.find_child("SituationMeta").text = meta
	for option in row.get("options", []):
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cost := float(option.get("pc_cost", 0.0))
		var label := str(option.get("label", ""))
		if cost > 0.0:
			label += "   · %.0f PC" % cost
		if option.get("is_default", false):
			label += "   · what happens if you do nothing"
		button.text = label
		button.disabled = not option.get("eligible", false)
		button.tooltip_text = str(option.get("disabled_reason", ""))
		button.pressed.connect(_choose_situation_option.bind(str(option.get("id", ""))))
		card.add_child(button)
		var detail := Label.new()
		detail.theme_type_variation = &"Muted"
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var text := str(option.get("description", ""))
		var reason := str(option.get("disabled_reason", ""))
		if reason != "":
			text += "\n" + reason
		detail.text = text
		card.add_child(detail)
		options_box.add_child(card)


func _choose_situation_option(option_id: String) -> void:
	if _game == null or _selected_event_id.is_empty():
		return
	var result: Dictionary = _game.resolve_situation(_selected_event_id, option_id)
	_sfx_result(result)
	if not result.get("ok", false):
		_set_situation_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_set_status("DECIDED / %s" % result.get("message", ""))
	_situation_open = false
	_resize_layout()


func _set_situation_status(text: String) -> void:
	%SituationPanel.find_child("SituationStatus").text = text


func _close_legislation() -> void:
	_sfx_cue("navigation")
	_legislation_open = false
	_resize_layout()


func _refresh_legislation() -> void:
	var model: Dictionary = snapshot.get("legislation", {})
	var choice: OptionButton = %LegislationPanel.find_child("BillChoice")
	choice.clear()
	if not model.get("ok", false):
		choice.disabled = true
		_set_legislation_status(str(model.get("error", "Legislation is unavailable.")))
		_apply_legislation_actions({})
		return
	var pending: Variant = model.get("pending")
	if pending is Dictionary:
		_selected_bill_id = str(pending.get("id", ""))
	var selected_index := 0
	for bill in model.get("bills", []):
		var index := choice.item_count
		choice.add_item(str(bill.get("name", bill.get("id", "Bill"))))
		choice.set_item_metadata(index, bill)
		var eligible := bool(bill.get("eligible", false))
		choice.set_item_disabled(index, not eligible)
		choice.get_popup().set_item_tooltip(index, str(bill.get("disabled_reason", bill.get("description", ""))))
		if str(bill.get("id", "")) == _selected_bill_id:
			selected_index = index
	choice.disabled = choice.item_count == 0 or model.get("pending") is Dictionary
	if choice.item_count > 0:
		choice.select(selected_index)
		if pending is Dictionary and model.get("pending_preview") is Dictionary:
			var selected_bill: Dictionary = choice.get_item_metadata(selected_index)
			%LegislationPanel.find_child("BillTitle").text = "%s / %s" % [str(selected_bill.get("tier", "bill")).to_upper(), selected_bill.get("name", "Bill")]
			%LegislationPanel.find_child("BillDescription").text = str(selected_bill.get("description", ""))
			_bill_preview = model["pending_preview"].duplicate(true)
			_display_bill_preview(_bill_preview)
		else:
			_on_bill_selected(selected_index)
	var lobby_choice: OptionButton = %LegislationPanel.find_child("LobbyChoice")
	lobby_choice.clear()
	var first_eligible := -1
	for faction in model.get("lobby_factions", []):
		var index := lobby_choice.item_count
		lobby_choice.add_item("%s — %.0f PC" % [faction.get("name", "Faction"), faction.get("cost", 0.0)])
		lobby_choice.set_item_metadata(index, faction)
		var eligible := bool(faction.get("eligible", false))
		lobby_choice.set_item_disabled(index, not eligible)
		lobby_choice.get_popup().set_item_tooltip(index, str(faction.get("disabled_reason", "")))
		if first_eligible < 0 and eligible:
			first_eligible = index
	if lobby_choice.item_count > 0:
		lobby_choice.select(first_eligible if first_eligible >= 0 else 0)
	var enacted_names: Array[String] = []
	for law in model.get("enacted", []):
		enacted_names.append(str(law.get("name", law.get("id", "Law"))))
	%LegislationPanel.find_child("ActiveLaws").text = "ENACTED / %s" % ", ".join(enacted_names) if not enacted_names.is_empty() else "No laws enacted during this campaign."
	_apply_legislation_actions(model.get("actions", {}))
	_update_bill_lobby_control()
	if pending is Dictionary:
		_set_legislation_status("%s is before parliament." % pending.get("name", "The bill"))


func _on_bill_choice_selected(index: int) -> void:
	_sfx_cue("selection")
	_on_bill_selected(index)

func _on_bill_selected(index: int) -> void:
	var choice: OptionButton = %LegislationPanel.find_child("BillChoice")
	if index < 0 or index >= choice.item_count:
		return
	var bill: Variant = choice.get_item_metadata(index)
	if not (bill is Dictionary):
		return
	_selected_bill_id = str(bill.get("id", ""))
	%LegislationPanel.find_child("BillTitle").text = "%s / %s" % [str(bill.get("tier", "bill")).to_upper(), bill.get("name", "Bill")]
	%LegislationPanel.find_child("BillDescription").text = str(bill.get("description", ""))
	var result: Dictionary = _game.preview_bill(_selected_bill_id)
	if not result.get("ok", false):
		_bill_preview.clear()
		_set_legislation_status(str(result.get("error", "This bill cannot be previewed.")))
		return
	_bill_preview = result.get("preview", {}).duplicate(true)
	_display_bill_preview(_bill_preview)


func _display_bill_preview(preview: Dictionary) -> void:
	var effect_lines: Array[String] = []
	var effects: Variant = preview.get("effects", [])
	if effects is Array:
		for effect in effects:
			effect_lines.append(_bill_effect_line(effect) if effect is Dictionary else str(effect))
	elif effects is Dictionary:
		for key in effects:
			effect_lines.append("%s: %s" % [str(key).capitalize(), effects[key]])
	%LegislationPanel.find_child("BillEffects").text = "CONSEQUENCES / %s" % " · ".join(effect_lines) if not effect_lines.is_empty() else "CONSEQUENCES / No immediate quantified effect."
	var verdict := "LIKELY PASS" if preview.get("passed", false) else "LIKELY DEFEAT"
	%LegislationPanel.find_child("BillProjection").text = "%s · %s for / %s against · %s needed" % [verdict, preview.get("votes_for", 0), preview.get("votes_against", 0), preview.get("threshold", 0)]
	%LegislationPanel.find_child("ProposeBillButton").text = "Table — %.0f PC" % preview.get("political_capital_cost", 0.0)


func _bill_effect_line(effect: Dictionary) -> String:
	var key := str(effect.get("key", "effect")).replace("_", " ").capitalize()
	var subject := str(effect.get("subject", ""))
	if subject != "":
		key = "%s: %s" % [subject, key.trim_prefix("Faction ")]
	var value := float(effect.get("value", 0.0))
	var magnitude := "%+.1f%%" % (value * 100.0) if absf(value) < 1.0 else "%+.1f" % value
	var timing := ""
	var delay := int(effect.get("delay", 0))
	if delay > 0:
		timing = " after %d month%s" % [delay, "" if delay == 1 else "s"]
	return "%s %s%s" % [key, magnitude, timing]


func _apply_legislation_actions(actions: Dictionary) -> void:
	for pair in [["ProposeBillButton", "propose"], ["VoteBillButton", "vote"], ["WithdrawBillButton", "withdraw"]]:
		var button: Button = %LegislationPanel.find_child(pair[0])
		var action: Dictionary = actions.get(pair[1], {})
		button.disabled = not bool(action.get("eligible", false))
		button.tooltip_text = str(action.get("disabled_reason", ""))


func _on_bill_lobby_selected(index: int) -> void:
	_sfx_cue("selection")
	_update_bill_lobby_control(index)

func _update_bill_lobby_control(_index: int = -1) -> void:
	var choice: OptionButton = %LegislationPanel.find_child("LobbyChoice")
	var button: Button = %LegislationPanel.find_child("LobbyButton")
	if choice.item_count == 0 or choice.selected < 0:
		choice.disabled = true
		button.disabled = true
		return
	var faction: Variant = choice.get_item_metadata(choice.selected)
	var eligible := faction is Dictionary and bool(faction.get("eligible", false))
	choice.disabled = false
	button.disabled = not eligible
	button.tooltip_text = "" if eligible else str(faction.get("disabled_reason", ""))


func _propose_bill() -> void:
	var result: Dictionary = _game.propose_law(_selected_bill_id)
	_set_legislation_status(str(result.get("message", "Proposal refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _lobby_bill() -> void:
	var choice: OptionButton = %LegislationPanel.find_child("LobbyChoice")
	if choice.selected < 0:
		return
	var faction: Variant = choice.get_item_metadata(choice.selected)
	if faction is Dictionary:
		var result: Dictionary = _game.lobby_law(str(faction.get("id", "")))
		_set_legislation_status(str(result.get("message", "Lobbying refused: %s" % result.get("error", "Unknown error"))))
		_sfx_result(result)


func _call_bill_vote() -> void:
	var result: Dictionary = _game.call_law_vote()
	if result.get("ok", false):
		_set_legislation_status("LAW ENACTED" if result.get("passed", false) else "BILL DEFEATED")
	else:
		_set_legislation_status("Vote refused: %s" % result.get("error", "Unknown error"))
	_sfx_result(result, true)


func _withdraw_bill() -> void:
	var result: Dictionary = _game.withdraw_law()
	_set_legislation_status(str(result.get("message", "Withdrawal refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _set_legislation_status(message: String) -> void:
	%LegislationPanel.find_child("LegislationStatus").text = message

func _select_region(region_id: String) -> void:
	_sfx_cue("selection")
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


func _on_program_choice_selected(index: int) -> void:
	_sfx_cue("selection")
	_on_program_selected(index)

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
	var event_id := str(decisions[_decision_index].get("event_id", ""))
	if not event_id.is_empty():
		_open_situation(event_id)
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
	_reset_budget_draft()
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
	_sfx_result(result)
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
		_sfx_result(result)
		_refresh_controls()
		return
	_starting = false
	_sfx_result(result)
	var load_snap: Dictionary = result.get("snapshot", {})
	if load_snap.is_empty():
		load_snap = _game.snapshot()
	_reset_budget_draft()
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
	_sfx_cue("clock_tick")
	_refresh_controls()

func _set_speed(value: int) -> void:
	if _fatal:
		return
	_speed = clampi(value, 1, 5)
	_sfx_cue("clock_tick")
	_refresh_controls()

func _start_selected_program() -> void:
	if _selected_program_id.is_empty():
		return
	var result: Dictionary = _game.start_regional_program(selected_region_id, _selected_program_id)
	if not result.get("ok", false):
		_set_status("PROGRAMME REFUSED / %s" % result.get("error", "Unknown error"))
	else:
		_set_status("PROGRAMME LAUNCHED / READY")
	_sfx_result(result)
	_refresh_controls()

func _refresh_controls() -> void:
	var ready := not snapshot.is_empty() and not _fatal
	%BudgetButton.disabled = not ready or _desk_open()
	%LegislationButton.disabled = not ready or _desk_open()
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
