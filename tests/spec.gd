class_name Spec
extends RefCounted

## Minimal assertion base for the headless suite.
##
## A full test framework would be more than this project needs: every check here
## is "fast-forward a seeded world, then assert an invariant over the result",
## which needs assertions, a runner and an exit code — not doubles or mocks.

var failures: Array[String] = []
var checks: int = 0
## Set by finish(). A spec that dies partway through a runtime error would
## otherwise report a clean pass for however many checks it managed first.
var completed: bool = false


func run() -> void:
	pass    # overridden


func finish() -> void:
	completed = true


func spec_name() -> String:
	return get_script().resource_path.get_file().trim_suffix(".gd")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_eq(actual, expected, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %f ± %f, got %f)" % [message, expected, tolerance, actual])


func check_gt(actual: float, floor_value: float, message: String) -> void:
	check(actual > floor_value, "%s (expected > %f, got %f)" % [message, floor_value, actual])
