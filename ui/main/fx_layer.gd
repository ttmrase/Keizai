class_name FxLayer
extends Control

## The moments that deserve more than a line of text, drawn over everything.
##
## A prophecy coming true, a calamity called down, a capital falling: these are
## what the game is played for, and they used to arrive as a card like any
## other. Here they get a second of light — rays for a prophecy fulfilled, a
## wash of colour and a jolt for a blow, a mark that rises and fades. Nothing
## here can be touched and nothing lasts: it is drawn, it decays, and the
## screen underneath is never held up for it.

## Whatever is shaken when the ground moves. Set by whoever owns the layer.
var shake_target: Control

var _effects: Array[Dictionary] = []
var _shake_left := 0.0
var _shake_life := 0.0
var _shake_size := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Rays and a ring opening from a point, with a mark at the heart of it: the
## thing foretold has come.
func burst(colour: Color, glyph: StringName = &"", origin: Vector2 = Vector2(-1, -1),
		reach: float = 1.0) -> void:
	_add({"kind": "burst", "life": 1.5, "colour": colour, "glyph": glyph,
		"origin": origin if origin.x >= 0.0 else size * Vector2(0.5, 0.42), "reach": reach,
		"spin": randf() * TAU})


## The whole screen tinted for an instant, as when the sky changes.
func wash(colour: Color, strength: float = 0.4, life: float = 0.8) -> void:
	_add({"kind": "wash", "life": life, "colour": colour, "strength": strength})


## A great mark that settles over the land and fades: what was called down.
func omen(glyph: StringName, colour: Color) -> void:
	_add({"kind": "omen", "life": 1.3, "colour": colour, "glyph": glyph})


## A few words that rise from a point and are gone — a gain, a loss.
func rise(text: String, colour: Color, from: Vector2) -> void:
	_add({"kind": "rise", "life": 1.4, "colour": colour, "text": text, "origin": from})


## The ground moving under everything, briefly.
func quake(seconds: float = 0.35, amplitude: float = 7.0) -> void:
	_shake_left = seconds
	_shake_life = seconds
	_shake_size = amplitude
	set_process(true)


func busy() -> bool:
	return not _effects.is_empty() or _shake_left > 0.0


func _add(effect: Dictionary) -> void:
	effect["t"] = 0.0
	_effects.append(effect)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for effect in _effects:
		effect["t"] = float(effect["t"]) + delta
	_effects = _effects.filter(func(e): return float(e["t"]) < float(e["life"]))
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		if shake_target != null:
			var fade := _shake_left / maxf(0.01, _shake_life)
			shake_target.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
				* _shake_size * fade if _shake_left > 0.0 else Vector2.ZERO
	queue_redraw()
	if not busy():
		if shake_target != null:
			shake_target.position = Vector2.ZERO
		set_process(false)


func _draw() -> void:
	for effect in _effects:
		var u := clampf(float(effect["t"]) / float(effect["life"]), 0.0, 1.0)
		match String(effect["kind"]):
			"burst":
				_draw_burst(effect, u)
			"wash":
				var fade := (1.0 - u) * (1.0 - u)
				draw_rect(Rect2(Vector2.ZERO, size),
					Color(effect["colour"], float(effect["strength"]) * fade))
			"omen":
				_draw_omen(effect, u)
			"rise":
				var font := get_theme_default_font()
				var at: Vector2 = effect["origin"] + Vector2(0, -54.0 * _ease_out(u))
				var alpha := 1.0 - u * u
				draw_string(font, at + Vector2(1, 2), effect["text"], HORIZONTAL_ALIGNMENT_LEFT,
					-1, 26, Color(0, 0, 0, 0.6 * alpha))
				draw_string(font, at, effect["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
					Color(effect["colour"], alpha))


func _draw_burst(effect: Dictionary, u: float) -> void:
	var colour: Color = effect["colour"]
	var origin: Vector2 = effect["origin"]
	var reach: float = float(effect["reach"])
	var open := _ease_out(u)
	var fade := 1.0 - u
	var radius := lerpf(40.0, 560.0, open) * reach
	var spin: float = float(effect["spin"]) + u * 0.5
	# Rays: long thin wedges, alternately long and short.
	var rays := 16
	for i in rays:
		var angle := spin + TAU * float(i) / float(rays)
		var length := radius * (1.0 if i % 2 == 0 else 0.62)
		var half := 0.035 if i % 2 == 0 else 0.022
		var tip := origin + Vector2.from_angle(angle) * length
		var a := origin + Vector2.from_angle(angle - half) * length * 0.18
		var b := origin + Vector2.from_angle(angle + half) * length * 0.18
		draw_colored_polygon(PackedVector2Array([a, tip, b]), Color(colour, 0.5 * fade * fade))
	draw_arc(origin, radius * 0.5, 0.0, TAU, 64, Color(colour, 0.8 * fade), maxf(1.0, 5.0 * fade), true)
	draw_arc(origin, radius * 0.78, 0.0, TAU, 64, Color(colour, 0.35 * fade), 2.0, true)
	draw_circle(origin, lerpf(70.0, 20.0, open) * reach, Color(colour.lightened(0.4), 0.35 * fade))
	if StringName(effect["glyph"]) != &"":
		var pop := 1.0 + 0.5 * sin(minf(u * 3.0, 1.0) * PI)
		Glyph.draw(self, effect["glyph"], origin, 84.0 * pop * reach,
			Color(colour.lightened(0.25), minf(1.0, fade * 1.6)))


func _draw_omen(effect: Dictionary, u: float) -> void:
	var colour: Color = effect["colour"]
	var centre := size * Vector2(0.5, 0.44)
	# Falls into place, holds, and thins out.
	var settle := _ease_out(minf(u / 0.35, 1.0))
	var scale := lerpf(2.1, 1.0, settle)
	var alpha := 0.55 * settle * (1.0 - clampf((u - 0.45) / 0.55, 0.0, 1.0))
	Glyph.draw(self, effect["glyph"], centre + Vector2(0, lerpf(-90.0, 0.0, settle)),
		300.0 * scale, Color(colour, alpha), 0.7)
	draw_arc(centre, lerpf(120.0, 420.0, _ease_out(u)), 0.0, TAU, 64,
		Color(colour, 0.45 * (1.0 - u)), 3.0, true)


static func _ease_out(u: float) -> float:
	return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)
