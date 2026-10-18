class_name SimSmokeTest
extends RefCounted
## 随机输入跑一局，检查运行时限制与基本不变量。


static func load_runtime(path: String) -> CharRuntime:
	var v := PackValidator.validate_file(path)
	if not v.is_valid():
		printerr("包不合法: ", path, "\n", v.report())
		return null
	return CharRuntime.new(v.data)


static func run(a: String, b: String, frames: int) -> bool:
	var ca := load_runtime(a)
	var cb := load_runtime(b)
	if ca == null or cb == null:
		return false
	var sim := MatchSim.new([ca, cb])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var R := Rules.data()
	var stats := {}
	var hold := [InputFrame.new(), InputFrame.new()]
	var ok := true
	for fr in frames:
		var inputs := []
		for i in 2:
			if fr % 6 == 0:
				var btn := 0
				for bit in [InputFrame.ATTACK, InputFrame.SPECIAL, InputFrame.JUMP, InputFrame.GUARD, InputFrame.ULT]:
					if rng.randf() < 0.18:
						btn |= bit
				var other: Fighter = sim.fighters[1 - i]
				var toward := signf(other.pos.x - sim.fighters[i].pos.x)
				var st := Vector2(toward if rng.randf() < 0.6 else rng.randf_range(-1, 1), rng.randf_range(-1, 1) if rng.randf() < 0.4 else 0.0)
				# 别总往场外跑
				if sim.fighters[i].pos.x < 90:
					st.x = 1
				elif sim.fighters[i].pos.x > 390:
					st.x = -1
				hold[i] = InputFrame.make(st, btn)
			inputs.append(hold[i])
		sim.step(inputs)
		for e in sim.events:
			stats[e.t] = stats.get(e.t, 0) + 1
		for f in sim.fighters:
			if f.hp < 0 or f.hp > f.stats().hp + 0.001:
				printerr("hp 越界 ", f.hp)
				ok = false
			if f.heal_used > R.runtime.max_heal_per_life + 0.001:
				printerr("回复超上限")
				ok = false
			var shots := 0
			var deploy := 0
			var area := 0.0
			for p in sim.projectiles:
				if p.owner == f.idx and not p.ult:
					area += p.full_area()
					if p.kind == "deployable":
						deploy += 1
					else:
						shots += 1
			if shots > R.runtime.max_shots or deploy > R.runtime.max_deployables or area > R.runtime.max_area + 0.01:
				printerr("运行时限制被突破 shots=%d deploy=%d area=%.1f" % [shots, deploy, area])
				ok = false
		if sim.over and sim.over_t > 120:
			print("比赛结束于第 %d 帧，胜者 %d" % [fr, sim.winner])
			break
	print("事件统计: ", stats)
	for f in sim.fighters:
		print("P%d %s hp=%.1f lives=%d state=%s" % [f.idx + 1, f.ch.name, f.hp, f.lives, f.state])
	sim.dispose()
	return ok
