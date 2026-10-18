class_name Fighter
extends RefCounted
## 单个角色的模拟状态：物理、动作处理、资源、状态效果、联动。
## 只依赖规则与角色包数据，不涉及渲染。

const HELD_ANGLE := 45.0   # 常态手持武器的显示角度（朝向空间）

var sim                    # MatchSim
var idx := 0
var ch: CharRuntime
var R: Dictionary

# 物理
var pos := Vector2.ZERO    # 脚底锚点（世界坐标）
var vel := Vector2.ZERO
var facing := 1
var on_ground := false
var ground_el := -1        # 脚下的场景元素（-1 = 无 / solid 布置物）
var ground_oneway := false
var wall_el := -1          # 贴着的可攀爬墙
var wall_dir := 0          # 墙在哪一侧：1 右，-1 左
var cling_t := 0
var cling_used := {}       # 本次落地前已经爬过的墙
var fast_fall := false
var jump_t := 99           # 起跳后的帧数（小跳判定）
var jump_cut := true
var dodge := {}            # {kind, t, dir}
var dodge_cd := 0
var air_dodged := false
var hazard_cd := {}        # 场景危险物 -> 上次受伤帧
var prev_stick := Vector2.ZERO
var drop_timer := 0
var down_hold := 0
var spawn_pos := Vector2.ZERO

# 战斗
var hp := 100.0
var lives := 2
var shield := 100.0
var ult := 0.0
var res := {}
var heal_used := 0.0
var state := "normal"      # normal action guard dodge cling hitstun shieldbreak grabbed ko dead out
var state_t := 0
var hitlag := 0
var invuln := 0
var combo_n := 0
var statuses := {}         # 类型 -> {t, p, tick, src}
var immune := {}           # 类型 -> 剩余帧
var grab_immune := 0
var cooldowns := {}        # 动作 -> 可再次使用的帧
var jumps_used := 0
var jump_double := false
var fly_used := false
var act := {}
var goto_pending := ""
var grabbing = null        # Fighter
var grabbed_by = null      # Fighter
var grab_t := 0
var char_t := 0
var flash := 0
var spawned_this_frame := 0
var act_counter := 0
var link_depth := 0

# 动画
var anim_name := ""
var anim_t := 0
var anim_idx := 0
var override_anim := ""
var override_t := 0

# 形态
var mask := 0
var eff := {}
var cond_sig := 0

# 输入
var input := InputFrame.new()
var prev_buttons := 0
var press_frame := {}


func setup(p_sim, p_idx: int, p_ch: CharRuntime, p_spawn: Vector2) -> void:
	sim = p_sim
	idx = p_idx
	ch = p_ch
	R = Rules.data()
	spawn_pos = p_spawn
	lives = int(R.combat.lives)
	ult = 0.0
	for rn in ch.data.get("resources", {}):
		res[rn] = float(ch.data.resources[rn].init)
	respawn(true)


func respawn(first := false) -> void:
	for rn in ch.data.get("resources", {}):
		var r: Dictionary = ch.data.resources[rn]
		if first or not r.get("keep_on_ko", false):
			res[rn] = float(r.init)
	update_forms()
	cond_sig = ch.condition_signature(_values())
	hp = float(stats().hp)
	shield = float(R.combat.shield.max)
	heal_used = 0.0
	statuses.clear()
	immune.clear()
	grab_immune = 0
	combo_n = 0
	act = {}
	goto_pending = ""
	grabbing = null
	grabbed_by = null
	state = "normal"
	pos = spawn_pos
	vel = Vector2.ZERO
	facing = 1 if spawn_pos.x < R.stage.width / 2.0 else -1
	on_ground = true
	jumps_used = 0
	fly_used = false
	fast_fall = false
	dodge = {}
	cling_used.clear()
	air_dodged = false
	ground_el = -1
	wall_el = -1
	char_t = 0
	invuln = 0 if first else int(R.combat.respawn_invuln)
	set_override("entrance")


# ---------------------------------------------------------------- 查询

func stats() -> Dictionary:
	return eff.stats


func body_size() -> Vector2:
	return Vector2(stats().body[0], stats().body[1])


func body_rect() -> Rect2:
	var b := body_size()
	return Rect2(pos.x - b.x / 2.0, pos.y - b.y, b.x, b.y)


func body_shape() -> Dictionary:
	return Geom.aabb(body_rect())


func center() -> Vector2:
	return pos - Vector2(0, body_size().y / 2.0)


func alive() -> bool:
	return not (state in ["ko", "dead", "out"])


func targetable() -> bool:
	return alive() and state != "out"


func _values() -> Dictionary:
	var v := res.duplicate()
	v["ult"] = ult
	return v


func has_status(t: String) -> bool:
	return t in statuses


func slow_factor() -> float:
	return statuses.slow.p.factor if has_status("slow") else 1.0


func can_act() -> bool:
	return not has_status("stun")


func in_window(key: String) -> bool:
	if act.is_empty() or not (key in act.def):
		return false
	var r: Array = act.def[key]
	return act.cur >= r[0] and act.cur <= r[1]


