class_name PolityForm
extends Resource

## A recognisable form of government, and what it calls the people who hold
## office under it.
##
## The form is never chosen directly. It is read off the balance of power each
## epoch: which faction speaks loudest, whether the guilds or the houses hold
## more standing, and what the regime's own institutions have drifted into. So
## "kingdom" and "merchant republic" are descriptions of a situation, not
## settings — and when the situation changes, the country's name for itself
## changes with it.

@export var form_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## All must hold. Evaluated against the political system organization.
@export var conditions: Array[RuleCondition] = []
## Checked highest first; the first form that matches wins.
@export var priority: int = 0

## What the head of state is called.
@export var ruler_title: String = "国王"
## What the head of a house holding a region is called under this form.
@export var local_ruler_title: String = "領主"
## What the assembly or court of this form is called, for flavour in the UI.
@export var council_label: String = "宮廷"
## How much pedigree counts under this form, 0..1. A hereditary monarchy runs on
## it; a popular republic barely notices a family name. Read by HouseRank, so the
## same 家格 is worth a great deal in one century and nothing in the next.
@export var rank_weight: float = 0.6
## How many seats the chamber of this form holds. A court is a handful of people
## around a throne; an assembly is a room full of them, which is what makes the
## division of seats between factions worth reading at all.
@export var chamber_seats: int = 12
