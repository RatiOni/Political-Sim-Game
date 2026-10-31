extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")

## Words that describe the machinery rather than the republic.
const BANNED := ["simulation", "snapshot", "connected", "authorised steps", "static preview", "worker"]
const VITALS := ["stability", "approval", "capital", "growth", "unemployment", "inflation", "debt", "revenue", "expenditure", "balance"]


func _initialize() -> void:
	_run.call_deferred()


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _sweep(t, app: Node, where: String) -> void:
	for node in _walk(app):
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		var words: Array[String] = [String((node as Control).tooltip_text)]
		if node is Label:
			words.append((node as Label).text)
		elif node is Button:
			words.append((node as Button).text)
		for text in words:
			var lower := text.to_lower()
			for banned in BANNED:
				# Whole words only: "Workers' Front" is a party, not a worker process.
				var hit := RegEx.create_from_string("\\b%s\\b" % banned).search(lower)
				if hit != null:
					t.truth(false, "%s: '%s' in %s says '%s'" % [where, banned, node.name, text])


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_player_copy")
	var app: Node = await h.fresh()
	_sweep(t, app, "dashboard")
	for opener in ["_open_budget", "_open_legislation", "_open_diplomacy", "_open_records", "_open_region_panel"]:
		app.call(opener)
		await h.frames(4)
		_sweep(t, app, opener)
	t.truth(true, "every visible label and tooltip was swept")

	var region_line: String = app.find_child("RegionId", true, false).text
	t.truth(region_line != "vashtera" and region_line.length() > 8, "the region brief names the region's standing, not its id")
	for key in VITALS:
		t.truth(String(app._vital_row(key).tooltip_text).length() > 20, "the %s figure explains itself" % key)
	for choice in ["CountryChoice", "PledgeChoice", "ShadowChoice"]:
		var button: Control = app.find_child(choice, true, false)
		t.truth(button != null and button.tooltip_text != "", "%s says what it chooses" % choice)
	var save_tip: String = app.find_child("SaveButton", true, false).tooltip_text
	t.truth(save_tip.contains("%s)" % Keys.label("save")) and not save_tip.contains("F5"), "the save tooltip names the real key")
	h.finish()
	quit(t.finish())
