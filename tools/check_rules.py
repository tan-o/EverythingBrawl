#!/usr/bin/env python3
"""检查 rules.json 与 character.schema.json 的一致性（CI 运行）。"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "skill", "scripts"))
import validate  # noqa: E402

rules = json.load(open(os.path.join(ROOT, "rules", "rules.json"), encoding="utf-8"))
schema = json.load(open(os.path.join(ROOT, "rules", "character.schema.json"), encoding="utf-8"))
defs = schema["$defs"]
bad = []


def check(cond, msg):
    if not cond:
        bad.append(msg)


check(schema["properties"]["format"]["const"] == rules["format"], "format 不一致")
check(sorted(defs["status"]["properties"]["type"]["enum"]) == sorted(rules["limits"]["status"]),
      "状态类型：schema 与 rules.limits.status 不一致")
when = set(defs["link"]["properties"]["when"]["enum"])
check(when == set(validate.ACTION_WHEN) | set(validate.BULLET_WHEN) | set(validate.CHAR_WHEN),
      "联动触发：schema 与校验器的 when 集合不一致")
types = set(defs["action"]["properties"]["type"]["enum"])
check(types == {"move", "jump", "fly", "swing", "shoot", "pose"}, "动作类型集合变化，需要同步校验器")
for a in rules["reserved_resources"]:
    check(a not in ("", None), "保留资源名为空")
lim = rules["limits"]
for group in ("stats", "move", "jump", "fly"):
    for k, v in lim[group].items():
        if isinstance(v, list):
            check(len(v) == 2 and v[0] <= v[1], "limits.%s.%s 不是 [下限, 上限]" % (group, k))
        else:
            check(isinstance(v, (int, float)) and v > 0, "limits.%s.%s 应为正数" % (group, k))
check(sorted(json.load(open(os.path.join(ROOT, "rules", "stage.schema.json"), encoding="utf-8"))["$defs"]["element"]["properties"])
      == sorted(["id", "rect", "collide", "tile", "background_region", "trap", "climb", "crumble", "bounce", "friction", "conveyor", "move", "damage",
                 "wind", "water", "blink", "breakable"]), "场景元素字段变化，需要同步校验器与运行时")
check(set(lim["stats"]) == {"hp", "body_w", "body_h", "weight", "gravity", "max_fall", "air_control"},
      "limits.stats 与 schema stats 字段不一致")
check(set(defs["form"]["properties"]["stats"]["properties"]) == set(schema["properties"]["stats"]["properties"]),
      "forms.stats 与 stats 字段不一致")
check(rules["points"]["form_max"] > 0 and rules["points"]["action_max"] > 0, "点数上限必须为正")

if bad:
    print("\n".join(bad))
    sys.exit(1)
print("rules / schema 一致")
