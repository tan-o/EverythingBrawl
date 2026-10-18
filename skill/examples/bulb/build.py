#!/usr/bin/env python3
"""示例：远程角色「灯泡法师」—— 子弹 / 光束 / 布置物与各种状态效果。

演示机制：光束（attach + rect，可操控 steer）、灼烧火球（burn）、冰霜散射（count + spread + slow）、
电击（stun）、藤蔓陷阱（布置物 + root）、静默追踪弹（steer + silence）、回旋光环（return + pierce）、
反射护罩（reflect）、闪现（子弹 projectile_expire → warp）、漂浮（fly）、非全屏大招（巨型光束，尺寸上限 ×3）。
运行：python build.py
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))
from pixel import blank, set_px, rect, Sheet  # noqa: E402

K = "#222034"
Y = "#fbf236"
YL = "#ffffff"
YD = "#d9a066"
GL = "#fff6bd"
S = "#cbdbfc"
D = "#8b9bb4"
G = "#595652"
OR = "#df7126"
RE = "#d95763"
CY = "#5fcde4"
PU = "#76428a"
GR = "#6abe30"
GRD = "#37946e"

FW = FH = 48
AX, AY = 24, 48


def bulb(dy=0, squash=0, lean=0, legs="stand", eyes="open", glow=False):
    """圆形玻璃灯泡 + 螺口底座。glow=True 时灯丝更亮。"""
    im = blank(FW, FH)
    leg_h = 2 if legs == "tuck" else 4
    base_h = 7
    R = 11 - (1 if squash >= 2 else 0)
    bottom = FH - 1 - leg_h + dy
    base_top = bottom - base_h + 1
    cy = base_top - R + 2 + squash // 2
    cx = AX

    def off(y):
        return int(round(lean * (bottom - y) / 30.0))

    # 玻璃球
    for y in range(cy - R, base_top + 1):
        for x in range(cx - R - 1, cx + R + 2):
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * (1.0 + squash * 0.04))
            if d <= R + 0.5:
                if d > R - 0.7:
                    c = K
                elif x < cx - 4 and y < cy - 3:
                    c = YL
                elif d > R - 3:
                    c = YD if not glow else Y
                else:
                    c = Y if not glow else GL
                set_px(im, [(x + off(y), y)], c)
    # 灯丝（嘴）
    fy = cy + 3
    for x in range(cx - 3, cx + 4):
        set_px(im, [(x + off(fy), fy + (1 if x in (cx - 2, cx + 2) else 0))], OR)
    # 底座螺纹
    for y in range(base_top, bottom + 1):
        ry = y - base_top
        for x in range(cx - 6, cx + 6):
            rx = x - (cx - 6)
            c = K if rx in (0, 11) or ry == base_h - 1 else (S if ry % 2 == 0 else D)
            set_px(im, [(x + off(y), y)], c)
    # 眼睛
    ey = cy - 2
    ex = cx + 2 + off(ey)
    if eyes == "open":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1)], K)
    elif eyes == "angry":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1), (ex - 1, ey - 2), (ex + 5, ey - 2)], K)
    elif eyes == "closed":
        set_px(im, [(ex - 1, ey + 1), (ex, ey + 1), (ex + 4, ey + 1), (ex + 5, ey + 1)], K)
    else:
        for e in (ex, ex + 4):
            set_px(im, [(e - 1, ey - 1), (e + 1, ey - 1), (e, ey), (e - 1, ey + 1), (e + 1, ey + 1)], K)
    lxs = {"stand": (20, 26), "walk1": (18, 27), "walk2": (22, 24), "tuck": (20, 26), "spread": (17, 29)}[legs]
    for x in lxs:
        xo = x + off(bottom)
        rect(im, xo, bottom + 1, xo + 1, bottom + leg_h, G)
        rect(im, xo, bottom + leg_h, xo + 2, bottom + leg_h, K)
    return im


def lying():
    im = blank(FW, FH)
    body = bulb(eyes="x").crop((12, 16, 37, 44))
    rot = body.rotate(90, expand=True)
    im.alpha_composite(rot, (10, FH - rot.height))
    return im


def circle(d, inner, outer, hi=None):
    im = blank(d, d)
    r = d / 2.0
    for y in range(d):
        for x in range(d):
            dd = math.hypot(x + 0.5 - r, y + 0.5 - r)
            if dd <= r:
                c = outer if dd > r - 1.5 else inner
                if hi and x < r - 1 and y < r - 1 and dd < r - 2:
                    c = hi
                set_px(im, [(x, y)], c)
    return im


def images():
    out = {}
    out["fireball.png"] = circle(10, OR, RE, Y)
    out["frost.png"] = circle(6, YL, CY)
    out["spark.png"] = circle(8, Y, OR, YL)
    out["hush.png"] = circle(8, PU, K, "#d77bba")
    ring = blank(12, 12)
    for y in range(12):
        for x in range(12):
            dd = math.hypot(x + 0.5 - 6, y + 0.5 - 6)
            if 3.5 <= dd <= 6:
                set_px(ring, [(x, y)], Y if dd < 5 else OR)
    out["ring.png"] = ring
    out["blink.png"] = circle(8, YL, CY)
    vine = blank(16, 8)
    for x in range(16):
        y = int(4 + 2.5 * math.sin(x * 0.9))
        rect(vine, x, y, x, min(7, y + 1), GR)
        if x % 4 == 0:
            set_px(vine, [(x, max(0, y - 1))], GRD)
    rect(vine, 0, 7, 15, 7, GRD)
    out["vine.png"] = vine
    beam = blank(8, 8)
    for y in range(8):
        c = GL if 2 <= y <= 5 else Y
        rect(beam, 0, y, 7, y, c)
    out["beam.png"] = beam
    big = blank(8, 24)
    for y in range(24):
        c = YL if 8 <= y <= 15 else (GL if 4 <= y <= 19 else Y)
        rect(big, 0, y, 7, y, c)
    out["bigbeam.png"] = big
    return out


def build():
    sh = Sheet(FW, FH, cols=8)
    f = {}
    f["idle0"] = sh.add(bulb())
    f["idle1"] = sh.add(bulb(squash=1, glow=True))
    f["walk1"] = sh.add(bulb(dy=-1, legs="walk1"))
    f["walk2"] = sh.add(bulb(dy=-1, legs="walk2"))
    f["jump"] = sh.add(bulb(dy=-2, legs="tuck", lean=1))
    f["fall"] = sh.add(bulb(legs="spread", eyes="closed"))
    f["squash"] = sh.add(bulb(squash=3, legs="spread"))
    f["hurt"] = sh.add(bulb(lean=-4, eyes="x"))
    f["guard"] = sh.add(bulb(squash=2, eyes="closed", legs="spread"))
    f["windup"] = sh.add(bulb(lean=-3, eyes="angry", glow=True))
    f["cast"] = sh.add(bulb(lean=3, eyes="angry", glow=True, legs="walk1"))
    f["follow"] = sh.add(bulb(lean=1, legs="spread", eyes="angry"))
    f["ko1"] = sh.add(bulb(lean=-7, eyes="x", legs="spread"))
    f["ko2"] = sh.add(lying())
    f["float"] = sh.add(bulb(dy=-3, legs="tuck", eyes="closed", glow=True))
    sh.save(os.path.join(HERE, "sheet.png"))
    for n, im in images().items():
        im.save(os.path.join(HERE, n))

    def A(frames, durations=None, hands=None, loop=True):
        a = {"frames": [f[x] for x in frames]}
        if durations is not None:
            a["durations"] = durations
            a["loop"] = loop
        if hands:
            a["hand"] = hands
        return a

    cast_hands = [[30, 30], [38, 30], [36, 31]]
    anims = {
        "idle": A(["idle0", "idle1", "idle0"], [20, 14, 20]),
        "walk": A(["walk1", "idle0", "walk2", "idle0"], [6, 6, 6, 6]),
        "jump": A(["jump"] * 3, [4, 4, 4], loop=False),
        "double_jump": A(["float", "jump", "float"], [4, 4, 4], loop=False),
        "fall": A(["fall"] * 3, [6, 6, 6]),
        "land": A(["squash", "idle1", "idle0"], [4, 3, 3], loop=False),
        "hurt": A(["hurt"] * 3, [5, 5, 5]),
        "guard": A(["guard"] * 3, [10, 10, 10]),
        "ko": A(["hurt", "ko1", "ko2"], [10, 10, 30], loop=False),
        "fly": A(["float", "idle1", "float"], [8, 8, 8]),
        "mirror": A(["guard", "idle1", "guard"], [6, 14, 8], loop=False),
        "victory": A(["float", "idle1", "float"], [12, 12, 12]),
        "cast": A(["windup", "cast", "follow"], hands=cast_hands),
        "cast_up": A(["windup", "cast", "follow"], hands=[[30, 28], [34, 22], [34, 26]]),
        "cast_low": A(["windup", "cast", "follow"], hands=[[30, 36], [38, 42], [36, 40]]),
        "beam_pose": A(["windup", "cast", "cast"], hands=cast_hands),
    }
    data = {
        "format": 1,
        "name": "灯泡法师",
        "frame_size": [FW, FH],
        "anchor": [AX, AY],
        "stats": {"hp": 90, "body": [22, 32], "weight": 3, "gravity": 0.32, "max_fall": 4.5, "air_control": 0.7},
        "assets": {
            "fireball": {"kind": "projectile", "image": "fireball.png", "shape": "circle", "size": [10, 10]},
            "frost": {"kind": "projectile", "image": "frost.png", "shape": "circle", "size": [6, 6]},
            "spark": {"kind": "projectile", "image": "spark.png", "shape": "circle", "size": [8, 8]},
            "hush": {"kind": "projectile", "image": "hush.png", "shape": "circle", "size": [8, 8]},
            "ring": {"kind": "projectile", "image": "ring.png", "shape": "circle", "size": [12, 12]},
            "blink": {"kind": "projectile", "image": "blink.png", "shape": "circle", "size": [8, 8]},
            "vine": {"kind": "projectile", "image": "vine.png", "shape": "rect", "size": [16, 8]},
            "beam": {"kind": "projectile", "image": "beam.png", "shape": "rect", "size": [150, 8], "tile": "repeat_x"},
            "bigbeam": {"kind": "projectile", "image": "bigbeam.png", "shape": "rect", "size": [450, 24], "tile": "repeat_x"},
            "zap": {"kind": "sfx", "params": {"wave_type": 1, "p_env_sustain": 0.06, "p_env_decay": 0.15, "p_base_freq": 0.7, "p_freq_ramp": -0.3, "p_duty": 0.4, "sound_vol": 0.25}},
            "hum": {"kind": "sfx", "params": {"wave_type": 0, "p_env_attack": 0.05, "p_env_sustain": 0.4, "p_env_decay": 0.3, "p_base_freq": 0.25, "p_vib_strength": 0.3, "p_vib_speed": 0.4, "p_duty": 0.5, "sound_vol": 0.25}},
            "poof": {"kind": "sfx", "params": {"wave_type": 3, "p_env_sustain": 0.05, "p_env_decay": 0.2, "p_base_freq": 0.55, "p_freq_ramp": 0.2, "sound_vol": 0.3}},
        },
        "anims": anims,
        "actions": {
            "move": {"type": "move", "speed": 1.8, "accel": 0.3},
            "jump": {"type": "jump", "velocity": 6.2, "max_count": 2},
            "fly": {"type": "fly", "duration": 50, "rise_speed": 0.6, "control": 0.7, "recharge": "on_land"},
            "fireball": {"type": "shoot", "anim": "cast", "projectile": "fireball", "aim": "fixed", "angle": 0, "speed": 3.5,
                         "lifetime": 70, "startup": 10, "active": 2, "recovery": 14, "damage": 4,
                         "status": {"type": "burn", "damage": 1, "interval": 30, "duration": 120},
                         "knockback": {"angle": 30, "force": 14}, "sfx": {"start": "zap"}},
            "frost": {"type": "shoot", "anim": "cast", "projectile": "frost", "aim": "fixed", "angle": 0, "speed": 4,
                      "count": 3, "spread": 30, "lifetime": 35, "startup": 10, "active": 2, "recovery": 16, "damage": 2,
                      "status": {"type": "slow", "factor": 0.7, "duration": 90},
                      "knockback": {"angle": 20, "force": 8}, "cooldown": 30, "sfx": {"start": "zap"}},
            "spark": {"type": "shoot", "anim": "cast_up", "projectile": "spark", "aim": "fixed", "angle": 70, "speed": 4,
                      "lifetime": 30, "startup": 12, "active": 2, "recovery": 16, "damage": 3,
                      "status": {"type": "stun", "duration": 25}, "cooldown": 60,
                      "knockback": {"angle": 80, "force": 15}, "sfx": {"start": "zap"}},
            "vine_trap": {"type": "shoot", "anim": "cast_low", "projectile": "vine", "aim": "fixed", "angle": 0, "speed": 0,
                          "lifetime": 300, "hp": 4, "startup": 12, "active": 2, "recovery": 14, "damage": 2,
                          "status": {"type": "root", "duration": 60}, "cooldown": 90,
                          "knockback": {"angle": 90, "force": 0}},
            "hush": {"type": "shoot", "anim": "cast", "projectile": "hush", "aim": "steer", "angle": 0, "turn_rate": 3,
                     "speed": 3, "lifetime": 90, "startup": 14, "active": 2, "recovery": 16, "damage": 3,
                     "status": {"type": "silence", "duration": 90}, "cooldown": 90,
                     "knockback": {"angle": 30, "force": 10}, "sfx": {"start": "hum"}},
            "ring": {"type": "shoot", "anim": "cast", "projectile": "ring", "aim": "fixed", "angle": 0, "speed": 4,
                     "lifetime": 60, "return": True, "pierce": 1, "hit_interval": 20, "startup": 10, "active": 2,
                     "recovery": 14, "damage": 3, "cooldown": 50, "knockback": {"angle": 40, "force": 14}},
            "light_beam": {"type": "shoot", "anim": "beam_pose", "projectile": "beam", "aim": "steer", "angle": 0,
                           "turn_rate": 1.5, "speed": 0, "attach": True, "grow": 10, "lifetime": 40, "hit_interval": 8,
                           "startup": 22, "active": 2, "recovery": 18, "damage": 2, "cooldown": 120,
                           "knockback": {"angle": 15, "force": 12}, "sfx": {"start": "hum"}},
            "mirror": {"type": "pose", "anim": "mirror", "reflect": [2, 20], "cooldown": 90},
            "blink": {"type": "shoot", "anim": "cast", "projectile": "blink", "aim": "input", "angle": 45, "speed": 6,
                      "lifetime": 20, "startup": 6, "active": 2, "recovery": 12, "damage": 1, "cooldown": 120,
                      "knockback": {"angle": 45, "force": 5},
                      "links": [{"when": "projectile_expire", "warp": "projectile"},
                                {"when": "projectile_hit", "warp": "projectile"}],
                      "sfx": {"start": "poof"}},
            "supernova": {"type": "shoot", "anim": "beam_pose", "projectile": "bigbeam", "aim": "fixed", "angle": 0,
                          "speed": 0, "attach": True, "grow": 12, "lifetime": 60, "hit_interval": 8, "startup": 50,
                          "active": 2, "recovery": 30, "damage": 4, "cooldown": 90, "ultimate": True,
                          "knockback": {"angle": 25, "force": 60}, "sfx": {"start": "hum"}},
        },
        "input": {
            "attack.neutral": "frost", "attack.side": "fireball", "attack.up": "spark", "attack.down": "vine_trap",
            "attack.neutral.air": "ring", "attack.side.air": "fireball",
            "special.neutral": "hush", "special.side": "light_beam", "special.up": "blink", "special.down": "mirror",
            "special.up.air": "fly", "jump": "jump",
        },
    }
    json.dump(data, open(os.path.join(HERE, "character.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    build()
