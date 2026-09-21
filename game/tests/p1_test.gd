extends SceneTree
## Real P1 scene, input dispatch and physics regression.
## Run: bash tools/godot.sh --headless --fixed-fps 60 --log-file /tmp/xiaban-p1-test.log --script res://tests/p1_test.gd
## Browser pointer capture, DOM focus and visual quality require browser acceptance.

const ARENA := Vector3(100.0, 0.05, 100.0)
const ACTIONS := ["move_forward", "move_back", "turn_left", "turn_right"]

var world: Node3D
var passed := 0
var failed := 0
var obstacles: Array[StaticBody3D] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = load("res://scenes/p1.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	_check(world.phase == "menu", "P1 opens at the start menu")
	_barrier(ARENA + Vector3(0, -0.3, 0), Vector3(40, 0.5, 40), false)
	world.start_game()
	await _frames(3)
	_check(world.phase == "playing", "Start enters playable state")
	await _test_movement()
	await _test_camera_controls()
	await _test_input_events()
	await _test_player_collision()
	await _test_camera_collision()
	await _test_camera_visibility()
	await _test_visual_independence()
	await _test_pause_and_retry()
	_release_input()
	print("P1_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.queue_free()
	await _frames(3)
	quit(1 if failed > 0 else 0)


func _test_movement() -> void:
	for action in ["turn_left", "turn_right"]:
		await _place(ARENA)
		var before: Vector3 = world.player.global_position
		Input.action_press(action)
		await _frames(24)
		_release_input()
		var heading: float = world.player.rotation.y
		_check(_flat_distance(before, world.player.global_position) < 0.02,
			"%s turns in place without strafing" % action)
		_check(heading > 0.15 if action == "turn_left" else heading < -0.15,
			"%s turns toward the correct side" % action)
		await _frames(90)
		_check(_angle_error(world.rig.yaw, heading) < 0.05,
			"Camera follows %s even without forward movement" % action)

	for heading in [0.0, PI / 2.0, PI, -PI / 2.0]:
		var forward := Vector3.FORWARD.rotated(Vector3.UP, heading)
		for action in ["move_forward", "move_back"]:
			await _place(ARENA, heading)
			var before: Vector3 = world.player.global_position
			var camera_heading: float = world.rig.yaw
			Input.action_press(action)
			await _frames(24)
			_release_input()
			var displacement: Vector3 = world.player.global_position - before
			displacement.y = 0.0
			var intended := forward if action == "move_forward" else -forward
			_check(displacement.length() > 0.5 and displacement.normalized().dot(intended) > 0.995,
				"%s respects actor heading %.2f" % [action, heading])
			_check(_angle_error(world.player.rotation.y, heading) < 0.001,
				"%s does not rotate actor at heading %.2f" % [action, heading])
			_check(_angle_error(world.rig.yaw, camera_heading) < 0.03,
				"%s does not flip camera at heading %.2f" % [action, heading])

	await _place(ARENA, 0.4)
	var stopped: Vector3 = world.player.global_position
	for action in ACTIONS:
		Input.action_press(action)
	await _frames(24)
	_release_input()
	_check(_flat_distance(stopped, world.player.global_position) < 0.02
		and _angle_error(world.player.rotation.y, 0.4) < 0.001,
		"Opposing W/S and A/D inputs cancel movement and turning")
	Input.action_press("move_forward")
	Input.action_press("turn_left")
	await _frames(24)
	_release_input()
	_check(_flat_distance(stopped, world.player.global_position) > 0.5
		and _angle_error(world.player.rotation.y, 0.4) > 0.15,
		"Forward movement and turning work together")
	await _frames(3)
	stopped = world.player.global_position
	await _frames(20)
	_check(_flat_distance(stopped, world.player.global_position) < 0.02,
		"Releasing all movement inputs stops the actor")


func _test_camera_controls() -> void:
	await _place(ARENA)
	var initial_camera: Vector3 = world.rig.camera.global_position
	_check(initial_camera.x > world.player.global_position.x + 0.2
		and initial_camera.z > world.player.global_position.z + 2.0,
		"Default view is behind and to the actor's right")
	world.rig.set_observing(true)
	world.rig.orbit(220.0)
	await _frames(10)
	var orbit_yaw: float = world.rig.yaw
	_check(_angle_error(orbit_yaw, world.player.rotation.y) > 0.3,
		"Right-button observation orbits away from actor heading")
	var before: Vector3 = world.player.global_position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	var displacement: Vector3 = world.player.global_position - before
	_check(displacement.z < -0.5 and absf(displacement.x) < 0.03
		and _angle_error(world.player.rotation.y, 0.0) < 0.001,
		"W retains actor-forward direction while observing")
	_check(_angle_error(world.rig.yaw, orbit_yaw) < 0.01,
		"Walking does not auto-center an active observation")
	# Let the physics controller consume W release before ending observation.
	await _frames(2)
	world.rig.set_observing(false)
	await _frames(60)
	_check(_angle_error(world.rig.yaw, orbit_yaw) < 0.01,
		"Standing still preserves the released observation angle")
	Input.action_press("move_back")
	await _frames(8)
	var intermediate_error := _angle_error(world.rig.yaw, 0.0)
	_check(intermediate_error > 0.01 and intermediate_error < _angle_error(orbit_yaw, 0.0),
		"Released observation returns smoothly while walking backward")
	Input.action_release("move_back")
	await _frames(2)
	var stopped_error := _angle_error(world.rig.yaw, 0.0)
	await _frames(20)
	_check(_angle_error(world.rig.yaw, 0.0) < stopped_error and is_zero_approx(world.player.move_input),
		"An already-started automatic recenter settles smoothly after walking stops")
	await _frames(100)
	_release_input()
	_check(_angle_error(world.rig.yaw, 0.0) < 0.05,
		"Backward movement returns camera to actor heading, not displacement")

	world.rig.zoom(-2.0)
	var selected_distance: float = world.rig.desired_distance
	world.rig.set_observing(true)
	world.rig.orbit(190.0)
	world.rig.set_observing(false)
	world.rig.recenter()
	await _frames(20)
	_check(_angle_error(world.rig.yaw, world.player.rotation.y) < 0.04,
		"Quick recenter restores actor heading")
	_check(is_equal_approx(world.rig.desired_distance, selected_distance),
		"Quick recenter preserves chosen camera distance")
	world.rig.set_observing(true)
	world.rig.orbit(190.0)
	world.rig.recenter()
	for frame in range(20):
		world.rig.orbit(0.0)
		await _frames(1)
	_check(_angle_error(world.rig.yaw, world.player.rotation.y) < 0.04
		and is_equal_approx(world.rig.desired_distance, selected_distance),
		"Vertical-only mouse motion cannot cancel F while the right button is held")
	world.rig.orbit(190.0)
	world.rig.set_observing(false)
	world.rig.recenter()
	await _frames(2)
	world.rig.set_observing(true)
	var held_yaw: float = world.rig.yaw
	await _frames(20)
	_check(_angle_error(world.rig.yaw, held_yaw) < 0.001
		and _angle_error(held_yaw, world.player.rotation.y) > 0.1,
		"Beginning a new right-button observation overrides an in-progress F recenter")
	world.rig.recenter()
	await _frames(2)
	world.rig.orbit(10.0)
	held_yaw = world.rig.yaw
	await _frames(20)
	_check(_angle_error(world.rig.yaw, held_yaw) < 0.001,
		"An intentional horizontal orbit overrides an in-progress F recenter")
	world.rig.set_observing(false)
	world.rig.zoom(1000.0)
	var first_limit: float = world.rig.desired_distance
	world.rig.zoom(1000.0)
	_check(is_equal_approx(first_limit, world.rig.desired_distance)
		and is_equal_approx(first_limit, world.rig.min_distance),
		"Zoom clamps at the configured minimum distance")
	world.rig.zoom(-1000.0)
	var second_limit: float = world.rig.desired_distance
	world.rig.zoom(-1000.0)
	_check(is_equal_approx(second_limit, world.rig.desired_distance)
		and is_equal_approx(second_limit, world.rig.max_distance)
		and absf(first_limit - second_limit) > 1.0,
		"Zoom clamps at the configured maximum distance")


func _test_input_events() -> void:
	# These are Godot input events. They do not test browser DOM delivery.
	await _place(ARENA)
	var before: Vector3 = world.player.global_position
	_key(KEY_W, true)
	await _frames(20)
	_key(KEY_W, false)
	await _frames(3)
	_check(world.player.global_position.z < before.z - 0.5
		and not Input.is_action_pressed("move_forward"),
		"Physical W key events reach the configured forward action and release")
	before = world.player.global_position
	_key(KEY_S, true)
	await _frames(20)
	_key(KEY_S, false)
	await _frames(3)
	_check(world.player.global_position.z > before.z + 0.5
		and not Input.is_action_pressed("move_back"),
		"Physical S key events reach the configured backward action and release")
	_key(KEY_A, true)
	await _frames(20)
	_key(KEY_A, false)
	await _frames(3)
	_check(world.player.rotation.y > 0.15 and not Input.is_action_pressed("turn_left"),
		"Physical A key events reach the configured turn action and release")
	var heading_before: float = world.player.rotation.y
	_key(KEY_D, true)
	await _frames(20)
	_key(KEY_D, false)
	await _frames(3)
	_check(world.player.rotation.y < heading_before - 0.15
		and not Input.is_action_pressed("turn_right"),
		"Physical D key events reach the configured turn action and release")
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	_check(world.rig.observing, "Right mouse press enables observation")
	var yaw_before_motion: float = world.rig.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(180, 0)
	Input.parse_input_event(motion)
	await _frames(2)
	_check(_angle_error(world.rig.yaw, yaw_before_motion) > 0.3,
		"Mouse motion dispatch orbits the active observation")
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	_check(not world.rig.observing, "Right mouse release ends observation")
	var old_distance: float = world.rig.desired_distance
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
	await _frames(2)
	_check(world.rig.desired_distance < old_distance,
		"Mouse wheel up dispatch moves the camera closer")
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	await _frames(2)
	_check(is_equal_approx(world.rig.desired_distance, old_distance),
		"Mouse wheel down dispatch moves the camera farther")
	var selected_distance: float = world.rig.desired_distance
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _frames(30)
	_check(_angle_error(world.rig.yaw, world.player.rotation.y) < 0.04
		and is_equal_approx(selected_distance, world.rig.desired_distance),
		"Physical F key dispatch recenters without resetting zoom")


func _test_player_collision() -> void:
	_barrier(ARENA + Vector3(0, 1.5, -2.0), Vector3(8, 3, 0.3))
	await _place(ARENA)
	Input.action_press("move_forward")
	await _frames(100)
	_release_input()
	_check(world.player.global_position.z > ARENA.z - 1.55,
		"Forward movement cannot cross a solid wall")
	_check(world.player.global_position.y > -0.05,
		"The actor remains supported by the floor")
	await _clear_obstacles()
	_barrier(ARENA + Vector3(0, 0.45, -1.6), Vector3(3, 0.9, 1.0))
	await _place(ARENA)
	Input.action_press("move_forward")
	await _frames(80)
	_release_input()
	_check(world.player.global_position.z > ARENA.z - 0.85,
		"A low desk has real player collision at its edge")
	await _clear_obstacles()


func _test_camera_collision() -> void:
	# Tall, thin blockers reveal side-offset and corner tunneling errors.
	# The actor never overlaps these fixtures; only the shoulder/camera path may.
	for scenario in ["right_wall", "corner", "narrow_door", "behind_wall", "low_desk"]:
		await _clear_obstacles()
		if scenario == "right_wall" or scenario == "corner":
			_barrier(ARENA + Vector3(0.65, 2.95, 0), Vector3(0.15, 6, 14))
		if scenario == "corner":
			_barrier(ARENA + Vector3(0, 2.95, 0.65), Vector3(14, 6, 0.15))
		elif scenario == "narrow_door":
			_barrier(ARENA + Vector3(-3.6, 2.95, 0.85), Vector3(6, 6, 0.15))
			_barrier(ARENA + Vector3(3.6, 2.95, 0.85), Vector3(6, 6, 0.15))
		elif scenario == "behind_wall":
			_barrier(ARENA + Vector3(0, 2.95, 1.4), Vector3(14, 6, 0.12))
		elif scenario == "low_desk":
			_barrier(ARENA + Vector3(0.8, 0.7, 2.0), Vector3(2, 1.4, 2))
		await _place(ARENA)
		world.rig.set_observing(true)
		var all_clear := true
		for angle in range(0, 360, 15):
			world.rig.yaw = deg_to_rad(float(angle))
			world.rig.update_camera(1.0 / 60.0, true)
			await _frames(2)
			if not _camera_clear():
				all_clear = false
				print("CAMERA_COLLISION scenario=%s angle=%d camera=%s" % [
					scenario, angle, world.rig.camera.global_position])
		_check(all_clear, "%s: camera sphere and anchor sightline clear at 24 orbit angles" % scenario)
		world.rig.set_observing(false)
	await _clear_obstacles()
	await _place(ARENA)
	var free_distance: float = world.rig.camera.global_position.distance_to(world.player.global_position)
	_barrier(ARENA + Vector3(0, 2.95, 1.4), Vector3(14, 6, 0.12))
	await _frames(4)
	var obstructed_distance: float = world.rig.camera.global_position.distance_to(world.player.global_position)
	_check(obstructed_distance < free_distance - 0.5 and _camera_clear(),
		"A newly encountered wall immediately shortens the camera arm")
	await _clear_obstacles()
	await _frames(120)
	_check(world.rig.camera.global_position.distance_to(world.player.global_position) > free_distance - 0.1,
		"Camera returns to the selected distance after leaving an obstruction")


func _test_camera_visibility() -> void:
	await _place(ARENA)
	var collision_layer: int = world.player.collision_layer
	var collision_mask: int = world.player.collision_mask
	var collider: CollisionShape3D = world.player.get_child(0)
	var shape: CapsuleShape3D = collider.shape
	var radius := shape.radius
	var height := shape.height
	var collision_transform := collider.transform
	var heading: float = world.player.rotation.y
	var body_mesh: MeshInstance3D = world.player.visual.get_child(0)
	_check(is_equal_approx(world.player.camera_alpha, 1.0)
		and is_equal_approx(body_mesh.material_override.albedo_color.a, 1.0),
		"Character is opaque at a comfortable camera distance")
	_barrier(ARENA + Vector3(0.65, 2.95, 0), Vector3(0.15, 6, 14))
	_barrier(ARENA + Vector3(0, 2.95, 0.65), Vector3(14, 6, 0.15))
	await _frames(5)
	_check(world.player.camera_alpha < 0.2
		and body_mesh.material_override.albedo_color.a < 0.2 and _camera_clear(),
		"Character fades beside a safely compressed camera in a tight corner")
	_check(world.player.collision_layer == collision_layer and world.player.collision_mask == collision_mask
		and collider.shape == shape and not collider.disabled
		and is_equal_approx(shape.radius, radius) and is_equal_approx(shape.height, height)
		and collider.transform.is_equal_approx(collision_transform)
		and is_equal_approx(world.player.rotation.y, heading),
		"Camera fade preserves player collision shape, collision layers and heading")
	await _clear_obstacles()
	await _frames(120)
	_check(is_equal_approx(world.player.camera_alpha, 1.0)
		and is_equal_approx(body_mesh.material_override.albedo_color.a, 1.0),
		"Character returns to full opacity as the camera recovers its distance")


func _test_visual_independence() -> void:
	await _place(ARENA)
	var camera_transform: Transform3D = world.rig.camera.global_transform
	var visual_transform: Transform3D = world.player.visual.transform
	world.player.visual.rotation = Vector3(PI * 0.8, 0.6, PI)
	world.player.visual.scale = Vector3(1.0, 0.45, 1.0)
	world.player.visual.position.y = -0.4
	await _frames(15)
	var actual: Transform3D = world.rig.camera.global_transform
	_check(actual.origin.distance_to(camera_transform.origin) < 0.02
		and actual.basis.is_equal_approx(camera_transform.basis),
		"Crouch/roll visual transforms do not move or flip the camera")
	world.player.visual.transform = visual_transform


func _test_pause_and_retry() -> void:
	await _place(ARENA)
	Input.action_press("move_forward")
	Input.action_press("turn_left")
	world.rig.set_observing(true)
	await _frames(8)
	world.pause_game()
	var stopped: Vector3 = world.player.global_position
	var heading: float = world.player.rotation.y
	await _frames(25)
	_check(world.phase == "paused" and _flat_distance(stopped, world.player.global_position) < 0.001
		and _angle_error(world.player.rotation.y, heading) < 0.001,
		"Pause freezes movement and actor heading")
	_check(not world.rig.observing and _input_cleared(),
		"Pause clears held movement and observation state")
	world.resume_game()
	await _frames(20)
	_check(world.phase == "playing" and _flat_distance(stopped, world.player.global_position) < 0.02,
		"Resume does not replay inputs held before pausing")
	Input.action_press("move_back")
	world.rig.set_observing(true)
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	_check(world.phase == "paused" and _input_cleared() and not world.rig.observing,
		"Application focus-out notification pauses and clears controls")
	world.resume_game()
	Input.action_press("move_forward")
	world.rig.set_observing(true)
	world.rig.orbit(160.0)
	world.restart_game()
	await _frames(3)
	_check(world.phase == "playing" and _input_cleared() and not world.rig.observing,
		"Retry clears held movement and observation state")
	_check(_flat_distance(world.player.global_position, Vector3(5.5, 0.05, 27.0)) < 0.03
		and _angle_error(world.player.rotation.y, 0.0) < 0.001,
		"Retry restores spawn and actor heading")
	world.show_menu()
	await _frames(3)
	_check(world.phase == "menu" and _input_cleared() and not world.rig.observing,
		"Returning to menu clears gameplay controls")
	world.start_game()
	await _frames(3)
	_check(world.phase == "playing", "A new session can start after returning to menu")
	var exit_center: Vector2 = world.level.exit_rect.get_center()
	world.player.reset_player(Vector3(exit_center.x, 0.05, exit_center.y))
	# Losing fullscreen has priority even if the player reaches the exit on the
	# same frame. Exercise the transition without requiring a native window.
	world._was_fullscreen = true
	world._process(1.0 / 60.0)
	_check(world.phase == "paused" and _input_cleared(),
		"Fullscreen exit cannot fall through to route completion in the same frame")
	world.resume_game()
	await _frames(3)
	_check(world.phase == "won" and _input_cleared() and not world.rig.observing,
		"Reaching the P1 exit ends the sample and clears controls")
	world.restart_game()
	await _frames(3)
	_check(world.phase == "playing"
		and _flat_distance(world.player.global_position, Vector3(5.5, 0.05, 27.0)) < 0.03,
		"Retry from the completed sample returns to a playable spawn")


func _place(at: Vector3, heading: float = 0.0) -> void:
	_release_input()
	world.player.reset_player(at, heading)
	world.rig.reset_camera()
	await _frames(5)


func _camera_clear() -> bool:
	var camera_position: Vector3 = world.rig.camera.global_position
	var shape := SphereShape3D.new()
	shape.radius = world.rig.camera_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, camera_position)
	query.collision_mask = 3
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var anchor: Vector3 = world.player.global_position + Vector3.UP * world.rig.anchor_height
	var ray := PhysicsRayQueryParameters3D.create(anchor, camera_position, 3)
	return space.intersect_ray(ray).is_empty()


func _barrier(at: Vector3, size: Vector3, temporary: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 3
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	if temporary:
		obstacles.append(body)
	return body


func _clear_obstacles() -> void:
	for body in obstacles:
		body.queue_free()
	obstacles.clear()
	await _frames(3)


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_input() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)
	for key in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_F]:
		_key(key, false)
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	Input.flush_buffered_events()


func _input_cleared() -> bool:
	for action in ACTIONS:
		if Input.is_action_pressed(action):
			return false
	return is_zero_approx(world.player.move_input) and is_zero_approx(world.player.turn_input)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _angle_error(a: float, b: float) -> float:
	return absf(angle_difference(a, b))


func _frames(count: int) -> void:
	for unused in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)
