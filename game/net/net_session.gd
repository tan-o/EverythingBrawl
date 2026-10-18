class_name NetSession
extends Node
## 联机会话（房主权威）：ENet 连接、大厅、角色包/场景包同步（按 SHA-256 缓存，房主用游戏内校验器校验）、
## 对战中的输入上传（不可靠通道 + 最近 8 帧冗余）与快照下发（不可靠通道，附带最近几帧的事件）。

signal lobby_changed
signal started(info: Dictionary)   # {players: [{id, char}], stage, seed}
signal ended
signal failed(msg: String)
signal notice(msg: String)

const PORT := 7777
const MAX_PLAYERS := 4
const PROTO := 1
const CH_RELIABLE := 0
const CH_FAST := 1
const MSG := 77       # 'M'：可靠消息（var_to_bytes 字典）
const INP := 73       # 'I'：输入
const SNP := 83       # 'S'：快照
const INPUT_REDUNDANCY := 8
const EVENT_FRAMES := 10

var peer: ENetMultiplayerPeer
var mp: SceneMultiplayer
var is_host := false
var my_id := 0
var my_name := ""
var players := {}         # id -> {id, name, char, stage, char_name, stage_name, char_ok, stage_ok, err, synced}
var order := []           # 加入顺序
var in_match := false
var _want_sent := {}
var _synced_sent := ""

# 对战
var remote := {}          # 房主：id -> {"queue": [], "last_seq": 0, "last": InputFrame}
var snaps := []           # 客户端：收到的快照（按帧排序）
var _seq := 0
var _hist := []           # 客户端：最近的输入（已编码）
var _recent_events := []  # 房主：[[frame, events], ...]


func _ready() -> void:
	my_name = "玩家 %s" % (NetDemo.local_ips()[0].split(".")[-1] if not NetDemo.local_ips().is_empty() else str(randi() % 1000))


# ---------------------------------------------------------------- 连接

func host() -> bool:
	close()
	peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1, 2) != OK:
		failed.emit("创建房间失败（端口 %d 被占用？）" % PORT)
		return false
	is_host = true
	_setup()
	my_id = 1
	_add_player(1, my_name)
	return true


func join(ip: String, port := PORT) -> bool:
	close()
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, port, 2) != OK:
		failed.emit("无法连接 %s" % ip)
		return false
	is_host = false
	_setup()
	return true


func _setup() -> void:
	mp = SceneMultiplayer.new()
	mp.multiplayer_peer = peer
	mp.peer_packet.connect(_on_packet)
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(func(): failed.emit("连接失败"))
	mp.server_disconnected.connect(func(): failed.emit("房主已断开"))
	get_tree().set_multiplayer(mp, get_path())


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	if mp != null:
		mp.multiplayer_peer = null
	mp = null
	players.clear()
	order.clear()
	in_match = false
	remote.clear()
	snaps.clear()
	_want_sent.clear()
	_synced_sent = ""


func connected() -> bool:
	return mp != null and (is_host or my_id != 0)


## 关掉 ENet 对不可靠包的节流（默认会在延迟抖动时主动丢弃不可靠包）。
static func disable_throttle(p: ENetPacketPeer) -> void:
	if p != null:
		p.throttle_configure(5000, 2, 0)


func _on_peer_connected(id: int) -> void:
	if is_host:
		disable_throttle(peer.get_peer(id))
	elif id == 1:
		disable_throttle(peer.get_peer(1))


func _on_connected() -> void:
	_send(1, {"t": "hello", "name": my_name, "v": PROTO})


func _on_peer_disconnected(id: int) -> void:
	if is_host and id in players:
		players.erase(id)
		order.erase(id)
		remote.erase(id)
		_broadcast_lobby()


# ---------------------------------------------------------------- 消息

func _send(to: int, msg: Dictionary) -> void:
	if mp == null:
		return
	var b := PackedByteArray([MSG])
	b.append_array(var_to_bytes(msg))
	mp.send_bytes(b, to, MultiplayerPeer.TRANSFER_MODE_RELIABLE, CH_RELIABLE)


func _on_packet(id: int, b: PackedByteArray) -> void:
	if b.is_empty():
		return
	match b[0]:
		MSG:
			var msg = bytes_to_var(b.slice(1))
			if msg is Dictionary:
				if is_host:
					_host_msg(id, msg)
				else:
					_client_msg(msg)
		INP:
			if is_host:
				_on_input(id, b)
		SNP:
			if not is_host:
				_on_snapshot(b)


