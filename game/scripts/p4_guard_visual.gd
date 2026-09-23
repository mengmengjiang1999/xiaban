extends Node3D
## A per-instance office pose, composed on top of the validated imported rig.
## Only this observer is modified; player clips and shared assets are untouched.
var _actor: Node3D
var _skeleton: Skeleton3D
var _base: Array[Transform3D] = []

func setup(actor: Node3D) -> void:
	_actor = actor
	_skeleton = actor.skeleton
	for index in _skeleton.get_bone_count():
		_base.append(_skeleton.get_bone_pose(index))

func apply_pose(lift: float, clock: float) -> void:
	for index in _base.size():
		_skeleton.set_bone_pose(index, _base[index])
	var work := 1.0 - lift
	# Head lowering is a visible telegraph, not a hidden detection switch.
	_rotate_world("spine_01", deg_to_rad(-12.0 * work))
	_rotate_world("neck_01", deg_to_rad(-12.0 * work))
	_rotate_world("head", deg_to_rad(-22.0 * work))
	# Forearms reach the standing desk. Tiny alternating hand movement reads
	# as keyboard work while both feet stay in the grounded source idle pose.
	for side in ["l", "r"]:
		var x := -1.0 if side == "l" else 1.0
		var pulse := sin(clock * 4.5 + (PI if side == "l" else 0.0)) * 0.008 * work
		_aim("upperarm_" + side, Vector3(x * 0.30, 1.15, -0.23), work)
		_aim("lowerarm_" + side, Vector3(x * 0.23, 1.20 + pulse, -0.55), work)

func _rotate_world(bone_name: String, angle: float) -> void:
	var bone := _skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var pose := _skeleton.get_bone_global_pose(bone)
	var world_axis: Vector3 = _actor.global_basis.x
	var axis := (_skeleton.global_basis.inverse() * world_axis).normalized()
	pose.basis = Basis(axis, angle) * pose.basis
	_skeleton.set_bone_global_pose(bone, pose)

func _aim(bone_name: String, target: Vector3, amount: float) -> void:
	var bone := _skeleton.find_bone(bone_name)
	if bone < 0 or amount < 0.0001:
		return
	var pose := _skeleton.get_bone_global_pose(bone)
	var destination := _skeleton.to_local(_actor.to_global(target))
	var direction := (destination - pose.origin).normalized()
	var rotate := Quaternion(pose.basis.y.normalized(), direction)
	pose.basis = Basis(Quaternion.IDENTITY.slerp(rotate, amount)) * pose.basis
	_skeleton.set_bone_global_pose(bone, pose)
