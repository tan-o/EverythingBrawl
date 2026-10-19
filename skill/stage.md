# 像素大乱斗   场景包生成

把用户拍的一张**照片（桌面、厨房、书架、公园......）**变成一个对战场景：判断照片里哪些东西能站、能爬、会碎、会动、会伤人，
画背景和地形贴图，写 `stage.json`，打包成 zip。游戏加载时严格校验，第 4 节的规则不满足就拒绝加载。

## 1. 工作流程

1. **先还原，再映射玩法**：记录照片的画幅、视角、前中后景、主要物体的归一化位置与占比、主色。保留人物姿态和最有辨识度的地标；不要随机摆平台、把物体换成无关道具或套用示例地图。
2. **确定构图**：映射到 480x270。优先等比缩放和适度裁切；裁切会丢掉关键物体时保留主体并补边。不要把整张照片拉伸到变形。先画一个低分辨率全景并与原图对照位置关系。
3. **标注照片中可玩的表面**：桌面/地面 -> `solid` 主地面；书架/薄边 -> `platform`；瓶子/书堆 -> 可攀爬区域。原图物体应决定布局。主地面宽 >=160；相邻上升 <=36、水平间隙 <=56，头顶留 >=52 像素。必要时只对实际物体的边缘做小调整；高处纯背景物体不必硬改成平台。不要为凑规则重排整张照片。
4. **选择合适的背景机关**：有人的手持球就可以抛球，持拍/棍的手可挥击；壶嘴、水龙头可喷水，风扇可吹风。能力必须与原图中的对象、姿态和位置对应。保持原图对象本身，机关挂点对齐它的手/嘴/喷口。没有合适对象就不加机关。
5. **画背景与分层素材**：背景 480x270 或 240x135，整包 <=64 色，无半透明。对于已画在背景中的静态表面/人物，用 `background_region: true` 定位碰撞或机关，无需重复平铺覆盖原图。会移动、消失或破碎的物体从背景里移除，单独做 `tile` 图层，避免留下重影。
6. **写数据并校验**：安排 4 个出生点；机关预警清晰，攻击范围远离出生区。运行 `python scripts/validate.py <目录>` 到通过，再 `python scripts/pack.py <目录>`。
7. **对照原图验收**：逐项核对主体形状/位置/比例、主色、背景地标、人物姿态和机关挂点。预览中的发射来源必须看起来确实属于该物体。技术合法不代表还原到位；失真则回改画面与坐标。

物体行为参考：脆物 `crumble`、弹性物 `bounce`、滑面 `friction`、传送带 `conveyor`、活动物 `move`、烫/尖物 `damage`、风 `wind`、水 `water`、易碎物 `breakable`。选择照片中有依据的行为，避免全部堆上去。

## 2. 格式

zip 内只有 `stage.json` 与 `.png`。

```json
{
  "format": 1,
  "kind": "stage",
  "name": "厨房台面",
  "background": "bg",
  "spawns": [[130, 200], [180, 200], [230, 200], [290, 200]],
  "assets": {
    "bg":      { "kind": "background", "image": "bg.png" },
    "counter": { "kind": "tile", "image": "counter.png" }
  },
  "elements": [
    { "id": "counter", "rect": [72, 200, 336, 70], "collide": "solid", "tile": "counter" }
  ]
}
```

- 坐标：像素，x 向右，y 向下，屏幕 480x270。角色在屏幕外 48 像素处出界。
- `background`：kind 为 `background` 的素材；可以是横向帧条做动画（`frames` + `durations`）。
- `spawns`：恰好 4 个 `[x, y]`，y 是脚底，必须正好站在静止、可站立、不弹跳的地形顶面上。
- `elements`：每个元素 `rect: [x, y, 宽, 高]`、`collide`、`tile` 或 `background_region: true`（二选一，后者表示照片背景中已画出的静态区域），再加任意行为。

### collide

| 值 | 含义 |
|---|---|
| `solid` | 实心：四面都挡，顶面可站 |
| `platform` | 单向平台：只有顶面，下面能跳上来，按住下能穿下去 |
| `none` | 区域：不挡人，用来做风、水、危险物 |

