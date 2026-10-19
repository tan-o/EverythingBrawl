class_name CharacterDetail
extends RefCounted
## 角色详情（只读）：概览 / 招式 / 按键 / 动画 / 校验与点数。

const TYPE_NAMES := {"move": "移动", "jump": "跳跃", "fly": "飞行", "swing": "挥砍", "shoot": "射击", "pose": "姿势"}
const KIND_NAMES := {"bullet": "子弹", "beam": "光束", "deployable": "布置物"}
const STATUS_NAMES := {"burn": "灼烧", "slow": "减速", "stun": "眩晕", "root": "定身", "silence": "沉默"}
const DIR_NAMES := {"neutral": "不推摇杆", "side": "左右", "up": "上", "down": "下"}


static func key_name(k: String) -> String:
	if k == "jump":
		return "跳跃键"
	if k == "grab":
		return "防御中按攻击（抓取）"
	if k == "attack.dash":
		return "跑动中按攻击"
	var parts := k.split(".")
	var s: String = ("攻击" if parts[0] == "attack" else "特殊") + " + " + DIR_NAMES.get(parts[1], parts[1])
	if parts.size() > 2:
		s += "（空中）"
	return s


static func build(e: Dictionary, on_practice: Callable, on_delete: Callable, on_back: Callable, on_showcase: Callable = Callable()) -> Control:
	var v: PackValidator = e.v
	var s := Menus.screen(e.name)
	var box: VBoxContainer = s[1]
	var bar: HBoxContainer = s[2]
	if e.valid:
		if on_showcase.is_valid():
			bar.add_child(Menus.button("技能展示", on_showcase, 180))
		bar.add_child(Menus.button("试玩", on_practice, 160))
	if e.user:
		bar.add_child(Menus.button("删除", on_delete, 160))
	bar.add_child(Menus.button("返回", on_back, 160))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 24)
	box.add_child(tabs)
	if e.valid:
		_add_tab(tabs, "概览", Menus.scroll(_overview(e)))
		_add_tab(tabs, "招式", Menus.scroll(_moves(v)))
		_add_tab(tabs, "按键", Menus.scroll(_inputs(v)))
		_add_tab(tabs, "动画", Menus.scroll(_anims(v)))
	var rep := TextEdit.new()
	rep.text = v.report()
	rep.editable = false
	rep.add_theme_font_size_override("font_size", 20)
	_add_tab(tabs, "校验与点数", rep)
	return s[0]


static func _add_tab(tabs: TabContainer, title: String, c: Control) -> void:
	c.name = title
	tabs.add_child(c)


static func _overview(e: Dictionary) -> Control:
	var v: PackValidator = e.v
	var d: Dictionary = v.data
	var st: Dictionary = d.stats
	var mv: Dictionary = {}
	var jp: Dictionary = {}
	for a in d.actions.values():
		if a.type == "move":
			mv = a
		elif a.type == "jump":
			jp = a
	var arc := PackPoints.jump_arc(jp.velocity, st.gravity, st.max_fall)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var pic := TextureRect.new()
	pic.texture = e.tex
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(200, 200)
	row.add_child(pic)
	var rows := [
		["来源", "导入" if e.user else "内置示例"],
		["血量", Menus.num(st.hp)],
		["碰撞箱", "%s x %s" % [Menus.num(st.body[0]), Menus.num(st.body[1])]],
		["重量", Menus.num(st.weight)],
		["重力 / 最大下落速度", "%s / %s" % [Menus.num(st.gravity), Menus.num(st.max_fall)]],
		["空中操控", Menus.num(st.air_control)],
		["移动速度 / 加速度", "%s / %s" % [Menus.num(mv.speed), Menus.num(mv.accel)]],
		["跳跃初速 / 次数", "%s / %s" % [Menus.num(jp.velocity), Menus.num(jp.max_count)]],
		["起跳高度 / 跳跃距离", "%s 像素 / %s 像素" % [Menus.num(snappedf(arc[0], 0.1)), Menus.num(snappedf(arc[1] * mv.speed, 0.1))]],
		["常态武器", d.get("held", "无") if d.get("held") != null else "无"],
		["动作数", str(d.actions.size())],
		["形态数", str(d.get("forms", []).size())],
	]
	var res: Dictionary = d.get("resources", {})
	for rn in res:
		var r: Dictionary = res[rn]
		rows.append(["资源 " + rn, "初始 %s，上限 %s%s%s" % [Menus.num(r.init), Menus.num(r.max), "，循环" if r.get("wrap", false) else "", "，每帧回复 %s" % Menus.num(r.regen) if r.get("regen", 0) != 0 else ""]])
	var labels: Array = v.points.keys()
	labels.sort()
	for label in labels:
		rows.append(["点数（形态 %s）" % label, "%s / %s" % [Menus.num(snappedf(v.points[label].total, 0.01)), Menus.num(Rules.data().points.form_max)]])
	row.add_child(Menus.table(rows))
	return row


