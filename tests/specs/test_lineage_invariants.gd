extends Spec

## The promise the whole design exists to keep: however far the civilization
## fragments, every institution traces back to the single root of its kind, and
## every person's ancestry terminates at the founding generation.

const TICKS := 12000


func run() -> void:
	SimTestHarness.eventful_world(90210, TICKS)

	_check_single_root_per_kind()
	_check_org_chains_terminate()
	_check_branch_depth_consistent()
	_check_ancestry_terminates()
	_check_parent_child_symmetry()
	_check_referential_integrity()
	_check_power_bounds()

	# A run this long should actually have produced upheaval, otherwise the
	# invariants above are passing over a world where nothing ever happened.
	check_gt(float(GameState.organizations.size()), 6.0,
		"a %d-tick eventful world should have produced branch organizations" % TICKS)
	finish()


func _check_single_root_per_kind() -> void:
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.HOUSE,
			Organization.OrgKind.FACTION, Organization.OrgKind.POLITICAL_SYSTEM]:
		var roots: Array[StringName] = []
		for org in GameState.organizations.values():
			if org.kind == kind and org.is_root():
				roots.append(org.org_id)
		check_eq(roots.size(), 1,
			"kind %d must have exactly one root organization, found %s" % [kind, roots])


func _check_org_chains_terminate() -> void:
	var roots_reached := {}
	for org in GameState.organizations.values():
		var chain := GenealogyValidator.org_lineage(org.org_id)
		check(not chain.is_empty(),
			"%s must have a lineage terminating at a root (cycle or dangling parent)"
				% org.display_name)
		if chain.is_empty():
			continue
		var root := chain[chain.size() - 1]
		check_eq(root.kind, org.kind, "%s must trace to a root of its own kind" % org.display_name)
		roots_reached["%d" % org.kind] = root.org_id
	# Dissolved organizations are still part of the record and must still resolve.
	for org in GameState.organizations.values():
		if not org.is_active():
			check(GenealogyValidator.traces_to_root(org.org_id),
				"dissolved %s must still trace to its root" % org.display_name)


func _check_branch_depth_consistent() -> void:
	for org in GameState.organizations.values():
		var chain := GenealogyValidator.org_lineage(org.org_id)
		if chain.is_empty():
			continue
		check_eq(org.branch_depth, chain.size() - 1,
			"%s branch_depth should equal its distance from the root" % org.display_name)


func _check_ancestry_terminates() -> void:
	var failures := GenealogyValidator.ancestry_failures()
	# str() first: formatting an empty array against one placeholder is an error.
	check_eq(failures.size(), 0,
		"every person's ancestry must terminate at a founder without cycles (%s)"
			% str(failures.slice(0, 5)))

	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		check(p.father_id != p.person_id and p.mother_id != p.person_id,
			"%s must not be their own parent" % p.full_name)


func _check_parent_child_symmetry() -> void:
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		for parent_id in [p.father_id, p.mother_id]:
			if parent_id == &"":
				continue
			var parent: NotableIndividual = GameState.people.get(parent_id)
			check(parent != null, "%s references a parent that does not exist" % p.full_name)
			if parent != null:
				check(parent.children_ids.has(p.person_id),
					"%s is not listed among %s's children" % [p.full_name, parent.full_name])


## Compaction must never drop an event another record still points at.
func _check_referential_integrity() -> void:
	var known := {}
	for e in HistoryLog.backbone:
		known[e.event_id] = true
	for e in HistoryLog.buffer:
		known[e.event_id] = true

	for org in GameState.organizations.values():
		check(org.origin_event_id == &"" or known.has(org.origin_event_id),
			"%s origin event %s is missing from the record"
				% [org.display_name, org.origin_event_id])
		if org.parent_org_id != &"":
			check(GameState.organizations.has(org.parent_org_id),
				"%s points at a parent that no longer exists" % org.display_name)


func _check_power_bounds() -> void:
	for org in GameState.organizations.values():
		if not org.is_active():
			continue
		var profile := ContentRegistry.get_power_profile(org.archetype_id)
		if profile == null:
			continue
		check(org.power_score >= 0.0 and org.power_score <= profile.max_score,
			"%s power %.2f is outside [0, %.0f]"
				% [org.display_name, org.power_score, profile.max_score])
		var sum := 0.0
		for key in org.power_drivers:
			sum += org.power_drivers[key]
		# They agree unless the score was clamped, in which case the sum is higher.
		check(sum >= org.power_score - 0.01,
			"%s driver contributions (%.2f) should account for its score (%.2f)"
				% [org.display_name, sum, org.power_score])
