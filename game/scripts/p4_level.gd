extends "res://scripts/p1_level.gd"
## One readable office encounter. Vision uses the same solid surfaces as the room.
const VISION_LAYER := 16
const ROOM := Rect2(3.8, 0.35, 8.4, 15.3)
const LOW_COVER := Rect2(6.7, 7.0, 1.0, 3.8)
const HIGH_COVER := Rect2(6.7, 11.5, 1.0, 3.0)
const WORK_DESK := Rect2(7.95, 7.35, 0.75, 2.3)
const LOW_COVER_HEIGHT := 1.18
var spawn_position := Vector3(5.5, 0.05, 14.0)
var guard_spawn := Vector3(9.3, 0.0, 8.5)
var guard_heading := PI / 2.0
var cover_test_position := Vector3(5.5, 0.0, 8.8)
var noise_test_position := Vector3(5.5, 0.0, 13.5)
var desk_clearance_probe: Array[Vector3] = [Vector3(9.0, 0.5, 8.5), Vector3(7.8, 0.5, 8.5)]
var desk_tabletop_probe: Array[Vector3] = [Vector3(9.0, 1.10, 8.5), Vector3(7.8, 1.10, 8.5)]

func _ready() -> void:
	exit_rect = Rect2(4.45, 0.65, 2.1, 1.7)
	font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	_build_floor()
	for wall in [Rect2(3.8, 0.35, 0.20, 15.3), Rect2(12.0, 0.35, 0.20, 15.3),
		Rect2(3.8, 15.45, 8.4, 0.20), Rect2(3.8, 0.35, 0.55, 0.20),
		Rect2(6.65, 0.35, 5.55, 0.20)]:
		_obstacle(wall, 2.3, "OfficeWall")
		_wall_visual(wall)
	_build_cover(LOW_COVER, LOW_COVER_HEIGHT, false)
	_build_cover(HIGH_COVER, 1.95, true)
	_build_work_desk()
	_build_exit()
	_build_details()

func _build_floor() -> void:
	var center := ROOM.get_center()
	_shape_box("OfficeFloor", Vector3(center.x, -0.2, center.y), Vector3(ROOM.size.x, 0.4, ROOM.size.y), 1)
	_box(Vector3(center.x, -0.11, center.y), Vector3(ROOM.size.x, 0.2, ROOM.size.y),
		_material("p4_floor_base", Color("293e48")))
	var colors := [Color("3a505b"), Color("3e555e")]
	for x in range(9):
		for z in range(16):
			var width := minf(1.0, ROOM.size.x - x)
			var depth := minf(1.0, ROOM.size.y - z)
			if width <= 0.0 or depth <= 0.0:
				continue
			_box(Vector3(ROOM.position.x + x + width * 0.5, -0.004, ROOM.position.y + z + depth * 0.5),
				Vector3(width - 0.012, 0.008, depth - 0.012),
				_material("p4_tile_%d" % ((x + z) % 2), colors[(x + z) % 2]))
	_box(Vector3(9.8, 0.005, 8.7), Vector3(4.1, 0.010, 7.6),
		_material("p4_office_carpet", Color("3d5250")))

func _build_cover(footprint: Rect2, height: float, tall: bool) -> void:
	var center := footprint.get_center()
	var prefix := "HighCabinet" if tall else "LowCabinet"
	_obstacle(footprint, height, prefix)
	# The top and cabinet faces partition one box, so there are no coincident faces.
	_box(Vector3(center.x, (height - 0.07) * 0.5, center.y),
		Vector3(footprint.size.x, height - 0.07, footprint.size.y),
		_material("p4_cabinet_body", Color("587a7a")))
	_box(Vector3(center.x, height - 0.035, center.y),
		Vector3(footprint.size.x, 0.07, footprint.size.y),
		_material("p4_cabinet_top", Color("adc7b3")))
	var sections := 3
	for index in range(sections):
		var z := footprint.position.y + (index + 0.5) * footprint.size.y / sections
		_box(Vector3(footprint.position.x - 0.010, (height - 0.13) * 0.5 + 0.03, z),
			Vector3(0.020, height - 0.13, footprint.size.y / sections - 0.05),
			_material("p4_cabinet_door", Color("638b87")))
		_box(Vector3(footprint.position.x - 0.038, height * 0.56, z - 0.2),
			Vector3(0.035, 0.13, 0.04), _material("p4_handle", Color("c9d6c8")))
	_wall_label("等待时机" if tall else "蹲下藏身", Vector3(footprint.position.x - 0.023, height - 0.25, center.y),
		-PI / 2.0, 30, Color("d5e7db"))

