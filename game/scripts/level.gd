extends Node3D
## Geometry and navigation share obstacle footprints; vision uses tall colliders only.
var obstacles: Array[Rect2] = []
var high_obstacles: Array[Rect2] = []
var grid := AStarGrid2D.new()
var exit_rect := Rect2(2.5,0.5,4,2)
var font: Font
var _materials: Dictionary = {}
const WALLS = [[0,0,24,0.3],[0,29.7,24,0.3],[0,0,0.3,30],[23.7,0,0.3,30],[0,19.85,4,0.3],[7,19.85,17,0.3],[0,9.85,17,0.3],[20,9.85,4,0.3],[11.85,14,0.3,6],[12,13.85,3,0.3],[18,13.85,6,0.3]]
const COVERS = [[6.8,25,1,3],[10,10.5,1,2],[13,6,8,1],[7,2.8,2,1.2]]
const DESKS = [[1.5,26.8,2,1.2],[9.5,26,4.5,1.2],[16,24,5,1.4],[16,27,5,1.4],[19,15.1,3,1.3],[2,15.5,2,1.3]]

func _ready() -> void:
	_build_floor()
	for item in WALLS:
		var r := _rect(item)
		_add_blocker(r,2.3,true)
		_wall_visual(r)
	for item in COVERS:
		var r := _rect(item)
		_add_blocker(r,1.9,true)
		_cabinet(r)
	for item in DESKS:
		var r := _rect(item)
		_add_blocker(r,0.94,false)
		_desk(r)
	_details()
	_build_navigation()

func _wall_visual(r: Rect2) -> void:
	# Legacy v0.1 keeps its translucent full-height panel and opaque wall skirt.
	# Alternative wall appearances must not change the shared collision footprint.
	_box(Vector3(r.get_center().x,1.15,r.get_center().y),Vector3(r.size.x,2.3,r.size.y),_material("glass",Color(0.47,0.67,0.71,0.22)))
	_box(Vector3(r.get_center().x,0.14,r.get_center().y),Vector3(r.size.x,0.28,r.size.y),_material("wall",Color("526873")))
	_box(Vector3(r.get_center().x,2.32,r.get_center().y),Vector3(r.size.x+0.03,0.07,r.size.y+0.03),_material("frame",Color("82999b")))

func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]),float(a[1]),float(a[2]),float(a[3]))

