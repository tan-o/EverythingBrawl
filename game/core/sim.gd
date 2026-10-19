class_name MatchSim
extends RefCounted
## 一局对战的完整模拟（房主权威）。step() 推进一帧，snapshot() 给渲染与联机。
## 包含规范 3.1 的全部运行时限制。

var R: Dictionary
var fighters: Array = []
var projectiles: Array = []
var frame := 0
var events: Array = []
var over := false
var winner := -1
var over_t := 0
var debug := false

var stage: Stage
var _next_proj := 1


func _init(chars: Array, stage_data: Dictionary) -> void:
	R = Rules.data()
	stage = Stage.new(stage_data)
	for i in chars.size():
		var f := Fighter.new()
		f.setup(self, i, chars[i], stage.spawns[i % stage.spawns.size()])
		fighters.append(f)


func dispose() -> void:
	for f in fighters:
		f.sim = null
		f.grabbing = null
		f.grabbed_by = null
	fighters.clear()
	projectiles.clear()


func emit(e: Dictionary) -> void:
	events.append(e)


# ---------------------------------------------------------------- 帧推进

func step(inputs: Array) -> void:
	events = []
	frame += 1
	events.append_array(stage.step())
	for i in fighters.size():
		fighters[i].begin_frame(inputs[i] if i < inputs.size() and inputs[i] != null else InputFrame.new())
	for f in fighters:
		if f.hitlag > 0:
			f.hitlag -= 1
			continue
		f.tick()
	_stage_hazards()
	_stage_attacks()
	_update_projectiles()
	_resolve_hits()
	_cleanup()
	_check_end()


func _check_end() -> void:
	if fighters.size() < 2:
		return
	var left := []
	for f in fighters:
		if f.state != "out":
			left.append(f)
	if over:
		over_t += 1
		return
	if left.size() <= 1:
		over = true
		winner = left[0].idx if left.size() == 1 else -1
		if winner >= 0:
			fighters[winner].set_override("victory")
			fighters[winner].override_t = 100000
		emit({"t": "game_over", "winner": winner})


# ---------------------------------------------------------------- 平台物理

## 可落脚的顶面：[Rect2, 单向?, 元素下标(-1 = solid 布置物)]
func _surfaces(f: Fighter) -> Array:
	var out := []
	for i in stage.colliders():
		var e: Dictionary = stage.els[i]
		var oneway: bool = e.def.collide == "platform"
		if oneway and f.drop_timer > 0:
			continue
		out.append([e.rect, oneway, i])
	for p in projectiles:
		if not p.dead and p.solid:
			out.append([p.top_rect(), true, -1])
	return out


func _solids() -> Array:
	var out := []
	for i in stage.colliders():
		if stage.els[i].def.collide == "solid":
			out.append(i)
	return out


func move_fighter(f: Fighter) -> void:
	var b := f.body_size()
	var hw := b.x / 2.0
	# 站在移动平台上 / 贴墙时随之移动；传送带
	if f.on_ground and f.ground_el >= 0:
		var ge: Dictionary = stage.els[f.ground_el]
		f.pos += ge.delta
		f.pos.x += ge.def.get("conveyor", 0.0)
	elif f.state == "cling" and f.wall_el >= 0:
		f.pos += stage.els[f.wall_el].delta
	# 水平
	f.pos.x += f.vel.x
	f.wall_el = -1
	for i in _solids():
		var sr: Rect2 = stage.els[i].rect
		var r := f.body_rect()
		var touching := r.grow_individual(1, 0, 1, 0).intersects(sr) and r.end.y > sr.position.y + 2 and r.position.y < sr.end.y
		if r.intersects(sr):
			if f.pos.x < sr.get_center().x:
				f.pos.x = sr.position.x - hw
			else:
				f.pos.x = sr.end.x + hw
			f.vel.x = 0
		if touching and "climb" in stage.els[i].def:
			f.wall_el = i
			f.wall_dir = 1 if f.pos.x < sr.get_center().x else -1
	# 垂直
	var prev_bottom := f.pos.y
	var prev_top := f.pos.y - b.y
	f.pos.y += f.vel.y
	var landed := false
	var ground := -2
	if f.vel.y >= 0:
		for s in _surfaces(f):
			var sr: Rect2 = s[0]
			if f.pos.x + hw <= sr.position.x or f.pos.x - hw >= sr.end.x:
				continue
			var tol := 0.01
			if s[2] >= 0:
				tol += abs(stage.els[s[2]].delta.y)
			if prev_bottom <= sr.position.y + tol and f.pos.y >= sr.position.y:
				f.pos.y = sr.position.y
				f.vel.y = 0
				landed = true
				ground = s[2]
				break
	else:
		for i in _solids():
			var sr: Rect2 = stage.els[i].rect
			if f.body_rect().intersects(sr) and prev_top >= sr.end.y - 0.01:
				f.pos.y = sr.end.y + b.y
				f.vel.y = 0
	# 被移动的实心地形挤进身体时，推到它上面
	for i in _solids():
		var sr: Rect2 = stage.els[i].rect
		if f.body_rect().intersects(sr) and f.pos.y - sr.position.y < 8:
			f.pos.y = sr.position.y
			f.vel.y = min(f.vel.y, 0.0)
			landed = true
			ground = i
	f.on_ground = landed
	f.ground_el = ground if landed else -1
	f.ground_oneway = false
	if landed:
		if ground < 0:
			f.ground_oneway = true
		else:
			var gd: Dictionary = stage.els[ground].def
			f.ground_oneway = gd.collide == "platform"
			stage.stood_on(ground)
			if "bounce" in gd:
				f.vel.y = -float(gd.bounce.velocity)
				f.on_ground = false
				f.ground_el = -1
				emit({"t": "bounce", "i": f.idx, "x": f.pos.x, "y": f.pos.y})


