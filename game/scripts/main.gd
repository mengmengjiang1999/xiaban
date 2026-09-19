extends Node3D
## The round owner resolves capture and exit once, including same-frame ties.
const LevelBuilder = preload("res://scripts/level.gd")
const PlayerBuilder = preload("res://scripts/player.gd")
const GuardBuilder = preload("res://scripts/guard.gd")
const HudBuilder = preload("res://scripts/hud.gd")
const SPAWN := Vector3(5.5,0.05,28.6)
var phase: String = "menu"
var elapsed: float = 0.0
var level: Node3D
var player: CharacterBody3D
var guards: Array = []
var hud: CanvasLayer
var camera: Camera3D
var exit_rect := Rect2(2.5,0.5,4,2)
var _caught_guard: Node
var _volume: float = 0.45
var _tones: Dictionary = {}
var _audio: AudioStreamPlayer
var _footstep_clock: float = 0.0
var _cue_clock: float = 0.0
var _last_stage: int = 1

func _ready() -> void:
	_register_inputs()
	var font: Font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	_build_lighting()
	level = LevelBuilder.new()
	level.font = font
	add_child(level)
	exit_rect = level.exit_rect
	player = PlayerBuilder.new()
	player.setup(self)
	add_child(player)
	player.reset_player(SPAWN)
	var routes: Array = [[Vector3(12,0,24)],[Vector3(20.5,0,17.5),Vector3(16.5,0,17.5),Vector3(16.5,0,12),Vector3(12,0,12)],[Vector3(16,0,4.5),Vector3(21,0,4.5),Vector3(11,0,4.5)]]
	for i in range(3):
		var guard = GuardBuilder.new()
		var route: Array[Vector3] = []
		for p in routes[i]:
			route.append(p)
		guard.setup(self,i,route)
		add_child(guard)
		guard.caught.connect(_on_caught)
		guard.spotted.connect(_on_spotted)
		guards.append(guard)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21.0
	camera.far = 90.0
	camera.current = true
	add_child(camera)
	_update_camera(1.0,true)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_make_audio()
	_load_settings()
	hud = HudBuilder.new()
	hud.setup(font)
	add_child(hud)
	hud.start_requested.connect(start_game)
	hud.retry_requested.connect(restart_game)
	hud.pause_requested.connect(pause_game)
	hud.resume_requested.connect(resume_game)
	hud.menu_requested.connect(_show_menu)
	hud.volume_changed.connect(_set_volume)
	hud.fullscreen_requested.connect(_toggle_fullscreen)
	hud.set_volume(_volume)
	hud.show_phase(phase)
	print("LEVEL_READY platform=%s guards=%d" % [OS.get_name(),guards.size()])

func _register_inputs() -> void:
	var mappings := {"move_up":[KEY_W,KEY_UP],"move_down":[KEY_S,KEY_DOWN],"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"sprint":[KEY_SHIFT]}
	for action in mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in mappings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action,event):
				InputMap.action_add_event(action,event)

func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("14222d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c5d9e2")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58,-24,0)
	sun.light_color = Color("ffe1b6")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)

func _process(delta: float) -> void:
	_cue_clock = maxf(0.0,_cue_clock-delta)
	if phase == "playing":
		_resolve_outcome()
		_update_camera(delta)
		var danger := 0.0
		var name_text := ""
		for guard in guards:
			if guard.alert > danger:
				danger = guard.alert
				name_text = guard.display_name
		var stage := 1 if player.position.z > 20 else (2 if player.position.z > 10 else 3)
		if stage != _last_stage:
			_last_stage = stage
			emit_cue("stage")
		hud.update_game(stage,danger,name_text,elapsed)

