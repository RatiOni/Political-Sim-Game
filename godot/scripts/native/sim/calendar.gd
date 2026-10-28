class_name Calendar
extends RefCounted


const _DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	if month == 2 and is_leap_year(year):
		return 29
	return _DAYS_IN_MONTH[month - 1]


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