## 脚下地形的摩擦倍率（冰面 < 1，粘地 > 1）。
func ground_friction_mul(f: Fighter) -> float:
	if f.on_ground and f.ground_el >= 0:
		return float(stage.els[f.ground_el].def.get("friction", 1.0))
	return 1.0


func standing_on_oneway(f: Fighter) -> bool:
	return f.on_ground and f.ground_oneway


## 角色所在区域的风与水：{"wind": Vector2, "gravity_mul": float, "drag": float}
func zone_at(f: Fighter) -> Dictionary:
	var z := {"wind": Vector2.ZERO, "gravity_mul": 1.0, "drag": 1.0}
	var body := f.body_rect()
	for i in stage.zones():
		var e: Dictionary = stage.els[i]
		if not body.intersects(e.rect):
			continue
		if "wind" in e.def:
			z.wind += Vector2(e.def.wind[0], e.def.wind[1])
		if "water" in e.def:
			z.gravity_mul = min(z.gravity_mul, float(e.def.water.gravity_mul))
			z.drag = min(z.drag, float(e.def.water.drag))
	return z


func _stage_hazards() -> void:
	for f in fighters:
		if not f.targetable() or f.is_invulnerable() or f.state == "grabbed":
			continue
		var body: Rect2 = f.body_rect()
		for i in stage.zones():
			var e: Dictionary = stage.els[i]
			if not ("damage" in e.def):
				continue
			var r: Rect2 = e.rect.grow(1.0 if e.def.collide != "none" else 0.0)
			if not body.intersects(r):
				continue
			var dm: Dictionary = e.def.damage
			if frame - int(f.hazard_cd.get(i, -100000)) < int(dm.interval):
				continue
			f.hazard_cd[i] = frame
			var c: Vector2 = f.center()
			apply_damage(null, f, dm.damage)
			f.flash = 6
			emit({"t": "hit", "i": f.idx, "tgt": f.idx, "x": c.x, "y": c.y, "dmg": dm.damage, "sfx": ""})
			if f.alive():
				_knockback(f, dm.knockback.angle, dm.knockback.force, 1 if c.x >= r.get_center().x else -1, 0)


func _stage_attacks() -> void:
	for shot in stage.traps.shots:
		for f in fighters:
			if not f.targetable() or f.is_invulnerable() or f.state == "grabbed":
				continue
			if Geom.overlap(Geom.capsule(shot.prev, shot.pos, shot.radius), Geom.aabb(f.body_rect())):
				_trap_hit(f, shot.def, shot.pos)
				shot.life = 0
				break
	stage.traps.shots = stage.traps.shots.filter(func(s): return s.life > 0)
	for swing in stage.traps.swings:
		var key := "trap:%d" % swing.el
		for f in fighters:
			if not f.targetable() or f.is_invulnerable() or f.state == "grabbed" or f.hazard_cd.get(key, -1) == swing.cycle:
				continue
			if Geom.overlap(Geom.capsule(swing.pos, swing.tip, swing.def.radius), Geom.aabb(f.body_rect())):
				f.hazard_cd[key] = swing.cycle
				_trap_hit(f, swing.def, swing.pos)


