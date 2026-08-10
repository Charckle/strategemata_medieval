extends PanelContainer

const VOLUME_MIN_DB := -50.0
const VOLUME_MAX_DB := 0.0

func _ready() -> void:
	populate_settings()

func populate_settings() -> void:
	if GlobalSet.settings.is_empty():
		return
	# Audio: 0.0–1.0 from settings, apply to buses
	_apply_audio_volumes()
	var m = GlobalSet.settings.get("master_volume", 1.0)
	var s = GlobalSet.settings.get("sfx_volume", 1.0)
	var mus = GlobalSet.settings.get("music_volume", 1.0)
	$margin/vbox/tabs/Audio/content/master_row/master_slider.value = m
	$margin/vbox/tabs/Audio/content/sfx_row/sfx_slider.value = s
	$margin/vbox/tabs/Audio/content/music_row/music_slider.value = mus
	var music_on = int(GlobalSet.settings.get("music_enabled", 1))
	var sfx_on = int(GlobalSet.settings.get("sfx_enabled", 1))
	$margin/vbox/tabs/Audio/content/music_on_off_row/music_on_off_btn.selected = $margin/vbox/tabs/Audio/content/music_on_off_row/music_on_off_btn.get_item_index(music_on)
	$margin/vbox/tabs/Audio/content/sfx_on_off_row/sfx_on_off_btn.selected = $margin/vbox/tabs/Audio/content/sfx_on_off_row/sfx_on_off_btn.get_item_index(sfx_on)
	# Video
	var fs = GlobalSet.settings.get("fullscreen", 0)
	$margin/vbox/tabs/Video/content/fullscreen_row/fullscreen_btn.selected = $margin/vbox/tabs/Video/content/fullscreen_row/fullscreen_btn.get_item_index(int(fs))
	var weather_on = GlobalSet.settings.get("show_weather", 1) != 0
	$margin/vbox/tabs/Video/content/show_weather_row/show_weather_chk.button_pressed = weather_on
	var season_tint_on = GlobalSet.settings.get("show_season_tint", 1) != 0
	$margin/vbox/tabs/Video/content/show_season_tint_row/show_season_tint_chk.button_pressed = season_tint_on

func _linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return VOLUME_MIN_DB
	return VOLUME_MIN_DB + linear * (VOLUME_MAX_DB - VOLUME_MIN_DB)

func _db_to_linear(db: float) -> float:
	if db <= VOLUME_MIN_DB:
		return 0.0
	return (db - VOLUME_MIN_DB) / (VOLUME_MAX_DB - VOLUME_MIN_DB)

func _apply_audio_volumes() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	var sfx_idx = AudioServer.get_bus_index("sfx")
	var music_idx = AudioServer.get_bus_index("music")
	if master_idx >= 0:
		var v = GlobalSet.settings.get("master_volume", 1.0)
		AudioServer.set_bus_volume_db(master_idx, _linear_to_db(v))
	if sfx_idx >= 0:
		var v = GlobalSet.settings.get("sfx_volume", 1.0)
		AudioServer.set_bus_volume_db(sfx_idx, _linear_to_db(v))
		AudioServer.set_bus_mute(sfx_idx, GlobalSet.settings.get("sfx_enabled", 1) == 0)
	if music_idx >= 0:
		var v = GlobalSet.settings.get("music_volume", 1.0)
		AudioServer.set_bus_volume_db(music_idx, _linear_to_db(v))
		AudioServer.set_bus_mute(music_idx, GlobalSet.settings.get("music_enabled", 1) == 0)

func _on_master_slider_value_changed(value: float) -> void:
	GlobalSet.settings["master_volume"] = value
	SettingsLoad.save_settings()
	var idx = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _linear_to_db(value))

func _on_sfx_slider_value_changed(value: float) -> void:
	GlobalSet.settings["sfx_volume"] = value
	SettingsLoad.save_settings()
	var idx = AudioServer.get_bus_index("sfx")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _linear_to_db(value))

func _on_music_slider_value_changed(value: float) -> void:
	GlobalSet.settings["music_volume"] = value
	SettingsLoad.save_settings()
	var idx = AudioServer.get_bus_index("music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _linear_to_db(value))

func _on_music_on_off_btn_item_selected(index: int) -> void:
	var enabled: int = $margin/vbox/tabs/Audio/content/music_on_off_row/music_on_off_btn.get_item_id(index)
	GlobalSet.settings["music_enabled"] = enabled
	SettingsLoad.save_settings()
	var idx = AudioServer.get_bus_index("music")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, enabled == 0)

func _on_sfx_on_off_btn_item_selected(index: int) -> void:
	var enabled: int = $margin/vbox/tabs/Audio/content/sfx_on_off_row/sfx_on_off_btn.get_item_id(index)
	GlobalSet.settings["sfx_enabled"] = enabled
	SettingsLoad.save_settings()
	var idx = AudioServer.get_bus_index("sfx")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, enabled == 0)

func _on_fullscreen_btn_item_selected(index: int) -> void:
	GlobalSet.settings["fullscreen"] = $margin/vbox/tabs/Video/content/fullscreen_row/fullscreen_btn.get_item_id(index)
	SettingsLoad.save_settings()
	if index == 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_show_weather_chk_toggled(pressed: bool) -> void:
	GlobalSet.settings["show_weather"] = 1 if pressed else 0
	SettingsLoad.save_settings()

func _on_show_season_tint_chk_toggled(pressed: bool) -> void:
	GlobalSet.settings["show_season_tint"] = 1 if pressed else 0
	SettingsLoad.save_settings()

func _on_back_btn_pressed() -> void:
	visible = false
