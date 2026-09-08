class_name Industry
extends RefCounted

## What each region lives on. Industry shapes what a place produces, and gives
## the guilds a reason to be strong in some regions and absent from others —
## a mining valley is where the artisans matter, not the farmers.

const MINING := &"mining"
const FORESTRY := &"forestry"
const FARMING := &"farming"
const TRADE := &"trade"
const FRONTIER := &"frontier"

const ALL: Array[StringName] = [MINING, FORESTRY, FARMING, TRADE, FRONTIER]

const LABELS := {
	MINING: "鉱業",
	FORESTRY: "林業",
	FARMING: "農業",
	TRADE: "交易",
	FRONTIER: "辺境警備",
}

const DESCRIPTIONS := {
	MINING: "坑道から鉱石を掘り出す土地。",
	FORESTRY: "森を伐り出して木材を得る土地。",
	FARMING: "畑が広がり、実りが人を養う土地。",
	TRADE: "街道と市が集まり、富が行き交う土地。",
	FRONTIER: "魔物の領域に接し、常に備えを要する土地。",
}

## Multipliers applied to this region's own production.
const YIELD_MODIFIERS := {
	MINING:   {"ore": 2.2, "wood": 0.6, "food": 0.78, "wealth": 1.0},
	FORESTRY: {"ore": 0.6, "wood": 2.3, "food": 0.85, "wealth": 1.0},
	FARMING:  {"ore": 0.4, "wood": 0.9, "food": 1.5,  "wealth": 0.9},
	TRADE:    {"ore": 0.8, "wood": 0.9, "food": 0.9,  "wealth": 2.1},
	FRONTIER: {"ore": 1.0, "wood": 1.1, "food": 0.85, "wealth": 0.8},
}

## Which guild archetype has a natural claim on a region of this kind. A guild
## that matches gets a large standing bonus here; others compete on raw power.
const AFFINITY := {
	MINING: [&"artisans_guild", &"founders_guild"],
	FORESTRY: [&"artisans_guild", &"merchants_guild"],
	FARMING: [&"founders_guild", &"farmers_faction"],
	TRADE: [&"merchants_guild", &"founders_guild"],
	FRONTIER: [&"monster_hunters_guild", &"mage_guild"],
}


static func label(industry: StringName) -> String:
	return LABELS.get(industry, String(industry))


static func description(industry: StringName) -> String:
	return DESCRIPTIONS.get(industry, "")


static func yield_modifier(industry: StringName, key: String) -> float:
	var table: Dictionary = YIELD_MODIFIERS.get(industry, {})
	return float(table.get(key, 1.0))


static func favours(industry: StringName, archetype_id: StringName) -> bool:
	return AFFINITY.get(industry, []).has(archetype_id)


## Assigns industries across the map so a world always has some of each rather
## than eight farming villages by chance.
static func assign_spread(count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
	var pool: Array[StringName] = []
	for i in count:
		if pool.is_empty():
			pool = ALL.duplicate()
			# Shuffle deterministically through the seeded stream.
			for j in range(pool.size() - 1, 0, -1):
				var k := rng.randi_range(0, j)
				var tmp := pool[j]
				pool[j] = pool[k]
				pool[k] = tmp
		out.append(pool.pop_back())
	return out
