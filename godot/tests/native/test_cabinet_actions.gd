extends SceneTree

## Task 14 red test: cabinet appointments must become a native, save-safe
## player action. This file intentionally precedes CabinetActions.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const CabinetActionsScript = preload("res://scripts/native/actions/cabinet_actions.gd")

static func _state(content: Dictionary, role: String = "government") -> GameState:
	return GameFactoryScript.new_campaign(content, {"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": role, "seed": 424242})

func _test_shortlist_is_stable_and_appointment_is_exact_once(t, content: Dictionary) -> void:
	var state := _state(content)
	var before := state.to_dict()
	var issued := CabinetActionsScript.issue_shortlist(state, "Finance")
	t.truth(issued.get("ok", false), "government can issue a Finance shortlist")
	var model := CabinetActionsScript.read_model(state)
	t.equal(model["portfolios"][0].get("candidates", []).size(), 3, "shortlist exposes three candidates")
	t.truth(state.to_dict() != before, "issuing a shortlist records it in campaign state")
	var candidate_id := str(model["portfolios"][0]["candidates"][0]["id"])
	var appointed := CabinetActionsScript.appoint(state, "Finance", candidate_id)
	t.truth(appointed.get("ok", false), "listed candidate can be appointed")
	t.truth(not CabinetActionsScript.appoint(state, "Finance", candidate_id).get("ok", true), "consumed candidate cannot be appointed twice")

func _test_guards_are_atomic(t, content: Dictionary) -> void:
	var opposition := _state(content, "opposition")
	var before := opposition.to_dict()
	t.truth(not CabinetActionsScript.issue_shortlist(opposition, "Finance").get("ok", true), "opposition cannot make government cabinet appointments")
	t.equal(opposition.to_dict(), before, "refused opposition appointment is atomic")
	var government := _state(content)
	var prior := government.to_dict()
	t.truth(not CabinetActionsScript.appoint(government, "Finance", "forged").get("ok", true), "forged candidate id is refused")
	t.equal(government.to_dict(), prior, "forged appointment is atomic")

func _initialize() -> void:
	var t = TestSupportScript.new()
	var content := ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for cabinet action tests")
	if not content.has("error"):
		_test_shortlist_is_stable_and_appointment_is_exact_once(t, content)
		_test_guards_are_atomic(t, content)
	quit(t.finish())