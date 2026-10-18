#!/usr/bin/env python3
"""示例：发展型角色「工具箱」—— 采集 → 合成 → 升级 → 工具损坏。

演示机制：
  采集：按住特殊键持续伐木（on_release + every gain），锤子命中也能获得木头（on_hit gain）
  合成：消耗 3 木头（cost），升级 tier 并把耐久设满（on_end gain / set）
  升级：锤子按 tier 升级（upgrades：伤害、范围、眩晕），held 武器随 tier 变化（forms），升级时播放 levelup
  损坏：命中消耗耐久（on_hit spend，if tier>=1），耐久归零（角色级 resource_empty）→ tier 归零并 goto 损坏动作
  另有：炮台布置物（every spawn bullet）、角色级持续回复（every heal）、HUD 图标与条
运行：python build.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))
from pixel import blank, set_px, rect, Sheet  # noqa: E402

K = "#222034"
B = "#5b6ee1"   # 箱体蓝
BL = "#639bff"
BD = "#3f3f74"
S = "#cbdbfc"
D = "#8b9bb4"
G = "#595652"
W = "#ffffff"
BR = "#8f563b"
BRL = "#d9a066"
STN = "#9badb7"
IRN = "#847e87"
GO = "#fbf236"
GR = "#6abe30"

FW = FH = 48
AX, AY = 24, 48


def box(dy=0, squash=0, lean=0, legs="stand", eyes="open", lid=0):
    """蓝色工具箱：顶部提手，正面银色锁扣。lid>0 时盖子掀开（合成）。"""
    im = blank(FW, FH)
    leg_h = 2 if legs == "tuck" else 4
    H = 22 - squash
    bottom = FH - 1 - leg_h + dy
    top = bottom - H + 1
    w = 24

    def off(y):
        return int(round(lean * (bottom - y) / float(H)))

    for y in range(top, bottom + 1):
        ry = y - top
        x0 = 12 + off(y)
        for rx in range(w):
            if rx in (0, w - 1) or ry in (0, H - 1):
                c = K
            elif ry == 5:
                c = BD
            elif rx in (1, 2) or ry in (1,):
                c = BL
            elif rx >= w - 3:
                c = BD
            else:
                c = B
            set_px(im, [(x0 + rx, y)], c)
    # 锁扣
    lx = 12 + off(top + 5) + w // 2 - 2
    rect(im, lx, top + 4, lx + 3, top + 7, S)
    set_px(im, [(lx + 1, top + 6), (lx + 2, top + 6)], D)
    # 提手
    hx = 12 + off(top) + 7
    hy = top - 3 - lid
    rect(im, hx, hy, hx + 9, hy, K)
    rect(im, hx, hy, hx, top - 1, K)
    rect(im, hx + 9, hy, hx + 9, top - 1, K)
    rect(im, hx + 1, hy + 1, hx + 8, hy + 1, D)
    # 眼睛
    ey = top + 10
    ex = 12 + off(ey) + 15
    if eyes == "open":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1)], K)
    elif eyes == "happy":
        set_px(im, [(ex - 1, ey + 1), (ex, ey), (ex + 1, ey + 1), (ex + 3, ey + 1), (ex + 4, ey), (ex + 5, ey + 1)], K)
    elif eyes == "angry":
        set_px(im, [(ex, ey), (ex, ey + 1), (ex + 4, ey), (ex + 4, ey + 1), (ex - 1, ey - 2), (ex + 5, ey - 2)], K)
    elif eyes == "closed":
        set_px(im, [(ex - 1, ey + 1), (ex, ey + 1), (ex + 4, ey + 1), (ex + 5, ey + 1)], K)
    else:
        for e in (ex, ex + 4):
            set_px(im, [(e - 1, ey - 1), (e + 1, ey - 1), (e, ey), (e - 1, ey + 1), (e + 1, ey + 1)], K)
    lxs = {"stand": (16, 29), "walk1": (14, 30), "walk2": (18, 27), "tuck": (16, 29), "spread": (13, 32)}[legs]
    for x in lxs:
        xo = x + off(bottom)
        rect(im, xo, bottom + 1, xo + 1, bottom + leg_h, G)
        rect(im, xo, bottom + leg_h, xo + 2, bottom + leg_h, K)
    return im


def lying():
    im = blank(FW, FH)
    body = box(eyes="x").crop((12, 19, 36, 44))
    rot = body.rotate(90, expand=True)
    im.alpha_composite(rot, (12, FH - rot.height))
    return im


def hammer(head, head_hi):
    im = blank(20, 11)
    rect(im, 0, 4, 2, 6, D)
    rect(im, 3, 4, 13, 6, BR)
    rect(im, 3, 4, 13, 4, BRL)
    rect(im, 13, 0, 19, 10, head)
    rect(im, 13, 0, 19, 1, head_hi)
    rect(im, 13, 0, 13, 10, K)
    return im


def images():
    out = {
        "hammer1.png": hammer(BRL, "#eec39a"),
        "hammer2.png": hammer(STN, S),
        "hammer3.png": hammer(IRN, W),
    }
    wood = blank(12, 10)
    rect(wood, 0, 2, 11, 7, BR)
    rect(wood, 0, 2, 11, 2, BRL)
    rect(wood, 9, 3, 11, 6, BRL)
    set_px(wood, [(10, 4), (10, 5)], BR)
    out["wood.png"] = wood
    gem = blank(10, 10)
    for y in range(10):
        hw = 5 - abs(y - 4.5)
        rect(gem, int(5 - hw), y, int(4 + hw), y, GR if y > 3 else "#99e550")
    out["gem.png"] = gem
    turret = blank(14, 14)
    rect(turret, 1, 6, 12, 13, IRN)
    rect(turret, 1, 6, 12, 6, S)
    rect(turret, 4, 2, 9, 6, D)
    rect(turret, 9, 3, 13, 4, K)
    out["turret.png"] = turret
    nail = blank(8, 3)
    rect(nail, 0, 0, 1, 2, D)
    rect(nail, 2, 1, 7, 1, S)
    out["nail.png"] = nail
    puff = blank(48, 16)
    for i in range(3):
        r = 3 + i * 2
        for y in range(16):
            for x in range(16):
                d = (x - 7.5) ** 2 + (y - 7.5) ** 2
                if r * r - 6 <= d <= r * r + 4:
                    set_px(puff, [(i * 16 + x, y)], W if i < 2 else D)
    out["puff.png"] = puff
    return out


def build():
    sh = Sheet(FW, FH, cols=8)
    f = {}
    f["idle0"] = sh.add(box())
    f["idle1"] = sh.add(box(squash=1))
    f["walk1"] = sh.add(box(dy=-1, legs="walk1"))
    f["walk2"] = sh.add(box(dy=-1, legs="walk2"))
    f["jump"] = sh.add(box(dy=-2, legs="tuck", lean=1))
    f["fall"] = sh.add(box(legs="spread", eyes="closed"))
    f["squash"] = sh.add(box(squash=4, legs="spread"))
    f["hurt"] = sh.add(box(lean=-4, eyes="x"))
    f["guard"] = sh.add(box(squash=2, eyes="closed", legs="spread"))
    f["windup"] = sh.add(box(lean=-3, eyes="angry"))
    f["strike"] = sh.add(box(lean=4, eyes="angry", legs="walk1"))
    f["follow"] = sh.add(box(lean=2, legs="spread", eyes="angry"))
    f["ko1"] = sh.add(box(lean=-7, eyes="x", legs="spread"))
    f["ko2"] = sh.add(lying())
    f["open1"] = sh.add(box(lid=2, eyes="happy"))
    f["open2"] = sh.add(box(lid=4, eyes="happy", dy=-1))
    f["sad"] = sh.add(box(squash=3, eyes="x", legs="spread"))
    sh.save(os.path.join(HERE, "sheet.png"))
    for n, im in images().items():
        im.save(os.path.join(HERE, n))

    def A(frames, durations=None, hands=None, loop=True, hold=None):
        a = {"frames": [f[x] for x in frames]}
        if durations is not None:
            a["durations"] = durations
            a["loop"] = loop
        if hold is not None:
            a["hold"] = hold
        a["hand"] = hands or [[37, 36]] * len(frames)
        return a

    anims = {
        "idle": A(["idle0", "idle1", "idle0"], [22, 14, 22], [[37, 36], [37, 37], [37, 36]]),
        "walk": A(["walk1", "idle0", "walk2", "idle0"], [6, 6, 6, 6], [[37, 35], [37, 36], [37, 35], [37, 36]]),
        "jump": A(["jump"] * 3, [4, 4, 4], [[37, 33]] * 3, loop=False),
        "double_jump": A(["jump", "fall", "jump"], [3, 3, 3], [[37, 33]] * 3, loop=False),
        "fall": A(["fall"] * 3, [6, 6, 6], [[37, 35]] * 3),
        "land": A(["squash", "idle1", "idle0"], [4, 3, 3], [[37, 40], [37, 37], [37, 36]], loop=False),
        "hurt": A(["hurt"] * 3, [5, 5, 5], [[33, 35]] * 3),
        "guard": A(["guard"] * 3, [10, 10, 10], [[34, 38]] * 3),
        "ko": A(["hurt", "ko1", "ko2"], [10, 10, 30], [[33, 35], [31, 38], [30, 45]], loop=False),
        "charge": A(["windup", "strike", "windup"], [8, 8, 8], [[33, 30], [39, 38], [33, 30]]),
        "gather": A(["windup", "strike", "follow"], [8, 8, 8], [[33, 30], [39, 38], [38, 39]], loop=False),
        "craft": A(["open1", "open2", "open1"], [10, 14, 10], [[30, 30], [30, 26], [30, 30]], loop=False),
        "levelup": A(["open2", "open1", "open2"], [8, 8, 8], [[30, 26], [30, 30], [30, 26]], loop=False),
        "break": A(["sad", "sad", "idle1"], [10, 14, 10], [[33, 40]] * 3, loop=False),
        "victory": A(["open2", "idle0", "open2"], [12, 12, 12], [[30, 26], [37, 36], [30, 26]]),
        "bonk": A(["windup", "strike", "follow"], hands=[[32, 27], [39, 34], [38, 38]]),
        "swingup": A(["follow", "strike", "windup"], hands=[[36, 38], [37, 27], [34, 28]]),
        "build": A(["windup", "follow", "follow"], hands=[[34, 36], [38, 38], [38, 38]]),
        "nailgun": A(["windup", "strike", "follow"], hands=[[34, 36], [38, 36], [37, 36]]),
        "bigbonk": A(["open2", "strike", "follow"], hands=[[30, 20], [40, 34], [38, 38]]),
    }
    hammer_up = [
        {"if": {"tier": ">=1"}, "set": {"weapon": "hammer2", "damage": 8, "knockback": {"angle": 40, "force": 32}}},
        {"if": {"tier": ">=2"}, "set": {"weapon": "hammer3", "damage": 9, "reach": [0, 4],
                                        "status": {"type": "stun", "duration": 20}}},
    ]
    wear = {"when": "on_hit", "if": {"tier": ">=1"}, "spend": {"dur": 1}}
    data = {
        "format": 1,
        "name": "工具箱",
        "frame_size": [FW, FH],
        "anchor": [AX, AY],
        "stats": {"hp": 110, "body": [24, 26], "weight": 6, "gravity": 0.4, "max_fall": 5.5, "air_control": 0.5},
        "held": "hammer1",
        "resources": {
            "wood": {"init": 0, "max": 9, "hud": "wood"},
            "tier": {"init": 0, "max": 2, "hud": "gem"},
            "dur": {"init": 0, "max": 10, "hud": "bar"},
        },
        "assets": {
            "hammer1": {"kind": "weapon", "image": "hammer1.png", "grip": [1, 5], "length": 18, "radius": 5, "hit_range": [0.6, 1]},
            "hammer2": {"kind": "weapon", "image": "hammer2.png", "grip": [1, 5], "length": 18, "radius": 5, "hit_range": [0.6, 1]},
            "hammer3": {"kind": "weapon", "image": "hammer3.png", "grip": [1, 5], "length": 18, "radius": 5, "hit_range": [0.6, 1]},
            "wood": {"kind": "icon", "image": "wood.png"},
            "gem": {"kind": "icon", "image": "gem.png"},
            "turret": {"kind": "projectile", "image": "turret.png", "shape": "rect", "size": [14, 12]},
            "nail": {"kind": "projectile", "image": "nail.png", "shape": "rect", "size": [8, 3]},
            "puff": {"kind": "fx", "image": "puff.png", "frames": 3, "durations": [4, 4, 6]},
            "chop": {"kind": "sfx", "params": {"wave_type": 3, "p_env_sustain": 0.03, "p_env_decay": 0.12, "p_base_freq": 0.4, "sound_vol": 0.3}},
            "ding": {"kind": "sfx", "params": {"wave_type": 2, "p_env_sustain": 0.1, "p_env_decay": 0.4, "p_base_freq": 0.7, "p_arp_mod": 0.3, "p_arp_speed": 0.6, "sound_vol": 0.3}},
            "crack": {"kind": "sfx", "params": {"wave_type": 3, "p_env_sustain": 0.15, "p_env_decay": 0.3, "p_base_freq": 0.2, "p_freq_ramp": -0.15, "sound_vol": 0.4}},
        },
        "anims": anims,
        "actions": {
            "move": {"type": "move", "speed": 2.0, "accel": 0.35},
            "jump": {"type": "jump", "velocity": 6.4, "max_count": 2},
            "bonk": {"type": "swing", "anim": "bonk", "weapon": "hammer1", "from": 110, "to": -30, "reach": [0, 2],
                     "startup": 8, "active": 4, "recovery": 14, "damage": 6, "knockback": {"angle": 40, "force": 26},
                     "upgrades": hammer_up, "links": [{"when": "on_hit", "gain": {"wood": 1}}, wear]},
            "swingup": {"type": "swing", "anim": "swingup", "weapon": "hammer1", "from": -20, "to": 130, "reach": [0, 2],
                        "startup": 7, "active": 4, "recovery": 14, "damage": 5, "knockback": {"angle": 85, "force": 30},
                        "upgrades": [{"if": {"tier": ">=1"}, "set": {"weapon": "hammer2", "damage": 7}},
                                     {"if": {"tier": ">=2"}, "set": {"weapon": "hammer3", "damage": 8}}],
                        "links": [wear]},
            "gather": {"type": "pose", "anim": "gather", "require": "ground",
                       "links": [{"when": "every", "interval": 40, "gain": {"wood": 1}, "fx": "puff", "sfx": "chop"},
                                 {"when": "on_release", "fx": "puff"}]},
            "craft": {"type": "pose", "anim": "craft", "cost": {"wood": 3}, "cooldown": 30, "require": "ground",
                      "sfx": {"start": "ding"},
                      "links": [{"when": "on_end", "gain": {"tier": 1}}, {"when": "on_end", "set": {"dur": 10}}]},
            "break": {"type": "pose", "anim": "break", "sfx": {"start": "crack"},
                      "links": [{"when": "on_start", "fx": "puff"}]},
            "turret": {"type": "shoot", "anim": "build", "projectile": "turret", "aim": "fixed", "angle": 0, "speed": 0,
                       "lifetime": 300, "hp": 6, "startup": 14, "active": 2, "recovery": 14, "damage": 2,
                       "cost": {"wood": 2}, "cooldown": 120, "knockback": {"angle": 45, "force": 15},
                       "links": [{"when": "every", "interval": 60, "spawn": "nail"}]},
            "nail": {"type": "shoot", "anim": "nailgun", "projectile": "nail", "aim": "fixed", "angle": 0, "speed": 5,
                     "lifetime": 50, "startup": 6, "active": 2, "recovery": 10, "damage": 3,
                     "knockback": {"angle": 10, "force": 12}},
            "mega_bonk": {"type": "swing", "anim": "bigbonk", "weapon": "hammer3", "from": 150, "to": -60, "reach": [0, 4],
                          "startup": 45, "active": 5, "recovery": 26, "damage": 30, "ultimate": True,
                          "knockback": {"angle": 45, "force": 90}, "sfx": {"hit": "crack"}},
        },
        "forms": [
            {"if": {"tier": ">=1"}, "held": "hammer2"},
            {"if": {"tier": ">=2"}, "held": "hammer3"},
        ],
        "links": [
            {"when": "resource_empty", "resource": "dur", "set": {"tier": 0}, "goto": "break"},
            {"when": "every", "interval": 300, "heal": 2},
        ],
        "input": {
            "attack.neutral": "bonk", "attack.side": "bonk", "attack.up": "swingup", "attack.neutral.air": "swingup",
            "special.neutral": "gather", "special.down": "craft", "special.side": "turret", "special.up": "nail",
            "jump": "jump",
        },
    }
    json.dump(data, open(os.path.join(HERE, "character.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    build()
