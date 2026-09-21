extends "res://tests/p1_test.gd"
## P2's real imported skin and clips, through scene input and engine frames.
## Run after importing office_worker.glb; never substitute the P1 capsule.
## bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p2_test.gd
## Browser capture and visual anatomy/animation quality need separate acceptance.
const MODEL_PATH := "res://assets/characters/office_worker.glb"
const SAMPLE_ACTIONS := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "roll"]
const SAMPLE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _collider: CollisionShape3D


func _run() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		_check(false, "P2 requires the actual imported office_worker.glb asset")
		print("P2_TEST_RESULT passed=%d failed=%d" % [passed, failed])
		quit(1)
		return
	world = load("res://scenes/p2.tscn").instantiate()
	root.add_child(world)
	await _frames(6)
	_check(world.phase == "menu", "P2 opens at its sample menu")
	if not _inspect_humanoid():
		await _finish()
		return
	_barrier(ARENA + Vector3(0, -0.3, 0), Vector3(40, 0.5, 40), false)
	world.start_game()
	await _frames(3)
	_check(world.phase == "playing" and world.player.preview_action.is_empty(),
		"P2 starts in normal humanoid walking mode")
	await _test_humanoid_movement()
	await _test_six_animation_previews()
	await _test_preview_camera_controls()
	await _test_preview_pause_and_reset()
	await _finish()


func _inspect_humanoid() -> bool:
	var actor: Node3D = world.player.actor
	_skeleton = actor.skeleton as Skeleton3D
	_animation_player = actor.animation_player as AnimationPlayer
	for child in world.player.get_children():
		if child is CollisionShape3D:
			_collider = child
	var real_skeleton := is_instance_valid(_skeleton) and _skeleton.get_bone_count() >= 15
	_check(real_skeleton, "Displayed actor has a real humanoid Skeleton3D with at least 15 bones")
	_check(is_instance_valid(_animation_player), "Imported actor contains an AnimationPlayer")
	_check(is_instance_valid(_collider) and _collider.shape is CapsuleShape3D,
		"P2 retains the separate standing gameplay collision body")
	if not real_skeleton or not is_instance_valid(_animation_player) or not is_instance_valid(_collider):
		return false
	var skinned_meshes := 0
	var weighted_vertices := 0
	var capsule_meshes := 0
	for node in world.player.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh is CapsuleMesh:
			capsule_meshes += 1
		if mesh_instance.skin == null or mesh_instance.skin.get_bind_count() == 0:
			continue
		if mesh_instance.get_node_or_null(mesh_instance.skeleton) != _skeleton:
			continue
		skinned_meshes += 1
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for weight in weights:
				if weight > 0.0001:
					weighted_vertices += 1
	_check(skinned_meshes > 0 and weighted_vertices > 0,
		"Imported mesh has skin binds, nonzero weights and a valid link to the displayed skeleton")
	_check(capsule_meshes == 0 and world.player.visual == actor,
		"P2 displays the imported skinned actor without a fallback capsule mesh")
	var depth_safe := true
	var cutouts := 0
	for material in actor.materials:
		depth_safe = depth_safe and material.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]
		if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			cutouts += 1
	_check(depth_safe and cutouts == 2,
		"Skin and clothes write opaque depth; only hair and brows use cutouts, avoiding face/clothing sorting artifacts")
	var copy: Node3D = load("res://scripts/humanoid_actor.gd").new()
	root.add_child(copy)
	actor.set_camera_alpha(0.3)
	var independent := true
	for material in copy.materials:
		independent = independent and is_equal_approx(material.albedo_color.a, 1.0)
	actor.set_camera_alpha(1.0)
	for index in actor.materials.size():
		independent = independent and actor.materials[index] != copy.materials[index] \
			and actor.materials[index].transparency == copy.materials[index].transparency \
			and is_equal_approx(actor.materials[index].albedo_color.a, 1.0)
	_check(independent, "Camera fading affects one actor only and restores the original opaque/cutout materials")
	copy.queue_free()
	var clips_complete := true
	for action in SAMPLE_ACTIONS:
		var clip := _clip_for(action)
		var bone_tracks := 0
		if clip != null:
			for track in clip.get_track_count():
				if clip.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] \
					and clip.track_get_path(track).get_subname_count() > 0 and clip.track_get_key_count(track) > 1:
					bone_tracks += 1
		var valid := clip != null and clip.length > 0.1 and bone_tracks > 0
		clips_complete = clips_complete and valid
		_check(valid, "%s has an imported, timed clip with keyed skeleton tracks" % action)
	return clips_complete and skinned_meshes > 0 and weighted_vertices > 0


