class_name PowerProfile
extends Resource

## Declares what makes one archetype powerful. This is the whole extensibility
## mechanism: a new guild or faction archetype is a new .tres file listing which
## world variables feed its influence, with no engine change anywhere.

@export var archetype_id: StringName = &""
@export var display_label: String = ""
@export var drivers: Array[PowerDriver] = []
@export var max_score: float = 100.0
## Baseline every organization of this archetype gets just for existing.
@export var base_score: float = 5.0
## How strongly membership scales the result (0 = size irrelevant).
@export var membership_weight: float = 0.25
## Fraction of monster population this archetype culls per point of power.
## Only the archetypes that actually fight monsters set this above zero.
@export var monster_suppression_factor: float = 0.0
## Naming/flavour hints used by the generator when this archetype is founded.
@export var default_leadership_title: String = "Head"
@export var noun_bank: Array[String] = []
