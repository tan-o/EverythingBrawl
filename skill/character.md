# 像素大乱斗   角色包生成

你要把用户拍的一张**现实物体照片**变成一个可以在《像素大乱斗》里对战的角色：
画像素帧动画、设计招式数据、打包成 zip。游戏会在加载时**严格校验**角色包--
本文第 5 节的规则是**游戏规则**，任何一条不满足，游戏都会拒绝加载整个包。
`scripts/validate.py` 是游戏校验器的镜像，生成过程中必须反复运行它直到通过。

目录：

1. 工作流程
2. 角色包格式
3. 动画与每帧画什么
4. 动作、子弹、联动、形态
5. 游戏规则摘要（不通过 = 拒绝加载）
6. 点数预算
7. 机制用法示例
8. 完整示例
9. 常见错误

---

## 1. 工作流程

1. **看照片，定概念**：它是什么、性格、体型（决定 `stats.body`）、用什么攻击：
   身体挂点直接发射 / 手持或可切换武器 / 子弹 / 光束 / 布置物 / 发展机制（资源、升级）/ 状态 / 抓投 / 大招。
   把物体的特征变成招式（例：灯泡 -> 光束、闪现；工具箱 -> 采集合成；易拉罐 -> 剑士）。
2. **先画定稿帧**：`idle` 第 0 帧。它的非透明区域宽高必须与 `body` 相差 <= +/-25%。
   其余所有帧都在它的基础上**小幅修改**（上下浮动、前倾后仰、压扁拉伸、换眼睛、换腿），
   **不得从头重画**，否则前后帧对不上。
3. **用 Python + Pillow 按像素数组画** `sheet.png` 与素材图：无抗锯齿、无半透明（alpha 只有 0/255）、
   整个包 <= 32 色。`scripts/pixel.py` 提供 `grid()`（字符网格画图）、`rect()`、`set_px()`、`shift()`、`Sheet`（按格拼图）。
   推荐像示例那样写一个 `build.py`，用一个带参数的绘制函数（如 `can(lean=..., squash=..., eyes=...)`）生成所有帧。
4. **设计音效**：为关键动作写 sfxr 参数（jsfxr 参数名，见 2.4）。
5. **写 `character.json`**（第 2、4 节）。
6. **运行校验**：`python scripts/validate.py <角色目录>`。不通过就按错误码与明细修改，直到通过。
   点数明细也会打印出来（第 6 节）。
7. **运行预览**：`python scripts/preview.py <角色目录> --out preview.png [--gif 目录]`，
   查看每个动画（叠加碰撞箱、anchor、命名挂点、武器与判定），检查前后帧是否一致、发射点是否在壶嘴等对应位置、武器是否绑定正确挂点。
8. **打包**：`python scripts/pack.py <角色目录> [输出.zip]`（打包前会再校验一次）。

依赖：`pip install pillow jsonschema`。`rules.json` 与 `character.schema.json` 是游戏规则的副本，不要修改。

---

## 2. 角色包格式

zip 内只能有 `character.json` 和 `.png` 文件。

| 文件 | 说明 |
|---|---|
| `character.json` | 角色数据（UTF-8） |
| `sheet.png` | 所有帧按 `frame_size` 网格排列，**行优先编号，从 0 开始**；宽高必须是 `frame_size` 的整数倍 |
| 其他 `.png` | 武器、子弹、特效、图标 |

### 2.1 坐标约定

- 像素坐标，x 向右，y 向下。
- **朝向空间**：角色包里的所有方向都按"朝右"来写。角度 0 = 前，90 = 上，逆时针为正；向量写作 `[前, 上]`。
  角色朝左时引擎整体镜像。所有帧都画成**面朝右**。
- `anchor` 是脚底锚点（帧内坐标，通常是底边中点，如 48x48 帧用 `[24, 48]`）。
- `stats.body` 是唯一的碰撞箱（物理 + 受击），底边中点对齐 `anchor`。

### 2.2 顶层字段

```json
{
  "format": 1,
  "name": "罐头骑士",
  "frame_size": [48, 48],
  "anchor": [24, 48],
  "stats": { "hp": 105, "body": [22, 32], "weight": 5, "gravity": 0.38, "max_fall": 5, "air_control": 0.55 },
  "held": "sword",
  "resources": { },
  "assets": { },
  "anims": { },
  "forms": [ ],
  "actions": { },
  "links": [ ],
  "input": { }
}
```

`held`、`held_socket`、`sockets`、`resources`、`forms`、`links` 可选。schema 不允许任何未知字段（拼错字段名会被拒绝）。

