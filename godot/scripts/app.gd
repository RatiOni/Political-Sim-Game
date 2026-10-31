extends PanelContainer

const SAVE_SLOT := "godot_slice"
const SPEED_DELAYS := [1.5, 1.0, 0.65, 0.4, 0.2]
const COMPACT_MAX_WIDTH := 1500
const COMPACT_MAX_HEIGHT := 850
const DATE_WIDTH_COMPACT := 120
const DATE_WIDTH_WIDE := 192
const NATIONAL_WIDTH_WIDE := 288
const NATIONAL_WIDTH_COMPACT := 236

## What each vital sign means, in the player's terms, on hover.
const VITAL_TERMS := {
	"stability": "How secure your government is. It moves toward a level set by coalition and cabinet loyalty, your majority, public approval, the economy and unrest.",
	"approval": "How the public rates your government. Each month it drifts toward a level set by the economy, party loyalty, household mood and public services.",
	"capital": "What you spend to act: tabling a budget or a bill, launching a programme, lobbying a party. It refills each month.",
	"growth": "How fast the economy is growing, per year.",
	"unemployment": "The share of the workforce without work.",
	"inflation": "How fast prices are rising, per year.",
	"debt": "Public debt as a share of the economy. Every deficit adds to it.",
	"revenue": "What the state collects in a year.",
	"expenditure": "What the state spends in a year.",
	"balance": "Revenue minus spending. A negative balance is a deficit, and adds to the debt.",
}


var _wire := WireLog.new()
var snapshot: Dictionary = {}
var selected_region_id := "vashtera"
var _decision_index := -1
var _game: Node
var _sfx: Node
var _sound := SoundControl.new()
var _clock := ClockDisplay.new()
var _date_text := ""
var _notice := StatusNotice.new()
var _fatal := false
var _starting := false
var _paused := true
var _speed := 1
var _clock_elapsed := 0.0
var _selected_program_id := ""
var _selected_program_option: Dictionary = {}
var _vital_rows: Dictionary = {}
var _seats: SeatStrip
var _trend_current: Dictionary = {}
var _trend_previous: Dictionary = {}
var _trend_date := ""
var _records_open := false
var _region_panel_open := false
var _charts: Dictionary = {}
var _region_view: RegionView
var _elections_seen := -1
var _budget_open := false
var _budget_adjustments := {}
var _budget_preview: Dictionary = {}
var _legislation_open := false
var _opposition_open := false
var save_slot := SAVE_SLOT
var _pending_snapshot: Dictionary = {}
var _snapshot_flush_queued := false
var _budget_view_key := 0
var _decisions_key := 0
var _situation_open := false
var _diplomacy_open := false
var _selected_country_id := ""
var _selected_event_id := ""
var _known_situations := {}
var _selected_bill_id := ""
var _bill_preview: Dictionary = {}

func _ready() -> void:
	TerminalFrame.adopt_all(self)
	TerminalFrame.capitalise(self)
	TerminalFrame.capitalise_buttons(self)
	_notice.name = "StatusNotice"
	add_child(_notice)
	_notice.bind(find_child("PreviewStatus"), find_child("Footer"))
	%DateLabel.add_theme_color_override("font_color", UiPalette.GOLD)
	_clock.name = "ClockDisplay"
	add_child(_clock)
	var pips: Array[Button] = []
	for index in range(5):
		pips.append(find_child("Speed%d" % (index + 1)) as Button)
	_clock.bind(%PlayButton, %DateLabel, pips)
	var wire_text: Label = %MonthlyReport.find_child("DispatchText")
	wire_text.visible = false
	wire_text.get_parent().add_child(_wire)
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
	var chart_choice: OptionButton = %BudgetPanel.find_child("ChartTypeChoice")
	for chart_name: String in BudgetChart.MODE_NAMES:
		chart_choice.add_item(chart_name)
	chart_choice.item_selected.connect(_on_budget_chart_type)
	%LegislationButton.pressed.connect(_open_legislation)
	%LegislationPanel.find_child("CloseLegislationButton").pressed.connect(_close_legislation)
	%LegislationPanel.find_child("BillChoice").item_selected.connect(_on_bill_choice_selected)
	%LegislationPanel.find_child("ProposeBillButton").pressed.connect(_propose_bill)
	%LegislationPanel.find_child("VoteBillButton").pressed.connect(_call_bill_vote)
	%LegislationPanel.find_child("WithdrawBillButton").pressed.connect(_withdraw_bill)
	%LegislationPanel.find_child("LobbyButton").pressed.connect(_lobby_bill)
	%LegislationPanel.find_child("LobbyChoice").item_selected.connect(_on_bill_lobby_selected)
	%SituationPanel.find_child("CloseSituationButton").pressed.connect(_close_situation)
	%DiplomacyButton.pressed.connect(_open_diplomacy)
	%RecordsButton.pressed.connect(_open_records)
	%RecordsPanel.find_child("CloseRecordsButton").pressed.connect(_close_records)
	%RegionPanel.find_child("CloseRegionButton").pressed.connect(_close_region_panel)
	%RegionBrief.find_child("OpenDossierButton").pressed.connect(_open_region_panel)
	%DiplomacyPanel.find_child("CloseDiplomacyButton").pressed.connect(_close_diplomacy)
	%DiplomacyPanel.find_child("CountryChoice").item_selected.connect(_on_country_selected)
	%OppositionPanel.requested.connect(_on_opposition_request)
	%OppositionPanel.close_requested.connect(_close_opposition)
	_sound.name = "SoundControl"
	find_child("Header").add_child(_sound)
	find_child("Header").move_child(_sound, find_child("SaveButton").get_index())
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
	find_child("SaveButton").tooltip_text = "Save the campaign (%s)" % Keys.label("save")
	find_child("LoadButton").tooltip_text = "Load a saved campaign (%s)" % Keys.label("load")
	if GameFlow.start_mode == "continue":
		_starting = true
		_do_load()
	else:
		_do_new_campaign()

func _process(delta: float) -> void:
	if _paused or _fatal or snapshot.is_empty() or _clock_held():
		return
	_clock_elapsed += delta
	if _clock_elapsed >= SPEED_DELAYS[_speed - 1]:
		_clock_elapsed = 0.0
		var result: Dictionary = _game.advance_day()
		_flush_snapshot()
		if not result.get("ok", false):
			_notice.say("Could not advance: %s" % result.get("error", "unknown error"), true)
		elif bool(result.get("month_rolled", false)):
			_sfx_cue("month_rollover")
		_refresh_controls()

## The one test for a small layout, on the size the layout actually gets:
## the window divided by the interface scale.
func _is_compact() -> bool:
	var view := Vector2(get_window().size) / maxf(get_window().content_scale_factor, 0.01)
	return view.x < COMPACT_MAX_WIDTH or view.y < COMPACT_MAX_HEIGHT


