extends RefCounted
## Authored, lightweight office wardrobes on the validated CC0 adult rig.
## The original clips, skin, actor transform and gameplay envelope are preserved.
const PALE := Color("e6e7de")

static func apply_to(actor: Node3D, identity: String) -> Node3D:
	if actor.has_meta("release_identity"):
		return actor.get_meta("release_identity")
	assert(identity in ["player", "team_lead", "supervisor", "manager"])
	var root := Node3D.new()
	root.name = "Wardrobe_" + identity
	root.set_meta("identity", identity)
	actor.add_child(root)
	actor.set_meta("release_identity", root)
	var cloth: MeshInstance3D
	var hair: MeshInstance3D
	for mesh in actor.meshes:
		if "CasualClothes" in mesh.name: cloth = mesh
		if "Hair" in mesh.name: hair = mesh
	assert(cloth != null and hair != null)
	var shirt := Color("d9e5df")
	var trousers := Color("172b35")
	match identity:
		"team_lead": shirt = Color("ccd4c7"); trousers = Color("292d31")
		"supervisor": shirt = Color("d7dbe4"); trousers = Color("23353d")
		"manager": shirt = Color("e6e2d5"); trousers = Color("292e37")
	for mat in actor.materials:
		if mat.resource_name == "PlainTealCotton": mat.albedo_color = shirt
		elif "male_casualsuit06" in mat.resource_name:
			mat.albedo_texture = null
			mat.normal_enabled = false
			mat.albedo_color = trousers
		elif "shoes01" in mat.resource_name:
			mat.albedo_color = Color("38312d")
	if identity == "player":
		_collar(actor, root, cloth, PALE, false)
		_lanyard(actor, root, cloth)
	elif identity == "team_lead":
		_garment(actor, cloth, "KnitVest", Color("9b6842"), "vest")
		_collar(actor, root, cloth, PALE, false)
		_glasses(actor, root, cloth, Color("544a39"), true)
		_hair_style(actor, hair, "cropped", Color("827b6f"))
		_pen(actor, root, cloth, Vector3(-.092, 1.31, -.138), Color("ddd9bc"))
	elif identity == "supervisor":
		_garment(actor, cloth, "NavyWaistcoat", Color("35495c"), "waistcoat")
		_sleeves(actor, cloth, Color("d7dbe4"), .73)
		_collar(actor, root, cloth, PALE, false)
		_hair_style(actor, hair, "tied", Color("392e2b"))
		_ellipsoid(actor, root, cloth, "head", "LowHairKnot", Vector3(0,1.63,.083), Vector3(.10,.095,.075), Color("302723"))
		_strip(actor, root, cloth, "head", "HairTie", Vector3(-.027,1.635,.098), Vector3(.027,1.635,.098), .014, Color("a58547"))
		_pin(actor, root, cloth, Color("c6a873"))
	else:
		_garment(actor, cloth, "ExecutiveJacket", Color("353b45"), "jacket")
		_sleeves(actor, cloth, Color("353b45"), .98)
		_collar(actor, root, cloth, PALE, true)
		_glasses(actor, root, cloth, Color("9d927d"), false)
		_hair_style(actor, hair, "silver", Color("c1bbb1"))
		_tie(actor, root, cloth)
		_pin(actor, root, cloth, Color("bc9859"))
	_batch_accessories(actor, root)
	root.set_meta("mesh_count", actor.meshes.size())
	return root

