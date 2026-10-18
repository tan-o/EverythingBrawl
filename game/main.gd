extends Control
## 应用入口与界面切换：开始游戏（联机大厅）/ 管理角色 / 管理场景 / 网络测试，以及试玩。

const OPPONENT_MODES := [["dummy", "木桩"], ["cpu", "电脑"], ["kb2", "键盘 B"]]

var current: Control
var practice := {"me": "", "foe": "", "mode": "cpu", "stage": ""}   # 试玩设置（存路径）
var _import_kind := "character"


func _ready() -> void:
	self.theme = ArcadeTheme.build()
	get_window().files_dropped.connect(_on_files_dropped)
	_show_menu()


func _set_screen(c: Control) -> void:
	if current != null:
		current.queue_free()
	current = c
	add_child(c)


# ---------------------------------------------------------------- 主菜单

func _show_menu() -> void:
	var s := Menus.screen("像素大乱斗")
	var box: VBoxContainer = s[1]
	var tag := Menus.label("EVERYTHING BRAWL  /  万物皆可战", 18)
	tag.add_theme_color_override("font_color", ArcadeTheme.MUTED)
	s[2].add_child(tag)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 380
	nav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_theme_constant_override("separation", 16)
	row.add_child(nav)
	var eyebrow := Menus.label("物品觉醒 / 即刻开打", 20)
	eyebrow.add_theme_color_override("font_color", ArcadeTheme.MINT)
	nav.add_child(eyebrow)
	var title := Menus.label("你的日常，\n就是主场。", 48)
	nav.add_child(title)
	nav.add_child(ArcadeTheme.primary(Menus.button("开始游戏   >", _show_lobby, 380)))
	var libraries := HBoxContainer.new()
	libraries.add_child(Menus.button("管理角色", _show_library.bind("character"), 184))
	libraries.add_child(Menus.button("管理场景", _show_library.bind("stage"), 184))
	nav.add_child(libraries)
	nav.add_child(Menus.button("网络测试", _show_net, 380))
	var hero := PanelContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_theme_stylebox_override("panel", ArcadeTheme.plate(ArcadeTheme.INK, ArcadeTheme.EDGE, 2, 0))
	row.add_child(hero)
	var art := ArcadeBackdrop.new()
	art.showcase = true
	art.custom_minimum_size = Vector2(400, 360)
	hero.add_child(art)
	var caption := VBoxContainer.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	caption.offset_left = 32
	caption.offset_top = 32
	caption.offset_right = -32
	art.add_child(caption)
	var cap := Menus.label("把身边的东西，变成对手。", 26)
	caption.add_child(cap)
	var sub := Menus.label("照片生成角色与场景  /  导入即可加入乱斗", 18, true)
	sub.add_theme_color_override("font_color", ArcadeTheme.MUTED)
	caption.add_child(sub)
	var foot := HBoxContainer.new()
	var hint := Menus.label("01  导入物品     02  选择场景     03  同屏开战", 18)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", ArcadeTheme.MUTED)
	foot.add_child(hint)
	var lan := Menus.label("2 - 4 人 / 局域网对战", 18)
	lan.add_theme_color_override("font_color", ArcadeTheme.MINT)
	foot.add_child(lan)
	box.add_child(foot)
	_set_screen(s[0])


func _show_lobby() -> void:
	var l := LobbyScreen.new()
	_set_screen(l)
	l.exited.connect(_show_menu)


func _show_net() -> void:
	var n := NetDemo.new()
	_set_screen(n)
	n.exited.connect(_show_menu)


# ---------------------------------------------------------------- 角色 / 场景库

func _show_library(kind: String) -> void:
	var title := "管理角色" if kind == "character" else "管理场景"
	var s := Menus.screen(title)
	var box: VBoxContainer = s[1]
	var bar: HBoxContainer = s[2]
	var add := Menus.button("+", _import.bind(kind), 90)
	add.add_theme_font_size_override("font_size", 44)
	bar.add_child(add)
	bar.add_child(Menus.button("返回", _show_menu, 160))
	var g := Menus.grid(5)
	box.add_child(g[0])
	for e in Catalog.entries(kind):
		var sub: String = ("" if e.valid else "不合法") + ("（导入）" if e.user else "")
		g[1].add_child(Menus.card(e.tex, e.name, sub, _show_detail.bind(kind, e)))
	box.add_child(Menus.label("点右上角 + 导入 zip 角色包 / 场景包（电脑版也可以把 zip 拖到窗口上）", 18, true))
	_set_screen(s[0])


