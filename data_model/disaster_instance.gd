class_name DisasterInstance
extends Resource

## A disaster currently in effect. Created by GodPowerAPI, applied and expired by
## GameState.step_resources().

@export var disaster_id: StringName = &""
@export var definition_id: StringName = &""
@export var target_settlement_id: StringName = &""   # empty = world-wide
@export var magnitude: float = 1.0
@export var start_tick: int = 0
@export var duration_ticks: int = 20


func is_active(tick: int) -> bool:
	return tick >= start_tick and tick < start_tick + duration_ticks


## 0..1 progress through the disaster's lifetime, used to sample the intensity curve.
func progress(tick: int) -> float:
	if duration_ticks <= 0:
		return 1.0
	return clampf(float(tick - start_tick) / float(duration_ticks), 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"disaster_id": String(disaster_id),
		"definition_id": String(definition_id),
		"target_settlement_id": String(target_settlement_id),
		"magnitude": magnitude,
		"start_tick": start_tick,
		"duration_ticks": duration_ticks,
	}


static func from_dict(d: Dictionary) -> DisasterInstance:
	var i := DisasterInstance.new()
	i.disaster_id = StringName(d.get("disaster_id", ""))
	i.definition_id = StringName(d.get("definition_id", ""))
	i.target_settlement_id = StringName(d.get("target_settlement_id", ""))
	i.magnitude = float(d.get("magnitude", 1.0))
	i.start_tick = int(d.get("start_tick", 0))
	i.duration_ticks = int(d.get("duration_ticks", 0))
	return i
