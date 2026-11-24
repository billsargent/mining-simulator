extends Node
## Sound: every sound in the game is synthesized here at start-up (no audio files), on a worker
## thread so loading doesn't wait for it. Anything can call the static helpers:
##   Sfx.play("dig", position)        one-shot, in 3D when a position is given
##   Sfx.loop_on(node, "motor")       a looping 3D sound riding on a node (returns the player)
## This node also runs the ambience (creek, wind, birds, crickets, rain) and now and then plays a
## few bars of guitar.

const RATE := 22050
const MUSIC_BUS := "Music"
const AMB_BUS := "Ambience"

static var _i = null                # the running instance

var main
var _sounds := {}                   # name -> AudioStreamWAV
var _ready_sounds := false
var _task := -1
var _built := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3: Array[AudioStreamPlayer3D] = []
var _amb := {}                      # name -> AudioStreamPlayer (looping ambience)
var _bird_t := 6.0
var _music_t := 40.0
var _music: AudioStreamPlayer
var _pan_loop: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


static func play(sound: String, pos = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _i != null:
		_i._play(sound, pos, volume_db, pitch)


## A looping 3D sound that follows a node. Starts silent and stopped: set .playing and volume.
static func loop_on(owner: Node3D, sound: String, unit_size: float = 8.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = unit_size
	p.max_distance = unit_size * 12.0
	p.bus = "Master"
	owner.add_child(p)
	p.set_meta("sound", sound)
	if _i != null and _i._ready_sounds:
		p.stream = _i._sounds.get(sound)
	return p


## Start or stop a loop made by loop_on (the stream arrives once sounds are built).
static func run_loop(p: AudioStreamPlayer3D, on: bool, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if p == null:
		return
	if p.stream == null:
		if _i == null or not _i._ready_sounds:
			return
		p.stream = _i._sounds.get(p.get_meta("sound"))
	p.volume_db = volume_db
	p.pitch_scale = pitch
	if on != p.playing:
		p.playing = on


func _ready() -> void:
	_i = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	for bus in [MUSIC_BUS, AMB_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_task = WorkerThreadPool.add_task(_synth_all)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	if _i == self:
		_i = null


func _process(delta: float) -> void:
	if not _ready_sounds:
		if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_sounds = _built
			_ready_sounds = true
			_start_ambience()
		return
	if main == null or main.player == null:
		return
	_ambience(delta)


# --- Playing ------------------------------------------------------------------------------------

func _play(sound: String, pos, volume_db: float, pitch: float) -> void:
	if not _ready_sounds or not _sounds.has(sound):
		return
	var jitter := _rng.randf_range(0.94, 1.06) * pitch
	if pos is Vector3:
		var p := _free3()
		p.global_position = pos
		p.stream = _sounds[sound]
		p.volume_db = volume_db
		p.pitch_scale = jitter
		p.play()
	else:
		var p := _free2()
		p.stream = _sounds[sound]
		p.volume_db = volume_db
		p.pitch_scale = jitter
		p.play()


func _free2() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	var p := AudioStreamPlayer.new()
	add_child(p)
	_pool.append(p)
	return p


func _free3() -> AudioStreamPlayer3D:
	for p in _pool3:
		if not p.playing:
			return p
	var p := AudioStreamPlayer3D.new()
	p.unit_size = 6.0
	p.max_distance = 90.0
	p.top_level = true
	add_child(p)
	_pool3.append(p)
	return p


# --- Ambience and music ---------------------------------------------------------------------------

func _start_ambience() -> void:
	for n in ["creek", "wind", "crickets", "rain", "drip"]:
		var p := AudioStreamPlayer.new()
		p.stream = _sounds[n]
		p.bus = AMB_BUS
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_amb[n] = p
	_pan_loop = AudioStreamPlayer.new()
	_pan_loop.stream = _sounds["swish"]
	_pan_loop.volume_db = -80.0
	add_child(_pan_loop)
	_pan_loop.play()
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	_music.volume_db = -9.0
	add_child(_music)


func _ambience(delta: float) -> void:
	var pl = main.player
	var f: Vector3 = main.focus_position()
	var dn = main.day_night
	var under: bool = pl.mine != null
	var hour: float = dn.hours
	var night := hour < 5.5 or hour > 20.5
	var storm: float = dn.storm
	var creek := 0.0
	if not under:
		var edge: float = main.world.coarse_river_edge(f.x, f.z)
		creek = clampf(1.0 - edge / 70.0, 0.0, 1.0)
		if main.terrain.water_depth(f.x, f.z) > 0.0:
			creek = maxf(creek, 0.9)
	_fade("creek", creek * creek, -6.0, delta)
	_fade("wind", 0.0 if under else 0.35 + 0.65 * storm + clampf((f.y - 120.0) / 300.0, 0.0, 0.5), -14.0, delta)
	_fade("crickets", 1.0 if night and not under and storm < 0.3 else 0.0, -16.0, delta)
	_fade("rain", 0.0 if under else storm, -6.0, delta)
	_fade("drip", 1.0 if under else 0.0, -12.0, delta)
	# The pan: water swishing while you shake or wash it.
	var pan = pl.pan_view
	var pan_level := 0.0
	if pan != null and is_instance_valid(pan) and not pan.sim.done:
		pan_level = 1.0 if pan.washing else (0.6 if pan.shaking else 0.15)
	_pan_loop.volume_db = move_toward(_pan_loop.volume_db, linear_to_db(maxf(pan_level, 0.0001)) - 4.0, delta * 80.0)
	# Birds by day, now and then.
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(4.0, 14.0)
		if not under and not night and storm < 0.5 and hour > 5.0 and hour < 20.0:
			var a := _rng.randf() * TAU
			var at: Vector3 = pl.global_position + Vector3(cos(a) * 25.0, 8.0, sin(a) * 25.0)
			_play("bird%d" % _rng.randi_range(0, 2), at, -8.0, _rng.randf_range(0.9, 1.15))
	# A few bars of guitar every few minutes.
	_music_t -= delta
	if _music_t <= 0.0 and not _music.playing:
		_music.stream = _sounds["tune%d" % _rng.randi_range(0, 2)]
		_music.play()
		_music_t = _rng.randf_range(150.0, 300.0)


func _fade(n: String, level: float, top_db: float, delta: float) -> void:
	var p: AudioStreamPlayer = _amb[n]
	var want := linear_to_db(maxf(level, 0.0001)) + top_db
	p.volume_db = move_toward(p.volume_db, want, delta * 20.0)


# --- Synthesis ----------------------------------------------------------------------------------
# All of this runs on a worker thread: it only fills _built.

func _synth_all() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	_built["dig"] = _wav(_dig(r))
	_built["pour"] = _wav(_pour(r, 0.55))
	_built["dump"] = _wav(_pour(r, 0.9))
	_built["chip"] = _wav(_chip(r))
	_built["splash"] = _wav(_splash(r))
	_built["clink"] = _wav(_bell([1800.0, 2730.0, 4100.0], 0.35, 0.25))
	_built["sell"] = _wav(_concat([_bell([1320.0, 2640.0], 0.25, 0.5), _bell([1760.0, 3520.0], 0.6, 0.5)]))
	_built["goal"] = _wav(_concat([_pluck(r, 392.0, 0.18), _pluck(r, 587.3, 0.7)]))
	# Nugget: a rising, ringing three-note chime over a soft shimmer.
	_built["nugget"] = _wav(_concat([_bell([1568.0, 3136.0, 4700.0], 0.14, 0.35), _bell([1976.0, 3952.0], 0.14, 0.35), _bell([2637.0, 5274.0, 7900.0], 1.1, 0.45)]))
	_built["thud"] = _wav(_thud(r))
	_built["creak"] = _wav(_creak(r))
	_built["roar"] = _wav(_roar(r))
	_built["click"] = _wav(_bell([2400.0], 0.06, 0.4))
	_built["creek"] = _wav(_loop_noise(r, 4.0, 0.08, 0.35, 0.6), true)
	_built["wind"] = _wav(_loop_noise(r, 6.0, 0.015, 0.5, 0.25), true)
	_built["rain"] = _wav(_loop_noise(r, 3.0, 0.5, 0.0, 0.35), true)
	_built["swish"] = _wav(_loop_noise(r, 2.0, 0.12, 0.8, 1.2), true)
	_built["crickets"] = _wav(_crickets(r), true)
	_built["drip"] = _wav(_drips(r), true)
	_built["engine"] = _wav(_engine(r, 45.0, 0.5), true)
	_built["motor"] = _wav(_engine(r, 30.0, 0.9), true)
	_built["water"] = _wav(_loop_noise(r, 3.0, 0.2, 0.25, 0.5), true)
	for k in 3:
		_built["bird%d" % k] = _wav(_bird(r))
	for k in 3:
		_built["tune%d" % k] = _wav(_tune(r, k))


func _wav(data: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


## Noise through a one-pole low-pass; `cut` 0..1 is the filter coefficient (small = darker).
## `wobble` slowly swells it, `gain` sets the level. Cross-faded so the loop has no seam.
func _loop_noise(r: RandomNumberGenerator, seconds: float, cut: float, wobble: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var fade := int(0.3 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var y := 0.0
	var y2 := 0.0
	for i in raw.size():
		var x := r.randf_range(-1.0, 1.0)
		y += cut * (x - y)
		y2 += 0.5 * (y - y2)
		var t := float(i) / RATE
		var swell := 1.0 - wobble * 0.5 * (1.0 + sin(TAU * t * 0.37 + sin(TAU * t * 0.11) * 2.0))
		raw[i] = (y - y2 * 0.3) * swell
	# Normalize.
	var peak := 0.0001
	for v in raw:
		peak = maxf(peak, absf(v))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := raw[i]
		if i < fade:
			var k := float(i) / fade
			v = v * k + raw[n + i] * (1.0 - k)
		out[i] = v / peak * gain
	return out


func _dig(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.32 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 14.0) * minf(1.0, t * 300.0)
		y += 0.25 * (r.randf_range(-1.0, 1.0) - y)
		var grit := (r.randf_range(-1.0, 1.0) if r.randf() < 0.08 else 0.0) * exp(-t * 8.0)
		out[i] = (y * 1.6 + grit * 0.5 + sin(TAU * 70.0 * t) * 0.4 * exp(-t * 25.0)) * env * 0.8
	return out


## Gravel tumbling: a run of small random clicks.
func _pour(r: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 20.0) * clampf((seconds - t) / (seconds * 0.6), 0.0, 1.0)
		var click := r.randf_range(-1.0, 1.0) if r.randf() < 0.05 else 0.0
		y += 0.35 * (click - y)
		out[i] = (y * 2.2 + r.randf_range(-0.05, 0.05)) * env * 0.7
	return out


func _chip(r: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _bell([2150.0, 3380.0, 5200.0], 0.22, 0.45)
	for i in mini(a.size(), 800):
		a[i] += r.randf_range(-1.0, 1.0) * exp(-float(i) / 120.0) * 0.6
	var b := _dig(r)
	for i in mini(a.size(), b.size()):
		a[i] += b[i] * 0.35
	return a


func _bell(freqs: Array, seconds: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * exp(-t * (6.0 + k * 5.0) / seconds * 0.6) / (k + 1)
		out[i] = v * gain * minf(1.0, t * 2000.0)
	return out


func _splash(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += 0.4 * (r.randf_range(-1.0, 1.0) - y)
		var bubble := sin(TAU * (600.0 + 900.0 * t) * t) * 0.15 * exp(-t * 9.0)
		out[i] = (y * exp(-t * 7.0) * minf(1.0, t * 60.0) + bubble) * 0.9
	return out


func _thud(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.35 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * (90.0 - 40.0 * t) * t) * 0.9 + r.randf_range(-1.0, 1.0) * 0.3 * exp(-t * 40.0)) * exp(-t * 12.0)
	return out


func _creak(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (210.0 + 60.0 * sin(t * 9.0) + r.randf_range(-20.0, 20.0)) / RATE
		var env := sin(PI * t / 0.7)
		out[i] = (fmod(ph, TAU) / TAU - 0.5) * env * 0.35
	return out


func _roar(r: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _loop_noise(r, 2.5, 0.05, 0.3, 0.8)
	for i in a.size():
		var t := float(i) / RATE
		a[i] *= minf(1.0, t * 3.0) * minf(1.0, (2.5 - t) * 2.0)
	return a


## An engine: a buzzy fundamental (whole cycles per second, so it loops) with firing pulses.
func _engine(r: RandomNumberGenerator, f0: float, rough: float) -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(f0 * t, 1.0)
		var pulse := exp(-ph * 9.0)
		y += 0.2 * (r.randf_range(-1.0, 1.0) - y)
		var v := (ph - 0.5) * 0.5 + pulse * 0.6 + sin(TAU * f0 * 2.0 * t) * 0.2 + y * rough * 0.5
		out[i] = v * 0.55
	return out


func _crickets(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := 4 * RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for c in 3:
		var f := r.randf_range(4200.0, 5200.0)
		var rate := r.randf_range(2.0, 3.0)        # chirp groups per second; whole cycles over 4 s
		rate = roundf(rate * 4.0) / 4.0
		var off := r.randf()
		for i in n:
			var t := float(i) / RATE
			var g := fmod(t * rate + off, 1.0)
			var on := 1.0 if g < 0.3 and fmod(g * 40.0, 1.0) < 0.5 else 0.0
			out[i] += sin(TAU * f * t) * on * 0.12
	return out


func _drips(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := 5 * RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for d in 6:
		var at := r.randi_range(0, n - 4000)
		var f := r.randf_range(900.0, 1600.0)
		for i in 3500:
			var t := float(i) / RATE
			out[at + i] += sin(TAU * (f + 1500.0 * t) * t) * exp(-t * 30.0) * 0.35
	return out


func _bird(r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var notes := r.randi_range(2, 5)
	var base := r.randf_range(2600.0, 3800.0)
	for k in notes:
		var dur := r.randf_range(0.06, 0.16)
		var sweep := r.randf_range(-1500.0, 1800.0)
		var n := int(dur * RATE)
		var ph := 0.0
		for i in n:
			var t := float(i) / RATE
			ph += TAU * (base + sweep * t / dur) / RATE
			out.append(sin(ph) * sin(PI * t / dur) * 0.3)
		for i in int(r.randf_range(0.03, 0.12) * RATE):
			out.append(0.0)
	return out


## Karplus-Strong plucked string.
func _pluck(r: RandomNumberGenerator, freq: float, seconds: float) -> PackedFloat32Array:
	var period := maxi(2, int(RATE / freq))
	var buf := PackedFloat32Array()
	buf.resize(period)
	for i in period:
		buf[i] = r.randf_range(-1.0, 1.0)
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var idx := 0
	for i in n:
		var nxt := (idx + 1) % period
		var v := 0.4985 * (buf[idx] + buf[nxt])
		out[i] = buf[idx] * 0.4
		buf[idx] = v
		idx = nxt
	return out


## A slow fingerpicked phrase in G, on the plucked string.
func _tune(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var scale := [196.0, 220.0, 246.9, 293.7, 329.6, 392.0, 440.0, 493.9, 587.3]
	var bass := [[98.0, 146.8], [110.0, 164.8], [130.8, 196.0], [146.8, 220.0]]
	var prog: Array = [[0, 2, 3, 0], [0, 1, 2, 3], [2, 0, 3, 0]][k]
	var beat := 0.55
	var total := int(beat * 4 * prog.size() * RATE + 3.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var deg := 4
	for bar in prog.size():
		var chord: Array = bass[prog[bar]]
		for b in 4:
			var at := int((bar * 4 + b) * beat * RATE)
			if b == 0 or b == 2:
				_mix(out, _pluck(r, chord[0 if b == 0 else 1], 2.4), at, 0.8)
			if r.randf() < 0.85:
				deg = clampi(deg + r.randi_range(-2, 2), 0, scale.size() - 1)
				var swing := int((0.0 if b % 2 == 0 else 0.06) * RATE)
				_mix(out, _pluck(r, scale[deg], 1.8), at + swing, 0.7)
				if r.randf() < 0.3:
					var deg2 := clampi(deg + r.randi_range(-1, 1), 0, scale.size() - 1)
					_mix(out, _pluck(r, scale[deg2], 1.2), at + int(beat * 0.5 * RATE), 0.5)
	_mix(out, _pluck(r, 98.0, 3.0), int(beat * 4 * prog.size() * RATE), 0.8)
	_mix(out, _pluck(r, 293.7, 3.0), int(beat * 4 * prog.size() * RATE), 0.5)
	return out


func _mix(out: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
	for i in src.size():
		if at + i >= out.size():
			return
		out[at + i] += src[i] * gain
