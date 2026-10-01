shader_type canvas_item;

// The world map, drawn entirely here.
//
// Every region is the ground nearer to its own town than to any other, with the
// test run on a warped copy of the plane so borders wander the way borders do.
// The land is a continent that reaches out toward every town; past it is sea,
// with the shallows hatched in the manner of an old chart. Each region is tinted
// by whatever the map is currently showing — who holds it, what it believes,
// how angry it is — and the animated parts (unrest, calamities) run on the GPU
// so the phone does none of that work on its own time.

const int MAX_SITES = 16;

uniform int site_count = 0;
uniform vec2 sites[16];
uniform vec4 site_tint[16];
uniform float site_unrest[16];
uniform int selected_site = -1;

// The rectangle this is drawn on never moves: it covers the whole view, and the
// pan and zoom are handed in instead, so the land can never slide a frame
// behind the towns drawn over it. Anything outside the map is open sea.
uniform vec2 canvas_size = vec2(720.0, 1100.0);
uniform vec2 view_offset = vec2(0.0);
uniform float view_zoom = 1.0;
uniform vec2 map_size = vec2(1000.0, 1450.0);
uniform vec2 aspect = vec2(1.0, 1.45);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 noise_shift = vec2(0.0);

uniform float tint_strength = 0.55;
uniform vec4 vellum : source_color = vec4(0.30, 0.26, 0.19, 1.0);
uniform vec4 vellum_light : source_color = vec4(0.42, 0.37, 0.28, 1.0);
uniform vec4 ink : source_color = vec4(0.09, 0.075, 0.055, 1.0);
uniform vec4 sea : source_color = vec4(0.055, 0.09, 0.12, 1.0);
uniform vec4 sea_light : source_color = vec4(0.12, 0.19, 0.24, 1.0);
uniform vec4 gold : source_color = vec4(0.83, 0.65, 0.28, 1.0);

// The calamity in progress, if any: 0 none, 1 drought, 2 plague, 3 fire,
// 4 monsters, 5 blessing.
uniform int fx_kind = 0;
uniform float fx_strength = 0.0;

float noise_at(vec2 uv) {
	return texture(noise_tex, uv + noise_shift).r;
}

