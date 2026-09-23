extends "res://tests/p3_test.gd"
## P4a uses the actual player skeleton, physics space and world lifecycle.
## Timings are prototype parameters, not assertions about final game balance.
## Run: bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p4_test.gd

var _guard_defaults: Dictionary = {}
var _discoveries := 0


func _run() -> void:
	world = load("res://scenes/p4.tscn").instantiate()
	root.add_child(world)
	await _frames(6)
	_check(world.phase == "menu" and bool(world.guard.get_status().frozen),
		"P4 opens at its own menu with the office leader frozen")
	for property in ["work_duration", "raise_duration", "watch_duration", "lower_duration", "confirm_duration"]:
		_guard_defaults[property] = world.guard.get(property)
	world.guard.discovered.connect(func(_guard): _discoveries += 1)
	world.player.sprint_noise_emitted.connect(_on_sprint_noise)
	_barrier(ARENA + Vector3(0, -0.3, 0), Vector3(40, 0.5, 40), false)
	world.start_game()
	await _frames(4)
	_check(world.phase == "playing" and _flat_distance(world.player.global_position, world.level.spawn_position) < 0.03,
		"Starting places the player at the P4 route spawn")
	await _test_real_cover_and_desk()
	await _test_sight_geometry()
	await _test_work_and_confirmation()
	await _test_noise_attention()
	await _test_roll_detection()
	await _test_pause_and_lifecycle()
	await _test_exit_priority()
	_restore_defaults()
	_release_input()
	print("P4_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.queue_free()
	await _frames(3)
	quit(1 if failed > 0 else 0)


func _test_real_cover_and_desk() -> void:
	_slow_confirm()
	world.guard.reset_guard()
	await _place(world.level.cover_test_position)
	await _wait_guard("watching")
	var standing: Array = world.player.get_detection_points()
	var exact_position: Vector3 = world.player.global_position
	_check(world.guard.can_see_player(), "Standing behind the actual low cabinet leaves a real head or chest point visible")
	await _enter_crouch()
	var crouching: Array = world.player.get_detection_points()
	_check(_flat_distance(exact_position, world.player.global_position) < 0.001
		and standing[0].y > crouching[0].y + 0.3 and not world.guard.can_see_player(),
		"Crouching at the exact same cabinet position hides the real animated head and chest")
	await _seconds(0.6)
	_check(world.phase == "playing" and float(world.guard.get_status().progress) == 0.0,
		"Staying crouched behind the cabinet cannot build hidden detection progress")
	await _tap(KEY_C)
	await _seconds(0.25)
	_check(world.guard.can_see_player(), "Standing back up behind the same cabinet restores actual visibility")
	var probe: Array = world.level.desk_clearance_probe
	var sight := PhysicsRayQueryParameters3D.create(probe[0], probe[1], 16)
	var movement := PhysicsRayQueryParameters3D.create(probe[0], probe[1], 1)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	_check(space.intersect_ray(sight).is_empty() and not space.intersect_ray(movement).is_empty(),
		"The open space between real desk legs transmits sight while the desk still blocks character passage")
	var top_probe: Array = world.level.desk_tabletop_probe
	_check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(top_probe[0], top_probe[1], 16)).is_empty(),
		"The rendered desk tabletop has actual vision-blocking geometry")


