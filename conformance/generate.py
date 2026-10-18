#!/usr/bin/env python3
"""生成一致性测试角色包（conformance/packs/*.zip）与期望结果（expected.json）。

每个违规包都由同一个合法基准包做一处修改得到，期望错误码集合在这里手写。
合法包的点数明细在首次生成时由 skill/scripts/validate.py 计算并冻结到
expected.json（--freeze-points），之后游戏内校验器与 validate.py 都必须给出相同结果。

  python conformance/generate.py                 重新生成 packs 并保留已冻结的点数
  python conformance/generate.py --freeze-points 重新冻结合法包的点数
"""
import copy
import io
import json
import os
import random
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "skill", "scripts"))
from PIL import Image  # noqa: E402
from pixel import grid, blank, rect, paste, Sheet, set_px  # noqa: E402

OUT = os.path.join(ROOT, "conformance", "packs")
EXPECTED = os.path.join(ROOT, "conformance", "expected.json")

C_BODY = "#5b6ee1"
C_DARK = "#222034"
C_HAND = "#fbf236"
C_STEEL = "#cbdbfc"
C_RED = "#d95763"


def body_frame(fw, fh, w, h, ax, ay, variant=0):
    """一个 w×h 的方块角色，底边中点在 (ax, ay)。"""
    im = blank(fw, fh)
    x0 = ax - w // 2
    y0 = ay - h
    rect(im, x0, y0, x0 + w - 1, ay - 1, C_BODY)
    rect(im, x0, y0, x0 + w - 1, y0, C_DARK)
    ex = x0 + w - 6 if variant != 2 else x0 + w - 7
    set_px(im, [(ex, y0 + 4), (ex + 2, y0 + 4)], C_DARK)
    if variant == 1:
        set_px(im, [(x0 + 2, y0 + 8)], C_HAND)
    return im


def sheet_img(fw=32, fh=32, w=20, h=28, n=3, extra=None):
    sh = Sheet(fw, fh, cols=max(n, 1))
    ax, ay = fw // 2, fh
    for i in range(n):
        if extra and i in extra:
            sh.add(extra[i])
        else:
            sh.add(body_frame(fw, fh, w, h, ax, ay, i % 3))
    return sh.image()


def circle_img(d, color=C_RED):
    im = blank(d, d)
    r = d / 2.0
    pts = []
    for y in range(d):
        for x in range(d):
            if (x + 0.5 - r) ** 2 + (y + 0.5 - r) ** 2 <= r * r + 0.5:
                pts.append((x, y))
    return set_px(im, pts, color)


def rect_img(w, h, color=C_HAND):
    return rect(blank(w, h), 0, 0, w - 1, h - 1, color)


def sword_img(w=22):
    im = blank(w, 5)
    rect(im, 0, 1, 3, 3, C_DARK)
    rect(im, 4, 0, 4, 4, C_DARK)
    rect(im, 5, 1, w - 2, 3, C_STEEL)
    set_px(im, [(w - 1, 2)], C_STEEL)
    return im


HAND = [[24, 16], [26, 15], [24, 17]]


def anim(frames=(0, 1, 2), durations=(8, 8, 8), loop=True, hand=True):
    a = {"frames": list(frames), "durations": list(durations), "loop": loop}
    if hand:
        a["hand"] = [list(h) for h in HAND[:len(frames)]] + [list(HAND[0])] * max(0, len(frames) - 3)
    return a


def attack_anim():
    return {"frames": [0, 1, 2], "hand": [list(h) for h in HAND]}


def base():
    d = {
        "format": 1,
        "name": "Base",
        "frame_size": [32, 32],
        "anchor": [16, 32],
        "stats": {"hp": 100, "body": [20, 28], "weight": 5, "gravity": 0.4, "max_fall": 5, "air_control": 0.5},
        "assets": {
            "sword": {"kind": "weapon", "image": "sword.png", "grip": [1, 2], "length": 20, "radius": 3,
                      "hit_range": [0.3, 1]},
            "ball": {"kind": "projectile", "image": "ball.png", "shape": "circle", "size": [8, 8]},
        },
        "anims": {n: anim() for n in ["idle", "walk", "jump", "fall", "land", "hurt", "guard", "ko", "taunt"]},
        "actions": {
            "move": {"type": "move", "speed": 2, "accel": 0.5},
            "jump": {"type": "jump", "velocity": 6.5, "max_count": 1},
            "slash": {"type": "swing", "anim": "slash", "weapon": "sword", "from": 60, "to": -30, "reach": [0, 4],
                      "startup": 6, "active": 4, "recovery": 10, "damage": 8,
                      "knockback": {"angle": 40, "force": 30}},
            "shot": {"type": "shoot", "anim": "cast", "projectile": "ball", "aim": "fixed", "angle": 0, "speed": 4,
                     "lifetime": 60, "startup": 8, "active": 2, "recovery": 12, "damage": 5,
                     "knockback": {"angle": 20, "force": 15}},
        },
        "input": {"attack.neutral": "slash", "special.neutral": "shot", "jump": "jump"},
    }
    d["anims"]["slash"] = attack_anim()
    d["anims"]["cast"] = attack_anim()
    imgs = {"sheet.png": sheet_img(), "sword.png": sword_img(), "ball.png": circle_img(8)}
    return d, imgs


class Case:
    def __init__(self):
        self.d, self.imgs = base()
        self.raw = {}           # 额外原始文件 name -> bytes
        self.drop_json = False
        self.json_text = None
        self.stored = False

    @property
    def acts(self):
        return self.d["actions"]


CASES = []


def case(name, codes):
    def deco(fn):
        CASES.append((name, fn, codes))
        return fn
    return deco


def add_res(c, name="r", **kw):
    r = {"init": 0, "max": 5}
    r.update(kw)
    c.d.setdefault("resources", {})[name] = r


