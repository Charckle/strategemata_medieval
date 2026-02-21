extends Control

func _ready() -> void:
	hide_all_overlays()
	_apply_display_settings()
	if ContinueGame.check_continue_exists():
		$center/panel/buttons/continue_btn.visible = true
	else:
		$center/panel/buttons/continue_btn.visible = false

func _apply_display_settings() -> void:
	if GlobalSet.settings.get("fullscreen", 0) == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func hide_all_overlays() -> void:
	$overlays/settings_pan.visible = false

func _on_settings_btn_pressed() -> void:
	hide_all_overlays()
	$overlays/settings_pan.visible = true
