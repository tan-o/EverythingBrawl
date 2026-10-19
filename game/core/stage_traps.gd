class_name StageTraps
extends RefCounted
## Host-simulated stage attacks. Rendering consumes snapshots, never local timers.
var shots: Array = []
var swings: Array = []
var warnings: Array = []
var serial := 0
var clocks := {}

static func direction(angle: float) -> Vector2:
	return Vector2(cos(deg_to_rad(angle)), -sin(deg_to_rad(angle)))

func step(stage: Stage) -> void:
	swings.clear()
	warnings.clear()
	for shot in shots:
		shot.prev = shot.pos
		shot.pos += shot.vel
		shot.life -= 1
		for i in stage.colliders():
			if i == shot.el or stage.els[i].def.collide != "solid":
				continue
			if Geom.overlap(Geom.capsule(shot.prev, shot.pos, shot.radius), Geom.aabb(stage.els[i].rect)):
				shot.life = 0
	shots = shots.filter(func(s): return s.life > 0)
	for i in stage.els.size():
		var e: Dictionary = stage.els[i]
		if not e.present or not ("trap" in e.def):
			clocks.erase(i)
			continue
		var a: Dictionary = e.def.trap
		# Offset delays the first cycle; newly restored traps get a full warning.
		var time := int(clocks.get(i, 0))
		clocks[i] = time + 1
		if time < int(a.get("offset", 0)):
			continue
		var phase := (time - int(a.get("offset", 0))) % int(a.period)
		var origin: Vector2 = e.rect.position + Vector2(a.origin[0], a.origin[1])
		if phase < int(a.warn):
			warnings.append({"el": i, "x": origin.x, "y": origin.y, "phase": phase, "angle": a.get("angle", a.get("from", 0))})
		if a.type == "shoot" and phase == int(a.warn):
			if shots.size() < int(Rules.data().stage_limits.trap.max_projectiles):
				serial += 1
				shots.append({"id": serial, "el": i, "pos": origin, "prev": origin, "vel": direction(a.angle) * a.speed, "life": int(a.lifetime), "radius": float(a.radius), "def": a})
		elif a.type == "swing" and phase >= int(a.warn) and phase < int(a.warn + a.active):
			var angle: float = lerp(float(a.from), float(a.to), float(phase - a.warn) / maxf(1, a.active - 1))
			var tip: Vector2 = origin + direction(angle) * a.length
			swings.append({"el": i, "cycle": stage.t - phase, "pos": origin, "tip": tip, "angle": angle, "def": a})

func snapshot() -> Dictionary:
	var bullets := []
	for s in shots:
		bullets.append({"id": s.id, "el": s.el, "x": s.pos.x, "y": s.pos.y})
	var arcs := []
	for s in swings:
		arcs.append({"el": s.el, "x": s.pos.x, "y": s.pos.y, "angle": s.angle})
	return {"shots": bullets, "swings": arcs, "warnings": warnings.duplicate(true)}
