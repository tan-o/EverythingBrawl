extends SceneTree
## ENet 延迟测试的本机自检：同一进程内一个房主一个客户端，跑 3 秒。

var host: NetDemo
var client: NetDemo
var n := 0


func _initialize() -> void:
	host = NetDemo.new()
	host.name = "Host"
	client = NetDemo.new()
	client.name = "Client"
	root.add_child(host)
	root.add_child(client)
	host._host.call_deferred()
	client.ip_edit.text = "127.0.0.1"
	client._join.call_deferred()


func _physics_process(_d: float) -> bool:
	n += 1
	if n == 200:
		print("-- 房主 --\n", host.result_text())
		print("-- 客户端 --\n", client.result_text())
		var ok: bool = client.rtts.size() > 100 and host.rtts.size() > 100 and not client.snap_gaps.is_empty()
		print("OK" if ok else "FAIL")
		host._close()
		client._close()
		return true
	return false
