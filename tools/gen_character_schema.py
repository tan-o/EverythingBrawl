"""生成 rules/character.schema.json（角色包结构）。改结构时改这里再运行。"""
import json
import os
INT = {"type": "integer"}
NUM = {"type": "number"}
STR = {"type": "string", "minLength": 1}
BOOL = {"type": "boolean"}
POS = {"type": "integer", "minimum": 1}
NONNEG = {"type": "integer", "minimum": 0}
POSNUM = {"type": "number", "exclusiveMinimum": 0}
def vec(t=NUM): return {"type": "array", "prefixItems": [t, t], "items": False, "minItems": 2}
RANGE = vec(INT)
COND = {"type": "object", "minProperties": 1,
        "additionalProperties": {"type": "string", "pattern": "^(>=|<=|==|>|<)\\s*-?[0-9]+(\\.[0-9]+)?$"}}
AMOUNTS = {"type": "object", "minProperties": 1, "additionalProperties": NUM}
KB = {"type": "object", "required": ["angle", "force"], "additionalProperties": False,
      "properties": {"angle": NUM, "force": NUM}}
STATUS_TYPES = ["burn", "slow", "stun", "root", "silence"]
status_req = {"burn": ["damage", "interval", "duration"], "slow": ["factor", "duration"],
              "stun": ["duration"], "root": ["duration"], "silence": ["duration"]}
STATUS = {"type": "object", "required": ["type", "duration"], "additionalProperties": False,
          "properties": {"type": {"enum": STATUS_TYPES}, "damage": NUM, "interval": POS,
                         "duration": POS, "factor": NUM},
          "allOf": [{"if": {"properties": {"type": {"const": t}}},
                     "then": {"required": r, "properties": {k: False for k in ["damage", "interval", "factor"] if k not in r}}}
                    for t, r in status_req.items()]}
WHEN = ["on_start", "on_end", "on_frame", "every", "on_hit", "on_whiff", "on_land", "on_release", "on_hurt",
        "projectile_hit", "projectile_expire", "resource_empty", "resource_full"]
LINK = {"type": "object", "required": ["when"], "additionalProperties": False,
        "properties": {"when": {"enum": WHEN}, "frame": NONNEG, "interval": POS, "resource": STR,
                       "input": {"type": "string", "pattern": "^(attack|special|jump|guard)(\\.(neutral|side|up|down))?$"}, "window": RANGE,
                       "if": {"$ref": "#/$defs/cond"}, "require": {"enum": ["ground", "air", "any"]},
                       "goto": STR, "spawn": STR, "gain": {"$ref": "#/$defs/amounts"},
                       "spend": {"$ref": "#/$defs/amounts"}, "set": {"$ref": "#/$defs/amounts"},
                       "heal": NUM, "warp": {"const": "projectile"}, "fx": STR, "sfx": STR},
        "allOf": [
            {"if": {"properties": {"when": {"const": "on_frame"}}}, "then": {"required": ["frame"]}, "else": {"properties": {"frame": False}}},
            {"if": {"properties": {"when": {"const": "every"}}}, "then": {"required": ["interval"]}, "else": {"properties": {"interval": False}}},
            {"if": {"properties": {"when": {"enum": ["resource_empty", "resource_full"]}}}, "then": {"required": ["resource"]}, "else": {"properties": {"resource": False}}},
        ]}
COMMON = {"type": None, "anim": STR, "require": {"enum": ["ground", "air", "any"]},
          "cost": {"$ref": "#/$defs/amounts"}, "cooldown": NONNEG,
          "upgrades": {"type": "array", "items": {"type": "object", "required": ["if", "set"], "additionalProperties": False,
                                                  "properties": {"if": {"$ref": "#/$defs/cond"},
                                                                 "set": {"type": "object", "properties": {"type": False}}}}},
          "links": {"type": "array", "items": {"$ref": "#/$defs/link"}},
          "motion": {"type": "array", "items": {"type": "object", "required": ["frame", "vel"], "additionalProperties": False,
                                                "properties": {"frame": NONNEG, "vel": vec(), "mode": {"enum": ["set", "add"]}}}},
          "gravity_scale": NUM, "armor": RANGE, "invuln": RANGE, "reflect": RANGE,
          "sfx": {"type": "object", "additionalProperties": False, "properties": {"start": STR, "hit": STR}},
          "ultimate": BOOL}
