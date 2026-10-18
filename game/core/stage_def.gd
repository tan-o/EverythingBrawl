class_name StageDef
extends RefCounted
## 场景元素的公共判定（校验器与运行时共用）。

const BEHAVIORS := ["climb", "crumble", "bounce", "friction", "conveyor", "move", "damage", "wind", "water", "blink", "breakable"]


static func offsets(el: Dictionary) -> Array:
	var out := []
	if "move" in el:
		for o in el.move.path:
			out.append(Vector2(o[0], o[1]))
	else:
		out.append(Vector2.ZERO)
	return out


static func is_static(el: Dictionary) -> bool:
	return not ("move" in el or "crumble" in el or "blink" in el or "breakable" in el)


static func is_standable(el: Dictionary) -> bool:
	return el.collide in ["solid", "platform"] and not ("damage" in el)


static func rect(el: Dictionary) -> Rect2:
	return Rect2(el.rect[0], el.rect[1], el.rect[2], el.rect[3])


## 含移动路径在内的包围盒。
static func hull(el: Dictionary) -> Rect2:
	var r := rect(el)
	var offs := offsets(el)
	var out := Rect2(r.position + offs[0], r.size)
	for o in offs:
		out = out.merge(Rect2(r.position + o, r.size))
	return out


static func path_length(el: Dictionary) -> float:
	var pts: Array = el.move.path
	var total := 0.0
	for i in range(pts.size() - 1):
		total += Vector2(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]).length()
	if el.move.get("mode", "loop") == "loop":
		total += Vector2(pts[0][0] - pts[-1][0], pts[0][1] - pts[-1][1]).length()
	else:
		total *= 2
	return total


## 移动元素在第 t 帧的偏移。
static func offset_at(el: Dictionary, t: int) -> Vector2:
	if not ("move" in el):
		return Vector2.ZERO
	var pts := offsets(el)
	var period: float = el.move.period
	var loop: bool = el.move.get("mode", "loop") == "loop"
	var seq := pts.duplicate()
	if loop:
		seq.append(pts[0])
	else:
		for i in range(pts.size() - 2, -1, -1):
			seq.append(pts[i])
	var lens := []
	var total := 0.0
	for i in range(seq.size() - 1):
		var l: float = seq[i].distance_to(seq[i + 1])
		lens.append(l)
		total += l
	if total <= 0:
		return pts[0]
	var d := fposmod(float(t), period) / period * total
	for i in lens.size():
		if d <= lens[i] or i == lens.size() - 1:
			var k: float = 0.0 if lens[i] == 0 else clamp(d / lens[i], 0.0, 1.0)
			return seq[i].lerp(seq[i + 1], k)
		d -= lens[i]
	return pts[0]
