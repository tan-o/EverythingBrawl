class_name FighterView
extends Node2D
## 按快照绘制一个角色：帧动画、武器、程序化效果（闪白、抖动、伸缩、状态、霸体、无敌、反射、护盾、玩家标记）。

const SHADER := preload("res://render/fighter.gdshader")

var assets: PackAssets
var idx := 0
var flipper := Node2D.new()
var sprite := AnimatedSprite2D.new()
var weapon := Sprite2D.new()
var mat := ShaderMaterial.new()
var snap := {}
var squash := Vector2.ONE
var was_ground := true
var tick := 0
var hidden_ko := false


func setup(p_assets: PackAssets, p_idx: int) -> void:
	assets = p_assets
	idx = p_idx
	add_child(flipper)
	sprite.sprite_frames = assets.frames
	sprite.centered = false
	sprite.offset = -assets.anchor
	mat.shader = SHADER
	sprite.material = mat
	flipper.add_child(sprite)
	weapon.centered = false
	weapon.material = mat
	flipper.add_child(weapon)


func on_event(e: Dictionary) -> void:
	match e.t:
		"jump":
			squash = Vector2(0.85, 1.18)
		"explode", "blast":
			hidden_ko = true
		"respawn":
			hidden_ko = false


func apply(s: Dictionary) -> void:
	snap = s
	tick += 1
	var st: String = s.st
	visible = not (st in ["dead", "out"]) and not hidden_ko
	if st in ["normal", "action", "guard", "hitstun", "grabbed", "shieldbreak"]:
		hidden_ko = false
	position = Vector2(round(s.x), round(s.y))
	flipper.scale = Vector2(s.f, 1) * squash
	if s.ground and not was_ground:
		squash = Vector2(1.15, 0.85)
	was_ground = s.ground
	squash = squash.lerp(Vector2.ONE, 0.25)
	if s.a != "" and assets.frames.has_animation(s.a):
		sprite.animation = s.a
		sprite.frame = clampi(int(s.ai), 0, assets.frames.get_frame_count(s.a) - 1)
	# 受击闪白 + 抖动
	mat.set_shader_parameter("flash", 1.0 if s.flash > 3 else (0.5 if s.flash > 0 else 0.0))
	mat.set_shader_parameter("outline", 1.0 if s.armor and (tick / 3) % 2 == 0 else 0.0)
	sprite.position = Vector2((tick % 2) * 2 - 1, 0) if s.flash > 0 else Vector2.ZERO
	var m := Color.WHITE
	if "slow" in s.status:
		m = Palette.SLOW
	if s.inv and (tick / 4) % 2 == 0:
		m.a = 0.35
	sprite.modulate = m
	weapon.modulate = m
	_update_weapon(s)
	queue_redraw()


func _update_weapon(s: Dictionary) -> void:
	var w: Dictionary = s.wpn
	if w.is_empty() or not (w.asset in assets.textures):
		weapon.visible = false
		return
	var anim = assets.data.anims.get(s.a)
	if anim == null or not ("hand" in anim):
		weapon.visible = false
		return
	var h: Array = anim.hand[clampi(int(s.ai), 0, anim.hand.size() - 1)]
	var wd: Dictionary = assets.data.assets[w.asset]
	var r := deg_to_rad(w.angle)
	var dir := Vector2(cos(r), -sin(r))
	weapon.visible = true
	weapon.texture = assets.textures[w.asset]
	weapon.offset = -Vector2(wd.grip[0], wd.grip[1])
	weapon.position = Vector2(h[0], h[1]) - assets.anchor + dir * w.reach + sprite.position
	weapon.rotation = -r


func _draw() -> void:
	if snap.is_empty():
		return
	var b: Array = assets.data.stats.body
	var bw: float = b[0]
	var bh: float = b[1]
	var col := Palette.player(idx)
	# 脚下玩家颜色标记
	draw_rect(Rect2(-bw / 2.0, 1, bw, 2), col)
	var st: Dictionary = snap.status
	var top := Vector2(0, -bh - 6)
	if "stun" in st:
		for i in 3:
			var a := tick * 0.15 + i * TAU / 3.0
			draw_rect(Rect2(top + Vector2(cos(a) * 8, sin(a) * 3) - Vector2(1, 1), Vector2(2, 2)), Palette.STAR)
	if "root" in st:
		for i in range(-int(bw / 2) - 2, int(bw / 2) + 3, 3):
			draw_rect(Rect2(i, -3, 2, 2), Palette.CHAIN)
	if "silence" in st:
		var c := top + Vector2(0, -2)
		for k in range(-2, 3):
			draw_rect(Rect2(c + Vector2(k, k), Vector2(1, 1)), Palette.SILENCE)
			draw_rect(Rect2(c + Vector2(k, -k), Vector2(1, 1)), Palette.SILENCE)
	if snap.st == "guard":
		var rad: float = max(bw, bh) * 0.6 * (0.4 + 0.6 * snap.sh / 100.0)
		draw_circle(Vector2(0, -bh / 2.0), rad, Palette.SHIELD)
	if snap.refl:
		draw_arc(Vector2(0, -bh / 2.0), max(bw, bh) * 0.5 + 8, 0, TAU, 24, Palette.REFLECT, 1.0)
