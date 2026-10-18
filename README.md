# 像素大乱斗 EverythingBrawl

手机端、本地联机、扣血制的像素平台格斗游戏。角色不是内置的：拍一张现实物体的照片交给 AI，
AI 按 `skill/` 生成角色包（像素帧动画 + 招式数据 zip），导入游戏即可对战。

需求来源：SPEC（开发规范）。引擎 **Godot 4.7.2**（GDScript，GL Compatibility 渲染），Android 优先。

## 目录

| 路径 | 内容 |
|---|---|
| `rules/rules.json` | 全部平衡数值（唯一来源） |
| `rules/character.schema.json` | 角色包结构（JSON Schema 2020-12） |
| `conformance/` | 一致性用例：`generate.py` 生成的 195 个合法/违规包 + 4 个示例包，`expected.json` 为期望错误码与点数 |
| `game/` | Godot 项目：`core/` 纯模拟、`render/` 绘制与程序化效果、`audio/` sfxr 合成、`net/` 联机、`pack/` 读取/校验/点数、`ui/` 菜单 HUD 摇杆 |
| `skill/` | 给 AI 的 skill：`SKILL.md`、`scripts/validate.py`（游戏校验器镜像）、`preview.py`、`pack.py`、`pixel.py`、`examples/` |
| `tools/` | `sync_rules.py`（把规则复制到 skill/ 与 game/data/）、`check_rules.py`、`build_examples.py` |

## 构建（GitHub Actions）

`.github/workflows/build.yml` 在每次 push 时：

1. **test**：规则副本与 schema 一致性 → `validate.py` 跑一致性用例 → 重新生成示例角色 →
   Godot 无头跑**游戏内校验器**一致性用例 → 示例角色两两对战的模拟冒烟测试（检查运行时限制）。
2. **export**：导出 Android 调试 APK（arm64 + armv7，CI 内生成调试签名）、Windows、Linux，以及 `skill.zip`，
   在 Actions 运行页面的 Artifacts 下载。

## 本地运行

```sh
python tools/sync_rules.py                 # 改了 rules/ 之后
python tools/build_examples.py             # 重新生成示例角色并打包进游戏
python skill/scripts/validate.py --conformance conformance
cd game
godot --headless --import
godot --headless --path . -s res://tests/run_tests.gd -- conformance ../conformance
godot --headless --path . -s res://tests/run_tests.gd -- sim data/packs/knight.zip data/packs/bulb.zip
godot --path .                             # 运行游戏
```

## 操作

- 手机：左半屏浮动摇杆；右侧 攻 / 特 / 跳 / 防，大招槽满时出现「大招」键。
- 键盘 A：WASD 移动，J 攻击，K 特殊，空格 跳，L 防御，U 大招。
- 键盘 B：方向键，`,` 攻击，`.` 特殊，`/` 跳，Shift 防御，`'` 大招（小键盘 1 2 3 0 4 亦可）。
- 在单向平台上按住下（不按其他键）6 帧穿过平台。
- 对战中「暂停 → 调试显示」显示碰撞箱、武器判定、子弹判定与类别（B 子弹 / 光束 / D 布置物）。
- 桌面版把角色包 zip 拖到窗口上即可导入（存到 `user://packs`）。

## 进度

| 阶段 | 状态 |
|---|---|
| P0 规则、schema、一致性用例 | ✅ 每条规则至少一个违规包，合法包冻结点数 |
| P1 校验器、加载、物理、基础动作、swing、held、扣血击退硬直连段命数复活 | ✅ |
| P2 shoot 三类及运行时限制、fly、pose、goto/spawn 与基础触发 | ✅ |
| P3 resources/wrap、cost、upgrades、forms、fx、HUD | ✅ 示例「瑞士军刀」「工具箱」 |
| P4 motion…warp、sfx、大招与大招槽 | ✅ 示例「罐头骑士」「灯泡法师」 |
| ENet 双机延迟测试 | ✅ 主菜单「联机延迟测试」——**请在手机热点下测量后把结果告诉我，再继续 P5** |
| P5 / P6 联机对战 | ⏸ 等待延迟测试结果 |
| P7 skill | ✅ validate / preview / pack / SKILL.md / 4 个示例；⏸ Android 端导入角色包未做 |

