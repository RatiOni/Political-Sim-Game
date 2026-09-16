extends PanelContainer

# This client formats a read model; it never advances or derives simulation state.
var snapshot: Dictionary = {}
var selected_region_id := "vashtera"
var _decision_index := -1

func _ready() -> void:
	%ArdeniaMap.region_selected.connect(_select_region)
	find_child("NextDecision").pressed.connect(_next_decision)
	get_window().size_changed.connect(_resize_layout)
	_resize_layout()
	# The fixture lives with the scene check and is visibly marked as synthetic.
	apply_snapshot(load("res://scripts/tests/vertical_slice_test.gd").fixture())

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
	_refresh_region()

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

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_decision"):
		_next_decision()
		get_viewport().set_input_as_handled()
