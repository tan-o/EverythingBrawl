class_name Sfxr
extends RefCounted
## jsfxr（https://github.com/chr15m/jsfxr）SoundEffect 合成器的 GDScript 移植。
## 角色包只存 jsfxr 参数，加载时合成为 16 位 AudioStreamWAV。
## 现有 Godot 版 sfxr 插件（tomeyro/godot-sfxr）是编辑器资源且已不维护，故按规范移植 jsfxr。

const OVERSAMPLING := 8
const MASTER_VOLUME := 1.0
const SQUARE := 0
const SAWTOOTH := 1
const SINE := 2
const NOISE := 3

const DEFAULTS := {
	"wave_type": 0,
	"p_env_attack": 0.0, "p_env_sustain": 0.3, "p_env_punch": 0.0, "p_env_decay": 0.4,
	"p_base_freq": 0.3, "p_freq_limit": 0.0, "p_freq_ramp": 0.0, "p_freq_dramp": 0.0,
	"p_vib_strength": 0.0, "p_vib_speed": 0.0,
	"p_arp_mod": 0.0, "p_arp_speed": 0.0,
	"p_duty": 0.0, "p_duty_ramp": 0.0,
	"p_repeat_speed": 0.0,
	"p_pha_offset": 0.0, "p_pha_ramp": 0.0,
	"p_lpf_freq": 1.0, "p_lpf_ramp": 0.0, "p_lpf_resonance": 0.0,
	"p_hpf_freq": 0.0, "p_hpf_ramp": 0.0,
	"sound_vol": 0.5, "sample_rate": 44100, "sample_size": 8,
}


