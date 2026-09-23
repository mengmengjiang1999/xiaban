extends "res://tests/p1_test.gd"
## P3 integration: real scene input, 3D collision, clip playback and lifecycle.
## bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p3_test.gd
## Runtime physics ticks are varied explicitly; --fixed-fps is a render clock.
var _noise_events: Array[Dictionary] = []
var _original_physics_ticks := 60


func _run() -> void:
	_original_physics_ticks = Engine.physics_ticks_per_second
	world = load("res://scenes/p3.tscn").instantiate()
	root.add_child(world)
	await _frames(6)
	_check(world.phase == "menu", "P3 opens at its own menu")
	_check(world.player.actor.skeleton.get_bone_count() >= 15,
		"P3 controls the real imported humanoid")
	world.player.sprint_noise_emitted.connect(_on_sprint_noise)
	_barrier(ARENA + Vector3(0, -0.3, 0), Vector3(40, 0.5, 40), false)
	world.start_game()
	await _frames(4)
	_check(world.phase == "playing" and world.player.stance == "standing",
		"Start enters standing gameplay")
	await _test_crouch_volume_and_camera()
	await _test_stand_obstructions()
	await _test_crouch_movement_and_sprint()
	await _test_roll_inputs_and_recovery()
	await _test_roll_obstacles()
	await _test_pause_focus_and_reset()
	await _test_rapid_inputs()
	await _test_physics_rates()
	await _test_exit_cleanup()
	Engine.physics_ticks_per_second = _original_physics_ticks
	_release_input()
	print("P3_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.queue_free()
	await _frames(3)
	quit(1 if failed > 0 else 0)


func _test_crouch_volume_and_camera() -> void:
	await _place(ARENA)
	await _seconds(0.25)
	var collider: CollisionShape3D = world.player.collider
	var stand_height: float = collider.shape.height
	var feet: float = collider.position.y - stand_height * 0.5
	var player_height: float = world.player.global_position.y
	var points_before: Array = world.player.get_detection_points()
	var camera_before: Transform3D = world.rig.camera.global_transform
	var anchor_before: float = world.rig.anchor_height
	await _tap(KEY_C)
	await _seconds(0.35)
	_check(world.player.stance == "crouched"
		and collider.shape.height < stand_height - 0.3,
		"C lowers the real gameplay capsule as well as the humanoid")
	_check(absf(collider.position.y - collider.shape.height * 0.5 - feet) < 0.002
		and absf(world.player.global_position.y - player_height) < 0.005,
		"Crouching keeps the capsule bottom and player feet on the same floor")
	var points_after: Array = world.player.get_detection_points()
	var points_lowered := points_before.size() >= 2 and points_after.size() == points_before.size()
	for index in points_after.size():
		points_lowered = points_lowered and points_before[index].y - points_after[index].y > 0.25
	_check(points_lowered, "Actual head and chest detection points lower with the crouched bones")
	var camera_after: Transform3D = world.rig.camera.global_transform
	_check(camera_after.origin.distance_to(camera_before.origin) < 0.01
		and camera_after.basis.is_equal_approx(camera_before.basis)
		and is_equal_approx(world.rig.anchor_height, anchor_before),
		"Crouching does not lower, tilt or roll the independent shoulder camera")
	for index in 5:
		_echo(KEY_C)
	await _frames(3)
	_check(world.player.stance == "crouched", "C key-repeat events do not repeatedly toggle stance")
	await _tap(KEY_C)
	await _seconds(0.25)
	_check(world.player.stance == "standing" and is_equal_approx(collider.shape.height, stand_height),
		"C restores standing collision in unobstructed space")
	await _tap(KEY_SPACE)
	await _frames(3)
	_check(world.player.action_state != "roll" and world.player.stance == "standing",
		"Space cannot start a roll from standing")
	await _tap(KEY_6)
	_check(world.player.action_state != "roll" and world.player.preview_action.is_empty(),
		"P3 does not accidentally invoke the P2 numeric animation preview")


func _test_stand_obstructions() -> void:
	await _place(ARENA)
	var stand_height: float = world.player.collider.shape.height
	await _enter_crouch()
	var crouch_height: float = world.player.collider.shape.height
	var feet: float = world.player.global_position.y
	var ceiling_bottom := lerpf(crouch_height, stand_height, 0.5)
	_barrier(Vector3(ARENA.x, feet + ceiling_bottom + 0.1, ARENA.z), Vector3(2, 0.2, 2))
	await _frames(3)
	await _tap(KEY_C)
	_check(world.player.stance == "crouched"
		and bool(world.player.get_control_status().get("stand_blocked", false)),
		"A low ceiling rejects standing and reports the obstruction")
	_check(is_equal_approx(world.player.collider.shape.height, crouch_height),
		"Blocked standing leaves the low capsule intact")
	var before_roll: Vector3 = world.player.global_position
	await _tap(KEY_SPACE)
	_check(world.player.action_state != "roll" and _flat_distance(before_roll, world.player.global_position) < 0.005,
		"A ceiling that permits crouching but not the rolling body envelope prevents starting a roll")
	await _clear_obstacles()
	await _tap(KEY_C)
	_check(world.player.stance == "standing", "Standing works immediately after the ceiling is removed")
	await _enter_crouch()
	var radius: float = world.player.collider.shape.radius
	# Offset from the center line: a single vertical ray would miss this lip.
	var lip_bottom := crouch_height + 0.07
	var lip_height := maxf(0.1, stand_height - 0.15 - lip_bottom)
	_barrier(Vector3(ARENA.x + radius - 0.02, feet + lip_bottom + lip_height * 0.5, ARENA.z),
		Vector3(0.16, lip_height, 0.8))
	await _frames(3)
	await _tap(KEY_C)
	_check(world.player.stance == "crouched",
		"A side overhang intersecting the standing capsule blocks rising even when the center ray is clear")
	await _clear_obstacles()
	await _tap(KEY_C)
	_check(world.player.stance == "standing", "Leaving the side overhang does not leave standing permanently blocked")


func _test_crouch_movement_and_sprint() -> void:
	for key in [KEY_W, KEY_S]:
		await _place(ARENA, 0.6)
		await _enter_crouch()
		var start: Vector3 = world.player.global_position
		var heading: float = world.player.rotation.y
		_key(key, true)
		await _seconds(0.5)
		var displacement: Vector3 = world.player.global_position - start
		displacement.y = 0.0
		var intended := Vector3.FORWARD.rotated(Vector3.UP, heading) * (1 if key == KEY_W else -1)
		var animation: Dictionary = world.player.get_animation_status()
		_check(displacement.length() > 0.2 and displacement.length() < world.player.walk_speed * 0.5
			and displacement.normalized().dot(intended) > 0.99
			and _angle_error(world.player.rotation.y, heading) < 0.001,
			"Crouched %s moves slowly along the body heading without rotating" % ("W" if key == KEY_W else "S"))
		_check(animation.get("action") == "crouch_walk"
			and (float(animation.get("rate", 0)) > 0 if key == KEY_W else float(animation.get("rate", 0)) < 0),
			"Crouch-walk animation follows the forward/backward direction")
		_release_input()
	await _place(ARENA)
	_noise_events.clear()
	_key(KEY_SHIFT, true)
	await _seconds(0.5)
	_check(world.player.action_state != "sprint" and _noise_events.is_empty(),
		"Shift alone neither sprints nor emits a sound event")
	_key(KEY_S, true)
	await _seconds(0.5)
	_check(world.player.action_state != "sprint" and _noise_events.is_empty(),
		"Shift plus backward movement stays ordinary walking and emits no sprint sound")
	_release_input()
	await _place(ARENA)
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	var before: Vector3 = world.player.global_position
	await _seconds(1.0)
	var distance := _flat_distance(before, world.player.global_position)
	_check(world.player.stance == "standing" and world.player.action_state == "sprint"
		and distance > world.player.walk_speed * 1.5
		and world.player.get_animation_status().get("action") == "run",
		"Standing Shift+W produces faster physical movement and the running animation")
	var valid_noise := not _noise_events.is_empty()
	for event in _noise_events:
		valid_noise = valid_noise and event["state"] == "sprint" and float(event["radius"]) > 0.0
	_check(valid_noise, "Actual sprinting emits finite-radius attention events only from the sprint state")
	_key(KEY_SHIFT, false)
	await _frames(3)
	_check(world.player.action_state == "walk", "Releasing Shift returns held W to walking")
	_release_input()
	await _place(ARENA)
	await _enter_crouch()
	_noise_events.clear()
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _seconds(0.5)
	_check(world.player.stance == "crouched" and world.player.action_state == "crouch_walk"
		and _noise_events.is_empty(),
		"Shift+W while crouched keeps crouch-walking without automatically standing or making sprint noise")
	_release_input()
	await _place(ARENA)
	_barrier(world.player.global_position + Vector3(0, 1.2, -0.9), Vector3(3, 2.4, 0.1))
	await _frames(3)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _seconds(0.6)
	_noise_events.clear()
	var blocked_position: Vector3 = world.player.global_position
	await _seconds(0.8)
	_check(_flat_distance(blocked_position, world.player.global_position) < 0.005
		and _noise_events.is_empty(),
		"Holding sprint into a solid wall does not keep generating running noise while stationary")
	_release_input()
	await _clear_obstacles()
	# An oblique wall contact leaves real tangential movement, substantially
	# slower than the commanded sprint. Pose and footfalls must follow that travel.
	await _place(ARENA, 0.35)
	_barrier(world.player.global_position + Vector3(0, 1.2, -1.0), Vector3(10, 2.4, 0.1))
	await _frames(3)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _seconds(0.8)
	_noise_events.clear()
	var slide_start: Vector3 = world.player.global_position
	var slide_started: float = world.elapsed
	await _seconds(2.0)
	var slide_distance := _flat_distance(slide_start, world.player.global_position)
	var slide_speed: float = slide_distance / (world.elapsed - slide_started)
	var slide_animation: Dictionary = world.player.get_animation_status()
	_check(slide_speed > 0.5 and slide_speed < world.player.sprint_speed * 0.5
		and slide_animation.get("action") == "run"
		and absf(float(slide_animation.get("rate", 0)) - slide_speed / 3.8) < 0.02,
		"Sliding against an angled wall slows the actual run animation to match physical travel")
	var expected_steps: float = slide_distance / (world.player.sprint_speed * world.player.sprint_step_interval)
	_check(_noise_events.size() >= floori(expected_steps) and _noise_events.size() <= ceili(expected_steps),
		"Slower wall sliding also spaces sprint sound events by actual distance instead of full-speed wall-clock cadence")
	_release_input()
	await _clear_obstacles()


func _test_roll_inputs_and_recovery() -> void:
	await _place(ARENA, 0.45)
	await _enter_crouch()
	_noise_events.clear()
	var start: Vector3 = world.player.global_position
	var heading: float = world.player.rotation.y
	var camera_basis: Basis = world.rig.camera.global_basis
	_key(KEY_SPACE, true)
	await _frames(2)
	_check(world.player.action_state == "roll" and world.player.stance == "crouched",
		"Space begins one physical roll from crouching")
	_key(KEY_A, true)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _tap(KEY_C)
	for index in 5:
		_echo(KEY_SPACE)
	await _seconds(0.2)
	_check(world.player.action_state == "roll" and world.player.stance == "crouched"
		and _angle_error(world.player.rotation.y, heading) < 0.001,
		"A/C/Shift cannot steer, cancel or stand up during the locked roll")
	_check(world.rig.camera.global_basis.is_equal_approx(camera_basis),
		"The rolling skeleton does not rotate the shoulder camera")
	_key(KEY_A, false)
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	await _wait_until_roll_ends()
	_check(world.player.action_state == "recovery" and world.player.stance == "crouched",
		"A completed roll enters crouched recovery")
	var end: Vector3 = world.player.global_position
	var displacement := end - start
	displacement.y = 0.0
	_check(absf(displacement.length() - world.player.roll_distance) < 0.05
		and displacement.normalized().dot(Vector3.FORWARD.rotated(Vector3.UP, heading)) > 0.995,
		"An unobstructed roll covers its configured distance along its initial body heading")
	await _tap(KEY_SPACE)
	_key(KEY_W, true)
	await _seconds(maxf(0.02, world.player.roll_recovery * 0.4))
	_check(world.player.action_state == "recovery" and _flat_distance(end, world.player.global_position) < 0.005,
		"Recovery rejects another roll and holds translation even if W is pressed")
	_release_input()
	await _seconds(world.player.roll_recovery + 0.15)
	_check(world.player.action_state == "crouch_idle" and world.player.stance == "crouched"
		and _noise_events.is_empty(),
		"Roll and recovery finish quietly in crouch idle")
	# Hold Space across an entire second roll, its cooldown and the idle period.
	_key(KEY_SPACE, true)
	await _frames(2)
	_check(world.player.action_state == "roll", "A fresh Space press can start a roll after recovery")
	await _seconds(world.player.roll_duration + world.player.roll_recovery + 0.4)
	_check(world.player.action_state == "crouch_idle", "Holding Space never automatically chains another roll")
	_release_input()


func _test_roll_obstacles() -> void:
	for fixture in ["thin wall", "off-center desk corner", "narrow doorway", "person"]:
		await _place(ARENA)
		var origin: Vector3 = world.player.global_position
		var person: CharacterBody3D
		if fixture == "thin wall":
			_barrier(origin + Vector3(0, 1.2, -2.0), Vector3(3.0, 2.4, 0.04))
		elif fixture == "off-center desk corner":
			_barrier(origin + Vector3(0.61, 0.6, -2.0), Vector3(0.4, 1.2, 0.4))
		elif fixture == "narrow doorway":
			for side in [-1, 1]:
				_barrier(origin + Vector3(side * 0.775, 1.2, -2.0), Vector3(1, 2.4, 0.1))
		else:
			person = CharacterBody3D.new()
			person.collision_layer = 8
			person.collision_mask = 1
			person.position = origin + Vector3(0, 0, -2.0)
			var collider := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.height = 1.75
			capsule.radius = 0.35
			collider.shape = capsule
			collider.position.y = 0.875
			person.add_child(collider)
			world.add_child(person)
		await _frames(3)
		await _enter_crouch()
		await _tap(KEY_SPACE)
		var previous: Vector3 = world.player.global_position
		var stopped_during_roll := false
		var stopped_position := Vector3.ZERO
		var stopped_animation_time := 0.0
		var animation_continues := false
		var stayed_stopped := true
		var deadline: float = world.elapsed + world.player.roll_duration + 0.5
		while world.player.action_state == "roll" and world.elapsed < deadline:
			await _frames(1)
			var current: Vector3 = world.player.global_position
			if world.player.action_state == "roll":
				if not stopped_during_roll and _flat_distance(origin, current) > 0.03 \
					and _flat_distance(previous, current) < 0.00001:
					stopped_during_roll = true
					stopped_position = current
					stopped_animation_time = float(world.player.get_animation_status().get("time", 0))
				elif stopped_during_roll:
					stayed_stopped = stayed_stopped and _flat_distance(current, stopped_position) < 0.001
					animation_continues = animation_continues or float(world.player.get_animation_status().get("time", 0)) > stopped_animation_time + 0.025
			previous = current
		_check(stopped_during_roll and stayed_stopped and animation_continues,
			"A %s stops roll translation while the actual clip finishes safely at the same position" % fixture)
		var stopped: Vector3 = world.player.global_position
		_check(stopped.z > origin.z - 1.2
			and _flat_distance(origin, stopped) < world.player.roll_distance * 0.75
			and world.player.action_state == "recovery",
			"Rolling stops against a %s instead of tunneling or sliding through" % fixture)
		await _seconds(world.player.roll_recovery + 0.15)
		_check(_flat_distance(stopped, world.player.global_position) < 0.005
			and world.player.stance == "crouched" and world.player.action_state == "crouch_idle",
			"Collision with a %s leaves a stable, usable crouched player" % fixture)
		if is_instance_valid(person):
			person.queue_free()
		await _clear_obstacles()


func _test_pause_focus_and_reset() -> void:
	for mode in ["crouch", "sprint", "roll"]:
		await _place(ARENA)
		if mode != "sprint":
			await _enter_crouch()
		if mode == "roll":
			await _tap(KEY_SPACE)
		else:
			_key(KEY_W, true)
			_key(KEY_SHIFT, mode == "sprint")
		await _seconds(0.2)
		if mode == "sprint":
			world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			await _tap(KEY_ESCAPE)
		await _frames(2)
		var position: Vector3 = world.player.global_position
		var controls: Dictionary = world.player.get_control_status()
		var animation: Dictionary = world.player.get_animation_status()
		var elapsed: float = world.elapsed
		var noise_count := _noise_events.size()
		await _seconds(0.4)
		var frozen: Dictionary = world.player.get_control_status()
		_check(world.phase == "paused" and _flat_distance(position, world.player.global_position) < 0.001
			and is_equal_approx(world.elapsed, elapsed)
			and absf(float(world.player.get_animation_status().get("time", -1)) - float(animation.get("time", 0))) < 0.001
			and bool(world.player.get_animation_status().get("paused", false)),
			"Pausing %s freezes physical position, the scene clock and animation playback" % mode)
		_check(_timers_equal(controls, frozen) and _noise_events.size() == noise_count
			and _all_input_cleared(),
			"Pausing %s freezes action timers, makes no noise and clears held controls" % mode)
		world.resume_game()
		await _frames(2)
		if mode == "roll":
			_check(world.player.action_state == "roll"
				and float(world.player.get_control_status().get("roll_progress", 0)) > float(controls.get("roll_progress", 0)),
				"Continue resumes the interrupted roll from its saved progress")
		else:
			_check(_flat_distance(position, world.player.global_position) < 0.01
				and world.player.action_state != "sprint",
				"Continue from %s does not replay pre-pause held movement" % mode)
		world.restart_game()
		await _frames(4)
		var reset: Dictionary = world.player.get_control_status()
		_check(world.phase == "playing" and world.player.stance == "standing"
			and world.player.action_state == "idle" and _all_input_cleared()
			and _flat_distance(world.player.global_position, Vector3(5.5, 0, 27)) < 0.04
			and float(reset.get("roll_remaining", -1)) == 0.0
			and float(reset.get("recovery_remaining", -1)) == 0.0,
			"Retry from %s clears stance, roll/recovery timers and residual controls" % mode)
	await _place(ARENA)
	await _enter_crouch()
	await _tap(KEY_SPACE)
	await _seconds(0.2)
	world.show_menu()
	await _frames(3)
	var menu_state: Dictionary = world.player.get_control_status()
	_check(world.phase == "menu" and not world.player.action_state in ["roll", "recovery", "sprint"]
		and float(menu_state.get("roll_remaining", -1)) == 0.0
		and float(menu_state.get("recovery_remaining", -1)) == 0.0 and _all_input_cleared(),
		"Returning to the menu cancels active action state and pending recovery")
	world.start_game()
	await _frames(3)


func _test_rapid_inputs() -> void:
	await _place(ARENA)
	for index in 12:
		await _tap(KEY_C)
		_key(KEY_SHIFT, true)
		_key(KEY_W, true)
		await _frames(2)
		await _tap(KEY_SPACE)
		await _tap(KEY_C)
		_key(KEY_SHIFT, false)
		_key(KEY_W, false)
		_echo(KEY_C)
		_echo(KEY_SPACE)
		await _frames(2)
	_release_input()
	await _seconds(world.player.roll_duration + world.player.roll_recovery + 0.3)
	_check(not world.player.action_state in ["roll", "recovery", "sprint"]
		and world.player.global_position.is_finite() and world.player.velocity.is_finite(),
		"Rapid C/Shift/Space alternation settles without an invalid or stuck action state")
	var settled: Vector3 = world.player.global_position
	await _seconds(0.3)
	_check(_flat_distance(settled, world.player.global_position) < 0.001,
		"Rapid input changes do not leave a buffered roll or residual translation")


func _test_physics_rates() -> void:
	var distances: Array[float] = []
	var durations: Array[float] = []
	for rate in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		await _place(ARENA)
		await _enter_crouch()
		var start: Vector3 = world.player.global_position
		var started: float = world.elapsed
		await _tap(KEY_SPACE)
		await _wait_until_roll_ends()
		var duration: float = world.elapsed - started
		var distance := _flat_distance(start, world.player.global_position)
		distances.append(distance)
		durations.append(duration)
		_check(absf(distance - world.player.roll_distance) < 0.05
			and absf(duration - world.player.roll_duration) < 0.075,
			"A real %d Hz physics clock preserves roll distance and duration (%.4f m, %.4f s)" % [rate, distance, duration])
	_check(distances.max() - distances.min() < 0.035 and durations.max() - durations.min() < 0.06,
		"30/60/120 Hz physics rates produce consistent roll travel and completion time")
	Engine.physics_ticks_per_second = _original_physics_ticks
	await _frames(3)


func _test_exit_cleanup() -> void:
	world.restart_game()
	await _frames(3)
	var exit_rect: Rect2 = world.level.exit_rect
	await _place(Vector3(exit_rect.get_center().x, 0.05, exit_rect.end.y + 0.5))
	await _enter_crouch()
	await _tap(KEY_SPACE)
	var deadline: float = world.elapsed + 2.0
	while world.phase == "playing" and world.elapsed < deadline:
		await _frames(1)
	var end: Dictionary = world.player.get_control_status()
	_check(world.phase == "won" and not world.player.action_state in ["roll", "recovery", "sprint"]
		and float(end.get("roll_remaining", -1)) == 0.0
		and float(end.get("recovery_remaining", -1)) == 0.0 and _all_input_cleared(),
		"Rolling across the exit completes the sample and clears action timers and input")
	world.restart_game()
	await _frames(3)
	_check(world.phase == "playing" and world.player.stance == "standing" and world.player.action_state == "idle",
		"Retry after rolling through the exit starts a fresh standing session")


func _on_sprint_noise(origin: Vector3, radius: float) -> void:
	_noise_events.append({"origin": origin, "radius": radius, "state": world.player.action_state})


func _timers_equal(first: Dictionary, second: Dictionary) -> bool:
	for key in ["roll_progress", "roll_remaining", "recovery_remaining"]:
		if absf(float(first.get(key, -1)) - float(second.get(key, -2))) > 0.00001:
			return false
	return true


func _all_input_cleared() -> bool:
	for action in InputMap.get_actions():
		if action in ["move_forward", "move_back", "turn_left", "turn_right", "sprint", "crouch_toggle", "roll"]:
			if Input.is_action_pressed(action):
				return false
	return _input_cleared()


func _wait_until_roll_ends() -> void:
	var deadline: float = world.elapsed + world.player.roll_duration + 0.5
	while world.player.action_state == "roll" and world.elapsed < deadline:
		await _frames(1)


func _tap(key: Key) -> void:
	_key(key, true)
	await _frames(1)
	_key(key, false)
	await _frames(1)


func _enter_crouch() -> void:
	# A preceding stand/crouch blend must complete before accepting another key.
	await _seconds(0.2)
	if world.player.stance == "standing":
		await _tap(KEY_C)
	await _seconds(0.2)


func _echo(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	event.echo = true
	Input.parse_input_event(event)


func _release_input() -> void:
	super._release_input()
	for key in [KEY_C, KEY_SPACE, KEY_SHIFT]:
		_key(key, false)
	for action in ["sprint", "crouch_toggle", "roll"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	Input.flush_buffered_events()


func _seconds(duration: float) -> void:
	await _frames(maxi(1, ceili(duration * Engine.physics_ticks_per_second)))
