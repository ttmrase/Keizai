extends Node

## Persistence, split so load time does not grow with how long the world has run.
##
## snapshot.json holds the current projection and loads in time proportional to
## how many entities exist, not how many ticks have elapsed. The chronicle lives
## in separate compressed segment files that the UI pages through lazily, plus a
## backbone file holding every lineage-critical event, which compaction never
## prunes.
##
## Save data is hand-rolled JSON rather than ResourceSaver: native resource files
## embed script paths, so renaming a script would silently break existing saves,
## and loading one can execute code. The .tres files under res://data/ are a
## different matter — they are authored content shipped with the build.

const SAVE_ROOT := "user://saves"
const SCHEMA_VERSION := 1
const AUTOSAVE_SLOT := 0

## Godot's own compressed container (deflate), not a standard gzip file — it must
## be read back through FileAccess.open_compressed with the same mode.
const SEGMENT_EXT := ".jsonl.z"


func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [SAVE_ROOT, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_dir(slot).path_join("manifest.json"))


func autosave() -> bool:
	return save_game(AUTOSAVE_SLOT)


func save_game(slot: int) -> bool:
	var dir := slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			push_error("SaveManager: cannot create %s (%d)" % [dir, err])
			return false
	var history_dir := dir.path_join("history")
	DirAccess.make_dir_recursive_absolute(history_dir)

	if not _write_json(dir.path_join("snapshot.json"), {
			"schema_version": SCHEMA_VERSION,
			"tick": SimClock.current_tick,
			"game_state": GameState.to_dict(),
			"rng": RngService.to_dict(),
		}):
		return false

	_clear_dir(history_dir)
	var segments := _write_history_segments(history_dir)
	_write_backbone(history_dir)

	if not _write_json(dir.path_join("manifest.json"), {
			"schema_version": SCHEMA_VERSION,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"world_seed": RngService.get_world_seed(),
			"tick": SimClock.current_tick,
			"year": SimClock.year(),
			"total_events_recorded": HistoryLog.total_recorded,
			"buffered_events": HistoryLog.buffer.size(),
			"backbone_events": HistoryLog.backbone.size(),
			"segments": segments,
		}):
		return false

	EventBus.save_completed.emit(slot)
	return true


func load_game(slot: int) -> bool:
	var dir := slot_dir(slot)
	var manifest := _read_json(dir.path_join("manifest.json"))
	if manifest.is_empty():
		push_warning("SaveManager: no save in slot %d" % slot)
		return false
	if int(manifest.get("schema_version", 0)) != SCHEMA_VERSION:
		push_error("SaveManager: save schema %s is not readable by this build (expected %d)"
			% [manifest.get("schema_version"), SCHEMA_VERSION])
		return false

	var snapshot := _read_json(dir.path_join("snapshot.json"))
	if snapshot.is_empty():
		return false

	SimClock.stop()
	GameState.reset()
	HistoryLog.reset()

	RngService.from_dict(snapshot.get("rng", {}))
	GameState.from_dict(snapshot.get("game_state", {}))

	var history_dir := dir.path_join("history")
	HistoryLog.buffer = _read_segments(history_dir, manifest.get("segments", []))
	HistoryLog.backbone = _read_backbone(history_dir)
	HistoryLog.total_recorded = int(manifest.get("total_events_recorded", HistoryLog.buffer.size()))

	SimClock.start(int(snapshot.get("tick", 0)))
	EventBus.game_loaded.emit()
	return true


## Folds old ordinary chronicle entries into epoch summaries. Lineage-critical
## events are excluded, so every parent/origin pointer still resolves after this.
func compact_history() -> int:
	return HistoryLog.compact(SimClock.current_tick)


func delete_save(slot: int) -> void:
	var dir := slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir):
		return
	_clear_dir(dir.path_join("history"))
	DirAccess.remove_absolute(dir.path_join("history"))
	for f in ["snapshot.json", "manifest.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# ------------------------------------------------------------------ internals

func _write_history_segments(history_dir: String) -> Array:
	var segments: Array = []
	var index := 0
	var i := 0
	while i < HistoryLog.buffer.size():
		var chunk := HistoryLog.buffer.slice(i, i + SimConfig.HISTORY_SEGMENT_EVENT_CAP)
		index += 1
		var file_name := "history_%05d%s" % [index, SEGMENT_EXT]
		if _write_events(history_dir.path_join(file_name), chunk):
			segments.append({
				"file": file_name,
				"count": chunk.size(),
				"first_tick": chunk[0].tick,
				"last_tick": chunk[chunk.size() - 1].tick,
			})
		i += SimConfig.HISTORY_SEGMENT_EVENT_CAP
	return segments


func _write_backbone(history_dir: String) -> void:
	_write_events(history_dir.path_join("backbone" + SEGMENT_EXT), HistoryLog.backbone)


func _read_backbone(history_dir: String) -> Array[HistoryEvent]:
	return _read_events(history_dir.path_join("backbone" + SEGMENT_EXT))


func _read_segments(history_dir: String, segments: Array) -> Array[HistoryEvent]:
	var out: Array[HistoryEvent] = []
	for seg in segments:
		out.append_array(_read_events(history_dir.path_join(seg.get("file", ""))))
	return out


func _write_events(path: String, events: Array) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if f == null:
		push_error("SaveManager: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	for e in events:
		f.store_line(JSON.stringify(e.to_dict()))
	f.close()
	return true


func _read_events(path: String) -> Array[HistoryEvent]:
	var out: Array[HistoryEvent] = []
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		push_error("SaveManager: cannot read %s" % path)
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(HistoryEvent.from_dict(parsed))
	f.close()
	return out


func _write_json(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
