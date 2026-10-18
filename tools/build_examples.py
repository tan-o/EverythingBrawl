#!/usr/bin/env python3
"""重新生成 skill/examples 下的示例角色，并打包到：
  game/data/packs/<名字>.zip            游戏内置示例
  conformance/packs/example_<名字>.zip  一致性用例（期望点数由 validate.py 冻结）
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EX = os.path.join(ROOT, "skill", "examples")
sys.path.insert(0, os.path.join(ROOT, "skill", "scripts"))
import pack  # noqa: E402
import validate  # noqa: E402

GAME = os.path.join(ROOT, "game", "data", "packs")
CONF = os.path.join(ROOT, "conformance")


def main():
    os.makedirs(GAME, exist_ok=True)
    exp_path = os.path.join(CONF, "expected.json")
    exp = json.load(open(exp_path, encoding="utf-8"))
    for name in sorted(os.listdir(EX)):
        d = os.path.join(EX, name)
        if not os.path.isfile(os.path.join(d, "build.py")):
            continue
        subprocess.check_call([sys.executable, os.path.join(d, "build.py")])
        out = os.path.join(GAME, name + ".zip")
        pack.pack(d, out, check=True)
        conf_name = "example_%s.zip" % name
        shutil.copyfile(out, os.path.join(CONF, "packs", conf_name))
        res = validate.validate_path(out)
        exp[conf_name] = {
            "valid": True, "errors": [],
            "points": {label: {"total": round(bd["total"], 4),
                               "actions": {k: round(v, 4) for k, v in sorted(bd["actions"].items())}}
                       for label, bd in res["points"].items()},
        }
    json.dump(exp, open(exp_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