### 命名挂点 sockets（新包优先使用）

挂点是**角色帧内像素坐标**，不是武器，也不产生判定。先在原图上找出嘴、喷口、手、尾巴等功能位置，再命名。

```json
"sockets": {"mouth": [42, 27], "lid": [24, 18], "right_hand": [32, 34]},
"anims": {
  "pour": {"frames": [0, 1, 2], "sockets": {"mouth": [[42,27], [43,27], [41,27]]}}
}
```

- 顶层 `sockets` 是固定默认坐标；`anims.<动画>.sockets.<名称>` 是逐帧覆盖，数量必须等于该动画的 `frames`。
- 每处最多 16 个挂点，坐标必须在 `frame_size` 范围内。按朝右绘制；朝左时引擎同时镜像挂点、武器和攻击。
- `shoot.socket` 选发射挂点；**不写 `weapon` 就直接从该挂点发射**。茶壶用 `socket: "mouth"`，不是给茶壶装一把假枪。
- `swing.socket` 选武器的旋转/握持挂点；武器的 `grip` 与其对齐。`shoot` 同时有 `weapon` 时，从绑定挂点所持武器末端发射。
- 常态武器用 `held` + `held_socket`；形态可以覆盖两者。没有常态武器就省略 `held`。
- 动作本体发射取攻击动画索引 `1`（数组第二项，即生效姿势）；角色/动作联动取当前帧，当前动画没有命名挂点时回退到顶层或该发射动作索引 `1`。附着发射跟随当前挂点。
- 子弹联动的 `spawn` 仍从父子弹位置发射。新挂点不绕过射程、布置距离或点数限制。
- 旧包 `anims.*.hand` 和未写 `socket` 的动作仍兼容，默认为 `hand`；显式写出的挂点必须存在，不能靠中心点回退。

可运行的无武器案例见 `examples/teapot/build.py`：`mouth` 发水滴，`lid` 发蒸汽，攻击帧的壶嘴挂点逐帧移动。

### 2.3 resources（资源）

```json
"resources": {
  "wood": { "init": 0, "max": 9, "hud": "wood" },
  "dur":  { "init": 0, "max": 10, "hud": "bar", "regen": 0 },
  "slot": { "init": 0, "max": 2, "wrap": true, "keep_on_ko": true }
}
```

- `regen` 每帧回复（可为负），`wrap: true` 时超过 max 回到 0、低于 0 回到 max（武器槽循环）。
- `keep_on_ko` 默认 false（复活时恢复 init）。`hud`：图标资源名 / `"bar"` / 不写即不显示。
- 资源名 `ult` 为引擎保留（大招槽），不能声明、不能 gain/spend/set/cost，但可以写在 `if` 条件里。

### 2.4 assets（素材）

| kind | 字段 |
|---|---|
| `weapon` | `image`、`grip [x,y]`（握点 = 旋转中心）、`length`（握点到判定末端的长度）、`radius`（判定半径）、`hit_range [a,b]`（0~1，沿长度有判定的区段） |
| `projectile` | `image`、`shape`（`circle`/`rect`）、`size [w,h]`（circle 时 w=h=直径；rect 的 w 沿飞行方向）、`tile`（可选 `"repeat_x"`，图片作为单元沿长度平铺，用于光束） |
| `fx` | `image`（横向帧条）、`frames`、`durations`（每帧时长，帧） |
| `icon` | `image` |
| `sfx` | `params`：jsfxr 参数对象（`wave_type` 0方波/1锯齿/2正弦/3噪声，`p_env_attack`、`p_env_sustain`、`p_env_punch`、`p_env_decay`、`p_base_freq`、`p_freq_ramp`、`p_arp_mod`、`p_duty`、`p_vib_strength`、`p_lpf_freq`... `sound_vol`） |

**武器图画法**：武器水平朝右画，握点（手握的位置）在左侧，刀尖/锤头在右。
可以在握点处画一个小拳头--角色帧里不必画手，武器会被画在动作指定的 `socket` 上（旧包默认 `hand`）。
音效时长 = (attack^2 + sustain^2 + decay^2) x 100000 / 44100 秒，必须 <= 2 秒。

---

## 3. 动画与每帧画什么

```json
"anims": {
  "idle": { "frames": [0, 1, 0], "durations": [20, 14, 20], "loop": true, "hand": [[36,34],[36,35],[36,34]] },
  "slash": { "frames": [9, 10, 11], "hand": [[33,32],[38,32],[37,33]] }
}
```

