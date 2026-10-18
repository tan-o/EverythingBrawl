class_name CpuInput
extends RefCounted
## 练习用的简单电脑对手：靠近、出招、跳上平台、躲避场外、偶尔防御。只产生输入，不碰模拟内部。

var rng := RandomNumberGenerator.new()
var hold := InputFrame.new()
var level := 1          # 0 = 木桩（不动），1 = 电脑


func _init(p_level := 1, seed := 1) -> void:
	level = p_level
	rng.seed = seed


func next(sim: MatchSim, me_idx: int) -> InputFrame:
	if level == 0:
		return InputFrame.new()
	var me: Fighter = sim.fighters[me_idx]
	if sim.frame % 6 != 0:
		# 按键只按一帧，摇杆保持
		var keep := InputFrame.new()
		keep.sx = hold.sx
		keep.sy = hold.sy
		keep.buttons = hold.buttons & InputFrame.GUARD
		return keep
	var target: Fighter = null
	var best := INF
	for f in sim.fighters:
		if f != me and f.alive():
			var d: float = f.pos.distance_to(me.pos)
			if d < best:
				best = d
				target = f
	var st := Vector2.ZERO
	var btn := 0
	var W: float = Rules.data().stage.width
	if target != null:
		var dx: float = target.pos.x - me.pos.x
		var dy: float = target.pos.y - me.pos.y
		st.x = signf(dx) if abs(dx) > 18 else 0.0
		if abs(dx) < 40 and abs(dy) < 30:
			btn |= InputFrame.ATTACK if rng.randf() < 0.6 else InputFrame.SPECIAL
			if rng.randf() < 0.3:
				st.y = -1.0 if dy < -10 else (1.0 if rng.randf() < 0.3 else 0.0)
		elif rng.randf() < 0.08:
			btn |= InputFrame.SPECIAL
		if dy < -30 and rng.randf() < 0.4:
			btn |= InputFrame.JUMP
		if target.state == "action" and abs(dx) < 50 and rng.randf() < 0.15:
			btn = InputFrame.GUARD
	if me.ult >= float(Rules.data().combat.ult.max) and rng.randf() < 0.3:
		btn |= InputFrame.ULT
	# 掉下去了就往场中跳
	if not me.on_ground and me.vel.y > 0 and (me.pos.y > 190 or me.pos.x < 40 or me.pos.x > W - 40):
		st.x = signf(W / 2.0 - me.pos.x)
		if rng.randf() < 0.5:
			btn |= InputFrame.JUMP
			st.y = -1.0
			btn |= InputFrame.SPECIAL if rng.randf() < 0.3 else 0
	hold = InputFrame.make(st, btn)
	return hold
