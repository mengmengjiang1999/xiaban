class_name EscapeHUD
extends CanvasLayer
## The HUD only presents state and emits intent; the level owns transitions.

signal start_requested
signal retry_requested
signal pause_requested
signal resume_requested
signal menu_requested
signal volume_changed(value: float)
signal fullscreen_requested

const INK := Color("111f30")
const PANEL := Color("172c40")
const MINT := Color("70e4c5")
const WHITE := Color("eaf5f3")
const MUTED := Color("a1b6c5")
const AMBER := Color("ffc778")
const RED := Color("ff8678")

var _font: Font
var _root: Control
var _game: Control
var _shade: ColorRect
var _menu: PanelContainer
var _pause: PanelContainer
var _result: PanelContainer
var _result_title: Label
var _result_detail: Label
var _result_time: Label
var _result_accent: Label
var _stage_label: Label
var _time_label: Label
var _alert_label: Label
var _alert_bar: ProgressBar
var _hint_label: Label
var _volume_sliders: Array[HSlider] = []
var _volume: float = 0.6


func setup(font: Font) -> void:
	_font = font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	if _font != null:
		theme.default_font = _font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", WHITE)
	_root.theme = theme
	add_child(_root)
	_build_game()
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.055, 0.09, 0.80)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_build_menu()
	_build_pause()
	_build_result()
	show_phase("menu")


func show_phase(phase: String, detail: String = "", elapsed: float = 0.0) -> void:
	if _root == null:
		return
	_game.visible = phase == "playing" or phase == "paused"
	_shade.visible = phase != "playing"
	_menu.visible = phase == "menu"
	_pause.visible = phase == "paused"
	_result.visible = phase == "won" or phase == "lost"
	if _result.visible:
		var won := phase == "won"
		_result_accent.text = "任务完成 / 18:00" if won else "被领导叫住了"
		_result_accent.add_theme_color_override("font_color", MINT if won else AMBER)
		_result_title.text = "准点下班！" if won else "下班失败"
		_result_detail.text = detail if not detail.is_empty() else (
			"你穿过办公室，终于走进了楼梯间。\n今天的工作，就到这里。" if won else
			"“稍等，这个需求我们再聊一下。”\n换一条路线，再试一次。")
		_result_time.text = "本次用时  %s" % _format_time(elapsed)


func update_game(stage: int, alert: float, guard_name: String, elapsed: float) -> void:
	if _stage_label == null:
		return
	var index := clampi(stage, 1, 3)
	_stage_label.text = ["01  离开工位", "02  穿过办公室走廊", "03  进入楼梯间"][index - 1]
	_time_label.text = _format_time(elapsed)
	_hint_label.text = [
		"等领导转身，从左上方门口离开工位。",
		"借高柜挡住视线，前往右上方门口。",
		"观察领导，绕过长柜去左上方绿色出口。"
	][index - 1]
	var value := clampf(alert, 0.0, 1.0)
	_alert_bar.value = value * 100.0
	var color := MINT
	if value >= 0.99:
		color = RED
		_alert_label.text = "被发现了！绕过掩体甩开领导"
	elif value > 0.01:
		color = AMBER
		_alert_label.text = "%s正在注意你 · %d%%" % [guard_name if not guard_name.is_empty() else "领导", roundi(value * 100.0)]
	else:
		_alert_label.text = "暂时安全 · 留意地面的视野范围"
	_alert_label.add_theme_color_override("font_color", color)
	var fill := _alert_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = color


func set_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	for slider in _volume_sliders:
		slider.set_value_no_signal(_volume)


func _build_game() -> void:
	_game = Control.new()
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_game)
	var left := _anchored_panel(_game, Vector4(24, 22, 276, 104))
	var left_row := VBoxContainer.new()
	left_row.add_theme_constant_override("separation", 4)
	left.add_child(left_row)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	left_row.add_child(heading)
	var brand := _label("准点下班", 16, MINT)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(brand)
	_time_label = _label("00:00", 16, MUTED)
	heading.add_child(_time_label)
	_stage_label = _label("01  离开工位", 20)
	left_row.add_child(_stage_label)

	var alert_panel := PanelContainer.new()
	alert_panel.anchor_left = 0.5
	alert_panel.anchor_right = 0.5
	alert_panel.offset_left = -208
	alert_panel.offset_right = 208
	alert_panel.offset_top = 22
	alert_panel.offset_bottom = 104
	alert_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.105, 0.16, 0.92), 14, 16))
	alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(alert_panel)
	var alerts := VBoxContainer.new()
	alerts.add_theme_constant_override("separation", 9)
	alert_panel.add_child(alerts)
	_alert_label = _label("暂时安全 · 留意地面的视野范围", 16, MINT)
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alerts.add_child(_alert_label)
	_alert_bar = ProgressBar.new()
	_alert_bar.custom_minimum_size.y = 7
	_alert_bar.show_percentage = false
	_alert_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_bar.add_theme_stylebox_override("background", _panel_style(Color("2e4352"), 4, 0))
	_alert_bar.add_theme_stylebox_override("fill", _panel_style(MINT, 4, 0))
	alerts.add_child(_alert_bar)

	var pause_button := _button("暂停 Ⅱ", func(): pause_requested.emit(), false)
	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.offset_left = -144
	pause_button.offset_right = -24
	pause_button.offset_top = 22
	pause_button.offset_bottom = 70
	_game.add_child(pause_button)

	var bottom := PanelContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -78
	bottom.offset_bottom = -20
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.105, 0.16, 0.92), 12, 16))
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	bottom.add_child(row)
	var keys := _label("WASD / 方向键  移动    Shift  跑步    Esc  暂停", 15, MUTED)
	row.add_child(keys)
	_hint_label = _label("等领导转身，再穿过办公区。", 16, WHITE)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_hint_label)


