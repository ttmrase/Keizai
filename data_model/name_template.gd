class_name NameTemplate
extends Resource

## Word banks and patterns the name generator stitches together. One template per
## organization kind is enough — archetype-specific nouns come from the
## archetype's PowerProfile, so adding an archetype does not need a new template.
##
## Patterns use {token} slots. The generator supplies these built-ins:
##   {adjective}   an ideology-derived adjective (only when an axis is strong)
##   {legitimacy}  世襲 / 選挙 / 実力主義 / 神権 / 軍事 / 金権
##   {structure}   専制 / 評議制 / 議会制
##   {ideology}    "軍国主義・鎖国" — the strong axes, joined
##   {noun}        archetype noun, e.g. 討伐者ギルド
##   {epithet}     a word drawn from this template's `word_bank`
##   {founder}     the founding leader's given name
##   {place}       the seat settlement's name
## Any other {token} is filled from `word_bank[token]`.

@export var applies_to_kind: Organization.OrgKind = Organization.OrgKind.GUILD
## Empty means "any archetype of that kind".
@export var archetype_filter: Array[StringName] = []
@export var name_pattern: String = "{epithet}{noun}"
@export var description_pattern: String = ""
## Alternative patterns used for branch organizations, so a splinter reads
## differently from a founding institution.
@export var branch_name_pattern: String = ""
## Branches can name their origin ({parent}), which a founding institution cannot.
@export var branch_description_pattern: String = ""
@export var word_bank: Dictionary = {}


func matches(kind: Organization.OrgKind, archetype_id: StringName) -> bool:
	if applies_to_kind != kind:
		return false
	if archetype_filter.is_empty():
		return true
	return archetype_filter.has(archetype_id)
