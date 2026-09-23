extends CharacterBody3D
## A fixed office observer. Timings are prototype tuning, not an omniscient AI.
const Humanoid = preload("res://scripts/humanoid_actor.gd")
const GuardVisual = preload("res://scripts/p4_guard_visual.gd")
# Stable presentation samples bound the source rig's head/chest animation
# envelopes. They are deliberately conservative, not a per-frame safe-zone
# mask. release_guard_cue_test checks all six clips against these bounds.
# Actual detection below continues to use the exact animated bone positions.
const CUE_HEIGHTS := {
	"standing": [1.60, 0.98],
	"crouched": [0.81, 0.64],
	"roll": [1.32, 0.07],
	"transition": [1.60, 0.64],
}
signal discovered(guard: Node)

@export var guard_id := "leader_1"
@export var display_name := "工位领导"
@export var shirt_color := Color(0.49, 0.32, 0.20)
@export var routine_watch_offset := 0.0
# Initial elapsed time in the first work phase; reset repeats this offset.
# Later cycles always use the full work_duration.
@export var phase_offset := 0.0
# Offset within the 150 ms guide refresh grid. Detection is never staggered.
@export_range(0.0, 0.149, 0.001) var cue_refresh_offset := 0.0
@export var work_duration := 4.0
@export var raise_duration := 0.7
@export var watch_duration := 2.2
@export var lower_duration := 0.5
@export var noise_watch_duration := 2.0
@export var confirm_duration := 0.35
@export var vision_range := 7.5
@export var vision_fov_degrees := 100.0
@export_flags_3d_physics var vision_mask := 16 | 8
var actor: Node3D
var state := "working"
var progress := 0.0
var _world: Node
var _spawn := Vector3.ZERO
var _work_heading := 0.0
var _watch_heading := 0.0
var _start_heading := 0.0
var _current_lift := 0.0
var _raise_start_lift := 0.0
var _state_time := 0.0
var _visual_time := 0.0
var _cue_time := 0.0
var _visible_time := 0.0
var _frozen := true
var _confirmed := false
var _noise_attention := false
var _heard_origin: Variant = null
var _pose: Node3D
var _fan: MeshInstance3D
var _fan_material: StandardMaterial3D
var _fan_refresh := 0.0
var _fan_vertices := PackedVector3Array()
var _fan_revision := 0
var _fan_refresh_count := 0
var _cue_height_profile := "standing"
var _label: Label3D

func setup(world: Node, spawn: Vector3, work_heading: float) -> void:
	_world = world
	_spawn = spawn
	_work_heading = work_heading

func _ready() -> void:
	name = "OfficeGuard_%s" % guard_id
	collision_layer = 8
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.80
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.90
	add_child(collider)
	actor = Humanoid.new()
	add_child(actor)
	actor.animation_player.seek(0.0, true)
	actor.set_paused(true)
	for material in actor.materials:
		if material.resource_name == "PlainTealCotton":
			material.albedo_color = shirt_color
	_pose = GuardVisual.new()
	add_child(_pose)
	_pose.setup(actor)
	_create_indicator()
	reset_guard()

func reset_guard() -> void:
	position = _spawn
	rotation.y = _work_heading
	_watch_heading = _work_heading + routine_watch_offset
	_start_heading = _work_heading
	_current_lift = 0.0
	_raise_start_lift = 0.0
	state = "working"
	_state_time = clampf(phase_offset, 0.0, maxf(0.0, work_duration - 0.001))
	_visual_time = _state_time
	_cue_time = 0.0
	_visible_time = 0.0
	progress = 0.0
	_confirmed = false
	_noise_attention = false
	_heard_origin = null
	velocity = Vector3.ZERO
	_fan_refresh = 0.0
	if is_instance_valid(_pose):
		_update_visual()

func set_frozen(value: bool) -> void:
	_frozen = value
	# The visual is posed explicitly by the same clock as the observer.
	if is_instance_valid(actor):
		actor.set_paused(true)

