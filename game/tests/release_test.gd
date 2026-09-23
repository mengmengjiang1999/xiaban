extends "res://tests/p4b_test.gd"
## Final production scene regression reuses the complete level's substantive
## geometry, visibility, sound, lifecycle and actual movement route checks.
## The inherited helper methods intentionally exercise the release actors and
## scenery instantiated below, rather than accepting historical P4 results.

func _run() -> void:
	world = load("res://scenes/release.tscn").instantiate()
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
	_test_release_characters()
	_test_audio_samples()
	world.player.sprint_noise_emitted.connect(_on_sprint_noise)
	world.start_game()
	await _frames(4)
	_check(world.phase == "playing" and _flat_distance(world.player.global_position, world.level.spawn_position) < 0.03,
		"Start places the player at the complete first-level spawn")
	await _test_release_feedback()
	await _test_independent_routines()
	await _test_cover_for_each_leader()
	await _test_desk_geometry()
	await _test_sound_isolation()
	await _test_room_occlusion()
	await _test_failure_for_each_leader()
	await _test_freeze_and_reset()
	await _test_all_exit_priorities()
	await _test_route()
	_check(world.audio.get_status().event_counts.won > 0 and world.audio.get_status().event_counts.lost >= 3,
		"Actual success and each leader discovery produce their outcome sounds")
	_restore_guards()
	_release_input()
	print("RELEASE_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	# Fixed-fps headless can simulate two minutes before the audio thread has
	# mixed even a handful of buffers. Stop sources and give it real wall time.
	world.show_menu()
	for source in world.find_children("*", "AudioStreamPlayer", true, false):
		source.stop()
	for source in world.find_children("*", "AudioStreamPlayer3D", true, false):
		source.stop()
	await _frames(3)
	OS.delay_msec(150)
	await _frames(3)
	world.queue_free()
	await _frames(3)
	OS.delay_msec(150)
	await _frames(3)
	quit(1 if failed > 0 else 0)

func _test_release_characters() -> void:
	var actors: Array[Node3D] = [world.player.actor]
	for observer in world.guards:
		actors.append(observer.actor)
	var identities: Array[String] = []
	var instance_materials := {}
	var expected_tasks: Array[String] = ["typing", "reading", "reviewing"]
	for index in actors.size():
		var actor := actors[index]
		var wardrobe: Node = actor.get_meta("release_identity", null)
		var identity := str(wardrobe.get_meta("identity", "")) if wardrobe != null else ""
		identities.append(identity)
		_check(not identity.is_empty() and actor.skeleton.get_bone_count() == 53
			and actor.status().actions.size() == 6 and actor.meshes.size() > 6,
			"Release %s retains the complete adult rig and six actions alongside actual wardrobe geometry" % identity)
		var original_alphas: Array[float] = []
		var original_modes: Array[int] = []
		var independent := true
		for material in actor.materials:
			original_alphas.append(material.albedo_color.a)
			original_modes.append(material.transparency)
			independent = independent and not instance_materials.has(material.get_instance_id())
			instance_materials[material.get_instance_id()] = true
		actor.set_camera_alpha(0.25)
		var fades := true
		for mat_index in actor.materials.size():
			fades = fades and is_equal_approx(actor.materials[mat_index].albedo_color.a, original_alphas[mat_index] * 0.25)
		actor.set_camera_alpha(1.0)
		var restored := true
		for mat_index in actor.materials.size():
			restored = restored and is_equal_approx(actor.materials[mat_index].albedo_color.a, original_alphas[mat_index])
			restored = restored and actor.materials[mat_index].transparency == original_modes[mat_index]
		_check(independent and fades and restored,
			"Release %s wardrobe fades with camera occlusion, restores cutouts and shares no mutable materials" % identity)
		if index > 0:
			_check(world.guards[index-1].get_status().office_task == expected_tasks[index-1],
				"Release %s uses its own office activity" % identity)
	_check(identities == ["player", "team_lead", "supervisor", "manager"],
		"The final scene assigns four distinct adult identities in the intended gameplay roles")

func _test_release_feedback() -> void:
	await _fresh()
	for observer in world.guards:
		observer.work_duration = 100.0
		observer.phase_offset = 0.0
		observer.reset_guard()
	var before: Dictionary = world.audio.get_status()
	_check(before.ambient_playing and before.event_counts.start > 0,
		"Starting a real game activates office ambience and the start cue")
	await _seconds(1.4)
	_check(world.audio.get_status().event_counts.office > before.event_counts.office,
		"Active independent office work produces spatial cosmetic foley")
	var bus := AudioServer.get_bus_index("Xiaban")
	var saved_volume: float = before.volume
	world.audio.set_volume(0.0)
	_check(bus >= 0 and AudioServer.is_bus_mute(bus) and world.audio.get_status().muted,
		"Zero volume mutes the actual shared release audio bus")
	var footsteps: Array[Node] = world.player.find_children("*", "AudioStreamPlayer3D", true, false)
	_check(not footsteps.is_empty() and footsteps.all(func(source): return source.bus == "Xiaban"),
		"The same volume control includes the existing sprint footstep source")
	world.audio.set_volume(saved_volume)
	await _frames(2)
	_noise_events.clear()
	before = world.audio.get_status()
	await _enter_crouch()
	await _frames(3)
	_check(world.audio.get_status().event_counts.crouch == before.event_counts.crouch + 1,
		"An actual crouch transition plays one movement cue")
	before = world.audio.get_status()
	await _tap(KEY_SPACE)
	await _wait_until_roll_ends()
	await _seconds(world.player.roll_recovery + 0.1)
	_check(world.audio.get_status().event_counts.roll == before.event_counts.roll + 1 and _noise_events.is_empty(),
		"An actual roll plays one cosmetic cue without emitting AI hearing noise")
	world.pause_game()
	await _frames(2)
	var paused: Dictionary = world.audio.get_status()
	await _seconds(0.5)
	var frozen: Dictionary = world.audio.get_status()
	_check(not frozen.ambient_playing and frozen.event_counts == paused.event_counts,
		"Pause silences office ambience and freezes feedback events")
	world.resume_game()
	await _frames(3)
	_check(world.audio.get_status().ambient_playing and world.audio.get_status().event_counts.start == paused.event_counts.start,
		"Continue restores ambience without replaying the new-game cue")
	await _fresh()

func _test_audio_samples() -> void:
	var streams: Dictionary = world.audio.get("_streams")
	var metrics := {}
	var valid := streams.size() == 11
	for kind in streams:
		var stream: AudioStreamWAV = streams[kind]
		var bytes: PackedByteArray = stream.data
		var squares := 0.0
		var peak := 0.0
		var count := bytes.size() / 2
		for index in count:
			var sample := float(bytes.decode_s16(index * 2)) / 32768.0
			squares += sample * sample
			peak = maxf(peak, absf(sample))
		var rms := sqrt(squares / maxf(1, count))
		var duration := float(count) / stream.mix_rate
		metrics[kind] = {"samples": count, "sample_rate": stream.mix_rate,
			"duration_seconds": duration, "peak": peak, "rms": rms,
			"looped": stream.loop_mode != AudioStreamWAV.LOOP_DISABLED}
		valid = valid and bytes.size() % 2 == 0 and stream.format == AudioStreamWAV.FORMAT_16_BITS
		valid = valid and count > 0 and rms > 0.0001 and rms < 0.6 and peak < 0.951 and duration >= 0.2
	_check(valid, "Every authored audio clip contains measurable nonclipping PCM with a valid duration and level")
	var ambience: AudioStreamWAV = streams.air
	var join := absf(float(ambience.data.decode_s16(0) - ambience.data.decode_s16(ambience.data.size() - 2)) / 32768.0)
	metrics.air["loop_join_delta"] = join
	_check(ambience.loop_mode == AudioStreamWAV.LOOP_FORWARD and ambience.loop_end == ambience.data.size() / 2 and join < 0.002,
		"The looping room tone has an explicit full-length loop and a quiet seam")
	var report := FileAccess.open(ProjectSettings.globalize_path("res://../.logs/release-audio-metrics.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify(metrics, "  "))
	print("RELEASE_AUDIO_METRICS ", JSON.stringify(metrics))
