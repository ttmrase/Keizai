class_name TriggerRule
extends Resource

## A condition set plus what happens when it holds. Authored as .tres content so
## new social pressures can be added without engine changes.
##
## One class covers every rule type rather than a subclass per type: rules are
## always evaluated through the same loop, and .tres authoring is simpler when
## there is one schema to fill in.

enum RuleType {
	SCHISM,       # spawn a branch organization
	SUCCESSION,   # choose the next leader when a seat is empty
	CONFLICT,     # declare a contest between organizations
	POWER_SHIFT,  # move control of a settlement
}

enum SuccessionMethod {
	PRIMOGENITURE,
	ELECTIVE,
	MERITOCRATIC_APPOINTMENT,
	MILITARY_STRONGEST,
}

@export var rule_id: StringName = &""
@export var rule_type: RuleType = RuleType.SCHISM
@export var applies_to_kind: Organization.OrgKind = Organization.OrgKind.GUILD
## Empty means "any archetype of that kind".
@export var applies_to_archetypes: Array[StringName] = []
## All conditions must hold (AND).
@export var conditions: Array[RuleCondition] = []
@export var cooldown_ticks: int = 400
@export var priority: int = 0
## Per-tick probability once the conditions hold, so pressure builds into an
## event at an unpredictable moment rather than the instant a threshold is crossed.
@export var chance_per_tick: float = 0.05

# --- SCHISM ---
@export var schism_kind: StringName = &"ideological_split"
## Archetype the branch adopts. Empty keeps the parent's archetype (a plain split);
## setting it makes this a specialization — the moment a new kind of institution
## is invented in response to the world.
@export var branch_archetype_id: StringName = &""
@export var inherited_member_fraction: Vector2 = Vector2(0.2, 0.45)
## axis name -> value the branch's ideology is pulled toward.
@export var ideology_drift_bias: Dictionary = {}
## Only fire if the parent has at least this many members, so tiny orgs do not
## shatter endlessly.
@export var min_parent_members: int = 40
## Cap on how many organizations of the branch archetype may exist at once.
@export var max_instances_of_archetype: int = 0   # 0 = unlimited
@export var branch_leadership_title: String = ""
## How far the branch is thrown from the parent, 0..1. An ordinary split is a
## disagreement about degree and inherits nearly everything; a radical one is a
## different answer to the question, and 1.0 means it keeps almost nothing but
## the lineage. This is what stops a century of schisms producing a shelf of
## near-identical factions.
@export var radicalism: float = 0.0
## The branch's own institutional facts, -1 to inherit the parent's. A movement
## born of famine does not merely disagree with the old order about taxes — it
## rejects that a seat should be inherited at all.
@export var branch_legitimacy_basis: int = -1
@export var branch_decision_structure: int = -1

# --- SUCCESSION ---
@export var method: SuccessionMethod = SuccessionMethod.PRIMOGENITURE
@export var allow_dispute: bool = true
## Chance a passed-over, ambitious heir walks out and founds their own line.
@export var schism_probability_on_loss: float = 0.35

@export var chronicle_template: String = ""
