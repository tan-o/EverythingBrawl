class_name StageValidator
extends RefCounted
## 场景包校验（权威实现）；skill/scripts/validate.py 的 StageValidator 是镜像。
## 复用 PackValidator 的错误收集与图片读取。

var v: PackValidator
var data: Dictionary
var SL: Dictionary


func _init(p_v: PackValidator) -> void:
	v = p_v
	SL = Rules.data().stage_limits


func run() -> void:
	var files: Dictionary = v.pack.files
	v.at_most("stage.zip_bytes", "zip", v.pack.zip_size, SL.zip_bytes)
	var json := JSON.new()
	if json.parse(files["stage.json"].get_string_from_utf8()) != OK:
		v.add("pack.read", "stage.json", "JSON 解析失败: %s" % json.get_error_message())
		return
	var d = json.data
	for name in files:
		if name != "stage.json" and not name.ends_with(".png"):
			v.add("pack.files", name, "包内只能有 stage.json 与 .png 文件")
	if not (d is Dictionary) or not SchemaValidator.json_equal(d.get("format"), 1):
		v.add("format", "format", "format 必须为 1")
		return
	var sv := SchemaValidator.new(Rules.stage_schema())
	var serr := sv.validate(d)
	for se in serr:
		v.add("schema", se.path, se.msg)
	if not serr.is_empty():
		return
	data = d
	v.data = d
	if not _load_images():
		return
	_check_art()
	_check_elements()
	if v.errors.is_empty():
		_check_layout()


func _load_images() -> bool:
	var ok := true
	for n in PackValidator._sorted_keys(v.pack.files):
		if n.ends_with(".png"):
			var im = v._decode_png(n)
			if im == null:
				ok = false
			else:
				v.images[n] = im
	for an in PackValidator._sorted_keys(data.assets):
		if not (data.assets[an].image in v.images):
			v.add("ref", "assets.%s.image" % an, "缺少图片 %s" % data.assets[an].image)
			ok = false
	return ok


func _check_ref(path: String, name, kind: String) -> bool:
	var a = data.assets.get(name)
	if a == null or a.kind != kind:
		v.add("ref", path, "%s 引用的 %s 不存在或不是 %s" % [path, name, kind])
		return false
	return true


func _check_art() -> void:
	var colors := {}
	for n in PackValidator._sorted_keys(v.images):
		var bytes: PackedByteArray = v.images[n].get_data()
		var bad := false
		for i in range(0, bytes.size(), 4):
			var a := bytes[i + 3]
			if a == 0:
				continue
			if a != 255:
				bad = true
				continue
			colors[(bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]] = true
		if bad:
			v.add("pack.alpha", n, "%s 含半透明像素（alpha 只能是 0 或 255）" % n)
	v.at_most("stage.colors", "colors", colors.size(), SL.colors)
	for an in PackValidator._sorted_keys(data.assets):
		var a: Dictionary = data.assets[an]
		var im: Image = v.images[a.image]
		var w := im.get_width()
		var h := im.get_height()
		if a.kind in ["tile", "hazard"]:
			if w > SL.tile_side or h > SL.tile_side:
				v.add("stage.tile_side", "assets.%s" % an, "地形贴图每边 <= %d（%s 为 %dx%d）" % [SL.tile_side, an, w, h])
		else:
			var fr := int(a.get("frames", 1))
			var ds: Array = a.get("durations", [1])
			if w % fr != 0 or ds.size() != fr:
				v.add("stage.background_frames", "assets.%s" % an, "背景图宽须能被 frames 整除，durations 数量须等于 frames")
				continue
			for i in a.get("durations", []).size():
				v.in_range("pack.duration", "assets.%s.durations.%d" % [an, i], a.durations[i], Rules.data().limits.pack.duration)
			var ok := false
			for sz in SL.background_sizes:
				if w / fr == int(sz[0]) and h == int(sz[1]):
					ok = true
			if not ok:
				v.add("stage.background_size", "assets.%s" % an, "背景每帧尺寸不符合要求")
	_check_ref("background", data.background, "background")


