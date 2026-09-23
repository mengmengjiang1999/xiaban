extends "res://scripts/p3_hud.gd"
var _guard_status: Label
var _suspicion: ProgressBar
var _suspicion_label: Label
const GUARD_LABELS := {"working": "领导低头办公 · 可以观察通路", "raising": "领导即将抬头 · 留意掩体", "watching": "领导正在观察 · 注意遮挡", "lowering": "领导正在收回视线"}

func _ready() -> void:
	super._ready()
	for node in _root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == "下班  /  蹲起、冲刺与翻滚":
			label.text = "下班  /  悄悄离开办公室"
		elif label.text == "OFFICE ESCAPE    /    P3":
			label.text = "OFFICE ESCAPE    /    P4a"
	_guard_status = _label("领导低头办公", 16, Color("ffd88d"))
	_route.get_parent().add_child(_guard_status)
	_suspicion_label = _label("", 14, Color("ffab91"))
	_route.get_parent().add_child(_suspicion_label)
	_suspicion = ProgressBar.new()
	_suspicion.max_value = 1.0
	_suspicion.show_percentage = false
	_suspicion.custom_minimum_size = Vector2(0, 6)
	_suspicion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suspicion.add_theme_stylebox_override("background", _style(Color("294550"), 0))
	_suspicion.add_theme_stylebox_override("fill", _style(Color("f08366"), 0))
	_route.get_parent().add_child(_suspicion)
	show_phase(_world.phase)

func show_phase(phase: String) -> void:
	super.show_phase(phase)
	if _panel == null:
		return
	match phase:
		"menu":
			_heading.text = "趁领导低头，出门"
			_heading.add_theme_font_size_override("font_size", 34)
			_description.text = "观察领导抬头的节奏，沿左侧通道到绿色门口。\n矮柜后蹲下能藏住身体；冲刺声会引他转头。\n黄色地面表示观察方向，能否藏住还取决于掩体。"
		"paused":
			_heading.text = "稍等一下"
			_description.text = "人物、领导和发现进度都已暂停。\n点击继续后，从当前动作接着玩。"
		"lost":
			_heading.text = "被领导发现了"
			_description.text = "领导实际看见并认出了你。\n下一次，留意抬头提示，或在矮柜后蹲下。"
			_primary.text = "重新尝试  →"
			_menu.visible = true
		"won":
			_heading.text = "悄悄出门了"
			_description.text = "你避开了这位领导，顺利离开办公室。\n可以再试一遍，比较蹲行、等待和安静翻滚。"
			_primary.text = "再试一次  →"

func update_game(time: float, distance: float, z: float) -> void:
	_status.text = "%02d:%02d   ·   已走 %.1f 米" % [int(time) / 60, int(time) % 60, distance]
	_route.text = "01  借高柜观察领导" if z > 11.0 else ("02  沿矮柜蹲行，等待机会" if z > 6.0 else "03  前往绿色门口")

func update_guard(status: Dictionary) -> void:
	if _guard_status == null:
		return
	var state := str(status.get("state", "working"))
	var alert := float(status.get("progress", 0.0))
	_guard_status.text = str(GUARD_LABELS.get(state, state))
	if bool(status.get("noise_attention", false)) and state in ["raising", "watching"]:
		_guard_status.text = "听到脚步 · 领导正看向声源"
	_suspicion.visible = alert > 0.0
	_suspicion_label.visible = alert > 0.0
	_suspicion.value = alert
	_suspicion_label.text = "正被注意，尽快进入遮挡"
