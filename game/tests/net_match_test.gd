extends SceneTree
## 联机流程自检（本机回环）：房主 + 客户端，选包、同步、开局、跑 600 帧。

var host := NetSession.new()
var client := NetSession.new()
var n := 0
var phase := "connect"
var hs: MatchScreen
var cs: MatchScreen
var picks := {}


func _initialize() -> void:
	host.name = "H"
	client.name = "C"
	root.add_child(host)
	root.add_child(client)
	host.started.connect(func(info): hs = _screen(host, info))
	client.started.connect(func(info): cs = _screen(client, info))
	picks = {
		"hc": PackLibrary.load_pack("res://data/packs/knight.zip").pack.sha256,
		"hs": PackLibrary.load_pack("res://data/stages/kitchen.zip").pack.sha256,
		"cc": PackLibrary.load_pack("res://data/packs/bulb.zip").pack.sha256,
		"cs": PackLibrary.load_pack("res://data/stages/desk.zip").pack.sha256,
	}

	if OS.get_cmdline_user_args().has("traps"):
		picks.hc = PackLibrary.load_pack("res://data/packs/teapot.zip").pack.sha256
		picks.hs = PackLibrary.load_pack("res://data/stages/gallery.zip").pack.sha256
		picks.cs = picks.hs


func _screen(s: NetSession, info: Dictionary) -> MatchScreen:
	var players := []
	for p in info.players:
		var id := int(p.id)
		var inp := "touch" if id == s.my_id else ("net" if s.is_host else "remote")
		players.append({"validator": PackLibrary.cache_validator(str(p.char)), "input": inp, "peer": id})
	var m := MatchScreen.new()
	root.add_child(m)
	m.start(players, PackLibrary.cache_validator(str(info.stage)), s)
	print("%s 开局，场景 %s" % ["房主" if s.is_host else "客户端", PackLibrary.cache_validator(str(info.stage)).data.name])
	return m


func _process(_d: float) -> bool:
	n += 1
	match phase:
		"connect":
			host.host()
			host.set_pick(picks.hc, picks.hs)
			client.join("127.0.0.1")
			phase = "lobby"
		"lobby":
			if client.my_id != 0 and not client.players.is_empty():
				client.set_pick(picks.cc, picks.cs)
				phase = "wait"
		"wait":
			if host.can_start():
				host.start_match()
				phase = "play"
				n = 0
		"play":
			if hs != null and hs.sim.frame >= 600:
				var ok := cs != null and client.snaps.size() > 0 and cs._render_frame >= hs.sim.frame - 8
				if OS.get_cmdline_user_args().has("traps"):
					ok = ok and not cs.world.last.get("traps", {}).get("shots", []).is_empty()
				print("客户端渲染到第 %d 帧，房主模拟到第 %d 帧" % [cs._render_frame if cs else -1, hs.sim.frame if hs else -1])
				print("OK" if ok else "FAIL")
				return true
	if n > 3000:
		print("FAIL: 超时 phase=", phase)
		return true
	return false