ATTACK = {"startup": POS, "active": POS, "recovery": POS, "damage": NUM, "knockback": KB, "hit_interval": NONNEG,
          "status": {"$ref": "#/$defs/status"},
          "charge": {"type": "object", "required": ["max", "damage", "force"], "additionalProperties": False,
                     "properties": {"max": POS, "damage": NUM, "force": NUM}},
          "area": {"const": "screen"}, "backdrop": STR}
ATTACK_REQ = ["anim", "startup", "active", "recovery", "damage", "knockback"]
TYPES = {
    "move": ({"speed": NUM, "accel": NUM}, ["speed", "accel"]),
    "jump": ({"velocity": NUM, "max_count": POS, "extra_anim": STR}, ["velocity", "max_count"]),
    "fly": ({"duration": POS, "rise_speed": NUM, "control": NUM, "recharge": {"const": "on_land"}}, ["duration", "rise_speed", "control"]),
    "swing": (dict(ATTACK, weapon=STR, **{"from": NUM, "to": NUM}, reach=vec(), grab=BOOL), ATTACK_REQ + ["weapon", "from", "to", "reach"]),
    "shoot": (dict(ATTACK, projectile=STR, weapon=STR, aim={"enum": ["fixed", "input", "steer"]}, angle=NUM, turn_rate=NUM,
                   speed={"type": "number", "minimum": 0}, count=POS, spread=NUM, lifetime=POS, gravity=NUM, attach=BOOL, grow=NONNEG, pierce={"type": "integer", "minimum": -1},
                   scale_over_life=vec(), solid=BOOL, **{"return": BOOL}, hp=INT),
              ATTACK_REQ + ["projectile", "aim", "angle", "speed", "lifetime"]),
    "pose": ({"throw": {"type": "object", "required": ["frame", "damage", "knockback"], "additionalProperties": False,
                        "properties": {"frame": NONNEG, "damage": NUM, "knockback": KB}}}, ["anim"]),
}
action_branches = []
for t, (props, req) in TYPES.items():
    p = dict(COMMON); p.update(props); p["type"] = {"const": t}
    action_branches.append({"if": {"properties": {"type": {"const": t}}},
                            "then": {"required": req, "additionalProperties": False, "properties": p}})
ACTION = {"type": "object", "required": ["type"], "properties": {"type": {"enum": list(TYPES)}}, "allOf": action_branches}
SFX_KEYS = ["p_env_attack", "p_env_sustain", "p_env_punch", "p_env_decay", "p_base_freq", "p_freq_limit", "p_freq_ramp",
            "p_freq_dramp", "p_vib_strength", "p_vib_speed", "p_arp_mod", "p_arp_speed", "p_duty", "p_duty_ramp",
            "p_repeat_speed", "p_pha_offset", "p_pha_ramp", "p_lpf_freq", "p_lpf_ramp", "p_lpf_resonance",
            "p_hpf_freq", "p_hpf_ramp", "sound_vol"]
