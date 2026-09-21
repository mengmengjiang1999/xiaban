extends SceneTree
## Headless regression for opaque P1 wall depth conflicts and legacy geometry.
## Run: bash tools/godot.sh --headless --script res://tests/p1_geometry_test.gd
const LegacyLevel = preload("res://scripts/level.gd")
const P1Level = preload("res://scripts/p1_level.gd")
const EPSILON := 0.00001
var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var legacy := LegacyLevel.new()
	var current := P1Level.new()
	root.add_child(legacy)
	root.add_child(current)
	_check(_collision_signature(legacy) == _collision_signature(current),
		"P1 and legacy retain identical movement blockers, dimensions and collision layers")
	_check(legacy.obstacles == current.obstacles and legacy.high_obstacles == current.high_obstacles,
		"P1 and legacy retain the same navigation and sight-blocking footprints")
	var legacy_glass := _with_material(legacy, "glass")
	var legacy_unchanged := legacy_glass.size() == LegacyLevel.WALLS.size()
	for model in legacy_glass:
		legacy_unchanged = legacy_unchanged and is_equal_approx(model.mesh.size.y, 2.3) \
			and is_equal_approx(model.position.y, 1.15) \
			and is_equal_approx(model.material_override.albedo_color.a, 0.22) \
			and model.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
	_check(legacy_unchanged, "Legacy v0.1 retains its full-height translucent wall appearance")
	# Reproduce the old P1 combination: legacy full-height panels made opaque.
	# This proves the surface check detects the original failure before checking
	# the separated wall bands, instead of accepting an always-empty detector.
	legacy._materials["glass"].transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	legacy._materials["glass"].albedo_color.a = 1.0
	_check(not _different_material_face_conflicts(legacy).is_empty(),
		"The geometry detector reproduces the former opaque-wall/skirt depth conflict")
	var plaster := _with_material(current, "glass")
	var skirts := _with_material(current, "wall")
	var bands_touch := plaster.size() == LegacyLevel.WALLS.size() and skirts.size() == plaster.size()
	for index in mini(plaster.size(), skirts.size()):
		var wall_bounds := _bounds(plaster[index])
		var skirt_bounds := _bounds(skirts[index])
		bands_touch = bands_touch and absf(wall_bounds.position.y - skirt_bounds.end.y) < EPSILON \
			and absf(wall_bounds.position.y - 0.28) < EPSILON \
			and absf(wall_bounds.end.y - 2.3) < EPSILON \
			and absf(skirt_bounds.position.y) < EPSILON \
			and plaster[index].material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	_check(bands_touch, "Opaque P1 wall bands meet at 0.28 m without overlapping their sides")
	var conflicts := _different_material_face_conflicts(current)
	for conflict in conflicts:
		print("COPLANAR_CONFLICT " + conflict)
	_check(conflicts.is_empty(), "All P1 box meshes avoid overlapping same-facing coplanar surfaces of different materials")
	var office_carpet := _bounds(_with_material(current, "carpet")[0])
	var work_carpet := _bounds(_with_material(current, "work_carpet")[0])
	var office_rect := Rect2(office_carpet.position.x, office_carpet.position.z, office_carpet.size.x, office_carpet.size.z)
	var work_rect := Rect2(work_carpet.position.x, work_carpet.position.z, work_carpet.size.x, work_carpet.size.z)
	_check(not office_rect.intersects(work_rect), "The two equal-height carpet surfaces do not overlap")
	var floor_separated := true
	for key in ["tile1", "tile2"]:
		for tile in _with_material(current, key):
			floor_separated = floor_separated and office_carpet.end.y - _bounds(tile).end.y > 0.01 \
				and work_carpet.end.y - _bounds(tile).end.y > 0.01
	_check(floor_separated, "Carpet surfaces remain above the floor tile surfaces")
	legacy.queue_free()
	current.queue_free()
	await process_frame
	print("P1_GEOMETRY_RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed else 0)


func _collision_signature(level: Node3D) -> Array[String]:
	var result: Array[String] = []
	for child in level.get_children():
		# P1 adds monitor-only camera blockers; shared player blockers must match.
		if not child is StaticBody3D or child.collision_layer == 2:
			continue
		for collider in child.get_children():
			if collider is CollisionShape3D and collider.shape is BoxShape3D:
				result.append("%s|%s|%s|%d|%d|%s" % [child.transform, collider.transform,
					collider.shape.size, child.collision_layer, child.collision_mask, collider.disabled])
	result.sort()
	return result


func _with_material(level: Node3D, key: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in level.get_children():
		if child is MeshInstance3D and child.material_override == level._materials[key]:
			result.append(child)
	return result


func _bounds(model: MeshInstance3D) -> AABB:
	return model.transform * model.mesh.get_aabb()


func _different_material_face_conflicts(level: Node3D) -> Array[String]:
	var models: Array[MeshInstance3D] = []
	var names: Dictionary = {}
	for key in level._materials:
		names[level._materials[key]] = key
	for child in level.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			models.append(child)
	var result: Array[String] = []
	for i in models.size():
		var a := models[i]
		for j in range(i + 1, models.size()):
			var b := models[j]
			if a.material_override == b.material_override:
				continue
			var first := _bounds(a)
			var second := _bounds(b)
			for axis in 3:
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var overlap_u: float = minf(first.end[u], second.end[u]) - maxf(first.position[u], second.position[u])
				var overlap_v: float = minf(first.end[v], second.end[v]) - maxf(first.position[v], second.position[v])
				if overlap_u <= EPSILON or overlap_v <= EPSILON:
					continue
				# Opposite normals at a touching seam are internal faces, not two
				# competing visible surfaces. Only compare faces with equal normals.
				if absf(first.position[axis] - second.position[axis]) < EPSILON \
					or absf(first.end[axis] - second.end[axis]) < EPSILON:
					result.append("%s %s / %s %s axis=%d" % [names[a.material_override], a.position,
						names[b.material_override], b.position, axis])
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)
