class_name AnimPreview
extends Control
## 只读的动画预览：按 durations 循环播放（攻击姿势按 10/6/10 帧），画出 hand 点。

var frames: Array = []     # Texture2D
var durations: Array = []
var scale_k := 3.0
var t := 0
var idx := 0


static func make(v: PackValidator, anim_name: String, k := 3.0) -> AnimPreview:
	var p := AnimPreview.new()
	var d: Dictionary = v.data
	var anim: Dictionary = d.anims[anim_name]
	var fs: Array = d.frame_size
	var sheet: Image = v.images["sheet.png"]
	var cols := sheet.get_width() / int(fs[0])
	for fi in anim.frames:
		var img := sheet.get_region(Rect2i((int(fi) % cols) * int(fs[0]), (int(fi) / cols) * int(fs[1]), int(fs[0]), int(fs[1])))
		p.frames.append(ImageTexture.create_from_image(img))
	p.durations = anim.get("durations", [10, 6, 10])
	p.scale_k = k
	p.custom_minimum_size = Vector2(fs[0], fs[1]) * k
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return p


func _process(_d: float) -> void:
	t += 1
	if t >= int(durations[idx % durations.size()]):
		t = 0
		idx = (idx + 1) % frames.size()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.2, 0.28))
	if frames.is_empty():
		return
	var tex: Texture2D = frames[idx]
	draw_texture_rect(tex, Rect2(Vector2.ZERO, tex.get_size() * scale_k), false)
