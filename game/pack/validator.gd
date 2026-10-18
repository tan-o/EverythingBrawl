class_name PackValidator
extends RefCounted
## 角色包加载时校验 -- 权威实现。skill/scripts/validate.py 是它的镜像，
## 两者由 conformance/ 下同一组用例保证一致。任何一项违规都拒绝整个包。

var pack: PackReader
var kind := "character"       # character / stage
var errors: Array = []        # [{code, path, msg}]
var _seen := {}
var images := {}              # 文件名 -> Image(RGBA8)
var data: Dictionary
var points := {}              # 形态标签 -> 明细
var _bbox_cache := {}
var _burst_use := {}
var R: Dictionary
var L: Dictionary


func _init(p: PackReader) -> void:
	pack = p
	R = Rules.data()
	L = R.limits


static func validate_file(path: String) -> PackValidator:
	var v := PackValidator.new(PackReader.from_file(path))
	v.run()
	return v


func is_valid() -> bool:
	return errors.is_empty()


func error_codes() -> Array:
	var s := {}
	for e in errors:
		s[e.code] = true
	var out := s.keys()
	out.sort()
	return out


# ---------------------------------------------------------------- 工具

func add(code: String, path: String, msg: String) -> void:
	var key := code + "|" + path
	if key in _seen:
		return
	_seen[key] = true
	errors.append({"code": code, "path": path, "msg": msg})


static func fmt(v) -> String:
	if typeof(v) == TYPE_FLOAT:
		if v == floor(v) and abs(v) < 1e15:
			return str(int(v))
		var s := "%.4f" % v
		s = s.rstrip("0").rstrip(".")
		return s
	return str(v)


func in_range(code: String, path: String, v: float, lim: Array) -> bool:
	if v < lim[0] or v > lim[1]:
		add(code, path, "%s = %s，应在 %s~%s" % [path, fmt(v), fmt(lim[0]), fmt(lim[1])])
		return false
	return true


func at_most(code: String, path: String, v: float, hi: float) -> bool:
	if v > hi:
		add(code, path, "%s = %s，应 <= %s" % [path, fmt(v), fmt(hi)])
		return false
	return true


func at_least(code: String, path: String, v: float, lo: float) -> bool:
	if v < lo:
		add(code, path, "%s = %s，应 >= %s" % [path, fmt(v), fmt(lo)])
		return false
	return true


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


static func r6(v: float) -> float:
	return snappedf(v, 0.000001)


# ---------------------------------------------------------------- 入口

func run() -> void:
	var lp: Dictionary = L.pack
	if pack.error != "":
		add("pack.read", "zip", pack.error)
		return
	if "stage.json" in pack.files and not ("character.json" in pack.files):
		kind = "stage"
		StageValidator.new(self).run()
		return
	at_most("pack.zip_bytes", "zip", pack.zip_size, lp.zip_bytes)
	if not ("character.json" in pack.files):
		add("pack.read", "character.json", "缺少 character.json")
		return
	var json := JSON.new()
	if json.parse(pack.files["character.json"].get_string_from_utf8()) != OK:
		add("pack.read", "character.json", "JSON 解析失败: %s（第 %d 行）" % [json.get_error_message(), json.get_error_line()])
		return
	var d = json.data
	for name in pack.files:
		if name != "character.json" and not name.ends_with(".png"):
			add("pack.files", name, "包内只能有 character.json 与 .png 文件")
	if not (d is Dictionary) or not SchemaValidator.json_equal(d.get("format"), 1):
		add("format", "format", "format 必须为 1")
		return
	var sv := SchemaValidator.new(Rules.schema())
	var serr := sv.validate(d)
	for se in serr:
		add("schema", se.path, se.msg)
	if not serr.is_empty():
		return
	data = d
	if not load_images():
		return
	check_art()
	check_structure()
	if errors.is_empty():
		check_sfx()
	if errors.is_empty():
		check_forms()
	if errors.is_empty():
		check_points()


# ---------------------------------------------------------------- 图片

func _decode_png(name: String):
	var im := Image.new()
	if im.load_png_from_buffer(pack.files[name]) != OK:
		add("pack.read", name, "PNG 读取失败")
		return null
	im.convert(Image.FORMAT_RGBA8)
	return im


func load_images() -> bool:
	var names := ["sheet.png"]
	for an in data.assets:
		var a: Dictionary = data.assets[an]
		if "image" in a:
			names.append(a.image)
	var ok := true
	for n in names:
		if n in images:
			continue
		if not (n in pack.files):
			add("ref", n, "缺少图片 %s" % n)
			ok = false
			continue
		var im = _decode_png(n)
		if im == null:
			ok = false
		else:
			images[n] = im
	for n in pack.files:
		if n.ends_with(".png") and not (n in images):
			var im = _decode_png(n)
			if im == null:
				ok = false
			else:
				images[n] = im
	return ok


func frame_grid() -> Vector2i:
	var fs: Array = data.frame_size
	var sheet: Image = images["sheet.png"]
	return Vector2i(sheet.get_width() / int(fs[0]), sheet.get_height() / int(fs[1]))


func total_frames() -> int:
	var g := frame_grid()
	return g.x * g.y


func frame_bbox(idx: int) -> Vector2i:
	if idx in _bbox_cache:
		return _bbox_cache[idx]
	var fw := int(data.frame_size[0])
	var fh := int(data.frame_size[1])
	var cols := frame_grid().x
	var sheet: Image = images["sheet.png"]
	var region := sheet.get_region(Rect2i((idx % cols) * fw, (idx / cols) * fh, fw, fh))
	var r := region.get_used_rect().size
	_bbox_cache[idx] = r
	return r


static func image_bbox(im: Image) -> Vector2i:
	return im.get_used_rect().size


