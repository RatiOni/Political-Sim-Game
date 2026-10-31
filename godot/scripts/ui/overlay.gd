class_name Overlay
extends Control

## A centred panel over a scrim. While any overlay is open the clock holds and
## the dashboard ignores its own keys; Escape belongs to the newest overlay.
## The confirm prompt, pause menu, options and save dialog are all overlays.

signal closed

const GROUP := &"overlay"

var body := VBoxContainer.new()
var _title := Label.new()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(GROUP)
	var scrim := ColorRect.new()
	scrim.color = Color(UiPalette.WINDOW, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	_title.theme_type_variation = &"Title"
	body.add_child(_title)


func set_title(text: String) -> void:
	_title.text = text


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		_on_back()


func _on_back() -> void:
	close()


func close() -> void:
	remove_from_group(GROUP)
	closed.emit()
	queue_free()


static func any_open(tree: SceneTree) -> bool:
	return not tree.get_nodes_in_group(GROUP).is_empty()
