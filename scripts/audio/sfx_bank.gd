class_name SfxBank
extends RefCounted

## Procedurally synthesized sound effects. The project ships zero imported
## assets, so every sound is generated at startup with plain math and packed
## into AudioStreamWAV (16-bit mono, 22050 Hz - half the memory of 44.1 kHz,
## and every effect here is dark/low anyway).
##
## Total budget: ~5 s of one-shots plus wind/fire/music loops, under 1 MB of
## PCM and well under a second of synthesis. Loops are seamless: drone
## frequencies are chosen so 16 s holds an integer number of cycles, and noise
## loops are crossfaded by _make_loop().

const RATE: int = 22050


## Builds every stream once. Keys:
##   one-shots: swing hit clang parry pickup gold potion step_a step_b
##              growl death chest levelup hurt equip
##   loops:     wind fire music
static func build_all() -> Dictionary:
	var out := {}
	out["swing"] = _stream(_swing(), false)
	out["hit"] = _stream(_hit(), false)
	out["clang"] = _stream(_clang(0.38), false)
	out["parry"] = _stream(_clang(0.62), false)
	out["pickup"] = _stream(_pickup(), false)
	out["gold"] = _stream(_gold(), false)
	out["potion"] = _stream(_potion(), false)
	out["step_a"] = _stream(_step(6), false)
	out["step_b"] = _stream(_step(9), false)
	out["growl"] = _stream(_growl(), false)
	out["death"] = _stream(_death(), false)
	out["chest"] = _stream(_chest(), false)
	out["levelup"] = _stream(_levelup(), false)
	out["hurt"] = _stream(_hurt(), false)
	out["equip"] = _stream(_equip(), false)
	out["wind"] = _stream(_make_loop(_wind(), 3000), true)
	out["fire"] = _stream(_make_loop(_fire(), 3000), true)
	out["music"] = _stream(_music(), true)
	return out


# --- packing -----------------------------------------------------------------

static func _stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## Removes the seam from a noise loop by crossfading its tail onto its head.
static func _make_loop(samples: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := samples.size()
	var body := n - fade
	var out := PackedFloat32Array()
	out.resize(body)
	for i in body:
		out[i] = samples[i]
	for i in fade:
		var k := float(i) / float(fade)
		out[i] = samples[i] * k + samples[body + i] * (1.0 - k)
	return out


# --- primitives --------------------------------------------------------------

static func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for i in samples.size():
		m = maxf(m, absf(samples[i]))
	var k := peak / m
	for i in samples.size():
		samples[i] *= k
	return samples


## Sliding-box lowpass. Small windows pass almost everything, 10+ muffles.
static func _lp(samples: PackedFloat32Array, window: int) -> PackedFloat32Array:
	var n := samples.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	for i in n:
		acc += samples[i]
		if i >= window:
			acc -= samples[i - window]
		out[i] = acc / float(mini(i + 1, window))
	return out


# --- one-shots ---------------------------------------------------------------

## Blade whoosh: one-pole lowpass with a sweeping cutoff over shaped noise.
static func _swing() -> PackedFloat32Array:
	var dur := 0.24
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var r := _rng(11)
	var state := 0.0
	for i in n:
		var t := float(i) / float(n)
		var win := 2.0 + 16.0 * sin(PI * t)
		var a := clampf(1.0 - win / 20.0, 0.12, 0.9)
		state = state * (1.0 - a) + r.randf_range(-1.0, 1.0) * a
		var env := sin(PI * t)
		out[i] = state * env * env
	return _normalize(out, 0.5)


static func _hit() -> PackedFloat32Array:
	var dur := 0.17
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var r := _rng(22)
	for i in n:
		var t := float(i) / RATE
		var thump := sin(TAU * 96.0 * t) * exp(-t * 26.0)
		var crack := r.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.7
		out[i] = clampf(thump * 0.9 + crack, -1.0, 1.0)
	return _normalize(out, 0.62)


## Metallic ring: a stack of inharmonic partials with a fast attack noise.
## ring_dur 0.38 = block, 0.62 = parry (longer, brighter ring).
static func _clang(ring_dur: float) -> PackedFloat32Array:
	var dur := ring_dur + 0.05
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var r := _rng(33)
	var partials := [1170.0, 1785.0, 2360.0, 862.0]
	var amps := [1.0, 0.72, 0.5, 0.85]
	var decays := [16.0, 21.0, 27.0, 12.0]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p in partials.size():
			s += amps[p] * sin(TAU * partials[p] * t + float(p) * 1.7) * exp(-t * decays[p])
		var attack := r.randf_range(-1.0, 1.0) * exp(-t * 140.0) * 0.9
		out[i] = clampf(s * 0.32 + attack, -1.0, 1.0)
	return _normalize(out, 0.55)


static func _pickup() -> PackedFloat32Array:
	var out := _silence(0.22)
	var notes := [[660.0, 0.0], [880.0, 0.09]]
	for note in notes:
		var f: float = note[0]
		var t0: float = note[1]
		for i in int(0.12 * RATE):
			var t := float(i) / RATE
			var env := sin(PI * clampf(t / 0.11, 0.0, 1.0))
			var idx := int((t0 + t) * RATE)
			if idx < out.size():
				out[idx] += (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t)) * env * 0.5
	return _normalize(out, 0.42)


