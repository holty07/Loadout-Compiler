extends RefCounted

const Rng = preload("res://sim/rng.gd")
const EventLog = preload("res://sim/log.gd")

func _run_placeholder(seed: int) -> String:
	var rng := Rng.new(seed)
	var log := EventLog.new()
	for tick in range(50):
		log.append(tick, "placeholder_tick", "sim", {"draw": rng.next_below(1000)})
	return log.log_hash()

func test_same_seed_same_hash() -> bool:
	return _run_placeholder(4242) == _run_placeholder(4242)

func test_different_seed_different_hash() -> bool:
	return _run_placeholder(1) != _run_placeholder(2)

func test_callable_twice_same_process_no_shared_state() -> bool:
	var first := _run_placeholder(555)
	var second := _run_placeholder(777)
	var first_again := _run_placeholder(555)
	return first == first_again and first != second
