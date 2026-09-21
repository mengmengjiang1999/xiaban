extends "res://scripts/p1_hud.gd"
## Reuse proven capture, pause and settings controls with compact P2 labels.
const ACTION_LABELS := {
	"idle": "站立",
	"walk": "行走",
	"run": "跑步",
	"crouch_idle": "蹲姿",
	"crouch_walk": "蹲走",
	"roll": "翻滚",
}
const MOVEMENT_HINT := "W / S 前后 · A / D 转身    右键 观察 · 滚轮 调距 · F 回正 · Esc 暂停"
const PREVIEW_HINT := "原地动作展示：1 站立 · 2 行走 · 3 跑步 · 4 蹲姿 · 5 蹲走 · 6 翻滚    0 返回行走试玩"
var _animation_status: Label


func _ready() -> void:
	super._ready()
	for node in _root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == "下班  /  移动与镜头试玩":
			label.text = "下班  /  人形动作样板"
		elif label.text == "OFFICE ESCAPE    /    P1":
			label.text = "OFFICE ESCAPE    /    P2"
		elif label.text.begins_with("W 前进   S 倒退"):
			label.text = MOVEMENT_HINT + "\n" + PREVIEW_HINT
			label.add_theme_font_size_override("font_size", 15)
			label.get_parent().offset_top = -94
	_animation_status = _label("行走试玩  ·  当前动作：站立", 15, MINT)
	_route.get_parent().add_child(_animation_status)
	show_phase(_world.phase)


func show_phase(phase: String) -> void:
	super.show_phase(phase)
	if _panel == null:
		return
	if phase == "menu":
		_heading.text = "人形动作样板"
		_primary.text = "开始体验  →"
		_description.text = "用一个人形检查走、跑、蹲与翻滚的动作表现。\n1–6 仅播放原地动作，0 返回行走试玩。\n蹲姿碰撞、冲刺与翻滚控制留在后续阶段。"
	elif phase == "paused":
		_heading.text = "样板已暂停"
		_description.text = "点击继续后恢复当前动作与观察。\n重新开始将返回正常行走试玩。"
	elif phase == "won":
		_heading.text = "人形走到出口了"
		_description.text = "人形已完成办公室行走路线。\n可重新开始，用 1–6 检查原地动作；0 返回行走试玩。"


func update_animation_status(status: Dictionary, preview_action: String) -> void:
	if _animation_status == null:
		return
	var action := str(status.get("action", status.get("animation", "idle")))
	if not preview_action.is_empty():
		action = preview_action
	var label := str(ACTION_LABELS.get(action, action))
	_animation_status.text = "原地动作展示：%s  ·  0 返回行走试玩" % label if not preview_action.is_empty() else "行走试玩  ·  当前动作：%s" % label
