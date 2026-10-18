class_name Palette
extends RefCounted
## 引擎内置美术用色（玩家色、状态效果、场地）。

const PLAYER := [Color("#e43b44"), Color("#3e8ed0"), Color("#63c74d"), Color("#feae34")]
const STAGE_TOP := Color("#8b9bb4")
const STAGE_BODY := Color("#3a4466")
const STAGE_EDGE := Color("#262b44")
const PLATFORM := Color("#c0cbdc")
const SKY_TOP := Color("#181425")
const SKY_BOTTOM := Color("#3a4466")
const FIRE := [Color("#f77622"), Color("#feae34"), Color("#e43b44")]
const SLOW := Color("#7fb6ff")
const STAR := Color("#fee761")
const CHAIN := Color("#8b9bb4")
const SILENCE := Color("#e43b44")
const SHIELD := Color(0.5, 0.8, 1.0, 0.45)
const REFLECT := Color(0.6, 1.0, 1.0, 0.8)
const GOLD := Color("#feae34")


static func player(i: int) -> Color:
	return PLAYER[i % PLAYER.size()]
