#!/usr/bin/env python3
"""生成 rules/stage.schema.json（场景包结构）。改结构时改这里再运行。"""
import json
import os

NUM = {"type": "number"}
INT = {"type": "integer"}
POS = {"type": "integer", "minimum": 1}
NONNEG = {"type": "integer", "minimum": 0}
STR = {"type": "string", "minLength": 1}


def vec(t=NUM):
    return {"type": "array", "prefixItems": [t, t], "items": False, "minItems": 2}


def obj(props, req):
    return {"type": "object", "required": req, "additionalProperties": False, "properties": props}


KB = obj({"angle": NUM, "force": NUM}, ["angle", "force"])
RECT = {"type": "array", "prefixItems": [NUM, NUM, {"type": "number", "exclusiveMinimum": 0},
                                         {"type": "number", "exclusiveMinimum": 0}], "items": False, "minItems": 4}
TRAP_COMMON = {"type": {"enum": ["shoot", "swing"]}, "origin": vec(), "asset": STR,
               "period": POS, "warn": POS, "offset": NONNEG, "damage": NUM, "knockback": KB, "radius": NUM}
TRAP = {"type": "object", "required": [k for k in TRAP_COMMON if k != "offset"],
        "properties": TRAP_COMMON, "allOf": [
    {"if": {"properties": {"type": {"const": "shoot"}}},
     "then": obj(dict(TRAP_COMMON, angle=NUM, speed=NUM, lifetime=POS), ["angle", "speed", "lifetime"])},
    {"if": {"properties": {"type": {"const": "swing"}}},
     "then": obj(dict(TRAP_COMMON, grip=vec(), length=NUM, active=POS, **{"from": NUM, "to": NUM}), ["grip", "length", "active", "from", "to"])},
]}
ELEMENT = obj({
    "id": STR,
    "rect": RECT,
    "collide": {"enum": ["solid", "platform", "none"]},
    "tile": STR,
    "background_region": {"const": True},
    "trap": TRAP,
    "climb": obj({"max": POS}, ["max"]),
    "crumble": obj({"after": POS, "respawn": POS}, ["after", "respawn"]),
    "bounce": obj({"velocity": NUM}, ["velocity"]),
    "friction": NUM,
    "conveyor": NUM,
    "move": obj({"path": {"type": "array", "items": vec(), "minItems": 2}, "period": POS,
                 "mode": {"enum": ["loop", "pingpong"]}}, ["path", "period"]),
    "damage": obj({"damage": NUM, "interval": POS, "knockback": KB}, ["damage", "interval", "knockback"]),
    "wind": vec(),
    "water": obj({"gravity_mul": NUM, "drag": NUM}, ["gravity_mul", "drag"]),
    "blink": obj({"on": POS, "off": POS, "offset": NONNEG, "warn": NONNEG}, ["on", "off"]),
    "breakable": obj({"hp": NUM, "respawn": POS}, ["hp", "respawn"]),
}, ["rect", "collide"])
ASSET = {"type": "object", "required": ["kind"], "properties": {"kind": {"enum": ["background", "tile", "hazard"]}}, "allOf": [
    {"if": {"properties": {"kind": {"const": "background"}}},
     "then": obj({"kind": {"const": "background"}, "image": STR, "frames": POS,
                  "durations": {"type": "array", "items": INT, "minItems": 1}}, ["kind", "image"])},
    {"if": {"properties": {"kind": {"const": "tile"}}},
     "then": obj({"kind": {"const": "tile"}, "image": STR}, ["kind", "image"])},
    {"if": {"properties": {"kind": {"const": "hazard"}}},
     "then": obj({"kind": {"const": "hazard"}, "image": STR}, ["kind", "image"])},
]}
schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "stage.schema.json",
    "title": "像素大乱斗场景包 stage.json (format 1)",
    "type": "object",
    "required": ["format", "kind", "name", "background", "spawns", "assets", "elements"],
    "additionalProperties": False,
    "properties": {
        "format": {"const": 1},
        "kind": {"const": "stage"},
        "name": {"type": "string", "minLength": 1, "maxLength": 24},
        "background": STR,
        "spawns": {"type": "array", "items": vec(), "minItems": 4, "maxItems": 4},
        "assets": {"type": "object", "additionalProperties": {"$ref": "#/$defs/asset"}},
        "elements": {"type": "array", "items": {"$ref": "#/$defs/element"}, "minItems": 1},
    },
    "$defs": {"element": ELEMENT, "asset": ASSET},
}
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "rules", "stage.schema.json")
json.dump(schema, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
