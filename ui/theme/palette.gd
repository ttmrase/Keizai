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
const DANGER := Color("c85a4a")
const GOOD := Color("7ab87a")

## One colour per kind of institution, used consistently on the map, the lineage
## trees and the power dashboard so an organization is recognisable anywhere.
const GUILD := Color("6fa8c8")
const HOUSE := Color("c8926f")
const FACTION := Color("8fbf7a")
const POLITY := Color("b48fd0")
const RELIGION := Color("d0b48f")


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
