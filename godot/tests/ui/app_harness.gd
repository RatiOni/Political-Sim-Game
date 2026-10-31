extends RefCounted

## Boots the real dashboard for a UI test: a seeded campaign in the test's own
## save slot, with autosave off, so a test never writes the player's files.

const MAIN := "res://scenes/main.tscn"

var tree: SceneTree
var slot: String
var app: Node


func _init(scene_tree: SceneTree, test_slot: String) -> void:
	tree = scene_tree
	slot = test_slot


func fresh(role: String = "contextual") -> Node:
	if app != null and is_instance_valid(app):
		app.queue_free()
		await frames()
	var flow: Node = tree.root.get_node("GameFlow")
	flow.start_mode = "new"
	flow.pending_role = role
	flow.pending_seed = 424242
	app = (load(MAIN) as PackedScene).instantiate()
	app.save_slot = slot
	if "autosave_slot" in app:
		app.autosave_slot = ""
	tree.root.add_child(app)
	await frames(3)
	return app


func frames(count: int = 2) -> void:
	for _i in range(count):
		await tree.process_frame


func tick(days: int) -> void:
	app._paused = false
	for _i in range(days):
		app._clock_elapsed = 999.0
		app._process(0.0)
		await frames(1)


func wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [slot, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func finish() -> void:
	wipe_slot()
	if app != null and is_instance_valid(app):
		app.queue_free()
