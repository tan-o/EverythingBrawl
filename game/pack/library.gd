class_name PackLibrary
extends RefCounted
## 角色包 / 场景包库：内置示例（res://data/…）+ 用户导入（user://…）+ 联机收到的缓存（user://cache）。
## 校验结果按 SHA-256 缓存。

const DIRS := {
	"character": ["res://data/packs", "user://packs"],
	"stage": ["res://data/stages", "user://stages"],
}
const CACHE := "user://cache"

static var _cache := {}   # sha -> PackValidator


static func ensure_dirs() -> void:
	for k in DIRS:
		DirAccess.make_dir_recursive_absolute(DIRS[k][1])
	DirAccess.make_dir_recursive_absolute(CACHE)


static func paths(kind: String) -> Array:
	ensure_dirs()
	var out := []
	for dir in DIRS[kind]:
		var names := Array(DirAccess.get_files_at(dir))
		names.sort()
		for f in names:
			if f.ends_with(".zip"):
				out.append(dir.path_join(f))
	return out


static func is_user(path: String) -> bool:
	return path.begins_with("user://")


static func load_pack(path: String) -> PackValidator:
	var r := PackReader.from_file(path)
	return _validated(r)


static func _validated(r: PackReader) -> PackValidator:
	if r.sha256 in _cache:
		return _cache[r.sha256]
	var v := PackValidator.new(r)
	v.run()
	_cache[r.sha256] = v
	return v


## 导入外部 zip：校验通过后按类型存进 user://packs 或 user://stages。返回校验器（可看拒绝原因）。
static func import_bytes(bytes: PackedByteArray) -> PackValidator:
	ensure_dirs()
	var v := _validated(PackReader.from_bytes(bytes))
	if v.is_valid():
		var dst: String = DIRS[v.kind][1].path_join(v.pack.sha256.substr(0, 16) + ".zip")
		_write(dst, bytes)
	return v


static func import_file(src: String) -> PackValidator:
	return import_bytes(FileAccess.get_file_as_bytes(src))


static func remove(path: String) -> void:
	if is_user(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 联机缓存：按 SHA-256 存取包内容。
static func cache_has(sha: String) -> bool:
	return FileAccess.file_exists(CACHE.path_join(sha + ".zip")) or find_local(sha) != ""


static func cache_put(bytes: PackedByteArray) -> String:
	ensure_dirs()
	var sha := PackReader.hash_bytes(bytes)
	_write(CACHE.path_join(sha + ".zip"), bytes)
	return sha


static func cache_get(sha: String) -> PackedByteArray:
	var local := find_local(sha)
	if local != "":
		return FileAccess.get_file_as_bytes(local)
	return FileAccess.get_file_as_bytes(CACHE.path_join(sha + ".zip"))


static func cache_validator(sha: String) -> PackValidator:
	if sha in _cache:
		return _cache[sha]
	return _validated(PackReader.from_bytes(cache_get(sha)))


## 在本地库里按 SHA-256 找包。
static func find_local(sha: String) -> String:
	for kind in DIRS:
		for p in paths(kind):
			var r := PackReader.from_file(p)
			if r.sha256 == sha:
				return p
	return ""


static func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
