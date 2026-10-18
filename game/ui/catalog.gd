class_name Catalog
extends RefCounted
## 界面用的包列表：名字、缩略图、来源。

static var _thumbs := {}   # sha -> Texture2D


## [{path, v, name, tex, user, valid}]
static func entries(kind: String) -> Array:
	var out := []
	for p in PackLibrary.paths(kind):
		var v := PackLibrary.load_pack(p)
		out.append(entry(p, v))
	return out


static func entry(p: String, v: PackValidator) -> Dictionary:
	var name: String = p.get_file().get_basename()
	if v.data != null and not v.data.is_empty() and v.data.get("name") is String:
		name = v.data.name
	return {"path": p, "v": v, "name": name, "tex": thumb(v), "user": PackLibrary.is_user(p), "valid": v.is_valid()}


static func valid_entries(kind: String) -> Array:
	return entries(kind).filter(func(e): return e.valid)


static func thumb(v: PackValidator) -> Texture2D:
	var sha := v.pack.sha256
	if sha in _thumbs:
		return _thumbs[sha]
	var tex: Texture2D = null
	if v.is_valid():
		if v.kind == "stage":
			var a: Dictionary = v.data.assets[v.data.background]
			var img: Image = v.images[a.image]
			var fw := img.get_width() / int(a.get("frames", 1))
			tex = ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, fw, img.get_height())))
		else:
			var idle: Dictionary = v.data.anims.idle
			var fs: Array = v.data.frame_size
			var sheet: Image = v.images["sheet.png"]
			var cols := sheet.get_width() / int(fs[0])
			var fi := int(idle.frames[0])
			var img := sheet.get_region(Rect2i((fi % cols) * int(fs[0]), (fi / cols) * int(fs[1]), int(fs[0]), int(fs[1])))
			var used := img.get_used_rect()
			if used.size.x > 0:
				img = img.get_region(used)
			tex = ImageTexture.create_from_image(img)
	_thumbs[sha] = tex
	return tex
