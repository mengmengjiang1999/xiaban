extends "res://scripts/p1_player.gd"
## P2 imports and previews one real skeleton. P3 owns full crouch/run/roll rules.
const Humanoid = preload("res://scripts/humanoid_actor.gd")
var preview_action: String = ""
var actor: Node3D

func _ready() -> void:
	super._ready()
	# Replace only the display; keep P1 movement collision and camera anchor.
	remove_child(visual)
	visual.queue_free()
	for child in get_children():
		if child is MeshInstance3D:
			remove_child(child)
			child.queue_free()
	_visual_materials.clear()
	actor = Humanoid.new()
	visual = actor
	add_child(actor)
	walk_speed = 1.65

func _physics_process(delta: float) -> void:
	if _world == null or _world.phase != "playing":
		stop_input()
		return
	actor.set_paused(false)
	if not preview_action.is_empty():
		# A stationary animation inspection is not the later gameplay action.
		move_input = 0.0
		turn_input = 0.0
		velocity = Vector3.ZERO
		actor.play_action(preview_action)
		return
	super._physics_process(delta)
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.05 and absf(move_input) > 0.01:
		actor.play_action("walk", signf(move_input) * clampf(speed / 1.65, 0.25, 1.5))
	else:
		actor.play_action("idle")

func set_preview_action(action: String) -> void:
	if not action.is_empty() and not action in Humanoid.ACTIONS:
		return
	preview_action = action
	stop_input()
	if actor != null:
		actor.set_paused(false)
		actor.play_action("idle" if action.is_empty() else action)

func stop_input() -> void:
	super.stop_input()
	if actor != null:
		actor.set_paused(true)

func set_camera_alpha(value: float) -> void:
	camera_alpha = clampf(value, 0.12, 1.0)
	if actor != null:
		actor.set_camera_alpha(camera_alpha)

func reset_player(at: Vector3, heading: float = 0.0) -> void:
	super.reset_player(at, heading)
	preview_action = ""
	if actor != null:
		actor.reset_pose()

func get_animation_status() -> Dictionary:
	var result: Dictionary = actor.status() if actor != null else {}
	result["preview"] = preview_action
	return result
