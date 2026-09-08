class_name ContentRegistry
extends RefCounted

## Loads everything authored as .tres content under res://data/ and indexes it by
## id. Content is immutable at runtime, so it is cached once per process.
##
## Everything a designer can add without touching engine code goes through here:
## disasters, power profiles, naming templates and trigger rules.

const DISASTER_DIR := "res://data/disasters"
const POWER_PROFILE_DIR := "res://data/power_profiles"
const NAME_TEMPLATE_DIR := "res://data/name_templates"
const RULE_DIR := "res://data/rules"

static var _disasters: Dictionary[StringName, DisasterDefinition] = {}
static var _power_profiles: Dictionary[StringName, PowerProfile] = {}
static var _name_templates: Array[NameTemplate] = []
static var _rules: Array[TriggerRule] = []
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for res in _load_dir(DISASTER_DIR):
		var d := res as DisasterDefinition
		if d != null:
			_disasters[d.definition_id] = d
	for res in _load_dir(POWER_PROFILE_DIR):
		var p := res as PowerProfile
		if p != null:
			_power_profiles[p.archetype_id] = p
	for res in _load_dir(NAME_TEMPLATE_DIR):
		var t := res as NameTemplate
		if t != null:
			_name_templates.append(t)
	for res in _load_dir(RULE_DIR):
		var r := res as TriggerRule
		if r != null:
			_rules.append(r)
	_rules.sort_custom(func(a, b): return a.priority > b.priority)


static func reload() -> void:
	_disasters.clear()
	_power_profiles.clear()
	_name_templates.clear()
	_rules.clear()
	_loaded = false
	ensure_loaded()


static func get_disaster(id: StringName) -> DisasterDefinition:
	ensure_loaded()
	return _disasters.get(id)


static func all_disasters() -> Array[DisasterDefinition]:
	ensure_loaded()
	var out: Array[DisasterDefinition] = []
	for k in _disasters:
		out.append(_disasters[k])
	out.sort_custom(func(a, b): return String(a.definition_id) < String(b.definition_id))
	return out


static func get_power_profile(archetype_id: StringName) -> PowerProfile:
	ensure_loaded()
	return _power_profiles.get(archetype_id)


static func has_power_profile(archetype_id: StringName) -> bool:
	ensure_loaded()
	return _power_profiles.has(archetype_id)


static func name_templates() -> Array[NameTemplate]:
	ensure_loaded()
	return _name_templates


static func rules() -> Array[TriggerRule]:
	ensure_loaded()
	return _rules


static func _load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ContentRegistry: missing content directory %s" % path)
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# Exported builds rename .tres to .remap; load() wants the original path.
			var clean := file_name.trim_suffix(".remap")
			if clean.ends_with(".tres") or clean.ends_with(".res"):
				var res := ResourceLoader.load(path.path_join(clean))
				if res != null:
					out.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out