def add_ult(c, name="ult_move", **kw):
    a = {"type": "swing", "anim": "slash", "weapon": "sword", "from": 90, "to": -90, "reach": [0, 4],
         "startup": 40, "active": 6, "recovery": 20, "damage": 20, "knockback": {"angle": 45, "force": 60},
         "ultimate": True}
    a.update(kw)
    c.acts[name] = a
    return a


def add_throw(c):
    c.d["anims"]["throw_a"] = anim()
    c.acts["throw"] = {"type": "pose", "anim": "throw_a",
                       "throw": {"frame": 10, "damage": 6, "knockback": {"angle": 45, "force": 40}}}


def add_grab(c, throw_frame=10, reach=(0, 4), link=True, durations=(6, 6, 6)):
    c.d["anims"]["throw_a"] = anim(durations=durations)
    c.acts["grab"] = {"type": "swing", "anim": "slash", "weapon": "sword", "from": 0, "to": 0, "reach": list(reach),
                      "startup": 6, "active": 3, "recovery": 12, "damage": 3, "grab": True,
                      "knockback": {"angle": 0, "force": 0}}
    if link:
        c.acts["grab"]["links"] = [{"when": "on_hit", "goto": "throw"}]
    c.acts["throw"] = {"type": "pose", "anim": "throw_a",
                       "throw": {"frame": throw_frame, "damage": 6, "knockback": {"angle": 45, "force": 40}}}


def add_beam(c, size=(120, 6), img=(16, 6), **kw):
    c.d["assets"]["beam"] = {"kind": "projectile", "image": "beam.png", "shape": "rect", "size": list(size),
                             "tile": "repeat_x"}
    c.imgs["beam.png"] = rect_img(*img)
    a = {"type": "shoot", "anim": "cast", "projectile": "beam", "aim": "fixed", "angle": 0, "speed": 0,
         "attach": True, "grow": 6, "lifetime": 40, "hit_interval": 8, "startup": 20, "active": 2, "recovery": 12,
         "damage": 2, "cooldown": 90, "knockback": {"angle": 10, "force": 10}}
    a.update(kw)
    c.acts["beam"] = a
    return a


def add_mine(c, d=10, name="mine", **kw):
    c.d["assets"][name] = {"kind": "projectile", "image": name + ".png", "shape": "circle", "size": [d, d]}
    c.imgs[name + ".png"] = circle_img(d, C_DARK)
    a = {"type": "shoot", "anim": "cast", "projectile": name, "aim": "fixed", "angle": 0, "speed": 0,
         "lifetime": 300, "hp": 5, "startup": 8, "active": 2, "recovery": 12, "damage": 6,
         "knockback": {"angle": 60, "force": 30}}
    a.update(kw)
    c.acts[name] = a
    return a


def add_shoot(c, name, **kw):
    a = copy.deepcopy(base()[0]["actions"]["shot"])
    a.update(kw)
    c.acts[name] = a
    return a


# ------------------------------------------------------------------ 合法包

@case("valid_base", [])
def _(c):
    pass


@case("valid_forms", [])
def _(c):
    add_res(c, "slot", init=0, max=2, wrap=True)
    c.d["held"] = "sword"
    c.acts["switch"] = {"type": "pose", "anim": "taunt", "cooldown": 30,
                        "links": [{"when": "on_end", "gain": {"slot": 1}}]}
    c.acts["heavy"] = dict(copy.deepcopy(c.acts["slash"]), startup=12, damage=12)
    c.d["input"]["special.down"] = "switch"
    c.d["forms"] = [
        {"if": {"slot": "==1"}, "stats": {"weight": 7, "hp": 110}, "input": {"attack.neutral": "heavy"}},
        {"if": {"slot": "==2"}, "input": {"attack.neutral": "shot"}},
    ]


@case("valid_upgrades", [])
def _(c):
    add_res(c, "tier", init=0, max=2)
    c.acts["slash"]["upgrades"] = [{"if": {"tier": ">=1"}, "set": {"damage": 9}},
                                   {"if": {"tier": ">=2"}, "set": {"damage": 9.5, "reach": [0, 8]}}]
    c.acts["slash"]["cost"] = {"tier": 0}


@case("valid_mechanics", [])
def _(c):
    d = c.d
    add_res(c, "mana", init=3, max=5, regen=0.01, hud="bar")
    d["anims"]["charge"] = anim()
    d["anims"]["fly"] = anim()
    d["anims"]["double_jump"] = anim()
    c.acts["jump"]["max_count"] = 2
    c.acts["slash"]["charge"] = {"max": 30, "damage": 1.3, "force": 1.2}
    c.acts["slash"]["status"] = {"type": "slow", "factor": 0.7, "duration": 60}
    c.acts["heavy"] = {"type": "swing", "anim": "slash", "weapon": "sword", "from": 120, "to": -60, "reach": [0, 6],
                       "startup": 14, "active": 4, "recovery": 18, "damage": 12, "armor": [2, 15],
                       "motion": [{"frame": 0, "vel": [3, 0]}, {"frame": 10, "vel": [0, 0]}],
                       "knockback": {"angle": 45, "force": 50}, "sfx": {"start": "whoosh"}}
    c.acts["dodge"] = {"type": "pose", "anim": "taunt", "invuln": [2, 12], "cooldown": 60, "gravity_scale": 0.5}
    c.acts["mirror"] = {"type": "pose", "anim": "taunt", "reflect": [0, 15], "cooldown": 90}
    c.acts["fly"] = {"type": "fly", "duration": 60, "rise_speed": 1, "control": 0.6, "recharge": "on_land"}
    add_grab(c)
    add_beam(c)
    add_mine(c, name="turret", lifetime=240, damage=3, speed=0,
             links=[{"when": "every", "interval": 60, "spawn": "pellet"}])
    add_shoot(c, "pellet", damage=2, lifetime=40, startup=4, recovery=8, knockback={"angle": 0, "force": 5})
    add_shoot(c, "bomb", damage=4, speed=3, lifetime=50, gravity=0.2, cost={"mana": 1},
              links=[{"when": "projectile_expire", "spawn": "burst"}])
    add_shoot(c, "burst", count=8, spread=360, damage=2, speed=3, lifetime=10, startup=4, recovery=8,
              knockback={"angle": 90, "force": 10})
    add_shoot(c, "blink", damage=2, speed=5, lifetime=30, cooldown=120,
              links=[{"when": "projectile_expire", "warp": "projectile"}])
    add_ult(c, area="screen", active=8, damage=25, startup=60, knockback={"angle": 70, "force": 80})
    d["assets"]["whoosh"] = {"kind": "sfx", "params": {"wave_type": 3, "p_env_sustain": 0.1, "p_env_decay": 0.2,
                                                       "p_base_freq": 0.6, "p_freq_ramp": -0.3}}
    d["assets"]["spark"] = {"kind": "fx", "image": "spark.png", "frames": 3, "durations": [3, 3, 3]}
    c.imgs["spark.png"] = rect_img(24, 8, C_HAND)
    d["links"] = [{"when": "every", "interval": 300, "heal": 3, "fx": "spark"},
                  {"when": "resource_full", "resource": "mana", "sfx": "whoosh"}]
    d["input"].update({"attack.side": "heavy", "attack.down": "grab", "special.side": "beam",
                       "special.down": "turret", "special.up": "fly", "attack.up": "bomb",
                       "special.neutral.air": "blink", "attack.neutral.air": "dodge", "attack.down.air": "mirror"})


