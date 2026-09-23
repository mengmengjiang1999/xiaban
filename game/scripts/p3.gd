extends "res://scripts/p1.gd"
const ControlPlayer = preload("res://scripts/p3_player.gd")
const ControlHud = preload("res://scripts/p3_hud.gd")
const CONTROL_ACTIONS := {"crouch_toggle": KEY_C, "sprint": KEY_SHIFT, "roll": KEY_SPACE}
var _p3_web_qa_enabled := false

func _create_player() -> CharacterBody3D:
	return ControlPlayer.new()

func _create_hud() -> CanvasLayer:
	return ControlHud.new()

func _ready() -> void:
	for action in CONTROL_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = CONTROL_ACTIONS[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	super._ready()
	print("P3_READY platform=%s" % OS.get_name())

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(hud):
		hud.update_controls(player.get_control_status())

func _unhandled_input(event: InputEvent) -> void:
	if phase == "playing" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_C:
			player.request_crouch_toggle()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_SPACE:
			player.request_roll()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _clear_input() -> void:
	for action in CONTROL_ACTIONS:
		Input.action_release(action)
	super._clear_input()

func _set_phase(next: String) -> void:
	super._set_phase(next)
	if next in ["menu", "won"] and is_instance_valid(player):
		player.cancel_action()

func _install_web_qa() -> void:
	super._install_web_qa()
	_p3_web_qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('p3_qa') === '1'"))

func _publish_web_qa_state() -> void:
	super._publish_web_qa_state()
	if _p3_web_qa_enabled and is_instance_valid(player):
		_web_window.xiabanP3State = JSON.stringify(player.get_control_status())

func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("delete window.xiabanP3State;")
	super._exit_tree()
