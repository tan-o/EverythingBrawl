class_name EffectsLayer
extends Node2D
## 粒子（击倒像素四散、命中火花、燃烧火苗）、角色包特效（fx）、资源获得图标上浮。

var parts := []      # {p, v, c, life, g}
var floaters := []   # {tex, p, life}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7


func burst_pixels(img: Image, origin: Vector2, anchor: Vector2, facing: int) -> void:
	if img == null:
		return
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lx := (x - anchor.x) * facing
			var p := origin + Vector2(lx, y - anchor.y)
			var away := (p - (origin - Vector2(0, anchor.y / 2.0))).normalized()
			var v := away * rng.randf_range(0.5, 2.5) + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-2.0, -0.5))
			parts.append({"p": p, "v": v, "c": c, "life": rng.randi_range(40, 80), "g": 0.08})


func sparks(at: Vector2, col: Color, n := 6) -> void:
	for i in n:
		var a := rng.randf() * TAU
		parts.append({"p": at, "v": Vector2(cos(a), sin(a)) * rng.randf_range(1.0, 2.5), "c": col, "life": rng.randi_range(8, 16), "g": 0.0})


func fire(at: Vector2, width: float) -> void:
	if rng.randf() < 0.5:
		var p := at + Vector2(rng.randf_range(-width / 2.0, width / 2.0), 0)
		parts.append({"p": p, "v": Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-1.2, -0.5)), "c": Palette.FIRE[rng.randi() % 3], "life": rng.randi_range(10, 20), "g": 0.0})


func play_fx(frames: SpriteFrames, at: Vector2, facing: int, behind := false) -> void:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.position = at.round()
	s.scale.x = facing
	if behind:
		s.z_as_relative = false
		s.z_index = 3
	add_child(s)
	s.animation_finished.connect(s.queue_free)
	s.play("default")


func float_icon(tex: Texture2D, at: Vector2) -> void:
	floaters.append({"tex": tex, "p": at, "life": 40})


func step() -> void:
	var keep := []
	for q in parts:
		q.life -= 1
		if q.life <= 0:
			continue
		q.v.y += q.g
		q.p += q.v
		keep.append(q)
	parts = keep
	var fk := []
	for f in floaters:
		f.life -= 1
		f.p.y -= 0.5
		if f.life > 0:
			fk.append(f)
	floaters = fk
	queue_redraw()


func _draw() -> void:
	for q in parts:
		draw_rect(Rect2(q.p.floor(), Vector2.ONE), q.c)
	for f in floaters:
		var t: Texture2D = f.tex
		var c := Color(1, 1, 1, clamp(f.life / 20.0, 0.0, 1.0))
		draw_texture(t, (f.p - t.get_size() / 2.0).floor(), c)
