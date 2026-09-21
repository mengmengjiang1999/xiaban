extends Node
## Staged render measurement: one player and three visual copies, no NPC AI.
## Run WITHOUT --fixed-fps; screenshot/readback and grounding scans are outside timing.
## bash tools/godot.sh --rendering-method gl_compatibility --resolution 1152x720 --position -4000,-4000 res://tests/p2_performance.tscn -- --output=/absolute/path
## The Web P2 Benchmark export publishes window.xiabanP2Benchmark and remains open.

const Humanoid = preload("res://scripts/humanoid_actor.gd")
const ACTIONS := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "roll"]
const LIVE_ACTIONS := ["walk", "run", "crouch_walk", "roll"]
const WARMUP_SECONDS := 2.0
const SAMPLE_SECONDS := 5.0
const GROUND_SAMPLES := 17
const VISIBLE_FLOOR_Y := 0.017 # The office carpet top; physical floor is y = 0.
var _world: Node3D
var _actors: Array[Node3D] = []
var _output := ""
var _skin_surfaces: Array[Dictionary] = []
var _skin_rest_error := 0.0
var _rest_bind_error := 0.0
var _weight_sum_error := 0.0
var _web := OS.has_feature("web")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or (not _web and not _output.is_absolute_path()):
		_fail("Requires graphics and, on native builds, an absolute --output= path")
		return
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--fixed-fps"):
			_fail("--fixed-fps invalidates this real-time performance measurement")
			return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("This baseline requires the Compatibility renderer")
		return
	if not _web and DirAccess.make_dir_recursive_absolute(_output) != OK:
		_fail("Cannot create output directory")
		return
	if not _web:
		DisplayServer.window_set_size(Vector2i(1152, 720))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		_publish_web({"status": "running"})
	Engine.max_fps = 0
	_world = load("res://scenes/p2.tscn").instantiate()
	add_child(_world)
	_world.player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_world.player.reset_player(Vector3(2.0, 0.001, 23.0), PI)
	_actors.append(_world.player.actor)
	for index in range(1, 4):
		var actor := Humanoid.new()
		_world.add_child(actor)
		actor.position = Vector3(2.0 + index * 1.5, 0.001, 23.0)
		actor.rotation.y = PI
		_actors.append(actor)
	for index in _actors.size():
		_actors[index].set_paused(false)
		_actors[index].play_action(LIVE_ACTIONS[index])
		_actors[index].animation_player.seek(index * 0.17, true)
	_world.player.preview_action = "walk"
	_world.hud.show_phase("playing")
	_world.hud.update_game(0.0, 0.0, 23.0)
	# A fixed inspection camera keeps all four characters in the open office aisle.
	# The world remains in menu state so it never captures the mouse or runs AI.
	var camera: Camera3D = _world.rig.camera
	camera.global_position = Vector3(4.25, 3.0, 29.0)
	camera.look_at(Vector3(4.25, 0.85, 23.0))
	camera.fov = 48.0
	await _wait_wall_seconds(WARMUP_SECONDS)
	var start_bones := _pose_samples()
	var frame_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var static_memory: Array[float] = []
	var video_memory: Array[float] = []
	var start_usec := Time.get_ticks_usec()
	var previous_usec := start_usec
	var now_usec := start_usec
	while float(now_usec - start_usec) / 1000000.0 < SAMPLE_SECONDS:
		await get_tree().process_frame
		now_usec = Time.get_ticks_usec()
		frame_ms.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		static_memory.append(Performance.get_monitor(Performance.MEMORY_STATIC))
		video_memory.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var duration := float(now_usec - start_usec) / 1000000.0
	var end_bones := _pose_samples()
	var elapsed_animation := []
	for index in _actors.size():
		elapsed_animation.append({"action": LIVE_ACTIONS[index], "playing": _actors[index].animation_player.is_playing(),
			"pose_changed": not start_bones[index].is_equal_approx(end_bones[index]),
			"bones": _actors[index].skeleton.get_bone_count(), "meshes": _actors[index].meshes.size()})
	# Finish the timing window before any GPU readback or CPU skinning inspection.
	var viewport_size := Vector2i(get_viewport().get_visible_rect().size)
	if viewport_size != Vector2i(1152, 720):
		_fail("The actual rendered viewport must be 1152 x 720")
		return
	if not _web:
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		if image.is_empty() or image.save_png(_output.path_join("four-actors.png")) != OK:
			_fail("Cannot save the four-actor screenshot")
			return
	var ground_report := await _scan_grounding()
	var report := {
		"status": "complete",
		"purpose": "Staged render baseline: one player plus three visual copies, no leader AI; not a playthrough",
		"scope": "One local run on this device and runtime only; do not generalize to other browsers or hardware",
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"device": {"os": OS.get_name(), "processor": OS.get_processor_name(),
			"gpu": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
			"godot": Engine.get_version_info().string, "rendering_method": RenderingServer.get_current_rendering_method()},
		"configuration": {"resolution": [viewport_size.x, viewport_size.y], "warmup_seconds": WARMUP_SECONDS,
			"runtime": "web" if _web else "native", "sample_seconds": SAMPLE_SECONDS,
			"fixed_fps": false, "engine_max_fps": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(),
			"window_position": [DisplayServer.window_get_position().x, DisplayServer.window_get_position().y],
			"phase": _world.phase, "player_physics_enabled": _world.player.is_physics_processing(),
			"actors": 4, "leader_ai": false, "screenshot": "four-actors.png"},
		"measurement": {"seconds": duration, "frames": frame_ms.size(), "average_fps": frame_ms.size() / duration,
			"frame_time_ms": _statistics(frame_ms), "draw_calls": _statistics(draw_calls),
			"engine_static_memory_bytes": _statistics(static_memory), "renderer_video_memory_bytes": _statistics(video_memory),
			"memory_note": "Godot engine/renderer allocation monitors; not process RSS or total system memory. An all-zero monitor in a release/Web runtime means unavailable, not zero allocation.",
			"animation_evidence": elapsed_animation},
		"grounding": ground_report,
	}
	if _web:
		for index in _actors.size():
			_actors[index].animation_player.stop()
			_actors[index].play_action(LIVE_ACTIONS[index])
			_actors[index].animation_player.seek(index * 0.17, true)
		_publish_web(report)
	else:
		var output := FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
		if output == null:
			_fail("Cannot write report.json")
			return
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("P2_PERFORMANCE fps=%.2f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f frames=%d seconds=%.3f" % [
		frame_ms.size() / duration, report.measurement.frame_time_ms.p50, report.measurement.frame_time_ms.p95,
		report.measurement.frame_time_ms.max, frame_ms.size(), duration])
	print("P2_GROUNDING passed=%s rest_error_m=%.7f report=%s" % [ground_report.passed, _skin_rest_error, _output.path_join("report.json")])
	if not _web:
		_world.queue_free()
		await get_tree().process_frame
		get_tree().quit(0 if ground_report.passed else 1)


