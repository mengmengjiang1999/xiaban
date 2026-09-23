extends "res://tests/p3_test.gd"
## P4b integration against the complete map, real actors and physics space.
## Placement and timing overrides isolate geometry, sound and lifecycle cases. The final
## route uses ordinary movement input with all three production routines active.
## bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p4b_test.gd
var _defaults: Array[Dictionary] = []
var _discovery_ids: Array[String] = []

func _run() -> void:
	world = load("res://scenes/p4b.tscn").instantiate()
	root.add_child(world)
	await _frames(6)
	_check(world.phase == "menu" and world.guards.size() == 3, "The full first level opens with exactly three leaders")
	var ids: Array[String] = []
	for guard in world.guards:
		var saved := {}
		for property in ["work_duration", "raise_duration", "watch_duration", "lower_duration", "confirm_duration", "phase_offset"]:
			saved[property] = guard.get(property)
		_defaults.append(saved)
		ids.append(guard.guard_id)
		guard.discovered.connect(func(source): _discovery_ids.append(source.guard_id))
		_check(bool(guard.get_status().frozen) and guard.actor.skeleton.get_bone_count() >= 15,
			"%s has a real independent humanoid and is frozen at the menu" % guard.guard_id)
	_check(ids.size() == 3 and ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2], "Every leader has a stable distinct identity")
	world.player.sprint_noise_emitted.connect(_on_sprint_noise)
	world.start_game()
	await _frames(4)
	_check(world.phase == "playing" and _flat_distance(world.player.global_position, world.level.spawn_position) < 0.03,
		"Start places the player at the complete first-level spawn")
	await _test_independent_routines()
	await _test_cover_for_each_leader()
	await _test_desk_geometry()
	await _test_sound_isolation()
	await _test_room_occlusion()
	await _test_failure_for_each_leader()
	await _test_freeze_and_reset()
	await _test_all_exit_priorities()
	await _test_route()
	_restore_guards()
	_release_input()
	print("P4B_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.queue_free()
	await _frames(3)
	quit(1 if failed > 0 else 0)

func _restore_guards() -> void:
	for index in world.guards.size():
		var guard = world.guards[index]
		var spec: Dictionary = world.level.guard_specs[index]
		guard.setup(world, spec.position, float(spec.work_heading))
		for property in _defaults[index]:
			guard.set(property, _defaults[index][property])
		guard.reset_guard()

func _fresh() -> void:
	_restore_guards()
	world.restart_game()
	await _frames(3)

func _isolated(index: int, at: Vector3, high_confirmation: bool = true) -> void:
	await _fresh()
	for other in world.guards:
		other.work_duration = 100.0
		other.phase_offset = 0.0
		other.reset_guard()
	var guard = world.guards[index]
	guard.work_duration = 0.12
	guard.raise_duration = 0.15
	guard.watch_duration = 30.0
	guard.confirm_duration = 10.0 if high_confirmation else 0.35
	guard.reset_guard()
	await _place(at)

func _wait_observer(guard: Node, expected: String, maximum: float = 12.0) -> bool:
	for unused in range(ceili(maximum * Engine.physics_ticks_per_second)):
		if guard.get_status().state == expected:
			return true
		if world.phase != "playing":
			break
		await _frames(1)
	_check(false, "%s reaches %s (actual %s, phase %s)" % [guard.guard_id, expected, guard.get_status().state, world.phase])
	return false

func _test_independent_routines() -> void:
	await _fresh()
	var distinct := false
	for unused in range(240):
		var states: Array[String] = []
		for guard in world.guards:
			states.append(guard.get_status().state)
		distinct = distinct or states[0] != states[1] or states[0] != states[2]
		await _frames(1)
	_check(distinct, "Three production routines reach different states rather than sharing a synchronized clock")
	for index in world.guards.size():
		await _isolated(index, world.level.observation_points[index])
		var guard = world.guards[index]
		await _wait_observer(guard, "watching")
		var expected := Vector3.FORWARD.rotated(Vector3.UP,
			float(world.level.guard_specs[index].work_heading) + float(world.level.guard_specs[index].watch_offset))
		var facing := _v3(guard.get_status().facing)
		_check(facing.dot(expected) > 0.999, "%s reaches its configured routine observation direction" % guard.guard_id)
		_check(not guard.can_see_player(), "%s has an actual protected observation point before its encounter" % guard.guard_id)

func _test_cover_for_each_leader() -> void:
	for index in world.guards.size():
		await _isolated(index, world.level.exposure_points[index])
		var guard = world.guards[index]
		await _wait_observer(guard, "watching")
		var standing: Array = world.player.get_detection_points()
		_check(guard.can_see_player(), "%s sees the standing head or chest above its real low cabinet" % guard.guard_id)
		var position: Vector3 = world.player.global_position
		await _enter_crouch()
		var crouched: Array = world.player.get_detection_points()
		await _seconds(0.6)
		_check(not guard.can_see_player() and float(guard.get_status().progress) == 0.0
			and standing[0].y - crouched[0].y > 0.3 and _flat_distance(position, world.player.global_position) < 0.001,
			"%s cannot see the real lowered head and chest at the same cabinet location" % guard.guard_id)
		await _tap(KEY_C)
		await _seconds(0.25)
		_check(guard.can_see_player(), "%s sees the player again after standing at that same point" % guard.guard_id)

func _test_desk_geometry() -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for index in world.guards.size():
		var probe: Array = world.level.desk_clearance_probes[index]
		_check(space.intersect_ray(PhysicsRayQueryParameters3D.create(probe[0], probe[1], 16)).is_empty()
			and not space.intersect_ray(PhysicsRayQueryParameters3D.create(probe[0], probe[1], 1)).is_empty(),
			"Desk %d transmits sight between its legs while preventing under-desk passage" % (index + 1))
		probe = world.level.desk_tabletop_probes[index]
		_check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(probe[0], probe[1], 16)).is_empty(),
			"Desk %d rendered tabletop blocks sight" % (index + 1))

