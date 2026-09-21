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

func play_action(action: String, rate: float = 1.0) -> void:
	if animation_player == null or not _animation_map.has(action):
		return
	current_rate = rate
	animation_player.speed_scale = rate
	if current_action != action or not animation_player.is_playing():
		current_action = action
		animation_player.play(_animation_map[action], 0.12, 1.0, rate < 0.0)
	if _paused:
		animation_player.pause()

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
