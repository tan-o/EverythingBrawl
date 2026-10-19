#!/usr/bin/env python3
"""生成场景包一致性用例（conformance/packs/stage_*.zip），期望结果并入 expected.json。

每个违规包由同一个合法基准场景做一处修改得到，期望错误码在这里手写。
"""
import copy
import io
import json
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "skill", "scripts"))
from PIL import Image  # noqa: E402
from pixel import blank, rect  # noqa: E402

OUT = os.path.join(ROOT, "conformance", "packs")
EXPECTED = os.path.join(ROOT, "conformance", "expected.json")


def bg(w=240, h=135, colors=4):
    im = blank(w, h)
    for y in range(h):
        c = (30 + (y * colors // h) * 9 % 200, 40, 80, 255)
        for x in range(w):
            im.putpixel((x, y), c)
    return im


def tile(w=16, h=16, color="#8f563b"):
    return rect(blank(w, h), 0, 0, w - 1, h - 1, color)


def base():
    d = {
        "format": 1, "kind": "stage", "name": "Base",
        "background": "bg",
        "spawns": [[120, 200], [200, 200], [280, 200], [360, 200]],
        "assets": {"bg": {"kind": "background", "image": "bg.png"},
                   "ground": {"kind": "tile", "image": "ground.png"},
                   "plank": {"kind": "tile", "image": "plank.png"}},
        "elements": [
            {"id": "main", "rect": [80, 200, 320, 40], "collide": "solid", "tile": "ground"},
            {"id": "left", "rect": [124, 166, 72, 4], "collide": "platform", "tile": "plank"},
            {"id": "right", "rect": [284, 166, 72, 4], "collide": "platform", "tile": "plank"},
        ],
    }
    imgs = {"bg.png": bg(), "ground.png": tile(), "plank.png": tile(16, 4, "#d9a066")}
    return d, imgs


class Case:
    def __init__(self):
        self.d, self.imgs = base()
        self.raw = {}

    @property
    def els(self):
        return self.d["elements"]


CASES = []


def case(name, codes):
    def deco(fn):
        CASES.append(("stage_" + name, fn, codes))
        return fn
    return deco


def add(c, **el):
    e = {"rect": [200, 120, 64, 4], "collide": "platform", "tile": "plank"}
    e.update(el)
    c.els.append(e)
    return e


@case("valid_base", [])
def _(c):
    pass


@case("valid_full", [])
def _(c):
    c.imgs["bg.png"] = bg(480, 270)
    add(c, id="box", rect=[40, 150, 24, 50], collide="solid", tile="ground", climb={"max": 90})
    c.els[0]["rect"] = [64, 200, 352, 40]
    add(c, id="crack", rect=[200, 134, 80, 4], crumble={"after": 60, "respawn": 240})
    add(c, id="spring", rect=[408, 192, 8, 8], collide="solid", bounce={"velocity": 8})
    add(c, id="ice", rect=[300, 196, 40, 4], collide="platform", friction=0.3)
    add(c, id="belt", rect=[90, 196, 40, 4], collide="platform", conveyor=1)
    add(c, id="lift", rect=[20, 120, 40, 4], move={"path": [[0, 0], [0, 40]], "period": 120, "mode": "pingpong"})
    add(c, id="stove", rect=[222, 192, 20, 8], collide="none", damage={"damage": 5, "interval": 60,
        "knockback": {"angle": 80, "force": 40}}, blink={"on": 120, "off": 180, "warn": 40})
    add(c, id="fan", rect=[400, 60, 60, 100], collide="none", wind=[-0.1, 0])
    add(c, id="sink", rect=[0, 230, 60, 30], collide="none", water={"gravity_mul": 0.5, "drag": 0.9})
    add(c, id="jar", rect=[180, 176, 16, 24], collide="solid", breakable={"hp": 20, "respawn": 300})
    c.d["spawns"] = [[100, 200], [160, 200], [290, 200], [360, 200]]


@case("pack_files", ["pack.files"])
def _(c):
    c.raw["readme.txt"] = b"x"


@case("format", ["format"])
def _(c):
    c.d["format"] = 2


@case("schema", ["schema"])
def _(c):
    c.els[0]["collide"] = "wall"


@case("schema_spawns", ["schema"])
def _(c):
    c.d["spawns"].pop()


@case("ref_tile", ["ref"])
def _(c):
    c.els[1]["tile"] = "bg"


@case("ref_background", ["ref"])
def _(c):
    c.d["background"] = "ground"


@case("ref_image", ["ref"])
def _(c):
    c.d["assets"]["plank"]["image"] = "nope.png"


@case("zip_bytes", ["stage.zip_bytes"])
def _(c):
    import random
    rnd = random.Random(1)
    im = Image.new("RGBA", (3000, 3000))
    im.putdata([(255, 255, 255, 255) if rnd.random() < 0.5 else (0, 0, 0, 255) for _ in range(3000 * 3000)])
    c.imgs["noise.png"] = im


@case("colors", ["stage.colors"])
def _(c):
    c.imgs["bg.png"] = bg(colors=70)


@case("alpha", ["pack.alpha"])
def _(c):
    c.imgs["plank.png"].putpixel((1, 1), (10, 10, 10, 100))


@case("tile_side", ["stage.tile_side"])
def _(c):
    c.imgs["ground.png"] = tile(70, 16)


@case("background_size", ["stage.background_size"])
def _(c):
    c.imgs["bg.png"] = bg(200, 100)


@case("background_frames", ["stage.background_frames"])
def _(c):
    c.d["assets"]["bg"]["frames"] = 2
    c.d["assets"]["bg"]["durations"] = [10]
    c.imgs["bg.png"] = bg(480, 135)


@case("elements", ["stage.elements"])
def _(c):
    for i in range(38):
        add(c, rect=[100 + (i % 10) * 28, 166 - 30 * (i // 10) - 4, 20, 4])
    c.els[3:] = [e for e in c.els[3:]]


@case("invisible", ["stage.invisible"])
def _(c):
    del c.els[1]["tile"]


@case("bounds", ["stage.bounds"])
def _(c):
    add(c, rect=[470, 160, 40, 4])


@case("bounds_move", ["stage.bounds"])
def _(c):
    add(c, rect=[200, 130, 40, 4], move={"path": [[0, 0], [0, -140]], "period": 600})


@case("behavior_climb", ["stage.behavior"])
def _(c):
    c.els[1]["climb"] = {"max": 60}


@case("behavior_zone", ["stage.behavior"])
def _(c):
    c.els[1]["wind"] = [0.1, 0]


@case("behavior_none", ["stage.behavior"])
def _(c):
    add(c, rect=[200, 100, 40, 40], collide="none", bounce={"velocity": 6})


@case("climb_max", ["stage.climb_max"])
def _(c):
    add(c, rect=[40, 150, 24, 50], collide="solid", tile="ground", climb={"max": 200})
    c.els[0]["rect"] = [64, 200, 352, 40]


@case("crumble_after", ["stage.crumble_after"])
def _(c):
    c.els[1]["crumble"] = {"after": 10, "respawn": 120}


@case("respawn", ["stage.respawn"])
def _(c):
    c.els[1]["crumble"] = {"after": 60, "respawn": 30}


@case("breakable_hp", ["stage.breakable_hp"])
def _(c):
    c.els[1]["breakable"] = {"hp": 100, "respawn": 200}


@case("bounce", ["stage.bounce"])
def _(c):
    c.els[1]["bounce"] = {"velocity": 12}


@case("friction", ["stage.friction"])
def _(c):
    c.els[1]["friction"] = 0.1


@case("conveyor", ["stage.conveyor"])
def _(c):
    c.els[1]["conveyor"] = 2


@case("move_points", ["stage.move_points"])
def _(c):
    c.els[1]["move"] = {"path": [[0, i % 2] for i in range(9)], "period": 600}


@case("move_period", ["stage.move_period"])
def _(c):
    c.els[1]["move"] = {"path": [[0, 0], [0, 4]], "period": 30}


@case("move_speed", ["stage.move_speed"])
def _(c):
    c.els[1]["move"] = {"path": [[0, 0], [0, -80]], "period": 60, "mode": "pingpong"}


def hazard(c, **kw):
    d = {"damage": 5, "interval": 60, "knockback": {"angle": 80, "force": 40}}
    d.update(kw)
    return add(c, rect=[230, 100, 20, 8], collide="none", damage=d)


@case("damage", ["stage.damage"])
def _(c):
    hazard(c, damage=11)


@case("damage_interval", ["stage.damage_interval"])
def _(c):
    hazard(c, interval=10)


@case("damage_force", ["stage.damage_force"])
def _(c):
    hazard(c, knockback={"angle": 80, "force": 70})


@case("damage_count", ["stage.damage_count"])
def _(c):
    for i in range(7):
        add(c, rect=[100 + i * 40, 60, 10, 8], collide="none",
            damage={"damage": 3, "interval": 60, "knockback": {"angle": 90, "force": 20}})


@case("wind", ["stage.wind"])
def _(c):
    add(c, rect=[200, 40, 60, 60], collide="none", wind=[0.2, 0])


@case("water_gravity", ["stage.water_gravity"])
def _(c):
    add(c, rect=[200, 40, 60, 60], collide="none", water={"gravity_mul": 0.1, "drag": 0.9})


@case("water_drag", ["stage.water_drag"])
def _(c):
    add(c, rect=[200, 40, 60, 60], collide="none", water={"gravity_mul": 0.5, "drag": 0.5})


@case("blink_on", ["stage.blink_on"])
def _(c):
    c.els[1]["blink"] = {"on": 30, "off": 120, "warn": 30}


@case("blink_off", ["stage.blink_off"])
def _(c):
    c.els[1]["blink"] = {"on": 120, "off": 2000, "warn": 30}


@case("blink_warn", ["stage.blink_warn"])
def _(c):
    c.els[1]["blink"] = {"on": 120, "off": 120}


@case("main", ["stage.main"])
def _(c):
    c.els[0]["rect"] = [160, 200, 150, 40]
    c.d["spawns"] = [[170, 200], [215, 200], [260, 200], [305, 200]]


@case("spawn_ground", ["stage.spawn_ground"])
def _(c):
    c.d["spawns"][0] = [120, 180]


@case("spawn_spacing", ["stage.spawn_spacing"])
def _(c):
    c.d["spawns"][1] = [140, 200]


@case("spawn_hazard", ["stage.spawn_hazard"])
def _(c):
    hazard(c)["rect"] = [190, 150, 20, 8]


@case("headroom", ["stage.headroom"])
def _(c):
    add(c, rect=[124, 130, 72, 10], collide="solid", tile="ground")


@case("reach", ["stage.reach"])
def _(c):
    add(c, rect=[200, 100, 80, 4])


@case("reach_gap", ["stage.reach"])
def _(c):
    add(c, rect=[0, 120, 10, 4])


def trap_case(c, kind="shoot"):
    c.imgs["hazard.png"] = tile(40, 8)
    c.d["assets"]["hazard"] = {"kind": "hazard", "image": "hazard.png"}
    a = {"type": kind, "origin": [20, 10], "asset": "hazard", "period": 180, "warn": 30,
         "damage": 5, "knockback": {"angle": 45, "force": 20}, "radius": 4}
    if kind == "shoot":
        a.update(angle=0, speed=2, lifetime=60)
    else:
        a.update(grip=[1, 4], length=36, active=30, **{"from": 45, "to": -45})
    add(c, id="actor", rect=[20, 60, 48, 64], collide="none", trap=a)
    return a

@case("valid_trap_shoot", [])
def _(c):
    trap_case(c)

@case("valid_trap_swing", [])
def _(c):
    trap_case(c, "swing")

@case("valid_background_region", [])
def _(c):
    c.els[0].pop("tile")
    c.els[0]["background_region"] = True

@case("background_region_motion", ["stage.background_region"])
def _(c):
    c.els[1].pop("tile")
    c.els[1].update(background_region=True, move={"path": [[0,0],[4,0]], "period": 120})

@case("trap_ref", ["ref"])
def _(c):
    trap_case(c)["asset"] = "absent"

@case("trap_warning", ["stage.trap_warn"])
def _(c):
    trap_case(c)["warn"] = 1

@case("trap_timing", ["stage.trap_timing"])
def _(c):
    trap_case(c).update(period=120, warn=120)

@case("trap_origin", ["stage.trap_origin"])
def _(c):
    trap_case(c)["origin"] = [50, 10]

@case("trap_speed", ["stage.trap_speed"])
def _(c):
    trap_case(c)["speed"] = 7

@case("trap_spawn", ["stage.trap_spawn"])
def _(c):
    trap_case(c)
    c.els[-1]["rect"][1] = 170

@case("trap_grip", ["stage.trap_grip"])
def _(c):
    trap_case(c, "swing")["grip"] = [-1, 4]

@case("trap_sweep", ["stage.trap_sweep"])
def _(c):
    trap_case(c, "swing")["to"] = -181

@case("trap_count", ["stage.trap_count"])
def _(c):
    for i in range(7): trap_case(c)


def build(c):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        def put(name, data):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
        put("stage.json", json.dumps(c.d, ensure_ascii=False, indent=1))
        for n in sorted(c.imgs):
            b = io.BytesIO()
            c.imgs[n].save(b, "PNG")
            put(n, b.getvalue())
        for n in sorted(c.raw):
            put(n, c.raw[n])
    return buf.getvalue()


def main():
    exp = json.load(open(EXPECTED, encoding="utf-8")) if os.path.exists(EXPECTED) else {}
    exp = {k: v for k, v in exp.items() if not k.startswith("stage_")}
    for f in os.listdir(OUT):
        if f.startswith("stage_"):
            os.remove(os.path.join(OUT, f))
    for name, fn, codes in CASES:
        c = Case()
        fn(c)
        open(os.path.join(OUT, name + ".zip"), "wb").write(build(c))
        exp[name + ".zip"] = {"valid": not codes, "errors": sorted(codes)}
    json.dump(exp, open(EXPECTED, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    print("generated %d stage packs" % len(CASES))


if __name__ == "__main__":
    main()