func _wait_wall_seconds(seconds: float) -> void:
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		await get_tree().process_frame


func _pose_samples() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for actor in _actors:
		var skeleton: Skeleton3D = actor.skeleton
		result.append(skeleton.get_bone_global_pose(skeleton.find_bone("hand_l")))
	return result


func _statistics(values: Array[float]) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var sum := 0.0
	for value in ordered:
		sum += value
	return {"min": ordered[0], "p50": ordered[ceili(ordered.size() * 0.50) - 1],
		"p95": ordered[ceili(ordered.size() * 0.95) - 1], "max": ordered[-1], "mean": sum / ordered.size()}


func _scan_grounding() -> Dictionary:
	var actor: Node3D = _actors[0]
	var skeleton: Skeleton3D = actor.skeleton
	for item in _actors:
		item.animation_player.speed_scale = 0.0
	_cache_skin_surfaces(actor)
	var clips: Dictionary = {}
	var passed := _skin_rest_error < 0.002 and _rest_bind_error < 0.002 and _weight_sum_error < 0.001 and not _skin_surfaces.is_empty()
	for action in ACTIONS:
		var clip_name := ""
		for candidate in actor.animation_player.get_animation_list():
			if String(candidate).get_file() == action:
				clip_name = candidate
		var clip: Animation = actor.animation_player.get_animation(clip_name)
		var heights: Array[float] = []
		var samples: Array[Dictionary] = []
		for index in GROUND_SAMPLES:
			var time := minf(clip.length - 0.0001, clip.length * float(index) / float(GROUND_SAMPLES - 1))
			actor.animation_player.play(clip_name, 0.0)
			actor.animation_player.seek(time, true)
			actor.animation_player.advance(0.0)
			skeleton.force_update_all_bone_transforms()
			var marker_heights: Dictionary = {}
			for bone_name in ["foot_l", "foot_r", "ball_l", "ball_r", "hand_l", "hand_r", "head", "pelvis"]:
				var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin
				passed = passed and point.is_finite()
				marker_heights[bone_name] = point.y
			var minimum := _minimum_skinned_y(skeleton)
			heights.append(minimum)
			samples.append({"time_seconds": time, "minimum_skinned_vertex_y": minimum,
				"clearance_above_carpet_m": minimum - VISIBLE_FLOOR_Y, "bone_world_y": marker_heights})
			# Keep the browser responsive during the untimed CPU skinning scan.
			await get_tree().process_frame
		var statistics := _statistics(heights)
		# Ankle bones sit inside shoes; they are diagnostic markers, not sole height.
		# Sprint is allowed an airborne phase; roll may contact with hands/head/hips.
		var grounded: bool = statistics.min >= VISIBLE_FLOOR_Y - 0.03 and (action == "run" or statistics.max <= VISIBLE_FLOOR_Y + 0.06)
		passed = passed and grounded
		clips[action] = {"passed": grounded, "minimum_vertex_y": statistics, "samples": samples}
		await get_tree().process_frame
	return {"passed": passed, "method": "CPU linear skinning of actual imported mesh vertices using Skin binds and evaluated Skeleton3D poses; outside performance window",
		"rest_reconstruction_max_error_m": _skin_rest_error, "rest_bind_consistency_max_error": _rest_bind_error,
		"skin_weight_sum_max_error": _weight_sum_error,
		"rest_calibration": "The GLB inverse binds include the authored GodotForward rotation. Compare with the common rest-bone times inverse-bind transform, not an unskinned mesh transform.",
		"physical_floor_y": 0.0, "visible_carpet_y": VISIBLE_FLOOR_Y,
		"samples_per_clip": GROUND_SAMPLES, "penetration_tolerance_m": 0.03, "planted_gap_tolerance_m": 0.06,
		"note": "Bone origins are not shoe soles. Roll can contact using hands/head/hips; sprint may be airborne. Sampled poses do not prove every interpolated frame or cloth self-intersection.",
		"clips": clips}


