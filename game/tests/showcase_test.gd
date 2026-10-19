extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var count := 0
	for e in Catalog.valid_entries("character"):
		var showcase := SkillShowcase.new()
		showcase.pack = e.v
		root.add_child(showcase)
		showcase.set_physics_process(false)
		for aid in e.v.data.actions:
			showcase.play(aid)
			if showcase.selected != aid or showcase.keys.text.is_empty():
				push_error("Showcase selection or shortcuts missing")
				quit(1)
				return
			for i in 120:
				showcase._physics_process(1.0 / 60)
			showcase.play("")
			if showcase.sfx.pool.size() != 12:
				push_error("Replay grew audio pool")
				quit(1)
				return
			count += 1
		showcase.queue_free()
		await process_frame
		await process_frame
	print("OK showcase %d skills and replays" % count)
	quit()
