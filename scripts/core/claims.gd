extends RefCounted
## Mining claims: round pieces of ground along the creeks. Anyone may pan and dig with a
## shovel on public land, but machines only run on a claim you own. Grandpa's claim is yours
## from the start; the rest are sold at the claims office in town.
## Before setup() is called (unit tests) everything counts as yours.

const WorldGen = preload("res://scripts/world/world_gen.gd")

static var list: Array = []       # {id, name, river, pos: Vector2, radius, price}
static var owned := {}            # id -> true; this is the inventory's own dictionary
static var finds := {}            # the inventory's finds: a secret claim shows once its find is read

const LEDGE_CLUES := ["journal", "note"]   # the mine finds that tell of Dutch's ledge
const LEDGE_PRICE := 25000        # Dutch's Ledge, the endgame: about 10 hours of high banker work


static func setup(world, deposits) -> void:
	list.clear()
	var base: Vector2 = world.sites["base"]["pos"]
	var camp: Vector2 = world.sites["camp"]["pos"]
	_add("home", "Grandpa's claim", "Cabin Creek", base, 140.0, 0)
	_add("sable", "Sable Bar", "Big Sable River", deposits.rich_spot("Big Sable River"), 90.0, 1200)
	_add("willow", "Willow Flats", "Willow Creek", deposits.rich_spot("Willow Creek"), 80.0, 1500)
	_add("rattlesnake", "Rattlesnake No. 2", "Rattlesnake Gulch", deposits.rich_spot("Rattlesnake Gulch"), 70.0, 2500)
	_add("tamarack", "Tamarack Cross", "Tamarack Creek", deposits.rich_spot("Tamarack Creek"), 70.0, 3500)
	_add("last_chance", "Last Chance Discovery", "Last Chance Creek", camp, 85.0, 6000)
	if not world.river_by_name("Coyote Wash").is_empty():
		_add("coyote", "Coyote Wash Placer", "Coyote Wash", deposits.rich_spot("Coyote Wash"), 75.0, 4000)
	if deposits.ledge != Vector2.INF:
		_add("ledge", "Dutch's Ledge", deposits.LEDGE_CREEK, deposits.ledge, 60.0, LEDGE_PRICE)
		list[-1]["secret"] = true


static func _add(id: String, name: String, river: String, pos: Vector2, radius: float, price: int) -> void:
	# Claims were sized for the 2 km world; creeks get longer as the world grows, so claims do too.
	var grow := sqrt(WorldGen.SIZE / 2048.0)
	list.append({"id": id, "name": name, "river": river, "pos": pos, "radius": radius * grow, "price": price})


## The claim this spot lies on, or {} for public land.
static func at(x: float, z: float) -> Dictionary:
	for c in list:
		if (c["pos"] as Vector2).distance_to(Vector2(x, z)) <= float(c["radius"]):
			return c
	return {}


## False for a secret claim until the find that tells of it has been read (or it's yours).
static func known(c: Dictionary) -> bool:
	return not c.has("secret") or LEDGE_CLUES.any(func(k): return finds.has(k)) or is_owned(c["id"])


static func is_owned(id: String) -> bool:
	return id == "home" or owned.has(id)


static func is_owned_at(x: float, z: float) -> bool:
	if list.is_empty():
		return true
	var c := at(x, z)
	return not c.is_empty() and is_owned(c["id"])


static func by_id(id: String) -> Dictionary:
	for c in list:
		if c["id"] == id:
			return c
	return {}
