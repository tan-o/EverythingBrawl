# 像素大乱斗 EverythingBrawl

手机端、局域网联机、扣血制的像素平台格斗游戏。角色和场景都不是内置的：拍一张物体照片交给 AI 做成**角色包**，
拍一张环境照片做成**场景包**（AI 按 `skill/` 生成像素图 + 数据 zip），导入游戏即可对战。

引擎 **Godot 4.7.2**（GDScript，GL Compatibility 渲染），Android 优先。

## 目录

| 路径 | 内容 |
|---|---|
| `rules/rules.json` | 全部平衡数值（唯一来源，含场景规则 `stage_limits`） |
| `rules/character.schema.json` / `stage.schema.json` | 角色包 / 场景包结构（由 `tools/gen_*_schema.py` 生成） |
| `conformance/` | 一致性用例：`generate.py`（角色）与 `generate_stage.py`（场景）生成的合法 / 违规包 + 示例包，`expected.json` 为期望错误码与点数 |
| `game/` | Godot 项目：`core/` 纯模拟、`render/` 绘制与程序化效果、`audio/` sfxr 合成、`net/` 发现 / 大厅 / 同步 / 对战数据、`pack/` 读取 / 校验 / 点数、`ui/` 菜单 HUD 摇杆 |
| `skill/` | 给 AI 的 skill：`SKILL.md`（入口）、`character.md`、`stage.md`、`scripts/`、`examples/`（4 个角色 + 2 个场景） |
| `tools/` | `sync_rules.py`、`check_rules.py`、`build_examples.py`、`gen_character_schema.py`、`gen_stage_schema.py` |

## 构建（GitHub Actions）

每次 push：

1. **test**：规则副本与 schema 一致性 → `validate.py` 跑一致性用例 → 重新生成示例角色与场景 → Godot 无头跑**游戏内校验器**一致性用例
   → 示例角色两两对战（两个场景轮换）检查运行时限制 → ENet 回环延迟自检 → 联机流程自检（房主 + 客户端选包、同步、开局、对战 600 帧）。
2. **export**：Android 调试 APK、Windows、Linux，以及 `skill.zip`（解压后是 `pixel-brawl/` 目录，可直接作为 Claude 的 skill 上传）。
   在 Actions 运行页面的 Artifacts 下载。

## 菜单

- **开始游戏**：选自己的角色和场景（卡片列表）→ 自动搜索同一 WiFi / 热点下的房间，点一下加入，或「创建房间」
  → 所有人选的角色包、场景包自动同步（按 SHA-256 缓存，已有的不再传）并由房主校验 → 房主点「开始对战」，
  从每个人选的场景里**随机选一个**。2~4 人。搜不到时可以手动输入房主 IP。
- **管理角色 / 管理场景**：卡片列表；右上角 **+** 用系统文件选择器导入 zip；点进去是只读的完整详情
  （角色：概览 / 招式 / 按键 / 动画预览 / 校验与点数；场景：预览 / 元素 / 校验）。导入的包可以删除。
  角色详情的「试玩」、场景详情的「在这里试玩」进入练习：选我的角色、对手、对手操作（木桩 / 电脑 / 键盘 B）、场景。
- **网络测试**：ENet 往返延迟、抖动、丢包、发送频率、帧率（两台设备，一台房主一台加入）。

## 操作

- 手机：左半屏浮动摇杆；右侧 攻 / 特 / 跳 / 防，大招槽满时出现「大招」键。
- 键盘 A：WASD 移动，J 攻击，K 特殊，空格 跳，L 防御，U 大招。键盘 B：方向键，`,` `.` `/` Shift `'`。
- 引擎内置（所有角色通用）：摇杆推到底跑动、跑动中攻击（`attack.dash`）、轻点跳跃小跳、空中下推快速下落、
  防御中推左右翻滚 / 推下原地闪避、空中按防御空中闪避、防御中按攻击抓取（`grab`）、贴可攀爬的墙（上爬 / 下滑 / 蹬墙跳）、
  地面按住下穿过单向平台。
- 对战中「菜单 -> 调试显示」：碰撞箱、武器判定、子弹判定与类别、帧率。

## 角色包新增的接口

