extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.FIELD

enum GROWN_STAGES { EMPTY, WINTER, SPRING, SUMMER, AUTUMN }

@export var grown_stage = GROWN_STAGES.SUMMER

@onready var field_sprite: Sprite2D = $field_sprite

var owner_building

# Returns global positions of tile centers this object blocks (for pathfinding).
func get_pathfinding_blocked_tile_centers() -> Array:
	# 1 tile: center at position + (32, 16) for 64x32 isometric
	return [global_position + Vector2(32, 16)]

func _ready() -> void:
	update_for_growth()
	
	
func update_for_growth():
	change_sprite()
	
	
func change_sprite():
	var textures := {
		GROWN_STAGES.EMPTY: preload("uid://pg7qvgiwn0ld"),
		GROWN_STAGES.WINTER: preload("uid://4rt1ci43b6h7"),
		GROWN_STAGES.SPRING: preload("uid://bvwlf26g7mwg5"),
		GROWN_STAGES.SUMMER: preload("uid://kjuwmnlo8gk0"),
		GROWN_STAGES.AUTUMN: preload("uid://bxrkdfvsesd0s")
	}
	
	field_sprite.texture = textures[grown_stage]