func _resize_layout() -> void:
	get_window().content_scale_size = get_window().size
	var compact := _is_compact()
	find_child("OfficeLabel").visible = not compact
	find_child("PreviewStatus").visible = not compact
	%DateLabel.custom_minimum_size.x = DATE_WIDTH_COMPACT if compact else DATE_WIDTH_WIDE
	var national := find_child("NationalPanel") as Control
	national.visible = not _desk_open()
	national.custom_minimum_size.x = NATIONAL_WIDTH_COMPACT if compact else NATIONAL_WIDTH_WIDE
	find_child("MapPanel").visible = not _desk_open()
	# A desk takes the whole body; its room needs the height the decision rail
	# would otherwise hold. The rail returns the moment the desk closes.
	find_child("DecisionRail").visible = not _desk_open()
	%RegionBrief.visible = not _desk_open()
	%BudgetPanel.visible = _budget_open
	%LegislationPanel.visible = _legislation_open
	%SituationPanel.visible = _situation_open
	%DiplomacyPanel.visible = _diplomacy_open
	%OppositionPanel.visible = _opposition_open
	%RecordsPanel.visible = _records_open
	%RegionPanel.visible = _region_panel_open
	find_child("MapHint").visible = not compact and not _desk_open()
	%MonthlyReport.custom_minimum_size.y = 88 if compact or _desk_open() else 150
	%RegionBrief.find_child("Details").custom_minimum_size.y = 48 if compact else 84
	for name in ["Rule", "PressureHeading", "PressureValue", "Details"]:
		%RegionBrief.find_child(name).visible = not compact
	find_child("Layout").add_theme_constant_override("separation", 12 if compact else 16)
	# The header carries eleven controls. At 1280 they fit only if the gaps
	# close up — hiding a destination instead would make it unreachable on
	# exactly the machines most likely to be running at that size.
	find_child("Header").add_theme_constant_override("separation", 8 if compact else 16)
	_sound.slider.visible = not compact
	%MonthlyReport.find_child("DispatchColumn").visible = not compact
	if not snapshot.is_empty():
		_refresh_controls()
	_refresh_rooms()
	if not snapshot.is_empty():
		if _budget_open:
			_refresh_budget()
		elif _legislation_open:
			_refresh_legislation()
		elif _situation_open:
			_refresh_situation()
		elif _diplomacy_open:
			_refresh_diplomacy()
		elif _opposition_open:
			_refresh_opposition()
		elif _records_open:
			_refresh_records()
		elif _region_panel_open:
			_refresh_region_panel()
		else:
			_refresh_region()

## Each desk opens on its own room (`scripts/ui/desk/`): mounted at the top
## of the panel once, then fed the snapshot whenever the layout refreshes.
const ROOMS := {
	"BudgetPanel": "treasury", "LegislationPanel": "parliament", "DiplomacyPanel": "foreign",
	"RecordsPanel": "records", "OppositionPanel": "opposition", "SituationPanel": "situation",
}
var _rooms: Dictionary = {}

## The bed under the current screen: the open desk's room, the selected
## region's street sized to its town, or the minister's own office. Desks win
## over the dossier because opening one leaves `_region_panel_open` set.
func _update_ambience() -> void:
	var ambience := get_node_or_null("/root/Ambience")
	if ambience == null:
		return
	var scene := "desk"
	if _budget_open:
		scene = "treasury"
	elif _legislation_open:
		scene = "parliament"
	elif _diplomacy_open:
		scene = "foreign"
	elif _situation_open:
		scene = "situation"
	elif _opposition_open:
		scene = "opposition"
	elif _records_open:
		scene = "records"
	elif _region_panel_open:
		var d := RegionCity.data_from(_selected_region_row())
		var harbour := RegionCity.is_harbour(String(d["id"]))
		ambience.set_scene(ambience.scene_for_region(float(d["population"]), harbour), float(d["trouble"]))
		return
	ambience.set_scene(scene)

func _refresh_rooms() -> void:
	_update_ambience()
	var compact := _is_compact()
	for panel_name in ROOMS:
		var panel := find_child(panel_name) as Control
		if panel == null or not panel.visible:
			continue
		var path := "res://scripts/ui/desk/room_%s.gd" % ROOMS[panel_name]
		if not ResourceLoader.exists(path):
			continue
		var room := load(path) as GDScript
		if not _rooms.has(panel_name) or not is_instance_valid(_rooms[panel_name]):
			var view := DeskView.new()
			view.name = "Room"
			view.painter = room.paint
			# The room fills the desk, as in a control-room console: the desk's
			# own controls move into a column on the left, the room takes the
			# rest of the panel at full height.
			var content := panel.get_child(0) as Control
			var split := HBoxContainer.new()
			split.name = "Split"
			split.add_theme_constant_override("separation", 16)
			var owners := {}
			for node in [content] + content.find_children("*", "", true, false):
				owners[node] = node.owner
			panel.remove_child(content)
			panel.add_child(split)
			split.add_child(content)
			# Re-parenting clears ownership; the desk's lookups need it back.
			split.owner = panel
			for node in owners:
				node.owner = owners[node] if owners[node] != null else panel
			content.size_flags_horizontal = Control.SIZE_FILL
			view.custom_minimum_size = Vector2(0, 0)
			view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			view.size_flags_vertical = Control.SIZE_EXPAND_FILL
			split.add_child(view)
			_rooms[panel_name] = view
		var view: DeskView = _rooms[panel_name]
		var column := view.get_parent().get_child(0) as Control
		column.custom_minimum_size.x = (460 if compact else 560) + (180 if panel_name == "BudgetPanel" else 0)
		# On a small window the budget sliders need the whole width.
		view.visible = not (compact and panel_name == "BudgetPanel")
		if not snapshot.is_empty():
			view.data = room.data_from(snapshot)

func apply_snapshot(value: Dictionary) -> void:
	var incoming_budget: Dictionary = value.get("budget", {})
	var incoming_pending: Variant = incoming_budget.get("pending")
	var incoming_proposal_year := int(incoming_budget.get("proposal_year", 0))
	var cached_plan: Dictionary = _budget_preview.get("plan", {})
	if incoming_pending is Dictionary or (not cached_plan.is_empty() \
			and int(cached_plan.get("year", 0)) != incoming_proposal_year):
		_reset_budget_draft()
	snapshot = value.duplicate(true)
	_refresh_rooms()
	_date_text = str(snapshot.get("date", {}).get("text", ""))
	var player: Dictionary = snapshot.get("player", {})
	# The header column is narrow beside eleven controls: the name always
	# fits, the full office rides in the tooltip.
	var office: Label = find_child("OfficeLabel")
	office.text = str(player.get("name", "—"))
	office.tooltip_text = "%s / %s" % [player.get("title", "Office of government"), player.get("name", "—")]
	find_child("StabilityLabel").text = str(snapshot.get("headline", {}).get("stability", "—"))
	var economy: Dictionary = snapshot.get("economy", {})
	_refresh_vitals(player, economy, snapshot.get("headline", {}))
	_seat_strip().set_factions(snapshot.get("factions", []))
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
		label.text = "Nothing needs your decision right now."
		items.add_child(label)
	find_child("NextDecision").disabled = decisions.is_empty()
	var decisions_key := decisions.hash()
	if decisions_key != _decisions_key:
		_decisions_key = decisions_key
		_decision_index = -1
	%MonthlyReport.find_child("ReportText").text = _lines(snapshot.get("digest", []), "Your first monthly report arrives at the end of the month. Start the clock to get there.")
	%MonthlyReport.find_child("DispatchText").text = _lines(snapshot.get("dispatches", []), "No dispatches this period.")
	_wire.show_rows(snapshot.get("dispatches", []), "No dispatches this period.")
	%ArdeniaMap.apply_snapshot(snapshot.get("regions", []), selected_region_id)

	_refresh_region()
	if _budget_open:
		_refresh_budget()
	elif _legislation_open:
		_refresh_legislation()
	elif _situation_open:
		_refresh_situation()
	elif _diplomacy_open:
		_refresh_diplomacy()
	elif _opposition_open:
		_refresh_opposition()
	elif _records_open:
		_refresh_records()
	elif _region_panel_open:
		_refresh_region_panel()
	_notice_new_situations()
	_notice_election()
	_refresh_controls()