func is_invulnerable() -> bool:
	if invuln > 0 or not alive() or dodge_invuln():
		return true
	if in_window("invuln"):
		return true
	if not act.is_empty() and act.def.get("ultimate", false) and act.def.type in CharDef.ATTACK_TYPES:
		return act.cur < act.def.startup + act.def.active
	return false


func armored() -> bool:
	return in_window("armor") and act.def.type in CharDef.ATTACK_TYPES and act.cur < act.def.startup + act.def.active


func reflecting() -> bool:
	return in_window("reflect")


func act_phase() -> String:
	if act.is_empty() or not (act.def.type in CharDef.ATTACK_TYPES):
		return ""
	if act.charging:
		return "startup"
	var a: Dictionary = act.def
	if act.cur < a.startup:
		return "startup"
	if act.cur < a.startup + a.active:
		return "active"
	return "recovery"


func current_anim():
	return ch.anim(eff, anim_name) if anim_name != "" else null


func _anim_by_resolved(n: String):
	return ch.data.anims.get(n)


func hand_world_at(anim, i: int):
	if anim == null or not ("hand" in anim) or i >= anim.hand.size():
		return null
	var h: Array = anim.hand[i]
	return pos + Vector2((h[0] - ch.anchor.x) * facing, h[1] - ch.anchor.y)


func current_hand() -> Vector2:
	var hw = hand_world_at(_anim_by_resolved(anim_name), anim_idx)
	return hw if hw != null else center()


func facing_dir(deg: float, f := 0) -> Vector2:
	var fc := facing if f == 0 else f
	var r := deg_to_rad(deg)
	return Vector2(cos(r) * fc, -sin(r))


# ---------------------------------------------------------------- 输入

func begin_frame(inp: InputFrame) -> void:
	prev_buttons = input.buttons
	prev_stick = input.stick()
	input = inp
	for b in InputFrame.BUTTONS.values():
		if input.held(b) and not (prev_buttons & b):
			press_frame[b] = sim.frame
			if not act.is_empty():
				# 联动的 input 条件可写 "attack" 或带方向的 "attack.up"
				act.press[_btn_name(b)] = act.frame
				act.press[_btn_name(b) + "." + InputFrame.direction(input.stick())] = act.frame


func pressed(b: int) -> bool:
	return sim.frame - int(press_frame.get(b, -1000)) <= int(R.physics.input_buffer)


func consume(b: int) -> void:
	press_frame[b] = -1000


static func _btn_name(b: int) -> String:
	for k in InputFrame.BUTTONS:
		if InputFrame.BUTTONS[k] == b:
			return k
	return ""


# ---------------------------------------------------------------- 主循环

func tick() -> void:
	spawned_this_frame = 0
	link_depth = 0
	if flash > 0:
		flash -= 1
	match state:
		"out":
			return
		"dead":
			state_t -= 1
			if state_t <= 0:
				respawn()
				sim.emit({"t": "respawn", "i": idx})
			return
		"ko":
			_advance_anim("ko")
			state_t -= 1
			if state_t <= 0:
				sim.emit({"t": "explode", "i": idx, "x": pos.x, "y": pos.y, "anim": anim_name, "ai": anim_idx, "f": facing})
				lose_life()
			return
	_timers()
	update_forms()
	if not alive():
		return
	match state:
		"hitstun", "shieldbreak":
			state_t -= 1
			_physics(true)
			if state_t <= 0:
				state = "normal"
				combo_n = 0
		"grabbed":
			grab_t += 1
			if grabbed_by == null or grabbed_by.grabbing != self:
				release_grabbed(false)
		"guard":
			if not input.held(InputFrame.GUARD) or not can_act() or not on_ground:
				state = "normal"
			else:
				_guard_options()
			if state == "guard":
				_move_control(Vector2.ZERO)
			_physics(false)
		"dodge":
			_update_dodge()
			_physics(false)
		"cling":
			_update_cling()
			_physics(false)
		"action":
			_update_action()
			_physics(false)
		"normal":
			_update_normal()
			_physics(false)
	if grabbing != null:
		_hold_grabbed()
	_update_anim()


func _timers() -> void:
	char_t += 1
	if invuln > 0:
		invuln -= 1
	if grab_immune > 0:
		grab_immune -= 1
	if override_t > 0:
		override_t -= 1
	if dodge_cd > 0:
		dodge_cd -= 1
	for t in immune.keys():
		immune[t] -= 1
		if immune[t] <= 0:
			immune.erase(t)
	for t in statuses.keys():
		var s: Dictionary = statuses[t]
		s.t -= 1
		if t == "burn":
			s.tick += 1
			if s.tick % int(s.p.interval) == 0:
				sim.apply_damage(sim.fighters[s.src] if s.src >= 0 else null, self, s.p.damage)
				if not alive():
					return
		if s.t <= 0:
			statuses.erase(t)
			var imm: Dictionary = R.runtime.immunity
			if t in imm:
				immune[t] = int(imm[t])
	if state != "guard":
		shield = min(float(R.combat.shield.max), shield + R.combat.shield.regen)
	for rn in res:
		var rg: float = ch.data.resources[rn].get("regen", 0)
		if rg != 0:
			change_res(rn, res[rn] + rg, false)
	var cl: Array = ch.data.get("links", [])
	for l in cl:
		if l.when == "every" and char_t % int(l.interval) == 0:
			_fire(l, {})