func _material(key: String,color: Color,glow: bool=false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.82
	if color.a < 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.65
	_materials[key] = m
	return m

func _box(at: Vector3,size: Vector3,material: Material) -> void:
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	model.mesh = mesh
	model.material_override = material
	model.position = at
	add_child(model)

func _add_blocker(r: Rect2,height: float,high: bool) -> void:
	obstacles.append(r)
	if high:
		high_obstacles.append(r)
	var body := StaticBody3D.new()
	body.collision_layer = 3 if high else 1
	body.collision_mask = 0
	body.position = Vector3(r.get_center().x,height*0.5,r.get_center().y)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(r.size.x,height,r.size.y)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var c := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(24,0.4,30)
	c.shape = shape
	body.add_child(c)
	body.position = Vector3(12,-0.2,15)
	add_child(body)
	_box(Vector3(12,-0.21,15),Vector3(24,0.4,30),_material("base",Color("20313e")))
	var tiles = [_material("tile1",Color("344855")),_material("tile2",Color("384d59"))]
	for x in range(12):
		for z in range(15):
			_box(Vector3(x*2+1,-0.015,z*2+1),Vector3(1.97,0.03,1.97),tiles[(x+z)%2])
	_box(Vector3(18,0.007,17),Vector3(11.6,0.02,5.6),_material("carpet",Color("3e5251")))
	_box(Vector3(12,0.007,25),Vector3(23.3,0.02,9.3),_material("work_carpet",Color("3a4b59")))

func _cabinet(r: Rect2) -> void:
	var center := r.get_center()
	_box(Vector3(center.x,0.92,center.y),Vector3(r.size.x,1.84,r.size.y),_material("cabinet",Color("587a7a")))
	_box(Vector3(center.x,1.89,center.y),Vector3(r.size.x+0.06,0.12,r.size.y+0.06),_material("cabtop",Color("adc7b3")))
	var count := maxi(1,int(r.size.x/0.8))
	for i in range(count):
		var x := r.position.x+(i+0.5)*r.size.x/count
		_box(Vector3(x,0.94,r.end.y+0.012),Vector3(r.size.x/count-0.04,1.66,0.035),_material("cabdoor",Color("648a87")))
		_box(Vector3(x+0.12,1.05,r.end.y+0.05),Vector3(0.05,0.25,0.07),_material("handle",Color("d0d8cc")))

func _desk(r: Rect2) -> void:
	var p := r.get_center()
	var metal := _material("metal",Color("223340"))
	_box(Vector3(p.x,0.89,p.y),Vector3(r.size.x,0.12,r.size.y),_material("wood",Color("d0ae7b")))
	for x in [r.position.x+0.14,r.end.x-0.14]:
		for z in [r.position.y+0.12,r.end.y-0.12]:
			_box(Vector3(x,0.42,z),Vector3(0.09,0.84,0.09),metal)
	var seats := maxi(1,int(r.size.x/1.7))
	for i in range(seats):
		var x := r.position.x+(i+0.5)*r.size.x/seats
		_box(Vector3(x,1.24,p.y-0.12),Vector3(0.72,0.45,0.08),metal)
		_box(Vector3(x,1.24,p.y-0.067),Vector3(0.64,0.37,0.012),_material("screen",Color("7bacab"),true))
		_box(Vector3(x,1.00,p.y-0.12),Vector3(0.06,0.18,0.06),metal)
		_box(Vector3(x,0.968,p.y+0.24),Vector3(0.52,0.035,0.18),_material("keyboard",Color("40505c")))
		_box(Vector3(x+0.56,1.015,p.y+0.2),Vector3(0.13,0.16,0.13),_material("mug",Color("e6ddd0")))

func _sign(text: String,at: Vector3,color: Color,size: int=36) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.013
	label.modulate = color
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if font != null:
		label.font = font
	label.position = at
	add_child(label)

func _details() -> void:
	var mint := _material("exit",Color("77e6b8"),true)
	_box(Vector3(4.5,0.022,1.5),Vector3(4,0.035,2),mint)
	for x in [2.5,6.5]:
		_box(Vector3(x,1.45,0.6),Vector3(0.17,2.9,0.2),mint)
	_box(Vector3(4.5,2.8,0.6),Vector3(4,0.18,0.2),mint)
	_sign("EXIT  /  下班",Vector3(4.5,3.15,0.6),Color("a7ffd6"),42)
	_sign("01   工位区",Vector3(18.5,0.10,21.5),Color("95b8c3"))
	_sign("02   办公室",Vector3(20,0.10,18.8),Color("95b8c3"))
	_sign("03   楼梯口",Vector3(16,0.10,2),Color("95b8c3"))
	for p in [Vector3(5.5,0.03,20),Vector3(18.5,0.03,10)]:
		_box(p,Vector3(2.7,0.03,0.16),_material("threshold",Color("cbbb88")))
	_sign("你的工位",Vector3(3,1.8,28.3),Color("a7ffd6"),28)

func is_point_walkable(point: Vector3,radius: float=0.35) -> bool:
	if point.x < radius or point.z < radius or point.x > 24-radius or point.z > 30-radius:
		return false
	for r in obstacles:
		var near := Vector2(clampf(point.x,r.position.x,r.end.x),clampf(point.z,r.position.y,r.end.y))
		if near.distance_to(Vector2(point.x,point.z)) < radius:
			return false
	return true

func _build_navigation() -> void:
	grid.region = Rect2i(0,0,48,60)
	grid.cell_size = Vector2(0.5,0.5)
	grid.offset = Vector2(0.25,0.25)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(48):
		for z in range(60):
			grid.set_point_solid(Vector2i(x,z),not is_point_walkable(Vector3(x*0.5+0.25,0,z*0.5+0.25),0.42))

func _nearest_cell(at: Vector3) -> Vector2i:
	var center := Vector2i(clampi(roundi((at.x-0.25)*2),0,47),clampi(roundi((at.z-0.25)*2),0,59))
	if not grid.is_point_solid(center):
		return center
	var best := Vector2i(-1,-1)
	var distance := INF
	for x in range(maxi(0,center.x-4),mini(47,center.x+4)+1):
		for z in range(maxi(0,center.y-4),mini(59,center.y+4)+1):
			var cell := Vector2i(x,z)
			if not grid.is_point_solid(cell):
				var d := Vector2(x*0.5+0.25,z*0.5+0.25).distance_squared_to(Vector2(at.x,at.z))
				if d < distance:
					distance = d
					best = cell
	return best

func find_path(from: Vector3,to: Vector3) -> PackedVector3Array:
	var start := _nearest_cell(from)
	var finish := _nearest_cell(to)
	var result := PackedVector3Array()
	if start.x < 0 or finish.x < 0:
		return result
	for p in grid.get_point_path(start,finish):
		result.append(Vector3(p.x,0,p.y))
	if result.is_empty():
		return result
	# Preserve real endpoints so patrols reach their markers instead of stopping at a cell centre.
	if result.size() > 1 and _segment_walkable(from,result[1]):
		result[0] = Vector3(from.x,0,from.z)
	elif _segment_walkable(from,result[0]):
		result.insert(0,Vector3(from.x,0,from.z))
	if is_point_walkable(to,0.34) and _segment_walkable(result[-1],to):
		result.append(Vector3(to.x,0,to.z))
	return result

func _segment_walkable(a: Vector3,b: Vector3) -> bool:
	var steps := maxi(1,ceili(a.distance_to(b)/0.04))
	for i in range(steps+1):
		if not is_point_walkable(a.lerp(b,float(i)/steps),0.34):
			return false
	return true
