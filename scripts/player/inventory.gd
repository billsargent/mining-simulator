extends RefCounted
## Everything the prospector owns, plus the step-by-step goals for this build.

const Paydirt = preload("res://scripts/gold/paydirt.gd")

const NUGGET_MASS := 0.3
const GOALS = [
	["pan", "Dig some gravel (left mouse), then pan it at the creek's edge (E)."],
	["sluice_placed", "Carry the sluice from the shed (F) and set it in the creek (left mouse)."],
	["sluice_fed", "Dig right next to the sluice: each shovelful goes straight in."],
	["cleaned", "Clean out the sluice's riffles (E on the sluice)."],
	["cons_panned", "Pan your jar of concentrate at the wash tub by the cabin (E)."],
	["smelted", "Melt your gold into a bar at the furnace (E)."],
	["sold", "Ship the bar in the gold buyer's box in front of the porch (E)."],
	["high_banker", "Save up $350 and order a high banker at the order board on the cabin."],
	["hb_running", "Set the pump at the creek's edge and the high banker on the bank, then feed it."],
	["drive", "Hop on the ATV or the pickup parked by the cabin (E) and take it for a spin."],
	["haul", "Carry a machine to a vehicle and set it on the rack or in the bed (left mouse)."],
	["map", "Open the map (M) and drop a waypoint where you want to go (left click)."],
	["last_chance", "Find the old camp on Last Chance Creek. The old-timers said that creek was rich."],
	["mine_enter", "Find the old mine above Rattlesnake Gulch (west on the map) and go in. Bring your headlamp (L)."],
	["ore", "Chip a white quartz vein in the mine wall (left mouse) to fill your ore sack."],
	["crushed", "Take the ore home and pound it in the ore crusher by the wash tub, then pan the jar."],
]

const ORE_CAPACITY := 10

var money := 0
var bucket: Array = []                  # Paydirt shovelfuls
var cons: Array = []                    # Paydirt jars of concentrate
var ore: Array = []                     # Paydirt pieces of quartz ore from the mine
var vial := PackedFloat32Array()        # loose gold: fines, flakes, pickers
var nuggets := PackedFloat32Array()
var bars: Array = []                    # {"grams": float, "purity": float}
var pans := 0
var high_banker_bought := false
var goals_done := {}
var samples := PackedVector3Array()     # test pans for the map: x, z, grams


func log_sample(x: float, z: float, grams: float) -> void:
	samples.append(Vector3(x, z, grams))


func add_gold(pieces: PackedFloat32Array) -> void:
	for m in pieces:
		if m >= NUGGET_MASS:
			nuggets.append(m)
		else:
			vial.append(m)


func vial_grams() -> float:
	return _sum(vial)


func nugget_grams() -> float:
	return _sum(nuggets)


func bar_grams() -> float:
	var total := 0.0
	for b in bars:
		total += float(b["grams"])
	return total


func take_vial() -> float:
	var g := vial_grams()
	vial = PackedFloat32Array()
	return g


## Returns true the first time a goal is completed.
func complete_goal(id: String) -> bool:
	if goals_done.has(id):
		return false
	goals_done[id] = true
	return true


func next_goal() -> String:
	for g in GOALS:
		if not goals_done.has(g[0]):
			return g[1]
	return "That's everything in this build. Keep prospecting: the old bench above Cabin Creek is rich."


func to_dict() -> Dictionary:
	return {
		"money": money, "bucket": _dirt_out(bucket), "cons": _dirt_out(cons), "ore": _dirt_out(ore),
		"vial": vial, "nuggets": nuggets, "bars": bars, "pans": pans,
		"high_banker_bought": high_banker_bought, "goals": goals_done, "samples": samples,
	}


func from_dict(d: Dictionary) -> void:
	money = d.get("money", 0)
	bucket = _dirt_in(d.get("bucket", []))
	cons = _dirt_in(d.get("cons", []))
	ore = _dirt_in(d.get("ore", []))
	vial = d.get("vial", PackedFloat32Array())
	nuggets = d.get("nuggets", PackedFloat32Array())
	bars = d.get("bars", [])
	pans = d.get("pans", 0)
	high_banker_bought = d.get("high_banker_bought", false)
	goals_done = d.get("goals", {})
	samples = d.get("samples", PackedVector3Array())


static func _sum(a: PackedFloat32Array) -> float:
	var t := 0.0
	for m in a:
		t += m
	return t


static func _dirt_out(list: Array) -> Array:
	var out := []
	for d in list:
		out.append(d.to_dict())
	return out


static func _dirt_in(list: Array) -> Array:
	var out := []
	for d in list:
		var p := Paydirt.new()
		p.load_dict(d)
		out.append(p)
	return out
