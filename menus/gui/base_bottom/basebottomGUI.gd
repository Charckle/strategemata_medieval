extends CanvasLayer

@onready var map_menu := $map_menu
@onready var economy_menu := $economy_menu
@onready var war_menu := $war_menu
@onready var settings_menu := $settings_menu
@onready var show_province_names_chk := $settings_menu/margin/vbox/tabs/Gameplay/show_province_names_row/show_province_names_chk

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

# Army action menu (move / split / disband / ...), built at runtime.
var _am_panel: PanelContainer = null
var _am_body: VBoxContainer = null
var _am_base = null
var _am_army: Node2D = null

# Disband confirmation panel.
var _db_panel: PanelContainer = null
var _db_info_lbl: Label = null
var _db_confirm_btn: Button = null
var _db_base = null
var _db_army: Node2D = null

# Force transfer menu (army<->army merge/split, army<->garrison), built at runtime.
var _fm_panel: PanelContainer = null
var _fm_body: VBoxContainer = null
var _fm_title: Label = null
var _fm_base = null
var _fm_left_id: String = ""
var _fm_right_is_garrison := false
var _fm_right_id: String = ""
var _fm_building: Node = null
var _fm_spot: int = GlobalUnits.SPOT.FLAT
var _fm_split_mode := false  # true = split-only; no right column, confirm spawns new army
var _fm_withdraw_mode := false  # true = guest player peels off only their troops
# Spinboxes keyed by stack index; used by split confirm to read amounts.
var _fm_split_spinboxes: Array = []
var _fm_left_spinboxes: Array = []
var _fm_right_spinboxes: Array = []

# Building info popup (built at runtime): header with title + X, plus a body.
var _building_popup: PanelContainer = null
var _building_popup_title: Label = null
var _building_popup_body: Label = null
var _building_popup_close: Button = null
var _building_popup_deploy: Button = null
var _building_popup_deploy_all: Button = null
var _building_popup_node: Node = null
var _building_popup_pinned := false

func _ready() -> void:
	$Panel/map_btn.pressed.connect(_on_map_btn_pressed)
	$Panel/economy_btn.pressed.connect(_on_economy_btn_pressed)
	$Panel/war_btn.pressed.connect(_on_war_btn_pressed)
	$Panel/settings_btn.pressed.connect(_on_settings_btn_pressed)
	_populate_gameplay_settings()
	show_province_names_chk.toggled.connect(_on_show_province_names_toggled)


func _populate_gameplay_settings() -> void:
	var enabled = GlobalSet.settings.get("show_province_names", 1) != 0
	show_province_names_chk.button_pressed = enabled


func _on_show_province_names_toggled(pressed: bool) -> void:
	GlobalSet.settings["show_province_names"] = 1 if pressed else 0
	SettingsLoad.save_settings()
	if is_instance_valid(parent_n) and parent_n.has_method("refresh_province_labels"):
		parent_n.refresh_province_labels()


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


# --- Building info popup (shown to the right of the cursor) ---

func _ensure_building_popup() -> void:
	if _building_popup != null:
		return
	_building_popup = PanelContainer.new()
	_building_popup.visible = false
	_building_popup.top_level = true
	_building_popup.z_index = 100
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	var vbox := VBoxContainer.new()
	var header := HBoxContainer.new()
	_building_popup_title = Label.new()
	_building_popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_popup_title.add_theme_font_size_override("font_size", 16)
	_building_popup_close = Button.new()
	_building_popup_close.text = "X"
	_building_popup_close.pressed.connect(_on_building_popup_close_pressed)
	header.add_child(_building_popup_title)
	header.add_child(_building_popup_close)
	_building_popup_body = Label.new()
	_building_popup_deploy = Button.new()
	_building_popup_deploy.text = "Ungarrison your troops"
	_building_popup_deploy.visible = false
	_building_popup_deploy_all = Button.new()
	_building_popup_deploy_all.text = "Deploy entire garrison"
	_building_popup_deploy_all.visible = false
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_building_popup_body)
	vbox.add_child(_building_popup_deploy)
	vbox.add_child(_building_popup_deploy_all)
	margin.add_child(vbox)
	_building_popup.add_child(margin)
	add_child(_building_popup)