func _physics_process(delta: float) -> void:
	if _frozen or _world == null or _world.phase != "playing" or _confirmed:
		return
	_visual_time += delta
	_cue_time += delta
	_state_time += delta
	match state:
		"working":
			if _state_time >= maxf(0.001, work_duration):
				_begin_raise(_work_heading + routine_watch_offset, false)
		"raising":
			if _state_time >= maxf(0.001, raise_duration):
				_enter_state("watching")
		"watching":
			if _state_time >= _watch_length():
				_start_heading = rotation.y
				_enter_state("lowering")
		"lowering":
			if _state_time >= maxf(0.001, lower_duration):
				_noise_attention = false
				_enter_state("working")
	_update_visual()
	if state == "watching":
		var player_visible := can_see_player()
		# A sight change must not wait out the coarse cue's 150 ms refresh.
		# Rebuild on this tick; the cue remains a sampled guide, not a safe zone.
		if player_visible != (_visible_time > 0.0):
			_fan_refresh = 0.0
		_visible_time = _visible_time + delta if player_visible else 0.0
		progress = clampf(_visible_time / maxf(0.001, confirm_duration), 0.0, 1.0)
		if progress >= 1.0:
			_confirmed = true
			_update_indicator()
			discovered.emit(self)
	else:
		_visible_time = 0.0
		progress = 0.0
	_fan_refresh -= delta
	# Stance/roll changes update immediately, while breathing and footsteps
	# cannot make the sampled geometry oscillate at the 150 ms refresh rate.
	if _get_cue_height_profile() != _cue_height_profile:
		_fan_refresh = 0.0
	if state == "watching" and _fan_refresh <= 0.0:
		# First observation and visibility changes rebuild immediately. Only
		# subsequent sampled guide refreshes use the configured time grid.
		_fan_refresh = maxf(0.001, 0.15 - fposmod(_cue_time - cue_refresh_offset, 0.15))
		_rebuild_fan()
	_update_indicator()

func _enter_state(next: String) -> void:
	state = next
	_state_time = 0.0
	_visible_time = 0.0
	progress = 0.0
	_fan_refresh = 0.0

func _begin_raise(heading: float, from_noise: bool) -> void:
	_raise_start_lift = _current_lift
	_start_heading = rotation.y
	_watch_heading = heading
	_noise_attention = from_noise
	_enter_state("raising")

func receive_noise(origin: Vector3, radius: float) -> void:
	if _frozen or _world == null or _world.phase != "playing" or _confirmed:
		return
	if radius <= 0.0 or global_position.distance_to(origin) > radius:
		return
	# One recorded source owns a reaction. Repeated footfalls cannot restart
	# its telegraph timer, or turn the observer into a live player tracker.
	if state in ["raising", "watching"]:
		return
	_heard_origin = origin
	var direction := origin - global_position
	direction.y = 0.0
	var heading := rotation.y if direction.length_squared() < 0.0001 else atan2(-direction.x, -direction.z)
	_begin_raise(heading, true)

func eye_position() -> Vector3:
	if not is_instance_valid(actor):
		return global_position + Vector3.UP * 1.62
	# Head joint is at the base of the skull; eyes are a little above/front.
	return actor.bone_world_position("head") + global_basis * Vector3(0, 0.075, -0.055)

func can_see_player() -> bool:
	if _frozen or _world == null or _world.phase != "playing" or state != "watching":
		return false
	if not is_instance_valid(_world.player):
		return false
	var eye := eye_position()
	for point in _world.player.get_detection_points():
		if _point_in_view(point, eye) and _ray_clear(eye, point):
			return true
	return false

func _point_in_view(point: Vector3, eye: Vector3) -> bool:
	var offset := point - eye
	if offset.length() > vision_range:
		return false
	var horizontal := Vector3(offset.x, 0, offset.z)
	if horizontal.length_squared() < 0.0001:
		return true
	var forward := -global_basis.z
	return forward.dot(horizontal.normalized()) >= cos(deg_to_rad(vision_fov_degrees * 0.5))

func _ray_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, vision_mask)
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(_world.player) and _world.player is CollisionObject3D:
		excluded.append(_world.player.get_rid())
	query.exclude = excluded
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _watch_length() -> float:
	return maxf(0.001, noise_watch_duration if _noise_attention else watch_duration)

func _state_length() -> float:
	match state:
		"working": return maxf(0.001, work_duration)
		"raising": return maxf(0.001, raise_duration)
		"watching": return _watch_length()
		"lowering": return maxf(0.001, lower_duration)
	return 0.0