SIGNED = {"p_freq_ramp", "p_freq_dramp", "p_arp_mod", "p_duty_ramp", "p_pha_offset", "p_pha_ramp", "p_lpf_ramp", "p_hpf_ramp"}
sfx_props = {k: {"type": "number", "minimum": -1 if k in SIGNED else 0, "maximum": 1} for k in SFX_KEYS}
sfx_props["wave_type"] = {"enum": [0, 1, 2, 3]}
sfx_props["sample_rate"] = {"enum": [44100, 22050, 11025, 5512]}
sfx_props["sample_size"] = {"enum": [8, 16]}
ASSET_KINDS = {
    "weapon": ({"image": STR, "grip": vec(), "length": NUM, "radius": NUM, "hit_range": vec()}, ["image", "grip", "length", "radius", "hit_range"]),
    "projectile": ({"image": STR, "shape": {"enum": ["circle", "rect"]}, "size": vec(POSNUM), "tile": {"const": "repeat_x"}}, ["image", "shape", "size"]),
    "fx": ({"image": STR, "frames": POS, "durations": {"type": "array", "items": INT, "minItems": 1}}, ["image", "frames", "durations"]),
    "icon": ({"image": STR}, ["image"]),
    "backdrop": ({"image": STR, "frames": POS, "durations": {"type": "array", "items": INT, "minItems": 1}}, ["image"]),
    "sfx": ({"params": {"type": "object", "additionalProperties": False, "properties": sfx_props}}, ["params"]),
}
asset_branches = []
for k, (props, req) in ASSET_KINDS.items():
    p = dict(props); p["kind"] = {"const": k}
    asset_branches.append({"if": {"properties": {"kind": {"const": k}}},
                           "then": {"required": req, "additionalProperties": False, "properties": p}})
ASSET = {"type": "object", "required": ["kind"], "properties": {"kind": {"enum": list(ASSET_KINDS)}}, "allOf": asset_branches}
STATS_PROPS = {"hp": NUM, "body": vec(POS), "weight": NUM, "gravity": NUM, "max_fall": NUM, "air_control": NUM}
INPUT = {"type": "object", "additionalProperties": False,
         "patternProperties": {"^((attack|special)\\.(neutral|side|up|down)(\\.air)?|attack\\.dash|grab|jump)$": STR}}
ANIM = {"type": "object", "required": ["frames"], "additionalProperties": False,
        "properties": {"frames": {"type": "array", "items": {"type": "integer", "minimum": 0}, "minItems": 1},
                       "durations": {"type": "array", "items": INT, "minItems": 1}, "loop": BOOL,
                       "hold": {"type": "integer", "minimum": 0},
                       "hand": {"type": "array", "items": vec()}}}
RESOURCE = {"type": "object", "required": ["init", "max"], "additionalProperties": False,
            "properties": {"init": NUM, "max": POSNUM, "regen": NUM, "wrap": BOOL, "keep_on_ko": BOOL, "hud": STR}}
FORM = {"type": "object", "required": ["if"], "additionalProperties": False,
        "properties": {"if": {"$ref": "#/$defs/cond"}, "held": STR,
                       "anims": {"type": "object", "additionalProperties": STR},
                       "stats": {"type": "object", "additionalProperties": False, "properties": STATS_PROPS},
                       "input": {"$ref": "#/$defs/input"}}}
schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "character.schema.json",
    "title": "像素大乱斗角色包 character.json (format 1)",
    "type": "object",
    "required": ["format", "name", "frame_size", "anchor", "stats", "assets", "anims", "actions", "input"],
    "additionalProperties": False,
    "properties": {
        "format": {"const": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 24},
        "frame_size": vec(POS), "anchor": vec(INT),
        "stats": {"type": "object", "required": list(STATS_PROPS), "additionalProperties": False, "properties": STATS_PROPS},
        "held": STR,
        "resources": {"type": "object", "additionalProperties": {"$ref": "#/$defs/resource"}},
        "assets": {"type": "object", "additionalProperties": {"$ref": "#/$defs/asset"}},
        "anims": {"type": "object", "additionalProperties": {"$ref": "#/$defs/anim"}},
        "forms": {"type": "array", "items": {"$ref": "#/$defs/form"}},
        "actions": {"type": "object", "minProperties": 1, "additionalProperties": {"$ref": "#/$defs/action"}},
        "links": {"type": "array", "items": {"$ref": "#/$defs/link"}},
        "input": {"$ref": "#/$defs/input"},
    },
    "$defs": {"cond": COND, "amounts": AMOUNTS, "status": STATUS, "link": LINK, "action": ACTION, "asset": ASSET,
              "anim": ANIM, "resource": RESOURCE, "form": FORM, "input": INPUT},
}
json.dump(schema, open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "rules", "character.schema.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
