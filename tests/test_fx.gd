extends RefCounted

const Fx = preload("res://sim/fx.gd")

func test_from_int_to_int_roundtrip() -> bool:
	var v := Fx.from_int(5)
	if Fx.to_int(v) != 5:
		print("  expected 5, got %d" % Fx.to_int(v))
		return false
	return true

func test_mul() -> bool:
	var half := Fx.ONE / 2
	var result := Fx.mul(Fx.from_int(10), half)
	if result != Fx.from_int(5):
		print("  expected %d, got %d" % [Fx.from_int(5), result])
		return false
	return true

func test_div() -> bool:
	# 10 / 4 = 2.5 -> 2560 in fixed point (2.5 * 1024).
	var result := Fx.div(Fx.from_int(10), Fx.from_int(4))
	if result != 2560:
		print("  expected 2560, got %d" % result)
		return false
	return true

func test_div_truncates_toward_zero() -> bool:
	# -1 / 3 = -0.333..., truncated toward zero -> -341, not floor's -342.
	var result := Fx.div(Fx.from_int(-1), Fx.from_int(3))
	if result != -341:
		print("  expected -341, got %d" % result)
		return false
	return true

func test_to_int_floors_negative() -> bool:
	if Fx.to_int(Fx.from_int(-1)) != -1:
		return false
	# -512 is -0.5 in fixed point; to_int floors toward -infinity, so -1, not 0.
	if Fx.to_int(-512) != -1:
		print("  expected floor(-0.5) == -1, got %d" % Fx.to_int(-512))
		return false
	return true

func test_clamp() -> bool:
	if Fx.clamp(Fx.from_int(50), Fx.from_int(0), Fx.from_int(10)) != Fx.from_int(10):
		return false
	if Fx.clamp(Fx.from_int(-5), Fx.from_int(0), Fx.from_int(10)) != Fx.from_int(0):
		return false
	return true

func test_lerp() -> bool:
	var t_half := Fx.ONE / 2
	var result := Fx.lerp(Fx.from_int(0), Fx.from_int(10), t_half)
	if result != Fx.from_int(5):
		print("  expected %d, got %d" % [Fx.from_int(5), result])
		return false
	return true

func test_mul_at_supported_range_extreme() -> bool:
	# Documented supported range is roughly ±1,000,000 whole units; confirm
	# no silent overflow at that boundary.
	var big := Fx.from_int(1000000)
	var result := Fx.mul(big, Fx.from_int(2))
	if result != Fx.from_int(2000000):
		print("  expected %d, got %d" % [Fx.from_int(2000000), result])
		return false
	return true
