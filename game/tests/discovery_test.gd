extends SceneTree
## 房间发现自检：同一进程里一个房主广播、一个客户端搜索。

var h := Discovery.new()
var c := Discovery.new()
var t := 0.0


func _initialize() -> void:
	root.add_child(h)
	root.add_child(c)
	h.start_host({"name": "测试房间", "players": 1, "max": 4, "port": 7777})
	c.start_client()


func _process(d: float) -> bool:
	t += d
	if not c.rooms.is_empty():
		print("发现房间：", c.rooms.values()[0].name)
		print("OK")
		return true
	if t > 5.0:
		print("FAIL：5 秒内没有发现房间")
		return true
	return false
