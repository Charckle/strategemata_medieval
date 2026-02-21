extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.VILLAGE

enum STAGES { EMPTY, SMALL, MEDIUM, BIG, RAZED }

@export var stage = STAGES.SMALL

@onready var village_sprite: Sprite2D = $building_spr

func _ready() -> void:
	update_for_stage()
	
	
func update_for_stage():
	change_sprite()


func change_sprite():
	var textures := {
		STAGES.SMALL: preload("res://sprites/overworld/objects/province/village/village.png"),
	}
	
	if stage == STAGES.EMPTY:
		village_sprite.visible = false
	else:
		village_sprite.texture = textures[stage]
