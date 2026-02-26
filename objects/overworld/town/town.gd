extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.TOWN

enum STAGES { SMALL, MEDIUM, BIG, RAZED }

@export var stage = STAGES.SMALL

var fields = []

@export var player_owner = 1

var population
var base_pop_growth = 0.05
var predicted_growth

func _ready() -> void:
	get_start_data()
	

func get_start_data():
	get_pop()
	calculate_predicted_growth()


func calculate_predicted_growth() -> void:
	predicted_growth = population * base_pop_growth

func get_pop():
	var pop := {
		STAGES.SMALL: 300,
		STAGES.MEDIUM: 600,
		STAGES.BIG: 900,
		STAGES.RAZED: 0,
	}
	
	population = pop[stage]
	
