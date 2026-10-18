# 像素大乱斗   场景包生成

把用户拍的一张**照片（桌面、厨房、书架、公园......）**变成一个对战场景：判断照片里哪些东西能站、能爬、会碎、会动、会伤人，
画背景和地形贴图，写 `stage.json`，打包成 zip。游戏加载时严格校验，第 4 节的规则不满足就拒绝加载。

## 1. 工作流程

1. **看照片，列物体**：每个显眼的物体想清楚它在游戏里是什么--
   - 大的水平面（桌面、台面、地面）：`solid` 主地面
   - 薄的、可以从下面跳上去的（砧板、书本边、铅笔、架子）：`platform`
   - 竖着的（盒子、书堆、瓶子）：`solid`，加 `climb` 可以贴墙攀爬
   - 脆的（饼干、薄冰、纸）：加 `crumble` 站久会碎
   - 有弹性的（弹簧、面包机、蹦床、海绵）：加 `bounce`
   - 滑的（冰、玻璃、肥皂）：`friction` < 1；黏的（胶带、蜂蜜）：`friction` > 1
   - 会带人走的（键盘、传送带、河流表面）：`conveyor`
   - 会动的（直尺、托盘、电梯）：`move`
   - 烫的、尖的（灶台、仙人掌、电线）：`damage`，最好配 `blink` 周期出现并预警
   - 风扇、蒸汽：`wind` 区域；水杯、水池、汤锅：`water` 区域
   - 易碎的罐子、积木：`breakable` 可被打碎
   - 灯光、开关、闪烁的东西：`blink` 周期出现 / 消失
2. **先定主地面**：宽 >= 160、静止。屏幕是 480x270，主地面一般在 y = 190~210。
3. **按跳跃保证摆高度**：所有角色都保证一次跳 >= 40 像素高、>= 64 像素远。场景规则是
   **相邻可站立面的上升高度 <= 36、水平间隙 <= 56**，按这个阶梯摆放平台，每块都要能从主地面一路跳上去。
4. **画背景**（240x135 画好后游戏放大 2 倍，或直接 480x270）和每种地形的**平铺贴图**（每边 <= 64，会在元素矩形里重复铺满）。
   整个包 <= 64 色，无半透明。背景只是装饰，不参与碰撞。
5. **写 `stage.json`**，放 4 个出生点。
6. `python scripts/validate.py <场景目录>` 直到通过；`python scripts/pack.py <场景目录>` 打包。

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
- `elements`：每个元素 `rect: [x, y, 宽, 高]`、`collide`、`tile`（必填，不能有看不见的地形），再加任意行为。

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
| `crumble: {after, respawn}` | solid / platform | 被站累计 `after` 帧后碎裂（快碎时会抖），`respawn` 帧后恢复 |
| `bounce: {velocity}` | solid / platform | 踩上去以 `velocity` 向上弹起 |
| `friction` | solid / platform | 地面摩擦倍率：0.3 很滑，2 很黏 |
| `conveyor` | solid / platform | 站在上面每帧被带着移动的像素（正数向右） |
| `move: {path, period, mode}` | 任意 | 沿 `path`（相对 rect 的偏移点列表）移动，`period` 帧走完一圈；`loop` 回到起点，`pingpong` 来回 |
| `damage: {damage, interval, knockback}` | 任意 | 碰到就受伤并被击退（角度：0 向外、90 向上），同一个人每 `interval` 帧最多一次，无视防御 |
| `wind: [x, y]` | none | 在区域内每帧加速度 |
| `water: {gravity_mul, drag}` | none | 区域内重力变小、速度衰减 |
| `blink: {on, off, offset, warn}` | 任意 | 出现 `on` 帧、消失 `off` 帧；消失时画淡影子；出现前 `warn` 帧闪烁预警 |
| `breakable: {hp, respawn}` | solid / platform | 被攻击打掉 `hp` 后碎掉，`respawn` 帧后恢复 |

## 3. 示例

`examples/stage_kitchen`（厨房台面）与 `examples/stage_desk`（书桌）各有一个 `build.py`，从零画出全部图片并写 `stage.json`，
可以照着改。厨房：台面、砧板、可爬的麦片盒、会碎的饼干、弹人的烤面包机、周期点火的灶台（带预警）、蒸汽上升气流、上下移动的托盘、可打碎的糖罐。
书桌：桌面、传送带键盘、左右移动的直尺、可爬的书堆、铅笔、会熄灭的台灯光斑、滑溜溜的橡皮、咖啡杯（水）、小风扇（风）。

## 4. 游戏规则（不满足就拒绝加载）

所有数值以 `rules.json` 的 `stage_limits` 为准。

| 项 | 规则 |
|---|---|
| 包 | zip <= 1 MB；只有 stage.json 与 png；整包 <= 64 色；alpha 只有 0 / 255 |
| 背景 | 每帧 480x270 或 240x135 |
| 贴图 | 每边 <= 64 |
| 元素 | <= 40 个；必须有贴图；含移动路径在内都在 x -16~496、y 0~300 内 |
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
| `stage.invisible` | 每个元素都要写 tile |
| `stage.blink_warn` | 会出现的地形或危险物要给 warn >= 30，让玩家有时间反应 |
| `stage.colors` | 背景颜色太多。用色带、少量纯色块，不要渐变 |
