extends "res://scripts/p3.gd"
## P4a: one office encounter, from observation through escape or discovery.
const StealthLevel = preload("res://scripts/p4_level.gd")
const OfficeGuard = preload("res://scripts/p4_guard.gd")
const StealthHud = preload("res://scripts/p4_hud.gd")
var guard: CharacterBody3D
var outcome := ""
var _p4_web_qa_enabled := false

func _create_level() -> Node3D:
	return StealthLevel.new()

func _create_hud() -> CanvasLayer:
	return StealthHud.new()

func _ready() -> void:
	super._ready()
	player.reset_player(level.spawn_position)
	rig.reset_camera()
	guard = OfficeGuard.new()
	guard.setup(self, level.guard_spawn, level.guard_heading)
	guard.discovered.connect(_on_discovered)
	add_child(guard)
	guard.set_frozen(true)
	player.sprint_noise_emitted.connect(_on_sprint_noise)
	print("P4_READY slice=one_office platform=%s" % OS.get_name())

func start_game() -> void:
	outcome = ""
	if is_instance_valid(guard):
		guard.reset_guard()
	super.start_game()
	player.reset_player(level.spawn_position)
	rig.reset_camera()

func _set_phase(next: String) -> void:
	# Discovery is synchronous in physics, before the parent checks the exit.
	if next == "won" and is_instance_valid(guard) and bool(guard.get_status().get("confirmed", false)):
		next = "lost"
	if next == "lost":
		outcome = "领导看见并认出了你"
	elif next == "won":
		outcome = "你悄悄离开了办公室"
	elif next == "menu":
		outcome = ""
	super._set_phase(next)
	if next == "lost" and is_instance_valid(player):
		player.cancel_action()
	if is_instance_valid(guard):
		guard.set_frozen(next != "playing")

func _on_discovered(_source: Node) -> void:
	if phase == "playing":
		_set_phase("lost")

func _on_sprint_noise(origin: Vector3, radius: float) -> void:
	if phase == "playing" and is_instance_valid(guard):
		guard.receive_noise(origin, radius)

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(guard) and is_instance_valid(hud):
		hud.update_guard(guard.get_status())

func _install_web_qa() -> void:
	super._install_web_qa()
	_p4_web_qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('p4_qa') === '1'"))

func _publish_web_qa_state() -> void:
	super._publish_web_qa_state()
	if _p4_web_qa_enabled and is_instance_valid(guard):
		_web_window.xiabanP4State = JSON.stringify({
			"guard": guard.get_status(), "outcome": outcome, "phase": phase,
			"spawn": [level.spawn_position.x, level.spawn_position.y, level.spawn_position.z],
			"exit_rect": [level.exit_rect.position.x, level.exit_rect.position.y, level.exit_rect.size.x, level.exit_rect.size.y],
		})

func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("delete window.xiabanP4State;")
	super._exit_tree()