func show_building_popup(building: Node, title: String, body: String, pinned: bool, deploy_cb: Callable = Callable(), deploy_all_cb: Callable = Callable()) -> void:
	_ensure_building_popup()
	_building_popup_node = building
	_building_popup_pinned = pinned
	_building_popup_title.text = title
	_building_popup_body.text = body
	# Only pinned popups get an X; transient ones close on unhover.
	_building_popup_close.visible = pinned
	if _building_popup_deploy.pressed.is_connected(_on_building_popup_deploy_pressed):
		_building_popup_deploy.pressed.disconnect(_on_building_popup_deploy_pressed)
	if deploy_cb.is_valid():
		_building_popup_deploy.text = "Ungarrison your troops"
		_building_popup_deploy.visible = true
		_building_popup_deploy.pressed.connect(_on_building_popup_deploy_pressed.bind(deploy_cb))
	else:
		_building_popup_deploy.visible = false
	if _building_popup_deploy_all.pressed.is_connected(_on_building_popup_deploy_all_pressed):
		_building_popup_deploy_all.pressed.disconnect(_on_building_popup_deploy_all_pressed)
	if deploy_all_cb.is_valid():
		_building_popup_deploy_all.visible = true
		_building_popup_deploy_all.pressed.connect(_on_building_popup_deploy_all_pressed.bind(deploy_all_cb))
	else:
		_building_popup_deploy_all.visible = false
	_building_popup.visible = true
	_building_popup.reset_size()
	_position_building_popup()


func _on_building_popup_deploy_all_pressed(deploy_all_cb: Callable) -> void:
	hide_building_popup()
	deploy_all_cb.call()


func _on_building_popup_deploy_pressed(deploy_cb: Callable) -> void:
	hide_building_popup()
	deploy_cb.call()


func _position_building_popup() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(14, 0)
	var vp := get_viewport().get_visible_rect().size
	var sz := _building_popup.size
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - sz.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - sz.y))
	_building_popup.position = pos


func hide_building_popup() -> void:
	if _building_popup != null:
		_building_popup.visible = false
	_building_popup_node = null
	_building_popup_pinned = false


func get_building_popup_node() -> Node:
	if _building_popup != null and _building_popup.visible:
		return _building_popup_node
	return null


func is_building_popup_pinned() -> bool:
	return _building_popup != null and _building_popup.visible and _building_popup_pinned


func _on_building_popup_close_pressed() -> void:
	hide_building_popup()


# --- Close everything (called on player switch / end-turn) ------------------

func close_all_popups() -> void:
	hide_building_popup()
	if _info_popup != null:
		_info_popup.hide()
	_close_army_menu()
	_close_force_menu()
	_close_deploy_panel()
	_close_disband_panel()
	for menu in [map_menu, economy_menu, war_menu, settings_menu]:
		if menu != null:
			menu.visible = false


# --- Army action menu -------------------------------------------------------

func _ensure_army_menu() -> void:
	if _am_panel != null:
		return
	_am_panel = PanelContainer.new()
	_am_panel.top_level = true
	_am_panel.z_index = 130
	_am_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_am_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_army_menu)
	header.add_child(title)
	header.add_child(close_btn)
	_am_body = VBoxContainer.new()
	_am_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_am_body)
	margin.add_child(vbox)
	_am_panel.add_child(margin)
	add_child(_am_panel)


func open_army_menu(base_map, army: Node2D) -> void:
	_ensure_army_menu()
	_am_base = base_map
	_am_army = army
	_rebuild_army_menu()


func _close_army_menu() -> void:
	if _am_panel != null:
		_am_panel.visible = false
	_am_base = null
	_am_army = null


