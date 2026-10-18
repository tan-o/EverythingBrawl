extends SceneTree
## 无头测试入口：
##   godot --headless --path game -s res://tests/run_tests.gd -- conformance <conformance目录>
##   godot --headless --path game -s res://tests/run_tests.gd -- validate <zip>
##   godot --headless --path game -s res://tests/run_tests.gd -- sim <zip> <zip> [帧数] [场景zip]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ok := false
	if args.size() >= 2 and args[0] == "conformance":
		ok = ConformanceTest.run(args[1])
	elif args.size() >= 2 and args[0] == "validate":
		var v := PackValidator.validate_file(args[1])
		print(v.report())
		ok = v.is_valid()
	elif args.size() >= 3 and args[0] == "sim":
		if args.size() > 4:
			ok = SimSmokeTest.run(args[1], args[2], int(args[3]), args[4])
		else:
			ok = SimSmokeTest.run(args[1], args[2], int(args[3]) if args.size() > 3 else 3600)
	else:
		printerr("用法见 run_tests.gd 注释")
	quit(0 if ok else 1)