func _cache_skin_surfaces(actor: Node3D) -> void:
	var skeleton: Skeleton3D = actor.skeleton
	for node in actor.meshes:
		var mesh: MeshInstance3D = node
		if mesh.skin == null:
			continue
		var bind_bones: Array[int] = []
		var bind_poses: Array[Transform3D] = []
		for index in mesh.skin.get_bind_count():
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(index))
			if bone < 0:
				bone = mesh.skin.get_bind_bone(index)
			bind_bones.append(bone)
			bind_poses.append(mesh.skin.get_bind_pose(index))
		var rest_mesh_transform := skeleton.get_bone_global_rest(bind_bones[0]) * bind_poses[0]
		for index in bind_bones.size():
			var candidate := skeleton.get_bone_global_rest(bind_bones[index]) * bind_poses[index]
			_rest_bind_error = maxf(_rest_bind_error, candidate.origin.distance_to(rest_mesh_transform.origin))
			for axis in 3:
				_rest_bind_error = maxf(_rest_bind_error, candidate.basis[axis].distance_to(rest_mesh_transform.basis[axis]))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / vertices.size()
			_skin_surfaces.append({"vertices": vertices, "bones": bones, "weights": weights,
				"influences": influences, "bind_bones": bind_bones, "bind_poses": bind_poses})
			# Inverse binds contain the authored root-axis conversion. An unskinned
			# mesh transform is not the reference for this GLB's bound rest geometry.
			for vertex_index in range(0, vertices.size(), maxi(1, vertices.size() / 32)):
				var reconstructed := Vector3.ZERO
				var weight_sum := 0.0
				for influence in influences:
					var weight_index: int = vertex_index * influences + influence
					var bind: int = bones[weight_index]
					reconstructed += (skeleton.get_bone_global_rest(bind_bones[bind]) * bind_poses[bind] * vertices[vertex_index]) * weights[weight_index]
					weight_sum += weights[weight_index]
				_weight_sum_error = maxf(_weight_sum_error, absf(weight_sum - 1.0))
				_skin_rest_error = maxf(_skin_rest_error, (skeleton.global_transform * reconstructed).distance_to(skeleton.global_transform * rest_mesh_transform * vertices[vertex_index]))


func _minimum_skinned_y(skeleton: Skeleton3D) -> float:
	var minimum := INF
	for surface in _skin_surfaces:
		var palette: Array[Transform3D] = []
		for index in surface.bind_bones.size():
			palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(surface.bind_bones[index]) * surface.bind_poses[index])
		var vertices: PackedVector3Array = surface.vertices
		var bones: PackedInt32Array = surface.bones
		var weights: PackedFloat32Array = surface.weights
		var influences: int = surface.influences
		for vertex_index in vertices.size():
			var position := Vector3.ZERO
			for influence in influences:
				var weight_index := vertex_index * influences + influence
				var weight := weights[weight_index]
				if weight > 0.00001:
					position += (palette[bones[weight_index]] * vertices[vertex_index]) * weight
			minimum = minf(minimum, position.y)
	return minimum


func _fail(message: String) -> void:
	push_error("P2 performance: " + message)
	if _web:
		_publish_web({"status": "failed", "error": message})
	else:
		get_tree().quit(2)


func _publish_web(report: Dictionary) -> void:
	JavaScriptBridge.eval("window.xiabanP2Benchmark = " + JSON.stringify(report) + ";", true)