func _trap_hit(f: Fighter, attack: Dictionary, origin: Vector2) -> void:
	var c := f.center()
	apply_damage(null, f, attack.damage)
	f.flash = 6
	emit({"t": "hit", "i": f.idx, "tgt": f.idx, "x": c.x, "y": c.y, "dmg": attack.damage, "sfx": ""})
	if f.alive():
		_knockback(f, attack.knockback.angle, attack.knockback.force, 1 if c.x >= origin.x else -1, 0)


func out_of_bounds(f: Fighter) -> bool:
	var m: float = R.stage.blast_margin
	var c := f.center()
	return c.x < -m or c.x > R.stage.width + m or c.y > R.stage.height + m or c.y < -m


## 点是否在某个实心地形内（子弹撞墙）。
func in_solid(p: Vector2) -> bool:
	for i in _solids():
		if stage.els[i].rect.has_point(p):
			return true
	return false


## 可破坏 / 会碎的地形挨打（自己和对方的攻击都算）。
func hit_stage(shape: Dictionary, dmg: float, hits: Dictionary, hi: int) -> bool:
	var any := false
	for i in stage.colliders():
		var e: Dictionary = stage.els[i]
		if not Stage.hittable(e.def):
			continue
		var key := "e%d" % i
		if not _can_hit(hits, key, hi, frame) or not Geom.overlap(shape, Geom.aabb(e.rect)):
			continue
		hits[key] = frame
		any = true
		if stage.damage(i, dmg):
			emit({"t": "stage_break", "el": i, "x": e.rect.get_center().x, "y": e.rect.get_center().y})
	return any


# ---------------------------------------------------------------- 子弹生成

func _owner_count(owner: int, kinds: Array) -> int:
	var n := 0
	for p in projectiles:
		if not p.dead and p.owner == owner and p.kind in kinds and not p.ult:
			n += 1
	return n


func _owner_area(owner: int) -> float:
	var s := 0.0
	for p in projectiles:
		if not p.dead and p.owner == owner and not p.ult:
			s += p.full_area()
	return s


