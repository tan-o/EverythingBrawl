#!/usr/bin/env python3
"""像素大乱斗角色包校验器 -- 游戏内校验器（game/pack/validator.gd）的镜像。

用法:
  python validate.py <角色目录或 zip>          校验并打印错误与点数明细
  python validate.py <...> --json              以 JSON 输出
  python validate.py --conformance <目录>      跑一致性用例（conformance/expected.json）

最终以游戏为准；本脚本与游戏共用 rules.json / character.schema.json，
并由同一组 conformance 用例保证一致。
"""
import io
import json
import math
import os
import re
import sys
import zipfile

from PIL import Image
import jsonschema

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(HERE)
RULES = json.load(open(os.path.join(SKILL_DIR, "rules.json"), encoding="utf-8"))
SCHEMA = json.load(open(os.path.join(SKILL_DIR, "character.schema.json"), encoding="utf-8"))
STAGE_SCHEMA = json.load(open(os.path.join(SKILL_DIR, "stage.schema.json"), encoding="utf-8"))
L = RULES["limits"]
P = RULES["points"]

ATTACK_TYPES = ("swing", "shoot")
REQUIRED_ANIMS = ["idle", "walk", "jump", "fall", "land", "hurt", "guard", "ko"]
OPTIONAL_ANIMS = ["entrance", "victory", "levelup", "run", "dodge", "cling"]
BULLET_WHEN = ["on_frame", "every", "projectile_hit", "projectile_expire"]
ACTION_WHEN = ["on_start", "on_end", "on_frame", "every", "on_hit", "on_whiff", "on_land", "on_release", "on_hurt"]
CHAR_WHEN = ["every", "on_land", "on_hurt", "resource_empty", "resource_full"]
COND_RE = re.compile(r"^(>=|<=|==|>|<)\s*(-?[0-9]+(?:\.[0-9]+)?)$")


# ---------------------------------------------------------------- 通用工具

class Errors:
    def __init__(self):
        self.items = []
        self._seen = set()

    def add(self, code, path, msg):
        key = (code, path)
        if key in self._seen:
            return
        self._seen.add(key)
        self.items.append({"code": code, "path": path, "msg": msg})

    def codes(self):
        return sorted(set(e["code"] for e in self.items))


def in_range(errs, code, path, v, lim):
    if v < lim[0] or v > lim[1]:
        errs.add(code, path, "%s = %s，应在 %s~%s" % (path, fmt(v), fmt(lim[0]), fmt(lim[1])))
        return False
    return True


def at_most(errs, code, path, v, hi):
    if v > hi:
        errs.add(code, path, "%s = %s，应 <= %s" % (path, fmt(v), fmt(hi)))
        return False
    return True


def at_least(errs, code, path, v, lo):
    if v < lo:
        errs.add(code, path, "%s = %s，应 >= %s" % (path, fmt(v), fmt(lo)))
        return False
    return True


def fmt(v):
    if isinstance(v, float):
        if v == int(v):
            return str(int(v))
        return ("%.4f" % v).rstrip("0").rstrip(".")
    return str(v)


def parse_cond(s):
    m = COND_RE.match(s.strip())
    return m.group(1), float(m.group(2))


def cmp(v, op, t):
    if op == ">=":
        return v >= t
    if op == "<=":
        return v <= t
    if op == "==":
        return v == t
    if op == ">":
        return v > t
    return v < t


def cond_true(cond, values):
    for res, s in cond.items():
        op, t = parse_cond(s)
        if not cmp(values.get(res, 0.0), op, t):
            return False
    return True


def resource_domains(data):
    d = {"ult": RULES["combat"]["ult"]["max"]}
    for name, r in data.get("resources", {}).items():
        d[name] = r["max"]
    return d


def feasible_masks(conds, domains):
    """返回所有可能同时成立的条件组合（位掩码）。每个资源在 [0, max] 上取值。"""
    n = len(conds)
    states = {(1 << n) - 1}
    names = sorted(set(r for c in conds for r in c if r in domains))
    for res in names:
        hi = float(domains[res])
        pts = {0.0, hi}
        for c in conds:
            if res in c:
                _, t = parse_cond(c[res])
                if 0.0 <= t <= hi:
                    pts.add(t)
        pts = sorted(pts)
        cands = list(pts)
        for i in range(len(pts) - 1):
            cands.append((pts[i] + pts[i + 1]) / 2.0)
        new_states = set()
        for st in states:
            for v in cands:
                m = st
                for i, c in enumerate(conds):
                    if res in c:
                        op, t = parse_cond(c[res])
                        if not cmp(v, op, t):
                            m &= ~(1 << i)
                new_states.add(m)
        states = new_states
    return sorted(states)


def mask_label(mask, n):
    bits = [str(i) for i in range(n) if mask & (1 << i)]
    return "+".join(bits) if bits else "base"


def socket_at(data, anim, index, socket="hand"):
    if anim is not None:
        points = anim.get("sockets", {}).get(socket, anim.get("hand", []) if socket == "hand" else [])
        if points:
            return points[min(index, len(points) - 1)]
    return data.get("sockets", {}).get(socket)


def effective_form(data, mask):
    eff = {
        "held": data.get("held"),
        "held_socket": data.get("held_socket", "hand"),
        "anims": {},
        "stats": dict(data["stats"]),
        "input": dict(data["input"]),
    }
    for i, f in enumerate(data.get("forms", [])):
        if not mask & (1 << i):
            continue
        if "held_socket" in f:
            eff["held_socket"] = f["held_socket"]
        if "held" in f:
            eff["held"] = f["held"]
        eff["anims"].update(f.get("anims", {}))
        eff["stats"].update(f.get("stats", {}))
        eff["input"].update(f.get("input", {}))
    return eff


def apply_upgrades(action, mask):
    a = dict(action)
    for i, u in enumerate(action.get("upgrades", [])):
        if mask & (1 << i):
            a.update(u["set"])
    return a


def all_upgrades(action):
    return apply_upgrades(action, (1 << len(action.get("upgrades", []))) - 1)


def action_links(a):
    if a["type"] == "shoot":
        return [l for l in a.get("links", []) if l["when"] not in BULLET_WHEN]
    return list(a.get("links", []))


def bullet_links(a):
    if a["type"] != "shoot":
        return []
    return [l for l in a.get("links", []) if l["when"] in BULLET_WHEN]


def shoot_kind(a, assets):
    proj = assets.get(a.get("projectile"), {})
    if a.get("attach", False) and proj.get("shape") == "rect":
        return "beam"
    if a.get("speed", 0) == 0 or a.get("solid", False):
        return "deployable"
    for l in bullet_links(a):
        if l["when"] == "every":
            return "deployable"
    return "bullet"


def resolve_anim(data, eff, name):
    return data["anims"].get(eff["anims"].get(name, name))


def action_frames(a, data, eff):
    t = a["type"]
    if t in ATTACK_TYPES:
        return a["startup"] + a["active"] + a["recovery"]
    if t == "pose":
        anim = resolve_anim(data, eff, a["anim"])
        if anim is None:
            return 0
        return sum(anim.get("durations", []))
    if t == "fly":
        return a["duration"]
    return 0


def span_len(r):
    return r[1] - r[0] + 1


def every_triggers(window, interval):
    e = P["extra"]["every"]
    return min(window / float(interval), e["max"]) * e["mul"]


# ---------------------------------------------------------------- 读取

class Pack:
    def __init__(self):
        self.files = {}
        self.zip_size = 0


def read_pack(src):
    pk = Pack()
    if os.path.isdir(src):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            for name in sorted(os.listdir(src)):
                p = os.path.join(src, name)
                if os.path.isfile(p) and (name in ("character.json", "stage.json") or name.endswith(".png")):
                    z.write(p, name)
        data = buf.getvalue()
    else:
        data = open(src, "rb").read()
    pk.zip_size = len(data)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            pk.files[info.filename] = z.read(info)
    return pk


# ---------------------------------------------------------------- 校验主体

