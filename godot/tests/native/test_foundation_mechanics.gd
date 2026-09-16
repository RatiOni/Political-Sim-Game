extends SceneTree

## Standalone headless test for Task 3: calendar, modifiers, and the
## serializable RNG.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_foundation_mechanics.gd
##
## These tests check the ported logic on its own terms (leap years are leap
## years, a modifier mid-ramp is at the right fraction of its magnitude, a
## restored RNG continues its own sequence) — no comparison against Python is
## made or needed (PLAN.md / task-3-brief.md: no oracle/parity requirement).

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const CalendarScript = preload("res://scripts/native/sim/calendar.gd")
const ModifiersScript = preload("res://scripts/native/sim/modifiers.gd")


# ── Calendar ─────────────────────────────────────────────────────────────

func _test_leap_years(t) -> void:
	t.truth(CalendarScript.is_leap_year(2000), "2000 is a leap year (divisible by 400)")
	t.truth(not CalendarScript.is_leap_year(1900), "1900 is not a leap year (divisible by 100, not 400)")
	t.truth(CalendarScript.is_leap_year(2024), "2024 is a leap year (divisible by 4, not 100)")
	t.truth(not CalendarScript.is_leap_year(2023), "2023 is not a leap year")
	t.truth(not CalendarScript.is_leap_year(2100), "2100 is not a leap year (divisible by 100, not 400)")

	t.equal(CalendarScript.days_in_month(2024, 2), 29, "Feb 2024 has 29 days")
	t.equal(CalendarScript.days_in_month(2023, 2), 28, "Feb 2023 has 28 days")
	t.equal(CalendarScript.days_in_month(2024, 4), 30, "Apr 2024 has 30 days")
	t.equal(CalendarScript.days_in_month(2024, 1), 31, "Jan 2024 has 31 days")


func _test_month_rollover(t) -> void:
	var state := GameState.new()
	state.year = 2024
	state.month = 1
	state.day = 31
	state.day_index = 0

	var rolled := CalendarScript.advance_day(state)
	t.truth(rolled, "advancing past Jan 31 rolls the month over")
	t.equal(state.year, 2024, "year unchanged rolling Jan -> Feb")
	t.equal(state.month, 2, "month becomes February")
	t.equal(state.day, 1, "day resets to 1 on month rollover")
	t.equal(state.day_index, 1, "day_index advances by exactly one day")

	var not_rolled := CalendarScript.advance_day(state)
	t.truth(not not_rolled, "advancing within February does not roll the month")
	t.equal(state.day, 2, "day advances normally mid-month")


func _test_leap_february_rollover(t) -> void:
	var state := GameState.new()
	state.year = 2024
	state.month = 2
	state.day = 28
	state.day_index = 0

	CalendarScript.advance_day(state)
	t.equal(state.day, 29, "leap year Feb 28 -> 29, not straight to March")
	t.equal(state.month, 2, "still February on day 29 of a leap year")

	var rolled := CalendarScript.advance_day(state)
	t.truth(rolled, "Feb 29 -> Mar 1 rolls the month over in a leap year")
	t.equal(state.month, 3, "month becomes March")
	t.equal(state.day, 1, "day resets to 1")


func _test_non_leap_february_rollover(t) -> void:
	var state := GameState.new()
	state.year = 2023
	state.month = 2
	state.day = 28
	state.day_index = 0

	var rolled := CalendarScript.advance_day(state)
	t.truth(rolled, "non-leap Feb 28 -> Mar 1 rolls the month over")
	t.equal(state.month, 3, "month becomes March (no Feb 29 in 2023)")
	t.equal(state.day, 1, "day resets to 1")


func _test_year_rollover(t) -> void:
	var state := GameState.new()
	state.year = 2024
	state.month = 12
	state.day = 31
	state.day_index = 500

	var rolled := CalendarScript.advance_day(state)
	t.truth(rolled, "Dec 31 -> Jan 1 rolls the month over")
	t.equal(state.year, 2025, "year increments on Dec -> Jan rollover")
	t.equal(state.month, 1, "month becomes January")
	t.equal(state.day, 1, "day resets to 1")
	t.equal(state.day_index, 501, "day_index keeps counting across the year boundary")


func _test_day_index_continuity(t) -> void:
	var state := GameState.new()
	state.year = 2023
	state.month = 1
	state.day = 1
	state.day_index = 0

	# Walk a full non-leap year plus a few days of the next one; day_index
	# must land exactly on "days walked", one step at a time, with no gaps
	# or double-counts across any month/year boundary crossed along the way.
	var days_to_walk := 370
	for i in range(days_to_walk):
		CalendarScript.advance_day(state)
		t.equal(state.day_index, i + 1, "day_index continuity at step %d" % (i + 1))

	t.equal(state.day_index, days_to_walk, "day_index equals total days advanced")
	t.equal(state.year, 2024, "walking 370 days from 2023-01-01 reaches 2024")


