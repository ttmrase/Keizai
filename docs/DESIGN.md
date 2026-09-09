# Keizai — Android Fantasy Civilization Observation Game

## Context

The repository is currently empty — this is a greenfield project. The goal is an Android APK "god game" in which the player does almost nothing directly: they only turn environmental dials (ore, wood, harvest/famine, monster population) and optionally trigger disasters/events. Everything else — a fantasy civilization organized into **guilds**, a **political system/regime**, a **ruling house (crown)**, and **factions** — must develop, compete for power, and fracture into branches entirely on its own, in reaction to those environmental inputs. The point of the game is to *watch* this emergent social complexity unfold over time, not to control it.

Two requirements from the original spec are non-negotiable and drive every architectural choice below:

1. **Power must shift dynamically and generically.** E.g. "when monsters are abundant, the monster-subjugation guild gains power" is one instance of a general rule — any guild/house/faction/regime archetype must be able to declare what world conditions drive its influence, without engine code changes per archetype.
2. **Every branch is always traceable to one root.** Guilds, houses, factions, and political systems can all split into branches/schisms over time, but there is exactly one founding "mainline" of each kind at game start, and any branch's lineage — and any notable individual's family tree — must always be traceable back to it, permanently, no matter how long the game has run or how much history has accumulated.

A third, later-added requirement: **political systems (and guild/faction ideology) must be procedurally generated from composable components**, not picked from a fixed hand-authored list like {Monarchy, Republic, Theocracy}.

This plan defines a Godot 4.x architecture that satisfies all three by construction (event-sourced history log for traceability; a data-driven, file-authored power-scoring system for genericity; a composable-axis generator for political systems), broken into 8 build phases of equal, execute-ready detail, for a separate implementation pass (Opus 5) to build incrementally. Each phase is independently runnable and verifiable inside the Godot editor.

### Locked-in decisions (confirmed with user before writing this plan)

