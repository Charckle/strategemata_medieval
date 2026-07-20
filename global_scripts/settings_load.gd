extends Node

var config_path := "user://settings.json"

func create_config_if_not() -> void:
	if not FileAccess.file_exists(config_path):
		var default_file = FileAccess.open("res://default_data/settings.json", FileAccess.READ)
		if default_file:
			var json_text = default_file.get_as_text()
			default_file.close()
			var user_file = FileAccess.open(config_path, FileAccess.WRITE)
			if user_file:
				user_file.store_string(json_text)
				user_file.close()

func save_settings() -> void:
	create_config_if_not()
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		var json_text = JSON.stringify(GlobalSet.settings, "\t")
		file.store_string(json_text)
		file.close()
	else:
		push_error("Could not open config file for writing: %s" % config_path)

func load_settings() -> void:
	create_config_if_not()
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(content)
		if typeof(parsed) == TYPE_DICTIONARY:
			GlobalSet.settings = parsed
			_merge_default_settings()
		else:
			push_error("Failed to parse settings JSON as dictionary.")
			GlobalSet.settings = {}
	else:
		push_error("Could not open config file for reading: %s" % config_path)
		GlobalSet.settings = {}


func _merge_default_settings() -> void:
	var default_file := FileAccess.open("res://default_data/settings.json", FileAccess.READ)
	if default_file == null:
		return
	var defaults = JSON.parse_string(default_file.get_as_text())
	default_file.close()
	if typeof(defaults) != TYPE_DICTIONARY:
		return
	var changed := false
	for key in defaults:
		if not GlobalSet.settings.has(key):
			GlobalSet.settings[key] = defaults[key]
			changed = true
	if changed:
		save_settings()
