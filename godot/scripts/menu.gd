extends PanelContainer

var _sfx: Node

func _ready() -> void:
	_sfx = get_node_or_null("/root/UiSfx")
	randomize()
	%NewCampaignButton.pressed.connect(_new_campaign)
	%ContinueButton.pressed.connect(_continue_campaign)
	%QuitButton.pressed.connect(_quit)

func _sfx_cue(cue: String) -> void:
	if _sfx != null and _sfx.has_method(cue):
		_sfx.call(cue)

func _new_campaign() -> void:
	_sfx_cue("confirm")
	GameFlow.start_mode = "new"
	GameFlow.pending_seed = randi()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _continue_campaign() -> void:
	_sfx_cue("selection")
	GameFlow.start_mode = "continue"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _quit() -> void:
	_sfx_cue("navigation")
	get_tree().quit()
