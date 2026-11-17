extends RefCounted
## Everything the prospector owns, plus the step-by-step goals for this build.

const Paydirt = preload("res://scripts/gold/paydirt.gd")

const NUGGET_MASS := 0.3
const GOALS = [
	["journal", "Read Grandpa's journal: it's on the crate in front of the porch (E)."],
	["pan", "Dig some gravel (left mouse), then pan it at the creek's edge (E)."],
	["sluice_placed", "Carry the sluice from the shed (F) and set it in the creek (left mouse)."],
	["sluice_fed", "Dig right next to the sluice: each shovelful goes straight in."],
	["cleaned", "Clean out the sluice's riffles (E on the sluice)."],
	["cons_panned", "Pan your jar of concentrate at the wash tub by the cabin (E)."],
	["smelted", "Melt your gold into a bar at the furnace (E)."],
	["sold", "Sell the bar at the assay office in town: take the road down Cabin Creek, then east along the river. M opens the map."],
	["high_banker", "Save up $900 and buy a high banker at the general store in town."],
	["hb_running", "Set the pump at the creek's edge and the high banker on the bank, then feed it."],
	["drive", "Hop on the ATV or the pickup parked by the cabin (E) and take it for a spin."],
	["haul", "Carry a machine to a vehicle and set it on the rack or in the bed (left mouse)."],
	["map", "Open the map (M) and drop a waypoint where you want to go (left click)."],
	["last_chance", "Find the old camp on Last Chance Creek. The old-timers said that creek was rich."],
	["mine_enter", "Find the old mine above Rattlesnake Gulch (west on the map) and go in. Bring your headlamp (L)."],
	["ore", "Chip a white quartz vein in the mine wall (left mouse) to fill your ore sack."],
	["crushed", "Take the ore home and pound it in the ore crusher by the wash tub, then pan the jar."],
	["claim", "Buy a claim at the claims office in town. Test-pan it first: machines only run on ground you own."],
	["find", "The old crew left things behind in the mine. Look in the far corners and read what you find."],
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
var tool_tier := 0                      # 0 hammer and chisel, 1 miner's pick, 2 rotary hammer
var crusher_powered := false
var specimens := PackedFloat32Array()   # gold in quartz, kept whole: grams of gold in each
var finds := {}                         # journals and maps already read
var gear := {}                          # small things from the store: classifier, bucket, sack, moss, detector
var claims := {}                        # ids of the claims you have bought
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


func bucket_capacity() -> int:
	return 10 if gear.has("bucket") else 6


func ore_capacity() -> int:
	return 20 if gear.has("sack") else ORE_CAPACITY


func add_specimen(grams: float) -> void:
	specimens.append(grams)


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
		"high_banker_bought": high_banker_bought, "tool_tier": tool_tier, "goals": goals_done, "samples": samples,
		"crusher_powered": crusher_powered, "specimens": specimens, "finds": finds, "gear": gear, "claims": claims,
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
	tool_tier = d.get("tool_tier", 0)
	goals_done = d.get("goals", {})
	samples = d.get("samples", PackedVector3Array())
	crusher_powered = d.get("crusher_powered", false)
	specimens = d.get("specimens", PackedFloat32Array())
	finds = d.get("finds", {})
	gear = d.get("gear", {})
	claims = d.get("claims", {})


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
