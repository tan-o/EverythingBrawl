extends SceneTree
## 数值平衡统计：电脑对电脑循环赛（每对角色 x 每个场景 x 若干种子），输出胜率、对局时长、击倒方式、伤害。
##   godot --headless --path game -s res://tests/balance.gd -- [每组局数=3] [最长帧数=14400]

const CHARS := ["knight", "swissknife", "toolbox", "bulb"]
const STAGES := ["kitchen", "desk"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var reps := int(args[0]) if args.size() > 0 else 3
	var max_frames := int(args[1]) if args.size() > 1 else 14400
	var runtimes := {}
	for c in CHARS:
		runtimes[c] = CharRuntime.new(PackValidator.validate_file("res://data/packs/%s.zip" % c).data)
	var stages := {}
	for s in STAGES:
		stages[s] = PackValidator.validate_file("res://data/stages/%s.zip" % s).data
	var st := {}
	for c in CHARS:
		st[c] = {"games": 0, "wins": 0, "dmg": 0.0, "hits": 0, "ko_hp": 0, "ko_blast": 0}
	var lengths := []
	var timeouts := 0
	var hazard_hits := 0
	var t0 := Time.get_ticks_msec()
	var seed := 1
	for a in CHARS:
		for b in CHARS:
			if a == b:
				continue
			for sname in STAGES:
				for r in reps:
					seed += 1
					var sim := MatchSim.new([runtimes[a], runtimes[b]], stages[sname])
					var cpus := [CpuInput.new(1, seed * 2), CpuInput.new(1, seed * 2 + 1)]
					var names := [a, b]
					while sim.frame < max_frames and not (sim.over and sim.over_t > 1):
						sim.step([cpus[0].next(sim, 0), cpus[1].next(sim, 1)])
						for e in sim.events:
							match e.t:
								"hit":
									if e.i == e.tgt:
										hazard_hits += 1
									else:
										st[names[e.i]].dmg += e.dmg
										st[names[e.i]].hits += 1
								"ko":
									st[names[e.i]].ko_hp += 1
								"blast":
									st[names[e.i]].ko_blast += 1
					for c in names:
						st[c].games += 1
					if sim.over and sim.winner >= 0:
						st[names[sim.winner]].wins += 1
						lengths.append(sim.frame)
					else:
						timeouts += 1
					sim.dispose()
	lengths.sort()
	print("对局 %d 场，超时 %d 场，用时 %.1f 秒" % [lengths.size() + timeouts, timeouts, (Time.get_ticks_msec() - t0) / 1000.0])
	if not lengths.is_empty():
		print("对局时长（秒）：中位 %.0f，最短 %.0f，最长 %.0f" % [lengths[lengths.size() / 2] / 60.0, lengths[0] / 60.0, lengths[-1] / 60.0])
	print("场景危险物命中：%d" % hazard_hits)
	for c in CHARS:
		var s: Dictionary = st[c]
		print("%-10s 胜率 %3.0f%%  每局伤害 %5.1f  每次命中 %4.1f  被打到 0 血 %d  出界 %d" % [
			c, 100.0 * s.wins / max(1, s.games), s.dmg / max(1, s.games), s.dmg / max(1, s.hits), s.ko_hp, s.ko_blast])
	quit()
