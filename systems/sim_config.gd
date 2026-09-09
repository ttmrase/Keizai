class_name SimConfig
extends RefCounted

## Central tuning constants. Gameplay balance lives here so it can be adjusted
## without hunting through systems.

# --- Time ---
const TICKS_PER_YEAR := 4          # one tick = one season
const DEFAULT_SECONDS_PER_TICK := 1.0
const MAX_TICKS_PER_FRAME := 30    # anti spiral-of-death clamp

# Cadence of expensive recomputation, in ticks.
const POWER_RECALC_EPOCH_TICKS := 10
const RULES_MIN_CHECK_INTERVAL := 4
const IDEOLOGY_DRIFT_EPOCH_TICKS := 10

# --- Resource economics (per settlement, per tick) ---
const ORE_YIELD_PER_CAPITA := 0.010
const WOOD_YIELD_PER_CAPITA := 0.014
const FOOD_YIELD_PER_CAPITA := 0.075
const FOOD_CONSUMPTION_PER_CAPITA := 0.060
# Stocks are spent as well as gathered, so a dial setting produces an
# equilibrium level rather than everything drifting to its ceiling forever.
const ORE_USE_PER_CAPITA := 0.008
const WOOD_USE_PER_CAPITA := 0.011
const STOCK_SPOILAGE := 0.010
## How much of the realm's spare food is moved to where it is needed each tick,
## and how much of it survives the journey.
const FOOD_SHARING_FRACTION := 0.35
const FOOD_TRANSPORT_EFFICIENCY := 0.85
const WEALTH_PER_ORE := 0.35
const WEALTH_PER_WOOD := 0.20
const WEALTH_DECAY := 0.004

# Stock ceilings keep unbounded accumulation (and unbounded power scores) in check.
const MAX_LOCAL_STOCK := 4000.0
const MAX_FOOD_STOCK := 3000.0
const MAX_WEALTH := 5000.0

# --- Population ---
const BASE_BIRTH_RATE := 0.0075
const BASE_DEATH_RATE := 0.0055
const STARVATION_DEATH_RATE := 0.018
const MIN_POPULATION := 20
const MAX_POPULATION := 20000

# --- Unrest ---
# Unrest chases a target set by current conditions rather than accumulating, so
# it can pin at 1.0 only while things are genuinely catastrophic, and eases as
# soon as they improve.
const UNREST_FROM_STARVATION := 0.85
const UNREST_FROM_MONSTERS := 0.55
const UNREST_ADJUST_RATE := 0.012

# --- Monsters ---
const MONSTER_BASE_GROWTH := 0.012
const MONSTER_CARRYING_CAPACITY := 1200.0
const MONSTER_CULL_PER_POWER := 0.25   # how effectively hunter power suppresses monsters
const MONSTER_RAID_DAMAGE := 0.0042    # extra per-tick mortality at maximum threat
## Monsters seep back into the world even after being wiped out. Growth alone is
## multiplicative, so without this a single effective purge would end the threat
## permanently — and with it every institution that exists to answer it.
const MONSTER_BASELINE_SPAWN := 0.9

# --- Notable individuals ---
const ADULT_AGE_YEARS := 16
const MAX_AGE_YEARS := 95
const BASE_FERTILITY_PER_TICK := 0.055
const MARRIAGE_CHANCE_PER_TICK := 0.10

# --- Organization membership ---
# Share of the population each kind of institution can draw on, split between
# organizations of that kind by their relative power. Without this every schism
# would shrink its parent forever and the world would end up as a crowd of
# five-member remnants.
const MEMBERSHIP_SHARE := {
	0: 0.12,   # GUILD
	1: 0.012,  # HOUSE
	2: 0.22,   # FACTION
	3: 0.06,   # POLITICAL_SYSTEM
	4: 0.30,   # RELIGION — a faith counts everyone who holds it, not a membership roll
}
const MEMBERSHIP_ADJUST_FRACTION := 0.06
## Below this a non-root organization is considered to have died out.
const ORG_DISSOLVE_MEMBERS := 3
## A society can only sustain so many parallel institutions of one kind. Without
## a ceiling, drift-driven schisms compound into a crowd of indistinguishable
## splinters and the lineage tree stops being readable.
const MAX_ACTIVE_ORGS_PER_KIND := 7
## Families are the exception, and by a long way. A country has a handful of
## guilds and dozens of households; capping houses at the same number as guilds
## makes extinction a one-way ratchet, because no cadet branch can ever form to
## replace a line that has died out, and the world grinds down to exactly the cap.
const MAX_ACTIVE_HOUSES := 40
## ...except that a society always has room for something it has never had
## before. A branch that invents a kind of institution the world does not yet
## contain may exceed the ceiling by this much; a plain splinter may not. Without
## the exception a world that has already filled its quota with lookalike
## factions can never produce a new politics, however badly it needs one.
const NEW_ARCHETYPE_HEADROOM := 2
## And no more than this many bodies of any one archetype. A society sustains a
## few rival lodges of the same trade, not seven — without the cap, whichever
## archetype the world currently rewards splits over and over until every faction
## in the country is a variation on the same one, which is exactly the sameness
## the archetypes exist to avoid.
const MAX_ACTIVE_PER_ARCHETYPE := 3

## Retainer houses attached to each founding noble house. They are the rank
## between the people and the nobility: near enough to the great families to
## matter, far enough to resent it.
const RETAINERS_PER_HOUSE := 3

## Longest name the player may give a place or an institution.
const MAX_NAME_LENGTH := 24

# --- History log / saves ---
const HISTORY_SEGMENT_EVENT_CAP := 5000
const HISTORY_HOT_WINDOW_TICKS := 2000
const COMPACTION_EPOCH_BUCKET_TICKS := 400