static func _bound_keys(d: Dictionary, aid: String) -> Array:
	var keys := []
	for k in d.input:
		if d.input[k] == aid:
			keys.append(key_name(k))
	var forms: Array = d.get("forms", [])
	for i in forms.size():
		for k in forms[i].get("input", {}):
			if forms[i].input[k] == aid:
				keys.append(key_name(k) + "（形态 %d）" % i)
	return keys


static func _moves(v: PackValidator) -> Control:
	var d: Dictionary = v.data
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 18)
	var ids: Array = d.actions.keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = d.actions[aid]
		var title := "%s  [%s]" % [aid, TYPE_NAMES.get(a.type, a.type)]
		if a.get("ultimate", false):
			title += "  大招"
		var t := Menus.label(title, 26)
		t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		list.add_child(t)
		var rows := []
		var keys := _bound_keys(d, aid)
		if a.get("ultimate", false):
			keys.append("大招键（大招槽满时）")
		rows.append(["按键", ", ".join(PackedStringArray(keys)) if not keys.is_empty() else "无（由联动触发）"])
		if a.type in ["swing", "shoot"]:
			rows.append(["前摇 / 生效 / 后摇", "%s / %s / %s 帧" % [Menus.num(a.startup), Menus.num(a.active), Menus.num(a.recovery)]])
			rows.append(["伤害", Menus.num(a.damage) + ("（每 %s 帧可再次命中）" % Menus.num(a.hit_interval) if a.get("hit_interval", 0) > 0 else "")])
			rows.append(["击退", "角度 %s，力度 %s" % [Menus.num(a.knockback.angle), Menus.num(a.knockback.force)]])
			if a.type == "swing":
				rows.append(["武器", "%s，角度 %s 到 %s，伸出 %s 到 %s%s" % [a.weapon, Menus.num(a.from), Menus.num(a.to), Menus.num(a.reach[0]), Menus.num(a.reach[1]), "，抓取" if a.get("grab", false) else ""]])
			else:
				var kind := CharDef.shoot_kind(a, d.assets)
				rows.append(["子弹", "%s（%s），速度 %s，存在 %s 帧，数量 %s" % [a.projectile, KIND_NAMES[kind], Menus.num(a.speed), Menus.num(a.lifetime), Menus.num(a.get("count", 1))]])
			if "status" in a:
				rows.append(["状态", "%s %s 帧" % [STATUS_NAMES[a.status.type], Menus.num(a.status.duration)]])
			if "charge" in a:
				rows.append(["蓄力", "最多 %s 帧，伤害 x%s，击退 x%s" % [Menus.num(a.charge.max), Menus.num(a.charge.damage), Menus.num(a.charge.force)]])
		elif a.type == "move":
			rows.append(["速度 / 加速度", "%s / %s" % [Menus.num(a.speed), Menus.num(a.accel)]])
		elif a.type == "jump":
			rows.append(["初速 / 次数", "%s / %s" % [Menus.num(a.velocity), Menus.num(a.max_count)]])
		elif a.type == "fly":
			rows.append(["时长 / 上升 / 操控", "%s / %s / %s" % [Menus.num(a.duration), Menus.num(a.rise_speed), Menus.num(a.control)]])
		if "throw" in a:
			rows.append(["投掷", "第 %s 帧，伤害 %s，力度 %s" % [Menus.num(a.throw.frame), Menus.num(a.throw.damage), Menus.num(a.throw.knockback.force)]])
		for k in [["armor", "霸体"], ["invuln", "无敌"], ["reflect", "反射"]]:
			if k[0] in a:
				rows.append([k[1], "第 %s 到 %s 帧" % [Menus.num(a[k[0]][0]), Menus.num(a[k[0]][1])]])
		if a.get("cooldown", 0) > 0:
			rows.append(["冷却", "%s 帧" % Menus.num(a.cooldown)])
		if "cost" in a:
			var cs := PackedStringArray()
			for rn in a.cost:
				cs.append("%s %s" % [rn, Menus.num(a.cost[rn])])
			rows.append(["消耗", ", ".join(cs)])
		var links: Array = a.get("links", [])
		if not links.is_empty():
			var ls := PackedStringArray()
			for l in links:
				ls.append(_link_text(l))
			rows.append(["联动", "\n".join(ls)])
		if not a.get("upgrades", []).is_empty():
			rows.append(["升级", "%d 级" % a.upgrades.size()])
		for b in v.points.values():
			if aid in b.actions:
				rows.append(["点数", Menus.num(snappedf(b.actions[aid], 0.01))])
				break
		list.add_child(Menus.table(rows, 20))
	return list


