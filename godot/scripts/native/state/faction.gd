class_name Faction
extends RefCounted


class Ideology extends RefCounted:
	var economic: float = 0.0
	var social: float = 0.0

	func distance_to(other: Ideology) -> float:
		var de := economic - other.economic
		var ds := social - other.social
		return sqrt(de * de + ds * ds)

	func label() -> String:
		var e := economic
		var s := social
		if e < -0.5 and s < -0.5:
			return "Authoritarian Left"
		if e < -0.5 and s > 0.5:
			return "Libertarian Left"
		if e > 0.5 and s < -0.5:
			return "Authoritarian Right"
		if e > 0.5 and s > 0.5:
			return "Libertarian Right"
		if e < -0.3:
			return "Centre Left"
		if e > 0.3:
			return "Centre Right"
		return "Centrist"

	static func from_json(data: Dictionary) -> Ideology:
		var i := Ideology.new()
		i.economic = float(data.get("economic", 0.0))
		i.social = float(data.get("social", 0.0))
		return i


	func to_dict() -> Dictionary:
		return {"economic": economic, "social": social}


	static func from_dict(data: Dictionary) -> Ideology:
		if not (data is Dictionary):
			push_error("Ideology.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var i := Ideology.new()
		i.economic = float(data.get("economic", 0.0))
		i.social = float(data.get("social", 0.0))
		return i


class Grievance extends RefCounted:
	var source: String
	var severity: float
	var turns_active: int = 0


	func to_dict() -> Dictionary:
		return {"source": source, "severity": severity, "turns_active": turns_active}


	static func from_dict(data: Dictionary) -> Grievance:
		if not (data is Dictionary):
			push_error("Grievance.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var grievance := Grievance.new()
		grievance.source = String(data.get("source", ""))
		grievance.severity = float(data.get("severity", 0.0))
		grievance.turns_active = Faction._int_field(data, "turns_active", 0)
		return grievance


class Demand extends RefCounted:
	var description: String
	var urgency: float = 0.5
	var law_id: String = ""


	func to_dict() -> Dictionary:
		return {"description": description, "urgency": urgency, "law_id": law_id}


	static func from_dict(data: Dictionary) -> Demand:
		if not (data is Dictionary):
			push_error("Demand.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var demand := Demand.new()
		demand.description = String(data.get("description", ""))
		demand.urgency = float(data.get("urgency", 0.5))
		demand.law_id = String(data.get("law_id", ""))
		return demand


class Wing extends RefCounted:
	var id: String
	var name: String
	var ideology: Ideology
	var strength: float
	var loyalty: float = 0.6
	var kind: String = "wing"
	var description: String = ""
	var policy_biases: Dictionary = {}

	static func from_json(data: Dictionary) -> Wing:
		var w := Wing.new()
		w.id = String(data.get("id", ""))
		w.name = String(data.get("name", ""))
		w.ideology = Ideology.from_json(data.get("ideology", {}))
		w.strength = float(data.get("strength", 0.0))
		w.loyalty = float(data.get("loyalty", 0.6))
		w.kind = String(data.get("kind", "wing"))
		w.description = String(data.get("description", ""))
		w.policy_biases = data.get("policy_biases", {}).duplicate(true)
		return w


	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"ideology": null if ideology == null else ideology.to_dict(),
			"strength": strength,
			"loyalty": loyalty,
			"kind": kind,
			"description": description,
			"policy_biases": policy_biases.duplicate(true),
		}


	static func from_dict(data: Dictionary) -> Wing:
		if not (data is Dictionary):
			push_error("Wing.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var w := Wing.new()
		w.id = String(data.get("id", ""))
		w.name = String(data.get("name", ""))
		var ideo: Variant = data.get("ideology", null)
		if ideo is Dictionary:
			w.ideology = Ideology.from_dict(ideo)
			if w.ideology == null:
				return null
		w.strength = float(data.get("strength", 0.0))
		w.loyalty = float(data.get("loyalty", 0.6))
		w.kind = String(data.get("kind", "wing"))
		w.description = String(data.get("description", ""))
		var biases: Variant = data.get("policy_biases", {})
		w.policy_biases = biases.duplicate(true) if biases is Dictionary else {}
		return w


var id: String
var name: String
var ideology: Ideology
var power: float
var loyalty: float
var seats: int
var in_coalition: bool = false
var grievances: Array[Grievance] = []
var demands: Array[Demand] = []
var support: float = 0.2
var color: String = ""
var wings: Array[Wing] = []
var leader: String = ""
var role: String = ""


func effective_ideology() -> Ideology:
	if wings.is_empty():
		return ideology
	var total := 0.0
	for w in wings:
		total += maxf(0.0, w.strength)
	if total <= 0.0:
		return ideology
	var econ := 0.0
	var soc := 0.0
	for w in wings:
		var s := maxf(0.0, w.strength)
		econ += w.ideology.economic * s
		soc += w.ideology.social * s
	var result := Ideology.new()
	result.economic = econ / total
	result.social = soc / total
	return result


func dominant_wing() -> Wing:
	if wings.is_empty():
		return null
	var best := wings[0]
	for w in wings:
		if w.strength > best.strength:
			best = w
	return best


func cohesion() -> float:
	if wings.size() < 2:
		return 1.0
	var centre := effective_ideology()
	var total := 0.0
	for w in wings:
		total += maxf(0.0, w.strength)
	if total <= 0.0:
		total = 1.0
	var spread := 0.0
	for w in wings:
		spread += w.ideology.distance_to(centre) * maxf(0.0, w.strength)
	spread /= total
	var spread_unity := maxf(0.0, 1.0 - spread / 2.83)
	var loyalty_sum := 0.0
	for w in wings:
		loyalty_sum += w.loyalty
	var loyalty_unity := (loyalty_sum / wings.size() + 1.0) / 2.0
	return clampf(0.5 * spread_unity + 0.5 * loyalty_unity, 0.0, 1.0)


func normalize_wings() -> void:
	if wings.is_empty():
		return
	for w in wings:
		w.strength = maxf(0.0, w.strength)
	var total := 0.0
	for w in wings:
		total += w.strength
	if total <= 0.0:
		for w in wings:
			w.strength = 1.0 / wings.size()
	else:
		for w in wings:
			w.strength /= total


func is_allied() -> bool:
	return in_coalition or loyalty > 0.4


func is_hostile() -> bool:
	return loyalty < -0.3


func opposition_strength() -> float:
	if loyalty >= 0.0:
		return 0.0
	return absf(loyalty) * power


func grievance_pressure() -> float:
	if grievances.is_empty():
		return 0.0
	var total := 0.0
	for g in grievances:
		total += g.severity
	return minf(1.0, total / 3.0)


static func from_json(data: Dictionary) -> Faction:
	var f := Faction.new()
	f.id = String(data.get("id", ""))
	f.name = String(data.get("name", ""))
	f.ideology = Ideology.from_json(data.get("ideology", {}))
	f.power = float(data.get("power", 0.0))
	f.loyalty = float(data.get("loyalty", 0.0))
	f.seats = int(data.get("seats", 0))
	f.in_coalition = bool(data.get("in_coalition", false))
	f.support = float(data.get("support", 0.2))
	f.color = String(data.get("color", ""))
	f.leader = String(data.get("leader", ""))
	f.role = String(data.get("role", ""))

	for g in data.get("grievances", []):
		var grievance := Grievance.new()
		grievance.source = String(g.get("source", ""))
		grievance.severity = float(g.get("severity", 0.0))
		grievance.turns_active = int(g.get("turns_active", 0))
		f.grievances.append(grievance)

	for d in data.get("demands", []):
		var demand := Demand.new()
		demand.description = String(d.get("description", ""))
		demand.urgency = float(d.get("urgency", 0.5))
		demand.law_id = String(d.get("law_id", ""))
		f.demands.append(demand)

	for w in data.get("wings", []):
		f.wings.append(Wing.from_json(w))

	return f


static func generate_default_wings(faction: Faction) -> Array[Wing]:
	var econ := faction.ideology.economic
	var soc := faction.ideology.social
	var mag := sqrt(econ * econ + soc * soc)
	var dx: float
	var dy: float
	if mag < 1e-6:
		dx = 0.0
		dy = 1.0
	else:
		dx = econ / mag
		dy = soc / mag
	var off := 0.22

	var specs := [
		{"suffix": "moderate", "name": "Moderates", "k": -1.0, "strength": 0.35, "loyalty": 0.65},
		{"suffix": "mainstream", "name": "Mainstream", "k": 0.0, "strength": 0.40, "loyalty": 0.70},
		{"suffix": "hardline", "name": "Hardliners", "k": 1.0, "strength": 0.25, "loyalty": 0.55},
	]

	var wings: Array[Wing] = []
	for spec in specs:
		var wing := Wing.new()
		wing.id = "%s_%s" % [faction.id, spec["suffix"]]
		wing.name = spec["name"]
		wing.ideology = Ideology.new()
		wing.ideology.economic = clampf(econ + dx * off * spec["k"], -1.0, 1.0)
		wing.ideology.social = clampf(soc + dy * off * spec["k"], -1.0, 1.0)
		wing.strength = spec["strength"]
		wing.loyalty = spec["loyalty"]
		wing.kind = "wing"
		wings.append(wing)
	return wings


func to_dict() -> Dictionary:
	var grievance_dicts: Array = []
	for g in grievances:
		grievance_dicts.append(g.to_dict())
	var demand_dicts: Array = []
	for d in demands:
		demand_dicts.append(d.to_dict())
	var wing_dicts: Array = []
	for w in wings:
		wing_dicts.append(w.to_dict())
	return {
		"id": id,
		"name": name,
		"ideology": null if ideology == null else ideology.to_dict(),
		"power": power,
		"loyalty": loyalty,
		"seats": seats,
		"in_coalition": in_coalition,
		"grievances": grievance_dicts,
		"demands": demand_dicts,
		"support": support,
		"color": color,
		"wings": wing_dicts,
		"leader": leader,
		"role": role,
	}


static func from_dict(data: Dictionary) -> Faction:
	if not (data is Dictionary):
		push_error("Faction.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var f := Faction.new()
	f.id = String(data.get("id", ""))
	f.name = String(data.get("name", ""))
	var ideo: Variant = data.get("ideology", null)
	if ideo is Dictionary:
		f.ideology = Ideology.from_dict(ideo)
		if f.ideology == null:
			return null
	f.power = float(data.get("power", 0.0))
	f.loyalty = float(data.get("loyalty", 0.0))
	f.seats = _int_field(data, "seats", 0)
	f.in_coalition = _bool_field(data, "in_coalition", false)
	var grievances_data: Variant = data.get("grievances", [])
	if grievances_data is Array:
		for g_data in grievances_data:
			if g_data is Dictionary:
				var grievance := Grievance.from_dict(g_data)
				if grievance != null:
					f.grievances.append(grievance)
	var demands_data: Variant = data.get("demands", [])
	if demands_data is Array:
		for d_data in demands_data:
			if d_data is Dictionary:
				var demand := Demand.from_dict(d_data)
				if demand != null:
					f.demands.append(demand)
	f.support = float(data.get("support", 0.2))
	f.color = String(data.get("color", ""))
	f.leader = String(data.get("leader", ""))
	f.role = String(data.get("role", ""))
	var wings_data: Variant = data.get("wings", [])
	if wings_data is Array:
		for w_data in wings_data:
			if w_data is Dictionary:
				var wing := Wing.from_dict(w_data)
				if wing != null:
					f.wings.append(wing)
	return f


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
