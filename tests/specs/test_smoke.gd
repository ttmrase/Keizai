extends Spec

## Proves the world boots: content loads, roots exist, ticks advance.

func run() -> void:
	ContentRegistry.reload()
	check(ContentRegistry.get_power_profile(&"founders_guild") != null,
		"founders_guild power profile should load from res://data/power_profiles")

	SimTestHarness.fresh_world(1234)
	check_eq(GameState.world.settlements.size(), WorldGenerator.SETTLEMENT_COUNT,
		"world generation should create the configured number of settlements")

	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.HOUSE,
			Organization.OrgKind.FACTION, Organization.OrgKind.POLITICAL_SYSTEM]:
		var roots := 0
		for org in GameState.organizations_of_kind(kind):
			if org.is_root():
				roots += 1
		check_eq(roots, 1, "exactly one root organization of kind %d at world start" % kind)

	check_gt(float(GameState.people.size()), 4.0, "founding generation should exist")

	var before := SimClock.current_tick
	SimTestHarness.advance(40)
	check_eq(SimClock.current_tick, before + 40, "instant advance should move the clock")
	check_gt(GameState.world.global_population, 0.0, "population should be positive")
	finish()
