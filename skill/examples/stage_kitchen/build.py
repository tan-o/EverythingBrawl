#!/usr/bin/env python3
"""示例场景「厨房台面」--假设照片是一张厨房台面：台面、砧板、麦片盒、饼干、烤面包机、灶台、水壶、托盘、糖罐。

照片里的物体 -> 场景元素：
  台面        solid 主地面
  砧板        platform 单向平台
  麦片盒      solid + climb（竖着的盒子可以贴墙攀爬，最多 90 帧）
  饼干        platform + crumble（站久了会碎，5 秒后恢复）
  烤面包机    solid + bounce（踩上去弹起来）
  灶台火      none + damage + blink（周期性点火，点火前闪烁预警）
  水壶蒸汽    none + wind（向上的气流）
  托盘        platform + move（上下移动）
  糖罐        solid + breakable（打碎后过一会儿恢复）
运行：python build.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))
from pixel import blank, rect, set_px  # noqa: E402

K = "#222034"
WOOD = "#d9a066"
WOOD_L = "#eec39a"
WOOD_D = "#8f563b"
WALL = "#cbdbfc"
WALL_L = "#ffffff"
WALL_D = "#9badb7"
SKY = "#5fcde4"
SKY_L = "#cbdbfc"
RED = "#d95763"
YEL = "#fbf236"
ORA = "#df7126"
SIL = "#cbdbfc"
SIL_D = "#847e87"
GRN = "#6abe30"
BRN = "#663931"


def background():
    w, h = 240, 135
    im = blank(w, h)
    rect(im, 0, 0, w - 1, h - 1, WALL)
    for y in range(0, h, 12):
        rect(im, 0, y, w - 1, y, WALL_D)
    for x in range(0, w, 12):
        rect(im, x, 0, x, h - 1, WALL_D)
    for y in range(0, h, 12):
        for x in range(0, w, 12):
            set_px(im, [(x + 2, y + 2), (x + 3, y + 2)], WALL_L)
    # 窗户
    rect(im, 140, 14, 200, 56, K)
    rect(im, 142, 16, 198, 54, SKY)
    rect(im, 142, 16, 198, 24, SKY_L)
    rect(im, 169, 16, 171, 54, K)
    rect(im, 142, 34, 198, 35, K)
    # 墙上的架子和杯子
    rect(im, 20, 40, 80, 42, WOOD_D)
    for i, c in enumerate((RED, GRN, YEL)):
        rect(im, 26 + i * 18, 32, 34 + i * 18, 39, c)
        rect(im, 26 + i * 18, 32, 34 + i * 18, 32, K)
    # 远处的冰箱轮廓
    rect(im, 210, 30, 236, 100, SIL_D)
    rect(im, 212, 32, 234, 64, SIL)
    rect(im, 212, 66, 234, 98, SIL)
    rect(im, 230, 44, 231, 54, K)
    return im


def tiles():
    t = {}
    counter = blank(16, 16)
    rect(counter, 0, 0, 15, 15, WOOD_D)
    rect(counter, 0, 0, 15, 2, WOOD_L)
    rect(counter, 0, 3, 15, 3, K)
    rect(counter, 0, 4, 15, 15, WOOD)
    rect(counter, 7, 6, 8, 13, WOOD_D)
    t["counter.png"] = counter
    board = blank(16, 4)
    rect(board, 0, 0, 15, 3, WOOD_L)
    rect(board, 0, 3, 15, 3, WOOD_D)
    t["board.png"] = board
    box = blank(16, 16)
    rect(box, 0, 0, 15, 15, RED)
    rect(box, 2, 3, 13, 9, YEL)
    rect(box, 4, 5, 11, 7, ORA)
    rect(box, 0, 0, 0, 15, K)
    rect(box, 15, 0, 15, 15, K)
    t["box.png"] = box
    cracker = blank(16, 4)
    rect(cracker, 0, 0, 15, 3, YEL)
    rect(cracker, 0, 3, 15, 3, ORA)
    set_px(cracker, [(3, 1), (8, 1), (13, 1)], ORA)
    t["cracker.png"] = cracker
    toaster = blank(16, 16)
    rect(toaster, 0, 0, 15, 15, SIL)
    rect(toaster, 0, 0, 15, 0, K)
    rect(toaster, 3, 2, 12, 3, K)
    rect(toaster, 0, 12, 15, 15, SIL_D)
    t["toaster.png"] = toaster
    flame = blank(8, 4)
    rect(flame, 0, 2, 7, 3, RED)
    set_px(flame, [(1, 1), (3, 0), (4, 1), (6, 1), (2, 1), (5, 0)], ORA)
    set_px(flame, [(3, 1), (4, 0)], YEL)
    t["flame.png"] = flame
    steam = blank(8, 8)
    set_px(steam, [(1, 1), (5, 3), (2, 6)], WALL_L)
    t["steam.png"] = steam
    tray = blank(16, 4)
    rect(tray, 0, 0, 15, 3, SIL_D)
    rect(tray, 0, 0, 15, 0, SIL)
    t["tray.png"] = tray
    jar = blank(14, 16)
    rect(jar, 0, 2, 13, 15, WALL_L)
    rect(jar, 2, 0, 11, 2, BRN)
    rect(jar, 0, 2, 0, 15, K)
    rect(jar, 13, 2, 13, 15, K)
    rect(jar, 2, 6, 11, 13, WALL)
    t["jar.png"] = jar
    return t


def build():
    background().save(os.path.join(HERE, "bg.png"))
    names = {}
    for n, im in tiles().items():
        im.save(os.path.join(HERE, n))
        names[n[:-4]] = {"kind": "tile", "image": n}
    assets = {"bg": {"kind": "background", "image": "bg.png"}}
    assets.update(names)
    data = {
        "format": 1,
        "kind": "stage",
        "name": "厨房台面",
        "background": "bg",
        "spawns": [[130, 200], [180, 200], [230, 200], [290, 200]],
        "assets": assets,
        "elements": [
            {"id": "counter", "rect": [72, 200, 336, 70], "collide": "solid", "tile": "counter"},
            {"id": "board", "rect": [120, 166, 80, 4], "collide": "platform", "tile": "board"},
            {"id": "cereal", "rect": [84, 140, 26, 60], "collide": "solid", "tile": "box", "climb": {"max": 90}},
            {"id": "cracker1", "rect": [220, 150, 40, 4], "collide": "platform", "tile": "cracker",
             "crumble": {"after": 60, "respawn": 300}},
            {"id": "cracker2", "rect": [270, 128, 40, 4], "collide": "platform", "tile": "cracker",
             "crumble": {"after": 60, "respawn": 300}},
            {"id": "toaster", "rect": [330, 184, 28, 16], "collide": "solid", "tile": "toaster", "bounce": {"velocity": 9}},
            {"id": "stove", "rect": [380, 196, 24, 4], "collide": "none", "tile": "flame",
             "damage": {"damage": 4, "interval": 45, "knockback": {"angle": 85, "force": 45}},
             "blink": {"on": 180, "off": 240, "warn": 45}},
            {"id": "steam", "rect": [296, 40, 40, 80], "collide": "none", "tile": "steam", "wind": [0, -0.12]},
            {"id": "tray", "rect": [400, 140, 40, 4], "collide": "platform", "tile": "tray",
             "move": {"path": [[0, 30], [0, -20]], "period": 240, "mode": "pingpong"}},
            {"id": "jar", "rect": [250, 184, 14, 16], "collide": "solid", "tile": "jar",
             "breakable": {"hp": 20, "respawn": 400}},
        ],
    }
    json.dump(data, open(os.path.join(HERE, "stage.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    build()
