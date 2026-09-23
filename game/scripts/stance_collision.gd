extends RefCounted
## Foot-origin, upright capsule helpers shared by posture changes.
## CollisionShape3D must be a direct child of the supplied CharacterBody3D.

# CharacterBody3D's normal contact recovery leaves its feet approximately on
# the floor. Trim only this contact tolerance from the query's bottom so the
# supporting floor cannot veto every stand attempt. Walls and ceilings stay
# on the same collision mask and are never excluded by their layer or RID.
const FOOT_CONTACT_TOLERANCE := 0.002


static func can_occupy(body: CharacterBody3D, height: float, radius: float, margin: float = 0.015) -> bool:
	if body == null or not body.is_inside_tree() or radius <= 0.0 or height < radius * 2.0:
		return false
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = body.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	# First test the complete destination shape, except its floor contact slop.
	# Keeping this exact-radius pass matters near the lower hemisphere: merely
	# lifting an expanded capsule would miss some of the original foot volume.
	var exact := CapsuleShape3D.new()
	exact.radius = radius
	exact.height = maxf(radius * 2.0, height - FOOT_CONTACT_TOLERANCE)
	query.shape = exact
	query.transform = body.global_transform.orthonormalized() * Transform3D(
		Basis.IDENTITY, Vector3(0, exact.height * 0.5 + FOOT_CONTACT_TOLERANCE, 0))
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var clearance := maxf(0.0, margin)
	if is_zero_approx(clearance):
		return true
	# Add side/top clearance while retaining a bottom just above the floor.
	# The upper hemisphere center matches the requested capsule; enlarging its
	# radius therefore adds exactly `margin` above the head. The exact pass
	# above covers the lower shell that this slightly raised safety shape lacks.
	var padded := CapsuleShape3D.new()
	padded.radius = radius + clearance
	padded.height = maxf(padded.radius * 2.0, height + clearance - FOOT_CONTACT_TOLERANCE)
	query.shape = padded
	query.transform = body.global_transform.orthonormalized() * Transform3D(
		Basis.IDENTITY, Vector3(0, padded.height * 0.5 + FOOT_CONTACT_TOLERANCE, 0))
	return space.intersect_shape(query, 1).is_empty()


static func apply_capsule(collider: CollisionShape3D, height: float, radius: float) -> void:
	assert(collider != null and radius > 0.0 and height >= radius * 2.0)
	# Never mutate a shared .tres/.tscn shape when one actor changes posture.
	var shape := CapsuleShape3D.new()
	shape.resource_local_to_scene = true
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	collider.transform = Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0))
