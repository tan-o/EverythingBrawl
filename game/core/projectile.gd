class_name Projectile
extends RefCounted
## 场上的子弹 / 光束 / 布置物（类别由 CharDef.shoot_kind 自动判定）。

var id := 0
var owner := 0           # 发射者下标（反射后改变）
var kind := "bullet"     # bullet / beam / deployable
var asset := ""
var shape := "circle"
var size := Vector2.ONE  # [w, h]：circle 时 w = 直径；rect 时 w 沿飞行方向
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var dir := Vector2.RIGHT # 世界方向
var fang := 0.0          # 附着时的朝向空间角度（度）
var facing := 1          # 击退镜像所用朝向
var speed := 0.0
var age := 0
var lifetime := 1
var damage := 0.0
var kb_angle := 0.0
var kb_force := 0.0
var hit_interval := 0
var status = null
var pierce := 0
var hits := {}           # 目标键 -> 最后命中帧
var hp := 0.0
var attach := false
var offset := Vector2.ZERO  # 附着偏移（朝向空间）
var grow := 0
var scale_from := 1.0
var scale_to := 1.0
var solid := false
var returns := false
var returning := false
var gravity := 0.0
var turn_rate := 0.0
var steer := false
var links := []
var inst := -1           # 发射它的动作实例（用于动作级 on_hit）
var ult := false
var screen := false
var sfx_hit := ""
var action_id := ""
var dead := false
var max_scale := 1.0


func scale() -> float:
	return lerp(scale_from, scale_to, clamp(float(age) / max(1, lifetime), 0.0, 1.0))


func length() -> float:
	var l := size.x * scale()
	if grow > 0 and shape == "rect":
		l *= clamp(float(age) / grow, 0.0, 1.0)
	return l


func hit_shape() -> Dictionary:
	var s := scale()
	if shape == "circle":
		return Geom.circle(pos, size.x * s / 2.0)
	var l := length()
	var h := size.y * s
	if kind == "beam":
		return Geom.obb(pos + dir * (l / 2.0), Vector2(l / 2.0, h / 2.0), dir.angle())
	return Geom.obb(pos, Vector2(l / 2.0, h / 2.0), dir.angle())


func full_area() -> float:
	var m := max_scale
	if shape == "circle":
		return PI * pow(size.x * m / 2.0, 2)
	return size.x * m * size.y * m


func current_area() -> float:
	return Geom.area(hit_shape())


## solid 布置物的顶面（单向平台）。
func top_rect() -> Rect2:
	var s := scale()
	var w := size.x * s
	var h := size.y * s
	return Rect2(pos.x - w / 2.0, pos.y - h / 2.0, w, h)
