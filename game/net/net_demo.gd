class_name NetDemo
extends Control
## 最小 ENet 双机测试：两端以 60Hz 互发 ping（不可靠通道），对方立即回显；
## 房主另以 60Hz 下发约 300 字节的模拟快照。统计往返延迟、抖动、丢包与快照到达间隔。

signal exited

const PORT := 7777
const PING := 1
const PONG := 2
const SNAP := 3
const SNAP_BYTES := 300

var peer: ENetMultiplayerPeer
var mp: SceneMultiplayer
var role := ""
var seq := 0
var sent := {}            # seq -> 发送时间（微秒）
var rtts := PackedFloat32Array()
var lost := 0
var received := 0
var last_rtt := -1.0
var jitter_sum := 0.0
var jitter_n := 0
var snap_last_us := 0
var snap_gaps := PackedFloat32Array()
var started_us := 0
var ip_edit := LineEdit.new()
var status := Label.new()
var stats_label := Label.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s := Menus.screen("联机延迟测试（ENet）")
	add_child(s[0])
	var box: VBoxContainer = s[1]
	box.add_child(Menus.label("本机 IP：" + ", ".join(local_ips()) + "    端口 %d" % PORT, 22))
	var row := HBoxContainer.new()
	row.add_child(Menus.button("作为房主", _host, 220))
	ip_edit.placeholder_text = "房主 IP"
	ip_edit.custom_minimum_size = Vector2(300, 64)
	row.add_child(ip_edit)
	row.add_child(Menus.button("加入", _join, 160))
	box.add_child(row)
	status.add_theme_font_size_override("font_size", 22)
	box.add_child(status)
	stats_label.add_theme_font_size_override("font_size", 22)
	box.add_child(stats_label)
	var row2 := HBoxContainer.new()
	row2.add_child(Menus.button("重置统计", _reset, 200))
	row2.add_child(Menus.button("复制结果", func(): DisplayServer.clipboard_set(result_text()), 200))
	row2.add_child(Menus.button("返回", _back, 200))
	box.add_child(row2)
	status.text = "选择一台设备作为房主，另一台输入其 IP 加入。"


static func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func _setup_mp() -> void:
	mp = SceneMultiplayer.new()
	mp.multiplayer_peer = peer
	mp.peer_packet.connect(_on_packet)
	mp.peer_connected.connect(_on_connected)
	mp.peer_disconnected.connect(_on_disconnected)
	get_tree().set_multiplayer(mp, get_path())


func _on_connected(id: int) -> void:
	status.text = "%s：已连接 peer %d" % [role, id]
	_reset()


func _on_disconnected(id: int) -> void:
	status.text = "%s：peer %d 断开" % [role, id]


func _host() -> void:
	_close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 3)
	if err != OK:
		status.text = "创建房间失败：%s" % error_string(err)
		return
	role = "房主"
	_setup_mp()
	status.text = "房主：等待连接（%s:%d）" % [", ".join(local_ips()), PORT]


func _join() -> void:
	_close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_edit.text.strip_edges(), PORT)
	if err != OK:
		status.text = "连接失败：%s" % error_string(err)
		return
	role = "客户端"
	_setup_mp()
	status.text = "客户端：连接中..."


func _close() -> void:
	if peer != null:
		peer.close()
	peer = null
	if mp != null:
		mp.multiplayer_peer = null
	mp = null


func _back() -> void:
	_close()
	exited.emit()


func _reset() -> void:
	sent.clear()
	rtts = PackedFloat32Array()
	lost = 0
	received = 0
	last_rtt = -1.0
	jitter_sum = 0.0
	jitter_n = 0
	snap_gaps = PackedFloat32Array()
	snap_last_us = 0
	started_us = Time.get_ticks_usec()


func _physics_process(_d: float) -> void:
	if mp == null or mp.get_peers().is_empty():
		return
	var now := Time.get_ticks_usec()
	seq += 1
	var b := PackedByteArray()
	b.resize(13)
	b.encode_u8(0, PING)
	b.encode_u32(1, seq)
	b.encode_u64(5, now)
	sent[seq] = now
	mp.send_bytes(b, 0, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	if role == "房主":
		var sn := PackedByteArray()
		sn.resize(SNAP_BYTES)
		sn.encode_u8(0, SNAP)
		mp.send_bytes(sn, 0, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	# 超过 1 秒未回的算丢包
	for k in sent.keys():
		if now - int(sent[k]) > 1000000:
			sent.erase(k)
			lost += 1
	_update_label()


func _on_packet(id: int, b: PackedByteArray) -> void:
	if b.size() < 1:
		return
	var t := b.decode_u8(0)
	if t == PING:
		var r := b.duplicate()
		r.encode_u8(0, PONG)
		mp.send_bytes(r, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	elif t == PONG:
		var s := b.decode_u32(1)
		if not (s in sent):
			return
		sent.erase(s)
		var rtt := (Time.get_ticks_usec() - b.decode_u64(5)) / 1000.0
		rtts.append(rtt)
		received += 1
		if last_rtt >= 0:
			jitter_sum += abs(rtt - last_rtt)
			jitter_n += 1
		last_rtt = rtt
	elif t == SNAP:
		var now := Time.get_ticks_usec()
		if snap_last_us > 0:
			snap_gaps.append((now - snap_last_us) / 1000.0)
		snap_last_us = now


static func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(p * (s.size() - 1)), 0, s.size() - 1)]


static func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func result_text() -> String:
	var secs := (Time.get_ticks_usec() - started_us) / 1e6
	var total := received + lost
	var lines := PackedStringArray()
	lines.append("角色：%s   时长：%.0f 秒   样本：%d" % [role, secs, rtts.size()])
	lines.append("往返延迟 RTT（ms）：最小 %.1f / 平均 %.1f / 中位 %.1f / P95 %.1f / P99 %.1f / 最大 %.1f" % [
		_pct(rtts, 0.0), _mean(rtts), _pct(rtts, 0.5), _pct(rtts, 0.95), _pct(rtts, 0.99), _pct(rtts, 1.0)])
	lines.append("抖动（相邻 RTT 差的平均）：%.2f ms" % (jitter_sum / max(1, jitter_n)))
	lines.append("丢包：%d / %d（%.2f%%）" % [lost, total, 100.0 * lost / max(1, total)])
	if not snap_gaps.is_empty():
		lines.append("快照到达间隔（ms，理想 16.7）：平均 %.2f / P95 %.2f / P99 %.2f / 最大 %.2f" % [
			_mean(snap_gaps), _pct(snap_gaps, 0.95), _pct(snap_gaps, 0.99), _pct(snap_gaps, 1.0)])
	return "\n".join(lines)


func _update_label() -> void:
	if Engine.get_physics_frames() % 15 == 0:
		stats_label.text = result_text()
