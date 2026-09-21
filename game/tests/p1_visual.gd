extends SceneTree
## Staged renderer QA, NOT a playthrough or browser-input test.
## Render explicit inspection poses without capturing the user's mouse.
## bash tools/godot.sh --fixed-fps 60 --script res://tests/p1_visual.gd -- --output=/absolute/path

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := "/tmp/xiaban-p1-visual-samples"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or not output.is_absolute_path():
		push_error("P1 visual QA requires a graphical renderer and absolute output path")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var world: Node3D = load("res://scenes/p1.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await process_frame
	world.hud.show_phase("playing")
	var samples := [
		["p1-start", Vector3(5.5, 0.001, 27), 0.0],
		["p1-office", Vector3(5.5, 0.001, 21.5), 0.0],
		["p1-tight-corner", Vector3(15.217, 0.001, 13.284), -1.577],
		["p1-door", Vector3(18.396, 0.001, 13.252), 0.0]
	]
	for sample in samples:
		world.player.reset_player(sample[1], sample[2])
		await physics_frame
		world.rig.reset_camera()
		world.hud.update_game(0.0, 0.0, world.player.position.z)
		# Let node notifications reach the render server before reading pixels.
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		var image: Image = root.get_texture().get_image()
		var result := image.save_png(output.path_join(sample[0] + ".png"))
		if result != OK:
			push_error("Screenshot write failed")
			quit(1)
			return
		print("P1_VISUAL sample=%s alpha=%.3f camera=%s" % [sample[0], world.player.camera_alpha, world.rig.camera.global_position])
	world.queue_free()
	await process_frame
	quit(0)
