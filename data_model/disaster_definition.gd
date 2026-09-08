class_name DisasterDefinition
extends Resource

## Authored content describing what a disaster (or blessing) does to the world.
## Adding a new one is a new .tres file under res://data/disasters/ — no code.
##
## `effects` maps a world modifier key to its strength at full intensity:
##   harvest / ore / wood / monster_spawn / mortality  — multiplicative, so
##       -0.6 means "60% worse at peak", +0.8 means "80% better at peak"
##   monster_influx — additive monsters per tick
## Every key lands on WorldState or SettlementState only; a disaster can never
## touch an organization, a leader, or an ideology directly.

enum Envelope { PLATEAU, SPIKE, RAMP }

@export var definition_id: StringName = &""
@export var display_name: String = ""
@export var duration_ticks: int = 24
@export var effects: Dictionary = {}
@export var envelope: Envelope = Envelope.PLATEAU
## Optional hand-authored intensity shape. When set it overrides `envelope`.
@export var intensity_curve: Curve
@export var chronicle_template: String = "{name} strikes {place}."
@export var is_benevolent: bool = false
## Whether the player must pick a target settlement, or it applies world-wide.
@export var targeted: bool = true


## Intensity at 0..1 progress through the disaster's life.
func intensity_at(progress: float) -> float:
	if intensity_curve != null:
		return clampf(intensity_curve.sample(clampf(progress, 0.0, 1.0)), 0.0, 4.0)
	match envelope:
		Envelope.SPIKE:
			# Hits hard immediately, fades fast.
			return maxf(0.0, 1.0 - progress * progress * 1.6)
		Envelope.RAMP:
			return clampf(progress, 0.0, 1.0)
		_:
			# Short onset, sustained middle, short recovery.
			if progress < 0.15:
				return progress / 0.15
			if progress > 0.8:
				return maxf(0.0, (1.0 - progress) / 0.2)
			return 1.0
