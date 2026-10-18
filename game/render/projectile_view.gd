class_name ProjectileView
extends Node2D
## 绘制一个子弹 / 光束 / 布置物。

var assets: PackAssets
var sprite := Sprite2D.new()
var snap := {}
var kind := ""


func setup(p_assets: PackAssets, s: Dictionary) -> void:
	assets = p_assets
	kind = s.k
	var tex: Texture2D = assets.textures.get(s.as)
	sprite.texture = tex
	var pd: Dictionary = assets.data.assets[s.as]
	if pd.get("tile") == "repeat_x":
		sprite.region_enabled = true
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if kind == "beam":
		sprite.centered = false
		sprite.offset = Vector2(0, -tex.get_height() / 2.0)
	add_child(sprite)


func apply(s: Dictionary) -> void:
	snap = s
	position = Vector2(s.x, s.y)
	var pd: Dictionary = assets.data.assets[s.as]
	var tex: Texture2D = sprite.texture
	if sprite.region_enabled:
		var unit_scale: float = pd.size[1] / float(tex.get_height())
		var w: float = s.len / max(0.001, s.sc * unit_scale)
		sprite.region_rect = Rect2(0, 0, max(1.0, w), tex.get_height())
		sprite.scale = Vector2(s.sc * unit_scale, s.sc * unit_scale)
	elif kind == "beam":
		sprite.scale = Vector2(s.len / max(1.0, tex.get_width()), s.sc)
	else:
		sprite.scale = Vector2(s.sc, s.sc)
	if pd.shape == "rect" or kind == "beam":
		sprite.rotation = s.ang
	queue_redraw()


func _draw() -> void:
	if kind != "deployable" or snap.is_empty():
		return
	var pd: Dictionary = assets.data.assets[snap.as]
	var w: float = pd.size[0] * snap.sc
	var h: float = pd.size[1] * snap.sc
	var col := Palette.player(snap.o)
	draw_rect(Rect2(-w / 2.0, h / 2.0 + 1, w, 1), col)
	draw_rect(Rect2(-w / 2.0, h / 2.0 + 3, w * snap.life, 1), Color(1, 1, 1, 0.8))
