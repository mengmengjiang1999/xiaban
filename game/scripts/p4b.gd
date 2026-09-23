extends "res://scripts/p3.gd"
## Complete P4 route. A noise is offered independently to every observer.
const FullLevel = preload("res://scripts/p4b_level.gd")
const OfficeGuard = preload("res://scripts/p4_guard.gd")
const FullHud = preload("res://scripts/p4b_hud.gd")
var guards: Array[CharacterBody3D] = []
var outcome := ""
var discovered_by := ""
var _p4b_web_qa_enabled := false

func _create_level() -> Node3D:
	return FullLevel.new()

func _create_hud() -> CanvasLayer:
	return FullHud.new()

func _create_guard() -> CharacterBody3D:
	return OfficeGuard.new()

func _ready() -> void:
	super._ready()
	player.reset_player(level.spawn_position)
	rig.reset_camera()
	for specification in level.guard_specs:
		var observer := _create_guard()
		observer.guard_id = str(specification.id)
		observer.display_name = str(specification.display_name)
		observer.shirt_color = specification.color
		observer.routine_watch_offset = float(specification.watch_offset)
		observer.work_duration = float(specification.work_duration)
		observer.watch_duration = float(specification.watch_duration)
		observer.phase_offset = float(specification.get("phase_offset", 0.0))
		observer.cue_refresh_offset = float(specification.get("cue_refresh_offset", guards.size() * 0.05))
		observer.setup(self, specification.position, float(specification.work_heading))
		observer.discovered.connect(_on_discovered)
		add_child(observer)
		observer.set_frozen(true)
		guards.append(observer)
	player.sprint_noise_emitted.connect(_on_sprint_noise)
	print("P4B_READY leaders=%d platform=%s" % [guards.size(), OS.get_name()])

func start_game() -> void:
	outcome = ""
	discovered_by = ""
	for observer in guards:
		observer.reset_guard()
	super.start_game()
	player.reset_player(level.spawn_position)
	rig.reset_camera()

func _set_phase(next: String) -> void:
	if next == "won":
		for observer in guards:
			if bool(observer.get_status().get("confirmed", false)):
				discovered_by = observer.guard_id
				outcome = observer.display_name + "看见并认出了你"
				next = "lost"
				break
	if next == "lost" and outcome.is_empty():
		outcome = "领导看见并认出了你"
	elif next == "won":
		outcome = "你避开三位领导，走到了楼梯口"
	elif next == "menu":
		outcome = ""
		discovered_by = ""
	super._set_phase(next)
	if next == "lost" and is_instance_valid(player):
		player.cancel_action()
	for observer in guards:
		observer.set_frozen(next != "playing")

func _on_discovered(source: Node) -> void:
	if phase == "playing":
		discovered_by = source.guard_id
		outcome = source.display_name + "看见并认出了你"
		_set_phase("lost")

func _on_sprint_noise(origin: Vector3, radius: float) -> void:
	if phase == "playing":
		for observer in guards:
			# Each observer decides whether this actual sound is within earshot.
			observer.receive_noise(origin, radius)

func _process(delta: float) -> void:
	super._process(delta)
	if not guards.is_empty() and is_instance_valid(hud):
		hud.update_guards(get_guard_statuses(), level.stage_index(player.global_position))

func get_guard_statuses() -> Array[Dictionary]:
	var statuses: Array[Dictionary] = []
	for observer in guards:
		statuses.append(observer.get_status())
	return statuses

func _install_web_qa() -> void:
	super._install_web_qa()
	_p4b_web_qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('p4b_qa') === '1'"))

func _publish_web_qa_state() -> void:
	super._publish_web_qa_state()
	if _p4b_web_qa_enabled and not guards.is_empty():
		var route: Array = []
		for point in level.route_waypoints:
			route.append([point.x, point.y, point.z])
		_web_window.xiabanP4BState = JSON.stringify({
			"guards": get_guard_statuses(), "phase": phase, "outcome": outcome,
			"discovered_by": discovered_by, "stage": level.stage_index(player.global_position),
			"spawn": [level.spawn_position.x, level.spawn_position.y, level.spawn_position.z],
			"exit_rect": [level.exit_rect.position.x, level.exit_rect.position.y, level.exit_rect.size.x, level.exit_rect.size.y],
			"route_waypoints": route,
		})

func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("delete window.xiabanP4BState;")
	super._exit_tree()