# ------------------------------------------------------------------ 包与美术

@case("pack_zip_bytes", ["pack.zip_bytes"])
def _(c):
    rnd = random.Random(7)
    im = Image.new("RGBA", (2100, 2100))
    im.putdata([(255, 255, 255, 255) if rnd.random() < 0.5 else (0, 0, 0, 255) for _ in range(2100 * 2100)])
    c.imgs["noise.png"] = im
    c.stored = True


@case("pack_read_missing_json", ["pack.read"])
def _(c):
    c.drop_json = True


@case("pack_read_bad_json", ["pack.read"])
def _(c):
    c.json_text = '{"format": 1, "name": '


@case("pack_read_bad_png", ["pack.read"])
def _(c):
    c.raw["ball.png"] = b"not a png"
    del c.imgs["ball.png"]


@case("pack_files", ["pack.files"])
def _(c):
    c.raw["notes.txt"] = b"hello"


@case("format", ["format"])
def _(c):
    c.d["format"] = 2


@case("schema_unknown_field", ["schema"])
def _(c):
    c.d["stats"]["speeed"] = 3


@case("schema_type", ["schema"])
def _(c):
    c.d["stats"]["hp"] = "100"


@case("schema_status", ["schema"])
def _(c):
    c.acts["slash"]["status"] = {"type": "burn", "damage": 1, "duration": 60}


@case("schema_upgrade", ["schema"])
def _(c):
    add_res(c, "tier")
    c.acts["slash"]["upgrades"] = [{"if": {"tier": ">=1"}, "set": {"reach": "far"}}]


@case("ref_image", ["ref"])
def _(c):
    c.d["assets"]["sword"]["image"] = "missing.png"


@case("pack_frame_size", ["pack.frame_size"])
def _(c):
    sh = Sheet(36, 36, cols=3)
    for i in range(3):
        sh.add(body_frame(36, 36, 20, 28, 18, 36, i))
    c.imgs["sheet.png"] = sh.image()
    c.d["frame_size"] = [36, 36]
    c.d["anchor"] = [18, 36]


@case("anchor", ["anchor"])
def _(c):
    c.d["anchor"] = [40, 32]


@case("pack_sheet_side", ["pack.sheet_side"])
def _(c):
    c.imgs["sheet.png"] = sheet_img(n=33)


@case("pack_sheet_grid", ["pack.sheet_grid"])
def _(c):
    im = blank(100, 32)
    im.alpha_composite(c.imgs["sheet.png"], (0, 0))
    c.imgs["sheet.png"] = im


@case("pack_total_frames", ["pack.total_frames"])
def _(c):
    im = blank(1024, 160)
    im.alpha_composite(c.imgs["sheet.png"], (0, 0))
    c.imgs["sheet.png"] = im


@case("pack_alpha", ["pack.alpha"])
def _(c):
    c.imgs["sword.png"].putpixel((10, 2), (200, 200, 200, 128))


@case("pack_colors", ["pack.colors"])
def _(c):
    im = blank(40, 1)
    for i in range(40):
        im.putpixel((i, 0), (i * 6, 100, 50, 255))
    c.imgs["extra.png"] = im


@case("asset_fx_frames", ["asset.fx_frames"])
def _(c):
    c.d["assets"]["boom"] = {"kind": "fx", "image": "boom.png", "frames": 4, "durations": [3, 3, 3, 3]}
    c.imgs["boom.png"] = rect_img(30, 8)


@case("pack_duration", ["pack.duration"])
def _(c):
    c.d["anims"]["idle"]["durations"] = [0, 8, 8]


@case("pack_duration_max", ["pack.duration"])
def _(c):
    c.d["anims"]["walk"]["durations"] = [61, 8, 8]


@case("pack_asset_side", ["pack.asset_side"])
def _(c):
    c.imgs["sword.png"] = sword_img(70)


@case("weapon_length", ["weapon.length"])
def _(c):
    c.d["assets"]["sword"]["length"] = 41


@case("weapon_radius", ["weapon.radius"])
def _(c):
    c.d["assets"]["sword"]["radius"] = 11


@case("weapon_hit_range", ["weapon.hit_range"])
def _(c):
    c.d["assets"]["sword"]["hit_range"] = [0.8, 0.5]