- 每个动画 3~8 帧；`durations` 每帧 1~60（帧）。`hold`：停在第几帧。`hand`：每帧手部坐标（帧内坐标）。
- **攻击姿势动画**（被 swing/shoot 引用）**恰好 3 帧**，对应 前摇 / 生效 / 后摇，**不写 durations**（时长取动作的 startup/active/recovery）。
  同一个动画不能既当攻击姿势又当普通动画。
- 带 `weapon` 的动作必须能解析其 `socket`（默认 `hand`）；设置了 `held` 时所有必需动画必须能解析 `held_socket`。可用顶层固定坐标或动画逐帧坐标，常态武器固定 45 度。

### 必需动画与建议画法

| 动画 | 何时播放 | 建议画法（都基于 idle 第 0 帧小改） |
|---|---|---|
| `idle` | 站立 | 第 0 帧定稿；第 1 帧压扁 1 像素（呼吸） |
| `walk` | 走路 | 身体上移 1 像素 + 两腿前后交替，4 帧 |
| `jump` | 上升 | 身体略拉高、收腿 |
| `fall` | 下落 | 张腿、眯眼 |
| `land` | 落地 | 压扁 3~4 像素 -> 恢复（不循环） |
| `hurt` | 硬直/眩晕/被抓 | 后仰 + 眼睛变 x（受击闪白与抖动由引擎叠加） |
| `guard` | 防御 | 压扁 + 闭眼（护盾泡由引擎画） |
| `ko` | 击倒 | 后仰 -> 更大后仰 -> 躺倒（不循环；播完引擎会把最后一帧拆成像素粒子） |
| `double_jump` | `max_count >= 2` 时第 2 次起跳（名字可由 jump 的 `extra_anim` 指定） | 翻滚/腾空姿态 |
| `fly` | 有 fly 动作时 | 悬浮 |
| `charge` | 有 `charge` 字段或 `on_release` 联动时（按住蓄力/持续） | 蓄力后拉 |
| `entrance` `victory` `levelup` | 可选：出场 / 胜利 / 形态或升级条件变化时 | 跳起、欢呼 |
| `run` `dodge` `cling` | 可选：跑动 / 闪避（翻滚、原地、空中）/ 贴墙 | 没有时分别用 walk / guard / fall 代替 |

**尺寸规则**：idle 第 0 帧非透明区域宽高与 body 相差 <= 25%；**任意帧**宽高 <= body 的 1.4 倍
（躺倒帧要缩短，例如不画腿再旋转 90度）。程序化效果（闪白、伸缩、状态图标、玩家颜色标记、霸体金边、无敌闪烁、反射圈）由引擎统一叠加，不要画进帧里。

---

## 4. 动作、子弹、联动、形态

### 4.1 动作类型

必须恰好 1 个 `move`、1 个 `jump`。

| type | 字段 | 行为 |
|---|---|---|
| `move` | `speed`、`accel` | 摇杆左右 |
| `jump` | `velocity`、`max_count`、`extra_anim` | 第 2 次起用 `extra_anim`（默认 `double_jump`） |
| `fly` | `duration`、`rise_speed`、`control`、`recharge: "on_land"` | 期间无重力；按上上升、左右平移；落地后才能再用 |
| `swing` | `weapon`、`from`、`to`、`reach [起,止]`、`grab` | 前摇停在 from；生效期角度 from->to、伸出 reach[0]->reach[1]；后摇停在 to。判定是沿武器 hit_range 段的胶囊体 |
| `shoot` | 见 4.2 | 生效第 1 帧发射 |
| `pose` | `throw`（可选） | 只播放动画，用 anim 的 durations。切武器、合成、蓄气、挑衅、投掷 |

通用字段：`name`（可选，简短技能名，用于技能展示列表）、`anim`、`require`（ground/air/any）、`cost`（资源消耗）、`cooldown`、`upgrades`、`links`、`effects`（纯视觉特效，见 4.7）、
`motion`（`[{frame, vel:[前,上], mode:"set"/"add"}]`）、`gravity_scale`（0~1）、`armor`/`invuln`/`reflect`（`[起,止]` 帧区间，从动作第 0 帧算）、
`sfx`（`{"start": 音效, "hit": 音效}`）、`ultimate`。

攻击类（swing/shoot）：`startup`/`active`/`recovery`、`damage`、`knockback {angle, force}`、
`hit_interval`（0 = 每个目标只打一次）、`status`、`charge {max, damage, force}`。