func _build_work_desk() -> void:
	var p := WORK_DESK.get_center()
	# Movement still blocks crawling underneath. Vision sees only the tabletop,
	# four legs and equipment that are visibly present above and below the desk.
	_obstacle(WORK_DESK, 1.15, "WorkDeskMovement", 1)
	_visible_solid("WorkDeskTop", Vector3(p.x, 1.10, p.y), Vector3(WORK_DESK.size.x, 0.10, WORK_DESK.size.y),
		_material("p4_wood", Color("c8aa7e")), 2 | VISION_LAYER)
	for x in [WORK_DESK.position.x + 0.10, WORK_DESK.end.x - 0.10]:
		for z in [WORK_DESK.position.y + 0.13, WORK_DESK.end.y - 0.13]:
			_visible_solid("WorkDeskLeg", Vector3(x, 0.525, z), Vector3(0.075, 1.05, 0.075),
				_material("p4_metal", Color("263d49")), VISION_LAYER)
	# The screen sits to one side of the working pose, leaving the leader's face readable.
	_visible_solid("WorkMonitor", Vector3(8.05, 1.51, 7.82), Vector3(0.08, 0.52, 0.68),
		_material("p4_metal", Color("263d49")), 2 | VISION_LAYER)
	_box(Vector3(8.095, 1.51, 7.82), Vector3(0.012, 0.44, 0.60),
		_material("p4_screen", Color("83b9b2"), true))
	_visible_solid("WorkMonitorStand", Vector3(8.05, 1.20, 7.82), Vector3(0.07, 0.10, 0.07),
		_material("p4_metal", Color("263d49")), VISION_LAYER)
	_visible_solid("WorkKeyboard", Vector3(8.52, 1.17, 8.12), Vector3(0.17, 0.04, 0.53),
		_material("p4_keyboard", Color("52656a")), VISION_LAYER)
	_visible_solid("WorkPapers", Vector3(8.40, 1.165, 8.78), Vector3(0.43, 0.03, 0.52),
		_material("p4_paper", Color("e0e3cd")), VISION_LAYER)
	_visible_solid("WorkMug", Vector3(8.27, 1.235, 9.35), Vector3(0.15, 0.17, 0.15),
		_material("p4_mug", Color("d5d7ba")), VISION_LAYER)

func _build_exit() -> void:
	var mint := _material("p4_exit", Color("77e6b8"), true)
	_box(Vector3(5.5, 0.016, 1.5), Vector3(2.0, 0.02, 1.65),
		_material("p4_exit_mat", Color("527e70")))
	for x in [4.35, 6.65]:
		_visible_solid("DoorPost", Vector3(x, 1.15, 0.45), Vector3(0.13, 2.3, 0.2), mint, 3 | VISION_LAYER)
	_visible_solid("DoorLintel", Vector3(5.5, 2.33, 0.45), Vector3(2.43, 0.13, 0.2), mint, 3 | VISION_LAYER)
	_wall_label("出口  /  下班", Vector3(5.5, 2.60, 0.52), 0.0, 40, Color("b4f9d2"))
	_box(Vector3(5.5, 0.020, 2.34), Vector3(2.10, 0.025, 0.09), mint)

func _build_details() -> void:
	_wall_label("办公室", Vector3(10.20, 1.65, 0.465), 0.0, 34, Color("d6e3da"))
	_wall_label("你的工位", Vector3(11.88, 1.7, 14.0), -PI / 2.0, 30, Color("b9d9cf"))
	# A quiet departure marker stays below the player instead of billboard text at face height.
	_box(Vector3(5.5, 0.016, 14.0), Vector3(1.25, 0.022, 0.10),
		_material("p4_departure", Color("a3b9a7")))
	# Closed files decorate the unoccupied side without creating another hiding route.
	for index in range(3):
		_visible_solid("ArchiveShelf", Vector3(11.65, 0.35 + index * 0.50, 4.3), Vector3(0.6, 0.08, 2.0),
			_material("p4_wood", Color("c8aa7e")), 3 | VISION_LAYER)
		for book in range(5):
			_visible_solid("ArchiveFiles", Vector3(11.65, 0.56 + index * 0.50, 3.53 + book * 0.36),
				Vector3(0.42, 0.34, 0.25), _material("p4_files_%d" % (book % 2),
				Color("697c73") if book % 2 == 0 else Color("9b8f78")), 3 | VISION_LAYER)

func _visible_solid(node_name: String, at: Vector3, size: Vector3, material: Material, layers: int) -> void:
	_box(at, size, material)
	_shape_box(node_name, at, size, layers)

func _shape_box(node_name: String, at: Vector3, size: Vector3, layers: int) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layers
	body.collision_mask = 0
	body.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _obstacle(footprint: Rect2, height: float, node_name: String, layers: int = 3 | VISION_LAYER) -> void:
	obstacles.append(footprint)
	if layers & VISION_LAYER:
		high_obstacles.append(footprint)
	_shape_box(node_name, Vector3(footprint.get_center().x, height * 0.5, footprint.get_center().y),
		Vector3(footprint.size.x, height, footprint.size.y), layers)

func _wall_label(text: String, at: Vector3, heading: float, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 3
	label.position = at
	label.rotation.y = heading
	add_child(label)

func is_point_walkable(point: Vector3, radius: float = 0.35) -> bool:
	if not ROOM.grow(-radius).has_point(Vector2(point.x, point.z)):
		return false
	for footprint in obstacles:
		var near := Vector2(clampf(point.x, footprint.position.x, footprint.end.x),
			clampf(point.z, footprint.position.y, footprint.end.y))
		if near.distance_to(Vector2(point.x, point.z)) < radius:
			return false
	return true
