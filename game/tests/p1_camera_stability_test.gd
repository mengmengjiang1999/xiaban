extends "res://tests/p1_playthrough.gd"
## Temporal camera regression: real office route, near-wall micro-orbit and rest.
## bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p1_camera_stability_test.gd
## Optional --camera-trace=/absolute/path.jsonl records every rendered route frame.

class FrameProbe extends Node:
	var sample: Callable
	func _process(delta: float) -> void:
		sample.call(delta)

var _frame_probe: FrameProbe
var _trace: FileAccess
var _has_previous_camera := false
var _previous_camera := Vector3.ZERO
var _route_camera_step := 0.0
var _route_render_frames := 0
var _route_render_obstructions := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--camera-trace="):
			var output := argument.trim_prefix("--camera-trace=")
			if not output.is_absolute_path():
				push_error("--camera-trace requires an absolute path")
				quit(2)
				return
			_trace = FileAccess.open(output, FileAccess.WRITE)
			if _trace == null:
				push_error("Cannot write camera trace: %s" % output)
				quit(2)
				return
	super._initialize()


func _frames(count: int) -> void:
	if _frame_probe == null:
		_frame_probe = FrameProbe.new()
		_frame_probe.sample = _sample_render_frame
		# Inspect the final camera after the world's process update, including frames
		# between physics ticks when testing at a different render frame rate.
		_frame_probe.process_priority = 100
		root.add_child(_frame_probe)
	await super._frames(count)


func _sample_render_frame(delta: float) -> void:
	if not _measuring or world == null or world.phase != "playing":
		_has_previous_camera = false
		return
	var camera_position: Vector3 = world.rig.camera.global_position
	if _has_previous_camera:
		_route_camera_step = maxf(_route_camera_step, camera_position.distance_to(_previous_camera))
	_previous_camera = camera_position
	_has_previous_camera = true
	_route_render_frames += 1
	var player_position: Vector3 = world.player.global_position
	var anchor: Vector3 = player_position + Vector3.UP * world.rig.anchor_height
	if not _camera_clear(anchor):
		_route_render_obstructions += 1
	if _trace != null:
		_trace.store_line(JSON.stringify({
			"frame": _route_render_frames,
			"delta": delta,
			"elapsed": world.elapsed,
			"player": [player_position.x, player_position.y, player_position.z],
			"camera": [camera_position.x, camera_position.y, camera_position.z],
			"anchor_distance": anchor.distance_to(camera_position),
			"camera_yaw": world.rig.yaw,
			"alpha": world.player.camera_alpha,
		}))


func _finish(won: bool) -> void:
	_measuring = false
	_release_keys()
	_check(_route_camera_step < 0.3,
		"Complete 60 FPS route keeps every rendered camera step below 30 cm")
	_check(_route_render_obstructions == 0,
		"Every rendered route frame keeps the camera volume and sightline clear")
	print("P1_CAMERA_ROUTE frames=%d max_step=%.6fm obstructions=%d" % [
		_route_render_frames, _route_camera_step, _route_render_obstructions])
	world.start_game()
	await _test_stationary_camera()
	await _test_micro_orbit()
	await _test_overlapping_prediction_origin()
	print("P1_CAMERA_STABILITY_RESULT passed=%d failed=%d" % [passed, failed])
	_frame_probe.queue_free()
	if _trace != null:
		_trace.close()
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if won and failed == 0 else 1)


