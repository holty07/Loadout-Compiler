class_name Rng
extends RefCounted

## Seeded xorshift128+. No global state — every draw comes from an explicit
## instance, and state is fully serialisable via get_state()/set_state().
##
## GDScript's ">>" is an arithmetic (sign-extending) shift, but xorshift128+
## requires a logical shift. _ushr() emulates one without floats or 32-bit
## splitting: masking after an arithmetic shift clears the incorrectly
## sign-extended high bits.

var _s0: int
var _s1: int

func _init(seed: int = 0) -> void:
	seed_with(seed)

func seed_with(seed: int) -> void:
	var state := seed
	state += _SPLITMIX_GAMMA
	var v0 := _splitmix64_value(state)
	state += _SPLITMIX_GAMMA
	var v1 := _splitmix64_value(state)
	_s0 = v0
	_s1 = v1
	if _s0 == 0 and _s1 == 0:
		_s0 = 1

# GDScript hex literals above 0x7FFFFFFFFFFFFFFF fail to parse rather than
# wrapping into the negative two's-complement bit pattern, so these constants
# are written as their signed 64-bit decimal equivalents:
#   -7046029254386353131 == 0x9E3779B97F4A7C15 (splitmix64 golden gamma)
#   -4658895280553007687 == 0xBF58476D1CE4E5B9
#   -7723592293110705685 == 0x94D049BB133111EB
const _SPLITMIX_GAMMA := -7046029254386353131
const _SPLITMIX_MUL_1 := -4658895280553007687
const _SPLITMIX_MUL_2 := -7723592293110705685

static func _splitmix64_value(state: int) -> int:
	var z := state
	z = (z ^ _ushr(z, 30)) * _SPLITMIX_MUL_1
	z = (z ^ _ushr(z, 27)) * _SPLITMIX_MUL_2
	return z ^ _ushr(z, 31)

static func _ushr(x: int, n: int) -> int:
	if n <= 0:
		return x
	return (x >> n) & (0x7FFFFFFFFFFFFFFF >> (n - 1))

func next_u64() -> int:
	var x := _s0
	var y := _s1
	_s0 = y
	x ^= x << 23
	x ^= _ushr(x, 17)
	x ^= y ^ _ushr(y, 26)
	_s1 = x
	return x + y

## Uniform draw in [0, bound). Modulo reduction on the low 63 bits — fine for
## a game RNG, not intended to be cryptographically uniform.
func next_below(bound: int) -> int:
	return (next_u64() & 0x7FFFFFFFFFFFFFFF) % bound

func get_state() -> Array:
	return [_s0, _s1]

func set_state(state: Array) -> void:
	_s0 = state[0]
	_s1 = state[1]
