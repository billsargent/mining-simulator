extends SceneTree
## Balance check for panning. Good technique should keep nearly all the gold in a
## reasonable time; washing without shaking, or tilting too steeply, should lose gold.
## Run: godot --headless --path . --script res://tests/test_pan.gd

const PanSim = preload("res://scripts/panning/pan_sim.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")

const TRIALS := 40


func _initialize() -> void:
	var dt := 1.0 / 60.0
	for strategy in ["good", "no_shake", "too_steep", "shake_once"]:
		var kept := 0
		var total := 0
		var time := 0.0
		var unfinished := 0
		for trial in TRIALS:
			var rng := RandomNumberGenerator.new()
			rng.seed = 100 + trial
			var dirt := Paydirt.new()
			dirt.black_sand = rng.randf_range(0.05, 0.3)
			for i in 12:
				dirt.add_gold(rng.randf_range(0.001, 0.05))
			var sim := PanSim.new()
			sim.setup(dirt, 1000 + trial)
			var t := 0.0
			while not sim.done and t < 120.0:
				var phase := fmod(t, 3.2)
				var shaking := false
				var tilt := 0.0
				match strategy:
					"good":
						shaking = phase < 1.2
						tilt = 0.0 if shaking else 18.0
					"no_shake":
						tilt = 18.0
					"too_steep":
						shaking = phase < 1.2
						tilt = 0.0 if shaking else 34.0
					"shake_once":
						shaking = t < 1.5
						tilt = 0.0 if shaking else 18.0
				sim.step(dt, shaking, tilt, 0.0)
				t += dt
			if not sim.done:
				unfinished += 1
			kept += sim.gold_kept().size()
			total += dirt.gold.size()
			time += t
		print("%-11s kept %5.1f%% of gold   avg time %5.1fs   unfinished %d/%d" % [
			strategy, 100.0 * kept / total, time / TRIALS, unfinished, TRIALS])
	quit()
