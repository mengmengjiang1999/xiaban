extends CharacterBody3D
## P1 movement sample. Body heading is independent of camera and visual pose.
var walk_speed: float = 3.6
var turn_speed: float = 2.2
var move_input: float = 0.0
var turn_input: float = 0.0
var travel_distance: float = 0.0
var visual: Node3D
var camera_alpha: float = 1.0
var _visual_materials: Array[StandardMaterial3D] = []
var _world: Node

func setup(world: Node) -> void:
	_world = world

func _ready() -> void:
	name = "Player"
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.25
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)
	visual = Node3D.new()
	visual.name = "PoseOnly"
	add_child(visual)
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.34
	mesh.height = 1.7
	body.mesh = mesh
	body.position.y = 0.85
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("55c8b1")
	material.roughness = 0.72
	_visual_materials.append(material)
	body.material_override = material
	visual.add_child(body)
	# A face strip identifies forward from every camera angle.
	var face := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(0.34, 0.15, 0.07)
	face.mesh = strip
	face.position = Vector3(0, 1.32, -0.31)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("1c3742")
	_visual_materials.append(dark)
	face.material_override = dark
	visual.add_child(face)
	var marker := MeshInstance3D.new()
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.32, 0.06, 0.42)
	marker.mesh = arrow
	marker.rotation.x = PI
	marker.position = Vector3(0, 0.05, -0.58)
	marker.material_override = material
	add_child(marker)

func _physics_process(delta: float) -> void:
	if _world == null or _world.phase != "playing":
		stop_input()
		return
	move_input = Input.get_axis("move_back", "move_forward")
	turn_input = Input.get_axis("turn_right", "turn_left")
	rotation.y = wrapf(rotation.y + turn_input * turn_speed * delta, -PI, PI)
	var forward := -global_basis.z
	velocity.x = forward.x * move_input * walk_speed
	velocity.z = forward.z * move_input * walk_speed
	velocity.y = -0.1 if is_on_floor() else velocity.y - 20.0 * delta
	var previous := global_position
	move_and_slide()
	travel_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()

func stop_input() -> void:
	move_input = 0.0
	turn_input = 0.0
	velocity = Vector3.ZERO

func set_camera_alpha(value: float) -> void:
	# Close walls can retract the camera into the capsule's silhouette. Fade
	# only its display materials; movement/physical shape never change here.
	camera_alpha = clampf(value, 0.12, 1.0)
	for material in _visual_materials:
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if camera_alpha >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = camera_alpha

func reset_player(at: Vector3, heading: float = 0.0) -> void:
	global_position = at
	rotation = Vector3(0, heading, 0)
	stop_input()
	travel_distance = 0.0
	if visual != null:
		visual.transform = Transform3D.IDENTITY
