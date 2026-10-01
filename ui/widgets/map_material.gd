class_name MapMaterial
extends RefCounted

## The world map's material, made in one place so the map screen and anything
## else that wants to show the land (the title screen) draw the same continent.

static func create() -> ShaderMaterial:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise

	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/world_map.gdshader")
	material.set_shader_parameter("noise_tex", texture)
	material.set_shader_parameter("vellum", Palette.VELLUM)
	material.set_shader_parameter("vellum_light", Palette.VELLUM_LIGHT)
	material.set_shader_parameter("ink", Palette.INK)
	material.set_shader_parameter("sea", Palette.SEA)
	material.set_shader_parameter("sea_light", Palette.SEA_LIGHT)
	material.set_shader_parameter("gold", Palette.ACCENT)
	return material


## Every town at its place, each region in the colours of the family holding it.
static func feed_world(material: ShaderMaterial, map_size: Vector2) -> void:
	var ids: Array[StringName] = []
	for id in GameState.world.settlements:
		ids.append(id)
	ids.sort_custom(func(a, b): return String(a) < String(b))
	var sites := PackedVector2Array()
	var tints: Array = []
	var unrest := PackedFloat32Array()
	for id in ids.slice(0, 16):
		var s: SettlementState = GameState.world.settlements[id]
		sites.append(s.position)
		var house := GameState.get_organization(s.ruling_house_id)
		tints.append(Heraldry.of_org(house) if house != null else Color(0, 0, 0, 0))
		unrest.append(0.0)
	for i in range(sites.size(), 16):
		sites.append(Vector2(-9, -9))
		tints.append(Color(0, 0, 0, 0))
		unrest.append(0.0)
	material.set_shader_parameter("site_count", mini(ids.size(), 16))
	material.set_shader_parameter("sites", sites)
	material.set_shader_parameter("site_tint", tints)
	material.set_shader_parameter("site_unrest", unrest)
	material.set_shader_parameter("selected_site", -1)
	material.set_shader_parameter("map_size", map_size)
	material.set_shader_parameter("aspect", Vector2(1.0, map_size.y / map_size.x))
	var s := float(GameState.world.seed % 9973) / 9973.0
	material.set_shader_parameter("noise_shift", Vector2(s, fmod(s * 7.13, 1.0)))
