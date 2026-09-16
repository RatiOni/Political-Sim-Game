class_name SimRng
extends RefCounted

## A small, deterministic PRNG for the Godot-native simulation.
##
## This is NOT a port of Python's `random` module — nothing in this project
## requires reproducing Python's byte stream (see PLAN.md / task-3-brief.md).
## It only needs to be deterministic *within this Godot build*: the same
## seed must produce the same sequence, run after run, on this machine.
##
## Algorithm: PCG32 (O'Neill, pcg-random.org) — a widely used, well-documented,
## statistically strong 32-bit generator built from a 64-bit linear
## congruential generator (LCG) plus a permutation (xorshift + variable
## rotation) applied to the LCG's internal state before output. Chosen over a
## bespoke generator because it is small, fast, has published reference
## vectors to verify a port against (used while writing this file — see
## godot/tests/native/test_foundation_mechanics.gd for this build's own
## correctness tests), and needs only one 64-bit multiply-add per step.
##
## Reference constants/algorithm (minimal C reference, pcg_basic.c):
##   state_next = state * 6364136223846793005 + inc      (inc must be odd)
##   xorshifted = (uint32)(((state >> 18) ^ state) >> 27)
##   rot        = (uint32)(state >> 59)
##   output     = rotate_right_32(xorshifted, rot)
## `from_seed` expands a single caller-supplied seed into the (initstate,
## initseq) pair PCG32 actually needs via SplitMix64 — the standard technique
## (recommended by PCG's own author) for turning one seed into two well-mixed
## 64-bit values, since a raw/small seed used directly as initstate+initseq
## would produce a visibly weak/short-period stream for the first few draws.
##
## GDScript's `int` is a signed 64-bit integer with NO unsigned 64-bit type,
## and it silently wraps on overflow (two's complement) rather than raising —
## confirmed empirically before writing this file. That silent wraparound is
## actually exactly what the LCG step needs (unsigned-mod-2^64 arithmetic is
## bit-for-bit identical to signed two's-complement wraparound), so the
## multiply-add line needs no masking at all. What DOES need explicit
## handling is right shift: GDScript's `>>` is an ARITHMETIC (sign-extending)
## shift, but PCG32's `state >> n` steps are LOGICAL (zero-filling) shifts on
## an unsigned 64-bit value. `_ushr64` below restores logical-shift behaviour
## by shifting arithmetically and then masking off any sign-extended 1 bits —
## masking wraparound (e.g. `(1 << 63) - 1` computing the 63-one-bits mask via
## silent overflow, since `1 << 63` alone overflows into the sign bit) is used
## deliberately here rather than avoided, since it is exactly the same
## well-defined two's-complement behaviour being relied on for the LCG step.

const MULT_64: int = 6364136223846793005
const MASK_32: int = 0xFFFFFFFF

var _state: int = 0
var _inc: int = 0


static func from_seed(seed: int) -> SimRng:
	var rng := SimRng.new()
	var mixer := _SplitMix64.new(seed)
	var initstate := mixer.next_u64()
	var initseq := mixer.next_u64()
	rng._seed(initstate, initseq)
	return rng


## The save/load boundary: RNG state persists as a plain Dictionary inside
## the save file, exactly like any other serialized GameState field.
func to_dict() -> Dictionary:
	return {"state": _state, "inc": _inc}


static func from_dict(data: Dictionary) -> SimRng:
	if not (data is Dictionary) or not data.has("state") or not data.has("inc"):
		push_error("SimRng.from_dict: malformed data, expected {state:int, inc:int}, got %s" % [data])
		return null
	if typeof(data["state"]) != TYPE_INT or typeof(data["inc"]) != TYPE_INT:
		push_error("SimRng.from_dict: malformed data, 'state'/'inc' must be int, got %s" % [data])
		return null
	var rng := SimRng.new()
	rng._state = data["state"]
	rng._inc = data["inc"]
	return rng


## One PCG32 step, returned as an unsigned 32-bit value in [0, 2^32).
func next_u32() -> int:
	return _step()


## A float in [0.0, 1.0), built from the top 24 bits of a draw (a double's
## mantissa is far more than 24 bits, but 24 bits of entropy from a 32-bit
## generator is already all a single `next_u32()` call can honestly provide).
func next_float() -> float:
	return float(next_u32() >> 8) / float(1 << 24)


## A uniform index in [0, size); -1 for a non-positive size.
## ponytail: modulo-biased for size that doesn't evenly divide 2^32 — the
## bias is undetectable at this generator's actual use sizes (small option
## lists, not shuffling millions of cards.) Rejection sampling if that
## changes.
func choose_index(size: int) -> int:
	if size <= 0:
		return -1
	return next_u32() % size


func _seed(initstate: int, initseq: int) -> void:
	_state = 0
	_inc = (initseq << 1) | 1
	_step()
	_state += initstate
	_step()


func _step() -> int:
	var oldstate := _state
	_state = oldstate * MULT_64 + _inc
	var xorshifted: int = _ushr64(_ushr64(oldstate, 18) ^ oldstate, 27) & MASK_32
	var rot: int = _ushr64(oldstate, 59) & 0x1F
	return _rotr32(xorshifted, rot)


## Logical (zero-filling) right shift of x's 64-bit bit pattern by n (0..64).
static func _ushr64(x: int, n: int) -> int:
	if n <= 0:
		return x
	if n >= 64:
		return 0
	var shifted := x >> n
	if x < 0:
		var keep_bits := 64 - n
		shifted = shifted & ((1 << keep_bits) - 1)
	return shifted


## 32-bit rotate-right of a value already known to fit in [0, 2^32).
static func _rotr32(x: int, r: int) -> int:
	var rr := r & 0x1F
	if rr == 0:
		return x & MASK_32
	return ((x >> rr) | (x << (32 - rr))) & MASK_32


## SplitMix64 (Vigna) — used only to expand one caller seed into PCG32's two
## required 64-bit parameters (see `from_seed` above). Not exposed outside
## this file; it is a seeding utility, not part of SimRng's public contract.
class _SplitMix64:
	var _state: int

	func _init(seed: int) -> void:
		_state = seed

	func next_u64() -> int:
		_state += -7046029254386353131  # 0x9E3779B97F4A7C15, as a signed literal
		var z := _state
		z = (z ^ SimRng._ushr64(z, 30)) * -4658895280553007687   # 0xBF58476D1CE4E5B9
		z = (z ^ SimRng._ushr64(z, 27)) * -7723592293110705685   # 0x94D049BB133111EB
		return z ^ SimRng._ushr64(z, 31)
