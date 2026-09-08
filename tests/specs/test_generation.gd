extends Spec

## Names and ideologies are assembled from composable parts rather than picked
## from a fixed list of regime types, so this checks the assembly rather than any
## particular output.

func run() -> void:
	_check_names_are_never_blank()
	_check_axes_compose_into_a_name()
	_check_branch_ideology_is_independent()
	_check_names_stay_distinct()
	_check_ideology_drifts_with_the_world()
	finish()


func _check_names_are_never_blank() -> void:
	for world_seed in [1, 77, 4096, 90210]:
		SimTestHarness.fresh_world(world_seed)
		for org in GameState.active_organizations():
			check(not org.display_name.strip_edges().is_empty(),
				"seed %d produced an organization with no name" % world_seed)
			check(not org.display_name.contains("{"),
				"%s has an unresolved naming slot" % org.display_name)
			check(not org.description.contains("{"),
				"%s has an unresolved slot in its description" % org.display_name)


func _check_axes_compose_into_a_name() -> void:
	SimTestHarness.fresh_world(555)
	var polity := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	polity.ideology.decision_structure = PoliticalSystemAxes.DecisionStructure.AUTOCRATIC
	polity.ideology.set_axis(&"tradition_reform", -0.8)
	polity.ideology.set_axis(&"militarism_pacifism", 0.7)
	polity.ideology.set_axis(&"isolationism_commerce", -0.6)

	var named := PoliticalSystemGenerator.name_and_describe(polity)
	check(named["display_name"].contains("世襲"), "a hereditary basis should show in the name")
	check(named["display_name"].contains("専制"), "an autocratic structure should show in the name")
	check(named["display_name"].contains("守旧"), "a strongly traditionalist axis should colour the name")
	check(named["description"].contains("軍国主義"), "a militarist axis should be listed")
	check(named["description"].contains("鎖国"), "an isolationist axis should be listed")

	# Changing one axis must change the description, or the axes are decorative.
	polity.ideology.set_axis(&"militarism_pacifism", -0.7)
	var pacific := PoliticalSystemGenerator.name_and_describe(polity)
	check(pacific["description"].contains("平和主義"),
		"flipping the militarism axis should flip how it is described")


func _check_branch_ideology_is_independent() -> void:
	SimTestHarness.fresh_world(556)
	var parent := GameState.root_of_kind(Organization.OrgKind.GUILD)
	var branch_axes := PoliticalSystemGenerator.generate_branch_axes(parent,
		{"tradition_reform": 0.6})
	var parent_before := parent.ideology.get_axis(&"tradition_reform")

	branch_axes.set_axis(&"tradition_reform", 1.0)
	check_near(parent.ideology.get_axis(&"tradition_reform"), parent_before, 0.0001,
		"editing a branch's ideology must not reach back into its parent's")


func _check_names_stay_distinct() -> void:
	SimTestHarness.eventful_world(557, 3500)
	var seen := {}
	for org in GameState.organizations.values():
		check(not seen.has(org.display_name),
			"two organizations are both called '%s'" % org.display_name)
		seen[org.display_name] = true


func _check_ideology_drifts_with_the_world() -> void:
	SimTestHarness.fresh_world(558)
	var polity := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	polity.ideology.set_axis(&"militarism_pacifism", -0.8)
	var before := polity.ideology.get_axis(&"militarism_pacifism")

	GodPowerAPI.set_monster_spawn_rate(3.0)
	SimTestHarness.advance(1200)

	check_gt(polity.ideology.get_axis(&"militarism_pacifism") - before, 0.15,
		"a world full of monsters should push a regime toward militarism over time")
