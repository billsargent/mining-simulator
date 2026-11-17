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


# --- Photo textures (assets/textures, CC0 from Poly Haven; see CREDITS.md) ----------------------

static var _photo := {}


## One map of a texture set: "albedo", "normal" or "rough". Loaded straight from the image file
## (no editor import step needed), with mipmaps, and cached. Null if the file is missing.
static func photo(set_name: String, map: String) -> Texture2D:
	var key := set_name + "/" + map
	if _photo.has(key):
		return _photo[key]
	var path := "res://assets/textures/%s/%s.jpg" % [set_name, map]
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	var tex: Texture2D = null
	if img != null:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_photo[key] = tex
	return tex


## Put a photo texture set on a material: color, normal and roughness, laid on with world-space
## triplanar mapping (in object space, so it rides along when
## the thing moves) so any box or cylinder gets it without UVs. `scale` is repeats per metre.
static func dress(m: StandardMaterial3D, set_name: String, scale: float, normal_strength: float = 1.0) -> void:
	var a := photo(set_name, "albedo")
	if a == null:
		return
	m.albedo_texture = a
	var n := photo(set_name, "normal")
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = normal_strength
	var r := photo(set_name, "rough")
	if r != null:
		m.roughness_texture = r
		m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## The average color of a texture set's albedo (for tinting it toward a chosen color).
static func average(set_name: String) -> Color:
	var key := set_name + "/avg"
	if _photo.has(key):
		return _photo[key]
	var c := Color(0.5, 0.5, 0.5)
	var t := photo(set_name, "albedo")
	if t != null:
		var img: Image = t.get_image()
		img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		c = img.get_pixel(0, 0)
	_photo[key] = c
	return c


## Dress a material and tint the photo so its average comes out as `color`.
static func dress_as(m: StandardMaterial3D, set_name: String, scale: float, color: Color, normal_strength: float = 1.0) -> void:
	dress(m, set_name, scale, normal_strength)
	if m.albedo_texture == null:
		return
	var avg := average(set_name)
	m.albedo_color = Color(clampf(color.r / maxf(avg.r, 0.05), 0.0, 2.5), clampf(color.g / maxf(avg.g, 0.05), 0.0, 2.5),
		clampf(color.b / maxf(avg.b, 0.05), 0.0, 2.5), color.a)
