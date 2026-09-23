extends Node3D
## Imported, skinned P2 actor. Animation never owns the gameplay/camera transform.
const MODEL_PATH := "res://assets/characters/office_worker.glb"
const ACTIONS: Array[String] = ["idle", "walk", "run", "crouch_idle", "crouch_walk", "roll"]
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var current_action: String = "idle"
var current_rate: float = 1.0
var meshes: Array[MeshInstance3D] = []
var materials: Array[StandardMaterial3D] = []
var _material_modes: Array[int] = []
var _material_alphas: Array[float] = []
var _animation_map: Dictionary = {}
var _paused := false

func _ready() -> void:
	name = "HumanoidVisual"
	var scene := load(MODEL_PATH) as PackedScene
	assert(scene != null, "P2 requires the imported office_worker.glb character")
	var model := scene.instantiate()
	model.name = "OfficeWorker"
	add_child(model)
	_collect(model)
	assert(animation_player != null and skeleton != null, "P2 asset must include a skeleton and animations")
	# Playback policy is per actor: P3's one-shot roll must not change P2 previews.
	for library_name in animation_player.get_animation_library_list():
		var source := animation_player.get_animation_library(library_name)
		var library := AnimationLibrary.new()
		for clip in source.get_animation_list():
			library.add_animation(clip, source.get_animation(clip).duplicate(true))
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)
	for animation_name in animation_player.get_animation_list():
		var action := String(animation_name).get_file()
		if action in ACTIONS:
			_animation_map[action] = animation_name
			animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	for action in ACTIONS:
		assert(_animation_map.has(action), "Missing P2 action: " + action)
	play_action("idle")

func _collect(node: Node) -> void:
	if node is AnimationPlayer:
		animation_player = node
	elif node is Skeleton3D:
		skeleton = node
	elif node is MeshInstance3D and node.mesh != null:
		meshes.append(node)
		# Each actor owns its materials so near-camera fading cannot affect copies.
		for index in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(index)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				node.set_surface_override_material(index, material)
				materials.append(material)
				_material_modes.append(material.transparency)
				_material_alphas.append(material.albedo_color.a)
	for child in node.get_children():
		_collect(child)

func play_action(action: String, rate: float = 1.0, restart: bool = false, looping: bool = true, blend: float = 0.12) -> void:
	if animation_player == null or not _animation_map.has(action):
		return
	current_rate = rate
	animation_player.get_animation(_animation_map[action]).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	animation_player.speed_scale = rate
	if restart or current_action != action or not animation_player.is_playing():
		current_action = action
		animation_player.play(_animation_map[action], blend, 1.0, rate < 0.0)
		if restart:
			animation_player.seek(0.0, true)
	if _paused:
		animation_player.pause()

func action_length(action: String) -> float:
	return animation_player.get_animation(_animation_map[action]).length if _animation_map.has(action) else 0.0

func bone_world_position(bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin if bone >= 0 else global_position

func set_paused(value: bool) -> void:
	if value == _paused:
		return
	_paused = value
	if animation_player != null:
		if _paused:
			animation_player.pause()
		else:
			animation_player.play()

func set_camera_alpha(value: float) -> void:
	for index in materials.size():
		var material := materials[index]
		# Restore authored hair/brow cutouts as well as opaque cloth after fading.
		material.transparency = _material_modes[index] if value >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		material.albedo_color.a = _material_alphas[index] * value

func reset_pose() -> void:
	_paused = false
	current_action = ""
	play_action("idle")
	if animation_player != null:
		animation_player.seek(0.0, true)

func status() -> Dictionary:
	return {
		"action": current_action,
		"rate": current_rate,
		"time": animation_player.current_animation_position if animation_player != null else 0.0,
		"paused": _paused,
		"actions": _animation_map.keys(),
		"bones": skeleton.get_bone_count() if skeleton != null else 0,
		"meshes": meshes.size(),
	}
