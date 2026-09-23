extends SceneTree
## Physical-key camera controls plus staged collision probes in the final map.
## Full stealth routes remain covered by release_test.gd and browser acceptance.
var world: Node3D
var passed := 0
var failed := 0
var held: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = load("res://scenes/release.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	world.start_game()
	await _frames(5)
	var position: Vector3 = world.player.global_position
	var heading: float = world.player.rotation.y
	await _hold([KEY_RIGHT, KEY_UP], 0.35)
	var yaw: float = world.rig.yaw
	var pitch: float = world.rig.pitch_degrees
	_check(yaw < -0.25 and pitch < 4.0, "Arrow right/up adjust both camera axes")
	_check(position.distance_to(world.player.global_position) < 0.002 and absf(world.player.rotation.y - heading) < 0.001,
		"Camera keys never move or turn the character")
	await _seconds(1.6)
	_check(absf(angle_difference(yaw, world.rig.yaw)) < 0.001 and absf(pitch - world.rig.pitch_degrees) < 0.01,
		"A stationary character retains the chosen view after the grace period")
	await _hold([KEY_LEFT, KEY_DOWN], 0.22)
	_check(world.rig.yaw > yaw + 0.15 and world.rig.pitch_degrees > pitch + 5.0, "Arrow left/down reverse the viewing direction")
	await _hold([KEY_UP], 1.0)
	_check(is_equal_approx(world.rig.pitch_degrees, -12.0), "Upward observation stops at the playable pitch limit")
	await _hold([KEY_DOWN], 1.5)
	_check(is_equal_approx(world.rig.pitch_degrees, 50.0), "Downward observation stops before an overhead inversion")
	world.rig.zoom(2.0)
	var zoom: float = world.rig.desired_distance
	await _tap(KEY_F)
	await _seconds(0.5)
	_check(absf(angle_difference(world.player.rotation.y, world.rig.yaw)) < 0.001 and absf(world.rig.pitch_degrees - 14.0) < 0.05
		and is_equal_approx(world.rig.desired_distance, zoom), "F quickly restores heading and pitch while preserving zoom")
	world.restart_game()
	await _frames(4)
	await _hold([KEY_RIGHT], 0.35)
	yaw = world.rig.yaw
	_key(KEY_W, true)
	await _seconds(0.7)
	_check(absf(angle_difference(yaw, world.rig.yaw)) < 0.001, "Movement does not steal the view during the 1.25-second grace period")
	await _seconds(0.8)
	_check(absf(world.rig.yaw) < absf(yaw) - 0.08 and absf(world.rig.yaw) > 0.05, "Continued movement returns the camera gradually after the grace period")
	await _seconds(2.5)
	_key(KEY_W, false)
	_check(absf(world.rig.yaw) < 0.01, "Walking eventually restores the useful forward view")
	world.restart_game()
	await _frames(4)
	position = world.player.global_position
	await _hold([KEY_W, KEY_RIGHT], 0.6)
	_check(world.rig.yaw < -0.85 and absf(world.player.rotation.y) < 0.001 and world.player.global_position.z < position.z - 0.8,
		"W and camera arrows can be held together without changing the movement reference")
	yaw = world.rig.yaw
	await _hold([KEY_A, KEY_UP], 0.3)
	_check(world.player.rotation.y > 0.3 and absf(angle_difference(yaw, world.rig.yaw)) < 0.001,
		"Character turning cannot override a simultaneous vertical observation")
	await _test_mouse()
	await _test_pause()
	await _test_collisions()
	print("RELEASE_CAMERA_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.show_menu()
	for source in world.find_children("*", "AudioStreamPlayer", true, false):
		source.stop()
	world.queue_free()
	await _frames(4)
	OS.delay_msec(150)
	quit(1 if failed else 0)

func _test_mouse() -> void:
	world.restart_game()
	await _frames(4)
	var expected_yaw: float = -80.0 * world.rig.mouse_sensitivity
	var expected_pitch: float = clampf(14.0 - rad_to_deg(35.0 * world.rig.mouse_sensitivity), world.rig.min_pitch_degrees, world.rig.max_pitch_degrees)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(80, -35) * float(root.size.x) / root.get_visible_rect().size.x
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frames(2)
	_check(absf(angle_difference(expected_yaw, world.rig.yaw)) < 0.001 and absf(world.rig.pitch_degrees - expected_pitch) < 0.001 and absf(world.player.rotation.y) < 0.001,
		"Right drag remains an alternative for both camera axes")
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await _frames(2)

func _test_pause() -> void:
	_key(KEY_RIGHT, true)
	await _seconds(0.15)
	await _tap(KEY_ESCAPE)
	var yaw: float = world.rig.yaw
	var pitch: float = world.rig.pitch_degrees
	var position: Vector3 = world.rig.camera.global_position
	await _seconds(0.3)
	_check(world.phase == "paused" and world.rig.look_input.is_zero_approx() and not Input.is_action_pressed("look_right")
		and position.distance_to(world.rig.camera.global_position) < 0.0001, "Pause clears arrow input and freezes the camera")
	_key(KEY_RIGHT, false)
	world.resume_game()
	await _seconds(0.4)
	_check(absf(angle_difference(yaw, world.rig.yaw)) < 0.001 and absf(pitch - world.rig.pitch_degrees) < 0.001,
		"Continue preserves the view without a stuck camera key")
	world.restart_game()
	await _frames(3)
	_check(is_zero_approx(world.rig.yaw) and is_equal_approx(world.rig.pitch_degrees, 14.0) and is_equal_approx(world.rig.desired_distance, 4.8),
		"Retry resets view, zoom and pending observation input")

func _test_collisions() -> void:
	# Staged camera-only probes freeze guards so an exposed test location cannot
	# end a sweep early. Full release regression separately tests live detection.
	var obstructions := 0
	var max_step := 0.0
	var max_rest_drift := 0.0
	var samples := 0
	for at in [Vector3(5.5, 0.05, 35), Vector3(4.45, 0.05, 33), Vector3(4.45, 0.05, 35.7), Vector3(10.9, 0.05, 24.45)]:
		world.restart_game()
		for observer in world.guards:
			observer.set_frozen(true)
		world.player.reset_player(at)
		world.rig.reset_camera()
		await _frames(60)
		var previous: Vector3 = world.rig.camera.global_position
		for key in [KEY_RIGHT, KEY_UP, KEY_LEFT, KEY_DOWN]:
			_key(key, true)
			for frame in 90:
				await _frames(1)
				var current: Vector3 = world.rig.camera.global_position
				if previous.distance_to(current) > max_step and previous.distance_to(current) > 0.25:
					print("CAMERA_STEP_PROBE position=%s key=%s frame=%d step=%.6f yaw=%.6f pitch=%.6f boom=%.6f previous=%s current=%s" % [at, key, frame, previous.distance_to(current), world.rig.yaw, world.rig.pitch_degrees, world.rig._resolved_length, previous, current])
				max_step = maxf(max_step, previous.distance_to(current))
				previous = current
				obstructions += 0 if _camera_clear() else 1
				samples += 1
			_key(key, false)
		_check(world.phase == "playing", "Collision probe remains in active gameplay")
		await _seconds(2.0)
		var resting: Vector3 = world.rig.camera.global_position
		for frame in 180:
			await _frames(1)
			max_rest_drift = maxf(max_rest_drift, resting.distance_to(world.rig.camera.global_position))
	_check(obstructions == 0, "All free-orbit wall/cabinet/floor samples keep the camera volume outside geometry")
	_check(max_step < 0.30, "Camera sweeps have no single-frame boom jumps exceeding 30 cm")
	_check(max_rest_drift < 0.0001, "Released camera stays steady for three seconds near each obstacle")
	print("RELEASE_CAMERA_COLLISION samples=%d max_step=%.6f rest_drift=%.8f obstructions=%d" % [samples, max_step, max_rest_drift, obstructions])

func _camera_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = world.rig.camera_radius - 0.002
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, world.rig.camera.global_position)
	query.collision_mask = world.rig.obstacle_mask
	query.exclude = world.rig._excluded
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _frames(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame

func _seconds(value: float) -> void:
	await _frames(ceili(value * Engine.physics_ticks_per_second))

func _key(code: Key, pressed: bool) -> void:
	if held.get(code, false) == pressed:
		return
	held[code] = pressed
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)

func _hold(keys: Array, duration: float) -> void:
	for code in keys:
		_key(code, true)
	await _seconds(duration)
	for code in keys:
		_key(code, false)
	await _frames(2)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS " + label)
	else:
		failed += 1
		push_error("FAIL " + label)
