class_name TouchControls
extends Control
## 手机操作：左侧浮动虚拟摇杆；右侧 攻击 / 特殊 / 跳跃 / 防御 四键，大招槽满时出现大招键。

const BTNS := [
	{"key": "attack", "label": "攻", "pos": Vector2(-150, -150), "r": 62},
	{"key": "special", "label": "特", "pos": Vector2(-290, -95), "r": 56},
	{"key": "jump", "label": "跳", "pos": Vector2(-110, -295), "r": 52},
	{"key": "guard", "label": "防", "pos": Vector2(-280, -235), "r": 46},
	{"key": "ult", "label": "大招", "pos": Vector2(-420, -110), "r": 50},
]
const STICK_R := 110.0

var ult_ready := false
var stick := Vector2.ZERO
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_touch := {}      # touch index -> key


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func buttons() -> int:
	var b := 0
	for k in _btn_touch.values():
		b |= InputFrame.BUTTONS[k]
	return b


func _btn_center(d: Dictionary) -> Vector2:
	return size + d.pos


func _hit_button(p: Vector2) -> String:
	for d in BTNS:
		if d.key == "ult" and not ult_ready:
			continue
		if p.distance_to(_btn_center(d)) <= d.r * 1.15:
			return d.key
	return ""


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			var k := _hit_button(p)
			if k != "":
				_btn_touch[event.index] = k
			elif p.x < size.x * 0.5 and _stick_touch == -1:
				_stick_touch = event.index
				_stick_origin = p
				_stick_pos = p
		else:
			_btn_touch.erase(event.index)
			if event.index == _stick_touch:
				_stick_touch = -1
				stick = Vector2.ZERO
		queue_redraw()
	elif event is InputEventScreenDrag:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.index == _stick_touch:
			_stick_pos = p
			stick = ((p - _stick_origin) / STICK_R).limit_length(1.0)
		elif event.index in _btn_touch:
			# 手指滑到别的键上时切换（例如从攻击滑到跳跃）
			var k := _hit_button(p)
			if k != "":
				_btn_touch[event.index] = k
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if _stick_touch != -1:
		draw_circle(_stick_origin, STICK_R, Color(1, 1, 1, 0.12))
		draw_circle(_stick_origin + stick * STICK_R, 44, Color(1, 1, 1, 0.35))
	else:
		var hint := Vector2(200, size.y - 180)
		draw_arc(hint, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.12), 3)
	var pressed := {}
	for k in _btn_touch.values():
		pressed[k] = true
	for d in BTNS:
		if d.key == "ult" and not ult_ready:
			continue
		var c := _btn_center(d)
		var col := Color(1, 1, 1, 0.45 if d.key in pressed else 0.2)
		if d.key == "ult":
			col = Color(1, 0.75, 0.2, 0.75 if d.key in pressed else 0.5)
		draw_circle(c, d.r, col)
		var fs := 34 if d.label.length() == 1 else 26
		var ts := font.get_string_size(d.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-ts.x / 2.0, fs * 0.35), d.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


func _process(_d: float) -> void:
	queue_redraw()
