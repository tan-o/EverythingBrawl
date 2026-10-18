class_name DebugLayer
extends Node2D
## 调试开关：碰撞箱、武器判定、子弹判定与类别。快照需在 debug 模式下生成。

const KIND_COLOR := {"bullet": Color(1, 0.9, 0.2, 0.8), "beam": Color(1, 0.3, 1, 0.8), "deployable": Color(0.3, 1, 0.5, 0.8)}

var snap := {}


func _draw() -> void:
	if snap.is_empty():
		return
	var font := ThemeDB.fallback_font
	for f in snap.fighters:
		if "dbg_body" in f:
			draw_rect(f.dbg_body, Color(0.2, 0.8, 1, 0.9), false, 1.0)
		if "dbg_swing" in f and not f.dbg_swing.is_empty():
			_shape(f.dbg_swing, Color(1, 0.2, 0.2, 0.9))
	for p in snap.proj:
		if p.shape.is_empty():
			continue
		var c: Color = KIND_COLOR.get(p.k, Color.WHITE)
		_shape(p.shape, c)
		draw_string(font, Vector2(p.x + 4, p.y - 4), p.k.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)


func _shape(s: Dictionary, c: Color) -> void:
	match s.t:
		"circle":
			draw_arc(s.c, s.r, 0, TAU, 16, c, 1.0)
		"capsule":
			draw_line(s.a, s.b, c, 1.0)
			draw_arc(s.a, s.r, 0, TAU, 12, c, 1.0)
			draw_arc(s.b, s.r, 0, TAU, 12, c, 1.0)
		"obb":
			var pts := PackedVector2Array()
			for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
				pts.append(s.c + (k * s.h).rotated(s.a))
			draw_polyline(pts, c, 1.0)