## An election is the campaign's big national moment, so a new result gets
## the newsreel card. The first snapshot only sets the baseline: loading a
## save must not replay an old count.
func _notice_election() -> void:
	var elections: Array = snapshot.get("history", {}).get("elections", [])
	var seen := _elections_seen
	_elections_seen = elections.size()
	if seen < 0 or elections.size() <= seen:
		return
	var row: Dictionary = elections[-1]
	var shares: Dictionary = row.get("vote_share", {})
	var ranked := shares.keys()
	ranked.sort_custom(func(a, b): return float(shares[a]) > float(shares[b]))
	var names := {}
	for faction in snapshot.get("factions", []):
		names[String(faction.get("id", ""))] = String(faction.get("name", ""))
	var details: Array[String] = []
	for i in mini(3, ranked.size()):
		var id := String(ranked[i])
		details.append("%s  %.1f%%" % [names.get(id, id), float(shares[id]) * 100.0])
	if not details.is_empty():
		details[0] = "%s first" % details[0]
	details.append("Turnout %.0f%%  /  %s" % [float(row.get("turnout", 0.0)) * 100.0, str(row.get("year", ""))])
	EventFlash.show_on(self, "ELECTION", details)

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


## Thousands separators, no decimals. The snapshot carries raw floats
## (12070.3321872016) and a treasury figure printed to 13 decimal places is
## noise, not information.
func _money(value: Variant) -> String:
	var whole := int(round(float(value)))
	var sign_text := "-" if whole < 0 else ""
	var digits := str(absi(whole))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return sign_text + out


## Trend is sampled per turn, never per repaint — otherwise an idle redraw
## compares a value with itself and every glyph reads "steady".
func _trend_for(key: String, value: float, date_text: String) -> int:
	if date_text != _trend_date:
		_trend_previous = _trend_current.duplicate()
		_trend_date = date_text
		_trend_current.clear()
	_trend_current[key] = value
	if not _trend_previous.has(key):
		return 0
	var delta: float = value - float(_trend_previous[key])
	if absf(delta) < 0.0005:
		return 0
	return 1 if delta > 0.0 else -1


func _vitals_box() -> VBoxContainer:
	return find_child("Vitals") as VBoxContainer


func _seat_strip() -> SeatStrip:
	var box := find_child("Assembly") as VBoxContainer
	if _seats == null or not is_instance_valid(_seats):
		_seats = SeatStrip.new()
		_seats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(_seats)
	return _seats


## Rows are built once and then only updated, so the panel never reflows
## as figures change (the dashboard's standing rule).
func _vital_row(key: String) -> StatBar:
	if _vital_rows.has(key) and is_instance_valid(_vital_rows[key]):
		return _vital_rows[key]
	var row := StatBar.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.tooltip_text = VITAL_TERMS.get(key, "")
	_vitals_box().add_child(row)
	_vital_rows[key] = row
	return row


func _vital_rule() -> void:
	var rule := HSeparator.new()
	_vitals_box().add_child(rule)


func _refresh_vitals(player: Dictionary, economy: Dictionary, headline: Dictionary) -> void:
	var date_text := str(snapshot.get("date", {}).get("text", ""))
	var first_build := _vital_rows.is_empty()

	# Bounded, higher-is-better readings get a meter. Everything else gets a
	# figure and a trend glyph — a bar for debt or inflation would imply a
	# full bar is good (CLAUDE.md, dashboard conventions).
	var stability := float(headline.get("value", 0.0))
	_vital_row("stability").set_meter("Stability", stability,
		"%.0f%%" % (stability * 100.0), UiPalette.good_scale(stability))

	var approval := float(player.get("approval", 0.0))
	_vital_row("approval").set_meter("Approval", approval,
		"%.1f%%" % (approval * 100.0), UiPalette.good_scale(approval))

	if first_build:
		_vital_rule()

	var capital := float(player.get("political_capital", 0.0))
	_vital_row("capital").set_figure("Political capital", "%.1f" % capital,
		_trend_for("capital", capital, date_text))

	var growth := float(economy.get("growth", 0.0))
	_vital_row("growth").set_figure("Growth", _percent(economy, "growth"),
		_trend_for("growth", growth, date_text))

	for metric in [["Unemployment", "unemployment"], ["Inflation", "inflation"], ["Debt / GDP", "debt"]]:
		var amount := float(economy.get(metric[1], 0.0))
		_vital_row(metric[1]).set_figure(metric[0], _percent(economy, metric[1]),
			_trend_for(metric[1], amount, date_text), true)

	if first_build:
		_vital_rule()

	var revenue := float(economy.get("revenue", 0.0))
	var expenditure := float(economy.get("expenditure", 0.0))
	_vital_row("revenue").set_figure("Revenue", "%s M" % _money(revenue),
		_trend_for("revenue", revenue, date_text))
	_vital_row("expenditure").set_figure("Expenditure", "%s M" % _money(expenditure),
		_trend_for("expenditure", expenditure, date_text), true)
	var balance := revenue - expenditure
	var balance_row := _vital_row("balance")
	balance_row.set_figure("Balance", "%s%s M" % ["+" if balance >= 0.0 else "", _money(balance)],
		_trend_for("balance", balance, date_text))

