extends SceneTree
## How much gold a sluice keeps at each angle, using the real mix of piece sizes.
## Run: godot --headless --path . --script res://tests/test_recovery.gd

const Recovery = preload("res://scripts/machines/recovery.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")


func _initialize() -> void:
	# Piece sizes don't depend on the world, so an ungenerated one is enough here.
	var field := DepositField.new(WorldGen.new(1849), 1849)
	var pieces := PackedFloat32Array()
	for i in 4000:
		pieces.append(field._piece_mass(true))
	var total := 0.0
	for m in pieces:
		total += m
	print("Share of gold (by weight) kept, by angle:   sluice   high banker")
	for a in [0.0, 2.0, 4.0, 5.0, 6.5, 8.0, 10.0, 12.0, 15.0]:
		var kept := 0.0
		var kept_hb := 0.0
		for m in pieces:
			kept += m * Recovery.catch_chance(m, a)
			kept_hb += m * Recovery.catch_chance(m, a, 0.04)
		print("  %4.1f°  %-12s %5.1f%%   %5.1f%%" % [a, ["good", "ok", "losing"][Recovery.zone(a)], 100.0 * kept / total, 100.0 * kept_hb / total])
	quit()