@case("projectile_circle", ["projectile.circle"])
def _(c):
    c.d["assets"]["ball"]["size"] = [8, 7]


@case("pack_projectile_bbox", ["pack.projectile_bbox"])
def _(c):
    c.d["assets"]["ball"]["size"] = [12, 12]


@case("pack_anim_frames_min", ["pack.anim_frames"])
def _(c):
    c.d["anims"]["idle"] = anim(frames=(0, 1), durations=(8, 8))


@case("pack_anim_frames_max", ["pack.anim_frames"])
def _(c):
    c.d["anims"]["idle"] = anim(frames=(0, 1, 2) * 3, durations=(8,) * 9)


@case("pack_attack_anim_frames", ["pack.attack_anim_frames"])
def _(c):
    c.d["anims"]["slash"] = {"frames": [0, 1, 2, 0], "hand": [list(h) for h in HAND] + [list(HAND[0])]}


@case("anim_durations_missing", ["anim.durations"])
def _(c):
    del c.d["anims"]["walk"]["durations"]


@case("anim_durations_attack", ["anim.durations"])
def _(c):
    c.d["anims"]["slash"]["durations"] = [4, 4, 4]


@case("anim_durations_shared", ["anim.durations"])
def _(c):
    c.acts["taunt"] = {"type": "pose", "anim": "slash"}
    c.d["input"]["special.up"] = "taunt"


@case("anim_hand_count", ["anim.hand"])
def _(c):
    c.d["anims"]["idle"]["hand"] = [[24, 16], [24, 16]]


@case("anim_hand_weapon", ["anim.hand"])
def _(c):
    del c.d["anims"]["slash"]["hand"]


@case("anim_hand_held", ["anim.hand"])
def _(c):
    c.d["held"] = "sword"
    del c.d["anims"]["fall"]["hand"]


@case("anim_hold", ["anim.hold"])
def _(c):
    c.d["anims"]["ko"]["hold"] = 3


@case("anim_required", ["anim.required"])
def _(c):
    del c.d["anims"]["guard"]


@case("anim_required_double_jump", ["anim.required"])
def _(c):
    c.acts["jump"]["max_count"] = 2


@case("anim_required_charge", ["anim.required"])
def _(c):
    c.acts["slash"]["charge"] = {"max": 20, "damage": 1.2, "force": 1.2}


@case("anim_required_fly", ["anim.required"])
def _(c):
    c.acts["fly"] = {"type": "fly", "duration": 60, "rise_speed": 1, "control": 0.5}


@case("ref_frame", ["ref"])
def _(c):
    c.d["anims"]["idle"]["frames"] = [0, 1, 5]


@case("structure_resources", ["structure.resources"])
def _(c):
    for i in range(7):
        add_res(c, "r%d" % i)


@case("reserved", ["reserved"])
def _(c):
    add_res(c, "ult")


@case("reserved_gain", ["reserved"])
def _(c):
    c.acts["slash"]["links"] = [{"when": "on_hit", "gain": {"ult": 10}}]


@case("structure_resource_max", ["structure.resource_max"])
def _(c):
    add_res(c, "r", max=100)


@case("resource_init", ["resource.init"])
def _(c):
    add_res(c, "r", init=5, max=3)


@case("structure_resource_regen", ["structure.resource_regen"])
def _(c):
    add_res(c, "r", regen=1.5)


@case("structure_forms", ["structure.forms"])
def _(c):
    add_res(c, "r")
    c.d["forms"] = [{"if": {"r": ">=1"}} for _ in range(5)]


@case("structure_actions", ["structure.actions"])
def _(c):
    for i in range(29):
        c.acts["p%d" % i] = {"type": "pose", "anim": "taunt"}


@case("structure_attacks", ["structure.attacks"])
def _(c):
    for i in range(19):
        c.acts["s%d" % i] = copy.deepcopy(c.acts["slash"])


@case("actions_move_jump", ["actions.move_jump"])
def _(c):
    c.acts["move2"] = {"type": "move", "speed": 2, "accel": 0.5}


@case("ultimate_count", ["ultimate.count"])
def _(c):
    add_ult(c, "u1")
    add_ult(c, "u2")


@case("ultimate_type", ["ultimate.type"])
def _(c):
    c.acts["big"] = {"type": "pose", "anim": "taunt", "ultimate": True}


@case("ultimate_input", ["ultimate.input"])
def _(c):
    add_ult(c)
    c.d["input"]["attack.up"] = "ult_move"


@case("input_move", ["input.move"])
def _(c):
    c.d["input"]["special.up"] = "move"


@case("ref_input", ["ref"])
def _(c):
    c.d["input"]["special.up"] = "nothing"


@case("structure_upgrades", ["structure.upgrades"])
def _(c):
    add_res(c, "r")
    c.acts["slash"]["upgrades"] = [{"if": {"r": ">=%d" % i}, "set": {"damage": 8}} for i in range(1, 6)]


@case("structure_char_links", ["structure.char_links"])
def _(c):
    add_res(c, "r")
    c.d["links"] = [{"when": "every", "interval": 60, "gain": {"r": 1}} for _ in range(9)]


@case("structure_links", ["structure.links"])
def _(c):
    add_res(c, "r")
    c.acts["slash"]["links"] = [{"when": "on_hit", "gain": {"r": 1}} for _ in range(7)]


@case("link_when", ["link.when"])
def _(c):
    c.d["links"] = [{"when": "on_start", "heal": 1}]


@case("link_when_bullet_trigger", ["link.when"])
def _(c):
    c.acts["slash"]["links"] = [{"when": "projectile_hit", "heal": 1}]


@case("link_input", ["link.input"])
def _(c):
    c.d["links"] = [{"when": "on_land", "input": "attack", "heal": 1}]