func check_art() -> void:
	var lp: Dictionary = L.pack
	var d := data
	var fw := int(d.frame_size[0])
	var fh := int(d.frame_size[1])
	for s in [fw, fh]:
		if s < lp.frame_size[0] or s > lp.frame_size[1] or s % int(lp.frame_size_step) != 0:
			add("pack.frame_size", "frame_size", "frame_size 每边须为 %d~%d 且为 %d 的倍数" % [lp.frame_size[0], lp.frame_size[1], lp.frame_size_step])
	var ax: float = d.anchor[0]
	var ay: float = d.anchor[1]
	if ax < 0 or ax > fw or ay < 0 or ay > fh:
		add("anchor", "anchor", "anchor 必须位于帧内")
	var sheet: Image = images["sheet.png"]
	var sw := sheet.get_width()
	var sh := sheet.get_height()
	if sw > lp.sheet_side or sh > lp.sheet_side:
		add("pack.sheet_side", "sheet.png", "sheet.png 不得超过 %dx%d" % [lp.sheet_side, lp.sheet_side])
	if sw % fw != 0 or sh % fh != 0:
		add("pack.sheet_grid", "sheet.png", "sheet.png 尺寸须为 frame_size 的整数倍")
	at_most("pack.total_frames", "sheet.png", total_frames(), lp.total_frames)
	var backdrop_imgs := {}
	for a in d.assets.values():
		if a.kind == "backdrop":
			backdrop_imgs[a.image] = true
	var colors := {}
	var bd_colors := {}
	for n in _sorted_keys(images):
		var im: Image = images[n]
		var bytes := im.get_data()
		var bad_alpha := false
		var target: Dictionary = bd_colors if n in backdrop_imgs else colors
		for i in range(0, bytes.size(), 4):
			var a := bytes[i + 3]
			if a == 0:
				continue
			if a != 255:
				bad_alpha = true
				continue
			target[(bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]] = true
		if bad_alpha:
			add("pack.alpha", n, "%s 含半透明像素（alpha 只能是 0 或 255）" % n)
	at_most("pack.colors", "colors", colors.size(), lp.colors)
	at_most("pack.backdrop_colors", "backdrop", bd_colors.size(), lp.backdrop_colors)
	at_most("pack.backdrop_count", "assets", backdrop_imgs.size(), lp.backdrop_count)
	var side: int = lp.asset_side
	for an in _sorted_keys(d.assets):
		var a: Dictionary = d.assets[an]
		if not ("image" in a):
			continue
		var im: Image = images[a.image]
		var w := im.get_width()
		var h := im.get_height()
		if a.kind == "fx":
			var fr := int(a.frames)
			if fr < 1 or w % fr != 0 or a.durations.size() != fr:
				add("asset.fx_frames", "assets.%s" % an, "fx 图宽须能被 frames 整除，durations 数量须等于 frames")
				continue
			w = w / fr
			for i in a.durations.size():
				in_range("pack.duration", "assets.%s.durations.%d" % [an, i], a.durations[i], lp.duration)
		if a.kind == "backdrop":
			var bf := int(a.get("frames", 1))
			var bds: Array = a.get("durations", [1])
			if w % bf != 0 or bds.size() != bf:
				add("asset.backdrop_frames", "assets.%s" % an, "backdrop 图宽须能被 frames 整除，多帧时 durations 数量须等于 frames")
				continue
			for i in a.get("durations", []).size():
				in_range("pack.duration", "assets.%s.durations.%d" % [an, i], a.durations[i], lp.duration)
			var ok_size := false
			for sz in lp.backdrop_sizes:
				if w / bf == int(sz[0]) and h == int(sz[1]):
					ok_size = true
			if not ok_size:
				add("pack.backdrop_size", "assets.%s" % an, "backdrop 每帧尺寸不符合要求（%s 为 %dx%d）" % [an, w / bf, h])
			continue
		if w > side or h > side:
			add("pack.asset_side", "assets.%s" % an, "素材图每边 <= %d（%s 为 %dx%d）" % [side, an, w, h])
		if a.kind == "weapon":
			in_range("weapon.length", "assets.%s.length" % an, a.length, L.weapon.length)
			in_range("weapon.radius", "assets.%s.radius" % an, a.radius, L.weapon.radius)
			var hr: Array = a.hit_range
			if hr[0] < 0 or hr[1] > 1 or hr[0] > hr[1]:
				add("weapon.hit_range", "assets.%s.hit_range" % an, "hit_range 须满足 0 <= a <= b <= 1")
		if a.kind == "projectile":
			var sw_: float = a.size[0]
			var sh_: float = a.size[1]
			if a.shape == "circle" and sw_ != sh_:
				add("projectile.circle", "assets.%s.size" % an, "circle 的 size 须 w = h（直径）")
			var bb := image_bbox(im)
			var tol: float = lp.projectile_tolerance
			var ok: bool
			if a.get("tile") == "repeat_x":
				ok = abs(bb.y - sh_) <= tol * sh_
			else:
				ok = abs(bb.x - sw_) <= tol * sw_ and abs(bb.y - sh_) <= tol * sh_
			if not ok:
				add("pack.projectile_bbox", "assets.%s" % an, "子弹图非透明区域 %dx%d 与 size %sx%s 相差超过 %d%%" % [bb.x, bb.y, fmt(sw_), fmt(sh_), int(tol * 100)])


# ---------------------------------------------------------------- 结构与引用

func asset_kind(name) -> String:
	var a = data.assets.get(name)
	return "" if a == null else a.kind


func check_ref(path: String, name, kind: String) -> bool:
	if asset_kind(name) != kind:
		add("ref", path, "%s 引用的 %s 不存在或不是 %s" % [path, name, kind])
		return false
	return true