void fragment() {
	vec2 world = (UV * canvas_size - view_offset) / view_zoom;
	vec2 map_uv = world / map_size;
	vec2 p = map_uv * aspect;

	// Warp the plane so borders and coasts wander instead of running straight.
	vec2 warp = vec2(noise_at(map_uv * 1.7) - 0.5, noise_at(map_uv * 1.7 + vec2(0.37, 0.61)) - 0.5);
	vec2 q = p + warp * 0.16;

	float d1 = 1e5;
	float d2 = 1e5;
	int nearest = -1;
	for (int i = 0; i < MAX_SITES; i++) {
		if (i >= site_count) {
			break;
		}
		float d = distance(q, sites[i] * aspect);
		if (d < d1) {
			d2 = d1;
			d1 = d;
			nearest = i;
		} else if (d < d2) {
			d2 = d;
		}
	}

	// The continent: one body over the middle of the map reaching out toward
	// every town, with a coast roughened by noise.
	vec2 centred = (map_uv - vec2(0.5)) * vec2(1.55, 1.32);
	float body = 1.0 - length(centred);
	float reach = 1.0 - d1 / 0.45;
	// Two scales of roughness: a slow one that shapes bays and headlands, and a
	// faint quick one for the crinkle of the shore. Too much of the quick one
	// and the land breaks into gravel.
	float shape = noise_at(map_uv * 1.6 + vec2(0.11, 0.9)) - 0.5;
	float crinkle = noise_at(map_uv * 5.0 + vec2(0.7, 0.2)) - 0.5;
	float field = max(body, reach) + shape * 0.30 + crinkle * 0.06;
	float coast = 0.5;
	float land = smoothstep(coast - 0.012, coast + 0.012, field);

	// --- the sea: dark water, the shallows hatched in rings off the coast.
	float grain = noise_at(map_uv * 9.0);
	vec3 water = mix(sea.rgb, sea_light.rgb, smoothstep(0.1, 0.5, field) * 0.85);
	water *= 0.9 + grain * 0.2;
	float shallows = smoothstep(0.1, 0.48, field);
	float rings = abs(fract(field * 14.0 - TIME * 0.04) - 0.5);
	water = mix(water, sea_light.rgb * 1.25, (1.0 - smoothstep(0.0, 0.06, rings)) * shallows * 0.35);

	// --- the land: vellum, darker at the edges of each region like an old map
	// coloured by hand, tinted by whatever the map is showing.
	float paper = noise_at(map_uv * 6.0) * 0.6 + noise_at(map_uv * 22.0) * 0.4;
	vec3 ground = mix(vellum.rgb, vellum_light.rgb, paper);
	float edge = d2 - d1;
	vec4 tint = nearest >= 0 ? site_tint[nearest] : vec4(0.0);
	ground = mix(ground, tint.rgb * (0.75 + paper * 0.35), tint.a * tint_strength);
	ground *= mix(0.72, 1.0, smoothstep(0.0, 0.11, edge));

	// Unrest smoulders: a red cast that breathes, and embers that rise.
	float unrest = nearest >= 0 ? site_unrest[nearest] : 0.0;
	if (unrest > 0.05) {
		float breath = 0.55 + 0.45 * sin(TIME * 2.4 + float(nearest) * 1.7);
		vec3 heat = vec3(0.78, 0.25, 0.16);
		ground = mix(ground, heat, unrest * 0.32 * breath);
		float ember = noise_at(map_uv * 30.0 + vec2(0.0, TIME * 0.05));
		ground += heat * smoothstep(0.82, 0.95, ember) * unrest * 0.8 * breath;
	}

	// The chosen region is lit, as if the lamp had been brought over to it.
	if (nearest == selected_site && selected_site >= 0) {
		ground = mix(ground, ground * 1.35 + vec3(0.04, 0.03, 0.0), 0.65);
	}

	// Borders in ink, the selected one in gold.
	float border = 1.0 - smoothstep(0.004, 0.012, edge);
	vec3 border_ink = ink.rgb;
	ground = mix(ground, border_ink, border * 0.85);

	// --- calamities, laid over the whole land.
	if (fx_kind == 1) {
		// Drought: the colour drains to dust and the ground cracks.
		float lum = dot(ground, vec3(0.33));
		ground = mix(ground, vec3(lum) * vec3(1.18, 1.0, 0.72), fx_strength * 0.7);
		float crack = abs(noise_at(map_uv * 16.0) - 0.5);
		ground = mix(ground, ink.rgb, (1.0 - smoothstep(0.0, 0.018, crack)) * fx_strength * 0.6);
	} else if (fx_kind == 2) {
		// Plague: a sick green that drifts across the land.
		float miasma = noise_at(map_uv * 2.6 + vec2(TIME * 0.02, TIME * 0.013));
		ground = mix(ground, vec3(0.42, 0.55, 0.22), smoothstep(0.45, 0.8, miasma) * fx_strength * 0.55);
	} else if (fx_kind == 3) {
		// Fire: an orange glow that flickers, and sparks.
		float flick = noise_at(map_uv * 5.0 + vec2(0.0, -TIME * 0.08));
		ground = mix(ground, vec3(0.95, 0.45, 0.12), smoothstep(0.5, 0.9, flick) * fx_strength * 0.6);
		float spark = noise_at(map_uv * 40.0 + vec2(TIME * 0.03, -TIME * 0.12));
		ground += vec3(1.0, 0.6, 0.2) * smoothstep(0.9, 0.97, spark) * fx_strength;
	} else if (fx_kind == 4) {
		// Monsters: the dark closes in from the wild edges of the world.
		float wild = smoothstep(0.75, 0.25, field) + 0.25 * (noise_at(map_uv * 4.0 + vec2(TIME * 0.03)) - 0.5);
		float pulse = 0.65 + 0.35 * sin(TIME * 3.1);
		ground = mix(ground, vec3(0.32, 0.06, 0.08), clamp(wild, 0.0, 1.0) * fx_strength * 0.75 * pulse);
	} else if (fx_kind == 5) {
		// Blessing: gold catches the light here and there.
		float glint = noise_at(map_uv * 34.0 + vec2(sin(TIME * 0.4) * 0.02, TIME * 0.015));
		ground += gold.rgb * smoothstep(0.86, 0.95, glint) * fx_strength * 0.9;
		ground = mix(ground, ground * vec3(1.08, 1.05, 0.9), fx_strength * 0.5);
	}

	vec3 colour = mix(water, ground, land);

	// The coast, inked.
	float coastline = 1.0 - smoothstep(0.0, 0.02, abs(field - coast));
	colour = mix(colour, ink.rgb, coastline * 0.9);

	// A soft vignette, so the map reads as a sheet lying on the table.
	vec2 v = UV - vec2(0.5);
	colour *= 1.0 - dot(v, v) * 0.9;

	COLOR = vec4(colour, 1.0);
}
