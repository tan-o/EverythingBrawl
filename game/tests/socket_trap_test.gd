extends SceneTree
## Runtime contract checks: socket coordinates, mirrored attacks, trap timing and snapshots.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var tea := PackLibrary.load_pack("res://data/packs/teapot.zip")
	var gallery := PackLibrary.load_pack("res://data/stages/gallery.zip")
	check(tea.is_valid(), "teapot must validate")
	check(gallery.is_valid(), "gallery must validate")
	if failures > 0:
		quit(1)
		return
	var sim := MatchSim.new([CharRuntime.new(tea.data), CharRuntime.new(tea.data)], gallery.data)
	var f: Fighter = sim.fighters[0]
	f.pos = Vector2(100, 180)
	f.facing = 1
	var water := f.ch.action("water", {})
	check(f.shoot_origin(water, 0, true).is_equal_approx(Vector2(119, 159)), "water must originate at the animated spout")
	check(f.weapon_visual().is_empty(), "teapot must have no weapon")
	f.facing = -1
	check(f.shoot_origin(water, 0, true).is_equal_approx(Vector2(81, 159)), "spout must mirror with facing")
	check(f.shoot_origin(f.ch.action("steam", {}), 90, true).is_equal_approx(Vector2(99, 150)), "steam follows the animated lid socket")
	f.facing = 1
	var attached := water.duplicate(true)
	attached.attach = true
	sim.fire_shoot(f, attached, null, 0, 1, 0)
	f.anim_name = "pour"
	f.anim_idx = 2
	sim._update_projectiles()
	check(sim.projectiles[0].pos.is_equal_approx(Vector2(117, 159)), "attached emission must follow the current animated socket")
	# Legacy weapon mounts and named mounts resolve through the same coordinate path.
	var knight := PackLibrary.load_pack("res://data/packs/knight.zip")
	var legacy = knight.data.anims.idle
	check(CharDef.socket_at(knight.data, legacy, 0) == legacy.hand[0], "legacy hand packs remain compatible")
	var named := knight.data.duplicate(true)
	named.held_socket = "grip"
	named.sockets = {"grip": [30, 32]}
	var mount := Fighter.new()
	mount.setup(sim, 0, CharRuntime.new(named), Vector2(100, 180))
	check(mount.weapon_visual().get("socket") == "grip", "held weapons bind to the selected socket")
	mount.sim = null
	var stage := Stage.new(gallery.data)
	for i in 45:
		stage.step()
	check(stage.traps.shots.is_empty(), "traps may not shoot during warning")
	check(not stage.traps.warnings.is_empty(), "warning must be visible")
	stage.step()
	check(stage.traps.shots.size() == 1, "trap fires once after warning")
	var first: Dictionary = stage.traps.shots[0]
	check(first.pos.is_equal_approx(Vector2(62, 99)), "background hand origin must align with artwork")
	# One impact, no player ownership; the same hit must not repeat.
	var victim: Fighter = sim.fighters[1]
	victim.pos = first.pos + Vector2(0, 15)
	victim.invuln = 0
	victim.state = "air"
	var hp := victim.hp
	sim.stage = stage
	sim._stage_attacks()
	check(victim.hp == hp - 5, "stage projectile must damage fighters")
	sim._stage_attacks()
	check(victim.hp == hp - 5, "stage projectile is consumed on impact")
	for i in 90:
		stage.step()
	check(not stage.traps.swings.is_empty(), "background weapon enters its active swing")
	if not stage.traps.swings.is_empty():
		var swing: Dictionary = stage.traps.swings[0]
		victim.pos = swing.tip + Vector2(0, 15)
		victim.invuln = 0
		victim.state = "air"
		hp = victim.hp
		sim._stage_attacks()
		sim._stage_attacks()
		check(victim.hp == hp - 5, "one swing hits each fighter at most once")
	var copied = bytes_to_var(var_to_bytes(sim.snapshot()))
	check(copied.traps == sim.snapshot().traps, "trap snapshots survive network serialization")
	# Inactive emitters cannot keep swinging; restoration restarts warning.
	stage.els[5].broken = 80
	stage.step()
	check(stage.traps.swings.is_empty(), "removed emitters stop swinging")
	for i in 80:
		stage.step()
	check(stage.traps.swings.is_empty(), "restored emitter cannot skip warning")
	# A moving source carries its origin; spawned bullets move independently.
	var moving_data := gallery.data.duplicate(true)
	moving_data.elements[4]["move"] = {"path": [[0,0],[10,0]], "period": 120}
	var moving := Stage.new(moving_data)
	for i in 46:
		moving.step()
	check(moving.traps.shots[0].pos.is_equal_approx(moving.els[4].rect.position + Vector2(34,29)), "moving emitter socket follows its element")
	# Swept collision must stop bullets at solid terrain.
	moving.els.append({"def": {"collide": "solid"}, "rect": Rect2(moving.traps.shots[0].pos + Vector2(2,-10), Vector2(2,20)), "present": true})
	moving.traps.step(moving)
	check(moving.traps.shots.is_empty(), "stage projectiles must stop at walls")
	sim.dispose()
	if failures == 0:
		print("OK sockets, stage traps, collision and snapshots")
	quit(1 if failures else 0)