func _rebuild_army_menu() -> void:
	if _am_base == null or _am_army == null:
		return
	for c in _am_body.get_children():
		c.queue_free()

	# Title: controller + total men
	var title_lbl: Label = _am_panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/Title")
	if title_lbl != null:
		var units: Array = _am_army.get_units()
		var pid = _am_army.get_controller()
		var pname := str(_am_base.players[pid].name_) if _am_base.players.has(pid) else "Army"
		title_lbl.text = "Army of %s  (%d men)" % [pname, GlobalUnits.total_men(units)]

	# Roster summary
	var units: Array = _am_army.get_units()
	for pid in GlobalUnits.owners_in(units):
		var owner_name := str(_am_base.players[pid].name_) if _am_base.players.has(pid) else "?"
		var owner_units: Array = []
		for s in units:
			if int(s["owner"]) == pid:
				owner_units.append(s)
		var row_lbl := Label.new()
		row_lbl.text = "[%s] %d men · str %d" % [owner_name, GlobalUnits.total_men(owner_units), GlobalUnits.total_strength(owner_units)]
		_am_body.add_child(row_lbl)
		for s in owner_units:
			var stack_lbl := Label.new()
			stack_lbl.text = "  %d × %s (%s)" % [int(s["count"]), GlobalUnits.unit_name(s["type"]), GlobalUnits.source_name(s["source"])]
			_am_body.add_child(stack_lbl)

	_am_body.add_child(HSeparator.new())

	var move_points = _am_army.movement_left
	var pts_lbl := Label.new()
	pts_lbl.text = "Movement points: %d" % move_points
	_am_body.add_child(pts_lbl)

	_am_body.add_child(HSeparator.new())

	# Move button
	var move_btn := Button.new()
	move_btn.text = "Move  (MP: %d)" % move_points
	move_btn.disabled = move_points <= 0
	move_btn.pressed.connect(_on_am_move_pressed)
	_am_body.add_child(move_btn)

	# Split requires ≥1 MP and enough men so both halves can have ≥ MIN_SPLIT_MEN.
	var split_btn := Button.new()
	split_btn.text = "Split army (min %d + %d men)" % [GlobalUnits.MIN_SPLIT_MEN, GlobalUnits.MIN_SPLIT_MEN]
	split_btn.disabled = GlobalUnits.total_men(units) < GlobalUnits.MIN_SPLIT_MEN * 2 or move_points <= 0
	split_btn.pressed.connect(_on_am_split_pressed)
	_am_body.add_child(split_btn)

	# Disband — always available as long as there are men.
	var disband_btn := Button.new()
	disband_btn.text = "Disband army"
	disband_btn.pressed.connect(_on_am_disband_pressed)
	_am_body.add_child(disband_btn)

	_am_panel.visible = true
	_am_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_am_panel.position = (vp - _am_panel.size) * 0.5


func _on_am_move_pressed() -> void:
	var army := _am_army
	var base = _am_base
	_close_army_menu()
	if army != null and base != null:
		base.pathfinding.select_army(army)


func _on_am_split_pressed() -> void:
	if _am_base == null or _am_army == null:
		return
	var base = _am_base
	var army := _am_army
	_close_army_menu()
	# Reuse the force transfer menu in split-only mode: left column only,
	# with a "Split off" button that spawns the split portion adjacent.
	_open_split_panel(base, army)


func _on_am_disband_pressed() -> void:
	if _am_base == null or _am_army == null:
		return
	var base = _am_base
	var army := _am_army
	_close_army_menu()
	_open_disband_confirm(base, army)


# --- Disband confirmation panel ---------------------------------------------

func _ensure_disband_panel() -> void:
	if _db_panel != null:
		return
	_db_panel = PanelContainer.new()
	_db_panel.top_level = true
	_db_panel.z_index = 140
	_db_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_db_panel.visible = false

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var hbox := HBoxContainer.new()
	var title := Label.new()
	title.text = "Disband army?"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_disband_panel)
	hbox.add_child(close_btn)
	vbox.add_child(hbox)

	_db_info_lbl = Label.new()
	_db_info_lbl.text = ""
	_db_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_db_info_lbl.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(_db_info_lbl)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_disband_panel)
	btn_row.add_child(cancel_btn)
	_db_confirm_btn = Button.new()
	_db_confirm_btn.text = "Disband"
	_db_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_db_confirm_btn.pressed.connect(_on_disband_confirm_pressed)
	btn_row.add_child(_db_confirm_btn)
	vbox.add_child(btn_row)

	margin.add_child(vbox)
	_db_panel.add_child(margin)
	add_child(_db_panel)


