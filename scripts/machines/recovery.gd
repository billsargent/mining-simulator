extends RefCounted
## How much gold a sluice-type machine catches, by piece size and sluice angle.
## The sweet spot is 5-8 degrees. Steeper washes fine gold out; shallower packs the riffles.

const SWEET_LO := 5.0
const SWEET_HI := 8.0

static var carpet_bonus := 0.0     # miner's moss: set by main.gd when the player owns it


## 0 = good flow, 1 = a bit off, 2 = losing gold
static func zone(angle: float) -> int:
	if angle >= SWEET_LO and angle <= SWEET_HI:
		return 0
	if angle >= SWEET_LO - 2.0 and angle <= SWEET_HI + 2.0:
		return 1
	return 2


static func catch_chance(mass: float, angle: float, bonus: float = 0.0) -> float:
	var base: float
	var steep_loss: float
	if mass < 0.004:          # fines
		base = 0.74
		steep_loss = 0.11
	elif mass < 0.015:        # flakes
		base = 0.9
		steep_loss = 0.06
	elif mass < 0.05:         # big flakes
		base = 0.96
		steep_loss = 0.03
	else:                     # pickers and nuggets
		base = 0.99
		steep_loss = 0.012
	var steep := maxf(0.0, angle - SWEET_HI)
	var shallow := maxf(0.0, SWEET_LO - angle)
	# Moss mostly helps the small gold; big pieces were being caught anyway.
	var carpet := carpet_bonus * (1.0 if mass < 0.004 else (0.5 if mass < 0.015 else 0.2))
	return clampf(base + bonus + carpet - steep * steep_loss - shallow * 0.06, 0.05, 0.995)