func _test_sight_geometry() -> void:
	await _arena(Vector3(0, 0, -4))
	await _wait_guard("watching")
	_check(world.guard.can_see_player(), "An unobstructed standing player in the watch cone is visible")
	await _place(ARENA + Vector3(0, 0, 4))
	_check(not world.guard.can_see_player(), "A player behind the watching leader is outside its cone")
	await _place(ARENA + Vector3(0, 0, -9))
	_check(not world.guard.can_see_player(), "A player beyond the configured sight distance is not visible")
	await _place(ARENA + Vector3(0, 0, -4))
	var wall := _barrier(ARENA + Vector3(0, 1.25, -2), Vector3(2, 2.5, 0.1))
	wall.collision_layer = 16
	await _frames(3)
	_check(not world.guard.can_see_player(), "A thin opaque wall blocks both animated detection points")
	await _clear_obstacles()
	var points: Array = world.player.get_detection_points()
	var eye: Array = world.guard.get_status().eye_position
	var midway_head: float = (float(eye[1]) + points[0].y) * 0.5
	var midway_chest: float = (float(eye[1]) + points[1].y) * 0.5
	var top: float = (midway_head + midway_chest) * 0.5
	var partial := _barrier(Vector3(ARENA.x, top * 0.5, ARENA.z - 2), Vector3(2, top, 0.1))
	partial.collision_layer = 16
	await _frames(3)
	_check(world.guard.can_see_player(), "One exposed head point is enough even while a wall hides the chest")
	await _clear_obstacles()


func _test_work_and_confirmation() -> void:
	await _arena(Vector3(0, 0, -4), false)
	world.guard.work_duration = 0.5
	world.guard.raise_duration = 0.4
	world.guard.confirm_duration = 0.35
	world.guard.reset_guard()
	await _seconds(0.3)
	_check(world.guard.get_status().state == "working" and not world.guard.can_see_player()
		and not bool(world.guard.get_status().fan_visible) and world.phase == "playing",
		"A head-down working leader neither sees the exposed player nor shows an active sight fan")
	await _wait_guard("raising")
	var head_before: Array = world.guard.get_status().head_position
	await _seconds(0.2)
	var head_after: Array = world.guard.get_status().head_position
	_check(world.guard.get_status().state == "raising" and not world.guard.can_see_player()
		and not bool(world.guard.get_status().fan_visible) and head_before != head_after,
		"The raising telegraph visibly changes the head pose before enabling detection")
	await _wait_guard("watching")
	await _seconds(0.12)
	var brief: Dictionary = world.guard.get_status()
	_check(world.phase == "playing" and float(brief.progress) > 0.0 and float(brief.progress) < 1.0
		and bool(brief.fan_visible), "Brief exposure creates visible confirmation progress without immediate failure")
	var wall := _barrier(ARENA + Vector3(0, 1.25, -2), Vector3(2, 2.5, 0.1))
	wall.collision_layer = 16
	await _frames(3)
	_check(world.phase == "playing" and float(world.guard.get_status().progress) == 0.0,
		"Returning behind solid cover resets incomplete confirmation")
	await _clear_obstacles()
	await _seconds(0.17)
	_check(world.phase == "playing", "A second short exposure does not inherit the previous hidden confirmation")
	var before := _discoveries
	await _seconds(0.3)
	_check(world.phase == "lost" and _discoveries == before + 1,
		"Sustained visible exposure confirms discovery and enters the failure screen exactly once")
	await _seconds(0.5)
	_check(_discoveries == before + 1 and _all_input_cleared(),
		"A failed game cannot repeatedly send discoveries and has cleared all held controls")
	await _arena(Vector3(0, 0, 4), false)
	world.guard.work_duration = 0.12
	world.guard.raise_duration = 0.12
	world.guard.watch_duration = 0.2
	world.guard.lower_duration = 0.2
	world.guard.reset_guard()
	await _wait_guard("lowering")
	_check(not world.guard.can_see_player() and not bool(world.guard.get_status().fan_visible),
		"Lowering the head disables the active observation cone")
	await _wait_guard("working")
	_check(world.guard.get_status().state == "working", "An uneventful look completes and returns to office work")


