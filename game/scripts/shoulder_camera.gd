class_name ShoulderCamera
extends Node3D
## Stable right-shoulder camera. The controller owns all input and update timing.
## These values are prototype tuning, not final art/camera specifications.

var camera: Camera3D
var observing: bool = false
var desired_distance: float = 4.8
var yaw: float = 0.0

var default_distance: float = 4.8
var min_distance: float = 1.8
var max_distance: float = 7.0
var zoom_step: float = 0.4
var mouse_sensitivity: float = 0.004
var anchor_height: float = 1.3
var shoulder_offset: float = 0.65
var pitch_degrees: float = 14.0
var auto_recenter_speed: float = 6.0
var quick_recenter_speed: float = 22.0
var obstruction_recovery_speed: float = 7.0
var obstruction_contraction_speed: float = 10.0
var max_boom_speed: float = 10.0
var collision_lookahead: float = 0.4
var collision_prediction_samples: int = 8
var camera_radius: float = 0.22
var collision_margin: float = 0.035
var obstacle_mask: int = 3

var _target: Node3D
var _sphere := SphereShape3D.new()
var _excluded: Array[RID] = []
var _has_move_input: bool = false
var _has_turn_input: bool = false
var _last_target_yaw: float = 0.0
var _auto_recentering: bool = false
var _quick_recentering: bool = false
var _resolved_length: float = 4.85
var _last_camera_yaw: float = 0.0
var _has_turn_speed: bool = false
var _orbit_prediction_rate: float = 0.0


func setup(target: Node3D) -> void:
	_target = target
	_ensure_camera()
	_excluded.clear()
	_collect_exclusions(target)
	_has_move_input = false
	_has_turn_input = false
	_has_turn_speed = false
	for property in target.get_property_list():
		if property.name == "move_input":
			_has_move_input = true
		elif property.name == "turn_input":
			_has_turn_input = true
		elif property.name == "turn_speed":
			_has_turn_speed = true
	reset_camera()


func update_camera(delta: float, snap: bool = false) -> void:
	if not is_instance_valid(_target) or not is_inside_tree():
		return
	_ensure_camera()
	var target_yaw := _target.global_rotation.y
	var turn_rate := 0.0
	if _has_turn_input and _has_turn_speed:
		turn_rate = float(_target.get("turn_input")) * float(_target.get("turn_speed"))
	var is_moving: bool = _has_move_input and absf(float(_target.get("move_input"))) > 0.001
	var is_turning: bool = _has_turn_input and absf(float(_target.get("turn_input"))) > 0.001
	var heading_changed := absf(angle_difference(_last_target_yaw, target_yaw)) > 0.0001
	_last_target_yaw = target_yaw
	if not observing and (is_moving or is_turning or heading_changed):
		_auto_recentering = true
	if _quick_recentering or (not observing and _auto_recentering):
		var speed := quick_recenter_speed if _quick_recentering else auto_recenter_speed
		yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-speed * maxf(delta, 0.0)))
		if absf(angle_difference(yaw, target_yaw)) < 0.001:
			yaw = target_yaw
			_quick_recentering = false
			_auto_recentering = false
	yaw = wrapf(yaw, -PI, PI)

	# Camera orientation ignores visual pose and movement direction. Velocity is
	# used only to anticipate obstructions, never to turn the view when backing up.
	var anchor := _target.global_position + Vector3.UP * anchor_height
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var pitch := deg_to_rad(pitch_degrees)
	var backward := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)
	_sphere.radius = camera_radius

	# Sweep the complete offset from the anchor. Starting the boom at a shoulder
	# already touching a wall makes near-parallel angles jump between distant hits.
	var desired_offset := right * shoulder_offset + backward * desired_distance
	var safe_offset := _safe_motion(anchor, desired_offset)
	var current_limit := safe_offset.length()
	# Prediction changes only the allowed distance; mouse/turn input stays immediate.
	var angular_velocity := clampf(angle_difference(_last_camera_yaw, yaw) / maxf(delta, 0.0001), -4.0, 4.0)
	_orbit_prediction_rate = lerpf(_orbit_prediction_rate, angular_velocity if observing else 0.0, 1.0 - exp(-20.0 * maxf(delta, 0.0)))
	# Read physics velocity/input directly: render frames may share one physics tick.
	var planar_velocity := Vector3.ZERO
	if _target is CharacterBody3D:
		planar_velocity = (_target as CharacterBody3D).velocity
		planar_velocity.y = 0.0
	var future_limit := current_limit
	if not snap:
		for sample_index in range(1, collision_prediction_samples + 1):
			var ahead := collision_lookahead * float(sample_index) / float(collision_prediction_samples)
			var future_anchor := anchor + planar_velocity.rotated(Vector3.UP, turn_rate * ahead * 0.5) * ahead
			var future_yaw := yaw + _orbit_prediction_rate * ahead
			if _quick_recentering or (not observing and _auto_recentering):
				var speed := quick_recenter_speed if _quick_recentering else auto_recenter_speed
				future_yaw = target_yaw + turn_rate * ahead - turn_rate / speed + (angle_difference(target_yaw, yaw) + turn_rate / speed) * exp(-speed * ahead)
			var future_right := Vector3.RIGHT.rotated(Vector3.UP, future_yaw)
			var future_backward := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, future_yaw)
			var future_offset := future_right * shoulder_offset + future_backward * desired_distance
			future_limit = minf(future_limit, _safe_motion(future_anchor, future_offset).length())
	if snap:
		_resolved_length = current_limit
	else:
		var smoothing_speed := obstruction_contraction_speed if future_limit < _resolved_length else obstruction_recovery_speed
		var softened := lerpf(_resolved_length, future_limit, 1.0 - exp(-smoothing_speed * maxf(delta, 0.0)))
		_resolved_length = move_toward(_resolved_length, softened, max_boom_speed * maxf(delta, 0.0))
		# Anticipation softens approach, but current geometry always wins over smoothing.
		_resolved_length = minf(_resolved_length, current_limit)
	var resolved_offset := desired_offset.normalized() * _resolved_length
	resolved_offset = _safe_motion(anchor, resolved_offset)
	_last_camera_yaw = yaw
	camera.global_position = anchor + resolved_offset
	camera.global_rotation = Vector3(-pitch, yaw, 0.0)
	# Tight corners may bring the camera beside the capsule. Fade only the
	# character's appearance so safe camera compression does not block the view.
	if _target.has_method("set_camera_alpha"):
		var visibility := lerpf(0.12, 1.0, smoothstep(0.5, 1.35, resolved_offset.length()))
		_target.set_camera_alpha(visibility)


