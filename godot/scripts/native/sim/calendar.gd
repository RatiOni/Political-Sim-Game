class_name Calendar
extends RefCounted

## Ports the daily-calendar logic engine/turn.py drives GameState with
## (`TurnEngine._advance_calendar_day`, `_advance_to_next_month`,
## `GameState.calendar_date/days_in_current_month`) — a plain Gregorian
## calendar with a running `day_index` (total days simulated since campaign
## start), used instead of Python's `datetime.date` (not available to
## GDScript) so this is a small hand-rolled proleptic-Gregorian calendar
## rather than a library call. Only the day-by-day path (`advance_day`) is
## ported — Python's month-jump `advance()`/`_advance_to_next_month` is a CLI
## compatibility shim the Godot build's GUI-style clock doesn't need.

const _DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	if month == 2 and is_leap_year(year):
		return 29
	return _DAYS_IN_MONTH[month - 1]


## Advances state's calendar by exactly one day, incrementing day_index and
## rolling day -> month -> year as each boundary is crossed. Returns true iff
## the month rolled over (mirrors TurnEngine.advance_day's
## `last_advance_monthly = state.month != previous_month`), which is what the
## caller uses to decide whether to run the heavier monthly simulation pulse.
static func advance_day(state: GameState) -> bool:
	var previous_month := state.month

	state.day += 1
	if state.day > days_in_month(state.year, state.month):
		state.day = 1
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1

	state.day_index += 1
	return state.month != previous_month