## 发射一个 shoot 动作的全部子弹。proj 非空表示由子弹联动发射（从子弹位置）。
func fire_shoot(f: Fighter, a: Dictionary, proj, depth: int, inst: int, charge_ratio: float) -> void:
	if depth > int(R.runtime.max_link_depth):
		return
	var rt: Dictionary = R.runtime
	var kind: String = a._kind
	var ult: bool = a.get("ultimate", false)
	var count := int(a.get("count", 1))
	var spread: float = a.get("spread", 0)
	var facing: int = proj.facing if proj != null else f.facing
	var base: float = a.angle
	if a.aim == "input":
		var st := f.input.stick()
		if st.length() >= 0.5:
			base = rad_to_deg(atan2(-st.y, st.x * facing))
	var asset := f.ch.asset(a.projectile)
	var dmg_mul := 1.0
	var kb_mul := 1.0
	if "charge" in a and charge_ratio > 0:
		dmg_mul = lerp(1.0, float(a.charge.damage), charge_ratio)
		kb_mul = lerp(1.0, float(a.charge.force), charge_ratio)
	for i in count:
		var ang := base
		if count > 1:
			if spread >= 360:
				ang = base + 360.0 * i / count
			else:
				ang = base - spread / 2.0 + spread * i / (count - 1)
		var p := Projectile.new()
		p.owner = f.idx
		p.kind = kind
		p.asset = a.projectile
		p.shape = asset.shape
		p.size = Vector2(asset.size[0], asset.size[1])
		var sol: Array = a.get("scale_over_life", [1, 1])
		p.scale_from = sol[0]
		p.scale_to = sol[1]
		p.max_scale = max(sol[0], sol[1])
		p.ult = ult
		if not ult:
			if f.spawned_this_frame >= int(rt.max_spawn_per_frame):
				return
			if kind != "deployable" and _owner_count(f.idx, ["bullet", "beam"]) >= int(rt.max_shots):
				return
			if _owner_area(f.idx) + p.full_area() > rt.max_area:
				return
			if kind == "deployable":
				var mine := []
				for q in projectiles:
					if not q.dead and q.owner == f.idx and q.kind == "deployable" and not q.ult:
						mine.append(q)
				while mine.size() >= int(rt.max_deployables):
					mine.pop_front().dead = true
		f.spawned_this_frame += 1
		p.id = _next_proj
		_next_proj += 1
		p.facing = facing
		p.fang = ang
		p.dir = f.facing_dir(ang, facing)
		p.pos = proj.pos if proj != null else f.shoot_origin(a, ang, inst >= 0)
		p.speed = a.speed
		p.vel = p.dir * p.speed
		p.lifetime = int(a.lifetime)
		p.damage = a.damage * dmg_mul
		p.kb_angle = a.knockback.angle
		p.kb_force = a.knockback.force * kb_mul
		p.hit_interval = int(a.get("hit_interval", 0))
		p.status = a.get("status")
		p.pierce = int(a.get("pierce", 0))
		p.hp = float(a.get("hp", 0))
		p.attach = a.get("attach", false) and proj == null
		if p.attach and "socket" in a:
			p.origin_action = a
		p.offset = Vector2((p.pos.x - f.pos.x) * facing, p.pos.y - f.pos.y)
		p.grow = int(a.get("grow", 0))
		p.solid = a.get("solid", false)
		p.returns = a.get("return", false)
		p.gravity = a.get("gravity", 0)
		p.turn_rate = a.get("turn_rate", 0)
		p.steer = a.aim == "steer"
		p.links = CharDef.bullet_links(a)
		p.inst = inst
		p.screen = a.get("area") == "screen"
		p.action_id = ""
		p.sfx_hit = a.get("sfx", {}).get("hit", "")
		projectiles.append(p)
		emit({"t": "spawn", "id": p.id, "i": f.idx})


func kill_attached(f: Fighter, inst: int) -> void:
	for p in projectiles:
		if p.attach and p.owner == f.idx and p.inst == inst:
			p.dead = true


func remove_owned(f: Fighter) -> void:
	for p in projectiles:
		if p.attach and p.owner == f.idx:
			p.dead = true


# ---------------------------------------------------------------- 子弹运动

func _update_projectiles() -> void:
	var W: float = R.stage.width
	var H: float = R.stage.height
	var m: float = R.stage.blast_margin * 2
	for p in projectiles.duplicate():
		if p.dead:
			continue
		var o: Fighter = fighters[p.owner]
		p.age += 1
		if p.age > p.lifetime:
			_expire(p)
			continue
		if p.steer:
			var st := o.input.stick()
			if st.length() >= 0.5:
				var target := st.normalized()
				var cur: Vector2 = p.dir
				var da: float = cur.angle_to(target)
				var mx := deg_to_rad(p.turn_rate)
				var turn: float = clamp(da, -mx, mx)
				p.dir = cur.rotated(turn)
				p.fang = rad_to_deg(atan2(-p.dir.y, p.dir.x * p.facing))
		if p.attach:
			if not o.alive():
				p.dead = true
				continue
			p.facing = o.facing
			p.pos = o.shoot_origin(p.origin_action, p.fang, false) if not p.origin_action.is_empty() else o.pos + Vector2(p.offset.x * o.facing, p.offset.y)
			p.dir = o.facing_dir(p.fang)
		else:
			if p.returns and not p.returning and p.age >= p.lifetime / 2.0:
				p.returning = true
			if p.returning:
				p.vel = (o.center() - p.pos).normalized() * max(p.speed, 1.0)
			elif p.steer:
				p.vel = p.dir * p.speed
			p.vel.y += p.gravity
			p.pos += p.vel
			if p.vel.length() > 0.01 and p.speed > 0:
				p.dir = p.vel.normalized()
			if p.kind == "deployable" and p.vel != Vector2.ZERO:
				_land_deployable(p)
			if p.kind == "bullet" and in_solid(p.pos):
				_expire(p)
				continue
			if p.returning and Geom.overlap(p.hit_shape(), o.body_shape()):
				p.dead = true
				continue
		if p.pos.x < -m or p.pos.x > W + m or p.pos.y < -m or p.pos.y > H + m:
			_expire(p)
			continue
		for l in p.links:
			if (l.when == "on_frame" and int(l.frame) == p.age) or (l.when == "every" and p.age % int(l.interval) == 0):
				if o.alive():
					o.fire_bullet_link(l, p)


