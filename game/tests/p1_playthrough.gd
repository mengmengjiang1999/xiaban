extends SceneTree
## Full P1 office acceptance using physical W/A/D and Escape events.
## No teleportation, collision changes, scene-logic disabling or direct victory calls.
## Headless: bash tools/godot.sh --headless --fixed-fps 60 --log-file /tmp/xiaban-p1-route.log --script res://tests/p1_playthrough.gd
## Visual: bash tools/godot.sh --max-fps 60 --script res://tests/p1_playthrough.gd -- --screenshots=/absolute/output/path --wait-for-start
## --wait-for-start waits for the real Start button; focus pauses remain active.

const ROUTE: Array[Vector2] = [
	Vector2(5.5, 21.5), Vector2(5.5, 17.4), Vector2(8.8, 17.4),
	Vector2(8.8, 13.25), Vector2(18.5, 13.25), Vector2(18.5, 8.4),
	Vector2(11.5, 8.4), Vector2(11.5, 6.0), Vector2(4.5, 6.0),
	Vector2(4.5, 3.0), Vector2(4.5, 1.5)
]
const LABELS := [
	"02_workstations", "03_first_door", "04_office_turn", "05_corridor_turn",
	"06_second_door_approach", "07_upper_room", "08_cabinet_turn",
	"09_exit_corridor", "10_exit_approach", "11_exit_door", "12_completed"
]
const FRAME_BUDGET := 7200

var world: Node3D
var passed := 0
var failed := 0
var simulated_frames := 0
var distance := 0.0
var max_route_deviation := 0.0
var min_camera_distance := INF
var camera_obstructions := 0
var screenshot_count := 0
var screenshot_dir := ""
var wait_for_start := false
var graphical := false
var _held_keys: Dictionary = {}
var _previous_position: Vector3
var _segment_start := Vector2.ZERO
var _segment_end := Vector2.ZERO
var _measuring := false
var _external_pause_reported := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			screenshot_dir = argument.trim_prefix("--screenshots=")
		elif argument == "--wait-for-start":
			wait_for_start = true
	if not screenshot_dir.is_empty():
		if not screenshot_dir.is_absolute_path():
			push_error("--screenshots requires an absolute directory path")
			quit(2)
			return
		if graphical:
			var error := DirAccess.make_dir_recursive_absolute(screenshot_dir)
			if error != OK:
				push_error("Cannot create screenshot directory: %s" % error_string(error))
				quit(2)
				return
		else:
			print("P1_SCREENSHOTS skipped: headless display has no rendered viewport")
	world = load("res://scenes/p1.tscn").instantiate()
	root.add_child(world)
	await _frames(5)
	_check(world.phase == "menu", "Playable scene starts at the menu")
	await _capture("00_menu")
	if wait_for_start and graphical:
		print("P1_WAITING_START: focus the game window and click Start")
		if not await _wait_until_playing(120000):
			await _finish(false)
			return
	else:
		world.start_game()
		await _frames(3)
		if graphical and world.phase != "playing":
			if not await _wait_until_playing(120000):
				await _finish(false)
				return
	_check(world.phase == "playing", "Start enters the live office")
	_check(_flat(world.player.global_position).distance_to(Vector2(5.5, 27.0)) < 0.05,
		"The route begins at the genuine player spawn")
	await _capture("01_spawn")
	_previous_position = world.player.global_position
	_segment_start = _flat(_previous_position)
	_measuring = true
	var route_ok := true
	for index in ROUTE.size():
		_segment_end = ROUTE[index]
		var reached := await _walk_to(_segment_end)
		print("P1_ROUTE_SEGMENT index=%02d target=%s reached=%s phase=%s time=%.2f distance=%.2f position=%s max_deviation=%.3f" % [
			index + 1, _segment_end, reached, world.phase, world.elapsed,
			distance, world.player.global_position, max_route_deviation])
		if world.phase == "won":
			await _capture("12_completed")
			break
		if not reached:
			route_ok = false
			break
		_release_keys()
		await _frames(24)
		await _capture(LABELS[index])
		if index == 2:
			await _test_midroute_pause()
		_segment_start = _segment_end
	_release_keys()
	await _frames(4)
	_check(route_ok and world.phase == "won", "Physical movement traverses every room and naturally reaches the exit")
	_check(distance > 35.0, "Completion includes substantial real travel through the office")
	_check(max_route_deviation < 0.45, "The physical route stays within 45 cm of its planned corridor segments")
	_check(camera_obstructions == 0, "The camera sphere and character sightline remain clear throughout the real route")
	await _finish(world.phase == "won")