func _test_humanoid_movement() -> void:
	for key in [KEY_W, KEY_S]:
		await _place(ARENA, 0.4)
		var before: Vector3 = world.player.global_position
		var heading: float = world.player.rotation.y
		var camera_heading: float = world.rig.yaw
		_key(key, true)
		await _frames(30)
		var status: Dictionary = world.player.get_animation_status()
		var displacement: Vector3 = world.player.global_position - before
		displacement.y = 0.0
		var expected := Vector3.FORWARD.rotated(Vector3.UP, heading)
		if key == KEY_S:
			expected = -expected
		_check(displacement.length() > 0.5 and displacement.normalized().dot(expected) > 0.995,
			"Humanoid %s input physically moves along the expected actor-relative direction" % ("W" if key == KEY_W else "S"))
		_check(_angle_error(world.player.rotation.y, heading) < 0.001 and _angle_error(world.rig.yaw, camera_heading) < 0.03,
			"Humanoid %s keeps actor and camera heading; backward walking does not turn them around" % ("W" if key == KEY_W else "S"))
		_check(status.get("action") == "walk" and (float(status.get("rate", 0.0)) > 0.0 if key == KEY_W else float(status.get("rate", 0.0)) < 0.0),
			"Humanoid %s selects a walking clip with the correct playback direction" % ("W" if key == KEY_W else "S"))
		_key(key, false)
		await _frames(5)
		_check(world.player.get_animation_status().get("action") == "idle",
			"Releasing %s restores the humanoid idle clip" % ("W" if key == KEY_W else "S"))


func _test_six_animation_previews() -> void:
	for index in SAMPLE_ACTIONS.size():
		var action: String = SAMPLE_ACTIONS[index]
		await _place(ARENA)
		_tap(SAMPLE_KEYS[index])
		await _frames(10) # Let the short animation blend finish before comparing poses.
		_check(world.player.preview_action == action and world.player.get_animation_status().get("action") == action,
			"Number key %d selects the %s stationary preview" % [index + 1, action])
		var body_before: Transform3D = world.player.global_transform
		var camera_before: Transform3D = world.rig.camera.global_transform
		var shape: CapsuleShape3D = _collider.shape
		var height := shape.height
		var radius := shape.radius
		var collision_transform := _collider.transform
		var layer: int = world.player.collision_layer
		var mask: int = world.player.collision_mask
		var initial_pose := _capture_pose()
		var max_pose_delta := 0.0
		var max_camera_shift := 0.0
		var max_camera_turn := 0.0
		_key(KEY_W, true)
		_key(KEY_A, true)
		for sample_index in range(24):
			await _frames(3)
			max_pose_delta = maxf(max_pose_delta, _pose_difference(initial_pose, _capture_pose()))
			var actual: Transform3D = world.rig.camera.global_transform
			max_camera_shift = maxf(max_camera_shift, actual.origin.distance_to(camera_before.origin))
			max_camera_turn = maxf(max_camera_turn, actual.basis.get_rotation_quaternion().angle_to(camera_before.basis.get_rotation_quaternion()))
		_key(KEY_W, false)
		_key(KEY_A, false)
		_check(max_pose_delta > 0.00001,
			"%s changes actual skeleton poses over time, including breathing for idle samples" % action)
		_check(max_camera_shift < 0.0002 and max_camera_turn < 0.001,
			"%s skeletal motion cannot translate or rotate the shoulder camera" % action)
		_check(world.player.global_transform.is_equal_approx(body_before)
			and _collider.shape == shape and not _collider.disabled
			and is_equal_approx(shape.height, height) and is_equal_approx(shape.radius, radius)
			and _collider.transform.is_equal_approx(collision_transform)
			and world.player.collision_layer == layer and world.player.collision_mask == mask,
			"%s is a stationary animation preview: held W/A cannot move it or alter gameplay collision" % action)
		print("P2_CLIP_SAMPLE action=%s pose_delta=%.6f camera_shift=%.6fm camera_turn=%.6f" % [action, max_pose_delta, max_camera_shift, max_camera_turn])
	_tap(KEY_0)
	await _frames(3)
	_check(world.player.preview_action.is_empty() and world.player.get_animation_status().get("action") == "idle",
		"Number key 0 leaves preview mode and restores normal walking control")
	var before: Vector3 = world.player.global_position
	_key(KEY_W, true)
	await _frames(24)
	_key(KEY_W, false)
	_check(world.player.global_position.z < before.z - 0.4,
		"W physically moves the humanoid again after leaving stationary preview")


