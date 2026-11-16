extends RefCounted
## One load of material and what is in it: a shovelful of dirt, or a jar of concentrate.

var gold := PackedFloat32Array()   # mass of each piece of gold, in grams
var black_sand := 0.1              # 0..1 share of heavy black sand (a sign of gold)
var gravel := 1.0                  # how much gravel and sand it carries, relative to a shovelful
var sand := 1.0
var source := Vector3.ZERO         # where it was dug


func add_gold(mass: float) -> void:
	gold.append(mass)


func gold_grams() -> float:
	var total := 0.0
	for m in gold:
		total += m
	return total


func is_concentrate() -> bool:
	return gravel <= 0.0


func to_dict() -> Dictionary:
	return {"gold": gold, "black_sand": black_sand, "gravel": gravel, "sand": sand}


func load_dict(d: Dictionary) -> void:
	gold = d.get("gold", PackedFloat32Array())
	black_sand = d.get("black_sand", 0.1)
	gravel = d.get("gravel", 1.0)
	sand = d.get("sand", 1.0)