func update_forms() -> void:
	var m := ch.form_mask(_values())
	if eff.is_empty() or m != mask:
		mask = m
		eff = ch.form(m)


func set_override(logical: String) -> void:
	var a = ch.anim(eff, logical)
	if a == null:
		return
	var total := 0
	for d in a.get("durations", []):
		total += int(d)
	override_anim = logical
	override_t = total


# ---------------------------------------------------------------- 普通状态

func _update_normal() -> void:
	var st := input.stick()
	if goto_pending != "":
		var g := goto_pending
		goto_pending = ""
		if _start_action(g, 0, true):
			_update_action()
		return
	if not can_act():
		_move_control(Vector2.ZERO)
		return
	if input.held(InputFrame.GUARD):
		if on_ground:
			state = "guard"
			override_t = 0
			return
		if pressed(InputFrame.GUARD) and not air_dodged and dodge_cd == 0:
			consume(InputFrame.GUARD)
			_start_dodge("air", st)
			return
	if pressed(InputFrame.ULT) and ch.ult_id != "" and ult >= float(R.combat.ult.max):
		if _try_start(ch.ult_id, InputFrame.ULT):
			consume(InputFrame.ULT)
			return
	for pair in [["attack", InputFrame.ATTACK], ["special", InputFrame.SPECIAL]]:
		if pressed(pair[1]):
			var key := "%s.%s" % [pair[0], InputFrame.direction(st)]
			# 跑动中按攻击 = 冲刺攻击（没写 attack.dash 时沿用 attack.side）
			if pair[0] == "attack" and running() and "attack.dash" in eff.input:
				key = "attack.dash"
			var aid := input_action(key)
			if aid != "" and _try_start(aid, pair[1]):
				consume(pair[1])
				return
	# 空中按向墙壁贴上可攀爬的墙
	if not on_ground and wall_el >= 0 and not (wall_el in cling_used) and sign(st.x) == wall_dir and abs(st.x) >= 0.5 and vel.y > -2.0:
		state = "cling"
		cling_t = 0
		vel = Vector2.ZERO
		facing = wall_dir
		fast_fall = false
		return
	if pressed(InputFrame.JUMP):
		var jid: String = eff.input.get("jump", "")
		if jid == ch.jump_id and jid != "":
			if _do_jump():
				consume(InputFrame.JUMP)
		elif jid != "" and _try_start(jid, InputFrame.JUMP):
			consume(InputFrame.JUMP)
			return
	_move_control(st)
	if on_ground and abs(st.x) >= 0.5 and not has_status("root"):
		facing = 1 if st.x > 0 else -1
	# 按住下键穿过单向平台
	if on_ground and st.y > 0.7 and input.buttons == 0:
		down_hold += 1
		if down_hold >= int(R.physics.drop_through_hold) and sim.standing_on_oneway(self):
			drop_timer = int(R.physics.drop_through_frames)
			on_ground = false
			down_hold = 0
	else:
		down_hold = 0


func input_action(key: String) -> String:
	if not on_ground and (key + ".air") in eff.input:
		return eff.input[key + ".air"]
	return eff.input.get(key, "")


func running() -> bool:
	var mv: Dictionary = ch.data.actions[ch.move_id]
	return on_ground and abs(vel.x) > mv.speed * slow_factor() * 1.05


func _move_control(st: Vector2) -> void:
	var mv: Dictionary = ch.data.actions[ch.move_id]
	var speed: float = mv.speed * slow_factor()
	var target := 0.0
	if abs(st.x) > 0.2 and not has_status("root"):
		target = sign(st.x) * speed * min(1.0, abs(st.x) / 0.8)
		# 摇杆推到底在地面上跑动
		if on_ground and abs(st.x) >= R.physics.run_threshold:
			target = sign(st.x) * speed * R.physics.run_mul
	if on_ground:
		var rate: float = mv.accel if target != 0.0 else max(mv.accel, R.physics.ground_friction)
		rate *= sim.ground_friction_mul(self)
		vel.x = move_toward(vel.x, target, rate)
	else:
		if target != 0.0:
			vel.x = move_toward(vel.x, target, mv.accel * stats().air_control)
		else:
			vel.x = move_toward(vel.x, 0.0, R.physics.air_friction)


func _do_jump() -> bool:
	if has_status("root"):
		return false
	var j: Dictionary = ch.action(ch.jump_id, _values())
	if on_ground:
		jumps_used = 1
		jump_double = false
	elif jumps_used < int(j.max_count):
		jumps_used = max(jumps_used, 1) + 1
		jump_double = true
	else:
		return false
	vel.y = -j.velocity * slow_factor()
	on_ground = false
	fast_fall = false
	jump_t = 0
	jump_cut = false
	override_t = 0
	anim_name = ""
	sim.emit({"t": "jump", "i": idx})
	return true


# ---------------------------------------------------------------- 动作

