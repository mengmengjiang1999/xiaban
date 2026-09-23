extends "res://scripts/p4_level.gd"
## Three office encounters, connected by two sheltered transfer corridors.
## Each room has a standing-height waiting spot and a separate low-cover lane.
const MAP_BOUNDS := Rect2(3.8, 0.35, 18.4, 36.5)
const FLOOR_ZONES: Array[Rect2] = [
	Rect2(3.8, 25.8, 8.4, 11.05),
	Rect2(3.8, 23.5, 18.4, 2.3),
	Rect2(12.0, 13.6, 10.2, 9.9),
	Rect2(3.8, 11.4, 18.4, 2.2),
	Rect2(3.8, 0.35, 8.4, 11.05),
]
var guard_specs: Array[Dictionary] = [
	{"id": "team_lead", "display_name": "工位组长", "position": Vector3(9.3, 0, 29.0),
		"work_heading": PI / 2.0, "watch_offset": 0.0, "work_duration": 4.8,
		"watch_duration": 2.0, "phase_offset": 0.0, "cue_refresh_offset": 0.0,
		"color": Color("916644")},
	{"id": "supervisor", "display_name": "办公室主管", "position": Vector3(15.2, 0, 18.5),
		"work_heading": 0.0, "watch_offset": -PI / 2.0, "work_duration": 5.6,
		"watch_duration": 2.5, "phase_offset": 1.1, "cue_refresh_offset": 0.05,
		"color": Color("5e718d")},
	{"id": "manager", "display_name": "楼梯口经理", "position": Vector3(9.3, 0, 6.7),
		"work_heading": PI, "watch_offset": -PI / 2.0, "work_duration": 4.2,
		"watch_duration": 2.2, "phase_offset": 2.0, "cue_refresh_offset": 0.10,
		"color": Color("876e86")},
]
var observation_points: Array[Vector3] = [
	Vector3(5.5, 0, 34.0), Vector3(18.5, 0, 22.2), Vector3(5.5, 0, 10.45),
]
var exposure_points: Array[Vector3] = [
	Vector3(5.5, 0, 29.0), Vector3(18.5, 0, 18.5), Vector3(5.5, 0, 6.7),
]
var route_waypoints: Array[Vector3] = [
	Vector3(5.5, 0, 35.0), Vector3(5.5, 0, 24.45), Vector3(18.5, 0, 24.45),
	Vector3(18.5, 0, 12.3), Vector3(5.5, 0, 12.3), Vector3(5.5, 0, 1.5),
]
var desk_clearance_probes: Array[Array] = []
var desk_tabletop_probes: Array[Array] = []

func _ready() -> void:
	spawn_position = Vector3(5.5, 0.05, 35.0)
	exit_rect = Rect2(4.45, 0.65, 2.1, 1.7)
	guard_spawn = guard_specs[0].position
	guard_heading = guard_specs[0].work_heading
	cover_test_position = exposure_points[0]
	noise_test_position = observation_points[0]
	font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	_build_floor()
	_build_walls()
	_build_zone_cover(Rect2(6.7, 27.0, 1.0, 4.0), LOW_COVER_HEIGHT, false, false)
	_build_zone_cover(Rect2(6.7, 32.0, 1.0, 3.5), 1.95, true, false)
	_build_zone_cover(Rect2(16.5, 16.0, 1.0, 3.8), LOW_COVER_HEIGHT, false, true)
	_build_zone_cover(Rect2(16.5, 20.7, 1.0, 2.4), 1.95, true, true)
	_build_zone_cover(Rect2(6.7, 4.5, 1.0, 3.8), LOW_COVER_HEIGHT, false, false)
	_build_zone_cover(Rect2(6.7, 9.0, 1.0, 1.8), 1.95, true, false)
	for spec in guard_specs:
		_build_oriented_work_desk(spec.position, spec.work_heading)
	desk_clearance_probe.assign(desk_clearance_probes[0])
	desk_tabletop_probe.assign(desk_tabletop_probes[0])
	_build_exit()
	_build_details()

func _build_walls() -> void:
	var walls: Array[Rect2] = [
		Rect2(3.8, 0.35, 0.20, 36.5), Rect2(22.0, 0.35, 0.20, 36.5),
		Rect2(3.8, 36.65, 18.4, 0.20),
		Rect2(3.8, 0.35, 0.55, 0.20), Rect2(6.65, 0.35, 15.55, 0.20),
		Rect2(12.0, 25.8, 0.20, 10.85),
		Rect2(12.0, 13.6, 0.20, 9.7),
		Rect2(12.0, 0.55, 0.20, 10.65),
	]
	# Door openings alternate sides. Corridors cannot see into the next room
	# through its wall, but each two-metre opening remains easy to approach.
	for partition in [Vector3(25.6, 4.35, 6.65), Vector3(23.3, 17.3, 19.7),
		Vector3(13.4, 17.3, 19.7), Vector3(11.2, 4.35, 6.65)]:
		walls.append(Rect2(3.8, partition.x, partition.y - 3.8, 0.20))
		walls.append(Rect2(partition.z, partition.x, 22.2 - partition.z, 0.20))
	for footprint in walls:
		_obstacle(footprint, 2.3, "OfficeWall")
		_wall_visual(footprint)

