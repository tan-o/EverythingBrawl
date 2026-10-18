class_name CharRuntime
extends RefCounted
## 已通过校验的角色包在模拟中的只读视图：按资源取当前形态、按资源取升级后的动作。

var data: Dictionary
var name: String
var anchor: Vector2
var frame_size: Vector2
var move_id := ""
var jump_id := ""
var ult_id := ""
var form_conds := []
var _eff_cache := {}       # 形态掩码 -> effective form
var _action_cache := {}    # "aid|掩码" -> 升级后的动作
var _upgrade_conds := {}   # aid -> [条件]


func _init(validated: Dictionary) -> void:
	data = validated
	name = data.name
	anchor = Vector2(data.anchor[0], data.anchor[1])
	frame_size = Vector2(data.frame_size[0], data.frame_size[1])
	for aid in data.actions:
		var a: Dictionary = data.actions[aid]
		match a.type:
			"move":
				move_id = aid
			"jump":
				jump_id = aid
		if a.get("ultimate", false):
			ult_id = aid
		var conds := []
		for u in a.get("upgrades", []):
			conds.append(u["if"])
		_upgrade_conds[aid] = conds
	for f in data.get("forms", []):
		form_conds.append(f["if"])


func form_mask(values: Dictionary) -> int:
	var m := 0
	for i in form_conds.size():
		if CharDef.cond_true(form_conds[i], values):
			m |= 1 << i
	return m


func form(mask: int) -> Dictionary:
	if not (mask in _eff_cache):
		_eff_cache[mask] = CharDef.effective_form(data, mask)
	return _eff_cache[mask]


func action(aid: String, values: Dictionary) -> Dictionary:
	var conds: Array = _upgrade_conds[aid]
	var m := 0
	for i in conds.size():
		if CharDef.cond_true(conds[i], values):
			m |= 1 << i
	var key := "%s|%d" % [aid, m]
	if not (key in _action_cache):
		var a := CharDef.apply_upgrades(data.actions[aid], m)
		if a.type == "shoot":
			a["_kind"] = CharDef.shoot_kind(a, data.assets)
		_action_cache[key] = a
	return _action_cache[key]


func has_action(aid) -> bool:
	return aid in data.actions


func anim(eff: Dictionary, logical: String):
	return data.anims.get(CharDef.resolve_anim_name(eff, logical))


func asset(n: String) -> Dictionary:
	return data.assets.get(n, {})


## 所有 if 条件（形态 + 升级）的成立情况，用于触发 levelup 动画。
func condition_signature(values: Dictionary) -> int:
	var sig := form_mask(values)
	var bit := form_conds.size()
	for aid in _upgrade_conds:
		for c in _upgrade_conds[aid]:
			if CharDef.cond_true(c, values):
				sig |= 1 << bit
			bit += 1
			if bit > 60:
				return sig
	return sig
