class_name ClockDisplay
extends Node

## The clock at a glance. The play button names the action it will take; the
## date's second line carries the state; the speed pips light as a ladder only
## while time runs; and a stopped clock pulses until someone starts it. A lit
## speed pip on a stopped clock used to read as "running".

const PULSE_SECONDS := 0.6
const PULSE_LOW := 0.45

var _play: Button
var _date: Label
var _pips: Array[Button] = []
var _pulse: Tween


func bind(play: Button, date: Label, pips: Array[Button]) -> void:
	_play = play
	_date = date
	_pips = pips


func show_state(date_text: String, paused: bool, speed: int, ready: bool) -> void:
	_play.text = "▶ Play" if paused else "❚❚ Pause"
	_play.tooltip_text = "Start the clock (Space)" if paused else "Stop the clock (Space)"
	var state_line := "❚❚ Paused" if paused else "%s Speed %d" % ["▸".repeat(speed), speed]
	_date.text = "%s\n%s" % [date_text, state_line]
	for i in _pips.size():
		_pips[i].set_pressed_no_signal(ready and not paused and i < speed)
	_set_pulse(ready and paused)


func is_pulsing() -> bool:
	return _pulse != null and _pulse.is_valid() and _pulse.is_running()


func _set_pulse(on: bool) -> void:
	if on == is_pulsing():
		return
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	_date.modulate.a = 1.0
	if not on:
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_date, "modulate:a", PULSE_LOW, PULSE_SECONDS)
	_pulse.tween_property(_date, "modulate:a", 1.0, PULSE_SECONDS)
