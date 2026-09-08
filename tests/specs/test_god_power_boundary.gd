extends Spec

## The player shapes the environment and nothing else. This checks that
## structurally rather than by inspection: no screen may write simulation state,
## and no god power may accept a political target.

const UI_DIR := "res://ui"

## Writes that would let the interface reach past the boundary and set an outcome
## directly instead of letting the simulation reach it.
const FORBIDDEN := [
	"HistoryLog.record(",
	"HistoryLog.emit_event(",
	".leader_person_id =",
	".power_score =",
	".member_count =",
	".legitimacy =",
	".ideology.",
	"GameState.apply(",
	"RulesEngine.",
	"SchismResolver.",
	"SuccessionResolver.",
]

## Anything on GodPowerAPI naming one of these would be a way to command society
## directly rather than to change the world it lives in.
const FORBIDDEN_API_TERMS := [
	"org", "organization", "leader", "person", "power", "ideology", "faction",
	"guild", "house", "schism", "succession",
]


func run() -> void:
	_check_ui_never_writes_simulation_state()
	_check_god_powers_take_no_political_target()
	finish()


func _check_ui_never_writes_simulation_state() -> void:
	var scripts := _gd_files(UI_DIR)
	check_gt(float(scripts.size()), 0.0, "there should be UI scripts to scan")
	for path in scripts:
		var text := FileAccess.get_file_as_string(path)
		for needle in FORBIDDEN:
			check(not text.contains(needle),
				"%s contains '%s' — screens must not write simulation state" % [path, needle])


func _check_god_powers_take_no_political_target() -> void:
	var source := FileAccess.get_file_as_string("res://autoload/god_power_api.gd")
	check(not source.is_empty(), "god_power_api.gd should be readable")

	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("func ") or trimmed.begins_with("func _"):
			continue
		var signature := trimmed.to_lower()
		var params := signature.substr(signature.find("("))
		for term in FORBIDDEN_API_TERMS:
			check(not params.contains(term),
				"god power '%s' takes a political parameter mentioning '%s'" % [trimmed, term])


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.trim_suffix(".remap").ends_with(".gd"):
			out.append(full.trim_suffix(".remap"))
		name = dir.get_next()
	dir.list_dir_end()
	return out
