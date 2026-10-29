class_name DayCycle
extends RefCounted

## One clock for daylight, shared by the map and every city view, so the
## country turns from day to night together as you play.
##
## A full day lasts PERIOD real seconds (7.5 min): long day, dusk, long night,
## dawn. `skip()` (the map's day/night button) jumps half a day ahead; the
## cycle keeps running from there.

const PERIOD := 450.0

static var _offset := 0.0


static func phase() -> float:
	return fposmod(Time.get_ticks_msec() / 1000.0 / PERIOD + _offset, 1.0)


## 1 at full day, 0 at full night. Day centres on phase 0, night on 0.5;
## dusk and dawn each take about 6% of the cycle (~30 s).
static func daylight() -> float:
	return smoothstep(-0.2, 0.2, cos(TAU * phase()))


static func is_night() -> bool:
	return daylight() < 0.5


static func skip() -> void:
	_offset += 0.5