func _test_sound_isolation() -> void:
	for index in world.guards.size():
		await _fresh()
		for guard in world.guards:
			guard.work_duration = 100.0
			guard.phase_offset = 0.0
			guard.reset_guard()
		await _place(world.level.observation_points[index])
		var start_positions: Array[Vector3] = []
		for guard in world.guards:
			start_positions.append(guard.global_position)
		_noise_events.clear()
		_key(KEY_W, true)
		_key(KEY_SHIFT, true)
		await _seconds(0.12)
		_release_input()
		_check(not _noise_events.is_empty(), "Encounter %d receives an actual moving sprint footstep" % (index + 1))
		var local = world.guards[index]
		var local_status: Dictionary = local.get_status()
		# After making a sound, actually retreat to cover; standing exposed must remain detectable.
		await _place(world.level.exposure_points[index])
		await _enter_crouch()
		_check(bool(local_status.noise_attention) and local_status.heard_origin != null and world.phase == "playing",
			"%s reacts to a nearby sprint without automatically discovering a hidden player" % local.guard_id)
		var isolated := true
		for other_index in world.guards.size():
			if other_index != index:
				var other: Dictionary = world.guards[other_index].get_status()
				isolated = isolated and other.heard_origin == null and not bool(other.noise_attention) and other.state == "working"
		_check(isolated, "A footstep in encounter %d is not shared with the two distant leaders" % (index + 1))
		await _wait_observer(local, "watching")
		var heard := _v3(local.get_status().heard_origin)
		var offset: Vector3 = heard - local.global_position
		offset.y = 0.0
		_check(_v3(local.get_status().facing).dot(offset.normalized()) > 0.99,
			"%s looks at its recorded sound location" % local.guard_id)
		await _seconds(0.45)
		var stationary := true
		for other_index in world.guards.size():
			stationary = stationary and world.guards[other_index].global_position.distance_to(start_positions[other_index]) < 0.001
		_check(stationary and world.phase == "playing", "All three leaders stay at their desks without chasing after a sound")

