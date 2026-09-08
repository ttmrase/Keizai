extends Spec

## The same seed must produce the same history. Without this, a bug reported from
## a save is unreproducible, and the named RNG streams stop being worth having.

func run() -> void:
	var first := _run_world(6502, 1200)
	var second := _run_world(6502, 1200)
	check_eq(second["signature"], first["signature"],
		"identical seeds should produce an identical world")
	check_eq(second["chronicle"], first["chronicle"],
		"identical seeds should produce an identical chronicle")

	var different := _run_world(6503, 1200)
	check(different["signature"] != first["signature"],
		"a different seed should produce a different world")
	finish()


func _run_world(world_seed: int, ticks: int) -> Dictionary:
	SimTestHarness.fresh_world(world_seed)
	SimTestHarness.advance(ticks)

	# Sort the rendered lines, not the ids: sorting an Array[StringName] orders by
	# pointer identity, which varies between runs even when the data does not.
	var parts: Array[String] = []
	for id in GameState.organizations:
		var org: Organization = GameState.organizations[id]
		parts.append("%s|%s|%s|%d|%.4f" % [org.org_id, org.display_name,
			org.parent_org_id, org.member_count, org.power_score])
	parts.sort()

	var chronicle: Array[String] = []
	for e in HistoryLog.backbone:
		chronicle.append("%d:%s:%s" % [e.tick, e.type_name(), e.description])

	return {
		"signature": "\n".join(parts),
		"chronicle": "\n".join(chronicle),
	}