class Validator:
    def __init__(self, pack):
        self.pack = pack
        self.errs = Errors()
        self.images = {}
        self.data = None
        self.bbox_cache = {}
        self.points = {}

    # ---- 入口
    def run(self):
        e = self.errs
        lp = L["pack"]
        files = self.pack.files
        if "stage.json" in files and "character.json" not in files:
            sv = StageValidator(self.pack)
            res = sv.run()
            self.kind = "stage"
            return res
        at_most(e, "pack.zip_bytes", "zip", self.pack.zip_size, lp["zip_bytes"])
        if "character.json" not in files:
            e.add("pack.read", "character.json", "缺少 character.json")
            return self.result()
        try:
            data = json.loads(files["character.json"].decode("utf-8"))
        except Exception as ex:  # noqa
            e.add("pack.read", "character.json", "JSON 解析失败: %s" % ex)
            return self.result()
        for name in files:
            if name != "character.json" and not name.endswith(".png"):
                e.add("pack.files", name, "包内只能有 character.json 与 .png 文件")
        if not isinstance(data, dict) or data.get("format") != 1:
            e.add("format", "format", "format 必须为 1")
            return self.result()
        v = jsonschema.Draft202012Validator(SCHEMA)
        schema_errors = sorted(v.iter_errors(data), key=lambda x: list(x.absolute_path))
        for se in schema_errors:
            path = ".".join(str(p) for p in se.absolute_path) or "(root)"
            e.add("schema", path, se.message)
        if schema_errors:
            return self.result()
        self.data = data
        if not self.load_images():
            return self.result()
        self.check_art()
        self.check_structure()
        if not e.items:
            self.check_sfx()
        if not e.items:
            self.check_forms()
        if not e.items:
            self.check_points()
        return self.result()

    def result(self):
        return {"valid": not self.errs.items, "errors": self.errs.items, "points": self.points}

    # ---- 图片
    def load_images(self):
        e = self.errs
        names = ["sheet.png"]
        for an, a in self.data["assets"].items():
            if "image" in a:
                names.append(a["image"])
        ok = True
        for n in names:
            if n in self.images:
                continue
            if n not in self.pack.files:
                e.add("ref", n, "缺少图片 %s" % n)
                ok = False
                continue
            try:
                im = Image.open(io.BytesIO(self.pack.files[n]))
                im.load()
                self.images[n] = im.convert("RGBA")
            except Exception as ex:  # noqa
                e.add("pack.read", n, "PNG 读取失败: %s" % ex)
                ok = False
        # 包内其余 png 也参与颜色检查
        for n in self.pack.files:
            if n.endswith(".png") and n not in self.images:
                try:
                    im = Image.open(io.BytesIO(self.pack.files[n]))
                    im.load()
                    self.images[n] = im.convert("RGBA")
                except Exception as ex:  # noqa
                    e.add("pack.read", n, "PNG 读取失败: %s" % ex)
                    ok = False
        return ok

    def frame_grid(self):
        fw, fh = self.data["frame_size"]
        sw, sh = self.images["sheet.png"].size
        return sw // fw, sh // fh

    def total_frames(self):
        c, r = self.frame_grid()
        return c * r

    def frame_bbox(self, idx):
        if idx in self.bbox_cache:
            return self.bbox_cache[idx]
        fw, fh = self.data["frame_size"]
        cols, _ = self.frame_grid()
        x, y = (idx % cols) * fw, (idx // cols) * fh
        crop = self.images["sheet.png"].crop((x, y, x + fw, y + fh))
        bb = crop.getchannel("A").getbbox()
        r = (0, 0) if bb is None else (bb[2] - bb[0], bb[3] - bb[1])
        self.bbox_cache[idx] = r
        return r

    @staticmethod
    def image_bbox(im):
        bb = im.getchannel("A").getbbox()
        return (0, 0) if bb is None else (bb[2] - bb[0], bb[3] - bb[1])

    def check_art(self):
        e = self.errs
        lp = L["pack"]
        d = self.data
        fw, fh = d["frame_size"]
        for i, s in enumerate((fw, fh)):
            if s < lp["frame_size"][0] or s > lp["frame_size"][1] or s % lp["frame_size_step"] != 0:
                e.add("pack.frame_size", "frame_size", "frame_size 每边须为 %d~%d 且为 %d 的倍数" %
                      (lp["frame_size"][0], lp["frame_size"][1], lp["frame_size_step"]))
        ax, ay = d["anchor"]
        if ax < 0 or ax > fw or ay < 0 or ay > fh:
            e.add("anchor", "anchor", "anchor 必须位于帧内")
        sheet = self.images["sheet.png"]
        sw, sh = sheet.size
        if sw > lp["sheet_side"] or sh > lp["sheet_side"]:
            e.add("pack.sheet_side", "sheet.png", "sheet.png 不得超过 %dx%d" % (lp["sheet_side"], lp["sheet_side"]))
        if fw > 0 and fh > 0 and (sw % fw != 0 or sh % fh != 0):
            e.add("pack.sheet_grid", "sheet.png", "sheet.png 尺寸须为 frame_size 的整数倍")
        at_most(e, "pack.total_frames", "sheet.png", self.total_frames(), lp["total_frames"])
        backdrop_imgs = set(a["image"] for a in d["assets"].values() if a["kind"] == "backdrop")
        colors = set()
        bd_colors = set()
        for n in sorted(self.images):
            im = self.images[n]
            bad_alpha = False
            target = bd_colors if n in backdrop_imgs else colors
            for r, g, b, a in (im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()):
                if a == 0:
                    continue
                if a != 255:
                    bad_alpha = True
                    continue
                target.add((r, g, b))
            if bad_alpha:
                e.add("pack.alpha", n, "%s 含半透明像素（alpha 只能是 0 或 255）" % n)
        at_most(e, "pack.colors", "colors", len(colors), lp["colors"])
        at_most(e, "pack.backdrop_colors", "backdrop", len(bd_colors), lp["backdrop_colors"])
        at_most(e, "pack.backdrop_count", "assets", len(backdrop_imgs), lp["backdrop_count"])
        side = lp["asset_side"]
        for an, a in sorted(d["assets"].items()):
            if "image" not in a:
                continue
            im = self.images[a["image"]]
            w, h = im.size
            if a["kind"] == "fx":
                if a["frames"] < 1 or w % a["frames"] != 0 or len(a["durations"]) != a["frames"]:
                    e.add("asset.fx_frames", "assets.%s" % an, "fx 图宽须能被 frames 整除，durations 数量须等于 frames")
                    continue
                w = w // a["frames"]
                for i, du in enumerate(a["durations"]):
                    in_range(e, "pack.duration", "assets.%s.durations.%d" % (an, i), du, lp["duration"])
            if a["kind"] == "backdrop":
                fr = a.get("frames", 1)
                if w % fr != 0 or (fr > 1 and len(a.get("durations", [])) != fr) or (fr == 1 and len(a.get("durations", [1])) != 1):
                    e.add("asset.backdrop_frames", "assets.%s" % an, "backdrop 图宽须能被 frames 整除，多帧时 durations 数量须等于 frames")
                    continue
                for i, du in enumerate(a.get("durations", [])):
                    in_range(e, "pack.duration", "assets.%s.durations.%d" % (an, i), du, lp["duration"])
                if [w // fr, h] not in lp["backdrop_sizes"]:
                    e.add("pack.backdrop_size", "assets.%s" % an, "backdrop 每帧须为 %s 之一（%s 为 %dx%d）" %
                          (" / ".join("%dx%d" % tuple(x) for x in lp["backdrop_sizes"]), an, w // fr, h))
                continue
            if w > side or h > side:
                e.add("pack.asset_side", "assets.%s" % an, "素材图每边 <= %d（%s 为 %dx%d）" % (side, an, w, h))
            if a["kind"] == "weapon":
                in_range(e, "weapon.length", "assets.%s.length" % an, a["length"], L["weapon"]["length"])
                in_range(e, "weapon.radius", "assets.%s.radius" % an, a["radius"], L["weapon"]["radius"])
                hr = a["hit_range"]
                if hr[0] < 0 or hr[1] > 1 or hr[0] > hr[1]:
                    e.add("weapon.hit_range", "assets.%s.hit_range" % an, "hit_range 须满足 0 <= a <= b <= 1")
            if a["kind"] == "projectile":
                sw_, sh_ = a["size"]
                if a["shape"] == "circle" and sw_ != sh_:
                    e.add("projectile.circle", "assets.%s.size" % an, "circle 的 size 须 w = h（直径）")
                bw, bh = self.image_bbox(im)
                tol = lp["projectile_tolerance"]
                if a.get("tile") == "repeat_x":
                    ok = abs(bh - sh_) <= tol * sh_
                else:
                    ok = abs(bw - sw_) <= tol * sw_ and abs(bh - sh_) <= tol * sh_
                if not ok:
                    e.add("pack.projectile_bbox", "assets.%s" % an,
                          "子弹图非透明区域 %dx%d 与 size %sx%s 相差超过 %d%%" % (bw, bh, fmt(sw_), fmt(sh_), tol * 100))

    # ---- 结构与引用
    def asset_kind(self, name):
        a = self.data["assets"].get(name)
        return None if a is None else a["kind"]

    def check_ref(self, path, name, kind):
        if self.asset_kind(name) != kind:
            self.errs.add("ref", path, "%s 引用的 %s 不存在或不是 %s" % (path, name, kind))
            return False
        return True

    def check_structure(self):
        e = self.errs
        d = self.data
        ls = L["structure"]
        lp = L["pack"]
        total = self.total_frames()
        for sn, point in d.get("sockets", {}).items():
            self.check_socket_point(point, "sockets." + sn)
        # 动画
        for an, anim in sorted(d["anims"].items()):
            p = "anims.%s" % an
            n = len(anim["frames"])
            in_range(e, "pack.anim_frames", p + ".frames", n, lp["anim_frames"])
            for i, f in enumerate(anim["frames"]):
                if f >= total:
                    e.add("ref", "%s.frames.%d" % (p, i), "帧编号 %d 超出 sheet（共 %d 帧）" % (f, total))
            if "durations" in anim:
                if len(anim["durations"]) != n:
                    e.add("anim.durations", p + ".durations", "durations 数量须与 frames 相同")
                for i, du in enumerate(anim["durations"]):
                    in_range(e, "pack.duration", "%s.durations.%d" % (p, i), du, lp["duration"])
            if "hand" in anim and len(anim["hand"]) != n:
                e.add("anim.hand", p + ".hand", "hand 数量须与 frames 相同")
            for sn, points in anim.get("sockets", {}).items():
                if len(points) != n:
                    e.add("anim.socket", p + ".sockets." + sn, "挂点数量须与 frames 相同")
                for point in points:
                    self.check_socket_point(point, p + ".sockets." + sn)
            if "hold" in anim and anim["hold"] >= n:
                e.add("anim.hold", p + ".hold", "hold 超出帧数")
        # 资源
        res = d.get("resources", {})
        at_most(e, "structure.resources", "resources", len(res), ls["resources"])
        for rn, r in sorted(res.items()):
            p = "resources.%s" % rn
            if rn in RULES["reserved_resources"]:
                e.add("reserved", p, "资源名 %s 为引擎保留" % rn)
            at_most(e, "structure.resource_max", p + ".max", r["max"], ls["resource_max"])
            if r["init"] < 0 or r["init"] > r["max"]:
                e.add("resource.init", p + ".init", "init 须在 0~max 之间")
            if abs(r.get("regen", 0)) > ls["resource_regen"]:
                e.add("structure.resource_regen", p + ".regen", "|regen| 须 <= %s" % fmt(ls["resource_regen"]))
            if "hud" in r and r["hud"] != "bar":
                self.check_ref(p + ".hud", r["hud"], "icon")
        # 资产引用
        if d.get("held") is not None:
            self.check_ref("held", d["held"], "weapon")
        # 形态
        forms = d.get("forms", [])
        at_most(e, "structure.forms", "forms", len(forms), ls["forms"])
        for i, f in enumerate(forms):
            p = "forms.%d" % i
            self.check_cond(p + ".if", f["if"])
            if "held" in f:
                self.check_ref(p + ".held", f["held"], "weapon")
            for k, v in sorted(f.get("anims", {}).items()):
                if v not in d["anims"]:
                    e.add("ref", "%s.anims.%s" % (p, k), "动画 %s 不存在" % v)
        # 动作
        acts = d["actions"]
        at_most(e, "structure.actions", "actions", len(acts), ls["actions"])
        n_att = len([1 for a in acts.values() if a["type"] in ATTACK_TYPES])
        at_most(e, "structure.attacks", "actions", n_att, ls["attacks"])
        n_move = len([1 for a in acts.values() if a["type"] == "move"])
        n_jump = len([1 for a in acts.values() if a["type"] == "jump"])
        if n_move != 1 or n_jump != 1:
            e.add("actions.move_jump", "actions", "必须恰好 1 个 move 与 1 个 jump 动作")
        ults = sorted(k for k, a in acts.items() if a.get("ultimate", False))
        at_most(e, "ultimate.count", "actions", len(ults), L["ultimate"]["count"])
        for aid, a in sorted(acts.items()):
            p = "actions.%s" % aid
            if a.get("ultimate", False) and a["type"] not in ATTACK_TYPES:
                e.add("ultimate.type", p, "大招必须是 swing 或 shoot")
            if "anim" in a and a["anim"] not in d["anims"]:
                e.add("ref", p + ".anim", "动画 %s 不存在" % a["anim"])
            for k, v in sorted(a.get("cost", {}).items()):
                self.check_res_name("%s.cost.%s" % (p, k), k, False)
            at_most(e, "structure.upgrades", p + ".upgrades", len(a.get("upgrades", [])), ls["upgrades"])
            for i, u in enumerate(a.get("upgrades", [])):
                self.check_cond("%s.upgrades.%d.if" % (p, i), u["if"])
            for ua_mask in range(1 << len(a.get("upgrades", []))):
                ua = apply_upgrades(a, ua_mask)
                self.check_action_refs(aid, ua)
            if "sfx" in a:
                for k, v in sorted(a["sfx"].items()):
                    self.check_ref("%s.sfx.%s" % (p, k), v, "sfx")
        # 角色级联动
        cl = d.get("links", [])
        at_most(e, "structure.char_links", "links", len(cl), ls["char_links"])
        for i, l in enumerate(cl):
            self.check_link("links.%d" % i, l, "char", None)
        # 输入
        for k, v in sorted(d["input"].items()):
            self.check_input_value("input.%s" % k, v)
        for i, f in enumerate(forms):
            for k, v in sorted(f.get("input", {}).items()):
                self.check_input_value("forms.%d.input.%s" % (i, k), v)
        # 静态联动结构
        self.check_graph()

    def check_input_value(self, path, v):
        a = self.data["actions"].get(v)
        if a is None:
            self.errs.add("ref", path, "动作 %s 不存在" % v)
        elif a.get("ultimate", False):
            self.errs.add("ultimate.input", path, "大招不能出现在 input 中")
        elif a["type"] == "move":
            self.errs.add("input.move", path, "move 动作由摇杆驱动，不能绑定按键")

    def check_res_name(self, path, name, allow_ult):
        if name in RULES["reserved_resources"]:
            if not allow_ult:
                self.errs.add("reserved", path, "不能操作引擎保留资源 %s" % name)
            return
        if name not in self.data.get("resources", {}):
            self.errs.add("ref", path, "资源 %s 不存在" % name)

    def check_cond(self, path, cond):
        for k in sorted(cond):
            self.check_res_name("%s.%s" % (path, k), k, True)

    def check_action_refs(self, aid, a):
        e = self.errs
        p = "actions.%s" % aid
        t = a["type"]
        if t == "swing":
            self.check_ref(p + ".weapon", a["weapon"], "weapon")
        if t == "shoot":
            self.check_ref(p + ".projectile", a["projectile"], "projectile")
            if "weapon" in a:
                self.check_ref(p + ".weapon", a["weapon"], "weapon")
        if "anim" in a and a["anim"] not in self.data["anims"]:
            e.add("ref", p + ".anim", "动画 %s 不存在" % a["anim"])
        effs = a.get("effects", [])
        at_most(e, "structure.effects", p + ".effects", len(effs), L["structure"]["effects"])
        for i, ef in enumerate(effs):
            self.check_ref("%s.effects.%d.fx" % (p, i), ef["fx"], "fx")
        if "backdrop" in a:
            self.check_ref(p + ".backdrop", a["backdrop"], "backdrop")
            if not a.get("ultimate", False):
                e.add("ultimate.backdrop", p + ".backdrop", "backdrop（大招背景）只能用于大招动作")
        if t == "jump" and "extra_anim" in a and a["extra_anim"] not in self.data["anims"]:
            e.add("ref", p + ".extra_anim", "动画 %s 不存在" % a["extra_anim"])
        links = a.get("links", [])
        at_most(e, "structure.links", p + ".links", len(links), L["structure"]["links"])
        for i, l in enumerate(links):
            where = "bullet" if (t == "shoot" and l["when"] in BULLET_WHEN) else "action"
            self.check_link("%s.links.%d" % (p, i), l, where, a)

    def check_link(self, path, l, where, a):
        e = self.errs
        d = self.data
        w = l["when"]
        allowed = {"char": CHAR_WHEN, "action": ACTION_WHEN, "bullet": BULLET_WHEN}[where]
        if w not in allowed:
            e.add("link.when", path + ".when", "%s 不能用在%s联动" % (w, {"char": "角色级", "action": "动作", "bullet": "子弹"}[where]))
        if ("input" in l or "window" in l) and where != "action":
            e.add("link.input", path, "input / window 只能用于动作联动")
        if "window" in l and l["window"][0] > l["window"][1]:
            e.add("link.window", path + ".window", "window 须起 <= 止")
        if where == "action" and w == "on_hurt" and "window" not in l:
            e.add("link.window", path, "动作级 on_hurt 必须配 window")
        if "warp" in l and where != "bullet":
            e.add("link.warp", path + ".warp", "warp 只能用于子弹联动")
        if "resource" in l:
            self.check_res_name(path + ".resource", l["resource"], False)
        if "if" in l:
            self.check_cond(path + ".if", l["if"])
        for eff in ("gain", "spend", "set"):
            for k in sorted(l.get(eff, {})):
                self.check_res_name("%s.%s.%s" % (path, eff, k), k, False)
        if "goto" in l and l["goto"] not in d["actions"]:
            e.add("ref", path + ".goto", "动作 %s 不存在" % l["goto"])
        if "goto" in l and l["goto"] in d["actions"] and d["actions"][l["goto"]].get("ultimate", False):
            e.add("ultimate.input", path + ".goto", "不能通过联动进入大招")
        if "spawn" in l:
            t = d["actions"].get(l["spawn"])
            if t is None or t["type"] != "shoot":
                e.add("link.spawn", path + ".spawn", "spawn 目标必须是 shoot 动作")
        if "fx" in l:
            self.check_ref(path + ".fx", l["fx"], "fx")
        if "sfx" in l:
            self.check_ref(path + ".sfx", l["sfx"], "sfx")
        if "heal" in l:
            at_most(e, "heal.max", path + ".heal", l["heal"], L["heal"]["max"])
            if l["heal"] < 0:
                e.add("heal.max", path + ".heal", "heal 须 >= 0")
            if w == "every":
                at_least(e, "heal.every_interval_min", path + ".interval", l["interval"], L["heal"]["every_interval_min"])
        if w == "every":
            at_least(e, "every.interval_min", path + ".interval", l["interval"], L["every"]["interval_min"])

    def link_edges(self, a):
        """返回 (goto 目标列表, spawn 目标列表)，覆盖动作所有升级组合。"""
        gotos, spawns = set(), set()
        for m in range(1 << len(a.get("upgrades", []))):
            ua = apply_upgrades(a, m)
            for l in ua.get("links", []):
                if "goto" in l:
                    gotos.add(l["goto"])
                if "spawn" in l:
                    spawns.add(l["spawn"])
        return sorted(gotos), sorted(spawns)

    def check_graph(self):
        e = self.errs
        acts = self.data["actions"]
        if e.items:
            return
        goto_g, spawn_g = {}, {}
        for aid, a in acts.items():
            goto_g[aid], spawn_g[aid] = self.link_edges(a)
        # goto 成环
        color = {}

        def dfs(u, stack):
            color[u] = 1
            for v in goto_g.get(u, []):
                if color.get(v) == 1:
                    e.add("structure.goto_cycle", "actions.%s" % u, "goto 成环: %s" % " -> ".join(stack + [v]))
                    return True
                if color.get(v) is None and dfs(v, stack + [v]):
                    return True
            color[u] = 2
            return False

        for aid in sorted(acts):
            if color.get(aid) is None:
                if dfs(aid, [aid]):
                    break
        # spawn 深度
        lim = L["structure"]["spawn_depth"]
        memo = {}

        def depth(u, seen):
            if u in seen:
                return 999
            if u in memo:
                return memo[u]
            best = 0
            for v in spawn_g.get(u, []):
                best = max(best, 1 + depth(v, seen | {u}))
            memo[u] = best
            return best

        roots = sorted(acts)
        for aid in roots:
            if depth(aid, frozenset()) > lim:
                e.add("structure.spawn_depth", "actions.%s" % aid, "spawn 链深度超过 %d（或成环）" % lim)
                break
        for i, l in enumerate(self.data.get("links", [])):
            if "spawn" in l and l["spawn"] in acts and 1 + depth(l["spawn"], frozenset()) > lim:
                e.add("structure.spawn_depth", "links.%d" % i, "spawn 链深度超过 %d" % lim)

    # ---- 音效
    def check_sfx(self):
        e = self.errs
        lp = L["pack"]
        sfx = sorted(k for k, a in self.data["assets"].items() if a["kind"] == "sfx")
        at_most(e, "pack.sfx_count", "assets", len(sfx), lp["sfx_count"])
        for k in sfx:
            secs = sfx_seconds(self.data["assets"][k]["params"])
            if secs > lp["sfx_seconds"]:
                e.add("pack.sfx_seconds", "assets.%s" % k, "音效 %s 时长 %.2f 秒，超过 %s 秒" % (k, secs, fmt(lp["sfx_seconds"])))

    # ---- 形态 x 动作
    def form_masks(self):
        forms = self.data.get("forms", [])
        return feasible_masks([f["if"] for f in forms], resource_domains(self.data))

    def check_forms(self):
        d = self.data
        acts = d["actions"]
        self.burst_use = self.compute_burst_use()
        for mask in self.form_masks():
            eff = effective_form(d, mask)
            self.check_form(eff)
            for aid in sorted(acts):
                a = acts[aid]
                ups = a.get("upgrades", [])
                for um in feasible_masks([u["if"] for u in ups], resource_domains(d)):
                    self.check_action(aid, apply_upgrades(a, um), eff, bool(um))

    def compute_burst_use(self):
        """返回 {动作ID: (被子弹联动 spawn, 被其他方式使用)}。"""
        d = self.data
        acts = d["actions"]
        burst, normal = set(), set()
        for aid, a in acts.items():
            for m in range(1 << len(a.get("upgrades", []))):
                ua = apply_upgrades(a, m)
                for l in ua.get("links", []):
                    if "spawn" not in l:
                        continue
                    if ua["type"] == "shoot" and l["when"] in BULLET_WHEN:
                        burst.add(l["spawn"])
                    else:
                        normal.add(l["spawn"])
        for l in d.get("links", []):
            if "spawn" in l:
                normal.add(l["spawn"])
        out = {}
        for aid in acts:
            b = aid in burst
            out[aid] = (b, (not b) or aid in normal or self.in_any_input(aid) or self.is_goto_target(aid))
        return out

    def in_any_input(self, aid):
        d = self.data
        if aid in d["input"].values():
            return True
        for f in d.get("forms", []):
            if aid in f.get("input", {}).values():
                return True
        return False

    def is_goto_target(self, aid):
        d = self.data
        for a in d["actions"].values():
            if aid in self.link_edges(a)[0]:
                return True
        for l in d.get("links", []):
            if l.get("goto") == aid:
                return True
        return False

    def check_form(self, eff):
        e = self.errs
        d = self.data
        ls = L["stats"]
        st = eff["stats"]
        for k in ("hp", "weight", "gravity", "max_fall", "air_control"):
            in_range(e, "stats." + k, "stats." + k, st[k], ls[k])
        bw, bh = st["body"]
        in_range(e, "stats.body_w", "stats.body", bw, ls["body_w"])
        in_range(e, "stats.body_h", "stats.body", bh, ls["body_h"])
        fw, fh = d["frame_size"]
        if bw > fw or bh > fh:
            e.add("stats.body_frame", "stats.body", "body 不能超过 frame_size")
        for k, v in sorted(eff["input"].items()):
            self.check_input_value("input.%s" % k, v)
        # 必需动画
        acts = d["actions"]
        req = list(REQUIRED_ANIMS)
        for a in acts.values():
            if a["type"] == "jump" and a["max_count"] >= 2:
                req.append(a.get("extra_anim", "double_jump"))
            if a["type"] == "fly":
                req.append("fly")
            if "charge" in a or any(l["when"] == "on_release" for l in a.get("links", [])):
                req.append("charge")
            for u in a.get("upgrades", []):
                s = u["set"]
                if "charge" in s or any(l["when"] == "on_release" for l in s.get("links", [])):
                    req.append("charge")
        req = sorted(set(req))
        for name in req:
            if resolve_anim(d, eff, name) is None:
                e.add("anim.required", "anims.%s" % name, "缺少必需动画 %s" % name)
        # 动画用途：攻击姿势 / 普通
        attack_anims, plain_anims = set(), set(req)
        for n in OPTIONAL_ANIMS:
            if resolve_anim(d, eff, n) is not None:
                plain_anims.add(n)
        for aid, a in acts.items():
            for m in range(1 << len(a.get("upgrades", []))):
                ua = apply_upgrades(a, m)
                if "anim" in ua:
                    (attack_anims if ua["type"] in ATTACK_TYPES else plain_anims).add(ua["anim"])
        def rname(n):
            return eff["anims"].get(n, n)
        attack_r = set(rname(n) for n in attack_anims)
        plain_r = set(rname(n) for n in plain_anims)
        for n in sorted(attack_r):
            anim = d["anims"].get(n)
            if anim is None:
                continue
            if n in plain_r:
                e.add("anim.durations", "anims.%s" % n, "攻击姿势动画 %s 不能同时用作普通动画" % n)
            if len(anim["frames"]) != L["pack"]["attack_anim_frames"]:
                e.add("pack.attack_anim_frames", "anims.%s.frames" % n, "攻击姿势动画必须恰好 %d 帧" % L["pack"]["attack_anim_frames"])
            if "durations" in anim:
                e.add("anim.durations", "anims.%s.durations" % n, "攻击姿势动画不写 durations")
        for n in sorted(plain_r - attack_r):
            anim = d["anims"].get(n)
            if anim is not None and "durations" not in anim:
                e.add("anim.durations", "anims.%s" % n, "动画 %s 缺少 durations" % n)
        # held 武器需要 hand
        if eff["held"] is not None:
            self.check_ref("held", eff["held"], "weapon")
            for name in req:
                anim = resolve_anim(d, eff, name)
                if anim is not None and socket_at(d, anim, 0, eff["held_socket"]) is None:
                    e.add("anim.hand" if eff["held_socket"] == "hand" else "ref.socket", "anims.%s" % rname(name), "缺少常态武器挂点")
        for aid, a in sorted(acts.items()):
            for m in range(1 << len(a.get("upgrades", []))):
                ua = apply_upgrades(a, m)
                if ua["type"] == "swing" or (ua["type"] == "shoot" and ("weapon" in ua or "socket" in ua)):
                    anim = resolve_anim(d, eff, ua["anim"])
                    if anim is not None and socket_at(d, anim, 1, ua.get("socket", "hand")) is None:
                        e.add("ref.socket" if "socket" in ua else "anim.hand", "actions." + aid, "缺少动作挂点")
        # 画面与碰撞箱一致
        lp = L["pack"]
        idle = resolve_anim(d, eff, "idle")
        if idle is not None and idle["frames"] and idle["frames"][0] < self.total_frames():
            iw, ih = self.frame_bbox(idle["frames"][0])
            tol = lp["idle_body_tolerance"]
            if abs(iw - bw) > tol * bw or abs(ih - bh) > tol * bh:
                e.add("pack.idle_body", "anims.idle",
                      "idle 第 0 帧非透明区域 %dx%d 与 body %dx%d 相差超过 %d%%" % (iw, ih, bw, bh, tol * 100))
        used = set()
        for n in plain_r | attack_r:
            anim = d["anims"].get(n)
            if anim is not None:
                used.update(f for f in anim["frames"] if f < self.total_frames())
        ratio = lp["frame_body_ratio"]
        for f in sorted(used):
            w, h = self.frame_bbox(f)
            if w > ratio * bw or h > ratio * bh:
                e.add("pack.frame_body", "sheet.png#%d" % f,
                      "第 %d 帧非透明区域 %dx%d 超过 body 的 %s 倍" % (f, w, h, fmt(ratio)))

    # ---- 单个动作（已应用升级）
    def check_action(self, aid, a, eff, upgraded):
        e = self.errs
        d = self.data
        p = "actions.%s" % aid
        if upgraded:
            v = jsonschema.Draft202012Validator({"$ref": "#/$defs/action", "$defs": SCHEMA["$defs"]})
            errs = list(v.iter_errors(a))
            for se in errs:
                e.add("schema", p + "(upgraded)", se.message)
            if errs:
                return
            self.check_action_refs(aid, a)
        t = a["type"]
        ult = a.get("ultimate", False)
        in_range(e, "cooldown", p + ".cooldown", a.get("cooldown", 0), L["cooldown"])
        if t == "move":
            in_range(e, "move.speed", p + ".speed", a["speed"], L["move"]["speed"])
            in_range(e, "move.accel", p + ".accel", a["accel"], L["move"]["accel"])
        elif t == "jump":
            in_range(e, "jump.velocity", p + ".velocity", a["velocity"], L["jump"]["velocity"])
            in_range(e, "jump.max_count", p + ".max_count", a["max_count"], L["jump"]["max_count"])
            st = eff["stats"]
            h, air = jump_arc(a["velocity"], st["gravity"], st["max_fall"])
            at_least(e, "jump.height_min", p + ".velocity", round(h, 6), L["jump"]["height_min"])
            reach = min_move_speed(d) * air
            at_least(e, "jump.reach_min", p, round(reach, 6), L["jump"]["reach_min"])
        elif t == "fly":
            for k in ("duration", "rise_speed", "control"):
                in_range(e, "fly." + k, p + "." + k, a[k], L["fly"][k])
        if t in ATTACK_TYPES:
            self.check_attack(aid, a, eff)
        elif "area" in a:
            e.add("ultimate.area", p + ".area", "area 只能用于大招")
        if t == "pose" and "throw" in a:
            th = a["throw"]
            in_range(e, "attack.damage", p + ".throw.damage", th["damage"], L["attack"]["damage"])
            in_range(e, "attack.force", p + ".throw.knockback.force", th["knockback"]["force"], L["attack"]["force"])
            if th["frame"] >= action_frames(a, d, eff):
                e.add("throw.frame", p + ".throw.frame", "throw.frame 超出动作帧数")
        # 通用字段
        total = action_frames(a, d, eff)
        if "armor" in a:
            r = a["armor"]
            la = L["armor"]
            if r[0] < 0 or r[0] > r[1]:
                e.add("armor.frames", p + ".armor", "armor 区间无效")
            at_most(e, "armor.frames", p + ".armor", span_len(r), la["frames"])
            if t in ATTACK_TYPES:
                if r[1] >= a["startup"] + a["active"]:
                    e.add("armor.window", p + ".armor", "armor 只能落在前摇+生效内")
                at_least(e, "armor.min_startup", p + ".startup", a["startup"], la["min_startup"])
            else:
                e.add("armor.min_startup", p + ".armor", "armor 只能用于 startup >= %d 的攻击动作" % la["min_startup"])
        for key in ("invuln", "reflect"):
            if key in a:
                r = a[key]
                lk = L[key]
                if r[0] < 0 or r[0] > r[1]:
                    e.add(key + ".frames", p + "." + key, "%s 区间无效" % key)
                at_most(e, key + ".frames", p + "." + key, span_len(r), lk["frames"])
                at_least(e, key + ".min_cooldown", p + ".cooldown", a.get("cooldown", 0), lk["min_cooldown"])
        if "motion" in a:
            lm = L["motion"]
            mo = a["motion"]
            at_most(e, "motion.entries", p + ".motion", len(mo), lm["entries"])
            for i, m in enumerate(mo):
                at_most(e, "motion.speed", "%s.motion.%d.vel" % (p, i), math.hypot(*m["vel"]), lm["speed"])
            dist = motion_distance(a, total)
            at_most(e, "motion.distance", p + ".motion", round(dist, 6), lm["distance"])
        if "gravity_scale" in a:
            in_range(e, "gravity_scale", p + ".gravity_scale", a["gravity_scale"], L["gravity_scale"])
        # 联动
        for i, l in enumerate(a.get("links", [])):
            lp_ = "%s.links.%d" % (p, i)
            if "warp" in l:
                at_least(e, "warp.min_cooldown", p + ".cooldown", a.get("cooldown", 0), L["warp"]["min_cooldown"])

    def check_attack(self, aid, a, eff):
        e = self.errs
        d = self.data
        p = "actions.%s" % aid
        la = L["attack"]
        t = a["type"]
        ult = a.get("ultimate", False)
        screen = a.get("area") == "screen"
        lu = L["ultimate"]
        dmg_mul = lu["damage_mul"] if (ult and not screen) else 1
        size_mul = lu["size_mul"] if (ult and not screen) else 1
        if ult:
            in_range(e, "ultimate.startup", p + ".startup", a["startup"], lu["startup"])
        else:
            in_range(e, "attack.startup", p + ".startup", a["startup"], la["startup"])
            if screen:
                e.add("ultimate.area", p + ".area", "area 只能用于大招")
        in_range(e, "attack.active", p + ".active", a["active"], la["active"])
        in_range(e, "attack.recovery", p + ".recovery", a["recovery"], la["recovery"])
        at_most(e, "attack.total_frames", p, a["startup"] + a["active"] + a["recovery"], la["total_frames"])
        if screen and ult:
            # 全屏大招的伤害上限由 ultimate.screen.damage 约束
            at_least(e, "attack.damage", p + ".damage", a["damage"], la["damage"][0])
        else:
            in_range(e, "attack.damage", p + ".damage", a["damage"], [la["damage"][0], la["damage"][1] * dmg_mul])
        force = a["knockback"]["force"]
        in_range(e, "attack.force", p + ".knockback.force", force, la["force"])
        hi = a.get("hit_interval", 0)
        if hi != 0:
            in_range(e, "attack.hit_interval", p + ".hit_interval", hi, la["hit_interval"])
        if screen:
            ls = lu["screen"]
            at_most(e, "ultimate.screen.active", p + ".active", a["active"], ls["active"])
            at_most(e, "ultimate.screen.damage", p + ".damage", a["damage"], ls["damage"])
            at_most(e, "ultimate.screen.force", p + ".knockback.force", force, ls["force"])
        # 关联约束
        ds, fs = la["damage_startup"], la["force_startup"]
        variants = [(a["damage"], force, a["startup"], "")]
        if "charge" in a:
            ch = a["charge"]
            in_range(e, "charge.max", p + ".charge.max", ch["max"], L["charge"]["max"])
            in_range(e, "charge.mult", p + ".charge.damage", ch["damage"], L["charge"]["mult"])
            in_range(e, "charge.mult", p + ".charge.force", ch["force"], L["charge"]["mult"])
            variants.append((a["damage"] * ch["damage"], force * ch["force"], a["startup"] + ch["max"], "（满蓄力）"))
        for dmg, frc, su, tag in variants:
            lim_d = ds["base"] + ds["per_startup"] * su
            lim_f = fs["base"] + fs["per_startup"] * su
            if dmg > lim_d + 1e-9:
                e.add("attack.damage_startup", p + ".damage",
                      "damage %s%s 超过 6 + 0.6 x startup = %s" % (fmt(dmg), tag, fmt(lim_d)))
            if frc > lim_f + 1e-9:
                e.add("attack.force_startup", p + ".knockback.force",
                      "force %s%s 超过 20 + 2.5 x startup = %s" % (fmt(frc), tag, fmt(lim_f)))
        # 状态
        if "status" in a:
            st = a["status"]
            ls = L["status"][st["type"]]
            sp = p + ".status"
            code = "status." + st["type"]
            if st["type"] == "burn":
                in_range(e, code + ".damage", sp + ".damage", st["damage"], ls["damage"])
                at_least(e, code + ".interval_min", sp + ".interval", st["interval"], ls["interval_min"])
            if st["type"] == "slow":
                in_range(e, code + ".factor", sp + ".factor", st["factor"], ls["factor"])
            at_most(e, code + ".duration_max", sp + ".duration", st["duration"], ls["duration_max"])
        # 对单个目标的总伤害
        total = target_damage(a, d)
        lim = lu["target_damage"] if ult else la["target_damage"]
        at_most(e, "ultimate.target_damage" if ult else "attack.target_damage", p, round(total, 6), lim)
        if t == "swing":
            self.check_swing(aid, a)
        else:
            self.check_shoot(aid, a, eff, size_mul, dmg_mul)

    def check_swing(self, aid, a):
        e = self.errs
        d = self.data
        p = "actions.%s" % aid
        la = L["attack"]
        for k in ("from", "to"):
            in_range(e, "attack.angle", p + "." + k, a[k], la["angle"])
        at_most(e, "attack.sweep", p, abs(a["to"] - a["from"]), la["sweep"])
        w = d["assets"][a["weapon"]]
        reach = w["length"] + a["reach"][1]
        at_most(e, "weapon.reach_total", p + ".reach", reach, L["weapon"]["reach_total"])
        if a.get("grab", False):
            lg = L["grab"]
            at_most(e, "grab.reach_total", p + ".reach", reach, lg["reach_total"])
            th = grab_throw(a, d)
            if th is None:
                e.add("grab.throw", p + ".links", "抓取动作必须有 on_hit 联动 goto 一个带 throw 的 pose 动作")
            else:
                link, pose = th
                hold = 1 + pose["throw"]["frame"]
                if "window" in link:
                    hold += max(0, link["window"][1] - a["startup"])
                at_most(e, "grab.max_hold", p, hold, lg["max_hold"])

    def check_shoot(self, aid, a, eff, size_mul, dmg_mul):
        e = self.errs
        d = self.data
        p = "actions.%s" % aid
        proj = d["assets"][a["projectile"]]
        kind = shoot_kind(a, d["assets"])
        lb = L["bullet"]
        sw, sh = proj["size"]
        sol = a.get("scale_over_life", [1, 1])
        for i, s in enumerate(sol):
            in_range(e, "bullet.scale", "%s.scale_over_life.%d" % (p, i), s, lb["scale"])
        smax = max(sol)
        msw, msh = sw * smax, sh * smax
        burst, normal = self.burst_use.get(aid, (False, True))
        count = a.get("count", 1)
        spread = a.get("spread", 0)
        if normal:
            in_range(e, "bullet.count", p + ".count", count, lb["count"])
            in_range(e, "bullet.spread", p + ".spread", spread, lb["spread"])
        if burst:
            in_range(e, "bullet.burst_count", p + ".count", count, [1, lb["burst_count"]])
            in_range(e, "bullet.burst_spread", p + ".spread", spread, [0, lb["burst_spread"]])
            at_most(e, "bullet.burst_damage", p + ".damage", a["damage"], lb["burst_damage"] * dmg_mul)
        if "hp" in a and kind != "deployable":
            e.add("shoot.hp", p + ".hp", "hp 只能用于布置物")
        in_range(e, "bullet.speed", p + ".speed", a["speed"], [0, lb["speed"][1]])
        hi = a.get("hit_interval", 0)
        if kind == "bullet":
            if proj["shape"] == "circle":
                in_range(e, "bullet.circle_d", p + ".projectile", msw, [lb["circle_d"][0], lb["circle_d"][1] * size_mul])
            else:
                if msw > lb["rect_max"][0] * size_mul or msh > lb["rect_max"][1] * size_mul:
                    e.add("bullet.rect_max", p + ".projectile", "rect 子弹（含缩放）不得超过 %sx%s" %
                          (fmt(lb["rect_max"][0] * size_mul), fmt(lb["rect_max"][1] * size_mul)))
            in_range(e, "bullet.speed", p + ".speed", a["speed"], lb["speed"])
            longest = max(msw, msh)
            if a["speed"] > lb["speed_side"] * size_mul / longest + 1e-9:
                e.add("bullet.speed_side", p + ".speed", "speed %s 超过 96 / 最长边(%s) = %s" %
                      (fmt(a["speed"]), fmt(longest), fmt(lb["speed_side"] * size_mul / longest)))
            in_range(e, "bullet.lifetime", p + ".lifetime", a["lifetime"], lb["lifetime"])
            at_most(e, "bullet.damage", p + ".damage", a["damage"], lb["damage"] * dmg_mul)
            pierce = a.get("pierce", 0)
            if pierce != 0 or "pierce" in a:
                in_range(e, "bullet.pierce", p + ".pierce", pierce, lb["pierce"])
            in_range(e, "bullet.turn_rate", p + ".turn_rate", a.get("turn_rate", 0), lb["turn_rate"])
            in_range(e, "bullet.gravity", p + ".gravity", a.get("gravity", 0), lb["gravity"])
        elif kind == "beam":
            lb2 = L["beam"]
            at_most(e, "beam.length", p + ".projectile", msw, lb2["length"] * size_mul)
            in_range(e, "beam.width", p + ".projectile", msh, [lb2["width"][0], lb2["width"][1] * size_mul])
            at_least(e, "beam.grow_min", p + ".grow", a.get("grow", 0), lb2["grow_min"])
            at_least(e, "beam.startup_min", p + ".startup", a["startup"], lb2["startup_min"])
            at_most(e, "beam.lifetime", p + ".lifetime", a["lifetime"], lb2["lifetime"])
            at_least(e, "beam.hit_interval_min", p + ".hit_interval", hi, lb2["hit_interval_min"])
            at_most(e, "beam.damage", p + ".damage", a["damage"], lb2["damage"] * dmg_mul)
            at_most(e, "beam.turn_rate", p + ".turn_rate", a.get("turn_rate", 0), lb2["turn_rate"])
            if a.get("turn_rate", 0) < 0:
                e.add("beam.turn_rate", p + ".turn_rate", "turn_rate 须 >= 0")
            at_least(e, "beam.cooldown_min", p + ".cooldown", a.get("cooldown", 0), lb2["cooldown_min"])
        else:
            ld = L["deployable"]
            if a.get("solid", False):
                if msw > ld["solid_size"][0] * size_mul or msh > ld["solid_size"][1] * size_mul:
                    e.add("deployable.solid_size", p + ".projectile", "solid 布置物（含缩放）不得超过 %sx%s" %
                          (fmt(ld["solid_size"][0] * size_mul), fmt(ld["solid_size"][1] * size_mul)))
            elif msw > ld["size"][0] * size_mul or msh > ld["size"][1] * size_mul:
                e.add("deployable.size", p + ".projectile", "布置物（含缩放）不得超过 %sx%s" %
                      (fmt(ld["size"][0] * size_mul), fmt(ld["size"][1] * size_mul)))
            in_range(e, "deployable.lifetime", p + ".lifetime", a["lifetime"], ld["lifetime"])
            if "hp" not in a:
                e.add("deployable.hp", p + ".hp", "布置物必须填写 hp")
            else:
                in_range(e, "deployable.hp", p + ".hp", a["hp"], ld["hp"])
            at_most(e, "deployable.damage", p + ".damage", a["damage"], ld["damage"] * dmg_mul)
            if hi != 0:
                e.add("deployable.hit_interval", p + ".hit_interval", "布置物 hit_interval 必须为 0")
            for i, l in enumerate(bullet_links(a)):
                lp_ = "%s.links.%d" % (p, i)
                if l["when"] == "every":
                    at_least(e, "deployable.every_interval_min", lp_ + ".interval", l["interval"], ld["every_interval_min"])
                if "spawn" in l:
                    t = d["actions"].get(l["spawn"])
                    if t is not None and t["type"] == "shoot" and shoot_kind(all_upgrades(t), d["assets"]) != "bullet":
                        e.add("deployable.spawn_kind", lp_ + ".spawn", "布置物的联动只能发射 bullet")
                    if t is not None and t["type"] == "shoot":
                        for um in range(1 << len(t.get("upgrades", []))):
                            if shoot_kind(apply_upgrades(t, um), d["assets"]) != "bullet":
                                e.add("deployable.spawn_kind", lp_ + ".spawn", "布置物的联动只能发射 bullet")
            dist = self.deploy_distance(aid, a, eff)
            if dist is None:
                e.add("deployable.distance", p, "布置物不能由子弹联动生成（无法保证放置距离）")
            else:
                at_most(e, "deployable.distance", p, round(dist, 6), ld["distance"])

    def deploy_distance(self, aid, a, eff):
        """布置物生成点到角色锚点的最大距离；None 表示无法确定（由子弹联动生成）。"""
        d = self.data
        acts = d["actions"]
        best = self.shoot_origin_distance(a, eff)
        for sid, s in acts.items():
            for m in range(1 << len(s.get("upgrades", []))):
                us = apply_upgrades(s, m)
                for l in us.get("links", []):
                    if l.get("spawn") != aid:
                        continue
                    if us["type"] == "shoot" and l["when"] in BULLET_WHEN:
                        return None
                    best = max(best, self.anim_hand_distance(us.get("anim"), eff, a.get("socket", "hand")) + (d["assets"][a["weapon"]]["length"] if "weapon" in a else 0))
        return best

    def body_center_distance(self, eff):
        return eff["stats"]["body"][1] / 2.0

    def check_socket_point(self, point, path):
        if not (0 <= point[0] <= self.data["frame_size"][0] and 0 <= point[1] <= self.data["frame_size"][1]):
            self.errs.add("socket.bounds", path, "挂点须位于角色帧内")

    def anim_hand_distance(self, anim_name, eff, socket="hand"):
        d = self.data
        anim = resolve_anim(d, eff, anim_name) if anim_name else None
        ax, ay = d["anchor"]
        points = [socket_at(d, anim, i, socket) for i in range(len(anim["frames"]) if anim else 1)]
        return max(math.hypot(h[0] - ax, h[1] - ay) if h is not None else self.body_center_distance(eff) for h in points)

    def shoot_origin_distance(self, a, eff):
        d = self.data
        anim = resolve_anim(d, eff, a["anim"])
        ax, ay = d["anchor"]
        h = socket_at(d, anim, 1, a.get("socket", "hand"))
        if h is None:
            hx, hy = 0.0, -self.body_center_distance(eff)
        else:
            hx, hy = h[0] - ax, -(h[1] - ay)
        if "weapon" not in a:
            return math.hypot(hx, hy)
        length = d["assets"][a["weapon"]]["length"]
        if a["aim"] == "fixed":
            r = math.radians(a["angle"])
            return math.hypot(hx + math.cos(r) * length, hy + math.sin(r) * length)
        return math.hypot(hx, hy) + length

    # ---- 点数
    def check_points(self):
        d = self.data
        e = self.errs
        forms = d.get("forms", [])
        n_input_forms = len([f for f in forms if "input" in f])
        for mask in self.form_masks():
            eff = effective_form(d, mask)
            label = mask_label(mask, len(forms))
            bd = form_points(d, eff, n_input_forms)
            self.points[label] = bd
            for aid, pts in sorted(bd["actions"].items()):
                if pts > P["action_max"] + 1e-9:
                    e.add("points.action", "actions.%s" % aid,
                          "形态 %s：动作 %s 点数 %.2f 超过 %s" % (label, aid, pts, fmt(P["action_max"])))
            if bd["total"] > P["form_max"] + 1e-9:
                e.add("points.form", "forms.%s" % label,
                      "形态 %s 总点数 %.2f 超过 %s" % (label, bd["total"], fmt(P["form_max"])))


# ---------------------------------------------------------------- 计算函数（与 GDScript 一致）

def motion_distance(a, total):
    mo = sorted(a.get("motion", []), key=lambda m: m["frame"])
    if "charge" in a:
        total += a["charge"]["max"]
    vx, vy = 0.0, 0.0
    dist = 0.0
    for i, m in enumerate(mo):
        if m.get("mode", "set") == "add":
            vx += m["vel"][0]
            vy += m["vel"][1]
        else:
            vx, vy = float(m["vel"][0]), float(m["vel"][1])
        end = mo[i + 1]["frame"] if i + 1 < len(mo) else total
        frames = max(0, end - m["frame"])
        dist += math.hypot(vx, vy) * frames
    return dist


def jump_arc(v, g, max_fall):
    """一次起跳（与引擎相同的逐帧积分）：返回 (最高点高度, 回到起跳高度前的滞空帧数)。"""
    vy = -float(v)
    y = 0.0
    top = 0.0
    frames = 0
    while frames < 1000:
        vy = min(vy + g, max_fall)
        y += vy
        frames += 1
        top = min(top, y)
        if y >= 0:
            break
    return -top, frames


def min_move_speed(d):
    """move 动作在所有升级组合下的最小速度（跳跃水平距离按最慢情况算）。"""
    for a in d["actions"].values():
        if a["type"] == "move":
            return min(apply_upgrades(a, m)["speed"] for m in range(1 << len(a.get("upgrades", []))))
    return 0.0


def burn_total(a):
    st = a.get("status")
    if st is None or st["type"] != "burn":
        return 0.0
    return st["damage"] * (st["duration"] // st["interval"])


def grab_throw(a, d):
    for l in a.get("links", []):
        if l["when"] == "on_hit" and "goto" in l:
            t = d["actions"].get(l["goto"])
            if t is not None and t["type"] == "pose" and "throw" in t:
                return l, t
    return None


def hit_count(window, hi):
    if hi == 0:
        return 1
    return int(math.ceil(window / float(hi)))


def target_damage(a, d):
    hi = a.get("hit_interval", 0)
    dmg = a["damage"]
    if "charge" in a:
        dmg *= a["charge"]["damage"]
    if a.get("area") == "screen":
        total = dmg * hit_count(a["active"], hi)
    elif a["type"] == "swing":
        total = dmg * hit_count(a["active"], hi)
        if a.get("grab", False):
            th = grab_throw(a, d)
            if th is not None:
                total += th[1]["throw"]["damage"]
    else:
        total = dmg * hit_count(a["lifetime"], hi) * a.get("count", 1)
    return total + burn_total(a)


def sfx_seconds(params):
    a = params.get("p_env_attack", 0.0)
    s = params.get("p_env_sustain", 0.3)
    dc = params.get("p_env_decay", 0.4)
    samples = math.floor(a * a * 100000) + math.floor(s * s * 100000) + math.floor(dc * dc * 100000)
    return samples / 44100.0


def attack_base_points(a, d):
    pa = P["attack"]
    t = a["type"]
    hi = a.get("hit_interval", 0)
    window = a["active"] if t == "swing" else a["lifetime"]
    hits = 1 if hi == 0 else min(int(math.ceil(window / float(hi))), pa["max_hits"])
    count = a.get("count", 1) if t == "shoot" else 1
    spread = a.get("spread", 0) if t == "shoot" else 0
    eff_count = 1 + (count - 1) * (1 - spread / float(pa["spread_div"])) * pa["count_mul"]
    damage = a["damage"]
    force = a["knockback"]["force"]
    startup = a["startup"]
    if "charge" in a:
        damage *= a["charge"]["damage"]
        force *= a["charge"]["force"]
        startup += a["charge"]["max"]
    dmg = damage * hits * eff_count
    kb = 1 + force / float(pa["force_div"])
    pf = pa["frame"]
    frame = math.sqrt(pf["startup_num"] / float(startup + pf["startup_add"]) *
                      pf["recovery_num"] / float(a["recovery"] + pf["recovery_add"]))
    if t == "swing":
        w = d["assets"][a["weapon"]]
        rng = 1 + (w["length"] + a["reach"][1]) / float(pa["swing_range_div"])
    else:
        proj = d["assets"][a["projectile"]]
        span = proj["size"][0] if a.get("attach", False) else a["speed"] * a["lifetime"]
        rng = 1 + min(span, pa["shoot_range_cap"]) / float(pa["shoot_range_div"])
    pfe = pa["feature"]
    feat = 1.0
    if t == "shoot":
        if a["aim"] == "steer":
            feat *= pfe["steer"]
        if a["aim"] == "input":
            feat *= pfe["input"]
        if a.get("pierce", 0) != 0:
            feat *= pfe["pierce"]
        if a.get("return", False):
            feat *= pfe["return"]
        if a.get("solid", False):
            feat *= pfe["solid"]
        if a.get("gravity", 0) > 0:
            feat *= pfe["gravity"]
    if t == "swing" and a.get("grab", False):
        feat *= pfe["grab"]
    cd = 1.0 / (1 + a.get("cooldown", 0) / float(pa["cooldown_div"]))
    costmul = pa["cost_mul"] if a.get("cost") else 1.0
    return dmg * kb * frame * rng * feat * cd * costmul * pa["scale"]


def status_points(st):
    pe = P["extra"]
    t = st["type"]
    if t == "burn":
        return st["damage"] * st["duration"] / float(st["interval"]) * pe["burn"]
    if t == "slow":
        return (1 - st["factor"]) * st["duration"] / float(pe["slow_div"])
    if t == "stun":
        return st["duration"] / float(pe["stun_div"])
    if t == "root":
        return st["duration"] / float(pe["root_div"])
    return st["duration"] / float(pe["silence_div"])


def link_points(l, window, d, eff, depth):
    pe = P["extra"]
    trig = every_triggers(window, l["interval"]) if l["when"] == "every" else 1.0
    pts = 0.0
    if "heal" in l:
        pts += l["heal"] * pe["heal_mul"] * trig
    if "warp" in l:
        pts += pe["warp"]
    if "goto" in l:
        pts += pe["goto"]
    if "spawn" in l and depth < 32:
        pts += action_points(d["actions"][l["spawn"]], d, eff, depth + 1) * pe["spawn_mul"] * trig
    return pts


def action_points(action, d, eff, depth=0):
    pe = P["extra"]
    ps = P["stats"]
    a = all_upgrades(action)
    t = a["type"]
    pts = 0.0
    if t == "move":
        pts += (a["speed"] - ps["move_speed"]["base"]) * ps["move_speed"]["mul"]
    elif t == "jump":
        pts += (a["max_count"] - ps["jump_count"]["base"]) * ps["jump_count"]["mul"]
        pts += (a["velocity"] - ps["jump_velocity"]["base"]) * ps["jump_velocity"]["mul"]
    elif t == "fly":
        pts += a["duration"] / float(ps["fly"]["frames"]) * (1 + a["rise_speed"]) * ps["fly"]["mul"]
    elif t in ATTACK_TYPES:
        pts += attack_base_points(a, d)
    if "status" in a:
        pts += status_points(a["status"])
    for key, div in (("armor", "armor_div"), ("invuln", "invuln_div"), ("reflect", "reflect_div")):
        if key in a:
            pts += span_len(a[key]) / float(pe[div])
    if "motion" in a:
        pts += sum(math.hypot(*m["vel"]) for m in a["motion"]) / float(pe["motion_div"])
    total = action_frames(a, d, eff)
    if "gravity_scale" in a and a["gravity_scale"] < 1:
        pts += (1 - a["gravity_scale"]) * total / float(pe["gravity_scale_div"])
    if t == "pose" and "throw" in a:
        th = a["throw"]
        pts += th["damage"] * (1 + th["knockback"]["force"] / float(pe["throw_force_div"])) * pe["throw_mul"]
    if t == "shoot" and shoot_kind(a, d["assets"]) == "deployable":
        pts += pe["deployable"]["mul"] * a["lifetime"] / float(pe["deployable"]["lifetime_div"])
    for l in action_links(a):
        pts += link_points(l, total, d, eff, depth)
    for l in bullet_links(a):
        pts += link_points(l, a["lifetime"], d, eff, depth)
    if t in ATTACK_TYPES and "charge" in a:
        pts *= pe["charge_mul"]
    if action.get("upgrades"):
        pts *= pe["upgrades_mul"]
    return pts


def reachable_actions(d, eff):
    acts = d["actions"]
    todo = [k for k, a in acts.items() if a["type"] in ("move", "jump")]
    todo += list(eff["input"].values())
    todo += [l["goto"] for l in d.get("links", []) if "goto" in l]
    seen = set()
    while todo:
        aid = todo.pop()
        if aid in seen or aid not in acts or acts[aid].get("ultimate", False):
            continue
        seen.add(aid)
        a = acts[aid]
        for m in range(1 << len(a.get("upgrades", []))):
            for l in apply_upgrades(a, m).get("links", []):
                if "goto" in l:
                    todo.append(l["goto"])
    return sorted(seen)


def form_points(d, eff, n_input_forms):
    ps = P["stats"]
    hp = (eff["stats"]["hp"] - ps["hp"]["base"]) * ps["hp"]["mul"]
    acts = {}
    for aid in reachable_actions(d, eff):
        acts[aid] = action_points(d["actions"][aid], d, eff)
    links = 0.0
    for l in d.get("links", []):
        links += link_points(l, P["extra"]["every"]["char_window"], d, eff, 0)
    extra = P["form_input"] * n_input_forms
    total = hp + sum(acts.values()) + links + extra
    return {"total": total, "hp": hp, "actions": acts, "links": links, "forms_input": extra}


# ---------------------------------------------------------------- 场景包

SL = RULES["stage_limits"]
STAGE_BEHAVIORS = ["climb", "crumble", "bounce", "friction", "conveyor", "move", "damage", "wind", "water", "blink", "breakable"]


def elem_offsets(el):
    return [tuple(o) for o in el["move"]["path"]] if "move" in el else [(0.0, 0.0)]


def elem_static(el):
    return not any(k in el for k in ("move", "crumble", "blink", "breakable"))


def elem_standable(el):
    return el["collide"] in ("solid", "platform") and "damage" not in el


def elem_hull(el):
    x, y, w, h = el["rect"]
    offs = elem_offsets(el)
    x0 = min(x + dx for dx, dy in offs)
    y0 = min(y + dy for dx, dy in offs)
    x1 = max(x + dx + w for dx, dy in offs)
    y1 = max(y + dy + h for dx, dy in offs)
    return x0, y0, x1, y1


def path_length(el):
    pts = el["move"]["path"]
    n = len(pts)
    total = 0.0
    for i in range(n - 1):
        total += math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
    if el["move"].get("mode", "loop") == "loop":
        total += math.hypot(pts[0][0] - pts[-1][0], pts[0][1] - pts[-1][1])
    else:
        total *= 2
    return total


def rect_point_dist(x0, y0, x1, y1, px, py):
    dx = max(x0 - px, 0, px - x1)
    dy = max(y0 - py, 0, py - y1)
    return math.hypot(dx, dy)


class StageValidator:
    def __init__(self, pack):
        self.pack = pack
        self.errs = Errors()
        self.images = {}
        self.data = None

    def result(self):
        return {"valid": not self.errs.items, "errors": self.errs.items, "points": {}, "kind": "stage"}

    def run(self):
        e = self.errs
        files = self.pack.files
        at_most(e, "stage.zip_bytes", "zip", self.pack.zip_size, SL["zip_bytes"])
        try:
            data = json.loads(files["stage.json"].decode("utf-8"))
        except Exception as ex:  # noqa
            e.add("pack.read", "stage.json", "JSON 解析失败: %s" % ex)
            return self.result()
        for name in files:
            if name != "stage.json" and not name.endswith(".png"):
                e.add("pack.files", name, "包内只能有 stage.json 与 .png 文件")
        if not isinstance(data, dict) or data.get("format") != 1:
            e.add("format", "format", "format 必须为 1")
            return self.result()
        v = jsonschema.Draft202012Validator(STAGE_SCHEMA)
        serr = sorted(v.iter_errors(data), key=lambda x: list(x.absolute_path))
        for se in serr:
            e.add("schema", ".".join(str(p) for p in se.absolute_path) or "(root)", se.message)
        if serr:
            return self.result()
        self.data = data
        if not self.load_images():
            return self.result()
        self.check_art()
        self.check_elements()
        if not e.items:
            self.check_layout()
        return self.result()

    def load_images(self):
        ok = True
        for n in sorted(self.pack.files):
            if not n.endswith(".png"):
                continue
            try:
                im = Image.open(io.BytesIO(self.pack.files[n]))
                im.load()
                self.images[n] = im.convert("RGBA")
            except Exception as ex:  # noqa
                self.errs.add("pack.read", n, "PNG 读取失败: %s" % ex)
                ok = False
        for an, a in sorted(self.data["assets"].items()):
            if a["image"] not in self.images:
                self.errs.add("ref", "assets.%s.image" % an, "缺少图片 %s" % a["image"])
                ok = False
        return ok

    def check_ref(self, path, name, kind):
        a = self.data["assets"].get(name)
        if a is None or a["kind"] != kind:
            self.errs.add("ref", path, "%s 引用的 %s 不存在或不是 %s" % (path, name, kind))
            return False
        return True

    def check_art(self):
        e = self.errs
        d = self.data
        colors = set()
        for n in sorted(self.images):
            bad = False
            im = self.images[n]
            for r, g, b, a in (im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()):
                if a == 0:
                    continue
                if a != 255:
                    bad = True
                    continue
                colors.add((r, g, b))
            if bad:
                e.add("pack.alpha", n, "%s 含半透明像素（alpha 只能是 0 或 255）" % n)
        at_most(e, "stage.colors", "colors", len(colors), SL["colors"])
        for an, a in sorted(d["assets"].items()):
            im = self.images[a["image"]]
            w, h = im.size
            if a["kind"] in ("tile", "hazard"):
                if w > SL["tile_side"] or h > SL["tile_side"]:
                    e.add("stage.tile_side", "assets.%s" % an, "地形贴图每边 <= %d（%s 为 %dx%d）" % (SL["tile_side"], an, w, h))
            else:
                fr = a.get("frames", 1)
                ds = a.get("durations", [1])
                if w % fr != 0 or len(ds) != fr:
                    e.add("stage.background_frames", "assets.%s" % an, "背景图宽须能被 frames 整除，durations 数量须等于 frames")
                    continue
                for i, du in enumerate(a.get("durations", [])):
                    in_range(e, "pack.duration", "assets.%s.durations.%d" % (an, i), du, L["pack"]["duration"])
                if [w // fr, h] not in SL["background_sizes"]:
                    e.add("stage.background_size", "assets.%s" % an, "背景每帧须为 %s 之一" %
                          " / ".join("%dx%d" % tuple(x) for x in SL["background_sizes"]))
        self.check_ref("background", d["background"], "background")

    def check_elements(self):
        e = self.errs
        els = self.data["elements"]
        at_most(e, "stage.elements", "elements", len(els), SL["elements"])
        n_damage = 0
        n_traps = 0
        bx0, by0, bx1, by1 = SL["bounds"]
        for i, el in enumerate(els):
            p = "elements.%d" % i
            col = el["collide"]
            if el.get("background_region", False):
                if "tile" in el or not elem_static(el):
                    e.add("stage.background_region", p, "背景区域不能同时指定 tile 或动态地形行为")
            elif "tile" not in el:
                e.add("stage.invisible", p, "每个元素都必须有贴图（不能有看不见的地形）")
            else:
                self.check_ref(p + ".tile", el["tile"], "tile")
            x0, y0, x1, y1 = elem_hull(el)
            if x0 < bx0 or y0 < by0 or x1 > bx1 or y1 > by1:
                e.add("stage.bounds", p, "元素（含移动路径）须在 %s 范围内" % SL["bounds"])
            if "trap" in el:
                n_traps += 1
                self.check_trap(el, p)
            if "climb" in el and col != "solid":
                e.add("stage.behavior", p + ".climb", "climb 只能用于 solid")
            for k in ("crumble", "bounce", "friction", "conveyor", "breakable"):
                if k in el and col == "none":
                    e.add("stage.behavior", p + "." + k, "%s 只能用于 solid / platform" % k)
            for k in ("wind", "water"):
                if k in el and col != "none":
                    e.add("stage.behavior", p + "." + k, "%s 只能用于 collide: none 的区域" % k)
            if "climb" in el:
                in_range(e, "stage.climb_max", p + ".climb.max", el["climb"]["max"], SL["climb_max"])
            if "crumble" in el:
                in_range(e, "stage.crumble_after", p + ".crumble.after", el["crumble"]["after"], SL["crumble_after"])
                in_range(e, "stage.respawn", p + ".crumble.respawn", el["crumble"]["respawn"], SL["respawn"])
            if "breakable" in el:
                in_range(e, "stage.breakable_hp", p + ".breakable.hp", el["breakable"]["hp"], SL["breakable"]["hp"])
                in_range(e, "stage.respawn", p + ".breakable.respawn", el["breakable"]["respawn"], SL["respawn"])
            if "bounce" in el:
                in_range(e, "stage.bounce", p + ".bounce.velocity", el["bounce"]["velocity"], SL["bounce"])
            if "friction" in el:
                in_range(e, "stage.friction", p + ".friction", el["friction"], SL["friction"])
            if "conveyor" in el:
                at_most(e, "stage.conveyor", p + ".conveyor", abs(el["conveyor"]), SL["conveyor"])
            if "move" in el:
                lm = SL["move"]
                at_most(e, "stage.move_points", p + ".move.path", len(el["move"]["path"]), lm["points"])
                in_range(e, "stage.move_period", p + ".move.period", el["move"]["period"], lm["period"])
                at_most(e, "stage.move_speed", p + ".move", round(path_length(el) / el["move"]["period"], 6), lm["speed"])
            if "damage" in el:
                n_damage += 1
                ld = SL["damage"]
                in_range(e, "stage.damage", p + ".damage.damage", el["damage"]["damage"], ld["damage"])
                at_least(e, "stage.damage_interval", p + ".damage.interval", el["damage"]["interval"], ld["interval_min"])
                in_range(e, "stage.damage_force", p + ".damage.knockback.force", el["damage"]["knockback"]["force"], ld["force"])
            if "wind" in el:
                at_most(e, "stage.wind", p + ".wind", round(math.hypot(*el["wind"]), 6), SL["wind"])
            if "water" in el:
                lw = SL["water"]
                in_range(e, "stage.water_gravity", p + ".water.gravity_mul", el["water"]["gravity_mul"], lw["gravity_mul"])
                in_range(e, "stage.water_drag", p + ".water.drag", el["water"]["drag"], lw["drag"])
            if "blink" in el:
                lb = SL["blink"]
                in_range(e, "stage.blink_on", p + ".blink.on", el["blink"]["on"], lb["on"])
                in_range(e, "stage.blink_off", p + ".blink.off", el["blink"]["off"], lb["off"])
                if (col != "none" or "damage" in el) and el["blink"].get("warn", 0) < lb["warn"]:
                    e.add("stage.blink_warn", p + ".blink.warn", "会出现的地形或危险物须有 >= %d 帧预警" % lb["warn"])
        at_most(e, "stage.trap_count", "elements", n_traps, SL["trap"]["count"])
        at_most(e, "stage.damage_count", "elements", n_damage, SL["damage"]["count"])

    def check_trap(self, el, p):
        a, lim, e = el["trap"], SL["trap"], self.errs
        p += ".trap"
        self.check_ref(p + ".asset", a["asset"], "hazard")
        for k in ["period", "warn", "damage", "radius"]:
            in_range(e, "stage.trap_" + k, p + "." + k, a[k], lim[k])
        in_range(e, "stage.trap_force", p + ".knockback.force", a["knockback"]["force"], lim["force"])
        if not (0 <= a["origin"][0] <= el["rect"][2] and 0 <= a["origin"][1] <= el["rect"][3]):
            e.add("stage.trap_origin", p + ".origin", "发射/挥击挂点须位于元素内")
        if a.get("offset", 0) >= a["period"]:
            e.add("stage.trap_timing", p, "offset 必须小于 period")
        duration = 1
        if a["type"] == "shoot":
            for k in ["speed", "lifetime"]:
                in_range(e, "stage.trap_" + k, p + "." + k, a[k], lim[k])
        else:
            duration = a["active"]
            for k in ["length", "active"]:
                in_range(e, "stage.trap_" + k, p + "." + k, a[k], lim[k])
            if abs(a["to"] - a["from"]) > 180:
                e.add("stage.trap_sweep", p, "挥击角度变化不能超过 180 度")
            if a["asset"] in self.data["assets"]:
                w, h = self.images[self.data["assets"][a["asset"]]["image"]].size
                if not (0 <= a["grip"][0] < w and 0 <= a["grip"][1] < h and a["grip"][0] + a["length"] <= w):
                    e.add("stage.trap_grip", p, "握点和长度须与武器图片一致")
        if a["warn"] + duration >= a["period"]:
            e.add("stage.trap_timing", p, "预警和攻击后须留出间歇")
        x0, y0, x1, y1 = elem_hull(el)
        ox, oy = a["origin"]
        x0, y0, x1, y1 = x0 + ox, y0 + oy, x1 - el["rect"][2] + ox, y1 - el["rect"][3] + oy
        if a["type"] == "shoot":
            r = math.radians(a["angle"])
            dx, dy = math.cos(r) * a["speed"] * a["lifetime"], -math.sin(r) * a["speed"] * a["lifetime"]
            x0, x1 = min(x0, x0 + dx), max(x1, x1 + dx)
            y0, y1 = min(y0, y0 + dy), max(y1, y1 + dy)
            grow = a["radius"]
        else:
            grow = a["length"] + a["radius"]
        for sx, sy in self.data["spawns"]:
            if x0 - grow < sx + 20 and x1 + grow > sx - 20 and y0 - grow < sy and y1 + grow > sy - 48:
                e.add("stage.trap_spawn", p, "陷阱攻击范围不能覆盖出生区域")
                break

    def check_layout(self):
        e = self.errs
        els = self.data["elements"]
        spawns = self.data["spawns"]
        mains = [i for i, el in enumerate(els)
                 if elem_static(el) and elem_standable(el) and el["rect"][2] >= SL["main_width"]]
        if not mains:
            e.add("stage.main", "elements", "至少要有一块宽 >= %d、静止、可站立的主地面" % SL["main_width"])
            return
        for si, (sx, sy) in enumerate(spawns):
            ok = False
            for el in els:
                x, y, w, h = el["rect"]
                if elem_static(el) and elem_standable(el) and "bounce" not in el and abs(sy - y) <= 1 and x <= sx <= x + w:
                    ok = True
            if not ok:
                e.add("stage.spawn_ground", "spawns.%d" % si, "出生点必须站在静止的可站立地形上")
            for sj in range(si + 1, len(spawns)):
                if math.hypot(sx - spawns[sj][0], sy - spawns[sj][1]) < SL["spawn_spacing"]:
                    e.add("stage.spawn_spacing", "spawns.%d" % si, "出生点之间距离须 >= %d" % SL["spawn_spacing"])
            for i, el in enumerate(els):
                if "damage" in el and rect_point_dist(*elem_hull(el), sx, sy) < SL["spawn_hazard_distance"]:
                    e.add("stage.spawn_hazard", "spawns.%d" % si, "出生点距危险物须 >= %d" % SL["spawn_hazard_distance"])
        # 头顶空间
        hr = SL["headroom"]
        for i, el in enumerate(els):
            if not elem_standable(el):
                continue
            x, y, w, h = el["rect"]
            cols = list(range(int(x) + 2, int(x + w), 4)) or [int(x + w / 2)]
            free = 0
            for cx in cols:
                blocked = False
                for j, o in enumerate(els):
                    if j == i or o["collide"] != "solid":
                        continue
                    ox, oy, ow, oh = o["rect"]
                    if ox <= cx <= ox + ow and oy < y and oy + oh > y - hr:
                        blocked = True
                        break
                if not blocked:
                    free += 1
            if free * 2 < len(cols):
                e.add("stage.headroom", "elements.%d" % i, "可站立地形上方至少一半宽度要留 >= %d 像素空间" % hr)
        # 可达性
        stand = [i for i, el in enumerate(els) if elem_standable(el)]
        reached = set(mains)
        changed = True
        while changed:
            changed = False
            for b in stand:
                if b in reached:
                    continue
                for a in list(reached):
                    if self.can_reach(els[a], els[b]):
                        reached.add(b)
                        changed = True
                        break
        for b in stand:
            if b not in reached:
                e.add("stage.reach", "elements.%d" % b,
                      "从主地面跳不上去（上升 <= %d、水平间隙 <= %d）" % (SL["step_max"], SL["gap_max"]))

    @staticmethod
    def can_reach(a, b):
        for adx, ady in elem_offsets(a):
            ax, ay, aw, ah = a["rect"]
            ax += adx
            ay += ady
            for bdx, bdy in elem_offsets(b):
                bx, by, bw, bh = b["rect"]
                bx += bdx
                by += bdy
                rise = ay - by
                gap = max(0, bx - (ax + aw), ax - (bx + bw))
                if rise <= SL["step_max"] and gap <= SL["gap_max"]:
                    return True
        return False


# ---------------------------------------------------------------- CLI

def validate_path(path):
    return Validator(read_pack(path)).run()


def print_result(res, out=sys.stdout):
    if res["valid"]:
        out.write("通过\n")
    else:
        out.write("不通过（%d 项）\n" % len(res["errors"]))
        for e in res["errors"]:
            out.write("  [%s] %s\n" % (e["code"], e["msg"]))
    for label, bd in sorted(res["points"].items()):
        out.write("点数 形态 %s: 总计 %.2f / %s（hp %.2f，角色级联动 %.2f，形态输入 %.2f）\n" %
                  (label, bd["total"], fmt(P["form_max"]), bd["hp"], bd["links"], bd["forms_input"]))
        for aid, pts in sorted(bd["actions"].items(), key=lambda x: -x[1]):
            flag = "  超出" if pts > P["action_max"] else ""
            out.write("    %-20s %6.2f%s\n" % (aid, pts, flag))


def run_conformance(cdir):
    exp = json.load(open(os.path.join(cdir, "expected.json"), encoding="utf-8"))
    fails = 0
    for name, want in sorted(exp.items()):
        res = validate_path(os.path.join(cdir, "packs", name))
        got_codes = sorted(set(e["code"] for e in res["errors"]))
        ok = res["valid"] == want["valid"] and got_codes == sorted(want["errors"])
        if ok and "points" in want:
            for label, wp in want["points"].items():
                gp = res["points"].get(label)
                if gp is None or abs(gp["total"] - wp["total"]) > 1e-3:
                    ok = False
                    break
                for aid, v in wp["actions"].items():
                    if abs(gp["actions"].get(aid, -999) - v) > 1e-3:
                        ok = False
                if set(gp["actions"]) != set(wp["actions"]):
                    ok = False
            if set(res["points"]) != set(want["points"]):
                ok = False
        if not ok:
            fails += 1
            print("FAIL %s: want valid=%s %s, got valid=%s %s" % (name, want["valid"], want["errors"], res["valid"], got_codes))
            for e in res["errors"]:
                print("     ", e["code"], e["msg"])
    print("conformance: %d/%d passed" % (len(exp) - fails, len(exp)))
    return fails == 0


def main(argv):
    if len(argv) >= 2 and argv[0] == "--conformance":
        sys.exit(0 if run_conformance(argv[1]) else 1)
    if not argv:
        print(__doc__)
        sys.exit(2)
    res = validate_path(argv[0])
    if "--json" in argv:
        print(json.dumps(res, ensure_ascii=False, indent=1))
    else:
        print_result(res)
    sys.exit(0 if res["valid"] else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