引擎的统一战斗规则（不由角色定义）：击退初速 = force/10 x (1.5 - 0.1xweight)；硬直 = min(8 + 0.3xforce, 40)；
打击停顿 = min(3 + damage/4, 10)；防御免疫伤害/击退/状态但扣护盾，抓取无视防御；连段衰减；每人 2 条命。

### 4.2 子弹

`shoot` 字段：`projectile`、`socket`（发射/持械挂点）、`weapon`（可选，有则从武器末端发射，否则直接从挂点）、`aim`（`fixed`/`input`/`steer`）、
`angle`、`turn_rate`、`speed`、`count`、`spread`、`lifetime`、`gravity`、`attach`、`grow`、`pierce`、
`scale_over_life [始,终]`、`solid`、`return`、`hp`、`links`。

**引擎自动分类**（你不能自己声明）：

| 类别 | 条件 |
|---|---|
| beam 光束 | `attach: true` 且 projectile 的 `shape: "rect"` |
| deployable 布置物 | 不是 beam，且 `speed: 0` 或 `solid: true` 或有 `every` 联动 |
| bullet 子弹 | 其余 |

shoot 动作的 `links` 里，`on_frame`/`every`/`projectile_hit`/`projectile_expire` 属于**子弹**（frame 按子弹存在的帧数算），其余属于动作本身。

### 4.3 状态效果

`"status": {"type": "burn", "damage": 1, "interval": 30, "duration": 120}`

| type | 参数 | 效果 |
|---|---|---|
| `burn` | damage、interval、duration | 持续扣血 |
| `slow` | factor、duration | 移动与跳跃 x factor |
| `stun` | duration | 无法行动 |
| `root` | duration | 不能移动与跳跃，可以攻击 |
| `silence` | duration | 不能用 `special.*` |

### 4.4 links（联动）

```json
{ "when": "on_hit", "input": "attack", "window": [6, 16], "if": {"tier": ">=1"}, "require": "ground",
  "goto": "slash2", "spawn": "burst", "gain": {"wood": 1}, "spend": {}, "set": {}, "heal": 5,
  "warp": "projectile", "fx": "sparkle", "sfx": "ding" }
```

| when | 位置 | 说明 |
|---|---|---|
| `on_start` / `on_end` | 动作 | on_end 只在自然结束时触发 |
| `on_frame` | 动作、子弹 | 配 `frame` |
| `every` | 动作、子弹、角色级 | 配 `interval` |
| `on_hit` / `on_whiff` | 动作 | 命中 / 生效期结束仍未命中 |
| `on_land` | 动作、角色级 | 落地 |
| `on_release` | 动作 | 松开发动它的按键；动作播完后仍按住会停在 `charge` 动画等待松开 |
| `on_hurt` | 动作（必须配 window）、角色级 | 被击中时；动作级用于反击（配合 armor） |
| `projectile_hit` / `projectile_expire` | 子弹 | 命中 / 到期、撞地、被摧毁 |
| `resource_empty` / `resource_full` | 角色级 | 配 `resource` |

条件：`input`（attack / special / jump / guard，也可带方向如 `attack.up`、`attack.side`，用来做分支连招）+ `window`（相对动作开始的帧区间：在窗口内按键才触发）、`require`、`if`。

分支连招示例：一段斩命中后，窗口内按 攻击+上 接挑空，按 攻击+左右 接突刺：

```json
"links": [
  { "when": "on_hit", "input": "attack.up",   "window": [6, 18], "goto": "launcher" },
  { "when": "on_hit", "input": "attack.side", "window": [6, 18], "goto": "lunge" }
]
```
效果：`goto`（下一帧切换动作）、`spawn`（必须是 shoot 动作，并行发射；在子弹上则从子弹位置发射）、
`gain`/`spend`/`set`、`heal`、`warp`（仅子弹联动：瞬移到子弹处）、`fx`、`sfx`。

### 4.5 input

键：`attack.<方向>`、`special.<方向>`，方向 属于 `neutral`/`side`/`up`/`down`，后缀 `.air` 为空中版本（没写则沿用地面版本）；
另有 `jump`、`attack.dash`（跑动中攻击）、`grab`（防御中按攻击）。
值是动作 ID。大招不出现在 input 中（大招槽满时出现大招键）。`move` 不能绑定。

### 4.6 引擎内置的操作（所有角色通用，不用写）

