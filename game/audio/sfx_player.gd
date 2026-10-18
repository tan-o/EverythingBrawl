class_name SfxPlayer
extends Node
## 播放快照事件对应的音效：角色包音效 + 引擎内置音效（命中、防御、击倒、跳跃、大招预警等）。

const ENGINE := {
	"hit": {"wave_type": 3, "p_env_sustain": 0.05, "p_env_decay": 0.18, "p_base_freq": 0.45, "p_freq_ramp": -0.35, "sound_vol": 0.35},
	"block": {"wave_type": 0, "p_env_sustain": 0.04, "p_env_decay": 0.1, "p_base_freq": 0.7, "p_duty": 0.4, "sound_vol": 0.25},
	"break": {"wave_type": 3, "p_env_sustain": 0.2, "p_env_decay": 0.4, "p_base_freq": 0.25, "p_freq_ramp": -0.1, "sound_vol": 0.4},
	"ko": {"wave_type": 3, "p_env_sustain": 0.3, "p_env_decay": 0.5, "p_base_freq": 0.18, "p_freq_ramp": -0.05, "sound_vol": 0.45},
	"jump": {"wave_type": 0, "p_env_sustain": 0.1, "p_env_decay": 0.15, "p_base_freq": 0.35, "p_freq_ramp": 0.2, "p_duty": 0.5, "sound_vol": 0.2},
	"ult": {"wave_type": 1, "p_env_attack": 0.1, "p_env_sustain": 0.4, "p_env_decay": 0.4, "p_base_freq": 0.2, "p_freq_ramp": 0.08, "p_vib_strength": 0.4, "p_vib_speed": 0.5, "sound_vol": 0.4},
	"heal": {"wave_type": 2, "p_env_sustain": 0.12, "p_env_decay": 0.2, "p_base_freq": 0.5, "p_freq_ramp": 0.15, "sound_vol": 0.25},
	"gain": {"wave_type": 0, "p_env_sustain": 0.05, "p_env_decay": 0.12, "p_base_freq": 0.6, "p_arp_mod": 0.4, "p_arp_speed": 0.6, "p_duty": 0.3, "sound_vol": 0.2},
}

var engine := {}
var packs: Array = []     # PackAssets
var pool: Array = []


func setup(p_packs: Array) -> void:
	packs = p_packs
	for k in ENGINE:
		engine[k] = Sfxr.generate(ENGINE[k])
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)


func play(stream: AudioStream) -> void:
	if stream == null:
		return
	for p in pool:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	pool[0].stream = stream
	pool[0].play()


func handle(events: Array) -> void:
	for e in events:
		match e.t:
			"sfx":
				play(packs[e.i].sounds.get(e.name))
			"hit":
				var s = packs[e.i].sounds.get(e.sfx) if e.sfx != "" else null
				play(s if s != null else engine.hit)
			"block":
				play(engine.block)
			"shield_break":
				play(engine["break"])
			"ko", "blast":
				play(engine.ko)
			"jump":
				play(engine.jump)
			"ult_start":
				play(engine.ult)
			"heal":
				play(engine.heal)
			"res_gain":
				play(engine.gain)
