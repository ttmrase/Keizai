class_name PowerDriver
extends Resource

## One reason an organization has influence: a world variable, how strongly it
## counts, and optionally how to remap it.

@export var world_var_path: StringName = &""
@export var weight: float = 1.0
## Optional non-linear remap (diminishing returns, thresholds). Sampled with the
## raw value normalized into 0..1 by `expected_max` first.
@export var curve: Curve
## The raw value treated as "1.0" when normalizing. Values above it clamp.
@export var expected_max: float = 1.0
## Inverts the reading, for drivers that gain from scarcity rather than plenty
## (a farmers' faction organizes when the harvest fails, not when it thrives).
@export var invert: bool = false
## Shown in the power dashboard so a player can read why someone is powerful.
@export var label: String = ""


func evaluate(raw: float) -> float:
	var normalized := clampf(raw / maxf(0.0001, expected_max), 0.0, 1.0)
	if invert:
		normalized = 1.0 - normalized
	if curve != null:
		normalized = clampf(curve.sample(normalized), 0.0, 1.0)
	return normalized * weight
