extends Node
## Original procedural foley; cosmetic sounds never feed the guards' hearing.
const BUS := "Xiaban"
const SAMPLE_RATE := 22050
var _world: Node
var _ambient: AudioStreamPlayer
var _effects: AudioStreamPlayer
var _office: Array[AudioStreamPlayer3D] = []
var _timers: Array[float] = [0.4, 0.85, 1.3]
var _guard_states: Array[String] = []
var _last_control := ""
var _noticed := false
var _volume := 0.65
var _streams := {}
var _events := {"start": 0, "raise": 0, "notice": 0, "crouch": 0, "roll": 0, "office": 0, "won": 0, "lost": 0}

func setup(world: Node) -> void:
	_world = world

func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
	for kind in ["air", "keys", "paper", "pen", "start", "raise", "notice", "crouch", "roll", "won", "lost"]:
		_streams[kind] = _make_sound(kind)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = BUS
	_ambient.stream = _streams.air
	_ambient.volume_db = -29
	add_child(_ambient)
	_effects = AudioStreamPlayer.new()
	_effects.bus = BUS
	_effects.volume_db = -16
	add_child(_effects)
	for observer in _world.guards:
		var source := AudioStreamPlayer3D.new()
		source.bus = BUS
		source.stream = _streams[["keys", "paper", "pen"][_office.size()]]
		source.volume_db = -13
		source.max_distance = 12
		source.unit_size = 2
		add_child(source)
		source.global_position = observer.global_position + Vector3(0, 0.9, 0)
		_office.append(source)
		_guard_states.append("working")
	# Include the existing sprint footfall in the same volume control.
	for node in _world.player.find_children("*", "AudioStreamPlayer3D", true, false):
		node.bus = BUS
	set_volume(_volume)

func set_volume(value: float) -> void:
	_volume = clampf(value, 0, 1)
	var index := AudioServer.get_bus_index(BUS)
	if index >= 0:
		AudioServer.set_bus_mute(index, _volume <= 0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(_volume, 0.0001)))

func change_phase(previous: String, next: String) -> void:
	if next == "playing":
		if not _ambient.playing:
			_ambient.play()
		_ambient.stream_paused = false
		if previous != "paused":
			_play("start")
			_last_control = ""
			_noticed = false
	else:
		_ambient.stream_paused = true
		for source in _office:
			source.stop()
		_effects.stop()
		if next in ["won", "lost"] and next != previous:
			_play(next)

func _process(delta: float) -> void:
	if _world.phase != "playing":
		return
	var control: Dictionary = _world.player.get_control_status()
	var current := str(control.get("state", "")) + ":" + str(control.get("stance", ""))
	if current != _last_control and not _last_control.is_empty():
		if control.get("state", "") == "roll":
			_play("roll")
		elif str(control.get("stance", "")) != _last_control.get_slice(":", 1):
			_play("crouch")
	_last_control = current
	var attention := false
	for index in _office.size():
		var observer: Node3D = _world.guards[index]
		var status: Dictionary = observer.get_status()
		var state := str(status.state)
		if state == "raising" and _guard_states[index] != state and observer.global_position.distance_to(_world.player.global_position) < 9:
			_play("raise")
		_guard_states[index] = state
		attention = attention or float(status.progress) > 0
		_timers[index] -= delta
		if state == "working" and _timers[index] <= 0:
			_office[index].play()
			_events.office += 1
			_timers[index] = [0.78, 1.7, 1.1][index]
		elif state != "working":
			_office[index].stop()
	if attention and not _noticed:
		_play("notice")
	_noticed = attention

func _play(kind: String) -> void:
	_events[kind] += 1
	_effects.stream = _streams[kind]
	_effects.play()

func get_status() -> Dictionary:
	return {"volume": _volume, "muted": _volume <= 0, "event_counts": _events.duplicate(), "ambient_playing": _ambient.playing and not _ambient.stream_paused, "phase": _world.phase}

func _make_sound(kind: String) -> AudioStreamWAV:
	var duration := 0.24
	if kind == "air": duration = 4.0
	elif kind in ["won", "lost"]: duration = 1.3
	elif kind == "roll": duration = 0.5
	elif kind in ["paper", "keys"]: duration = 0.36
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 827 + kind.hash()
	var filtered := 0.0
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var progress := time / duration
		var envelope := sin(PI * progress) * exp(-progress * 3)
		var noise := rng.randf_range(-1.0, 1.0)
		filtered = lerpf(filtered, noise, 0.12)
		var value := 0.0
		match kind:
			"air": value = (filtered * 0.16 + sin(TAU * 60 * time) * 0.035) * minf(1.0, minf(time, duration - time) * 25)
			"keys":
				var tick := fmod(time, 0.09)
				value = (noise * 0.4 + sin(TAU * 620 * time) * 0.15) * exp(-tick * 160) * sin(PI * progress)
			"paper", "roll", "crouch": value = filtered * envelope * 2.5
			"pen": value = (sin(TAU * 820 * time) * 0.3 + noise * 0.15) * exp(-time * 80)
			"raise": value = sin(TAU * 420 * time) * envelope * 0.2
			"notice": value = sin(TAU * (300 * time + 280 * time * time)) * envelope * 0.55
			"start": value = (sin(TAU * 440 * time) + sin(TAU * 660 * time)) * envelope * 0.3
			"won":
				for note in 3:
					var nt := time - note * 0.15
					if nt >= 0:
						value += sin(TAU * [440, 554.37, 659.25][note] * nt) * exp(-nt * 3) * minf(nt * 50, 1) * 0.23
			"lost": value = (sin(TAU * 220 * time) + sin(TAU * 174.61 * time)) * envelope * 0.28
		bytes.encode_s16(index * 2, int(clampf(value, -0.95, 0.95) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	if kind == "air":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream
