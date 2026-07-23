extends VBoxContainer

@onready var main_menu: Control = get_node("../../..")

func _on_continue_btn_pressed() -> void:
	GlobalSet.load_saved_continue = true
	# TODO: change to your game scene when you have it
	# get_tree().change_scene_to_file("res://path/to/game_scene.tscn")
	# For now we only set the flag; add scene when game exists
	pass

func _on_new_game_btn_pressed() -> void:
	main_menu._on_new_game_btn_pressed()

func _on_load_game_btn_pressed() -> void:
	# TODO: open load game UI or scene
	pass

func _on_settings_btn_pressed() -> void:
	main_menu._on_settings_btn_pressed()

func _on_exit_btn_pressed() -> void:
	get_tree().quit()
