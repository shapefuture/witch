extends TestCase

# The raccoon of the new references (docs/art/characters_painted.md, "The raccoon of the new references"):
# chubby, upright on two legs, arms crossed on the chest, a big tail sweeping out to the side, a straight hat between the ears.
# The bone and clip names are the game's contract and are checked in test_character_models.gd; this checks the shape.

func _skeleton(visual: Node) -> Skeleton3D:
	var found := visual.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null

func _rest(skeleton: Skeleton3D, bone: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin

func _dispose(visual: Node) -> void:
	visual.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame

func _spawn() -> Node3D:
	var visual := CharacterModels.instantiate("raccoon")
	if visual != null:
		(Engine.get_main_loop() as SceneTree).root.add_child(visual)
	return visual

func test_it_stands_upright_on_two_legs_with_the_tail_behind() -> void:
	var visual := _spawn()
	ok(visual != null, "raccoon loads")
	if visual == null:
		return
	var skeleton := _skeleton(visual)
	ok(skeleton != null, "raccoon has a skeleton")
	if skeleton == null:
		return
	var column := ["foot.L", "leg.L", "hips", "spine", "chest", "head", "hat", "hat_tip"]
	for i in range(1, column.size()):
		ok(_rest(skeleton, column[i]).y > _rest(skeleton, column[i - 1]).y, "%s is above %s" % [column[i], column[i - 1]])
	ok(_rest(skeleton, "foot.L").y < 0.08, "the feet are on the floor")
	ok(_rest(skeleton, "foot.L").x > 0.03 and _rest(skeleton, "foot.R").x < -0.03, "two feet, the left one on +X")
	var hips := _rest(skeleton, "hips")
	ok(_rest(skeleton, "tail1").z < hips.z - 0.05, "the tail starts behind the hips")
	ok(_rest(skeleton, "tail3").z < _rest(skeleton, "tail1").z - 0.15, "the tail trails away behind it")
	ok(_rest(skeleton, "tail3").y < _rest(skeleton, "tail1").y, "the tail droops toward the floor")
	var head_height := _rest(skeleton, "head").y
	ok(head_height > 0.38 * 0.76 and head_height < 0.5, "the head sits at the top of a body about 0.4 m tall (%.2f)" % head_height)
	await _dispose(visual)

func test_the_arms_are_crossed_on_the_chest() -> void:
	var visual := _spawn()
	if visual == null:
		ok(false, "raccoon loads")
		return
	var skeleton := _skeleton(visual)
	var chest := _rest(skeleton, "chest")
	var hand_l := _rest(skeleton, "hand.L")
	var hand_r := _rest(skeleton, "hand.R")
	ok(hand_l.x < -0.01, "the left hand lies across to the right side (x %.3f)" % hand_l.x)
	ok(hand_r.x > 0.01, "the right hand lies across to the left side (x %.3f)" % hand_r.x)
	ok(hand_l.z > chest.z + 0.03 and hand_r.z > chest.z + 0.03, "both hands are in front of the chest")
	ok(absf(hand_l.y - chest.y) < 0.08 and absf(hand_r.y - chest.y) < 0.08, "the hands are at chest height")
	ok(_rest(skeleton, "forearm.L").x > 0.06, "the elbows are out at the sides")
	await _dispose(visual)

func test_it_is_chubby_with_a_big_tail_and_stays_within_the_mobile_budget() -> void:
	var visual := _spawn()
	if visual == null:
		ok(false, "raccoon loads")
		return
	var low := Vector3(1e9, 1e9, 1e9)
	var high := Vector3(-1e9, -1e9, -1e9)
	var surfaces := 0
	var triangles := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var box := mesh_instance.get_aabb()
		low = low.min(box.position)
		high = high.max(box.end)
		surfaces += mesh_instance.mesh.get_surface_count()
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += indices.size() / 3
	var size := high - low
	# The tail sweeps out to one side (raccoon.py TAIL_SIDE), so the width includes it: body plus tail, still compact.
	ok(size.x / size.y > 0.5 and size.x / size.y < 0.95, "chubby with a tail out to the side: %.2f of its height wide" % (size.x / size.y))
	ok(size.x > 0.4, "the tail sticks out to the side: %.2f m across" % size.x)
	ok(size.z > 0.2, "and has depth: %.2f m from snout to the tail's back" % size.z)
	ok(surfaces <= 2, "%d surfaces" % surfaces)
	ok(triangles <= 3000, "%d triangles" % triangles)
	await _dispose(visual)

func _angle(skeleton: Skeleton3D, bone: String) -> float:
	return skeleton.get_bone_pose_rotation(skeleton.find_bone(bone)).get_angle()

func _at(visual: Node, clip: String, time: float) -> void:
	var player := CharacterModels.player_of(visual)
	player.play(clip)
	player.seek(time, true)
	player.advance(0.0)

func test_the_clips_move_the_upright_body() -> void:
	var visual := _spawn()
	if visual == null:
		ok(false, "raccoon loads")
		return
	var skeleton := _skeleton(visual)
	_at(visual, "walk", 0.2)
	ok(_angle(skeleton, "leg.L") > 0.2 and _angle(skeleton, "leg.R") > 0.2, "walk swings the legs")
	ok(_angle(skeleton, "hips") > 0.03, "walk rolls the hips")
	ok(skeleton.get_bone_global_pose(skeleton.find_bone("hand.L")).origin.x < 0.0, "the arms stay crossed while it walks")
	_at(visual, "talk", 1.0)
	ok(_angle(skeleton, "forearm.L") > 0.6, "talk lifts the left forearm off the chest")
	ok(_angle(skeleton, "forearm.R") < 0.01, "the right arm stays crossed while it talks")
	_at(visual, "watch", 1.5)
	ok(_angle(skeleton, "head") > 0.6, "watch turns the head")
	_at(visual, "idle", 1.0)
	ok(_angle(skeleton, "tail2") > 0.02, "idle sways the tail")
	await _dispose(visual)
