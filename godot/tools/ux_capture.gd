extends SceneTree

## Renders a first session for visual review: the menu settled, the dashboard,
## the clock running, each desk, the pause menu, options, the save list and a
## month later. Windowed (not headless) so text and art actually render.
## Usage: --resolution 1920x1080 --script res://tools/ux_capture.gd -- --out=C:/path

const SLOT := "zz_ux_capture"

var out := ""
var step := 0
var app: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out == "":
		push_error("ux_capture: pass -- --out=<directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _shot(name: String) -> void:
	step += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, step, name])
	print("shot %02d %s" % [step, name])


func _close_overlays() -> void:
	for node in get_nodes_in_group(Overlay.GROUP):
		(node as Overlay).close()
	await _frames(3)


func _run() -> void:
	var menu: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(240)
	await _shot("menu")
	OptionsPanel.open(menu)
	await _frames(6)
	await _shot("options_from_menu")
	menu.queue_free()
	await _frames(2)

	var flow: Node = root.get_node("GameFlow")
	flow.start_mode = "new"
	flow.pending_role = "contextual"
	flow.pending_seed = 424242
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = SLOT
	app.autosave_slot = ""
	root.add_child(app)
	await _frames(12)
	await _shot("dashboard_paused")
	app._toggle_pause()
	app._set_speed(3)
	await _frames(4)
	await _shot("dashboard_running_speed_3")
	app._toggle_pause()
	for desk in ["budget", "legislation", "diplomacy", "records"]:
		await app._go_to_desk(desk)
		await _frames(8)
		await _shot("desk_%s" % desk)
	await app._go_to_desk("records")
	app._open_pause_menu()
	await _frames(6)
	await _shot("pause_menu")
	await _close_overlays()
	SaveDialog.open(app, "load", true)
	await _frames(6)
	await _shot("load_dialog")
	await _close_overlays()
	app._paused = false
	for _i in range(32):
		app._clock_elapsed = 999.0
		app._process(0.0)
		await _frames(1)
	app._paused = true
	await _frames(4)
	await _shot("after_one_month")
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	quit(0)