static func _link_text(l: Dictionary) -> String:
	var when: String = {
		"on_start": "开始时", "on_end": "结束时", "on_frame": "第 %s 帧" % Menus.num(l.get("frame", 0)),
		"every": "每 %s 帧" % Menus.num(l.get("interval", 0)), "on_hit": "命中时", "on_whiff": "落空时",
		"on_land": "落地时", "on_release": "松开按键时", "on_hurt": "被击中时",
		"projectile_hit": "子弹命中时", "projectile_expire": "子弹消失时",
		"resource_empty": "资源耗尽时", "resource_full": "资源满时",
	}.get(l.when, l.when)
	var cond := ""
	if "input" in l:
		cond += "，按 %s" % l.input
	if "window" in l:
		cond += "（第 %s 到 %s 帧内）" % [Menus.num(l.window[0]), Menus.num(l.window[1])]
	var eff := PackedStringArray()
	if "goto" in l:
		eff.append("接 " + l.goto)
	if "spawn" in l:
		eff.append("发射 " + l.spawn)
	for k in ["gain", "spend", "set"]:
		for rn in l.get(k, {}):
			eff.append({"gain": "获得", "spend": "消耗", "set": "设为"}[k] + " %s %s" % [rn, Menus.num(l[k][rn])])
	if "heal" in l:
		eff.append("回复 %s" % Menus.num(l.heal))
	if "warp" in l:
		eff.append("瞬移到子弹处")
	return when + cond + "：" + ("，".join(eff) if not eff.is_empty() else "特效 / 音效")


static func _inputs(v: PackValidator) -> Control:
	var d: Dictionary = v.data
	var rows := []
	var keys: Array = d.input.keys()
	keys.sort()
	for k in keys:
		rows.append([key_name(k), d.input[k]])
	var forms: Array = d.get("forms", [])
	for i in forms.size():
		var cond := PackedStringArray()
		for rn in forms[i]["if"]:
			cond.append("%s %s" % [rn, forms[i]["if"][rn]])
		rows.append(["形态 %d（%s）" % [i, " 且 ".join(cond)], ""])
		for k in forms[i].get("input", {}):
			rows.append(["    " + key_name(k), forms[i].input[k]])
	rows.append(["防御中推左右 / 推下", "翻滚 / 原地闪避（引擎内置）"])
	rows.append(["空中按防御", "空中闪避（引擎内置）"])
	rows.append(["空中下落时推下", "快速下落（引擎内置）"])
	rows.append(["轻点跳跃键", "小跳（引擎内置）"])
	return Menus.table(rows)


static func _anims(v: PackValidator) -> Control:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 16)
	var names: Array = v.data.anims.keys()
	names.sort()
	for n in names:
		var cell := VBoxContainer.new()
		cell.add_child(AnimPreview.make(v, n, 3.0))
		cell.add_child(Menus.label(n, 20))
		g.add_child(cell)
	return g