| 操作 | 效果 |
|---|---|
| 摇杆推到底 | 跑动（速度 x1.5）；跑动中按攻击触发 `attack.dash`（没写则用 `attack.side`） |
| 轻点跳跃键 | 小跳；按住为满跳。起跳高度按满跳计算 |
| 空中下落时把摇杆往下推 | 快速下落 |
| 防御中推左右 / 推下 | 翻滚 / 原地闪避（有无敌帧） |
| 空中按防御 | 空中闪避（可带方向，落地前只能一次） |
| 防御中按攻击 | 触发 `grab` 键位绑定的动作（抓取） |
| 空中贴着可攀爬的墙并推向墙 | 贴墙，可上爬 / 下滑 / 蹬墙跳（时长由场景决定） |
| 地面按住下 | 穿过单向平台 |

### 4.7 effects（纯视觉特效）与大招背景

动作可以在任意帧播放 fx 动画，**只有画面，没有判定、不计点数**，每个动作最多 4 个：

```json
"effects": [
  { "fx": "aura",  "frame": 0,  "offset": [0, 16], "follow": true, "behind": true },
  { "fx": "spark", "frame": 14, "offset": [30, 14] }
]
```

- `frame`：动作第几帧开始播放；`offset`：相对脚底锚点的位置 `[前, 上]`
- `follow: true` 跟着角色移动（如身上的气场），否则停在原地（如地面裂痕、刀光）
- `behind: true` 画在角色后面

大招可以设 `backdrop`：在前摇与生效期间用一张全屏图代替场景背景（其他角色被压暗、施放者高亮）。

```json
"assets": { "ult_bg": { "kind": "backdrop", "image": "ult_bg.png", "frames": 2, "durations": [6, 6] } },
"actions": { "excalibur": { "...": "...", "ultimate": true, "backdrop": "ult_bg" } }
```

backdrop 每帧必须是 480x270 或 240x135（放大 2 倍铺满），横向帧条，颜色单独计算（<= 32 色），每个包最多 1 个。

### 4.8 forms（形态）与 upgrades（升级）

```json
"forms": [
  { "if": {"slot": "==1"}, "held": "axe", "anims": {"idle": "idle_heavy"}, "stats": {"weight": 7},
    "input": {"attack.side": "axe_chop"} }
]
```

按顺序累积生效（条件成立的形态依次叠加）。可覆盖 `anims`（只替换列出的）、`held`、`held_socket`、`stats`（只替换列出的字段）、`input`（只替换列出的键）。

```json
"upgrades": [ { "if": {"tier": ">=1"}, "set": {"damage": 8, "weapon": "hammer2"} } ]
```

在动作开始时按资源取值，依次覆盖除 `type` 外的任意字段。**每一种可能同时成立的组合都必须满足全部规则。**

---

## 5. 游戏规则摘要（游戏执行，违反即拒绝加载）

参考尺度：场地 480x270，角色碰撞箱约 24x32，横穿全屏 480 px。所有数值以 `rules.json` 为准。

**包与美术**：zip <= 512 KB；frame_size 每边 32~64 且为 8 的倍数；sheet <= 1024x1024；总帧数 <= 128；
动画 3~8 帧（攻击姿势恰好 3）；durations 1~60；整包 <= 32 色、alpha 只有 0/255；单张素材每边 <= 64（fx 按单帧算）；
idle 第 0 帧与 body 相差 <= +/-25%，任意帧 <= bodyx1.4；子弹图非透明区域与 size 相差 <= +/-25%（repeat_x 只比高度）；音效 <= 16 个、每个 <= 2 秒。

**属性**：hp 80~150；body 宽 12~40、高 12~48 且不超过 frame_size；weight 1~10；gravity 0.2~0.6；max_fall 3~7；air_control 0.1~1；
move.speed 1~3.5、accel 0.1~1；jump.velocity 4~8、max_count 1~3；fly duration 1~120、rise_speed 0~1.5、control 0~1。

**跳跃保证（场景按这个设计高度，跳不上去的角色会被拒绝）**：一次满跳的最高点 >= 40 像素，
一次跳跃在空中的水平距离（最慢移动速度 x 滞空帧数）>= 64 像素。按引擎逐帧积分计算：每帧 `vy += gravity`（下落时不超过 max_fall），`y += vy`。
参考：velocity 6.5 / gravity 0.4 -> 高约 50、滞空 32 帧；速度 2.0 -> 距离 64。重力大就要提高 velocity；移动慢就要让滞空更久。
有 forms 改了 gravity / max_fall 的，每种形态都要满足。