### 联机延迟测试怎么用

两部手机连同一 WiFi 或一部开热点：A 点「作为房主」，B 输入 A 显示的 IP 点「加入」。
两端各自以 60Hz 发送 ping（不可靠通道）并统计往返延迟、抖动、丢包；房主另以 60Hz 下发 300 字节的模拟快照，
客户端统计快照到达间隔。跑 1～2 分钟后点「复制结果」，把两端的文字发给我。

## 规范未明确、由我暂定的地方（请确认或修改）

规范要求遇到未覆盖的设计问题先询问。下面这些点为了让游戏能跑起来先做了最小假设，
数值类都放在 `rules.json`，可直接改：

1. **物理常数**（规范只说「受重力与空气阻力」）：地面摩擦 0.4、空中摩擦 0.04、硬直期间速度每帧 ×0.95、
   复活等待 60 帧、输入缓冲 5 帧、破盾后护盾恢复到 30、按住下 6 帧穿平台。
2. **场地**：主平台 x 80–400、顶面 y 200、厚 24（实心，可从边缘掉落）；两个 72 宽单向平台在 y 146；出生点 4 个。
3. **shoot 的 `links`**：规范里动作 links 与子弹 links 同名。按触发器区分：`on_frame` / `every` / `projectile_hit` /
   `projectile_expire` 属于子弹（frame/every 按子弹存在帧数计），其余属于动作。这也和「有 every 联动即布置物」一致。
4. **大招**：全屏大招的单次伤害上限取 30（规范 5.5）而非 25；非全屏大招尺寸 ×3 时 `speed ≤ 96/最长边` 的 96 也 ×3；
   大招的子弹不计入同屏数量与面积上限（否则 ×3 光束必然超过 3000 px²）；大招三段合计仍 ≤ 100 帧；大招槽在动作结束时清零；
   全屏 shoot 大招直接在生效帧判定全场，不再发射子弹。
5. **布置物**：不能由子弹联动生成（无法静态保证「距角色 ≤ 64 px」，按违规处理）；布置物速度上限沿用 bullet 的 8；
   `count`/`spread` 上限对三类都适用；布置物会落在平台上；`pierce` 0 的布置物（地雷）触发一次后消失。
6. **子弹与地形**：bullet 中心进入主平台即消失（触发 projectile_expire）；光束与布置物不受影响。
7. **形态与升级的组合**：按资源取值范围求出所有「可能同时成立」的条件组合，逐一校验全部规则；点数按规范用「全部升级生效」×0.85。
8. **点数里计入某形态的动作**：move、jump、该形态 input 中的动作、以及经 goto 可达的动作（含角色级 goto）；被 spawn 的动作只按 spawn 规则计入发起者。
9. **抓取**：抓住→throw 的时长 = 1 + throw.frame（若 on_hit 联动有 window 再加窗口末端与 startup 的差）；运行时抓住超过 60 帧自动无伤释放。
10. **on_release**：动作自然播完时若仍按住，停在 `charge` 动画等待松开（every 联动继续计时）。
11. **levelup**：任何形态/升级条件由不成立变为成立时播放；`entrance` 在出生/复活时播放；常态手持武器固定显示 45°。
12. **被打断**：附着在该动作上的子弹（光束）随之消失；被防御的命中不触发 on_hit，但会消耗 pierce。
13. **防御**在空中也可用；没有写到的方向键位不会回退到 neutral（没有动作）。
14. **音效**：调研到的 Godot sfxr 实现（tomeyro/godot-sfxr）是编辑器资源且 2023 年后无维护，故按规范移植 jsfxr 合成器；噪声用固定种子保证各端一致。
15. **错误码**：数值上限的错误码就是 `rules.json` 里 limits 的键路径（如 `bullet.speed_side`），其余见 `validate.py`。
