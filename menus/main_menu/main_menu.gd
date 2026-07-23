extends Control

func _ready() -> void:
	hide_all_overlays()
	_apply_display_settings()
	if ContinueGame.check_continue_exists():
		$center/panel/buttons/continue_btn.visible = true
	else:
		$center/panel/buttons/continue_btn.visible = false
	if GlobalSet.return_to_new_game:
		GlobalSet.return_to_new_game = false
		_on_new_game_btn_pressed()

func _apply_display_settings() -> void:
	if GlobalSet.settings.get("fullscreen", 0) == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func hide_all_overlays() -> void:
	$overlays/settings_pan.visible = false
	if has_node("overlays/new_game_pan"):
		$overlays/new_game_pan.visible = false

func _on_settings_btn_pressed() -> void:
	hide_all_overlays()
	$overlays/settings_pan.visible = true

func _on_new_game_btn_pressed() -> void:
	hide_all_overlays()
	var pan := $overlays/new_game_pan
	if pan.has_method("reset_to_defaults"):
		pan.reset_to_defaults()
	pan.visible = true