func _walk_to(destination: Vector2) -> bool:
	var stuck_frames := 0
	while simulated_frames < FRAME_BUDGET:
		if world.phase == "won":
			return true
		if world.phase != "playing":
			_release_keys()
			if not graphical or not await _wait_until_playing(120000):
				return false
		var current := _flat(world.player.global_position)
		var difference := destination - current
		if difference.length() < 0.105:
			_release_keys()
			return true
		var wanted_heading := atan2(-difference.x, -difference.y)
		var error: float = angle_difference(world.player.rotation.y, wanted_heading)
		# Turn in place before each corner, then steer gently while walking.
		_set_key(KEY_A, error > 0.022)
		_set_key(KEY_D, error < -0.022)
		var moving := absf(error) < 0.12
		_set_key(KEY_W, moving)
		Input.flush_buffered_events()
		await _tick()
		if moving and current.distance_to(_flat(world.player.global_position)) < 0.001:
			stuck_frames += 1
		else:
			stuck_frames = 0
		if stuck_frames > 150:
			push_error("P1_ROUTE_STUCK at=%s target=%s" % [world.player.global_position, destination])
			return false
	push_error("P1 route exceeded its physical frame budget")
	return false


func _test_midroute_pause() -> void:
	_release_keys()
	_set_key(KEY_ESCAPE, true)
	Input.flush_buffered_events()
	_set_key(KEY_ESCAPE, false)
	Input.flush_buffered_events()
	await _frames(2)
	var frozen_position: Vector3 = world.player.global_position
	var frozen_time: float = world.elapsed
	var frozen_heading: float = world.player.rotation.y
	await _capture("04a_paused")
	await _frames(30)
	_check(world.phase == "paused"
		and world.player.global_position.distance_to(frozen_position) < 0.001
		and absf(world.player.rotation.y - frozen_heading) < 0.001
		and is_equal_approx(world.elapsed, frozen_time),
		"Midroute Escape pauses position, facing and elapsed time")
	# This is the same public transition used by the real Continue button.
	world.resume_game()
	await _frames(3)
	_check(world.phase == "playing"
		and world.player.global_position.distance_to(frozen_position) < 0.02,
		"Continue resumes at the same point without replaying a movement key")
	await _capture("04b_resumed")


func _wait_until_playing(timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	if not _external_pause_reported:
		print("P1_WAITING_FOCUS: use the real game window Start/Continue button; focus protection is unchanged")
		_external_pause_reported = true
	while world.phase != "playing" and Time.get_ticks_msec() < deadline:
		await process_frame
	_external_pause_reported = false
	if world.phase != "playing":
		_check(false, "Game window did not enter playing before the interactive timeout")
		return false
	return true


func _tick() -> void:
	await physics_frame
	await process_frame
	simulated_frames += 1
	if not _measuring:
		return
	var current: Vector3 = world.player.global_position
	distance += _flat(current).distance_to(_flat(_previous_position))
	_previous_position = current
	var route_point: Vector2 = Geometry2D.get_closest_point_to_segment(_flat(current), _segment_start, _segment_end)
	max_route_deviation = maxf(max_route_deviation, _flat(current).distance_to(route_point))
	var anchor: Vector3 = current + Vector3.UP * world.rig.anchor_height
	min_camera_distance = minf(min_camera_distance, anchor.distance_to(world.rig.camera.global_position))
	if not _camera_clear(anchor):
		camera_obstructions += 1
		if camera_obstructions <= 3:
			print("P1_ROUTE_CAMERA_OBSTRUCTION player=%s camera=%s" % [current, world.rig.camera.global_position])


func _camera_clear(anchor: Vector3) -> bool:
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
	var ray := PhysicsRayQueryParameters3D.create(anchor, camera_position, 3)
	return space.intersect_ray(ray).is_empty()


func _capture(label: String) -> void:
	if screenshot_dir.is_empty() or not graphical:
		return
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var output := screenshot_dir.path_join(label + ".png")
	var error := picture.save_png(output)
	if error == OK:
		screenshot_count += 1
		print("P1_SCREENSHOT %s" % output)
	else:
		_check(false, "Screenshot write failed: %s (%s)" % [output, error_string(error)])


func _set_key(key: Key, pressed: bool) -> void:
	if bool(_held_keys.get(key, false)) == pressed:
		return
	_held_keys[key] = pressed
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_keys() -> void:
	for key in [KEY_W, KEY_A, KEY_D, KEY_ESCAPE]:
		_set_key(key, false)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for unused in range(count):
		await physics_frame
		await process_frame


func _flat(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)


func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)


func _finish(won: bool) -> void:
	_release_keys()
	print("P1_PLAYTHROUGH_RESULT passed=%d failed=%d won=%s distance=%.3fm time=%.3fs frames=%d max_route_deviation=%.3fm min_camera_distance=%.3fm camera_obstructions=%d screenshots=%d" % [
		passed, failed, won, distance, world.elapsed, simulated_frames,
		max_route_deviation, min_camera_distance, camera_obstructions, screenshot_count])
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if won and failed == 0 else 1)
