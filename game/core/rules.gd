class_name Rules
extends RefCounted
## rules.json（由 tools/sync_rules.py 从 /rules 复制）是全部平衡数值的唯一来源。

const RULES_PATH := "res://data/rules.json"
const SCHEMA_PATH := "res://data/character.schema.json"
const STAGE_SCHEMA_PATH := "res://data/stage.schema.json"

static var _rules: Dictionary
static var _schema: Dictionary
static var _stage_schema: Dictionary


static func data() -> Dictionary:
	if _rules.is_empty():
		_rules = _load(RULES_PATH)
	return _rules


static func schema() -> Dictionary:
	if _schema.is_empty():
		_schema = _load(SCHEMA_PATH)
	return _schema


static func stage_schema() -> Dictionary:
	if _stage_schema.is_empty():
		_stage_schema = _load(STAGE_SCHEMA_PATH)
	return _stage_schema


static func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(text)
	assert(v is Dictionary, "无法读取 " + path)
	return v
