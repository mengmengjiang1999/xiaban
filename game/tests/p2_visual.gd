extends SceneTree
## Staged, graphical pose inspection, NOT an input test or a playthrough.
## Uses the real P2 scene, imported character, clips, lights and collision-aware rig.
## bash tools/godot.sh --fixed-fps 60 --script res://tests/p2_visual.gd -- --output=/absolute/path

const SCENE_PATH := "res://scenes/p2.tscn"
const MODEL_PATH := "res://assets/characters/office_worker.glb"
const STAGE_POSITION := Vector3(5.5, 0.001, 21.5)
const ACTION_SAMPLES := [
	{"action": "idle", "fractions": [0.15, 0.65]},
	{"action": "walk", "fractions": [0.10, 0.60]},
	{"action": "run", "fractions": [0.10, 0.60]},
	{"action": "crouch_idle", "fractions": [0.15, 0.65]},
	{"action": "crouch_walk", "fractions": [0.15, 0.65]},
	{"action": "roll", "fractions": [0.05, 0.30, 0.55, 0.80]},
]

var _world: Node3D
var _output: String
var _captures: Array[Dictionary] = []
var _clips: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or not _output.is_absolute_path():
		_fail("A graphical renderer and an absolute --output= path are required", 2)
		return
	if not ResourceLoader.exists(MODEL_PATH):
		_fail("Import the real office_worker.glb before running visual QA", 2)
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		_fail("Cannot create output directory: " + _output)
		return
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		_fail("Cannot load the P2 scene")
		return
	_world = scene.instantiate()
	root.add_child(_world)
	# Keep menu semantics: no mouse capture, elapsed gameplay, or focus-out pause.
	# Disable movement only for this staged inspection, then display the real HUD.
	_world.player.set_physics_process(false)
	await physics_frame
	await physics_frame
	await process_frame
	_world.player.reset_player(STAGE_POSITION)
	_world.hud.show_phase("playing")
	_world.hud.update_game(0.0, 0.0, STAGE_POSITION.z)
	var actor: Node3D = _world.player.actor
	var animation_player: AnimationPlayer = actor.animation_player
	if animation_player == null or actor.skeleton == null:
		_fail("The real P2 character must contain an AnimationPlayer and Skeleton3D")
		return
	for animation_name in animation_player.get_animation_list():
		_clips[String(animation_name).get_file()] = animation_name
	for sample in ACTION_SAMPLES:
		var action: String = sample.action
		if not _clips.has(action) or animation_player.get_animation(_clips[action]).length <= 0.0:
			_fail("Missing or empty animation: " + action)
			return

	# Document view: recognizable office context with a full-body shoulder view.
	_frame_character(false)
	if not await _capture("p2-00-office-shoulder", "idle", 0.15, "shoulder"):
		return
	# The frontal view faces into the open room, away from the wall behind the actor.
	# A narrower QA field of view makes limbs readable while keeping 5.2 m clearance.
	_frame_character(true)
	if not await _capture("p2-00-idle-front", "idle", 0.15, "front"):
		return
	for action_index in ACTION_SAMPLES.size():
		var sample: Dictionary = ACTION_SAMPLES[action_index]
		var action: String = sample.action
		for sample_index in sample.fractions.size():
			var filename := "p2-%02d-%s-front-%02d" % [action_index + 1, action, sample_index + 1]
			if not await _capture(filename, action, float(sample.fractions[sample_index]), "front"):
				return

	var manifest := FileAccess.open(_output.path_join("p2-visual-manifest.json"), FileAccess.WRITE)
	if manifest == null:
		_fail("Cannot write the visual QA manifest")
		return
	manifest.store_string(JSON.stringify({
		"purpose": "Staged graphical pose inspection; not an input test or a playthrough",
		"scene": SCENE_PATH,
		"model": MODEL_PATH,
		"display_server": DisplayServer.get_name(),
		"world_phase": _world.phase,
		"player_physics_enabled": _world.player.is_physics_processing(),
		"bone_count": actor.skeleton.get_bone_count(),
		"mesh_count": actor.meshes.size(),
		"captures": _captures,
	}, "\t"))
	manifest.close()
	print("P2_VISUAL_OK staged=true screenshots=%d output=%s" % [_captures.size(), _output])
	_world.queue_free()
	await process_frame
	quit(0)


func _frame_character(front: bool) -> void:
	_world.player.rotation.y = PI if front else 0.0
	_world.rig.set_observing(true)
	_world.rig.yaw = -0.28 if front else 0.0
	_world.rig.desired_distance = 5.2
	_world.rig.anchor_height = 1.05 if front else 1.3
	_world.rig.pitch_degrees = 10.0 if front else 14.0
	_world.rig.camera.fov = 45.0 if front else 60.0
	_world.rig.update_camera(0.0, true)


func _capture(filename: String, action: String, fraction: float, view: String) -> bool:
	var actor: Node3D = _world.player.actor
	var animation_player: AnimationPlayer = actor.animation_player
	var clip_name: StringName = _clips[action]
	var clip: Animation = animation_player.get_animation(clip_name)
	var sample_time := clip.length * fraction
	# No crossfade from the preceding clip, and no automatic time advance between
	# sampling and drawing. seek(update=true) evaluates the actual imported tracks.
	actor.set_paused(false)
	actor.current_action = action
	actor.current_rate = 0.0
	_world.player.preview_action = action
	animation_player.play(clip_name, 0.0)
	animation_player.speed_scale = 0.0
	animation_player.seek(sample_time, true)
	animation_player.advance(0.0)
	actor.skeleton.force_update_all_bone_transforms()
	_world.rig.update_camera(0.0, true)
	_world.hud.update_animation_status(actor.status(), action)
	# The skin palette, material uploads and viewport must reach an actual draw.
	# Waiting only for physics would allow a capture of the preceding pose.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if _world.phase != "menu" or not is_equal_approx(animation_player.current_animation_position, sample_time):
		_fail("Staged pose changed before capture: " + filename)
		return false
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("The graphical viewport did not produce an image: " + filename)
		return false
	if image.save_png(_output.path_join(filename + ".png")) != OK:
		_fail("Cannot save screenshot: " + filename)
		return false
	var camera: Camera3D = _world.rig.camera
	var anchor: Vector3 = _world.player.global_position + Vector3.UP * _world.rig.anchor_height
	_captures.append({
		"file": filename + ".png", "action": action, "clip": String(clip_name),
		"view": view, "fraction": fraction, "time_seconds": sample_time,
		"clip_length_seconds": clip.length, "rendered_time_seconds": animation_player.current_animation_position,
		"image_size": [image.get_width(), image.get_height()],
		"player_position": _vector_array(_world.player.global_position),
		"player_heading": _world.player.rotation.y, "camera_position": _vector_array(camera.global_position),
		"camera_yaw": _world.rig.yaw, "camera_fov": camera.fov,
		"camera_anchor_distance": camera.global_position.distance_to(anchor),
		"character_alpha": _world.player.camera_alpha,
	})
	print("P2_VISUAL staged=true sample=%s action=%s time=%.4f/%.4f" % [filename, action, sample_time, clip.length])
	return true


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _fail(message: String, code: int = 1) -> void:
	push_error("P2 visual QA: " + message)
	quit(code)
