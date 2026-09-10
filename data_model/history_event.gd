class_name HistoryEvent
extends Resource

## One discrete, narratively significant thing that happened.
##
## This is the backbone of the traceability guarantee: `origin_event_id` chains
## every event back to the event that caused it, and `parent_org_id` chains every
## organization back to the single root of its kind. Continuously varying numbers
## (power scores, unrest, resource levels) are deliberately NOT recorded here —
## they are cached state captured by the snapshot instead. See docs/DESIGN.md §A.

enum EventType {
	FOUNDING,
	BIRTH,
	MARRIAGE,
	DEATH,
	SUCCESSION,
	SCHISM,
	POWER_TRANSFER,
	IDEOLOGY_SHIFT,
	DISASTER_OCCURRED,
	RESOURCE_SHOCK,
	ALLIANCE_FORMED,
	CONFLICT_DECLARED,
	CONFLICT_RESOLVED,
	DISSOLVED,
	RENAMED,
	## A rupture: something that does not happen in the ordinary course of a
	## century and rearranges the board when it does. Its mechanical consequences
	## go through the ordinary events — a death, a transfer of power — and this is
	## the headline that says what they were all part of.
	INCIDENT,
	EPOCH_SUMMARY,
}

const TYPE_NAMES := {
	EventType.FOUNDING: "FOUNDING",
	EventType.BIRTH: "BIRTH",
	EventType.MARRIAGE: "MARRIAGE",
	EventType.DEATH: "DEATH",
	EventType.SUCCESSION: "SUCCESSION",
	EventType.SCHISM: "SCHISM",
	EventType.POWER_TRANSFER: "POWER_TRANSFER",
	EventType.IDEOLOGY_SHIFT: "IDEOLOGY_SHIFT",
	EventType.DISASTER_OCCURRED: "DISASTER_OCCURRED",
	EventType.RESOURCE_SHOCK: "RESOURCE_SHOCK",
	EventType.ALLIANCE_FORMED: "ALLIANCE_FORMED",
	EventType.CONFLICT_DECLARED: "CONFLICT_DECLARED",
	EventType.CONFLICT_RESOLVED: "CONFLICT_RESOLVED",
	EventType.DISSOLVED: "DISSOLVED",
	EventType.RENAMED: "RENAMED",
	EventType.INCIDENT: "INCIDENT",
	EventType.EPOCH_SUMMARY: "EPOCH_SUMMARY",
}

@export var event_id: StringName = &""
@export var event_type: EventType = EventType.FOUNDING
@export var tick: int = 0
## Real-world timestamp. Metadata for the player only — simulation logic must
## never branch on this, or determinism replays break.
@export var wall_time_unix: int = 0
@export var subject_org_id: StringName = &""
@export var subject_person_id: StringName = &""
@export var origin_event_id: StringName = &""
@export var parent_org_id: StringName = &""
@export var related_person_ids: Array[StringName] = []
@export var payload: Dictionary = {}
@export var is_lineage_critical: bool = true
@export var description: String = ""


func type_name() -> String:
	return TYPE_NAMES.get(event_type, "UNKNOWN")


func to_dict() -> Dictionary:
	var d := {
		"event_id": String(event_id),
		"event_type": type_name(),
		"tick": tick,
	}
	if wall_time_unix != 0:
		d["wall_time_unix"] = wall_time_unix
	if subject_org_id != &"":
		d["subject_org_id"] = String(subject_org_id)
	if subject_person_id != &"":
		d["subject_person_id"] = String(subject_person_id)
	if origin_event_id != &"":
		d["origin_event_id"] = String(origin_event_id)
	if parent_org_id != &"":
		d["parent_org_id"] = String(parent_org_id)
	if not related_person_ids.is_empty():
		var rel: Array = []
		for p in related_person_ids:
			rel.append(String(p))
		d["related_person_ids"] = rel
	if not payload.is_empty():
		d["payload"] = payload
	if not is_lineage_critical:
		d["is_lineage_critical"] = false
	if description != "":
		d["description"] = description
	return d


static func from_dict(d: Dictionary) -> HistoryEvent:
	var e := HistoryEvent.new()
	e.event_id = StringName(d.get("event_id", ""))
	e.event_type = type_from_name(d.get("event_type", "FOUNDING"))
	e.tick = int(d.get("tick", 0))
	e.wall_time_unix = int(d.get("wall_time_unix", 0))
	e.subject_org_id = StringName(d.get("subject_org_id", ""))
	e.subject_person_id = StringName(d.get("subject_person_id", ""))
	e.origin_event_id = StringName(d.get("origin_event_id", ""))
	e.parent_org_id = StringName(d.get("parent_org_id", ""))
	var rel: Array[StringName] = []
	for p in d.get("related_person_ids", []):
		rel.append(StringName(p))
	e.related_person_ids = rel
	e.payload = d.get("payload", {})
	e.is_lineage_critical = bool(d.get("is_lineage_critical", true))
	e.description = d.get("description", "")
	return e


static func type_from_name(n: String) -> EventType:
	for k in TYPE_NAMES:
		if TYPE_NAMES[k] == n:
			return k
	return EventType.FOUNDING