func check_structure() -> void:
	var d := data
	var ls: Dictionary = L.structure
	var lp: Dictionary = L.pack
	var total := total_frames()
	for an in _sorted_keys(d.anims):
		var anim: Dictionary = d.anims[an]
		var p := "anims.%s" % an
		var n: int = anim.frames.size()
		in_range("pack.anim_frames", p + ".frames", n, lp.anim_frames)
		for i in n:
			if anim.frames[i] >= total:
				add("ref", "%s.frames.%d" % [p, i], "帧编号 %d 超出 sheet（共 %d 帧）" % [anim.frames[i], total])
		if "durations" in anim:
			if anim.durations.size() != n:
				add("anim.durations", p + ".durations", "durations 数量须与 frames 相同")
			for i in anim.durations.size():
				in_range("pack.duration", "%s.durations.%d" % [p, i], anim.durations[i], lp.duration)
		if "hand" in anim and anim.hand.size() != n:
			add("anim.hand", p + ".hand", "hand 数量须与 frames 相同")
		if "hold" in anim and anim.hold >= n:
			add("anim.hold", p + ".hold", "hold 超出帧数")
	var res: Dictionary = d.get("resources", {})
	at_most("structure.resources", "resources", res.size(), ls.resources)
	for rn in _sorted_keys(res):
		var r: Dictionary = res[rn]
		var p := "resources.%s" % rn
		if rn in R.reserved_resources:
			add("reserved", p, "资源名 %s 为引擎保留" % rn)
		at_most("structure.resource_max", p + ".max", r.max, ls.resource_max)
		if r.init < 0 or r.init > r.max:
			add("resource.init", p + ".init", "init 须在 0~max 之间")
		if abs(r.get("regen", 0)) > ls.resource_regen:
			add("structure.resource_regen", p + ".regen", "|regen| 须 <= %s" % fmt(ls.resource_regen))
		if "hud" in r and r.hud != "bar":
			check_ref(p + ".hud", r.hud, "icon")
	if d.get("held") != null:
		check_ref("held", d.held, "weapon")
	var forms: Array = d.get("forms", [])
	at_most("structure.forms", "forms", forms.size(), ls.forms)
	for i in forms.size():
		var f: Dictionary = forms[i]
		var p := "forms.%d" % i
		check_cond(p + ".if", f["if"])
		if "held" in f:
			check_ref(p + ".held", f.held, "weapon")
		var fa: Dictionary = f.get("anims", {})
		for k in _sorted_keys(fa):
			if not (fa[k] in d.anims):
				add("ref", "%s.anims.%s" % [p, k], "动画 %s 不存在" % fa[k])
	var acts: Dictionary = d.actions
	at_most("structure.actions", "actions", acts.size(), ls.actions)
	var n_att := 0
	var n_move := 0
	var n_jump := 0
	var n_ult := 0
	for a in acts.values():
		if a.type in CharDef.ATTACK_TYPES:
			n_att += 1
		if a.type == "move":
			n_move += 1
		if a.type == "jump":
			n_jump += 1
		if a.get("ultimate", false):
			n_ult += 1
	at_most("structure.attacks", "actions", n_att, ls.attacks)
	if n_move != 1 or n_jump != 1:
		add("actions.move_jump", "actions", "必须恰好 1 个 move 与 1 个 jump 动作")
	at_most("ultimate.count", "actions", n_ult, L.ultimate.count)
	for aid in _sorted_keys(acts):
		var a: Dictionary = acts[aid]
		var p := "actions.%s" % aid
		if a.get("ultimate", false) and not (a.type in CharDef.ATTACK_TYPES):
			add("ultimate.type", p, "大招必须是 swing 或 shoot")
		if "anim" in a and not (a.anim in d.anims):
			add("ref", p + ".anim", "动画 %s 不存在" % a.anim)
		var cost: Dictionary = a.get("cost", {})
		for k in _sorted_keys(cost):
			check_res_name("%s.cost.%s" % [p, k], k, false)
		var ups: Array = a.get("upgrades", [])
		at_most("structure.upgrades", p + ".upgrades", ups.size(), ls.upgrades)
		for i in ups.size():
			check_cond("%s.upgrades.%d.if" % [p, i], ups[i]["if"])
		for m in range(1 << ups.size()):
			check_action_refs(aid, CharDef.apply_upgrades(a, m))
		if "sfx" in a:
			for k in _sorted_keys(a.sfx):
				check_ref("%s.sfx.%s" % [p, k], a.sfx[k], "sfx")
	var cl: Array = d.get("links", [])
	at_most("structure.char_links", "links", cl.size(), ls.char_links)
	for i in cl.size():
		check_link("links.%d" % i, cl[i], "char")
	for k in _sorted_keys(d.input):
		check_input_value("input.%s" % k, d.input[k])
	for i in forms.size():
		var fi: Dictionary = forms[i].get("input", {})
		for k in _sorted_keys(fi):
			check_input_value("forms.%d.input.%s" % [i, k], fi[k])
	check_graph()


func check_input_value(path: String, v) -> void:
	var a = data.actions.get(v)
	if a == null:
		add("ref", path, "动作 %s 不存在" % v)
	elif a.get("ultimate", false):
		add("ultimate.input", path, "大招不能出现在 input 中")
	elif a.type == "move":
		add("input.move", path, "move 动作由摇杆驱动，不能绑定按键")


func check_res_name(path: String, name: String, allow_ult: bool) -> void:
	if name in R.reserved_resources:
		if not allow_ult:
			add("reserved", path, "不能操作引擎保留资源 %s" % name)
		return
	if not (name in data.get("resources", {})):
		add("ref", path, "资源 %s 不存在" % name)


func check_cond(path: String, cond: Dictionary) -> void:
	for k in _sorted_keys(cond):
		check_res_name("%s.%s" % [path, k], k, true)


func check_action_refs(aid: String, a: Dictionary) -> void:
	var p := "actions.%s" % aid
	var t: String = a.type
	if t == "swing":
		check_ref(p + ".weapon", a.weapon, "weapon")
	if t == "shoot":
		check_ref(p + ".projectile", a.projectile, "projectile")
		if "weapon" in a:
			check_ref(p + ".weapon", a.weapon, "weapon")
	if "anim" in a and not (a.anim in data.anims):
		add("ref", p + ".anim", "动画 %s 不存在" % a.anim)
	var effs: Array = a.get("effects", [])
	at_most("structure.effects", p + ".effects", effs.size(), L.structure.effects)
	for i in effs.size():
		check_ref("%s.effects.%d.fx" % [p, i], effs[i].fx, "fx")
	if "backdrop" in a:
		check_ref(p + ".backdrop", a.backdrop, "backdrop")
		if not a.get("ultimate", false):
			add("ultimate.backdrop", p + ".backdrop", "backdrop（大招背景）只能用于大招动作")
	if t == "jump" and "extra_anim" in a and not (a.extra_anim in data.anims):
		add("ref", p + ".extra_anim", "动画 %s 不存在" % a.extra_anim)
	var links: Array = a.get("links", [])
	at_most("structure.links", p + ".links", links.size(), L.structure.links)
	for i in links.size():
		var l: Dictionary = links[i]
		var where := "bullet" if (t == "shoot" and l.when in CharDef.BULLET_WHEN) else "action"
		check_link("%s.links.%d" % [p, i], l, where)


