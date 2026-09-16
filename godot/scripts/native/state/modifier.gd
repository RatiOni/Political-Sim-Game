class_name Modifier
extends RefCounted

## Typed mirror of models/modifiers.py: the core primitive for long-term
## consequences (laws, loans, treaties, events attach one of these instead of
## mutating a stat directly). Task 3's calendar/modifier aging logic reads and
## mutates `age` on these; `current_value()` is recomputed fresh every turn,
## never accumulated, so effects stay bounded however long they run.
##
## Python's `hold_duration: Optional[int]` (None = holds forever) becomes a
## negative sentinel here (`hold_duration < 0` = holds forever), since typed
## GDScript ints can't be null.

var id: String
var source: String            # human-readable origin, for logs/UI
var target: String            # stat key the turn engine reads
var magnitude: float          # full-strength delta once ramped in
var onset_delay: int = 0
var ramp_duration: int = 1
var hold_duration: int = -1   # -1 == Python's None: holds at full strength forever
var decay_duration: int = 0
var age: int = 0
var source_id: String = ""    # law/loan/treaty id; "" == Python's None
var portfolio: String = ""    # "" == Python's None
var institutional: bool = true


func current_value() -> float:
	var t := age
	if t < onset_delay:
		return 0.0
	t -= onset_delay

	if t < ramp_duration:
		var frac := float(t + 1) / float(maxi(1, ramp_duration))
		return magnitude * minf(1.0, frac)
	t -= ramp_duration

	if hold_duration < 0:
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
	## Indefinite modifiers (hold_duration < 0) never auto-expire.
	if hold_duration < 0:
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

	if hold_duration < 0:
		return "active"
	if t < hold_duration:
		return "active"
	t -= hold_duration

	if decay_duration > 0 and t < decay_duration:
		return "fading (%d/%dmo)" % [t + 1, decay_duration]
	return "expired"