func _land_deployable(p: Projectile) -> void:
	var half := p.size.y * p.scale() / 2.0
	var bottom := p.pos.y + half
	var prev_bottom := bottom - p.vel.y
	for i in stage.colliders():
		var sr: Rect2 = stage.els[i].rect
		if p.pos.x < sr.position.x or p.pos.x > sr.end.x:
			continue
		if p.vel.y >= 0 and prev_bottom <= sr.position.y + 0.01 and bottom >= sr.position.y:
			p.pos.y = sr.position.y - half
			p.vel = Vector2.ZERO
			return


func _expire(p: Projectile) -> void:
	if p.dead:
		return
	p.dead = true
	var o: Fighter = fighters[p.owner]
	for l in p.links:
		if l.when == "projectile_expire" and o.alive():
			o.fire_bullet_link(l, p)


func _cleanup() -> void:
	var keep := []
	for p in projectiles:
		if not p.dead:
			keep.append(p)
	projectiles = keep


# ---------------------------------------------------------------- 命中

static func _can_hit(hits: Dictionary, key, hi: int, now: int) -> bool:
	if not (key in hits):
		return true
	if hi == 0:
		return false
	return now - int(hits[key]) >= hi


func _resolve_hits() -> void:
	for f in fighters:
		if not f.alive() or f.act.is_empty() or f.hitlag > 0:
			continue
		var a: Dictionary = f.act.def
		if not (a.type in CharDef.ATTACK_TYPES) or f.act_phase() != "active":
			continue
		var screen: bool = a.get("area") == "screen" and a.get("ultimate", false)
		if a.type == "shoot" and not screen:
			continue
		var shape: Dictionary = {} if screen else f.swing_shape()
		var hi := int(a.get("hit_interval", 0))
		var mul := _charge_mul(f, a)
		var params := {
			"damage": a.damage * mul[0], "angle": a.knockback.angle, "force": a.knockback.force * mul[1],
			"status": a.get("status"), "grab": a.get("grab", false), "screen": screen,
			"facing": f.facing, "melee": true, "sfx": a.get("sfx", {}).get("hit", ""), "inst": f.act.inst,
		}
		for t in fighters:
			if t == f or not t.targetable() or f.act.is_empty():
				continue
			if not screen and not Geom.overlap(shape, t.body_shape()):
				continue
			if not _can_hit(f.act.hits, t.idx, hi, frame):
				continue
			if hit_fighter(f, t, params, null):
				if not f.act.is_empty():
					f.act.hits[t.idx] = frame
		if f.act.is_empty():
			continue
		for q in projectiles:
			if q.dead or q.kind != "deployable" or q.owner == f.idx:
				continue
			var key := "p%d" % q.id
			if (screen or Geom.overlap(shape, q.hit_shape())) and _can_hit(f.act.hits, key, hi, frame):
				f.act.hits[key] = frame
				_damage_deployable(q, params.damage)
		if not screen and not shape.is_empty():
			hit_stage(shape, params.damage, f.act.hits, hi)
	for p in projectiles:
		if p.dead:
			continue
		var o: Fighter = fighters[p.owner]
		var shape: Dictionary = p.hit_shape()
		for t in fighters:
			if p.dead:
				break
			if t.idx == p.owner or not t.targetable():
				continue
			if p.kind == "bullet" and t.reflecting() and Geom.overlap(shape, Geom.grow(t.body_shape(), R.combat.reflect_margin)):
				_reflect(p, t)
				break
			if not Geom.overlap(shape, t.body_shape()) or not _can_hit(p.hits, t.idx, p.hit_interval, frame):
				continue
			var params := {
				"damage": p.damage, "angle": p.kb_angle, "force": p.kb_force, "status": p.status, "grab": false,
				"screen": p.screen and p.ult, "facing": p.facing, "melee": false, "sfx": p.sfx_hit, "inst": p.inst,
			}
			var hit_result := hit_fighter(o, t, params, p)
			if hit_result:
				p.hits[t.idx] = frame
				_on_projectile_contact(p, o)
		if p.dead or p.kind == "deployable":
			continue
		if hit_stage(shape, p.damage, p.hits, p.hit_interval):
			_on_projectile_contact(p, o, false)
			if p.dead:
				continue
		for q in projectiles:
			if q.dead or q.kind != "deployable" or q.owner == p.owner or q == p:
				continue
			var key := "p%d" % q.id
			if Geom.overlap(p.hit_shape(), q.hit_shape()) and _can_hit(p.hits, key, p.hit_interval, frame):
				p.hits[key] = frame
				_damage_deployable(q, p.damage)
				_on_projectile_contact(p, o, false)
				if p.dead:
					break