func _build_floor() -> void:
	var center := MAP_BOUNDS.get_center()
	_shape_box("OfficeFloor", Vector3(center.x, -0.2, center.y),
		Vector3(MAP_BOUNDS.size.x, 0.4, MAP_BOUNDS.size.y), 1)
	_box(Vector3(center.x, -0.11, center.y), Vector3(MAP_BOUNDS.size.x, 0.2, MAP_BOUNDS.size.y),
		_material("p4b_floor_base", Color("293e48")))
	var palette: Array[Color] = [Color("3b5658"), Color("46565c"), Color("465462"),
		Color("46565c"), Color("514f5b")]
	for index in FLOOR_ZONES.size():
		_build_tiled_zone(FLOOR_ZONES[index], palette[index], index)

func _build_tiled_zone(area: Rect2, tint: Color, zone: int) -> void:
	# Batched tile faces keep the larger map near ten floor draw calls, rather
	# than creating one mesh node per tile. Gaps reveal the solid dark base.
	var mesh := ArrayMesh.new()
	for parity in 2:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for x in ceili(area.size.x):
			for z in ceili(area.size.y):
				if (x + z) % 2 != parity:
					continue
				var left := area.position.x + x + 0.006
				var right := minf(area.position.x + x + 0.994, area.end.x - 0.006)
				var near := area.position.y + z + 0.006
				var far := minf(area.position.y + z + 0.994, area.end.y - 0.006)
				vertices.append_array(PackedVector3Array([
					Vector3(left, 0.0, near), Vector3(right, 0.0, near), Vector3(left, 0.0, far),
					Vector3(right, 0.0, near), Vector3(right, 0.0, far), Vector3(left, 0.0, far),
				]))
				for vertex in 6:
					normals.append(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(parity, _material("p4b_floor_%d_%d" % [zone, parity],
			tint.lightened(0.04) if parity == 1 else tint))
	var instance := MeshInstance3D.new()
	instance.name = "OfficeFloorTiles%d" % zone
	instance.mesh = mesh
	add_child(instance)

func _build_zone_cover(footprint: Rect2, height: float, tall: bool, face_right: bool) -> void:
	var center := footprint.get_center()
	_obstacle(footprint, height, "HighCabinet" if tall else "LowCabinet")
	_box(Vector3(center.x, (height - 0.07) * 0.5, center.y),
		Vector3(footprint.size.x, height - 0.07, footprint.size.y),
		_material("p4_cabinet_body", Color("587a7a")))
	_box(Vector3(center.x, height - 0.035, center.y), Vector3(footprint.size.x, 0.07, footprint.size.y),
		_material("p4_cabinet_top", Color("adc7b3")))
	var side := 1.0 if face_right else -1.0
	var edge := footprint.end.x if face_right else footprint.position.x
	var sections := maxi(2, ceili(footprint.size.y))
	for index in sections:
		var z := footprint.position.y + (index + 0.5) * footprint.size.y / sections
		_box(Vector3(edge + side * 0.010, (height - 0.13) * 0.5 + 0.03, z),
			Vector3(0.020, height - 0.13, footprint.size.y / sections - 0.05),
			_material("p4_cabinet_door", Color("638b87")))
		_box(Vector3(edge + side * 0.038, height * 0.56, z - 0.2),
			Vector3(0.035, 0.13, 0.04), _material("p4_handle", Color("c9d6c8")))
	_wall_label("等待时机" if tall else "蹲下藏身", Vector3(edge + side * 0.023, height - 0.25, center.y),
		side * PI / 2.0, 30, Color("d5e7db"))

func _desk_point(origin: Vector3, turn: float, point: Vector3) -> Vector3:
	return origin + point.rotated(Vector3.UP, turn)

func _desk_size(turn: float, size: Vector3) -> Vector3:
	return Vector3(absf(cos(turn)) * size.x + absf(sin(turn)) * size.z, size.y,
		absf(sin(turn)) * size.x + absf(cos(turn)) * size.z)

func _desk_solid(node_name: String, origin: Vector3, turn: float, at: Vector3,
	size: Vector3, material: Material, layers: int) -> void:
	_visible_solid(node_name, _desk_point(origin, turn, at), _desk_size(turn, size), material, layers)

func _build_oriented_work_desk(origin: Vector3, heading: float) -> void:
	# The P4a working pose faces local -X. Rotate the visible surfaces and their
	# exact ray blockers together; movement alone still forbids desk crawling.
	var turn := heading - PI / 2.0
	var center := _desk_point(origin, turn, Vector3(-0.975, 0, 0))
	var size := _desk_size(turn, Vector3(0.75, 1.15, 2.3))
	_obstacle(Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z),
		1.15, "WorkDeskMovement", 1)
	var metal := _material("p4_metal", Color("263d49"))
	_desk_solid("WorkDeskTop", origin, turn, Vector3(-0.975, 1.10, 0), Vector3(0.75, 0.10, 2.3),
		_material("p4_wood", Color("c8aa7e")), 2 | VISION_LAYER)
	for x in [-1.25, -0.70]:
		for z in [-1.02, 1.02]:
			_desk_solid("WorkDeskLeg", origin, turn, Vector3(x, 0.525, z), Vector3(0.075, 1.05, 0.075),
				metal, VISION_LAYER)
	_desk_solid("WorkMonitor", origin, turn, Vector3(-1.25, 1.51, -0.68), Vector3(0.08, 0.52, 0.68),
		metal, 2 | VISION_LAYER)
	_box(_desk_point(origin, turn, Vector3(-1.205, 1.51, -0.68)), _desk_size(turn, Vector3(0.012, 0.44, 0.60)),
		_material("p4_screen", Color("83b9b2"), true))
	_desk_solid("WorkMonitorStand", origin, turn, Vector3(-1.25, 1.20, -0.68), Vector3(0.07, 0.10, 0.07),
		metal, VISION_LAYER)
	_desk_solid("WorkKeyboard", origin, turn, Vector3(-0.78, 1.17, -0.38), Vector3(0.17, 0.04, 0.53),
		_material("p4_keyboard", Color("52656a")), VISION_LAYER)
	_desk_solid("WorkPapers", origin, turn, Vector3(-0.90, 1.165, 0.28), Vector3(0.43, 0.03, 0.52),
		_material("p4_paper", Color("e0e3cd")), VISION_LAYER)
	_desk_solid("WorkMug", origin, turn, Vector3(-1.03, 1.235, 0.85), Vector3(0.15, 0.17, 0.15),
		_material("p4_mug", Color("d5d7ba")), VISION_LAYER)
	desk_clearance_probes.append([_desk_point(origin, turn, Vector3(-0.3, 0.5, 0)),
		_desk_point(origin, turn, Vector3(-1.5, 0.5, 0))])
	desk_tabletop_probes.append([_desk_point(origin, turn, Vector3(-0.3, 1.10, 0)),
		_desk_point(origin, turn, Vector3(-1.5, 1.10, 0))])

