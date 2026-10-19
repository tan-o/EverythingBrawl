extends SceneTree
## Exercise real screens and optionally capture them under xvfb for visual review.
## godot --path game -s res://tests/ui_smoke_test.gd -- <screenshot-directory>
var app: Control
var out := ""

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for i in 8:
		await process_frame

func _capture(name: String) -> void:
	await _settle()
	if not out.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var err := root.get_texture().get_image().save_png(out.path_join(name + ".png"))
		if err != OK:
			push_error("Screenshot failed: " + name)
			quit(1)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
		DirAccess.make_dir_recursive_absolute(out)
	for ch in "像素大乱斗攻特跳防":
		if not ArcadeTheme.FONT.has_char(ch.unicode_at(0)):
			push_error("Bundled font is missing Chinese glyph: " + ch)
			quit(1)
			return
	root.size = Vector2i(1280, 720)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await _capture("01-menu")
	app._show_library("character")
	await _capture("02-characters")
	var chars := Catalog.valid_entries("character")
	var stages := Catalog.valid_entries("stage")
	if chars.is_empty() or stages.is_empty():
		push_error("Missing example packs")
		quit(1)
		return
	app._show_detail("character", chars[0])
	await _capture("03-character-detail")
	app._show_showcase(chars[0])
	await _capture("03b-skill-showcase")
	app.current.play("")
	await _settle()
	app.current.exited.emit()
	await _settle()
	app._show_library("stage")
	await _capture("04-stages")
	app._show_detail("stage", stages[0])
	await _capture("05-stage-detail")
	app._show_lobby()
	await _capture("06-lobby")
	app.current._back()
	await _settle()
	app._show_practice()
	await _capture("07-practice")
	app.practice.foe = chars[1].path if chars.size() > 1 else chars[0].path
	app._start_practice()
	await _capture("08-match")
	var match_ui: MatchScreen = app.current
	match_ui.touch.ult_ready = true
	match_ui._set_paused(true)
	await _capture("09-pause")
	match_ui._set_paused(false)
	match_ui.paused = true
	match_ui._game_over({"winner": 0})
	await _capture("10-results")
	match_ui._quit()
	await _settle()
	var trap_match := MatchScreen.new()
	app._set_screen(trap_match)
	trap_match.start([{"validator": PackLibrary.load_pack("res://data/packs/teapot.zip"), "input":"none"}, {"validator": chars[0].v, "input":"dummy"}], PackLibrary.load_pack("res://data/stages/gallery.zip"))
	trap_match.paused = true
	for i in 138:
		trap_match.sim.step([InputFrame.new(), InputFrame.new()])
	trap_match._show(trap_match.sim.snapshot())
	await _capture("10b-stage-traps")
	trap_match.sim.dispose()
	app._show_net()
	await _capture("11-network")
	app.current._back()
	await _settle()
	# Wide mobile aspect ratio, using the same 720-high canvas.
	root.size = Vector2i(1600, 720)
	await _capture("12-menu-wide")
	app.queue_free()
	await _settle()
	print("OK UI screens, match overlays and wide layout")
	quit()