func _test_preview_camera_controls() -> void:
	await _place(ARENA)
	_tap(KEY_5)
	await _frames(6)
	var body: Transform3D = world.player.global_transform
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	var before: float = world.rig.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(180, 0)
	Input.parse_input_event(motion)
	await _frames(4)
	_check(world.rig.observing and _angle_error(world.rig.yaw, before) > 0.3
		and world.player.preview_action == "crouch_walk" and world.player.global_transform.is_equal_approx(body),
		"Right-drag observes the crouch-walk preview without rotating or moving the actor")
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	await _frames(2)
	var selected_distance: float = world.rig.desired_distance
	_tap(KEY_F)
	await _frames(30)
	_check(_angle_error(world.rig.yaw, world.player.rotation.y) < 0.04
		and is_equal_approx(world.rig.desired_distance, selected_distance)
		and world.player.preview_action == "crouch_walk",
		"F recenters during preview without resetting selected zoom or changing the clip")
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	_check(not world.rig.observing, "Releasing right mouse ends observation during animation preview")


func _test_preview_pause_and_reset() -> void:
	await _place(ARENA)
	_tap(KEY_6)
	await _frames(12)
	_key(KEY_W, true)
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	_tap(KEY_ESCAPE)
	await _frames(3)
	var paused_time: float = _animation_player.current_animation_position
	var paused_pose := _capture_pose()
	var paused_position: Vector3 = world.player.global_position
	await _frames(30)
	_check(world.phase == "paused" and world.player.get_animation_status().get("paused") == true
		and absf(_animation_player.current_animation_position - paused_time) < 0.00001
		and _pose_difference(paused_pose, _capture_pose()) < 0.00001,
		"Esc freezes animation playback time and the actual rolling skeleton pose")
	_check(_input_cleared() and not world.rig.observing and world.player.global_position.is_equal_approx(paused_position),
		"Preview pause clears held movement and observation without moving the actor")
	_tap(KEY_2)
	await _frames(3)
	_check(world.player.preview_action == "roll" and absf(_animation_player.current_animation_position - paused_time) < 0.00001,
		"Sample-selection keys do not change or restart a paused animation")
	_key(KEY_W, false)
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	world.resume_game()
	await _frames(12)
	_check(world.phase == "playing" and world.player.preview_action == "roll"
		and world.player.get_animation_status().get("paused") == false
		and _pose_difference(paused_pose, _capture_pose()) > 0.00001,
		"Continue resumes the selected rolling preview and its skeleton animation")
	_check(_input_cleared() and not world.rig.observing and world.player.global_position.is_equal_approx(paused_position),
		"Continue does not restore movement or right-button input held before pause")
	_key(KEY_W, true)
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	# Input.parse_input_event is queued. Establish genuinely held inputs before
	# invoking retry; otherwise this would enqueue new input after the reset.
	await _frames(3)
	world.rig.zoom(-2.0)
	world.restart_game()
	await _frames(4)
	_check(world.phase == "playing" and world.player.preview_action.is_empty()
		and world.player.get_animation_status().get("action") == "idle"
		and _input_cleared() and not world.rig.observing,
		"Retry clears selected preview, held controls and observation and selects idle")
	_check(_flat_distance(world.player.global_position, Vector3(5.5, 0.05, 27.0)) < 0.03
		and _angle_error(world.player.rotation.y, 0.0) < 0.001
		and is_equal_approx(world.rig.desired_distance, world.rig.default_distance),
		"Retry restores humanoid spawn, heading and initial camera distance")
	_release_input()
	world.show_menu()
	_tap(KEY_3)
	await _frames(3)
	_check(world.phase == "menu" and world.player.preview_action.is_empty(),
		"Menu ignores numeric sample selection and keeps the next session clean")
	world.start_game()
	await _frames(3)
	_check(world.phase == "playing" and world.player.preview_action.is_empty() and _input_cleared(),
		"A new humanoid session starts without stale preview or input state")


func _clip_for(action: String) -> Animation:
	for clip_name in _animation_player.get_animation_list():
		if String(clip_name).get_file() == action:
			return _animation_player.get_animation(clip_name)
	return null


func _capture_pose() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in _skeleton.get_bone_count():
		result.append(_skeleton.get_bone_pose(bone))
	return result


func _pose_difference(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var difference := 0.0
	for bone in mini(first.size(), second.size()):
		difference = maxf(difference, first[bone].origin.distance_to(second[bone].origin))
		# Compare basis components directly: acos of two numerically identical
		# quaternions can produce a tiny apparent angle on a frozen pose.
		difference = maxf(difference, first[bone].basis.x.distance_to(second[bone].basis.x))
		difference = maxf(difference, first[bone].basis.y.distance_to(second[bone].basis.y))
		difference = maxf(difference, first[bone].basis.z.distance_to(second[bone].basis.z))
	return difference


func _tap(key: Key) -> void:
	_key(key, true)
	_key(key, false)
	Input.flush_buffered_events()


func _finish() -> void:
	_release_input()
	print("P2_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	if is_instance_valid(world):
		world.queue_free()
	await _frames(3)
	quit(1 if failed > 0 else 0)
