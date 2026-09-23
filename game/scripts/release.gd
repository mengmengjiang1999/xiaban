extends "res://scripts/p4b.gd"
## Finished first level; the P4 route and detection rules remain the same.
const ReleaseLevel = preload("res://scripts/release_level.gd")
const ReleaseGuard = preload("res://scripts/release_guard.gd")
const ReleaseCharacter = preload("res://scripts/release_character.gd")
const ReleaseHud = preload("res://scripts/release_hud.gd")
const ReleaseAudio = preload("res://scripts/release_audio.gd")
const SETTINGS_PATH := "user://release-settings.cfg"
const LOOK_ACTIONS := {"look_left": KEY_LEFT, "look_right": KEY_RIGHT, "look_up": KEY_UP, "look_down": KEY_DOWN}
var audio: Node
var settings := {"volume": 0.65, "sensitivity": 1.0}
var _settings_dirty := false
var _save_delay := 0.0
var _release_web_qa_enabled := false
var _camera_prepared := false

func _create_level() -> Node3D:
	return ReleaseLevel.new()

func _create_hud() -> CanvasLayer:
	return ReleaseHud.new()

func _create_guard() -> CharacterBody3D:
	return ReleaseGuard.new()

func _create_rig() -> Node3D:
	var result := Rig.new()
	result.vertical_orbit_enabled = true
	result.manual_recenter_delay = 1.25
	result.auto_recenter_speed = 1.8
	result.obstruction_contraction_speed = 16.0
	result.max_boom_speed = 14.0
	return result

func _ready() -> void:
	for action in LOOK_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = LOOK_ACTIONS[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	_load_settings()
	super._ready()
	ReleaseCharacter.apply_to(player.actor, "player")
	player.actor.retain_camera_fade_shaders()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.55
			child.environment.ambient_light_color = Color("e4e9e8")
		elif child is DirectionalLight3D:
			child.light_energy = 0.8
			child.light_color = Color("fff0d9")
	audio = ReleaseAudio.new()
	audio.setup(self)
	add_child(audio)
	audio.set_volume(settings.volume)
	rig.mouse_sensitivity = 0.004 * settings.sensitivity
	hud.apply_settings(settings)
	_prepare_camera_rendering()

func _prepare_camera_rendering() -> void:
	if DisplayServer.get_name() != "headless":
		# Compile the actual opaque and fade draw variants before accepting play.
		# Keeping resources alive prevents later eviction, but creating a material
		# alone does not exercise its GPU rendering path. Cover the warmup frames
		# so the character never visibly blinks during startup.
		var cover := CanvasLayer.new()
		cover.layer = 100
		var backdrop := ColorRect.new()
		backdrop.color = Color("142a34")
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.add_child(backdrop)
		add_child(cover)
		hud._primary.disabled = true
		# Let the inherited initial camera settle before controlling its alpha.
		await RenderingServer.frame_post_draw
		# The first observation also introduces an unshaded transparent pipeline.
		# Draw its real shared material on a temporary triangle in view. This
		# prepares rendering without changing any guard state or detection clock.
		var cue_preview := MeshInstance3D.new()
		var cue_mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(0, 1, -1)])
		cue_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		cue_preview.mesh = cue_mesh
		cue_preview.material_override = guards[0]._fan_material
		cue_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.camera.add_child(cue_preview)
		player.actor.set_camera_alpha(0.5)
		await RenderingServer.frame_post_draw
		cue_preview.queue_free()
		player.actor.set_camera_alpha(player.camera_alpha)
		await RenderingServer.frame_post_draw
		hud._primary.disabled = false
		hud._primary.grab_focus()
		cover.queue_free()
	_camera_prepared = true
	print("RELEASE_READY leaders=%d version=%s platform=%s" % [guards.size(), ProjectSettings.get_setting("application/config/version"), OS.get_name()])

func start_game() -> void:
	if _camera_prepared:
		super.start_game()

func _set_phase(next: String) -> void:
	var previous := phase
	super._set_phase(next)
	if is_instance_valid(audio):
		audio.change_phase(previous, phase)

func _process(delta: float) -> void:
	if phase == "playing":
		rig.set_look_input(Input.get_vector("look_left", "look_right", "look_up", "look_down"))
	super._process(delta)
	if _settings_dirty:
		_save_delay -= delta
		if _save_delay <= 0:
			_save_settings()

func _clear_input() -> void:
	super._clear_input()
	for action in LOOK_ACTIONS:
		Input.action_release(action)

func change_setting(key: String, value: float) -> void:
	if key == "volume":
		settings.volume = clampf(value, 0.0, 1.0)
		if is_instance_valid(audio):
			audio.set_volume(settings.volume)
	elif key == "sensitivity":
		settings.sensitivity = clampf(value, 0.5, 2.0)
		rig.mouse_sensitivity = 0.004 * settings.sensitivity
	else:
		return
	_settings_dirty = true
	_save_delay = 0.25

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		settings.volume = clampf(float(config.get_value("audio", "volume", 0.65)), 0.0, 1.0)
		settings.sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.5, 2.0)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", settings.volume)
	config.set_value("controls", "sensitivity", settings.sensitivity)
	var result := config.save(SETTINGS_PATH)
	if result != OK:
		push_warning("Settings could not be saved: %s" % error_string(result))
	_settings_dirty = false

func _install_web_qa() -> void:
	super._install_web_qa()
	_release_web_qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('release_qa') === '1'"))

func _publish_web_qa_state() -> void:
	super._publish_web_qa_state()
	if _release_web_qa_enabled and _camera_prepared and is_instance_valid(audio):
		_web_window.xiabanReleaseState = JSON.stringify({
			"version": ProjectSettings.get_setting("application/config/version"),
			"audio": audio.get_status(), "settings": settings,
			"controls": hud.get_release_controls(),
		})

func _exit_tree() -> void:
	if _settings_dirty:
		_save_settings()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("delete window.xiabanReleaseState;")
	super._exit_tree()
