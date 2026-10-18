class_name InputFrame
extends RefCounted
## 一帧输入：按键位掩码 + 量化摇杆（每轴 int8）。联机时原样上传。

const ATTACK := 1
const SPECIAL := 2
const JUMP := 4
const GUARD := 8
const ULT := 16
const BUTTONS := {"attack": ATTACK, "special": SPECIAL, "jump": JUMP, "guard": GUARD, "ult": ULT}

var buttons := 0
var sx := 0   # -127..127，右为正
var sy := 0   # -127..127，下为正


static func make(stick: Vector2, btn: int) -> InputFrame:
	var f := InputFrame.new()
	var s := stick.limit_length(1.0)
	f.sx = clampi(roundi(s.x * 127.0), -127, 127)
	f.sy = clampi(roundi(s.y * 127.0), -127, 127)
	f.buttons = btn
	return f


func stick() -> Vector2:
	return Vector2(sx / 127.0, sy / 127.0)


func held(b: int) -> bool:
	return buttons & b != 0


func encode() -> PackedByteArray:
	return PackedByteArray([buttons & 0xff, sx & 0xff, sy & 0xff])


static func decode(b: PackedByteArray, ofs := 0) -> InputFrame:
	var f := InputFrame.new()
	f.buttons = b[ofs]
	f.sx = b[ofs + 1] - 256 if b[ofs + 1] > 127 else b[ofs + 1]
	f.sy = b[ofs + 2] - 256 if b[ofs + 2] > 127 else b[ofs + 2]
	return f


## 规范 4.9：偏移 < 0.5 为 neutral；否则 |y| > |x| 取 up/down，反之 side。
static func direction(stick: Vector2) -> String:
	if stick.length() < 0.5:
		return "neutral"
	if abs(stick.y) > abs(stick.x):
		return "up" if stick.y < 0 else "down"
	return "side"
