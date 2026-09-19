class_name EscapeGuard
extends CharacterBody3D
## Shared boss behavior. All distances are world metres; positions are feet.

signal caught(guard: EscapeGuard)
signal spotted(guard: EscapeGuard)

const EYE_HEIGHT: float = 1.48
const TARGET_HEIGHT: float = 1.05
const PATROL_SPEED: float = 1.5
# First-level pacing: exposure has a one-second grace period. Walking cannot
# outrun a chase, but the player's 5.2 m/s sprint can still reach real cover.
const CHASE_SPEED: float = 4.4
const ALERT_SECONDS: float = 1.0
const SIGHT_MASK: int = 2
const FAN_STEPS: int = 36

var world: Node
var guard_id: int = 0
var display_name: String = "工位领导"
var waypoints: Array[Vector3] = []
var sight_range: float = 8.0
var fov_degrees: float = 70.0
var alert: float = 0.0
var state: String = "patrol"
var facing: Vector3 = Vector3.FORWARD
var visual: Node3D

var _spawn: Vector3
var _waypoint_index: int = 1
var _waypoint_step: int = 1
var _patrol_time: float = 0.0
var _wait_time: float = 0.0
var _unseen_time: float = 0.0
var _search_time: float = 0.0
var _last_seen: Vector3
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _path_target: Vector3 = Vector3.INF
var _repath_time: float = 0.0
var _caught_sent: bool = false
var _fan_clock: float = 0.0
var _initial_fan: bool = true
var _walk_time: float = 0.0
var _fan: MeshInstance3D
var _fan_material: StandardMaterial3D
var _label: Label3D
var _left_leg: Node3D
var _right_leg: Node3D


func setup(level: Node, id: int, points: Array[Vector3]) -> void:
	world = level
	guard_id = id
	waypoints.assign(points)
	_spawn = waypoints[0] if not waypoints.is_empty() else Vector3.ZERO
	position = _spawn
	sight_range = [9.0, 8.0, 7.0][clampi(id, 0, 2)]
	fov_degrees = 90.0 if id == 0 else 70.0
	display_name = ["工位领导", "办公室领导", "楼梯口领导"][clampi(id, 0, 2)]
	# L1 first watches the aisle, prompting the player to observe from cover.
	facing = Vector3.RIGHT if id == 2 else Vector3.LEFT
	collision_layer = 8
	collision_mask = 1
	floor_snap_length = 0.25


func _ready() -> void:
	_build_body()
	_build_fan()
	reset_guard()


func reset_guard() -> void:
	position = _spawn
	velocity = Vector3.ZERO
	alert = 0.0
	state = "patrol"
	facing = Vector3.RIGHT if guard_id == 2 else Vector3.LEFT
	_waypoint_index = 1 if waypoints.size() > 1 else 0
	_waypoint_step = 1
	_patrol_time = 0.0
	_wait_time = 0.0
	_unseen_time = 0.0
	_search_time = 0.0
	_last_seen = _spawn
	_path.clear()
	_path_index = 0
	_path_target = Vector3.INF
	_repath_time = 0.0
	_caught_sent = false
	_fan_clock = 0.0
	_initial_fan = true
	_walk_time = 0.0
	if is_instance_valid(visual):
		visual.position = Vector3.ZERO
		visual.rotation.y = atan2(facing.x, facing.z)
		_left_leg.rotation.x = 0.0
		_right_leg.rotation.x = 0.0
		_update_label()


func _physics_process(delta: float) -> void:
	# Populate the frozen menu's view once the physics space is available.
	if _initial_fan:
		_initial_fan = false
		_update_fan()
	if not is_instance_valid(world) or world.get("phase") != "playing":
		velocity = Vector3.ZERO
		return
	var target: CharacterBody3D = world.get("player") as CharacterBody3D
	if not is_instance_valid(target):
		return
	_repath_time -= delta
	_wait_time = maxf(0.0, _wait_time - delta)
	var visible: bool = can_see(target.global_position)
	if visible:
		_unseen_time = 0.0
		_last_seen = target.global_position
		if state == "chase" or state == "search":
			state = "chase"
			alert = 1.0
		else:
			alert = minf(1.0, alert + delta / ALERT_SECONDS)
			if alert >= 1.0:
				_begin_chase()
			else:
				state = "suspicious"
	else:
		_unseen_time += delta
		if state == "suspicious":
			if _unseen_time > 0.35:
				alert = maxf(0.0, alert - delta * 0.45)
			if alert <= 0.0:
				state = "return"
		elif state == "return" or state == "patrol":
			alert = maxf(0.0, alert - delta * 0.38)

	var movement: Vector3 = Vector3.ZERO
	match state:
		"patrol":
			movement = _patrol(delta)
		"suspicious":
			_turn_towards(_last_seen - global_position, delta)
		"chase":
			movement = _follow_target(_last_seen, CHASE_SPEED, delta)
			if not visible and (_flat_distance(global_position, _last_seen) < 0.5 or _unseen_time > 6.0):
				state = "search"
				_search_time = 0.0
				movement = Vector3.ZERO
		"search":
			_search_time += delta
			alert = maxf(0.3, alert - delta * 0.25)
			_turn_towards(Vector3(sin(_search_time * 2.1), 0, cos(_search_time * 2.1)), delta)
			if _search_time >= 2.8:
				state = "return"
				_repath_time = 0.0
		"return":
			var home: Vector3 = _spawn if guard_id == 0 else waypoints[_waypoint_index]
			movement = _follow_target(home, PATROL_SPEED, delta)
			if _flat_distance(global_position, home) < 0.3:
				state = "patrol"
				_wait_time = 0.6
	velocity.x = movement.x
	velocity.z = movement.z
	if is_on_floor():
		velocity.y = -0.4
	else:
		velocity.y -= 20.0 * delta
	move_and_slide()
	# Only a boss whose alert has filled can catch the player. Query at waist
	# height, so a low desk still prevents grabbing through it.
	if state == "chase" and not _caught_sent and _flat_distance(global_position, target.global_position) < 0.75:
		if _clear_line(target.global_position, 0.55, 0.55, 1):
			_caught_sent = true
			caught.emit(self)
	_fan_clock += delta
	if _fan_clock >= 0.10:
		_fan_clock = 0.0
		_update_fan()
		_update_label()


