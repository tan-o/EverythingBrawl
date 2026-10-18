class_name CpuInput
extends RefCounted
## 练习 / 平衡测试用的电脑对手：按招式实际射程选招、转向后出招、看到对方出招时防御或翻滚、掉下去会回场。
## 只产生输入，不改模拟。level 0 = 木桩。

var rng := RandomNumberGenerator.new()
var level := 1
var hold := InputFrame.new()
var _moves := []          # [{key, reach, dmg, up, ranged}]
var _ground := Rect2()    # 主地面
var _plan := []           # 接下来几帧的输入
var _ready := false


func _init(p_level := 1, seed := 1) -> void:
	level = p_level
	rng.seed = seed


func _setup(sim: MatchSim, me: Fighter) -> void:
	_ready = true
	var best := 0.0
	for e in sim.stage.els:
		var el: Dictionary = e.def
		if StageDef.is_static(el) and StageDef.is_standable(el) and el.rect[2] > best:
			best = el.rect[2]
			_ground = StageDef.rect(el)
	var d: Dictionary = me.ch.data
	for key in d.input:
		if key == "jump" or key == "grab":
			continue
		var a: Dictionary = d.actions[d.input[key]]
		var reach := 0.0
		var dmg := 0.0
		var ranged := false
		match a.type:
			"swing":
				reach = float(d.assets[a.weapon].length) + float(a.reach[1]) + 10.0
				dmg = PackPoints.target_damage(a, d)
			"shoot":
				ranged = a.speed > 0
				reach = min(float(a.speed) * float(a.lifetime), 220.0) if ranged else 30.0
				dmg = PackPoints.target_damage(a, d)
			_:
				continue
		var parts: PackedStringArray = key.split(".")
		_moves.append({"key": key, "btn": InputFrame.ATTACK if parts[0] == "attack" else InputFrame.SPECIAL,
			"dir": parts[1] if parts.size() > 1 else "neutral", "air": key.ends_with(".air"),
			"reach": reach, "dmg": dmg / (1.0 + float(a.startup) / 20.0), "ranged": ranged,
			"cd": int(a.get("cooldown", 0))})


func next(sim: MatchSim, me_idx: int) -> InputFrame:
	if level == 0:
		return InputFrame.new()
	var me: Fighter = sim.fighters[me_idx]
	if not _ready:
		_setup(sim, me)
	if not _plan.is_empty():
		hold = _plan.pop_front()
		return hold
	if sim.frame % 3 != 0:
		var keep := InputFrame.new()
		keep.sx = hold.sx
		keep.sy = hold.sy
		keep.buttons = hold.buttons & InputFrame.GUARD
		return keep
	hold = _decide(sim, me)
	return hold


func _target(sim: MatchSim, me: Fighter) -> Fighter:
	var best := INF
	var t: Fighter = null
	for f in sim.fighters:
		if f != me and f.alive() and f.state != "out":
			var dd: float = f.pos.distance_to(me.pos)
			if dd < best:
				best = dd
				t = f
	return t


func _decide(sim: MatchSim, me: Fighter) -> InputFrame:
	var mid := _ground.get_center().x
	# 回场：在主地面外侧或下方
	var off_stage := me.pos.x < _ground.position.x - 4 or me.pos.x > _ground.end.x + 4 or me.pos.y > _ground.position.y + 2
	if off_stage and not me.on_ground:
		var dir := signf(mid - me.pos.x)
		if me.vel.y > -1.0:
			if me.jumps_used < int(me.ch.data.actions[me.ch.jump_id].max_count):
				return InputFrame.make(Vector2(dir, -1), InputFrame.JUMP)
			if "special.up" in me.eff.input and rng.randf() < 0.5:
				return InputFrame.make(Vector2(dir, -1), InputFrame.SPECIAL)
		return InputFrame.make(Vector2(dir, 0), 0)
	var t := _target(sim, me)
	if t == null:
		return InputFrame.new()
	var dx: float = t.pos.x - me.pos.x
	var dy: float = t.pos.y - me.pos.y
	var adx: float = abs(dx)
	var toward := signf(dx) if dx != 0 else float(me.facing)
	# 防守：对方正在出招且离得近
	if t.state == "action" and t.act_phase() in ["startup", "active"] and adx < 60 and abs(dy) < 40 and me.on_ground:
		var r := rng.randf()
		if r < 0.25:
			return InputFrame.make(Vector2.ZERO, InputFrame.GUARD)
		if r < 0.4 and me.dodge_cd == 0:
			_plan = [InputFrame.make(Vector2(-toward, 0), InputFrame.GUARD)]
			return InputFrame.make(Vector2.ZERO, InputFrame.GUARD)
	if me.ult >= float(Rules.data().combat.ult.max) and adx < 120 and rng.randf() < 0.5:
		return InputFrame.make(Vector2.ZERO, InputFrame.ULT)
	if me.state == "action":
		return InputFrame.make(Vector2(toward * 0.3, 0), 0)
	# 选招：射程够、方向对得上的里面挑期望伤害最高的（带一点随机）
	var best: Dictionary = {}
	var best_score := -1.0
	for m in _moves:
		if m.air == me.on_ground:
			continue
		if int(me.cooldowns.get(me.eff.input.get(m.key, ""), 0)) > sim.frame:
			continue
		var ok := false
		match m.dir:
			"side", "neutral":
				ok = adx <= m.reach and abs(dy) < 24
			"up":
				ok = adx < 30 and dy < -6 and dy > -m.reach - 20
			"down":
				ok = adx < 30 and (dy > 6 or (m.ranged == false and abs(dy) < 16 and adx < m.reach * 0.6))
		if m.ranged and m.dir in ["side", "neutral"]:
			ok = abs(dy) < 20 and adx <= m.reach
		if not ok:
			continue
		var score: float = m.dmg * rng.randf_range(0.6, 1.4)
		if score > best_score:
			best_score = score
			best = m
	if not best.is_empty() and rng.randf() < 0.85:
		var st := Vector2.ZERO
		match best.dir:
			"side":
				st = Vector2(toward, 0)
			"up":
				st = Vector2(0, -1)
			"down":
				st = Vector2(0, 1)
		if best.dir != "side" and toward != me.facing:
			# 先转身再出招
			_plan = [InputFrame.make(st, best.btn)]
			return InputFrame.make(Vector2(toward * 0.6, 0), 0)
		return InputFrame.make(st, best.btn)
	# 走位：远程角色保持距离，近战角色靠近
	var want := 30.0
	for m in _moves:
		if m.ranged:
			want = 90.0
	var st := Vector2.ZERO
	if adx > want + 10:
		st.x = toward
	elif adx < want - 30 and want > 60:
		st.x = -toward
	var btn := 0
	if dy < -28 and adx < 70 and me.on_ground and rng.randf() < 0.5:
		btn = InputFrame.JUMP
	elif dy > 28 and me.on_ground and me.ground_oneway and adx < 60:
		st = Vector2(0, 1)
	# 别自己走出边缘
	if me.on_ground and ((me.pos.x < _ground.position.x + 12 and st.x < 0) or (me.pos.x > _ground.end.x - 12 and st.x > 0)):
		st.x = 0
	return InputFrame.make(st, btn)