### 行为（可以组合）

| 字段 | 用在 | 效果 |
|---|---|---|
| `climb: {max}` | solid | 两侧可贴墙攀爬，最多 `max` 帧，之后必须离开（落地才恢复）。可上爬、下滑、蹬墙跳 |
| `crumble: {after, respawn}` | solid / platform | 被站累计 `after` 帧后碎裂（快碎时会抖），`respawn` 帧后恢复；任何人的攻击打到它也会推进碎裂（每 1 点伤害算 6 帧） |
| `bounce: {velocity}` | solid / platform | 踩上去以 `velocity` 向上弹起 |
| `friction` | solid / platform | 地面摩擦倍率：0.3 很滑，2 很黏 |
| `conveyor` | solid / platform | 站在上面每帧被带着移动的像素（正数向右） |
| `move: {path, period, mode}` | 任意 | 沿 `path`（相对 rect 的偏移点列表）移动，`period` 帧走完一圈；`loop` 回到起点，`pingpong` 来回 |
| `damage: {damage, interval, knockback}` | 任意 | 碰到就受伤并被击退（角度：0 向外、90 向上），同一个人每 `interval` 帧最多一次，无视防御 |
| `wind: [x, y]` | none | 在区域内每帧加速度 |
| `water: {gravity_mul, drag}` | none | 区域内重力变小、速度衰减 |
| `blink: {on, off, offset, warn}` | 任意 | 出现 `on` 帧、消失 `off` 帧；消失时画淡影子；出现前 `warn` 帧闪烁预警 |
| `breakable: {hp, respawn}` | solid / platform | 被攻击打掉 `hp` 后碎掉，`respawn` 帧后恢复 |

### 背景区域与主动机关

`background_region: true` 复用背景中已画出的区域，只用于静态元素，不能同时写 `tile`，也不能配 `move/crumble/blink/breakable`。
普通背景装饰不需要元素；只有参与碰撞或有机关的对象才定义 `rect`。`rect` 与背景中的对象对应，不能用空白区域隐藏地形。

`trap` 属于某个元素，`origin` 是相对该元素 `rect` 左上角的局部坐标，必须在元素内部。元素移动时挂点跟着动；人物本体可留在背景，抛出的物体/挥击武器作为独立素材绘制。素材 kind 为 `hazard`，每边 <=64。

背景人物从手部发射：

```json
{"id":"person", "rect":[28,70,48,66], "collide":"none", "background_region":true,
 "trap":{"type":"shoot", "origin":[40,30], "asset":"ball",
         "period":240, "warn":45, "damage":5, "radius":4,
         "knockback":{"angle":45,"force":20}, "angle":0, "speed":3, "lifetime":110}}
```

配套素材：`"ball": {"kind":"hazard", "image":"ball.png"}`。图片画成直径 `2*radius` 的球/水滴，游戏按这个圆形尺寸显示和判定。世界角度 0 向右、90 向上；不追踪玩家、不随机方向，每周期预警后发射一枚，碰到实心地形或玩家消失，无穿透/反射。

背景人物持械挥击：

```json
{"id":"batter", "rect":[410,65,54,71], "collide":"none", "background_region":true,
 "trap":{"type":"swing", "origin":[10,30], "asset":"bat", "grip":[1,4],
         "length":36, "radius":4, "from":-60, "to":-120, "active":30,
         "period":240, "warn":45, "offset":90, "damage":5,
         "knockback":{"angle":45,"force":20}}}
```

配套素材 `bat` 同样是 `hazard`；武器水平朝右画，`grip` 是图片内握点，与人物的 `origin` 对齐。
`length` 与画出的武器长度一致，不能超过图片右侧；`radius` 与武器厚度一致。挥击生效期由 `from` 线性转到 `to`，判定为挂点到武器末端的胶囊体，每轮对每人只命中一次。

共同行为：每周期前 `warn` 帧显示环形和方向预警，再攻击，再休息；`offset` 延后第一周期，不跳过预警。元素消失/被破坏时停止发起攻击，恢复后重走预警；已经发出的弹体自然飞行到消失。机关攻击沿用场景危险物规则，无视普通防御，尊重无敌和出生保护。联机时只由房主模拟，客户端读取快照。