func _charge_mul(f: Fighter, a: Dictionary) -> Array:
	if not ("charge" in a) or f.act.ratio <= 0:
		return [1.0, 1.0]
	return [lerp(1.0, float(a.charge.damage), f.act.ratio), lerp(1.0, float(a.charge.force), f.act.ratio)]


func _on_projectile_contact(p: Projectile, o: Fighter, fighter_hit := true) -> void:
	if fighter_hit:
		for l in p.links:
			if l.when == "projectile_hit" and o.alive():
				o.fire_bullet_link(l, p)
	if p.pierce == 0:
		p.dead = true
	elif p.pierce > 0:
		p.pierce -= 1


func _reflect(p: Projectile, t: Fighter) -> void:
	p.owner = t.idx
	p.vel = -p.vel
	p.dir = -p.dir
	p.facing = -p.facing
	p.hits = {}
	p.inst = -1
	p.returning = false
	p.returns = false
	emit({"t": "reflect", "i": t.idx, "x": p.pos.x, "y": p.pos.y})


func _damage_deployable(q: Projectile, dmg: float) -> void:
	q.hp -= dmg
	emit({"t": "hit_object", "id": q.id, "x": q.pos.x, "y": q.pos.y})
	if q.hp <= 0:
		_expire(q)


## 返回是否接触（命中或被防御）。
func hit_fighter(att: Fighter, t: Fighter, prm: Dictionary, proj) -> bool:
	if t.is_invulnerable():
		return false
	var hitpos := t.center()
	if prm.grab:
		if t.grab_immune > 0 or t.state == "grabbed" or t.grabbing != null or att.grabbing != null:
			return false
		t.become_grabbed(att)
		att.grabbing = t
		apply_damage(att, t, prm.damage * _combo_damage(t))
		t.combo_n += 1
		emit({"t": "grab", "i": att.idx, "tgt": t.idx})
		att.on_action_hit(prm.inst)
		return true
	if t.state == "guard":
		var sh: Dictionary = R.combat.shield
		if prm.screen:
			t.shield = 0.0
		else:
			t.shield -= prm.damage
			if t.shield <= 0:
				t.state = "shieldbreak"
				t.state_t = int(sh.break_stun)
				t.shield = float(sh.after_break)
				emit({"t": "shield_break", "i": t.idx, "x": hitpos.x, "y": hitpos.y})
				return true
		emit({"t": "block", "i": t.idx, "x": hitpos.x, "y": hitpos.y})
		return true
	var n := t.combo_n
	var dmg: float = prm.damage * _combo_damage(t)
	t.combo_n += 1
	apply_damage(att, t, dmg)
	t.flash = 6
	emit({"t": "hit", "i": att.idx, "tgt": t.idx, "x": hitpos.x, "y": hitpos.y, "dmg": dmg, "sfx": prm.sfx})
	if proj == null:
		att.on_action_hit(prm.inst)
	elif prm.inst >= 0:
		att.on_action_hit(prm.inst)
	if not t.alive():
		return true
	t.on_hurt()
	if not t.armored():
		_knockback(t, prm.angle, prm.force, prm.facing, n)
	if prm.status != null:
		t.apply_status(prm.status, att.idx)
	var hl: Dictionary = R.combat.hitlag
	var lag := int(min(hl.base + dmg / hl.damage_div, hl.max))
	t.hitlag = lag
	if prm.melee:
		att.hitlag = lag
	return true


func _combo_damage(t: Fighter) -> float:
	var c: Dictionary = R.runtime.combo
	return max(c.damage_min, 1.0 - c.damage_step * t.combo_n)


