extends "res://tests/p3_test.gd"
## Actual skinned vertices during physical roll collisions and their recovery.
## Regression: mixing an interrupted upside-down roll directly into crouch
## could bury the mesh 40 cm below the floor or lift it 36 cm above the floor.
## Uses P2's calibrated Skin-bind helper without starting its benchmark scene.
## bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p3_roll_grounding_test.gd
const SkinProbe = preload("res://tests/p2_performance.gd")


func _run() -> void:
	world = load("res://scenes/p3.tscn").instantiate()
	root.add_child(world)
	await _frames(6)
	_barrier(ARENA + Vector3(0, -0.3, 0), Vector3(40, 0.5, 40), false)
	world.start_game()
	await _frames(3)
	var probe := SkinProbe.new()
	probe._cache_skin_surfaces(world.player.actor)
	_check(probe._skin_rest_error < 0.0002 and probe._rest_bind_error < 0.0002,
		"Skinned-vertex reconstruction matches this imported actor's calibrated rest binds")
	for scenario in [
		{"label": "near static wall", "wall_distance": 1.4},
		{"label": "middle static wall", "wall_distance": 1.8},
		{"label": "late static wall", "wall_distance": 2.2},
		{"label": "early incoming body", "incoming_after": 0.1},
		{"label": "mid-roll incoming body", "incoming_after": 0.4},
		{"label": "unobstructed completion"},
	]:
		await _place(ARENA)
		if scenario.has("wall_distance"):
			_barrier(world.player.global_position + Vector3(0, 1.2, -float(scenario.wall_distance)), Vector3(3, 2.4, 0.1))
		await _enter_crouch()
		await _tap(KEY_SPACE)
		var started: float = world.elapsed - 2.0 / Engine.physics_ticks_per_second
		var injected := false
		var minimum := INF
		var maximum_gap := -INF
		var sample_count := 0
		var stopped := false
		var stop_position := Vector3.ZERO
		var stop_animation_time := 0.0
		var held_position := true
		var animation_finished_in_place := false
		while world.elapsed < started + world.player.roll_duration + world.player.roll_recovery + 0.1:
			if scenario.has("incoming_after") and not injected and world.elapsed - started >= float(scenario.incoming_after):
				# The body enters the swept envelope from outside without overlapping
				# the player's smaller crouched gameplay capsule.
				_barrier(world.player.global_position + Vector3(0, 0.8, -1.1), Vector3(2, 1.6, 0.1))
				injected = true
			await _frames(1)
			world.player.actor.skeleton.force_update_all_bone_transforms()
			var y: float = probe._minimum_skinned_y(world.player.actor.skeleton) - world.player.global_position.y
			minimum = minf(minimum, y)
			maximum_gap = maxf(maximum_gap, y)
			sample_count += 1
			var state: Dictionary = world.player.get_control_status()
			if bool(state.get("roll_stopped", false)) and state.state == "roll":
				if not stopped:
					stopped = true
					stop_position = world.player.global_position
					stop_animation_time = float(world.player.get_animation_status().time)
				else:
					held_position = held_position and _flat_distance(stop_position, world.player.global_position) < 0.001
					animation_finished_in_place = animation_finished_in_place or float(world.player.get_animation_status().time) > stop_animation_time + 0.05
		var label: String = scenario.label
		_check(sample_count >= 50 and minimum > -0.03,
			"%s: every sampled roll/recovery pose stays above the 30 mm penetration limit (min %.5f m)" % [label, minimum])
		_check(maximum_gap < 0.06,
			"%s: collision recovery creates no artificial floor gap above 60 mm (max %.5f m)" % [label, maximum_gap])
		if scenario.has("wall_distance") or scenario.has("incoming_after"):
			_check(stopped and held_position and animation_finished_in_place,
				"%s: physical displacement stops while the actual roll clip continues toward its safe crouched ending" % label)
		print("P3_ROLL_GROUND_SAMPLE ", JSON.stringify({"scenario": label, "frames": sample_count,
			"minimum_y_from_feet": minimum, "maximum_floor_gap": maximum_gap, "stopped": stopped}))
		await _clear_obstacles()
	probe.free()
	_release_input()
	print("P3_ROLL_GROUNDING_RESULT passed=%d failed=%d" % [passed, failed])
	world.queue_free()
	await _frames(3)
	quit(1 if failed > 0 else 0)
