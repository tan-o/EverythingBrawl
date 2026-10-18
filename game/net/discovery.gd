class_name Discovery
extends Node
## 局域网房间发现（UDP 广播）。
## 房主每 0.5 秒广播房间信息，并回复客户端的探测；客户端每 0.5 秒广播探测，并收集房间。
## Android 上开启广播时 Godot 会自动取得 WiFi MulticastLock（需要 CHANGE_WIFI_MULTICAST_STATE 权限，已在导出设置中开启）。

signal rooms_changed

const PORT := 7778
const PROTO := 1

var udp := PacketPeerUDP.new()
var hosting := false
var room := {}            # 房主广播的信息
var rooms := {}           # ip -> {name, players, port, seen}
var _t := 0.0


func start_client() -> void:
	_open()
	hosting = false


func start_host(info: Dictionary) -> void:
	_open()
	hosting = true
	room = info


func stop() -> void:
	udp.close()
	rooms.clear()


func _open() -> void:
	udp.close()
	udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	if udp.bind(PORT) != OK:
		udp.bind(0)


static func broadcast_addresses() -> Array:
	var out := ["255.255.255.255"]
	for a in NetDemo.local_ips():
		var p := a.split(".")
		out.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
	return out


func _send_all(msg: Dictionary) -> void:
	var b := var_to_bytes(msg)
	for addr in broadcast_addresses():
		udp.set_dest_address(addr, PORT)
		udp.put_packet(b)


func _process(delta: float) -> void:
	if not udp.is_bound():
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		if hosting:
			_send_all(_beacon())
		else:
			_send_all({"t": "probe", "v": PROTO})
		_expire()
	while udp.get_available_packet_count() > 0:
		var pkt := udp.get_packet()
		var ip := udp.get_packet_ip()
		var port := udp.get_packet_port()
		var msg = bytes_to_var(pkt)
		if not (msg is Dictionary) or msg.get("v") != PROTO:
			continue
		if hosting and msg.get("t") == "probe":
			udp.set_dest_address(ip, port)
			udp.put_packet(var_to_bytes(_beacon()))
		elif not hosting and msg.get("t") == "room":
			var changed: bool = not (ip in rooms) or rooms[ip].players != msg.players
			rooms[ip] = {"name": str(msg.name), "players": int(msg.players), "max": int(msg.max), "port": int(msg.port), "seen": Time.get_ticks_msec()}
			if changed:
				rooms_changed.emit()


func _beacon() -> Dictionary:
	var b := room.duplicate()
	b["t"] = "room"
	b["v"] = PROTO
	return b


func _expire() -> void:
	var now := Time.get_ticks_msec()
	var changed := false
	for ip in rooms.keys():
		if now - int(rooms[ip].seen) > 3000:
			rooms.erase(ip)
			changed = true
	if changed:
		rooms_changed.emit()