# ── Modifiers ────────────────────────────────────────────────────────────

func _make_modifier(magnitude: float, onset_delay: int, ramp_duration: int,
		hold_duration: int, decay_duration: int, institutional: bool = true) -> Modifier:
	var m := Modifier.new()
	m.id = "test"
	m.source = "test"
	m.target = "gdp_growth"
	m.magnitude = magnitude
	m.onset_delay = onset_delay
	m.ramp_duration = ramp_duration
	m.hold_duration = hold_duration
	m.decay_duration = decay_duration
	m.institutional = institutional
	m.age = 0
	return m


func _test_modifier_lifecycle(t) -> void:
	# onset=2, ramp=4, hold=3, decay=5, magnitude=10 — hand-computed against
	# the documented onset -> ramp -> hold -> decay -> gone phases.
	var m := _make_modifier(10.0, 2, 4, 3, 5)

	var expected := {
		0: 0.0, 1: 0.0,
		2: 2.5, 3: 5.0, 4: 7.5, 5: 10.0,
		6: 10.0, 7: 10.0, 8: 10.0,
		9: 8.0, 10: 6.0, 11: 4.0, 12: 2.0, 13: 0.0,
	}
	for age in expected.keys():
		m.age = age
		t.near(ModifiersScript.current_value(m), expected[age], 0.0001,
			"modifier current_value at age %d" % age)

	m.age = 13
	t.truth(not ModifiersScript.is_expired(m), "modifier not yet expired at age 13 (total life 14)")
	m.age = 14
	t.truth(ModifiersScript.is_expired(m), "modifier expired at age 14 (== total life)")
	t.near(ModifiersScript.current_value(m), 0.0, 0.0001, "expired modifier reads 0.0")


func _test_modifier_indefinite_hold(t) -> void:
	# hold_duration = -1 is this port's sentinel for Python's hold_duration=None:
	# holds at full magnitude forever, never auto-expires.
	var m := _make_modifier(5.0, 1, 2, -1, 0)

	t.near(ModifiersScript.current_value(m), 0.0, 0.0001, "age 0: before onset")
	m.age = 0
	t.near(ModifiersScript.current_value(m), 0.0, 0.0001, "still pending at age 0 (onset_delay=1)")
	m.age = 1
	t.near(ModifiersScript.current_value(m), 2.5, 0.0001, "ramping in at age 1")
	m.age = 2
	t.near(ModifiersScript.current_value(m), 5.0, 0.0001, "fully ramped at age 2")

	for age in [3, 100, 100000]:
		m.age = age
		t.near(ModifiersScript.current_value(m), 5.0, 0.0001,
			"indefinite modifier holds at full magnitude at age %d" % age)
		t.truth(not ModifiersScript.is_expired(m),
			"indefinite modifier never expires at age %d" % age)


func _test_modifier_institutional_flag_not_discounted_here(t) -> void:
	# `institutional=False` is reserved for effects (loan interest) that no
	# minister/crisis discount can touch — but that discount is applied by
	# the turn engine reading `current_value()` from the outside (Python:
	# `_modifiers_sum`), not inside current_value() itself. So at this layer
	# an institutional=False modifier's lifecycle math must be byte-for-byte
	# identical to an otherwise-identical institutional=True one — this test
	# pins that current_value()/is_expired() never apply a hidden discount.
	var institutional := _make_modifier(8.0, 1, 3, 2, 2, true)
	var contractual := _make_modifier(8.0, 1, 3, 2, 2, false)

	for age in range(0, 10):
		institutional.age = age
		contractual.age = age
		t.equal(ModifiersScript.current_value(institutional), ModifiersScript.current_value(contractual),
			"institutional flag does not change current_value at age %d" % age)
		t.equal(ModifiersScript.is_expired(institutional), ModifiersScript.is_expired(contractual),
			"institutional flag does not change is_expired at age %d" % age)


