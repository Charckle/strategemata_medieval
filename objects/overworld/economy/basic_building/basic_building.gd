extends Node2D

enum SUBTYPES { WOODCUTTER, IRONMINE, GOLDMINE, SILVERMINE, STONEQUARRY, BLACKSMITH }

var type_ = GlobalStuff.BUILDING_TYPE.ECONOMY
@export var subtype = SUBTYPES.WOODCUTTER

enum STAGES { EMPTY, SMALL, MEDIUM, BIG, RAZED }

@export var stage = STAGES.SMALL

@onready var building_spr: Sprite2D = $building_spr


func _ready() -> void:
	update_for_stage()
	
	
func update_for_stage():
	change_sprite()


func change_sprite():
	var textures := {
		SUBTYPES.WOODCUTTER: 
			{
			STAGES.SMALL: preload("uid://c43brywdf0lxo"),
			},
		SUBTYPES.STONEQUARRY: 
			{
			STAGES.SMALL: preload("uid://ft668a4yuq1k"),
			}
	}
	
	if stage == STAGES.EMPTY:
		building_spr.visible = false
	else:
		building_spr.texture = textures[subtype][stage]