func _open_disband_confirm(base_map, army: Node2D) -> void:
	_ensure_disband_panel()
	_db_base = base_map
	_db_army = army

	var units: Array = army.get_units()
	var own_levy := 0
	var own_sell := 0
	var foreign_men := 0
	var my_id: int = base_map.my_pl_id
	for s in units:
		var cnt := int(s["count"])
		if int(s["owner"]) == my_id:
			if int(s["source"]) == GlobalUnits.SOURCE.LEVY:
				own_levy += cnt
			else:
				own_sell += cnt
		else:
			foreign_men += cnt
	var lines: Array = []
	if own_levy > 0:
		lines.append("%d levy → added to your settlements" % own_levy)
	if own_sell > 0:
		lines.append("%d sellswords → disbanded (lost)" % own_sell)
	if foreign_men > 0:
		lines.append("%d foreign troops → released as new armies" % foreign_men)
	_db_info_lbl.text = "\n".join(lines) if lines.size() > 0 else "Army will be removed."

	_db_panel.visible = true
	_db_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_db_panel.position = (vp - _db_panel.size) * 0.5


func _close_disband_panel() -> void:
	if _db_panel != null:
		_db_panel.visible = false
	_db_base = null
	_db_army = null


func _on_disband_confirm_pressed() -> void:
	var base = _db_base
	var army := _db_army
	_close_disband_panel()
	if base == null or army == null:
		return
	base.request_disband_force.rpc_id(1, army.force_id)




func _open_split_panel(base_map, army: Node2D, withdraw_only: bool = false) -> void:
	_ensure_force_menu()
	_fm_base = base_map
	_fm_left_id = army.force_id
	_fm_right_is_garrison = false
	_fm_right_id = ""
	_fm_building = null
	_fm_spot = GlobalUnits.SPOT.FLAT
	_fm_split_mode = true
	_fm_withdraw_mode = withdraw_only
	_rebuild_force_menu()


func open_withdraw_menu(base_map, army: Node2D) -> void:
	_open_split_panel(base_map, army, true)


# --- Ungarrison menu --------------------------------------------------------
# (shown when clicking a building that has the player's troops inside)

var _dp_panel: PanelContainer = null
var _dp_body: VBoxContainer = null
var _dp_base = null
var _dp_building: Node = null
var _dp_player_id: int = -1
var _dp_spot: int = GlobalUnits.SPOT.FLAT
var _dp_spinboxes: Array = []


func _ensure_deploy_panel() -> void:
	if _dp_panel != null:
		return
	_dp_panel = PanelContainer.new()
	_dp_panel.top_level = true
	_dp_panel.z_index = 130
	_dp_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dp_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_deploy_panel)
	header.add_child(title)
	header.add_child(close_btn)
	_dp_body = VBoxContainer.new()
	_dp_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_dp_body)
	margin.add_child(vbox)
	_dp_panel.add_child(margin)
	add_child(_dp_panel)


func open_deploy_menu(base_map, building: Node, player_id: int) -> void:
	_ensure_deploy_panel()
	_dp_base = base_map
	_dp_building = building
	_dp_player_id = player_id
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	_dp_spot = GlobalUnits.SPOT.INSIDE if is_castle else GlobalUnits.SPOT.FLAT
	_rebuild_deploy_panel()


func _close_deploy_panel() -> void:
	if _dp_panel != null:
		_dp_panel.visible = false
	_dp_base = null
	_dp_building = null
	_dp_player_id = -1
	_dp_spinboxes.clear()


