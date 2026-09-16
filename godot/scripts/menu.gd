extends PanelContainer

func _ready() -> void:
	%NewCampaignButton.pressed.connect(_new_campaign)
	%ContinueButton.pressed.connect(_continue_campaign)
	%QuitButton.pressed.connect(_quit)

func _new_campaign() -> void:
	GameFlow.start_mode = "new"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _continue_campaign() -> void:
	# No save-existence check here: App already falls back to a fresh
	# campaign if this client has no save to load (the same path bridge
	# reconnection uses), so a first-time player pressing Continue just
	# gets a new campaign rather than an error.
	GameFlow.start_mode = "continue"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _quit() -> void:
	get_tree().quit()
