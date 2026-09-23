extends SceneTree
## Staged render inspection; real input and completion are covered in Chrome.
class StagedWorld extends "res://scripts/p4b.gd":
	func _notification(_what: int) -> void:
		pass

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
	world = StagedWorld.new()
	root.add_child(world)
	world.set_process(false)
	await _frames(12)
	await _capture("01-menu")
	for index in 3:
		world.start_game()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		world.player.reset_player(world.level.exposure_points[index] + Vector3.UP * 0.05)
		world.rig.reset_camera()
		await _frames(10)
		world.player.request_crouch_toggle()
		await _frames(25)
		var attempts := 0
		while world.guards[index].get_status().state != "watching" and attempts < 600:
			await _frames(1)
			attempts += 1
		await _frames(10)
		await _capture("0%d-zone-%d-cover" % [index + 2, index + 1])
	world.player.request_crouch_toggle()
	await _frames(60)
	await _capture("05-manager-discovery")
	world.start_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.reset_player(Vector3(11.0, 0.05, 24.45))
	world.player.rotation.y = -PI / 2.0
	world.rig.reset_camera()
	await _frames(20)
	await _capture("06-transfer-corridor")
	world.player.reset_player(Vector3(5.5, 0.05, 2.0))
	world.rig.reset_camera()
	world._set_phase("won")
	await _frames(12)
	await _capture("07-stair-exit")
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose": "Staged native P4 full-level render inspection", "captures": captures}, "\t"))
	print("P4B_VISUAL_OK screenshots=%d" % captures.size())
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
	for observer in world.guards:
		observer.set_frozen(true)
	world.hud.update_controls(world.player.get_control_status())
	world.hud.update_guards(world.get_guard_statuses(), world.level.stage_index(world.player.position))
	world.hud.update_game(world.elapsed, world.player.travel_distance, world.player.position.z)
	world.rig.update_camera(0.0, true)
	await process_frame
	await RenderingServer.frame_post_draw
	captures.append({"file": filename + ".png", "phase": world.phase,
		"player": world.player.get_control_status(), "guards": world.get_guard_statuses()})
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))
	world.player.set_physics_process(true)
	if world.phase == "playing":
		world.player.actor.set_paused(false)
		for observer in world.guards:
			observer.set_frozen(false)