@case("link_window", ["link.window"])
def _(c):
    c.acts["slash"]["links"] = [{"when": "on_hurt", "goto": "shot"}]


@case("link_warp", ["link.warp"])
def _(c):
    c.acts["slash"]["cooldown"] = 120
    c.acts["slash"]["links"] = [{"when": "on_hit", "warp": "projectile"}]


@case("link_spawn", ["link.spawn"])
def _(c):
    c.acts["shot"]["links"] = [{"when": "on_start", "spawn": "slash"}]


@case("ref_goto", ["ref"])
def _(c):
    c.acts["slash"]["links"] = [{"when": "on_hit", "goto": "nowhere"}]


@case("heal_max", ["heal.max"])
def _(c):
    c.acts["slash"]["links"] = [{"when": "on_hit", "heal": 11}]


@case("heal_every_interval_min", ["heal.every_interval_min"])
def _(c):
    c.d["links"] = [{"when": "every", "interval": 60, "heal": 5}]


@case("every_interval_min", ["every.interval_min"])
def _(c):
    add_res(c, "r")
    c.d["links"] = [{"when": "every", "interval": 20, "gain": {"r": 1}}]


@case("structure_goto_cycle", ["structure.goto_cycle"])
def _(c):
    c.acts["slash2"] = copy.deepcopy(c.acts["slash"])
    c.acts["slash"]["links"] = [{"when": "on_hit", "input": "attack", "window": [6, 16], "goto": "slash2"}]
    c.acts["slash2"]["links"] = [{"when": "on_hit", "input": "attack", "window": [6, 16], "goto": "slash"}]


@case("structure_spawn_depth", ["structure.spawn_depth"])
def _(c):
    for i in range(10):
        a = add_shoot(c, "chain%d" % i)
        if i < 9:
            a["links"] = [{"when": "on_start", "spawn": "chain%d" % (i + 1)}]


@case("pack_sfx_count", ["pack.sfx_count"])
def _(c):
    for i in range(17):
        c.d["assets"]["s%d" % i] = {"kind": "sfx", "params": {"p_base_freq": 0.3}}


@case("pack_sfx_seconds", ["pack.sfx_seconds"])
def _(c):
    c.d["assets"]["long"] = {"kind": "sfx", "params": {"p_env_sustain": 1, "p_env_decay": 0.5}}


@case("ref_sfx", ["ref"])
def _(c):
    c.acts["slash"]["sfx"] = {"start": "nope"}


@case("ref_fx", ["ref"])
def _(c):
    c.acts["slash"]["links"] = [{"when": "on_hit", "fx": "nope"}]


@case("ref_hud", ["ref"])
def _(c):
    add_res(c, "r", hud="nope")


@case("ref_held", ["ref"])
def _(c):
    c.d["held"] = "ball"


@case("ref_resource", ["ref"])
def _(c):
    c.acts["slash"]["cost"] = {"gold": 1}


# ------------------------------------------------------------------ 属性

@case("stats_hp", ["stats.hp"])
def _(c):
    c.d["stats"]["hp"] = 151


@case("stats_weight", ["stats.weight"])
def _(c):
    c.d["stats"]["weight"] = 0.5


@case("stats_gravity", ["stats.gravity"])
def _(c):
    c.d["stats"]["gravity"] = 0.7


@case("stats_max_fall", ["stats.max_fall"])
def _(c):
    c.d["stats"]["max_fall"] = 8


@case("stats_air_control", ["stats.air_control"])
def _(c):
    c.d["stats"]["air_control"] = 0.05


def big_body(c, w, h):
    c.d["frame_size"] = [64, 64]
    c.d["anchor"] = [32, 64]
    c.imgs["sheet.png"] = sheet_img(64, 64, w, h)
    c.d["stats"]["body"] = [w, h]
    for a in c.d["anims"].values():
        if "hand" in a:
            a["hand"] = [[40, 40]] * len(a["frames"])


@case("stats_body_w", ["stats.body_w"])
def _(c):
    big_body(c, 42, 28)


@case("stats_body_h", ["stats.body_h"])
def _(c):
    big_body(c, 20, 50)


@case("stats_body_frame", ["stats.body_frame"])
def _(c):
    c.d["stats"]["body"] = [20, 36]


@case("pack_idle_body", ["pack.idle_body"])
def _(c):
    c.imgs["sheet.png"] = sheet_img(extra={0: body_frame(32, 32, 20, 18, 16, 32)})


@case("pack_frame_body", ["pack.frame_body"])
def _(c):
    c.imgs["sheet.png"] = sheet_img(extra={2: body_frame(32, 32, 30, 28, 16, 32)})


@case("form_stats", ["stats.hp"])
def _(c):
    add_res(c, "r")
    c.d["forms"] = [{"if": {"r": "==5"}, "stats": {"hp": 200}}]


@case("form_input_ult", ["ultimate.input"])
def _(c):
    add_res(c, "r")
    add_ult(c)
    c.d["forms"] = [{"if": {"r": ">=1"}, "input": {"attack.up": "ult_move"}}]


@case("form_anim_missing", ["ref"])
def _(c):
    add_res(c, "r")
    c.d["forms"] = [{"if": {"r": ">=1"}, "anims": {"idle": "idle_big"}}]


# ------------------------------------------------------------------ 动作通用

@case("cooldown", ["cooldown"])
def _(c):
    c.acts["slash"]["cooldown"] = 601


@case("move_speed", ["move.speed"])
def _(c):
    c.acts["move"]["speed"] = 3.6


@case("move_accel", ["move.accel"])
def _(c):
    c.acts["move"]["accel"] = 1.1


@case("jump_velocity", ["jump.velocity"])
def _(c):
    c.acts["jump"]["velocity"] = 3.9


@case("jump_max_count", ["jump.max_count"])
def _(c):
    c.acts["jump"]["max_count"] = 4
    c.d["anims"]["double_jump"] = anim()