- `effects`：动作在指定帧播放纯视觉特效（无判定），可跟随角色、可画在身后。
- `backdrop`：大招动画期间用一张全屏图（可多帧）替换场景背景，其他角色压暗。
- 联动的 `input` 可以带方向（如 `attack.up`），做分支连招。
- 输入键新增 `attack.dash`、`grab`；可选动画新增 `run`、`dodge`、`cling`。
- 新规则：满跳最高点 >= 40 像素、空中水平距离 >= 64 像素（场景按这个设计高度）。

## 场景包

照片里的物体对应地形元素：`solid` / `platform` / `none` 区域，可组合行为：攀爬（限时）、站久碎裂、弹跳、摩擦（冰面）、传送带、
移动平台、危险物（伤害 + 击退）、风、水、周期出现 / 消失（带预警）、可打碎。规则保证：有主地面、出生点安全、
每块平台都能用最低跳跃能力跳上去（相邻上升 <= 36、间隙 <= 56）、头顶留出空间。详见 `skill/stage.md`。

## 本地运行

```sh
python tools/sync_rules.py                 # 改了 rules/ 之后
python tools/build_examples.py             # 重新生成示例角色与场景并打包进游戏
python skill/scripts/validate.py --conformance conformance
cd game
godot --headless --import
godot --headless --path . -s res://tests/run_tests.gd -- conformance ../conformance
godot --headless --path . -s res://tests/run_tests.gd -- sim data/packs/knight.zip data/packs/bulb.zip 12000 res://data/stages/kitchen.zip
godot --headless --path . -s res://tests/net_match_test.gd
godot --path .                             # 运行游戏
```

## 规范未明确、由我暂定的地方（请确认或修改）

数值类都在 `rules.json`，可以直接改。

1. **物理常数**：地面摩擦 0.4、空中摩擦 0.04、硬直期间速度每帧 x0.95、复活等待 60 帧、输入缓冲 5 帧、破盾后护盾 30、按住下 6 帧穿平台。
2. **新增的通用操作**：跑动 x1.5（摇杆 >= 0.9）、小跳（起跳 4 帧内松开，上升速度 x0.55）、快速下落（下落速度上限 x1.6）、
   翻滚 / 原地 / 空中闪避（帧数与无敌帧见 `rules.json` 的 `dodge`，每次扣护盾 8）、贴墙下滑 0.8、蹬墙跳。
3. **跳跃保证**：40 像素高、64 像素远（用最慢移动速度计算），场景相邻上升 <= 36、间隙 <= 56。
4. **shoot 的 `links`**：按触发器区分：`on_frame` / `every` / `projectile_hit` / `projectile_expire` 属于子弹，其余属于动作。
5. **大招**：全屏大招单次伤害上限取 30；非全屏大招尺寸 x3 时 `96/最长边` 的 96 也 x3；大招的子弹不计入同屏数量与面积上限；
   大招槽在动作结束时清零；backdrop 颜色单独算（<= 32 色），每包最多 1 个。
6. **布置物**：不能由子弹联动生成；速度上限沿用 bullet 的 8；会落在平台上。
7. **场景**：危险物无视防御；碎裂按累计站立时间计算（离开不清零，恢复后清零）；子弹撞到实心地形消失；可打碎地形挨攻击扣血；
   出生点由场景包给出；背景图不参与碰撞。
8. **联机**：每人选一个场景，开打时随机一个；房主看不到自己的 IP 时仍可被自动发现；输入每帧上传、带最近 8 帧冗余，
   房主积压超过 2 帧时合并（按键不丢）；快照压缩后每帧下发，客户端延后 2 帧插值显示；关闭了 ENet 对不可靠包的节流。
9. **电脑对手**：练习模式里的简单 AI（靠近、出招、跳上平台、回场），规范里没有，仅用于练习。
10. **其余沿用上一版**：on_release、levelup、被打断时附着子弹消失、防御的命中不触发 on_hit、错误码命名等。

## 进度

| 阶段 | 状态 |
|---|---|
| P0 ~ P4 | 完成 |
| P5 局域网：广播发现、大厅、房主校验、包同步与缓存、房主权威 | 完成（本机回环测试通过，需要两部手机实测） |
| P6 4 人、全部程序化效果 | 完成（大厅最多 4 人） |
| P7 skill、Android 导入 | 完成（系统文件选择器导入；从其他应用「分享」到游戏尚未做） |
| 场景包 | 完成：格式、校验（游戏 + Python 镜像，一致性用例）、运行时、渲染、2 个示例、`stage.md` |