func _process(delta: float) -> void:
	if not is_instance_valid(world) or world.get("phase") != "playing":
		return
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_walk_time += delta * speed * 3.0
	var stride: float = sin(_walk_time) * minf(speed / 3.2, 1.0) * 0.48
	_left_leg.rotation.x = stride
	_right_leg.rotation.x = -stride
	visual.position.y = absf(sin(_walk_time)) * minf(speed, 1.0) * 0.035


func can_see(point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > sight_range:
		return false
	if distance > 0.001 and facing.dot(offset / distance) < cos(deg_to_rad(fov_degrees * 0.5)):
		return false
	return _clear_line(point, EYE_HEIGHT, TARGET_HEIGHT, SIGHT_MASK)


func _clear_line(point: Vector3, from_height: float, to_height: float, mask: int) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * from_height, point + Vector3.UP * to_height, mask
	)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _begin_chase() -> void:
	state = "chase"
	alert = 1.0
	_repath_time = 0.0
	spotted.emit(self)


func _patrol(delta: float) -> Vector3:
	if guard_id == 0 or waypoints.size() < 2:
		_patrol_time += delta
		var look: Vector3 = Vector3.LEFT if fmod(_patrol_time, 7.0) < 3.8 else Vector3.BACK
		_turn_towards(look, delta)
		return Vector3.ZERO
	if _wait_time > 0.0:
		return Vector3.ZERO
	var destination: Vector3 = waypoints[_waypoint_index]
	if _flat_distance(global_position, destination) < 0.26:
		# L3's first point is an initial position; its two outer points are
		# the continuing route, so it does not turn around at its spawn point.
		if guard_id == 2 and waypoints.size() >= 3:
			_waypoint_index = 2 if _waypoint_index == 1 else 1
			_wait_time = 1.1
			_repath_time = 0.0
			return Vector3.ZERO
		if _waypoint_index == waypoints.size() - 1:
			_waypoint_step = -1
			_wait_time = 1.1
		elif _waypoint_index == 0:
			_waypoint_step = 1
			_wait_time = 0.8
		_waypoint_index += _waypoint_step
		_repath_time = 0.0
		return Vector3.ZERO
	return _follow_target(destination, PATROL_SPEED, delta)


func _follow_target(destination: Vector3, speed: float, delta: float) -> Vector3:
	if _repath_time <= 0.0 or _flat_distance(destination, _path_target) > 0.7:
		var requested: Variant = world.call("find_path", global_position, destination)
		_path = requested if requested is PackedVector3Array else PackedVector3Array()
		_path_index = 0
		_path_target = destination
		_repath_time = 0.45
	while _path_index < _path.size() and _flat_distance(global_position, _path[_path_index]) < 0.22:
		_path_index += 1
	if _path_index >= _path.size():
		return Vector3.ZERO
	var direction: Vector3 = _path[_path_index] - global_position
	direction.y = 0.0
	direction = direction.normalized()
	_turn_towards(direction, delta)
	return direction * speed


func _turn_towards(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var angle: float = atan2(facing.x, facing.z)
	var target_angle: float = atan2(direction.x, direction.z)
	angle = lerp_angle(angle, target_angle, 1.0 - exp(-5.0 * delta))
	facing = Vector3(sin(angle), 0, cos(angle))
	visual.rotation.y = angle


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _build_fan() -> void:
	_fan_material = StandardMaterial3D.new()
	_fan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fan_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fan_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fan_material.no_depth_test = false
	_fan_material.render_priority = 1
	_fan = MeshInstance3D.new()
	_fan.name = "SightFan"
	_fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fan)


