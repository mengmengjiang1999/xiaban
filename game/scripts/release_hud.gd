extends "res://scripts/p4b_hud.gd"
var _volume: HSlider
var _volume_label: Label
var _sensitivity: HSlider
var _hint: Label

func _ready() -> void:
	super._ready()
	_panel.offset_top = -320
	_panel.offset_bottom = 320
	_panel.add_theme_stylebox_override("panel", _style(INK, 24))
	var box: VBoxContainer = _heading.get_parent()
	box.add_theme_constant_override("separation", 10)
	_heading.add_theme_font_size_override("font_size", 34)
	_description.add_theme_font_size_override("font_size", 17)
	for node in _root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text.begins_with("OFFICE ESCAPE"):
			label.text = "OFFICE ESCAPE   /   第一关"
		elif "Space" in label.text and label.get_parent() == box:
			label.text = "W / S 前进倒退 · A / D 转身 · C 蹲起\n站立 Shift + W 冲刺 · 蹲下 Space 向前翻滚\n方向键 / 右键观察 · 滚轮调距 · F 回正 · Esc 暂停"
			label.add_theme_font_size_override("font_size", 16)
		elif "右键" in label.text and "Space" in label.text:
			label.text = "W / S 前后 · A / D 转身    C 蹲起 · Shift+W 冲刺 · 蹲姿 Space 翻滚\n方向键 / 右键 观察 · 滚轮 调距 · F 回正 · Esc 暂停"
		elif label.text == "观察灵敏度":
			label.text = "鼠标观察灵敏度"
	for node in _root.find_children("*", "HSlider", true, false):
		_sensitivity = node as HSlider
		break
	_sensitivity.value_changed.connect(func(value: float): _world.change_setting("sensitivity", value))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_label("游戏音量", 15, MUTED))
	_volume = HSlider.new()
	_volume.min_value = 0
	_volume.max_value = 1
	_volume.step = 0.05
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.focus_mode = Control.FOCUS_NONE
	_volume.custom_minimum_size = Vector2(140, 28)
	_volume.value_changed.connect(_volume_changed)
	row.add_child(_volume)
	_volume_label = _label("65%", 14, MUTED)
	_volume_label.custom_minimum_size.x = 45
	row.add_child(_volume_label)
	box.add_child(_label("单人潜行 · 本地保存音量与灵敏度", 13, MUTED))
	_hint = _label("", 14, MINT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(330, 42)
	_route.get_parent().add_child(_hint)
	show_phase(_world.phase)

func apply_settings(values: Dictionary) -> void:
	_volume.set_value_no_signal(values.volume)
	_sensitivity.set_value_no_signal(values.sensitivity)
	_update_volume_text(values.volume)

func _volume_changed(value: float) -> void:
	_update_volume_text(value)
	_world.change_setting("volume", value)

func _update_volume_text(value: float) -> void:
	_volume_label.text = "静音" if value <= 0 else "%d%%" % roundi(value * 100)

func show_phase(phase: String) -> void:
	super.show_phase(phase)
	if _panel == null:
		return
	match phase:
		"menu":
			_heading.text = "今天，也要准时下班"
			_primary.text = "开始下班  →"
			_description.text = "先在高柜后观察，趁领导低头向前移动。\n到矮柜后按 C 蹲下；转好方向，再按空格翻滚。\n穿过三段办公区，走到绿色楼梯口就能下班。"
		"paused":
			_description.text = "进度已暂停，领导也在等待。\n矮柜需要蹲下藏身；冲刺的脚步会引起注意。\n调整好音量与灵敏度，再继续出发。"
		"lost":
			_description.text = _world.outcome + "。\n先借高柜等他低头，再蹲着沿矮柜通过。\n黄色区域提示朝向；真正挡住身体的掩体才安全。"
		"won":
			_heading.text = "下班，回家"
			_description.text = "用时 %02d:%02d，走过 %.1f 米。\n你避开三位领导，走到了楼梯口。\n今天的工作到这里，剩下的时间属于自己。" % [int(_world.elapsed) / 60, int(_world.elapsed) % 60, _world.player.travel_distance]

func update_controls(status: Dictionary) -> void:
	super.update_controls(status)
	if _hint == null:
		return
	var stage: int = _world.level.stage_index(_world.player.global_position)
	var z: float = _world.player.global_position.z
	var before_cover: bool = z > [31.8, 20.3, 8.8][stage]
	if (z >= 23.3 and z <= 25.6) or (z >= 11.2 and z <= 13.4):
		_hint.text = "在走廊停下观察，沿指示牌前往下一处入口。"
	elif status.get("state", "") == "roll":
		_hint.text = "翻滚朝向已锁定，落稳后再继续移动。"
	elif before_cover:
		_hint.text = "方向键观察周围，F 回正；领导低头时再向前挪。"
	elif status.get("stance", "standing") == "standing":
		_hint.text = "矮柜挡不住站立身体，按 C 蹲下。"
	else:
		_hint.text = "保持蹲姿沿柜通过；Space 朝人物前方翻滚。"

func get_release_controls() -> Dictionary:
	var result := {}
	for key in {"volume": _volume, "sensitivity": _sensitivity}:
		var control: Control = _volume if key == "volume" else _sensitivity
		var rect := control.get_global_rect()
		result[key] = {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "visible": control.is_visible_in_tree()}
	return result