func _rebuild_deploy_panel() -> void:
	if _dp_base == null or _dp_building == null:
		return
	_dp_spinboxes.clear()
	for c in _dp_body.get_children():
		c.queue_free()

	var title_lbl: Label = _dp_panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/Title")
	if title_lbl != null:
		title_lbl.text = "Ungarrison from %s" % _dp_base._building_display_name(_dp_building)

	# Spot selector for castles.
	var is_castle = _dp_building.get("type_") != null and _dp_building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	if is_castle:
		var spot_row := HBoxContainer.new()
		var spot_lbl := Label.new()
		spot_lbl.text = "Spot:"
		var opt := OptionButton.new()
		opt.add_item("Inside", GlobalUnits.SPOT.INSIDE)
		opt.add_item("Outside", GlobalUnits.SPOT.OUTSIDE)
		opt.select(0 if _dp_spot == GlobalUnits.SPOT.INSIDE else 1)
		opt.item_selected.connect(_on_dp_spot_selected.bind(opt))
		spot_row.add_child(spot_lbl)
		spot_row.add_child(opt)
		_dp_body.add_child(spot_row)

	var units: Array = _dp_base.get_building_garrison(_dp_building, _dp_spot)
	# Only show stacks belonging to the player.
	var own_units: Array = []
	for s in units:
		if int(s["owner"]) == _dp_player_id:
			own_units.append(s)

	if own_units.is_empty():
		var lbl := Label.new()
		lbl.text = "(no troops to ungarrison)"
		_dp_body.add_child(lbl)
	else:
		var head := Label.new()
		head.text = "Choose how many to ungarrison (new army → 0 MP this turn):"
		_dp_body.add_child(head)
		_dp_body.add_child(HSeparator.new())
		for stack in own_units:
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.text = "%d %s" % [int(stack["count"]), GlobalUnits.unit_name(stack["type"])]
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.max_value = int(stack["count"])
			spin.value = int(stack["count"])
			spin.step = 1
			_dp_spinboxes.append({"stack": stack.duplicate(), "spin": spin})
			row.add_child(lbl)
			row.add_child(spin)
			_dp_body.add_child(row)

	_dp_body.add_child(HSeparator.new())
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm Ungarrison"
	confirm_btn.disabled = own_units.is_empty()
	confirm_btn.pressed.connect(_on_dp_confirm)
	_dp_body.add_child(confirm_btn)

	_dp_panel.visible = true
	_dp_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_dp_panel.position = (vp - _dp_panel.size) * 0.5


func _on_dp_spot_selected(_index: int, opt: OptionButton) -> void:
	_dp_spot = opt.get_selected_id()
	_rebuild_deploy_panel()


func _on_dp_confirm() -> void:
	if _dp_base == null or _dp_building == null:
		return
	var out_units: Array = []
	for entry in _dp_spinboxes:
		var count := int(entry["spin"].value)
		if count > 0:
			out_units.append(GlobalUnits.make_stack(
				entry["stack"]["type"],
				entry["stack"]["owner"],
				entry["stack"]["source"],
				count
			))
	if out_units.is_empty():
		show_info_popup("Select at least one unit to ungarrison")
		return
	var base = _dp_base
	var building := _dp_building
	var spot := _dp_spot
	_close_deploy_panel()
	base.do_sortie(building, spot, out_units)


# --- Deploy entire garrison (building owner) ----------------------------------

func open_deploy_all_confirm(base_map, building: Node) -> void:
	base_map.do_deploy_all_garrison(building)


# --- Force transfer menu ----------------------------------------------------

func _ensure_force_menu() -> void:
	if _fm_panel != null:
		return
	_fm_panel = PanelContainer.new()
	_fm_panel.top_level = true
	_fm_panel.z_index = 120
	_fm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fm_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	var vbox := VBoxContainer.new()
	var header := HBoxContainer.new()
	_fm_title = Label.new()
	_fm_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fm_title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_force_menu)
	header.add_child(_fm_title)
	header.add_child(close_btn)
	_fm_body = VBoxContainer.new()
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_fm_body)
	margin.add_child(vbox)
	_fm_panel.add_child(margin)
	add_child(_fm_panel)


func open_force_menu(base_map, left_id: String, right_id: String) -> void:
	_ensure_force_menu()
	_fm_base = base_map
	_fm_left_id = left_id
	_fm_right_is_garrison = false
	_fm_right_id = right_id
	_fm_building = null
	_fm_spot = GlobalUnits.SPOT.FLAT
	_fm_split_mode = false
	_rebuild_force_menu()


func open_garrison_menu(base_map, army_id: String, building: Node) -> void:
	_ensure_force_menu()
	_fm_base = base_map
	_fm_left_id = army_id
	_fm_right_is_garrison = true
	_fm_right_id = ""
	_fm_building = building
	var is_castle = building.get("type_") != null and building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	_fm_spot = GlobalUnits.SPOT.INSIDE if is_castle else GlobalUnits.SPOT.FLAT
	_fm_split_mode = false
	_rebuild_force_menu()


func _close_force_menu() -> void:
	if _fm_panel != null:
		_fm_panel.visible = false
	_fm_base = null
	_fm_split_mode = false
	_fm_withdraw_mode = false
	_fm_split_spinboxes.clear()
	_fm_left_spinboxes.clear()
	_fm_right_spinboxes.clear()


