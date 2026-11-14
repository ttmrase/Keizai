extends Control

## Entry point. Boots a world (or resumes the autosave) and shows the observation
## shell. Screens are added under ScreenHost; nothing here touches simulation
## state beyond starting it.
##
## It also keeps the game clear of the phone's own furniture: the game draws to
## the whole window, and this is where the status strip, the screens and the
## dock are held inside the part of it a finger can reach (see SafeArea).

@onready var _screen_host: Control = $ScreenHost

const DEFAULT_SEED := 20260908
## How often the device is asked again where its bars are. They move when the
## bars are hidden or shown, and the first answer can come before the window
## has settled.
const SAFE_POLL_SECONDS := 1.0

var _margins := Vector4(-1, -1, -1, -1)
var _since_poll := 0.0
var _title: TitleScreen


func _ready() -> void:
	ContentRegistry.ensure_loaded()
	if SaveManager.has_save(SaveManager.AUTOSAVE_SLOT):
		if not SaveManager.load_game(SaveManager.AUTOSAVE_SLOT):
			_start_new_world()
	else:
		_start_new_world()

	SafeArea.apply_display_mode()

	var shell := preload("res://ui/main/ObservationShell.tscn").instantiate()
	shell.new_world_requested.connect(_on_new_world_requested)
	shell.display_changed.connect(_on_display_changed)
	_screen_host.add_child(shell)

	# The title sits over the shell until the reader chooses; whichever they
	# choose, the clock starts when it lifts, because this is a game that is
	# watched running. The shell is hidden beneath it meanwhile, so the phone
	# is not painting two maps where one is seen. The title is not held inside
	# the margins: its map runs under the bars, and it keeps its own words clear.
	_title = TitleScreen.new()
	shell.visible = false
	_title.new_world_requested.connect(_on_new_world_requested)
	_title.leaving.connect(func(): shell.visible = true)
	_title.dismissed.connect(func(): SimClock.set_time_scale(1.0))
	add_child(_title)
	_apply_safe_area()


func _process(delta: float) -> void:
	_since_poll += delta
	if _since_poll >= SAFE_POLL_SECONDS:
		_since_poll = 0.0
		_apply_safe_area()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_RESIZED:
		_since_poll = SAFE_POLL_SECONDS


## The reader changed how the screen is arranged, from the settings.
func _on_display_changed() -> void:
	SafeArea.apply_display_mode()
	_apply_safe_area()
	# Hiding or showing the bars takes the system a moment; look again soon.
	_since_poll = SAFE_POLL_SECONDS - 0.3


func _apply_safe_area() -> void:
	if _screen_host == null:
		return
	var margins := SafeArea.margins(get_viewport())
	if margins == _margins:
		return
	_margins = margins
	SafeArea.inset(_screen_host, margins)
	if is_instance_valid(_title):
		_title.set_safe_margins(margins)
	queue_redraw()


## What shows under the phone's bars: the status strip's own colour above and
## the dock's below, so the bars sit on the game rather than on a black band.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	if _margins.y > 0.0:
		draw_rect(Rect2(0, 0, size.x, _margins.y), Palette.PANEL)
	if _margins.w > 0.0:
		draw_rect(Rect2(0, size.y - _margins.w, size.x, _margins.w), Palette.PANEL)


## World creation lives here rather than in a screen: the UI may ask for a new
## world, but it does not get to build one.
func _on_new_world_requested() -> void:
	_start_new_world(randi())


func _start_new_world(world_seed: int = DEFAULT_SEED) -> void:
	WorldGenerator.generate(world_seed)
	SimClock.start(0)
	SimClock.set_time_scale(0.0)