func _build_exit() -> void:
	super._build_exit()

func _build_details() -> void:
	_wall_label("01  /  工位区", Vector3(8.85, 1.80, 25.815), 0.0, 33, Color("d6e3da"))
	_wall_label("02  /  主管区", Vector3(14.5, 1.80, 13.615), 0.0, 33, Color("d0dbea"))
	_wall_label("03  /  楼梯前厅", Vector3(8.9, 1.80, 0.575), 0.0, 33, Color("e2d8e8"))
	_wall_label("主管区  →", Vector3(11.5, 1.6, 23.515), 0.0, 32, Color("d0dbea"))
	_wall_label("←  安全楼梯", Vector3(14.7, 1.6, 11.415), 0.0, 32, Color("b4f9d2"))
	_wall_label("你的工位", Vector3(11.88, 1.7, 35.0), -PI / 2.0, 30, Color("b9d9cf"))
	_box(Vector3(5.5, 0.016, 35.0), Vector3(1.25, 0.022, 0.10),
		_material("p4_departure", Color("a3b9a7")))
	# Wall-side file shelves add depth without obscuring leaders or forming a
	# shortcut behind the three intended cover lanes.
	for entry in [Vector3(11.60, 0, 31.8), Vector3(21.60, 0, 16.2), Vector3(11.60, 0, 3.2)]:
		for index in 3:
			_visible_solid("ArchiveShelf", entry + Vector3(0, 0.35 + index * 0.50, 0), Vector3(0.6, 0.08, 1.8),
				_material("p4_wood", Color("c8aa7e")), 3 | VISION_LAYER)
			for book in 4:
				_visible_solid("ArchiveFiles", entry + Vector3(0, 0.56 + index * 0.50, -0.55 + book * 0.36),
					Vector3(0.42, 0.34, 0.25), _material("p4_files_%d" % (book % 2),
						Color("697c73") if book % 2 == 0 else Color("9b8f78")), 3 | VISION_LAYER)

func stage_index(at: Vector3) -> int:
	if at.z >= 23.3:
		return 0
	return 1 if at.z >= 11.2 else 2

func is_point_walkable(point: Vector3, radius: float = 0.35) -> bool:
	var horizontal := Vector2(point.x, point.z)
	if not MAP_BOUNDS.grow(-radius).has_point(horizontal):
		return false
	var inside_route_area := false
	for area in FLOOR_ZONES:
		if area.has_point(horizontal):
			inside_route_area = true
			break
	if not inside_route_area:
		return false
	for footprint in obstacles:
		var near := Vector2(clampf(point.x, footprint.position.x, footprint.end.x),
			clampf(point.z, footprint.position.y, footprint.end.y))
		if near.distance_to(horizontal) < radius:
			return false
	return true