# ---------------------------------------------------------------- 房主

func _add_player(id: int, name: String) -> void:
	players[id] = {"id": id, "name": name, "char": "", "stage": "", "char_name": "", "stage_name": "",
		"char_ok": false, "stage_ok": false, "err": "", "synced": id == 1}
	order.append(id)


func _host_msg(id: int, msg: Dictionary) -> void:
	match msg.get("t"):
		"hello":
			if msg.get("v") != PROTO:
				_send(id, {"t": "bye", "why": "版本不一致"})
				return
			if players.size() >= MAX_PLAYERS or in_match:
				_send(id, {"t": "bye", "why": "房间已满或正在对战"})
				return
			_add_player(id, str(msg.get("name", "玩家")))
			_send(id, {"t": "welcome", "id": id})
			_broadcast_lobby()
		"pick":
			if id in players:
				_set_pick(id, str(msg.get("char", "")), str(msg.get("stage", "")))
		"pack":
			_receive_pack(msg)
		"want":
			var sha := str(msg.get("sha", ""))
			if PackLibrary.cache_has(sha):
				_send(id, {"t": "pack", "sha": sha, "data": PackLibrary.cache_get(sha)})
		"synced":
			if id in players:
				players[id].synced = bool(msg.get("ok", false))
				_broadcast_lobby()


func _set_pick(id: int, char_sha: String, stage_sha: String) -> void:
	var p: Dictionary = players[id]
	p.char = char_sha
	p.stage = stage_sha
	for sha in [char_sha, stage_sha]:
		if sha != "" and not PackLibrary.cache_has(sha):
			_send(id, {"t": "need", "sha": sha})
	_revalidate()
	_broadcast_lobby()


func _receive_pack(msg: Dictionary) -> void:
	var data: PackedByteArray = msg.get("data", PackedByteArray())
	var sha := PackReader.hash_bytes(data)
	if sha != str(msg.get("sha", "")):
		return
	PackLibrary.cache_put(data)
	if is_host:
		_revalidate()
		_broadcast_lobby()
	else:
		_check_sync()


## 房主用游戏内校验器校验每个玩家选的角色与场景。
func _revalidate() -> void:
	for p in players.values():
		p.err = ""
		p.char_ok = _check(p, "char", "character")
		p.stage_ok = _check(p, "stage", "stage")


func _check(p: Dictionary, key: String, kind: String) -> bool:
	var sha: String = p[key]
	p[key + "_name"] = ""
	if sha == "" or not PackLibrary.cache_has(sha):
		return false
	var v := PackLibrary.cache_validator(sha)
	if v.data != null and not v.data.is_empty():
		p[key + "_name"] = str(v.data.get("name", ""))
	if not v.is_valid() or v.kind != kind:
		p.err = ("角色包" if kind == "character" else "场景包") + "不合法：\n" + v.report()
		return false
	return true


func _broadcast_lobby() -> void:
	var list := []
	for id in order:
		list.append(players[id])
	for id in order:
		if id != 1:
			_send(id, {"t": "lobby", "players": list})
	lobby_changed.emit()


func can_start() -> bool:
	if not is_host or players.size() < 2 or in_match:
		return false
	for p in players.values():
		if not (p.char_ok and p.stage_ok and p.synced):
			return false
	return true


func start_match() -> void:
	if not can_start():
		return
	var plist := []
	var stages := []
	for id in order:
		plist.append({"id": id, "char": players[id].char})
		stages.append(players[id].stage)
	# 每人选一个场景，开打时随机选其中一个
	var info := {"t": "start", "players": plist, "stage": stages[randi() % stages.size()], "seed": randi()}
	for id in order:
		if id != 1:
			_send(id, info)
	_begin(info)


func end_match() -> void:
	if is_host:
		for id in order:
			if id != 1:
				_send(id, {"t": "end"})
	in_match = false
	ended.emit()


func _begin(info: Dictionary) -> void:
	in_match = true
	remote.clear()
	snaps.clear()
	_recent_events.clear()
	_seq = 0
	_hist.clear()
	started.emit(info)


# ---------------------------------------------------------------- 客户端

