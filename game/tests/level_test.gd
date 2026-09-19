extends SceneTree
## Run with: bash tools/godot.sh --headless --script res://tests/level_test.gd
## These checks exercise the real scene, input actions and physics world.
## They do not certify rendering, sound or the difficulty of a full playthrough.

var level: Node3D
var passed: int = 0
var failed: int = 0
var spawn: Vector3
var guard_spawns: Array[Vector3] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	level = scene.instantiate()
	root.add_child(level)
	await _frames(6)
	spawn = level.player.global_position
	for guard in level.guards:
		guard_spawns.append(guard.global_position)
	_check(level.phase == "menu", "Scene opens at the start menu")
	_check(level.guards.size() == 3, "The level has three bosses")
	level.start_game()
	await _frames(2)
	_check(level.phase == "playing", "Start enters playable state")
	await _test_spawn_safety()
	await _test_patrol()
	await _test_vision()
	await _test_navigation()
	await _test_movement()
	await _test_physical_keys()
	await _test_alert_and_pause()
	await _test_outcomes()
	_release_input()
	print("LEVEL_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	# End the last retry's short sound before releasing its owning scene.
	level.phase = "menu"
	level.get("_audio").stop()
	await _frames(30)
	level.queue_free()
	await _frames(30)
	quit(1 if failed > 0 else 0)


func _test_spawn_safety() -> void:
	level.restart_game()
	await _frames(180)
	var safe: bool = level.phase == "playing"
	for guard in level.guards:
		safe = safe and guard.alert < 0.01
	_check(safe, "An idle new player is safe at spawn for three seconds")


func _test_patrol() -> void:
	level.restart_game()
	level.player.global_position = Vector3(2, 0, 3)
	level.player.velocity = Vector3.ZERO
	var office_reached_end: bool = false
	var office_reversed: bool = false
	var stair_reached_right: bool = false
	var stair_reached_left: bool = false
	var stair_reversed_twice: bool = false
	for frame in range(1260):
		await _frames(1)
		var office: Vector3 = level.guards[1].global_position
		var stairs: Vector3 = level.guards[2].global_position
		if office.x < 12.6 and absf(office.z - 12.0) < 0.5:
			office_reached_end = true
		if office_reached_end and office.x > 13.4:
			office_reversed = true
		if stairs.x > 20.5:
			stair_reached_right = true
		if stair_reached_right and stairs.x < 11.5:
			stair_reached_left = true
		if stair_reached_left and stairs.x > 12.5:
			stair_reversed_twice = true
	_check(office_reached_end and office_reversed, "Office boss passes through the doorway and reverses at the corridor endpoint")
	_check(stair_reached_right and stair_reached_left and stair_reversed_twice, "Stair boss reaches both patrol endpoints and keeps patrolling")
	_check(level.phase == "playing", "Patrol testing does not accidentally trigger an outcome")


func _test_vision() -> void:
	level.restart_game()
	_freeze_guards(true)
	var guard = level.guards[0]
	guard.global_position = Vector3(2, 0, 24)
	guard.facing = Vector3.RIGHT
	await _frames(3)
	_check(guard.can_see(Vector3(5, 0, 24)), "Boss sees an unobstructed player in front")
	_check(not guard.can_see(Vector3(1, 0, 24)), "Boss cannot see directly behind")
	_check(not guard.can_see(Vector3(2 + guard.sight_range + 1, 0, 24)), "Sight respects its maximum distance")
	_check(not guard.can_see(Vector3(2, 0, 26)), "Sight excludes points outside its angle")
	var barrier := _barrier(Vector3(3.5, 1, 24), Vector3(0.3, 2, 2), 3)
	await _frames(3)
	_check(not guard.can_see(Vector3(5, 0, 24)), "A tall physical wall blocks sight")
	barrier.queue_free()
	await _frames(3)
	barrier = _barrier(Vector3(3.5, 0.4, 24), Vector3(0.3, 0.8, 2), 1)
	await _frames(3)
	_check(guard.can_see(Vector3(5, 0, 24)), "A low desk blocks movement but not standing sight")
	barrier.queue_free()
	guard.global_position = Vector3(5.5, 0, 26.5)
	guard.facing = Vector3.RIGHT
	await _frames(3)
	_check(not guard.can_see(Vector3(9, 0, 26.5)), "The actual workstation partition blocks sight")


func _test_navigation() -> void:
	var from := Vector3(8.5, 0, 11.5)
	var to := Vector3(12.5, 0, 11.5)
	var path: PackedVector3Array = level.find_path(from, to)
	_check(path.size() > 2, "A route exists around the corridor cabinet")
	var total: float = 0.0
	var previous: Vector3 = from
	var safe: bool = not path.is_empty()
	for point in path:
		total += previous.distance_to(point)
		if not _segment_clear(previous, point, 0.32):
			safe = false
		previous = point
	_check(safe, "Every navigation segment clears real environment colliders")
	_check(total > from.distance_to(to) + 0.3, "The route detours instead of crossing the cabinet")
	_check(not path.is_empty() and path[path.size() - 1].distance_to(to) < 0.6, "Navigation reaches the requested destination")
	var route: PackedVector3Array = level.find_path(spawn, Vector3(4.5, 0, 1.5))
	var entire_route_safe: bool = route.size() > 3
	previous = spawn
	for point in route:
		entire_route_safe = entire_route_safe and _segment_clear(previous, point, 0.32)
		previous = point
	_check(entire_route_safe, "All three rooms are physically connected from spawn to exit")


func _test_movement() -> void:
	level.restart_game()
	_freeze_guards(true)
	for guard in level.guards:
		guard.global_position = Vector3(20, 0, 4)
	var origin := Vector3(2, 0, 25)
	var straight: Vector3 = await _move(origin, ["move_up"], 24)
	var diagonal: Vector3 = await _move(origin, ["move_up", "move_right"], 24)
	var running: Vector3 = await _move(origin, ["move_up", "sprint"], 24)
	var walk_distance: float = Vector2(straight.x, straight.z).length()
	var diagonal_distance: float = Vector2(diagonal.x, diagonal.z).length()
	var run_distance: float = Vector2(running.x, running.z).length()
	_check(straight.z < -0.5 and absf(straight.x) < 0.1, "W moves north using the real physics controller")
	_check(diagonal.x > 0.2 and diagonal.z < -0.2, "Diagonal input moves in both intended axes")
	_check(absf(diagonal_distance - walk_distance) < walk_distance * 0.12, "Diagonal walking is normalized")
	_check(run_distance > walk_distance * 1.25, "Holding Shift runs faster than walking")
	var stopped: Vector3 = level.player.global_position
	await _frames(12)
	_check(stopped.distance_to(level.player.global_position) < 0.12, "Releasing movement stops the player")
	await _move(Vector3(1, 0, 27), ["move_left", "sprint"], 60)
	_check(level.player.global_position.x >= 0.3, "Running into the outer wall cannot cross it")
	_check(level.player.global_position.y > -0.08, "The player stays on the floor")
	await _move(Vector3(5.7, 0, 26.5), ["move_right", "sprint"], 60)
	_check(level.player.global_position.x < 6.6, "The workstation partition has real player collision")


func _test_physical_keys() -> void:
	# Unlike action_press, parsed key events exercise the actual InputMap bindings.
	# This verifies Godot's mapping and physics response, not browser DOM delivery.
	var origin := Vector3(2, 0, 25)
	var walked: Vector3 = await _move_with_keys(origin, [KEY_W], 24)
	var stopped: Vector3 = level.player.global_position
	await _frames(8)
	_check(walked.z < -0.5 and absf(walked.x) < 0.1 and not Input.is_action_pressed("move_up") and stopped.distance_to(level.player.global_position) < 0.1, "Physical W key press maps to north movement and key release stops it")
	var ran: Vector3 = await _move_with_keys(origin, [KEY_SHIFT, KEY_W], 24)
	var walk_distance: float = Vector2(walked.x, walked.z).length()
	var run_distance: float = Vector2(ran.x, ran.z).length()
	_check(ran.z < -0.5 and run_distance > walk_distance * 1.25 and not Input.is_action_pressed("sprint") and not Input.is_action_pressed("move_up"), "Physical Shift plus W maps to faster running and both keys release")
	print("PHYSICAL_KEY_RESULT walk_distance=%.3f run_distance=%.3f" % [walk_distance, run_distance])


func _move_with_keys(origin: Vector3, keys: Array, frame_count: int) -> Vector3:
	level.player.global_position = origin
	level.player.velocity = Vector3.ZERO
	await _frames(4)
	var before: Vector3 = level.player.global_position
	for key in keys:
		_send_physical_key(key, true)
	await _frames(frame_count)
	var moved: Vector3 = level.player.global_position - before
	for key in keys:
		_send_physical_key(key, false)
	await _frames(2)
	return moved


func _send_physical_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _test_alert_and_pause() -> void:
	level.restart_game()
	_freeze_guards(true)
	var guard = level.guards[0]
	level.player.global_position = Vector3(5, 0, 24)
	level.player.velocity = Vector3.ZERO
	guard.global_position = Vector3(2, 0, 24)
	guard.facing = Vector3.RIGHT
	guard.state = "suspicious"
	guard.alert = 0.05
	guard.set_physics_process(true)
	await _frames(24)
	_check(guard.alert > 0.25 and guard.state == "suspicious", "Exposure raises the boss's suspicion over time")
	level.pause_game()
	var frozen_player: Vector3 = level.player.global_position
	var frozen_guard: Vector3 = guard.global_position
	var frozen_alert: float = guard.alert
	var frozen_elapsed: float = level.elapsed
	Input.action_press("move_up")
	await _frames(40)
	Input.action_release("move_up")
	_check(level.phase == "paused", "Pause opens the paused state")
	_check(frozen_player.distance_to(level.player.global_position) < 0.001 and frozen_guard.distance_to(guard.global_position) < 0.001, "Pause freezes both player and boss movement")
	_check(is_equal_approx(frozen_alert, guard.alert) and is_equal_approx(frozen_elapsed, level.elapsed), "Pause freezes alert and the level timer")
	level.resume_game()
	# Follow the state transition rather than assuming a particular alert tuning.
	for frame in range(120):
		if guard.state == "chase" or level.phase != "playing":
			break
		await _frames(1)
	await _frames(8)
	_check(guard.state == "chase" and guard.alert > 0.99, "Continued exposure starts a real chase")
	_check(guard.global_position.distance_to(frozen_guard) > 0.2, "A chasing boss actually moves toward the target")
	# Keep the actor far from the search area so sight is genuinely lost.
	# This position lies outside the exit and beyond the boss's sight distance.
	level.player.global_position = Vector3(2, 0, 3)
	level.player.velocity = Vector3.ZERO
	await _frames(620)
	_check(guard.state == "return" or guard.state == "patrol", "Losing the player ends search and returns to duty")
	_freeze_guards(true)


func _test_outcomes() -> void:
	level.restart_game()
	_freeze_guards(true)
	var exit_center: Vector2 = level.exit_rect.get_center()
	level.player.global_position = Vector3(exit_center.x, 0, exit_center.y)
	level._resolve_outcome()
	_check(level.phase == "won", "Reaching the exit wins the level")
	level.restart_game()
	_check(level.phase == "playing" and level.player.global_position.distance_to(spawn) < 0.12, "Retry after success restores the starting player")
	var reset: bool = is_zero_approx(level.elapsed)
	for i in range(level.guards.size()):
		var guard = level.guards[i]
		reset = reset and guard.global_position.distance_to(guard_spawns[i]) < 0.12 and is_zero_approx(guard.alert) and guard.state == "patrol"
	_check(reset, "Retry resets all bosses, alert and time")
	var guard = level.guards[0]
	guard.global_position = level.player.global_position + Vector3(0.5, 0, 0)
	guard.facing = Vector3.RIGHT
	level._resolve_outcome()
	_check(level.phase == "playing", "An unaware boss does not capture a player sneaking behind")
	guard.state = "chase"
	guard.alert = 1.0
	await _frames(2)
	level._resolve_outcome()
	_check(level.phase == "lost", "An unobstructed close encounter loses the level")
	level.restart_game()
	_freeze_guards(true)
	level.player.global_position = Vector3(2, 0, 24)
	guard.global_position = Vector3(2.65, 0, 24)
	guard.state = "chase"
	guard.alert = 1.0
	var thin_wall := _barrier(Vector3(2.32, 1, 24), Vector3(0.08, 2, 2), 3)
	await _frames(3)
	level._resolve_outcome()
	_check(level.phase == "playing", "A thin wall prevents a close-range capture through it")
	thin_wall.queue_free()
	await _frames(3)
	level.restart_game()
	_freeze_guards(true)
	level.player.global_position = Vector3(exit_center.x, 0, exit_center.y)
	guard.global_position = level.player.global_position + Vector3(0.5, 0, 0)
	guard.state = "chase"
	guard.alert = 1.0
	level._resolve_outcome()
	_check(level.phase == "lost", "Capture takes priority when exit and capture happen together")
	level._finish(true, "test repeated result")
	_check(level.phase == "lost", "The outcome is resolved only once")
	level.restart_game()
	_check(level.phase == "playing" and level.player.global_position.distance_to(spawn) < 0.12, "Retry after failure returns to a playable start")


func _move(origin: Vector3, actions: Array, frame_count: int) -> Vector3:
	_release_input()
	level.player.global_position = origin
	level.player.velocity = Vector3.ZERO
	await _frames(4)
	var before: Vector3 = level.player.global_position
	for action in actions:
		Input.action_press(action)
	await _frames(frame_count)
	var moved: Vector3 = level.player.global_position - before
	_release_input()
	return moved


func _segment_clear(from: Vector3, to: Vector3, radius: float) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * 0.6)
	query.motion = to - from
	query.collision_mask = 1
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var cast: PackedFloat32Array = space.cast_motion(query)
	return cast.is_empty() or cast[0] > 0.999


func _barrier(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	level.add_child(body)
	return body


func _freeze_guards(freeze: bool) -> void:
	for guard in level.guards:
		guard.set_physics_process(not freeze)
		guard.set_process(not freeze)


func _release_input() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(action)


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