func _fm_left_units() -> Array:
	if _fm_base == null or not _fm_base.forces.has(_fm_left_id):
		return []
	return _fm_base.forces[_fm_left_id]["units"]


func _fm_right_units() -> Array:
	if _fm_base == null:
		return []
	if _fm_right_is_garrison:
		return _fm_base.get_building_garrison(_fm_building, _fm_spot)
	if _fm_base.forces.has(_fm_right_id):
		return _fm_base.forces[_fm_right_id]["units"]
	return []


func _rebuild_force_menu() -> void:
	if _fm_base == null:
		return
	# The left (mover) army must still exist; otherwise close.
	if not _fm_base.forces.has(_fm_left_id):
		_close_force_menu()
		return
	for child in _fm_body.get_children():
		child.queue_free()

	var left_name := _fm_force_label(_fm_left_id, false)
	var right_name := ""
	if _fm_right_is_garrison:
		right_name = _fm_base._building_display_name(_fm_building) if _fm_base.has_method("_building_display_name") else "Building"
		_fm_title.text = "%s  ⇄  %s" % [left_name, right_name]
	else:
		right_name = _fm_force_label(_fm_right_id, false)
		_fm_title.text = "%s  ⇄  %s" % [left_name, right_name]

	# Castle spot selector.
	if _fm_right_is_garrison and _fm_building.get("type_") != null and _fm_building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE:
		var spot_row := HBoxContainer.new()
		var spot_lbl := Label.new()
		spot_lbl.text = "Position:"
		var opt := OptionButton.new()
		opt.add_item("Inside (x3)", GlobalUnits.SPOT.INSIDE)
		opt.add_item("Outside", GlobalUnits.SPOT.OUTSIDE)
		opt.select(0 if _fm_spot == GlobalUnits.SPOT.INSIDE else 1)
		opt.item_selected.connect(_on_fm_spot_selected.bind(opt))
		spot_row.add_child(spot_lbl)
		spot_row.add_child(opt)
		_fm_body.add_child(spot_row)

	if _fm_split_mode:
		_fm_split_spinboxes.clear()
		if _fm_withdraw_mode:
			_fm_title.text = "Withdraw your troops from %s" % left_name
		else:
			_fm_title.text = "Split: %s" % left_name
		_fm_body.add_child(_build_split_column())
		_fm_body.add_child(HSeparator.new())
		if not _fm_withdraw_mode:
			var half_btn := Button.new()
			half_btn.text = "50 : 50 split"
			half_btn.pressed.connect(_on_fm_split_half)
			_fm_body.add_child(half_btn)
		var confirm_btn := Button.new()
		confirm_btn.text = "Confirm Withdraw" if _fm_withdraw_mode else "Confirm Split"
		confirm_btn.pressed.connect(_on_fm_split_confirm)
		_fm_body.add_child(confirm_btn)
	else:
		_fm_left_spinboxes.clear()
		_fm_right_spinboxes.clear()
		var hint := Label.new()
		hint.text = "Set amounts to move, then confirm (→ left to right, ← right to left):"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fm_body.add_child(hint)
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override("separation", 20)
		columns.add_child(_build_force_column(true))
		columns.add_child(VSeparator.new())
		columns.add_child(_build_force_column(false))
		_fm_body.add_child(columns)
		_fm_body.add_child(HSeparator.new())
		var confirm_btn := Button.new()
		confirm_btn.text = "Confirm Transfer"
		confirm_btn.pressed.connect(_on_fm_transfer_confirm)
		_fm_body.add_child(confirm_btn)

		# Quick merge for two armies.
		if not _fm_right_is_garrison:
			var merge_btn := Button.new()
			merge_btn.text = "Merge all into %s" % right_name
			merge_btn.pressed.connect(_on_fm_merge_all)
			_fm_body.add_child(merge_btn)

	_fm_panel.visible = true
	_fm_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_fm_panel.position = (vp - _fm_panel.size) * 0.5


