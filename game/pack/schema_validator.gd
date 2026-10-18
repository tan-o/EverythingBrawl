class_name SchemaValidator
extends RefCounted
## JSON Schema（draft 2020-12）的子集解释器，覆盖 character.schema.json 用到的关键字：
## type properties patternProperties additionalProperties required minProperties items prefixItems
## minItems enum const minimum maximum exclusiveMinimum minLength maxLength pattern $ref allOf if/then/else

var root: Dictionary
var errors: Array = []  # [{path, msg}]
var _regex_cache := {}


func _init(root_schema: Dictionary) -> void:
	root = root_schema


func validate(instance, schema = null) -> Array:
	errors = []
	_check(instance, root if schema == null else schema, "")
	return errors


func _fail(path: String, msg: String) -> void:
	errors.append({"path": path if path != "" else "(root)", "msg": msg})


func _join(path: String, key) -> String:
	return str(key) if path == "" else path + "." + str(key)


func _resolve(ref: String) -> Dictionary:
	# 只支持 "#/$defs/name"
	var parts := ref.trim_prefix("#/").split("/")
	var node = root
	for p in parts:
		node = node[p]
	return node


func _is_valid(instance, schema) -> bool:
	var saved := errors
	errors = []
	_check(instance, schema, "")
	var ok := errors.is_empty()
	errors = saved
	return ok


static func is_number(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func is_integer(v) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and floor(v) == v)


static func json_equal(a, b) -> bool:
	if is_number(a) and is_number(b):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not json_equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not (k in b) or not json_equal(a[k], b[k]):
				return false
		return true
	return a == b


func _type_ok(v, t: String) -> bool:
	match t:
		"object":
			return v is Dictionary
		"array":
			return v is Array
		"string":
			return v is String
		"number":
			return is_number(v)
		"integer":
			return is_integer(v)
		"boolean":
			return typeof(v) == TYPE_BOOL
		"null":
			return v == null
	return false


func _regex(p: String) -> RegEx:
	if not (p in _regex_cache):
		_regex_cache[p] = RegEx.create_from_string(p)
	return _regex_cache[p]


func _check(v, s, path: String) -> void:
	if typeof(s) == TYPE_BOOL:
		if not s:
			_fail(path, "不允许出现该字段")
		return
	if "$ref" in s:
		_check(v, _resolve(s["$ref"]), path)
	if "type" in s:
		if not _type_ok(v, s.type):
			_fail(path, "类型应为 %s" % s.type)
			return
	if "const" in s and not json_equal(v, s.const):
		_fail(path, "值应为 %s" % JSON.stringify(s.const))
	if "enum" in s:
		var found := false
		for e in s.enum:
			if json_equal(v, e):
				found = true
				break
		if not found:
			_fail(path, "值应为 %s 之一" % JSON.stringify(s.enum))
	if is_number(v):
		if "minimum" in s and v < s.minimum:
			_fail(path, "应 ≥ %s" % s.minimum)
		if "maximum" in s and v > s.maximum:
			_fail(path, "应 ≤ %s" % s.maximum)
		if "exclusiveMinimum" in s and v <= s.exclusiveMinimum:
			_fail(path, "应 > %s" % s.exclusiveMinimum)
	if v is String:
		if "minLength" in s and v.length() < s.minLength:
			_fail(path, "长度应 ≥ %d" % s.minLength)
		if "maxLength" in s and v.length() > s.maxLength:
			_fail(path, "长度应 ≤ %d" % s.maxLength)
		if "pattern" in s and _regex(s.pattern).search(v) == null:
			_fail(path, "格式不符合 %s" % s.pattern)
	if v is Array:
		if "minItems" in s and v.size() < s.minItems:
			_fail(path, "至少 %d 项" % s.minItems)
		var start := 0
		if "prefixItems" in s:
			var pi: Array = s.prefixItems
			for i in min(pi.size(), v.size()):
				_check(v[i], pi[i], _join(path, i))
			start = pi.size()
		if "items" in s:
			for i in range(start, v.size()):
				_check(v[i], s.items, _join(path, i))
	if v is Dictionary:
		if "minProperties" in s and v.size() < s.minProperties:
			_fail(path, "至少 %d 个字段" % s.minProperties)
		for r in s.get("required", []):
			if not (r in v):
				_fail(path, "缺少字段 %s" % r)
		var props: Dictionary = s.get("properties", {})
		var pprops: Dictionary = s.get("patternProperties", {})
		for k in v:
			var matched := false
			if k in props:
				matched = true
				_check(v[k], props[k], _join(path, k))
			for p in pprops:
				if _regex(p).search(k) != null:
					matched = true
					_check(v[k], pprops[p], _join(path, k))
			if not matched and "additionalProperties" in s:
				var ap = s.additionalProperties
				if typeof(ap) == TYPE_BOOL and not ap:
					_fail(_join(path, k), "未知字段 %s" % k)
				else:
					_check(v[k], ap, _join(path, k))
	for sub in s.get("allOf", []):
		_check(v, sub, path)
	if "if" in s:
		if _is_valid(v, s["if"]):
			if "then" in s:
				_check(v, s["then"], path)
		elif "else" in s:
			_check(v, s["else"], path)