func _physics_process(delta: float) -> void:
	if phase != "playing":
		return
	elapsed += delta
	_footstep_clock -= delta
	if Vector2(player.velocity.x,player.velocity.z).length() > 0.4 and _footstep_clock <= 0:
		_footstep_clock = 0.27 if Input.is_action_pressed("sprint") else 0.38
		if not _audio.playing:
			_play_tone("step",-17.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if phase == "playing":
				pause_game()
			elif phase == "paused":
				resume_game()
		elif event.physical_keycode == KEY_R and phase in ["won","lost"]:
			restart_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase == "playing":
		pause_game()

func _update_camera(delta: float,snap: bool=false) -> void:
	var focus := Vector3(12,0,clampf(player.position.z,7.5,24.0))
	var desired := focus+Vector3(0,21,13.5)
	camera.position = desired if snap else camera.position.lerp(desired,1.0-exp(-6.0*delta))
	camera.look_at(camera.position-Vector3(0,21,13.5),Vector3.UP)

func start_game() -> void:
	_reset_round()
	phase = "playing"
	hud.show_phase(phase)
	hud.update_game(1,0.0,"",0.0)
	emit_cue("start")
	print("GAME_STATE playing")

func restart_game() -> void:
	start_game()

func _reset_round() -> void:
	elapsed = 0.0
	_caught_guard = null
	_last_stage = 1
	_footstep_clock = 0.0
	player.reset_player(SPAWN)
	for guard in guards:
		guard.reset_guard()
	_audio.stop()
	_update_camera(1.0,true)

func pause_game() -> void:
	if phase != "playing":
		return
	phase = "paused"
	_audio.stop()
	hud.show_phase(phase)
	print("GAME_STATE paused")

func resume_game() -> void:
	if phase != "paused":
		return
	phase = "playing"
	hud.show_phase(phase)
	print("GAME_STATE playing")

func _show_menu() -> void:
	phase = "menu"
	_reset_round()
	hud.show_phase(phase)

func _on_caught(guard: Node) -> void:
	if phase == "playing":
		_caught_guard = guard

func _on_spotted(_guard: Node) -> void:
	emit_cue("alarm")

func _resolve_outcome() -> void:
	if phase != "playing":
		return
	for guard in guards:
		if guard.state != "chase":
			continue
		var flat := Vector2(guard.position.x-player.position.x,guard.position.z-player.position.z)
		if flat.length() < 0.76:
			var query := PhysicsRayQueryParameters3D.create(guard.global_position+Vector3.UP*0.55,player.global_position+Vector3.UP*0.55,1)
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				_caught_guard = guard
	if _caught_guard != null:
		_finish(false,"被%s叫住了：\n“正好，还有个需求……”" % _caught_guard.display_name)
	elif exit_rect.has_point(Vector2(player.position.x,player.position.z)):
		_finish(true,"今天的工作，到此为止。\n门外的时间属于你。")

func _finish(won: bool,detail: String) -> void:
	if phase != "playing":
		return
	phase = "won" if won else "lost"
	player.velocity = Vector3.ZERO
	hud.show_phase(phase,detail,elapsed)
	emit_cue("win" if won else "lose")
	print("GAME_STATE %s time=%.2f" % [phase,elapsed])

func find_path(from: Vector3,to: Vector3) -> PackedVector3Array:
	return level.find_path(from,to)

func is_point_walkable(point: Vector3,radius: float=0.35) -> bool:
	return level.is_point_walkable(point,radius)

func emit_cue(kind: String) -> void:
	if not is_instance_valid(_audio):
		return
	if kind == "alarm" and _cue_clock > 0:
		return
	if kind == "alarm":
		_cue_clock = 0.8
	_play_tone(kind,-5.0)

func _play_tone(kind: String,db: float) -> void:
	if not _tones.has(kind) or _volume <= 0.001:
		return
	_audio.stop()
	_audio.stream = _tones[kind]
	_audio.volume_db = linear_to_db(_volume)+db
	_audio.play()

func _make_audio() -> void:
	var sequences := {"step":[110.0],"start":[440.0,660.0],"stage":[520.0,780.0],"alarm":[660.0,440.0,660.0],"win":[440.0,554.0,660.0,880.0],"lose":[330.0,260.0,196.0]}
	for key in sequences:
		var duration := 0.06 if key == "step" else 0.15
		var notes: Array = sequences[key]
		var pcm := PackedByteArray()
		for note in notes:
			var samples := int(22050*duration)
			for i in range(samples):
				var t := float(i)/22050.0
				var envelope := sin(PI*float(i)/samples)*exp(-t*5.0)
				var sample := int(sin(TAU*float(note)*t)*envelope*6500.0)
				pcm.append(sample & 255)
				pcm.append((sample >> 8) & 255)
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		stream.data = pcm
		_tones[key] = stream

func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		_volume = clampf(float(settings.get_value("audio","volume",0.45)),0.0,1.0)

func _set_volume(value: float) -> void:
	_volume = clampf(value,0.0,1.0)
	if _volume <= 0.001:
		_audio.stop()
	var settings := ConfigFile.new()
	settings.set_value("audio","volume",_volume)
	# Persistence is optional; inability to save must never block playing.
	settings.save("user://settings.cfg")

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