static func _gold() -> PackedFloat32Array:
	var out := _silence(0.16)
	var pings := [[1568.0, 0.0], [2093.0, 0.05]]
	for ping in pings:
		var f: float = ping[0]
		var t0: float = ping[1]
		for i in int(0.09 * RATE):
			var t := float(i) / RATE
			var idx := int((t0 + t) * RATE)
			if idx < out.size():
				out[idx] += sin(TAU * f * t) * exp(-t * 38.0) * 0.6
	return _normalize(out, 0.38)


static func _potion() -> PackedFloat32Array:
	var out := _silence(0.34)
	# A descending gulp plus two rising bubbles.
	for i in out.size():
		var t := float(i) / RATE
		var f := lerpf(310.0, 130.0, clampf(t / 0.22, 0.0, 1.0))
		var env := exp(-maxf(t - 0.2, 0.0) * 14.0) * clampf(t * 60.0, 0.0, 1.0)
		out[i] = sin(TAU * f * t) * env * 0.8
	for b in 2:
		var t0 := 0.18 + 0.07 * float(b)
		var f2 := 520.0 + 180.0 * float(b)
		for i in int(0.05 * RATE):
			var t := float(i) / RATE
			var idx := int((t0 + t) * RATE)
			if idx < out.size():
				out[idx] += sin(TAU * f2 * t) * sin(PI * t / 0.05) * 0.22
	return _normalize(out, 0.45)


## Footstep: muffled noise burst. window tunes the tone (a/b variants).
static func _step(window: int) -> PackedFloat32Array:
	var dur := 0.085
	var n := int(dur * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var r := _rng(55 + window)
	for i in n:
		raw[i] = r.randf_range(-1.0, 1.0)
	var filtered := _lp(raw, window)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 42.0) * clampf(t * 200.0, 0.0, 1.0)
		out[i] = filtered[i] * env * 2.4
	return _normalize(out, 0.3)


## Draugr aggro: a dark harmonically-stacked growl with an 8 Hz wobble.
static func _growl() -> PackedFloat32Array:
	var dur := 0.72
	var n := int(dur * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for h in 5:
			s += sin(TAU * 68.0 * float(h + 1) * t + float(h) * 0.9) / float(h + 1)
		var wobble := 0.7 + 0.3 * sin(TAU * 8.0 * t)
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))
		raw[i] = s * 0.4 * wobble * env
	var out := _lp(raw, 8)
	return _normalize(out, 0.5)


static func _death() -> PackedFloat32Array:
	var dur := 0.62
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var r := _rng(66)
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(205.0, 82.0, clampf(t / dur, 0.0, 1.0))
		var env := exp(-t * 4.5) * clampf(t * 80.0, 0.0, 1.0)
		var tail := r.randf_range(-1.0, 1.0) * exp(-maxf(t - 0.35, 0.0) * 12.0) * 0.2
		out[i] = (sin(TAU * f * t) * 0.8 + tail) * env
	return _normalize(out, 0.5)


