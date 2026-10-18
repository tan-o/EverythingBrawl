class_name Stage
extends RefCounted
## 场景运行时：元素位置（移动）、出现/消失（blink）、碎裂（crumble）、可破坏（breakable）。
## 物理碰撞与区域效果由 MatchSim 查询这里的当前状态。

var data: Dictionary
var name := ""
var spawns: Array = []
var els: Array = []     # 每项：{def, rect, delta, present, warn, stand, broken, hp, shake}
var t := 0


func _init(validated: Dictionary) -> void:
	data = validated
	name = data.name
	for s in data.spawns:
		spawns.append(Vector2(s[0], s[1]))
	for el in data.elements:
		var e := {
			"def": el, "rect": StageDef.rect(el), "delta": Vector2.ZERO, "present": true, "warn": false,
			"stand": 0, "broken": 0, "hp": float(el.get("breakable", {}).get("hp", 0)),
		}
		e.rect.position += StageDef.offset_at(el, 0)
		els.append(e)
	_update_blink()


func step() -> Array:
	## 推进一帧，返回本帧事件（碎裂、恢复）。
	var events := []
	t += 1
	for i in els.size():
		var e: Dictionary = els[i]
		var el: Dictionary = e.def
		if "move" in el:
			var np: Vector2 = Vector2(el.rect[0], el.rect[1]) + StageDef.offset_at(el, t)
			e.delta = np - e.rect.position
			e.rect.position = np
		if e.broken > 0:
			e.broken -= 1
			if e.broken == 0:
				e.stand = 0
				e.hp = float(el.get("breakable", {}).get("hp", 0))
				events.append({"t": "stage_restore", "el": i})
		elif "crumble" in el and e.stand >= int(el.crumble.after):
			e.broken = int(el.crumble.respawn)
			events.append({"t": "stage_break", "el": i, "x": e.rect.get_center().x, "y": e.rect.get_center().y})
	_update_blink()
	return events


func _update_blink() -> void:
	for e in els:
		var el: Dictionary = e.def
		var on := true
		e.warn = false
		if "blink" in el:
			var b: Dictionary = el.blink
			var period := int(b.on) + int(b.off)
			var ph := (t + int(b.get("offset", 0))) % period
			on = ph < int(b.on)
			e.warn = not on and ph >= period - int(b.get("warn", 0))
		e.present = on and e.broken == 0


## 被站立一帧（碎裂计时）。
func stood_on(i: int) -> void:
	els[i].stand += 1


## 被攻击（任何人的攻击都算，包括自己的）。可破坏元素扣血；会碎的元素按伤害推进碎裂进度。
## 返回是否被打碎。
func damage(i: int, amount: float) -> bool:
	var e: Dictionary = els[i]
	if not e.present:
		return false
	if "breakable" in e.def:
		e.hp -= amount
		if e.hp <= 0:
			e.broken = int(e.def.breakable.respawn)
			e.present = false
			return true
	elif "crumble" in e.def:
		e.stand += int(ceil(amount * float(Rules.data().stage.crumble_frames_per_damage)))
		if e.stand >= int(e.def.crumble.after):
			e.broken = int(e.def.crumble.respawn)
			e.present = false
			return true
	return false


## 能被攻击打到的元素（可破坏 / 会碎）。
static func hittable(el: Dictionary) -> bool:
	return "breakable" in el or "crumble" in el


func colliders() -> Array:
	var out := []
	for i in els.size():
		var e: Dictionary = els[i]
		if e.present and e.def.collide != "none":
			out.append(i)
	return out


func zones() -> Array:
	var out := []
	for i in els.size():
		var e: Dictionary = els[i]
		if e.present and ("wind" in e.def or "water" in e.def or "damage" in e.def):
			out.append(i)
	return out


func snapshot() -> Array:
	var out := []
	for e in els:
		var el: Dictionary = e.def
		var crack := 0.0
		if "crumble" in el:
			crack = clamp(float(e.stand) / el.crumble.after, 0.0, 1.0)
		elif "breakable" in el:
			crack = 1.0 - clamp(e.hp / float(el.breakable.hp), 0.0, 1.0)
		out.append([e.rect.position.x, e.rect.position.y, e.present, e.warn, crack])
	return out
