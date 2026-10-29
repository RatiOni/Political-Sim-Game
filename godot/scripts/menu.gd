extends PanelContainer

var _sfx: Node

func _ready() -> void:
	_sfx = get_node_or_null("/root/UiSfx")
	randomize()
	%NewCampaignButton.pressed.connect(_new_campaign.bind("contextual"))
	%OppositionCampaignButton.pressed.connect(_new_campaign.bind("opposition"))
	%ContinueButton.pressed.connect(_continue_campaign)
	%QuitButton.pressed.connect(_quit)
	# Keyboard first: the title screen opens with a focused entry so arrows
	# and Enter work without touching the mouse.
	%NewCampaignButton.grab_focus()
	_reveal_title()


## The title surfaces from a wall of rolling capitals, then the picture behind
## burns white and settles. The label keeps its text for layout and tests;
## only its ink is hidden.
func _reveal_title() -> void:
	var title: Label = $Center/Plate/Layout/Title
	var reveal := TitleReveal.new()
	reveal.cols = 11
	title.custom_minimum_size.y = reveal.rows * reveal.font_size * 1.05
	title.self_modulate = Color(1, 1, 1, 0)
	reveal.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(reveal)
	var backdrop := $Backdrop
	if backdrop.has_method("burst"):
		reveal.revealed.connect(backdrop.burst)

func _sfx_cue(cue: String) -> void:
	if _sfx != null and _sfx.has_method(cue):
		_sfx.call(cue)

func _new_campaign(role: String) -> void:
	_sfx_cue("confirm")
	GameFlow.start_mode = "new"
	GameFlow.pending_role = role
	GameFlow.pending_seed = randi()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _continue_campaign() -> void:
	_sfx_cue("selection")
	GameFlow.start_mode = "continue"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _quit() -> void:
	_sfx_cue("navigation")
	get_tree().quit()
