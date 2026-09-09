extends Node

## Headless entry point for the invariant suite.
##
##   godot --headless --path . res://tests/TestRunner.tscn
##
## Exits non-zero if anything fails, so it works as a CI gate.

const SPEC_DIR := "res://tests/specs"


func _ready() -> void:
	var start := Time.get_ticks_msec()
	var total_checks := 0
	var failed_specs := 0
	var all_failures: Array[String] = []

	var paths := _spec_paths()
	if paths.is_empty():
		push_error("test_runner: no specs found under %s" % SPEC_DIR)
		get_tree().quit(1)
		return

	# Running one spec at a time matters once the suite takes twenty minutes:
	#   godot --headless --path . res://tests/TestRunner.tscn -- --spec=houses
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spec="):
			only = arg.split("=")[1]
	if not only.is_empty():
		var filtered: Array[String] = []
		for path in paths:
			if path.contains(only):
				filtered.append(path)
		paths = filtered

	print("running %d specs" % paths.size())
	for path in paths:
		var script: GDScript = load(path)
		if script == null:
			all_failures.append("%s: failed to load" % path)
			failed_specs += 1
			continue
		var spec: Spec = script.new()
		spec.run()
		total_checks += spec.checks
		if not spec.completed:
			spec.failures.append("spec did not reach finish() — it aborted partway through")
		if spec.failures.is_empty():
			print("  PASS  %-34s %d checks" % [spec.spec_name(), spec.checks])
		else:
			failed_specs += 1
			print("  FAIL  %-34s %d checks, %d failures"
				% [spec.spec_name(), spec.checks, spec.failures.size()])
			for f in spec.failures:
				print("          - %s" % f)
				all_failures.append("%s: %s" % [spec.spec_name(), f])

	var elapsed := Time.get_ticks_msec() - start
	print("\n%d checks in %d specs, %d failing specs (%.1fs)"
		% [total_checks, paths.size(), failed_specs, elapsed / 1000.0])
	get_tree().quit(1 if failed_specs > 0 else 0)


func _spec_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SPEC_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var clean := name.trim_suffix(".remap")
			if clean.ends_with(".gd"):
				out.append(SPEC_DIR.path_join(clean))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
