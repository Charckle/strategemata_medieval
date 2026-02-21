extends CanvasLayer

@onready var map_menu := $map_menu
@onready var economy_menu := $economy_menu
@onready var war_menu := $war_menu
@onready var settings_menu := $settings_menu


func _ready() -> void:
	$Panel/map_btn.pressed.connect(_on_map_btn_pressed)
	$Panel/economy_btn.pressed.connect(_on_economy_btn_pressed)
	$Panel/war_btn.pressed.connect(_on_war_btn_pressed)
	$Panel/settings_btn.pressed.connect(_on_settings_btn_pressed)


func _on_map_btn_pressed() -> void:
	_toggle_menu(map_menu)


func _on_economy_btn_pressed() -> void:
	_toggle_menu(economy_menu)


func _on_war_btn_pressed() -> void:
	_toggle_menu(war_menu)


func _on_settings_btn_pressed() -> void:
	_toggle_menu(settings_menu)


func _toggle_menu(menu: Control) -> void:
	if menu.visible:
		# Already visible - bring to front in case others are on top
		_bring_to_front(menu)
	else:
		if menu.has_method("show_menu"):
			menu.show_menu()
		else:
			menu.visible = true
		_bring_to_front(menu)


func _bring_to_front(menu: Control) -> void:
	var parent := menu.get_parent()
	parent.move_child(menu, parent.get_child_count() - 1)
