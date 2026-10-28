class_name Modifier
extends RefCounted


var id: String
var source: String
var target: String
var magnitude: float
var onset_delay: int = 0
var ramp_duration: int = 1
const HOLDS_FOREVER: int = -1

var hold_duration: int = HOLDS_FOREVER
var decay_duration: int = 0
var age: int = 0
var source_id: String = ""
var portfolio: String = ""
var institutional: bool = true


func holds_forever() -> bool:
	return hold_duration < 0


func current_value() -> float:
	var t := age
	if t < onset_delay:
		return 0.0
	t -= onset_delay

	if t < ramp_duration:
		var frac := float(t + 1) / float(maxi(1, ramp_duration))
		return magnitude * minf(1.0, frac)
	t -= ramp_duration

	if holds_forever():
		return magnitude
	if t < hold_duration:
		return magnitude
	t -= hold_duration

	if decay_duration <= 0:
		return 0.0
	if t < decay_duration:
		var frac := 1.0 - float(t + 1) / float(decay_duration)
		return magnitude * maxf(0.0, frac)
	return 0.0


func is_expired() -> bool:
	if holds_forever():
		return false
	var total_life := onset_delay + ramp_duration + hold_duration + decay_duration
	return age >= total_life


func phase_label() -> String:
	var t := age
	if t < onset_delay:
		return "pending (starts in %dmo)" % (onset_delay - t)
	t -= onset_delay

	if ramp_duration > 1:
		if t < ramp_duration:
			return "phasing in (%d/%dmo)" % [t + 1, ramp_duration]
		t -= ramp_duration

	if holds_forever():
		return "active"
	if t < hold_duration:
		return "active"
	t -= hold_duration

	if decay_duration > 0 and t < decay_duration:
		return "fading (%d/%dmo)" % [t + 1, decay_duration]
	return "expired"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"source": source,
		"target": target,
		"magnitude": magnitude,
		"onset_delay": onset_delay,
		"ramp_duration": ramp_duration,
		"hold_duration": hold_duration,
		"decay_duration": decay_duration,
		"age": age,
		"source_id": source_id,
		"portfolio": portfolio,
		"institutional": institutional,
	}


static func from_dict(data: Dictionary) -> Modifier:
	if not (data is Dictionary):
		push_error("Modifier.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var m := Modifier.new()
	m.id = String(data.get("id", ""))
	m.source = String(data.get("source", ""))
	m.target = String(data.get("target", ""))
	m.magnitude = float(data.get("magnitude", 0.0))
	m.onset_delay = _int_field(data, "onset_delay", 0)
	m.ramp_duration = _int_field(data, "ramp_duration", 1)
	m.hold_duration = _int_field(data, "hold_duration", HOLDS_FOREVER)
	m.decay_duration = _int_field(data, "decay_duration", 0)
	m.age = _int_field(data, "age", 0)
	m.source_id = String(data.get("source_id", ""))
	m.portfolio = String(data.get("portfolio", ""))
	m.institutional = _bool_field(data, "institutional", true)
	return m


static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) <= 9007199254740992.0:
		return int(v)
	return fallback


static func _bool_field(data: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_BOOL:
		return v
	return fallback
