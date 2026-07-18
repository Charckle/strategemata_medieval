extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.FIELD

enum GROWN_STAGES { EMPTY, WINTER, SPRING, SUMMER, AUTUMN }
enum CROP { EMPTY, GRAIN, HORSES }

@export var grown_stage = GROWN_STAGES.EMPTY
@export var crop: CROP = CROP.EMPTY

## True once grain seed was spent (confirmed at end of winter); false until next sow.
var planted: bool = false
## Visual-only: underworked grain fields look idle but keep their crop assignment.
var neglected: bool = false
## Visual-only: horses placed on this pasture after holding stock is distributed.
var display_horses: int = 0

@onready var field_sprite: Sprite2D = $field_sprite

var owner_building


func get_pathfinding_blocked_tile_centers() -> Array:
	return [global_position + Vector2(32, 16)]


func _ready() -> void:
	update_visuals()


func get_controller_id() -> int:
	if owner_building != null and owner_building.get("player_owner") != null:
		return int(owner_building.player_owner)
	return -1


func get_crop_name() -> String:
	match crop:
		CROP.GRAIN: return "Grain"
		CROP.HORSES: return "Horses"
		_: return "Idle"


## Assign crop use. Does not spend seed — province.try_sow_field handles planting.
func set_crop(new_crop: int, season: int) -> void:
	var staying_sown := (crop == CROP.GRAIN and planted and int(new_crop) == int(CROP.GRAIN))
	crop = new_crop as CROP
	neglected = false
	if not staying_sown:
		planted = false
	if crop != CROP.HORSES:
		display_horses = 0
	update_visuals_for_season(season)


func mark_sown() -> void:
	planted = true
	neglected = false


func clear_after_harvest() -> void:
	planted = false
	neglected = false


func update_visuals_for_season(season: int) -> void:
	if crop == CROP.EMPTY or neglected:
		grown_stage = GROWN_STAGES.EMPTY
	elif crop == CROP.HORSES:
		grown_stage = GROWN_STAGES.SPRING
	elif crop == CROP.GRAIN:
		if planted:
			match season:
				0: grown_stage = GROWN_STAGES.WINTER
				1: grown_stage = GROWN_STAGES.SPRING
				2: grown_stage = GROWN_STAGES.SUMMER
				3: grown_stage = GROWN_STAGES.AUTUMN
				_: grown_stage = GROWN_STAGES.EMPTY
		elif int(season) == 0:
			# Winter plan marker: looks sown; seed spent when leaving winter.
			grown_stage = GROWN_STAGES.WINTER
		else:
			grown_stage = GROWN_STAGES.EMPTY
	update_visuals()


func update_visuals() -> void:
	change_sprite()


func update_for_growth() -> void:
	update_visuals()


func change_sprite() -> void:
	if field_sprite == null:
		return
	if crop == CROP.HORSES:
		if display_horses > 0:
			field_sprite.texture = preload("uid://b0d4fpwlqrylg") # field_horse_occupied
		else:
			field_sprite.texture = preload("uid://bq8885n2ex0eh") # field_horse_occupied_empty
		return
	var textures := {
		GROWN_STAGES.EMPTY: preload("uid://pg7qvgiwn0ld"),
		GROWN_STAGES.WINTER: preload("uid://4rt1ci43b6h7"),
		GROWN_STAGES.SPRING: preload("uid://bvwlf26g7mwg5"),
		GROWN_STAGES.SUMMER: preload("uid://kjuwmnlo8gk0"),
		GROWN_STAGES.AUTUMN: preload("uid://bxrkdfvsesd0s")
	}
	field_sprite.texture = textures[grown_stage]
