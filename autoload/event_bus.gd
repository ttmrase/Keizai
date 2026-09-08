extends Node

## Decouples the simulation from the UI. Systems emit; screens listen. Nothing
## in ui/ is allowed to reach back into simulation state to mutate it.

signal tick_advanced(tick: int)
signal event_recorded(event: HistoryEvent)
signal power_recalculated(tick: int)
signal world_reset()
signal game_loaded()
signal save_completed(slot: int)
signal speed_changed(time_scale: float)
