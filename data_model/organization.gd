class_name Organization
extends Resource

## A guild, house, faction, or political system.
##
## All four kinds share one class rather than using subclasses. The design calls
## for uniform handling — the same lineage walk, the same PowerCalculator, the
## same schism rules apply to every kind — and the kind-specific fields are few
## enough that a `kind` discriminator serves that better than four subclasses
## would (GDScript also cannot have a base class construct its own subclasses
## without a cyclic class_name dependency).
##
## `parent_org_id` is the traceability chain: exactly one organization per kind
## has an empty parent, and every other organization reaches it by walking up.

enum OrgKind { GUILD, HOUSE, FACTION, POLITICAL_SYSTEM }

const KIND_NAMES := {
	OrgKind.GUILD: "GUILD",
	OrgKind.HOUSE: "HOUSE",
	OrgKind.FACTION: "FACTION",
	OrgKind.POLITICAL_SYSTEM: "POLITICAL_SYSTEM",
}

@export var org_id: StringName = &""
@export var kind: OrgKind = OrgKind.GUILD
## Selects the PowerProfile and naming word bank. Adding an archetype is a data
## change, never an engine change.
@export var archetype_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

# --- Lineage ---
@export var parent_org_id: StringName = &""
@export var origin_event_id: StringName = &""
@export var founding_tick: int = 0
@export var branch_depth: int = 0
@export var child_org_ids: Array[StringName] = []
@export var dissolved_tick: int = -1

# --- Leadership and membership ---
@export var leader_person_id: StringName = &""
@export var leadership_title: String = "Head"
@export var member_count: int = 0
@export var resources: Dictionary[StringName, float] = {}

# --- Cached, recomputed each power epoch; never event-sourced ---
@export var power_score: float = 0.0
@export var power_drivers: Dictionary[StringName, float] = {}

## rule_id -> tick it last fired for this organization (cooldown bookkeeping).
@export var last_fired_tick: Dictionary[StringName, int] = {}

@export var ideology: PoliticalSystemAxes
## What this organization believed when it was founded. Drift rules compare
## against this rather than a time series, so "it is no longer what it was" is
## answerable without storing history per axis.
@export var ideology_baseline: PoliticalSystemAxes

# --- Kind-specific ---
@export var trade_specialty: StringName = &""                  # GUILD
@export var dynasty_seat_settlement_id: StringName = &""       # HOUSE
@export var succession_rule_id: StringName = &""               # HOUSE
@export var cause_tags: Array[StringName] = []                 # FACTION
@export var governs_settlement_ids: Array[StringName] = []     # POLITICAL_SYSTEM
@export var legitimacy: float = 0.7                            # POLITICAL_SYSTEM


func kind_name() -> String:
	return KIND_NAMES.get(kind, "UNKNOWN")


func is_root() -> bool:
	return parent_org_id == &""


func is_active() -> bool:
	return dissolved_tick < 0


func to_dict() -> Dictionary:
	var d := {
		"org_id": String(org_id),
		"kind": kind_name(),
		"archetype_id": String(archetype_id),
		"display_name": display_name,
		"description": description,
		"parent_org_id": String(parent_org_id),
		"origin_event_id": String(origin_event_id),
		"founding_tick": founding_tick,
		"branch_depth": branch_depth,
		"child_org_ids": _names_to_strings(child_org_ids),
		"dissolved_tick": dissolved_tick,
		"leader_person_id": String(leader_person_id),
		"leadership_title": leadership_title,
		"member_count": member_count,
		"resources": _name_keyed_to_strings(resources),
		"power_score": power_score,
		"power_drivers": _name_keyed_to_strings(power_drivers),
		"last_fired_tick": _name_keyed_to_strings(last_fired_tick),
		"legitimacy": legitimacy,
	}
	if ideology != null:
		d["ideology"] = ideology.to_dict()
	if ideology_baseline != null:
		d["ideology_baseline"] = ideology_baseline.to_dict()
	if trade_specialty != &"":
		d["trade_specialty"] = String(trade_specialty)
	if dynasty_seat_settlement_id != &"":
		d["dynasty_seat_settlement_id"] = String(dynasty_seat_settlement_id)
	if succession_rule_id != &"":
		d["succession_rule_id"] = String(succession_rule_id)
	if not cause_tags.is_empty():
		d["cause_tags"] = _names_to_strings(cause_tags)
	if not governs_settlement_ids.is_empty():
		d["governs_settlement_ids"] = _names_to_strings(governs_settlement_ids)
	return d


static func from_dict(d: Dictionary) -> Organization:
	var o := Organization.new()
	o.org_id = StringName(d.get("org_id", ""))
	o.kind = _kind_from_name(d.get("kind", "GUILD"))
	o.archetype_id = StringName(d.get("archetype_id", ""))
	o.display_name = d.get("display_name", "")
	o.description = d.get("description", "")
	o.parent_org_id = StringName(d.get("parent_org_id", ""))
	o.origin_event_id = StringName(d.get("origin_event_id", ""))
	o.founding_tick = int(d.get("founding_tick", 0))
	o.branch_depth = int(d.get("branch_depth", 0))
	o.child_org_ids = _strings_to_names(d.get("child_org_ids", []))
	o.dissolved_tick = int(d.get("dissolved_tick", -1))
	o.leader_person_id = StringName(d.get("leader_person_id", ""))
	o.leadership_title = d.get("leadership_title", "Head")
	o.member_count = int(d.get("member_count", 0))
	var res: Dictionary[StringName, float] = {}
	for k in d.get("resources", {}):
		res[StringName(k)] = float(d["resources"][k])
	o.resources = res
	o.power_score = float(d.get("power_score", 0.0))
	var drivers: Dictionary[StringName, float] = {}
	for k in d.get("power_drivers", {}):
		drivers[StringName(k)] = float(d["power_drivers"][k])
	o.power_drivers = drivers
	var fired: Dictionary[StringName, int] = {}
	for k in d.get("last_fired_tick", {}):
		fired[StringName(k)] = int(d["last_fired_tick"][k])
	o.last_fired_tick = fired
	if d.has("ideology"):
		o.ideology = PoliticalSystemAxes.from_dict(d["ideology"])
	if d.has("ideology_baseline"):
		o.ideology_baseline = PoliticalSystemAxes.from_dict(d["ideology_baseline"])
	o.trade_specialty = StringName(d.get("trade_specialty", ""))
	o.dynasty_seat_settlement_id = StringName(d.get("dynasty_seat_settlement_id", ""))
	o.succession_rule_id = StringName(d.get("succession_rule_id", ""))
	o.cause_tags = _strings_to_names(d.get("cause_tags", []))
	o.governs_settlement_ids = _strings_to_names(d.get("governs_settlement_ids", []))
	o.legitimacy = float(d.get("legitimacy", 0.7))
	return o


static func _kind_from_name(n: String) -> OrgKind:
	for k in KIND_NAMES:
		if KIND_NAMES[k] == n:
			return k
	return OrgKind.GUILD


static func _names_to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out


static func _strings_to_names(arr: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in arr:
		out.append(StringName(v))
	return out


static func _name_keyed_to_strings(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out