func _check_elements() -> void:
	var els: Array = data.elements
	v.at_most("stage.elements", "elements", els.size(), SL.elements)
	var n_damage := 0
	var n_traps := 0
	var b: Array = SL.bounds
	for i in els.size():
		var el: Dictionary = els[i]
		var p := "elements.%d" % i
		var col: String = el.collide
		if el.get("background_region", false):
			if "tile" in el or not StageDef.is_static(el):
				v.add("stage.background_region", p, "背景区域不能同时指定 tile 或动态地形行为")
		elif not ("tile" in el):
			v.add("stage.invisible", p, "每个元素都必须有贴图（不能有看不见的地形）")
		else:
			_check_ref(p + ".tile", el.tile, "tile")
		var hull := StageDef.hull(el)
		if hull.position.x < b[0] or hull.position.y < b[1] or hull.end.x > b[2] or hull.end.y > b[3]:
			v.add("stage.bounds", p, "元素（含移动路径）须在 %s 范围内" % [b])
		if "trap" in el:
			n_traps += 1
			_check_trap(el, p)
		if "climb" in el and col != "solid":
			v.add("stage.behavior", p + ".climb", "climb 只能用于 solid")
		for k in ["crumble", "bounce", "friction", "conveyor", "breakable"]:
			if k in el and col == "none":
				v.add("stage.behavior", p + "." + k, "%s 只能用于 solid / platform" % k)
		for k in ["wind", "water"]:
			if k in el and col != "none":
				v.add("stage.behavior", p + "." + k, "%s 只能用于 collide: none 的区域" % k)
		if "climb" in el:
			v.in_range("stage.climb_max", p + ".climb.max", el.climb.max, SL.climb_max)
		if "crumble" in el:
			v.in_range("stage.crumble_after", p + ".crumble.after", el.crumble.after, SL.crumble_after)
			v.in_range("stage.respawn", p + ".crumble.respawn", el.crumble.respawn, SL.respawn)
		if "breakable" in el:
			v.in_range("stage.breakable_hp", p + ".breakable.hp", el.breakable.hp, SL.breakable.hp)
			v.in_range("stage.respawn", p + ".breakable.respawn", el.breakable.respawn, SL.respawn)
		if "bounce" in el:
			v.in_range("stage.bounce", p + ".bounce.velocity", el.bounce.velocity, SL.bounce)
		if "friction" in el:
			v.in_range("stage.friction", p + ".friction", el.friction, SL.friction)
		if "conveyor" in el:
			v.at_most("stage.conveyor", p + ".conveyor", abs(el.conveyor), SL.conveyor)
		if "move" in el:
			var lm: Dictionary = SL.move
			v.at_most("stage.move_points", p + ".move.path", el.move.path.size(), lm.points)
			v.in_range("stage.move_period", p + ".move.period", el.move.period, lm.period)
			v.at_most("stage.move_speed", p + ".move", PackValidator.r6(StageDef.path_length(el) / el.move.period), lm.speed)
		if "damage" in el:
			n_damage += 1
			var ld: Dictionary = SL.damage
			v.in_range("stage.damage", p + ".damage.damage", el.damage.damage, ld.damage)
			v.at_least("stage.damage_interval", p + ".damage.interval", el.damage.interval, ld.interval_min)
			v.in_range("stage.damage_force", p + ".damage.knockback.force", el.damage.knockback.force, ld.force)
		if "wind" in el:
			v.at_most("stage.wind", p + ".wind", PackValidator.r6(Vector2(el.wind[0], el.wind[1]).length()), SL.wind)
		if "water" in el:
			v.in_range("stage.water_gravity", p + ".water.gravity_mul", el.water.gravity_mul, SL.water.gravity_mul)
			v.in_range("stage.water_drag", p + ".water.drag", el.water.drag, SL.water.drag)
		if "blink" in el:
			var lb: Dictionary = SL.blink
			v.in_range("stage.blink_on", p + ".blink.on", el.blink.on, lb.on)
			v.in_range("stage.blink_off", p + ".blink.off", el.blink.off, lb.off)
			if (col != "none" or "damage" in el) and el.blink.get("warn", 0) < lb.warn:
				v.add("stage.blink_warn", p + ".blink.warn", "会出现的地形或危险物须有 >= %d 帧预警" % lb.warn)
	v.at_most("stage.trap_count", "elements", n_traps, SL.trap.count)
	v.at_most("stage.damage_count", "elements", n_damage, SL.damage.count)


func _check_trap(el: Dictionary, p: String) -> void:
	var a: Dictionary = el.trap
	var lim: Dictionary = SL.trap
	p += ".trap"
	_check_ref(p + ".asset", a.asset, "hazard")
	for k in ["period", "warn", "damage", "radius"]:
		v.in_range("stage.trap_" + k, p + "." + k, a[k], lim[k])
	v.in_range("stage.trap_force", p + ".knockback.force", a.knockback.force, lim.force)
	if a.origin[0] < 0 or a.origin[1] < 0 or a.origin[0] > el.rect[2] or a.origin[1] > el.rect[3]:
		v.add("stage.trap_origin", p + ".origin", "发射/挥击挂点须位于元素内")
	if a.get("offset", 0) >= a.period:
		v.add("stage.trap_timing", p, "offset 必须小于 period")
	var duration := 1
	if a.type == "shoot":
		for k in ["speed", "lifetime"]:
			v.in_range("stage.trap_" + k, p + "." + k, a[k], lim[k])
	else:
		duration = int(a.active)
		for k in ["length", "active"]:
			v.in_range("stage.trap_" + k, p + "." + k, a[k], lim[k])
		if abs(a.to - a.from) > 180:
			v.add("stage.trap_sweep", p, "挥击角度变化不能超过 180 度")
		if a.asset in data.assets:
			var im: Image = v.images[data.assets[a.asset].image]
			if a.grip[0] < 0 or a.grip[1] < 0 or a.grip[0] >= im.get_width() or a.grip[1] >= im.get_height() or a.grip[0] + a.length > im.get_width():
				v.add("stage.trap_grip", p, "握点和长度须与武器图片一致")
	if a.warn + duration >= a.period:
		v.add("stage.trap_timing", p, "预警和攻击后须留出间歇")
	# Keep the full path/arc away from spawn bodies, including moving emitters.
	for spawn in data.spawns:
		var body := Rect2(spawn[0] - 20, spawn[1] - 48, 40, 48)
		var hull := StageDef.hull(el)
		var origin := hull.position + Vector2(a.origin[0], a.origin[1])
		var area := Rect2(origin, hull.size - Vector2(el.rect[2], el.rect[3]))
		if a.type == "shoot":
			var end: Vector2 = area.position + StageTraps.direction(a.angle) * a.speed * a.lifetime
			area = area.merge(Rect2(end, area.size)).grow(a.radius)
		else:
			area = area.grow(a.length + a.radius)
		if area.intersects(body):
			v.add("stage.trap_spawn", p, "陷阱攻击范围不能覆盖出生区域")
			break


