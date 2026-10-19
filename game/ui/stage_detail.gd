class_name StageDetail
extends RefCounted
## 场景详情（只读）：预览图、元素列表、校验结果。

const COLLIDE := {"solid": "实心", "platform": "单向平台", "none": "区域"}


static func behaviors(el: Dictionary) -> String:
	var out := PackedStringArray()
	if "trap" in el:
		out.append("发射陷阱" if el.trap.type == "shoot" else "挥击陷阱")
	if "climb" in el:
		out.append("可攀爬 %s 帧" % Menus.num(el.climb.max))
	if "crumble" in el:
		out.append("站 %s 帧后碎裂，%s 帧后恢复" % [Menus.num(el.crumble.after), Menus.num(el.crumble.respawn)])
	if "bounce" in el:
		out.append("弹跳 %s" % Menus.num(el.bounce.velocity))
	if "friction" in el:
		out.append("摩擦 x%s" % Menus.num(el.friction))
	if "conveyor" in el:
		out.append("传送带 %s" % Menus.num(el.conveyor))
	if "move" in el:
		out.append("移动（%d 个点，周期 %s 帧）" % [el.move.path.size(), Menus.num(el.move.period)])
	if "damage" in el:
		out.append("伤害 %s，每 %s 帧" % [Menus.num(el.damage.damage), Menus.num(el.damage.interval)])
	if "wind" in el:
		out.append("风 (%s, %s)" % [Menus.num(el.wind[0]), Menus.num(el.wind[1])])
	if "water" in el:
		out.append("水（重力 x%s）" % Menus.num(el.water.gravity_mul))
	if "blink" in el:
		out.append("出现 %s 帧 / 消失 %s 帧" % [Menus.num(el.blink.on), Menus.num(el.blink.off)])
	if "breakable" in el:
		out.append("可打碎（%s 血）" % Menus.num(el.breakable.hp))
	return "，".join(out) if not out.is_empty() else "无"


## 场景预览：在 SubViewport 里画一次场景。
static func preview(v: PackValidator, k := 1.5) -> Control:
	var R := Rules.data()
	var vp := SubViewport.new()
	vp.size = Vector2i(int(R.stage.width), int(R.stage.height))
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var sv := StageView.build(v)
	vp.add_child(sv)
	var st := Stage.new(v.data)
	sv.apply(st.snapshot())
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = Vector2(vp.size) * k
	tr.add_child(vp)
	# 出生点标记
	var marks := Control.new()
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.draw.connect(func():
		for i in st.spawns.size():
			var p: Vector2 = st.spawns[i] * k
			marks.draw_rect(Rect2(p - Vector2(6, 16), Vector2(12, 16)), Palette.player(i), false, 2.0))
	tr.add_child(marks)
	return tr


static func build(e: Dictionary, on_practice: Callable, on_delete: Callable, on_back: Callable) -> Control:
	var v: PackValidator = e.v
	var s := Menus.screen(e.name)
	var box: VBoxContainer = s[1]
	var bar: HBoxContainer = s[2]
	if e.valid:
		bar.add_child(Menus.button("在这里试玩", on_practice, 200))
	if e.user:
		bar.add_child(Menus.button("删除", on_delete, 160))
	bar.add_child(Menus.button("返回", on_back, 160))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 24)
	box.add_child(tabs)
	if e.valid:
		var c := CenterContainer.new()
		c.name = "预览"
		c.add_child(preview(v))
		tabs.add_child(c)
		var rows := []
		var els: Array = v.data.elements
		for i in els.size():
			var el: Dictionary = els[i]
			rows.append(["%s（%s）" % [el.get("id", "元素 %d" % i), COLLIDE[el.collide]], behaviors(el)])
		var t := Menus.scroll(Menus.table(rows))
		t.name = "元素"
		tabs.add_child(t)
	var rep := TextEdit.new()
	rep.name = "校验"
	rep.text = v.report()
	rep.editable = false
	rep.add_theme_font_size_override("font_size", 20)
	tabs.add_child(rep)
	return s[0]
