class_name SkillShowcase
extends Control
## Isolated, real simulation for skill demonstrations; never changes a saved pack/match.
signal exited
var pack: PackValidator
var sim: MatchSim
var world: WorldView
var viewport := SubViewport.new()
var selected := ""
var frame := 0
var replay_after := 180
var keys := Label.new()
var buttons := {}
var sfx := SfxPlayer.new()
var demo_assets: Array = []

static func shortcut(key: String) -> String:
	if key == "jump":
		return "跳 / Space"
	if key == "grab":
		return "防 + 攻 / L + J"
	if key == "attack.dash":
		return "跑动 + 攻 / A 或 D + J（跑动中）"
	var parts := key.split(".")
	var button := "攻" if parts[0] == "attack" else "特"
	var keyboard := "J" if parts[0] == "attack" else "K"
	var direction := parts[1] if parts.size() > 1 else "neutral"
	var prefix: String = {"neutral": "", "side": "左右 + ", "up": "上 + ", "down": "下 + "}.get(direction, "")
	var kb_prefix: String = {"neutral": "", "side": "A 或 D + ", "up": "W + ", "down": "S + "}.get(direction, "")
	return ("空中 · " if parts.size() > 2 else "") + prefix + button + " / " + kb_prefix + keyboard

static func bindings(data: Dictionary, aid: String) -> PackedStringArray:
	var result := PackedStringArray()
	for key in data.input:
		if data.input[key] == aid:
			result.append(shortcut(key))
	for i in data.get("forms", []).size():
		for key in data.forms[i].get("input", {}):
			if data.forms[i].input[key] == aid:
				result.append("形态 %d · %s" % [i, shortcut(key)])
	if data.actions[aid].get("ultimate", false):
		result.append("大招 / U（满槽）")
	if result.is_empty():
		result.append("联动触发" if data.actions[aid].type != "move" else "移动 / A、D")
	return result

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var screen := Menus.screen("技能展示")
	add_child(screen[0])
	screen[2].add_child(Menus.button("重播", play.bind(""), 120))
	screen[2].add_child(Menus.button("返回", func(): exited.emit(), 120))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen[1].add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var name_label := Menus.label(pack.data.name, 28)
	left.add_child(name_label)
	var picture := TextureRect.new()
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.size = Vector2i(480, 270)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	picture.texture = viewport.get_texture()
	left.add_child(picture)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.add_theme_font_size_override("font_size", 18)
	keys.add_theme_color_override("font_color", ArcadeTheme.MUTED)
	left.add_child(keys)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 390
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for aid in pack.data.actions:
		var a: Dictionary = pack.data.actions[aid]
		var hints := bindings(pack.data, aid)
		var b := Menus.button(a.get("name", aid) + "\n" + hints[0], play.bind(aid), 370)
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = "\n".join(hints)
		b.toggle_mode = true
		b.button_group = group
		list.add_child(b)
		buttons[aid] = b
	add_child(sfx)
	demo_assets = [PackAssets.build(pack), PackAssets.build(pack)]
	sfx.setup(demo_assets)
	var start: String = pack.data.input.get("attack.neutral", pack.data.actions.keys()[0])
	play(start)

func play(aid: String) -> void:
	if aid == "":
		aid = selected
	selected = aid
	frame = 0
	if sim != null:
		sim.dispose()
	if world != null:
		viewport.remove_child(world)
		world.queue_free()
	var stage_data := {"name": "展示", "spawns": [[160,225],[260,225]], "assets": {}, "elements": [{"rect": [0,225,480,45], "collide": "solid"}]}
	sim = MatchSim.new([CharRuntime.new(pack.data), CharRuntime.new(pack.data)], stage_data)
	var assets := demo_assets
	var stage_view := StageView.new()
	stage_view.add_child(stage_view.bg)
	stage_view.data = stage_data
	stage_view.draw.connect(func():
		stage_view.draw_rect(Rect2(0,0,480,270), ArcadeTheme.INK)
		for x in range(0,480,20):
			stage_view.draw_line(Vector2(x,0),Vector2(x,270),ArcadeTheme.PANEL)
		stage_view.draw_rect(Rect2(0,225,480,45),ArcadeTheme.PANEL)
		stage_view.draw_line(Vector2(0,225),Vector2(480,225),ArcadeTheme.MINT,2))
	world = WorldView.new()
	world.setup(assets, stage_view)
	viewport.add_child(world)
	var camera := Camera2D.new()
	camera.position = Vector2(210,170)
	camera.zoom = Vector2(1.6,1.6)
	viewport.add_child(camera)
	# Reuse a single camera across replays.
	for child in viewport.get_children():
		if child is Camera2D and child != camera:
			viewport.remove_child(child)
			child.queue_free()
	world.fviews[1].modulate = Color(0.6,0.65,0.75,0.5)
	var f: Fighter = sim.fighters[0]
	var a: Dictionary = f.ch.data.actions[aid]
	if not aid in pack.data.input.values():
		for form in pack.data.get("forms", []):
			if aid in form.get("input", {}).values():
				for rn in form["if"]:
					var condition := CharDef.parse_cond(form["if"][rn])
					var value: float = condition[1] + (1 if condition[0] == ">" else -1 if condition[0] == "<" else 0)
					if rn != "ult":
						f.res[rn] = clampf(value, 0, pack.data.resources[rn].max)
				break
	for rn in a.get("cost", {}):
		f.res[rn] = maxf(f.res.get(rn, 0), a.cost[rn])
	f.ult = float(Rules.data().combat.ult.max)
	f.update_forms()
	if a.get("require", "") == "air" or _air_only(aid):
		f.pos.y -= 45
		f.on_ground = false
		f.state = "air"
	f.input = InputFrame.make(Vector2.ZERO, InputFrame.ATTACK)
	f.prev_buttons = InputFrame.ATTACK
	if a.type == "jump":
		f.prev_buttons = InputFrame.JUMP
		f._do_jump()
	elif a.type != "move":
		f._start_action(aid, InputFrame.ATTACK, true)
	if a.get("grab", false):
		sim.fighters[1].pos.x = f.pos.x + 28
	if "throw" in a:
		sim.fighters[1].become_grabbed(f)
		f.grabbing = sim.fighters[1]
	replay_after = maxi(180, CharDef.action_frames(a, pack.data, f.eff) + int(a.get("lifetime", 0)) + int(a.get("charge", {}).get("max", 0)) + 90)
	keys.text = "  ·  ".join(bindings(pack.data, aid))
	if aid in buttons:
		buttons[aid].button_pressed = true
	world.apply(sim.snapshot())

func _air_only(aid: String) -> bool:
	var found := false
	for key in pack.data.input:
		if pack.data.input[key] == aid:
			found = true
			if not key.ends_with(".air"):
				return false
	return found

func _physics_process(_delta: float) -> void:
	if sim == null:
		return
	frame += 1
	var a: Dictionary = pack.data.actions[selected]
	var held := InputFrame.ATTACK if a.type not in ["move", "jump"] and frame < int(a.get("charge", {}).get("max", 30)) else 0
	var stick := Vector2.RIGHT if a.type == "move" and frame < 45 else Vector2.ZERO
	if a.type == "fly":
		stick = Vector2.UP
	if a.type == "jump" and frame < 30:
		held |= InputFrame.JUMP
	# Stay in this isolated arena; reset before the next demonstration.
	sim.step([InputFrame.make(stick, held), InputFrame.new()])
	world.apply(sim.snapshot())
	sfx.handle(sim.events)
	if frame >= replay_after or sim.over:
		play(selected)

func _exit_tree() -> void:
	if sim != null:
		sim.dispose()
