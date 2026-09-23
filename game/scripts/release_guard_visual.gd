extends "res://scripts/p4_guard_visual.gd"
## Three office tasks share the exact P4 head/eye telegraph and clocks.
const Wardrobe = preload("res://scripts/release_character.gd")
var identity := "team_lead"
var _document: Node3D
var _writing_pen: MeshInstance3D

func configure(value: String) -> void:
	identity = value

func setup(actor: Node3D) -> void:
	super.setup(actor)
	if identity == "team_lead": return
	_document = Node3D.new()
	_document.name = "ReadingFolder" if identity == "supervisor" else "ReviewClipboard"
	add_child(_document)
	var backing := Color("426982") if identity == "supervisor" else Color("866344")
	_part(_document,"DocumentBacking",Vector3.ZERO,Vector3(.24,.30,.014),backing)
	_part(_document,"Paper",Vector3(0,0,-.009),Vector3(.208,.268,.004),Color("eee9d8"))
	_part(_document,"PageTitle",Vector3(0,.10,-.012),Vector3(.14,.014,.002),Color("567783"))
	for line in 5:
		_part(_document,"PrintedLine",Vector3(-.01,.064-line*.031,-.012),Vector3(.14 if line%2 == 0 else .115,.004,.002),Color("939c99"))
	if identity == "manager":
		_part(_document,"MetalClip",Vector3(0,.144,-.011),Vector3(.075,.022,.014),Color("a0a7a8"))
		var cylinder := CylinderMesh.new()
		cylinder.top_radius=.004
		cylinder.bottom_radius=.004
		cylinder.height=.105
		cylinder.radial_segments=8
		_writing_pen=MeshInstance3D.new()
		_writing_pen.name="ReviewPen"
		_writing_pen.mesh=cylinder
		_writing_pen.material_override=Wardrobe._material(_actor,"ReviewPen",Color("2b3c45"))
		_actor.meshes.append(_writing_pen)
		add_child(_writing_pen)
	var batch_marker:=Node3D.new()
	batch_marker.set_meta("anchor_spine_03",_document)
	Wardrobe._batch_accessories(_actor,batch_marker)
	batch_marker.free()
	_document.get_child(0).name="PrintedDocument"

func apply_pose(lift: float, clock: float) -> void:
	# The head/spine telegraph is intentionally identical to the accepted P4
	# rig. Wardrobe and hand animation never silently change sight height.
	super.apply_pose(lift,clock)
	var work := 1.0-lift
	if identity == "team_lead":
		for side in ["l","r"]:
			var x := -1.0 if side == "l" else 1.0
			var tap := sin(clock*6.0+(PI if side=="l" else 0.0))*.012*work
			_aim("upperarm_"+side,Vector3(x*.28,1.18,-.24),work)
			_aim("lowerarm_"+side,Vector3(x*.20,1.20+tap,-.66),work)
		return
	# Left arm supports a folder. The right hand turns pages or annotates.
	_aim("upperarm_l",Vector3(-.28,1.21,-.16),work)
	_aim("lowerarm_l",Vector3(-.16,1.17,-.40),work)
	_aim("upperarm_r",Vector3(.28,1.23,-.17),work)
	var motion := sin(clock*(1.7 if identity=="supervisor" else 4.0))*.025*work
	_aim("lowerarm_r",Vector3(.075+motion,1.21,-.41),work)
	if is_instance_valid(_document):
		var hand: Vector3 = _actor.bone_world_position("hand_l")
		var local := Vector3(.07,.025,-.015)
		var pitch := lerpf(-.20,-1.00,work)
		_document.global_transform=Transform3D(_actor.global_basis*Basis(Vector3.RIGHT,pitch),hand+_actor.global_basis*local)
	if is_instance_valid(_writing_pen):
		var hand: Vector3 = _actor.bone_world_position("hand_r")
		var basis := Basis(Quaternion(Vector3.UP,Vector3(-.35,.60,.72).normalized()))
		_writing_pen.global_transform=Transform3D(_actor.global_basis*basis,hand+_actor.global_basis*Vector3(-.013,-.018,-.025))

func _part(parent: Node3D, label: String, at: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name=label
	var mesh := BoxMesh.new()
	mesh.size=size
	instance.mesh=mesh
	instance.position=at
	instance.material_override=Wardrobe._material(_actor,label,color)
	parent.add_child(instance)
	_actor.meshes.append(instance)