func _try_start(aid: String, btn: int) -> bool:
	if not ch.has_action(aid):
		return false
	var a := ch.action(aid, _values())
	var req: String = a.get("require", "any")
	if req == "ground" and not on_ground:
		return false
	if req == "air" and on_ground:
		return false
	if btn == InputFrame.SPECIAL and has_status("silence"):
		return false
	if a.type in ["move", "jump", "fly"] and has_status("root"):
		return false
	if a.type == "fly" and fly_used:
		return false
	if a.type == "jump":
		return _do_jump()
	return _start_action(aid, btn, false)


func _affordable(a: Dictionary, aid: String) -> bool:
	if int(cooldowns.get(aid, 0)) > sim.frame:
		return false
	var cost: Dictionary = a.get("cost", {})
	for k in cost:
		if res.get(k, 0.0) < cost[k]:
			return false
	return true


func _start_action(aid: String, btn: int, from_goto: bool) -> bool:
	var a := ch.action(aid, _values())
	if a.type == "move":
		return false
	if not _affordable(a, aid):
		return false
	var cost: Dictionary = a.get("cost", {})
	for k in cost:
		change_res(k, res[k] - cost[k], true)
	cooldowns[aid] = sim.frame + int(a.get("cooldown", 0))
	var st := input.stick()
	if InputFrame.direction(st) == "side" and not from_goto:
		facing = 1 if st.x > 0 else -1
	act_counter += 1
	act = {
		"id": aid, "def": a, "frame": 0, "cur": 0, "t": 0, "inst": idx * 100000 + act_counter,
		"btn": btn, "hits": {}, "hit_any": false, "pending": {}, "fired": {}, "press": {},
		"charging": false, "charge_t": 0, "charge_done": false, "ratio": 0.0,
		"holding": false, "released": btn == 0 or not input.held(btn), "motion_active": false,
		"shot": false, "links": CharDef.action_links(a), "total": CharDef.action_frames(a, ch.data, eff),
		"has_release": _has_when(CharDef.action_links(a), "on_release"),
	}
	if a.type == "fly":
		fly_used = true
	state = "action"
	override_t = 0
	if "sfx" in a and "start" in a.sfx:
		sim.emit({"t": "sfx", "name": a.sfx.start, "i": idx})
	if a.get("ultimate", false):
		sim.emit({"t": "ult_start", "i": idx})
	_act_trigger("on_start")
	return true


## 动作附带的纯视觉特效（无判定）。
func _play_effects(a: Dictionary, f: int) -> void:
	for ef in a.get("effects", []):
		if int(ef.frame) != f:
			continue
		var off: Array = ef.get("offset", [0, 0])
		var at := pos + Vector2(off[0] * facing, -off[1])
		sim.emit({"t": "vfx", "i": idx, "fx": ef.fx, "x": at.x, "y": at.y, "ox": off[0], "oy": off[1], "f": facing,
			"follow": ef.get("follow", false), "behind": ef.get("behind", false)})


static func _has_when(links: Array, w: String) -> bool:
	for l in links:
		if l.when == w:
			return true
	return false


func _update_action() -> void:
	if act.is_empty():
		state = "normal"
		return
	if goto_pending != "":
		var g := goto_pending
		goto_pending = ""
		_switch_to(g)
		return
	var a: Dictionary = act.def
	if not act.released and not input.held(act.btn):
		act.released = true
		_act_trigger("on_release")
		if act.is_empty() or state != "action":
			return
	if a.type == "fly":
		_fly_tick(a)
		return
	act.cur = act.frame
	if act.charging:
		act.charge_t += 1
		if act.released or act.charge_t >= int(a.charge.max):
			act.charging = false
			act.charge_done = true
			act.ratio = float(act.charge_t) / float(a.charge.max)
		_every_tick()
		_input_links()
		act.t += 1
		if act.charging:
			_air_drift()
			return
	if act.holding:
		_every_tick()
		act.t += 1
		if act.released:
			_end_action(true)
		return
	var f: int = act.frame
	for m in a.get("motion", []):
		if int(m.frame) == f:
			var mv := Vector2(m.vel[0] * facing, -m.vel[1])
			if m.get("mode", "set") == "add":
				vel += mv
			else:
				vel = mv
			act.motion_active = true
	_act_trigger("on_frame")
	_play_effects(a, f)
	_every_tick()
	_input_links()
	if act.is_empty() or state != "action":
		return
	if a.type in CharDef.ATTACK_TYPES:
		if "charge" in a and f == int(a.startup) - 1 and not act.charge_done and not act.released:
			act.charging = true
		if a.type == "shoot" and f == int(a.startup) and not act.shot and a.get("area") != "screen":
			act.shot = true
			sim.fire_shoot(self, a, null, 0, act.inst, act.ratio)
		if f == int(a.startup + a.active) - 1 and not act.hit_any:
			_act_trigger("on_whiff")
			if act.is_empty() or state != "action":
				return
	if a.type == "pose" and "throw" in a and f == int(a.throw.frame) and grabbing != null:
		sim.do_throw(self, a.throw)
	if not act.motion_active:
		_air_drift()
	act.t += 1
	if act.charging:
		return
	act.frame += 1
	if act.frame >= act.total:
		if act.has_release and not act.released:
			act.holding = true
			act.frame = act.total - 1
			return
		_end_action(true)


