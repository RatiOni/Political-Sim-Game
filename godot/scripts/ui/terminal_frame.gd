class_name TerminalFrame
extends RefCounted

## Cuts a panel's title into its top frame line — `─ PROTOCOL ────` — the
## signature of the control-room look. A panel adopts the text of its first
## `Section` label, which is then hidden so the title is not printed twice.


static func adopt_all(root: Node) -> void:
	for node in root.find_children("*", "PanelContainer", true, false):
		var panel := node as PanelContainer
		if panel.theme_type_variation != &"" or panel.has_meta("framed"):
			continue
		# A panel may name itself (`metadata/frame_text`), else it adopts a
		# leading Section heading. Only a *leading* one: a Section further down
		# is a status line or sub-heading, not the panel's name.
		var heading := _leading_section(panel)
		if heading == null and not panel.has_meta("frame_text"):
			continue
		panel.set_meta("framed", true)
		if heading != null:
			# Hidden, so it is read when the panel draws rather than drawn
			# itself. Frame headings are static names, not live status.
			panel.set_meta("frame_label", heading)
			heading.visible = false
		panel.draw.connect(_draw_title.bind(panel))
		panel.queue_redraw()


## Follow first children down from the panel; the heading must be first.
static func _leading_section(panel: Node) -> Label:
	var node := panel
	while node != null:
		var next: Node = null
		for child in node.get_children():
			if child is Control:
				next = child
				break
		if next is Label:
			var label := next as Label
			return label if label.theme_type_variation == &"Section" else null
		if not next is Container:
			return null
		node = next
	return null


static func _draw_title(panel: PanelContainer) -> void:
	var heading: Label = panel.get_meta("frame_label") if panel.has_meta("frame_label") else null
	var text := String(panel.get_meta("frame_text", "")).to_upper()
	if heading != null:
		text = heading.text.to_upper()
	if text.is_empty():
		return
	var font := panel.get_theme_font("font", "Label")
	var size := panel.get_theme_font_size("font_size", "Label")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := 14.0
	# Erase the frame line under the title, with a space either side.
	panel.draw_rect(Rect2(x - 6, -1, w + 12, 3), UiPalette.WINDOW, true)
	panel.draw_string(font, Vector2(x, font.get_ascent(size) * 0.5 - 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiPalette.TEXT_DIM)


## Control-room type is all caps. Display-only (`Label.uppercase`), so the
## text the code and tests read stays as written. Hooks the tree so rows
## built at runtime (vitals, dispatches) get it too.
## Buttons have no display-only caps, and the app rewrites their text as
## state changes, so a watcher raises any lower case it finds each frame.
static func capitalise_buttons(root: Node) -> void:
	var watcher := Timer.new()
	watcher.wait_time = 0.05
	watcher.autostart = true
	watcher.timeout.connect(func() -> void:
		for node in root.find_children("*", "BaseButton", true, false):
			if node is OptionButton:
				var option := node as OptionButton
				for i in option.item_count:
					var item := option.get_item_text(i)
					if item != item.to_upper():
						option.set_item_text(i, item.to_upper())
			elif node is Button:
				var button := node as Button
				if button.text != button.text.to_upper():
					button.text = button.text.to_upper())
	root.add_child(watcher)


static func capitalise(root: Node) -> void:
	for node in root.find_children("*", "Label", true, false):
		(node as Label).uppercase = true
	root.get_tree().node_added.connect(func(node: Node) -> void:
		if node is Label:
			(node as Label).uppercase = true)
