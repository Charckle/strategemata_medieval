extends Node

var continue_path := "user://continue_game.json"

func save_continue(game_state: Dictionary) -> void:
	var file = FileAccess.open(continue_path, FileAccess.WRITE)
	if file:
		var json_text = JSON.stringify(game_state, "\t")
		file.store_string(json_text)
		file.close()
	else:
		push_error("Could not open continue file for writing: %s" % continue_path)

func load_continue() -> Dictionary:
	var file = FileAccess.open(continue_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(content)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
		else:
			push_error("Failed to parse continue JSON as dictionary.")
	else:
		push_error("Could not open continue file for reading: %s" % continue_path)
	return {}

func check_continue_exists() -> bool:
	return FileAccess.file_exists(continue_path)

func delete_continue() -> void:
	if FileAccess.file_exists(continue_path):
		var err := DirAccess.remove_absolute(continue_path)
		if err != OK:
			push_error("Failed to delete %s (err %d)" % [continue_path, err])
