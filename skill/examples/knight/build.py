#!/usr/bin/env python3
"""示例：单武器角色「罐头骑士」—— 易拉罐身体，常态手持一把剑。

演示机制：三段连击（on_hit + input window → goto）、蓄力斩（charge）、上升斩（motion + invuln + gravity_scale）、
反击（armor + on_hurt → goto）、抓投（grab → throw）、剑气（bullet）、全屏大招、音效与特效。

运行：python build.py  → 生成 sheet.png、素材图与 character.json（同目录）
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))
from pixel import blank, set_px, rect, Sheet  # noqa: E402

K = "#222034"   # 描边
R = "#d95763"   # 罐身红
RL = "#e88a8a"  # 高光
RD = "#ac3232"  # 暗部
S = "#cbdbfc"   # 银
D = "#8b9bb4"   # 银暗
W = "#ffffff"
G = "#595652"   # 腿
BR = "#8f563b"  # 剑柄
GO = "#fbf236"  # 护手
CY = "#5fcde4"  # 剑气

FW = FH = 48
AX, AY = 24, 48


def can(dy=0, squash=0, lean=0, legs="stand", eyes="open"):
    """画一帧罐子身体。lean>0 向前倾（朝右），squash 压扁行数，dy 整体上移（负数）。"""
    im = blank(FW, FH)
    leg_h = 2 if legs == "tuck" else 4
    H = 28 - squash
    bottom = FH - 1 - leg_h + dy
    top = bottom - H + 1

    def off(y):
        return int(round(lean * (bottom - y) / float(H)))

    for y in range(top, bottom + 1):
        ry = y - top
        x0 = 13 + off(y)
        for rx in range(22):
            x = x0 + rx
            if rx in (0, 21) or ry in (0, H - 1):
                c = K
            elif ry <= 2:
                c = S if ry == 1 else D
            elif ry >= H - 3:
                c = D if ry == H - 3 else S
            elif ry in (H // 2, H // 2 + 1) and (rx + ry) % 6 != 0:
                c = W
            elif rx in (3, 4):
                c = RL
            elif rx >= 17:
                c = RD
            else:
                c = R
            set_px(im, [(x, y)], c)
    # 眼睛（朝右）
    ey = top + 7
    ex = 13 + off(ey) + 13
    if eyes == "open":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1)], K)
    elif eyes == "angry":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1), (ex - 1, ey - 2), (ex, ey - 1), (ex + 5, ey - 2), (ex + 4, ey - 1)], K)
    elif eyes == "closed":
        set_px(im, [(ex - 1, ey + 1), (ex, ey + 1), (ex + 4, ey + 1), (ex + 5, ey + 1)], K)
    elif eyes == "x":
        for e in (ex, ex + 4):
            set_px(im, [(e - 1, ey - 1), (e + 1, ey - 1), (e, ey), (e - 1, ey + 1), (e + 1, ey + 1)], K)
    # 腿
    lx = {"stand": (16, 27), "walk1": (14, 28), "walk2": (18, 25), "tuck": (16, 27), "spread": (13, 30)}[legs]
    for i, x in enumerate(lx):
        xo = x + off(bottom)
        rect(im, xo, bottom + 1, xo + 1, bottom + leg_h, G)
        rect(im, xo, bottom + leg_h, xo + 2, bottom + leg_h, K)
    return im


def _lying():
    """击倒最后一帧：躺倒（身体旋转 90°）。"""
    im = blank(FW, FH)
    body = can(eyes="x").crop((13, 16, 35, 44))  # 22×28（不含腿）
    rot = body.rotate(90, expand=True)           # 28×22
    im.alpha_composite(rot, (8, FH - rot.height))
    return im


def weapon_images():
    sword = blank(26, 7)
    rect(sword, 0, 1, 4, 5, S)
    set_px(sword, [(0, 1), (4, 1), (0, 5), (4, 5)], (D))
    rect(sword, 5, 2, 6, 4, BR)
    rect(sword, 7, 0, 7, 6, GO)
    rect(sword, 8, 2, 24, 4, S)
    rect(sword, 8, 2, 24, 2, W)
    set_px(sword, [(25, 3)], S)
    fist = blank(8, 7)
    rect(fist, 1, 1, 6, 5, S)
    rect(fist, 0, 2, 7, 4, S)
    set_px(fist, [(3, 2), (3, 4), (5, 2), (5, 4)], D)
    wave = blank(14, 8)
    for y in range(8):
        for x in range(14):
            cx, cy = 3.0, 3.5
            d = ((x - cx) ** 2 / 100.0 + (y - cy) ** 2 / 12.25)
            d2 = ((x - cx + 4) ** 2 / 100.0 + (y - cy) ** 2 / 12.25)
            if d <= 1.0 and d2 > 1.0:
                set_px(wave, [(x, y)], CY if d > 0.6 else W)
    spark = blank(48, 16)
    for i, r in enumerate((3, 5, 7)):
        cx = 8 + i * 16
        for k in range(8):
            a = k * math.pi / 4
            for t in range(r - 2, r + 1):
                set_px(spark, [(int(cx + math.cos(a) * t), int(8 + math.sin(a) * t))], GO if i < 2 else W)
    # 大招背景：金色放射光 + 剑影（240x135，游戏里放大 2 倍铺满屏幕；两帧交替闪烁）
    bd = blank(480, 135)
    rays = ["#3f3f74", "#5b6ee1", "#fbf236", "#df7126", "#ffffff"]
    for fr in range(2):
        ox = fr * 240
        for y in range(135):
            for x in range(240):
                a = math.atan2(y - 67, x - 120)
                band = int((a + math.pi) / (math.pi / 12) + fr) % 2
                d = math.hypot(x - 120, y - 67)
                c = rays[0] if band else rays[1]
                if d < 30:
                    c = rays[4] if d < 18 else rays[2]
                elif d < 44 and band == 0:
                    c = rays[3]
                set_px(bd, [(ox + x, y)], c)
        rect(bd, ox + 116, 10, ox + 123, 100, "#cbdbfc")
        rect(bd, ox + 104, 96, ox + 135, 101, "#fbf236")
        rect(bd, ox + 117, 102, ox + 122, 124, "#8f563b")
    return {"sword.png": sword, "fist.png": fist, "wave.png": wave, "spark.png": spark, "ult_bg.png": bd}


def build():
    sh = Sheet(FW, FH, cols=8)
    f = {}
    f["idle0"] = sh.add(can())
    f["idle1"] = sh.add(can(squash=1))
    f["walk1"] = sh.add(can(dy=-1, legs="walk1"))
    f["walk2"] = sh.add(can(dy=-1, legs="walk2"))
    f["jump"] = sh.add(can(dy=-2, legs="tuck", lean=1))
    f["fall"] = sh.add(can(legs="spread", eyes="closed"))
    f["squash"] = sh.add(can(squash=4, legs="spread"))
    f["hurt"] = sh.add(can(lean=-4, eyes="x"))
    f["guard"] = sh.add(can(squash=2, eyes="closed", legs="spread"))
    f["windup"] = sh.add(can(lean=-3, eyes="angry"))
    f["strike"] = sh.add(can(lean=4, eyes="angry", legs="walk1"))
    f["follow"] = sh.add(can(lean=2, legs="spread", eyes="angry"))
    f["ko1"] = sh.add(can(lean=-7, eyes="x", legs="spread"))
    f["ko2"] = sh.add(_lying())
    f["air"] = sh.add(can(dy=-2, legs="tuck", eyes="angry"))
    f["cheer"] = sh.add(can(dy=-3, legs="spread", eyes="closed"))
    sh.save(os.path.join(HERE, "sheet.png"))
    for n, im in weapon_images().items():
        im.save(os.path.join(HERE, n))

    def A(frames, durations=None, hands=None, loop=True, hold=None):
        a = {"frames": [f[x] for x in frames]}
        if durations is not None:
            a["durations"] = durations
            a["loop"] = loop
        if hold is not None:
            a["hold"] = hold
        a["hand"] = hands or [[36, 34]] * len(frames)
        return a

    anims = {
        "idle": A(["idle0", "idle1", "idle0"], [20, 14, 20], [[36, 34], [36, 35], [36, 34]]),
        "walk": A(["walk1", "idle0", "walk2", "idle0"], [6, 6, 6, 6], [[36, 33], [36, 34], [36, 33], [36, 34]]),
        "jump": A(["jump", "jump", "jump"], [4, 4, 4], [[36, 30]] * 3, loop=False),
        "double_jump": A(["air", "jump", "air"], [4, 4, 4], [[37, 29]] * 3, loop=False),
        "fall": A(["fall", "fall", "fall"], [6, 6, 6], [[36, 33]] * 3),
        "land": A(["squash", "idle1", "idle0"], [4, 3, 3], [[36, 38], [36, 35], [36, 34]], loop=False),
        "hurt": A(["hurt", "hurt", "hurt"], [5, 5, 5], [[32, 33]] * 3),
        "guard": A(["guard", "guard", "guard"], [10, 10, 10], [[33, 36]] * 3),
        "ko": A(["hurt", "ko1", "ko2"], [10, 10, 30], [[32, 33], [30, 36], [30, 44]], loop=False),
        "charge": A(["windup", "squash", "windup"], [6, 6, 6], [[30, 32], [30, 36], [30, 32]]),
        "victory": A(["cheer", "idle0", "cheer"], [12, 12, 12], [[36, 24], [36, 34], [36, 24]]),
        "entrance": A(["fall", "squash", "idle0"], [6, 6, 6], [[36, 33], [36, 38], [36, 34]], loop=False),
        "throw": A(["windup", "strike", "follow"], [8, 6, 10], [[30, 30], [40, 30], [38, 34]], loop=False),
        # 攻击姿势：恰好 3 帧（前摇 / 生效 / 后摇），不写 durations
        "jab1": A(["windup", "strike", "follow"], hands=[[33, 32], [38, 32], [37, 33]]),
        "jab2": A(["follow", "strike", "follow"], hands=[[36, 36], [39, 30], [37, 33]]),
        "jab3": A(["windup", "strike", "follow"], hands=[[31, 26], [39, 30], [38, 36]]),
        "smash": A(["windup", "strike", "follow"], hands=[[28, 26], [40, 31], [39, 36]]),
        "upslash": A(["windup", "strike", "follow"], hands=[[34, 36], [36, 24], [36, 28]]),
        "poke": A(["windup", "strike", "follow"], hands=[[32, 38], [40, 40], [38, 39]]),
        "spin": A(["air", "air", "air"], hands=[[36, 30], [36, 30], [36, 30]]),
        "meteor": A(["air", "strike", "fall"], hands=[[34, 26], [38, 36], [36, 34]]),
        "rise": A(["squash", "jump", "air"], hands=[[36, 34], [36, 24], [36, 28]]),
        "counter": A(["guard", "strike", "follow"], hands=[[33, 36], [39, 31], [37, 34]]),
        "riposte": A(["windup", "strike", "follow"], hands=[[31, 28], [40, 31], [38, 35]]),
        "grab": A(["windup", "strike", "follow"], hands=[[33, 34], [38, 34], [36, 34]]),
        "wave": A(["windup", "strike", "follow"], hands=[[31, 28], [39, 31], [38, 34]]),
        "ult": A(["cheer", "strike", "follow"], hands=[[34, 18], [40, 30], [38, 36]]),
    }
    slash_sfx = {"wave_type": 3, "p_env_sustain": 0.04, "p_env_decay": 0.14, "p_base_freq": 0.75, "p_freq_ramp": -0.4, "sound_vol": 0.3}
    data = {
        "format": 1,
        "name": "罐头骑士",
        "frame_size": [FW, FH],
        "anchor": [AX, AY],
        "stats": {"hp": 105, "body": [22, 32], "weight": 5, "gravity": 0.38, "max_fall": 5, "air_control": 0.55},
        "held": "sword",
        "assets": {
            "sword": {"kind": "weapon", "image": "sword.png", "grip": [2, 3], "length": 23, "radius": 3, "hit_range": [0.25, 1]},
            "fist": {"kind": "weapon", "image": "fist.png", "grip": [2, 3], "length": 8, "radius": 5, "hit_range": [0, 1]},
            "wave": {"kind": "projectile", "image": "wave.png", "shape": "rect", "size": [10, 8]},
            "spark": {"kind": "fx", "image": "spark.png", "frames": 3, "durations": [3, 3, 4]},
            "ult_bg": {"kind": "backdrop", "image": "ult_bg.png", "frames": 2, "durations": [6, 6]},
            "slash": {"kind": "sfx", "params": slash_sfx},
            "heavy": {"kind": "sfx", "params": dict(slash_sfx, p_base_freq=0.45, p_env_decay=0.3, sound_vol=0.4)},
            "zing": {"kind": "sfx", "params": {"wave_type": 1, "p_env_sustain": 0.1, "p_env_decay": 0.2, "p_base_freq": 0.6, "p_freq_ramp": -0.25, "p_duty": 0.3, "sound_vol": 0.25}},
            "fanfare": {"kind": "sfx", "params": {"wave_type": 0, "p_env_sustain": 0.35, "p_env_decay": 0.5, "p_base_freq": 0.35, "p_arp_mod": 0.5, "p_arp_speed": 0.55, "p_duty": 0.4, "sound_vol": 0.35}},
        },
        "anims": anims,
        "actions": {
            "move": {"type": "move", "speed": 2.2, "accel": 0.4},
            "jump": {"type": "jump", "velocity": 6.6, "max_count": 2, "extra_anim": "double_jump"},
            "jab1": {"type": "swing", "anim": "jab1", "weapon": "sword", "from": 70, "to": -20, "reach": [0, 2],
                     "startup": 4, "active": 3, "recovery": 10, "damage": 4, "knockback": {"angle": 30, "force": 8},
                     "sfx": {"start": "slash"},
                     "links": [{"when": "on_hit", "input": "attack", "window": [4, 16], "goto": "jab2"}]},
            "jab2": {"type": "swing", "anim": "jab2", "weapon": "sword", "from": -30, "to": 70, "reach": [0, 2],
                     "startup": 3, "active": 3, "recovery": 10, "damage": 4, "knockback": {"angle": 50, "force": 10},
                     "sfx": {"start": "slash"},
                     "links": [{"when": "on_hit", "input": "attack", "window": [3, 15], "goto": "jab3"}]},
            "jab3": {"type": "swing", "anim": "jab3", "weapon": "sword", "from": 120, "to": -40, "reach": [0, 4],
                     "startup": 6, "active": 4, "recovery": 16, "damage": 7, "knockback": {"angle": 40, "force": 34},
                     "sfx": {"start": "heavy"}, "links": [{"when": "on_hit", "fx": "spark"}]},
            "smash": {"type": "swing", "anim": "smash", "weapon": "sword", "from": 110, "to": -50, "reach": [0, 6],
                      "startup": 14, "active": 4, "recovery": 22, "damage": 10, "knockback": {"angle": 38, "force": 48},
                      "charge": {"max": 40, "damage": 1.4, "force": 1.3},
                      "motion": [{"frame": 12, "vel": [2.5, 0]}, {"frame": 18, "vel": [0, 0]}],
                      "effects": [{"fx": "spark", "frame": 14, "offset": [30, 14]}],
                      "sfx": {"start": "heavy"}, "links": [{"when": "on_hit", "fx": "spark"}]},
            "upslash": {"type": "swing", "anim": "upslash", "weapon": "sword", "from": 170, "to": 30, "reach": [0, 2],
                        "startup": 5, "active": 4, "recovery": 12, "damage": 6, "knockback": {"angle": 88, "force": 30},
                        "sfx": {"start": "slash"}},
            "poke": {"type": "swing", "anim": "poke", "weapon": "sword", "from": -15, "to": -15, "reach": [0, 8],
                     "startup": 5, "active": 3, "recovery": 12, "damage": 5, "knockback": {"angle": 20, "force": 26},
                     "require": "ground", "sfx": {"start": "slash"}},
            "spin": {"type": "swing", "anim": "spin", "weapon": "sword", "from": 180, "to": -180, "reach": [0, 0],
                     "startup": 5, "active": 8, "recovery": 10, "damage": 3, "hit_interval": 4,
                     "knockback": {"angle": 45, "force": 18}, "require": "air", "sfx": {"start": "slash"}},
            "meteor": {"type": "swing", "anim": "meteor", "weapon": "sword", "from": -40, "to": -120, "reach": [0, 2],
                       "startup": 9, "active": 4, "recovery": 14, "damage": 8, "knockback": {"angle": -70, "force": 30},
                       "require": "air", "sfx": {"start": "heavy"}},
            "rise": {"type": "swing", "anim": "rise", "weapon": "sword", "from": 80, "to": 100, "reach": [0, 2],
                     "startup": 4, "active": 10, "recovery": 18, "damage": 5, "knockback": {"angle": 80, "force": 30},
                     "cooldown": 60, "invuln": [0, 5], "gravity_scale": 0.6,
                     "motion": [{"frame": 3, "vel": [1.5, 6.5]}, {"frame": 14, "vel": [0.5, 1]}], "sfx": {"start": "zing"},
                     "effects": [{"fx": "spark", "frame": 2, "offset": [0, 2], "behind": True},
                                 {"fx": "spark", "frame": 6, "offset": [4, 30], "follow": True}]},
            "counter": {"type": "swing", "anim": "counter", "weapon": "sword", "from": 60, "to": -30, "reach": [0, 2],
                        "startup": 14, "active": 3, "recovery": 18, "damage": 6, "knockback": {"angle": 40, "force": 30},
                        "armor": [0, 13], "cooldown": 30,
                        "links": [{"when": "on_hurt", "window": [0, 13], "goto": "riposte"}]},
            "riposte": {"type": "swing", "anim": "riposte", "weapon": "sword", "from": 100, "to": -60, "reach": [0, 4],
                        "startup": 3, "active": 4, "recovery": 16, "damage": 7, "knockback": {"angle": 45, "force": 27},
                        "sfx": {"start": "heavy"}, "links": [{"when": "on_start", "fx": "spark"}]},
            "grab": {"type": "swing", "anim": "grab", "weapon": "fist", "from": 0, "to": 0, "reach": [0, 10],
                     "startup": 6, "active": 4, "recovery": 18, "damage": 2, "grab": True,
                     "knockback": {"angle": 0, "force": 0}, "require": "ground",
                     "links": [{"when": "on_hit", "goto": "throw"}]},
            "throw": {"type": "pose", "anim": "throw",
                      "throw": {"frame": 10, "damage": 7, "knockback": {"angle": 40, "force": 45}}, "sfx": {"start": "heavy"}},
            "wave": {"type": "shoot", "anim": "wave", "weapon": "sword", "projectile": "wave", "aim": "fixed", "angle": 0,
                     "speed": 5, "lifetime": 40, "startup": 12, "active": 2, "recovery": 18, "damage": 5,
                     "knockback": {"angle": 25, "force": 20}, "cooldown": 40, "sfx": {"start": "zing"}},
            "excalibur": {"type": "swing", "anim": "ult", "weapon": "sword", "from": 90, "to": -90, "reach": [0, 6],
                          "startup": 60, "active": 6, "recovery": 30, "damage": 24, "area": "screen", "ultimate": True,
                          "knockback": {"angle": 60, "force": 72}, "sfx": {"start": "fanfare"}, "backdrop": "ult_bg",
                          "effects": [{"fx": "spark", "frame": 58, "offset": [0, 40], "follow": True}]},
        },
        "input": {
            "attack.neutral": "jab1", "attack.side": "smash", "attack.up": "upslash", "attack.down": "poke",
            "attack.neutral.air": "spin", "attack.side.air": "spin", "attack.down.air": "meteor",
            "special.neutral": "wave", "special.side": "grab", "special.up": "rise", "special.down": "counter",
            "jump": "jump",
        },
    }
    json.dump(data, open(os.path.join(HERE, "character.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    build()
