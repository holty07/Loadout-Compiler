class_name Fx
extends RefCounted

## Integer fixed-point math. 1 unit = 1/1024 (SHIFT = 10 bits).
## No floats anywhere in this file — sim determinism depends on it.

const SHIFT := 10
const ONE := 1 << SHIFT # 1.0

## Supported operand range is roughly ±1,000,000 whole units. mul()'s
## intermediate product (a * b) must fit in a signed 64-bit integer; values
## within this range keep that product far under the int64 limit (~9.2e18).

static func from_int(i: int) -> int:
	return i << SHIFT

## Truncates toward negative infinity (arithmetic shift), i.e. floor() — not
## truncation toward zero. to_int(-512) == -1, not 0.
static func to_int(f: int) -> int:
	return f >> SHIFT

static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT

## Truncates toward zero (GDScript integer division), unlike to_int()'s floor.
static func div(a: int, b: int) -> int:
	return (a << SHIFT) / b

static func lerp(a: int, b: int, t: int) -> int:
	return a + mul(b - a, t)

static func clamp(x: int, lo: int, hi: int) -> int:
	if x < lo:
		return lo
	if x > hi:
		return hi
	return x