**攻击**：startup 2~60 / active 1~20 / recovery 4~60，合计 <= 100；damage 1~25；**对单个目标总伤害 <= 25**（含多段、burn、throw、满蓄力）；
force 0~100；hit_interval 0 或 4~30；cooldown 0~600；武器 length 4~40、radius 2~10、`length + reach[1]` <= 56；
swing 角度 -360...360；motion <= 4 条、每条 |vel| <= 10、按速度积分的总位移 <= 160（不计重力，算到动作结束）；gravity_scale 0~1；
armor 区间 <= 20 帧且只在前摇+生效内、startup >= 10；invuln <= 15 帧且 cooldown >= 60；reflect <= 20 帧且 cooldown >= 60；
charge max 10~90、倍率 1~1.5；burn damage 1~3、interval >= 20、duration <= 180；slow factor 0.5~0.9、<= 120；stun <= 45；root <= 90；silence <= 120；
抓取武器 `length + reach[1]` <= 24，抓住到 throw 生效 <= 60 帧；heal 单次 <= 10，every 回复 interval >= 120；warp 所在动作 cooldown >= 120；every interval >= 30。

**关联约束（越快的招越弱）**：`damage <= 6 + 0.6 x startup`，`force <= 20 + 2.5 x startup`；满蓄力后同样适用（startup 加上 charge.max）。

**bullet**：circle 直径 2~16、rect <= 24x8（含 scale_over_life 放大）；speed 1~8 且 `speed <= 96 / 最长边`；scale 0.5~2；lifetime 1~180；
count 1~5、spread 0~120（被子弹联动 spawn 的爆散：count <= 8、spread <= 360、damage <= 3）；damage <= 10；pierce 0~2；turn_rate 0~4；gravity 0~0.4。

**beam**：长 <= 200、宽 4~12；grow >= 4；startup >= 20；lifetime <= 60；hit_interval >= 6；damage <= 3；turn_rate <= 2；cooldown >= 90。

**deployable**：<= 24x24（solid <= 48x8）；lifetime 60~600；hp 1~20 必填；生成点距 anchor <= 64（不能由子弹联动生成）；
接触 damage <= 8 且 hit_interval = 0；every interval >= 45 且只能 spawn bullet。

**大招**：最多 1 个；startup 40~90；对单目标总伤害 <= 40；`area: "screen"` 时 active <= 10、damage <= 30、force <= 80；
非全屏大招子弹/光束尺寸上限 x3、伤害上限 x2。大招不计点数。

**数量**：动作 <= 32、攻击 <= 20；资源 <= 6、max <= 99、|regen| <= 1；每动作 upgrades <= 4；forms <= 4；每动作/子弹 links <= 6、角色级 <= 8；goto 不成环；spawn 链深度 <= 8。

**运行时**（引擎强制，写多了也没用）：连段衰减；控制免疫；同屏 bullet+beam <= 8；子弹判定总面积 <= 3000 px^2；布置物 <= 2（第 3 个顶掉最早的）；
每条命回复 <= 30；同一状态只刷新不叠加；同帧生成 <= 8；联动链深度 <= 8。

---

## 6. 点数预算

每种形态总点数 <= 60，单个动作 <= 15；有改变 input 的形态时，每多一种这样的形态总点数 +2。大招不计。
validate.py 会打印每种形态的逐项明细。

- 属性：hp `(hp-100)x0.2`；move `(speed-2)x6`；jump `(max_count-2)x4 + (velocity-6.5)x2`；fly `duration/60x(1+rise_speed)x1.5`
- 攻击：`damage x hits x eff_count x (1+force/100) x sqrt(20/(startup+10) x 30/(recovery+20)) x range x feature x 1/(1+cooldown/120) x (有 cost 0.8) x 0.25`
  - hits = hit_interval 为 0 时 1，否则 min(ceil(window/hit_interval),10)（swing 的 window = active，shoot = lifetime）
  - eff_count = 1 + (count-1)x(1-spread/360)x0.8
  - range：swing `1+(length+reach[1])/80`；shoot `1+min(attach ? size.w : speedxlifetime, 480)/240`
  - feature 连乘：steer 1.3、input 1.1、pierce!=0 1.2、return 1.15、solid 1.2、grab 1.3、gravity>0 0.9
- 附加：status（burn `damagexduration/intervalx0.5`，slow `(1-factor)xduration/20`，stun `/6`，root `/20`，silence `/30`）；
  armor/invuln/reflect 区间长 `/6`、`/3`、`/5`；motion `求和|vel|/3`；gravity_scale<1 `(1-g)x总帧数/30`；
  throw `damagex(1+force/100)x0.25`；heal `x0.6x触发次数`；warp +3；布置物 `+2xlifetime/300`；goto 每条 +1；
  spawn `被 spawn 动作点数x0.5x触发次数`；every 触发次数 `min(window/interval,10)x0.5`（角色级 window=600）
