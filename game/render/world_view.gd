class_name WorldView
extends Node2D
## 480×270 逻辑画面：场地、角色、子弹、特效、大招预警、调试叠加。只读快照。

var R: Dictionary
var assets: Array = []          # 每位玩家的 PackAssets
var fviews: Array = []
var pviews := {}                # 子弹 id -> ProjectileView
var proj_layer := Node2D.new()
var fighter_layer := Node2D.new()
var effects := EffectsLayer.new()
var dim := ColorRect.new()
var backdrop := AnimatedSprite2D.new()
var backdrop_key := ""
var debug_layer := DebugLayer.new()
var show_debug := false
var last := {}


func setup(p_assets: Array) -> void:
	R = Rules.data()
	assets = p_assets
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(R.stage.width, R.stage.height)
	dim.visible = false
	dim.z_index = 10
	backdrop.centered = false
	backdrop.z_index = 2
	backdrop.visible = false
	add_child(backdrop)
	proj_layer.z_index = 5
	fighter_layer.z_index = 4
	effects.z_index = 20
	debug_layer.z_index = 30
	add_child(fighter_layer)
	add_child(proj_layer)
	add_child(dim)
	add_child(effects)
	add_child(debug_layer)
	for i in assets.size():
		var v := FighterView.new()
		v.setup(assets[i], i)
		fighter_layer.add_child(v)
		fviews.append(v)


func apply(s: Dictionary) -> void:
	last = s
	for e in s.events:
		_event(e)
	for fs in s.fighters:
		var v: FighterView = fviews[fs.i]
		v.apply(fs)
		var caster: int = s.dim if s.dim >= 0 else s.get("ultbg", {}).get("i", -1)
		v.z_index = 20 if caster == fs.i else 0
		if "burn" in fs.status and v.visible:
			effects.fire(Vector2(fs.x, fs.y - 4), assets[fs.i].data.stats.body[0])
	_update_backdrop(s.get("ultbg", {}))
	dim.visible = s.dim >= 0 or backdrop.visible
	dim.color = Color(0, 0, 0, 0.35 if backdrop.visible else 0.6)
	var seen := {}
	for ps in s.proj:
		seen[ps.id] = true
		var pv: ProjectileView = pviews.get(ps.id)
		if pv == null:
			pv = ProjectileView.new()
			pv.setup(assets[_owner_assets(ps)], ps)
			proj_layer.add_child(pv)
			pviews[ps.id] = pv
		pv.apply(ps)
	for id in pviews.keys():
		if not (id in seen):
			pviews[id].queue_free()
			pviews.erase(id)
	effects.step()
	debug_layer.visible = show_debug
	if show_debug:
		debug_layer.snap = s
		debug_layer.queue_redraw()
	queue_redraw()


## 大招背景：施放者的 backdrop 盖住场地背景，其他角色被压暗、施放者高亮。
func _update_backdrop(bg: Dictionary) -> void:
	if bg.is_empty():
		backdrop.visible = false
		backdrop_key = ""
		return
	var b = assets[bg.i].backdrops.get(bg.as)
	if b == null:
		backdrop.visible = false
		return
	var key := "%d|%s" % [bg.i, bg.as]
	if key != backdrop_key:
		backdrop_key = key
		backdrop.sprite_frames = b.frames
		backdrop.scale = Vector2(b.scale, b.scale)
		backdrop.play("default")
	backdrop.visible = true


## 反射后归属会变，但贴图仍属于最初的角色包：按资产名在各包里找。
func _owner_assets(ps: Dictionary) -> int:
	var o: int = ps.o
	if ps.as in assets[o].textures:
		return o
	for i in assets.size():
		if ps.as in assets[i].textures:
			return i
	return o


func _event(e: Dictionary) -> void:
	match e.t:
		"hit":
			effects.sparks(Vector2(e.x, e.y), Color.WHITE, 6 + int(e.dmg))
		"block":
			effects.sparks(Vector2(e.x, e.y), Palette.SHIELD, 4)
		"shield_break":
			effects.sparks(Vector2(e.x, e.y), Palette.SLOW, 16)
		"reflect":
			effects.sparks(Vector2(e.x, e.y), Palette.REFLECT, 6)
		"explode":
			var a: PackAssets = assets[e.i]
			effects.burst_pixels(a.frame_image(e.anim, e.ai), Vector2(e.x, e.y), a.anchor, e.f)
		"fx":
			var fr = assets[e.i].fx_frames.get(e.name)
			if fr != null:
				effects.play_fx(fr, Vector2(e.x, e.y), e.f)
		"res_gain":
			var r: Dictionary = assets[e.i].data.resources[e.res]
			var hud: String = r.get("hud", "")
			if hud != "" and hud != "bar" and hud in assets[e.i].textures:
				var fv: FighterView = fviews[e.i]
				effects.float_icon(assets[e.i].textures[hud], fv.position - Vector2(0, assets[e.i].data.stats.body[1] + 8))
	if "i" in e and e.i < fviews.size():
		fviews[e.i].on_event(e)


func _draw() -> void:
	var W: float = R.stage.width
	var H: float = R.stage.height
	# 背景
	var bands := 6
	for i in bands:
		var c := Palette.SKY_TOP.lerp(Palette.SKY_BOTTOM, float(i) / (bands - 1))
		draw_rect(Rect2(0, H * i / bands, W, H / bands + 1), c)
	var m: Dictionary = R.stage.main
	draw_rect(Rect2(m.x, m.y, m.w, m.h), Palette.STAGE_BODY)
	draw_rect(Rect2(m.x, m.y, m.w, 3), Palette.STAGE_TOP)
	draw_rect(Rect2(m.x, m.y + m.h - 2, m.w, 2), Palette.STAGE_EDGE)
	for p in R.stage.platforms:
		draw_rect(Rect2(p.x, p.y, p.w, 3), Palette.PLATFORM)
		draw_rect(Rect2(p.x, p.y + 3, p.w, 1), Palette.STAGE_EDGE)
