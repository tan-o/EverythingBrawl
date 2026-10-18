extends Control
## 应用入口：主菜单 / 本地对战设置 / 角色包 / 联机测试 / 对战。

const INPUTS := ["touch", "kb1", "kb2", "none"]
const INPUT_NAMES := {"touch": "触屏", "kb1": "键盘 A", "kb2": "键盘 B", "none": "无操作"}

var current: Control
var packs := []           # [{path, v}]
var picks := [0, 1, 0, 1]
var input_picks := [0, 2, 3, 3]
var player_count := 2


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font_size = 28
	self.theme = theme
	get_window().files_dropped.connect(_on_files_dropped)
	_show_menu()


func _set_screen(c: Control) -> void:
	if current != null:
		current.queue_free()
	current = c
	add_child(c)


func _reload_packs() -> void:
	packs = []
	for p in PackLibrary.paths():
		packs.append({"path": p, "v": PackLibrary.load_pack(p)})


func _valid_packs() -> Array:
	var out := []
	for p in packs:
		if p.v.is_valid():
			out.append(p)
	return out


func _show_menu() -> void:
	var s := Menus.screen("像素大乱斗")
	var box: VBoxContainer = s[1]
	box.add_child(Menus.button("本地对战", _show_versus))
	box.add_child(Menus.button("角色包", _show_packs))
	box.add_child(Menus.button("联机延迟测试（ENet）", _show_net))
	box.add_child(Menus.label("键盘 A：WASD 移动，J 攻击，K 特殊，空格 跳，L 防御，U 大招\n键盘 B：方向键，, 攻击，. 特殊，/ 跳，Shift 防御，' 大招", 20))
	_set_screen(s[0])


func _show_versus() -> void:
	_reload_packs()
	var valid := _valid_packs()
	var s := Menus.screen("本地对战")
	var box: VBoxContainer = s[1]
	if valid.size() == 0:
		box.add_child(Menus.label("没有可用的角色包。"))
		box.add_child(Menus.button("返回", _show_menu))
		_set_screen(s[0])
		return
	var count_row := HBoxContainer.new()
	count_row.add_child(Menus.label("人数"))
	for n in [2, 3, 4]:
		var b := Menus.button("%d 人" % n, _set_count.bind(n), 120)
		b.disabled = n == player_count
		count_row.add_child(b)
	box.add_child(count_row)
	for i in player_count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := Menus.label("P%d" % (i + 1))
		l.add_theme_color_override("font_color", Palette.player(i))
		l.custom_minimum_size.x = 60
		row.add_child(l)
		picks[i] = picks[i] % valid.size()
		var pb := Menus.button(valid[picks[i]].v.data.name, _cycle_pick.bind(i, valid.size()), 320)
		row.add_child(pb)
		var ib := Menus.button(INPUT_NAMES[INPUTS[input_picks[i]]], _cycle_input.bind(i), 200)
		row.add_child(ib)
		box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(Menus.button("开始", _start_match, 240))
	row2.add_child(Menus.button("返回", _show_menu, 240))
	box.add_child(row2)
	_set_screen(s[0])


func _set_count(n: int) -> void:
	player_count = n
	_show_versus()


func _cycle_pick(i: int, n: int) -> void:
	picks[i] = (picks[i] + 1) % n
	_show_versus()


func _cycle_input(i: int) -> void:
	input_picks[i] = (input_picks[i] + 1) % INPUTS.size()
	_show_versus()


func _start_match() -> void:
	var valid := _valid_packs()
	var players := []
	for i in player_count:
		players.append({"validator": valid[picks[i] % valid.size()].v, "input": INPUTS[input_picks[i]]})
	var m := MatchScreen.new()
	_set_screen(m)
	m.start(players)
	m.exited.connect(_show_versus)


func _show_packs() -> void:
	_reload_packs()
	var s := Menus.screen("角色包")
	var box: VBoxContainer = s[1]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)
	for p in packs:
		var v: PackValidator = p.v
		var name: String = v.data.get("name", p.path.get_file()) if v.data != null and not v.data.is_empty() else p.path.get_file()
		var text: String = ("✔ " if v.is_valid() else "✘ ") + name + "    " + p.path.get_file()
		list.add_child(Menus.button(text, _show_report.bind(p), 600))
	box.add_child(Menus.label("导入：把角色包 zip 拖到窗口上，或放入 %s" % ProjectSettings.globalize_path(PackLibrary.USER), 18))
	box.add_child(Menus.button("返回", _show_menu))
	_set_screen(s[0])


func _show_report(p: Dictionary) -> void:
	var s := Menus.screen(p.path.get_file())
	var box: VBoxContainer = s[1]
	var t := TextEdit.new()
	t.text = p.v.report()
	t.editable = false
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 20)
	box.add_child(t)
	box.add_child(Menus.button("返回", _show_packs))
	_set_screen(s[0])


func _show_net() -> void:
	var n := NetDemo.new()
	_set_screen(n)
	n.exited.connect(_show_menu)


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.ends_with(".zip"):
			PackLibrary.import_file(f)
	_show_packs()
