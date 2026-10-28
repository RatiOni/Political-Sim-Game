class_name SimRng
extends RefCounted


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


static func from_state_seq(initstate: int, initseq: int) -> SimRng:
	var rng := SimRng.new()
	rng._seed(initstate, initseq)
	return rng


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


func next_u32() -> int:
	return _step()


func next_float() -> float:
	return float(next_u32() >> 8) / float(1 << 24)


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


static func _rotr32(x: int, r: int) -> int:
	var rr := r & 0x1F
	if rr == 0:
		return x & MASK_32
	return ((x >> rr) | (x << (32 - rr))) & MASK_32


class _SplitMix64:
	const GOLDEN_GAMMA: int = -7046029254386353131
	const MIX_MULT_1: int = -4658895280553007687
	const MIX_MULT_2: int = -7723592293110705685

	var _state: int

	func _init(seed: int) -> void:
		_state = seed

	func next_u64() -> int:
		_state += GOLDEN_GAMMA
		var z := _state
		z = (z ^ SimRng._ushr64(z, 30)) * MIX_MULT_1
		z = (z ^ SimRng._ushr64(z, 27)) * MIX_MULT_2
		return z ^ SimRng._ushr64(z, 31)
