class_name Situation
extends RefCounted

## A situation waiting on the government: an authored event that has
## arrived and not yet been decided. It stays in the "needs you" list until
## the player chooses or the deadline passes, when the event's default
## option is taken for them — a government that looks away still decides.

var event_id: String = ""
var arrived_turn: int = 0
var deadline_turn: int = 0
## The foreign relation a diplomatic event is about, fixed on arrival so the
## choice is made about the same country the briefing described.
var target_country_id: String = ""


func to_dict() -> Dictionary:
	return {"event_id": event_id, "arrived_turn": arrived_turn,
		"deadline_turn": deadline_turn, "target_country_id": target_country_id}


static func from_dict(data: Variant) -> Situation:
	if not (data is Dictionary):
		push_error("Situation.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var s := Situation.new()
	s.event_id = String(data.get("event_id", ""))
	s.arrived_turn = int(data.get("arrived_turn", 0))
	s.deadline_turn = int(data.get("deadline_turn", 0))
	s.target_country_id = String(data.get("target_country_id", ""))
	if s.event_id == "":
		push_error("Situation.from_dict: missing event_id")
		return null
	return s
