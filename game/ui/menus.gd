class_name Menus
extends RefCounted
## 界面构建小工具（纯代码，无场景文件）。界面文字只用中文与 ASCII，避免手机字体缺字。


## 返回 [根节点, 内容 VBox, 标题栏 HBox]
static func screen(title: String) -> Array:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 28)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 44)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(t)
	box.add_child(bar)
	return [root, box, bar]


static func button(text: String, cb: Callable, min_w := 360) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 68)
	b.pressed.connect(cb)
	return b


static func label(text: String, fs := 24, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 卡片：上图下字的按钮。toggle=true 时可作为单选项。
static func card(tex: Texture2D, title: String, sub: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(190, 200)
	b.text = title + ("\n" + sub if sub != "" else "")
	b.icon = tex
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_font_size_override("font_size", 22)
	b.toggle_mode = toggle
	if toggle:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color(0.25, 0.22, 0.12)
		sel.border_color = Palette.GOLD
		sel.set_border_width_all(4)
		sel.set_corner_radius_all(4)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
	b.pressed.connect(cb)
	return b


## 可滚动的卡片网格。返回 [ScrollContainer, GridContainer]
static func grid(columns := 5) -> Array:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	sc.add_child(g)
	return [sc, g]


## 两列只读表格（名称 / 值）。
static func table(rows: Array, fs := 22) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 6)
	for r in rows:
		var k := label(str(r[0]), fs)
		k.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
		g.add_child(k)
		var v := label(str(r[1]), fs, true)
		v.custom_minimum_size.x = 520
		g.add_child(v)
	return g


static func scroll(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


static func num(v) -> String:
	return PackValidator.fmt(v)
