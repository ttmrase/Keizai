class_name RuleConditionEvaluator
extends RefCounted

## Evaluates a rule's conditions against the world and the organization under
## consideration. All conditions must hold.

static func all_hold(rule: TriggerRule, org: Organization) -> bool:
	for c in rule.conditions:
		if not holds(c, org):
			return false
	return true


static func holds(c: RuleCondition, org: Organization) -> bool:
	var value := WorldStateQuery.get_value(c.world_var_path, org)
	match c.op:
		RuleCondition.Op.GREATER_THAN:
			return value > c.threshold
		RuleCondition.Op.LESS_THAN:
			return value < c.threshold
		RuleCondition.Op.BETWEEN:
			return value >= c.threshold and value <= c.threshold_high
		RuleCondition.Op.DRIFTED_FROM_BASELINE:
			if org == null or org.ideology == null or org.ideology_baseline == null:
				return false
			var axis := StringName(String(c.world_var_path).get_file())
			var drift: float = absf(org.ideology.get_axis(axis) - org.ideology_baseline.get_axis(axis))
			return drift > c.threshold
	return false


## Human-readable reason a rule fired, for the chronicle entry.
static func describe(rule: TriggerRule, org: Organization) -> String:
	var reasons: Array[String] = []
	for c in rule.conditions:
		if not c.describe_as.is_empty():
			reasons.append(c.describe_as)
	return "、".join(reasons)
