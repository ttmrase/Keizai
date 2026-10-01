class_name UiSettings
extends RefCounted

## The handful of things the reader decides about how the screens behave, kept
## between sessions. Nothing here touches the world: it is how the window onto it
## is arranged.

const PATH := "user://ui_settings.cfg"

static var _config: ConfigFile


static func _load() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(PATH)
	return _config


static func get_value(key: String, fallback: Variant) -> Variant:
	return _load().get_value("ui", key, fallback)


static func set_value(key: String, value: Variant) -> void:
	_load().set_value("ui", key, value)
	_config.save(PATH)


## Whether the clock stops when something history will remember happens, so it
## is not missed at four times speed.
static func auto_pause() -> bool:
	return bool(get_value("auto_pause", true))


static func set_auto_pause(on: bool) -> void:
	set_value("auto_pause", on)
