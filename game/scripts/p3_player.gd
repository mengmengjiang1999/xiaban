extends "res://scripts/p2_player.gd"
## Gameplay state owns displacement; the imported skeleton owns only the pose.
const StanceCollision = preload("res://scripts/stance_collision.gd")
signal sprint_noise_emitted(origin: Vector3, radius: float)

@export var standing_height := 1.80
@export var crouch_height := 1.05
@export var body_radius := 0.35
@export var crouch_speed := 0.75
@export var sprint_speed := 3.8
@export var roll_distance := 2.4
@export var roll_duration := 0.85
@export var roll_recovery := 0.20
@export var sprint_noise_radius := 8.0
@export var sprint_step_interval := 0.31
# Union of actual skinned Roll bounds (121 samples), rounded outwards.
const ROLL_CLEARANCE := Vector3(1.06, 1.55, 2.20)
const STANCE_BLEND_TIME := 0.15
var collider: CollisionShape3D
var stance := "standing"
var action_state := "idle"
var stand_blocked := false
var roll_blocked := false
var _roll_time := 0.0
var _roll_direction := Vector3.FORWARD
var _roll_heading := 0.0
var _roll_stopped := false
var _recovery_remaining := 0.0
var _stance_transition := 0.0
var _noise_count := 0
var _step_remaining := 0.0
var _feedback := ""
var _feedback_remaining := 0.0
var _footstep: AudioStreamPlayer3D
var _roll_shape: BoxShape3D

func _ready() -> void:
	super._ready()
	collision_mask = 1 | 8 # Architecture and future NPC bodies.
	for child in get_children():
		if child is CollisionShape3D:
			collider = child
	StanceCollision.apply_capsule(collider, standing_height, body_radius)
	actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_roll_shape = BoxShape3D.new()
	_roll_shape.size = ROLL_CLEARANCE
	_create_footstep()

func _physics_process(delta: float) -> void:
	if _world == null or _world.phase != "playing":
		stop_input()
		return
	actor.set_paused(false)
	_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	if action_state == "roll":
		_update_roll(delta)
		return
	if action_state == "recovery":
		_recovery_remaining = maxf(0.0, _recovery_remaining - delta)
		move_input = 0.0
		turn_input = 0.0
		_settle_ground(delta)
		if _recovery_remaining <= 0.0:
			action_state = "crouch_idle"
		return
	if _stance_transition > 0.0:
		_stance_transition = maxf(0.0, _stance_transition - delta)
		move_input = 0.0
		turn_input = 0.0
		_settle_ground(delta)
		if _stance_transition <= 0.0:
			StanceCollision.apply_capsule(collider, crouch_height if stance == "crouched" else standing_height, body_radius)
		return
	move_input = Input.get_axis("move_back", "move_forward")
	turn_input = Input.get_axis("turn_right", "turn_left")
	rotation.y = wrapf(rotation.y + turn_input * turn_speed * delta, -PI, PI)
	var sprinting := stance == "standing" and move_input > 0.0 and Input.is_action_pressed("sprint")
	var speed: float = crouch_speed if stance == "crouched" else (sprint_speed if sprinting else walk_speed)
	var movement := -global_basis.z * move_input * speed
	velocity.x = movement.x
	velocity.z = movement.z
	velocity.y = -0.1 if is_on_floor() else velocity.y - 20.0 * delta
	var before := global_position
	move_and_slide()
	var distance := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	travel_distance += distance
	var actual_speed := distance / delta
	var moving := actual_speed > 0.05 and absf(move_input) > 0.01
	if stance == "crouched":
		action_state = "crouch_walk" if moving else "crouch_idle"
		actor.play_action(action_state, signf(move_input) * actual_speed / 0.72 if moving else 1.0)
	else:
		action_state = ("sprint" if sprinting else "walk") if moving else "idle"
		actor.play_action("run" if action_state == "sprint" else action_state,
			(actual_speed / 3.8 if sprinting else signf(move_input) * actual_speed / 1.08) if moving else 1.0)
	if action_state == "sprint":
		# Match both the pose and footfalls to actual sliding distance at obstacles.
		_step_remaining -= distance / sprint_speed
		if _step_remaining <= 0.0:
			_step_remaining = sprint_step_interval
			_noise_count += 1
			sprint_noise_emitted.emit(global_position, sprint_noise_radius)
			_footstep.play()
	else:
		_step_remaining = 0.0

func request_crouch_toggle() -> bool:
	if not _can_request_action():
		return false
	stand_blocked = false
	roll_blocked = false
	if stance == "crouched":
		if not StanceCollision.can_occupy(self, standing_height, body_radius):
			stand_blocked = true
			_notice("上方或身侧空间不足，保持蹲姿")
			return false
		stance = "standing"
		StanceCollision.apply_capsule(collider, standing_height, body_radius)
		action_state = "idle"
	else:
		stance = "crouched"
		action_state = "crouch_idle"
	# Retain the tall collision until the body has finished folding down.
	_stance_transition = STANCE_BLEND_TIME
	velocity = Vector3.ZERO
	actor.play_action(action_state)
	return true

