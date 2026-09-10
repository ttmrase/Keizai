extends Node

## Drives simulation time from wall-clock seconds, independent of frame rate.
##
## Uses _process with its own accumulator rather than _physics_process, and
## never touches get_tree().paused — so a paused world still has a fully
## interactive UI, which matters in a game where pausing is how you read the
## chronicle and the family trees.

var seconds_per_tick: float = SimConfig.DEFAULT_SECONDS_PER_TICK
var time_scale: float = 0.0        # 0 = paused
var current_tick: int = 0
var running: bool = false

var _accumulator: float = 0.0

const SPEED_STEPS: Array[float] = [0.0, 1.0, 2.0, 4.0]


func _process(delta: float) -> void:
	if not running or time_scale <= 0.0:
		return
	_accumulator += delta * time_scale
	var steps := 0
	while _accumulator >= seconds_per_tick and steps < SimConfig.MAX_TICKS_PER_FRAME:
		_accumulator -= seconds_per_tick
		_advance_one_tick()
		steps += 1
	if steps >= SimConfig.MAX_TICKS_PER_FRAME:
		# Too far behind to catch up; drop the backlog rather than compounding it.
		_accumulator = 0.0


func _advance_one_tick() -> void:
	current_tick += 1
	GameState.step_resources(current_tick)
	Demography.step(current_tick)
	if current_tick % SimConfig.POWER_RECALC_EPOCH_TICKS == 0:
		PowerCalculator.recalculate_all(current_tick)
		# Standing decides the rest, in the order the answers depend on each
		# other: what each family's name is worth, which guild matters where,
		# who stands behind whom and how that divides the chamber, whether the
		# chamber is now strong enough to overturn the regime, and what form of
		# government the whole arrangement adds up to afterwards.
		Religion.refresh_all(current_tick)
		HouseRank.refresh_all(current_tick)
		# Before the land is reassigned, not after: a county whose family has died
		# out is first claim of the households that were serving there, and only
		# what nobody claims falls to whichever great house is nearest. The other
		# order funnels every vacancy to the strongest survivor until one family
		# holds the entire country and the nobility is a single name.
		Retainers.refresh_all(current_tick)
		RegionalStanding.refresh_all(current_tick)
		SocialTies.refresh_all(current_tick)
		RegimeShift.consider_all(current_tick)
		PolityFormEvaluator.refresh_all(current_tick)
		HouseRelations.refresh_all(current_tick)
		# Precedence is granted last, once the standings it responds to are
		# current: the crown answers this season's friends and enemies, not the
		# ones it had before the chamber moved.
		Honours.consider_all(current_tick)
		HouseCharacter.refresh_all(current_tick)
		EventBus.power_recalculated.emit(current_tick)
	if current_tick % SimConfig.IDEOLOGY_DRIFT_EPOCH_TICKS == 0:
		PoliticalSystemGenerator.drift_all(current_tick)
	# Ruptures are considered after everything that could have caused one has been
	# read for this season, and before the rules that react to the world it leaves.
	Incidents.consider_all(current_tick)
	HousePartition.step(current_tick)
	RulesEngine.evaluate_tick(current_tick)
	EventBus.tick_advanced.emit(current_tick)


## Fast-forwards without waiting for real time. Used by the headless invariant
## suite and the debug panel; never by normal play.
func advance_n_ticks_instant(n: int) -> void:
	for i in n:
		_advance_one_tick()


func set_time_scale(scale: float) -> void:
	time_scale = maxf(0.0, scale)
	_accumulator = 0.0
	EventBus.speed_changed.emit(time_scale)


func toggle_pause() -> void:
	set_time_scale(0.0 if time_scale > 0.0 else 1.0)


func is_paused() -> bool:
	return time_scale <= 0.0


func start(at_tick: int = 0) -> void:
	current_tick = at_tick
	_accumulator = 0.0
	running = true


func stop() -> void:
	running = false
	time_scale = 0.0


func year() -> int:
	return int(current_tick / SimConfig.TICKS_PER_YEAR)


## Formats a tick as an in-world date for the chronicle.
func format_tick(tick: int) -> String:
	var seasons := ["春", "夏", "秋", "冬"]
	var y := int(tick / SimConfig.TICKS_PER_YEAR)
	var s: int = tick % SimConfig.TICKS_PER_YEAR
	return "%d年%s" % [y, seasons[s]]


func _notification(what: int) -> void:
	match what:
		# Android can kill a backgrounded app without any graceful-quit signal, so
		# the pause notification is the last reliable moment to persist progress.
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			if running:
				SaveManager.autosave()
		NOTIFICATION_APPLICATION_RESUMED:
			# The world does not run while the app is backgrounded. Clearing the
			# accumulator stops the time spent away from arriving as a burst of
			# ticks the moment the player comes back.
			_accumulator = 0.0
