extends "res://scripts/p4b_level.gd"
## Final first-level dressing. The playable footprints and all sight blockers
## remain the tested P4b geometry; decoration is a thin skin on those surfaces.
## Box dressing is instanced by material instead of adding hundreds of draws.

const RELEASE_PALETTE := {
	"glass": "a19f91", "wall": "394a4a", "frame": "566361",
	"p4_cabinet_body": "455c59", "p4_cabinet_top": "b3966f",
	"p4_cabinet_door": "5b726b", "p4_handle": "c4c3ad",
	"p4_wood": "ac8963", "p4_metal": "263333", "p4_keyboard": "344240",
	"p4_screen": "365b5e", "p4_paper": "d4d1bb", "p4_mug": "b7b7a0",
	"p4_files_0": "577c7a", "p4_files_1": "9b735a",
	"p4_exit": "83c8a5", "p4_exit_mat": "42675c", "p4_departure": "83a99a",
	"p4b_floor_base": "293533",
}
const FLOOR_COLORS: Array[Color] = [Color("425853"), Color("878779"),
	Color("48565c"), Color("878779"), Color("55545b")]
var _box_groups: Dictionary = {}
var _surface_textures: Dictionary = {}
var decoration_instances := 0
var material_batches := 0

func _ready() -> void:
	super._ready()
	_flush_box_batches()
	set_meta("visual_profile", "office_release_v1")
	set_meta("collision_profile", "unchanged_p4b")

