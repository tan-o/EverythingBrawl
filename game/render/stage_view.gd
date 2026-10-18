class_name StageView
extends Node2D
## 场景绘制：背景（可动画）+ 按快照绘制每个元素（平铺贴图、移动、碎裂前抖动、闪烁预警、裂纹）。

var data: Dictionary
var bg := AnimatedSprite2D.new()
var tiles := {}         # 资产名 -> ImageTexture
var snap: Array = []
var tick := 0


static func build(v: PackValidator) -> StageView:
	var sv := StageView.new()
	sv._build(v.data, v.images)
	return sv


func _build(d: Dictionary, images: Dictionary) -> void:
	data = d
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for k in d.assets:
		var a: Dictionary = d.assets[k]
		var img: Image = images[a.image]
		if a.kind == "tile":
			tiles[k] = ImageTexture.create_from_image(img)
		elif k == d.background:
			var tex := ImageTexture.create_from_image(img)
			var n := int(a.get("frames", 1))
			var fw := img.get_width() / n
			var sf := SpriteFrames.new()
			sf.set_animation_loop("default", true)
			sf.set_animation_speed("default", 60.0)
			var durs: Array = a.get("durations", [1])
			for i in n:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * fw, 0, fw, img.get_height())
				sf.add_frame("default", at, float(durs[i]))
			bg.sprite_frames = sf
			bg.centered = false
			bg.scale = Vector2.ONE * (float(Rules.data().stage.width) / fw)
			bg.z_index = -10
			bg.show_behind_parent = true
	add_child(bg)
	bg.play("default")


func apply(stage_snap: Array) -> void:
	snap = stage_snap
	tick += 1
	queue_redraw()


func _draw() -> void:
	var els: Array = data.elements
	for i in els.size():
		var el: Dictionary = els[i]
		var r := Rect2(el.rect[0], el.rect[1], el.rect[2], el.rect[3])
		var present := true
		var warn := false
		var crack := 0.0
		if i < snap.size():
			r.position = Vector2(snap[i][0], snap[i][1])
			present = snap[i][2]
			warn = snap[i][3]
			crack = snap[i][4]
		var col := Color.WHITE
		if not present:
			if not warn:
				# 不在场时画一个很淡的影子，让玩家知道这里会出现东西
				col.a = 0.18
			else:
				col.a = 0.35 + 0.45 * float((tick / 4) % 2)
		if "crumble" in el and present and crack > 0.6:
			r.position.x += float((tick % 3) - 1)
		var tex: Texture2D = tiles.get(el.get("tile", ""))
		if tex != null:
			draw_texture_rect(tex, r, true, col)
		if present and crack > 0.0:
			_draw_cracks(r, crack)


func _draw_cracks(r: Rect2, k: float) -> void:
	var n := int(ceil(k * 4))
	var c := Color(0.1, 0.08, 0.12, 0.9)
	for j in n:
		var x := r.position.x + r.size.x * (0.2 + 0.2 * j)
		var y := r.position.y
		for s in 4:
			var nx := x + (2 if (s + j) % 2 == 0 else -2)
			var ny: float = min(y + 2, r.end.y - 1)
			draw_line(Vector2(x, y), Vector2(nx, ny), c, 1.0)
			x = nx
			y = ny
