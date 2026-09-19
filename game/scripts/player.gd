class_name EscapePlayer
extends CharacterBody3D
## The controllable office worker. The level owns state, the player owns movement.

var walk_speed: float = 3.6
var run_speed: float = 5.2
var travel_distance: float = 0.0
var visual: Node3D

var _world: Node
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _stride: float = 0.0


func setup(world: Node) -> void:
	_world = world


func _ready() -> void:
	name = "Player"
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.25
	floor_stop_on_slope = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)
	_build_visual()


func _physics_process(delta: float) -> void:
	if _world == null or _world.phase != "playing":
		velocity = Vector3.ZERO
		_pose_legs(0.0)
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0.0, input.y)
	var speed := run_speed if Input.is_action_pressed("sprint") else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.1
	var previous := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
	travel_distance += moved
	if direction.length_squared() > 0.001:
		var angle := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, angle, minf(delta * 15.0, 1.0))
	if moved > 0.0001:
		_stride += moved * 8.0
		_pose_legs(sin(_stride) * 0.38)
		visual.position.y = absf(sin(_stride)) * 0.035
	else:
		_pose_legs(0.0)
		visual.position.y = 0.0


func reset_player(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	travel_distance = 0.0
	_stride = 0.0
	if visual != null:
		visual.rotation = Vector3.ZERO
		visual.position.y = 0.0
		_pose_legs(0.0)


func _pose_legs(amount: float) -> void:
	if _left_leg == null:
		return
	_left_leg.rotation.x = amount
	_right_leg.rotation.x = -amount
	_left_arm.rotation.x = -amount * 0.6
	_right_arm.rotation.x = amount * 0.6


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Programmer"
	add_child(visual)
	var coat := _material(Color("37c5b0"))
	var dark_coat := _material(Color("248e89"))
	var pants := _material(Color("203249"))
	var skin := _material(Color("f5c49c"))
	var hair := _material(Color("253345"))
	var shoe := _material(Color("dce9e9"))
	var bag := _material(Color("344c67"))
	var eyes := _material(Color("152431"))
	_box(visual, Vector3(0.51, 0.58, 0.31), Vector3(0, 0.98, 0), coat)
	_box(visual, Vector3(0.11, 0.36, 0.018), Vector3(0, 1.06, -0.165), dark_coat)
	_box(visual, Vector3(0.1, 0.14, 0.025), Vector3(0.13, 1.05, -0.17), shoe)
	_box(visual, Vector3(0.21, 0.1, 0.19), Vector3(0, 1.31, 0), skin)
	_box(visual, Vector3(0.39, 0.37, 0.35), Vector3(0, 1.52, -0.012), skin)
	_box(visual, Vector3(0.42, 0.12, 0.38), Vector3(0, 1.73, -0.006), hair)
	_box(visual, Vector3(0.42, 0.2, 0.11), Vector3(0, 1.6, 0.15), hair)
	_box(visual, Vector3(0.12, 0.045, 0.024), Vector3(-0.09, 1.55, -0.197), eyes)
	_box(visual, Vector3(0.12, 0.045, 0.024), Vector3(0.09, 1.55, -0.197), eyes)
	_box(visual, Vector3(0.08, 0.02, 0.028), Vector3(0, 1.55, -0.197), eyes)
	# A small laptop backpack makes the silhouette readable from the overhead camera.
	_box(visual, Vector3(0.35, 0.45, 0.16), Vector3(0, 1.04, 0.22), bag)
	_box(visual, Vector3(0.23, 0.03, 0.02), Vector3(0, 1.11, 0.31), dark_coat)
	_left_leg = _limb(Vector3(-0.145, 0.69, 0), Vector3(0.21, 0.53, 0.23), pants)
	_right_leg = _limb(Vector3(0.145, 0.69, 0), Vector3(0.21, 0.53, 0.23), pants)
	_box(_left_leg, Vector3(0.23, 0.15, 0.35), Vector3(0, -0.61, -0.05), shoe)
	_box(_right_leg, Vector3(0.23, 0.15, 0.35), Vector3(0, -0.61, -0.05), shoe)
	_left_arm = _limb(Vector3(-0.335, 1.21, 0), Vector3(0.16, 0.45, 0.21), coat)
	_right_arm = _limb(Vector3(0.335, 1.21, 0), Vector3(0.16, 0.45, 0.21), coat)
	_box(_left_arm, Vector3(0.15, 0.14, 0.17), Vector3(0, -0.5, 0), skin)
	_box(_right_arm, Vector3(0.15, 0.14, 0.17), Vector3(0, -0.5, 0), skin)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.40
	ring.outer_radius = 0.44
	ring.rings = 24
	ring.ring_segments = 6
	var marker := MeshInstance3D.new()
	marker.mesh = ring
	marker.position.y = 0.035
	var marker_material := _material(Color("66efce"))
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)


func _limb(at: Vector3, size: Vector3, material: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	visual.add_child(pivot)
	_box(pivot, size, Vector3(0, -size.y / 2.0, 0), material)
	return pivot


func _box(parent: Node3D, size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.86
	return result
