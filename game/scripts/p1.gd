extends Node3D
## P1 only: no legacy guard logic is loaded into the new movement sample.
const Level = preload("res://scripts/p1_level.gd")
const Player = preload("res://scripts/p1_player.gd")
const Rig = preload("res://scripts/shoulder_camera.gd")
const Hud = preload("res://scripts/p1_hud.gd")
const SPAWN := Vector3(5.5, 0.05, 27.0)
const ACTIONS := {"move_forward": KEY_W, "move_back": KEY_S, "turn_left": KEY_A, "turn_right": KEY_D}
var phase: String = "menu"
var player: CharacterBody3D
var rig: Node3D
var level: Node3D
var hud: CanvasLayer
var elapsed: float = 0.0
var _capture_grace: float = 0.0
var _web_callback: JavaScriptObject
var _web_window: JavaScriptObject
var _was_fullscreen: bool = false
var _web_qa_enabled: bool = false
var _web_qa_buttons: Dictionary = {}

func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = ACTIONS[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("b0c6c9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d9e7eb")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_color = Color("ffe6c5")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	level = _create_level()
	level.font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	add_child(level)
	player = _create_player()
	player.setup(self)
	add_child(player)
	player.reset_player(SPAWN)
	rig = _create_rig()
	add_child(rig)
	rig.setup(player)
	hud = _create_hud()
	hud.setup(self)
	add_child(hud)
	hud.show_phase(phase)
	_install_web_events()
	_settle_preview()
	print("P1_READY platform=%s" % OS.get_name())

func _create_level() -> Node3D:
	return Level.new()

func _create_player() -> CharacterBody3D:
	return Player.new()

func _create_hud() -> CanvasLayer:
	return Hud.new()

func _create_rig() -> Node3D:
	return Rig.new()

func _settle_preview() -> void:
	# Physics bodies must be registered before resolving the initial menu view.
	await get_tree().physics_frame
	await get_tree().process_frame
	if is_instance_valid(rig):
		rig.update_camera(0.0, true)

func _process(delta: float) -> void:
	if phase == "playing":
		_capture_grace = maxf(0.0, _capture_grace - delta)
		if DisplayServer.get_name() != "headless" and _capture_grace <= 0.0 and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			pause_game()
			_publish_web_qa_state()
			return
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if _was_fullscreen and not fullscreen:
			pause_game()
			_was_fullscreen = false
			_publish_web_qa_state()
			return
		_was_fullscreen = fullscreen
		rig.update_camera(delta)
		hud.update_game(elapsed, player.travel_distance, player.position.z)
		if level.exit_rect.has_point(Vector2(player.position.x, player.position.z)):
			_set_phase("won")
	_publish_web_qa_state()

func _physics_process(delta: float) -> void:
	if phase == "playing":
		elapsed += delta

func _unhandled_input(event: InputEvent) -> void:
	if phase != "playing":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			pause_game()
		elif event.physical_keycode == KEY_F:
			rig.recenter()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			rig.set_observing(event.pressed)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.zoom(1.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom(-1.0)
	elif event is InputEventMouseMotion and rig.observing:
		rig.orbit_motion(event.relative)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		pause_game()

func _clear_input() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	if is_instance_valid(player):
		player.stop_input()
	if is_instance_valid(rig):
		rig.set_observing(false)
		rig.set_look_input(Vector2.ZERO)

func _set_phase(next: String) -> void:
	phase = next
	_clear_input()
	if next != "playing":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(hud):
		hud.show_phase(phase)
	print("P1_STATE %s" % phase)

func _capture() -> void:
	_capture_grace = 0.75
	_was_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_game() -> void:
	player.reset_player(SPAWN)
	elapsed = 0.0
	rig.reset_camera()
	_set_phase("playing")
	_capture()

func restart_game() -> void:
	start_game()

func pause_game() -> void:
	if phase == "playing":
		_set_phase("paused")

func resume_game() -> void:
	if phase == "paused":
		_set_phase("playing")
		_capture()

func show_menu() -> void:
	_set_phase("menu")

func toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _install_web_events() -> void:
	if not OS.has_feature("web"):
		return
	_web_callback = JavaScriptBridge.create_callback(_on_web_event)
	_web_window = JavaScriptBridge.get_interface("window")
	_web_window.xiabanPause = _web_callback
	JavaScriptBridge.eval("""
	window.xiabanListeners = {
	 lock: () => { if (!document.pointerLockElement) window.xiabanPause(); },
	 hidden: () => { if (document.hidden) window.xiabanPause(); },
	 blur: () => window.xiabanPause(),
	 full: () => { if (!document.fullscreenElement) window.xiabanPause(); },
	 context: e => { if (e.target.tagName === 'CANVAS') e.preventDefault(); }
	};
	document.addEventListener('pointerlockchange', window.xiabanListeners.lock);
	document.addEventListener('pointerlockerror', window.xiabanListeners.blur);
	document.addEventListener('visibilitychange', window.xiabanListeners.hidden);
	document.addEventListener('fullscreenchange', window.xiabanListeners.full);
	window.addEventListener('blur', window.xiabanListeners.blur);
	document.addEventListener('contextmenu', window.xiabanListeners.context);
	""")
	_install_web_qa()

func _install_web_qa() -> void:
	# Opt-in, read-only snapshots for tests that drive actual browser input.
	# No callback or incoming test value can alter the scene through this bridge.
	_web_qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('p1_qa') === '1'"))
	if not _web_qa_enabled:
		return
	_web_qa_buttons = {
		"primary": hud.get("_primary"),
		"restart": hud.get("_restart"),
		"menu": hud.get("_menu"),
	}
	for node in hud.find_children("*", "Button", true, false):
		if node is Button and node.text == "全屏":
			_web_qa_buttons["fullscreen"] = node
			break

func _publish_web_qa_state() -> void:
	if not _web_qa_enabled:
		return
	var buttons: Dictionary = {}
	for button_name in _web_qa_buttons:
		var button: Button = _web_qa_buttons[button_name]
		var rect: Rect2 = button.get_global_rect()
		buttons[button_name] = {
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"visible": button.is_visible_in_tree(),
		}
	var camera_position: Vector3 = rig.camera.global_position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_web_window.xiabanP1State = JSON.stringify({
		"phase": phase,
		"elapsed": elapsed,
		"position": [player.position.x, player.position.y, player.position.z],
		"heading": player.rotation.y,
		"travel_distance": player.travel_distance,
		"camera_yaw": rig.yaw,
		"camera_pitch": rig.pitch_degrees,
		"camera_look_input": [rig.look_input.x, rig.look_input.y],
		"recenter_hold_remaining": rig.recenter_hold_remaining,
		"desired_distance": rig.desired_distance,
		"observing": rig.observing,
		"move_input": player.move_input,
		"turn_input": player.turn_input,
		"camera_position": [camera_position.x, camera_position.y, camera_position.z],
		"camera_alpha": player.camera_alpha,
		"viewport": [viewport_size.x, viewport_size.y],
		"buttons": buttons,
	})

func _on_web_event(_args: Array) -> void:
	pause_game()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
		const l = window.xiabanListeners;
		if (l) {
		 document.removeEventListener('pointerlockchange', l.lock);
		 document.removeEventListener('pointerlockerror', l.blur);
		 document.removeEventListener('visibilitychange', l.hidden);
		 document.removeEventListener('fullscreenchange', l.full);
		 document.removeEventListener('contextmenu', l.context);
		 window.removeEventListener('blur', l.blur);
		}
		delete window.xiabanPause; delete window.xiabanListeners; delete window.xiabanP1State;
		""")