def add_fly(c, **kw):
    c.d["anims"]["fly"] = anim()
    a = {"type": "fly", "duration": 60, "rise_speed": 1, "control": 0.5}
    a.update(kw)
    c.acts["fly"] = a


@case("fly_duration", ["fly.duration"])
def _(c):
    add_fly(c, duration=121)


@case("fly_rise_speed", ["fly.rise_speed"])
def _(c):
    add_fly(c, rise_speed=1.6)


@case("fly_control", ["fly.control"])
def _(c):
    add_fly(c, control=1.1)


@case("ultimate_area", ["ultimate.area"])
def _(c):
    c.acts["slash"]["area"] = "screen"


@case("throw_damage", ["attack.damage"])
def _(c):
    add_throw(c)
    c.acts["throw"]["throw"]["damage"] = 30


@case("throw_force", ["attack.force"])
def _(c):
    add_throw(c)
    c.acts["throw"]["throw"]["knockback"]["force"] = 101


@case("throw_frame", ["throw.frame"])
def _(c):
    add_throw(c)
    c.acts["throw"]["throw"]["frame"] = 99


@case("armor_frames", ["armor.frames"])
def _(c):
    c.acts["slash"].update(startup=20, armor=[0, 20])


@case("armor_window", ["armor.window"])
def _(c):
    c.acts["slash"].update(startup=10, armor=[10, 14])


@case("armor_min_startup", ["armor.min_startup"])
def _(c):
    c.acts["slash"].update(armor=[0, 3])


@case("armor_pose", ["armor.min_startup"])
def _(c):
    c.acts["tank"] = {"type": "pose", "anim": "taunt", "armor": [0, 5]}


@case("invuln_frames", ["invuln.frames"])
def _(c):
    c.acts["slash"].update(invuln=[0, 15], cooldown=60)


@case("invuln_min_cooldown", ["invuln.min_cooldown"])
def _(c):
    c.acts["slash"].update(invuln=[0, 5], cooldown=30)


@case("reflect_frames", ["reflect.frames"])
def _(c):
    c.acts["slash"].update(reflect=[0, 20], cooldown=60)


@case("reflect_min_cooldown", ["reflect.min_cooldown"])
def _(c):
    c.acts["slash"].update(reflect=[0, 5], cooldown=30)


@case("motion_entries", ["motion.entries"])
def _(c):
    c.acts["slash"]["motion"] = [{"frame": i, "vel": [1, 0]} for i in range(5)]


@case("motion_speed", ["motion.speed"])
def _(c):
    c.acts["slash"]["motion"] = [{"frame": 0, "vel": [11, 0]}, {"frame": 1, "vel": [0, 0]}]


@case("motion_distance", ["motion.distance"])
def _(c):
    c.acts["slash"]["motion"] = [{"frame": 0, "vel": [9, 0]}]


@case("gravity_scale", ["gravity_scale"])
def _(c):
    c.acts["slash"]["gravity_scale"] = 1.5


@case("warp_min_cooldown", ["warp.min_cooldown"])
def _(c):
    c.acts["shot"]["cooldown"] = 60
    c.acts["shot"]["links"] = [{"when": "projectile_hit", "warp": "projectile"}]


# ------------------------------------------------------------------ 攻击

@case("ultimate_startup", ["ultimate.startup"])
def _(c):
    add_ult(c, startup=30)


@case("attack_startup_min", ["attack.startup"])
def _(c):
    c.acts["slash"].update(startup=1, damage=6, knockback={"angle": 40, "force": 20})


@case("attack_startup_max", ["attack.startup"])
def _(c):
    c.acts["slash"].update(startup=61)


@case("attack_active", ["attack.active"])
def _(c):
    c.acts["slash"].update(active=21)


@case("attack_recovery", ["attack.recovery"])
def _(c):
    c.acts["slash"].update(recovery=3)


@case("attack_total_frames", ["attack.total_frames"])
def _(c):
    c.acts["slash"].update(startup=50, active=20, recovery=40)


@case("attack_damage", ["attack.damage"])
def _(c):
    c.acts["slash"].update(damage=0.5)


@case("attack_force", ["attack.force"])
def _(c):
    c.acts["slash"].update(knockback={"angle": 40, "force": -1})


@case("attack_hit_interval", ["attack.hit_interval"])
def _(c):
    c.acts["slash"].update(hit_interval=3)


@case("ultimate_screen_active", ["ultimate.screen.active"])
def _(c):
    add_ult(c, area="screen", active=11, damage=2)


@case("ultimate_screen_damage", ["ultimate.screen.damage"])
def _(c):
    add_ult(c, area="screen", startup=60, damage=31)


@case("ultimate_screen_force", ["ultimate.screen.force"])
def _(c):
    add_ult(c, area="screen", knockback={"angle": 45, "force": 81})


@case("charge_max", ["charge.max"])
def _(c):
    c.d["anims"]["charge"] = anim()
    c.acts["slash"]["charge"] = {"max": 91, "damage": 1.2, "force": 1.2}


@case("charge_mult", ["charge.mult"])
def _(c):
    c.d["anims"]["charge"] = anim()
    c.acts["slash"]["charge"] = {"max": 30, "damage": 1.6, "force": 1.2}


@case("attack_damage_startup", ["attack.damage_startup"])
def _(c):
    c.acts["slash"].update(damage=10)


@case("attack_force_startup", ["attack.force_startup"])
def _(c):
    c.acts["slash"].update(knockback={"angle": 40, "force": 36})


@case("attack_force_startup_charged", ["attack.force_startup"])
def _(c):
    c.d["anims"]["charge"] = anim()
    c.acts["slash"].update(startup=20, knockback={"angle": 40, "force": 70},
                           charge={"max": 10, "damage": 1, "force": 1.5})


