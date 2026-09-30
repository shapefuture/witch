class_name InteractionProbe
extends RefCounted

# Turns a point on the screen into "what is being pointed at": an Interactable if the ray hits
# one, otherwise the ground. Because fingers are fat and the render is 320x240, a tap that
# misses every pick volume still snaps to the nearest interactable within a few pixels.

const SNAP_PIXELS := 14.0
const RAY_LENGTH := 100.0

var camera: Camera3D

func _init(p_camera: Camera3D = null) -> void:
	camera = p_camera

# Returns {"target_id": String, "ground": Vector3, "has_ground": bool}.
func pick(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var space := camera.get_world_3d().direct_space_state
	var ground_point := Vector3.ZERO
	var has_ground := false
	var ground_query := PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_LENGTH, PhysicsLayers.GROUND)
	var ground_hit := space.intersect_ray(ground_query)
	if not ground_hit.is_empty():
		ground_point = ground_hit["position"]
		has_ground = true
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_LENGTH, PhysicsLayers.INTERACTABLE)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is Interactable:
		var interactable := hit["collider"] as Interactable
		return {"target_id": interactable.target_id, "ground": ground_point, "has_ground": has_ground}
	var snapped := _nearest_on_screen(screen_position)
	if not snapped.is_empty():
		return {"target_id": snapped, "ground": ground_point, "has_ground": has_ground}
	return {"target_id": "", "ground": ground_point, "has_ground": has_ground}

func _nearest_on_screen(screen_position: Vector2) -> String:
	var best := ""
	var best_distance := SNAP_PIXELS
	for node in camera.get_tree().get_nodes_in_group("interactable"):
		var interactable := node as Interactable
		if interactable == null or camera.is_position_behind(interactable.focus_point()):
			continue
		var distance := camera.unproject_position(interactable.focus_point()).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = interactable.target_id
	return best
