class_name Menus
extends RefCounted
## 菜单界面构建（纯代码，无场景文件）。


static func screen(title: String) -> Array:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 32)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 44)
	box.add_child(t)
	return [root, box]


static func button(text: String, cb: Callable, min_w := 360) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 68)
	b.pressed.connect(cb)
	return b


static func label(text: String, fs := 24) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
