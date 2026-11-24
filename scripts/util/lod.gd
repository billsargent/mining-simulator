extends RefCounted
## Distance culling for small built pieces (signs, trim, tools, fence posts, labels). Each piece
## stops drawing once it would be only a few pixels tall: the reach grows with its size, so
## buildings and big landmarks are untouched. Pieces that already have a range keep it, and
## particles (chimney smoke) are left alone.

const PER_METRE := 110.0    # metres of reach per metre of size (about 6 px at 1080p)
const MIN_REACH := 60.0
const LABEL_REACH := 120.0  # text is unreadable well before this


static func cull_small(root: Node) -> void:
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.visibility_range_end > 0.0 or gi is CPUParticles3D or gi is GPUParticles3D:
			continue
		var reach := LABEL_REACH
		if not (gi is Label3D):
			var box := gi.global_transform * gi.get_aabb()
			reach = maxf(MIN_REACH, box.size[box.get_longest_axis_index()] * PER_METRE)
			if reach >= 1500.0:
				continue      # big: seen as far as the camera reaches anyway
		gi.visibility_range_end = reach
		gi.visibility_range_end_margin = reach * 0.1