func _test_room_occlusion() -> void:
	# An overlong test-only range isolates wall occlusion from distance and FOV.
	await _fresh()
	for index in world.guards.size():
		var guard = world.guards[index]
		guard.work_duration = 0.1
		guard.raise_duration = 0.1
		guard.watch_duration = 100.0
		guard.confirm_duration = 100.0
		guard.phase_offset = 0.0
		guard.reset_guard()
	await _seconds(0.25)
	for index in world.guards.size():
		var guard = world.guards[index]
		var old_range: float = guard.vision_range
		var old_fov: float = guard.vision_fov_degrees
		guard.vision_range = 100.0
		guard.vision_fov_degrees = 360.0
		var blocked := true
		for other in world.guards.size():
			if other == index:
				continue
			await _place(world.level.exposure_points[other])
			blocked = blocked and not guard.can_see_player()
		_check(blocked, "%s cannot see players through the opaque partitions of the other office areas" % guard.guard_id)
		guard.vision_range = old_range
		guard.vision_fov_degrees = old_fov

func _test_failure_for_each_leader() -> void:
	for index in world.guards.size():
		await _isolated(index, world.level.exposure_points[index], false)
		var guard = world.guards[index]
		var before := _discovery_ids.size()
		await _wait_observer(guard, "watching")
		await _seconds(0.12)
		_check(world.phase == "playing" and float(guard.get_status().progress) > 0.0 and float(guard.get_status().progress) < 1.0,
			"%s provides a visible confirmation interval before discovery" % guard.guard_id)
		await _seconds(0.4)
		_check(world.phase == "lost" and world.discovered_by == guard.guard_id and _discovery_ids.size() == before + 1,
			"%s independently causes the correct named failure exactly once" % guard.guard_id)
		await _seconds(0.2)
		_check(_all_frozen() and _all_input_cleared() and _discovery_ids.size() == before + 1,
			"Failure by %s freezes every leader and clears controls without repeated discovery" % guard.guard_id)

func _test_freeze_and_reset() -> void:
	await _fresh()
	await _seconds(1.0)
	world.pause_game()
	await _frames(2)
	var paused: Array[Dictionary] = world.get_guard_statuses()
	var elapsed: float = world.elapsed
	await _seconds(0.5)
	var frozen: Array[Dictionary] = world.get_guard_statuses()
	_check(paused == frozen and _all_frozen() and elapsed == world.elapsed, "Pause freezes every independent clock, body pose and detection counter")
	world.resume_game()
	await _seconds(0.15)
	var all_advanced := true
	for index in world.guards.size():
		all_advanced = all_advanced and float(world.guards[index].get_status().visual_time) > float(paused[index].visual_time)
	_check(all_advanced and _all_input_cleared(), "Continue advances all saved office routines without replaying held controls")
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(world.phase == "paused" and _all_frozen(), "Losing application focus pauses all four characters")
	world.show_menu()
	await _frames(2)
	_check(world.phase == "menu" and _all_frozen() and world.discovered_by.is_empty(), "Returning to the menu freezes the whole encounter and clears prior outcome identity")
	await _fresh()
	var reset := true
	for index in world.guards.size():
		var guard = world.guards[index]
		var status: Dictionary = guard.get_status()
		reset = reset and status.state == "working" and status.heard_origin == null and not bool(status.confirmed)
		reset = reset and float(status.progress) == 0.0 and _flat_distance(guard.global_position, world.level.guard_specs[index].position) < 0.001
	_check(reset and world.player.stance == "standing" and world.discovered_by.is_empty(), "New game resets all three positions, routines, sound targets and confirmations together")

