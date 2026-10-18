extends SceneTree
## 截图测试（需要显示环境，如 xvfb-run）：
##   godot --path game -s res://tests/screenshot.gd -- <包A> <包B> <输出目录> [帧1,帧2,...] [debug]

var m: MatchScreen
var frames: Array = []
var out := ""
var rng := RandomNumberGenerator.new()
var hold := [InputFrame.new(), InputFrame.new()]
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[2]
	DirAccess.make_dir_recursive_absolute(out)
	for s in (args[3] if args.size() > 3 else "60,300,600").split(","):
		frames.append(int(s))
	root.size = Vector2i(1280, 720)
	m = MatchScreen.new()
	root.add_child(m)
	m.start([
		{"validator": PackLibrary.load_pack(args[0]), "input": "none"},
		{"validator": PackLibrary.load_pack(args[1]), "input": "none"},
	])
	if args.size() > 4 and args[4] == "debug":
		m._toggle_debug()
	rng.seed = 3
	m.input_provider = _bot


func _bot(sim: MatchSim) -> Array:
	var res := []
	for i in 2:
		if sim.frame % 8 == 0:
			var me: Fighter = sim.fighters[i]
			var other: Fighter = sim.fighters[1 - i]
			var btn := 0
			for bit in [InputFrame.ATTACK, InputFrame.SPECIAL, InputFrame.JUMP, InputFrame.ULT]:
				if rng.randf() < 0.2:
					btn |= bit
			var st := Vector2(signf(other.pos.x - me.pos.x), 0)
			if rng.randf() < 0.3:
				st.y = rng.randf_range(-1, 1)
			if me.pos.x < 90:
				st.x = 1
			elif me.pos.x > 390:
				st.x = -1
			hold[i] = InputFrame.make(st, btn)
		res.append(hold[i])
	return res


func _process(_d: float) -> bool:
	n += 1
	if n in frames:
		var img := root.get_texture().get_image()
		img.save_png(out.path_join("frame_%05d.png" % n))
	return n > frames.max()
