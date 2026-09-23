extends SceneTree
## Real rig/physics temporal tests. Append -- --capture-dir=/absolute/path
## to save consecutive native rendered frames; do not capture in headless mode.
var world: Node3D
var passed := 0
var failed := 0
var report := {"animations": [], "captures": []}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = load("res://scenes/release.tscn").instantiate()
	root.add_child(world)
	await _frames(6)
	world.start_game()
	await _frames(4)
	world.player.set_physics_process(false)
	for guard in world.guards:
		guard.set_physics_process(false)
		guard._enter_state("watching")
		guard._update_visual()
	_test_animation_envelopes()
	await _test_transitions_and_actual_sight()
	await _test_obstacle_changes()
	await _test_refresh_clock()
	var capture_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty():
		if DisplayServer.get_name() == "headless":
			_check(false, "Frame capture requires a rendering display")
		else:
			await _capture_sequences(capture_dir)
	report["passed"] = passed
	report["failed"] = failed
	var report_path := ProjectSettings.globalize_path("res://../.logs/release-guard-cue-after.json")
	if not capture_dir.is_empty(): report_path = capture_dir.path_join("report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  "))
	print("RELEASE_GUARD_CUE_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	world.show_menu()
	for source in world.find_children("*", "AudioStreamPlayer", true, false): source.stop()
	for source in world.find_children("*", "AudioStreamPlayer3D", true, false): source.stop()
	await _frames(3)
	OS.delay_msec(150)
	world.queue_free()
	await _frames(4)
	OS.delay_msec(150)
	quit(1 if failed else 0)

func _set_action(action: String) -> void:
	world.player.stance = "crouched" if action.begins_with("crouch") or action == "roll" else "standing"
	world.player.action_state = action
	world.player._stance_transition = 0.0
	world.player.actor.play_action(action, 1.0, true, action != "roll", 0.0)
	world.player.actor.animation_player.pause()

func _test_animation_envelopes() -> void:
	for guard in world.guards:
		for action in ["idle", "walk", "run", "crouch_idle", "crouch_walk", "roll"]:
			_set_action(action)
			var unique := {}
			var changes := 0
			var last := 0
			var minimum := INF
			var maximum := -INF
			var stable_instance := true
			var previous_instance := 0
			var omitted_cells := 0
			for sample in 121:
				world.player.actor.animation_player.seek(world.player.actor.action_length(action) * sample / 120.0, true)
				for point in world.player.get_detection_points():
					minimum = minf(minimum, point.y - world.player.global_position.y)
					maximum = maxf(maximum, point.y - world.player.global_position.y)
				guard._rebuild_fan()
				omitted_cells += _omitted_animated_cells(guard)
				var signature := hash(guard._fan_vertices)
				var instance: int = guard._fan.mesh.get_instance_id()
				unique[signature] = true
				if sample > 0:
					if signature != last: changes += 1
					stable_instance = stable_instance and previous_instance == instance
				previous_instance = instance
				last = signature
			var profile: String = guard.get_status().cue_height_profile
			var heights: Array = guard.CUE_HEIGHTS[profile]
			var metrics := {"guard": guard.guard_id, "action": action, "profile": profile,
				"unique_meshes": unique.size(), "changes": changes, "stable_mesh_instance": stable_instance,
				"bone_min": minimum, "bone_max": maximum, "profile_min": heights.min(), "profile_max": heights.max(),
				"omitted_animated_cells": omitted_cells}
			report.animations.append(metrics)
			print("CUE_ANIMATION ", JSON.stringify(metrics))
			_check(changes == 0 and unique.size() == 1 and stable_instance,
				"%s %s keeps one mesh across 121 animation phases" % [guard.guard_id, action])
			_check(minimum >= float(heights.min()) and maximum <= float(heights.max()),
				"%s %s head/chest fit the fixed cue envelope" % [guard.guard_id, action])
			_check(omitted_cells == 0, "%s %s omits no cells shown by the previous animated-height guide" % [guard.guard_id, action])

func _omitted_animated_cells(guard: Node3D) -> int:
	# Independent reproduction of the old two-ray-per-cell guide. This checks
	# current level blockers as well as envelope bounds, including thin desks.
	var current := {}
	for vertex in range(0, guard._fan_vertices.size(), 6):
		current[hash(guard._fan_vertices[vertex])] = true
	var eye: Vector3 = guard.eye_position()
	var heights: Array[float] = []
	for point in world.player.get_detection_points(): heights.append(point.y - world.player.global_position.y)
	var missing := 0
	var half_angle := deg_to_rad(float(guard.vision_fov_degrees) * 0.5)
	for angle_index in 28:
		var a0 := lerpf(-half_angle, half_angle, float(angle_index) / 28)
		var a1 := lerpf(-half_angle, half_angle, float(angle_index + 1) / 28)
		for ring in 15:
			var r0 := maxf(0.40, float(guard.vision_range) * ring / 15)
			var r1: float = guard.vision_range * (ring + 1) / 15
			if r1 <= r0: continue
			var p0 := Vector3.FORWARD.rotated(Vector3.UP, a0) * r0 + Vector3.UP * 0.026
			if current.has(hash(p0)): continue
			var center := Vector3.FORWARD.rotated(Vector3.UP, (a0 + a1) * 0.5) * ((r0 + r1) * 0.5)
			var point := guard.to_global(center)
			for height in heights:
				var target := Vector3(point.x, guard.global_position.y + height, point.z)
				if guard._point_in_view(target, eye) and guard._ray_clear(eye, target):
					missing += 1
					break
	return missing

func _test_transitions_and_actual_sight() -> void:
	for index in world.guards.size():
		var guard = world.guards[index]
		world.player.global_position = world.level.exposure_points[index]
		await _frames(2)
		_set_action("idle")
		world.player.actor.animation_player.seek(0.4, true)
		guard._rebuild_fan()
		var standing_vertices: PackedVector3Array = guard._fan_vertices.duplicate()
		_check(guard.can_see_player(), "%s detects real standing bones over cover" % guard.guard_id)
		_set_action("crouch_idle")
		world.player.actor.animation_player.seek(0.4, true)
		guard._rebuild_fan()
		_check(not guard.can_see_player() and guard._fan_vertices != standing_vertices,
			"%s loses exact crouched bones behind cover and updates the pose guide" % guard.guard_id)
		world.player._stance_transition = 0.08
		guard._rebuild_fan()
		_check(guard.get_status().cue_height_profile == "transition"
			and float(guard.CUE_HEIGHTS.transition.max()) >= float(guard.CUE_HEIGHTS.standing.max())
			and float(guard.CUE_HEIGHTS.transition.min()) <= float(guard.CUE_HEIGHTS.crouched.min()),
			"%s uses both height envelopes during crouch/stand blending" % guard.guard_id)
		world.player._stance_transition = 0.0
		world.player.action_state = "recovery"
		guard._rebuild_fan()
		_check(guard.get_status().cue_height_profile == "roll", "%s keeps the roll envelope through recovery" % guard.guard_id)

func _test_obstacle_changes() -> void:
	var guard = world.guards[0]
	_set_action("idle")
	guard._rebuild_fan()
	var original: PackedVector3Array = guard._fan_vertices.duplicate()
	var revision: int = guard.get_status().fan_revision
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 16
	blocker.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 3.0, 5.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	blocker.add_child(collision)
	world.add_child(blocker)
	blocker.global_position = guard.global_position - guard.global_basis.z * 0.8 + Vector3.UP * 1.5
	await _frames(3)
	guard._rebuild_fan()
	_check(guard._fan_vertices != original and guard.get_status().fan_revision == revision + 1,
		"A new physical sight blocker changes the guide despite mesh reuse")
	blocker.queue_free()
	await _frames(3)
	guard._rebuild_fan()
	_check(guard._fan_vertices == original and guard.get_status().fan_revision == revision + 2,
		"Removing a blocker restores the original guide")

func _test_refresh_clock() -> void:
	var guard = world.guards[0]
	world.player.global_position = world.level.observation_points[0]
	_set_action("idle")
	world.player.actor.animation_player.play()
	guard.watch_duration = 100.0
	guard.confirm_duration = 100.0
	guard._enter_state("watching")
	guard._update_visual()
	guard._rebuild_fan()
	var before: Dictionary = guard.get_status()
	guard.set_physics_process(true)
	await _frames(180)
	var after: Dictionary = guard.get_status()
	guard.set_physics_process(false)
	world.player.actor.animation_player.pause()
	_check(after.fan_revision == before.fan_revision and after.fan_refresh_count > before.fan_refresh_count + 12,
		"Three seconds of animated physics refresh without replacing the guide mesh")
	_check(after.progress == 0.0 and world.phase == "playing", "Protected observation stays undetected during temporal sampling")
	report["clock"] = {"before": before, "after": after}

func _capture_sequences(capture_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	world.set_process(false)
	world.player.global_position = world.level.exposure_points[0]
	world.player.rotation.y = -PI / 2.0
	world.rig.reset_camera()
	world.rig.observing = true
	var guard = world.guards[0]
	guard.progress = 0.0
	guard._enter_state("watching")
	guard._update_visual()
	var scenarios := [
		{"name": "standing_fixed", "action": "idle", "pitch": 14.0, "orbit": false},
		{"name": "crouched_fixed", "action": "crouch_idle", "pitch": 38.0, "orbit": false},
		{"name": "camera_sweep", "action": "idle", "pitch": 14.0, "orbit": true},
	]
	for scenario in scenarios:
		_set_action(scenario.action)
		guard._rebuild_fan()
		guard._update_indicator()
		# The world process is paused for staged captures; refresh the HUD to
		# match the deliberately selected actor pose instead of its earlier state.
		world.hud.update_controls(world.player.get_control_status())
		world.hud.update_guards(world.get_guard_statuses(), 0)
		var initial_revision: int = guard.get_status().fan_revision
		var sequence := []
		var start := Time.get_ticks_usec()
		for frame in 90:
			var time := float(frame) / 60.0
			world.player.actor.animation_player.seek(fmod(time, world.player.actor.action_length(scenario.action)), true)
			world.rig.yaw = -PI / 2.0 + (sin(time * TAU / 1.5) * 0.18 if scenario.orbit else 0.0)
			world.rig.pitch_degrees = lerpf(-12.0, 50.0, float(frame) / 89.0) if scenario.orbit else float(scenario.pitch)
			world.rig.update_camera(1.0 / 60.0, not scenario.orbit)
			guard._rebuild_fan()
			await RenderingServer.frame_post_draw
			var filename := "%s-%03d.png" % [scenario.name, frame]
			root.get_texture().get_image().save_png(capture_dir.path_join(filename))
			var camera_position: Vector3 = world.rig.camera.global_position
			sequence.append({"frame": frame, "file": filename, "fan_revision": guard.get_status().fan_revision,
				"fan_vertex_count": guard.get_status().fan_vertex_count, "profile": guard.get_status().cue_height_profile,
				"pitch": world.rig.pitch_degrees, "yaw": world.rig.yaw,
				"camera": [camera_position.x, camera_position.y, camera_position.z]})
		_check(guard.get_status().fan_revision == initial_revision,
			"%s keeps one guide across 90 consecutive native renders" % scenario.name)
		report.captures.append({"scenario": scenario.name, "frames": sequence,
			"elapsed_seconds": (Time.get_ticks_usec() - start) / 1000000.0})

func _frames(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS ", message)
	else:
		failed += 1
		push_error("FAIL " + message)
