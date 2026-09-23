extends "res://scripts/p4_guard.gd"
## Presentation-only subclass. Detection, hearing and timing use the P4 AI.
const Wardrobe = preload("res://scripts/release_character.gd")
const OfficeTask = preload("res://scripts/release_guard_visual.gd")

func _ready() -> void:
	super._ready()
	# Preserve the original local pose captured before P4 first lowered the head.
	# Re-seeking a clip alone would leave procedurally changed unkeyed positions.
	var source_pose: Array[Transform3D] = _pose._base.duplicate()
	_pose.free()
	Wardrobe.apply_to(actor,guard_id)
	_pose=OfficeTask.new()
	_pose.configure(guard_id)
	add_child(_pose)
	_pose.setup(actor)
	_pose._base=source_pose
	_update_visual()

func get_status() -> Dictionary:
	var status := super.get_status()
	status["wardrobe"] = guard_id
	status["office_task"] = "typing" if guard_id == "team_lead" else ("reading" if guard_id == "supervisor" else "reviewing")
	return status