func _air_drift() -> void:
	if on_ground:
		_move_control(Vector2.ZERO)
	else:
		_move_control(Vector2(input.stick().x, 0))


func _fly_tick(a: Dictionary) -> void:
	act.cur = act.frame
	var st := input.stick()
	var mv: Dictionary = ch.data.actions[ch.move_id]
	vel.x = st.x * mv.speed * a.control * slow_factor() if abs(st.x) > 0.2 else 0.0
	vel.y = -a.rise_speed if st.y < -0.5 else 0.0
	for pair in [["attack", InputFrame.ATTACK], ["special", InputFrame.SPECIAL]]:
		if pressed(pair[1]):
			var aid := input_action("%s.%s" % [pair[0], InputFrame.direction(st)])
			if aid != "" and aid != act.id:
				var na := ch.action(aid, _values())
				if na.type != "fly" and _affordable(na, aid):
					consume(pair[1])
					_end_action(false)
					_try_start(aid, pair[1])
					if state == "action":
						_update_action()
					return
	_play_effects(a, act.frame)
	_every_tick()
	act.t += 1
	act.frame += 1
	if act.frame >= act.total:
		_end_action(true)


func _switch_to(aid: String) -> void:
	var keep_grab := false
	if ch.has_action(aid):
		var na: Dictionary = ch.data.actions[aid]
		keep_grab = na.type == "pose" and "throw" in na
	var held_target = grabbing
	if not act.is_empty():
		_end_action(false, keep_grab)
	if keep_grab:
		grabbing = held_target
	if _start_action(aid, act.get("btn", 0) if not act.is_empty() else 0, true):
		_update_action()
	elif grabbing != null:
		release_grabbed_target(false)


func _end_action(natural: bool, keep_grab := false) -> void:
	if act.is_empty():
		return
	var a: Dictionary = act.def
	if natural:
		_act_trigger("on_end")
	if a.get("ultimate", false):
		ult = 0.0
	if grabbing != null and not keep_grab and goto_pending == "":
		release_grabbed_target(false)
	act = {}
	if state == "action":
		state = "normal"
	anim_name = ""


## 被打断（受击 / 被抓 / 击倒）：不触发 on_end，附着的子弹随之消失。
func interrupt() -> void:
	if act.is_empty():
		return
	sim.kill_attached(self, act.inst)
	if act.def.get("ultimate", false):
		ult = 0.0
	act = {}
	goto_pending = ""
	if grabbing != null:
		release_grabbed_target(false)
	anim_name = ""


func on_action_hit(inst: int) -> void:
	if act.is_empty() or act.inst != inst:
		return
	act.hit_any = true
	_act_trigger("on_hit")


func on_hurt() -> void:
	if not act.is_empty():
		_act_trigger("on_hurt")
	for l in ch.data.get("links", []):
		if l.when == "on_hurt":
			_fire(l, {})


func on_land() -> void:
	jumps_used = 0
	jump_double = false
	fly_used = false
	fast_fall = false
	air_dodged = false
	cling_used.clear()
	if not act.is_empty():
		_act_trigger("on_land")
	for l in ch.data.get("links", []):
		if l.when == "on_land":
			_fire(l, {})
	if state == "normal":
		set_override("land")


# ---------------------------------------------------------------- 联动

func _act_trigger(when: String) -> void:
	if act.is_empty():
		return
	var links: Array = act.links
	var inst: int = act.inst
	for i in links.size():
		if act.is_empty() or act.inst != inst:
			return
		var l: Dictionary = links[i]
		if l.when != when:
			continue
		if when == "on_frame" and int(l.frame) != act.cur:
			continue
		if "input" in l:
			if not (i in act.fired):
				act.pending[i] = true
			continue
		if "window" in l and (act.cur < l.window[0] or act.cur > l.window[1]):
			continue
		_fire(l, {})


func _every_tick() -> void:
	if act.is_empty() or act.t <= 0:
		return
	for l in act.links:
		if l.when == "every" and act.t % int(l.interval) == 0:
			_fire(l, {})
			if act.is_empty():
				return


func _input_links() -> void:
	if act.is_empty() or act.pending.is_empty():
		return
	var inst: int = act.inst
	for i in act.pending.keys():
		if act.is_empty() or act.inst != inst:
			return
		var l: Dictionary = act.links[i]
		var w: Array = l.get("window", [0, 100000])
		if act.cur > w[1]:
			act.pending.erase(i)
			continue
		var pf: int = act.press.get(l.input, -1)
		if act.cur >= w[0] and pf >= w[0] and pf <= act.cur:
			act.pending.erase(i)
			act.fired[i] = true
			_fire(l, {})


func _conds_ok(l: Dictionary) -> bool:
	if "if" in l and not CharDef.cond_true(l["if"], _values()):
		return false
	var req: String = l.get("require", "any")
	if req == "ground" and not on_ground:
		return false
	if req == "air" and on_ground:
		return false
	return true