func _show_detail(kind: String, e: Dictionary) -> void:
	if kind == "character":
		_set_screen(CharacterDetail.build(e, _practice_with.bind("me", e.path), _delete.bind(kind, e.path), _show_library.bind(kind)))
	else:
		_set_screen(StageDetail.build(e, _practice_with.bind("stage", e.path), _delete.bind(kind, e.path), _show_library.bind(kind)))


func _delete(kind: String, path: String) -> void:
	PackLibrary.remove(path)
	_show_library(kind)


# ---------------------------------------------------------------- 导入

func _import(kind: String) -> void:
	_import_kind = kind
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("导入角色包或场景包", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
			PackedStringArray(["*.zip;角色包 / 场景包;application/zip"]), _on_native_files)
	else:
		var fd := FileDialog.new()
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.filters = PackedStringArray(["*.zip"])
		fd.use_native_dialog = false
		fd.files_selected.connect(_import_paths)
		add_child(fd)
		fd.popup_centered_ratio(0.8)


func _on_native_files(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok:
		_import_paths.call_deferred(paths)


func _on_files_dropped(files: PackedStringArray) -> void:
	_import_paths(files)


func _import_paths(paths: PackedStringArray) -> void:
	var bad := []
	var kind := _import_kind
	for p in paths:
		var bytes := FileAccess.get_file_as_bytes(p)
		if bytes.is_empty():
			bad.append([p.get_file(), "无法读取文件"])
			continue
		var v := PackLibrary.import_bytes(bytes)
		if v.is_valid():
			kind = v.kind
		else:
			bad.append([p.get_file(), v.report()])
	if bad.is_empty():
		_show_library(kind)
		return
	var s := Menus.screen("导入失败")
	var box: VBoxContainer = s[1]
	var t := TextEdit.new()
	t.editable = false
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 20)
	var txt := PackedStringArray()
	for b in bad:
		txt.append("%s\n%s\n" % b)
	t.text = "\n".join(txt)
	box.add_child(t)
	box.add_child(Menus.button("返回", _show_library.bind(kind)))
	_set_screen(s[0])


# ---------------------------------------------------------------- 试玩

func _practice_with(slot: String, path: String) -> void:
	practice[slot] = path
	_show_practice()


func _show_practice() -> void:
	var chars := Catalog.valid_entries("character")
	var stages := Catalog.valid_entries("stage")
	if chars.is_empty() or stages.is_empty():
		_show_menu()
		return
	for k in ["me", "foe"]:
		if not chars.any(func(e): return e.path == practice[k]):
			practice[k] = chars[0].path
	if not stages.any(func(e): return e.path == practice.stage):
		practice.stage = stages[0].path
	var s := Menus.screen("试玩")
	var box: VBoxContainer = s[1]
	var bar: HBoxContainer = s[2]
	bar.add_child(Menus.button("开始", _start_practice, 180))
	bar.add_child(Menus.button("返回", _show_menu, 160))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.add_child(Menus.label("我的角色（触屏 / 键盘 A）", 26))
	content.add_child(_pick_row(chars, "me"))
	content.add_child(Menus.label("对手", 26))
	content.add_child(_pick_row(chars, "foe"))
	var modes := HBoxContainer.new()
	var group := ButtonGroup.new()
	for m in OPPONENT_MODES:
		var b := Menus.button(m[1], _set_practice.bind("mode", m[0]), 180)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = practice.mode == m[0]
		modes.add_child(b)
	content.add_child(Menus.label("对手操作", 26))
	content.add_child(modes)
	content.add_child(Menus.label("场景", 26))
	content.add_child(_pick_row(stages, "stage"))
	box.add_child(Menus.scroll(content))
	_set_screen(s[0])


## 一行可横向滚动的卡片，单选。
func _pick_row(entries: Array, slot: String) -> Control:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size.y = 220
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for e in entries:
		var c := Menus.card(e.tex, e.name, "", _set_practice.bind(slot, e.path), true)
		c.button_group = group
		c.button_pressed = practice[slot] == e.path
		row.add_child(c)
	sc.add_child(row)
	return sc


func _set_practice(slot: String, value: String) -> void:
	practice[slot] = value


func _start_practice() -> void:
	var players := [
		{"validator": PackLibrary.load_pack(practice.me), "input": "touch"},
		{"validator": PackLibrary.load_pack(practice.foe), "input": practice.mode},
	]
	var m := MatchScreen.new()
	_set_screen(m)
	m.start(players, PackLibrary.load_pack(practice.stage))
	m.exited.connect(_show_practice)
