class_name WarState
extends Resource

## A war in progress: a country that split rather than fell, and the two states
## now fighting over it.
##
## That the war exists, who fights it, which battles were fought and who changed
## sides are discrete facts and arrive through the record — CONFLICT_DECLARED
## opens one, CONFLICT_RESOLVED closes it, battles and defections are
## POWER_TRANSFER events carrying the war's id. How it is going (the front, how
## worn out each side is) is a continuous number like a power score, kept here as
## cached state and saved with the snapshot. See CivilWar.

@export var war_id: StringName = &""
## The state that stood before the split: the old order, the loyalists.
@export var side_a: StringName = &""
## The state that broke away: the new order, or the stronger party of a renewed war.
@export var side_b: StringName = &""
@export var start_tick: int = 0
## Why it started: "split" (a country divided over a change of regime) or
## "renewal" (two states that were one, fighting again after a truce).
@export var cause: String = "split"
## What the challenge rested on — the chamber, the street, force, the altar.
@export var ground: String = ""
## Whether the change that split the country was taken by force.
@export var forced: bool = false
## The house each side's cause centres on, as it stood when the war began.
@export var house_a: StringName = &""
@export var house_b: StringName = &""

## -1 (side B has won) .. +1 (side A has won). Cached.
@export var front: float = 0.0
## 0 .. 1+, how worn out each side is. A side past 1 cannot go on. Cached.
@export var exhaustion_a: float = 0.0
@export var exhaustion_b: float = 0.0
## The last few strengths, for the screen that shows the balance. Cached.
@export var strength_a: float = 0.0
@export var strength_b: float = 0.0
## Each side's strength in the war's first year: who was the underdog. Cached.
@export var opening_a: float = 0.0
@export var opening_b: float = 0.0

## Battles fought, newest last: {tick, settlement_id, winner ("a"/"b"), taken}.
## Written only by GameState.apply from the battle events.
@export var battles: Array = []
## Houses that changed sides, in the order they did. Written only by apply.
@export var defectors: Array[StringName] = []


func years(tick: int) -> int:
	return int((tick - start_tick) / SimConfig.TICKS_PER_YEAR)


func side_of(polity_id: StringName) -> String:
	if polity_id == side_a:
		return "a"
	if polity_id == side_b:
		return "b"
	return ""


func involves(polity_id: StringName) -> bool:
	return polity_id != &"" and (polity_id == side_a or polity_id == side_b)


func to_dict() -> Dictionary:
	return {
		"war_id": String(war_id),
		"side_a": String(side_a),
		"side_b": String(side_b),
		"start_tick": start_tick,
		"cause": cause,
		"ground": ground,
		"forced": forced,
		"house_a": String(house_a),
		"house_b": String(house_b),
		"front": front,
		"exhaustion_a": exhaustion_a,
		"exhaustion_b": exhaustion_b,
		"strength_a": strength_a,
		"strength_b": strength_b,
		"opening_a": opening_a,
		"opening_b": opening_b,
		"battles": battles.duplicate(true),
		"defectors": Organization._names_to_strings(defectors),
	}


static func from_dict(d: Dictionary) -> WarState:
	var w := WarState.new()
	w.war_id = StringName(d.get("war_id", ""))
	w.side_a = StringName(d.get("side_a", ""))
	w.side_b = StringName(d.get("side_b", ""))
	w.start_tick = int(d.get("start_tick", 0))
	w.cause = String(d.get("cause", "split"))
	w.ground = String(d.get("ground", ""))
	w.forced = bool(d.get("forced", false))
	w.house_a = StringName(d.get("house_a", ""))
	w.house_b = StringName(d.get("house_b", ""))
	w.front = float(d.get("front", 0.0))
	w.exhaustion_a = float(d.get("exhaustion_a", 0.0))
	w.exhaustion_b = float(d.get("exhaustion_b", 0.0))
	w.strength_a = float(d.get("strength_a", 0.0))
	w.strength_b = float(d.get("strength_b", 0.0))
	w.opening_a = float(d.get("opening_a", 0.0))
	w.opening_b = float(d.get("opening_b", 0.0))
	var fought: Array = []
	for b in d.get("battles", []):
		if b is Dictionary:
			fought.append({
				"tick": int(b.get("tick", 0)),
				"settlement_id": String(b.get("settlement_id", "")),
				"winner": String(b.get("winner", "")),
				"taken": bool(b.get("taken", false)),
			})
	w.battles = fought
	w.defectors = Organization._strings_to_names(d.get("defectors", []))
	return w
