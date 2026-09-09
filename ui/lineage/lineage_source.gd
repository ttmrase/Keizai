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


## Every node, for a source whose shape is a graph rather than a forest of trees.
func all_ids() -> Array[StringName]:
	return []


## True when this source should be laid out by generation rather than as trees
## hanging from roots. A family tree has to be: the marriages between houses are
## edges of the same graph, so drawing each house as its own tree means drawing
## every married couple twice, once in each family. Organizations really are a
## forest — a guild has one parent guild — and stay that way.
func is_generational() -> bool:
	return false


## The generation a node sits in: 0 for the founding cohort, otherwise one below
## the deepest parent. Only meaningful for a generational source.
func generation(_id: StringName) -> int:
	return 0