func request_roll() -> bool:
	if not _can_request_action():
		return false
	if stance != "crouched":
		_notice("先按 C 蹲下，再按 Space 翻滚")
		return false
	roll_blocked = not _roll_space_clear()
	if roll_blocked:
		_notice("翻滚空间不足，先离开障碍物")
		return false
	stand_blocked = false
	action_state = "roll"
	_roll_time = 0.0
	_roll_stopped = false
	_roll_heading = rotation.y
	_roll_direction = -global_basis.z.normalized()
	velocity = Vector3.ZERO
	move_input = 0.0
	turn_input = 0.0
	actor.play_action("roll", actor.action_length("roll") / roll_duration, true, false, 0.06)
	return true

func _can_request_action() -> bool:
	return _world != null and _world.phase == "playing" and not action_state in ["roll", "recovery"] and _stance_transition <= 0.0 and is_on_floor()

func _roll_query(motion: Vector3 = Vector3.ZERO) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _roll_shape
	query.transform = global_transform.orthonormalized() * Transform3D(Basis.IDENTITY, Vector3(0, ROLL_CLEARANCE.y * 0.5 + 0.015, 0))
	query.motion = motion
	query.margin = 0.008
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return query

func _roll_space_clear() -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_roll_query(), 1).is_empty()

func _update_roll(delta: float) -> void:
	rotation.y = _roll_heading
	move_input = 0.0
	turn_input = 0.0
	var previous := _roll_time / roll_duration
	_roll_time = minf(roll_duration, _roll_time + delta)
	var current := _roll_time / roll_duration
	if not _roll_stopped and not _roll_space_clear():
		_stop_roll_motion()
	# Arbitrary blends out of an inverted pose can put the head below the floor.
	# On impact, finish the already clearance-checked clip in place, then recover.
	if _roll_stopped:
		_settle_ground(delta)
		if _roll_time >= roll_duration:
			_finish_roll()
		return
	# Integrating the cumulative curve keeps total travel equal at 30/60/120 Hz.
	var step := roll_distance * (cos(PI * previous) - cos(PI * current)) * 0.5
	var motion := _roll_direction * step
	var sweep := get_world_3d().direct_space_state.cast_motion(_roll_query(motion))
	var fraction: float = sweep[0]
	var before := global_position
	var collision := move_and_collide(motion * maxf(0.0, fraction - (0.003 / maxf(step, 0.003) if fraction < 1.0 else 0.0)))
	travel_distance += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_settle_ground(delta)
	if fraction < 1.0 or collision != null:
		_stop_roll_motion()
	if _roll_time >= roll_duration:
		_finish_roll()

func _stop_roll_motion() -> void:
	_roll_stopped = true
	velocity = Vector3.ZERO
	_notice("前方受阻，原地完成翻滚")

func _finish_roll() -> void:
	action_state = "recovery"
	_recovery_remaining = roll_recovery
	velocity = Vector3.ZERO
	actor.play_action("crouch_idle", 1.0, true, true, 0.08)

func _settle_ground(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -0.1 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()

func stop_input() -> void:
	super.stop_input()
	if _footstep != null:
		_footstep.stop()

func reset_player(at: Vector3, heading: float = 0.0) -> void:
	super.reset_player(at, heading)
	stance = "standing"
	action_state = "idle"
	stand_blocked = false
	roll_blocked = false
	_roll_time = 0.0
	_roll_stopped = false
	_recovery_remaining = 0.0
	_stance_transition = 0.0
	_step_remaining = 0.0
	_noise_count = 0
	_feedback_remaining = 0.0
	if collider != null:
		StanceCollision.apply_capsule(collider, standing_height, body_radius)

func cancel_action() -> void:
	# Menu/completion clears a one-shot without forcing a blocked stand-up.
	_roll_time = 0.0
	_roll_stopped = false
	_recovery_remaining = 0.0
	_stance_transition = 0.0
	action_state = "crouch_idle" if stance == "crouched" else "idle"
	StanceCollision.apply_capsule(collider, crouch_height if stance == "crouched" else standing_height, body_radius)
	actor.play_action(action_state, 1.0, true)
	stop_input()

func get_detection_points() -> Array[Vector3]:
	return [actor.bone_world_position("head"), actor.bone_world_position("spine_03")]

func get_control_status() -> Dictionary:
	return {"stance": stance, "state": action_state, "stand_blocked": stand_blocked,
		"roll_blocked": roll_blocked, "roll_stopped": _roll_stopped, "roll_progress": _roll_time / roll_duration,
		"roll_remaining": maxf(0.0, roll_duration - _roll_time) if action_state == "roll" else 0.0,
		"recovery_remaining": _recovery_remaining, "noise_count": _noise_count,
		"collider_height": collider.shape.height, "transition_remaining": _stance_transition,
		"feedback": _feedback if _feedback_remaining > 0.0 else "",
		"animation_status": get_animation_status()}

func _notice(message: String) -> void:
	_feedback = message
	_feedback_remaining = 2.0

func _create_footstep() -> void:
	# Short original synthesized shoe thump; no external audio asset or AI listener.
	var pcm := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var filtered := 0.0
	for index in range(5292):
		var time := float(index) / 44100.0
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.18)
		var sample := (sin(TAU * 95.0 * time) * 0.45 + filtered * 0.55) * exp(-time * 48.0) * minf(time * 500.0, 1.0)
		var value := int(clampf(sample * 16000.0, -32767, 32767))
		pcm.append(value & 255)
		pcm.append((value >> 8) & 255)
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 44100
	sound.data = pcm
	_footstep = AudioStreamPlayer3D.new()
	_footstep.stream = sound
	_footstep.volume_db = -5.0
	_footstep.max_distance = 20.0
	add_child(_footstep)
