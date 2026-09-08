class_name SettlementState
extends Resource

## Aggregate state for one settlement. The general populace is never simulated
## as individuals — only as these numbers. Named figures live in NotableIndividual.

@export var id: StringName = &""
@export var display_name: String = ""
@export var population: float = 500.0
@export var unrest: float = 0.0          # 0..1
@export var wealth: float = 100.0
@export var local_ore: float = 0.0
@export var local_wood: float = 0.0
@export var food_stock: float = 200.0
@export var controlling_org_id: StringName = &""
## What this place lives on. Shapes its yields, and decides which guild has a
## reason to be strong here.
@export var industry: StringName = &"farming"
## The house that holds this place locally. Its head is the region's lord, under
## whatever title the current form of government uses.
@export var ruling_house_id: StringName = &""
## Recomputed each power epoch: the guild with most standing here.
@export var dominant_guild_id: StringName = &""
@export var position: Vector2 = Vector2.ZERO
## Set by the resource step each tick so rules/UI can react to famine without
## recomputing the food balance themselves.
@export var starving: bool = false


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"population": population,
		"unrest": unrest,
		"wealth": wealth,
		"local_ore": local_ore,
		"local_wood": local_wood,
		"food_stock": food_stock,
		"controlling_org_id": String(controlling_org_id),
		"industry": String(industry),
		"ruling_house_id": String(ruling_house_id),
		"dominant_guild_id": String(dominant_guild_id),
		"position_x": position.x,
		"position_y": position.y,
		"starving": starving,
	}


static func from_dict(d: Dictionary) -> SettlementState:
	var s := SettlementState.new()
	s.id = StringName(d.get("id", ""))
	s.display_name = d.get("display_name", "")
	s.population = float(d.get("population", 0.0))
	s.unrest = float(d.get("unrest", 0.0))
	s.wealth = float(d.get("wealth", 0.0))
	s.local_ore = float(d.get("local_ore", 0.0))
	s.local_wood = float(d.get("local_wood", 0.0))
	s.food_stock = float(d.get("food_stock", 0.0))
	s.controlling_org_id = StringName(d.get("controlling_org_id", ""))
	s.industry = StringName(d.get("industry", "farming"))
	s.ruling_house_id = StringName(d.get("ruling_house_id", ""))
	s.dominant_guild_id = StringName(d.get("dominant_guild_id", ""))
	s.position = Vector2(float(d.get("position_x", 0.0)), float(d.get("position_y", 0.0)))
	s.starving = bool(d.get("starving", false))
	return s
