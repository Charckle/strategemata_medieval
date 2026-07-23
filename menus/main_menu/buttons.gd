extends VBoxContainer

@onready var main_menu: Control = get_node("../../..")

func _on_continue_btn_pressed() -> void:
	main_menu._on_continue_btn_pressed()

func _on_new_game_btn_pressed() -> void:
	main_menu._on_new_game_btn_pressed()

func _on_load_game_btn_pressed() -> void:
	main_menu._on_load_game_btn_pressed()

func _on_settings_btn_pressed() -> void:
	main_menu._on_settings_btn_pressed()

func _on_exit_btn_pressed() -> void:
	get_tree().quit()
