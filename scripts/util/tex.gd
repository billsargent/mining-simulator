extends RefCounted
## Small helpers for procedural textures (placeholders until real art arrives).


static func noise(frequency: float, noise_seed: int, size: int = 256, normal_map: bool = false, bump: float = 4.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = frequency
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal_map
	t.bump_strength = bump
	t.generate_mipmaps = true
	return t