@case("status_burn_damage", ["status.burn.damage"])
def _(c):
    c.acts["slash"]["status"] = {"type": "burn", "damage": 4, "interval": 20, "duration": 60}


@case("status_burn_interval_min", ["status.burn.interval_min"])
def _(c):
    c.acts["slash"]["status"] = {"type": "burn", "damage": 1, "interval": 10, "duration": 60}


@case("status_burn_duration_max", ["status.burn.duration_max"])
def _(c):
    c.acts["slash"]["status"] = {"type": "burn", "damage": 1, "interval": 60, "duration": 181}


@case("status_slow_factor", ["status.slow.factor"])
def _(c):
    c.acts["slash"]["status"] = {"type": "slow", "factor": 0.4, "duration": 60}


@case("status_slow_duration_max", ["status.slow.duration_max"])
def _(c):
    c.acts["slash"]["status"] = {"type": "slow", "factor": 0.7, "duration": 121}


@case("status_stun_duration_max", ["status.stun.duration_max"])
def _(c):
    c.acts["slash"]["status"] = {"type": "stun", "duration": 46}


@case("status_root_duration_max", ["status.root.duration_max"])
def _(c):
    c.acts["slash"]["status"] = {"type": "root", "duration": 91}


@case("status_silence_duration_max", ["status.silence.duration_max"])
def _(c):
    c.acts["slash"]["status"] = {"type": "silence", "duration": 121}


@case("attack_target_damage", ["attack.target_damage"])
def _(c):
    c.acts["slash"].update(hit_interval=4, active=16)


@case("attack_target_damage_burn", ["attack.target_damage"])
def _(c):
    c.acts["slash"].update(status={"type": "burn", "damage": 3, "interval": 20, "duration": 120})
    c.acts["slash"].update(hit_interval=4, active=8)


@case("ultimate_target_damage", ["ultimate.target_damage"])
def _(c):
    add_ult(c, damage=25, hit_interval=4, active=8)


@case("attack_angle", ["attack.angle"])
def _(c):
    c.acts["slash"]["from"] = 400


@case("attack_sweep", ["attack.angle", "attack.sweep"])
def _(c):
    c.acts["slash"]["from"] = -400
    c.acts["slash"]["to"] = 400


@case("weapon_reach_total", ["weapon.reach_total"])
def _(c):
    c.acts["slash"]["reach"] = [0, 40]


@case("grab_reach_total", ["grab.reach_total"])
def _(c):
    add_grab(c, reach=(0, 10))


@case("grab_throw", ["grab.throw"])
def _(c):
    add_grab(c, link=False)


@case("grab_max_hold", ["grab.max_hold"])
def _(c):
    add_grab(c, throw_frame=60, durations=(30, 30, 30))


# ------------------------------------------------------------------ 子弹

@case("bullet_scale", ["bullet.scale"])
def _(c):
    c.acts["shot"]["scale_over_life"] = [0.4, 1]


@case("bullet_count", ["bullet.count"])
def _(c):
    c.acts["shot"].update(count=6, damage=4)


@case("bullet_spread", ["bullet.spread"])
def _(c):
    c.acts["shot"].update(count=3, spread=121)


def add_burst(c, **kw):
    c.acts["shot"]["links"] = [{"when": "projectile_hit", "spawn": "burst"}]
    a = add_shoot(c, "burst", count=8, spread=360, damage=2, lifetime=10)
    a.update(kw)


@case("bullet_burst_count", ["bullet.burst_count"])
def _(c):
    add_burst(c, count=9)


@case("bullet_burst_spread", ["bullet.burst_spread"])
def _(c):
    add_burst(c, spread=361)


@case("bullet_burst_damage", ["bullet.burst_damage"])
def _(c):
    add_burst(c, count=3, damage=4)


@case("shoot_hp", ["shoot.hp"])
def _(c):
    c.acts["shot"]["hp"] = 5


@case("bullet_speed_min", ["bullet.speed"])
def _(c):
    c.acts["shot"]["speed"] = 0.5


@case("bullet_speed_max", ["bullet.speed"])
def _(c):
    c.acts["shot"]["speed"] = 9


@case("bullet_circle_d", ["bullet.circle_d"])
def _(c):
    c.d["assets"]["ball"]["size"] = [18, 18]
    c.imgs["ball.png"] = circle_img(18)


@case("bullet_rect_max", ["bullet.rect_max"])
def _(c):
    c.d["assets"]["ball"] = {"kind": "projectile", "image": "ball.png", "shape": "rect", "size": [26, 6]}
    c.imgs["ball.png"] = rect_img(26, 6)
    c.acts["shot"]["speed"] = 3


@case("bullet_speed_side", ["bullet.speed_side"])
def _(c):
    c.d["assets"]["ball"]["size"] = [16, 16]
    c.imgs["ball.png"] = circle_img(16)
    c.acts["shot"]["speed"] = 7


@case("bullet_lifetime", ["bullet.lifetime"])
def _(c):
    c.acts["shot"]["lifetime"] = 181


@case("bullet_damage", ["bullet.damage"])
def _(c):
    c.acts["shot"].update(damage=11, startup=10)


@case("bullet_pierce", ["bullet.pierce"])
def _(c):
    c.acts["shot"]["pierce"] = 3


@case("bullet_turn_rate", ["bullet.turn_rate"])
def _(c):
    c.acts["shot"].update(aim="steer", turn_rate=5)


@case("bullet_gravity", ["bullet.gravity"])
def _(c):
    c.acts["shot"]["gravity"] = 0.5


@case("beam_length", ["beam.length"])
def _(c):
    add_beam(c, size=(210, 6))


@case("beam_width", ["beam.width"])
def _(c):
    add_beam(c, size=(120, 3), img=(16, 3))


@case("beam_grow_min", ["beam.grow_min"])
def _(c):
    add_beam(c, grow=3)


@case("beam_startup_min", ["beam.startup_min"])
def _(c):
    add_beam(c, startup=19)