func _material(key: String, color: Color, glow: bool = false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	if RELEASE_PALETTE.has(key):
		color = Color(RELEASE_PALETTE[key])
	if key.begins_with("p4b_floor_") and key != "p4b_floor_base":
		var pieces := key.split("_")
		var zone := int(pieces[2])
		color = FLOOR_COLORS[zone]
		if pieces[3] == "1":
			color = color.lightened(0.012)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if key in ["p4_metal", "p4_handle", "release_trim"]:
		material.roughness = 0.56
		material.metallic = 0.18
	var surface := ""
	if key in ["p4_wood", "p4_cabinet_top", "release_dado"]:
		surface = "wood"
	elif key == "glass":
		surface = "plaster"
	elif key.begins_with("p4b_floor_") and not key.ends_with("base"):
		var zone := int(key.split("_")[2])
		surface = "stone" if zone in [1, 3] else "carpet"
	if not surface.is_empty():
		material.albedo_texture = _surface_texture(surface)
		material.uv1_triplanar = true
		material.uv1_triplanar_sharpness = 2.0
		material.uv1_scale = Vector3(2, 2, 2) if surface != "wood" else Vector3(0.8, 0.8, 0.8)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.16
	_materials[key] = material
	return material

func _surface_texture(surface: String) -> Texture2D:
	if _surface_textures.has(surface):
		return _surface_textures[surface]
	# Original, deterministic microstructure. Mipmaps prevent grain aliasing as
	# the shoulder camera moves; contrast is intentionally kept very low.
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var grain := float((x * 19 + y * 43 + x * y * 7) % 31) / 30.0
			var value := 0.965 + grain * 0.035
			if surface == "carpet":
				value = 0.92 + grain * 0.06 + float((x + y) % 2) * 0.02
			elif surface == "wood":
				value = 0.92 + 0.055 * sin(float(y) * TAU / 8.0 + 0.6 * sin(float(x) * TAU / 64.0)) + grain * 0.025
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_surface_textures[surface] = texture
	return texture

func _box(at: Vector3, size: Vector3, material: Material) -> void:
	var identity := material.get_instance_id()
	if not _box_groups.has(identity):
		_box_groups[identity] = {"material": material, "transforms": []}
	_box_groups[identity].transforms.append(Transform3D(Basis.from_scale(size), at))
	decoration_instances += 1

func _flush_box_batches() -> void:
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	for identity in _box_groups:
		var group: Dictionary = _box_groups[identity]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = unit_box
		instances.instance_count = group.transforms.size()
		for index in instances.instance_count:
			instances.set_instance_transform(index, group.transforms[index])
		var node := MultiMeshInstance3D.new()
		node.name = "OfficeMaterialBatch%02d" % material_batches
		node.multimesh = instances
		node.material_override = group.material
		add_child(node)
		material_batches += 1
	_box_groups.clear()

func _wall_visual(area: Rect2) -> void:
	var center := area.get_center()
	# These layers partition the original 2.3 m wall volume. Their faces never
	# coincide, including the skirting/dado boundary that used to shimmer in P1.
	for layer in [[0.0, 0.10, "wall", Color("394a4a")],
		[0.10, 0.64, "release_dado", Color("787967")],
		[0.64, 0.67, "release_trim", Color("46534c")],
		[0.67, 2.30, "glass", Color("a19f91")]]:
		var low := float(layer[0])
		var high := float(layer[1])
		_box(Vector3(center.x, (low + high) * 0.5, center.y),
			Vector3(area.size.x, high - low, area.size.y), _material(layer[2], layer[3]))
	_box(Vector3(center.x, 2.32, center.y), Vector3(area.size.x + 0.03, 0.07, area.size.y + 0.03),
		_material("frame", Color("566361")))

func _build_floor() -> void:
	var center := MAP_BOUNDS.get_center()
	_shape_box("OfficeFloor", Vector3(center.x, -0.2, center.y),
		Vector3(MAP_BOUNDS.size.x, 0.4, MAP_BOUNDS.size.y), 1)
	_box(Vector3(center.x, -0.11, center.y), Vector3(MAP_BOUNDS.size.x, 0.2, MAP_BOUNDS.size.y),
		_material("p4b_floor_base", Color("293533")))
	for index in FLOOR_ZONES.size():
		_build_tiled_zone(FLOOR_ZONES[index], FLOOR_COLORS[index], index)

func _build_oriented_work_desk(origin: Vector3, heading: float) -> void:
	super._build_oriented_work_desk(origin, heading)
	var turn := heading - PI / 2.0
	var light := _material("release_screen_text", Color("99c7bb"), true)
	var dim := _material("release_screen_dim", Color("547d78"), true)
	# Screen content is flush against the existing monitor, never a new blocker.
	for row in 5:
		var length := 0.27 if row % 2 == 0 else 0.38
		_desk_detail(origin, turn, Vector3(-1.197, 1.67 - row * 0.065, -0.72),
			Vector3(0.005, 0.015, length), light if row == 0 else dim)
	_desk_detail(origin, turn, Vector3(-1.197, 1.51, -0.46), Vector3(0.005, 0.32, 0.025), dim)
	var keycap := _material("release_keycaps", Color("85928a"))
	for row in 3:
		for column in 9:
			_desk_detail(origin, turn, Vector3(-0.83 + row * 0.052, 1.193, -0.605 + column * 0.055),
				Vector3(0.032, 0.004, 0.035), keycap)
	var ink := _material("release_ink", Color("6c7770"))
	for row in 7:
		_desk_detail(origin, turn, Vector3(-1.055 + row * 0.05, 1.182, 0.26),
			Vector3(0.008, 0.003, 0.33 if row > 0 else 0.20), ink)
	_desk_detail(origin, turn, Vector3(-0.70, 1.185, 0.63), Vector3(0.018, 0.018, 0.17),
		_material("release_pen", Color("334e4e")))

func _desk_detail(origin: Vector3, turn: float, at: Vector3, size: Vector3, material: Material) -> void:
	_box(_desk_point(origin, turn, at), _desk_size(turn, size), material)

func _build_details() -> void:
	# Preserve the archive shelves and their precise visual/physics geometry.
	super._build_details()
	# Replace the older floating wall labels with a consistent framed sign system.
	for child in get_children():
		if child is Label3D and child.text in ["01  /  工位区", "02  /  主管区", "03  /  楼梯前厅",
			"主管区  →", "←  安全楼梯", "你的工位"]:
			child.queue_free()
	_wall_sign("01   工位区", "OPERATIONS", Vector3(9.0, 1.65, 25.81), 0.0, 2.25)
	_wall_sign("02   主管办公室", "SUPERVISOR", Vector3(14.6, 1.65, 13.61), 0.0, 2.55)
	_wall_sign("03   楼梯前厅", "STAIR LOBBY", Vector3(9.2, 1.65, 0.56), 0.0, 2.5)
	_wall_sign("主管办公室  →", "02   /   OFFICE", Vector3(11.4, 1.62, 23.51), 0.0, 2.6)
	_wall_sign("←  安全楼梯", "03   /   STAIRS", Vector3(14.8, 1.62, 11.41), 0.0, 2.55)
	_wall_sign("你的工位", "18:00   /   TIME TO GO", Vector3(11.99, 1.68, 35.0), -PI / 2.0, 1.9)
	# Opaque window murals suggest the city at dusk without claiming that the
	# tested walls are transparent. Their maximum relief is below camera margin.
	_window_mural(Vector3(4.010, 1.52, 31.1), PI / 2.0, 2.25)
	_window_mural(Vector3(21.990, 1.52, 16.2), -PI / 2.0, 2.30)
	_window_mural(Vector3(4.010, 1.52, 5.5), PI / 2.0, 2.25)
	_notice_board(Vector3(11.99, 1.55, 27.0), -PI / 2.0)
	_notice_board(Vector3(21.990, 1.55, 20.0), -PI / 2.0)
	_botanical_print(Vector3(11.99, 1.56, 9.1), -PI / 2.0)
	_botanical_print(Vector3(4.010, 1.56, 34.5), PI / 2.0)
	_wall_clock(Vector3(10.8, 1.83, 25.81), 0.0)
	_wall_clock(Vector3(20.7, 1.83, 13.61), 0.0)
	for origin in [Vector3(7.2, 1.90, 23.51), Vector3(19.9, 1.90, 11.41)]:
		_panel_box(origin, 0.0, Vector3.ZERO, Vector3(0.30, 0.08, 0.015),
			_material("release_wall_lamp", Color("bcb99d"), true))

func _panel_box(origin: Vector3, heading: float, offset: Vector3, size: Vector3, material: Material) -> void:
	var at := origin + offset.rotated(Vector3.UP, heading)
	_box(at, _desk_size(heading, size), material)

func _wall_sign(title: String, subtitle: String, at: Vector3, heading: float, width: float) -> void:
	var dark := _material("release_sign", Color("263d3b"))
	_panel_box(at, heading, Vector3(0, 0, 0), Vector3(width, 0.58, 0.018), dark)
	_panel_box(at, heading, Vector3(-width * 0.5 + 0.07, 0, 0.012), Vector3(0.035, 0.44, 0.006),
		_material("release_sign_accent", Color("85b1a0")))
	_wall_label(title, at + Vector3(0, 0.065, 0.016).rotated(Vector3.UP, heading), heading, 31, Color("e4e6d6"))
	_wall_label(subtitle, at + Vector3(0, -0.15, 0.016).rotated(Vector3.UP, heading), heading, 16, Color("9db6a8"))

func _window_mural(at: Vector3, heading: float, width: float) -> void:
	var frame := _material("release_window_frame", Color("354949"))
	_panel_box(at, heading, Vector3.ZERO, Vector3(width, 0.94, 0.012), frame)
	_panel_box(at, heading, Vector3(0, 0, 0.01), Vector3(width - 0.12, 0.82, 0.006),
		_material("release_dusk", Color("91a69c")))
	_panel_box(at, heading, Vector3(0, -0.24, 0.014), Vector3(width - 0.12, 0.30, 0.003),
		_material("release_dusk_horizon", Color("718d89")))
	for index in 9:
		var height := 0.19 + float((index * 7) % 5) * 0.057
		var x := -width * 0.5 + 0.18 + index * (width - 0.36) / 8.0
		_panel_box(at, heading, Vector3(x, -0.40 + height * 0.5, 0.018), Vector3(0.16, height, 0.003),
			_material("release_city", Color("526f70")))
	_panel_box(at, heading, Vector3.ZERO, Vector3(0.045, 0.94, 0.042), frame)
	_panel_box(at, heading, Vector3(0, -0.10, 0.021), Vector3(width, 0.035, 0.003), frame)

func _notice_board(at: Vector3, heading: float) -> void:
	_panel_box(at, heading, Vector3.ZERO, Vector3(1.4, 0.98, 0.018),
		_material("release_board_frame", Color("46574f")))
	_panel_box(at, heading, Vector3(0, 0, 0.012), Vector3(1.3, 0.88, 0.004),
		_material("release_cork", Color("8e8468")))
	for index in 4:
		var offset := Vector3(-0.45 + float(index % 2) * 0.73, 0.20 - float(index / 2) * 0.44, 0.017)
		_panel_box(at, heading, offset, Vector3(0.42, 0.32, 0.003), _material("p4_paper", Color("d4d1bb")))
		for row in 3:
			_panel_box(at, heading, offset + Vector3(0, 0.07 - row * 0.07, 0.004), Vector3(0.27, 0.012, 0.002),
				_material("release_ink", Color("6c7770")))

func _botanical_print(at: Vector3, heading: float) -> void:
	_panel_box(at, heading, Vector3.ZERO, Vector3(0.76, 0.98, 0.018),
		_material("release_board_frame", Color("46574f")))
	_panel_box(at, heading, Vector3(0, 0, 0.012), Vector3(0.68, 0.90, 0.004),
		_material("release_print_paper", Color("bfbe9f")))
	_panel_box(at, heading, Vector3(0, -0.01, 0.017), Vector3(0.018, 0.57, 0.003),
		_material("release_botanical", Color("536e59")))
	for index in 4:
		var side := -1.0 if index % 2 == 0 else 1.0
		_panel_box(at, heading, Vector3(side * 0.085, -0.19 + index * 0.12, 0.019),
			Vector3(0.16, 0.062, 0.003), _material("release_botanical", Color("536e59")))

func _wall_clock(at: Vector3, heading: float) -> void:
	_panel_box(at, heading, Vector3.ZERO, Vector3(0.38, 0.38, 0.018),
		_material("release_board_frame", Color("46574f")))
	_panel_box(at, heading, Vector3(0, 0, 0.012), Vector3(0.32, 0.32, 0.004),
		_material("release_print_paper", Color("bfbe9f")))
	_panel_box(at, heading, Vector3(0, 0.063, 0.018), Vector3(0.011, 0.14, 0.003),
		_material("release_ink", Color("6c7770")))
	_panel_box(at, heading, Vector3(0, -0.038, 0.020), Vector3(0.018, 0.09, 0.003),
		_material("release_ink", Color("6c7770")))
