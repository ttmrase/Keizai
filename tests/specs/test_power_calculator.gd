extends Spec

## Power must react to world conditions, selectively. The point of the design is
## that "monsters are common, so the hunters gain influence" is one instance of a
## general rule — so raising one world variable must move exactly the
## organizations that declared a dependence on it, and leave the rest alone.

func run() -> void:
	_check_hand_computed_score()
	_check_selective_reaction()
	_check_new_archetype_needs_no_code()
	finish()


func _check_hand_computed_score() -> void:
	var profile := PowerProfile.new()
	profile.archetype_id = &"test_archetype"
	profile.base_score = 10.0
	profile.max_score = 100.0
	profile.membership_weight = 0.0
	var driver := PowerDriver.new()
	driver.world_var_path = &"global_monster_threat_level"
	driver.weight = 40.0
	driver.expected_max = 0.8
	profile.drivers = [driver]

	SimTestHarness.fresh_world(11)
	GameState.world.global_monster_threat_level = 0.4

	var org := Organization.new()
	org.org_id = &"test_org"
	org.archetype_id = &"test_archetype"
	# 0.4 / 0.8 = 0.5 normalized, times weight 40 = 20, plus base 10.
	# Leadership contributes -3 for a vacant seat.
	check_near(PowerCalculator.calculate(org, profile), 27.0, 0.001,
		"score should be base + normalized driver + vacant-seat penalty")

	GameState.world.global_monster_threat_level = 5.0
	check_near(PowerCalculator.calculate(org, profile), 47.0, 0.001,
		"a driver reading above expected_max should clamp, not run away")


func _check_selective_reaction() -> void:
	SimTestHarness.fresh_world(12)
	# Give the world one organization of every archetype so each profile is live.
	var samples := {}
	for archetype in [&"monster_hunters_guild", &"merchants_guild", &"farmers_faction"]:
		var org := Organization.new()
		org.org_id = StringName("probe_" + String(archetype))
		org.archetype_id = archetype
		org.member_count = 100
		samples[archetype] = org

	var baseline := {}
	for archetype in samples:
		baseline[archetype] = PowerCalculator.calculate(samples[archetype],
			ContentRegistry.get_power_profile(archetype))

	GameState.world.global_monster_threat_level = 0.7

	var after := {}
	for archetype in samples:
		after[archetype] = PowerCalculator.calculate(samples[archetype],
			ContentRegistry.get_power_profile(archetype))

	check_gt(after[&"monster_hunters_guild"] - baseline[&"monster_hunters_guild"], 10.0,
		"monster threat should raise the hunters' influence")
	check_near(after[&"merchants_guild"], baseline[&"merchants_guild"], 0.001,
		"monster threat must not move an archetype that never declared it")
	check_near(after[&"farmers_faction"], baseline[&"farmers_faction"], 0.001,
		"monster threat must not move the farmers either")


## The extensibility claim, checked directly: a profile built at runtime against
## an existing world variable scores correctly with no engine change.
func _check_new_archetype_needs_no_code() -> void:
	SimTestHarness.fresh_world(13)
	GameState.world.global_wood = 3000.0

	var profile := PowerProfile.new()
	profile.archetype_id = &"foresters_guild"
	profile.base_score = 0.0
	profile.max_score = 100.0
	profile.membership_weight = 0.0
	var driver := PowerDriver.new()
	driver.world_var_path = &"global_wood"
	driver.weight = 50.0
	driver.expected_max = 6000.0
	profile.drivers = [driver]

	var org := Organization.new()
	org.org_id = &"foresters"
	org.archetype_id = &"foresters_guild"
	var score := PowerCalculator.calculate(org, profile)
	check_near(score, 22.0, 0.001,
		"a brand-new archetype should score from data alone (3000/6000 * 50 - 3 vacant)")
	check(org.power_drivers.has(&"global_wood"),
		"the driver breakdown should name the world variable responsible")