func _update_visual() -> void:
	var lift := 0.0
	match state:
		"raising":
			var amount := smoothstep(0.0, 1.0, _state_time / maxf(0.001, raise_duration))
			lift = lerpf(_raise_start_lift, 1.0, amount)
			rotation.y = lerp_angle(_start_heading, _watch_heading, amount)
		"watching":
			lift = 1.0
			rotation.y = _watch_heading
		"lowering":
			var amount := smoothstep(0.0, 1.0, _state_time / maxf(0.001, lower_duration))
			lift = 1.0 - amount
			rotation.y = lerp_angle(_start_heading, _work_heading, amount)
		"working":
			rotation.y = _work_heading
	_current_lift = lift
	_pose.apply_pose(lift, _visual_time)
	_update_indicator()

func _create_indicator() -> void:
	_fan = MeshInstance3D.new()
	_fan.name = "ActiveVisionCue"
	_fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fan_material = StandardMaterial3D.new()
	_fan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fan_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fan_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fan_material.albedo_color = Color(1, 0.64, 0.16, 0.20)
	_fan.material_override = _fan_material
	add_child(_fan)
	_label = Label3D.new()
	_label.name = "GuardActionCue"
	_label.font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	_label.font_size = 26
	_label.pixel_size = 0.005
	_label.position.y = 2.12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.modulate = Color(1.0, 0.80, 0.43)
	_label.outline_size = 7
	_label.visibility_range_end = 14.0
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_label)

func _update_indicator() -> void:
	if not is_instance_valid(_fan):
		return
	_fan.visible = state == "watching"
	_fan_material.albedo_color = Color(1, 0.64, 0.16, 0.20).lerp(Color(1, 0.15, 0.08, 0.35), progress)
	var action_text := ""
	match state:
		"working": action_text = "办公中"
		"raising": action_text = "听到脚步" if _noise_attention else "正在抬头"
		"watching": action_text = "发现 %d%%" % roundi(progress * 100) if progress > 0 else ("查看声源" if _noise_attention else "正在观察")
		"lowering": action_text = "回到工作"
	var text := "%s\n%s" % [display_name, action_text]
	if _label.text != text:
		_label.text = text

func _get_cue_height_profile() -> String:
	if _world == null or not is_instance_valid(_world.player) or not _world.player.has_method("get_control_status"):
		return "standing"
	var control: Dictionary = _world.player.get_control_status()
	if float(control.get("transition_remaining", 0.0)) > 0.0:
		return "transition"
	if control.get("state", "") in ["roll", "recovery"]:
		return "roll"
	return "crouched" if control.get("stance", "standing") == "crouched" else "standing"

func _cue_column_visible(point: Vector3, eye: Vector3, heights: Array) -> bool:
	# Test a whole stable vertical envelope, not just isolated heights. A thin
	# opening between sampled rays must be marked as potentially visible.
	var horizontal := Vector3(point.x, eye.y, point.z)
	if not _point_in_view(horizontal, eye):
		return false
	var vertical_limit := sqrt(maxf(0.0, vision_range * vision_range - eye.distance_squared_to(horizontal)))
	var eye_height := eye.y - global_position.y
	var low := maxf(float(heights.min()), eye_height - vertical_limit)
	var high := minf(float(heights.max()), eye_height + vertical_limit)
	if low > high:
		return false
	var previous := {}
	var previous_height := INF
	# At most two physical rays per cell, independent of animation complexity.
	for sample in [high, low]:
		var height := clampf(float(sample), low, high)
		if is_equal_approx(height, previous_height):
			continue
		previous_height = height
		var query := PhysicsRayQueryParameters3D.create(eye,
			Vector3(point.x, global_position.y + height, point.z), vision_mask)
		query.exclude = [get_rid(), _world.player.get_rid()] if _world.player is CollisionObject3D else [get_rid()]
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return true
		if not previous.is_empty():
			# The shadow of one convex shape covers every ray between these
			# endpoints. Different shapes cannot prove that the gap is closed.
			if hit.rid != previous.rid or hit.shape != previous.shape or not _cue_hit_is_convex(hit):
				return true
		previous = hit
	return false

