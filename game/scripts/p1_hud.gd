extends CanvasLayer
const INK := Color("142b35")
const MINT := Color("8de5c5")
const WHITE := Color("eff7f3")
const MUTED := Color("aec5cc")
var _world: Node
var _root: Control
var _shade: ColorRect
var _panel: PanelContainer
var _heading: Label
var _description: Label
var _primary: Button
var _restart: Button
var _menu: Button
var _game: Control
var _status: Label
var _route: Label

func setup(world: Node) -> void:
	_world = world

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", WHITE)
	_root.theme = theme
	add_child(_root)
	_game = Control.new()
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_game)
	var top := PanelContainer.new()
	top.position = Vector2(24, 24)
	top.add_theme_stylebox_override("panel", _style(INK, 18))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(top)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	top.add_child(stack)
	stack.add_child(_label("下班  /  移动与镜头试玩", 20, MINT))
	_route = _label("01  离开工位", 18)
	stack.add_child(_route)
	_status = _label("", 14, MUTED)
	stack.add_child(_status)
	var keys := PanelContainer.new()
	keys.anchor_top = 1
	keys.anchor_bottom = 1
	keys.anchor_right = 1
	keys.offset_left = 24
	keys.offset_right = -24
	keys.offset_top = -72
	keys.offset_bottom = -20
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_theme_stylebox_override("panel", _style(INK, 14))
	_game.add_child(keys)
	var key_label := _label("W 前进   S 倒退   A / D 转身     右键拖动 观察     滚轮 调距     F 回正     Esc 暂停", 16, MUTED)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_child(key_label)
	_shade = ColorRect.new()
	_shade.color = Color(0.02, 0.06, 0.08, 0.78)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -280
	_panel.offset_right = 280
	_panel.offset_top = -295
	_panel.offset_bottom = 295
	_panel.add_theme_stylebox_override("panel", _style(INK, 30))
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	box.add_child(_label("OFFICE ESCAPE    /    P1", 15, MINT))
	_heading = _label("下班", 46)
	box.add_child(_heading)
	_description = _label("", 18, MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(500, 68)
	box.add_child(_description)
	box.add_child(_label("W 前进 · S 倒退 · A / D 左右转身\n右键拖动环绕观察 · 滚轮调节远近\nF 快速回正 · Esc 暂停并释放鼠标", 17))
	_primary = _button("开始试玩  →", _activate, true)
	box.add_child(_primary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_restart = _button("重新开始", _world.restart_game)
	row.add_child(_restart)
	_menu = _button("返回菜单", _world.show_menu)
	row.add_child(_menu)
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	box.add_child(settings)
	settings.add_child(_label("观察灵敏度", 15, MUTED))
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 2.0
	slider.step = 0.1
	slider.value = 1.0
	slider.custom_minimum_size.x = 140
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float): _world.rig.mouse_sensitivity = 0.004 * value)
	settings.add_child(slider)
	settings.add_child(_button("全屏", _world.toggle_fullscreen))

func _activate() -> void:
	if _world.phase == "paused":
		_world.resume_game()
	else:
		_world.start_game()

func show_phase(phase: String) -> void:
	if _panel == null:
		return
	_game.visible = phase == "playing"
	_panel.visible = phase != "playing"
	_shade.visible = phase != "playing"
	_restart.visible = phase == "paused"
	_menu.visible = phase != "menu"
	_heading.text = "休息一下" if phase == "paused" else ("走到出口了" if phase == "won" else "下班")
	_primary.text = "点击继续  →" if phase == "paused" else ("再走一遍  →" if phase == "won" else "开始试玩  →")
	_description.text = "进度已暂停。点击继续后重新控制角色。" if phase == "paused" else ("移动路线体验完成。可以再试试转角观察、\n倒退和不同的镜头距离。" if phase == "won" else "从工位走到楼梯入口，试试移动和观察。\n本阶段使用胶囊角色，尚未接入领导与潜行规则。")
	if phase != "playing":
		_primary.call_deferred("grab_focus")

func update_game(elapsed: float, distance: float, z: float) -> void:
	_status.text = "%02d:%02d   ·   已走 %.1f 米" % [int(elapsed) / 60, int(elapsed) % 60, distance]
	_route.text = "01  沿前方通道离开工位" if z > 20 else ("02  穿过办公室，寻找下一处门口" if z > 10 else "03  前往绿色楼梯入口")

func _label(text: String, size: int, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", INK if primary else WHITE)
	button.add_theme_color_override("font_hover_color", INK if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", INK if primary else WHITE)
	button.add_theme_color_override("font_focus_color", INK if primary else WHITE)
	button.add_theme_stylebox_override("normal", _style(MINT if primary else Color("294550"), 10))
	button.add_theme_stylebox_override("hover", _style(Color("b5f2d9") if primary else Color("3a5862"), 10))
	button.add_theme_stylebox_override("pressed", _style(Color("66c6a7") if primary else Color("223a46"), 10))
	# Press, not release: browsers require capture/fullscreen within a user gesture.
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(callback)
	return button

func _style(color: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
