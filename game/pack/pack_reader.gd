class_name PackReader
extends RefCounted
## 读取角色包 zip：文件表、zip 大小与 SHA-256。不解析内容。

var files := {}          # 文件名 -> PackedByteArray
var zip_size := 0
var sha256 := ""
var error := ""          # 非空表示 zip 本身无法读取


static func from_bytes(bytes: PackedByteArray) -> PackReader:
	var tmp := "user://_incoming_pack.zip"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var r := from_file(tmp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return r


static func from_file(path: String) -> PackReader:
	if path.begins_with("res://"):
		# 导出包内的文件不在真实文件系统上，ZIPReader 需要先落地到 user://
		return from_bytes(FileAccess.get_file_as_bytes(path))
	var r := PackReader.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	r.zip_size = bytes.size()
	r.sha256 = hash_bytes(bytes)
	var z := ZIPReader.new()
	if z.open(path) != OK:
		r.error = "不是有效的 zip 文件"
		return r
	for name in z.get_files():
		if name.ends_with("/"):
			continue
		r.files[name] = z.read_file(name)
	z.close()
	return r


static func hash_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