func orbit(relative_x: float) -> void:
	# Vertical-only motion is not an orbit command and must not cancel F.
	if not observing or is_zero_approx(relative_x):
		return
	yaw = wrapf(yaw - relative_x * mouse_sensitivity, -PI, PI)
	_auto_recentering = false
	_quick_recentering = false


func set_observing(value: bool) -> void:
	observing = value
	if observing:
		_auto_recentering = false
		_quick_recentering = false


func zoom(steps: float) -> void:
	# A positive wheel step (wheel up) moves closer without changing orientation.
	desired_distance = clampf(desired_distance - steps * zoom_step, min_distance, max_distance)


func recenter() -> void:
	# F also works while stationary and does not change the user's chosen zoom.
	_quick_recentering = true
	_auto_recentering = false


func reset_camera() -> void:
	observing = false
	_orbit_prediction_rate = 0.0
	_auto_recentering = false
	_quick_recentering = false
	desired_distance = clampf(default_distance, min_distance, max_distance)
	if is_instance_valid(_target):
		yaw = _target.global_rotation.y
		_last_target_yaw = yaw
		_last_camera_yaw = yaw
	_resolved_length = sqrt(shoulder_offset * shoulder_offset + desired_distance * desired_distance)
	update_camera(0.0, true)


func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "RightShoulderCamera"
	camera.fov = 68.0
	camera.near = 0.07
	camera.far = 100.0
	add_child(camera)
	camera.current = true


func _safe_motion(origin: Vector3, motion: Vector3) -> Vector3:
	var length := motion.length()
	if length < 0.00001:
		return Vector3.ZERO
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = motion
	query.collision_mask = obstacle_mask
	query.exclude = _excluded
	query.margin = collision_margin
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space := get_world_3d().direct_space_state
	# cast_motion ignores shapes overlapping its starting point. In particular,
	# a future anchor inside a wall must not report the entire boom as clear.
	if not space.intersect_shape(query, 1).is_empty():
		return Vector3.ZERO
	var fractions := space.cast_motion(query)
	if fractions.is_empty():
		return motion
	# The engine returns a nonpenetrating fraction for the whole sphere. A tiny
	# extra clearance prevents touching surfaces from alternating across frames.
	var safe_length := length * fractions[0]
	if fractions[0] < 1.0:
		safe_length = maxf(0.0, safe_length - 0.005)
	return motion * (safe_length / length)


func _collect_exclusions(node: Node) -> void:
	if node is CollisionObject3D:
		_excluded.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_exclusions(child)
