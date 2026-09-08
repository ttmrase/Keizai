class_name RuleCondition
extends Resource

## One test against the world or against the organization being evaluated.
## Paths are resolved by WorldStateQuery, so a condition can read a global
## resource, a governed settlement's average, or a field on the org itself.

enum Op {
	GREATER_THAN,
	LESS_THAN,
	BETWEEN,
	DRIFTED_FROM_BASELINE,   # |current - founding baseline| > threshold
}

@export var world_var_path: StringName = &""
@export var op: Op = Op.GREATER_THAN
@export var threshold: float = 0.0
@export var threshold_high: float = 1.0
## Human-readable reason, surfaced in the chronicle when the rule fires.
@export var describe_as: String = ""