func _update_fan() -> void:
	if not is_instance_valid(_fan):
		return
	var safe_color := Color(1.0, 0.76, 0.25, 0.17)
	var alert_color := Color(1.0, 0.19, 0.15, 0.31)
	_fan_material.albedo_color = safe_color.lerp(alert_color, alert)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fan_material)
	var previous := Vector3.ZERO
	var base_angle: float = atan2(facing.x, facing.z)
	for i in range(FAN_STEPS + 1):
		var angle: float = base_angle + deg_to_rad(-fov_degrees * 0.5 + fov_degrees * float(i) / float(FAN_STEPS))
		var direction := Vector3(sin(angle), 0, cos(angle))
		var distance: float = sight_range
		# The ray has the same eye/body heights and mask as real detection.
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * EYE_HEIGHT,
			global_position + direction * sight_range + Vector3.UP * TARGET_HEIGHT,
			SIGHT_MASK
		)
		query.exclude = [get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			distance = maxf(0.0, _flat_distance(global_position, hit_position) - 0.045)
		var point: Vector3 = direction * distance
		point.y = 0.028 - position.y
		if i > 0:
			mesh.surface_add_vertex(Vector3(0, point.y, 0))
			mesh.surface_add_vertex(previous)
			mesh.surface_add_vertex(point)
		previous = point
	mesh.surface_end()
	_fan.mesh = mesh


func _update_label() -> void:
	var status: String = "WORKING" if guard_id == 0 else "PATROL"
	match state:
		"suspicious": status = "?  %d%%" % int(alert * 100.0)
		"chase": status = "!  STOP!"
		"search": status = "?  SEARCHING"
		"return": status = "RETURNING"
	_label.text = "L%d  %s" % [guard_id + 1, status]
	_label.modulate = Color(1.0, 0.47, 0.38) if state == "chase" else Color(1.0, 0.90, 0.66)


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.74
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.87
	add_child(collision)
	visual = Node3D.new()
	visual.name = "BossModel"
	add_child(visual)
	var suit_color: Color = [Color("55435e"), Color("775043"), Color("3b5368")][clampi(guard_id, 0, 2)]
	var suit: StandardMaterial3D = _material(suit_color)
	var pants: StandardMaterial3D = _material(Color("252735"))
	var skin: StandardMaterial3D = _material(Color("dfaa82"))
	var hair: StandardMaterial3D = _material(Color("34302d"))
	var shirt: StandardMaterial3D = _material(Color("f6ead1"))
	var tie: StandardMaterial3D = _material(Color("eeac44"))
	var shoes: StandardMaterial3D = _material(Color("171d26"))
	_box(visual, Vector3(0.59, 0.66, 0.34), Vector3(0, 1.01, 0), suit)
	_box(visual, Vector3(0.23, 0.43, 0.025), Vector3(0, 1.08, 0.178), shirt)
	_box(visual, Vector3(0.067, 0.33, 0.031), Vector3(0, 1.09, 0.199), tie)
	_box(visual, Vector3(0.46, 0.45, 0.40), Vector3(0, 1.57, 0), skin)
	_box(visual, Vector3(0.49, 0.13, 0.43), Vector3(0, 1.78, -0.015), hair)
	_box(visual, Vector3(0.46, 0.21, 0.07), Vector3(0, 1.64, -0.18), hair)
	_box(visual, Vector3(0.085, 0.045, 0.04), Vector3(-0.115, 1.61, 0.204), shoes)
	_box(visual, Vector3(0.085, 0.045, 0.04), Vector3(0.115, 1.61, 0.204), shoes)
	_box(visual, Vector3(0.06, 0.025, 0.05), Vector3(0, 1.61, 0.207), shoes)
	for side in [-1.0, 1.0]:
		_box(visual, Vector3(0.17, 0.54, 0.24), Vector3(side * 0.37, 1.02, 0), suit)
		_box(visual, Vector3(0.15, 0.14, 0.20), Vector3(side * 0.37, 0.70, 0.025), skin)
	_left_leg = Node3D.new()
	_right_leg = Node3D.new()
	for i in range(2):
		var leg: Node3D = _left_leg if i == 0 else _right_leg
		leg.position = Vector3(-0.15 if i == 0 else 0.15, 0.69, 0)
		visual.add_child(leg)
		_box(leg, Vector3(0.22, 0.52, 0.25), Vector3(0, -0.26, 0), pants)
		_box(leg, Vector3(0.24, 0.14, 0.35), Vector3(0, -0.62, 0.045), shoes)
	_label = Label3D.new()
	_label.name = "BossStatus"
	_label.position.y = 2.20
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 34
	_label.outline_size = 9
	_label.pixel_size = 0.007
	_label.outline_modulate = Color("1c1b26")
	add_child(_label)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)
