extends Node3D
## A few animals streamed around the player, built from boxes in code. No physics: they stand on
## terrain height. Deer graze at forest edges at dawn and dusk and bound off when you come close;
## hawks and ravens circle by day; now and then a bear ambles through the woods at a distance and
## wanders off. Harmless, just there. Nothing spawns while underground.

const Sfx = preload("res://scripts/core/sfx.gd")

const MAX_DEER := 4
const MAX_BIRDS := 2
const DESPAWN := 280.0          # metres from the player
const DEER_SPOOK := 30.0        # bound away when the player is this close
const DEER_RUN := 10.0          # m/s
const BEAR_CHANCE := 0.004      # per second, when in a forest by day
const BEAR_LIFE := 120.0

var terrain
var world
var day_night
var player: Node3D

var animals: Array = []         # {kind, node, vel(Vector2), t, state, center, ...}
var _tick := 0.0
var _rng := RandomNumberGenerator.new()
var _mats := {}


func setup(t, w, dn, p: Node3D) -> void:
	terrain = t
	world = w
	day_night = dn
	player = p
	_rng.randomize()


func _process(delta: float) -> void:
	if player == null:
		return
	if day_night.underground:
		clear()
		return
	var pp := player.global_position
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_stream(pp)
	for a in animals.duplicate():
		_update(a, delta, pp)


func clear() -> void:
	for a in animals:
		a["node"].queue_free()
	animals.clear()


func count(kind: String) -> int:
	var n := 0
	for a in animals:
		if a["kind"] == kind:
			n += 1
	return n


## Deer come out around dawn and dusk.
func deer_hours() -> bool:
	var h: float = day_night.hours
	return (h > 5.0 and h < 8.5) or (h > 17.0 and h < 20.5)


func _stream(pp: Vector3) -> void:
	for a in animals.duplicate():
		var n: Node3D = a["node"]
		var far := Vector2(n.position.x - pp.x, n.position.z - pp.z).length() > DESPAWN
		if far or (a["kind"] == "bear" and a["t"] > BEAR_LIFE) or (a["kind"] == "bird" and day_night.is_dark()):
			_remove(a)
	if deer_hours() and count("deer") == 0 and _rng.randf() < 0.15:
		var spot = _find_spot(pp, 70.0, 160.0, 0.3, 0.65)
		if spot != null:
			for i in _rng.randi_range(1, 3):
				if count("deer") < MAX_DEER:
					spawn("deer", spot + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)))
	var day: bool = day_night.sun_elevation() > 6.0 and day_night.storm < 0.5
	if day and count("bird") < MAX_BIRDS and _rng.randf() < 0.05:
		var ang := _rng.randf() * TAU
		spawn("bird", Vector2(pp.x, pp.z) + Vector2(cos(ang), sin(ang)) * _rng.randf_range(30.0, 120.0))
	if day and count("bear") == 0 and _rng.randf() < BEAR_CHANCE and world.forest(pp.x, pp.z) > 0.45:
		var spot = _find_spot(pp, 90.0, 150.0, 0.5, 1.0)
		if spot != null:
			spawn("bear", spot)


## A dry spot at a distance whose forest amount is in [lo, hi], or null.
func _find_spot(pp: Vector3, near: float, far: float, lo: float, hi: float):
	for i in 10:
		var ang := _rng.randf() * TAU
		var p := Vector2(pp.x, pp.z) + Vector2(cos(ang), sin(ang)) * _rng.randf_range(near, far)
		var f: float = world.forest(p.x, p.y)
		if f >= lo and f <= hi and terrain.water_depth(p.x, p.y) < -0.5 and not world.in_pad(p.x, p.y, 2.0):
			return p
	return null


func spawn(kind: String, p: Vector2) -> Dictionary:
	var n := Node3D.new()
	match kind:
		"deer": _build_deer(n)
		"bear": _build_bear(n)
		_: _build_bird(n, _rng.randf() < 0.5)
	add_child(n)
	var a := {"kind": kind, "node": n, "t": 0.0, "state": "graze", "vel": Vector2.ZERO,
			"center": p, "phase": _rng.randf() * TAU, "wait": _rng.randf_range(1.0, 5.0)}
	if kind == "bird":
		a["radius"] = _rng.randf_range(25.0, 60.0)
		a["height"] = _rng.randf_range(35.0, 70.0)
		a["speed"] = _rng.randf_range(0.2, 0.35) * (1.0 if _rng.randf() < 0.5 else -1.0)
		a["cry"] = _rng.randf_range(8.0, 30.0)
	elif kind == "bear":
		var ang := _rng.randf() * TAU
		a["vel"] = Vector2(cos(ang), sin(ang)) * 1.1
		a["state"] = "walk"
	n.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	animals.append(a)
	if kind == "bird":
		_update(a, 0.0, n.position)
	return a


func _remove(a: Dictionary) -> void:
	a["node"].queue_free()
	animals.erase(a)


