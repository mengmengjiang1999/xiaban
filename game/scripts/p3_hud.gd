extends "res://scripts/p1_hud.gd"
const LABELS := {"idle": "站立", "walk": "行走", "crouch_idle": "蹲姿", "crouch_walk": "蹲行", "sprint": "冲刺 · 脚步声较响", "roll": "翻滚", "recovery": "翻滚收势"}
var _controls: Label
var _feedback: Label

func _ready() -> void:
	super._ready()
	for node in _root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == "下班  /  移动与镜头试玩":
			label.text = "下班  /  蹲起、冲刺与翻滚"
		elif label.text == "OFFICE ESCAPE    /    P1":
			label.text = "OFFICE ESCAPE    /    P3"
		elif label.text.begins_with("W 前进   S 倒退"):
			label.text = "W / S 前后 · A / D 转身    C 蹲起 · Shift+W 冲刺 · 蹲姿 Space 翻滚\n右键 观察 · 滚轮 调距 · F 回正 · Esc 暂停"
			label.add_theme_font_size_override("font_size", 15)
			label.get_parent().offset_top = -94
		elif label.text.begins_with("W 前进 · S 倒退"):
			label.text = "C 切换蹲起 · 站姿 Shift+W 冲刺\n蹲姿 Space 向前翻滚 · 途中保持方向\n右键观察 · 滚轮调距 · F 回正 · Esc 暂停"
	_controls = _label("站立", 16, MINT)
	_route.get_parent().add_child(_controls)
	_feedback = _label("", 14, Color("ffd88d"))
	_route.get_parent().add_child(_feedback)
	show_phase(_world.phase)

func show_phase(phase: String) -> void:
	super.show_phase(phase)
	if _panel == null:
		return
	if phase == "menu":
		_heading.text = "动起来，再下班"
		_description.text = "穿过办公室，体验站立、蹲行、冲刺和翻滚。\n空间不足时无法站起或翻滚，碰到障碍会停下。"
	elif phase == "paused":
		_description.text = "动作和计时已暂停。点击继续接着玩；\n重新开始会恢复站姿，并返回工位。"
	elif phase == "won":
		_description.text = "已完成办公室路线。\n可以重新开始，尝试不同的移动方式。"

func update_controls(status: Dictionary) -> void:
	if _controls == null:
		return
	_controls.text = str(LABELS.get(status.state, status.state))
	_feedback.text = status.feedback
	_feedback.visible = not _feedback.text.is_empty()
