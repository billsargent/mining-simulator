extends RefCounted
## Everything the prospector owns, plus the step-by-step goals for this build.
const Sfx = preload("res://scripts/core/sfx.gd")

const Paydirt = preload("res://scripts/gold/paydirt.gd")

const NUGGET_MASS := 0.3
const GOALS = [
	["journal", "Read Grandpa's journal: it's on the crate in front of the porch (E)."],
	["pan", "Dig some gravel (left mouse), then pan it at the creek's edge (E). The green marker shows where."],
	["read_creek", "Read the creek: gold sinks where the water slows. Try the inside of a bend or just below a big boulder, and dig deep. Pan until you get a few colors."],
	["sluice_placed", "Carry the sluice from the shed (F) and set it in the creek (left mouse)."],
	["sluice_fed", "Dig right next to the sluice: each shovelful goes straight in."],
	["cleaned", "Clean out the sluice's riffles (E on the sluice)."],
	["cons_panned", "Pan your jar of concentrate at the wash tub by the cabin (E)."],
	["smelted", "Melt your gold into a bar at the furnace (E)."],
	["drive", "Hop on the ATV or the pickup parked by the cabin (E) and drive it: town is a long walk."],
	["sold", "Sell the bar at the assay office in town: take the road down Cabin Creek, then east along the river. M opens the map."],
	["high_banker", "Save up $900 and buy a high banker at the general store in town."],
	["hb_running", "Set the pump at the creek's edge and the high banker on the bank, then feed it."],
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
var garnets := PackedFloat32Array()     # garnets, by size in carats
var finds := {}                         # journals and maps already read
var gear := {}                          # small things from the store: classifier, bucket, sack, moss, detector
var claims := {}                        # ids of the claims you have bought

# The storage chest in the cabin.
var chest_cons: Array = []
var chest_ore: Array = []
var chest_vial := PackedFloat32Array()
var chest_nuggets := PackedFloat32Array()
var chest_specimens := PackedFloat32Array()
var chest_garnets := PackedFloat32Array()
var chest_bars: Array = []
var goals_done := {}
var samples := PackedVector3Array()     # test pans for the map: x, z, grams
# Records for the pause menu's Records page.
var biggest_nugget := 0.0               # grams
var gold_found := 0.0                   # grams, all time
var earned := 0                         # dollars from sales, all time
var best_day := 0                       # most dollars sold in one game day
var best_day_no := 0
var _today_no := 0
var _today := 0
var garnets_found := 0
var walked := 0.0                       # metres
var driven := 0.0
var _garnets_seen := 0                  # garnets carried when last looked, to count new finds


func log_sample(x: float, z: float, grams: float) -> void:
	samples.append(Vector3(x, z, grams))


## A whole nugget, kept apart from the dust (packed arrays only change from here).
func add_nugget(m: float) -> void:
	nuggets.append(m)
	gold_found += m
	biggest_nugget = maxf(biggest_nugget, m)


func add_gold(pieces: PackedFloat32Array) -> void:
	for m in pieces:
		gold_found += m
		biggest_nugget = maxf(biggest_nugget, m)
		if m >= NUGGET_MASS:
			nuggets.append(m)
		else:
			vial.append(m)


## Note a sale for the records.
func record_sale(dollars: int, day: int) -> void:
	watch_garnets()
	earned += dollars
	if day != _today_no:
		_today_no = day
		_today = 0
	_today += dollars
	if _today > best_day:
		best_day = _today
		best_day_no = day


## Called every frame: counts garnets that have turned up since the last look.
func watch_garnets() -> void:
	if garnets.size() > _garnets_seen:
		garnets_found += garnets.size() - _garnets_seen
	_garnets_seen = garnets.size()


## Put every valuable you carry into the chest. Returns what moved, in describe_goods() form.
func store_in_chest() -> Array:
	var moved := carried_goods()
	chest_cons.append_array(cons)
	chest_ore.append_array(ore)
	chest_bars.append_array(bars)
	chest_vial.append_array(vial)
	chest_nuggets.append_array(nuggets)
	chest_specimens.append_array(specimens)
	chest_garnets.append_array(garnets)
	cons = []
	ore = []
	bars = []
	vial = PackedFloat32Array()
	nuggets = PackedFloat32Array()
	specimens = PackedFloat32Array()
	garnets = PackedFloat32Array()
	_garnets_seen = 0
	return moved


## Take everything back out (ore only as far as the sack holds; the rest stays in the chest).
## Returns what moved, in describe_goods() form.
func take_from_chest() -> Array:
	var room := maxi(0, ore_capacity() - ore.size())
	var ore_out := chest_ore.slice(0, room)
	var moved := chest_goods()
	moved[1] = ore_out.size()
	cons.append_array(chest_cons)
	ore.append_array(ore_out)
	bars.append_array(chest_bars)
	vial.append_array(chest_vial)
	nuggets.append_array(chest_nuggets)
	specimens.append_array(chest_specimens)
	garnets.append_array(chest_garnets)
	chest_cons = []
	chest_ore = chest_ore.slice(room)
	chest_bars = []
	chest_vial = PackedFloat32Array()
	chest_nuggets = PackedFloat32Array()
	chest_specimens = PackedFloat32Array()
	chest_garnets = PackedFloat32Array()
	_garnets_seen = garnets.size()
	return moved


## True when describe_goods() would say "nothing".
static func goods_empty(g: Array) -> bool:
	for i in g.size():
		if float(g[i]) > 0.0:
			return false
	return true


func chest_goods() -> Array:
	return [chest_cons.size(), chest_ore.size(), _sum(chest_vial), chest_nuggets.size(), chest_specimens.size(), chest_bars.size(), chest_garnets.size()]


func carried_goods() -> Array:
	return [cons.size(), ore.size(), vial_grams(), nuggets.size(), specimens.size(), bars.size(), garnets.size()]


## [jars, ore, loose grams, nuggets, specimens, bars, garnets] as words.
static func describe_goods(g: Array) -> String:
	var parts := PackedStringArray()
	for item in [[g[5], "bar"], [g[3], "nugget"], [g[4], "specimen"], [g[6] if g.size() > 6 else 0, "garnet"], [g[0], "jar"], [g[1], "piece of ore", "pieces of ore"]]:
		if int(item[0]) > 0:
			parts.append("%d %s" % [item[0], item[1] if int(item[0]) == 1 else (item[2] if item.size() > 2 else item[1] + "s")])
	if float(g[2]) > 0.0:
		parts.append("%.3f g loose gold" % g[2])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


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
	Sfx.play("goal", null, -6.0)
	return true


## The id of the next goal, or "" when they're all done.
func next_goal_id() -> String:
	for g in GOALS:
		if not goals_done.has(g[0]):
			return g[0]
	return ""


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
		"crusher_powered": crusher_powered, "specimens": specimens, "garnets": garnets, "finds": finds, "gear": gear, "claims": claims,
		"records": {"biggest_nugget": biggest_nugget, "gold_found": gold_found, "earned": earned, "best_day": best_day,
			"best_day_no": best_day_no, "today_no": _today_no, "today": _today, "garnets_found": garnets_found,
			"walked": walked, "driven": driven},
		"chest": {"cons": _dirt_out(chest_cons), "ore": _dirt_out(chest_ore), "vial": chest_vial, "nuggets": chest_nuggets,
			"specimens": chest_specimens, "garnets": chest_garnets, "bars": chest_bars},
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
	garnets = d.get("garnets", PackedFloat32Array())
	finds = d.get("finds", {})
	gear = d.get("gear", {})
	claims = d.get("claims", {})
	var r: Dictionary = d.get("records", {})
	biggest_nugget = r.get("biggest_nugget", 0.0)
	gold_found = r.get("gold_found", 0.0)
	earned = r.get("earned", 0)
	best_day = r.get("best_day", 0)
	best_day_no = r.get("best_day_no", 0)
	_today_no = r.get("today_no", 0)
	_today = r.get("today", 0)
	garnets_found = r.get("garnets_found", 0)
	walked = r.get("walked", 0.0)
	driven = r.get("driven", 0.0)
	_garnets_seen = garnets.size()
	var ch: Dictionary = d.get("chest", {})
	chest_cons = _dirt_in(ch.get("cons", []))
	chest_ore = _dirt_in(ch.get("ore", []))
	chest_vial = ch.get("vial", PackedFloat32Array())
	chest_nuggets = ch.get("nuggets", PackedFloat32Array())
	chest_garnets = ch.get("garnets", PackedFloat32Array())
	chest_specimens = ch.get("specimens", PackedFloat32Array())
	chest_bars = ch.get("bars", [])


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