| Decision | Choice |
|---|---|
| Engine / target | Godot 4.x (GDScript), Android APK export. Target Godot **4.7.x** stable; **4.4 is the hard minimum** (typed `Dictionary[K,V]` syntax is used throughout). |
| Population granularity | **Hybrid.** General populace = aggregate per-settlement stats (headcount, unrest, wealth). Named leaders/heads/monarchs/guild masters = individually simulated with full genealogy (birth/marriage/death/succession). |
| Time progression | Real-time tick simulation, pausable, variable speed (1x/2x/4x). Player can act at any time; the world advances on its own. |
| Political system generation | **Procedural/compositional, not a fixed enum.** Two discrete axes (`legitimacy_basis`, `decision_structure`) + five continuous, world-reactive ideology axes + free-form tags, combined via name/description templates. The same machinery is reused for guild and faction ideology — not a one-off for the crown. |
| Roadmap detail | All 8 phases (Phase 0–7) detailed to **equal depth** — an explicit user request overriding the usual "sketch the later phases" default. |
| Initial MVP archetype roster | 7 archetypes (see Section B), each driven by a different combination of the player's environmental dials, including the user's own worked example (monster threat → hunters' guild). |

---

## A. Godot Project Architecture

### Folder structure

```
res://
├── autoload/          # Node singletons — the only long-lived global state
│   ├── sim_clock.gd  event_bus.gd  rng_service.gd  game_state.gd
│   ├── history_log.gd  rules_engine.gd  god_power_api.gd  save_manager.gd
├── data_model/         # extends Resource — pure data, Inspector-editable, serializable
│   ├── world_state.gd  settlement_state.gd  history_event.gd
│   ├── notable_individual.gd  role_tenure.gd
│   ├── organization.gd  guild.gd  house.gd  faction.gd  political_system.gd
│   ├── political_system_axes.gd  name_template.gd
│   ├── power_profile.gd  power_driver.gd
│   ├── trigger_rule.gd  rule_condition.gd  schism_rule.gd  succession_rule.gd
│   └── disaster_definition.gd  disaster_instance.gd
├── systems/            # extends RefCounted — stateless/pure logic, no scene tree, unit-testable
│   ├── world_generator.gd  demography.gd
│   ├── political_system_generator.gd  name_generator.gd
│   ├── power_calculator.gd  world_state_query.gd
│   ├── rule_registry.gd  rule_condition_evaluator.gd  schism_resolver.gd  succession_resolver.gd
│   ├── genealogy_validator.gd  save_codec.gd  name_index.gd
├── data/                # authored CONTENT resources (.tres), shipped in the APK, version-controlled
│   ├── name_templates/*.tres  power_profiles/*.tres  rules/*.tres  disasters/*.tres
├── ui/
│   ├── main/Main.tscn  main/screen_manager.gd
│   ├── screens/  WorldMapView.tscn  SettlementDetailPanel.tscn  ChronicleTimeline.tscn
│   │             GenealogyTreeView.tscn  OrgLineageView.tscn  PowerDashboard.tscn  GodPowerPanel.tscn
│   └── lineage/  LineageGraphView.tscn  genealogy_data_source.gd
│                 organization_lineage_data_source.gd  focus_traversal.gd
├── debug/DebugSimPanel.tscn
├── tests/               # GUT specs — see Section H
└── addons/gut/          # third-party headless test framework
```

Runtime save data lives under `user://saves/slot_<n>/`, **outside** `res://` (see below).

### Three-tier system split

| Tier | Godot base type | Lifetime | Examples |
|---|---|---|---|
| Autoload singleton | `Node` | App lifetime | `SimClock`, `GameState`, `HistoryLog`, `RulesEngine`, `GodPowerAPI`, `SaveManager` |
| Scene-tree node | `.tscn` | Only while a screen is open | `WorldMapView`, `ChronicleTimeline`, `GenealogyTreeView`, `GodPowerPanel` |
| `Resource` (data) | `extends Resource` | Owned by an autoload/collection; Inspector-editable, deep-copyable, serializable | `WorldState`, `HistoryEvent`, `Organization`+subtypes, `NotableIndividual`, `PowerProfile` |
| `RefCounted` (logic) | `extends RefCounted` | On-demand / static | `PowerCalculator`, `PoliticalSystemGenerator`, `SchismResolver`, `SaveCodec` |

There is exactly one of each autoload; scenes are disposable presentation; Resources are data (reuse `Resource.duplicate(true)` for true deep copies — critical when a schism clones a parent's ideology axes); RefCounted classes are pure logic, trivially unit-testable in isolation.

**Rejected alternative:** an embedded SQLite GDExtension for the history log. Not worth the native-binary Android build/ABI surface at this data scale (tens of thousands of narrative events, not millions of rows) — a segmented flat-file log (below) is simpler and easier to debug.

### Tick loop, decoupled from rendering

`SimClock` (autoload) runs its own wall-clock accumulator in `_process(delta)`, **not** `_physics_process` (which is tied to physics tick rate, not "game time"). This keeps sim speed independent of device frame rate and lets pause leave the UI fully interactive (important — players pause specifically to go read the chronicle/genealogy screens).

```gdscript
# autoload/sim_clock.gd
@export var seconds_per_tick: float = 1.0
var time_scale: float = 1.0        # 0 = paused
var current_tick: int = 0
var _accumulator: float = 0.0
const MAX_TICKS_PER_FRAME := 30    # anti-spiral-of-death clamp

func _process(delta: float) -> void:
    if time_scale <= 0.0: return
    _accumulator += delta * time_scale
    var steps := 0
    while _accumulator >= seconds_per_tick and steps < MAX_TICKS_PER_FRAME:
        _accumulator -= seconds_per_tick
        current_tick += 1
        _advance_one_tick()
        steps += 1
    if steps == MAX_TICKS_PER_FRAME: _accumulator = 0.0

func _advance_one_tick() -> void:
    GameState.step_resources(current_tick)
    RulesEngine.evaluate_tick(current_tick)
    EventBus.tick_advanced.emit(current_tick)
```

A test-only `advance_n_ticks_instant(n)` calls `_advance_one_tick()` in a tight loop, bypassing the accumulator — this is what makes 50,000-tick invariant tests run in seconds during headless verification (Section H), and it must be introduced alongside `SimClock` in Phase 1, not bolted on later.

### Save/load & the event-log growth problem

**Save format is hand-rolled JSON (`to_dict()`/`from_dict()`), not native `ResourceSaver.save()`.** Native Resource serialization embeds script *paths* into the file; renaming a `.gd` file during an 8-phase build would silently break old saves, and loading an untrusted `.tres`/`.res` can execute script code. Every `data_model/*.gd` class implements `to_dict()`/`from_dict()`, and `SaveCodec` (RefCounted) drives JSON (de)serialization. This restriction is **only** for save data — `.tres` files under `res://data/` are authored content shipped in the APK and are fine as native Resources.

Per save slot (`user://saves/slot_N/`):
1. **`snapshot.json`** — the full current projection (`WorldState`, all `Organization`s, all `NotableIndividual`s, `SimClock.current_tick`, `RngService` state). Load time is O(current entity count), independent of total ticks ever played.
2. **`history/history_00001.jsonl.gz`, ...** — the event-sourced log, NDJSON, gzip-compressed via `FileAccess.open_compressed(..., FileAccess.COMPRESSION_GZIP)`, rolled to a new segment every ~5,000 events so normal play only **appends**.
3. **`manifest.json`** — schema version, world seed, per-segment tick ranges, snapshot tick — lets the Chronicle UI page through segments lazily.

**The primary growth control is architectural:** `HistoryEvent` only represents discrete, narratively-significant transitions (founding, birth, marriage, death, succession, schism, power transfer, ideology shift, disaster onset). Continuously-varying numbers (`power_score`, `unrest`, resource levels) are cached fields, recomputed each tick/epoch and captured by the snapshot — **never individually event-sourced**. This keeps raw event volume proportional to population/organization count and event *rate*, not to ticks elapsed.

**Tiered compaction** (`SaveManager.compact()`, run periodically) is the secondary backstop, designed so it **cannot** break traceability:
- **Tier 2 (permanent backbone, never pruned):** any event flagged `is_lineage_critical = true` — `FOUNDING`, `SCHISM`, `SUCCESSION`, `POWER_TRANSFER` (leadership changes), threshold-crossing `IDEOLOGY_SHIFT`, and `BIRTH`/`MARRIAGE`/`DEATH` of anyone who ever held a `RoleTenure`. Bounded by org/notable-person count, not by ticks elapsed. Written to `history/backbone.jsonl`, excluded from compaction.
- **Tier 1 (compactable):** everything else, older than a hot window, folded per-(org, event_type, epoch-bucket) into `EPOCH_SUMMARY` roll-ups.
- **Tier 0 (hot):** the most recent ~2,000 ticks stay at full fidelity for a responsive "recent chronicle" feed.

Because Tier 2 is untouched by compaction, walking any org's `parent_org_id`/`origin_event_id` chain or any individual's `father_id`/`mother_id` chain always resolves through the permanent backbone — traceability is preserved by construction, not by hoping compaction stays conservative.

---

## B. Core Data Model

### `WorldState` / `SettlementState`
Global resource ledger + per-settlement breakdown: `tick`, `seed`, `settlements: Dictionary[StringName, SettlementState]`, `global_ore/wood/food_stock: float`, `global_harvest_modifier: float` (0=famine, 1=normal, >1=bounty), `global_monster_population/threat_level: float`, player-set dials `ore_supply_rate/wood_supply_rate/harvest_rate_modifier/monster_spawn_rate: float`, `active_disasters: Array[DisasterInstance]`.
`SettlementState`: `id`, `display_name`, `population`, `unrest [0..1]`, `wealth`, local resource stocks, `controlling_faction_id`, `position: Vector2`.

### `HistoryEvent` — the traceability backbone
`event_id`, `event_type` (enum: `FOUNDING, BIRTH, MARRIAGE, DEATH, SUCCESSION, SCHISM, POWER_TRANSFER, IDEOLOGY_SHIFT, DISASTER_OCCURRED, RESOURCE_SHOCK, ALLIANCE_FORMED, CONFLICT_DECLARED, CONFLICT_RESOLVED, EPOCH_SUMMARY`), `tick`, `wall_time_unix` (metadata only — **never** branch simulation logic on this), `subject_org_id`, `subject_person_id`, **`origin_event_id`** (the causally-preceding event — the pointer chain traceability is built on), **`parent_org_id`** (for `FOUNDING`/`SCHISM`; sentinel `""` marks the one true root of that `kind`), `related_person_ids`, `payload: Dictionary`, `is_lineage_critical: bool`, `description: String` (pre-rendered at creation, not re-templated per UI draw).

### `NotableIndividual`
`person_id`, `full_name`, `sex`, `birth_tick`, `birth_event_id`, `death_tick = -1` (alive), `death_event_id`, `father_id`, `mother_id`, `spouse_ids: Array`, `children_ids: Array`, `personality_tags: Array[StringName]` (e.g. `&"ambitious"` — open-ended, biases rule-engine weights without hardcoded stat blocks), `role_history: Array[RoleTenure]`, **`is_founder_generation: bool`** (marks world-gen-seeded individuals with no simulated parents; genealogy termination accepts either an empty parent id or this flag).
`RoleTenure`: `org_id`, `title`, `start_tick`, `end_tick = -1`, `start_event_id`, `end_event_id`.

### `Organization` (base) + `Guild` / `House` / `Faction` / `PoliticalSystem`
`org_id`, `kind` (enum `GUILD, HOUSE, FACTION, POLITICAL_SYSTEM`), `archetype_id` (e.g. `&"monster_hunters_guild"` — drives `PowerProfile` lookup by data, not a hardcoded switch), `display_name`/`description` (generated), **`parent_org_id = ""`** (empty only for the single root per `kind`), `origin_event_id`, `founding_tick`, **`branch_depth`** (0 at root, else `parent.branch_depth+1` — gives an O(depth) proof the chain can't cycle, and a free UI grouping key), `child_org_ids: Array`, `leader_person_id`, `leadership_title`, `member_count`, `resources: Dictionary[StringName, float]` (open-ended pool), `power_score` (cached) + `power_drivers: Dictionary` (last-computed per-driver contribution, for "why is this org powerful" UI), `last_fired_tick: Dictionary` (per-rule cooldowns), **`ideology: PoliticalSystemAxes`** (every organization carries one, not just the crown).

`PoliticalSystem` **extends `Organization`** rather than living in a separate hierarchy — political systems can schism too, and reuse means the same lineage-tree UI, `PowerCalculator`, and `SchismRule` engine work uniformly across all four kinds. This is the concrete mechanism behind "generic, not a hardcoded special case."

Subtype fields: `Guild.trade_specialty`; `House.dynasty_seat_settlement_id`, `House.succession_rule_id`; `Faction.cause_tags: Array`; `PoliticalSystem.governs_settlement_ids: Array`, `PoliticalSystem.legitimacy: float`.

### `PoliticalSystemAxes` + `PoliticalSystemGenerator` — confirmed design

- `legitimacy_basis` (enum): `HEREDITARY, ELECTED, MERITOCRATIC, THEOCRATIC, MILITARY_STRENGTH, WEALTH_BASED`
- `decision_structure` (enum): `AUTOCRATIC, OLIGARCHIC_COUNCIL, ASSEMBLY`
- Five continuous axes, floats normalized `-1.0..1.0`: `centralization`, `tradition_reform`, `militarism_pacifism`, `isolationism_commerce`, `secular_theocratic`
- `tags: Array[StringName]` — open-ended, accumulated from history (e.g. `&"war_torn"`)

Enums for the two institutional facts (discrete by nature); floats for ideology (must drift smoothly and support threshold-crossing schism triggers via `move_toward(axis.value, worldstate_pull, drift_rate)` each epoch).

`PoliticalSystemGenerator` (RefCounted):
- `generate_root(rng, config) -> PoliticalSystem` — seeds a moderate hereditary-autocratic starting configuration.
- `generate_branch(parent, rng, drift_bias := {}) -> PoliticalSystem` — **deep-copies** the parent's axes (`Resource.duplicate(true)`, never a shared reference), applies RNG perturbation + any rule-supplied `drift_bias` (e.g. a "reform schism" biases `tradition_reform` toward reform).
- `name_and_describe(axes, org_kind, rng) -> {display_name, description}` — loads a `NameTemplate` matching `(org_kind, legitimacy_basis, decision_structure)`, resolves `{slot}` tokens from a word bank gated by axis thresholds. Example output: *"守旧的な世襲専制、イデオロギー:軍国主義・鎖国"* (a traditionalist hereditary autocracy, ideology: militarist/isolationist).

`NameTemplate`: `applies_to_kind`, `legitimacy_basis_filter`/`decision_structure_filter` (empty = any), `name_pattern`, `description_pattern`, `word_bank: Dictionary[StringName, Array]`. A token-substitution engine (not a full grammar DSL) is the right MVP scope — a fuller grammar is optional Phase 6 polish, not a blocker.

**This exact machinery is reused unmodified for Guild and Faction ideology** — every `Organization.ideology`, regardless of `kind`, runs through the same generator/drift logic; only the `NameTemplate` word banks differ per `(kind, archetype_id)`.

### `PowerCalculator` — extensible influence scoring

```gdscript
static func calculate(org: Organization, world: WorldState) -> float:
    var profile := PowerProfileRegistry.get_profile(org.archetype_id)
    var score := 0.0
    var drivers: Dictionary[StringName, float] = {}
    for driver in profile.drivers:                      # PowerDriver: {world_var_path, weight, curve}
        var raw := WorldStateQuery.get_value(world, org, driver.world_var_path)
        var normalized := driver.curve.sample(raw) if driver.curve else raw
        drivers[driver.world_var_path] = normalized * driver.weight
        score += drivers[driver.world_var_path]
    org.power_drivers = drivers
    return clampf(score, 0.0, profile.max_score)
```

`PowerProfile` (`.tres`): `archetype_id`, `drivers: Array[PowerDriver]`, `max_score`, `decay_rate`. `PowerDriver`: `world_var_path` (e.g. `&"global_monster_threat_level"`), `weight`, `curve: Curve` (**reuse Godot's built-in `Curve` resource** for nonlinear/diminishing-returns remaps rather than hand-rolling one). `WorldStateQuery.get_value()` is a small path resolver (handles `global_*`, `settlement.<id>.*`, `org.self.*` prefixes) — a few lines of routing, not a per-variable branch.

**Adding a new guild archetype means authoring one new `.tres` file, zero GDScript changes** — the concrete mechanism satisfying requirement #1. Recomputed every `power_recalc_epoch_ticks` (e.g. 10 ticks), not every tick, both for performance and so shifts read as gradual.

### Confirmed initial archetype roster (7)

Each tied to a different combination of the player's own environmental dials, so every observed power shift is traceable back to something the player did (or didn't do):

| `archetype_id` | `kind` | Concept | Primary power driver(s) |
|---|---|---|---|
| `monster_hunters_guild` | GUILD | 討伐ギルド | `global_monster_threat_level` (high weight) — the user's own worked example |
| `merchants_guild` | GUILD | 商業ギルド | `global_ore` + `global_wood` surplus, settlement wealth |
| `artisans_guild` | GUILD | 職人ギルド | `global_ore` (production-side; distinct weighting from merchants' trade-flow focus) |
| `farmers_faction` | FACTION | 農民派閥 | **low** `global_harvest_modifier` (famine) + settlement `unrest` — hardship organizes agrarian discontent into political leverage |
| `crown_house` | HOUSE (root) | 王家 | genealogy/succession only — no power driver of its own; the paired root `PoliticalSystem` (see below) is what holds power |
| `crown_political_system` | POLITICAL_SYSTEM (root) | 王権/政権 | `legitimacy` + `governs_settlement_ids.size()` |
| `temple_faction` | FACTION | 神殿/教会派閥 | recent `DISASTER_OCCURRED` frequency (rolling window) — triggering disasters as "god" directly empowers the theocratic faction, a deliberate thematic through-line |
| `mage_guild` | GUILD | 魔術師ギルド | secondary `global_monster_threat_level` weight (smaller than hunters', creating an emergent hunters-vs-mages rivalry for the same narrative territory) + disaster magnitude |

Exact weight/curve tuning is a Phase 3 implementation/playtest concern, not locked here — the point of the data-driven design is that it's cheap to iterate. Additional archetypes (beyond these 7) are pure content additions later (new `.tres` files), never engine changes.

### Projection sync: event log ↔ queryable state

`GameState` (current-state cache: who's king, current power %, current members) is a **derived projection, never mutated directly**. Every state change funnels through one entry point:

```gdscript
HistoryLog.record(event: HistoryEvent) -> void:
    _append_to_log(event)      # in-memory buffer + queued disk append
    GameState.apply(event)     # match on event_type, mutate the relevant Organization/
                                # NotableIndividual/WorldState fields in place
```

No other code path may write `Organization.leader_person_id`, `NotableIndividual.death_tick`, etc. — `GameState`'s dictionaries expose read-only getters (`get_organization(id)`, `get_current_leader(org_id)`); mutation only happens inside `apply()`. This makes `GameState` formally `fold(apply, events, initial_state)` — correct by construction, and a fresh load only needs the **last fold result** (`snapshot.json`), never a full replay.

Exception: `power_score`/`power_drivers` are cache fields recomputed every epoch and captured directly in the snapshot — not event-sourced (a float changing every 10 ticks isn't a chronicle-worthy "thing that happened"). `RulesEngine` writes a real `POWER_TRANSFER`/`IDEOLOGY_SHIFT` event only when a score crosses a narratively-significant threshold.

---

## C. Schism / Succession / Power-Shift Rule Engine

Data-driven `Resource` rules, not hardcoded if-chains:

- `TriggerRule` (base): `rule_id`, `applies_to_kind`, `applies_to_archetypes` (empty = any), `conditions: Array[RuleCondition]` (AND-combined), `cooldown_ticks`, `priority`
- `RuleCondition`: `world_var_path` (reuses `WorldStateQuery`), `op` (`GREATER_THAN, LESS_THAN, EQUALS, BETWEEN, CHANGED_BY_MORE_THAN`), `threshold[_high]`, `window_ticks`
- `SchismRule extends TriggerRule`: `schism_kind` (free-form, e.g. `&"ideological_split"`), `inherited_member_fraction_range: Vector2`, `ideology_drift_bias: Dictionary`, `min_branch_depth_gap_ticks`
- `SuccessionRule extends TriggerRule`: `method` (`PRIMOGENITURE, ELECTIVE, MERITOCRATIC_APPOINTMENT, MILITARY_STRONGEST`), `allow_dispute: bool`

`RulesEngine.evaluate_tick(tick)` iterates live organizations, checks each applicable rule's cooldown then conditions via `RuleConditionEvaluator`, and dispatches to a resolver on match.

**Worked examples** (the concrete content Phase 4 ships as `.tres` files):

1. **Succession dispute.** `DEATH` of a `leader_person_id` → look up `House.succession_rule_id` → find living eligible heirs. Exactly one → clean `SUCCESSION`. Multiple + `allow_dispute` → seeded weighted contest (weights from `personality_tags` + controlled resources). Losers whose ambition weight clears a threshold independently roll a schism chance; on success, that heir founds a new `House`/`Faction` with `parent_org_id` = the original org and `origin_event_id` = the new `SCHISM` event.
2. **Ideological drift.** `RuleCondition{world_var_path: "org.self.ideology.tradition_reform", op: CHANGED_BY_MORE_THAN, threshold: 0.5, window_ticks: 2000}` combined with a check that leadership is "pinned" against the drift. Fires `IDEOLOGY_SHIFT`; if configured as a schism rule, spins off a rump organization whose axes snap back toward pre-drift values — "the traditionalists who refused to change."
3. **Resource scarcity / power vacuum.** Condition on a controlled settlement's food stock plus the ruling org's own low `power_score` (connecting directly to the player's harvest/famine dial). Resolves as `POWER_TRANSFER` to the highest-`power_score` rival in the region. MVP scope is bookkeeping + chronicling, not tactical conflict simulation.
4. **Military defeat.** A minimal `CONFLICT_DECLARED` → `CONFLICT_RESOLVED` pair resolved probabilistically from relative `power_score`. The loser's `power_score`/`legitimacy` takes a hit — **no bespoke schism code path for "defeat"** — that hit alone is enough to trigger the *generic* low-legitimacy rule from example #3 next tick. This is the payoff of the data-driven design: new pressures are new content, not new engine code.

---

## D. Player "God Power" Layer

Every environmental dial is both a persistent supply-rate slider **and** a paired one-shot disaster injection, unified under `GodPowerAPI` (autoload):

| Variable | Continuous dial | One-shot injection |
|---|---|---|
| Ore | `set_ore_supply_rate(rate)` | `trigger_disaster(&"mineral_strike", settlement_id, magnitude)` |
| Wood | `set_wood_supply_rate(rate)` | `trigger_disaster(&"blessed_grove"/&"wildfire", ...)` |
| Harvest/Famine | `set_harvest_modifier(value)` | `trigger_disaster(&"drought"/&"bountiful_harvest", ...)` |
| Monsters | `set_monster_spawn_rate(rate)` | `trigger_disaster(&"monster_incursion", ...)` |

Initial disaster set (7, `.tres` content): `drought, plague, monster_incursion, mineral_strike, bountiful_harvest, wildfire, blessed_grove`. `trigger_disaster()` looks up a `DisasterDefinition` (`duration_ticks`, `affected_vars`, `magnitude_curve`, `chronicle_description_template`), appends a `DisasterInstance` to `WorldState.active_disasters` (applied/expired each tick by `GameState.step_resources()`), and immediately records a `DISASTER_OCCURRED` event — the disaster's *onset* is the chronicled moment. `plague` is the one disaster that reasonably hooks into `Demography`'s death-probability modifier rather than a raw resource, but still never touches `Organization`/political fields directly.

**API boundary — the player can never set political outcomes directly.** `GodPowerAPI` structurally accepts no `Organization`, `NotableIndividual`, `power_score`, leader, or ideology-axis parameter anywhere — there is no `set_org_leader()` or `force_schism()`. Political mutation originates only from `RulesEngine`, invoked only from `SimClock._advance_one_tick()`. Enforced both structurally and by an automated guardrail: a headless test scans every script under `res://ui/` for `HistoryLog.record(`, `.leader_person_id =`, `.power_score =`, `.ideology.` and fails the build if any appear outside allowed files (Section H).

---

## E. Observation UI (Android, touch-first)

Six screens from a bottom nav dock in `Main.tscn`: **Map / Chronicle / Genealogy / Org Tree / Power / God-Powers** (Genealogy+Org Tree may collapse into one "Lineage" tab with an in-screen toggle if six feels crowded on-device — a Phase 6 layout call, not decided here).

1. **World Map** (`WorldMapView.tscn`) — pannable/zoomable `Node2D`/`Camera2D`; drag via `InputEventScreenDrag`, pinch via `InputEventMagnifyGesture` (native Godot touch events). Settlement icons sized/colored by population/unrest; tap → `SettlementDetailPanel`.
2. **Chronicle** (`ChronicleTimeline.tscn`) — `ScrollContainer`+`VBoxContainer` of pre-rendered `event.description`, newest-first, lazily loading older history segments via `manifest.json`'s tick-range index. Filter chips by event type/org/person; tap deep-links to genealogy/lineage/map.
3. **Genealogy Tree Viewer** (`GenealogyTreeView.tscn`) — built on Godot's **native `GraphEdit`/`GraphNode`** (built-in pan/zoom/edge rendering — no custom drawing needed). **Focus mode by default**: centered on one person, showing only ancestors/descendants to a configurable depth + siblings, never the whole graph at once. Collapsible generations (a chevron folds a subtree into a "+12 descendants" summary node — simply not instanced, saving both draw calls and memory). Search-by-name via a prebuilt name index. A persistent **"Jump to Founder"** button — root navigation is first-class, matching the game's core payoff.
4. **Organization Lineage Tree Viewer** (`OrgLineageView.tscn`) — same pattern, factored as a shared base `LineageGraphView.tscn` behind a small adapter interface (`get_root_ids()`, `get_children(id)`, `get_node_label(id)`), with `GenealogyDataSource` and `OrganizationLineageDataSource` as the two thin implementations — the focus/collapse/search UX is written once, reused for both entity kinds. Nodes color-coded by `kind`, border thickness scaled by `power_score`.
5. **Power Dashboard** (`PowerDashboard.tscn`) — ranked bar list of `power_score`, filterable by `kind`; tap expands the cached `power_drivers` breakdown — directly surfacing the causal WorldState → power link.
6. **God-Power Panel** (`GodPowerPanel.tscn`) — persistent bottom sheet in the thumb-reachable zone: 4 `HSlider`s bound to `GodPowerAPI` setters + a scrolling row of disaster buttons (confirm popup with a tap-on-map target picker) + `SimClock` transport controls (play/pause/1x/2x/4x).

Global: portrait-primary layout (flagged overridable — the map screen specifically might want landscape), ~48dp-equivalent minimum touch targets, safe-area insets via `DisplayServer.get_display_safe_area()` so the bottom drawer never collides with Android's gesture nav bar.

---

## F. Phased Delivery Roadmap

Eight phases, each to equal depth: goal, deliverables, data model additions, key algorithms, UI additions, definition-of-done, headless-verification notes. Every phase is independently runnable/testable in the Godot editor.

### Phase 0 — Project setup & Android export pipeline
- **Goal:** empty repo → a Godot project that builds and runs on desktop editor *and* a real Android device, export automation proven, so every later phase can be verified on-device from day one.
- **Deliverables:** `project.godot`; `res://main/Main.tscn` (placeholder label); `.gitignore` (`.godot/`, export artifacts); `export_presets.cfg` with an Android preset (package id e.g. `com.ttmrase.keizai`, arch `arm64-v8a`, min SDK 24, target SDK — see Section G); debug keystore documented; release-keystore generation documented but **not committed**; `README.md` build instructions.
- **Data model additions:** none.
- **Key algorithms:** none.
- **UI additions:** placeholder screen only, proving the pipeline end-to-end.
- **Definition of done:** (1) project opens with zero import errors; (2) F5 run shows the placeholder; (3) `godot --headless --export-debug "Android" build/keizai-debug.apk` exits 0; (4) that APK installs and launches on a physical/emulated API-24+ device without crashing.
- **Headless verification:** the export command itself is the CI smoke test (exit-code check). On-device install stays manual.

### Phase 1 — Core simulation engine (world state, tick loop, event log, save/load)
- **Goal:** a running, saveable/loadable simulation of `WorldState` advancing over ticks, with the full event-sourcing + snapshot/compaction machinery proven, before any organizations/people exist — the highest-infrastructure-risk pieces validated first.
- **Deliverables:** `autoload/sim_clock.gd, event_bus.gd, game_state.gd` (holds `WorldState` only for now), `history_log.gd, save_manager.gd, rng_service.gd`; `data_model/world_state.gd, settlement_state.gd, history_event.gd` (only `FOUNDING/RESOURCE_SHOCK/EPOCH_SUMMARY` active, rest of enum stubbed); `systems/save_codec.gd`; `debug/DebugSimPanel.tscn` (tick counter, pause/speed, raw field readout). **Also pull forward a minimal autosave-on-`NOTIFICATION_APPLICATION_PAUSED`** from Phase 7 — cheap now, and mobile OSes can kill a backgrounded app without warning at any time, making this closer to correctness than polish.
- **Data model additions:** full `WorldState`/`SettlementState`/`HistoryEvent`.
- **Key algorithms:** the `SimClock` accumulator loop; snapshot + segmented-log write/read; tiered compaction (provable now against simple resource-shock events before organizations add complexity).
- **UI additions:** `DebugSimPanel` only.
- **Definition of done:** (1) unpausing advances tick count and e.g. `global_ore` per `ore_supply_rate` over real time; window/render stress doesn't change tick *rate*. (2) pausing freezes the tick counter while the panel stays interactive. (3) save → quit → relaunch → load reproduces tick count and all `WorldState` fields exactly. (4) a debug "fast-forward 10,000 ticks" button rolls segment files per the size cap; `SaveManager.compact()` shrinks on-disk history with `manifest.json` counts reconciling; load time stays flat regardless of ticks elapsed.
- **Headless verification:** stand up **GUT** here (first phase with logic worth regression-testing). `tests/test_sim_clock.gd`, `tests/test_save_roundtrip.gd` assert tick-rate correctness and field-for-field save/load equality.

### Phase 2 — Population & organizations (guilds/houses/factions, notable individuals, genealogy)
- **Goal:** seed exactly one root `Guild`/`House`/`Faction` with founding `NotableIndividual` leaders, and get birth/marriage/death ticking forward correctly through `HistoryLog` — no schism/succession *rules* yet (Phase 4); this phase proves the data mutates correctly.
- **Deliverables:** `data_model/organization.gd, guild.gd, house.gd, faction.gd` (`political_system.gd` deferred to Phase 3, though `Organization`'s base fields already support it), `notable_individual.gd, role_tenure.gd`; `GameState` extended with `organizations`/`people` dictionaries + query methods (`get_children`, `get_living_descendants`, `get_current_leader`); `HistoryEvent.EventType` usage extended to `BIRTH/MARRIAGE/DEATH/FOUNDING(org)/SUCCESSION` (simple no-dispute case only); `systems/world_generator.gd` (seeds the initial roots + leaders, including all 7 confirmed archetypes' orgs even though their power/ideology stay inert until Phase 3); `systems/demography.gd` (probabilistic birth/death for notable individuals only — general population uses pure aggregate math on `SettlementState`, already available from Phase 1).
- **Data model additions:** as above; `Organization.ideology` exists but holds neutral placeholders.
- **Key algorithms:** aggregate population growth (`settlement.population += settlement.population * (birth_rate - death_rate + migration_rate) * dt`, modulated by `food_stock`/`unrest`); notable-individual birth/death probability via age curves (**reuse Godot's `Curve` resource**, not a hand-rolled table); `systems/genealogy_validator.gd` introduced now (`trace_to_founder(person_id) -> bool`), reused by Section H's invariants later.
- **UI additions:** `DebugSimPanel` extended with org/people counts + an indented-text "print family tree" debug dump (not the real `GraphEdit` UI yet).
- **Definition of done:** (1) new game creates exactly one root of each kind, each with exactly one founding leader. (2) fast-forwarding shows new `BIRTH` events correctly linking `father_id`/`mother_id`/`children_ids` both directions. (3) forcing a death with a single heir produces a correct `SUCCESSION`, closing/opening `RoleTenure` correctly. (4) the debug family-tree dump visually matches the expected shape after several generations.
- **Headless verification:** `tests/test_genealogy.gd` — seeded world-gen, `advance_n_ticks_instant(N)`, assert `GenealogyValidator.trace_to_founder(p)` for every living individual, and parent/child link symmetry across the whole population.

### Phase 3 — Political-system procedural generation + power-dynamics calculator
- **Goal:** replace placeholder ideology with the full confirmed axis system, stand up the root `PoliticalSystem`, and make `PowerCalculator`/`PowerProfile` live and visibly reactive to `WorldState` for all 7 archetypes.
- **Deliverables:** `data_model/political_system.gd, political_system_axes.gd, name_template.gd, power_profile.gd, power_driver.gd`; `systems/political_system_generator.gd, power_calculator.gd, world_state_query.gd`; `data/name_templates/*.tres` and `data/power_profiles/*.tres` for all **7 confirmed archetypes** (Section B table); `WorldGenerator` extended to call `PoliticalSystemGenerator.generate_root()` and assign `PowerProfile`s to Phase 2's orgs.
- **Data model additions:** as above; `Organization.power_score`/`power_drivers` now populated.
- **Key algorithms:** axis drift step (`move_toward(axis.value, worldstate_pull, drift_rate)`); the `PowerCalculator.calculate()` formula (Section B); name-template token resolution; recompute cadence = every `power_recalc_epoch_ticks` (e.g. 10 ticks).
- **UI additions:** `DebugSimPanel` extended with a live table of every org's `power_score`, top driver, and generated `display_name`/`description`.
- **Definition of done:** (1) the root `PoliticalSystem` has a plausible generated name/description matching its starting axes (e.g. the confirmed worked example: *"守旧的な世襲専制、イデオロギー:軍国主義・鎖国"*). (2) driving `global_monster_threat_level` up via the debug slider raises `monster_hunters_guild`'s (and, more slowly, `mage_guild`'s) `power_score` within one or two epochs while unrelated orgs' scores stay flat — proof the per-archetype wiring is genuinely selective. (3) triggering a disaster raises `temple_faction`'s score over the following epochs. (4) authoring one brand-new `PowerProfile` `.tres` with zero GDScript changes scores correctly when assigned to a test org.
- **Headless verification:** `tests/test_power_calculator.gd` (hand-computed expected value against a fixture); `tests/test_name_generator.gd` (never empty, deterministic for a fixed seed).

### Phase 4 — Schism/branching + succession rule engine
- **Goal:** make the Section C rule system live so organizations/lines of succession branch and resolve disputes autonomously over a long fast-forwarded run, with every branch satisfying root-traceability.
- **Deliverables:** `data_model/trigger_rule.gd, rule_condition.gd, schism_rule.gd, succession_rule.gd`; `systems/rule_registry.gd, rule_condition_evaluator.gd, schism_resolver.gd, succession_resolver.gd`; `autoload/rules_engine.gd`; `data/rules/*.tres` covering the four Section C worked examples; `HistoryEvent.EventType` usage extended to fully exercise `SCHISM/SUCCESSION/POWER_TRANSFER/IDEOLOGY_SHIFT/CONFLICT_DECLARED/CONFLICT_RESOLVED`.
- **Data model additions:** `Organization.last_fired_tick`, `branch_depth`, `child_org_ids` now actually exercised (were dormant since Phase 2/3).
- **Key algorithms:** full `RulesEngine.evaluate_tick()` loop; succession-dispute weighted contest; schism member/resource split via `inherited_member_fraction_range` sampling; the "defeat → legitimacy hit → generic low-legitimacy rule fires" reuse chain.
- **UI additions:** `DebugSimPanel` extended with a scrolling "recent chronicle events" feed for visibility during long fast-forward runs.
- **Definition of done:** (1) fast-forwarding a fresh seeded game via the instant-advance debug shortcut until at least one `SCHISM` appears; inspect the new org's `parent_org_id`/`origin_event_id` and confirm they point at a real existing parent/event. (2) forcing a leader death with 2+ living heirs produces either a clean `SUCCESSION` or a `SUCCESSION`+`SCHISM` pair, fully chronicled. (3) authoring one new `TriggerRule` `.tres` with zero GDScript changes fires correctly under the right conditions.
- **Headless verification:** the highest-value target for Section H's invariant harness — `tests/test_lineage_invariants.gd`: seeded `advance_n_ticks_instant(50000)`, then for every `Organization` assert the `parent_org_id` walk terminates (cycle-guarded) at exactly one `""`-rooted org per `kind`; same check for every individual's `father_id`/`mother_id` chain.

### Phase 5 — Player god-power layer (resources/disasters/events)
- **Goal:** replace the Phase 1 debug sliders with the real `GodPowerAPI` boundary and full disaster system.
- **Deliverables:** `autoload/god_power_api.gd`; `data_model/disaster_definition.gd, disaster_instance.gd`; `data/disasters/*.tres` (the 7 disasters from Section D); `GameState.step_resources()` extended to apply/expire `active_disasters`; `HistoryEvent.EventType` usage for `DISASTER_OCCURRED`/`RESOURCE_SHOCK` with real payload + pre-rendered `description`.
- **Data model additions:** `WorldState.active_disasters` (stubbed since Phase 1, now populated).
- **Key algorithms:** disaster magnitude-over-duration curve application (**reuse `Curve`** again); `plague`'s hook into `Demography`'s death-probability modifier.
- **UI additions:** the real `GodPowerPanel.tscn` (sliders + disaster buttons + confirm popups), retiring the debug sliders as the only way to act on the world (debug panel keeps raw-dump features for QA).
- **Definition of done:** (1) dragging the real ore slider changes `global_ore` trend within the same session. (2) "Trigger Drought" → target/confirm → harvest/food figures dip for the configured duration then recover, with a sensible chronicled `DISASTER_OCCURRED` entry. (3) manual review confirms no script under `res://ui/` calls `HistoryLog.record()` or touches `Organization`/`NotableIndividual` setters directly.
- **Headless verification:** `tests/test_god_power_boundary.gd` — static source scan, fails the build if `HistoryLog.record(`, `.leader_person_id =`, `.power_score =`, or `.ideology.` appear under `res://ui/`; `tests/test_disasters.gd` asserts a triggered `DisasterInstance` applies and correctly expires.

### Phase 6 — Observation UI (map, chronicle, family tree, org tree, power dashboard)
- **Goal:** build the full Section E screen set on the now-complete backend, implementing the large-tree UX mechanisms (focus mode, collapsing, search).
- **Deliverables:** `ui/screens/WorldMapView.tscn` (+`SettlementDetailPanel.tscn`), `ChronicleTimeline.tscn` (+ lazy segment load), `ui/lineage/LineageGraphView.tscn` + both data sources, thin `GenealogyTreeView.tscn`/`OrgLineageView.tscn` wrappers, `PowerDashboard.tscn`, `ui/main/Main.tscn` + `screen_manager.gd` (nav shell), `systems/name_index.gd`.
- **Data model additions:** none — pure presentation over Phases 1–5's data.
- **Key algorithms:** focus-mode BFS from the focused node up to a configurable ancestor/descendant depth; collapse/expand session state (not persisted); substring/fuzzy name search over the prebuilt index; lazy segment-load trigger near scroll boundary.
- **UI additions:** this phase *is* the UI addition — all six screens + navigation shell.
- **Definition of done:** (1) navigate all six screens without errors. (2) genealogy search re-centers focus mode on a known descendant, showing ancestors up to the founder. (3) "Jump to Founder" works from any focus depth. (4) on a long fast-forwarded save with several schisms (reuse Phase 4's stress test), collapsing/expanding an Org Tree branch changes visible node count correctly, and every visible node traces to the single root for its kind. (5) Power Dashboard's driver breakdown matches Phase 3's debug numbers. (6) on a physical device, touch targets are comfortable one-handed and pinch-zoom/pan work on the map and both graph views.
- **Headless verification:** mostly manual (visual/UX-heavy), but data adapters are unit-testable: `tests/test_lineage_data_source.gd` checks `get_children()` against known fixtures for both adapters.

### Phase 7 — Android build hardening / performance / polish
- **Goal:** take the feature-complete game to a well-behaved release build — non-functional quality, not new gameplay systems.
- **Deliverables:** an on-device profiling pass (Godot's Debugger/Profiler via remote debug); tuning of `power_recalc_epoch_ticks`, `RulesEngine` throttling, `GraphEdit` node instancing based on measured bottlenecks; full lifecycle handling (`NOTIFICATION_APPLICATION_RESUMED` catch-up, building on Phase 1's pulled-forward autosave); final `export_presets.cfg` hardening (icons/splash, target SDK re-verified against Play's *current* requirement — see Section G); release keystore finalized and secured outside the repo; a permissions audit (this game needs no camera/mic/location/network permission — confirm the export preset requests nothing beyond engine defaults, e.g. checking/removing `INTERNET` if genuinely unused).
- **Data model additions:** a reserved `SaveCodec` schema-version-bump/migration slot, if hardening surfaces a breaking field change.
- **Key algorithms:** `Engine.max_fps`/`OS.low_processor_usage_mode` tuning for battery (cap render FPS — this is a low-action-rate sim — never throttle `SimClock`'s real-time basis); compaction cadence re-tuned against real soak-test save sizes.
- **UI additions:** polish only — loading spinners, empty-state messaging, a settings screen (catch-up-on-resume toggle, tick rate). Sound is explicitly unscoped by this design.
- **Definition of done:** (1) a multi-thousand-tick soak-test save loads in an acceptably short time on a real mid-range device (concrete target: under ~3s, validated on-device). (2) backgrounding/returning after a delay, including force-close while backgrounded, never crashes or corrupts the save. (3) on-device profiling shows no core pegged at 100% while idle/paused. (4) `godot --headless --export-release "Android" build/keizai-release.apk` installs cleanly on a clean device.
- **Headless verification:** export exit-code check; a final re-run of the **entire** Section H invariant suite at a larger tick count (e.g. 200,000+) as a release gate — this specifically catches a performance-tuning change accidentally breaking a correctness assumption Phase 4's rule engine relied on running every tick.

---

## G. Android Export Specifics

- **Backgrounding:** Godot Android apps stop rendering/processing when backgrounded by default — rely on this rather than a foreground service/wake-lock; there is no background-simulation feature (matches RimWorld/WorldBox precedent). `NOTIFICATION_APPLICATION_PAUSED` triggers an immediate autosave since a backgrounded app can be killed without a graceful-quit signal.
- **Battery:** cap `Engine.max_fps` (e.g. 30); consider `OS.low_processor_usage_mode = true` on menu-heavy screens.
- **Save growth:** addressed in Section A; segments are additionally gzip-compressed given mobile storage constraints and Android auto-backup size ceilings.
- **Min/target API level:** **min SDK 24** (Android 7.0) as a pragmatic floor. **Target SDK must be re-verified against Google Play's current requirement at each real export, not fixed at project start** — Play's target-API requirement moves roughly annually; Phase 7's DoD explicitly includes re-checking it at actual submission time rather than trusting a number written during planning.
- **Touch/screen adaptation:** `content_scale_mode = canvas_items` with `content_scale_aspect = expand` (favored over `viewport` for a `Control`-heavy app, so containers reflow across Android's aspect-ratio range instead of letterboxing); portrait-primary default (overridable per-screen); 48dp-equivalent minimum touch targets; safe-area insets via `DisplayServer.get_display_safe_area()`.
- **Export pipeline setup (Phase 0):** Android SDK command-line tools + a platform image matching the target API, OpenJDK 17, Godot's Android export templates installed via *Editor → Manage Export Templates* **matching the exact Godot version** (version mismatch is the most common export failure), Editor Settings → Export → Android pointed at SDK/JDK paths, an export preset with package name/orientation/icons, the auto-generated debug keystore for iterative testing, and a **separately generated** release keystore (`keytool -genkeypair -v -keystore release.keystore -alias keizai -keyalg RSA -keysize 2048 -validity 10000`) referenced via Editor Settings globally — never committed to version control. Losing this keystore means losing the ability to update the same Play listing, so back it up securely starting in Phase 0 even though it's only used for real in Phase 7.

---

## H. Testing & Verification Strategy

- **Seeded RNG via named sub-streams.** `RngService` (autoload) exposes named streams, each its own `RandomNumberGenerator` deterministically seeded from `world_seed + stream_name.hash()` (e.g. `RngService.stream(&"demography")`, `&"rules"`, `&"naming"`) — not one shared stream, because RNG consumers are added incrementally phase-by-phase, and a shared stream would make an old save's future draws sensitive to unrelated code added in a later phase. Every stochastic decision draws from a named stream, never ad hoc `randi()`. Each stream's `state` (not just `seed`) is persisted in the snapshot so a loaded game continues its exact sequence.
- **Headless fast-forward + assertions.** Standardize on **GUT** (`res://addons/gut/`), invoked via `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. `tests/sim_test_harness.gd` exposes `advance_n_ticks_instant(n)` (Section A), making 50,000+-tick invariant runs take seconds of CPU time.
- **Concrete invariant checks** (the automated release-gate suite, introduced incrementally per phase, run in full at Phase 4 and Phase 7):
  1. **Organization lineage: acyclic *and* single-root.** Walk `parent_org_id` with a visited-set cycle guard for every org; assert termination at the **same** `""`-parent org per `kind` — stronger than mere acyclicity (a disconnected multi-root forest would pass a naive cycle check but fail this game's actual requirement).
  2. **Individual ancestry terminates at founder generation.** Walk `father_id`/`mother_id` for every individual; assert termination at `""` or `is_founder_generation == true`, bounded depth, no cycles.
  3. **HistoryEvent referential integrity.** Every non-null `origin_event_id`/`related_person_ids`/`subject_org_id`/`subject_person_id` resolves to an entity that exists or existed — run specifically against `history/backbone.jsonl` to validate compaction never silently dropped a lineage-critical reference.
  4. **Power score bounds/sanity.** Every `power_score` stays within `[0, profile.max_score]`; `power_drivers` values sum to (approximately) the pre-clamp score.
  5. **Save/load round-trip equality.** Serialize a live `GameState`, deserialize, deep-compare field-by-field.
  6. **Determinism.** Run the same seed for N ticks twice in-process; assert the final `GameState` dump is byte-identical.
  7. **God-power API boundary** (Phase 5's static source-scan guard).
- **Manual vs. automated split.** Invariants 1–7 are fully headless-automatable and should run routinely. What stays manual is the subjective layer — does generated flavor text read well, does `GraphEdit` stay legible at scale, does touch UX feel good on-device, does performance feel smooth — matching each phase's own DoD split above.

---

## Critical Files (first created in, and defining for, the phases noted)

- `res://autoload/history_log.gd` (Phase 1) — the event-sourcing funnel every state mutation passes through; gets the traceability guarantee right or wrong for the whole project.
- `res://data_model/history_event.gd` (Phase 1) — the log-entry schema (`origin_event_id`/`parent_org_id` chain) the "always traceable to root" requirement is built on.
- `res://data_model/organization.gd` (Phase 2) — the shared base for Guild/House/Faction/PoliticalSystem; `parent_org_id`/`branch_depth`/`ideology` here make the schism/power/naming systems generic instead of per-kind special cases.
- `res://autoload/sim_clock.gd` (Phase 1) — the tick-loop accumulator decoupling simulation from frame rate and enabling both real-time play and instant headless fast-forward.
- `res://systems/power_calculator.gd` + `res://data_model/power_profile.gd` (Phase 3) — the data-driven scoring mechanism letting new archetypes plug into world-state without engine changes.
- `res://data_model/political_system_axes.gd` + `res://systems/political_system_generator.gd` (Phase 3) — the confirmed compositional political-system generator.
- `res://autoload/rules_engine.gd` + `res://data_model/trigger_rule.gd` (Phase 4) — the data-driven schism/succession engine.
- `res://autoload/god_power_api.gd` (Phase 5) — the sole player-facing mutation boundary; must never gain a political setter.

Godot built-ins to reuse rather than reinvent (referenced throughout): `Curve` (nonlinear driver/age/disaster-magnitude remapping), `GraphEdit`/`GraphNode` (both tree UIs), `RandomNumberGenerator` with persisted `.state` (deterministic named streams), `FileAccess.open_compressed(..., COMPRESSION_GZIP)` (history segments), `Resource.duplicate(true)` (deep-copying ideology axes on branch), `DisplayServer.get_display_safe_area()` (touch layout), `NOTIFICATION_APPLICATION_PAUSED`/`_RESUMED` (lifecycle/autosave).

---

## How to Verify End-to-End

Each phase's own "Definition of done" (Section F) is the primary verification unit — every phase must pass its manual checklist and its headless tests (once GUT exists from Phase 1 onward) before the next phase begins. Beyond per-phase checks:

1. **Full-run smoke test (after Phase 4):** fresh seeded game → `advance_n_ticks_instant(50000)` in the Godot editor's remote debugger or a debug button → run the full Section H invariant suite → expect zero failures, and expect to see at least one `SCHISM` and one contested `SUCCESSION` in the chronicle.
2. **Full observation loop (after Phase 6):** play manually for several in-game "years" at 2x/4x speed, occasionally pausing to (a) trigger a disaster from `GodPowerPanel`, (b) confirm the thematically-linked archetype's power rises in `PowerDashboard` within a couple epochs, (c) find the resulting chronicle entry in `ChronicleTimeline`, (d) if a schism resulted, confirm the new branch is visible and correctly rooted in `OrgLineageView`.
3. **Release gate (Phase 7):** `godot --headless --export-release "Android" build/keizai-release.apk` exits 0; install on a real device from a clean state; full Section H invariant suite passes at 200,000+ ticks; soak-test save load time meets the ~3s target.
4. **Regression safety net throughout:** run `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` after every phase's changes before moving on — this is cheap once GUT exists (Phase 1+) and is what keeps an 8-phase incremental build from silently regressing earlier phases' guarantees (especially the lineage invariants, which are easy to break unnoticed while iterating on rule content in Phase 4 and beyond).

---

## Where the implementation diverged from this plan

The plan above is kept as written for the record. These are the places the build
deliberately went another way, and why.

**Specialised institutions are invented, not seeded.** The plan listed seven
archetypes as the starting roster. The implementation starts with *four* root
organizations — one guild, one house, one faction, one political system — and
lets the monster-hunting order, artisan and merchant guilds, mage circle, temple
and farmers' movement appear later, as branches, when world conditions call for
them (`data/rules/specialize_*.tres`). This satisfies "最初の本流は一つ" literally
rather than approximately, and it turns the roster into the thing the game is
actually about: the society inventing what it needs. Their power profiles are
unchanged from the plan.

**One `Organization` class instead of four subclasses.** GDScript cannot let a
base class construct its own subclasses without a cyclic `class_name`
dependency, which would have meant a separate factory file purely to work around
the language. Since every system handles the four kinds uniformly — the same
lineage walk, the same power calculator, the same schism rules — a `kind`
discriminator with six kind-specific fields serves the design's actual goal
better than the subclass hierarchy would have.

**A small custom test runner instead of GUT.** What the plan actually required
was headless fast-forward plus invariant assertions plus an exit code. That is
about a hundred lines (`tests/spec.gd`, `tests/test_runner.gd`), and it avoids
vendoring a large addon whose doubles, stubs and editor panel this project never
uses. The invariant suite itself is as specified, and larger: 22,000 checks.

**Lineage trees are drawn directly rather than with `GraphEdit`.** These are
trees, not general graphs, and they are read on a phone. A layered layout with
its own touch handling gave a far more legible result than `GraphEdit`'s
editor-flavoured nodes, and focus mode, collapsing and search all needed custom
behaviour regardless. In the whole-tree view the four root trees stack
vertically, because side by side they do not fit a portrait screen.

**Save history is buffered in memory and written in segments on save**, rather
than appended continuously. The guarantees are the same — segmented, compressed,
with an uncompactable lineage backbone — and compaction keeps the buffer bounded,
so the simpler scheme costs nothing. Note the segment files use Godot's own
compressed container (deflate), so they are not readable by `gunzip`; the
extension is `.jsonl.z` rather than the plan's `.jsonl.gz` to avoid implying
otherwise.

**Balance work the plan could not anticipate.** Playtesting through the
diagnostic tool surfaced several problems that needed model changes, not tuning:
monsters could be driven to exactly zero and never return (multiplicative growth
from nothing), so a small additive baseline spawn was added; unrest accumulated
rather than tracking conditions, so it pinned at maximum and never recovered;
organizations only ever lost members at a schism, so the world decayed into
five-member remnants, and membership now follows influence and population;
ideological schisms repeated forever because the split never resolved the drift
that caused it, so a parent now re-baselines its ideology after one; and a
single well-connected claimant could end up ruling several rival states at once,
so nobody may now hold two seats of the same kind.

**Not verified: the APK on a real device.** Both APKs build and their signatures
verify (debug 32MB, release 30MB, arm64-v8a, no permissions requested, min SDK
24 / target SDK 36), and every screen was rendered and inspected under a virtual
display. But no Android device or emulator was available, so touch feel, pinch
gestures, resume-from-background and on-device load times remain unchecked.

---

## Second iteration: houses as the substrate

A round of changes after the first build, in response to the parts of the world
that did not yet mean anything.

**People come only from houses.** Previously, when a guild needed a master and
nobody suitable was alive, one was invented — flagged founding-generation so the
ancestry walk still terminated. That kept the invariant but hollowed out the
family tree: half the cast had no relations. Now the world begins with one house
per region and *nothing* creates a person afterwards. Every guild master, every
monarch, is somebody's child. A house that stops producing heirs dies out, and
what it held is taken over by whoever is standing.

This made the demographic model load-bearing in a way it had not been, and three
things had to change before the world could survive its own history: widows could
never remarry, which alone was enough to extinguish the entire notable population
within four centuries; the crowding cap only ever pushed fertility down, so a bad
century had no recovery; and famine reached the great houses as hard as it
reached the fields. Marriage after widowhood, a fertility floor that rises as the
houses thin, and a ceiling on how far catastrophe can raise notable mortality
between them keep the cast stable around fifty to a hundred and fifty people
without anyone being conjured up.

**A surname is a house's name, not a person's.** `given_name` is stored;
`family_name` mirrors whichever house the person currently belongs to. A bride
joins her husband's house and takes its name — unless she heads a house herself,
in which case he marries in, which is how a house with no sons survives. A cadet
branch takes its founder's line with it, and they take the new name, so a 分家 is
legible in the family tree without reading the edges. Renaming a house renames
every living member.

**Regions have industry.** Each has one of mining, forestry, farming, trade or
frontier work, which bends what it produces and decides which guild has a claim
there — a mining valley lifts the artisans and ignores the farmers. Since
production is now lopsided, the realm shares food between the regions it governs;
without that, any region whose industry is not food starves to the floor and
stays there, which is eight unrelated villages rather than a country.

**The form of government is derived, not set.** Factions and political systems
were each legible on their own but did not add up to anything. Now the balance
between houses, guilds and factions is read every epoch against the forms in
`data/polity_forms/` and produces one: a dominant temple faction makes a
theocracy, a merchants' guild with an assembly makes a merchant republic, houses
holding their own land make a feudal kingdom. The form decides what the head of
state is called and what a house head holding a region is called — count,
high priest, mayor. Nobody declares any of it; the country simply becomes
something else, and the chronicle notes that it has.

**Houses regard each other.** Standing between two houses is recomputed from
what is currently true rather than accumulated: marriage ties and shared blood
draw them together, a contested office or a widening gap in ideals pushes them
apart, and the house wearing the crown is resented by the ones that are not.
Because it is read rather than remembered, a feud ends when its cause does. This
also required giving each institution a fixed character of its own — derived from
its identity, so it survives save and reload — since pulled only by world
conditions every house drifted to the same position and none of them ever found
anything to disagree about.

**Naming is the player's, and is not a god power.** `NamingService` is separate
from `GodPowerAPI` on purpose: naming a place changes no number and shifts no
outcome, so it does not belong behind the boundary that keeps the player out of
politics. That boundary is unchanged and still checked mechanically.

---

## Third iteration: the wiring between the elements

The four kinds of institution each worked and none of them touched. A guild
could double its influence without the crown noticing; a faction was an opinion
with no constituency; a political system drifted through adjectives without ever
becoming a different kind of thing. This round is almost entirely about the
links, plus the two consequences that only became possible once the links
existed.

**Everything horizontal is derived, none of it is stored as sentiment.**
`SocialTies.refresh_all()` runs once an epoch and reads four relations off
things that are already true:

- *A family owning an office.* One sweep over everyone who ever held a post
  totals, per body, how long each house has held it. Past a share of its whole
  recorded history the office is that house's — and then the office starts to
  admit it, drifting toward hereditary legitimacy, which makes the next
  succession draw from the same house again. When the family dies out the hold
  releases and the seat goes back to being argued over. This loop is the answer
  to 世襲制／実力制／協議制: they are not settings, they are what a body's history
  has made of it.
- *A support base.* Which houses and guilds stand behind a faction, from
  ideological distance, offices held, a shared patron family, and whether the
  land a house holds is ground the faction speaks for.
- *A chamber.* Seats divided among the factions by influence and by how much of
  the realm leans their way, allocated by largest remainder with ties broken on
  org id so a replay divides the room the same way. The chamber's size comes
  from the form of government, so a country that becomes a republic grows a room
  to argue in.
- *Leaning land.* Each region is with somebody, from its industry, its ruling
  house's allegiances, and its dominant guild's.

**家格.** `HouseRank` gives every house a tier from its land, standing, the crown
and its age — capped by a quota, because a peerage is comparative and a country
with eight dukes has none. What makes it worth having is that its *weight* is
not constant: `PolityForm.rank_weight` says how much a form of government cares,
`PowerProfile.rank_sensitivity` says how much a kind of body cares, and the two
multiply. Under a feudal crown a name decides successions, wins vacant counties
and is the title its holder is addressed by; under a popular assembly the same
name is worth almost nothing, and a hunters' lodge never cared either way.

**Regimes can now be taken.** Ideology drifted but institutions did not, so the
crown survived everything. `RegimeShift` measures who is actually holding the
country up — a bloc with two seats in five, an estate of guilds outweighing the
throne, or a population angry enough that neither matters — and drains the
regime's legitimacy while that lasts. When a challenger's hold exceeds what is
left of the regime's standing, the discrete facts change hands: legitimacy basis
and decision structure are rewritten in the winner's image, the country's ideals
are dragged most of the way to theirs, and unless the new order still runs on
blood the sitting ruler is deposed and the seat refilled next tick under the new
rules. Those two fields are institutional facts rather than continuous values,
so unlike the drifting axes they change through `HistoryLog.record()` and
nowhere else.

**Crises produce politics nobody had tried.** Schism rules gained a `radicalism`
scale and the ability to set the branch's own legitimacy basis and decision
structure. An ordinary split is a disagreement about degree and inherits nearly
everything; a radical one keeps the lineage and little else. Five archetypes are
authored against extreme conditions — levellers out of famine and anger,
millenarians out of unending calamity, a junta out of an existential threat,
free cities out of wealth the crown cannot tax, technocrats where craft and
magic outrun tradition. Two ceilings keep this legible rather than noisy: a
society carries at most three bodies of any one archetype, so whichever
archetype the world currently rewards cannot split into seven variations of
itself, and a branch introducing a kind of institution the world does not yet
have may exceed the per-kind ceiling, because a society always has room for
something it has never had before.

**One family tree instead of eight.** The old view drew a tree per founding
couple. Since houses only meet by marriage, everyone who married out appeared
twice — once beside their partner and once at the head of their own line — and
the marriage joining the two families read as a coincidence of surnames. The
family view is now laid out by generation: households (a person, or a married
pair) are placed on a row, each person appears exactly once, and the marriage
lines are what hold the houses together. Rows come from birth date rather than
depth of descent, because people marry across generations and counting descent
inflates to fifty-odd rows over four centuries; a relaxation pass then pushes
any household below its parents, so the ordering stays true. Ordering within a
row is a few barycentre sweeps, and placement recentres each row on its own
centre of gravity after resolving overlaps — without that, resolving overlaps
rightward walks the chart wider on every sweep. Organization lineages are
genuinely forests and keep the old layout.
