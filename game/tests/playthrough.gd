extends SceneTree
## Full-level acceptance: move only through public input actions and wait.
## Never teleport, alter guards, disable collision, or call the finish method.

const ROUTE: Array[Vector2] = [
	Vector2(5.5, 21.5), Vector2(5.5, 17.4), Vector2(8.8, 17.4),
	Vector2(8.8, 12), Vector2(8.8, 13.25), Vector2(18.5, 13.25),
	Vector2(18.5, 8.4), Vector2(11.5, 8.4), Vector2(11.5, 6),
	Vector2(4.5, 6), Vector2(4.5, 1.5)
]
const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "sprint"]

var world: Node3D
var _peak_alerts: Array[float] = [0.0, 0.0, 0.0]
var _chases: Array[bool] = [false, false, false]
var _last_states: Array[String] = ["", "", ""]
var _scenario := ""
var _frame_budget := 12000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	# Accelerated simulation tests gameplay, not real-time audio. Do not change saved settings.
	world.set("_volume", 0.0)
	await _ticks(3)
	var wins := 0
	var observation_won := false
	var sprint_triggered_chase := false
	var walking_was_caught := false
	for test_case in [["blind_sprint", true, false], ["blind_walk", false, false], ["observe_and_cross", false, true]]:
		var won := await _run_route(test_case[0], test_case[1], test_case[2])
		if won:
			wins += 1
		if test_case[0] == "observe_and_cross":
			observation_won = won and not _chases.has(true)
		elif test_case[0] == "blind_sprint":
			sprint_triggered_chase = _chases.has(true)
		elif test_case[0] == "blind_walk":
			walking_was_caught = world.phase == "lost"
	_release_input()
	var passed := observation_won and sprint_triggered_chase and walking_was_caught
	print("PLAYTHROUGH_RESULT wins=%d / 3 observation_safe=%s blind_sprint_chase=%s blind_walk_caught=%s acceptance=%s" % [
		wins, observation_won, sprint_triggered_chase, walking_was_caught, "PASS" if passed else "FAIL"
	])
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)


func _run_route(label: String, sprint: bool, cautious: bool) -> bool:
	_release_input()
	_scenario = label
	_peak_alerts = [0.0, 0.0, 0.0]
	_chases = [false, false, false]
	_last_states = ["", "", ""]
	_frame_budget = 12000
	world.start_game()
	print("SCENARIO_START %s" % label)
	await _ticks(2)
	if cautious:
		await _wait_for_first_turn()
	for index in ROUTE.size():
		var destination := ROUTE[index]
		if cautious and index == 4:
			await _wait_for_office_return()
		elif cautious and index == 8:
			await _wait_for_departure(2, 12.5)
		var crossing: bool = cautious and index in [5, 6, 8, 9]
		var reached := await _walk_to(destination, sprint or crossing)
		print("SEGMENT %s #%02d target=%s reached=%s elapsed=%.2f position=%s alert=%s chase=%s" % [
			label, index + 1, destination, reached, world.elapsed,
			world.player.position, _peak_alerts, _chases
		])
		if world.phase != "playing" or not reached:
			break
	_release_input()
	await _ticks(4)
	var won: bool = world.phase == "won"
	print("SCENARIO_RESULT %s phase=%s time=%.2f max_alert=%s chases=%s" % [
		label, world.phase, world.elapsed, _peak_alerts, _chases
	])
	if won and _peak_alerts.max() < 0.02:
		print("BALANCE_WARNING %s bypassed all three bosses without meaningful alert" % label)
	return won


func _wait_for_first_turn() -> void:
	_release_input()
	var started: float = world.elapsed
	var guard = world.guards[0]
	for frame in 1200:
		if world.phase != "playing":
			break
		if guard.facing.z > 0.8 and guard.state == "patrol":
			break
		await _ticks(1)
	print("OBSERVE %s L1 turned_to_desk waited=%.2f facing=%s" % [_scenario, world.elapsed - started, guard.facing])


func _wait_for_office_return() -> void:
	_release_input()
	var started: float = world.elapsed
	var guard = world.guards[1]
	for frame in 2400:
		if world.phase != "playing":
			break
		if guard.position.z > 14.6 and guard.facing.z > 0.65 and guard.state == "patrol":
			break
		await _ticks(1)
	print("OBSERVE %s L2 returned_to_office waited=%.2f position=%s facing=%s" % [_scenario, world.elapsed - started, guard.position, guard.facing])


func _wait_for_departure(guard_index: int, left_limit: float) -> void:
	_release_input()
	var started: float = world.elapsed
	var guard = world.guards[guard_index]
	# Watch the boss reach the left endpoint and turn away. This is the
	# same observable cue available to a player behind the nearby cabinet.
	for frame in 2400:
		if world.phase != "playing":
			break
		if guard.position.x < left_limit and guard.facing.x > 0.6 and guard.state == "patrol":
			break
		await _ticks(1)
	print("OBSERVE %s L%d waited=%.2f position=%s facing=%s" % [_scenario, guard_index + 1, world.elapsed - started, guard.position, guard.facing])


func _walk_to(destination: Vector2, sprint: bool) -> bool:
	var stuck_frames := 0
	var previous: Vector3 = world.player.position
	while world.phase == "playing" and _frame_budget > 0:
		var at := Vector2(world.player.position.x, world.player.position.z)
		var difference := destination - at
		if difference.length() < 0.10:
			_release_input()
			return true
		_release_input()
		if absf(difference.x) > 0.035:
			Input.action_press("move_right" if difference.x > 0 else "move_left")
		if absf(difference.y) > 0.035:
			Input.action_press("move_down" if difference.y > 0 else "move_up")
		if sprint:
			Input.action_press("sprint")
		await _ticks(1)
		if world.player.position.distance_to(previous) < 0.001:
			stuck_frames += 1
		else:
			stuck_frames = 0
		previous = world.player.position
		if stuck_frames > 180:
			print("STUCK %s at=%s target=%s" % [_scenario, previous, destination])
			break
	_release_input()
	return false


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		_frame_budget -= 1
		if world != null and world.phase == "playing":
			for index in world.guards.size():
				var guard = world.guards[index]
				_peak_alerts[index] = maxf(_peak_alerts[index], guard.alert)
				_chases[index] = _chases[index] or guard.state == "chase"
				if guard.state != _last_states[index]:
					print("GUARD %s L%d %s elapsed=%.2f alert=%.3f" % [_scenario, index + 1, guard.state, world.elapsed, guard.alert])
					_last_states[index] = guard.state


func _release_input() -> void:
	for action in MOVE_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)
