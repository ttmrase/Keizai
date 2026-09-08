class_name LineageSource
extends RefCounted

## What a lineage tree needs to know about whatever it is drawing. Implemented
## once for organizations and once for people, so the focus, collapse and search
## behaviour is written a single time and both trees get it.

func roots() -> Array[StringName]:
	return []


func children(_id: StringName) -> Array[StringName]:
	return []


func parents(_id: StringName) -> Array[StringName]:
	return []


## People a node is married to. Organizations have none; the family tree draws
## them beside their partner and hangs the children off the pair.
func spouses(_id: StringName) -> Array[StringName]:
	return []


func label(_id: StringName) -> String:
	return ""


func sublabel(_id: StringName) -> String:
	return ""


func colour(_id: StringName) -> Color:
	return Palette.TEXT


func is_faded(_id: StringName) -> bool:
	return false


## BBCode shown when a node is tapped.
func detail(_id: StringName) -> String:
	return ""


func search(_query: String) -> Array[StringName]:
	return []


func exists(_id: StringName) -> bool:
	return false
