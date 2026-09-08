class_name WorldState
extends Resource

## The environment the player manipulates, and the aggregate numbers it produces.
##
## The four *_rate / *_modifier dials are the ONLY fields the player writes to
## (through GodPowerAPI). Everything political reacts to the values below; nothing
## political is written here.

@export var tick: int = 0
@export var seed: int = 0

@export var settlements: Dictionary[StringName, SettlementState] = {}

# Cached sums of settlement values, refreshed each tick for fast UI/PowerCalculator reads.
@export var global_ore: float = 0.0
@export var global_wood: float = 0.0
@export var global_food_stock: float = 0.0
@export var global_population: float = 0.0
@export var global_wealth: float = 0.0
@export var global_unrest: float = 0.0

# 0 = total crop failure, 1 = normal, >1 = bounty.
@export var global_harvest_modifier: float = 1.0
@export var global_monster_population: float = 120.0
@export var global_monster_threat_level: float = 0.0

# --- Player dials ---
@export var ore_supply_rate: float = 1.0
@export var wood_supply_rate: float = 1.0
@export var harvest_rate_modifier: float = 1.0
@export var monster_spawn_rate: float = 1.0

@export var active_disasters: Array[DisasterInstance] = []

## Rolling count of disasters that began recently. Drives the temple faction's
## power without it needing to read the history log.
@export var recent_disaster_pressure: float = 0.0
## Largest magnitude among currently active disasters; drives the mage guild.
@export var peak_disaster_magnitude: float = 0.0
## Aggregate suppression applied to monster growth by whoever is hunting them.
## Written by PowerCalculator's epoch pass, read by the resource step.
@export var monster_suppression: float = 0.0


func get_settlement(id: StringName) -> SettlementState:
	return settlements.get(id)


func to_dict() -> Dictionary:
	var settle := {}
	for k in settlements:
		settle[String(k)] = settlements[k].to_dict()
	var disasters: Array = []
	for d in active_disasters:
		disasters.append(d.to_dict())
	return {
		"tick": tick,
		"seed": seed,
		"settlements": settle,
		"global_ore": global_ore,
		"global_wood": global_wood,
		"global_food_stock": global_food_stock,
		"global_population": global_population,
		"global_wealth": global_wealth,
		"global_unrest": global_unrest,
		"global_harvest_modifier": global_harvest_modifier,
		"global_monster_population": global_monster_population,
		"global_monster_threat_level": global_monster_threat_level,
		"ore_supply_rate": ore_supply_rate,
		"wood_supply_rate": wood_supply_rate,
		"harvest_rate_modifier": harvest_rate_modifier,
		"monster_spawn_rate": monster_spawn_rate,
		"active_disasters": disasters,
		"recent_disaster_pressure": recent_disaster_pressure,
		"peak_disaster_magnitude": peak_disaster_magnitude,
		"monster_suppression": monster_suppression,
	}


static func from_dict(d: Dictionary) -> WorldState:
	var w := WorldState.new()
	w.tick = int(d.get("tick", 0))
	w.seed = int(d.get("seed", 0))
	var settle: Dictionary[StringName, SettlementState] = {}
	for k in d.get("settlements", {}):
		settle[StringName(k)] = SettlementState.from_dict(d["settlements"][k])
	w.settlements = settle
	w.global_ore = float(d.get("global_ore", 0.0))
	w.global_wood = float(d.get("global_wood", 0.0))
	w.global_food_stock = float(d.get("global_food_stock", 0.0))
	w.global_population = float(d.get("global_population", 0.0))
	w.global_wealth = float(d.get("global_wealth", 0.0))
	w.global_unrest = float(d.get("global_unrest", 0.0))
	w.global_harvest_modifier = float(d.get("global_harvest_modifier", 1.0))
	w.global_monster_population = float(d.get("global_monster_population", 0.0))
	w.global_monster_threat_level = float(d.get("global_monster_threat_level", 0.0))
	w.ore_supply_rate = float(d.get("ore_supply_rate", 1.0))
	w.wood_supply_rate = float(d.get("wood_supply_rate", 1.0))
	w.harvest_rate_modifier = float(d.get("harvest_rate_modifier", 1.0))
	w.monster_spawn_rate = float(d.get("monster_spawn_rate", 1.0))
	var disasters: Array[DisasterInstance] = []
	for entry in d.get("active_disasters", []):
		disasters.append(DisasterInstance.from_dict(entry))
	w.active_disasters = disasters
	w.recent_disaster_pressure = float(d.get("recent_disaster_pressure", 0.0))
	w.peak_disaster_magnitude = float(d.get("peak_disaster_magnitude", 0.0))
	w.monster_suppression = float(d.get("monster_suppression", 0.0))
	return w
