extends Node

## The single funnel every lineage-relevant change passes through.
##
## record() appends to the log and then folds the event into GameState. Nothing
## else is allowed to create organizations, kill people, or move leadership, so
## "who descends from whom" can never disagree with the chronicle.
##
## Events are kept in a hot in-memory buffer and flushed to segment files by
## SaveManager. Lineage-critical events additionally go to a permanent backbone
## that compaction never touches.

## Events still in memory, newest last.
var buffer: Array[HistoryEvent] = []
## Every lineage-critical event this session, kept so traceability survives
## compaction of the ordinary chronicle.
var backbone: Array[HistoryEvent] = []
var total_recorded: int = 0

const _LINEAGE_CRITICAL_TYPES := [
	HistoryEvent.EventType.FOUNDING,
	HistoryEvent.EventType.SCHISM,
	HistoryEvent.EventType.SUCCESSION,
	HistoryEvent.EventType.POWER_TRANSFER,
	HistoryEvent.EventType.MARRIAGE,
	HistoryEvent.EventType.DISSOLVED,
	# A rupture is the hinge a later century is explained by. Never compacted.
	HistoryEvent.EventType.INCIDENT,
]


func record(e: HistoryEvent) -> HistoryEvent:
	if e.event_id == &"":
		e.event_id = GameState.mint_event_id()
	if e.wall_time_unix == 0:
		e.wall_time_unix = int(Time.get_unix_time_from_system())
	e.is_lineage_critical = _is_lineage_critical(e)

	buffer.append(e)
	if e.is_lineage_critical:
		backbone.append(e)
	total_recorded += 1

	GameState.apply(e)
	EventBus.event_recorded.emit(e)
	return e


## Builds and records an event in one step.
func emit_event(
		event_type: HistoryEvent.EventType,
		tick: int,
		description: String,
		payload: Dictionary = {},
		subject_org_id: StringName = &"",
		subject_person_id: StringName = &"",
		origin_event_id: StringName = &"",
		related_person_ids: Array[StringName] = []) -> HistoryEvent:
	var e := HistoryEvent.new()
	e.event_type = event_type
	e.tick = tick
	e.description = description
	e.payload = payload
	e.subject_org_id = subject_org_id
	e.subject_person_id = subject_person_id
	e.origin_event_id = origin_event_id
	e.related_person_ids = related_person_ids
	if payload.has("organization"):
		e.parent_org_id = StringName(payload["organization"].get("parent_org_id", ""))
	return record(e)


## Whether an event must survive compaction forever. Births, marriages and deaths
## are only permanent for people who ever held office — that keeps the backbone
## bounded by the number of notable figures rather than by elapsed time, while
## still guaranteeing every ruler's ancestry stays walkable.
func _is_lineage_critical(e: HistoryEvent) -> bool:
	if _LINEAGE_CRITICAL_TYPES.has(e.event_type):
		return true
	if e.event_type == HistoryEvent.EventType.BIRTH or e.event_type == HistoryEvent.EventType.DEATH:
		var p: NotableIndividual = GameState.get_person(e.subject_person_id)
		return p == null or p.ever_held_office() or p.is_founder_generation
	if e.event_type == HistoryEvent.EventType.IDEOLOGY_SHIFT:
		# A change to a discrete institutional fact — what a regime rests on, who
		# owns an office, what form the country takes — is permanent. A house
		# sliding a rung down the peerage is worth chronicling but not worth
		# keeping forever, or the backbone would grow with elapsed time rather
		# than with the number of institutions.
		return not bool(e.payload.get("transient", false))
	return false


## Newest-first slice for the chronicle UI.
func recent(count: int, filter_type: int = -1) -> Array[HistoryEvent]:
	var out: Array[HistoryEvent] = []
	for i in range(buffer.size() - 1, -1, -1):
		if filter_type >= 0 and buffer[i].event_type != filter_type:
			continue
		out.append(buffer[i])
		if out.size() >= count:
			break
	return out


func events_for_org(org_id: StringName, limit: int = 50) -> Array[HistoryEvent]:
	var out: Array[HistoryEvent] = []
	for i in range(buffer.size() - 1, -1, -1):
		var e := buffer[i]
		if e.subject_org_id == org_id or e.parent_org_id == org_id:
			out.append(e)
			if out.size() >= limit:
				break
	return out


func find_event(event_id: StringName) -> HistoryEvent:
	for e in buffer:
		if e.event_id == event_id:
			return e
	for e in backbone:
		if e.event_id == event_id:
			return e
	return null


func reset() -> void:
	buffer.clear()
	backbone.clear()
	total_recorded = 0


## Trims the ordinary chronicle down to the hot window, folding older ordinary
## events into per-(type, bucket) summaries. The backbone is never touched, so
## every lineage pointer still resolves afterwards.
func compact(current_tick: int) -> int:
	var cutoff: int = current_tick - SimConfig.HISTORY_HOT_WINDOW_TICKS
	if cutoff <= 0:
		return 0

	var kept: Array[HistoryEvent] = []
	var summaries := {}
	var folded := 0
	for e in buffer:
		if e.tick >= cutoff or e.is_lineage_critical:
			kept.append(e)
			continue
		var bucket: int = e.tick / SimConfig.COMPACTION_EPOCH_BUCKET_TICKS
		var key := "%d:%d" % [e.event_type, bucket]
		if not summaries.has(key):
			var s := HistoryEvent.new()
			s.event_id = GameState.mint_event_id()
			s.event_type = HistoryEvent.EventType.EPOCH_SUMMARY
			s.tick = bucket * SimConfig.COMPACTION_EPOCH_BUCKET_TICKS
			s.is_lineage_critical = false
			s.payload = {"of_type": e.type_name(), "count": 0, "first_tick": e.tick, "last_tick": e.tick}
			summaries[key] = s
		var summary: HistoryEvent = summaries[key]
		summary.payload["count"] = int(summary.payload["count"]) + 1
		summary.payload["last_tick"] = maxi(int(summary.payload["last_tick"]), e.tick)
		folded += 1

	for key in summaries:
		var s: HistoryEvent = summaries[key]
		s.description = "この時代に%sが%d件。" % [s.payload["of_type"], s.payload["count"]]
		kept.append(s)

	kept.sort_custom(func(a, b): return a.tick < b.tick)
	buffer = kept
	return folded