func check_link(path: String, l: Dictionary, where: String) -> void:
	var d := data
	var w: String = l.when
	var allowed: Array = {"char": CharDef.CHAR_WHEN, "action": CharDef.ACTION_WHEN, "bullet": CharDef.BULLET_WHEN}[where]
	if not (w in allowed):
		add("link.when", path + ".when", "%s 不能用在%s联动" % [w, {"char": "角色级", "action": "动作", "bullet": "子弹"}[where]])
	if ("input" in l or "window" in l) and where != "action":
		add("link.input", path, "input / window 只能用于动作联动")
	if "window" in l and l.window[0] > l.window[1]:
		add("link.window", path + ".window", "window 须起 <= 止")
	if where == "action" and w == "on_hurt" and not ("window" in l):
		add("link.window", path, "动作级 on_hurt 必须配 window")
	if "warp" in l and where != "bullet":
		add("link.warp", path + ".warp", "warp 只能用于子弹联动")
	if "resource" in l:
		check_res_name(path + ".resource", l.resource, false)
	if "if" in l:
		check_cond(path + ".if", l["if"])
	for eff in ["gain", "spend", "set"]:
		var amounts: Dictionary = l.get(eff, {})
		for k in _sorted_keys(amounts):
			check_res_name("%s.%s.%s" % [path, eff, k], k, false)
	if "goto" in l and not (l.goto in d.actions):
		add("ref", path + ".goto", "动作 %s 不存在" % l.goto)
	if "goto" in l and l.goto in d.actions and d.actions[l.goto].get("ultimate", false):
		add("ultimate.input", path + ".goto", "不能通过联动进入大招")
	if "spawn" in l:
		var t = d.actions.get(l.spawn)
		if t == null or t.type != "shoot":
			add("link.spawn", path + ".spawn", "spawn 目标必须是 shoot 动作")
	if "fx" in l:
		check_ref(path + ".fx", l.fx, "fx")
	if "sfx" in l:
		check_ref(path + ".sfx", l.sfx, "sfx")
	if "heal" in l:
		at_most("heal.max", path + ".heal", l.heal, L.heal.max)
		if l.heal < 0:
			add("heal.max", path + ".heal", "heal 须 >= 0")
		if w == "every":
			at_least("heal.every_interval_min", path + ".interval", l.interval, L.heal.every_interval_min)
	if w == "every":
		at_least("every.interval_min", path + ".interval", l.interval, L.every.interval_min)


## [goto 目标, spawn 目标]，覆盖动作所有升级组合。
func link_edges(a: Dictionary) -> Array:
	var gotos := {}
	var spawns := {}
	for m in range(1 << CharDef.upgrade_count(a)):
		var ua := CharDef.apply_upgrades(a, m)
		for l in ua.get("links", []):
			if "goto" in l:
				gotos[l.goto] = true
			if "spawn" in l:
				spawns[l.spawn] = true
	var g := gotos.keys()
	g.sort()
	var s := spawns.keys()
	s.sort()
	return [g, s]


var _goto_g := {}
var _spawn_g := {}
var _color := {}
var _depth_memo := {}


func _goto_dfs(u: String, stack: Array) -> bool:
	_color[u] = 1
	for v in _goto_g.get(u, []):
		if _color.get(v) == 1:
			add("structure.goto_cycle", "actions.%s" % u, "goto 成环: %s" % " -> ".join(PackedStringArray(stack + [v])))
			return true
		if _color.get(v) == null and _goto_dfs(v, stack + [v]):
			return true
	_color[u] = 2
	return false


func _spawn_depth(u: String, seen: Dictionary) -> int:
	if u in seen:
		return 999
	if u in _depth_memo:
		return _depth_memo[u]
	var best := 0
	var seen2 := seen.duplicate()
	seen2[u] = true
	for v in _spawn_g.get(u, []):
		best = max(best, 1 + _spawn_depth(v, seen2))
	_depth_memo[u] = best
	return best


func check_graph() -> void:
	if not errors.is_empty():
		return
	var acts: Dictionary = data.actions
	for aid in acts:
		var ed := link_edges(acts[aid])
		_goto_g[aid] = ed[0]
		_spawn_g[aid] = ed[1]
	for aid in _sorted_keys(acts):
		if _color.get(aid) == null:
			if _goto_dfs(aid, [aid]):
				break
	var lim: int = L.structure.spawn_depth
	for aid in _sorted_keys(acts):
		if _spawn_depth(aid, {}) > lim:
			add("structure.spawn_depth", "actions.%s" % aid, "spawn 链深度超过 %d（或成环）" % lim)
			break
	var cl: Array = data.get("links", [])
	for i in cl.size():
		var l: Dictionary = cl[i]
		if "spawn" in l and l.spawn in acts and 1 + _spawn_depth(l.spawn, {}) > lim:
			add("structure.spawn_depth", "links.%d" % i, "spawn 链深度超过 %d" % lim)


# ---------------------------------------------------------------- 音效

func check_sfx() -> void:
	var lp: Dictionary = L.pack
	var sfx := []
	for k in _sorted_keys(data.assets):
		if data.assets[k].kind == "sfx":
			sfx.append(k)
	at_most("pack.sfx_count", "assets", sfx.size(), lp.sfx_count)
	for k in sfx:
		var secs := Sfxr.seconds(data.assets[k].params)
		if secs > lp.sfx_seconds:
			add("pack.sfx_seconds", "assets.%s" % k, "音效 %s 时长 %.2f 秒，超过 %s 秒" % [k, secs, fmt(lp.sfx_seconds)])


# ---------------------------------------------------------------- 形态 x 动作

func form_masks() -> Array:
	var conds := []
	for f in data.get("forms", []):
		conds.append(f["if"])
	return CharDef.feasible_masks(conds, CharDef.resource_domains(data))


func check_forms() -> void:
	var acts: Dictionary = data.actions
	_burst_use = compute_burst_use()
	for mask in form_masks():
		var eff := CharDef.effective_form(data, mask)
		check_form(eff)
		for aid in _sorted_keys(acts):
			var a: Dictionary = acts[aid]
			var conds := []
			for u in a.get("upgrades", []):
				conds.append(u["if"])
			for um in CharDef.feasible_masks(conds, CharDef.resource_domains(data)):
				check_action(aid, CharDef.apply_upgrades(a, um), eff, um != 0)


func compute_burst_use() -> Dictionary:
	var acts: Dictionary = data.actions
	var burst := {}
	var normal := {}
	for aid in acts:
		var a: Dictionary = acts[aid]
		for m in range(1 << CharDef.upgrade_count(a)):
			var ua := CharDef.apply_upgrades(a, m)
			for l in ua.get("links", []):
				if not ("spawn" in l):
					continue
				if ua.type == "shoot" and l.when in CharDef.BULLET_WHEN:
					burst[l.spawn] = true
				else:
					normal[l.spawn] = true
	for l in data.get("links", []):
		if "spawn" in l:
			normal[l.spawn] = true
	var out := {}
	for aid in acts:
		var b: bool = aid in burst
		out[aid] = [b, (not b) or aid in normal or in_any_input(aid) or is_goto_target(aid)]
	return out