func _test_noise_attention() -> void:
	await _arena(Vector3(0, 0, 4), false)
	world.guard.work_duration = 10.0
	world.guard.raise_duration = 0.35
	world.guard.watch_duration = 0.7
	world.guard.lower_duration = 0.2
	world.guard.reset_guard()
	var initial_position: Vector3 = world.guard.global_position
	world.guard.receive_noise(ARENA + Vector3(-4, 0, 0), 2.0)
	await _frames(2)
	_check(world.guard.get_status().state == "working" and world.guard.get_status().heard_origin == null,
		"Noise outside its finite radius does not reveal a sound source or interrupt work")
	var sound_source := ARENA + Vector3(-3, 0, 0)
	world.guard.receive_noise(sound_source, 8.0)
	await _frames(2)
	_check(world.guard.get_status().state == "raising" and bool(world.guard.get_status().noise_attention)
		and world.phase == "playing", "Audible sprint noise starts the raising telegraph without causing discovery")
	for unused in range(30):
		world.guard.receive_noise(sound_source, 8.0)
		await _frames(1)
	var attending: Dictionary = world.guard.get_status()
	_check(attending.state == "watching", "Repeated footsteps cannot indefinitely restart the raising telegraph")
	var facing := _vector(attending.facing)
	_check(facing.dot(Vector3.LEFT) > 0.99 and _vector(attending.heard_origin).distance_to(sound_source) < 0.001,
		"Noise turns the leader toward its recorded source instead of the player's hidden current position")
	await _place(ARENA + Vector3(3, 0, 0))
	_check(_vector(world.guard.get_status().facing).dot(Vector3.LEFT) > 0.99 and world.phase == "playing",
		"A hidden player moving away from the sound does not attract omniscient tracking")
	await _wait_guard("working")
	_check(world.guard.global_position.distance_to(initial_position) < 0.001 and world.phase == "playing",
		"Noise investigation completes at the same desk without chasing or failing an unseen player")
	# An independently configured second leader receives no event implicitly.
	var other = load("res://scripts/p4_guard.gd").new()
	other.setup(world, ARENA + Vector3(12, 0, 0), 0.0)
	other.work_duration = 10.0
	world.add_child(other)
	other.set_frozen(false)
	world.guard.receive_noise(sound_source, 8.0)
	await _frames(3)
	_check(other.get_status().state == "working" and other.get_status().heard_origin == null,
		"One leader's noise response does not share hidden information with another instance")
	other.queue_free()
	await _frames(2)


func _test_roll_detection() -> void:
	await _arena(Vector3(0, 0, -4))
	await _enter_crouch()
	await _wait_guard("watching")
	_noise_events.clear()
	world.guard.confirm_duration = 0.25
	await _tap(KEY_SPACE)
	_check(world.player.action_state == "roll" and world.guard.can_see_player(),
		"The actual rolling head and chest remain visually detectable in an unobstructed cone")
	await _seconds(0.4)
	_check(_noise_events.is_empty() and world.phase == "lost",
		"Rolling is quiet but cannot bypass visual discovery through a stealth immunity flag")


func _test_pause_and_lifecycle() -> void:
	await _arena(Vector3(0, 0, 4), false)
	world.guard.work_duration = 0.12
	world.guard.raise_duration = 0.7
	world.guard.reset_guard()
	await _wait_guard("raising")
	await _seconds(0.15)
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	await _frames(2)
	world.pause_game()
	await _frames(2)
	var paused: Dictionary = world.guard.get_status()
	var player_time: float = world.player.get_animation_status().time
	var elapsed: float = world.elapsed
	var position: Vector3 = world.player.global_position
	await _seconds(0.5)
	var frozen: Dictionary = world.guard.get_status()
	_check(world.phase == "paused" and bool(frozen.frozen)
		and frozen.state == paused.state and is_equal_approx(float(frozen.state_time), float(paused.state_time))
		and frozen.head_position == paused.head_position and frozen.visual_time == paused.visual_time,
		"Pause freezes the leader's raising clock and actual animated pose")
	_check(is_equal_approx(elapsed, world.elapsed) and position.distance_to(world.player.global_position) < 0.001
		and is_equal_approx(player_time, world.player.get_animation_status().time) and _all_input_cleared(),
		"The same pause also freezes player pose, movement and game time while clearing held inputs")
	world.resume_game()
	await _seconds(0.1)
	_check(world.guard.get_status().state == "raising"
		and float(world.guard.get_status().state_time) > float(paused.state_time)
		and position.distance_to(world.player.global_position) < 0.01,
		"Continue resumes the saved telegraph without replaying old movement")
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(world.phase == "paused" and bool(world.guard.get_status().frozen),
		"Losing application focus pauses both player and leader")
	world.show_menu()
	await _frames(2)
	world.guard.setup(world, world.level.guard_spawn, world.level.guard_heading)
	world.start_game()
	await _frames(2)
	_check(world.phase == "playing" and world.guard.get_status().state == "working"
		and world.guard.get_status().heard_origin == null and float(world.guard.get_status().progress) == 0.0
		and not bool(world.guard.get_status().confirmed) and world.player.stance == "standing"
		and _flat_distance(world.guard.global_position, world.level.guard_spawn) < 0.001,
		"A new game clears the sound target, confirmation, leader pose and previous player action")
	await _arena(Vector3(0, 0, -4))
	world.guard.confirm_duration = 0.1
	await _wait_guard("watching")
	await _seconds(0.2)
	_check(world.phase == "lost", "The failure lifecycle is reached through real line-of-sight detection")
	world.restart_game()
	await _frames(2)
	_check(world.phase == "playing" and world.guard.get_status().state == "working"
		and not bool(world.guard.get_status().confirmed) and world.guard.get_status().heard_origin == null
		and world.player.action_state == "idle" and _all_input_cleared(),
		"Retry from failure creates a fresh playable office encounter")


