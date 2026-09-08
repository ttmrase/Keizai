extends Spec

## Save, reload, and confirm the world came back exactly as it was — including
## the chronicle and the RNG position, so a loaded game continues its own history
## rather than starting a new one.

const SLOT := 9


func run() -> void:
	SimTestHarness.eventful_world(31337, 1500)

	var before_state := GameState.to_dict()
	var before_tick := SimClock.current_tick
	var before_events := HistoryLog.buffer.size()
	var before_backbone := HistoryLog.backbone.size()
	var before_orgs := GameState.organizations.size()
	var before_people := GameState.people.size()

	check(SaveManager.save_game(SLOT), "saving should succeed")
	check(SaveManager.has_save(SLOT), "the slot should report a save present")

	# Wipe the world completely, so a successful reload cannot be a leftover.
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading should succeed")

	check_eq(SimClock.current_tick, before_tick, "tick should be restored")
	check_eq(GameState.organizations.size(), before_orgs, "organization count should be restored")
	check_eq(GameState.people.size(), before_people, "person count should be restored")
	check_eq(HistoryLog.buffer.size(), before_events, "chronicle length should be restored")
	check_eq(HistoryLog.backbone.size(), before_backbone, "backbone length should be restored")

	var after_state := GameState.to_dict()
	_compare(before_state, after_state, "game_state")

	# Lineage must survive the round trip, not just the field values.
	for id in GameState.organizations:
		check(GenealogyValidator.traces_to_root(id),
			"%s should still trace to its root after loading" % id)

	SaveManager.delete_save(SLOT)
	finish()


func _compare(a: Dictionary, b: Dictionary, path: String) -> void:
	for key in a:
		var full := "%s.%s" % [path, key]
		if not b.has(key):
			check(false, "%s missing after reload" % full)
			continue
		var av = a[key]
		var bv = b[key]
		if av is Dictionary:
			_compare(av, bv, full)
		elif av is float:
			check_near(bv, av, 0.0001, "%s should survive the round trip" % full)
		elif av is Array:
			check_eq(bv.size(), av.size(), "%s length should survive the round trip" % full)
		else:
			check_eq(bv, av, "%s should survive the round trip" % full)
