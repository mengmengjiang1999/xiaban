extends SceneTree
## Promotional staging of the real release scene, not gameplay acceptance.
## Geometry, wardrobe, animation clips and lighting all come from production.
## A fixed SubViewport guarantees the itch.io 315:250 ratio at 1260x1000.

const COVER_SIZE := Vector2i(1260, 1000)
const PLAYER_POSITION := Vector3(5.5, 0.05, 30.0)
const CAMERA_POSITION := Vector3(4.5, 2.5, 33.0)
const CAMERA_TARGET := Vector3(7.5, 1.0, 29.0)

class CoverWorld extends "res://scripts/release.gd":
	func _notification(_what: int) -> void:
		pass
	func _load_settings() -> void:
		pass
	func _save_settings() -> void:
		pass
	func _install_web_events() -> void:
		pass
	func _install_web_qa() -> void:
		pass

var _world: Node3D
var _render: SubViewport
var _output := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if _output.is_empty():
		_output = ProjectSettings.globalize_path("res://../art/release/xiaban-cover.png")
	if not _output.is_absolute_path() or not _output.to_lower().ends_with(".png"):
		push_error("Use --output=/absolute/path/cover.png")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Capture requires the native renderer. Use --headless --check-only for compilation only.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
	root.title = "下班 · 宣传封面取景"
	root.size = COVER_SIZE
	root.content_scale_size = COVER_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	_render = SubViewport.new()
	_render.name = "CoverRender1260x1000"
	_render.size = COVER_SIZE
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_render)
	var preview := TextureRect.new()
	preview.texture = _render.get_texture()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(preview)
	_world = CoverWorld.new()
	_render.add_child(_world)
	# Do not call start_game: a cover should not capture the user's mouse or
	# advance the leaders' routines. It is an explicitly staged still image.
	_world.set_process(false)
	_world.set_physics_process(false)
	_world.set_process_input(false)
	_world.set_process_unhandled_input(false)
	_world.hud.hide()
	_world.audio.process_mode = Node.PROCESS_MODE_DISABLED
	_world.phase = "playing"
	_world.player.reset_player(PLAYER_POSITION, -0.20)
	_world.player.set_physics_process(false)
	# This is direct animation staging, not a simulated physical crouch input.
	# Zero blend plus an explicit update avoids freezing the old standing pose.
	_world.player.actor.play_action("crouch_idle", 1.0, true, true, 0.0)
	_world.player.actor.animation_player.advance(0.0)
	_world.player.actor.animation_player.seek(0.8, true)
	_world.player.actor.animation_player.advance(0.0)
	_world.player.actor.set_paused(true)
	_world.player.set_camera_alpha(1.0)
	for observer in _world.guards:
		observer.set_frozen(true)
		for label in observer.find_children("*", "Label3D", true, false):
			label.hide()
	# The real first leader stays at the desk in its authored working pose.
	# No synthetic vision fan, detection meter or diagnostic HUD is composited.
	var camera := Camera3D.new()
	camera.name = "PromotionalCamera"
	camera.fov = 52.0
	camera.near = 0.05
	camera.far = 70.0
	_world.add_child(camera)
	camera.global_position = CAMERA_POSITION
	camera.look_at(CAMERA_TARGET)
	camera.make_current()
	_add_title()
	# Allow deferred level labels, bone attachments and material uploads to
	# settle. Keep the new camera current after the inherited preview settles.
	for unused in 12:
		await process_frame
		camera.make_current()
		_world.player.set_camera_alpha(1.0)
	await RenderingServer.frame_post_draw
	var result := _render.get_texture().get_image()
	if result.get_size() != COVER_SIZE:
		push_error("Unexpected cover size: %s" % result.get_size())
		quit(3)
		return
	var error := result.save_png(_output)
	if error != OK:
		push_error("Could not save cover: %s" % error_string(error))
		quit(4)
		return
	print("RELEASE_COVER_OK staged=true width=%d height=%d file=%s" % [COVER_SIZE.x, COVER_SIZE.y, _output])
	_world.queue_free()
	await process_frame
	quit()

func _add_title() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	_render.add_child(layer)
	var overlay := Control.new()
	overlay.size = Vector2(COVER_SIZE)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([Color(0.04, 0.105, 0.105, 0.93),
		Color(0.04, 0.105, 0.105, 0.60), Color(0.04, 0.105, 0.105, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 512
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.size = Vector2(COVER_SIZE.x, 470)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	var accent := ColorRect.new()
	accent.position = Vector2(80, 53)
	accent.size = Vector2(112, 6)
	accent.color = Color("9dd5b7")
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(accent)
	var font: Font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	_label(overlay, font, "下班", Vector2(68, 52), Vector2(620, 239), 188, Color("edf0da"))
	_label(overlay, font, "今天，也要准时下班", Vector2(81, 288), Vector2(900, 68), 44, Color("d6e9dc"))
	_label(overlay, font, "OFFICE ESCAPE", Vector2(81, 926), Vector2(600, 45), 25, Color("d6e9dc"))

func _label(parent: Control, font: Font, text: String, at: Vector2, size: Vector2,
	font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.06, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