func _client_msg(msg: Dictionary) -> void:
	match msg.get("t"):
		"welcome":
			my_id = int(msg.id)
			lobby_changed.emit()
		"bye":
			failed.emit(str(msg.get("why", "被房间拒绝")))
		"lobby":
			players.clear()
			order.clear()
			for p in msg.players:
				players[int(p.id)] = p
				order.append(int(p.id))
			_check_sync()
			lobby_changed.emit()
		"need":
			var sha := str(msg.sha)
			if PackLibrary.cache_has(sha):
				_send(1, {"t": "pack", "sha": sha, "data": PackLibrary.cache_get(sha)})
		"pack":
			_receive_pack(msg)
		"start":
			_begin(msg)
		"end":
			in_match = false
			ended.emit()


## 自己的选择（房主直接生效；客户端发给房主）。
func set_pick(char_sha: String, stage_sha: String) -> void:
	if is_host:
		_set_pick(1, char_sha, stage_sha)
	elif my_id != 0:
		_send(1, {"t": "pick", "char": char_sha, "stage": stage_sha})


## 客户端：把大厅里所有人选的包都拿到本地；齐了就告诉房主。
func _check_sync() -> void:
	var missing := false
	for p in players.values():
		for sha in [p.char, p.stage]:
			if sha == "" or PackLibrary.cache_has(sha):
				continue
			missing = true
			if not (sha in _want_sent):
				_want_sent[sha] = true
				_send(1, {"t": "want", "sha": sha})
	var key := str(missing) + "|" + ",".join(PackedStringArray(players.keys().map(func(k): return str(players[k].char) + str(players[k].stage))))
	if key != _synced_sent:
		_synced_sent = key
		_send(1, {"t": "synced", "ok": not missing})


# ---------------------------------------------------------------- 对战数据

## 客户端：上传本帧输入（附带最近 8 帧）。
func send_input(f: InputFrame) -> void:
	_seq += 1
	_hist.append(f.encode())
	if _hist.size() > INPUT_REDUNDANCY:
		_hist.pop_front()
	var b := PackedByteArray([INP, 0, 0, 0, 0, _hist.size()])
	b.encode_u32(1, _seq)
	for h in _hist:
		b.append_array(h)
	mp.send_bytes(b, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, CH_FAST)


func _on_input(id: int, b: PackedByteArray) -> void:
	if b.size() < 6:
		return
	var seq := b.decode_u32(1)
	var n := b[5]
	if b.size() < 6 + n * 3:
		return
	if not (id in remote):
		remote[id] = {"queue": [], "last_seq": 0, "last": InputFrame.new()}
	var r: Dictionary = remote[id]
	# 包里是 seq-n+1 .. seq 的输入，只取没收到过的
	for k in n:
		var s := seq - n + 1 + k
		if s > r.last_seq:
			r.queue.append(InputFrame.decode(b, 6 + k * 3))
	r.last_seq = max(r.last_seq, seq)


## 房主：取某玩家本帧输入。积压时合并，保证按键不丢、延迟不涨。
func input_for(id: int) -> InputFrame:
	if not (id in remote):
		return InputFrame.new()
	var r: Dictionary = remote[id]
	var q: Array = r.queue
	if q.is_empty():
		return r.last
	var merged := 0
	while q.size() > 2:
		merged |= q.pop_front().buttons
	var f: InputFrame = q.pop_front()
	f.buttons |= merged
	r.last = f
	return f


## 房主：下发快照（附带最近几帧事件，丢包时客户端也能补上音效特效）。
func send_snapshot(s: Dictionary) -> void:
	_recent_events.append([s.frame, s.events])
	if _recent_events.size() > EVENT_FRAMES:
		_recent_events.pop_front()
	var out := s.duplicate()
	out.erase("events")
	out["ev"] = _recent_events
	var raw := var_to_bytes(out)
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var b := PackedByteArray([SNP, 0, 0, 0, 0])
	b.encode_u32(1, raw.size())
	b.append_array(z)
	mp.send_bytes(b, 0, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, CH_FAST)


func _on_snapshot(b: PackedByteArray) -> void:
	if b.size() < 6:
		return
	var raw := b.slice(5).decompress(b.decode_u32(1), FileAccess.COMPRESSION_DEFLATE)
	var s = bytes_to_var(raw)
	if not (s is Dictionary):
		return
	snaps.append(s)
	snaps.sort_custom(func(x, y): return x.frame < y.frame)
	while snaps.size() > 30:
		snaps.pop_front()