static func with_defaults(params: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	return p


## 包络总长（秒），用于加载时校验音效时长。
static func seconds(params: Dictionary) -> float:
	var p := with_defaults(params)
	var n: float = floor(p.p_env_attack * p.p_env_attack * 100000.0) + floor(p.p_env_sustain * p.p_env_sustain * 100000.0) + floor(p.p_env_decay * p.p_env_decay * 100000.0)
	return n / 44100.0


var ps: Dictionary
var period: float
var period_max: float
var enable_frequency_cutoff: bool
var period_mult: float
var period_mult_slide: float
var duty_cycle: float
var duty_cycle_slide: float
var arpeggio_multiplier: float
var arpeggio_time: int
var elapsed_since_repeat: int


func _init_for_repeat() -> void:
	elapsed_since_repeat = 0
	period = 100.0 / (ps.p_base_freq * ps.p_base_freq + 0.001)
	period_max = 100.0 / (ps.p_freq_limit * ps.p_freq_limit + 0.001)
	enable_frequency_cutoff = ps.p_freq_limit > 0
	period_mult = 1 - pow(ps.p_freq_ramp, 3) * 0.01
	period_mult_slide = -pow(ps.p_freq_dramp, 3) * 0.000001
	duty_cycle = 0.5 - ps.p_duty * 0.5
	duty_cycle_slide = -ps.p_duty_ramp * 0.00005
	if ps.p_arp_mod >= 0:
		arpeggio_multiplier = 1 - pow(ps.p_arp_mod, 2) * 0.9
	else:
		arpeggio_multiplier = 1 + pow(ps.p_arp_mod, 2) * 10
	arpeggio_time = int(floor(pow(1 - ps.p_arp_speed, 2) * 20000 + 32))
	if ps.p_arp_speed == 1:
		arpeggio_time = 0


## 合成为 AudioStreamWAV（16 位单声道）。噪声用固定种子，保证各端一致。
static func generate(params: Dictionary) -> AudioStreamWAV:
	var s := Sfxr.new()
	return s._generate(with_defaults(params))


func _generate(p: Dictionary) -> AudioStreamWAV:
	ps = p
	_init_for_repeat()
	var wave_shape := int(ps.wave_type)
	var fltw: float = pow(ps.p_lpf_freq, 3) * 0.1
	var enable_low_pass_filter: bool = ps.p_lpf_freq != 1
	var fltw_d: float = 1 + ps.p_lpf_ramp * 0.0001
	var fltdmp: float = 5 / (1 + pow(ps.p_lpf_resonance, 2) * 20) * (0.01 + fltw)
	if fltdmp > 0.8:
		fltdmp = 0.8
	var flthp: float = pow(ps.p_hpf_freq, 2) * 0.1
	var flthp_d: float = 1 + ps.p_hpf_ramp * 0.0003
	var vibrato_speed: float = pow(ps.p_vib_speed, 2) * 0.01
	var vibrato_amplitude: float = ps.p_vib_strength * 0.5
	var envelope_length := [
		int(floor(ps.p_env_attack * ps.p_env_attack * 100000)),
		int(floor(ps.p_env_sustain * ps.p_env_sustain * 100000)),
		int(floor(ps.p_env_decay * ps.p_env_decay * 100000)),
	]
	var envelope_punch: float = ps.p_env_punch
	var flanger_offset: float = pow(ps.p_pha_offset, 2) * 1020
	if ps.p_pha_offset < 0:
		flanger_offset = -flanger_offset
	var flanger_offset_slide: float = pow(ps.p_pha_ramp, 2) * 1
	if ps.p_pha_ramp < 0:
		flanger_offset_slide = -flanger_offset_slide
	var repeat_time := int(floor(pow(1 - ps.p_repeat_speed, 2) * 20000 + 32))
	if ps.p_repeat_speed == 0:
		repeat_time = 0
	var gain: float = exp(ps.sound_vol) - 1
	var sample_rate := int(ps.sample_rate)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var fltp := 0.0
	var fltdp := 0.0
	var fltphp := 0.0
	var noise_buffer := PackedFloat32Array()
	noise_buffer.resize(32)
	for i in 32:
		noise_buffer[i] = rng.randf() * 2 - 1
	var envelope_stage := 0
	var envelope_elapsed := 0
	var vibrato_phase := 0.0
	var phase := 0
	var ipp := 0
	var flanger_buffer := PackedFloat32Array()
	flanger_buffer.resize(1024)
	var out := PackedByteArray()
	var sample_sum := 0.0
	var num_summed := 0
	var summands := int(floor(44100.0 / sample_rate))
	var t := 0
	while true:
		# Repeats
		elapsed_since_repeat += 1
		if repeat_time != 0 and elapsed_since_repeat >= repeat_time:
			_init_for_repeat()
		# Arpeggio (single)
		if arpeggio_time != 0 and t >= arpeggio_time:
			arpeggio_time = 0
			period *= arpeggio_multiplier
		# Frequency slide, and frequency slide slide!
		period_mult += period_mult_slide
		period *= period_mult
		if period > period_max:
			period = period_max
			if enable_frequency_cutoff:
				break
		# Vibrato
		var rfperiod := period
		if vibrato_amplitude > 0:
			vibrato_phase += vibrato_speed
			rfperiod = period * (1 + sin(vibrato_phase) * vibrato_amplitude)
		var iperiod := int(floor(rfperiod))
		if iperiod < OVERSAMPLING:
			iperiod = OVERSAMPLING
		# Square wave duty cycle
		duty_cycle += duty_cycle_slide
		duty_cycle = clamp(duty_cycle, 0.0, 0.5)
		# Volume envelope
		envelope_elapsed += 1
		if envelope_elapsed > envelope_length[envelope_stage]:
			envelope_elapsed = 0
			envelope_stage += 1
			if envelope_stage > 2:
				break
		var env_vol: float
		var stage_len: int = envelope_length[envelope_stage]
		var envf := float(envelope_elapsed) / stage_len if stage_len > 0 else 0.0
		if envelope_stage == 0:
			env_vol = envf
		elif envelope_stage == 1:
			env_vol = 1 + (1 - envf) * 2 * envelope_punch
		else:
			env_vol = 1 - envf
		# Flanger step
		flanger_offset += flanger_offset_slide
		var iphase := absi(int(floor(flanger_offset)))
		if iphase > 1023:
			iphase = 1023
		if flthp_d != 0:
			flthp *= flthp_d
			flthp = clamp(flthp, 0.00001, 0.1)
		# 8x oversampling
		var sample := 0.0
		for si in OVERSAMPLING:
			var sub_sample := 0.0
			phase += 1
			if phase >= iperiod:
				phase %= iperiod
				if wave_shape == NOISE:
					for i in 32:
						noise_buffer[i] = rng.randf() * 2 - 1
			var fp := float(phase) / iperiod
			if wave_shape == SQUARE:
				sub_sample = 0.5 if fp < duty_cycle else -0.5
			elif wave_shape == SAWTOOTH:
				if fp < duty_cycle:
					sub_sample = -1 + 2 * fp / duty_cycle
				else:
					sub_sample = 1 - 2 * (fp - duty_cycle) / (1 - duty_cycle)
			elif wave_shape == SINE:
				sub_sample = sin(fp * 2 * PI)
			else:
				sub_sample = noise_buffer[int(floor(phase * 32.0 / iperiod))]
			# Low-pass filter
			var pp := fltp
			fltw *= fltw_d
			fltw = clamp(fltw, 0.0, 0.1)
			if enable_low_pass_filter:
				fltdp += (sub_sample - fltp) * fltw
				fltdp -= fltdp * fltdmp
			else:
				fltp = sub_sample
				fltdp = 0
			fltp += fltdp
			# High-pass filter
			fltphp += fltp - pp
			fltphp -= fltphp * flthp
			sub_sample = fltphp
			# Flanger
			flanger_buffer[ipp & 1023] = sub_sample
			sub_sample += flanger_buffer[(ipp - iphase + 1024) & 1023]
			ipp = (ipp + 1) & 1023
			sample += sub_sample * env_vol
		t += 1
		sample_sum += sample
		num_summed += 1
		if num_summed >= summands:
			num_summed = 0
			sample = sample_sum / summands
			sample_sum = 0
		else:
			continue
		sample = sample / OVERSAMPLING * MASTER_VOLUME
		sample *= gain
		var v := clampi(int(floor(sample * 32768)), -32768, 32767)
		out.append(v & 0xff)
		out.append((v >> 8) & 0xff)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = out
	return wav
