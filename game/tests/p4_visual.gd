extends SceneTree
## Staged native render inspection. Separate browser tests drive actual input.
class StagedWorld extends "res://scripts/p4.gd":
	# Focus behavior is tested separately. An inspection window must not disturb
	# the user's desktop or invalidate fixed pose captures when it loses focus.
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
	world.phase = "playing"
	world.hud.show_phase("playing")
	world.guard.set_frozen(false)
	await _frames(20)
	await _capture("02-observation-point")
	world.player.reset_player(world.level.cover_test_position + Vector3.UP * 0.05)
	await _frames(10)
	world.player.request_crouch_toggle()
	await _frames(20)
	await _capture("03-crouched-working")
	var attempts := 0
	while world.guard.get_status().state != "watching" and attempts < 600:
		await _frames(1)
		attempts += 1
	await _frames(10)
	await _capture("04-crouched-watching")
	world.player.request_crouch_toggle()
	attempts = 0
	while float(world.guard.get_status().get("progress", 0.0)) <= 0.0 and attempts < 60:
		await _frames(1)
		attempts += 1
	await _frames(7)
	await _capture("05-standing-exposed")
	await _frames(30)
	await _capture("06-discovered")
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose": "Staged native P4a render inspection", "captures": captures}, "\t"))
	print("P4_VISUAL_OK screenshots=%d" % captures.size())
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
	world.guard.set_frozen(true)
	world.hud.update_controls(world.player.get_control_status())
	world.hud.update_guard(world.guard.get_status())
	world.hud.update_game(world.elapsed, world.player.travel_distance, world.player.position.z)
	world.rig.update_camera(0.0, true)
	await process_frame
	await RenderingServer.frame_post_draw
	var status: Dictionary = world.guard.get_status()
	captures.append({"file": filename + ".png", "phase": world.phase,
		"player": world.player.get_control_status(), "guard": status})
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))
	world.player.set_physics_process(true)
	if world.phase == "playing":
		world.player.actor.set_paused(false)
		world.guard.set_frozen(false)