- charge：按满蓄力参数计算后 x0.8；upgrades：按全部升级生效后计算 x0.85。
- 计入形态的动作：move、jump、该形态 input 里的动作、以及沿 goto 可达的动作（被 spawn 的动作只通过 spawn 计点）。

省点数的办法：加 cooldown、加 cost、拉长 startup/recovery、减少多段、减小范围。

---

## 7. 机制用法示例

**光束（beam）**--attach + rect，grow 伸长，steer 可操控：
```json
"light_beam": { "type": "shoot", "anim": "beam_pose", "projectile": "beam", "aim": "steer", "angle": 0, "turn_rate": 1.5,
  "speed": 0, "attach": true, "grow": 10, "lifetime": 40, "hit_interval": 8, "startup": 22, "active": 2, "recovery": 18,
  "damage": 2, "cooldown": 120, "knockback": {"angle": 15, "force": 12} }
```
（projectile：`{"kind":"projectile","image":"beam.png","shape":"rect","size":[150,8],"tile":"repeat_x"}`）

**布置物（炮台）**--speed 0 + every 发射 bullet：
```json
"turret": { "type": "shoot", "anim": "build", "projectile": "turret", "aim": "fixed", "angle": 0, "speed": 0,
  "lifetime": 300, "hp": 6, "startup": 14, "active": 2, "recovery": 14, "damage": 2, "cost": {"wood": 2}, "cooldown": 120,
  "knockback": {"angle": 45, "force": 15}, "links": [ {"when": "every", "interval": 60, "spawn": "nail"} ] }
```

**全屏大招**：
```json
"excalibur": { "type": "swing", "anim": "ult", "weapon": "sword", "from": 90, "to": -90, "reach": [0, 6],
  "startup": 60, "active": 6, "recovery": 30, "damage": 24, "area": "screen", "ultimate": true,
  "knockback": {"angle": 60, "force": 72} }
```

**motion + invuln + gravity_scale（上升斩）**：
```json
"rise": { "type": "swing", "anim": "rise", "weapon": "sword", "from": 80, "to": 100, "reach": [0, 2], "startup": 4, "active": 10,
  "recovery": 18, "damage": 5, "knockback": {"angle": 80, "force": 30}, "cooldown": 60, "invuln": [0, 5], "gravity_scale": 0.6,
  "motion": [ {"frame": 3, "vel": [1.5, 6.5]}, {"frame": 14, "vel": [0.5, 1]} ] }
```

**armor + on_hurt 反击**：
```json
"counter": { "type": "swing", "anim": "counter", "weapon": "sword", "from": 60, "to": -30, "reach": [0, 2], "startup": 14,
  "active": 3, "recovery": 18, "damage": 6, "knockback": {"angle": 40, "force": 30}, "armor": [0, 13], "cooldown": 30,
  "links": [ {"when": "on_hurt", "window": [0, 13], "goto": "riposte"} ] }
```

**reflect**：`"mirror": { "type": "pose", "anim": "mirror", "reflect": [2, 20], "cooldown": 90 }`

**status**：`"status": {"type": "slow", "factor": 0.7, "duration": 90}`（写在攻击动作上，每个动作最多 1 个）

**grab / throw**：
```json
"grab":  { "type": "swing", "anim": "grab", "weapon": "fist", "from": 0, "to": 0, "reach": [0, 10], "startup": 6, "active": 4,
  "recovery": 18, "damage": 2, "grab": true, "knockback": {"angle": 0, "force": 0}, "links": [ {"when": "on_hit", "goto": "throw"} ] },
"throw": { "type": "pose", "anim": "throw", "throw": {"frame": 10, "damage": 7, "knockback": {"angle": 40, "force": 45}} }
```

**charge**：`"charge": {"max": 40, "damage": 1.4, "force": 1.3}`（需要 `charge` 动画；注意满蓄力的关联约束与总伤害）

**every / heal（角色级持续回复）**：`"links": [ {"when": "every", "interval": 300, "heal": 2} ]`

**warp（闪现）**：
```json
"blink": { "type": "shoot", "anim": "cast", "projectile": "blink", "aim": "input", "angle": 45, "speed": 6, "lifetime": 20,
  "startup": 6, "active": 2, "recovery": 12, "damage": 1, "cooldown": 120, "knockback": {"angle": 45, "force": 5},
  "links": [ {"when": "projectile_expire", "warp": "projectile"} ] }
```

