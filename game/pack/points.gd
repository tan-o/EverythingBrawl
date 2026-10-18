class_name PackPoints
extends RefCounted
## 点数预算（规范第 6 节）与校验用到的派生量。系数全部来自 rules.json 的 points 段。


static func P() -> Dictionary:
	return Rules.data().points


static func motion_distance(a: Dictionary, total: int) -> float:
	var mo: Array = a.get("motion", []).duplicate()
	mo.sort_custom(func(x, y): return x.frame < y.frame)
	if "charge" in a:
		total += int(a.charge.max)
	var v := Vector2.ZERO
	var dist := 0.0
	for i in mo.size():
		var m: Dictionary = mo[i]
		var mv := Vector2(m.vel[0], m.vel[1])
		if m.get("mode", "set") == "add":
			v += mv
		else:
			v = mv
		var end: float = mo[i + 1].frame if i + 1 < mo.size() else float(total)
		dist += v.length() * max(0.0, end - m.frame)
	return dist


static func burn_total(a: Dictionary) -> float:
	var st = a.get("status")
	if st == null or st.type != "burn":
		return 0.0
	return st.damage * floor(st.duration / st.interval)


## [on_hit 联动, throw pose]；没有则返回空数组。
static func grab_throw(a: Dictionary, d: Dictionary) -> Array:
	for l in a.get("links", []):
		if l.when == "on_hit" and "goto" in l:
			var t = d.actions.get(l.goto)
			if t != null and t.type == "pose" and "throw" in t:
				return [l, t]
	return []


static func hit_count(window: float, hi: float) -> int:
	if hi == 0:
		return 1
	return int(ceil(window / hi))


static func target_damage(a: Dictionary, d: Dictionary) -> float:
	var hi: float = a.get("hit_interval", 0)
	var dmg: float = a.damage
	if "charge" in a:
		dmg *= a.charge.damage
	var total: float
	if a.get("area") == "screen":
		total = dmg * hit_count(a.active, hi)
	elif a.type == "swing":
		total = dmg * hit_count(a.active, hi)
		if a.get("grab", false):
			var th := grab_throw(a, d)
			if not th.is_empty():
				total += th[1].throw.damage
	else:
		total = dmg * hit_count(a.lifetime, hi) * a.get("count", 1)
	return total + burn_total(a)


static func every_triggers(window: float, interval: float) -> float:
	var e: Dictionary = P().extra.every
	return min(window / interval, e.max) * e.mul


static func attack_base_points(a: Dictionary, d: Dictionary) -> float:
	var pa: Dictionary = P().attack
	var t: String = a.type
	var hi: float = a.get("hit_interval", 0)
	var window: float = a.active if t == "swing" else a.lifetime
	var hits: float = 1 if hi == 0 else min(int(ceil(window / hi)), pa.max_hits)
	var count: float = a.get("count", 1) if t == "shoot" else 1.0
	var spread: float = a.get("spread", 0) if t == "shoot" else 0.0
	var eff_count: float = 1 + (count - 1) * (1 - spread / pa.spread_div) * pa.count_mul
	var damage: float = a.damage
	var force: float = a.knockback.force
	var startup: float = a.startup
	if "charge" in a:
		damage *= a.charge.damage
		force *= a.charge.force
		startup += a.charge.max
	var dmg := damage * hits * eff_count
	var kb: float = 1 + force / pa.force_div
	var pf: Dictionary = pa.frame
	var frame := sqrt(pf.startup_num / (startup + pf.startup_add) * pf.recovery_num / (a.recovery + pf.recovery_add))
	var rng: float
	if t == "swing":
		var w: Dictionary = d.assets[a.weapon]
		rng = 1 + (w.length + a.reach[1]) / pa.swing_range_div
	else:
		var proj: Dictionary = d.assets[a.projectile]
		var span: float = proj.size[0] if a.get("attach", false) else a.speed * a.lifetime
		rng = 1 + min(span, pa.shoot_range_cap) / pa.shoot_range_div
	var pfe: Dictionary = pa.feature
	var feat := 1.0
	if t == "shoot":
		if a.aim == "steer":
			feat *= pfe.steer
		if a.aim == "input":
			feat *= pfe.input
		if a.get("pierce", 0) != 0:
			feat *= pfe.pierce
		if a.get("return", false):
			feat *= pfe["return"]
		if a.get("solid", false):
			feat *= pfe.solid
		if a.get("gravity", 0) > 0:
			feat *= pfe.gravity
	if t == "swing" and a.get("grab", false):
		feat *= pfe.grab
	var cd: float = 1.0 / (1 + a.get("cooldown", 0) / pa.cooldown_div)
	var costmul: float = pa.cost_mul if not a.get("cost", {}).is_empty() else 1.0
	return dmg * kb * frame * rng * feat * cd * costmul * pa.scale


