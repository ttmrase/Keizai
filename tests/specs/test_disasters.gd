extends Spec

## Disasters must actually bite, expire on schedule, and reach the political
## layer only indirectly — by changing conditions others react to.

func run() -> void:
	_check_drought_applies_and_expires()
	_check_disaster_is_chronicled()
	_check_calamity_lifts_the_temple()
	finish()


func _check_drought_applies_and_expires() -> void:
	SimTestHarness.fresh_world(2024)
	SimTestHarness.advance(80)
	var normal := GameState.world.global_harvest_modifier

	var def := ContentRegistry.get_disaster(&"drought")
	check(def != null, "the drought definition should load")
	GodPowerAPI.trigger_disaster(&"drought", &"", 1.0)
	SimTestHarness.advance(int(def.duration_ticks * 0.5))
	check(GameState.world.global_harvest_modifier < normal * 0.75,
		"a drought at full intensity should sharply cut the harvest")

	SimTestHarness.advance(def.duration_ticks)
	check_eq(GameState.world.active_disasters.size(), 0,
		"the drought should have expired once its duration elapsed")
	check_near(GameState.world.global_harvest_modifier, normal, 0.001,
		"the harvest should recover once the drought passes")


func _check_disaster_is_chronicled() -> void:
	SimTestHarness.fresh_world(2025)
	var before := HistoryLog.total_recorded
	GodPowerAPI.trigger_disaster(&"plague", &"", 1.0)
	check_eq(HistoryLog.total_recorded, before + 1, "a disaster should record one event")

	var recent := HistoryLog.recent(1)
	check_eq(recent[0].event_type, HistoryEvent.EventType.DISASTER_OCCURRED,
		"the recorded event should be a disaster")
	check(not recent[0].description.is_empty(),
		"the chronicle entry should have readable text, not a blank line")

	check(GodPowerAPI.trigger_disaster(&"no_such_disaster", &"", 1.0) == null,
		"an unknown disaster id should be refused rather than half-applied")


## The thematic through-line: calling down disasters as a god is what makes the
## temple faction matter. Verified through the public API only.
func _check_calamity_lifts_the_temple() -> void:
	SimTestHarness.fresh_world(2026)
	var temple := Organization.new()
	temple.org_id = &"probe_temple"
	temple.archetype_id = &"temple_faction"
	temple.member_count = 120
	var profile := ContentRegistry.get_power_profile(&"temple_faction")
	var quiet := PowerCalculator.calculate(temple, profile)

	for i in 3:
		GodPowerAPI.trigger_disaster(&"drought", &"", 1.0)
		SimTestHarness.advance(30)
	var troubled := PowerCalculator.calculate(temple, profile)

	check_gt(troubled - quiet, 3.0,
		"repeated calamity should raise the temple faction's influence")
