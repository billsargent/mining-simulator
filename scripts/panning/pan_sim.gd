extends RefCounted
## Panning, modeled simply. Every grain has a height in the bed (0 = pan bottom, 1 = top).
## Shaking sorts the bed by density, so gold sinks. Tilting the pan washes the top layer
## over the far lip. Wash before you shake and gold rides out with the sand.
## No visuals in here, so it can be balance-tested headless (see tests/test_pan.gd).

signal gold_washed_out(mass: float)
signal finished

enum { GRAVEL, SAND, BLACK_SAND, GOLD }

const SETTLE_TO = [0.88, 0.62, 0.2, 0.03]       # where each kind ends up after shaking
const SETTLE_SPREAD = [0.09, 0.14, 0.07, 0.025]
const MOBILITY = [1.0, 0.85, 0.08, 0.01]        # how easily moving water carries it off
const GRAVEL_COUNT := 110
const SAND_COUNT := 330
const SHAKE_RATE := 2.4
const WASH_RATE := 3.2
const STIR_RATE := 0.3       # washing slowly re-mixes the bed, so shake again now and then
const WASH_START := 10.0     # degrees of tilt where the water starts carrying material off
const SAFE_TILT := 26.0      # steeper than this and heavy material starts going too
const MAX_TILT := 40.0
const FRONT := -PI / 2.0     # direction of the far lip, where material spills out
const DONE_FRACTION := 0.04
const OUT_TIME := 0.7

var kind := PackedByteArray()
var mass := PackedFloat32Array()
var r := PackedFloat32Array()          # 0..1 distance from the pan's center
var th := PackedFloat32Array()         # angle around the pan
var h := PackedFloat32Array()          # height in the bed
var settle := PackedFloat32Array()     # height this grain sorts to when shaken
var state := PackedByteArray()         # 0 in the pan, 1 washing out, 2 gone
var out_t := PackedFloat32Array()      # 0..1 progress of washing out (for visuals)
var gold_lost := PackedFloat32Array()
var light_start := 0
var light_left := 0
var done := false
var _rng := RandomNumberGenerator.new()


func setup(dirt, rng_seed: int = 0) -> void:
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	var n_gravel := roundi(GRAVEL_COUNT * float(dirt.gravel))
	var n_sand := roundi(SAND_COUNT * float(dirt.sand))
	_add(GRAVEL, 0.0, n_gravel)
	_add(SAND, 0.0, n_sand)
	_add(BLACK_SAND, 0.0, 30 + int(300.0 * dirt.black_sand))
	for m in dirt.gold:
		_add(GOLD, m, 1)
	light_start = n_gravel + n_sand
	light_left = light_start


func _add(k: int, m: float, n: int) -> void:
	var to: float = SETTLE_TO[k]
	var spread: float = SETTLE_SPREAD[k]
	var reach := 0.8 if k == GOLD else 1.0     # gold stays on the flat bottom, not the slope
	for i in n:
		kind.append(k)
		mass.append(m)
		r.append(sqrt(_rng.randf()) * reach)
		th.append(_rng.randf() * TAU)
		h.append(_rng.randf())
		settle.append(clampf(to + _rng.randfn(0.0, spread), 0.0, 1.0))
		state.append(0)
		out_t.append(0.0)


func count() -> int:
	return kind.size()


## Share of the light material (gravel and sand) still in the pan.
func material_left() -> float:
	return float(light_left) / float(maxi(light_start, 1))


func step(dt: float, shaking: bool, tilt: float, swirl: float) -> void:
	_advance_outgoing(dt)
	if done:
		return
	if shaking:
		_shake(dt)
	if tilt > WASH_START:
		_wash(dt, tilt)
	if swirl != 0.0:
		_swirl(swirl)
	if light_left <= ceili(light_start * DONE_FRACTION):
		done = true
		finished.emit()


func gold_kept() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in kind.size():
		if kind[i] == GOLD and state[i] == 0:
			out.append(mass[i])
	return out


func black_sand_left() -> int:
	var n := 0
	for i in kind.size():
		if kind[i] == BLACK_SAND and state[i] == 0:
			n += 1
	return n


## Once the pan is clean, spread the gold into a visible tail across the bottom.
func arrange_gold_tail(center_angle: float) -> void:
	for i in kind.size():
		if kind[i] == GOLD and state[i] == 0:
			th[i] = center_angle + _rng.randfn(0.0, 0.35)
			r[i] = _rng.randf_range(0.55, 0.95)


func _shake(dt: float) -> void:
	var k := 1.0 - exp(-SHAKE_RATE * dt)
	var jitter := 0.05 * sqrt(dt)
	var spin := 0.25 * sqrt(dt)
	for i in kind.size():
		if state[i] != 0:
			continue
		h[i] = clampf(h[i] + (settle[i] - h[i]) * k + _rng.randfn(0.0, jitter), 0.0, 1.0)
		th[i] += _rng.randfn(0.0, spin)


func _wash(dt: float, tilt: float) -> void:
	# Steeper washes faster, but past SAFE_TILT the whole bed starts sliding, gold included.
	var steep := smoothstep(SAFE_TILT, MAX_TILT, tilt)
	var flow := smoothstep(WASH_START, WASH_START + 8.0, tilt) * (1.0 + 0.8 * steep)
	var lo := 1.0
	var hi := 0.0
	for i in kind.size():
		if state[i] == 0:
			lo = minf(lo, h[i])
			hi = maxf(hi, h[i])
	var span := maxf(hi - lo, 0.05)
	var stir := 1.0 - exp(-STIR_RATE * flow * dt)
	for i in kind.size():
		if state[i] != 0:
			continue
		var k: int = kind[i]
		var front := 0.25 + 0.75 * (0.5 + 0.5 * cos(th[i] - FRONT))
		var top := smoothstep(0.5, 1.0, (h[i] - lo) / span)
		var mob: float = MOBILITY[k]
		if k == GOLD:
			# Gold that hasn't settled to the bottom rides out with the sand.
			mob *= 1.0 + 14.0 * clampf(h[i] - 0.12, 0.0, 1.0)
		var p := WASH_RATE * dt * flow * top * front * mob
		if k == GOLD:
			p += WASH_RATE * dt * steep * front * 0.035
		elif k == BLACK_SAND:
			p += WASH_RATE * dt * steep * front * 0.15
		if _rng.randf() < p:
			_wash_out(i)
			continue
		h[i] += (0.5 - h[i]) * stir


func _wash_out(i: int) -> void:
	state[i] = 1
	out_t[i] = 0.0
	if kind[i] == GOLD:
		gold_lost.append(mass[i])
		gold_washed_out.emit(mass[i])
	elif kind[i] == GRAVEL or kind[i] == SAND:
		light_left -= 1


func _swirl(amount: float) -> void:
	for i in kind.size():
		if state[i] == 0:
			th[i] += amount * (0.4 + 0.6 * h[i])


func _advance_outgoing(dt: float) -> void:
	for i in kind.size():
		if state[i] == 1:
			out_t[i] += dt / OUT_TIME
			if out_t[i] >= 1.0:
				state[i] = 2
