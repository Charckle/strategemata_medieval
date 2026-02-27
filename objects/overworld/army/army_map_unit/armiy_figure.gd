extends Node2D

@export var player_owner = 0

var base_map 

func setup_building() -> void:
	set_flags()


func set_flags():
	print("Iran")
	$Flag.setup_flag()