func _test_age_all(t) -> void:
	var state := GameState.new()
	state.modifiers = []

	# About to expire on this exact age-up (total life 2+0+0+0 = 2, currently
	# at age 1 -> becomes age 2 -> expired -> dropped).
	var about_to_expire := _make_modifier(3.0, 2, 0, 0, 0)
	about_to_expire.age = 1
	about_to_expire.id = "expiring"

	# Indefinite: never dropped no matter how many times it's aged.
	var indefinite := _make_modifier(4.0, 0, 1, -1, 0)
	indefinite.age = 5
	indefinite.id = "indefinite"

	state.modifiers.append(about_to_expire)
	state.modifiers.append(indefinite)

	ModifiersScript.age_all(state)

	t.equal(state.modifiers.size(), 1, "age_all drops the modifier that just expired")
	if state.modifiers.size() == 1:
		t.equal(state.modifiers[0].id, "indefinite", "the surviving modifier is the indefinite one")
		t.equal(state.modifiers[0].age, 6, "the surviving modifier's age was incremented")

	# Age it many more times — still never dropped.
	for i in range(50):
		ModifiersScript.age_all(state)
	t.equal(state.modifiers.size(), 1, "indefinite modifier survives repeated aging")
	t.equal(state.modifiers[0].age, 56, "indefinite modifier's age keeps accumulating")


# ── SimRng ───────────────────────────────────────────────────────────────

func _test_rng_determinism(t) -> void:
	var a := SimRng.from_seed(12345)
	var b := SimRng.from_seed(12345)

	var mismatch := false
	for i in range(200):
		if a.next_u32() != b.next_u32():
			mismatch = true
			break
	t.truth(not mismatch, "two SimRngs from the same seed produce an identical u32 sequence")

	var c := SimRng.from_seed(12345)
	var d := SimRng.from_seed(54321)
	var any_diff := false
	for i in range(20):
		if c.next_u32() != d.next_u32():
			any_diff = true
			break
	t.truth(any_diff, "different seeds produce different sequences")


func _test_rng_round_trip(t) -> void:
	var original := SimRng.from_seed(777)
	# Burn some draws so we're not testing the trivial just-seeded state.
	for i in range(10):
		original.next_u32()

	var saved_dict := original.to_dict()

	# Continue drawing from the original — this is the "truth" the restored
	# copy must reproduce exactly.
	var expected: Array = []
	for i in range(25):
		expected.append(original.next_u32())

	var restored := SimRng.from_dict(saved_dict)
	t.truth(restored != null, "from_dict succeeds on a well-formed dict")
	if restored == null:
		return

	var actual: Array = []
	for i in range(25):
		actual.append(restored.next_u32())

	t.equal(actual, expected, "a restored SimRng continues exactly where to_dict() snapshotted it")

	# The dict itself round-trips as plain data (the save-file boundary).
	t.truth(saved_dict.has("state") and saved_dict.has("inc"), "to_dict exposes state/inc")


func _test_rng_rejects_malformed_seed(t) -> void:
	t.equal(SimRng.from_dict({}), null, "from_dict rejects an empty dict")
	t.equal(SimRng.from_dict({"state": 1}), null, "from_dict rejects a dict missing 'inc'")
	t.equal(SimRng.from_dict({"inc": 1}), null, "from_dict rejects a dict missing 'state'")
	t.equal(SimRng.from_dict({"state": "not-an-int", "inc": 1}), null,
		"from_dict rejects a non-int 'state'")
	t.equal(SimRng.from_dict({"state": 1, "inc": 1.5}), null,
		"from_dict rejects a non-int 'inc'")
	t.equal(SimRng.from_dict({"state": 1, "inc": null}), null,
		"from_dict rejects a null 'inc'")


func _test_rng_output_ranges(t) -> void:
	var rng := SimRng.from_seed(999)
	var saw_zero_or_more := true
	for i in range(500):
		var f := rng.next_float()
		if f < 0.0 or f >= 1.0:
			saw_zero_or_more = false
			break
	t.truth(saw_zero_or_more, "next_float() always lands in [0.0, 1.0) over 500 draws")

	var rng2 := SimRng.from_seed(999)
	var in_range := true
	for i in range(500):
		var idx := rng2.choose_index(7)
		if idx < 0 or idx >= 7:
			in_range = false
			break
	t.truth(in_range, "choose_index(7) always lands in [0, 7) over 500 draws")

	t.equal(rng2.choose_index(0), -1, "choose_index(0) returns -1")
	t.equal(rng2.choose_index(-3), -1, "choose_index(negative) returns -1")


func _initialize() -> void:
	var t = TestSupportScript.new()

	_test_leap_years(t)
	_test_month_rollover(t)
	_test_leap_february_rollover(t)
	_test_non_leap_february_rollover(t)
	_test_year_rollover(t)
	_test_day_index_continuity(t)

	_test_modifier_lifecycle(t)
	_test_modifier_indefinite_hold(t)
	_test_modifier_institutional_flag_not_discounted_here(t)
	_test_age_all(t)

	_test_rng_determinism(t)
	_test_rng_round_trip(t)
	_test_rng_rejects_malformed_seed(t)
	_test_rng_output_ranges(t)

	quit(t.finish())
