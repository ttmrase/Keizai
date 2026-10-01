class_name Palette
extends RefCounted

## Shared colours. A muted, warm dark scheme — this is a game you leave running
## and glance at, so it needs to be restful rather than bright.

const BG := Color("14120f")
const PANEL := Color("1e1b16")
const PANEL_RAISED := Color("2a2620")
const LINE := Color("3a352c")

const TEXT := Color("e8e0d0")
const TEXT_MUTED := Color("9a9080")
const TEXT_DIM := Color("6a6357")

const ACCENT := Color("d4a748")
const ACCENT_SOFT := Color("8a6d32")
const DANGER := Color("c85a4a")
const GOOD := Color("7ab87a")

## One colour per kind of institution, used consistently on the map, the lineage
## trees and the power dashboard so an organization is recognisable anywhere.
const GUILD := Color("6fa8c8")
const HOUSE := Color("c8926f")
const FACTION := Color("8fbf7a")
const POLITY := Color("b48fd0")
const RELIGION := Color("d0b48f")

## The map: ink on old vellum, and a dark sea around it.
const SEA := Color("101a22")
const SEA_LIGHT := Color("1c2c38")
const VELLUM := Color("3a3326")
const VELLUM_LIGHT := Color("54493a")
const INK := Color("1a1610")


static func for_kind(kind: int) -> Color:
	match kind:
		Organization.OrgKind.GUILD:
			return GUILD
		Organization.OrgKind.HOUSE:
			return HOUSE
		Organization.OrgKind.FACTION:
			return FACTION
		Organization.OrgKind.POLITICAL_SYSTEM:
			return POLITY
		Organization.OrgKind.RELIGION:
			return RELIGION
	return TEXT_MUTED


static func kind_label(kind: int) -> String:
	match kind:
		Organization.OrgKind.GUILD:
			return "ギルド"
		Organization.OrgKind.HOUSE:
			return "家"
		Organization.OrgKind.FACTION:
			return "派閥"
		Organization.OrgKind.POLITICAL_SYSTEM:
			return "政体"
		Organization.OrgKind.RELIGION:
			return "信仰"
	return "組織"


## Green through amber to red, for gauges where high is bad (unrest, threat).
static func severity(value: float) -> Color:
	return GOOD.lerp(DANGER, clampf(value, 0.0, 1.0))


## The rounded chip used wherever one of a few views is picked: filled gold
## when chosen, a faint outline when not.
static func pill(active: bool, radius: int = 19) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT if active else Color(0.08, 0.07, 0.05, 0.78)
	box.border_color = ACCENT if active else Color(1, 1, 1, 0.12)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8
	box.content_margin_right = 8
	return box


## Dresses a toggle button as a pill and keeps its text legible on either fill.
static func style_pill(button: Button, active: bool) -> void:
	button.button_pressed = active
	for state in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(state, pill(active))
	button.add_theme_stylebox_override("pressed", pill(true))
	button.add_theme_stylebox_override("hover_pressed", pill(true))
	var ink := INK if active else TEXT
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_focus_color", ink)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", INK)