func _test_all_exit_priorities() -> void:
	var original_exit: Rect2 = world.level.exit_rect
	for index in world.guards.size():
		await _isolated(index, world.level.exposure_points[index], false)
		var guard = world.guards[index]
		guard.confirm_duration = 0.08
		await _wait_observer(guard, "watching")
		await _frames(3)
		world.level.exit_rect = Rect2(world.player.position.x - 0.4, world.player.position.z - 1.0, 0.8, 0.995)
		_key(KEY_W, true)
		await _frames(3)
		_release_input()
		_check(world.phase == "lost" and world.discovered_by == guard.guard_id,
			"%s discovery wins over an exit crossed on the confirming physics update" % guard.guard_id)
		world.level.exit_rect = original_exit

func _test_route() -> void:
	await _fresh()
	await _enter_crouch()
	_noise_events.clear()
	var reached := true
	for index in world.guards.size():
		var exposure: Vector3 = world.level.exposure_points[index]
		var entry := exposure + Vector3(0, 0, -2.1)
		if not await _walk_to(world.level.observation_points[index]):
			reached = false
			break
		await _wait_observer(world.guards[index], "watching")
		await _wait_observer(world.guards[index], "working")
		if not await _walk_to(exposure) or not await _walk_to(entry):
			reached = false
			break
		await _wait_observer(world.guards[index], "watching")
		await _wait_observer(world.guards[index], "working")
		await _tap(KEY_SPACE)
		await _wait_until_roll_ends()
		await _seconds(world.player.roll_recovery + 0.1)
		_check(_noise_events.is_empty(), "Encounter %d timed roll creates no sprint sound" % (index + 1))
		if index < 2:
			if not await _walk_to(world.level.route_waypoints[1 + 2 * index]) or not await _walk_to(world.level.route_waypoints[2 + 2 * index]):
				reached = false
				break
		else:
			reached = await _walk_to(world.level.route_waypoints[-1])
	await _frames(3)
	print("P4B_ROUTE_METRICS elapsed=%.3f distance=%.3f" % [world.elapsed, world.player.travel_distance])
	_check(reached and world.phase == "won" and world.player.travel_distance > 58.0,
		"A controller uses crouched movement, waits and quiet rolls through every full-level corridor with all three original AI routines active")
	_check(world.phase == "won" and _all_frozen() and _all_input_cleared(), "The final exit freezes all three leaders and clears active controls")
	await _fresh()
	_check(world.phase == "playing" and world.level.stage_index(world.player.global_position) == 0
		and _flat_distance(world.player.global_position, world.level.spawn_position) < 0.03,
		"Retry after the complete route restores the first encounter")

func _walk_to(target: Vector3) -> bool:
	for unused in range(ceili(45.0 * Engine.physics_ticks_per_second)):
		if world.phase == "won":
			_release_input()
			return true
		if world.phase != "playing":
			print("P4B_ROUTE_FAILURE target=%s at=%s phase=%s guard=%s" % [target, world.player.global_position, world.phase, world.discovered_by])
			_release_input()
			return false
		var offset: Vector3 = target - world.player.global_position
		offset.y = 0.0
		if offset.length() < 0.055:
			_release_input()
			return true
		var heading := atan2(-offset.x, -offset.z)
		var error := angle_difference(world.player.rotation.y, heading)
		Input.action_press("turn_left") if error > 0.025 else Input.action_release("turn_left")
		Input.action_press("turn_right") if error < -0.025 else Input.action_release("turn_right")
		Input.action_press("move_forward") if absf(error) < 0.12 else Input.action_release("move_forward")
		await _frames(1)
	print("P4B_ROUTE_TIMEOUT target=%s at=%s" % [target, world.player.global_position])
	_release_input()
	return false

func _all_frozen() -> bool:
	for guard in world.guards:
		if not bool(guard.get_status().frozen):
			return false
	return true

func _v3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