func _check_layout() -> void:
	var els: Array = data.elements
	var spawns: Array = data.spawns
	var mains := []
	for i in els.size():
		var el: Dictionary = els[i]
		if StageDef.is_static(el) and StageDef.is_standable(el) and el.rect[2] >= SL.main_width:
			mains.append(i)
	if mains.is_empty():
		v.add("stage.main", "elements", "至少要有一块宽 >= %d、静止、可站立的主地面" % SL.main_width)
		return
	for si in spawns.size():
		var sx: float = spawns[si][0]
		var sy: float = spawns[si][1]
		var ok := false
		for el in els:
			var r: Array = el.rect
			if StageDef.is_static(el) and StageDef.is_standable(el) and not ("bounce" in el) and abs(sy - r[1]) <= 1 and r[0] <= sx and sx <= r[0] + r[2]:
				ok = true
		if not ok:
			v.add("stage.spawn_ground", "spawns.%d" % si, "出生点必须站在静止的可站立地形上")
		for sj in range(si + 1, spawns.size()):
			if Vector2(sx - spawns[sj][0], sy - spawns[sj][1]).length() < SL.spawn_spacing:
				v.add("stage.spawn_spacing", "spawns.%d" % si, "出生点之间距离须 >= %d" % SL.spawn_spacing)
		for el in els:
			if "damage" in el:
				var hr := StageDef.hull(el)
				var dx: float = max(hr.position.x - sx, 0.0, sx - hr.end.x)
				var dy: float = max(hr.position.y - sy, 0.0, sy - hr.end.y)
				if Vector2(dx, dy).length() < SL.spawn_hazard_distance:
					v.add("stage.spawn_hazard", "spawns.%d" % si, "出生点距危险物须 >= %d" % SL.spawn_hazard_distance)
	var head: float = SL.headroom
	for i in els.size():
		var el: Dictionary = els[i]
		if not StageDef.is_standable(el):
			continue
		var r: Array = el.rect
		var cols := []
		var cx := int(r[0]) + 2
		while cx < r[0] + r[2]:
			cols.append(cx)
			cx += 4
		if cols.is_empty():
			cols.append(int(r[0] + r[2] / 2.0))
		var free := 0
		for c in cols:
			var blocked := false
			for j in els.size():
				var o: Dictionary = els[j]
				if j == i or o.collide != "solid":
					continue
				var orr: Array = o.rect
				if orr[0] <= c and c <= orr[0] + orr[2] and orr[1] < r[1] and orr[1] + orr[3] > r[1] - head:
					blocked = true
					break
			if not blocked:
				free += 1
		if free * 2 < cols.size():
			v.add("stage.headroom", "elements.%d" % i, "可站立地形上方至少一半宽度要留 >= %d 像素空间" % head)
	var stand := []
	for i in els.size():
		if StageDef.is_standable(els[i]):
			stand.append(i)
	var reached := {}
	for m in mains:
		reached[m] = true
	var changed := true
	while changed:
		changed = false
		for bi in stand:
			if bi in reached:
				continue
			for ai in reached.keys():
				if _can_reach(els[ai], els[bi]):
					reached[bi] = true
					changed = true
					break
	for bi in stand:
		if not (bi in reached):
			v.add("stage.reach", "elements.%d" % bi, "从主地面跳不上去（上升 <= %d、水平间隙 <= %d）" % [SL.step_max, SL.gap_max])


func _can_reach(a: Dictionary, b: Dictionary) -> bool:
	for ao in StageDef.offsets(a):
		var ar := Rect2(a.rect[0] + ao.x, a.rect[1] + ao.y, a.rect[2], a.rect[3])
		for bo in StageDef.offsets(b):
			var br := Rect2(b.rect[0] + bo.x, b.rect[1] + bo.y, b.rect[2], b.rect[3])
			var rise := ar.position.y - br.position.y
			var gap: float = max(0.0, br.position.x - ar.end.x, ar.position.x - br.end.x)
			if rise <= SL.step_max and gap <= SL.gap_max:
				return true
	return false