func in_any_input(aid: String) -> bool:
	if aid in data.input.values():
		return true
	for f in data.get("forms", []):
		if aid in f.get("input", {}).values():
			return true
	return false


func is_goto_target(aid: String) -> bool:
	for a in data.actions.values():
		if aid in link_edges(a)[0]:
			return true
	for l in data.get("links", []):
		if l.get("goto") == aid:
			return true
	return false


func check_form(eff: Dictionary) -> void:
	var d := data
	var ls: Dictionary = L.stats
	var st: Dictionary = eff.stats
	for k in ["hp", "weight", "gravity", "max_fall", "air_control"]:
		in_range("stats." + k, "stats." + k, st[k], ls[k])
	var bw: float = st.body[0]
	var bh: float = st.body[1]
	in_range("stats.body_w", "stats.body", bw, ls.body_w)
	in_range("stats.body_h", "stats.body", bh, ls.body_h)
	if bw > d.frame_size[0] or bh > d.frame_size[1]:
		add("stats.body_frame", "stats.body", "body 不能超过 frame_size")
	for k in _sorted_keys(eff.input):
		check_input_value("input.%s" % k, eff.input[k])
	var acts: Dictionary = d.actions
	var reqd := {}
	for n in CharDef.REQUIRED_ANIMS:
		reqd[n] = true
	for a in acts.values():
		if a.type == "jump" and a.max_count >= 2:
			reqd[a.get("extra_anim", "double_jump")] = true
		if a.type == "fly":
			reqd["fly"] = true
		if CharDef.needs_charge_anim(a):
			reqd["charge"] = true
		for u in a.get("upgrades", []):
			if CharDef.needs_charge_anim(u.set):
				reqd["charge"] = true
	var req := reqd.keys()
	req.sort()
	for name in req:
		if CharDef.resolve_anim(d, eff, name) == null:
			add("anim.required", "anims.%s" % name, "缺少必需动画 %s" % name)
	var attack_anims := {}
	var plain_anims := reqd.duplicate()
	for n in CharDef.OPTIONAL_ANIMS:
		if CharDef.resolve_anim(d, eff, n) != null:
			plain_anims[n] = true
	for aid in acts:
		var a: Dictionary = acts[aid]
		for m in range(1 << CharDef.upgrade_count(a)):
			var ua := CharDef.apply_upgrades(a, m)
			if "anim" in ua:
				if ua.type in CharDef.ATTACK_TYPES:
					attack_anims[ua.anim] = true
				else:
					plain_anims[ua.anim] = true
	var attack_r := {}
	var plain_r := {}
	for n in attack_anims:
		attack_r[CharDef.resolve_anim_name(eff, n)] = true
	for n in plain_anims:
		plain_r[CharDef.resolve_anim_name(eff, n)] = true
	var lp: Dictionary = L.pack
	for n in _sorted_keys(attack_r):
		var anim = d.anims.get(n)
		if anim == null:
			continue
		if n in plain_r:
			add("anim.durations", "anims.%s" % n, "攻击姿势动画 %s 不能同时用作普通动画" % n)
		if anim.frames.size() != lp.attack_anim_frames:
			add("pack.attack_anim_frames", "anims.%s.frames" % n, "攻击姿势动画必须恰好 %d 帧" % lp.attack_anim_frames)
		if "durations" in anim:
			add("anim.durations", "anims.%s.durations" % n, "攻击姿势动画不写 durations")
	for n in _sorted_keys(plain_r):
		if n in attack_r:
			continue
		var anim = d.anims.get(n)
		if anim != null and not ("durations" in anim):
			add("anim.durations", "anims.%s" % n, "动画 %s 缺少 durations" % n)
	if eff.held != null:
		check_ref("held", eff.held, "weapon")
		for name in req:
			var anim = CharDef.resolve_anim(d, eff, name)
			if anim != null and not ("hand" in anim):
				var rn := CharDef.resolve_anim_name(eff, name)
				add("anim.hand", "anims.%s" % rn, "设置了 held 时必需动画 %s 必须提供 hand" % rn)
	for aid in _sorted_keys(acts):
		var a: Dictionary = acts[aid]
		for m in range(1 << CharDef.upgrade_count(a)):
			var ua := CharDef.apply_upgrades(a, m)
			if ua.type == "swing" or (ua.type == "shoot" and "weapon" in ua):
				var anim = CharDef.resolve_anim(d, eff, ua.anim)
				if anim != null and not ("hand" in anim):
					add("anim.hand", "anims.%s" % CharDef.resolve_anim_name(eff, ua.anim), "带 weapon 的动作 %s 的动画必须提供 hand" % aid)
	var idle = CharDef.resolve_anim(d, eff, "idle")
	if idle != null and idle.frames.size() > 0 and idle.frames[0] < total_frames():
		var ib := frame_bbox(int(idle.frames[0]))
		var tol: float = lp.idle_body_tolerance
		if abs(ib.x - bw) > tol * bw or abs(ib.y - bh) > tol * bh:
			add("pack.idle_body", "anims.idle", "idle 第 0 帧非透明区域 %dx%d 与 body %dx%d 相差超过 %d%%" % [ib.x, ib.y, bw, bh, int(tol * 100)])
	var used := {}
	for n in plain_r.keys() + attack_r.keys():
		var anim = d.anims.get(n)
		if anim != null:
			for f in anim.frames:
				if f < total_frames():
					used[int(f)] = true
	var ratio: float = lp.frame_body_ratio
	var ul := used.keys()
	ul.sort()
	for f in ul:
		var b := frame_bbox(f)
		if b.x > ratio * bw or b.y > ratio * bh:
			add("pack.frame_body", "sheet.png#%d" % f, "第 %d 帧非透明区域 %dx%d 超过 body 的 %s 倍" % [f, b.x, b.y, fmt(ratio)])