func _test_stationary_camera() -> void:
	var maximum_camera_drift := 0.0
	var maximum_actor_drift := 0.0
	var maximum_alpha_drift := 0.0
	# These straddle the previously discontinuous wall-parallel boom directions.
	for probe in [
		Vector3(13.41778, 13.32609, -1.558208),
		Vector3(15.21708, 13.28386, -1.544),
		Vector3(18.39637, 13.25192, -1.55588),
		Vector3(18.39637, 13.25192, -1.54390),
	]:
		world.player.reset_player(Vector3(probe.x, 0.000837, probe.y), probe.z)
		world.rig.reset_camera()
		await _frames(180)
		var camera_position: Vector3 = world.rig.camera.global_position
		var player_position: Vector3 = world.player.global_position
		var alpha: float = world.player.camera_alpha
		for frame in range(300):
			await _frames(1)
			maximum_camera_drift = maxf(maximum_camera_drift, camera_position.distance_to(world.rig.camera.global_position))
			maximum_actor_drift = maxf(maximum_actor_drift, player_position.distance_to(world.player.global_position))
			maximum_alpha_drift = maxf(maximum_alpha_drift, absf(alpha - world.player.camera_alpha))
	_check(maximum_camera_drift < 0.0001 and maximum_actor_drift < 0.0001 and maximum_alpha_drift < 0.0001,
		"Resting near walls keeps camera, actor and transparency stable for 300 frames")
	print("P1_CAMERA_REST camera_drift=%.8fm actor_drift=%.8fm alpha_drift=%.8f" % [
		maximum_camera_drift, maximum_actor_drift, maximum_alpha_drift])


func _test_micro_orbit() -> void:
	world.player.reset_player(Vector3(18.39637, 0.000837, 13.25192), -1.556)
	world.rig.reset_camera()
	await _frames(10)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	Input.parse_input_event(right)
	Input.flush_buffered_events()
	var previous: Vector3 = world.rig.camera.global_position
	var previous_alpha: float = world.player.camera_alpha
	var previous_mode: int = world.player._visual_materials[0].transparency
	var max_step := 0.0
	var max_alpha_step := 0.0
	var max_input_error := 0.0
	var mode_switches := 0
	var obstructions := 0
	for frame in range(900):
		var angle := -1.556 + sin(float(frame) * 0.02) * 0.008
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(angle_difference(angle, world.rig.yaw) / world.rig.mouse_sensitivity, 0.0)
		# Input.parse_input_event uses window pixels, then the project stretch mode
		# scales into viewport pixels (the headless window can be only 64 px wide).
		motion.relative *= float(root.size.x) / root.get_visible_rect().size.x
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await _frames(1)
		var current: Vector3 = world.rig.camera.global_position
		max_step = maxf(max_step, previous.distance_to(current))
		max_alpha_step = maxf(max_alpha_step, absf(previous_alpha - world.player.camera_alpha))
		max_input_error = maxf(max_input_error, absf(angle_difference(angle, world.rig.yaw)))
		var mode: int = world.player._visual_materials[0].transparency
		if mode != previous_mode:
			mode_switches += 1
		previous = current
		previous_alpha = world.player.camera_alpha
		previous_mode = mode
		var anchor: Vector3 = world.player.global_position + Vector3.UP * world.rig.anchor_height
		if not _camera_clear(anchor):
			obstructions += 1
	right.pressed = false
	Input.parse_input_event(right)
	Input.flush_buffered_events()
	_check(max_step < 0.03 and max_alpha_step < 0.02 and mode_switches == 0 and max_input_error < 0.0001,
		"Tiny right-drag observations near a parallel wall cannot cause camera or material flashes")
	_check(obstructions == 0, "Micro-orbit keeps the camera volume and sightline clear")
	print("P1_CAMERA_MICRO_ORBIT max_step=%.6fm max_alpha_step=%.6f material_switches=%d obstructions=%d" % [
		max_step, max_alpha_step, mode_switches, obstructions])


func _test_overlapping_prediction_origin() -> void:
	var barrier := StaticBody3D.new()
	barrier.collision_layer = 1
	barrier.position = Vector3(200, 1.3, 200)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	collider.shape = box
	barrier.add_child(collider)
	world.add_child(barrier)
	await _frames(2)
	var motion: Vector3 = world.rig._safe_motion(barrier.global_position, Vector3(0, 0, 4.8))
	_check(motion.is_zero_approx(), "A predicted anchor already inside an obstacle returns no safe boom distance")
	barrier.queue_free()
	await _frames(2)
