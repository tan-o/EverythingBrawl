class_name KeyboardInput
extends RefCounted
## 开发期键盘输入。方案 A：WASD + J攻击 K特殊 空格跳 L防御 U大招；
## 方案 B：方向键 + ,攻击 .特殊 /跳 右Shift防御 '大招（亦可用小键盘 1 2 3 0 4）。

const SCHEMES := {
	"kb1": {"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"attack": [KEY_J], "special": [KEY_K], "jump": [KEY_SPACE], "guard": [KEY_L], "ult": [KEY_U]},
	"kb2": {"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"attack": [KEY_COMMA, KEY_KP_1], "special": [KEY_PERIOD, KEY_KP_2], "jump": [KEY_SLASH, KEY_KP_3],
		"guard": [KEY_SHIFT, KEY_KP_0], "ult": [KEY_APOSTROPHE, KEY_KP_4]},
}


static func _down(keys: Array) -> bool:
	for k in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


static func read(scheme: String) -> Array:
	var s: Dictionary = SCHEMES[scheme]
	var stick := Vector2(float(_down(s.right)) - float(_down(s.left)), float(_down(s.down)) - float(_down(s.up)))
	var b := 0
	for k in ["attack", "special", "jump", "guard", "ult"]:
		if _down(s[k]):
			b |= InputFrame.BUTTONS[k]
	return [stick, b]