func check_action(aid: String, a: Dictionary, eff: Dictionary, upgraded: bool) -> void:
	var d := data
	var p := "actions.%s" % aid
	if upgraded:
		var sv := SchemaValidator.new(Rules.schema())
		var serr := sv.validate(a, {"$ref": "#/$defs/action"})
		for se in serr:
			add("schema", p + "(upgraded)", se.msg)
		if not serr.is_empty():
			return
		check_action_refs(aid, a)
	var t: String = a.type
	in_range("cooldown", p + ".cooldown", a.get("cooldown", 0), L.cooldown)
	if t == "move":
		in_range("move.speed", p + ".speed", a.speed, L.move.speed)
		in_range("move.accel", p + ".accel", a.accel, L.move.accel)
	elif t == "jump":
		in_range("jump.velocity", p + ".velocity", a.velocity, L.jump.velocity)
		in_range("jump.max_count", p + ".max_count", a.max_count, L.jump.max_count)
		var arc := PackPoints.jump_arc(a.velocity, eff.stats.gravity, eff.stats.max_fall)
		at_least("jump.height_min", p + ".velocity", r6(arc[0]), L.jump.height_min)
		at_least("jump.reach_min", p, r6(PackPoints.min_move_speed(d) * arc[1]), L.jump.reach_min)
	elif t == "fly":
		for k in ["duration", "rise_speed", "control"]:
			in_range("fly." + k, p + "." + k, a[k], L.fly[k])
	if t in CharDef.ATTACK_TYPES:
		check_attack(aid, a, eff)
	elif "area" in a:
		add("ultimate.area", p + ".area", "area 只能用于大招")
	if t == "pose" and "throw" in a:
		var th: Dictionary = a.throw
		in_range("attack.damage", p + ".throw.damage", th.damage, L.attack.damage)
		in_range("attack.force", p + ".throw.knockback.force", th.knockback.force, L.attack.force)
		if th.frame >= CharDef.action_frames(a, d, eff):
			add("throw.frame", p + ".throw.frame", "throw.frame 超出动作帧数")
	var total := CharDef.action_frames(a, d, eff)
	if "armor" in a:
		var r: Array = a.armor
		var la: Dictionary = L.armor
		if r[0] < 0 or r[0] > r[1]:
			add("armor.frames", p + ".armor", "armor 区间无效")
		at_most("armor.frames", p + ".armor", CharDef.span_len(r), la.frames)
		if t in CharDef.ATTACK_TYPES:
			if r[1] >= a.startup + a.active:
				add("armor.window", p + ".armor", "armor 只能落在前摇+生效内")
			at_least("armor.min_startup", p + ".startup", a.startup, la.min_startup)
		else:
			add("armor.min_startup", p + ".armor", "armor 只能用于 startup >= %d 的攻击动作" % la.min_startup)
	for key in ["invuln", "reflect"]:
		if key in a:
			var r: Array = a[key]
			var lk: Dictionary = L[key]
			if r[0] < 0 or r[0] > r[1]:
				add(key + ".frames", p + "." + key, "%s 区间无效" % key)
			at_most(key + ".frames", p + "." + key, CharDef.span_len(r), lk.frames)
			at_least(key + ".min_cooldown", p + ".cooldown", a.get("cooldown", 0), lk.min_cooldown)
	if "motion" in a:
		var lm: Dictionary = L.motion
		var mo: Array = a.motion
		at_most("motion.entries", p + ".motion", mo.size(), lm.entries)
		for i in mo.size():
			at_most("motion.speed", "%s.motion.%d.vel" % [p, i], Vector2(mo[i].vel[0], mo[i].vel[1]).length(), lm.speed)
		at_most("motion.distance", p + ".motion", r6(PackPoints.motion_distance(a, total)), lm.distance)
	if "gravity_scale" in a:
		in_range("gravity_scale", p + ".gravity_scale", a.gravity_scale, L.gravity_scale)
	for l in a.get("links", []):
		if "warp" in l:
			at_least("warp.min_cooldown", p + ".cooldown", a.get("cooldown", 0), L.warp.min_cooldown)


func check_attack(aid: String, a: Dictionary, eff: Dictionary) -> void:
	var d := data
	var p := "actions.%s" % aid
	var la: Dictionary = L.attack
	var t: String = a.type
	var ult: bool = a.get("ultimate", false)
	var screen: bool = a.get("area") == "screen"
	var lu: Dictionary = L.ultimate
	var dmg_mul: float = lu.damage_mul if (ult and not screen) else 1.0
	var size_mul: float = lu.size_mul if (ult and not screen) else 1.0
	if ult:
		in_range("ultimate.startup", p + ".startup", a.startup, lu.startup)
	else:
		in_range("attack.startup", p + ".startup", a.startup, la.startup)
		if screen:
			add("ultimate.area", p + ".area", "area 只能用于大招")
	in_range("attack.active", p + ".active", a.active, la.active)
	in_range("attack.recovery", p + ".recovery", a.recovery, la.recovery)
	at_most("attack.total_frames", p, a.startup + a.active + a.recovery, la.total_frames)
	if screen and ult:
		at_least("attack.damage", p + ".damage", a.damage, la.damage[0])
	else:
		in_range("attack.damage", p + ".damage", a.damage, [la.damage[0], la.damage[1] * dmg_mul])
	var force: float = a.knockback.force
	in_range("attack.force", p + ".knockback.force", force, la.force)
	var hi: float = a.get("hit_interval", 0)
	if hi != 0:
		in_range("attack.hit_interval", p + ".hit_interval", hi, la.hit_interval)
	if screen:
		var lsc: Dictionary = lu.screen
		at_most("ultimate.screen.active", p + ".active", a.active, lsc.active)
		at_most("ultimate.screen.damage", p + ".damage", a.damage, lsc.damage)
		at_most("ultimate.screen.force", p + ".knockback.force", force, lsc.force)
	var ds: Dictionary = la.damage_startup
	var fs: Dictionary = la.force_startup
	var variants := [[float(a.damage), force, float(a.startup), ""]]
	if "charge" in a:
		var ch: Dictionary = a.charge
		in_range("charge.max", p + ".charge.max", ch.max, L.charge.max)
		in_range("charge.mult", p + ".charge.damage", ch.damage, L.charge.mult)
		in_range("charge.mult", p + ".charge.force", ch.force, L.charge.mult)
		variants.append([a.damage * ch.damage, force * ch.force, float(a.startup + ch.max), "（满蓄力）"])
	for v in variants:
		var lim_d: float = ds.base + ds.per_startup * v[2]
		var lim_f: float = fs.base + fs.per_startup * v[2]
		if v[0] > lim_d + 1e-9:
			add("attack.damage_startup", p + ".damage", "damage %s%s 超过 6 + 0.6 x startup = %s" % [fmt(v[0]), v[3], fmt(lim_d)])
		if v[1] > lim_f + 1e-9:
			add("attack.force_startup", p + ".knockback.force", "force %s%s 超过 20 + 2.5 x startup = %s" % [fmt(v[1]), v[3], fmt(lim_f)])
	if "status" in a:
		var st: Dictionary = a.status
		var lst: Dictionary = L.status[st.type]
		var sp := p + ".status"
		var code: String = "status." + st.type
		if st.type == "burn":
			in_range(code + ".damage", sp + ".damage", st.damage, lst.damage)
			at_least(code + ".interval_min", sp + ".interval", st.interval, lst.interval_min)
		if st.type == "slow":
			in_range(code + ".factor", sp + ".factor", st.factor, lst.factor)
		at_most(code + ".duration_max", sp + ".duration", st.duration, lst.duration_max)
	var total := PackPoints.target_damage(a, d)
	var lim: float = lu.target_damage if ult else la.target_damage
	at_most("ultimate.target_damage" if ult else "attack.target_damage", p, r6(total), lim)
	if t == "swing":
		check_swing(aid, a)
	else:
		check_shoot(aid, a, eff, size_mul, dmg_mul)


