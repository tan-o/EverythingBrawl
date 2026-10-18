class_name Geom
extends RefCounted
## 判定几何：circle / obb（含 AABB）/ capsule 两两相交。
## 形状用字典表示：
##   {"t": "circle", "c": Vector2, "r": float}
##   {"t": "obb", "c": Vector2, "h": Vector2(半宽, 半高), "a": 弧度}
##   {"t": "capsule", "a": Vector2, "b": Vector2, "r": float}


static func circle(c: Vector2, r: float) -> Dictionary:
	return {"t": "circle", "c": c, "r": r}


static func obb(c: Vector2, half: Vector2, a := 0.0) -> Dictionary:
	return {"t": "obb", "c": c, "h": half, "a": a}


static func aabb(r: Rect2) -> Dictionary:
	return obb(r.get_center(), r.size / 2.0, 0.0)


static func capsule(a: Vector2, b: Vector2, r: float) -> Dictionary:
	return {"t": "capsule", "a": a, "b": b, "r": r}


static func grow(s: Dictionary, m: float) -> Dictionary:
	var o := s.duplicate()
	match s.t:
		"obb":
			o.h = s.h + Vector2(m, m)
		_:
			o.r = s.r + m
	return o


static func seg_point_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 == 0.0:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _to_local(o: Dictionary, p: Vector2) -> Vector2:
	return (p - o.c).rotated(-o.a)


static func point_box_dist(d: Vector2, h: Vector2) -> float:
	var q := Vector2(clamp(d.x, -h.x, h.x), clamp(d.y, -h.y, h.y))
	return d.distance_to(q)


static func _seg_hits_box(a: Vector2, b: Vector2, h: Vector2) -> bool:
	# Liang-Barsky
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x + h.x, h.x - a.x, a.y + h.y, h.y - a.y]
	for i in 4:
		if p[i] == 0.0:
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = max(t0, t)
			else:
				t1 = min(t1, t)
			if t0 > t1:
				return false
	return true


static func seg_box_dist(a: Vector2, b: Vector2, h: Vector2) -> float:
	if _seg_hits_box(a, b, h):
		return 0.0
	var best: float = min(point_box_dist(a, h), point_box_dist(b, h))
	for c in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		best = min(best, seg_point_dist(a, b, c))
	return best


static func _obb_axes(o: Dictionary) -> Array:
	return [Vector2.RIGHT.rotated(o.a), Vector2.DOWN.rotated(o.a)]


static func _obb_project(o: Dictionary, axis: Vector2) -> float:
	var ax: Array = _obb_axes(o)
	return abs(ax[0].dot(axis)) * o.h.x + abs(ax[1].dot(axis)) * o.h.y


static func _obb_obb(p: Dictionary, q: Dictionary) -> bool:
	var d: Vector2 = q.c - p.c
	for axis in _obb_axes(p) + _obb_axes(q):
		if abs(d.dot(axis)) > _obb_project(p, axis) + _obb_project(q, axis):
			return false
	return true


static func overlap(s1: Dictionary, s2: Dictionary) -> bool:
	var a := s1
	var b := s2
	var order := {"circle": 0, "obb": 1, "capsule": 2}
	if order[a.t] > order[b.t]:
		a = s2
		b = s1
	match [a.t, b.t]:
		["circle", "circle"]:
			return a.c.distance_to(b.c) <= a.r + b.r
		["circle", "obb"]:
			return point_box_dist(_to_local(b, a.c), b.h) <= a.r
		["circle", "capsule"]:
			return seg_point_dist(b.a, b.b, a.c) <= a.r + b.r
		["obb", "obb"]:
			return _obb_obb(a, b)
		["obb", "capsule"]:
			return seg_box_dist(_to_local(a, b.a), _to_local(a, b.b), a.h) <= b.r
		["capsule", "capsule"]:
			var dd: float = min(min(seg_point_dist(a.a, a.b, b.a), seg_point_dist(a.a, a.b, b.b)), min(seg_point_dist(b.a, b.b, a.a), seg_point_dist(b.a, b.b, a.b)))
			return dd <= a.r + b.r
	return false


static func area(s: Dictionary) -> float:
	match s.t:
		"circle":
			return PI * s.r * s.r
		"obb":
			return 4.0 * s.h.x * s.h.y
	return 0.0
