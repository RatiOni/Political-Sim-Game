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
	# Every campaign carries an explicit int seed; NativeGame reseeds its
	# SimRng from it, so each New Campaign press deals a fresh stream.
	GameFlow.pending_seed = randi()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _continue_campaign() -> void:
	_sfx_cue("selection")
	# No save-existence check here: App already falls back to a fresh
	# campaign if this client has no save to load, so a first-time player
	# pressing Continue just gets a new campaign rather than an error.
	GameFlow.start_mode = "continue"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _quit() -> void:
	_sfx_cue("navigation")
	get_tree().quit()