## 执行联动效果。ctx: {"proj": Projectile} 表示子弹联动。
func _fire(l: Dictionary, ctx: Dictionary) -> void:
	if not _conds_ok(l) or not alive():
		return
	link_depth += 1
	if link_depth > int(R.runtime.max_link_depth):
		link_depth -= 1
		return
	var proj = ctx.get("proj")
	var at: Vector2 = proj.pos if proj != null else current_hand()
	for k in l.get("gain", {}):
		change_res(k, res[k] + l.gain[k], true)
	for k in l.get("spend", {}):
		change_res(k, res[k] - l.spend[k], true)
	for k in l.get("set", {}):
		change_res(k, float(l.set[k]), true)
	if "heal" in l:
		heal(l.heal)
	if "warp" in l and proj != null:
		pos = proj.pos + Vector2(0, body_size().y / 2.0)
		vel = Vector2.ZERO
		sim.emit({"t": "warp", "i": idx, "x": pos.x, "y": pos.y})
	if "fx" in l:
		sim.emit({"t": "fx", "name": l.fx, "i": idx, "x": at.x, "y": at.y, "f": facing})
	if "sfx" in l:
		sim.emit({"t": "sfx", "name": l.sfx, "i": idx})
	if "spawn" in l and ch.has_action(l.spawn):
		sim.fire_shoot(self, ch.action(l.spawn, _values()), proj, link_depth, -1, 0.0)
	if "goto" in l and ch.has_action(l.goto) and alive() and not (state in ["hitstun", "shieldbreak", "grabbed"]):
		goto_pending = l.goto
	link_depth -= 1


func fire_bullet_link(l: Dictionary, p: Projectile) -> void:
	_fire(l, {"proj": p})


func change_res(name: String, value: float, events: bool) -> void:
	if not (name in res):
		return
	var r: Dictionary = ch.data.resources[name]
	var mx: float = r.max
	var old: float = res[name]
	var v := value
	if r.get("wrap", false):
		if v > mx:
			v = 0.0
		elif v < 0.0:
			v = mx
	else:
		v = clamp(v, 0.0, mx)
	res[name] = v
	if events and v > old:
		sim.emit({"t": "res_gain", "i": idx, "res": name, "n": v - old})
	update_forms()
	var sig := ch.condition_signature(_values())
	if sig != cond_sig:
		if state == "normal" and sig > cond_sig:
			set_override("levelup")
		cond_sig = sig
	for l in ch.data.get("links", []):
		if l.get("resource") != name:
			continue
		if l.when == "resource_empty" and v <= 0.0 and old > 0.0:
			_fire(l, {})
		elif l.when == "resource_full" and v >= mx and old < mx:
			_fire(l, {})


func heal(n: float) -> void:
	var cap: float = R.runtime.max_heal_per_life
	var amount: float = min(n, cap - heal_used, float(stats().hp) - hp)
	if amount <= 0:
		return
	heal_used += amount
	hp += amount
	sim.emit({"t": "heal", "i": idx, "n": amount})


# ---------------------------------------------------------------- 状态效果

func apply_status(st: Dictionary, src: int) -> void:
	var t: String = st.type
	if t in immune:
		return
	if t in statuses:
		statuses[t].t = int(st.duration)
		statuses[t].p = st
		statuses[t].src = src
		return
	statuses[t] = {"t": int(st.duration), "p": st, "tick": 0, "src": src}
	if t == "stun" and state == "guard":
		state = "normal"


# ---------------------------------------------------------------- 抓取

func _hold_grabbed() -> void:
	var g: Fighter = grabbing
	if g.state != "grabbed" or g.grabbed_by != self:
		grabbing = null
		return
	if g.grab_t > int(R.limits.grab.max_hold) or state != "action":
		release_grabbed_target(false)
		return
	g.pos = current_hand() + Vector2(0, g.body_size().y / 2.0)
	g.vel = Vector2.ZERO
	g.facing = -facing


func release_grabbed_target(thrown: bool) -> void:
	if grabbing == null:
		return
	var g: Fighter = grabbing
	grabbing = null
	g.release_grabbed(thrown)


func release_grabbed(_thrown: bool) -> void:
	if state == "grabbed":
		state = "normal"
	grabbed_by = null
	grab_immune = int(R.runtime.immunity.grab)


func become_grabbed(holder: Fighter) -> void:
	interrupt()
	state = "grabbed"
	grabbed_by = holder
	grab_t = 0
	vel = Vector2.ZERO


# ---------------------------------------------------------------- 击倒

func start_ko() -> void:
	interrupt()
	if grabbed_by != null:
		grabbed_by.grabbing = null
		grabbed_by = null
	state = "ko"
	vel = Vector2.ZERO
	anim_name = ""
	var a = ch.anim(eff, "ko")
	var total := 0
	for d in a.durations:
		total += int(d)
	state_t = total + 6
	sim.emit({"t": "ko", "i": idx, "x": pos.x, "y": pos.y})


func lose_life() -> void:
	sim.remove_owned(self)
	lives -= 1
	if lives <= 0:
		state = "out"
	else:
		state = "dead"
		state_t = int(R.combat.respawn_delay)


func blast() -> void:
	interrupt()
	if grabbing != null:
		release_grabbed_target(false)
	if grabbed_by != null:
		grabbed_by.grabbing = null
		grabbed_by = null
	sim.emit({"t": "blast", "i": idx, "x": clamp(pos.x, 0, R.stage.width), "y": clamp(pos.y, 0, R.stage.height)})
	lose_life()