func _build_menu() -> void:
	_menu = _center_panel(620, 580)
	var box := _column(_menu, 16)
	box.add_child(_label("OFFICE ESCAPE     /     18:00", 15, MINT))
	box.add_child(_label("准点下班", 54))
	box.add_child(_label("第一关 · 最后一个离开的人", 21, MUTED))
	box.add_child(_space(5))
	var premise := _label("电脑已经关了，领导还没走。\n穿过办公区，绕开三位领导，抵达楼梯出口。", 19)
	premise.add_theme_constant_override("line_spacing", 7)
	box.add_child(premise)
	box.add_child(_label("观察视野   →   等待空隙   →   利用掩体", 17, AMBER))
	box.add_child(_space(2))
	box.add_child(_button("开始下班   →", func(): start_requested.emit()))
	var keys := _label("WASD / 方向键 移动    ·    Shift 跑步    ·    Esc 暂停", 15, MUTED)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)
	box.add_child(_volume_row())


func _build_pause() -> void:
	_pause = _center_panel(520, 445)
	var box := _column(_pause, 16)
	box.add_child(_label("喝口水，再找机会", 15, MINT))
	box.add_child(_label("休息一下", 38))
	box.add_child(_label("时间暂停了，领导也在原地等着。", 17, MUTED))
	box.add_child(_space(3))
	box.add_child(_button("继续下班", func(): resume_requested.emit()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_button("重新开始", func(): retry_requested.emit(), false))
	row.add_child(_button("返回菜单", func(): menu_requested.emit(), false))
	box.add_child(_volume_row())


func _build_result() -> void:
	_result = _center_panel(600, 425)
	var box := _column(_result, 18)
	_result_accent = _label("任务完成 / 18:00", 16, MINT)
	box.add_child(_result_accent)
	_result_title = _label("准点下班！", 44)
	box.add_child(_result_title)
	_result_detail = _label("", 19, MUTED)
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_detail.custom_minimum_size = Vector2(0, 60)
	_result_detail.add_theme_constant_override("line_spacing", 7)
	box.add_child(_result_detail)
	_result_time = _label("本次用时  00:00", 16, AMBER)
	box.add_child(_result_time)
	box.add_child(_space(4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_button("重新开始", func(): retry_requested.emit()))
	row.add_child(_button("返回菜单", func(): menu_requested.emit(), false))


func _volume_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	var label := _label("音量", 15, MUTED)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = _volume
	slider.custom_minimum_size = Vector2(120, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float):
		set_volume(value)
		volume_changed.emit(value)
	)
	_volume_sliders.append(slider)
	row.add_child(slider)
	var fullscreen := _button("全屏", func(): fullscreen_requested.emit(), false)
	fullscreen.custom_minimum_size = Vector2(86, 38)
	fullscreen.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(fullscreen)
	return row


func _center_panel(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -width / 2.0
	panel.offset_right = width / 2.0
	panel.offset_top = -height / 2.0
	panel.offset_bottom = height / 2.0
	panel.add_theme_stylebox_override("panel", _panel_style(INK, 22, 34))
	_root.add_child(panel)
	return panel


func _anchored_panel(parent: Control, rect: Vector4) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.offset_left = rect.x
	panel.offset_top = rect.y
	panel.offset_right = rect.z
	panel.offset_bottom = rect.w
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.105, 0.16, 0.92), 14, 16))
	parent.add_child(panel)
	return panel


func _column(parent: Control, separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _label(text: String, size: int = 18, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, callback: Callable, primary: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else WHITE)
	button.add_theme_color_override("font_hover_color", INK if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", INK if primary else WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(MINT if primary else PANEL, 10, 12))
	button.add_theme_stylebox_override("hover", _panel_style(Color("a0f0d9") if primary else Color("29465d"), 10, 12))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("47c5a9") if primary else Color("203b51"), 10, 12))
	button.pressed.connect(callback)
	return button


func _space(height: float) -> Control:
	var result := Control.new()
	result.custom_minimum_size.y = height
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _panel_style(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _format_time(elapsed: float) -> String:
	var total := maxi(0, int(elapsed))
	return "%02d:%02d" % [total / 60, total % 60]