func _cue_hit_is_convex(hit: Dictionary) -> bool:
	var collider: CollisionObject3D = hit.collider as CollisionObject3D
	if collider == null:
		return false
	var owner := collider.shape_owner_get_owner(collider.shape_find_owner(int(hit.shape)))
	if not owner is CollisionShape3D:
		return false
	var shape: Shape3D = owner.shape
	return shape is BoxShape3D or shape is CapsuleShape3D or shape is SphereShape3D or shape is CylinderShape3D or shape is ConvexPolygonShape3D

func _rebuild_fan() -> void:
	# A deliberately coarse ground cue, clipped against the same 3D blockers
	# using a fixed pose envelope. Sampling the current animation frame here
	# caused stationary breathing to toggle whole cells behind cover. Exact
	# animated head/chest rays still own discovery, never this guide mesh.
	_cue_height_profile = _get_cue_height_profile()
	var target_heights: Array = CUE_HEIGHTS[_cue_height_profile]
	_fan_refresh_count += 1
	var eye := eye_position()
	var vertices := PackedVector3Array()
	const ANGLES := 28
	const RINGS := 15
	var half_angle := deg_to_rad(vision_fov_degrees * 0.5)
	for angle_index in ANGLES:
		var a0 := lerpf(-half_angle, half_angle, float(angle_index) / ANGLES)
		var a1 := lerpf(-half_angle, half_angle, float(angle_index + 1) / ANGLES)
		for ring in RINGS:
			var r0 := maxf(0.40, vision_range * ring / RINGS)
			var r1 := vision_range * (ring + 1) / RINGS
			if r1 <= r0:
				continue
			var center := Vector3.FORWARD.rotated(Vector3.UP, (a0 + a1) * 0.5) * ((r0 + r1) * 0.5)
			var point := to_global(center)
			if not _cue_column_visible(point, eye, target_heights):
				continue
			var p0 := Vector3.FORWARD.rotated(Vector3.UP, a0) * r0 + Vector3.UP * 0.026
			var p1 := Vector3.FORWARD.rotated(Vector3.UP, a1) * r0 + Vector3.UP * 0.026
			var p2 := Vector3.FORWARD.rotated(Vector3.UP, a0) * r1 + Vector3.UP * 0.026
			var p3 := Vector3.FORWARD.rotated(Vector3.UP, a1) * r1 + Vector3.UP * 0.026
			vertices.append_array(PackedVector3Array([p0, p1, p2, p2, p1, p3]))
	# Do not replace the GPU mesh for an unchanged guide. Moving blockers can
	# still change it on the next sample, and posture changes sample at once.
	if vertices == _fan_vertices and _fan.mesh != null:
		return
	_fan_vertices = vertices
	_fan_revision += 1
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_fan.mesh = mesh

func get_status() -> Dictionary:
	var facing := -global_basis.z
	var eye := eye_position()
	var head: Vector3 = actor.bone_world_position("head") if is_instance_valid(actor) else eye
	return {
		"guard_id": guard_id, "display_name": display_name,
		"state": state, "progress": progress, "confirmed": _confirmed, "detected": _confirmed,
		"noise_attention": _noise_attention, "frozen": _frozen,
		"position": [global_position.x, global_position.y, global_position.z],
		"facing": [facing.x, facing.y, facing.z],
		"state_time": _state_time, "remaining": maxf(0.0, _state_length() - _state_time),
		"eye_position": [eye.x, eye.y, eye.z], "head_position": [head.x, head.y, head.z],
		"visual_time": _visual_time,
		"work_heading": _work_heading, "watch_heading": _watch_heading,
		"routine_watch_offset": routine_watch_offset, "phase_offset": phase_offset,
		"work_duration": work_duration, "raise_duration": raise_duration,
		"watch_duration": watch_duration, "lower_duration": lower_duration,
		"noise_watch_duration": noise_watch_duration, "confirm_duration": confirm_duration,
		"vision_range": vision_range, "vision_fov_degrees": vision_fov_degrees,
		"cue_refresh_offset": cue_refresh_offset,
		"cue_height_profile": _cue_height_profile,
		"fan_revision": _fan_revision, "fan_refresh_count": _fan_refresh_count,
		"fan_vertex_count": _fan_vertices.size(),
		"heard_origin": [_heard_origin.x, _heard_origin.y, _heard_origin.z] if _heard_origin is Vector3 else null,
		"fan_visible": is_instance_valid(_fan) and _fan.visible,
	}
