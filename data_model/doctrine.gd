class_name Doctrine
extends Resource

## 思想 — a way of thinking about how a country ought to be run, with a lineage
## of its own apart from the countries that try it.
##
## Not an organization: a doctrine has no members, no treasury and no head. It
## has a founder, the thinkers who revised it after, the countries that took it
## as their creed, and a picture of the state it believes in, drawn on the same
## axes as a real regime so the two can be compared. Every doctrine but the
## first comes out of an earlier one — carried on, split over, turned against,
## married to another, or dug up again after it had died — so the whole of a
## world's thought can be followed back to a single root, the same promise every
## other lineage in the game keeps.
##
## That it exists, who wrote what, and who adopted it are discrete facts and come
## through the record (DOCTRINE events, applied by GameState). How admired it is
## and how widely it is shared are continuous numbers kept here as cache.

@export var doctrine_id: StringName = &""
@export var name: String = ""
## The doctrine it came out of. For a reaction, the one it was written against.
@export var parent_id: StringName = &""
## A synthesis has two: the other one it took from.
@export var second_parent_id: StringName = &""
## root / development / schism / reaction / synthesis / revival / governance
@export var derivation: String = "root"
@export var founder_id: StringName = &""
@export var born_tick: int = 0
@export var born_polity_id: StringName = &""
## Born from a reign rather than a book: the state and the ruler it took as its
## model.
@export var model_polity_id: StringName = &""
@export var model_ruler_id: StringName = &""
## The state it believes in, on PoliticalSystemAxes' continuous axes
## (axis name -> -1..1), with what makes rule right and who decides.
@export var claims: Dictionary = {}
## What it argued when first written, before anybody revised it.
@export var origin_claims: Dictionary = {}
@export var basis: int = 0
@export var structure: int = 0
## How it meets change: -1 hold to what was .. +1 remake everything.
@export var change: float = 0.0
## How finished a body of thought it is, 0..1. Raised by each revision.
@export var maturity: float = 0.2
## rising / underground / faded
@export var state: String = "rising"
@export var state_tick: int = 0
## Where it is mostly at home now: the country it was born in, until it is
## driven out of it.
@export var home_polity_id: StringName = &""
## Those who wrote it, in order: {person, tick, kind, work, teacher}.
@export var thinkers: Array = []
## Countries that have held it as their creed: {polity, start, end}.
@export var adoptions: Array = []
## The dominant faith's view of it: "" (none taken), "blessed", "heresy".
@export var faith_stance: String = ""
@export var origin_event_id: StringName = &""

## Cached: how admired it is (0..1) and how widely the great families and
## factions share its picture of the state (0..1).
@export var prestige: float = 0.3
@export var support: float = 0.0


func is_alive() -> bool:
	return state != "faded"


func adopted_by() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in adoptions:
		if int(a.get("end", -1)) < 0:
			out.append(StringName(a.get("polity", "")))
	return out


func founder() -> NotableIndividual:
	return GameState.get_person(founder_id)


func to_dict() -> Dictionary:
	return {
		"doctrine_id": String(doctrine_id),
		"name": name,
		"parent_id": String(parent_id),
		"second_parent_id": String(second_parent_id),
		"derivation": derivation,
		"founder_id": String(founder_id),
		"born_tick": born_tick,
		"born_polity_id": String(born_polity_id),
		"model_polity_id": String(model_polity_id),
		"model_ruler_id": String(model_ruler_id),
		"claims": claims.duplicate(),
		"origin_claims": origin_claims.duplicate(),
		"basis": basis,
		"structure": structure,
		"change": change,
		"maturity": maturity,
		"state": state,
		"state_tick": state_tick,
		"home_polity_id": String(home_polity_id),
		"thinkers": thinkers.duplicate(true),
		"adoptions": adoptions.duplicate(true),
		"faith_stance": faith_stance,
		"origin_event_id": String(origin_event_id),
		"prestige": prestige,
		"support": support,
	}


static func from_dict(d: Dictionary) -> Doctrine:
	var x := Doctrine.new()
	x.doctrine_id = StringName(d.get("doctrine_id", ""))
	x.name = String(d.get("name", ""))
	x.parent_id = StringName(d.get("parent_id", ""))
	x.second_parent_id = StringName(d.get("second_parent_id", ""))
	x.derivation = String(d.get("derivation", "root"))
	x.founder_id = StringName(d.get("founder_id", ""))
	x.born_tick = int(d.get("born_tick", 0))
	x.born_polity_id = StringName(d.get("born_polity_id", ""))
	x.model_polity_id = StringName(d.get("model_polity_id", ""))
	x.model_ruler_id = StringName(d.get("model_ruler_id", ""))
	var claims := {}
	var raw: Dictionary = d.get("claims", {})
	for axis in raw:
		claims[String(axis)] = float(raw[axis])
	x.claims = claims
	var origin := {}
	var raw_origin: Dictionary = d.get("origin_claims", {})
	for axis in raw_origin:
		origin[String(axis)] = float(raw_origin[axis])
	x.origin_claims = origin
	x.basis = int(d.get("basis", 0))
	x.structure = int(d.get("structure", 0))
	x.change = float(d.get("change", 0.0))
	x.maturity = float(d.get("maturity", 0.2))
	x.state = String(d.get("state", "rising"))
	x.state_tick = int(d.get("state_tick", 0))
	x.home_polity_id = StringName(d.get("home_polity_id", ""))
	var thinkers: Array = []
	for t in d.get("thinkers", []):
		if t is Dictionary:
			var copy: Dictionary = t.duplicate()
			copy["tick"] = int(copy.get("tick", 0))
			thinkers.append(copy)
	x.thinkers = thinkers
	var adoptions: Array = []
	for a in d.get("adoptions", []):
		if a is Dictionary:
			var copy: Dictionary = a.duplicate()
			copy["start"] = int(copy.get("start", 0))
			copy["end"] = int(copy.get("end", -1))
			adoptions.append(copy)
	x.adoptions = adoptions
	x.faith_stance = String(d.get("faith_stance", ""))
	x.origin_event_id = StringName(d.get("origin_event_id", ""))
	x.prestige = float(d.get("prestige", 0.3))
	x.support = float(d.get("support", 0.0))
	return x
