class_name RoleTenure
extends Resource

## One stint holding a titled position. Enough to answer "who led org X at tick T"
## long after the person is dead.

@export var org_id: StringName = &""
@export var title: String = ""
@export var start_tick: int = 0
@export var end_tick: int = -1      # -1 = still in office
@export var start_event_id: StringName = &""
@export var end_event_id: StringName = &""


func is_current() -> bool:
	return end_tick < 0


func to_dict() -> Dictionary:
	return {
		"org_id": String(org_id),
		"title": title,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"start_event_id": String(start_event_id),
		"end_event_id": String(end_event_id),
	}


static func from_dict(d: Dictionary) -> RoleTenure:
	var r := RoleTenure.new()
	r.org_id = StringName(d.get("org_id", ""))
	r.title = d.get("title", "")
	r.start_tick = int(d.get("start_tick", 0))
	r.end_tick = int(d.get("end_tick", -1))
	r.start_event_id = StringName(d.get("start_event_id", ""))
	r.end_event_id = StringName(d.get("end_event_id", ""))
	return r
