#!/usr/bin/env python3
"""示例场景「书桌」——假设照片是一张书桌：桌面、键盘、直尺、一摞书、铅笔、咖啡杯、小风扇、台灯光斑。

照片里的物体 → 场景元素：
  桌面        solid 主地面
  键盘        solid + conveyor（站上去会被慢慢带着走）
  直尺        platform + move（左右来回）
  一摞书      solid + climb（可攀爬，最多 120 帧）
  铅笔        platform
  台灯光斑    platform + blink（亮时可以站，熄灭前闪烁）
  咖啡杯      none + water（掉进去下落变慢、移动变慢）
  小风扇      none + wind（把人往左吹）
  橡皮擦      platform + friction 0.3（很滑）
运行：python build.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts"))
from pixel import blank, rect, set_px  # noqa: E402

K = "#222034"
DESK = "#8f563b"
DESK_L = "#d9a066"
DESK_D = "#663931"
WALL = "#3f3f74"
WALL_L = "#5b6ee1"
POSTER = "#d77bba"
KEY = "#595652"
KEY_L = "#9badb7"
RULER = "#fbf236"
BOOK1 = "#ac3232"
BOOK2 = "#37946e"
BOOK3 = "#5fcde4"
PENCIL = "#df7126"
LIGHT = "#fff6bd"
COFFEE = "#663931"
FOAM = "#eec39a"
WIND = "#cbdbfc"
ERASER = "#d95763"
WHITE = "#ffffff"


def background():
    w, h = 240, 135
    im = blank(w, h)
    rect(im, 0, 0, w - 1, h - 1, WALL)
    for y in range(0, h, 2):
        if (y // 2) % 6 == 0:
            rect(im, 0, y, w - 1, y, WALL_L)
    # 墙上的海报与便签
    rect(im, 30, 20, 70, 60, K)
    rect(im, 32, 22, 68, 58, POSTER)
    rect(im, 40, 30, 60, 50, WHITE)
    for i, c in enumerate((RULER, BOOK3, ERASER)):
        rect(im, 160 + i * 14, 28 + (i % 2) * 6, 170 + i * 14, 38 + (i % 2) * 6, c)
    # 窗外夜景
    rect(im, 96, 14, 140, 50, K)
    rect(im, 98, 16, 138, 48, "#222034")
    for x, y in ((104, 22), (120, 30), (130, 20), (110, 40)):
        set_px(im, [(x, y)], LIGHT)
    return im


def tiles():
    t = {}
    desk = blank(16, 16)
    rect(desk, 0, 0, 15, 15, DESK)
    rect(desk, 0, 0, 15, 1, DESK_L)
    rect(desk, 0, 2, 15, 2, K)
    rect(desk, 0, 9, 15, 9, DESK_D)
    t["desk.png"] = desk
    key = blank(8, 8)
    rect(key, 0, 0, 7, 7, KEY)
    rect(key, 1, 1, 6, 5, KEY_L)
    rect(key, 0, 7, 7, 7, K)
    t["keyboard.png"] = key
    ruler = blank(16, 4)
    rect(ruler, 0, 0, 15, 3, RULER)
    for x in range(0, 16, 4):
        rect(ruler, x, 0, x, 1, K)
    t["ruler.png"] = ruler
    books = blank(16, 12)
    rect(books, 0, 0, 15, 3, BOOK1)
    rect(books, 1, 4, 15, 7, BOOK2)
    rect(books, 0, 8, 14, 11, BOOK3)
    for y in (3, 7, 11):
        rect(books, 0, y, 15, y, K)
    t["books.png"] = books
    pencil = blank(16, 4)
    rect(pencil, 0, 0, 13, 3, PENCIL)
    rect(pencil, 14, 1, 15, 2, DESK_L)
    rect(pencil, 0, 0, 1, 3, ERASER)
    t["pencil.png"] = pencil
    light = blank(8, 4)
    rect(light, 0, 0, 7, 3, LIGHT)
    rect(light, 0, 3, 7, 3, RULER)
    t["light.png"] = light
    coffee = blank(8, 8)
    rect(coffee, 0, 0, 7, 7, COFFEE)
    set_px(coffee, [(1, 1), (4, 2), (6, 5), (2, 6)], FOAM)
    t["coffee.png"] = coffee
    wind = blank(16, 8)
    rect(wind, 2, 2, 7, 2, WIND)
    rect(wind, 9, 6, 13, 6, WIND)
    t["wind.png"] = wind
    eraser = blank(16, 4)
    rect(eraser, 0, 0, 15, 3, ERASER)
    rect(eraser, 0, 0, 15, 0, WHITE)
    t["eraser.png"] = eraser
    return t


def build():
    background().save(os.path.join(HERE, "bg.png"))
    assets = {"bg": {"kind": "background", "image": "bg.png"}}
    for n, im in tiles().items():
        im.save(os.path.join(HERE, n))
        assets[n[:-4]] = {"kind": "tile", "image": n}
    data = {
        "format": 1,
        "kind": "stage",
        "name": "书桌",
        "background": "bg",
        "spawns": [[125, 206], [270, 206], [320, 206], [400, 206]],
        "assets": assets,
        "elements": [
            {"id": "desk", "rect": [60, 206, 360, 64], "collide": "solid", "tile": "desk"},
            {"id": "keyboard", "rect": [150, 198, 90, 8], "collide": "solid", "tile": "keyboard", "conveyor": 1.0},
            {"id": "books", "rect": [80, 150, 30, 56], "collide": "solid", "tile": "books", "climb": {"max": 120}},
            {"id": "ruler", "rect": [120, 170, 50, 4], "collide": "platform", "tile": "ruler",
             "move": {"path": [[0, 0], [60, 0]], "period": 300, "mode": "pingpong"}},
            {"id": "pencil", "rect": [250, 160, 60, 4], "collide": "platform", "tile": "pencil"},
            {"id": "lamp", "rect": [300, 128, 50, 4], "collide": "platform", "tile": "light",
             "blink": {"on": 240, "off": 120, "warn": 40}},
            {"id": "eraser", "rect": [200, 132, 40, 4], "collide": "platform", "tile": "eraser", "friction": 0.3},
            {"id": "mug", "rect": [340, 170, 30, 36], "collide": "none", "tile": "coffee",
             "water": {"gravity_mul": 0.5, "drag": 0.9}},
            {"id": "fan", "rect": [380, 90, 60, 100], "collide": "none", "tile": "wind", "wind": [-0.1, 0]},
        ],
    }
    json.dump(data, open(os.path.join(HERE, "stage.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    build()
