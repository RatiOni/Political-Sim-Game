class_name PauseMenu
extends Overlay

## Escape on the dashboard: everything that is not governing — save, load,
## options and the ways out. The clock holds while it is open. Save, load and
## options open over it and return to it.

signal action(id: String)

const ENTRIES := [
	["resume", "Resume"], ["save", "Save game"], ["load", "Load game"],
	["options", "Options"], ["main_menu", "Exit to main menu"], ["quit", "Quit to desktop"],
]


static func open(host: Node) -> PauseMenu:
	var menu := PauseMenu.new()
	menu.set_title("Paused")
	for entry in ENTRIES:
		var button := Button.new()
		button.name = "Entry_%s" % entry[0]
		button.text = String(entry[1])
		button.custom_minimum_size = Vector2(360, 44)
		button.pressed.connect(menu._pick.bind(String(entry[0])))
		menu.body.add_child(button)
	host.add_child(menu)
	(menu.body.get_child(1) as Button).grab_focus.call_deferred()
	return menu


func _on_back() -> void:
	_pick("resume")


func _pick(id: String) -> void:
	action.emit(id)
	if id == "resume":
		close()