func _build_split_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(280, 0)
	var units := _fm_left_units()
	if _fm_withdraw_mode and _fm_base != null:
		units = GlobalUnits.units_of_owner(units, _fm_base.my_pl_id)
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 14)
	if _fm_withdraw_mode:
		head.text = "Choose how many of your troops to withdraw:"
	else:
		head.text = "Choose how many to split off:"
	col.add_child(head)
	col.add_child(HSeparator.new())
	if units.is_empty():
		var empty := Label.new()
		empty.text = "(no troops to withdraw)"
		col.add_child(empty)
		return col
	for stack in units:
		var row := HBoxContainer.new()
		var owner_name := ""
		if _fm_base.players.has(int(stack["owner"])):
			owner_name = str(_fm_base.players[int(stack["owner"])].name_)
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s %s [%s]" % [int(stack["count"]), GlobalUnits.unit_name(stack["type"]), owner_name]
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = int(stack["count"])
		spin.value = 0
		spin.step = 1
		_fm_split_spinboxes.append({"stack": stack.duplicate(), "spin": spin})
		row.add_child(lbl)
		row.add_child(spin)
		col.add_child(row)
	return col


func _on_fm_split_half() -> void:
	for entry in _fm_split_spinboxes:
		var total := int(entry["stack"]["count"])
		entry["spin"].value = total / 2


func _collect_out_units(spinbox_entries: Array) -> Array:
	var out_units: Array = []
	for entry in spinbox_entries:
		var count := int(entry["spin"].value)
		if count > 0:
			out_units.append(GlobalUnits.make_stack(
				entry["stack"]["type"],
				entry["stack"]["owner"],
				entry["stack"]["source"],
				count
			))
	return out_units


func _on_fm_transfer_confirm() -> void:
	if _fm_base == null or not _fm_base.forces.has(_fm_left_id):
		return

	var left_to_right := _collect_out_units(_fm_left_spinboxes)
	var right_to_left := _collect_out_units(_fm_right_spinboxes)
	if left_to_right.is_empty() and right_to_left.is_empty():
		show_info_popup("Select at least one unit to transfer")
		return

	var base = _fm_base
	var left_id := _fm_left_id

	if _fm_right_is_garrison:
		var fig = base.armies.get_node_or_null(left_id)
		if fig == null:
			return
		var left_after := GlobalUnits.clone_units(_fm_left_units())
		var garrison_after := GlobalUnits.clone_units(_fm_right_units())
		GlobalUnits.subtract_units(left_after, left_to_right)
		GlobalUnits.subtract_units(garrison_after, right_to_left)
		garrison_after = GlobalUnits.merge_units(garrison_after, GlobalUnits.units_from_spec(left_to_right))
		left_after = GlobalUnits.merge_units(left_after, GlobalUnits.units_from_spec(right_to_left))

		var left_men := GlobalUnits.total_men(left_after)
		if left_men > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Army must keep at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return

		var cap: int = _fm_building.get_garrison_capacity(_fm_spot)
		var garrison_men := GlobalUnits.total_men(garrison_after)
		if garrison_men > cap:
			show_info_popup("Garrison capacity is %d men" % cap)
			return

		if not left_to_right.is_empty() and fig.movement_left < 1:
			show_info_popup("Garrisoning costs 1 movement point")
			return

		var building_key = base.get_building_key(_fm_building)
		_close_force_menu()
		base.request_batch_garrison_units.rpc_id(1, left_id, building_key, _fm_spot, left_to_right, right_to_left)
	else:
		if not base.forces.has(_fm_right_id):
			return
		var right_id := _fm_right_id
		var left_after := GlobalUnits.clone_units(_fm_left_units())
		var right_after := GlobalUnits.clone_units(_fm_right_units())
		GlobalUnits.subtract_units(left_after, left_to_right)
		GlobalUnits.subtract_units(right_after, right_to_left)
		left_after = GlobalUnits.merge_units(left_after, GlobalUnits.units_from_spec(right_to_left))
		right_after = GlobalUnits.merge_units(right_after, GlobalUnits.units_from_spec(left_to_right))

		var left_men := GlobalUnits.total_men(left_after)
		var right_men := GlobalUnits.total_men(right_after)
		if left_men > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Left army must keep at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return
		if right_men > 0 and right_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Right army must keep at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return

		_close_force_menu()
		base.request_batch_transfer_units.rpc_id(1, left_id, right_id, left_to_right, right_to_left)


