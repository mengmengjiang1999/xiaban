extends "res://scripts/p1.gd"
## P2 validates one humanoid and its clips; it does not define P3 action controls.
const HumanoidPlayer = preload("res://scripts/p2_player.gd")
const HumanoidHud = preload("res://scripts/p2_hud.gd")
const PREVIEW_KEYS := {
	KEY_1: "idle",
	KEY_2: "walk",
	KEY_3: "run",
	KEY_4: "crouch_idle",
	KEY_5: "crouch_walk",
	KEY_6: "roll",
	KEY_0: "",
}
var _p2_web_qa_enabled: bool = false


func _create_player() -> CharacterBody3D:
	return HumanoidPlayer.new()


func _create_hud() -> CanvasLayer:
	return HumanoidHud.new()


func _ready() -> void:
	super._ready()
	_update_animation_hud()
	print("P2_READY platform=%s" % OS.get_name())


func _process(delta: float) -> void:
	super._process(delta)
	_update_animation_hud()


func _unhandled_input(event: InputEvent) -> void:
	if phase == "playing" and event is InputEventKey and event.pressed and not event.echo:
		if PREVIEW_KEYS.has(event.physical_keycode):
			player.set_preview_action(PREVIEW_KEYS[event.physical_keycode])
			_update_animation_hud()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _update_animation_hud() -> void:
	if is_instance_valid(player) and is_instance_valid(hud):
		hud.update_animation_status(player.get_animation_status(), player.preview_action)


func _install_web_qa() -> void:
	super._install_web_qa()
	# Like P1, observation is opt-in and exposes no gameplay control callback.
	_p2_web_qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('p2_qa') === '1'"))


func _publish_web_qa_state() -> void:
	super._publish_web_qa_state()
	if _p2_web_qa_enabled and is_instance_valid(player):
		_web_window.xiabanP2State = JSON.stringify({
			"phase": phase,
			"preview_action": player.preview_action,
			"animation_status": player.get_animation_status(),
		})


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("delete window.xiabanP2State;")
	super._exit_tree()
