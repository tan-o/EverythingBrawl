#!/usr/bin/env python3
"""把角色目录打包成 zip（只收 character.json 与 .png），打包前先跑 validate.py。

  python pack.py <角色目录> [输出.zip]
"""
import json
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate  # noqa: E402


def pack(src, out=None, check=True):
    data = json.load(open(os.path.join(src, "character.json"), encoding="utf-8"))
    if out is None:
        out = os.path.join(os.path.dirname(os.path.abspath(src)), "%s.zip" % os.path.basename(os.path.abspath(src)))
    names = sorted(n for n in os.listdir(src) if n == "character.json" or n.endswith(".png"))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            # 固定时间戳，保证同样的内容打出同样的 zip（SHA-256 相同，联机缓存可复用）
            info = zipfile.ZipInfo(n, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, open(os.path.join(src, n), "rb").read())
    if check:
        res = validate.validate_path(out)
        validate.print_result(res)
        if not res["valid"]:
            os.remove(out)
            raise SystemExit("校验未通过，未输出 zip")
    print("已输出 %s（%d 字节，角色：%s）" % (out, os.path.getsize(out), data.get("name")))
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    pack(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
