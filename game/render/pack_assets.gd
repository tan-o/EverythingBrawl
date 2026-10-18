class_name PackAssets
extends RefCounted
## 从已校验的角色包构建渲染/音频资源：SpriteFrames、武器与子弹贴图、特效、图标、音效。

var data: Dictionary
var sheet: Image
var sheet_tex: ImageTexture
var frames: SpriteFrames            # 动画名 -> 帧
var textures := {}                  # 资产名 -> ImageTexture（weapon / projectile / icon）
var fx_frames := {}                 # 资产名 -> SpriteFrames（动画名 "fx"）
var sounds := {}                    # 资产名 -> AudioStreamWAV
var frame_size: Vector2i
var anchor: Vector2


static func build(v: PackValidator) -> PackAssets:
	var a := PackAssets.new()
	a._build(v.data, v.images)
	return a


func _build(d: Dictionary, images: Dictionary) -> void:
	data = d
	frame_size = Vector2i(int(d.frame_size[0]), int(d.frame_size[1]))
	anchor = Vector2(d.anchor[0], d.anchor[1])
	sheet = images["sheet.png"]
	sheet_tex = ImageTexture.create_from_image(sheet)
	var cols := sheet.get_width() / frame_size.x
	frames = SpriteFrames.new()
	frames.remove_animation("default")
	for an in d.anims:
		var anim: Dictionary = d.anims[an]
		frames.add_animation(an)
		frames.set_animation_loop(an, false)
		for fi in anim.frames:
			var at := AtlasTexture.new()
			at.atlas = sheet_tex
			at.region = Rect2((int(fi) % cols) * frame_size.x, (int(fi) / cols) * frame_size.y, frame_size.x, frame_size.y)
			frames.add_frame(an, at)
	for k in d.assets:
		var as_: Dictionary = d.assets[k]
		match as_.kind:
			"weapon", "projectile", "icon":
				var tex := ImageTexture.create_from_image(images[as_.image])
				textures[k] = tex
			"fx":
				var img: Image = images[as_.image]
				var tex := ImageTexture.create_from_image(img)
				var fw := img.get_width() / int(as_.frames)
				var sf := SpriteFrames.new()
				sf.set_animation_loop("default", false)
				sf.set_animation_speed("default", 60.0)
				for i in int(as_.frames):
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = Rect2(i * fw, 0, fw, img.get_height())
					sf.add_frame("default", at, float(as_.durations[i]))
				fx_frames[k] = sf
			"sfx":
				sounds[k] = Sfxr.generate(as_.params)


## 某动画某帧的像素图（用于击倒粒子）。
func frame_image(anim_name: String, idx: int) -> Image:
	var anim = data.anims.get(anim_name)
	if anim == null:
		return null
	var fi := int(anim.frames[clampi(idx, 0, anim.frames.size() - 1)])
	var cols := sheet.get_width() / frame_size.x
	return sheet.get_region(Rect2i((fi % cols) * frame_size.x, (fi / cols) * frame_size.y, frame_size.x, frame_size.y))


func icon_texture() -> Texture2D:
	var idle = data.anims.get("idle")
	if idle == null:
		return null
	return frames.get_frame_texture("idle", 0)