static func _material(actor: Node3D, label: String, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Release_" + label
	mat.albedo_color = color
	mat.roughness = .87
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	actor.materials.append(mat)
	actor._material_modes.append(mat.transparency)
	actor._material_alphas.append(color.a)
	return mat

static func _skin_slot(reference: MeshInstance3D, bone: String) -> int:
	for index in reference.skin.get_bind_count():
		if str(reference.skin.get_bind_name(index)) == bone: return index
	return -1

static func _anchor(actor: Node3D, root: Node3D, reference: MeshInstance3D, bone: String) -> Node3D:
	var key := "anchor_" + bone
	if root.has_meta(key): return root.get_meta(key)
	var attachment := BoneAttachment3D.new()
	attachment.name = "Wardrobe_" + bone
	attachment.bone_name = bone
	actor.skeleton.add_child(attachment)
	var anchor := Node3D.new()
	anchor.name = "BindSpace"
	anchor.transform = reference.skin.get_bind_pose(_skin_slot(reference, bone))
	attachment.add_child(anchor)
	root.set_meta(key, anchor)
	return anchor

static func _mesh(actor: Node3D, root: Node3D, reference: MeshInstance3D, bone: String, label: String, geometry: Mesh, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = geometry
	instance.material_override = _material(actor, label, color)
	_anchor(actor, root, reference, bone).add_child(instance)
	actor.meshes.append(instance)
	return instance

static func _panel(actor: Node3D, root: Node3D, reference: MeshInstance3D, bone: String, label: String, points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, points.size() - 1):
		for point in [points[0], points[index], points[index + 1]]: surface.add_vertex(point)
	surface.generate_normals()
	return _mesh(actor, root, reference, bone, label, surface.commit(), color)

static func _strip(actor: Node3D, root: Node3D, reference: MeshInstance3D, bone: String, label: String, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var sideways := (b - a).cross(Vector3.FORWARD).normalized() * width * .5
	if sideways.length_squared() < .000001: sideways = Vector3.RIGHT * width * .5
	_panel(actor, root, reference, bone, label, PackedVector3Array([a-sideways, a+sideways, b+sideways, b-sideways]), color)

static func _box(actor: Node3D, root: Node3D, reference: MeshInstance3D, bone: String, label: String, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var geometry := BoxMesh.new()
	geometry.size = size
	var mesh := _mesh(actor, root, reference, bone, label, geometry, color)
	mesh.position = position
	return mesh

static func _ellipsoid(actor: Node3D, root: Node3D, reference: MeshInstance3D, bone: String, label: String, position: Vector3, size: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1
	sphere.radial_segments = 12
	sphere.rings = 6
	var mesh := _mesh(actor, root, reference, bone, label, sphere, color)
	mesh.position = position
	mesh.scale = size

static func _collar(actor: Node3D, root: Node3D, reference: MeshInstance3D, color: Color, lapels: bool) -> void:
	for side in [-1.0, 1.0]:
		_panel(actor, root, reference, "spine_03", "ShirtCollar", PackedVector3Array([
			Vector3(side*.038,1.465,-.066), Vector3(side*.086,1.42,-.095),
			Vector3(side*.052,1.365,-.127), Vector3(side*.018,1.425,-.10)]), color)
		if lapels:
			_panel(actor, root, reference, "spine_03", "NotchedLapel", PackedVector3Array([
				Vector3(side*.088,1.426,-.098),Vector3(side*.14,1.39,-.12),
				Vector3(side*.12,1.347,-.135),Vector3(side*.14,1.32,-.141),
				Vector3(side*.034,1.197,-.165),Vector3(side*.052,1.365,-.135)]),Color("4b535d"))

static func _lanyard(actor: Node3D, root: Node3D, reference: MeshInstance3D) -> void:
	for side in [-1.0, 1.0]:
		_strip(actor, root, reference, "spine_03", "TealLanyard",Vector3(side*.052,1.422,-.102),Vector3(side*.019,1.232,-.168),.012,Color("217d83"))
	_box(actor, root, reference, "spine_03", "StaffBadge",Vector3(0,1.208,-.165),Vector3(.058,.080,.005),Color("e7ede6"))
	_box(actor, root, reference, "spine_03", "BadgePhoto",Vector3(-.012,1.218,-.169),Vector3(.018,.026,.002),Color("687f85"))
	_box(actor, root, reference, "spine_03", "BadgeStripe",Vector3(0,1.184,-.169),Vector3(.045,.008,.002),Color("248d90"))

static func _tie(actor: Node3D, root: Node3D, reference: MeshInstance3D) -> void:
	_panel(actor, root, reference, "spine_03", "BurgundyTie", PackedVector3Array([
		Vector3(-.015,1.414,-.112),Vector3(.015,1.414,-.112),Vector3(.009,1.382,-.128),
		Vector3(.026,1.214,-.170),Vector3(0,1.181,-.171),Vector3(-.026,1.214,-.170),
		Vector3(-.009,1.382,-.128)]), Color("723e3d"))

static func _pin(actor: Node3D, root: Node3D, reference: MeshInstance3D, color: Color) -> void:
	_box(actor, root, reference, "spine_03", "LapelPin",Vector3(-.105,1.356,-.141),Vector3(.018,.024,.005),color)

static func _pen(actor: Node3D, root: Node3D, reference: MeshInstance3D, position: Vector3, color: Color) -> void:
	_box(actor, root, reference, "spine_03", "PocketPen",position,Vector3(.009,.065,.009),color)

static func _glasses(actor: Node3D, root: Node3D, reference: MeshInstance3D, color: Color, round_frames: bool) -> void:
	for side in [-1.0, 1.0]:
		var center := Vector3(side*.035,1.617,-.148)
		var count := 12 if round_frames else 4
		for index in count:
			var a := TAU * index / count + (PI*.25 if not round_frames else 0.0)
			var b := TAU * (index+1) / count + (PI*.25 if not round_frames else 0.0)
			var radii := Vector2(.027,.021) if round_frames else Vector2(.036,.023)
			_strip(actor,root,reference,"head","SpectacleFrame",center+Vector3(cos(a)*radii.x,sin(a)*radii.y,0),center+Vector3(cos(b)*radii.x,sin(b)*radii.y,0),.004,color)
		_box(actor,root,reference,"head","SpectacleTemple",Vector3(side*.069,1.616,-.104),Vector3(.004,.004,.084),color)
	_box(actor,root,reference,"head","SpectacleBridge",Vector3(0,1.618,-.15),Vector3(.016,.004,.004),color)

static func _hair_style(_actor: Node3D, hair: MeshInstance3D, style: String, color: Color) -> void:
	# Never push the alpha-card shell inside the scalp. A private texture copy
	# changes hair colour while preserving every authored cutout and vertex.
	for index in hair.mesh.get_surface_count():
		var material: StandardMaterial3D = hair.get_active_material(index)
		if style in ["silver","cropped"] and material.albedo_texture != null:
			var pixels := material.albedo_texture.get_image()
			if pixels.is_compressed(): pixels.decompress()
			pixels.adjust_bcs(1.45 if style == "silver" else 1.12, .45 if style == "silver" else .80, .0 if style == "silver" else .4)
			material.albedo_texture=ImageTexture.create_from_image(pixels)
		material.albedo_color=color

static func _garment(actor: Node3D, reference: MeshInstance3D, _label: String, color: Color, cut: String) -> void:
	# Rebuild the continuous original shirt once. Exact clipping creates clean
	# V-neck and hem colour boundaries; no second coincident cloth surface.
	var arrays := reference.mesh.surface_get_arrays(1)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var shirt: StandardMaterial3D=reference.get_active_material(1)
	var pale:=shirt.albedo_color
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outside: Array[Plane]=[]
	if cut != "jacket":
		outside=[Plane(Vector3.RIGHT,.177),Plane(Vector3.LEFT,.177),Plane(Vector3.UP,-1.075)]
	# Distances below use n.dot(p)+d >= 0. The neck cut is a convex V,
	# limited to the front half of the shirt; the back remains solid cloth.
	var neck: Array[Plane]=[Plane(Vector3.UP,-1.20),Plane(Vector3.FORWARD,0),Plane(Vector3(-1,.38,0),-.456),Plane(Vector3(1,.38,0),-.456)]
	for triangle in range(0,indices.size(),3):
		var polygon: Array=[]
		for corner in 3:
			var vertex:=indices[triangle+corner]
			var influence: Dictionary={}
			for slot in 4:
				if weights[vertex*4+slot] > .000001: influence[bones[vertex*4+slot]]=weights[vertex*4+slot]
			polygon.append({"p":vertices[vertex],"n":normals[vertex],"w":influence})
		for plane in outside:
			var split:=_clip(polygon,plane)
			_painted(surface,split[1],pale)
			polygon=split[0]
		for plane in neck:
			var split:=_clip(polygon,plane)
			_painted(surface,split[1],color)
			polygon=split[0]
		_painted(surface,polygon,pale)
	var edited:=ArrayMesh.new()
	edited.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,reference.mesh.surface_get_arrays(0))
	surface.index()
	surface.commit(edited)
	reference.mesh=edited
	shirt.albedo_color=Color.WHITE
	shirt.albedo_texture=null
	shirt.normal_enabled=false
	shirt.vertex_color_use_as_albedo=true

static func _clip(polygon: Array, plane: Plane) -> Array:
	var inside: Array=[]
	var outside: Array=[]
	if polygon.is_empty(): return [inside,outside]
	for index in polygon.size():
		var a: Dictionary=polygon[index]
		var b: Dictionary=polygon[(index+1)%polygon.size()]
		var da:=plane.normal.dot(a.p)+plane.d
		var db:=plane.normal.dot(b.p)+plane.d
		if da>=0: inside.append(a)
		else: outside.append(a)
		if (da>=0) != (db>=0):
			var fraction:=da/(da-db)
			var influences: Dictionary={}
			for key in a.w: influences[key]=float(a.w[key])*(1-fraction)
			for key in b.w: influences[key]=float(influences.get(key,0))+float(b.w[key])*fraction
			var crossing: Dictionary={"p":a.p.lerp(b.p,fraction),"n":a.n.lerp(b.n,fraction).normalized(),"w":influences}
			inside.append(crossing)
			outside.append(crossing)
	return [inside,outside]

static func _painted(surface: SurfaceTool, polygon: Array, color: Color) -> void:
	for triangle in range(1,polygon.size()-1):
		for vertex in [polygon[0],polygon[triangle],polygon[triangle+1]]:
			var keys: Array=vertex.w.keys()
			keys.sort_custom(func(a,b): return vertex.w[a]>vertex.w[b])
			var bone_indices:=PackedInt32Array([0,0,0,0])
			var bone_weights:=PackedFloat32Array([0,0,0,0])
			var total:=0.0
			for index in mini(4,keys.size()):
				bone_indices[index]=int(keys[index])
				bone_weights[index]=float(vertex.w[keys[index]])
				total+=bone_weights[index]
			for index in 4: bone_weights[index]/=total
			surface.set_bones(bone_indices)
			surface.set_weights(bone_weights)
			surface.set_normal(vertex.n)
			surface.set_color(color)
			surface.add_vertex(vertex.p)

static func _sleeves(actor: Node3D, reference: MeshInstance3D, color: Color, length: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 12
	for side in ["l", "r"]:
		var upper := _skin_slot(reference,"upperarm_"+side)
		var lower := _skin_slot(reference,"lowerarm_"+side)
		var hand := _skin_slot(reference,"hand_"+side)
		var shoulder := reference.skin.get_bind_pose(upper).affine_inverse().origin
		var elbow := reference.skin.get_bind_pose(lower).affine_inverse().origin
		var wrist := reference.skin.get_bind_pose(hand).affine_inverse().origin
		var centers: Array[Vector3] = [shoulder.lerp(elbow,.27), shoulder.lerp(elbow,.70), elbow, elbow.lerp(wrist,length)]
		var radii := [.093,.085,.079,.064 if length > .9 else .069]
		var offset := vertices.size()
		for ring in centers.size():
			var axis := (elbow-shoulder).normalized() if ring < 2 else (wrist-elbow).normalized()
			var across := axis.cross(Vector3.FORWARD).normalized()
			var other := axis.cross(across).normalized()
			for segment in SEGMENTS:
				var angle := TAU*segment/SEGMENTS
				var normal := across*cos(angle)+other*sin(angle)
				vertices.append(centers[ring]+normal*float(radii[ring]))
				normals.append(normal)
				bones.append_array(PackedInt32Array([upper,lower,0,0]))
				var blend := 0.0 if ring < 2 else (0.5 if ring == 2 else 1.0)
				weights.append_array(PackedFloat32Array([1-blend,blend,0,0]))
		for ring in centers.size()-1:
			for segment in SEGMENTS:
				var a := offset+ring*SEGMENTS+segment
				var b := offset+ring*SEGMENTS+(segment+1)%SEGMENTS
				indices.append_array(PackedInt32Array([a,b,a+SEGMENTS,b,b+SEGMENTS,a+SEGMENTS]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_BONES]=bones
	arrays[Mesh.ARRAY_WEIGHTS]=weights
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := MeshInstance3D.new()
	mesh.name = "TailoredSleeves"
	mesh.mesh = ArrayMesh.new()
	mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.skin = reference.skin
	mesh.skeleton = reference.skeleton
	mesh.material_override = _material(actor,"TailoredSleeves",color)
	reference.get_parent().add_child(mesh)
	actor.meshes.append(mesh)

static func _batch_accessories(actor: Node3D, root: Node3D) -> void:
	# One vertex-coloured draw per anchor, including all thin frame segments.
	# Keep the skin and clothing surfaces separate so their source UVs remain.
	for bone in ["head","spine_03"]:
		var key: String = "anchor_"+str(bone)
		if not root.has_meta(key): continue
		var anchor: Node3D = root.get_meta(key)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for child in anchor.get_children():
			if not child is MeshInstance3D: continue
			var mat: StandardMaterial3D = child.material_override
			for part in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(part)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if indices.is_empty():
					for index in vertices.size(): indices.append(index)
				for index in indices:
					surface.set_color(mat.albedo_color)
					surface.set_normal((child.basis*normals[index]).normalized())
					surface.add_vertex(child.transform*vertices[index])
			actor.meshes.erase(child)
			var material_index: int = actor.materials.find(mat)
			if material_index >= 0:
				actor.materials.remove_at(material_index)
				actor._material_modes.remove_at(material_index)
				actor._material_alphas.remove_at(material_index)
			child.free()
		surface.index()
		var combined := MeshInstance3D.new()
		combined.name="OfficeAccessories_"+bone
		combined.mesh=surface.commit()
		var material := _material(actor,combined.name,Color.WHITE)
		material.vertex_color_use_as_albedo=true
		combined.material_override=material
		anchor.add_child(combined)
		actor.meshes.append(combined)
