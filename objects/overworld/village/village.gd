extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.VILLAGE

enum STAGES { EMPTY, SMALL, MEDIUM, BIG, RAZED }

@export var stage = STAGES.SMALL

@onready var village_sprite: Sprite2D = $building_spr

var fields = []

@export var player_owner = 1

var population
var base_pop_growth = 0.05
var predicted_growth
var predicted_marks = 0

func _ready() -> void:
	update_for_stage()
	get_start_data()
	
	
func update_for_stage():
	change_sprite()


func change_sprite():
	var textures := {
		STAGES.EMPTY: preload("res://sprites/overworld/objects/province/village/village.png"),
		STAGES.SMALL: preload("res://sprites/overworld/objects/province/village/village.png"),
		STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/village/village.png"),
		STAGES.BIG: preload("res://sprites/overworld/objects/province/village/village.png"),
		STAGES.RAZED: preload("res://sprites/overworld/objects/province/village/village.png")
	}
	
	if stage == STAGES.EMPTY:
		village_sprite.visible = false
	else:
		village_sprite.texture = textures[stage]


func get_start_data():
	get_pop()
	calculate_predicted_growth()
	calculate_predicted_marks()


func calculate_predicted_marks() -> void:
	predicted_marks = int(ceil(population * 0.10))


func calculate_predicted_growth() -> void:
	predicted_growth = population * base_pop_growth

func get_pop():
	var pop := {
		STAGES.EMPTY: 0,
		STAGES.SMALL: 20,
		STAGES.MEDIUM: 60,
		STAGES.BIG: 120,
		STAGES.RAZED: 0,
	}
	
	population = pop[stage]
