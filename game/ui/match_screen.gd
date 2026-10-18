class_name MatchScreen
extends Control
## 本地对战：模拟 → 快照 → 渲染 / HUD / 音效。480×270 画面经 SubViewport 最近邻整数放大。

signal exited

var sim: MatchSim
var world := WorldView.new()
var hud := Hud.new()
var touch := TouchControls.new()
var sfx := SfxPlayer.new()
var viewport := SubViewport.new()
var view := TextureRect.new()
var inputs_cfg: Array = []
var input_provider: Callable   # 测试用：返回 Array[InputFrame]，设置后替代键盘/触屏
var paused := false
var pause_panel: Control
var over_panel: Control
var over_label: Label
var R: Dictionary


## players: [{"validator": PackValidator, "input": "touch"/"kb1"/"kb2"/"none"}]
func start(players: Array) -> void:
	R = Rules.data()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
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
	var names := []
	for p in players:
		var v: PackValidator = p.validator
		chars.append(CharRuntime.new(v.data))
		assets.append(PackAssets.build(v))
		names.append(v.data.name)
		inputs_cfg.append(p.input)
	sim = MatchSim.new(chars)
	world.setup(assets)
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
	var pb := Button.new()
	pb.text = "暂停"
	pb.position = Vector2(12, 100)
	pb.focus_mode = Control.FOCUS_NONE
	pb.pressed.connect(func(): _set_paused(not paused))
	add_child(pb)
	pause_panel = _panel(["继续", "调试显示", "退出对战"], [_set_paused.bind(false), _toggle_debug, _quit])
	over_panel = _panel(["返回"], [_quit])
	over_label = Label.new()
	over_label.add_theme_font_size_override("font_size", 48)
	over_panel.get_child(0).add_child(over_label)
	over_panel.get_child(0).move_child(over_label, 0)


func _panel(labels: Array, actions: Array) -> Control:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	c.add_child(box)
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.custom_minimum_size = Vector2(320, 72)
		b.pressed.connect(actions[i])
		box.add_child(b)
	add_child(c)
	return c


func _toggle_debug() -> void:
	world.show_debug = not world.show_debug
	sim.debug = world.show_debug


func _set_paused(p: bool) -> void:
	paused = p
	pause_panel.visible = p


func _quit() -> void:
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


func _physics_process(_d: float) -> void:
	if sim == null or paused:
		return
	var inputs := []
	if input_provider.is_valid():
		inputs = input_provider.call(sim)
	for i in range(inputs.size(), inputs_cfg.size()):
		var src: String = inputs_cfg[i]
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
		inputs.append(InputFrame.make(stick, b))
	sim.step(inputs)
	var s := sim.snapshot()
	world.apply(s)
	sfx.handle(s.events)
	hud.snap = s
	hud.queue_redraw()
	var ti := inputs_cfg.find("touch")
	if ti >= 0:
		touch.ult_ready = s.fighters[ti].ultready
	if s.over and sim.over_t > 90 and not over_panel.visible:
		over_label.text = "P%d %s 获胜！" % [s.winner + 1, sim.fighters[s.winner].ch.name] if s.winner >= 0 else "平局"
		over_panel.visible = true
