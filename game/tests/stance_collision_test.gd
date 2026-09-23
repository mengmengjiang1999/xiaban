extends SceneTree
## Headless integration checks against Godot's actual 3D physics space.
const StanceCollision := preload("res://scripts/stance_collision.gd")
const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.05
const RADIUS := 0.35
var _passed := 0
var _failed := 0
var _player: CharacterBody3D
var _collider: CollisionShape3D
var _fixtures: Array[Node3D] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_player = CharacterBody3D.new()
	_player.collision_layer = 4
	_player.collision_mask = 1 | 8
	_collider = CollisionShape3D.new()
	StanceCollision.apply_capsule(_collider, CROUCH_HEIGHT, RADIUS)
	_player.add_child(_collider)
	root.add_child(_player)
	await _physics_frames()
	_check(_can_stand(), "Empty space permits the complete standing capsule")
	_player.collision_mask |= 4
	_check(_can_stand(), "The player's own body is excluded even when its layer is in the mask")
	_player.collision_mask = 1 | 8
	_box(Vector3(0, -0.25, 0), Vector3(20, 0.5, 20))
	await _physics_frames()
	_check(_can_stand(), "A floor touching the feet does not prevent standing")
	_player.position.y = -0.0005
	await _physics_frames()
	_check(_can_stand(), "Sub-millimeter contact recovery tolerance does not mistake the floor for a ceiling")
	_player.position.y = 0.0
	var ceiling := _box(Vector3(0, 1.3, 0), Vector3(4, 0.2, 4))
	await _physics_frames()
	_check(not _can_stand(), "A low ceiling on the same layer as the floor blocks standing")
	_check(StanceCollision.can_occupy(_player, CROUCH_HEIGHT, RADIUS), "The actual crouched capsule fits below that ceiling")
	_player.position.x = 3.0
	await _physics_frames()
	_check(_can_stand(), "Leaving the low ceiling permits standing again")
	_player.position.x = 0.0
	ceiling.queue_free()
	await _physics_frames()
	# This thin overhang misses a vertical ray through the actor's center but
	# intersects the standing capsule's upper side.
	var overhang := _box(Vector3(0.31, 1.38, 0), Vector3(0.14, 0.18, 0.7))
	await _physics_frames()
	_check(not _can_stand(), "A side overhang blocks the full target volume even with a clear center ray")
	_check(StanceCollision.can_occupy(_player, CROUCH_HEIGHT, RADIUS), "A crouched actor can remain beneath the side overhang")
	overhang.queue_free()
	await _physics_frames()
	var upper_wall := _box(Vector3(0.420, 1.05, 0), Vector3(0.1, 0.3, 1))
	await _physics_frames()
	_check(_can_stand(), "A wall outside the chosen side clearance permits standing")
	upper_wall.position.x = 0.408
	await _physics_frames()
	_check(not _can_stand(), "The side clearance catches a nearby wall before physical penetration")
	_check(StanceCollision.can_occupy(_player, STAND_HEIGHT, RADIUS, 0.0), "Zero clearance can fit the same physically non-overlapping capsule")
	upper_wall.queue_free()
	await _physics_frames()
	var near_ceiling := _box(Vector3(0, 1.81, 0), Vector3(1, 0.1, 1))
	await _physics_frames()
	_check(not _can_stand(), "The top clearance reserves room beneath a ceiling within 15 millimeters")
	_check(StanceCollision.can_occupy(_player, STAND_HEIGHT, RADIUS, 0.0), "Zero clearance still permits a genuine ten-millimeter head gap")
	near_ceiling.queue_free()
	await _physics_frames()
	# A small obstacle near the lower hemisphere verifies the exact-radius pass
	# rather than just headroom or the raised clearance shape.
	var foot_obstacle := _box(Vector3(0.30, 0.18, 0), Vector3(0.06, 0.06, 0.2))
	await _physics_frames()
	_check(not _can_stand(), "An obstacle intersecting the lower capsule also blocks occupancy")
	foot_obstacle.queue_free()
	await _physics_frames()
	var other := CharacterBody3D.new()
	other.collision_layer = 8
	other.collision_mask = 1 | 4
	var other_shape := CollisionShape3D.new()
	StanceCollision.apply_capsule(other_shape, STAND_HEIGHT, RADIUS)
	other.add_child(other_shape)
	root.add_child(other)
	other.position = Vector3(0.45, 0, 0)
	await _physics_frames()
	_check(not _can_stand(), "Another CharacterBody3D on a masked layer prevents overlap")
	_player.collision_mask = 1
	_check(_can_stand(), "The query respects the body's collision mask")
	_player.collision_mask = 1 | 8
	other.position.x = 1.0
	await _physics_frames()
	_check(_can_stand(), "Standing is allowed after the other character moves away")
	var shared := _collider.shape as CapsuleShape3D
	other_shape.shape = shared
	var feet_before := _player.global_position
	StanceCollision.apply_capsule(_collider, STAND_HEIGHT, RADIUS)
	_check(_collider.shape != shared and is_equal_approx(shared.height, CROUCH_HEIGHT),
		"Changing one actor's height leaves a previously shared shape untouched")
	_check(is_equal_approx((_collider.shape as CapsuleShape3D).height, STAND_HEIGHT)
		and is_equal_approx(_collider.position.y - STAND_HEIGHT * 0.5, 0.0)
		and _player.global_position.is_equal_approx(feet_before), "Standing changes the capsule while preserving the world-space feet origin")
	StanceCollision.apply_capsule(_collider, CROUCH_HEIGHT, RADIUS)
	_check(is_equal_approx((_collider.shape as CapsuleShape3D).height, CROUCH_HEIGHT)
		and is_equal_approx(_collider.position.y - CROUCH_HEIGHT * 0.5, 0.0), "Crouching also preserves the collider's bottom at zero")
	_check(not StanceCollision.can_occupy(_player, 0.5, RADIUS), "Impossible capsule dimensions are rejected")
	print("STANCE_COLLISION_TEST_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed else 0)


func _can_stand() -> bool:
	return StanceCollision.can_occupy(_player, STAND_HEIGHT, RADIUS)


func _box(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	body.position = at
	_fixtures.append(body)
	return body


func _physics_frames() -> void:
	for index in 3:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		push_error("FAIL: " + label)
