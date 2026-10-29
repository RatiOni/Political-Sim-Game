extends PanelContainer

signal requested(action: String, argument: String)
signal close_requested

const PLEDGE_SLOTS := 3
const RESPONSE_BUTTONS := {"support": "SupportButton", "oppose": "OpposeButton", "amend": "AmendButton"}
const NO_BILL := "No government bill is before parliament."

var _pledge_ids: Array[String] = ["", "", ""]


func _ready() -> void:
	find_child("CloseOppositionButton").pressed.connect(func() -> void: close_requested.emit())
	for response in RESPONSE_BUTTONS:
		_button(RESPONSE_BUTTONS[response]).pressed.connect(func() -> void: requested.emit("respond", response))
	for slot in range(1, PLEDGE_SLOTS + 1):
		_button("CampaignButton%d" % slot).pressed.connect(func() -> void: requested.emit("campaign", _pledge_ids[slot - 1]))
		_button("DropButton%d" % slot).pressed.connect(func() -> void: requested.emit("drop", _pledge_ids[slot - 1]))
	_button("AddPledgeButton").pressed.connect(func() -> void: requested.emit("pledge", _selected_id("PledgeChoice")))
	_button("AppointShadowButton").pressed.connect(func() -> void: requested.emit("shadow", _selected_id("ShadowChoice")))
	_choice("PledgeChoice").item_selected.connect(func(_i: int) -> void: _sync_choice_buttons())
	_choice("ShadowChoice").item_selected.connect(func(_i: int) -> void: _sync_choice_buttons())


func show_model(model: Dictionary) -> void:
	_label("Standing").text = "Credibility %d%%  ·  electoral edge %+.1f points" % [
		roundi(float(model.get("credibility", 0.5)) * 100.0), float(model.get("electoral_edge", 0.0)) * 100.0]
	_show_bill(model.get("government_bill"))
	_show_pledges(model.get("pledges", []))
	_fill_choice("PledgeChoice", model.get("pledge_options", []), "id",
		func(row: Dictionary) -> String: return "%s  · %.0f PC" % [row["name"], float(row["cost"])])
	_fill_choice("ShadowChoice", model.get("portfolios", []), "portfolio",
		func(row: Dictionary) -> String: return "Shadow %s  · %.0f PC" % [row["portfolio"], float(row["cost"])])
	var lines: Array[String] = []
	for row in model.get("portfolios", []):
		lines.append("%s — %s" % [row["portfolio"], row["holder"] if String(row["holder"]) != "" else "vacant"])
	_label("ShadowList").text = "\n".join(lines)
	_sync_choice_buttons()


func set_status(text: String) -> void:
	_label("OppositionStatus").text = text


func _show_bill(bill: Variant) -> void:
	if not (bill is Dictionary):
		_label("BillName").text = NO_BILL
		for response in RESPONSE_BUTTONS:
			_set_button(RESPONSE_BUTTONS[response], false, NO_BILL)
		return
	var declared := String(bill.get("response", ""))
	_label("BillName").text = "%s%s" % [bill["name"], "" if declared == "" else "  — you chose to %s" % declared]
	for row in bill.get("responses", []):
		_set_button(RESPONSE_BUTTONS[row["response"]], bool(row["eligible"]), String(row["disabled_reason"]))


func _show_pledges(pledges: Array) -> void:
	for slot in range(PLEDGE_SLOTS):
		var row: Dictionary = pledges[slot] if slot < pledges.size() else {}
		_pledge_ids[slot] = String(row.get("bill_id", ""))
		var number := slot + 1
		if row.is_empty():
			_label("PledgeName%d" % number).text = "—"
			_set_button("CampaignButton%d" % number, false, "An empty place in the platform.")
			_set_button("DropButton%d" % number, false, "An empty place in the platform.")
			continue
		var cooldown := int(row.get("cooldown", 0))
		_label("PledgeName%d" % number).text = "%s  · %s, %d campaign%s" % [row["name"], row["status"],
			int(row["campaigns"]), "" if int(row["campaigns"]) == 1 else "s"]
		_set_button("CampaignButton%d" % number, cooldown == 0,
			"" if cooldown == 0 else "Rests for %d more month%s." % [cooldown, "" if cooldown == 1 else "s"])
		_set_button("DropButton%d" % number, true, "")


func _fill_choice(name: String, rows: Array, id_key: String, label: Callable) -> void:
	var choice := _choice(name)
	var keep := _selected_id(name)
	choice.clear()
	for row in rows:
		choice.add_item(label.call(row))
		var index := choice.item_count - 1
		choice.set_item_metadata(index, {"id": String(row[id_key]), "eligible": bool(row["eligible"]),
			"reason": String(row["disabled_reason"])})
		if String(row[id_key]) == keep:
			choice.select(index)
	if choice.selected < 0 and choice.item_count > 0:
		choice.select(0)


func _sync_choice_buttons() -> void:
	for pair in [["PledgeChoice", "AddPledgeButton"], ["ShadowChoice", "AppointShadowButton"]]:
		var choice := _choice(pair[0])
		var meta: Variant = choice.get_item_metadata(choice.selected) if choice.selected >= 0 else null
		var ok: bool = meta is Dictionary and bool(meta["eligible"])
		_set_button(pair[1], ok, "" if ok or not (meta is Dictionary) else String(meta["reason"]))


func _selected_id(name: String) -> String:
	var choice := _choice(name)
	if choice.selected < 0:
		return ""
	var meta: Variant = choice.get_item_metadata(choice.selected)
	return String(meta["id"]) if meta is Dictionary else ""


func _set_button(name: String, enabled: bool, reason: String) -> void:
	var button := _button(name)
	button.disabled = not enabled
	button.tooltip_text = reason


func _button(name: String) -> Button:
	return find_child(name) as Button


func _label(name: String) -> Label:
	return find_child(name) as Label


func _choice(name: String) -> OptionButton:
	return find_child(name) as OptionButton