限制（以 `rules.json.stage_limits.trap` 为准）：最多6个机关、同时24枚弹体；period 120~1200，warn 30~180，warn+active < period，offset < period；伤害1~15，击退0~60，半径2~12；发射速度0.5~6、寿命1~120；挥击长度4~64、生效6~60帧、转角 <=180度。攻击全过程的保守包围范围不能覆盖出生区（按最大角色 40x48 计算），包括移动机关的全路径。

若校验报 `stage.trap_spawn`，调整朝向/射程/机关或出生点。不能缩小判定伪装成安全；出生位置也必须符合照片中的可站立表面。

## 3. 示例

`examples/stage_kitchen`（厨房台面）与 `examples/stage_desk`（书桌）各有一个 `build.py`，从零画出全部图片并写 `stage.json`，
这些是接口演示素材，不是新用户照片的默认布局。`stage_gallery` 演示背景人物抛球与挥拍；正式生成必须按实际照片重画。厨房：台面、砧板、可爬的麦片盒、会碎的饼干、弹人的烤面包机、周期点火的灶台（带预警）、蒸汽上升气流、上下移动的托盘、可打碎的糖罐。
书桌：桌面、传送带键盘、左右移动的直尺、可爬的书堆、铅笔、会熄灭的台灯光斑、滑溜溜的橡皮、咖啡杯（水）、小风扇（风）。

## 4. 游戏规则（不满足就拒绝加载）

所有数值以 `rules.json` 的 `stage_limits` 为准。

| 项 | 规则 |
|---|---|
| 包 | zip <= 1 MB；只有 stage.json 与 png；整包 <= 64 色；alpha 只有 0 / 255 |
| 背景 | 每帧 480x270 或 240x135 |
| 贴图 | 每边 <= 64 |
| 元素 | <= 40 个；有贴图或声明背景区域；含移动路径在内都在 x -16~496、y 0~300 内 |
| 主地面 | 至少一块宽 >= 160、静止（无 move / crumble / blink / breakable）、可站立、无伤害 |
| 出生点 | 4 个，站在静止可站立地形顶面（误差 1 像素内），两两距离 >= 40，离危险物 >= 48 |
| 头顶空间 | 每块可站立地形上方至少一半宽度留出 >= 52 像素不被 solid 挡住 |
| 可达 | 每块可站立地形都能从主地面跳过去：相邻上升 <= 36、水平间隙 <= 56（移动平台按路径上任一位置算） |
| climb | max 10~120 帧，只能用于 solid |
| crumble | after 30~600，respawn 60~900 |
| breakable | hp 5~60，respawn 60~900 |
| bounce | velocity 4~10 |
| friction | 0.2~2 |
| conveyor | 绝对值 <= 1.5 |
| move | path <= 8 个点；period 60~1200；平均速度 <= 2 像素/帧 |
| damage | damage 1~10；interval >= 30；force 0~60；全场最多 6 个 |
| wind | 加速度长度 <= 0.15 |
| water | gravity_mul 0.3~1；drag 0.85~1 |
| blink | on、off 各 60~1200；会挡人或会伤人的 blink 必须 warn >= 30 |
| 组合 | climb 只能 solid；crumble / bounce / friction / conveyor / breakable 不能用于 none；wind / water 只能用于 none |

## 5. 常见错误

| 错误码 | 改法 |
|---|---|
| `stage.reach` | 某个平台太高或太远。中间加一级台阶，或降低到距下面的面 <= 36 像素 |
| `stage.spawn_ground` | 出生点 y 要等于地面 rect 的 y，x 要在地面范围内，地面不能是移动 / 会碎 / 弹跳的 |
| `stage.headroom` | 地形上面压着太低的实心物体，角色站不进去 |
| `stage.invisible` | 写 tile；若物体已经画在背景上且静止，用 background_region: true |
| `stage.blink_warn` | 会出现的地形或危险物要给 warn >= 30，让玩家有时间反应 |
| `stage.colors` | 背景颜色太多。用色带、少量纯色块，不要渐变 |
