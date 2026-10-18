class_name ConformanceTest
extends RefCounted
## 用 conformance/expected.json 检查游戏内校验器（与 validate.py 共用同一组用例）。


static func run(dir: String) -> bool:
	var exp = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("expected.json")))
	var names: Array = exp.keys()
	names.sort()
	var fails := 0
	for name in names:
		var want: Dictionary = exp[name]
		var v := PackValidator.validate_file(dir.path_join("packs").path_join(name))
		var got := v.error_codes()
		var want_codes: Array = want.errors.duplicate()
		want_codes.sort()
		var ok: bool = v.is_valid() == want.valid and got == want_codes
		if ok and "points" in want:
			ok = _points_match(want.points, v.points)
		if not ok:
			fails += 1
			print("FAIL %s: want valid=%s %s, got valid=%s %s" % [name, want.valid, want_codes, v.is_valid(), got])
			print(v.report())
	print("conformance (game): %d/%d passed" % [names.size() - fails, names.size()])
	return fails == 0


static func _points_match(want: Dictionary, got: Dictionary) -> bool:
	if want.size() != got.size():
		return false
	for label in want:
		if not (label in got):
			return false
		var w: Dictionary = want[label]
		var g: Dictionary = got[label]
		if abs(w.total - g.total) > 1e-3:
			return false
		if w.actions.size() != g.actions.size():
			return false
		for aid in w.actions:
			if not (aid in g.actions) or abs(w.actions[aid] - g.actions[aid]) > 1e-3:
				return false
	return true