func check_swing(aid: String, a: Dictionary) -> void:
	var p := "actions.%s" % aid
	var la: Dictionary = L.attack
	for k in ["from", "to"]:
		in_range("attack.angle", p + "." + k, a[k], la.angle)
	at_most("attack.sweep", p, abs(a.to - a.from), la.sweep)
	var w: Dictionary = data.assets[a.weapon]
	var reach: float = w.length + a.reach[1]
	at_most("weapon.reach_total", p + ".reach", reach, L.weapon.reach_total)
	if a.get("grab", false):
		var lg: Dictionary = L.grab
		at_most("grab.reach_total", p + ".reach", reach, lg.reach_total)
		var th := PackPoints.grab_throw(a, data)
		if th.is_empty():
			add("grab.throw", p + ".links", "抓取动作必须有 on_hit 联动 goto 一个带 throw 的 pose 动作")
		else:
			var hold: float = 1 + th[1].throw.frame
			if "window" in th[0]:
				hold += max(0, th[0].window[1] - a.startup)
			at_most("grab.max_hold", p, hold, lg.max_hold)


func check_shoot(aid: String, a: Dictionary, eff: Dictionary, size_mul: float, dmg_mul: float) -> void:
	var d := data
	var p := "actions.%s" % aid
	var proj: Dictionary = d.assets[a.projectile]
	var kind := CharDef.shoot_kind(a, d.assets)
	var lb: Dictionary = L.bullet
	var sw: float = proj.size[0]
	var sh: float = proj.size[1]
	var sol: Array = a.get("scale_over_life", [1, 1])
	for i in sol.size():
		in_range("bullet.scale", "%s.scale_over_life.%d" % [p, i], sol[i], lb.scale)
	var smax: float = max(sol[0], sol[1])
	var msw := sw * smax
	var msh := sh * smax
	var bu: Array = _burst_use.get(aid, [false, true])
	var count: float = a.get("count", 1)
	var spread: float = a.get("spread", 0)
	if bu[1]:
		in_range("bullet.count", p + ".count", count, lb.count)
		in_range("bullet.spread", p + ".spread", spread, lb.spread)
	if bu[0]:
		in_range("bullet.burst_count", p + ".count", count, [1, lb.burst_count])
		in_range("bullet.burst_spread", p + ".spread", spread, [0, lb.burst_spread])
		at_most("bullet.burst_damage", p + ".damage", a.damage, lb.burst_damage * dmg_mul)
	if "hp" in a and kind != "deployable":
		add("shoot.hp", p + ".hp", "hp 只能用于布置物")
	in_range("bullet.speed", p + ".speed", a.speed, [0, lb.speed[1]])
	var hi: float = a.get("hit_interval", 0)
	if kind == "bullet":
		if proj.shape == "circle":
			in_range("bullet.circle_d", p + ".projectile", msw, [lb.circle_d[0], lb.circle_d[1] * size_mul])
		elif msw > lb.rect_max[0] * size_mul or msh > lb.rect_max[1] * size_mul:
			add("bullet.rect_max", p + ".projectile", "rect 子弹（含缩放）不得超过 %sx%s" % [fmt(lb.rect_max[0] * size_mul), fmt(lb.rect_max[1] * size_mul)])
		in_range("bullet.speed", p + ".speed", a.speed, lb.speed)
		var longest: float = max(msw, msh)
		if a.speed > lb.speed_side * size_mul / longest + 1e-9:
			add("bullet.speed_side", p + ".speed", "speed %s 超过 96 / 最长边(%s) = %s" % [fmt(a.speed), fmt(longest), fmt(lb.speed_side * size_mul / longest)])
		in_range("bullet.lifetime", p + ".lifetime", a.lifetime, lb.lifetime)
		at_most("bullet.damage", p + ".damage", a.damage, lb.damage * dmg_mul)
		var pierce: float = a.get("pierce", 0)
		if pierce != 0 or "pierce" in a:
			in_range("bullet.pierce", p + ".pierce", pierce, lb.pierce)
		in_range("bullet.turn_rate", p + ".turn_rate", a.get("turn_rate", 0), lb.turn_rate)
		in_range("bullet.gravity", p + ".gravity", a.get("gravity", 0), lb.gravity)
	elif kind == "beam":
		var lb2: Dictionary = L.beam
		at_most("beam.length", p + ".projectile", msw, lb2.length * size_mul)
		in_range("beam.width", p + ".projectile", msh, [lb2.width[0], lb2.width[1] * size_mul])
		at_least("beam.grow_min", p + ".grow", a.get("grow", 0), lb2.grow_min)
		at_least("beam.startup_min", p + ".startup", a.startup, lb2.startup_min)
		at_most("beam.lifetime", p + ".lifetime", a.lifetime, lb2.lifetime)
		at_least("beam.hit_interval_min", p + ".hit_interval", hi, lb2.hit_interval_min)
		at_most("beam.damage", p + ".damage", a.damage, lb2.damage * dmg_mul)
		at_most("beam.turn_rate", p + ".turn_rate", a.get("turn_rate", 0), lb2.turn_rate)
		if a.get("turn_rate", 0) < 0:
			add("beam.turn_rate", p + ".turn_rate", "turn_rate 须 >= 0")
		at_least("beam.cooldown_min", p + ".cooldown", a.get("cooldown", 0), lb2.cooldown_min)
	else:
		var ld: Dictionary = L.deployable
		if a.get("solid", false):
			if msw > ld.solid_size[0] * size_mul or msh > ld.solid_size[1] * size_mul:
				add("deployable.solid_size", p + ".projectile", "solid 布置物（含缩放）不得超过 %sx%s" % [fmt(ld.solid_size[0] * size_mul), fmt(ld.solid_size[1] * size_mul)])
		elif msw > ld.size[0] * size_mul or msh > ld.size[1] * size_mul:
			add("deployable.size", p + ".projectile", "布置物（含缩放）不得超过 %sx%s" % [fmt(ld.size[0] * size_mul), fmt(ld.size[1] * size_mul)])
		in_range("deployable.lifetime", p + ".lifetime", a.lifetime, ld.lifetime)
		if not ("hp" in a):
			add("deployable.hp", p + ".hp", "布置物必须填写 hp")
		else:
			in_range("deployable.hp", p + ".hp", a.hp, ld.hp)
		at_most("deployable.damage", p + ".damage", a.damage, ld.damage * dmg_mul)
		if hi != 0:
			add("deployable.hit_interval", p + ".hit_interval", "布置物 hit_interval 必须为 0")
		var bl := CharDef.bullet_links(a)
		for i in bl.size():
			var l: Dictionary = bl[i]
			var lp_ := "%s.links.%d" % [p, i]
			if l.when == "every":
				at_least("deployable.every_interval_min", lp_ + ".interval", l.interval, ld.every_interval_min)
			if "spawn" in l:
				var t = d.actions.get(l.spawn)
				if t != null and t.type == "shoot":
					for um in range(1 << CharDef.upgrade_count(t)):
						if CharDef.shoot_kind(CharDef.apply_upgrades(t, um), d.assets) != "bullet":
							add("deployable.spawn_kind", lp_ + ".spawn", "布置物的联动只能发射 bullet")
		var dist := deploy_distance(aid, a, eff)
		if dist < 0:
			add("deployable.distance", p, "布置物不能由子弹联动生成（无法保证放置距离）")
		else:
			at_most("deployable.distance", p, r6(dist), ld.distance)


