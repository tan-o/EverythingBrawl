class_name Hud
extends Control
## 原生分辨率的 HUD：每位玩家的血量、命数、护盾、大招槽、资源；角色头顶名字牌。

var names: Array = []
var packs: Array = []     # PackAssets
var snap := {}
var view_rect := Rect2()  # 480x270 画面在屏幕上的位置
var view_scale := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func world_to_screen(p: Vector2) -> Vector2:
	return view_rect.position + p * view_scale


func _draw() -> void:
	if snap.is_empty():
		return
	var font := ThemeDB.fallback_font
	var R := Rules.data()
	var n: int = snap.fighters.size()
	var pw: float = min(300.0, (size.x - 40) / n)
	var y0 := 8.0
	for fs in snap.fighters:
		var i: int = fs.i
		var col := Palette.player(i)
		var x := 20 + i * (pw + 0) + (size.x - 40 - pw * n) / 2.0
		var r := Rect2(x + 4, y0, pw - 8, 86)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(r.position, Vector2(6, r.size.y)), col)
		var pa: PackAssets = packs[i]
		var icon := pa.icon_texture()
		if icon != null:
			var s: float = 56.0 / max(icon.get_width(), icon.get_height())
			draw_texture_rect(icon, Rect2(r.position + Vector2(12, 6), icon.get_size() * s), false)
		var tx := r.position.x + 74
		draw_string(font, Vector2(tx, r.position.y + 24), "P%d %s" % [i + 1, names[i]], HORIZONTAL_ALIGNMENT_LEFT, pw - 90, 20, Color.WHITE)
		var hpmax: float = pa.data.stats.hp
		var mask: int = fs.mask
		var bw := pw - 90
		# 血量
		var hp_ratio: float = clamp(fs.hp / max(1.0, _hp_max(pa, mask)), 0.0, 1.0)
		draw_rect(Rect2(tx, r.position.y + 32, bw, 12), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(tx, r.position.y + 32, bw * hp_ratio, 12), Color("#63c74d") if hp_ratio > 0.3 else Color("#e43b44"))
		draw_string(font, Vector2(tx + 4, r.position.y + 43), "%d" % ceil(fs.hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		# 护盾
		draw_rect(Rect2(tx, r.position.y + 47, bw * fs.sh / float(R.combat.shield.max), 4), Palette.SHIELD)
		# 大招槽
		var ur: float = fs.ult / float(R.combat.ult.max)
		draw_rect(Rect2(tx, r.position.y + 54, bw, 6), Color(0.2, 0.2, 0.2))
		var uc := Palette.GOLD if ur >= 1.0 and int(snap.frame / 8) % 2 == 0 else Color("#feae34").darkened(0.3)
		draw_rect(Rect2(tx, r.position.y + 54, bw * ur, 6), uc)
		# 命数
		for k in fs.lives:
			draw_circle(Vector2(r.position.x + 18 + k * 14, r.position.y + 74), 5, col)
		# 资源
		var rx := tx
		for rn in pa.data.get("resources", {}):
			var rd: Dictionary = pa.data.resources[rn]
			var hud: String = rd.get("hud", "")
			if hud == "":
				continue
			var v: float = fs.res.get(rn, 0)
			if hud == "bar":
				draw_rect(Rect2(rx, r.position.y + 66, 40, 6), Color(0.2, 0.2, 0.2))
				draw_rect(Rect2(rx, r.position.y + 66, 40 * v / rd.max, 6), Color("#7fb6ff"))
				rx += 46
			elif hud in pa.textures:
				var t: Texture2D = pa.textures[hud]
				var s2: float = 16.0 / max(t.get_width(), t.get_height())
				draw_texture_rect(t, Rect2(rx, r.position.y + 62, t.get_width() * s2, t.get_height() * s2), false)
				draw_string(font, Vector2(rx + 18, r.position.y + 76), "%d" % floor(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
				rx += 44
	# 名字牌
	for fs in snap.fighters:
		if fs.st in ["dead", "out"]:
			continue
		var pa: PackAssets = packs[fs.i]
		var head := world_to_screen(Vector2(fs.x, fs.y - pa.data.stats.body[1] - 4))
		var label := "P%d" % (fs.i + 1)
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, head + Vector2(-ts.x / 2.0, -4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.player(fs.i))


func _hp_max(pa: PackAssets, mask: int) -> float:
	var hp: float = pa.data.stats.hp
	var forms: Array = pa.data.get("forms", [])
	for i in forms.size():
		if mask & (1 << i) and "stats" in forms[i] and "hp" in forms[i].stats:
			hp = forms[i].stats.hp
	return hp