func _test_exit_priority() -> void:
	await _arena(Vector3(0, 0, -4), false)
	world.guard.work_duration = 0.1
	world.guard.raise_duration = 0.1
	world.guard.confirm_duration = 0.08
	world.guard.reset_guard()
	await _wait_guard("watching")
	# Walk into a nearby exit on the physics tick that completes confirmation.
	# The current point remains outside, so rendering cannot finish early.
	await _frames(3)
	var old_exit: Rect2 = world.level.exit_rect
	world.level.exit_rect = Rect2(Vector2(world.player.position.x - 0.4, world.player.position.z - 1.0), Vector2(0.8, 0.995))
	_key(KEY_W, true)
	await _frames(3)
	_release_input()
	_check(world.phase == "lost", "Confirmed discovery takes priority over an exit reached on the same encounter update")
	world.level.exit_rect = old_exit
	_restore_defaults()
	world.restart_game()
	await _frames(3)
	var center: Vector2 = world.level.exit_rect.get_center()
	await _place(Vector3(center.x, 0.05, center.y))
	await _frames(3)
	_check(world.phase == "won" and _all_input_cleared() and bool(world.guard.get_status().frozen),
		"Reaching the door without being discovered completes the route and freezes the leader")
	world.restart_game()
	await _frames(3)
	_check(world.phase == "playing" and _flat_distance(world.player.global_position, world.level.spawn_position) < 0.03
		and world.guard.get_status().state == "working" and float(world.guard.get_status().progress) == 0.0,
		"Retry after success resets both the player route and the office leader")


func _arena(player_offset: Vector3, accelerated: bool = true) -> void:
	world.restart_game()
	world.guard.set_frozen(true)
	_slow_confirm()
	if not accelerated:
		world.guard.work_duration = 10.0
	world.guard.setup(world, ARENA, 0.0)
	world.guard.reset_guard()
	await _place(ARENA + player_offset)
	world.guard.set_frozen(false)


func _slow_confirm() -> void:
	world.guard.work_duration = 0.12
	world.guard.raise_duration = 0.15
	world.guard.watch_duration = 20.0
	world.guard.lower_duration = 0.15
	world.guard.confirm_duration = 10.0


func _wait_guard(expected: String, max_seconds: float = 3.0) -> void:
	for unused in range(ceili(max_seconds * Engine.physics_ticks_per_second)):
		if world.guard.get_status().state == expected:
			return
		await _frames(1)
	_check(false, "Leader reached expected state %s (actual %s)" % [expected, world.guard.get_status().state])


func _restore_defaults() -> void:
	world.guard.setup(world, world.level.guard_spawn, world.level.guard_heading)
	for property in _guard_defaults:
		world.guard.set(property, _guard_defaults[property])


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
