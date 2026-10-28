class_name Voice
extends RefCounted


static var _pools: Dictionary = {}


static func templates() -> Dictionary:
	if _pools.is_empty():
		_pools = ContentRepository.load_all().get("catalogs", {}).get("dispatch_pools", {})
	return _pools.get("templates", {})


static func markers() -> Dictionary:
	templates()
	return _pools.get("markers", {})


static func render(state: GameState, key: String, fields: Dictionary) -> String:
	var pool: Array = templates().get(key, [])
	if pool.is_empty():
		return ""
	return String(pool[variant_index(state.turn, key, state.monthly_news.size(), pool.size())]).format(fields)


static func variant_index(turn: int, key: String, position: int, size: int) -> int:
	var local := RandomNumberGenerator.new()
	local.seed = ("%d|%s|%d" % [turn, key, position]).hash()
	return local.randi_range(0, size - 1)


static func say(state: GameState, key: String, fields: Dictionary) -> String:
	var text := render(state, key, fields)
	if text == "":
		push_error("Voice.say: no dispatch pool for '%s'" % key)
		return ""
	record(state, key, fields, text)
	return text


static func record(state: GameState, key: String, fields: Dictionary, text: String) -> void:
	state.monthly_news.append({"key": key, "fields": fields.duplicate(), "text": text})


static func leader(c: Country) -> String:
	return c.leader_name if c.leader_name != "" else "%s's leadership" % c.name