func _compact_region_status(region: Dictionary) -> String:
	return "Pressure %.0f%% · Jobless %.1f%% · Reach %.0f%%" % [
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
	_diplomacy_open = false
	_legislation_open = false
	_situation_open = false
	_opposition_open = false
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
	var view_key := [model, _budget_adjustments, _budget_preview].hash()
	if view_key == _budget_view_key:
		return
	_budget_view_key = view_key
	var actions: Dictionary = model.get("actions", {})
	var preview_action: Dictionary = actions.get("preview", {})
	var rows: VBoxContainer = %BudgetPanel.find_child("BudgetRows")
	if not model.get("ok", false):
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		var unavailable := Label.new()
		unavailable.text = str(model.get("error", "Budget data is unavailable."))
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(unavailable)
		_set_budget_status(unavailable.text)
		_apply_budget_actions({})
		return
	_sync_budget_sliders(rows, model.get("envelopes", []), bool(preview_action.get("eligible", false)),
		str(preview_action.get("disabled_reason", "")))
	_display_income(model)

	var lobby_choice: OptionButton = %BudgetPanel.find_child("LobbyChoice")
	var keep_budget_lobby := _selected_id(lobby_choice)
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
	if lobby_choice.item_count > 0 and not _reselect(lobby_choice, keep_budget_lobby):
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


## Slider rows are kept alive across snapshots (rebuilding them mid-drag
## would drop the drag); only a change of envelope ids rebuilds them.
func _sync_budget_sliders(rows: VBoxContainer, envelopes: Array, editable: bool, reason: String) -> void:
	var ids: Array[String] = []
	for envelope: Dictionary in envelopes:
		ids.append(str(envelope.get("id", "")))
	var existing: Array[String] = []
	for child in rows.get_children():
		existing.append(String(child.get_meta("envelope_id", "")))
	if existing != ids:
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		for envelope: Dictionary in envelopes:
			rows.add_child(_budget_slider_row(envelope))
	for envelope: Dictionary in envelopes:
		var envelope_id := str(envelope.get("id", ""))
		var row := rows.find_child("BudgetRow_%s" % envelope_id, false, false)
		var slider: HSlider = row.find_child("Adjustment_%s" % envelope_id, true, false)
		slider.set_value_no_signal(float(_budget_adjustments.get(envelope_id, 0.0)))
		slider.editable = editable
		slider.tooltip_text = reason
		row.set_meta("current", float(envelope.get("current", 0.0)))


func _budget_slider_row(envelope: Dictionary) -> VBoxContainer:
	var envelope_id := str(envelope.get("id", ""))
	var steps: Array[float] = []
	for value in envelope.get("allowed_adjustments", [0.0]):
		steps.append(float(value))
	steps.sort()
	var row := VBoxContainer.new()
	row.name = "BudgetRow_%s" % envelope_id
	row.set_meta("envelope_id", envelope_id)
	row.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	var label := Label.new()
	label.name = "EnvelopeName"
	label.text = str(envelope.get("name", envelope_id.capitalize())).to_upper()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.tooltip_text = str(envelope.get("body", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var amount := Label.new()
	amount.name = "EnvelopeAmount"
	amount.custom_minimum_size = Vector2(220, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.clip_text = true
	top.add_child(label)
	top.add_child(amount)
	row.add_child(top)
	var slider := HSlider.new()
	slider.name = "Adjustment_%s" % envelope_id
	slider.custom_minimum_size = Vector2(0, 44)
	slider.min_value = steps[0]
	slider.max_value = steps[-1]
	# ponytail: uniform step from the catalogue; the sim only accepts its listed steps.
	slider.step = steps[1] - steps[0] if steps.size() > 1 else 1.0
	slider.tick_count = steps.size()
	slider.ticks_on_borders = true
	slider.value_changed.connect(_on_budget_slider.bind(envelope_id))
	row.add_child(slider)
	return row


func _on_budget_slider(value: float, envelope_id: String) -> void:
	var step := snappedf(value, 0.0001)
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


func _on_budget_chart_type(index: int) -> void:
	_sfx_cue("selection")
	for chart_name in ["SpendingChart", "IncomeChart"]:
		(%BudgetPanel.find_child(chart_name) as BudgetChart).mode = index as BudgetChart.Mode


## Income tab: the read-only `revenue_sources` split from the snapshot.
func _display_income(model: Dictionary) -> void:
	var sources: Array = model.get("revenue_sources", [])
	(%BudgetPanel.find_child("IncomeChart") as BudgetChart).set_items(sources)
	var total := 0.0
	for source: Dictionary in sources:
		total += float(source.get("value", 0.0))
	var lines: Array[String] = []
	for source: Dictionary in sources:
		var value := float(source.get("value", 0.0))
		lines.append("%s  %+.0f M  %.1f%%" % [str(source.get("name", "")).to_upper(), value,
			100.0 * value / total if total > 0.0 else 0.0])
	lines.append("TOTAL REVENUE  %.0f M" % total)
	lines.append("DEBT SERVICE (OUTSIDE ENVELOPES)  %.0f M" % float(model.get("debt_service", 0.0)))
	%BudgetPanel.find_child("IncomeRows").text = "\n".join(lines)


func _display_budget_preview(preview: Dictionary) -> void:
	if preview.is_empty():
		%BudgetPanel.find_child("BudgetSummary").text = "No fiscal preview available."
		%BudgetPanel.find_child("BudgetProjection").text = "No parliamentary projection available."
		return
	var plan: Dictionary = preview.get("plan", {})
	var total := float(preview.get("total", 0.0))
	var free := float(preview.get("forecast_balance", 0.0))
	%BudgetPanel.find_child("RevenueFigure").text = "REVENUE %.0f M" % float(preview.get("forecast_revenue", 0.0))
	%BudgetPanel.find_child("SpendFigure").text = "SPENDING %.0f M" % total
	var free_label: Label = %BudgetPanel.find_child("FreeFigure")
	free_label.text = ("FREE %+.0f M" if free >= 0.0 else "DEFICIT %+.0f M") % free
	free_label.add_theme_color_override("font_color", UiPalette.GOOD if free >= 0.0 else UiPalette.BAD)
	var chart_rows: Array = []
	var rows: VBoxContainer = %BudgetPanel.find_child("BudgetRows")
	for line: Dictionary in preview.get("rows", []):
		var proposed := float(line.get("proposed", 0.0))
		chart_rows.append({"name": line.get("name", ""), "value": proposed})
		var row := rows.find_child("BudgetRow_%s" % line.get("id", ""), false, false)
		if row == null:
			continue
		var current := float(line.get("current", 0.0))
		(row.find_child("EnvelopeAmount", true, false) as Label).text = "%.0f M %+.0f%%  %4.1f%%" % [
			proposed, 100.0 * (proposed - current) / maxf(1.0, current), 100.0 * proposed / maxf(1.0, total)]
	(%BudgetPanel.find_child("SpendingChart") as BudgetChart).set_items(chart_rows)
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
	_flush_snapshot()
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
	_flush_snapshot()
	_set_budget_status(str(result.get("message", "Lobbying refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _call_budget_vote() -> void:
	var result: Dictionary = _game.call_budget_vote()
	_flush_snapshot()
	if result.get("ok", false):
		_set_budget_status("Budget approved." if result.get("passed", false) else "Budget defeated.")
	else:
		_set_budget_status("Vote refused: %s" % result.get("error", "Unknown error"))
	_sfx_result(result, true)


func _withdraw_budget() -> void:
	var result: Dictionary = _game.withdraw_budget()
	_flush_snapshot()
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
	if not _in_government():
		_open_opposition()
		return
	_sfx_cue("navigation")
	_diplomacy_open = false
	_budget_open = false
	_situation_open = false
	_opposition_open = false
	_legislation_open = true
	_bill_preview.clear()
	_resize_layout()


func _open_diplomacy() -> void:
	if snapshot.is_empty() or _fatal:
		return
	_sfx_cue("navigation")
	_budget_open = false
	_legislation_open = false
	_situation_open = false
	_opposition_open = false
	_diplomacy_open = true
	_set_diplomacy_status("")
	_resize_layout()


func _close_diplomacy() -> void:
	_sfx_cue("navigation")
	_diplomacy_open = false
	_resize_layout()


# --- the record (history charts) ----------------------------------------

func _open_records() -> void:
	if snapshot.is_empty() or _fatal:
		return
	_sfx_cue("navigation")
	_budget_open = false
	_legislation_open = false
	_situation_open = false
	_opposition_open = false
	_diplomacy_open = false
	_region_panel_open = false
	_records_open = true
	_refresh_records()
	_resize_layout()


func _close_records() -> void:
	_sfx_cue("navigation")
	_records_open = false
	_resize_layout()


## Charts are built once and then re-fed, so opening the panel does not
## rebuild the scene tree every time.
func _chart(key: String, title: String, height: int) -> PixelChart:
	if _charts.has(key) and is_instance_valid(_charts[key]):
		return _charts[key]
	var body := %RecordsPanel.find_child("RecordsBody")
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"Section"
	body.add_child(heading)
	var chart := PixelChart.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size.y = height
	body.add_child(chart)
	_charts[key] = chart
	return chart


func _refresh_records() -> void:
	var history: Dictionary = snapshot.get("history", {})
	var economy: Array = history.get("economy", [])
	var budgets: Array = history.get("budgets", [])
	var elections: Array = history.get("elections", [])

	# Growth and inflation share an axis: both are rates, and reading them
	# against each other is the point.
	var growth: Array = []
	var inflation: Array = []
	var months: Array = []
	for row in economy:
		growth.append(float(row.get("growth", 0.0)) * 100.0)
		inflation.append(float(row.get("inflation", 0.0)) * 100.0)
		months.append("%s" % row.get("year", ""))
	_chart("growth", "GROWTH AND INFLATION  /  PER MONTH", 150).plot_lines([
		{"name": "Growth", "color": UiPalette.GOOD, "points": growth},
		{"name": "Inflation", "color": UiPalette.WARN, "points": inflation},
	], months, "%.1f%%")

	var unemployment: Array = []
	var debt: Array = []
	for row in economy:
		unemployment.append(float(row.get("unemployment", 0.0)) * 100.0)
		debt.append(float(row.get("debt", 0.0)) * 100.0)
	_chart("burden", "UNEMPLOYMENT AND DEBT  /  PER MONTH", 150).plot_lines([
		{"name": "Unemployment", "color": UiPalette.PARTY[1], "points": unemployment},
		{"name": "Debt / GDP", "color": UiPalette.BAD, "points": debt},
	], months, "%.0f%%")

	var approval: Array = []
	var stability: Array = []
	for row in economy:
		approval.append(float(row.get("approval", 0.0)) * 100.0)
		stability.append(float(row.get("stability", 0.0)) * 100.0)
	_chart("standing", "APPROVAL AND STABILITY  /  PER MONTH", 150).plot_lines([
		{"name": "Approval", "color": UiPalette.GOLD, "points": approval},
		{"name": "Stability", "color": UiPalette.GOOD, "points": stability},
	], months, "%.0f%%")

	# Budgets: the balance per year, so a run of deficits is one picture.
	var balances: Array = []
	var years: Array = []
	for row in budgets:
		balances.append(float(row.get("balance", 0.0)))
		years.append(str(row.get("year", "")))
	_chart("budget", "BUDGET BALANCE  /  PER YEAR  (M)", 150).plot_bars(balances, years, "%.0f")

	_refresh_election_charts(elections)


func _refresh_election_charts(elections: Array) -> void:
	var turnout: Array = []
	var labels: Array = []
	for row in elections:
		turnout.append(float(row.get("turnout", 0.0)) * 100.0)
		labels.append(str(row.get("year", "")))
	_chart("turnout", "TURNOUT  /  PER ELECTION", 130).plot_lines([
		{"name": "Turnout", "color": UiPalette.GOLD, "points": turnout},
	], labels, "%.0f%%")

	# One line per party that has ever stood, in its assembly colour, so the
	# chart and the chamber agree.
	var names := {}
	var hexes := {}
	for faction in snapshot.get("factions", []):
		names[String(faction.get("id", ""))] = String(faction.get("name", ""))
		hexes[String(faction.get("id", ""))] = String(faction.get("color", ""))
	var ordered: Array = []
	for faction in snapshot.get("factions", []):
		ordered.append(String(faction.get("color", "")))
	var colors := UiPalette.party_colors(ordered)
	var index := 0
	var series: Array = []
	for faction in snapshot.get("factions", []):
		var id := String(faction.get("id", ""))
		var points: Array = []
		for row in elections:
			var shares: Dictionary = row.get("vote_share", {})
			points.append(float(shares.get(id, 0.0)) * 100.0)
		if not points.is_empty():
			series.append({"name": names.get(id, id), "color": colors[index], "points": points})
		index += 1
	_chart("shares", "VOTE SHARE  /  PER ELECTION", 150).plot_lines(series, labels, "%.0f%%")


# --- the region dossier -------------------------------------------------

func _open_region_panel() -> void:
	if snapshot.is_empty() or _fatal or selected_region_id.is_empty():
		return
	_sfx_cue("navigation")
	_budget_open = false
	_legislation_open = false
	_situation_open = false
	_opposition_open = false
	_diplomacy_open = false
	_records_open = false
	_region_panel_open = true
	_refresh_region_panel()
	_resize_layout()


func _close_region_panel() -> void:
	_sfx_cue("navigation")
	_region_panel_open = false
	_resize_layout()


func _selected_region_row() -> Dictionary:
	for row in snapshot.get("regions", []):
		if String(row.get("id", "")) == selected_region_id:
			return row
	return {}


func _refresh_region_panel() -> void:
	var region := _selected_region_row()
	if region.is_empty():
		return
	var panel := %RegionPanel
	panel.find_child("Heading").text = String(region.get("name", "Region")).to_upper()

	if _region_view == null or not is_instance_valid(_region_view):
		_region_view = RegionView.new()
		_region_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_region_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.find_child("Picture").add_child(_region_view)
	_region_view.show_region(region)

	var pressure := float(region.get("pressure", 0.0))
	var unemployment := float(region.get("unemployment", 0.0))
	var reach := float(region.get("state_reach", 0.0))
	var development := float(region.get("development", 0.0))
	panel.find_child("Standing").text = _region_standing(region)
	panel.find_child("Caption").text = _region_caption(region)

	var body := panel.find_child("RegionBody")
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var rows := [
		["Development", "%.0f%%" % (development * 100.0), development, UiPalette.good_scale(development)],
		["State reach", "%.0f%%" % (reach * 100.0), reach, UiPalette.good_scale(reach)],
		["Political pressure", "%.0f%%" % (pressure * 100.0), pressure, UiPalette.risk_scale(pressure, 0.3, 0.6)],
		["Unemployment", "%.1f%%" % (unemployment * 100.0), unemployment, UiPalette.risk_scale(unemployment, 0.1, 0.2)],
	]
	for row in rows:
		var bar := StatBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(bar)
		bar.set_meter(row[0], row[2], row[1], row[3])

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = &"Muted"
	var program: Variant = region.get("active_program")
	if program is Dictionary:
		note.text = "%s — month %d of %d, %.0f M a month." % [
			program.get("name", "Programme"), int(program.get("months_active", 0)) + 1,
			int(program.get("duration", 0)), float(program.get("monthly_cost", 0.0))]
	else:
		note.text = "No programme running here."
	body.add_child(note)


## One line on how the place is doing, in plain words.
func _region_standing(region: Dictionary) -> String:
	if String(region.get("control", "full")) == "separatist":
		return "Outside the government's administration."
	var pressure := float(region.get("pressure", 0.0))
	var development := float(region.get("development", 0.0))
	if bool(region.get("civil_war", false)):
		return "In open conflict."
	if pressure > 0.6:
		return "Close to losing patience."
	if pressure > 0.35:
		return "Restless, and watching."
	if development > 0.65:
		return "Prosperous and quiet."
	return "Getting by."


## The caption explains what changed the picture, so the art is read as
## information rather than decoration.
func _region_caption(region: Dictionary) -> String:
	var parts: Array[String] = []
	var development := float(region.get("development", 0.0))
	if development > 0.7:
		parts.append("new building and a paved street")
	elif development < 0.35:
		parts.append("little has been built here")
	var unemployment := float(region.get("unemployment", 0.0))
	if unemployment > 0.18:
		parts.append("shuttered windows where the work went")
	elif unemployment < 0.08:
		parts.append("the works are running")
	var pressure := float(region.get("pressure", 0.0))
	if pressure > 0.6:
		parts.append("barricades on the road")
	elif pressure > 0.4:
		parts.append("an uneasy quiet")
	if float(region.get("state_reach", 0.0)) < 0.4:
		parts.append("the state is barely present")
	if parts.is_empty():
		return "An ordinary month."
	var text := "; ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


func _on_country_selected(index: int) -> void:
	var choice: OptionButton = %DiplomacyPanel.find_child("CountryChoice")
	_selected_country_id = str(choice.get_item_metadata(index))
	_sfx_cue("selection")
	_refresh_diplomacy()


func _refresh_diplomacy() -> void:
	_refresh_orientation()
	_refresh_energy()
	var rows: Array = snapshot.get("diplomacy", [])
	var panel = %DiplomacyPanel
	var choice: OptionButton = panel.find_child("CountryChoice")
	choice.clear()
	var selected: Dictionary = {}
	for row in rows:
		choice.add_item("%s — %s" % [row.get("name", ""), row.get("status", "")])
		choice.set_item_metadata(choice.item_count - 1, str(row.get("id", "")))
		if str(row.get("id", "")) == _selected_country_id:
			selected = row
			choice.select(choice.item_count - 1)
	if selected.is_empty() and not rows.is_empty():
		selected = rows[0]
		_selected_country_id = str(selected.get("id", ""))
		choice.select(0)
	var actions_box: VBoxContainer = panel.find_child("DiplomacyActions")
	for child in actions_box.get_children():
		actions_box.remove_child(child)
		child.queue_free()
	if selected.is_empty():
		panel.find_child("CountryStanding").text = "No foreign relations are known."
		panel.find_child("CountryDetail").text = ""
		return
	panel.find_child("CountryStanding").text = "%s / %s (%+.2f)" % [
		str(selected.get("name", "")).to_upper(), selected.get("status", ""), float(selected.get("score", 0.0))]
	var lines: Array[String] = []
	lines.append("Government: %s" % str(selected.get("regime", "")).replace("_", " "))
	lines.append("Trade: %.0f M a year%s" % [float(selected.get("trade", 0.0)), " — under your sanctions" if selected.get("sanctioned", false) else ""])
	if selected.get("in_civil_war", false):
		lines.append("At war with itself.")
	var treaty_names: Array[String] = []
	for tr in selected.get("treaties", []):
		treaty_names.append("%s (%d months)" % [tr.get("name", ""), int(tr.get("months", 0))])
	lines.append("Treaties: %s" % (", ".join(treaty_names) if not treaty_names.is_empty() else "none"))
	panel.find_child("CountryDetail").text = "\n".join(lines)
	for action in selected.get("actions", []):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cost := float(action.get("cost", 0.0))
		button.text = str(action.get("label", "")) + ("   · %.0f PC" % cost if cost > 0.0 else "")
		button.disabled = not action.get("eligible", false)
		button.tooltip_text = str(action.get("disabled_reason", ""))
		button.pressed.connect(_take_diplomatic_action.bind(str(action.get("verb", "")), str(action.get("treaty_id", ""))))
		actions_box.add_child(button)
		var reason := str(action.get("disabled_reason", ""))
		if reason != "":
			var why := Label.new()
			why.theme_type_variation = &"Muted"
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			why.text = reason
			actions_box.add_child(why)


func _take_diplomatic_action(verb: String, treaty_id: String) -> void:
	if _game == null or _selected_country_id.is_empty():
		return
	var result: Dictionary = _game.diplomacy_act(verb, _selected_country_id, treaty_id)
	_flush_snapshot()
	_sfx_result(result)
	if not result.get("ok", false):
		_set_diplomacy_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_set_diplomacy_status(str(result.get("message", "")))


func _set_diplomacy_status(text: String) -> void:
	%DiplomacyPanel.find_child("DiplomacyStatus").text = text


func _refresh_orientation() -> void:
	var foreign: Dictionary = snapshot.get("foreign", {})
	var panel = %DiplomacyPanel
	var lines: Array[String] = []
	for p in foreign.get("powers", []):
		lines.append("%s / dependence %.2f / commitment %.2f / leverage %.2f" % [
			str(p.get("name", "")).to_upper(), float(p.get("dependence", 0.0)),
			float(p.get("commitment", 0.0)), float(p.get("leverage", 0.0))])
	panel.find_child("OrientationPowers").text = "\n".join(lines)
	panel.find_child("OrientationReviews").text = _isf_line(foreign.get("isf", {}), foreign)
	var box: VBoxContainer = panel.find_child("OrientationSteps")
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for step in foreign.get("steps", []):
		if step.get("held", false):
			var held := Label.new()
			held.theme_type_variation = &"Muted"
			held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			held.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			held.text = "IN PLACE / %s" % str(step.get("label", ""))
			box.add_child(held)
			continue
		_add_step_button(box, step, _take_orientation_step)


func _add_step_button(box: VBoxContainer, step: Dictionary, on_press: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost := float(step.get("cost", 0.0))
	button.text = str(step.get("label", "")) + ("   · %.0f PC" % cost if cost > 0.0 else "")
	button.clip_text = true
	button.disabled = not step.get("eligible", false)
	button.tooltip_text = str(step.get("disabled_reason", ""))
	button.pressed.connect(on_press.bind(str(step.get("verb", ""))))
	box.add_child(button)
	var reason := str(step.get("disabled_reason", ""))
	if reason != "":
		var why := Label.new()
		why.theme_type_variation = &"Muted"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.text = reason
		box.add_child(why)


func _refresh_energy() -> void:
	var energy: Dictionary = snapshot.get("foreign", {}).get("energy", {})
	var panel = %DiplomacyPanel
	panel.find_child("EnergyContract").text = _energy_line(energy)
	var box: VBoxContainer = panel.find_child("EnergySteps")
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for step in energy.get("steps", []):
		_add_step_button(box, step, _take_energy_step)


static func _energy_line(energy: Dictionary) -> String:
	if not energy.get("active", false):
		return "Ardenia has no gas contract to manage."
	var lines: Array[String] = [
		"%s / price %.1f (reference %.1f)%s / renewal in %d months" % [
			str(energy.get("supplier", "")).to_upper(), float(energy.get("price", 0.0)),
			float(energy.get("reference_price", 0.0)), " / Union cap" if energy.get("union_capped", false) else "",
			int(energy.get("months_to_renewal", 0))],
		"Arrears %.0f / storage %.2f of %.2f / second line: %s" % [
			float(energy.get("arrears", 0.0)), float(energy.get("storage", 0.0)),
			float(energy.get("storage_capacity", 0.0)), str(energy.get("second_line", "none"))],
	]
	if energy.get("threat", false):
		lines.append("VALVE THREATENED / deliveries fall next month unless the arrears come down")
	if float(energy.get("cut", 0.0)) > 0.0:
		lines.append("CUT / deliveries down %d%%" % roundi(float(energy["cut"]) * 100.0))
	lines.append("Supply this month %d%% of demand" % roundi((1.0 - float(energy.get("shortfall", 0.0))) * 100.0))
	return "\n".join(lines)


func _take_energy_step(verb: String) -> void:
	if _game == null:
		return
	var result: Dictionary = _game.energy_act(verb)
	_flush_snapshot()
	_sfx_result(result)
	if not result.get("ok", false):
		_set_diplomacy_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_set_diplomacy_status(str(result.get("message", "")))


static func _isf_line(isf: Dictionary, foreign: Dictionary) -> String:
	if isf.is_empty():
		return ""
	return "ISF reviews %d of %d / passed %d / failed %d%s / next targets: deficit %.1f%%, inflation %.1f%%%s\nConcert discipline: %d of %d months" % [
		int(isf.get("reviews_held", 0)), int(isf.get("reviews_total", 0)),
		int(isf.get("passed", 0)), int(isf.get("failed", 0)),
		" / SUSPENDED" if isf.get("suspended", false) else "",
		float(isf.get("deficit_target", 0.0)) * 100.0, float(isf.get("inflation_target", 0.0)) * 100.0,
		", independent bank" if isf.get("bank_required", false) else "",
		int(foreign.get("western_qualifying_months", 0)), int(foreign.get("qualifying_months_needed", 0))]


func _take_orientation_step(verb: String) -> void:
	if _game == null:
		return
	var result: Dictionary = _game.orientation_act(verb)
	_flush_snapshot()
	_sfx_result(result)
	if not result.get("ok", false):
		_set_diplomacy_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_set_diplomacy_status(str(result.get("message", "")))


func _desk_open() -> bool:
	return _budget_open or _legislation_open or _situation_open or _diplomacy_open \
		or _opposition_open or _records_open or _region_panel_open


func _notice_new_situations() -> void:
	var fresh := false
	var live := {}
	for row in snapshot.get("situations", []):
		var id := _situation_arrival_key(row)
		live[id] = true
		if not _known_situations.has(id):
			fresh = true
	_known_situations = live
	if fresh:
		_paused = true
		_sfx_cue("alert")


func _situation_arrival_key(row: Dictionary) -> String:
	return "%s@%s" % [row.get("event_id", ""), row.get("arrived_turn", 0)]


func _open_situation(event_id: String) -> void:
	if snapshot.is_empty() or _fatal:
		return
	_sfx_cue("navigation")
	_diplomacy_open = false
	_budget_open = false
	_legislation_open = false
	_opposition_open = false
	_situation_open = true
	_paused = true
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
	_flush_snapshot()
	_sfx_result(result)
	if not result.get("ok", false):
		_set_situation_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_notice.say("Decided: %s" % result.get("message", ""))
	_situation_open = false
	_resize_layout()


func _set_situation_status(text: String) -> void:
	%SituationPanel.find_child("SituationStatus").text = text


func _in_government() -> bool:
	return bool(snapshot.get("player", {}).get("in_government", true))


func _open_opposition() -> void:
	_sfx_cue("navigation")
	_budget_open = false
	_legislation_open = false
	_situation_open = false
	_diplomacy_open = false
	_opposition_open = true
	%OppositionPanel.set_status("")
	_resize_layout()


func _close_opposition() -> void:
	_sfx_cue("navigation")
	_opposition_open = false
	_resize_layout()


func _refresh_opposition() -> void:
	%OppositionPanel.show_model(snapshot.get("opposition", {}))


func _on_opposition_request(action: String, argument: String) -> void:
	if _game == null or argument == "":
		return
	var result: Dictionary
	match action:
		"respond": result = _game.respond_to_government_bill(argument)
		"pledge": result = _game.add_pledge(argument)
		"drop": result = _game.drop_pledge(argument)
		"campaign": result = _game.campaign_on_pledge(argument)
		"shadow": result = _game.appoint_shadow_minister(argument)
		_: return
	_flush_snapshot()
	_sfx_result(result)
	%OppositionPanel.set_status(str(result.get("message", "")) if result.get("ok", false)
		else "REFUSED / %s" % result.get("error", "Unknown error"))
	_refresh_opposition()


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
	var keep_bill_lobby := _selected_id(lobby_choice)
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
	if lobby_choice.item_count > 0 and not _reselect(lobby_choice, keep_bill_lobby):
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
	_flush_snapshot()
	_set_legislation_status(str(result.get("message", "Proposal refused: %s" % result.get("error", "Unknown error"))))
	_sfx_result(result)


func _lobby_bill() -> void:
	var choice: OptionButton = %LegislationPanel.find_child("LobbyChoice")
	if choice.selected < 0:
		return
	var faction: Variant = choice.get_item_metadata(choice.selected)
	if faction is Dictionary:
		var result: Dictionary = _game.lobby_law(str(faction.get("id", "")))
		_flush_snapshot()
		_set_legislation_status(str(result.get("message", "Lobbying refused: %s" % result.get("error", "Unknown error"))))
		_sfx_result(result)


func _call_bill_vote() -> void:
	var result: Dictionary = _game.call_law_vote()
	_flush_snapshot()
	if result.get("ok", false):
		_set_legislation_status("LAW ENACTED" if result.get("passed", false) else "BILL DEFEATED")
	else:
		_set_legislation_status("Vote refused: %s" % result.get("error", "Unknown error"))
	_sfx_result(result, true)


func _withdraw_bill() -> void:
	var result: Dictionary = _game.withdraw_law()
	_flush_snapshot()
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
	var keep_program := _selected_program_id
	choice.clear()
	_selected_program_id = ""
	_selected_program_option = {}
	%RegionBrief.find_child("RegionName").text = selected_region_id.capitalize()
	%RegionBrief.find_child("RegionId").text = ""
	%RegionBrief.find_child("PressureValue").text = "—"
	%RegionBrief.find_child("RegionMetrics").text = "No regional figures yet."
	%RegionBrief.find_child("ProgrammeStatus").text = "Select a region to review available programmes."
	for region in snapshot.get("regions", []):
		if region.get("id") != selected_region_id:
			continue
		%RegionBrief.find_child("RegionName").text = str(region.get("name", selected_region_id.capitalize()))
		%RegionBrief.find_child("RegionId").text = str(region.get("control_label", ""))
		%RegionBrief.find_child("PressureValue").text = "%.0f%%" % (float(region["pressure"]) * 100.0) if region.has("pressure") else "—"
		%RegionBrief.find_child("RegionMetrics").text = "Unemployment    %s\n\nState reach    %s" % [_percent(region, "unemployment"), _percent(region, "state_reach")]
		var active: Variant = region.get("active_program")
		if active is Dictionary:
			var active_text := "%s\nMonth %d of %d · %.0f M/month" % [active.get("name", "Active programme"), int(active.get("months_active", 0)) + 1, active.get("duration", 0), active.get("monthly_cost", 0.0)]
			if _is_compact():
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
		if _reselect(choice, keep_program):
			_on_program_selected(choice.selected)
		elif first_eligible >= 0:
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
				if _is_compact():
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
		"opening_role": GameFlow.pending_role,
		"seed": seed,
	}

func _do_new_campaign() -> void:
	_reset_desks()
	if _fatal:
		return
	var result: Dictionary = _game.new_campaign(_campaign_config())
	_flush_snapshot()
	if not result.get("ok", false):
		_notice.say("Could not start the campaign: %s" % result.get("error", "unknown error"), true)
		_refresh_controls()
		return
	var new_snap: Dictionary = result.get("snapshot", {})
	if new_snap.is_empty():
		new_snap = _game.snapshot()
	_reset_budget_draft()
	apply_snapshot(new_snap)
	_refresh_controls()

func _do_save() -> void:
	if _fatal or snapshot.is_empty():
		return
	var result: Dictionary = _game.save(save_slot)
	if not result.get("ok", false):
		_notice.say("Save failed: %s" % result.get("error", "unknown error"), true)
	else:
		_notice.say("Saved")
	_sfx_result(result)
	_refresh_controls()

func _do_load() -> void:
	if _fatal:
		return
	var was_starting := _starting
	_reset_desks()
	var result: Dictionary = _game.load(save_slot)
	_flush_snapshot()
	if not result.get("ok", false):
		if was_starting:
			_starting = false
			_do_new_campaign()
			return
		_notice.say("Load failed: %s" % result.get("error", "unknown error"), true)
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
	_notice.say("Loaded")
	_refresh_controls()

func _on_state_changed(value: Dictionary) -> void:
	_pending_snapshot = value
	if not _snapshot_flush_queued:
		_snapshot_flush_queued = true
		_flush_snapshot.call_deferred()


func _flush_snapshot() -> void:
	_snapshot_flush_queued = false
	if _pending_snapshot.is_empty():
		return
	apply_snapshot(_pending_snapshot)
	_pending_snapshot = {}
	_refresh_controls()


func _clock_held() -> bool:
	return _situation_open or (_budget_open and not _budget_adjustments.is_empty()) \
		or Overlay.any_open(get_tree())


func _reset_desks() -> void:
	_budget_open = false
	_legislation_open = false
	_situation_open = false
	_opposition_open = false
	_diplomacy_open = false
	_selected_event_id = ""
	_selected_bill_id = ""
	_selected_country_id = ""
	_selected_program_id = ""
	_budget_adjustments.clear()
	_budget_preview.clear()
	_bill_preview.clear()
	_known_situations = {}
	_budget_view_key = 0
	_decisions_key = 0


func _reselect(choice: OptionButton, wanted: String) -> bool:
	if wanted == "":
		return false
	for index in range(choice.item_count):
		var meta: Variant = choice.get_item_metadata(index)
		var id := str((meta as Dictionary).get("id", "")) if meta is Dictionary else str(meta)
		if id == wanted and not choice.is_item_disabled(index):
			choice.select(index)
			return true
	return false


func _selected_id(choice: OptionButton) -> String:
	if choice.selected < 0:
		return ""
	var meta: Variant = choice.get_item_metadata(choice.selected)
	return str((meta as Dictionary).get("id", "")) if meta is Dictionary else str(meta)

func _on_fatal_error(message: String) -> void:
	_reset_desks()
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
	_flush_snapshot()
	if not result.get("ok", false):
		_notice.say("Programme refused: %s" % result.get("error", "unknown error"), true)
	else:
		_notice.say("Programme launched")
	_sfx_result(result)
	_refresh_controls()

func _refresh_controls() -> void:
	var ready := not snapshot.is_empty() and not _fatal
	%BudgetButton.disabled = not ready or _desk_open()
	%LegislationButton.disabled = not ready or _desk_open()
	%LegislationButton.text = "Legislation" if _in_government() else "Opposition"
	%DiplomacyButton.disabled = not ready or _desk_open()
	%RecordsButton.disabled = not ready or _desk_open()
	%PlayButton.disabled = not ready
	for index in range(5):
		(find_child("Speed%d" % (index + 1)) as Button).disabled = not ready
	_clock.show_state(_date_text, _paused, _speed, ready)
	_update_program_controls(ready)
	find_child("SaveButton").disabled = not ready
	find_child("LoadButton").disabled = not ready

func _show_blocking_error(message: String) -> void:
	_remove_blocking_error()
	_notice.say("Error", true)
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
	label.text = "THE GAME HIT AN ERROR\n\n%s\n\nYour last save is untouched. Restart Ardenia to carry on from it." % message
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

func _input(event: InputEvent) -> void:
	if _fatal or snapshot.is_empty():
		return
	if Overlay.any_open(get_tree()):
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back") and _desk_open():
		_close_open_desk()
		get_viewport().set_input_as_handled()


func _close_open_desk() -> void:
	if _budget_open:
		_close_budget()
	elif _legislation_open:
		_close_legislation()
	elif _situation_open:
		_close_situation()
	elif _diplomacy_open:
		_close_diplomacy()
	elif _opposition_open:
		_close_opposition()
	elif _records_open:
		_close_records()
	elif _region_panel_open:
		_close_region_panel()


func _unhandled_key_input(event: InputEvent) -> void:
	if Overlay.any_open(get_tree()):
		return
	if (event.is_action_pressed("save") or event.is_action_pressed("load")) and _desk_open():
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
