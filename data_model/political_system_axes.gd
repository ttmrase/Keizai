class_name PoliticalSystemAxes
extends Resource

## The composable ideology/power-structure components every organization carries.
##
## Political systems are never picked from a fixed list of regime types. They are
## assembled from two discrete institutional axes plus five continuous ideology
## axes that drift in response to world conditions, and named from that
## combination by PoliticalSystemGenerator. Guilds and factions reuse the exact
## same structure — only the naming word banks differ.

enum LegitimacyBasis {
	HEREDITARY,
	ELECTED,
	MERITOCRATIC,
	THEOCRATIC,
	MILITARY_STRENGTH,
	WEALTH_BASED,
}

enum DecisionStructure {
	AUTOCRATIC,
	OLIGARCHIC_COUNCIL,
	ASSEMBLY,
}

## Continuous axes, all normalized -1.0..1.0 with 0.0 neutral. Negative pole first.
const AXIS_NAMES: Array[StringName] = [
	&"centralization",        # -1 decentralized .. +1 centralized
	&"tradition_reform",      # -1 traditionalist .. +1 reformist
	&"militarism_pacifism",   # -1 pacifist .. +1 militarist
	&"isolationism_commerce", # -1 isolationist .. +1 mercantile
	&"secular_theocratic",    # -1 secular .. +1 theocratic
]

const LEGITIMACY_NAMES := {
	LegitimacyBasis.HEREDITARY: "hereditary",
	LegitimacyBasis.ELECTED: "elected",
	LegitimacyBasis.MERITOCRATIC: "meritocratic",
	LegitimacyBasis.THEOCRATIC: "theocratic",
	LegitimacyBasis.MILITARY_STRENGTH: "military",
	LegitimacyBasis.WEALTH_BASED: "plutocratic",
}

const STRUCTURE_NAMES := {
	DecisionStructure.AUTOCRATIC: "autocratic",
	DecisionStructure.OLIGARCHIC_COUNCIL: "council",
	DecisionStructure.ASSEMBLY: "assembly",
}

@export var legitimacy_basis: LegitimacyBasis = LegitimacyBasis.HEREDITARY
@export var decision_structure: DecisionStructure = DecisionStructure.AUTOCRATIC

@export var centralization: float = 0.0
@export var tradition_reform: float = 0.0
@export var militarism_pacifism: float = 0.0
@export var isolationism_commerce: float = 0.0
@export var secular_theocratic: float = 0.0

## Open-ended descriptive tags accumulated from history, e.g. &"war_torn".
@export var tags: Array[StringName] = []


func get_axis(axis: StringName) -> float:
	return get(String(axis))


func set_axis(axis: StringName, value: float) -> void:
	set(String(axis), clampf(value, -1.0, 1.0))


func nudge_axis(axis: StringName, toward: float, rate: float) -> void:
	set_axis(axis, move_toward(get_axis(axis), clampf(toward, -1.0, 1.0), rate))


func add_tag(tag: StringName) -> void:
	if not tags.has(tag):
		tags.append(tag)


## Explicit deep copy. A schism must never leave parent and branch sharing one
## axes object, or their ideologies would evolve in lockstep forever after.
func clone() -> PoliticalSystemAxes:
	var c := PoliticalSystemAxes.new()
	c.legitimacy_basis = legitimacy_basis
	c.decision_structure = decision_structure
	for a in AXIS_NAMES:
		c.set_axis(a, get_axis(a))
	c.tags = tags.duplicate()
	return c


## Mean absolute difference across the continuous axes, 0..1.
func ideological_distance(other: PoliticalSystemAxes) -> float:
	var total := 0.0
	for a in AXIS_NAMES:
		total += absf(get_axis(a) - other.get_axis(a))
	return total / float(AXIS_NAMES.size()) / 2.0


func to_dict() -> Dictionary:
	var d := {
		"legitimacy_basis": LEGITIMACY_NAMES[legitimacy_basis],
		"decision_structure": STRUCTURE_NAMES[decision_structure],
	}
	for a in AXIS_NAMES:
		d[String(a)] = get_axis(a)
	if not tags.is_empty():
		var t: Array = []
		for tag in tags:
			t.append(String(tag))
		d["tags"] = t
	return d


static func from_dict(d: Dictionary) -> PoliticalSystemAxes:
	var a := PoliticalSystemAxes.new()
	a.legitimacy_basis = _enum_from_name(LEGITIMACY_NAMES, d.get("legitimacy_basis", "hereditary"), LegitimacyBasis.HEREDITARY)
	a.decision_structure = _enum_from_name(STRUCTURE_NAMES, d.get("decision_structure", "autocratic"), DecisionStructure.AUTOCRATIC)
	for axis in AXIS_NAMES:
		a.set_axis(axis, float(d.get(String(axis), 0.0)))
	var tags_in: Array[StringName] = []
	for t in d.get("tags", []):
		tags_in.append(StringName(t))
	a.tags = tags_in
	return a


static func _enum_from_name(table: Dictionary, name: String, fallback: int) -> int:
	for k in table:
		if table[k] == name:
			return k
	return fallback