@case("beam_lifetime", ["beam.lifetime"])
def _(c):
    add_beam(c, lifetime=61)


@case("beam_hit_interval_min", ["beam.hit_interval_min"])
def _(c):
    add_beam(c, hit_interval=5)


@case("beam_damage", ["beam.damage"])
def _(c):
    add_beam(c, damage=4)


@case("beam_turn_rate", ["beam.turn_rate"])
def _(c):
    add_beam(c, aim="steer", turn_rate=3)


@case("beam_cooldown_min", ["beam.cooldown_min"])
def _(c):
    add_beam(c, cooldown=89)


@case("deployable_size", ["deployable.size"])
def _(c):
    add_mine(c, d=26)


@case("deployable_solid_size", ["deployable.solid_size"])
def _(c):
    c.d["assets"]["block"] = {"kind": "projectile", "image": "block.png", "shape": "rect", "size": [50, 8]}
    c.imgs["block.png"] = rect_img(50, 8)
    add_mine(c, solid=True, projectile="block")


@case("deployable_lifetime", ["deployable.lifetime"])
def _(c):
    add_mine(c, lifetime=50)


@case("deployable_hp_missing", ["deployable.hp"])
def _(c):
    del add_mine(c)["hp"]


@case("deployable_hp", ["deployable.hp"])
def _(c):
    add_mine(c, hp=21)


@case("deployable_damage", ["deployable.damage"])
def _(c):
    add_mine(c, damage=9)


@case("deployable_hit_interval", ["deployable.hit_interval"])
def _(c):
    add_mine(c, hit_interval=10, lifetime=60, damage=1)


@case("deployable_every_interval_min", ["deployable.every_interval_min"])
def _(c):
    add_mine(c, name="turret", links=[{"when": "every", "interval": 40, "spawn": "pellet"}])
    add_shoot(c, "pellet", damage=2, lifetime=40)


@case("deployable_spawn_kind", ["deployable.spawn_kind"])
def _(c):
    add_beam(c)
    add_mine(c, name="turret", links=[{"when": "every", "interval": 60, "spawn": "beam"}])


@case("deployable_distance_bullet", ["deployable.distance"])
def _(c):
    add_mine(c, damage=2)
    c.acts["shot"]["links"] = [{"when": "projectile_expire", "spawn": "mine"}]


@case("deployable_distance", ["deployable.distance"])
def _(c):
    big_body(c, 24, 32)
    c.d["anims"]["cast"]["hand"] = [[62, 2], [62, 2], [62, 2]]
    add_mine(c)


# ------------------------------------------------------------------ 点数

@case("points_action", ["points.action"])
def _(c):
    c.acts["slash"].update(hit_interval=4, active=12, status={"type": "stun", "duration": 40})


@case("points_form", ["points.form"])
def _(c):
    keys = ["attack.side", "attack.up", "attack.down", "attack.neutral.air", "attack.side.air", "attack.up.air",
            "attack.down.air", "special.side", "special.up"]
    for i, k in enumerate(keys):
        c.acts["s%d" % i] = dict(copy.deepcopy(c.acts["slash"]), hit_interval=4, active=8)
        c.d["input"][k] = "s%d" % i


@case("points_form_variant", ["points.form"])
def _(c):
    add_res(c, "slot", max=1)
    keys = ["attack.side", "attack.up", "attack.down", "attack.neutral.air", "attack.side.air", "attack.up.air",
            "attack.down.air", "special.side", "special.up"]
    inp = {}
    for i, k in enumerate(keys):
        c.acts["s%d" % i] = dict(copy.deepcopy(c.acts["slash"]), hit_interval=4, active=8)
        inp[k] = "s%d" % i
    c.d["forms"] = [{"if": {"slot": "==1"}, "input": inp}]


# ------------------------------------------------------------------ 输出

def build(fn):
    c = Case()
    fn(c)
    buf = io.BytesIO()
    method = zipfile.ZIP_STORED if c.stored else zipfile.ZIP_DEFLATED
    def put(z, name, data):
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = method
        z.writestr(info, data)

    with zipfile.ZipFile(buf, "w", method) as z:
        if not c.drop_json:
            text = c.json_text if c.json_text is not None else json.dumps(c.d, ensure_ascii=False, indent=1)
            put(z, "character.json", text)
        for name in sorted(c.imgs):
            b = io.BytesIO()
            c.imgs[name].save(b, "PNG")
            put(z, name, b.getvalue())
        for name in sorted(c.raw):
            put(z, name, c.raw[name])
    return buf.getvalue()


def main():
    freeze = "--freeze-points" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    old = {}
    if os.path.exists(EXPECTED):
        old = json.load(open(EXPECTED, encoding="utf-8"))
    for f in os.listdir(OUT):
        if f.endswith(".zip") and not f.startswith("example_"):
            os.remove(os.path.join(OUT, f))
    exp = {k: v for k, v in old.items() if k.startswith("example_")}
    names = set()
    for name, fn, codes in CASES:
        assert name not in names, name
        names.add(name)
        fname = name + ".zip"
        open(os.path.join(OUT, fname), "wb").write(build(fn))
        e = {"valid": not codes, "errors": sorted(codes)}
        if not codes:
            if freeze or fname not in old or "points" not in old[fname]:
                import validate  # noqa
                res = validate.validate_path(os.path.join(OUT, fname))
                e["points"] = round_points(res["points"])
            else:
                e["points"] = old[fname]["points"]
        exp[fname] = e
    json.dump(exp, open(EXPECTED, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    print("generated %d packs" % len(CASES))


def round_points(points):
    out = {}
    for label, bd in points.items():
        out[label] = {"total": round(bd["total"], 4),
                      "actions": {k: round(v, 4) for k, v in sorted(bd["actions"].items())}}
    return out


if __name__ == "__main__":
    main()