func _on_fm_split_confirm() -> void:
	if _fm_base == null or not _fm_base.forces.has(_fm_left_id):
		return
	var out_units: Array = _collect_out_units(_fm_split_spinboxes)
	if out_units.is_empty():
		show_info_popup("Select at least one unit to split off")
		return
	var split_men := GlobalUnits.total_men(out_units)
	if _fm_withdraw_mode:
		if not GlobalUnits.all_owned_by(out_units, _fm_base.my_pl_id):
			show_info_popup("You can only withdraw your own troops")
			return
	else:
		var source_total := GlobalUnits.total_men(_fm_left_units())
		var remainder := source_total - split_men
		if split_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Split-off army needs at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return
		if remainder < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Remaining army must keep at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return
	# Capture locals before _close_force_menu() nulls _fm_base/_fm_left_id.
	var base = _fm_base
	var source_id := _fm_left_id
	var withdraw := _fm_withdraw_mode
	var withdraw_player = base.my_pl_id if withdraw else -1
	var fig = base.armies.get_node_or_null(source_id)
	if fig == null:
		return
	var army_cell: Vector2i = base.pathfinding.get_army_cell(fig)
	var free_cell = base.pathfinding.get_free_adjacent_cell(army_cell)
	if free_cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		show_info_popup("No free adjacent tile to place split army")
		return
	_close_force_menu()
	base.request_split_force.rpc_id(1, source_id, out_units, free_cell.x, free_cell.y, withdraw, withdraw_player)


func _build_force_column(is_left: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(240, 0)
	var units := _fm_left_units() if is_left else _fm_right_units()

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 14)
	if is_left:
		head.text = "%s\n%d men · str %d" % [_fm_force_label(_fm_left_id, false), GlobalUnits.total_men(units), GlobalUnits.total_strength(units)]
	else:
		var cap_txt := ""
		if _fm_right_is_garrison:
			var cap: int = _fm_building.get_garrison_capacity(_fm_spot)
			var mult := GlobalUnits.CASTLE_INSIDE_BONUS if _fm_spot == GlobalUnits.SPOT.INSIDE else 1.0
			cap_txt = "%d/%d men · str %d" % [GlobalUnits.total_men(units), cap, GlobalUnits.total_strength(units, mult)]
		else:
			cap_txt = "%d men · str %d" % [GlobalUnits.total_men(units), GlobalUnits.total_strength(units)]
		head.text = "%s\n%s" % ["Garrison" if _fm_right_is_garrison else _fm_force_label(_fm_right_id, false), cap_txt]
	col.add_child(head)
	col.add_child(HSeparator.new())

	if units.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		col.add_child(empty)
		return col

	var dir_hint := Label.new()
	dir_hint.text = "→ move right" if is_left else "← move left"
	col.add_child(dir_hint)

	for stack in units:
		var row := HBoxContainer.new()
		var owner_name := ""
		if _fm_base.players.has(int(stack["owner"])):
			owner_name = str(_fm_base.players[int(stack["owner"])].name_)
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%d %s [%s]" % [int(stack["count"]), GlobalUnits.unit_name(stack["type"]), owner_name]
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = int(stack["count"])
		spin.value = 0
		spin.step = 1
		var entry := {"stack": stack.duplicate(), "spin": spin}
		if is_left:
			_fm_left_spinboxes.append(entry)
			row.add_child(lbl)
			row.add_child(spin)
		else:
			_fm_right_spinboxes.append(entry)
			row.add_child(spin)
			row.add_child(lbl)
		col.add_child(row)
	return col


func _fm_force_label(fid: String, _unused: bool) -> String:
	if _fm_base == null or not _fm_base.forces.has(fid):
		return "Army"
	var controller = _fm_base.get_force_controller(fid)
	if _fm_base.players.has(controller):
		return "Army of %s" % str(_fm_base.players[controller].name_)
	return "Army"


func _on_fm_spot_selected(_index: int, opt: OptionButton) -> void:
	_fm_spot = opt.get_selected_id()
	_rebuild_force_menu()


func _on_fm_merge_all() -> void:
	if _fm_base == null or _fm_right_is_garrison:
		return
	# Fold the left (mover) army entirely into the right one.
	_fm_base.do_merge_all(_fm_right_id, _fm_left_id)
	_close_force_menu()


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
