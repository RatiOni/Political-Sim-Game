class_name Press
extends RefCounted


const MONTHS := ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]
const MAX_SECONDARY_HEADLINES := 4
const UNRANKED := 10

const DRAMA := {
	"vetrenka_retaken": 98, "vetrenka_rout": 97, "vasca_dead": 96,
	"civil_war_out": 95, "vetrenka_settled": 95, "vasca_captured": 94,
	"vetrenka_offensive": 92, "world_civil_war_out": 90, "vasca_exiled": 88,
	"vetrenka_partition": 86, "civil_war_end": 82, "scandal": 80,
	"schemer_ascendant": 78, "vetrenka_talks_failed": 76, "vetrenka_backlash": 74,
	"vasca_unresolved": 72, "situation": 70, "vetrenka_talks": 70,
	"schemer_neutralized": 68, "vasca_isolated": 66, "civil_war_ongoing": 65,
	"vasca_operation": 64, "vote_failed": 60, "vasca_amnesty": 60,
	"vote_passed": 55, "schemer_bought": 52, "protest": 50,
	"situation_lapsed": 47, "situation_resolved": 45, "vetrenka_normalised": 44,
	"schemer_arc": 44, "minister_restless": 42, "wing_takeover": 40,
	"world_axis": 38, "world_feud": 38, "world_arc_ends": 35,
	"minister_appointed": 32, "world_civil_war_end": 28,
	"world_condemn_player": 26, "world_pressure_player": 26,
	"world_court_player": 24, "world_trade_pact": 24,
	"world_condemn": 22, "world_undermine": 22, "world_deepen": 20,
	"vetrenka_incident": 18, "economy_move": 15, "world_deliberates": 12,
}


static var _templates: Dictionary = {}


static func headlines() -> Dictionary:
	if _templates.is_empty():
		_templates = ContentRepository.load_all().get("catalogs", {}).get("press_templates", {})
	return _templates.get("headlines", {})


static func leads() -> Dictionary:
	headlines()
	return _templates.get("leads", {})


static func masthead(state: GameState) -> String:
	return state.country.paper if state.country.paper != "" else "The %s Herald" % state.country.name


static func front_page(state: GameState, before: Dictionary = {}, after: Dictionary = {}) -> Dictionary:
	var ranked: Array = []
	for i in range(state.monthly_news.size()):
		var item: Dictionary = state.monthly_news[i]
		if headlines().has(String(item["key"])):
			ranked.append([int(DRAMA.get(item["key"], UNRANKED)), i])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var lead := {"headline": ("a quiet month in %s" % state.country.name).to_upper(),
		"body": _pick(state, leads().get("quiet", [""]), "b:quiet", {})}
	var used := {}
	var secondary: Array = []
	for r in range(mini(ranked.size(), 1 + MAX_SECONDARY_HEADLINES)):
		var index: int = ranked[r][1]
		var item: Dictionary = state.monthly_news[index]
		var key := String(item["key"])
		used[index] = true
		if r == 0:
			lead = {"headline": _pick(state, headlines()[key], "h:%s" % key, item["fields"]).to_upper(),
				"body": _pick(state, leads().get(key, [""]), "b:%s" % key, item["fields"])}
		else:
			secondary.append(_pick(state, headlines()[key], "h:%s:%d" % [key, index], item["fields"]).to_upper())
	var briefs: Array = []
	for i in range(state.monthly_news.size()):
		if not used.has(i):
			briefs.append(String(state.monthly_news[i]["text"]))
	return {"masthead": masthead(state), "dateline": dateline(state), "lead": lead,
		"headlines": secondary, "briefs": briefs,
		"numbers": [before, after] if not before.is_empty() and not after.is_empty() else []}


static func dateline(state: GameState) -> String:
	return "%s %d" % [MONTHS[clampi(state.month, 1, 12) - 1], state.year]


static func lines(page: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if page.is_empty():
		return out
	out.append("%s — %s" % [page["masthead"], page["dateline"]])
	out.append(String(page["lead"]["headline"]))
	if String(page["lead"]["body"]) != "":
		out.append(String(page["lead"]["body"]))
	for h in page["headlines"]:
		out.append(String(h))
	return out


static func _pick(state: GameState, pool: Array, salt: String, fields: Dictionary) -> String:
	if pool.is_empty():
		return ""
	return String(pool[Voice.variant_index(state.turn, "press:" + salt, 0, pool.size())]).format(fields)
