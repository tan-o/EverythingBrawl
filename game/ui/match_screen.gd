class_name MatchScreen
extends Control
## 对战画面：模拟 -> 快照 -> 渲染 / HUD / 音效。480x270 画面经 SubViewport 最近邻整数放大。
## 三种模式：本地（自己跑模拟）、联机房主（跑模拟并下发快照）、联机客户端（只上传输入，按快照插值显示）。

signal exited

const INTERP_DELAY := 2

var sim: MatchSim
var net: NetSession
var mode := "local"            # local / host / client
var world := WorldView.new()
var hud := Hud.new()
var touch := TouchControls.new()
var sfx := SfxPlayer.new()
var viewport := SubViewport.new()
var view := TextureRect.new()
var inputs_cfg: Array = []     # 每位玩家的输入来源：touch / kb1 / kb2 / cpu / dummy / net / remote
var peers: Array = []          # 联机时每位玩家的 peer id
var names: Array = []
var input_provider: Callable   # 测试用：返回 Array[InputFrame]，设置后替代键盘/触屏
var cpus := {}                 # 玩家下标 -> CpuInput
var paused := false
var pause_panel: Control
var over_panel: Control
var over_label: Label
var fps_label: Label
var R: Dictionary
var _render_frame := -1
var _last_event_frame := 0


## players: [{"validator": PackValidator, "input": 输入来源, "peer": 联机 id（可选）}]；stage：场景包校验器；
## p_net 非空时为联机对战。
func start(players: Array, stage: PackValidator, p_net: NetSession = null) -> void:
	R = Rules.data()
	net = p_net
	if net != null:
		mode = "host" if net.is_host else "client"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = ArcadeTheme.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	viewport.size = Vector2i(int(R.stage.width), int(R.stage.height))
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.snap_2d_transforms_to_pixel = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	view.texture = viewport.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(view)
	var chars := []
	var assets := []
	for p in players:
		var v: PackValidator = p.validator
		chars.append(CharRuntime.new(v.data))
		assets.append(PackAssets.build(v))
		names.append(v.data.name)
		inputs_cfg.append(p.input)
		peers.append(p.get("peer", 0))
		if p.input in ["cpu", "dummy"]:
			cpus[inputs_cfg.size() - 1] = CpuInput.new(1 if p.input == "cpu" else 0, inputs_cfg.size())
	if mode != "client":
		sim = MatchSim.new(chars, stage.data)
	world.setup(assets, StageView.build(stage))
	viewport.add_child(world)
	hud.names = names
	hud.packs = assets
	add_child(hud)
	add_child(touch)
	touch.visible = "touch" in inputs_cfg
	add_child(sfx)
	sfx.setup(assets)
	_build_overlays()
	resized.connect(_layout)
	_layout.call_deferred()


func _build_overlays() -> void:
	var pb := Menus.button("菜单", func(): _set_paused(not pause_panel.visible), 110)
	pb.custom_minimum_size.y = 48
	pb.position = Vector2(12, 100)
	pb.focus_mode = Control.FOCUS_NONE
	add_child(pb)
	var resume := "继续" if mode == "local" else "关闭菜单"
	var quit := "离开房间" if mode == "client" else "退出对战"
	pause_panel = _panel([resume, "调试显示", quit], [_set_paused.bind(false), _toggle_debug, _quit])
	over_panel = _panel(["离开房间"] if mode == "client" else ["返回"], [_quit])
	over_label = Label.new()
	over_label.add_theme_font_size_override("font_size", 48)
	var result_box: VBoxContainer = over_panel.get_meta("content")
	result_box.add_child(over_label)
	result_box.move_child(over_label, 1)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.add_theme_color_override("font_color", ArcadeTheme.GOLD)
	fps_label = Label.new()
	fps_label.position = Vector2(12, 160)
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.visible = false
	add_child(fps_label)


func _panel(labels: Array, actions: Array) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.08, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArcadeTheme.plate(ArcadeTheme.PANEL, ArcadeTheme.GOLD, 3, 32))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var title := Menus.label("对战菜单" if labels.size() > 1 else "对战结束", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ArcadeTheme.MUTED)
	box.add_child(title)
	box.add_child(HSeparator.new())
	for i in labels.size():
		var b := Menus.button(labels[i], actions[i], 360)
		if i == 0:
			ArcadeTheme.primary(b)
		box.add_child(b)
	c.set_meta("content", box)
	add_child(c)
	return c


func _toggle_debug() -> void:
	world.show_debug = not world.show_debug
	fps_label.visible = world.show_debug
	if sim != null:
		sim.debug = world.show_debug


func _set_paused(p: bool) -> void:
	# 联机时菜单不暂停对战
	paused = p and mode == "local"
	pause_panel.visible = p


func _quit() -> void:
	if sim != null:
		sim.dispose()
	exited.emit()