static func status_points(st: Dictionary) -> float:
	var pe: Dictionary = P().extra
	match st.type:
		"burn":
			return st.damage * st.duration / st.interval * pe.burn
		"slow":
			return (1 - st.factor) * st.duration / pe.slow_div
		"stun":
			return st.duration / pe.stun_div
		"root":
			return st.duration / pe.root_div
	return st.duration / pe.silence_div


static func link_points(l: Dictionary, window: float, d: Dictionary, eff: Dictionary, depth: int) -> float:
	var pe: Dictionary = P().extra
	var trig: float = every_triggers(window, l.interval) if l.when == "every" else 1.0
	var pts := 0.0
	if "heal" in l:
		pts += l.heal * pe.heal_mul * trig
	if "warp" in l:
		pts += pe.warp
	if "goto" in l:
		pts += pe.goto
	if "spawn" in l and depth < 32:
		pts += action_points(d.actions[l.spawn], d, eff, depth + 1) * pe.spawn_mul * trig
	return pts


static func action_points(action: Dictionary, d: Dictionary, eff: Dictionary, depth := 0) -> float:
	var pe: Dictionary = P().extra
	var ps: Dictionary = P().stats
	var a := CharDef.all_upgrades(action)
	var t: String = a.type
	var pts := 0.0
	if t == "move":
		pts += (a.speed - ps.move_speed.base) * ps.move_speed.mul
	elif t == "jump":
		pts += (a.max_count - ps.jump_count.base) * ps.jump_count.mul
		pts += (a.velocity - ps.jump_velocity.base) * ps.jump_velocity.mul
	elif t == "fly":
		pts += a.duration / ps.fly.frames * (1 + a.rise_speed) * ps.fly.mul
	elif t in CharDef.ATTACK_TYPES:
		pts += attack_base_points(a, d)
	if "status" in a:
		pts += status_points(a.status)
	for pair in [["armor", "armor_div"], ["invuln", "invuln_div"], ["reflect", "reflect_div"]]:
		if pair[0] in a:
			pts += CharDef.span_len(a[pair[0]]) / pe[pair[1]]
	if "motion" in a:
		var s := 0.0
		for m in a.motion:
			s += Vector2(m.vel[0], m.vel[1]).length()
		pts += s / pe.motion_div
	var total := CharDef.action_frames(a, d, eff)
	if "gravity_scale" in a and a.gravity_scale < 1:
		pts += (1 - a.gravity_scale) * total / pe.gravity_scale_div
	if t == "pose" and "throw" in a:
		var th: Dictionary = a.throw
		pts += th.damage * (1 + th.knockback.force / pe.throw_force_div) * pe.throw_mul
	if t == "shoot" and CharDef.shoot_kind(a, d.assets) == "deployable":
		pts += pe.deployable.mul * a.lifetime / pe.deployable.lifetime_div
	for l in CharDef.action_links(a):
		pts += link_points(l, total, d, eff, depth)
	for l in CharDef.bullet_links(a):
		pts += link_points(l, a.lifetime, d, eff, depth)
	if t in CharDef.ATTACK_TYPES and "charge" in a:
		pts *= pe.charge_mul
	if not action.get("upgrades", []).is_empty():
		pts *= pe.upgrades_mul
	return pts


## 某形态下从 input / 角色级 goto 出发、沿 goto 可达的非大招动作（含 move 与 jump）。
static func reachable_actions(d: Dictionary, eff: Dictionary) -> Array:
	var acts: Dictionary = d.actions
	var todo := []
	for k in acts:
		if acts[k].type in ["move", "jump"]:
			todo.append(k)
	todo.append_array(eff.input.values())
	for l in d.get("links", []):
		if "goto" in l:
			todo.append(l.goto)
	var seen := {}
	while not todo.is_empty():
		var aid = todo.pop_back()
		if aid in seen or not (aid in acts) or acts[aid].get("ultimate", false):
			continue
		seen[aid] = true
		var a: Dictionary = acts[aid]
		for m in range(1 << CharDef.upgrade_count(a)):
			for l in CharDef.apply_upgrades(a, m).get("links", []):
				if "goto" in l:
					todo.append(l.goto)
	var out := seen.keys()
	out.sort()
	return out


static func form_points(d: Dictionary, eff: Dictionary, n_input_forms: int) -> Dictionary:
	var ps: Dictionary = P().stats
	var hp: float = (eff.stats.hp - ps.hp.base) * ps.hp.mul
	var acts := {}
	var sum := 0.0
	for aid in reachable_actions(d, eff):
		acts[aid] = action_points(d.actions[aid], d, eff)
		sum += acts[aid]
	var links := 0.0
	for l in d.get("links", []):
		links += link_points(l, P().extra.every.char_window, d, eff, 0)
	var extra: float = P().form_input * n_input_forms
	return {"total": hp + sum + links + extra, "hp": hp, "actions": acts, "links": links, "forms_input": extra}