func _knockback(t: Fighter, angle: float, force: float, facing: int, n: int) -> void:
	var kb: Dictionary = R.combat.knockback
	var hs: Dictionary = R.combat.hitstun
	var c: Dictionary = R.runtime.combo
	var speed: float = force / kb.force_div * (kb.base - kb.per_weight * t.stats().weight)
	t.interrupt()
	t.vel = t.facing_dir(angle, facing) * speed
	if t.vel.y < 0:
		t.on_ground = false
	var stun: float = min(hs.base + force * hs.per_force, hs.max) * max(c.hitstun_min, 1.0 - c.hitstun_step * n)
	t.state = "hitstun"
	t.state_t = int(round(stun))


func apply_damage(att, t: Fighter, dmg: float) -> void:
	if not t.alive() or dmg <= 0:
		return
	var u: Dictionary = R.combat.ult
	t.hp -= dmg
	t.ult = min(float(u.max), t.ult + dmg * u.per_damage_taken)
	if att != null and att != t:
		att.ult = min(float(u.max), att.ult + dmg * u.per_damage_dealt)
	if t.hp <= 0:
		t.hp = 0
		t.start_ko()


func do_throw(f: Fighter, th: Dictionary) -> void:
	var t: Fighter = f.grabbing
	f.release_grabbed_target(true)
	if t == null or not t.alive():
		return
	var n := t.combo_n
	var dmg: float = th.damage * _combo_damage(t)
	t.combo_n += 1
	apply_damage(f, t, dmg)
	t.flash = 6
	var c := t.center()
	emit({"t": "hit", "i": f.idx, "tgt": t.idx, "x": c.x, "y": c.y, "dmg": dmg, "sfx": ""})
	if t.alive():
		_knockback(t, th.knockback.angle, th.knockback.force, f.facing, n)


# ---------------------------------------------------------------- 快照

func ult_dim_owner() -> int:
	for f in fighters:
		if not f.act.is_empty() and f.act.def.get("ultimate", false) and f.act_phase() == "startup":
			return f.idx
	return -1


## 大招背景：施放者在大招前摇与生效期间，若动作带 backdrop，返回 {i, as, t}。
func ult_backdrop() -> Dictionary:
	for f in fighters:
		if f.act.is_empty() or not f.act.def.get("ultimate", false) or not ("backdrop" in f.act.def):
			continue
		var ph: String = f.act_phase()
		if ph == "startup" or ph == "active":
			return {"i": f.idx, "as": f.act.def.backdrop, "t": f.act.t}
	return {}


func snapshot() -> Dictionary:
	var fs := []
	for f in fighters:
		var st := {}
		for k in f.statuses:
			st[k] = f.statuses[k].t
		var wv: Dictionary = f.weapon_visual()
		var d := {
			"i": f.idx, "x": f.pos.x, "y": f.pos.y, "vx": f.vel.x, "vy": f.vel.y, "f": f.facing,
			"st": f.state, "a": f.anim_name, "ai": f.anim_idx, "hp": f.hp, "lives": f.lives,
			"sh": f.shield, "ult": f.ult, "res": f.res.duplicate(), "status": st,
			"act": f.act.get("id", ""), "af": f.act.get("cur", 0), "inv": f.is_invulnerable() and f.alive(),
			"armor": f.armored(), "refl": f.reflecting(), "flash": f.flash, "ground": f.on_ground,
			"grab": f.grabbed_by.idx if f.grabbed_by != null else -1, "mask": f.mask,
			"wpn": wv, "ultready": f.ch.ult_id != "" and f.ult >= float(R.combat.ult.max),
		}
		if debug:
			d["dbg_swing"] = f.swing_shape()
			d["dbg_body"] = f.body_rect()
		fs.append(d)
	var ps := []
	for p in projectiles:
		ps.append({
			"id": p.id, "o": p.owner, "k": p.kind, "as": p.asset, "x": p.pos.x, "y": p.pos.y,
			"ang": p.dir.angle(), "len": p.length(), "sc": p.scale(), "hp": p.hp,
			"life": 1.0 - float(p.age) / max(1, p.lifetime), "shape": p.hit_shape() if debug else {},
		})
	return {"frame": frame, "fighters": fs, "proj": ps, "stage": stage.snapshot(), "traps": stage.traps.snapshot(), "dim": ult_dim_owner(), "ultbg": ult_backdrop(), "over": over, "winner": winner, "events": events}
