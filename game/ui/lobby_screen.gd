class_name LobbyScreen
extends Control
## 开始游戏：选自己的角色和场景 → 自动发现附近房间 / 创建房间 → 自动同步所有人的包 → 房主开始。
## 开打时从每位玩家选的场景里随机选一个。

signal exited

const SETTINGS := "user://settings.cfg"

var net := NetSession.new()
var disc := Discovery.new()
var ui: Control
var room_box: VBoxContainer
var my_char := ""      # 路径
var my_stage := ""
var match_screen: MatchScreen
var _status := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(net)
	add_child(disc)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	my_char = cfg.get_value("pick", "char", "")
	my_stage = cfg.get_value("pick", "stage", "")
	net.lobby_changed.connect(_refresh_room)
	net.failed.connect(_on_failed)
	net.started.connect(_on_started)
	net.ended.connect(_on_ended)
	disc.rooms_changed.connect(_refresh_room)
	disc.start_client()
	_build()


func _build() -> void:
	if ui != null:
		ui.queue_free()
	var chars := Catalog.valid_entries("character")
	var stages := Catalog.valid_entries("stage")
	if not chars.any(func(e): return e.path == my_char) and not chars.is_empty():
		my_char = chars[0].path
	if not stages.any(func(e): return e.path == my_stage) and not stages.is_empty():
		my_stage = stages[0].path
	var s := Menus.screen("开始游戏")
	ui = s[0]
	var box: VBoxContainer = s[1]
	var bar: HBoxContainer = s[2]
	bar.add_child(Menus.button("返回", _back, 160))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.add_child(Menus.label("我的角色", 26))
	content.add_child(_pick_row(chars, "char"))
	content.add_child(Menus.label("我的场景（开打时从所有人选的场景里随机一个）", 26))
	content.add_child(_pick_row(stages, "stage"))
	room_box = VBoxContainer.new()
	room_box.add_theme_constant_override("separation", 10)
	content.add_child(room_box)
	box.add_child(Menus.scroll(content))
	add_child(ui)
	_refresh_room()


func _pick_row(entries: Array, slot: String) -> Control:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size.y = 220
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for e in entries:
		var c := Menus.card(e.tex, e.name, "", _pick.bind(slot, e.path), true)
		c.button_group = group
		c.button_pressed = (my_char if slot == "char" else my_stage) == e.path
		row.add_child(c)
	sc.add_child(row)
	return sc


func _pick(slot: String, path: String) -> void:
	if slot == "char":
		my_char = path
	else:
		my_stage = path
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("pick", "char", my_char)
	cfg.set_value("pick", "stage", my_stage)
	cfg.save(SETTINGS)
	_send_pick()


func _send_pick() -> void:
	if not net.connected() or my_char == "" or my_stage == "":
		return
	net.set_pick(PackLibrary.load_pack(my_char).pack.sha256, PackLibrary.load_pack(my_stage).pack.sha256)


# ---------------------------------------------------------------- 房间

func _refresh_room() -> void:
	if room_box == null:
		return
	for c in room_box.get_children():
		c.queue_free()
	if _status != "":
		room_box.add_child(Menus.label(_status, 22, true))
	if net.mp == null:
		_room_list()
	else:
		_room_view()


func _room_list() -> void:
	room_box.add_child(Menus.label("附近的房间", 26))
	if disc.rooms.is_empty():
		room_box.add_child(Menus.label("正在搜索同一 WiFi / 热点下的房间……", 22))
	for ip in disc.rooms:
		var r: Dictionary = disc.rooms[ip]
		room_box.add_child(Menus.button("加入 %s（%d/%d 人）" % [r.name, r.players, r.max], _join.bind(ip, r.port), 520))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Menus.button("创建房间", _host, 240))
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "或输入房主 IP"
	ip_edit.custom_minimum_size = Vector2(260, 64)
	row.add_child(ip_edit)
	row.add_child(Menus.button("加入", func(): _join(ip_edit.text.strip_edges(), NetSession.PORT), 120))
	room_box.add_child(row)


func _room_view() -> void:
	var title := "房间（我是房主，IP：%s）" % ", ".join(NetDemo.local_ips()) if net.is_host else "房间"
	room_box.add_child(Menus.label(title, 26))
	if not net.is_host and net.my_id == 0:
		room_box.add_child(Menus.label("连接中……", 22))
	var i := 0
	for id in net.order:
		var p: Dictionary = net.players[id]
		var state := "就绪"
		if p.err != "":
			state = "包不合法"
		elif p.char == "" or p.stage == "":
			state = "选择中"
		elif not (p.char_ok and p.stage_ok):
			state = "上传中"
		elif not p.synced:
			state = "同步中"
		var who: String = p.name + ("（房主）" if id == 1 else "") + ("（我）" if id == net.my_id else "")
		var l := Menus.label("P%d  %s    角色：%s    场景：%s    %s" % [i + 1, who, p.char_name, p.stage_name, state], 22, true)
		l.add_theme_color_override("font_color", Palette.player(i))
		room_box.add_child(l)
		if p.err != "" and id == net.my_id:
			room_box.add_child(Menus.label(p.err, 18, true))
		i += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if net.is_host:
		var b := Menus.button("开始对战", net.start_match, 240)
		b.disabled = not net.can_start()
		row.add_child(b)
		disc.room = {"name": net.my_name, "players": net.players.size(), "max": NetSession.MAX_PLAYERS, "port": NetSession.PORT}
	else:
		row.add_child(Menus.label("等待房主开始", 22))
	row.add_child(Menus.button("离开房间", _leave, 200))
	room_box.add_child(row)


func _host() -> void:
	_status = ""
	if net.host():
		disc.start_host({"name": net.my_name, "players": 1, "max": NetSession.MAX_PLAYERS, "port": NetSession.PORT})
		_send_pick()
	_refresh_room()


func _join(ip: String, port: int) -> void:
	_status = ""
	if ip == "":
		return
	disc.stop()
	if net.join(ip, port):
		net.lobby_changed.connect(_send_pick_once, CONNECT_ONE_SHOT)
	_refresh_room()


func _send_pick_once() -> void:
	_send_pick()


func _leave() -> void:
	net.close()
	disc.start_client()
	_refresh_room()


func _on_failed(msg: String) -> void:
	_status = msg
	if match_screen != null:
		match_screen.queue_free()
		match_screen = null
		ui.visible = true
	net.close()
	disc.start_client()
	_refresh_room()


func _back() -> void:
	net.close()
	disc.stop()
	exited.emit()


# ---------------------------------------------------------------- 对战

func _on_started(info: Dictionary) -> void:
	var players := []
	for p in info.players:
		var id := int(p.id)
		var inp := "touch" if id == net.my_id else ("net" if net.is_host else "remote")
		players.append({"validator": PackLibrary.cache_validator(str(p.char)), "input": inp, "peer": id})
	ui.visible = false
	disc.stop()
	match_screen = MatchScreen.new()
	add_child(match_screen)
	match_screen.start(players, PackLibrary.cache_validator(str(info.stage)), net)
	match_screen.exited.connect(_on_match_exit)


func _on_match_exit() -> void:
	if net.is_host:
		net.end_match()
	else:
		_leave()
		_on_ended()


func _on_ended() -> void:
	if match_screen != null:
		match_screen.queue_free()
		match_screen = null
	ui.visible = true
	if net.is_host:
		disc.start_host({"name": net.my_name, "players": net.players.size(), "max": NetSession.MAX_PLAYERS, "port": NetSession.PORT})
	_refresh_room()