## 布置物生成点到角色锚点的最大距离；-1 表示由子弹联动生成、无法确定。
func deploy_distance(aid: String, a: Dictionary, eff: Dictionary) -> float:
	var best := shoot_origin_distance(a, eff)
	for sid in data.actions:
		var s: Dictionary = data.actions[sid]
		for m in range(1 << CharDef.upgrade_count(s)):
			var us := CharDef.apply_upgrades(s, m)
			for l in us.get("links", []):
				if l.get("spawn") != aid:
					continue
				if us.type == "shoot" and l.when in CharDef.BULLET_WHEN:
					return -1.0
				best = max(best, anim_hand_distance(us.get("anim", ""), eff))
	return best


func anim_hand_distance(anim_name: String, eff: Dictionary) -> float:
	var anim = CharDef.resolve_anim(data, eff, anim_name) if anim_name != "" else null
	if anim == null or not ("hand" in anim):
		return eff.stats.body[1] / 2.0
	var ax: float = data.anchor[0]
	var ay: float = data.anchor[1]
	var best := 0.0
	for h in anim.hand:
		best = max(best, Vector2(h[0] - ax, h[1] - ay).length())
	return best


func shoot_origin_distance(a: Dictionary, eff: Dictionary) -> float:
	var anim = CharDef.resolve_anim(data, eff, a.anim)
	var ax: float = data.anchor[0]
	var ay: float = data.anchor[1]
	var hx := 0.0
	var hy := 0.0
	if anim == null or not ("hand" in anim) or anim.hand.size() < 2:
		hy = -eff.stats.body[1] / 2.0
	else:
		var h: Array = anim.hand[1]
		hx = h[0] - ax
		hy = -(h[1] - ay)
	if not ("weapon" in a):
		return Vector2(hx, hy).length()
	var length: float = data.assets[a.weapon].length
	if a.aim == "fixed":
		var r := deg_to_rad(a.angle)
		return Vector2(hx + cos(r) * length, hy + sin(r) * length).length()
	return Vector2(hx, hy).length() + length


# ---------------------------------------------------------------- 点数

func check_points() -> void:
	var forms: Array = data.get("forms", [])
	var n_input_forms := 0
	for f in forms:
		if "input" in f:
			n_input_forms += 1
	var P: Dictionary = R.points
	for mask in form_masks():
		var eff := CharDef.effective_form(data, mask)
		var label := CharDef.mask_label(mask, forms.size())
		var bd := PackPoints.form_points(data, eff, n_input_forms)
		points[label] = bd
		for aid in _sorted_keys(bd.actions):
			var pts: float = bd.actions[aid]
			if pts > P.action_max + 1e-9:
				add("points.action", "actions.%s" % aid, "形态 %s：动作 %s 点数 %.2f 超过 %s" % [label, aid, pts, fmt(P.action_max)])
		if bd.total > P.form_max + 1e-9:
			add("points.form", "forms.%s" % label, "形态 %s 总点数 %.2f 超过 %s" % [label, bd.total, fmt(P.form_max)])


## 人类可读的明细（拒绝原因 + 各形态点数）。
func report() -> String:
	var lines := PackedStringArray()
	if errors.is_empty():
		lines.append("通过")
	else:
		lines.append("不通过（%d 项）" % errors.size())
		for e in errors:
			lines.append("  [%s] %s" % [e.code, e.msg])
	var P: Dictionary = R.points
	for label in _sorted_keys(points):
		var bd: Dictionary = points[label]
		lines.append("点数 形态 %s：总计 %.2f / %s（hp %.2f，角色级联动 %.2f，形态输入 %.2f）" % [label, bd.total, fmt(P.form_max), bd.hp, bd.links, bd.forms_input])
		var ids: Array = bd.actions.keys()
		ids.sort_custom(func(x, y): return bd.actions[x] > bd.actions[y])
		for aid in ids:
			lines.append("    %s  %.2f%s" % [aid, bd.actions[aid], "  超出" if bd.actions[aid] > P.action_max else ""])
	return "\n".join(lines)