func _update(a: Dictionary, delta: float, pp: Vector3) -> void:
	a["t"] += delta
	var n: Node3D = a["node"]
	match a["kind"]:
		"bird":
			a["phase"] += a["speed"] * delta
			var c: Vector2 = a["center"]
			var ph: float = a["phase"]
			var p: Vector2 = c + Vector2(cos(ph), sin(ph)) * a["radius"]
			var y: float = terrain.height_at(c.x, c.y) + a["height"] + sin(a["t"] * 0.3) * 3.0
			n.position = Vector3(p.x, y, p.y)
			var dir := Vector2(-sin(ph), cos(ph)) * signf(a["speed"])
			n.rotation.y = atan2(dir.x, dir.y)
			n.rotation.z = -0.35 * signf(a["speed"])
			var flap := sin(a["t"] * 7.0) * 0.5 if fmod(a["t"], 9.0) < 2.0 else 0.08
			n.get_child(1).rotation.z = flap
			n.get_child(2).rotation.z = -flap
			a["cry"] -= delta
			if a["cry"] <= 0.0:
				a["cry"] = _rng.randf_range(15.0, 45.0)
				Sfx.play("hawk", n.position, -4.0, _rng.randf_range(0.9, 1.1))
			return
		"deer":
			var away := Vector2(n.position.x - pp.x, n.position.z - pp.z)
			if a["state"] == "graze" and away.length() < DEER_SPOOK:
				a["state"] = "flee"
				a["vel"] = away.normalized().rotated(_rng.randf_range(-0.4, 0.4)) * DEER_RUN
			if a["state"] == "graze":
				a["wait"] -= delta
				if a["wait"] <= 0.0:
					a["wait"] = _rng.randf_range(3.0, 8.0)
					var ang := _rng.randf() * TAU
					a["vel"] = Vector2(cos(ang), sin(ang)) * 0.6 if _rng.randf() < 0.5 else Vector2.ZERO
		"bear":
			a["wait"] -= delta
			if a["wait"] <= 0.0:
				a["wait"] = _rng.randf_range(4.0, 10.0)
				a["vel"] = a["vel"].rotated(_rng.randf_range(-0.6, 0.6))
	var v: Vector2 = a["vel"]
	var p := Vector2(n.position.x, n.position.z) + v * delta
	if terrain.water_depth(p.x, p.y) > -0.2 and a["state"] != "flee":
		a["vel"] = -v
		p = Vector2(n.position.x, n.position.z)
	var y: float = terrain.height_at(p.x, p.y)
	var head: Node3D = n.get_node("Head")
	if a["state"] == "flee":
		y += absf(sin(a["t"] * 6.0)) * 0.7
		head.rotation.x = 0.3
	elif a["kind"] == "deer":
		head.rotation.x = -1.1 if v == Vector2.ZERO else 0.0
	n.position = Vector3(p.x, y, p.y)
	if v.length() > 0.01:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(v.x, v.y), minf(1.0, delta * 5.0))


func _mat(key: String, c: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _legs(n: Node3D, w: float, l: float, h: float, t: float, mat: Material) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(n, Vector3(t, h, t), Vector3(sx * w, h * 0.5, sz * l), mat)


## Facing +Z.
func _build_deer(n: Node3D) -> void:
	var fur := _mat("deer", Color(0.52, 0.36, 0.22))
	var pale := _mat("deer_pale", Color(0.85, 0.8, 0.7))
	_legs(n, 0.13, 0.42, 0.75, 0.07, fur)
	_box(n, Vector3(0.36, 0.42, 1.15), Vector3(0, 0.95, 0), fur)
	_box(n, Vector3(0.14, 0.14, 0.08), Vector3(0, 1.08, -0.6), pale)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.05, 0.5)
	n.add_child(head)
	_box(head, Vector3(0.16, 0.5, 0.16), Vector3(0, 0.25, 0.05), fur, Vector3(0.35, 0, 0))
	_box(head, Vector3(0.16, 0.16, 0.32), Vector3(0, 0.5, 0.25), fur)
	_box(head, Vector3(0.06, 0.14, 0.03), Vector3(0.09, 0.62, 0.15), fur)
	_box(head, Vector3(0.06, 0.14, 0.03), Vector3(-0.09, 0.62, 0.15), fur)


func _build_bear(n: Node3D) -> void:
	var fur := _mat("bear", Color(0.13, 0.09, 0.07))
	_legs(n, 0.28, 0.55, 0.6, 0.2, fur)
	_box(n, Vector3(0.8, 0.75, 1.6), Vector3(0, 0.95, 0), fur)
	_box(n, Vector3(0.7, 0.3, 0.5), Vector3(0, 1.3, -0.2), fur)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.05, 0.85)
	n.add_child(head)
	_box(head, Vector3(0.45, 0.4, 0.4), Vector3(0, 0, 0.1), fur)
	_box(head, Vector3(0.22, 0.18, 0.22), Vector3(0, -0.05, 0.38), _mat("bear_nose", Color(0.3, 0.22, 0.15)))
	_box(head, Vector3(0.12, 0.12, 0.06), Vector3(0.16, 0.25, 0.0), fur)
	_box(head, Vector3(0.12, 0.12, 0.06), Vector3(-0.16, 0.25, 0.0), fur)


## Child 0 is the body, 1 and 2 the wings (flapped by rotation.z).
func _build_bird(n: Node3D, raven: bool) -> void:
	var c := Color(0.06, 0.06, 0.07) if raven else Color(0.42, 0.3, 0.2)
	var m := _mat("raven" if raven else "hawk", c)
	_box(n, Vector3(0.14, 0.12, 0.55), Vector3.ZERO, m)
	for s in [1.0, -1.0]:
		var pivot := Node3D.new()
		n.add_child(pivot)
		_box(pivot, Vector3(0.6, 0.03, 0.26), Vector3(s * 0.33, 0, 0.02), m)
	_box(n, Vector3(0.22, 0.02, 0.18), Vector3(0, 0, -0.33), m)
