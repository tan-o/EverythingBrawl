#!/usr/bin/env python3
"""把 /rules 下的 rules.json 与 character.schema.json 复制到 skill/ 与 game/data/。

  python tools/sync_rules.py          复制
  python tools/sync_rules.py --check  只检查副本是否一致（CI 用）
"""
import filecmp
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["rules.json", "character.schema.json", "stage.schema.json"]
TARGETS = [os.path.join(ROOT, "skill"), os.path.join(ROOT, "game", "data")]


def main():
    check = "--check" in sys.argv
    bad = []
    for t in TARGETS:
        os.makedirs(t, exist_ok=True)
        for f in FILES:
            src = os.path.join(ROOT, "rules", f)
            dst = os.path.join(t, f)
            if check:
                if not os.path.exists(dst) or not filecmp.cmp(src, dst, shallow=False):
                    bad.append(os.path.relpath(dst, ROOT))
            else:
                shutil.copyfile(src, dst)
    if bad:
        print("以下副本与 /rules 不一致，请运行 python tools/sync_rules.py:\n  " + "\n  ".join(bad))
        sys.exit(1)


if __name__ == "__main__":
    main()
