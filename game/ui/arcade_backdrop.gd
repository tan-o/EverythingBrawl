class_name ArcadeBackdrop
extends Control
## Lightweight pixel geometry; no imported art or per-frame texture allocation.
var showcase := false
var icons: Array[Texture2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)
	if showcase:
		for e in Catalog.valid_entries("character"):
			if e.tex != null:
				icons.append(e.tex)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ArcadeTheme.INK)
	for x in range(0, int(size.x), 40):
		for y in range(0, int(size.y), 40):
			draw_rect(Rect2(x, y, 2, 2), Color("263148"))
	if not showcase:
		for i in 6:
			var x := size.x - 48.0 - i * 28.0
			draw_rect(Rect2(x, size.y - 12, 16, 4), Palette.player(i))
		return
	var w := size.x
	var h := size.y
	# Stepped skyline and a floating tabletop arena.
	for i in 10:
		var bh := 30.0 + float((i * 37) % 90)
		draw_rect(Rect2(i * w / 10, h * 0.76 - bh, w / 10 - 4, bh), Color("1c2941"))
	var arena := Rect2(w * 0.09, h * 0.76, w * 0.82, 20)
	draw_rect(Rect2(arena.position + Vector2(0, 8), Vector2(arena.size.x, 34)), Color("304258"))
	draw_rect(arena, ArcadeTheme.MINT)
	for i in range(0, int(arena.size.x), 24):
		draw_rect(Rect2(arena.position + Vector2(i, 20), Vector2(12, 10)), Color("1b293e"))
	for i in icons.size():
		var tex := icons[i]
		var k := minf(3.0, (w / 5.5) / maxf(tex.get_width(), tex.get_height()))
		var dimensions := tex.get_size() * k
		var x := w * (0.2 + i * 0.2)
		var y := h * 0.76 - dimensions.y - (24 if i % 2 == 1 else 0)
		draw_rect(Rect2(x - 28, h * 0.76 - 4, 56, 4), Color("0c1424"))
		draw_texture_rect(tex, Rect2(Vector2(x - dimensions.x / 2, y), dimensions), false)
		var col := Palette.player(i)
		draw_rect(Rect2(x - 20, y - 22, 40, 5), col)
	for i in 12:
		var p := Vector2(w * (0.08 + float((i * 17) % 84) / 100), h * (0.15 + float((i * 11) % 35) / 100))
		draw_rect(Rect2(p, Vector2(4, 4)), ArcadeTheme.GOLD if i % 3 == 0 else ArcadeTheme.EDGE)
	draw_rect(Rect2(16, 16, 44, 4), ArcadeTheme.GOLD)
	draw_rect(Rect2(16, 16, 4, 24), ArcadeTheme.GOLD)
	draw_rect(Rect2(w - 60, h - 20, 44, 4), ArcadeTheme.MINT)
	draw_rect(Rect2(w - 20, h - 40, 4, 24), ArcadeTheme.MINT)
