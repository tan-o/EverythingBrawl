"""像素绘制小工具：用字符网格画像素图，按 frame_size 拼 sheet。

只产生不透明（alpha=255）或全透明（alpha=0）的像素，不做抗锯齿。

    from pixel import grid, Sheet, shift
    PAL = {"k": "#222034", "w": "#ffffff"}
    idle0 = grid(['..kk..', '.kwwk.', '..kk..'], PAL)
"""
from PIL import Image


def hex_rgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def grid(rows, palette, size=None):
    """rows: 字符串列表；'.' 或 ' ' 为透明；其余字符按 palette 取色。
    size: 可选 (w, h)，把图放在该尺寸画布的左上角。"""
    h = len(rows)
    w = max(len(r) for r in rows)
    im = Image.new("RGBA", size or (w, h), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in ". ":
                continue
            r, g, b = hex_rgb(palette[ch])
            px[x, y] = (r, g, b, 255)
    return im


def blank(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def paste(dst, src, x, y):
    """把 src 的不透明像素盖到 dst 的 (x, y)。"""
    _paste_clip(dst, src, x, y)
    return dst


def _paste_clip(dst, src, x, y):
    sx, sy = max(0, -x), max(0, -y)
    w = min(src.width - sx, dst.width - max(0, x))
    h = min(src.height - sy, dst.height - max(0, y))
    if w <= 0 or h <= 0:
        return
    crop = src.crop((sx, sy, sx + w, sy + h))
    dst.alpha_composite(crop, (max(0, x), max(0, y)))


def shift(im, dx, dy):
    """整体平移（超出部分裁掉）。"""
    out = blank(im.width, im.height)
    _paste_clip(out, im, dx, dy)
    return out


def flip(im):
    return im.transpose(Image.FLIP_LEFT_RIGHT)


def recolor(im, mapping):
    """mapping: {旧色hex: 新色hex}。"""
    m = {hex_rgb(k): hex_rgb(v) for k, v in mapping.items()}
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in m:
                px[x, y] = m[(r, g, b)] + (255,)
    return out


def set_px(im, pts, color):
    r, g, b = hex_rgb(color)
    px = im.load()
    for x, y in pts:
        if 0 <= x < im.width and 0 <= y < im.height:
            px[x, y] = (r, g, b, 255)
    return im


def clear_px(im, pts):
    px = im.load()
    for x, y in pts:
        if 0 <= x < im.width and 0 <= y < im.height:
            px[x, y] = (0, 0, 0, 0)
    return im


def rect(im, x0, y0, x1, y1, color):
    """填充矩形（含端点）。"""
    return set_px(im, [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)], color)


class Sheet:
    """按 frame_size 网格排列帧，行优先编号。"""

    def __init__(self, fw, fh, cols=8):
        self.fw, self.fh, self.cols = fw, fh, cols
        self.frames = []

    def add(self, im):
        assert im.width <= self.fw and im.height <= self.fh, "帧图大于 frame_size"
        self.frames.append(im)
        return len(self.frames) - 1

    def image(self):
        n = max(1, len(self.frames))
        cols = min(self.cols, n)
        rows = (n + cols - 1) // cols
        out = blank(cols * self.fw, rows * self.fh)
        for i, im in enumerate(self.frames):
            out.alpha_composite(im, ((i % cols) * self.fw, (i // cols) * self.fh))
        return out

    def save(self, path):
        self.image().save(path)
