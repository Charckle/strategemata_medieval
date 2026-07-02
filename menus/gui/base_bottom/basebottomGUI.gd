extends CanvasLayer

@onready var map_menu := $map_menu
@onready var economy_menu := $economy_menu
@onready var war_menu := $war_menu
@onready var settings_menu := $settings_menu

@onready var parent_n = get_parent()

# Economy menu tab refs
@onready var economy_tabs := $economy_menu/margin/vbox/tabs
@onready var overview_provinces_lbl := $economy_menu/margin/vbox/tabs/overview/provinces_count_lbl
@onready var overview_money_lbl := $economy_menu/margin/vbox/tabs/overview/money_lbl
@onready var overview_population_lbl := $economy_menu/margin/vbox/tabs/overview/population_lbl
@onready var provinces_list_container := $economy_menu/margin/vbox/tabs/all_provinces/ScrollContainer/provinces_list
@onready var province_tab_name := $economy_menu/margin/vbox/tabs/province/province_name_lbl
@onready var province_tab_status := $economy_menu/margin/vbox/tabs/province/status_lbl
@onready var province_tab_owner := $economy_menu/margin/vbox/tabs/province/owner_lbl
@onready var province_tab_defacto := $economy_menu/margin/vbox/tabs/province/defacto_lbl
@onready var province_tab_dejure := $economy_menu/margin/vbox/tabs/province/dejure_lbl
@onready var province_tab_population := $economy_menu/margin/vbox/tabs/province/population_prov_lbl
@onready var province_tab_income := $economy_menu/margin/vbox/tabs/province/income_prov_lbl
@onready var province_tab_villages := $economy_menu/margin/vbox/tabs/province/buildings_grid/villages_val
@onready var province_tab_towns := $economy_menu/margin/vbox/tabs/province/buildings_grid/towns_val
@onready var province_tab_castles := $economy_menu/margin/vbox/tabs/province/buildings_grid/castles_val
@onready var province_tab_economy := $economy_menu/margin/vbox/tabs/province/buildings_grid/economy_val

var selected_province_id: String = ""

var _info_popup: PopupPanel = null
var _info_popup_label: Label = null

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


func _on_end_turn_btn_pressed() -> void:
	parent_n.player_ended_turn.rpc_id(1, parent_n.my_pl_id)

# Small transient popup shown near the cursor; closes when clicking away.
func show_info_popup(text: String) -> void:
	if _info_popup == null:
		_info_popup = PopupPanel.new()
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		_info_popup_label = Label.new()
		margin.add_child(_info_popup_label)
		_info_popup.add_child(margin)
		add_child(_info_popup)
	_info_popup_label.text = text
	var mouse_pos := get_viewport().get_mouse_position()
	_info_popup.popup(Rect2i(Vector2i(mouse_pos) + Vector2i(12, 12), Vector2i.ZERO))


func update_season(season_id):
	$top_panel/MarginContainer/HBoxContainer/season_lbl.text = GlobalStuff.get_season_name(season_id)

func update_money(m_value):
	$top_panel/MarginContainer/HBoxContainer/mark_val_lbl.text = str(m_value)

func update_pname(player_name):
	$top_panel/MarginContainer/HBoxContainer/player_name_lbl.text = player_name


func update_economy_menu(base_map: Node) -> void:
	if not is_instance_valid(base_map) or not base_map.has_method("get_player_overview_data"):
		return
	var pid = base_map.my_pl_id
	var overview = base_map.get_player_overview_data(pid)
	overview_provinces_lbl.text = "Provinces: %d" % overview.get("num_provinces", 0)
	overview_money_lbl.text = "Marks: %s" % overview.get("marks", 0)
	overview_population_lbl.text = "Population: %s" % overview.get("population", 0)

	var list_data = base_map.get_all_provinces_list_data(pid)
	for child in provinces_list_container.get_children():
		child.queue_free()
	var separator_added := false
	for entry in list_data:
		if not entry.get("owned", true) and not separator_added:
			separator_added = true
			var sep = HSeparator.new()
			provinces_list_container.add_child(sep)
			var lbl = Label.new()
			lbl.text = "De jure / De facto only"
			lbl.add_theme_font_size_override("font_size", 12)
			provinces_list_container.add_child(lbl)
		var btn = Button.new()
		btn.text = "%s — Pop: %s  Income: %s" % [
			entry.get("name", "—"),
			entry.get("population", 0),
			entry.get("predicted_income", 0)
		]
		btn.set_meta("province_id", entry.get("id", ""))
		btn.pressed.connect(_on_province_list_clicked.bind(entry.get("id", "")))
		provinces_list_container.add_child(btn)

	if selected_province_id != "":
		_fill_province_tab(base_map, selected_province_id)


func _on_province_list_clicked(province_id: String) -> void:
	selected_province_id = province_id
	economy_tabs.current_tab = 2
	if is_instance_valid(parent_n) and parent_n.has_method("get_province_data"):
		_fill_province_tab(parent_n, province_id)


func _fill_province_tab(base_map: Node, province_id: String) -> void:
	var data = base_map.get_province_data(province_id)
	if data.is_empty():
		province_tab_name.text = "—"
		province_tab_status.text = "Status: —"
		province_tab_owner.text = "Owner: —"
		province_tab_defacto.text = "De facto: —"
		province_tab_dejure.text = "De jure: —"
		province_tab_population.text = "Population: —"
		province_tab_income.text = "Predicted income: —"
		province_tab_villages.text = "— / —"
		province_tab_towns.text = "— / —"
		province_tab_castles.text = "— / —"
		province_tab_economy.text = "— / —"
		return
	province_tab_name.text = data.get("name", "—")
	province_tab_status.text = "Status: %s" % data.get("status_name", "—")
	province_tab_owner.text = "Owner: %s" % data.get("owner_name", "—")
	province_tab_defacto.text = "De facto: %s" % data.get("defacto_name", "—")
	province_tab_dejure.text = "De jure: %s" % data.get("dejure_name", "—")
	province_tab_population.text = "Population: %s (next: %s)" % [data.get("population_has", 0), data.get("population_will", 0)]
	province_tab_income.text = "Predicted income: %s" % data.get("marks_will", 0)
	var v = data.get("villages", {"control": 0, "all": 0})
	province_tab_villages.text = "%d / %d" % [v.get("control", 0), v.get("all", 0)]
	var t = data.get("towns", {"control": 0, "all": 0})
	province_tab_towns.text = "%d / %d" % [t.get("control", 0), t.get("all", 0)]
	var c = data.get("castles", {"control": 0, "all": 0})
	province_tab_castles.text = "%d / %d" % [c.get("control", 0), c.get("all", 0)]
	var e = data.get("economy", {"control": 0, "all": 0})
	province_tab_economy.text = "%d / %d" % [e.get("control", 0), e.get("all", 0)]