**连击（goto + input window）**：
`"links": [ {"when": "on_hit", "input": "attack", "window": [4, 16], "goto": "jab2"} ]`

**爆散（子弹联动 spawn）**：`"links": [ {"when": "projectile_expire", "spawn": "burst"} ]`，
burst 是 `count: 8, spread: 360, damage: 2` 的 shoot 动作。

---

## 8. 完整示例

`examples/` 下每个目录是一个完整角色，`build.py` 从零生成全部图片与 `character.json`：

| 目录 | 角色 | 展示 |
|---|---|---|
| `knight` | 罐头骑士（单武器） | held 剑、三段连击、蓄力、上升斩、反击、抓投、剑气、全屏大招 + 大招背景 backdrop、动作特效 effects、音效 |
| `swissknife` | 瑞士军刀（切换武器） | wrap 资源 + forms：剑 / 斧 / 弓；斧霸体；弓箭 aim input + gravity；巨箭大招 |
| `toolbox` | 工具箱（发展机制） | 采集（on_release + every）-> 合成（cost）-> 升级（upgrades + forms + levelup）-> 损坏（resource_empty -> goto）；炮台；持续回复 |
| `bulb` | 灯泡法师（远程） | beam、burn、slow 散射、stun、root 陷阱、silence 追踪、return 回旋、reflect、warp、fly、巨型光束大招 |

单武器角色最简写法：设 `held: "sword"`，不写 `resources` 和 `forms`。
切换武器写法见 `examples/swissknife/build.py`：

```json
"held": "sword",
"resources": { "slot": { "init": 0, "max": 2, "wrap": true, "keep_on_ko": true, "hud": "slot" } },
"actions": { "switch": { "type": "pose", "anim": "switch", "cooldown": 30, "links": [ { "when": "on_end", "gain": { "slot": 1 } } ] }, "...": {} },
"forms": [
  { "if": { "slot": "==1" }, "held": "axe", "input": { "attack.side": "axe_chop" } },
  { "if": { "slot": "==2" }, "held": "bow", "input": { "attack.side": "arrow" } }
],
"input": { "attack.side": "sword_lunge", "special.down": "switch", "jump": "jump" }
```

---

## 9. 常见错误

| 错误码 | 原因与改法 |
|---|---|
| `schema` | 字段名拼错、类型不对、缺必填字段。看 path 定位 |
| `pack.idle_body` / `pack.frame_body` | idle 第 0 帧与 body 不匹配，或某帧（常见：躺倒帧、举手帧）太大。改 body 或缩小那一帧 |
| `pack.colors` / `pack.alpha` | 颜色超过 32 种或有半透明。不要用抗锯齿、渐变、阴影混色 |
| `pack.attack_anim_frames` / `anim.durations` | 攻击姿势动画必须 3 帧且不写 durations；普通动画必须写 durations |
| `anim.hand` | 带武器的动作或设置了 held 时，相关动画必须有 hand，且数量等于帧数 |
| `attack.damage_startup` / `attack.force_startup` | 出招太快又太痛。加 startup 或减 damage/force |
| `attack.target_damage` | 多段 x 伤害 + burn + throw + 满蓄力超过 25。减段数或伤害 |
| `bullet.speed_side` | 子弹越大越慢：speed <= 96 / 最长边 |
| `motion.distance` | 位移不计重力积分到动作结束；在后面加一条把速度设小的 motion |
| `deployable.*` | 布置物要写 hp，接触伤害 hit_interval 必须 0，every 只能发射 bullet |
| `points.action` / `points.form` | 点数超预算：加 cooldown/cost、减伤害或段数 |
| `anim.required` | 缺必需动画；`max_count >= 2` 需要 double_jump，fly 需要 fly，charge / on_release 需要 charge |
| `jump.height_min` / `jump.reach_min` | 跳得太低或太近（场景是按这个保证设计的）。提高 velocity、降低 gravity、提高移动速度 |
| `link.when` / `link.input` / `link.warp` | 触发器用错位置；input/window 只能用于动作联动，warp 只能用于子弹联动 |

## 技能展示与快捷键

为主要动作填写简短 `name`，例如“壶嘴喷水”。在 `input` 中填写真实操作绑定；展示界面从 `input`、形态 `input` 和 `ultimate` 自动推导快捷键，不能另写一份可能过期的键位表。
键盘 A：J 攻、K 特、Space 跳、L 防、U 大招，W/A/S/D 方向。无直接按键的派生动作显示“联动触发”。
技能展示使用独立模拟播放实际攻击、子弹和特效，重复播放不改变角色包或对战状态。