func _layout() -> void:
	if not is_inside_tree():
		return
	var W: float = R.stage.width
	var H: float = R.stage.height
	var s: float = get_viewport().get_final_transform().get_scale().x
	var phys := size * s
	var k: float = max(1.0, floor(min(phys.x / W, phys.y / H)))
	var vs := Vector2(W, H) * k / s
	view.size = vs
	view.position = ((size - vs) / 2.0).floor()
	hud.view_rect = Rect2(view.position, vs)
	hud.view_scale = vs.x / W


func _local_input(src: String) -> InputFrame:
	var stick := Vector2.ZERO
	var b := 0
	if src == "touch":
		stick = touch.stick
		b = touch.buttons()
		var kb := KeyboardInput.read("kb1")
		if kb[0] != Vector2.ZERO:
			stick = kb[0]
		b |= kb[1]
	elif src in KeyboardInput.SCHEMES:
		var kb := KeyboardInput.read(src)
		stick = kb[0]
		b = kb[1]
	return InputFrame.make(stick, b)


func _physics_process(_d: float) -> void:
	if fps_label.visible:
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	if mode == "client":
		_client_tick()
		return
	if sim == null or paused:
		return
	var inputs := []
	if input_provider.is_valid():
		inputs = input_provider.call(sim)
	for i in range(inputs.size(), inputs_cfg.size()):
		var src: String = inputs_cfg[i]
		if i in cpus:
			inputs.append(cpus[i].next(sim, i))
		elif src == "net":
			inputs.append(net.input_for(peers[i]))
		else:
			inputs.append(_local_input(src))
	sim.step(inputs)
	var s := sim.snapshot()
	if mode == "host":
		net.send_snapshot(s)
	_show(s)
	if s.over and sim.over_t > 90 and not over_panel.visible:
		_game_over(s)


func _show(s: Dictionary) -> void:
	world.apply(s)
	sfx.handle(s.events)
	hud.snap = s
	hud.queue_redraw()
	var ti := inputs_cfg.find("touch")
	if ti >= 0 and ti < s.fighters.size():
		touch.ult_ready = s.fighters[ti].ultready


func _game_over(s: Dictionary) -> void:
	over_label.text = ("P%d %s 获胜" % [s.winner + 1, names[s.winner]]) if s.winner >= 0 else "平局"
	if mode == "client":
		over_label.text += "\n等待房主返回大厅"
	over_panel.visible = true


# ---------------------------------------------------------------- 客户端：上传输入、插值显示快照

func _client_tick() -> void:
	var me := inputs_cfg.find("touch")
	net.send_input(_local_input("touch") if me >= 0 else InputFrame.new())
	var snaps: Array = net.snaps
	if snaps.is_empty():
		return
	var newest: int = snaps[-1].frame
	if _render_frame < 0:
		_render_frame = newest - INTERP_DELAY
	else:
		_render_frame += 1
	if newest - _render_frame > INTERP_DELAY + 4:
		_render_frame = newest - INTERP_DELAY   # 落后太多：追上
	if _render_frame > newest:
		_render_frame = newest                  # 没收到新快照：停在最新
	var a: Dictionary = snaps[0]
	var b = null
	for s in snaps:
		if s.frame <= _render_frame:
			a = s
		elif b == null:
			b = s
	var out := a.duplicate(true)
	if b != null and b.frame > a.frame and _render_frame > a.frame:
		_lerp_into(out, b, float(_render_frame - a.frame) / float(b.frame - a.frame))
	# 事件：从所有已到达的快照里补齐，按帧去重
	var events := []
	var max_ev := _last_event_frame
	for s in snaps:
		if s.frame > _render_frame:
			continue
		for pair in s.ev:
			if pair[0] > _last_event_frame and pair[0] <= _render_frame:
				events.append_array(pair[1])
				max_ev = max(max_ev, pair[0])
	_last_event_frame = max_ev
	out["events"] = events
	while snaps.size() > 2 and snaps[1].frame <= _render_frame:
		snaps.pop_front()
	_show(out)
	if out.over and not over_panel.visible:
		_game_over(out)


static func _lerp_into(out: Dictionary, b: Dictionary, k: float) -> void:
	for i in min(out.fighters.size(), b.fighters.size()):
		var fa: Dictionary = out.fighters[i]
		var fb: Dictionary = b.fighters[i]
		if fa.st == fb.st:
			fa.x = lerp(float(fa.x), float(fb.x), k)
			fa.y = lerp(float(fa.y), float(fb.y), k)
	var by_id := {}
	for p in b.proj:
		by_id[p.id] = p
	for p in out.proj:
		if p.id in by_id:
			p.x = lerp(float(p.x), float(by_id[p.id].x), k)
			p.y = lerp(float(p.y), float(by_id[p.id].y), k)