static func _chest() -> PackedFloat32Array:
	var dur := 0.5
	var n := int(dur * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var r := _rng(77)
	for i in n:
		raw[i] = r.randf_range(-1.0, 1.0)
	var creak := _lp(raw, 12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var swell := sin(PI * clampf(t / 0.32, 0.0, 1.0)) * clampf(t * 30.0, 0.0, 1.0)
		out[i] = creak[i] * swell * 1.6
		# Closing chime.
		if t > 0.34:
			var tc := t - 0.34
			out[i] += sin(TAU * 988.0 * tc) * exp(-tc * 16.0) * 0.3
	return _normalize(out, 0.42)


static func _levelup() -> PackedFloat32Array:
	var out := _silence(0.55)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		var f: float = notes[i]
		var t0 := 0.1 * float(i)
		for j in int(0.24 * RATE):
			var t := float(j) / RATE
			var env := sin(PI * clampf(t / 0.23, 0.0, 1.0))
			var idx := int((t0 + t) * RATE)
			if idx < out.size():
				out[idx] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * 0.4
	return _normalize(out, 0.46)


static func _hurt() -> PackedFloat32Array:
	var dur := 0.22
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var r := _rng(88)
	for i in n:
		var t := float(i) / RATE
		var sq := tanh(3.0 * sin(TAU * 152.0 * t))
		var env := exp(-t * 16.0)
		out[i] = (sq * 0.7 + r.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.4) * env
	return _normalize(out, 0.42)


## Short steel slide - equip flourish.
static func _equip() -> PackedFloat32Array:
	var dur := 0.16
	var n := int(dur * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var r := _rng(99)
	for i in n:
		raw[i] = r.randf_range(-1.0, 1.0)
	var hiss := _lp(raw, 5)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))
		var ring := sin(TAU * 2400.0 * t) * exp(-t * 30.0) * 0.12
		out[i] = hiss[i] * env * 1.2 + ring * env
	return _normalize(out, 0.3)


# --- ambient loops -----------------------------------------------------------

static func _wind() -> PackedFloat32Array:
	var dur := 7.0
	var n := int(dur * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var r := _rng(111)
	for i in n:
		raw[i] = r.randf_range(-1.0, 1.0)
	var soft := _lp(_lp(raw, 14), 10)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var lfo := 0.55 + 0.30 * sin(TAU * t / 6.1) + 0.15 * sin(TAU * t / 2.7 + 1.3)
		out[i] = soft[i] * lfo * 1.5
	return _normalize(out, 0.34)


static func _fire() -> PackedFloat32Array:
	var dur := 5.0
	var out := _silence(dur)
	var r := _rng(122)
	# Sparse crackles: short decaying noise pops.
	for p in 34:
		var t0 := r.randf_range(0.0, dur - 0.05)
		var f_pop := r.randf_range(1400.0, 4200.0)
		var amp := r.randf_range(0.25, 0.85)
		var dec := r.randf_range(60.0, 160.0)
		for i in int(0.045 * RATE):
			var t := float(i) / RATE
			var idx := int((t0 + t) * RATE)
			if idx < out.size():
				out[idx] += sin(TAU * f_pop * t) * exp(-t * dec) * amp * 0.5
	# Low ember rumble underneath.
	var raw := PackedFloat32Array()
	raw.resize(out.size())
	for i in raw.size():
		raw[i] = r.randf_range(-1.0, 1.0)
	var rumble := _lp(raw, 24)
	for i in out.size():
		out[i] += rumble[i] * 0.35
	return _normalize(out, 0.4)


## 16 s dark-ambient loop. Every drone/melody frequency completes an integer
## number of cycles in 16 s, so the seam is perfectly continuous.
static func _music() -> PackedFloat32Array:
	var dur := 16.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# Drone: A minor. 110/165/262/247 Hz * 16 s are all integer cycles.
	var drones := [[110.0, 0.16], [165.0, 0.10], [262.0, 0.07], [247.0, 0.035]]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for d in drones.size():
			var swell := 0.6 + 0.4 * sin(TAU * t / dur + float(d) * 1.9)
			s += sin(TAU * drones[d][0] * t + float(d) * 2.1) * drones[d][1] * swell
		out[i] = s
	# Sparse pentatonic melody with a soft vibrato.
	var melody := [[220.0, 1.3], [262.0, 4.6], [330.0, 7.9], [392.0, 10.4], [262.0, 13.4]]
	for note in melody:
		var f: float = note[0]
		var t0: float = note[1]
		for j in int(2.2 * RATE):
			var t := float(j) / RATE
			var idx := int((t0 + t) * RATE)
			if idx >= out.size():
				break
			var vib := 1.0 + 0.004 * sin(TAU * 4.6 * t)
			var env := sin(PI * clampf(t / 2.2, 0.0, 1.0))
			env *= env
			out[idx] += sin(TAU * f * vib * t) * env * 0.085
	return _normalize(out, 0.4)
