extends RefCounted
## The gold price. It drifts a little from day to day, the same way every game, so it is
## worth holding a bar for a better day but never worth agonizing over.

const BASE_PRICE := 95.0           # dollars per gram of pure gold

static var day := 1                # kept current by main.gd


const EVENT_DAYS := 3               # a spike or slump lasts this many days
const SPIKE := 0.3                 # top of a spike, over the drift
const SLUMP := -0.25               # bottom of a slump


static func price(on_day: int = -1) -> float:
	var d := day if on_day < 0 else on_day
	var drift := 0.1 * sin(d * 0.7) + 0.05 * sin(d * 1.9 + 1.3)
	return snappedf(BASE_PRICE * (1.0 + drift + event_shift(d)), 0.5)


## Price events are fixed by the day number, like storms: each week after the first may
## hold one spike or slump of EVENT_DAYS days. Returns [start_day, "spike"|"slump"] or [].
static func _week_event(week: int) -> Array:
	if week < 1:
		return []
	var h := hash(week * 6151 + 977)
	if h % 100 >= 45:
		return []
	return [week * 7 + 1 + (h / 100) % 3, "spike" if (h / 1000) % 2 == 0 else "slump"]


## "spike", "slump" or "" on that day.
static func event(on_day: int = -1) -> String:
	var d := day if on_day < 0 else on_day
	var e := _week_event(d / 7)
	if e.is_empty() or d < e[0] or d >= e[0] + EVENT_DAYS:
		return ""
	return e[1]


## How far the event moves the price that day: strongest on its middle day.
static func event_shift(d: int) -> float:
	var k := event(d)
	if k == "":
		return 0.0
	var e := _week_event(d / 7)
	var mid := d - int(e[0]) == 1
	return (SPIKE if k == "spike" else SLUMP) * (1.0 if mid else 0.6)


## A line of news about today's event, or a rumor of tomorrow's; "" when quiet.
static func news() -> String:
	match event():
		"spike":
			return "Gold is spiking: buyers back East are paying well. It won't last."
		"slump":
			return "Gold has slumped. Hold your bars a few days if you can."
	match event(day + 1):
		"spike":
			return "Word is the price will jump tomorrow."
		"slump":
			return "Word is the price will fall tomorrow."
	return ""


## "up", "down" or "steady" against yesterday.
static func trend() -> String:
	var change := price() - price(day - 1)
	if absf(change) < 1.0:
		return "steady"
	return "up" if change > 0.0 else "down"


static func bar_value(bar: Dictionary) -> int:
	return roundi(float(bar["grams"]) * float(bar["purity"]) * price())


## Collectors pay more for nuggets, and more again for big ones.
static func nugget_value(m: float) -> int:
	return roundi(m * price() * (1.5 + minf(m, 2.0) * 0.25))


## Gold in quartz, left whole.
static func specimen_value(grams: float) -> int:
	return roundi(grams * price() * 2.5)
