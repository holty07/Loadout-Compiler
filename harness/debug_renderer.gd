extends Control

## godot --script harness/debug_renderer.tscn -- --seed 1234 --loadout fixtures/basic.json
##
## The M2 debug renderer: boxes and labels, no design tokens, no polish,
## thrown away at M4 (docs/M2.md, docs/plan.md's "Testing points"). Exists
## only so a human can watch a run before the real schematic shell lands.
## Loads one recorded run at startup and lets you scrub or play through its
## event log. Everything it shows comes from harness/debug_replay.gd's pure
## functions, never from live sim state — the same "renderer is a pure
## function of the log" discipline the real M4 shell must hold to, even
## though nothing here enforces it with a test.
##
## Needs a display — run it from the Godot editor or `godot` without
## --headless. This file was written and its logic tested headlessly
## (tests/test_debug_replay.gd), but the actual rendering has not been
## visually verified in this environment, which has no display. Open it
## yourself before trusting it.

const DataLoader = preload("res://tools/data_loader.gd")
const Run = preload("res://sim/run.gd")
const DebugReplay = preload("res://harness/debug_replay.gd")

const KIND_COLORS := {
	"fire": Color(0.6, 0.6, 0.6),
	"jam": Color(0.9, 0.6, 0.1),
	"hit": Color(0.9, 0.9, 0.2),
	"kill": Color(0.9, 0.2, 0.2),
	"damage_taken": Color(0.85, 0.3, 0.3),
	"module_offline": Color(0.5, 0.0, 0.0),
	"room_enter": Color(0.2, 0.5, 0.9),
	"spawn": Color(0.2, 0.7, 0.3),
	"run_end": Color(0.1, 0.1, 0.1),
	"vent": Color(0.2, 0.8, 0.8),
}

var _records: Array = []
var _max_tick: int = 0
var _integrity_max: int = 0
var _playing: bool = false

var _slider: HSlider
var _readout: Label
var _event_list: VBoxContainer
var _play_button: Button
var _timer: Timer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_run()
	_build_ui()
	_on_scrub(0.0)

func _load_run() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_val := 1234
	var loadout_path := "fixtures/basic.json"
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			seed_val = int(args[i + 1])
		elif args[i] == "--loadout" and i + 1 < args.size():
			loadout_path = args[i + 1]

	var data := DataLoader.load_all()
	_integrity_max = int(data.get("tuning", {}).get("player", {}).get("integrity_max", 1))

	var module_ids: Array = []
	if FileAccess.file_exists(loadout_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(loadout_path)) == OK:
			module_ids = (json.data as Dictionary).get("modules", [])

	var result := Run.execute(seed_val, module_ids, [], data, false)
	_records = result["log"].records if result.get("ok", false) else []
	_max_tick = 0
	for r in _records:
		_max_tick = max(_max_tick, int(r["tick"]))

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var controls := HBoxContainer.new()
	root.add_child(controls)

	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_on_play_pressed)
	controls.add_child(_play_button)

	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = max(1, _max_tick)
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_scrub)
	controls.add_child(_slider)

	_readout = Label.new()
	root.add_child(_readout)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_event_list = VBoxContainer.new()
	scroll.add_child(_event_list)

	_timer = Timer.new()
	_timer.wait_time = 0.02
	_timer.timeout.connect(_on_tick)
	add_child(_timer)

func _on_play_pressed() -> void:
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"
	if _playing:
		_timer.start()
	else:
		_timer.stop()

func _on_tick() -> void:
	var next_tick: float = _slider.value + 1
	if next_tick > _slider.max_value:
		_playing = false
		_play_button.text = "Play"
		_timer.stop()
		return
	_slider.value = next_tick

func _on_scrub(value: float) -> void:
	var tick := int(value)
	var state := DebugReplay.state_at(_records, tick, _integrity_max)
	_readout.text = "tick=%d/%d  depth=%d  integrity=%d  kills=%d  outcome=%s  offline=%s" % [
		tick, _max_tick, int(state["depth"]), int(state["integrity"]), int(state["kills"]),
		String(state["outcome"]), str(state["offline_modules"]),
	]

	for child in _event_list.get_children():
		child.queue_free()
	for r in DebugReplay.records_up_to(_records, tick):
		_event_list.add_child(_make_event_row(r))

func _make_event_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(16, 16)
	box.color = KIND_COLORS.get(String(r["kind"]), Color(0.4, 0.4, 0.4))
	row.add_child(box)
	var label := Label.new()
	label.text = "t=%-6d %-15s %-24s %s" % [int(r["tick"]), String(r["kind"]), String(r["subject"]), str(r["payload"])]
	row.add_child(label)
	return row
