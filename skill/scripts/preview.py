#!/usr/bin/env python3
"""把角色包每个动画渲染成拼图（以及可选的 GIF），叠加碰撞箱与判定，供生成时自查前后帧一致性。

  python preview.py <角色目录或 zip> [--out preview.png] [--gif 目录] [--scale 4]

叠加说明：
  青色框   stats.body 碰撞箱（底边中点对齐 anchor）
  品红点   anchor
  黄点     hand
  武器     攻击姿势：前摇画在 from、生效画在中间角度、后摇画在 to；普通动画画 held 武器（45°）
  红色胶囊 swing 生效帧的武器判定（hit_range 段 + radius）
  橙色     shoot 生效帧的子弹判定与发射方向
"""
import io
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate  # noqa: E402

HELD_ANGLE = 45.0


def load(src):
    pk = validate.read_pack(src)
    import json
    data = json.loads(pk.files["character.json"].decode("utf-8"))
    imgs = {}
    for n, b in pk.files.items():
        if n.endswith(".png"):
            imgs[n] = Image.open(io.BytesIO(b)).convert("RGBA")
    return data, imgs


def frame_img(data, imgs, idx):
    fw, fh = data["frame_size"]
    sheet = imgs["sheet.png"]
    cols = sheet.width // fw
    x, y = (idx % cols) * fw, (idx // cols) * fh
    return sheet.crop((x, y, x + fw, y + fh))


def anim_users(data):
    """动画名 -> 使用它的动作列表。"""
    out = {}
    for aid, a in data["actions"].items():
        if "anim" in a:
            out.setdefault(a["anim"], []).append((aid, a))
    return out


def draw_weapon(canvas, d, data, imgs, wname, hand, ang, reach, s, ox, oy, capsule=False):
    w = data["assets"].get(wname)
    if not w:
        return
    wim = imgs[w["image"]]
    gx, gy = w["grip"]
    r = math.radians(ang)
    dirv = (math.cos(r), -math.sin(r))
    hx = hand[0] + dirv[0] * reach
    hy = hand[1] + dirv[1] * reach
    big = wim.resize((wim.width * s, wim.height * s), Image.NEAREST)
    # 以握点为中心旋转
    pad = max(big.width, big.height) * 2
    tmp = Image.new("RGBA", (pad, pad), (0, 0, 0, 0))
    tmp.alpha_composite(big, (pad // 2 - gx * s, pad // 2 - gy * s))
    rot = tmp.rotate(ang, resample=Image.NEAREST, center=(pad // 2, pad // 2))
    canvas.alpha_composite(rot, (int(ox + hx * s - pad // 2), int(oy + hy * s - pad // 2)))
    if capsule:
        L = w["length"]
        a0 = reach + L * w["hit_range"][0]
        a1 = reach + L * w["hit_range"][1]
        p0 = (ox + (hand[0] + dirv[0] * a0) * s, oy + (hand[1] + dirv[1] * a0) * s)
        p1 = (ox + (hand[0] + dirv[0] * a1) * s, oy + (hand[1] + dirv[1] * a1) * s)
        rr = w["radius"] * s
        d.line([p0, p1], fill=(255, 60, 60, 255), width=1)
        for p in (p0, p1):
            d.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], outline=(255, 60, 60, 255))


def render_frame(data, imgs, anim_name, i, s, users):
    fw, fh = data["frame_size"]
    ax, ay = data["anchor"]
    anim = data["anims"][anim_name]
    im = frame_img(data, imgs, anim["frames"][i]).resize((fw * s, fh * s), Image.NEAREST)
    pad = 24 * s
    canvas = Image.new("RGBA", (fw * s + pad * 2, fh * s + pad * 2), (40, 44, 60, 255))
    # 网格棋盘底
    dd = ImageDraw.Draw(canvas)
    for yy in range(0, fh):
        for xx in range(0, fw):
            if (xx + yy) % 2 == 0:
                dd.rectangle([pad + xx * s, pad + yy * s, pad + xx * s + s - 1, pad + yy * s + s - 1], fill=(48, 52, 70, 255))
    canvas.alpha_composite(im, (pad, pad))
    d = ImageDraw.Draw(canvas)
    bw, bh = data["stats"]["body"]
    d.rectangle([pad + (ax - bw / 2.0) * s, pad + (ay - bh) * s, pad + (ax + bw / 2.0) * s - 1, pad + ay * s - 1], outline=(80, 220, 255, 255))
    d.ellipse([pad + ax * s - 3, pad + ay * s - 3, pad + ax * s + 3, pad + ay * s + 3], fill=(255, 0, 255, 255))
    hand = anim["hand"][i] if "hand" in anim and i < len(anim["hand"]) else None
    attack = [(aid, a) for aid, a in users.get(anim_name, []) if a["type"] in ("swing", "shoot")]
    if hand is not None:
        if attack:
            aid, a = attack[0]
            if a["type"] == "swing":
                ang = [a["from"], (a["from"] + a["to"]) / 2.0, a["to"]][min(i, 2)]
                reach = [a["reach"][0], sum(a["reach"]) / 2.0, a["reach"][1]][min(i, 2)]
                draw_weapon(canvas, d, data, imgs, a["weapon"], hand, ang, reach, s, pad, pad, capsule=(i == 1))
            else:
                if "weapon" in a:
                    draw_weapon(canvas, d, data, imgs, a["weapon"], hand, a["angle"], 0, s, pad, pad)
                if i == 1:
                    proj = data["assets"][a["projectile"]]
                    r = math.radians(a["angle"])
                    L = data["assets"][a["weapon"]]["length"] if "weapon" in a else 0
                    px, py = hand[0] + math.cos(r) * L, hand[1] - math.sin(r) * L
                    pw, ph = proj["size"]
                    d.line([(pad + px * s, pad + py * s), (pad + (px + math.cos(r) * 16) * s, pad + (py - math.sin(r) * 16) * s)], fill=(255, 160, 40, 255), width=2)
                    d.rectangle([pad + (px - pw / 2) * s, pad + (py - ph / 2) * s, pad + (px + pw / 2) * s, pad + (py + ph / 2) * s], outline=(255, 160, 40, 255))
        elif data.get("held"):
            draw_weapon(canvas, d, data, imgs, data["held"], hand, HELD_ANGLE, 0, s, pad, pad)
        d.ellipse([pad + hand[0] * s - 2, pad + hand[1] * s - 2, pad + hand[0] * s + 2, pad + hand[1] * s + 2], fill=(255, 240, 60, 255))
    return canvas


def contact_sheet(data, imgs, s=4):
    users = anim_users(data)
    rows = []
    for name in sorted(data["anims"]):
        anim = data["anims"][name]
        frames = [render_frame(data, imgs, name, i, s, users) for i in range(len(anim["frames"]))]
        label = name
        if "durations" in anim:
            label += "  " + ",".join(str(x) for x in anim["durations"]) + ("  loop" if anim.get("loop") else "")
        else:
            label += "  attack: startup/active/recovery"
        rows.append((label, frames))
    fw = rows[0][1][0].width
    fh = rows[0][1][0].height
    maxn = max(len(f) for _, f in rows)
    out = Image.new("RGBA", (160 + maxn * (fw + 4), len(rows) * (fh + 4)), (24, 20, 37, 255))
    d = ImageDraw.Draw(out)
    for r, (label, frames) in enumerate(rows):
        y = r * (fh + 4)
        d.text((6, y + 6), label.split("  ")[0], fill=(255, 255, 255, 255))
        if len(label.split("  ")) > 1:
            d.text((6, y + 22), label.split("  ")[1], fill=(180, 180, 200, 255))
        for i, fr in enumerate(frames):
            out.alpha_composite(fr, (160 + i * (fw + 4), y))
    return out


def gifs(data, imgs, outdir, s=4):
    os.makedirs(outdir, exist_ok=True)
    users = anim_users(data)
    for name, anim in data["anims"].items():
        frames = [render_frame(data, imgs, name, i, s, users) for i in range(len(anim["frames"]))]
        durs = anim.get("durations") or [10, 6, 10]
        frames[0].save(os.path.join(outdir, name + ".gif"), save_all=True, append_images=frames[1:],
                       duration=[int(1000 * x / 60.0) for x in durs[:len(frames)]], loop=0, disposal=2)


def main(argv):
    if not argv:
        print(__doc__)
        sys.exit(2)
    src = argv[0]
    out = "preview.png"
    gifdir = None
    s = 4
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    if "--gif" in argv:
        gifdir = argv[argv.index("--gif") + 1]
    if "--scale" in argv:
        s = int(argv[argv.index("--scale") + 1])
    data, imgs = load(src)
    contact_sheet(data, imgs, s).save(out)
    print("已输出", out)
    if gifdir:
        gifs(data, imgs, gifdir, s)
        print("已输出 GIF 到", gifdir)


if __name__ == "__main__":
    main(sys.argv[1:])
