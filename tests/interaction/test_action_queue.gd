extends TestCase

class Recorder:
	extends RefCounted
	var log: Array[String] = []
	var release := Signal()

func _make_queue(log: Array[String], present_delay_frames: int = 0) -> ActionQueue:
	var queue := ActionQueue.new()
	queue.resolver = func(action: MirrorAction) -> Dictionary:
		log.append("resolve:%s" % action.id)
		return {"ok": action.id != "bad", "id": action.id}
	queue.presenter = func(result: Dictionary) -> void:
		log.append("present:%s" % result["id"])
	return queue

func test_actions_resolve_and_present_in_fifo_order() -> void:
	var log: Array[String] = []
	var queue := _make_queue(log)
	queue.enqueue(MirrorAction.new("a"))
	queue.enqueue(MirrorAction.new("b"))
	eq(log, ["resolve:a", "present:a", "resolve:b", "present:b"], "each action is fully presented before the next resolves")
	ok(not queue.is_busy(), "idle when drained")

func test_failed_actions_are_not_presented() -> void:
	var log: Array[String] = []
	var queue := _make_queue(log)
	queue.enqueue(MirrorAction.new("bad"))
	eq(log, ["resolve:bad"], "nothing plays for a refused action")

func test_a_second_action_cannot_commit_while_the_first_is_presenting() -> void:
	var log: Array[String] = []
	var gate := Signal()
	var holder := {"emitter": null}
	var emitter := GateEmitter.new()
	var queue := ActionQueue.new()
	queue.resolver = func(action: MirrorAction) -> Dictionary:
		log.append("resolve:%s" % action.id)
		return {"ok": true, "id": action.id}
	queue.presenter = func(result: Dictionary) -> void:
		log.append("present-start:%s" % result["id"])
		await emitter.opened
		log.append("present-end:%s" % result["id"])
	queue.enqueue(MirrorAction.new("a"))
	queue.enqueue(MirrorAction.new("b"))
	eq(log, ["resolve:a", "present-start:a"], "b is waiting, not interleaved")
	ok(queue.is_busy(), "busy during presentation")
	eq(queue.pending_count(), 1, "b is queued")
	emitter.opened.emit()
	eq(log, ["resolve:a", "present-start:a", "present-end:a", "resolve:b", "present-start:b"], "b resolves only after a finished")
	emitter.opened.emit()
	ok(not queue.is_busy(), "drained")

func test_runtime_serialises_real_actions_through_the_queue() -> void:
	var r := GameFixtures.runtime()
	var order: Array[String] = []
	var emitter := GateEmitter.new()
	r.presenter = func(_presentation: Array, result: Dictionary) -> void:
		order.append("present:%s" % result["events"][0].payload["action"]["id"])
		await emitter.opened
	r.submit(r.make_action("look_tomas", "tomas"))
	r.submit(r.make_action("look_bell", "bell"))
	ok(r.is_busy(), "busy while the first presentation plays")
	eq(r.engine.event_store.size(), 3, "only the prologue and the first action are committed")
	ok(not r.engine.knowledge.has("bell_tilted_into_wind"), "the second action has not committed")
	emitter.opened.emit()
	emitter.opened.emit()
	ok(not r.is_busy(), "drained")
	eq(order, ["present:look_tomas", "present:look_bell"], "presented strictly in order")
	ok(r.engine.knowledge.has("bell_tilted_into_wind"), "second action committed afterwards")

class GateEmitter:
	extends RefCounted
	signal opened
