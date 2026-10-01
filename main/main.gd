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
	shell.new_world_requested.connect(_on_new_world_requested)
	_screen_host.add_child(shell)

	# The title sits over the shell until the reader chooses; whichever they
	# choose, the clock starts when it lifts, because this is a game that is
	# watched running. The shell is hidden beneath it meanwhile, so the phone
	# is not painting two maps where one is seen.
	var title := TitleScreen.new()
	shell.visible = false
	title.new_world_requested.connect(_on_new_world_requested)
	title.leaving.connect(func(): shell.visible = true)
	title.dismissed.connect(func(): SimClock.set_time_scale(1.0))
	_screen_host.add_child(title)


## World creation lives here rather than in a screen: the UI may ask for a new
## world, but it does not get to build one.
func _on_new_world_requested() -> void:
	_start_new_world(randi())


func _start_new_world(world_seed: int = DEFAULT_SEED) -> void:
	WorldGenerator.generate(world_seed)
	SimClock.start(0)
	SimClock.set_time_scale(0.0)
