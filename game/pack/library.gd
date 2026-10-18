class_name PackLibrary
extends RefCounted
## 角色包库：内置示例（res://data/packs）+ 用户导入（user://packs）。校验结果按 SHA-256 缓存。

const BUNDLED := "res://data/packs"
const USER := "user://packs"

static var _cache := {}   # sha -> PackValidator


static func ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(USER)


static func paths() -> Array:
	ensure_user_dir()
	var out := []
	for dir in [BUNDLED, USER]:
		var files := DirAccess.get_files_at(dir)
		var names := Array(files)
		names.sort()
		for f in names:
			if f.ends_with(".zip"):
				out.append(dir.path_join(f))
	return out


static func load_pack(path: String) -> PackValidator:
	var r := PackReader.from_file(path)
	if r.sha256 in _cache:
		return _cache[r.sha256]
	var v := PackValidator.new(r)
	v.run()
	_cache[r.sha256] = v
	return v


## 导入外部 zip（复制到 user://packs，按 SHA-256 命名避免重复）。
static func import_file(src: String) -> String:
	ensure_user_dir()
	var bytes := FileAccess.get_file_as_bytes(src)
	if bytes.is_empty():
		return ""
	var dst := USER.path_join(PackReader.hash_bytes(bytes).substr(0, 16) + ".zip")
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return dst
