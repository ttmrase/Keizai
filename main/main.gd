extends Control

## Entry point. Boots a world (or resumes the autosave) and shows the observation
## shell. Screens are added under ScreenHost; nothing here touches simulation
## state beyond starting it.

@onready var _screen_host: Control = $ScreenHost

const DEFAULT_SEED := 20260908


func _ready() -> void:
	ContentRegistry.ensure_loaded()
	if SaveManager.has_save(SaveManager.AUTOSAVE_SLOT):
		if not SaveManager.load_game(SaveManager.AUTOSAVE_SLOT):
			_start_new_world()
	else:
		_start_new_world()

	var shell := preload("res://ui/main/ObservationShell.tscn").instantiate()
	_screen_host.add_child(shell)


func _start_new_world() -> void:
	var world_seed := DEFAULT_SEED
	WorldGenerator.generate(world_seed)
	SimClock.start(0)
	SimClock.set_time_scale(0.0)
