extends "res://scripts/p4b.gd"
## Finished first level; the P4 route and detection rules remain the same.
const ReleaseLevel = preload("res://scripts/release_level.gd")
const ReleaseGuard = preload("res://scripts/release_guard.gd")
const ReleaseCharacter = preload("res://scripts/release_character.gd")
const ReleaseHud = preload("res://scripts/release_hud.gd")
const ReleaseAudio = preload("res://scripts/release_audio.gd")
const SETTINGS_PATH := "user://release-settings.cfg"
var audio: Node
var settings := {"volume": 0.65, "sensitivity": 1.0}
var _settings_dirty := false
var _save_delay := 0.0
var _release_web_qa_enabled := false

func _create_level() -> Node3D:
	return ReleaseLevel.new()

func _create_hud() -> CanvasLayer:
	return ReleaseHud.new()

func _create_guard() -> CharacterBody3D:
	return ReleaseGuard.new()

func _ready() -> void:
	_load_settings()
	super._ready()
	ReleaseCharacter.apply_to(player.actor, "player")
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
	print("RELEASE_READY leaders=%d version=%s platform=%s" % [guards.size(), ProjectSettings.get_setting("application/config/version"), OS.get_name()])

func _set_phase(next: String) -> void:
	var previous := phase
	super._set_phase(next)
	if is_instance_valid(audio):
		audio.change_phase(previous, phase)

func _process(delta: float) -> void:
	super._process(delta)
	if _settings_dirty:
		_save_delay -= delta
		if _save_delay <= 0:
			_save_settings()

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
	if _release_web_qa_enabled and is_instance_valid(audio):
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
