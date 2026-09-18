extends RefCounted

const Rng = preload("res://sim/rng.gd")

func test_same_seed_same_sequence() -> bool:
	var a := Rng.new(1234)
	var b := Rng.new(1234)
	for i in 20:
		if a.next_u64() != b.next_u64():
			return false
	return true

func test_different_seed_different_sequence() -> bool:
	var a := Rng.new(1)
	var b := Rng.new(2)
	var any_diff := false
	for i in 5:
		if a.next_u64() != b.next_u64():
			any_diff = true
	return any_diff

func test_next_below_within_bound() -> bool:
	var r := Rng.new(42)
	for i in 200:
		var v := r.next_below(37)
		if v < 0 or v >= 37:
			print("  out of bound: %d" % v)
			return false
	return true

func test_state_roundtrip() -> bool:
	var a := Rng.new(99)
	a.next_u64()
	a.next_u64()
	var state := a.get_state()
	var b := Rng.new(0)
	b.set_state(state)
	return a.next_u64() == b.next_u64()

func test_instances_do_not_share_state() -> bool:
	var a := Rng.new(7)
	var seq_a: Array = []
	for i in 5:
		seq_a.append(a.next_u64())
	var b := Rng.new(1234567)
	for i in 5:
		b.next_u64()
	var c := Rng.new(7)
	for i in 5:
		if c.next_u64() != seq_a[i]:
			return false
	return true