# ---------------------------------------------------------------- 物理

func _physics(stunned: bool) -> void:
	var z: Dictionary = sim.zone_at(self)
	var g: float = stats().gravity * z.gravity_mul
	if not act.is_empty():
		g *= act.def.get("gravity_scale", 1.0)
		if act.def.type == "fly":
			g = 0.0
	if state == "cling":
		g = 0.0
	vel.y += g
	vel += z.wind
	# 小跳：起跳后很快松开跳跃键，上升速度减小
	if jump_t < 99:
		jump_t += 1
		var sh: Dictionary = R.physics.short_hop
		if not jump_cut and vel.y < 0 and not input.held(InputFrame.JUMP):
			if jump_t <= int(sh.window):
				vel.y *= sh.mul
			jump_cut = true
	# 快速下落：空中下落时把摇杆往下推
	var st := input.stick()
	if not stunned and not on_ground and state in ["normal", "action"] and vel.y >= 0 and st.y >= 0.7 and prev_stick.y < 0.7:
		fast_fall = true
	var cap: float = stats().max_fall * (R.physics.fast_fall_mul if fast_fall else 1.0)
	if fast_fall and not stunned and vel.y >= 0:
		vel.y = cap
	if stunned:
		fast_fall = false
		vel *= R.physics.hitstun_drag
	elif vel.y > cap and state != "cling":
		vel.y = cap
	if z.drag < 1.0:
		vel *= z.drag
	if drop_timer > 0:
		drop_timer -= 1
	var was_ground := on_ground
	sim.move_fighter(self)
	if on_ground and not was_ground:
		on_land()
	elif was_ground and not on_ground and jumps_used == 0:
		jumps_used = 1
	if sim.out_of_bounds(self):
		blast()


# ---------------------------------------------------------------- 防御、闪避、攀墙

func _guard_options() -> void:
	var st := input.stick()
	if pressed(InputFrame.ATTACK) and "grab" in eff.input:
		consume(InputFrame.ATTACK)
		state = "normal"
		if not _try_start(eff.input.grab, InputFrame.ATTACK):
			state = "guard"
		return
	if dodge_cd > 0:
		return
	if abs(st.x) >= 0.7 and abs(prev_stick.x) < 0.7:
		_start_dodge("roll", Vector2(sign(st.x), 0))
	elif st.y >= 0.7 and prev_stick.y < 0.7:
		_start_dodge("spot", Vector2.ZERO)


func _start_dodge(kind: String, dir: Vector2) -> void:
	var cfg: Dictionary = R.dodge[kind]
	dodge = {"kind": kind, "t": 0, "dir": dir.normalized() if dir.length() >= 0.5 else Vector2.ZERO}
	state = "dodge"
	override_t = 0
	dodge_cd = int(cfg.frames) + int(R.dodge.cooldown)
	shield = max(0.0, shield - R.dodge.shield_cost)
	fast_fall = false
	if kind == "air":
		air_dodged = true
		vel = dodge.dir * float(cfg.speed)
	sim.emit({"t": "dodge", "i": idx})


func _update_dodge() -> void:
	var cfg: Dictionary = R.dodge[dodge.kind]
	dodge.t += 1
	match dodge.kind:
		"roll":
			vel.x = dodge.dir.x * float(cfg.speed) * (1.0 - float(dodge.t) / float(cfg.frames))
		"spot":
			vel.x = 0.0
		"air":
			vel *= 0.9
	if dodge.t >= int(cfg.frames):
		state = "normal"
		dodge = {}


func dodge_invuln() -> bool:
	if state != "dodge" or dodge.is_empty():
		return false
	var w: Array = R.dodge[dodge.kind].invuln
	return dodge.t >= w[0] and dodge.t <= w[1]


func _update_cling() -> void:
	if wall_el < 0 or on_ground:
		state = "normal"
		return
	var wcfg: Dictionary = R.physics.wall
	var el: Dictionary = sim.stage.els[wall_el].def
	var st := input.stick()
	cling_t += 1
	if pressed(InputFrame.JUMP):
		consume(InputFrame.JUMP)
		var j: Dictionary = ch.action(ch.jump_id, _values())
		var mv: Dictionary = ch.data.actions[ch.move_id]
		cling_used[wall_el] = true
		vel = Vector2(-wall_dir * mv.speed * wcfg.jump_out, -j.velocity * wcfg.jump_up * slow_factor())
		facing = -wall_dir
		jumps_used = 1
		jump_t = 0
		jump_cut = false
		state = "normal"
		sim.emit({"t": "jump", "i": idx})
		return
	var leave: bool = cling_t > int(el.climb.max) or pressed(InputFrame.GUARD) or (sign(st.x) == -wall_dir and abs(st.x) >= 0.5)
	if leave or pressed(InputFrame.ATTACK) or pressed(InputFrame.SPECIAL):
		cling_used[wall_el] = true
		state = "normal"
		if not leave:
			_update_normal()
		return
	vel.x = wall_dir * 0.5
	if st.y < -0.5:
		vel.y = -1.0
	elif st.y > 0.5:
		vel.y = 2.5
	else:
		vel.y = wcfg.slide_speed


