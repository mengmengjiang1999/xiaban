extends SceneTree
## Native rendered inspection of real P3 state transitions; browser tests own DOM input QA.
var world: Node3D
var output := ""
var captures: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	world = load("res://scenes/p3.tscn").instantiate()
	root.add_child(world)
	# Staged native inspection doesn't capture the user's mouse. The controller
	# still runs real physics and animations; camera updates are explicit here.
	world.set_process(false)
	world.set_physics_process(false)
	world.phase = "playing"
	world.hud.show_phase("playing")
	world.player.reset_player(Vector3(5.5, 0.05, 23.0))
	await _frames(12)
	await _capture("01-standing")
	world.player.request_crouch_toggle()
	await _frames(18)
	await _capture("02-crouched")
	Input.action_press("move_forward")
	await _frames(25)
	await _capture("03-crouch-walk")
	Input.action_release("move_forward")
	await _frames(3)
	if not world.player.request_roll():
		push_error("Native visual fixture must have space for rolling")
		quit(1)
		return
	await _frames(12)
	await _capture("04-roll-early")
	await _frames(13)
	await _capture("05-roll-middle")
	await _frames(14)
	await _capture("06-roll-late")
	await _frames(35)
	await _capture("07-roll-finished")
	world.player.reset_player(Vector3(5.5, 0.05, 23.0))
	await _frames(8)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(22)
	await _capture("08-sprint")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose": "Native P3 physics and rendered state inspection; no browser input injection", "captures": captures}, "\t"))
	print("P3_VISUAL_OK screenshots=%d" % captures.size())
	world.queue_free()
	await process_frame
	quit()

func _frames(count: int) -> void:
	for unused in range(count):
		await physics_frame
		await process_frame
		world.rig.update_camera(1.0 / 60.0)

func _capture(filename: String) -> void:
	world.player.set_physics_process(false)
	world.player.actor.set_paused(true)
	world.hud.update_controls(world.player.get_control_status())
	world.hud.update_game(world.elapsed, world.player.travel_distance, world.player.position.z)
	world.rig.update_camera(0.0, true)
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot: Dictionary = world.player.get_control_status()
	snapshot["file"] = filename + ".png"
	snapshot["phase"] = world.phase
	snapshot["position"] = str(world.player.position)
	snapshot["camera"] = str(world.rig.camera.global_transform)
	captures.append(snapshot)
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))
	world.player.actor.set_paused(false)
	world.player.set_physics_process(true)
