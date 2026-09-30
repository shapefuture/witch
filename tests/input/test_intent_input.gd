extends TestCase

var _now := 0.0

func _input(picker: Callable) -> IntentInput:
	var input: IntentInput = track(IntentInput.new())
	input.picker = picker
	input.clock = func() -> float: return _now
	return input

func _hit_tomas(_p: Vector2) -> Dictionary:
	return {"target_id": "tomas", "ground": Vector3(1, 0, 2), "has_ground": true}

func _hit_ground(p: Vector2) -> Dictionary:
	return {"target_id": "", "ground": Vector3(p.x / 100.0, 0, p.y / 100.0), "has_ground": true}

func _hit_nothing(_p: Vector2) -> Dictionary:
	return {"target_id": "", "has_ground": false}

func _click(input: IntentInput, pos: Vector2, dt: float = 0.1) -> PlayerIntent:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	input.handle_event(down)
	_now += dt
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	return input.handle_event(up)

func _tap(input: IntentInput, pos: Vector2, dt: float = 0.1, index: int = 0) -> PlayerIntent:
	var down := InputEventScreenTouch.new()
	down.index = index
	down.pressed = true
	down.position = pos
	input.handle_event(down)
	_now += dt
	var up := InputEventScreenTouch.new()
	up.index = index
	up.pressed = false
	up.position = pos
	return input.handle_event(up)

func test_tap_and_click_on_an_object_mean_exactly_the_same() -> void:
	var a := _input(_hit_tomas)
	var b := _input(_hit_tomas)
	var clicked := _click(a, Vector2(120, 90))
	var tapped := _tap(b, Vector2(120, 90))
	ok(clicked != null and tapped != null, "both produce an intent")
	ok(clicked.same_meaning(tapped), "semantically identical: %s vs %s" % [clicked.semantic(), tapped.semantic()])
	eq(clicked.type, PlayerIntent.Type.INSPECT, "inspect the target")
	eq(clicked.source, "mouse", "provenance kept for debugging")
	eq(tapped.source, "touch", "provenance kept for debugging")

func test_tap_and_click_on_the_ground_mean_the_same() -> void:
	var clicked := _click(_input(_hit_ground), Vector2(200, 150))
	var tapped := _tap(_input(_hit_ground), Vector2(200, 150))
	ok(clicked.same_meaning(tapped), "same move")
	eq(clicked.type, PlayerIntent.Type.MOVE_TO, "move")

func test_tap_and_click_resolve_to_identical_mirror_actions() -> void:
	# The claim that matters: input device never changes what the engine is asked to do.
	var r := GameFixtures.runtime()
	var r2 := GameFixtures.runtime()
	var clicked := _click(_input(_hit_tomas), Vector2(10, 10))
	var tapped := _tap(_input(_hit_tomas), Vector2(10, 10))
	var option_a: InteractionOption = r.options_for(clicked.target_id).filter(func(o): return o.action_id == "look_tomas")[0]
	var option_b: InteractionOption = r2.options_for(tapped.target_id).filter(func(o): return o.action_id == "look_tomas")[0]
	eq(option_a.to_action().to_dict(), option_b.to_action().to_dict(), "identical action")
	r.resolve_now(option_a.to_action())
	r2.resolve_now(option_b.to_action())
	eq(r.engine.event_store.head_hash(), r2.engine.event_store.head_hash(), "identical event chain")

func test_a_drag_is_not_a_tap() -> void:
	var input := _input(_hit_ground)
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = Vector2(50, 50)
	input.handle_event(down)
	_now += 0.1
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = Vector2(120, 50)
	eq(input.handle_event(up), null, "moved well past the slop")

func test_a_long_press_is_not_a_tap() -> void:
	eq(_tap(_input(_hit_ground), Vector2(50, 50), 0.9), null, "held too long")

func test_a_second_finger_cancels_the_tap() -> void:
	var input := _input(_hit_ground)
	var first := InputEventScreenTouch.new()
	first.index = 0
	first.pressed = true
	first.position = Vector2(50, 50)
	input.handle_event(first)
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.pressed = true
	second.position = Vector2(80, 80)
	input.handle_event(second)
	_now += 0.1
	var up0 := InputEventScreenTouch.new()
	up0.index = 0
	up0.pressed = false
	up0.position = Vector2(50, 50)
	eq(input.handle_event(up0), null, "a pinch is not a tap")
	var up1 := InputEventScreenTouch.new()
	up1.index = 1
	up1.pressed = false
	up1.position = Vector2(80, 80)
	eq(input.handle_event(up1), null, "neither finger taps after a pinch")

func test_tapping_nothing_does_nothing() -> void:
	eq(_click(_input(_hit_nothing), Vector2(1, 1)), null, "no target and no ground")

func test_right_click_cancels() -> void:
	var input := _input(_hit_tomas)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	var intent := input.handle_event(up)
	eq(intent.type, PlayerIntent.Type.CANCEL, "cancel")

func test_disabled_input_ignores_everything() -> void:
	var input := _input(_hit_tomas)
	input.enabled = false
	eq(_click(input, Vector2(5, 5)), null, "presentation in progress: input is off")

func test_intent_semantics_quantise_positions_to_a_millimetre() -> void:
	var a := PlayerIntent.move_to(Vector3(1.0001, 0, 2.0), "mouse")
	var b := PlayerIntent.move_to(Vector3(1.0002, 0, 2.0), "touch")
	ok(a.same_meaning(b), "sub-millimetre noise between devices is not a different intent")
	ok(not a.same_meaning(PlayerIntent.move_to(Vector3(1.01, 0, 2.0))), "a centimetre is")