# ---------------------------------------------------------------- 动画

func _update_anim() -> void:
	match state:
		"action":
			var a: Dictionary = act.def
			if act.charging or act.holding:
				_advance_anim("charge")
			elif a.type in CharDef.ATTACK_TYPES:
				_set_anim(a.anim)
				var ph := act_phase()
				anim_idx = 0 if ph == "startup" else (1 if ph == "active" else 2)
			elif a.type == "fly":
				_advance_anim("fly")
			else:
				_set_anim(a.anim)
				anim_t = act.frame
				anim_idx = _anim_index(current_anim(), anim_t)
		"guard":
			_advance_anim("guard")
		"dodge":
			_advance_anim(_fallback("dodge", "guard"))
		"cling":
			_advance_anim(_fallback("cling", "fall"))
		"hitstun", "shieldbreak", "grabbed":
			_advance_anim("hurt")
		"normal":
			if not can_act():
				_advance_anim("hurt")
			elif override_t > 0 and (override_anim != "land" or (on_ground and abs(input.stick().x) < 0.2)):
				_advance_anim(override_anim)
			elif on_ground:
				if running():
					_advance_anim(_fallback("run", "walk"))
				else:
					_advance_anim("walk" if abs(vel.x) > 0.3 else "idle")
			elif vel.y < 0:
				var j: Dictionary = ch.data.actions[ch.jump_id]
				_advance_anim(j.get("extra_anim", "double_jump") if jump_double else "jump")
			else:
				_advance_anim("fall")


## 可选动画不存在时用替代动画。
func _fallback(logical: String, alt: String) -> String:
	return logical if ch.anim(eff, logical) != null else alt


func _set_anim(logical: String) -> void:
	var n := CharDef.resolve_anim_name(eff, logical)
	if n != anim_name:
		anim_name = n
		anim_t = 0
		anim_idx = 0


func _advance_anim(logical: String) -> void:
	var n := CharDef.resolve_anim_name(eff, logical)
	if n != anim_name:
		anim_name = n
		anim_t = 0
	else:
		anim_t += 1
	anim_idx = _anim_index(_anim_by_resolved(n), anim_t)


static func _anim_index(a, t: int) -> int:
	if a == null:
		return 0
	var ds: Array = a.get("durations", [])
	if ds.is_empty():
		return 0
	var total := 0
	for d in ds:
		total += int(d)
	var tt := t
	if a.get("loop", false) and not ("hold" in a) and total > 0:
		tt = t % total
	var acc := 0
	var i := ds.size() - 1
	for k in ds.size():
		acc += int(ds[k])
		if tt < acc:
			i = k
			break
	if "hold" in a:
		i = min(i, int(a.hold))
	return i


# ---------------------------------------------------------------- 判定与显示

## 本帧挥击判定（胶囊体）；不在生效期返回空。
func swing_shape() -> Dictionary:
	if act.is_empty() or act.def.type != "swing" or act_phase() != "active":
		return {}
	var a: Dictionary = act.def
	var w: Dictionary = ch.asset(a.weapon)
	var t := 0.0 if a.active <= 1 else float(act.cur - a.startup) / float(a.active - 1)
	var ang: float = lerp(float(a.from), float(a.to), t)
	var reach: float = lerp(float(a.reach[0]), float(a.reach[1]), t)
	var d := facing_dir(ang)
	var hw = hand_world_at(ch.anim(eff, a.anim), 1)
	var grip: Vector2 = hw if hw != null else center()
	var p0: Vector2 = grip + d * (reach + w.length * w.hit_range[0])
	var p1: Vector2 = grip + d * (reach + w.length * w.hit_range[1])
	return Geom.capsule(p0, p1, w.radius)


## 武器显示：{asset, angle(朝向空间度), reach}；无则空。
func weapon_visual() -> Dictionary:
	if state == "action":
		var a: Dictionary = act.def
		if a.type == "swing":
			var ph := act_phase()
			var t := 0.0
			if ph == "active":
				t = 0.0 if a.active <= 1 else float(act.cur - a.startup) / float(a.active - 1)
			elif ph == "recovery":
				t = 1.0
			return {"asset": a.weapon, "angle": lerp(float(a.from), float(a.to), t), "reach": lerp(float(a.reach[0]), float(a.reach[1]), t)}
		if a.type == "shoot" and "weapon" in a:
			return {"asset": a.weapon, "angle": float(a.angle), "reach": 0.0}
		if a.type in CharDef.ATTACK_TYPES:
			return {}
	if eff.held == null or not alive():
		return {}
	var an = _anim_by_resolved(anim_name)
	if an == null or not ("hand" in an):
		return {}
	return {"asset": eff.held, "angle": HELD_ANGLE, "reach": 0.0}


## direct = 由动作本身发射（取攻击姿势生效帧的 hand），否则取当前帧 hand。
func shoot_origin(a: Dictionary, ang: float, direct: bool) -> Vector2:
	var base := current_hand()
	if direct:
		var hw = hand_world_at(ch.anim(eff, a.anim), 1)
		base = hw if hw != null else center()
	if "weapon" in a:
		base += facing_dir(ang) * float(ch.asset(a.weapon).length)
	return base
