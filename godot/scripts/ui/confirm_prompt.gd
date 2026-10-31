class_name ConfirmPrompt
extends Overlay

## A question with two or three answers. The first answer is the default
## (Enter); the last is the way out (Escape). Await `chosen` for the answer.

signal chosen(choice: String)

var _cancel := ""


static func ask(host: Node, title: String, text: String, choices: Array) -> ConfirmPrompt:
	var prompt := ConfirmPrompt.new()
	prompt.set_title(title)
	var line := Label.new()
	line.name = "PromptText"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(400, 0)
	line.text = text
	prompt.body.add_child(line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	prompt.body.add_child(row)
	for pair in choices:
		var button := Button.new()
		button.name = "Choice_%s" % String(pair[0])
		button.text = String(pair[1])
		button.custom_minimum_size = Vector2(0, 44)
		button.pressed.connect(prompt._choose.bind(String(pair[0])))
		row.add_child(button)
	prompt._cancel = String(choices[-1][0])
	host.add_child(prompt)
	(row.get_child(0) as Button).grab_focus.call_deferred()
	return prompt


func _on_back() -> void:
	_choose(_cancel)


func _choose(choice: String) -> void:
	chosen.emit(choice)
	close()
