class_name CharDef
extends RefCounted
## 角色包数据模型的公共规则：条件、形态、升级、联动归属、子弹分类。
## 校验器（pack/）与模拟（core/）共用，保证两边对同一份 character.json 的解释一致。

const ATTACK_TYPES := ["swing", "shoot"]
const REQUIRED_ANIMS := ["idle", "walk", "jump", "fall", "land", "hurt", "guard", "ko"]
const OPTIONAL_ANIMS := ["entrance", "victory", "levelup", "run", "dodge", "cling"]
const BULLET_WHEN := ["on_frame", "every", "projectile_hit", "projectile_expire"]
const ACTION_WHEN := ["on_start", "on_end", "on_frame", "every", "on_hit", "on_whiff", "on_land", "on_release", "on_hurt"]
const CHAR_WHEN := ["every", "on_land", "on_hurt", "resource_empty", "resource_full"]

static var _cond_re: RegEx


static func parse_cond(s: String) -> Array:
	if _cond_re == null:
		_cond_re = RegEx.create_from_string("^(>=|<=|==|>|<)\\s*(-?[0-9]+(?:\\.[0-9]+)?)$")
	var m := _cond_re.search(s.strip_edges())
	return [m.get_string(1), float(m.get_string(2))]


static func cmp(v: float, op: String, t: float) -> bool:
	match op:
		">=":
			return v >= t
		"<=":
			return v <= t
		"==":
			return v == t
		">":
			return v > t
	return v < t


static func cond_true(cond: Dictionary, values: Dictionary) -> bool:
	for res in cond:
		var c := parse_cond(cond[res])
		if not cmp(float(values.get(res, 0.0)), c[0], c[1]):
			return false
	return true


static func resource_domains(data: Dictionary) -> Dictionary:
	var d := {"ult": float(Rules.data().combat.ult.max)}
	var res: Dictionary = data.get("resources", {})
	for name in res:
		d[name] = float(res[name].max)
	return d


## 所有可能同时成立的条件组合（位掩码），每个资源在 [0, max] 上取值。
static func feasible_masks(conds: Array, domains: Dictionary) -> Array:
	var n := conds.size()
	var states := {((1 << n) - 1): true}
	var names := {}
	for c in conds:
		for r in c:
			if r in domains:
				names[r] = true
	var sorted_names := names.keys()
	sorted_names.sort()
	for res in sorted_names:
		var hi := float(domains[res])
		var pts := {0.0: true, hi: true}
		for c in conds:
			if res in c:
				var t: float = parse_cond(c[res])[1]
				if t >= 0.0 and t <= hi:
					pts[t] = true
		var pl := pts.keys()
		pl.sort()
		var cands := pl.duplicate()
		for i in range(pl.size() - 1):
			cands.append((pl[i] + pl[i + 1]) / 2.0)
		var new_states := {}
		for st in states:
			for v in cands:
				var m: int = st
				for i in n:
					var c: Dictionary = conds[i]
					if res in c:
						var pc := parse_cond(c[res])
						if not cmp(v, pc[0], pc[1]):
							m &= ~(1 << i)
				new_states[m] = true
		states = new_states
	var out := states.keys()
	out.sort()
	return out


static func mask_label(mask: int, n: int) -> String:
	var bits := PackedStringArray()
	for i in n:
		if mask & (1 << i):
			bits.append(str(i))
	return "+".join(bits) if bits.size() > 0 else "base"


## 按形态位掩码叠加后的 held / anims 映射 / stats / input。
static func effective_form(data: Dictionary, mask: int) -> Dictionary:
	var eff := {
		"held": data.get("held"),
		"held_socket": data.get("held_socket", "hand"),
		"anims": {},
		"stats": data.stats.duplicate(true),
		"input": data.input.duplicate(),
	}
	var forms: Array = data.get("forms", [])
	for i in forms.size():
		if not mask & (1 << i):
			continue
		var f: Dictionary = forms[i]
		if "held_socket" in f:
			eff.held_socket = f.held_socket
		if "held" in f:
			eff.held = f.held
		eff.anims.merge(f.get("anims", {}), true)
		eff.stats.merge(f.get("stats", {}), true)
		eff.input.merge(f.get("input", {}), true)
	return eff


static func apply_upgrades(action: Dictionary, mask: int) -> Dictionary:
	var a := action.duplicate()
	var ups: Array = action.get("upgrades", [])
	for i in ups.size():
		if mask & (1 << i):
			a.merge(ups[i].set, true)
	return a


static func all_upgrades(action: Dictionary) -> Dictionary:
	return apply_upgrades(action, (1 << action.get("upgrades", []).size()) - 1)


static func upgrade_count(action: Dictionary) -> int:
	return action.get("upgrades", []).size()


static func action_links(a: Dictionary) -> Array:
	var out := []
	for l in a.get("links", []):
		if a.type != "shoot" or not (l.when in BULLET_WHEN):
			out.append(l)
	return out


static func bullet_links(a: Dictionary) -> Array:
	var out := []
	if a.type != "shoot":
		return out
	for l in a.get("links", []):
		if l.when in BULLET_WHEN:
			out.append(l)
	return out


## beam / deployable / bullet，由参数自动判定。
static func shoot_kind(a: Dictionary, assets: Dictionary) -> String:
	var proj: Dictionary = assets.get(a.get("projectile", ""), {})
	if a.get("attach", false) and proj.get("shape") == "rect":
		return "beam"
	if a.get("speed", 0) == 0 or a.get("solid", false):
		return "deployable"
	for l in bullet_links(a):
		if l.when == "every":
			return "deployable"
	return "bullet"


static func resolve_anim_name(eff: Dictionary, name: String) -> String:
	return eff.anims.get(name, name)


static func resolve_anim(data: Dictionary, eff: Dictionary, name: String):
	return data.anims.get(resolve_anim_name(eff, name))


static func action_frames(a: Dictionary, data: Dictionary, eff: Dictionary) -> int:
	var t: String = a.type
	if t in ATTACK_TYPES:
		return int(a.startup + a.active + a.recovery)
	if t == "pose":
		var anim = resolve_anim(data, eff, a.anim)
		if anim == null:
			return 0
		var s := 0
		for du in anim.get("durations", []):
			s += int(du)
		return s
	if t == "fly":
		return int(a.duration)
	return 0


static func span_len(r: Array) -> int:
	return int(r[1] - r[0] + 1)


## 有 charge 字段或 on_release 联动的动作需要 charge 动画。
static func needs_charge_anim(a: Dictionary) -> bool:
	if "charge" in a:
		return true
	for l in a.get("links", []):
		if l.when == "on_release":
			return true
	return false


## Frame-local point. Animated socket overrides static defaults; hand is a legacy alias.
static func socket_at(data: Dictionary, anim, index: int, socket := "hand"):
	if anim != null:
		var points: Array = anim.get("sockets", {}).get(socket, anim.get("hand", []) if socket == "hand" else [])
		if not points.is_empty():
			return points[clampi(index, 0, points.size() - 1)]
	return data.get("sockets", {}).get(socket)
