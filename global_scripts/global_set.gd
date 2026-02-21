extends Node

var load_saved_continue = false
var settings: Dictionary = {}

func _ready() -> void:
	SettingsLoad.load_settings()
