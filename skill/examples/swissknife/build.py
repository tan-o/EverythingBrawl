#!/usr/bin/env python3
"""示例：可切换武器角色「瑞士军刀」-- 剑 / 斧 / 弓三种武器循环切换。

演示机制：资源 wrap（武器槽 0->1->2->0）、forms（按槽位换 held / 动画 / 属性 / 输入）、
pose 切换动作（cooldown + on_end gain）、斧的霸体（armor）、弓箭（bullet + gravity / aim input）、
非全屏大招（巨箭，尺寸上限 x3）。

运行：python build.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))
from pixel import blank, set_px, rect, Sheet  # noqa: E402

K = "#222034"
RD = "#ac3232"
R = "#d95763"
RL = "#e88a8a"
W = "#ffffff"
S = "#cbdbfc"
D = "#8b9bb4"
G = "#595652"
BR = "#8f563b"
BRL = "#d9a066"
GO = "#fbf236"

FW = FH = 48
AX, AY = 24, 48


def knife(dy=0, squash=0, lean=0, legs="stand", eyes="open", tools=False):
    """红色圆角刀身 + 白十字；tools=True 时头顶露出工具尖。"""
    im = blank(FW, FH)
    leg_h = 2 if legs == "tuck" else 4
    H = 26 - squash
    bottom = FH - 1 - leg_h + dy
    top = bottom - H + 1
    w = 20

    def off(y):
        return int(round(lean * (bottom - y) / float(H)))

    for y in range(top, bottom + 1):
        ry = y - top
        x0 = 14 + off(y)
        for rx in range(w):
            corner = (ry in (0, H - 1) and rx in (0, 1, w - 2, w - 1)) or (ry in (1, H - 2) and rx in (0, w - 1))
            if corner:
                continue
            edge = rx in (0, w - 1) or ry in (0, H - 1) or (ry in (1, H - 2) and rx in (1, w - 2)) or (rx in (1, w - 2) and ry in (1, H - 2))
            if edge:
                c = K
            elif rx in (2, 3):
                c = RL
            elif rx >= w - 4:
                c = RD
            else:
                c = R
            set_px(im, [(x0 + rx, y)], c)
    # 白十字（偏下）
    cy = top + H // 2 + 3
    cx = 14 + off(cy) + w // 2 - 1
    rect(im, cx - 1, cy - 4, cx + 1, cy + 4, W)
    rect(im, cx - 4, cy - 1, cx + 4, cy + 1, W)
    # 眼睛
    ey = top + 5
    ex = 14 + off(ey) + 11
    if eyes == "open":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1)], K)
    elif eyes == "angry":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1), (ex - 1, ey - 2), (ex + 5, ey - 2)], K)
    elif eyes == "closed":
        set_px(im, [(ex - 1, ey + 1), (ex, ey + 1), (ex + 4, ey + 1), (ex + 5, ey + 1)], K)
    else:
        for e in (ex, ex + 4):
            set_px(im, [(e - 1, ey - 1), (e + 1, ey - 1), (e, ey), (e - 1, ey + 1), (e + 1, ey + 1)], K)
    if tools:
        tx = 14 + off(top) + 4
        rect(im, tx, top - 4, tx + 1, top - 1, S)
        rect(im, tx + 9, top - 3, tx + 10, top - 1, D)
    lx = {"stand": (17, 27), "walk1": (15, 28), "walk2": (19, 25), "tuck": (17, 27), "spread": (14, 30)}[legs]
    for x in lx:
        xo = x + off(bottom)
        rect(im, xo, bottom + 1, xo + 1, bottom + leg_h, G)
        rect(im, xo, bottom + leg_h, xo + 2, bottom + leg_h, K)
    return im


def lying():
    im = blank(FW, FH)
    body = knife(eyes="x").crop((14, 18, 34, 44))
    rot = body.rotate(90, expand=True)
    im.alpha_composite(rot, (10, FH - rot.height))
    return im


def weapons():
    out = {}
    sw = blank(22, 7)
    rect(sw, 0, 1, 3, 5, S)
    rect(sw, 4, 0, 4, 6, GO)
    rect(sw, 5, 2, 20, 4, S)
    rect(sw, 5, 2, 20, 2, W)
    set_px(sw, [(21, 3)], S)
    out["sword.png"] = sw
    ax = blank(22, 14)
    rect(ax, 0, 5, 3, 9, S)
    rect(ax, 4, 6, 17, 8, BR)
    rect(ax, 4, 6, 17, 6, BRL)
    rect(ax, 14, 1, 20, 12, D)
    rect(ax, 15, 0, 19, 13, S)
    rect(ax, 19, 1, 21, 12, W)
    out["axe.png"] = ax
    bow = blank(12, 26)
    for y in range(26):
        x = int(round(6 - 6 * (1 - ((y - 12.5) / 12.5) ** 2)))
        set_px(bow, [(x + 5, y), (x + 6, y)], BR)
        set_px(bow, [(4, y)], W)
    rect(bow, 0, 11, 3, 15, S)
    out["bow.png"] = bow
    arrow = blank(16, 4)
    rect(arrow, 0, 1, 12, 2, BRL)
    rect(arrow, 13, 0, 15, 3, S)
    set_px(arrow, [(0, 0), (1, 0), (0, 3), (1, 3)], W)
    out["arrow.png"] = arrow
    big = blank(60, 16)
    rect(big, 0, 6, 46, 9, BRL)
    rect(big, 0, 6, 46, 6, GO)
    for i in range(14):
        rect(big, 46 + i, i // 2 + 1, 46 + i, 14 - i // 2, S if i < 12 else W)
    for i in range(6):
        rect(big, i, 2 + i // 2, i, 5, R)
        rect(big, i, 10, i, 13 - i // 2, R)
    out["bigarrow.png"] = big
    icon = blank(12, 12)
    rect(icon, 1, 1, 10, 10, R)
    rect(icon, 5, 2, 6, 9, W)
    rect(icon, 2, 5, 9, 6, W)
    out["slot.png"] = icon
    return out


def build():
    sh = Sheet(FW, FH, cols=8)
    f = {}
    f["idle0"] = sh.add(knife())
    f["idle1"] = sh.add(knife(squash=1))
    f["heavy0"] = sh.add(knife(squash=1, legs="spread", eyes="angry"))
    f["walk1"] = sh.add(knife(dy=-1, legs="walk1"))
    f["walk2"] = sh.add(knife(dy=-1, legs="walk2"))
    f["jump"] = sh.add(knife(dy=-2, legs="tuck", lean=1))
    f["fall"] = sh.add(knife(legs="spread", eyes="closed"))
    f["squash"] = sh.add(knife(squash=4, legs="spread"))
    f["hurt"] = sh.add(knife(lean=-4, eyes="x"))
    f["guard"] = sh.add(knife(squash=2, eyes="closed", legs="spread"))
    f["windup"] = sh.add(knife(lean=-3, eyes="angry"))
    f["strike"] = sh.add(knife(lean=4, eyes="angry", legs="walk1"))
    f["follow"] = sh.add(knife(lean=2, legs="spread", eyes="angry"))
    f["ko1"] = sh.add(knife(lean=-7, eyes="x", legs="spread"))
    f["ko2"] = sh.add(lying())
    f["tools"] = sh.add(knife(tools=True, eyes="closed"))
    f["cheer"] = sh.add(knife(dy=-3, legs="spread", eyes="closed", tools=True))
    sh.save(os.path.join(HERE, "sheet.png"))
    for n, im in weapons().items():
        im.save(os.path.join(HERE, n))

    def A(frames, durations=None, hands=None, loop=True):
        a = {"frames": [f[x] for x in frames]}
        if durations is not None:
            a["durations"] = durations
            a["loop"] = loop
        a["hand"] = hands or [[35, 34]] * len(frames)
        return a

    anims = {
        "idle": A(["idle0", "idle1", "idle0"], [20, 14, 20], [[35, 34], [35, 35], [35, 34]]),
        "idle_heavy": A(["heavy0", "idle1", "heavy0"], [24, 16, 24], [[35, 36], [35, 36], [35, 36]]),
        "walk": A(["walk1", "idle0", "walk2", "idle0"], [6, 6, 6, 6], [[35, 33], [35, 34], [35, 33], [35, 34]]),
        "jump": A(["jump"] * 3, [4, 4, 4], [[35, 31]] * 3, loop=False),
        "fall": A(["fall"] * 3, [6, 6, 6], [[35, 33]] * 3),
        "land": A(["squash", "idle1", "idle0"], [4, 3, 3], [[35, 38], [35, 35], [35, 34]], loop=False),
        "hurt": A(["hurt"] * 3, [5, 5, 5], [[31, 33]] * 3),
        "guard": A(["guard"] * 3, [10, 10, 10], [[32, 36]] * 3),
        "ko": A(["hurt", "ko1", "ko2"], [10, 10, 30], [[31, 33], [29, 36], [30, 44]], loop=False),
        "switch": A(["tools", "squash", "tools"], [8, 6, 10], [[35, 30], [35, 38], [35, 30]], loop=False),
        "victory": A(["cheer", "idle0", "cheer"], [12, 12, 12], [[35, 26], [35, 34], [35, 26]]),
        "slash": A(["windup", "strike", "follow"], hands=[[32, 30], [38, 31], [37, 34]]),
        "lunge": A(["windup", "strike", "follow"], hands=[[31, 34], [40, 33], [38, 34]]),
        "chop": A(["windup", "strike", "follow"], hands=[[30, 24], [39, 32], [38, 38]]),
        "sweep": A(["windup", "strike", "follow"], hands=[[31, 36], [39, 38], [38, 38]]),
        "draw": A(["windup", "follow", "follow"], hands=[[34, 33], [36, 32], [36, 33]]),
        "volley": A(["windup", "follow", "follow"], hands=[[34, 30], [36, 28], [36, 30]]),
        "ultdraw": A(["cheer", "strike", "follow"], hands=[[34, 28], [37, 32], [36, 33]]),
    }
    data = {
        "format": 1,
        "name": "瑞士军刀",
        "frame_size": [FW, FH],
        "anchor": [AX, AY],
        "stats": {"hp": 100, "body": [20, 30], "weight": 5, "gravity": 0.38, "max_fall": 5, "air_control": 0.6},
        "held": "sword",
        "resources": {"slot": {"init": 0, "max": 2, "wrap": True, "keep_on_ko": True, "hud": "slot"}},
        "assets": {
            "sword": {"kind": "weapon", "image": "sword.png", "grip": [1, 3], "length": 20, "radius": 3, "hit_range": [0.2, 1]},
            "axe": {"kind": "weapon", "image": "axe.png", "grip": [1, 7], "length": 20, "radius": 6, "hit_range": [0.6, 1]},
            "bow": {"kind": "weapon", "image": "bow.png", "grip": [2, 13], "length": 6, "radius": 2, "hit_range": [0, 1]},
            "arrow": {"kind": "projectile", "image": "arrow.png", "shape": "rect", "size": [16, 4]},
            "bigarrow": {"kind": "projectile", "image": "bigarrow.png", "shape": "rect", "size": [60, 16]},
            "slot": {"kind": "icon", "image": "slot.png"},
            "click": {"kind": "sfx", "params": {"wave_type": 0, "p_env_sustain": 0.03, "p_env_decay": 0.08, "p_base_freq": 0.8, "p_duty": 0.5, "sound_vol": 0.25}},
            "twang": {"kind": "sfx", "params": {"wave_type": 1, "p_env_sustain": 0.05, "p_env_decay": 0.25, "p_base_freq": 0.5, "p_freq_ramp": -0.2, "p_vib_strength": 0.3, "p_vib_speed": 0.6, "sound_vol": 0.3}},
            "whack": {"kind": "sfx", "params": {"wave_type": 3, "p_env_sustain": 0.06, "p_env_decay": 0.25, "p_base_freq": 0.3, "p_freq_ramp": -0.2, "sound_vol": 0.4}},
        },
        "anims": anims,
        "actions": {
            "move": {"type": "move", "speed": 2.1, "accel": 0.4},
            "jump": {"type": "jump", "velocity": 6.5, "max_count": 1},
            "switch": {"type": "pose", "anim": "switch", "cooldown": 30, "sfx": {"start": "click"},
                       "links": [{"when": "on_end", "gain": {"slot": 1}}]},
            "sword_cut": {"type": "swing", "anim": "slash", "weapon": "sword", "from": 80, "to": -30, "reach": [0, 2],
                          "startup": 5, "active": 3, "recovery": 11, "damage": 6, "knockback": {"angle": 35, "force": 22}},
            "sword_lunge": {"type": "swing", "anim": "lunge", "weapon": "sword", "from": 0, "to": 0, "reach": [0, 10],
                            "startup": 9, "active": 4, "recovery": 16, "damage": 8, "knockback": {"angle": 25, "force": 38},
                            "motion": [{"frame": 8, "vel": [3, 0]}, {"frame": 14, "vel": [0, 0]}]},
            "axe_chop": {"type": "swing", "anim": "chop", "weapon": "axe", "from": 120, "to": -60, "reach": [0, 2],
                         "startup": 16, "active": 4, "recovery": 22, "damage": 15, "knockback": {"angle": 45, "force": 55},
                         "armor": [4, 18], "sfx": {"hit": "whack"}},
            "axe_sweep": {"type": "swing", "anim": "sweep", "weapon": "axe", "from": -10, "to": -40, "reach": [0, 2],
                          "startup": 12, "active": 4, "recovery": 18, "damage": 10, "knockback": {"angle": 70, "force": 40},
                          "sfx": {"hit": "whack"}},
            "arrow": {"type": "shoot", "anim": "draw", "weapon": "bow", "projectile": "arrow", "aim": "input", "angle": 5,
                      "speed": 5, "lifetime": 70, "gravity": 0.06, "startup": 12, "active": 2, "recovery": 12, "damage": 7,
                      "knockback": {"angle": 20, "force": 22}, "sfx": {"start": "twang"}},
            "volley": {"type": "shoot", "anim": "volley", "weapon": "bow", "projectile": "arrow", "aim": "fixed", "angle": 50,
                       "count": 3, "spread": 30, "speed": 4.5, "lifetime": 60, "gravity": 0.15, "startup": 16, "active": 2,
                       "recovery": 16, "damage": 4, "cooldown": 45, "knockback": {"angle": 60, "force": 18},
                       "sfx": {"start": "twang"}},
            "giant_arrow": {"type": "shoot", "anim": "ultdraw", "weapon": "bow", "projectile": "bigarrow", "aim": "fixed",
                            "angle": 0, "speed": 4.5, "lifetime": 110, "pierce": 2, "startup": 50, "active": 2,
                            "recovery": 24, "damage": 20, "ultimate": True, "knockback": {"angle": 30, "force": 85},
                            "sfx": {"start": "twang"}},
        },
        "forms": [
            {"if": {"slot": "==1"}, "held": "axe", "anims": {"idle": "idle_heavy"}, "stats": {"weight": 7},
             "input": {"attack.neutral": "axe_sweep", "attack.side": "axe_chop"}},
            {"if": {"slot": "==2"}, "held": "bow", "stats": {"weight": 4},
             "input": {"attack.neutral": "arrow", "attack.side": "arrow", "attack.up": "volley"}},
        ],
        "input": {"attack.neutral": "sword_cut", "attack.side": "sword_lunge", "special.down": "switch", "jump": "jump"},
    }
    json.dump(data, open(os.path.join(HERE, "character.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    build()
