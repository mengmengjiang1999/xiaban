extends "res://scripts/p4_hud.gd"
const ROUTE_LABELS := ["01 / 03  离开工位，借矮柜隐蔽", "02 / 03  穿过办公室门前", "03 / 03  留意楼梯口，准备下班"]

func _ready() -> void:
	super._ready()
	for node in _root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == "下班  /  悄悄离开办公室":
			label.text = "下班  /  避开三位领导"
		elif label.text == "OFFICE ESCAPE    /    P4a":
			label.text = "OFFICE ESCAPE    /    第一关"
	show_phase(_world.phase)

func show_phase(phase: String) -> void:
	super.show_phase(phase)
	if _panel == null:
		return
	match phase:
		"menu":
			_heading.text = "今天，也要准时下班"
			_description.text = "从工位出发，经过办公室，走到绿色楼梯口。\n三位领导各自办公；抬头时利用掩体躲开视线。\n冲刺声会引起转头，转角的走廊可以停下观察。"
		"lost":
			_heading.text = "这次没能溜走"
			_description.text = _world.outcome + "。\n再试一次，留意抬头提示，利用高柜与矮柜。"
		"won":
			_heading.text = "终于下班了"
			_description.text = "你穿过三段办公区，顺利到达楼梯口。\n可以再试一遍，选择不同的行动时机。"

func update_game(time: float, distance: float, _z: float) -> void:
	_status.text = "%02d:%02d   ·   已走 %.1f 米" % [int(time) / 60, int(time) % 60, distance]
	_route.text = ROUTE_LABELS[clampi(_world.level.stage_index(_world.player.global_position), 0, 2)]

func update_guards(statuses: Array[Dictionary], stage: int) -> void:
	if statuses.is_empty():
		return
	var focus := statuses[clampi(stage, 0, statuses.size() - 1)]
	for status in statuses:
		if float(status.progress) > float(focus.progress):
			focus = status
	update_guard(focus)
	_guard_status.text = str(focus.display_name) + " · " + _guard_status.text.trim_prefix("领导")
