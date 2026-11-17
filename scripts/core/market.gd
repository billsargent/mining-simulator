extends RefCounted
## The gold price. It drifts a little from day to day, the same way every game, so it is
## worth holding a bar for a better day but never worth agonizing over.

const BASE_PRICE := 95.0           # dollars per gram of pure gold

static var day := 1                # kept current by main.gd


static func price(on_day: int = -1) -> float:
	var d := float(day if on_day < 0 else on_day)
	var drift := 0.1 * sin(d * 0.7) + 0.05 * sin(d * 1.9 + 1.3)
	return snappedf(BASE_PRICE * (1.0 + drift), 0.5)


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
