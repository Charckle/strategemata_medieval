extends CanvasLayer

@onready var map_menu := $map_menu
@onready var economy_menu := $economy_menu
@onready var war_menu := $war_menu
@onready var msg_menu := $msg_menu
@onready var settings_menu := $settings_menu
@onready var msg_btn := $Panel/msg_btn
@onready var msg_list := $msg_menu/margin/vbox/tabs/Inbox/ScrollContainer/msg_list
@onready var msg_empty_lbl := $msg_menu/margin/vbox/tabs/Inbox/empty_lbl
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
@onready var province_tab_root := $economy_menu/margin/vbox/tabs/province

@onready var alliances_list := $war_menu/margin/vbox/tabs/Alliances/ScrollContainer/alliances_list

var selected_province_id: String = ""
var _refreshing_alliances := false

# Province levy / weapons UI (built under province tab at runtime).
var _prov_happiness_lbl: Label = null
var _prov_levy_lbl: Label = null
var _prov_weapons_lbl: Label = null
var _prov_shipments_lbl: Label = null
var _prov_recruit_btn: Button = null
var _prov_ship_btn: Button = null

# Recruit levy panel.
var _rc_panel: PanelContainer = null
var _rc_body: VBoxContainer = null
var _rc_info_lbl: Label = null
var _rc_base = null
var _rc_province_id: String = ""
var _rc_spinboxes: Dictionary = {}  # UNIT_TYPE -> SpinBox

# Ship weapons panel.
var _sw_panel: PanelContainer = null
var _sw_body: VBoxContainer = null
var _sw_info_lbl: Label = null
var _sw_dest: OptionButton = null
var _sw_base = null
var _sw_province_id: String = ""
var _sw_spinboxes: Dictionary = {}  # weapon key -> SpinBox
var _sw_dest_ids: Array = []

# Merchant shop panel (tabbed: Weapons + Materials).
var _ms_panel: PanelContainer = null
var _ms_info_lbl: Label = null
var _ms_weapons_body: VBoxContainer = null
var _ms_materials_body: VBoxContainer = null
var _ms_total_lbl: Label = null
var _ms_base = null
var _ms_merchant: Node = null
var _ms_weapon_spinboxes: Dictionary = {}  # weapon key -> SpinBox
var _ms_material_spinboxes: Dictionary = {}  # material key -> SpinBox
var _ms_competition := false

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
var _building_popup_node: Node = null
var _building_popup_pinned := false

# Battle preview / result UI (built at runtime).
var _bt_panel: PanelContainer = null
var _bt_body: VBoxContainer = null
var _bt_title: Label = null
var _bt_base = null
var _bt_attacker_id: String = ""
var _bt_defender_id: String = ""
var _bt_building: Node = null

# Hostage decision after a won battle.
var _hs_panel: PanelContainer = null
var _hs_body: VBoxContainer = null
var _hs_base = null
var _hs_attacker_id: String = ""
var _hs_pool: Array = []
var _hs_building: Node = null
var _hs_event_id: String = ""

# Building capture / raid / raze after clearing a hostile settlement.
var _ba_panel: PanelContainer = null
var _ba_body: VBoxContainer = null
var _ba_base = null
var _ba_force_id: String = ""
var _ba_building: Node = null

# Event report card (populated from game event id).
var _er_panel: PanelContainer = null
var _er_title: Label = null
var _er_body: Label = null
var _er_goto: Button = null
var _er_base = null
var _er_event_id: String = ""

func _ready() -> void:
	$Panel/map_btn.pressed.connect(_on_map_btn_pressed)
	$Panel/economy_btn.pressed.connect(_on_economy_btn_pressed)
	$Panel/war_btn.pressed.connect(_on_war_btn_pressed)
	$Panel/settings_btn.pressed.connect(_on_settings_btn_pressed)
	msg_btn.pressed.connect(_on_msg_btn_pressed)
	_populate_gameplay_settings()
	show_province_names_chk.toggled.connect(_on_show_province_names_toggled)
	_ensure_province_levy_widgets()
	refresh_msg_button()


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
	if war_menu.visible:
		refresh_alliances_list()


func _on_settings_btn_pressed() -> void:
	_toggle_menu(settings_menu)


func _on_msg_btn_pressed() -> void:
	_toggle_menu(msg_menu)
	if msg_menu.visible:
		if is_instance_valid(parent_n) and parent_n.has_method("clear_msg_unread"):
			parent_n.clear_msg_unread()
		refresh_msg_button()
		refresh_msg_list()


func refresh_msg_button() -> void:
	if msg_btn == null:
		return
	var unread := false
	if is_instance_valid(parent_n) and parent_n.has_method("has_msg_unread"):
		unread = parent_n.has_msg_unread()
	msg_btn.text = "MSG*" if unread else "MSG"


func refresh_msg_list() -> void:
	if msg_list == null:
		return
	for child in msg_list.get_children():
		child.queue_free()
	if not is_instance_valid(parent_n) or not parent_n.has_method("get_inbox_entries"):
		if msg_empty_lbl != null:
			msg_empty_lbl.visible = true
		return
	var entries: Array = parent_n.get_inbox_entries()
	if msg_empty_lbl != null:
		msg_empty_lbl.visible = entries.is_empty()
	var reader_id: int = int(parent_n.my_pl_id) if parent_n.get("my_pl_id") != null else 0
	for entry in entries:
		var event_id := str(entry.get("event_id", ""))
		var event: Dictionary = parent_n.get_event(event_id) if parent_n.has_method("get_event") else {}
		if event.is_empty():
			continue
		var btn := Button.new()
		btn.text = GameEvents.inbox_label(event, reader_id)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_msg_entry_pressed.bind(event_id))
		msg_list.add_child(btn)


func refresh_msg_list_if_open() -> void:
	if msg_menu != null and msg_menu.visible:
		refresh_msg_list()


func _on_msg_entry_pressed(event_id: String) -> void:
	open_event_report(parent_n, event_id)


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
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_building_popup_body)
	vbox.add_child(_building_popup_deploy)
	margin.add_child(vbox)
	_building_popup.add_child(margin)
	add_child(_building_popup)


func show_building_popup(building: Node, title: String, body: String, pinned: bool, deploy_cb: Callable = Callable()) -> void:
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
	_building_popup.visible = true
	_building_popup.reset_size()
	_position_building_popup()


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
	_close_battle_menu()
	_close_hostage_menu()
	_close_building_actions_menu()
	_close_event_report()
	_close_recruit_menu()
	_close_ship_menu()
	_close_merchant_shop()
	for menu in [map_menu, economy_menu, war_menu, msg_menu, settings_menu]:
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
	_am_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_am_body = VBoxContainer.new()
	_am_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_am_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_am_body)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(scroll)
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


func _clear_army_menu_body() -> void:
	# remove_child so layout updates immediately; queue_free alone leaves
	# orphans in the tree until end of frame and blows up panel height.
	for child in _am_body.get_children():
		_am_body.remove_child(child)
		child.queue_free()


func _fit_army_menu_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	var max_w := minf(420.0, vp.x * 0.92)
	var max_h := vp.y * 0.7
	var scroll := _am_body.get_parent() as ScrollContainer
	# Give the body a real width first so long labels don't explode vertically.
	if scroll != null:
		scroll.custom_minimum_size = Vector2(max_w - 48.0, 0)
	_am_body.reset_size()
	var body_h := _am_body.get_combined_minimum_size().y
	var header_budget := 64.0
	if scroll != null:
		scroll.custom_minimum_size = Vector2(max_w - 48.0, minf(body_h, max_h - header_budget))
	_am_panel.reset_size()
	var sz := _am_panel.get_combined_minimum_size()
	sz.x = max_w
	sz.y = minf(sz.y, max_h)
	_am_panel.size = sz
	_am_panel.position = (vp - _am_panel.size) * 0.5
	_am_panel.position.x = clampf(_am_panel.position.x, 0.0, maxf(0.0, vp.x - _am_panel.size.x))
	_am_panel.position.y = clampf(_am_panel.position.y, 0.0, maxf(0.0, vp.y - _am_panel.size.y))


func _rebuild_army_menu() -> void:
	if _am_base == null or _am_army == null:
		return
	_clear_army_menu_body()

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
		row_lbl.text = "[%s] %d men · fight str %d" % [
			owner_name,
			GlobalUnits.total_men(owner_units),
			GlobalUnits.fighting_strength(owner_units)
		]
		_am_body.add_child(row_lbl)
		for s in owner_units:
			var stack_lbl := Label.new()
			stack_lbl.text = "  %d × %s (%s)" % [int(s["count"]), GlobalUnits.unit_name(s["type"]), GlobalUnits.source_name(s["source"])]
			var st := GlobalUnits.stack_status(s)
			if st != GlobalUnits.STATUS.FIGHTING:
				stack_lbl.text += " [%s]" % GlobalUnits.status_name(st)
				var rec := int(s.get("recover_in", 0))
				if rec > 0:
					stack_lbl.text += " %ds" % rec
			if bool(s.get("join_pending", false)):
				stack_lbl.text += " (join pending)"
			_am_body.add_child(stack_lbl)

	_am_body.add_child(HSeparator.new())

	var move_points = _am_army.movement_left
	var max_mp = _am_army.effective_max_mp() if _am_army.has_method("effective_max_mp") else move_points
	var pts_lbl := Label.new()
	pts_lbl.text = "Movement points: %d / %d" % [move_points, max_mp]
	if GlobalUnits.is_knights_only(units):
		pts_lbl.text += "  (knights +50%)"
	var wound_pen := GlobalUnits.wound_mp_penalty(units)
	if wound_pen > 0.0:
		pts_lbl.text += "  (wounded −%.0f%%)" % (wound_pen * 100.0)
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

	# Captured / hostage actions
	var special: Array = []
	for s in units:
		var st := GlobalUnits.stack_status(s)
		if st == GlobalUnits.STATUS.CAPTURED or st == GlobalUnits.STATUS.HOSTAGE:
			special.append(s)
	if not special.is_empty():
		_am_body.add_child(HSeparator.new())
		var spec_lbl := Label.new()
		spec_lbl.text = "Prisoners"
		_am_body.add_child(spec_lbl)
		for s in special:
			var st := GlobalUnits.stack_status(s)
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.text = "%d %s [%s]" % [int(s["count"]), GlobalUnits.unit_name(s["type"]), GlobalUnits.status_name(st)]
			row.add_child(lbl)
			if st == GlobalUnits.STATUS.CAPTURED and not bool(s.get("join_pending", false)):
				var join_btn := Button.new()
				var chance := int(GlobalUnits.join_chance_for_stack(s) * 100.0)
				join_btn.text = "Offer join (%d%%)" % chance
				join_btn.pressed.connect(_on_am_offer_join.bind(s.duplicate(true)))
				row.add_child(join_btn)
			var sword_btn := Button.new()
			sword_btn.text = "Sword"
			sword_btn.pressed.connect(_on_am_put_to_sword.bind(s.duplicate(true)))
			row.add_child(sword_btn)
			_am_body.add_child(row)

	_am_panel.visible = true
	_fit_army_menu_panel()


func refresh_army_menu_if_force(force_id: String) -> void:
	if _am_panel != null and _am_panel.visible and _am_army != null and _am_army.force_id == force_id:
		_rebuild_army_menu()


func _on_am_offer_join(stack_spec: Dictionary) -> void:
	if _am_base == null or _am_army == null:
		return
	_am_base.do_offer_join(_am_army.force_id, stack_spec)


func _on_am_put_to_sword(stack_spec: Dictionary) -> void:
	if _am_base == null or _am_army == null:
		return
	_am_base.do_put_stack_to_sword(_am_army.force_id, stack_spec)


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

	var refund := GlobalUnits.weapons_from_units(units, my_id)
	var refund_parts: PackedStringArray = []
	for k in GlobalUnits.WEAPON_KEYS:
		var amt := int(refund.get(k, 0))
		if amt > 0:
			refund_parts.append("%d %s" % [amt, GlobalUnits.weapon_name(k)])
	var can_refund := true
	if base_map.has_method("disband_refunds_weapons"):
		can_refund = base_map.disband_refunds_weapons(army.force_id, my_id)
	if not refund_parts.is_empty():
		if can_refund:
			lines.append("Weapons refunded: %s" % ", ".join(refund_parts))
		else:
			lines.append("WARNING: Not in a de jure province — weapons will be LOST:")
			lines.append(", ".join(refund_parts))
			_db_confirm_btn.text = "Disband anyway"
	else:
		_db_confirm_btn.text = "Disband"

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
			row.add_child(_make_spin_all_button(spin))
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


# --- Force transfer menu ----------------------------------------------------

func _ensure_force_menu() -> void:
	if _fm_panel != null:
		return
	_fm_panel = PanelContainer.new()
	_fm_panel.top_level = true
	_fm_panel.z_index = 120
	_fm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fm_panel.visible = false
	_fm_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.12, 0.07, 0.96)
	style.set_border_width_all(3)
	style.border_color = Color(0.05, 0.03, 0.015, 1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 4
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_fm_panel.add_theme_stylebox_override("panel", style)
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fm_body = VBoxContainer.new()
	_fm_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fm_body)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(scroll)
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


func is_force_menu_open() -> bool:
	return _fm_panel != null and _fm_panel.visible


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


func _clear_force_menu_body() -> void:
	# remove_child so layout updates immediately; queue_free alone leaves
	# orphans in the tree until end of frame and blows up panel height.
	for child in _fm_body.get_children():
		_fm_body.remove_child(child)
		child.queue_free()


func _fit_force_menu_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	var max_w := minf(560.0, vp.x * 0.92)
	var max_h := vp.y * 0.8
	var scroll := _fm_body.get_parent() as ScrollContainer
	# Give the body a real width first so autowrap/labels don't explode vertically.
	if scroll != null:
		scroll.custom_minimum_size = Vector2(max_w - 48.0, 0)
	_fm_body.reset_size()
	var body_h := _fm_body.get_combined_minimum_size().y
	var header_budget := 64.0
	if scroll != null:
		scroll.custom_minimum_size = Vector2(max_w - 48.0, minf(body_h, max_h - header_budget))
	_fm_panel.reset_size()
	var sz := _fm_panel.get_combined_minimum_size()
	sz.x = max_w
	sz.y = minf(sz.y, max_h)
	_fm_panel.size = sz
	_fm_panel.position = (vp - _fm_panel.size) * 0.5
	_fm_panel.position.x = clampf(_fm_panel.position.x, 0.0, maxf(0.0, vp.x - _fm_panel.size.x))
	_fm_panel.position.y = clampf(_fm_panel.position.y, 0.0, maxf(0.0, vp.y - _fm_panel.size.y))


func _rebuild_force_menu() -> void:
	if _fm_base == null:
		return
	# The left (mover) army must still exist; otherwise close.
	if not _fm_base.forces.has(_fm_left_id):
		_close_force_menu()
		return
	_clear_force_menu_body()

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
		# Without a width, autowrap collapses to ~1px and stacks one glyph per
		# line — panel becomes taller than the screen and looks empty.
		hint.custom_minimum_size = Vector2(480, 0)
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
	_fit_force_menu_panel()


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
		row.add_child(_make_spin_all_button(spin))
		col.add_child(row)
	return col


func _make_spin_all_button(spin: SpinBox) -> Button:
	var btn := Button.new()
	btn.text = "ALL"
	btn.tooltip_text = "Select all of this type"
	btn.pressed.connect(func(): spin.value = spin.max_value)
	return btn


func _on_fm_split_half() -> void:
	for entry in _fm_split_spinboxes:
		var total := int(entry["stack"]["count"])
		entry["spin"].value = total / 2


func _collect_out_units(spinbox_entries: Array) -> Array:
	var out_units: Array = []
	for entry in spinbox_entries:
		var count := int(entry["spin"].value)
		if count > 0:
			var src: Dictionary = entry["stack"]
			out_units.append(GlobalUnits.make_stack(
				src["type"],
				src["owner"],
				src["source"],
				count,
				GlobalUnits.stack_status(src),
				int(src.get("recover_in", 0)),
				bool(src.get("join_pending", false))
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
		var st := GlobalUnits.stack_status(stack)
		if st != GlobalUnits.STATUS.FIGHTING:
			lbl.text += " (%s)" % GlobalUnits.status_name(st)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = int(stack["count"])
		spin.value = 0
		spin.step = 1
		var entry := {"stack": stack.duplicate(), "spin": spin}
		var all_btn := _make_spin_all_button(spin)
		if is_left:
			_fm_left_spinboxes.append(entry)
			row.add_child(lbl)
			row.add_child(spin)
			row.add_child(all_btn)
		else:
			_fm_right_spinboxes.append(entry)
			row.add_child(all_btn)
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


func refresh_alliances_list() -> void:
	if alliances_list == null:
		return
	var base_map = parent_n
	if not is_instance_valid(base_map) or not base_map.has_method("get_playing_players_except"):
		return
	_refreshing_alliances = true
	for child in alliances_list.get_children():
		alliances_list.remove_child(child)
		child.queue_free()
	var my_id: int = int(base_map.my_pl_id)
	var others: Array = base_map.get_playing_players_except(my_id)
	if others.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No other players"
		alliances_list.add_child(empty_lbl)
		_refreshing_alliances = false
		return
	for pid in others:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pname := "?"
		if base_map.players.has(pid):
			pname = str(base_map.players[pid].name_)
		name_lbl.text = pname
		var chk := CheckButton.new()
		chk.text = "Allied"
		chk.button_pressed = base_map.are_allied(my_id, int(pid))
		chk.toggled.connect(_on_alliance_toggled.bind(int(pid)))
		row.add_child(name_lbl)
		row.add_child(chk)
		alliances_list.add_child(row)
	_refreshing_alliances = false


func _on_alliance_toggled(pressed: bool, other_id: int) -> void:
	if _refreshing_alliances:
		return
	if not is_instance_valid(parent_n) or not parent_n.has_method("do_set_alliance"):
		return
	parent_n.do_set_alliance(other_id, pressed)


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


func _ensure_province_levy_widgets() -> void:
	if _prov_happiness_lbl != null or province_tab_root == null:
		return
	province_tab_root.add_child(HSeparator.new())
	_prov_happiness_lbl = Label.new()
	_prov_happiness_lbl.text = "Happiness: —"
	province_tab_root.add_child(_prov_happiness_lbl)
	_prov_levy_lbl = Label.new()
	_prov_levy_lbl.text = "Levy: —"
	province_tab_root.add_child(_prov_levy_lbl)
	_prov_weapons_lbl = Label.new()
	_prov_weapons_lbl.text = "Weapons: —"
	_prov_weapons_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	province_tab_root.add_child(_prov_weapons_lbl)
	_prov_shipments_lbl = Label.new()
	_prov_shipments_lbl.text = ""
	_prov_shipments_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	province_tab_root.add_child(_prov_shipments_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_prov_recruit_btn = Button.new()
	_prov_recruit_btn.text = "Recruit army"
	_prov_recruit_btn.pressed.connect(_on_province_recruit_pressed)
	row.add_child(_prov_recruit_btn)
	_prov_ship_btn = Button.new()
	_prov_ship_btn.text = "Ship weapons"
	_prov_ship_btn.pressed.connect(_on_province_ship_pressed)
	row.add_child(_prov_ship_btn)
	province_tab_root.add_child(row)


func _fill_province_tab(base_map: Node, province_id: String) -> void:
	_ensure_province_levy_widgets()
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
		if _prov_happiness_lbl:
			_prov_happiness_lbl.text = "Happiness: —"
			_prov_levy_lbl.text = "Levy: —"
			_prov_weapons_lbl.text = "Weapons: —"
			_prov_shipments_lbl.text = ""
			_prov_recruit_btn.visible = false
			_prov_ship_btn.visible = false
		return
	province_tab_name.text = data.get("name", "—")
	province_tab_status.text = "Status: %s" % data.get("status_name", "—")
	province_tab_owner.text = "Owner: %s" % data.get("owner_name", "—")
	province_tab_defacto.text = "De facto: %s" % data.get("defacto_name", "—")
	province_tab_dejure.text = "De jure: %s" % data.get("dejure_name", "—")
	province_tab_population.text = "Population: %s (next: %s)" % [data.get("population_has", 0), data.get("population_will", 0)]
	if data.get("viewer_has_dejure", false):
		province_tab_income.text = "Predicted income: %s" % data.get("marks_will", 0)
	else:
		province_tab_income.text = "Predicted income: 0  (no de jure — no income)"

	var v = data.get("villages", {"control": 0, "all": 0})
	province_tab_villages.text = "%d / %d" % [v.get("control", 0), v.get("all", 0)]
	var t = data.get("towns", {"control": 0, "all": 0})
	province_tab_towns.text = "%d / %d" % [t.get("control", 0), t.get("all", 0)]
	var c = data.get("castles", {"control": 0, "all": 0})
	province_tab_castles.text = "%d / %d" % [c.get("control", 0), c.get("all", 0)]
	var e = data.get("economy", {"control": 0, "all": 0})
	province_tab_economy.text = "%d / %d" % [e.get("control", 0), e.get("all", 0)]

	_prov_happiness_lbl.text = "Happiness: %.0f" % float(data.get("happiness", 100))
	_prov_levy_lbl.text = "Levy this season: %d / remaining %d (cap 80%% of %d)" % [
		int(data.get("levied_this_season", 0)),
		int(data.get("levy_remaining", 0)),
		int(data.get("season_start_population", 0)),
	]
	var weapons: Dictionary = data.get("weapons", {})
	var wparts: PackedStringArray = []
	for k in GlobalUnits.WEAPON_KEYS:
		wparts.append("%s %d" % [GlobalUnits.weapon_name(k), int(weapons.get(k, 0))])
	_prov_weapons_lbl.text = "Weapons: %s" % ", ".join(wparts)

	var ship_lines: PackedStringArray = []
	if base_map.has_method("get_weapon_shipments_involving"):
		for s in base_map.get_weapon_shipments_involving(province_id):
			var cargo_bits: PackedStringArray = []
			var cargo: Dictionary = s.get("cargo", {})
			for k in GlobalUnits.WEAPON_KEYS:
				var amt := int(cargo.get(k, 0))
				if amt > 0:
					cargo_bits.append("%d %s" % [amt, GlobalUnits.weapon_name(k)])
			var from_name := str(s.get("from_id", "?"))
			var to_name := str(s.get("to_id", "?"))
			var from_data: Dictionary = base_map.get_province_data(from_name)
			var to_data: Dictionary = base_map.get_province_data(to_name)
			if not from_data.is_empty():
				from_name = str(from_data.get("name", from_name))
			if not to_data.is_empty():
				to_name = str(to_data.get("name", to_name))
			ship_lines.append("%s → %s (%d seasons): %s" % [
				from_name, to_name, int(s.get("seasons_left", 0)), ", ".join(cargo_bits),
			])
	_prov_shipments_lbl.text = ("In transit:\n" + "\n".join(ship_lines)) if not ship_lines.is_empty() else ""

	var has_dejure := bool(data.get("viewer_has_dejure", false))
	_prov_recruit_btn.visible = has_dejure
	_prov_ship_btn.visible = has_dejure


# --- Battle menu ------------------------------------------------------------

func _ensure_battle_menu() -> void:
	if _bt_panel != null:
		return
	_bt_panel = PanelContainer.new()
	_bt_panel.top_level = true
	_bt_panel.z_index = 140
	_bt_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_bt_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	_bt_title = Label.new()
	_bt_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bt_title.add_theme_font_size_override("font_size", 16)
	_bt_title.text = "Battle"
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_battle_menu)
	header.add_child(_bt_title)
	header.add_child(close_btn)
	_bt_body = VBoxContainer.new()
	_bt_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_bt_body)
	margin.add_child(vbox)
	_bt_panel.add_child(margin)
	add_child(_bt_panel)


func open_battle_menu(base_map, attacker_id: String, defender_army_id: String, building: Node) -> void:
	_ensure_battle_menu()
	_bt_base = base_map
	_bt_attacker_id = attacker_id
	_bt_defender_id = defender_army_id
	_bt_building = building
	_rebuild_battle_menu()


func _close_battle_menu() -> void:
	if _bt_panel != null:
		_bt_panel.visible = false
	_bt_base = null
	_bt_attacker_id = ""
	_bt_defender_id = ""
	_bt_building = null


func _rebuild_battle_menu() -> void:
	if _bt_base == null or not _bt_base.forces.has(_bt_attacker_id):
		_close_battle_menu()
		return
	for c in _bt_body.get_children():
		_bt_body.remove_child(c)
		c.queue_free()

	var atk_units: Array = _bt_base.forces[_bt_attacker_id]["units"]
	var atk_str := GlobalUnits.fighting_strength(atk_units)
	var atk_men := GlobalUnits.fighting_men(atk_units)
	var def_str := 0
	var def_men := 0
	var def_name := "Enemy"
	if _bt_building != null:
		def_str = _bt_base.get_building_battle_strength(_bt_building)
		def_men = GlobalUnits.fighting_men(_bt_base.get_all_building_garrison(_bt_building))
		def_name = _bt_base._building_display_name(_bt_building) if _bt_base.has_method("_building_display_name") else "Building"
		_bt_title.text = "Assault"
	else:
		if not _bt_base.forces.has(_bt_defender_id):
			_close_battle_menu()
			return
		var def_units: Array = _bt_base.forces[_bt_defender_id]["units"]
		def_str = GlobalUnits.fighting_strength(def_units)
		def_men = GlobalUnits.fighting_men(def_units)
		def_name = _fm_force_label(_bt_defender_id, false) if _bt_base.forces.has(_bt_defender_id) else "Enemy army"
		# Reuse label helper with temporary context
		var ctrl = _bt_base.get_force_controller(_bt_defender_id)
		if _bt_base.players.has(ctrl):
			def_name = "Army of %s" % str(_bt_base.players[ctrl].name_)
		_bt_title.text = "Battle"

	var atk_ctrl = _bt_base.get_force_controller(_bt_attacker_id)
	var atk_name := "Your army"
	if _bt_base.players.has(atk_ctrl):
		atk_name = "Army of %s" % str(_bt_base.players[atk_ctrl].name_)

	var you := Label.new()
	you.text = "%s\n%d fighting · strength %d" % [atk_name, atk_men, atk_str]
	you.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	you.custom_minimum_size = Vector2(360, 0)
	_bt_body.add_child(you)

	var vs := Label.new()
	vs.text = "vs"
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bt_body.add_child(vs)

	var them := Label.new()
	them.text = "%s\n%d fighting · strength %d" % [def_name, def_men, def_str]
	them.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	them.custom_minimum_size = Vector2(360, 0)
	_bt_body.add_child(them)

	var hint := Label.new()
	hint.text = "Strength is modified by luck when you attack. Stand ground leaves both armies in place."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(360, 0)
	hint.add_theme_font_size_override("font_size", 12)
	_bt_body.add_child(hint)

	_bt_body.add_child(HSeparator.new())

	var attack_btn := Button.new()
	attack_btn.text = "Attack"
	attack_btn.pressed.connect(_on_bt_attack)
	_bt_body.add_child(attack_btn)

	var stand_btn := Button.new()
	stand_btn.text = "Stand ground"
	stand_btn.pressed.connect(_close_battle_menu)
	_bt_body.add_child(stand_btn)

	_bt_panel.visible = true
	_bt_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_bt_panel.size = Vector2(minf(420, vp.x * 0.9), _bt_panel.get_combined_minimum_size().y)
	_bt_panel.position = (vp - _bt_panel.size) * 0.5


func _on_bt_attack() -> void:
	if _bt_base == null:
		return
	var base = _bt_base
	var atk := _bt_attacker_id
	var def := _bt_defender_id
	var building = _bt_building
	_close_battle_menu()
	base.do_battle_attack(atk, def, building)


func on_battle_resolved(base_map, attacker_id: String, building: Node, attacker_won: bool, hostage_pool: Array, event_id: String = "") -> void:
	# Battle report is delivered via the event inbox. Only the attacker
	# controller gets hostage / building follow-up menus. With hostages, the
	# report opens after fate is chosen (see apply_battle_hostage_fate).
	var show_followup := false
	if base_map.forces.has(attacker_id):
		show_followup = base_map.get_force_controller(attacker_id) == base_map.my_pl_id

	if not show_followup:
		return
	if not attacker_won:
		return

	# Hostages first; building actions after (or immediately if no hostages).
	if not hostage_pool.is_empty():
		open_hostage_menu(base_map, attacker_id, hostage_pool, building, event_id)
	elif building != null and is_instance_valid(building):
		open_building_actions_menu(base_map, attacker_id, building)


# --- Event report card ------------------------------------------------------

func _ensure_event_report() -> void:
	if _er_panel != null:
		return
	_er_panel = PanelContainer.new()
	_er_panel.top_level = true
	# Below hostage / building-action menus so follow-ups stay clickable.
	_er_panel.z_index = 140
	_er_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_er_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	_er_title = Label.new()
	_er_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_er_title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_event_report)
	header.add_child(_er_title)
	header.add_child(close_btn)
	_er_body = Label.new()
	_er_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_er_body.custom_minimum_size = Vector2(320, 0)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_er_goto = Button.new()
	_er_goto.text = "Go to location"
	_er_goto.pressed.connect(_on_event_report_goto)
	var ok_btn := Button.new()
	ok_btn.text = "Close"
	ok_btn.pressed.connect(_close_event_report)
	actions.add_child(_er_goto)
	actions.add_child(ok_btn)
	vbox.add_child(header)
	vbox.add_child(_er_body)
	vbox.add_child(actions)
	margin.add_child(vbox)
	_er_panel.add_child(margin)
	add_child(_er_panel)


func open_event_report(base_map, event_id: String) -> void:
	if base_map == null or event_id == "":
		return
	_ensure_event_report()
	_er_base = base_map
	_er_event_id = event_id
	var event: Dictionary = base_map.get_event(event_id) if base_map.has_method("get_event") else {}
	if event.is_empty():
		return
	# MSG menu steals input when brought in front of the report; close it first.
	if msg_menu != null and msg_menu.visible:
		msg_menu.visible = false
	var reader_id: int = int(base_map.my_pl_id)
	var name_cb := Callable(base_map, "player_display_name")
	_er_title.text = GameEvents.report_title(event, reader_id)
	_er_body.text = GameEvents.report_body(event, reader_id, name_cb)
	_er_panel.visible = true
	_er_panel.z_index = 200
	move_child(_er_panel, get_child_count() - 1)
	# Center roughly on screen.
	var vp := get_viewport().get_visible_rect().size
	_er_panel.reset_size()
	var sz := _er_panel.get_combined_minimum_size()
	_er_panel.position = Vector2((vp.x - sz.x) * 0.5, (vp.y - sz.y) * 0.35)


func _close_event_report() -> void:
	if _er_panel != null:
		_er_panel.visible = false
	_er_base = null
	_er_event_id = ""


func _on_event_report_goto() -> void:
	if _er_base != null and _er_event_id != "" and _er_base.has_method("center_camera_on_event"):
		_er_base.center_camera_on_event(_er_event_id)


# --- Hostage menu -----------------------------------------------------------

func _ensure_hostage_menu() -> void:
	if _hs_panel != null:
		return
	_hs_panel = PanelContainer.new()
	_hs_panel.top_level = true
	_hs_panel.z_index = 145
	_hs_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_hs_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	var vbox := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Enemy wounded"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_on_hs_sword)
	header.add_child(title)
	header.add_child(close_btn)
	_hs_body = VBoxContainer.new()
	_hs_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_hs_body)
	margin.add_child(vbox)
	_hs_panel.add_child(margin)
	add_child(_hs_panel)


func open_hostage_menu(base_map, attacker_id: String, pool: Array, building: Node, event_id: String = "") -> void:
	_ensure_hostage_menu()
	_hs_base = base_map
	_hs_attacker_id = attacker_id
	_hs_pool = GlobalUnits.clone_units(pool)
	_hs_building = building
	_hs_event_id = event_id
	for c in _hs_body.get_children():
		_hs_body.remove_child(c)
		c.queue_free()
	var info := Label.new()
	info.text = "Take them as hostages (heal in 2 seasons, then Captured) or put them to the sword."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(360, 0)
	_hs_body.add_child(info)
	var roster := Label.new()
	roster.text = GlobalUnits.describe_units(_hs_pool)
	_hs_body.add_child(roster)
	_hs_body.add_child(HSeparator.new())
	var take_btn := Button.new()
	take_btn.text = "Take as hostages"
	take_btn.pressed.connect(_on_hs_take)
	_hs_body.add_child(take_btn)
	var sword_btn := Button.new()
	sword_btn.text = "Put to the sword"
	sword_btn.pressed.connect(_on_hs_sword)
	_hs_body.add_child(sword_btn)
	_hs_panel.visible = true
	_hs_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_hs_panel.size = Vector2(minf(420, vp.x * 0.9), _hs_panel.get_combined_minimum_size().y)
	_hs_panel.position = (vp - _hs_panel.size) * 0.5


func _close_hostage_menu() -> void:
	if _hs_panel != null:
		_hs_panel.visible = false
	_hs_base = null
	_hs_attacker_id = ""
	_hs_pool.clear()
	_hs_building = null
	_hs_event_id = ""


func _on_hs_take() -> void:
	var base = _hs_base
	var atk := _hs_attacker_id
	var pool: Array = _hs_pool.duplicate(true)
	var building = _hs_building
	var event_id := _hs_event_id
	_close_hostage_menu()
	if base != null:
		base.do_take_hostages(atk, pool)
		if event_id != "" and base.has_method("resolve_battle_hostage_fate"):
			base.resolve_battle_hostage_fate(event_id, "taken")
		if building != null and is_instance_valid(building) and base.forces.has(atk):
			open_building_actions_menu(base, atk, building)


func _on_hs_sword() -> void:
	var base = _hs_base
	var atk := _hs_attacker_id
	var building = _hs_building
	var event_id := _hs_event_id
	_close_hostage_menu()
	if base != null:
		if event_id != "" and base.has_method("resolve_battle_hostage_fate"):
			base.resolve_battle_hostage_fate(event_id, "sword")
		if building != null and is_instance_valid(building) and base.forces.has(atk):
			open_building_actions_menu(base, atk, building)


# --- Building actions (capture / raid / raze) -------------------------------

func _ensure_building_actions_menu() -> void:
	if _ba_panel != null:
		return
	_ba_panel = PanelContainer.new()
	_ba_panel.top_level = true
	_ba_panel.z_index = 142
	_ba_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ba_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	var vbox := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.name = "Title"
	title.text = "Settlement"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_building_actions_menu)
	header.add_child(title)
	header.add_child(close_btn)
	_ba_body = VBoxContainer.new()
	_ba_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_ba_body)
	margin.add_child(vbox)
	_ba_panel.add_child(margin)
	add_child(_ba_panel)


func open_building_actions_menu(base_map, force_id: String, building: Node) -> void:
	_ensure_building_actions_menu()
	_ba_base = base_map
	_ba_force_id = force_id
	_ba_building = building
	for c in _ba_body.get_children():
		_ba_body.remove_child(c)
		c.queue_free()
	var title: Label = _ba_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/Title")
	var bname = base_map._building_display_name(building) if base_map.has_method("_building_display_name") else "Building"
	if title != null:
		title.text = bname

	var type_ = building.get("type_")
	var is_castle = type_ == GlobalStuff.BUILDING_TYPE.CASTLE
	var is_economy = type_ == GlobalStuff.BUILDING_TYPE.ECONOMY

	var loot = base_map.compute_raid_loot(building)
	var can_raid = base_map.can_raid_building(building)
	var is_razed = base_map.is_building_razed(building) if base_map.has_method("is_building_razed") else false

	var capt_btn := Button.new()
	capt_btn.text = "Capture"
	capt_btn.pressed.connect(_on_ba_capture)
	_ba_body.add_child(capt_btn)

	var raid_btn := Button.new()
	raid_btn.text = "Raid (%d marks)" % loot
	raid_btn.disabled = not can_raid or loot <= 0
	if is_razed:
		raid_btn.text = "Raid (razed)"
		raid_btn.disabled = true
	elif not can_raid:
		raid_btn.text = "Raid (already raided this season)"
	raid_btn.pressed.connect(_on_ba_raid)
	_ba_body.add_child(raid_btn)

	if not is_castle:
		var raze_btn := Button.new()
		raze_btn.text = "Raze"
		if is_razed or (base_map.has_method("can_raze_building") and not base_map.can_raze_building(building)):
			raze_btn.disabled = true
			raze_btn.text = "Raze (already razed)" if is_razed else "Raze"
		raze_btn.pressed.connect(_on_ba_raze)
		_ba_body.add_child(raze_btn)

	if is_economy:
		# Economy: capture or raze only.
		raid_btn.visible = false

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.pressed.connect(_close_building_actions_menu)
	_ba_body.add_child(leave_btn)

	_ba_panel.visible = true
	_ba_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_ba_panel.size = Vector2(minf(400, vp.x * 0.9), _ba_panel.get_combined_minimum_size().y)
	_ba_panel.position = (vp - _ba_panel.size) * 0.5


func _close_building_actions_menu() -> void:
	if _ba_panel != null:
		_ba_panel.visible = false
	_ba_base = null
	_ba_force_id = ""
	_ba_building = null


func _on_ba_capture() -> void:
	var base = _ba_base
	var fid := _ba_force_id
	var building = _ba_building
	_close_building_actions_menu()
	if base != null and building != null:
		base.do_capture_building(fid, building)


func _on_ba_raid() -> void:
	var base = _ba_base
	var fid := _ba_force_id
	var building = _ba_building
	_close_building_actions_menu()
	if base != null and building != null:
		base.do_raid_building(fid, building)


func _on_ba_raze() -> void:
	var base = _ba_base
	var fid := _ba_force_id
	var building = _ba_building
	_close_building_actions_menu()
	if base != null and building != null:
		base.do_raze_building(fid, building)


# --- Province recruit / ship weapons ----------------------------------------

func _on_province_recruit_pressed() -> void:
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	open_recruit_menu(parent_n, selected_province_id)


func _on_province_ship_pressed() -> void:
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	open_ship_weapons_menu(parent_n, selected_province_id)


func _ensure_recruit_panel() -> void:
	if _rc_panel != null:
		return
	_rc_panel = PanelContainer.new()
	_rc_panel.top_level = true
	_rc_panel.z_index = 140
	_rc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rc_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Recruit army"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_recruit_menu)
	header.add_child(close_btn)
	vbox.add_child(header)
	_rc_info_lbl = Label.new()
	_rc_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rc_info_lbl.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(_rc_info_lbl)
	vbox.add_child(HSeparator.new())
	_rc_body = VBoxContainer.new()
	_rc_body.add_theme_constant_override("separation", 4)
	vbox.add_child(_rc_body)
	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_recruit_menu)
	btn_row.add_child(cancel_btn)
	var confirm_btn := Button.new()
	confirm_btn.text = "Raise levy"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(_on_recruit_confirm)
	btn_row.add_child(confirm_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_rc_panel.add_child(margin)
	add_child(_rc_panel)


func open_recruit_menu(base_map: Node, province_id: String) -> void:
	_ensure_recruit_panel()
	_rc_base = base_map
	_rc_province_id = province_id
	var data: Dictionary = base_map.get_province_data(province_id)
	if data.is_empty() or not data.get("viewer_has_dejure", false):
		show_info_popup("You need de jure ownership to recruit here")
		return

	var levy_left := int(data.get("levy_remaining", 0))
	var owned_pop := int(data.get("owned_population", 0))
	var max_men := mini(levy_left, owned_pop)
	var weapons: Dictionary = data.get("weapons", {})
	_rc_info_lbl.text = (
		"%s\nMax this raise: %d (levy left %d, your pop %d)\nMin %d men. First 10%% of season pop is free on happiness."
		% [data.get("name", "Province"), max_men, levy_left, owned_pop, GlobalUnits.MIN_SPLIT_MEN]
	)

	for child in _rc_body.get_children():
		child.queue_free()
	_rc_spinboxes.clear()

	var types := [
		GlobalUnits.UNIT_TYPE.PEASANT,
		GlobalUnits.UNIT_TYPE.MACEMEN,
		GlobalUnits.UNIT_TYPE.PIKEMEN,
		GlobalUnits.UNIT_TYPE.ARCHER,
		GlobalUnits.UNIT_TYPE.SWORDSMEN,
		GlobalUnits.UNIT_TYPE.CROSSBOWMEN,
		GlobalUnits.UNIT_TYPE.KNIGHTS,
	]
	for ut in types:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cost: Dictionary = GlobalUnits.weapon_cost_for_type(ut)
		var cost_txt := "no weapons"
		if not cost.is_empty():
			var bits: PackedStringArray = []
			for k in cost:
				bits.append("%d %s" % [int(cost[k]), GlobalUnits.weapon_name(k)])
			cost_txt = ", ".join(bits)
		var type_max := max_men
		if not cost.is_empty():
			type_max = max_men
			for k in cost:
				var per := int(cost[k])
				if per <= 0:
					continue
				type_max = mini(type_max, int(weapons.get(k, 0)) / per)
		lbl.text = "%s (%s)  max %d" % [GlobalUnits.unit_name(ut), cost_txt, type_max]
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(0, type_max)
		spin.step = 1
		spin.value = 0
		spin.custom_minimum_size = Vector2(90, 0)
		row.add_child(spin)
		_rc_body.add_child(row)
		_rc_spinboxes[ut] = spin

	_rc_panel.visible = true
	_rc_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_rc_panel.size = Vector2(minf(420, vp.x * 0.9), _rc_panel.get_combined_minimum_size().y)
	_rc_panel.position = (vp - _rc_panel.size) * 0.5


func _close_recruit_menu() -> void:
	if _rc_panel != null:
		_rc_panel.visible = false
	_rc_base = null
	_rc_province_id = ""
	_rc_spinboxes.clear()


func _on_recruit_confirm() -> void:
	var base = _rc_base
	var province_id := _rc_province_id
	var composition: Array = []
	for ut in _rc_spinboxes:
		var spin: SpinBox = _rc_spinboxes[ut]
		var cnt := int(spin.value)
		if cnt > 0:
			composition.append({"type": int(ut), "count": cnt})
	_close_recruit_menu()
	if base == null or province_id == "":
		return
	var total := GlobalUnits.composition_total_men(composition)
	if total < GlobalUnits.MIN_SPLIT_MEN:
		show_info_popup("Need at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
		return
	var data: Dictionary = base.get_province_data(province_id)
	var max_men := mini(int(data.get("levy_remaining", 0)), int(data.get("owned_population", 0)))
	if total > max_men:
		show_info_popup("Cannot raise more than %d men" % max_men)
		return
	var need := GlobalUnits.weapons_needed_for_composition(composition)
	if not GlobalUnits.can_afford_weapons(data.get("weapons", {}), need):
		show_info_popup("Not enough weapons in this province")
		return
	base.do_recruit_levy(province_id, composition)


func _ensure_ship_panel() -> void:
	if _sw_panel != null:
		return
	_sw_panel = PanelContainer.new()
	_sw_panel.top_level = true
	_sw_panel.z_index = 140
	_sw_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_sw_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Ship weapons"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_ship_menu)
	header.add_child(close_btn)
	vbox.add_child(header)
	_sw_info_lbl = Label.new()
	_sw_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sw_info_lbl.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_sw_info_lbl)
	var dest_row := HBoxContainer.new()
	var dest_lbl := Label.new()
	dest_lbl.text = "Destination:"
	dest_row.add_child(dest_lbl)
	_sw_dest = OptionButton.new()
	_sw_dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest_row.add_child(_sw_dest)
	vbox.add_child(dest_row)
	_sw_body = VBoxContainer.new()
	_sw_body.add_theme_constant_override("separation", 4)
	vbox.add_child(_sw_body)
	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_ship_menu)
	btn_row.add_child(cancel_btn)
	var confirm_btn := Button.new()
	confirm_btn.text = "Ship (%d seasons)" % GlobalUnits.WEAPON_SHIP_SEASONS
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(_on_ship_confirm)
	btn_row.add_child(confirm_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_sw_panel.add_child(margin)
	add_child(_sw_panel)


func open_ship_weapons_menu(base_map: Node, province_id: String) -> void:
	_ensure_ship_panel()
	_sw_base = base_map
	_sw_province_id = province_id
	var data: Dictionary = base_map.get_province_data(province_id)
	if data.is_empty() or not data.get("viewer_has_dejure", false):
		show_info_popup("You need de jure ownership to ship from here")
		return

	_sw_info_lbl.text = "Ship from %s. Cargo arrives in %d seasons to whoever holds de jure at the destination." % [
		data.get("name", "Province"), GlobalUnits.WEAPON_SHIP_SEASONS
	]

	_sw_dest.clear()
	_sw_dest_ids.clear()
	var list_data: Array = base_map.get_all_provinces_list_data(base_map.my_pl_id)
	for entry in list_data:
		var pid := str(entry.get("id", ""))
		if pid == province_id:
			continue
		var dest_data: Dictionary = base_map.get_province_data(pid)
		if not dest_data.get("viewer_has_dejure", false):
			continue
		_sw_dest.add_item(str(dest_data.get("name", pid)))
		_sw_dest_ids.append(pid)
	if _sw_dest_ids.is_empty():
		_sw_base = null
		_sw_province_id = ""
		show_info_popup("No other de jure province to ship to")
		return

	for child in _sw_body.get_children():
		child.queue_free()
	_sw_spinboxes.clear()
	var weapons: Dictionary = data.get("weapons", {})
	for k in GlobalUnits.WEAPON_KEYS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s (have %d)" % [GlobalUnits.weapon_name(k), int(weapons.get(k, 0))]
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(0, int(weapons.get(k, 0)))
		spin.step = 1
		spin.value = 0
		spin.custom_minimum_size = Vector2(90, 0)
		row.add_child(spin)
		_sw_body.add_child(row)
		_sw_spinboxes[k] = spin

	_sw_panel.visible = true
	_sw_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_sw_panel.size = Vector2(minf(400, vp.x * 0.9), _sw_panel.get_combined_minimum_size().y)
	_sw_panel.position = (vp - _sw_panel.size) * 0.5


func _close_ship_menu() -> void:
	if _sw_panel != null:
		_sw_panel.visible = false
	_sw_base = null
	_sw_province_id = ""
	_sw_spinboxes.clear()
	_sw_dest_ids.clear()


func _on_ship_confirm() -> void:
	var base = _sw_base
	var from_id := _sw_province_id
	var dest_idx := _sw_dest.selected if _sw_dest != null else -1
	var to_id := ""
	if dest_idx >= 0 and dest_idx < _sw_dest_ids.size():
		to_id = str(_sw_dest_ids[dest_idx])
	var cargo := GlobalUnits.empty_weapon_stock()
	var any := false
	for k in _sw_spinboxes:
		var amt := int(_sw_spinboxes[k].value)
		cargo[k] = amt
		if amt > 0:
			any = true
	_close_ship_menu()
	if base == null or from_id == "" or to_id == "":
		show_info_popup("Pick a destination province")
		return
	if not any:
		show_info_popup("Select weapons to ship")
		return
	base.do_ship_weapons(from_id, to_id, cargo)


# --- Merchant shop ----------------------------------------------------------

func _ensure_merchant_shop() -> void:
	if _ms_panel != null:
		return
	_ms_panel = PanelContainer.new()
	_ms_panel.top_level = true
	_ms_panel.z_index = 140
	_ms_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ms_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Merchant"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_merchant_shop)
	header.add_child(close_btn)
	vbox.add_child(header)
	_ms_info_lbl = Label.new()
	_ms_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ms_info_lbl.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(_ms_info_lbl)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(360, 220)
	var weapons_tab := VBoxContainer.new()
	weapons_tab.name = "Weapons"
	weapons_tab.add_theme_constant_override("separation", 4)
	var w_scroll := ScrollContainer.new()
	w_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	w_scroll.custom_minimum_size = Vector2(0, 160)
	_ms_weapons_body = VBoxContainer.new()
	_ms_weapons_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_weapons_body.add_theme_constant_override("separation", 4)
	w_scroll.add_child(_ms_weapons_body)
	weapons_tab.add_child(w_scroll)
	tabs.add_child(weapons_tab)
	var materials_tab := VBoxContainer.new()
	materials_tab.name = "Materials"
	materials_tab.add_theme_constant_override("separation", 4)
	var m_scroll := ScrollContainer.new()
	m_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m_scroll.custom_minimum_size = Vector2(0, 160)
	_ms_materials_body = VBoxContainer.new()
	_ms_materials_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_materials_body.add_theme_constant_override("separation", 4)
	m_scroll.add_child(_ms_materials_body)
	materials_tab.add_child(m_scroll)
	tabs.add_child(materials_tab)
	vbox.add_child(tabs)
	_ms_total_lbl = Label.new()
	_ms_total_lbl.text = "Total: 0 marks"
	vbox.add_child(_ms_total_lbl)
	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_merchant_shop)
	btn_row.add_child(cancel_btn)
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_btn.pressed.connect(_on_merchant_buy_confirm)
	btn_row.add_child(buy_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_ms_panel.add_child(margin)
	add_child(_ms_panel)


func open_merchant_shop(base_map: Node, merchant: Node) -> void:
	_ensure_merchant_shop()
	_ms_base = base_map
	_ms_merchant = merchant
	var prov = merchant.get("province")
	var pname := "Province"
	if prov != null and prov.get("p_name") != null:
		pname = str(prov.p_name)
	_ms_competition = base_map.merchant_competition_in_province(prov)
	var marks := 0
	if base_map.players.has(base_map.my_pl_id):
		marks = int(base_map.players[base_map.my_pl_id].game_data.get("marks", 0))
	var info := "Buying for %s.\nYour marks: %d" % [pname, marks]
	if _ms_competition:
		info += "\nCompetition: 15% discount (2+ merchants here)"
	_ms_info_lbl.text = info

	for child in _ms_weapons_body.get_children():
		child.queue_free()
	_ms_weapon_spinboxes.clear()
	for k in GlobalUnits.WEAPON_KEYS:
		_ms_add_shop_row(
			_ms_weapons_body,
			_ms_weapon_spinboxes,
			k,
			GlobalUnits.weapon_name(k),
			GlobalUnits.weapon_mark_price_discounted(k, _ms_competition),
			"weapon"
		)

	for child in _ms_materials_body.get_children():
		child.queue_free()
	_ms_material_spinboxes.clear()
	for k in GlobalUnits.MATERIAL_KEYS:
		_ms_add_shop_row(
			_ms_materials_body,
			_ms_material_spinboxes,
			k,
			GlobalUnits.material_name(k),
			GlobalUnits.material_mark_price_discounted(k, _ms_competition),
			"material"
		)

	_refresh_merchant_total()
	_ms_panel.visible = true
	_ms_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_ms_panel.size = Vector2(minf(480, vp.x * 0.9), minf(420, vp.y * 0.85))
	_ms_panel.position = (vp - _ms_panel.size) * 0.5


func _ms_add_shop_row(
	body: VBoxContainer,
	spin_map: Dictionary,
	key: String,
	display_name: String,
	price: int,
	kind: String
) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = "%s — %d marks each" % [display_name, price]
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999
	spin.step = 1
	spin.value = 0
	spin.custom_minimum_size = Vector2(90, 0)
	spin.value_changed.connect(_on_merchant_qty_changed)
	row.add_child(spin)
	var max_btn := Button.new()
	max_btn.text = "MAX"
	max_btn.pressed.connect(_on_merchant_max_pressed.bind(key, kind))
	row.add_child(max_btn)
	body.add_child(row)
	spin_map[key] = spin


func _on_merchant_qty_changed(_value: float) -> void:
	_refresh_merchant_total()


func _merchant_player_marks() -> int:
	if _ms_base == null or not _ms_base.players.has(_ms_base.my_pl_id):
		return 0
	return int(_ms_base.players[_ms_base.my_pl_id].game_data.get("marks", 0))


func _merchant_item_price(key: String, kind: String) -> int:
	if kind == "material":
		return GlobalUnits.material_mark_price_discounted(key, _ms_competition)
	return GlobalUnits.weapon_mark_price_discounted(key, _ms_competition)


func _merchant_cart_cost_excluding(exclude_key: String, exclude_kind: String) -> int:
	var total := 0
	for k in _ms_weapon_spinboxes:
		if exclude_kind == "weapon" and k == exclude_key:
			continue
		var amt := int(_ms_weapon_spinboxes[k].value)
		if amt > 0:
			total += GlobalUnits.weapon_mark_price_discounted(k, _ms_competition) * amt
	for k in _ms_material_spinboxes:
		if exclude_kind == "material" and k == exclude_key:
			continue
		var amt := int(_ms_material_spinboxes[k].value)
		if amt > 0:
			total += GlobalUnits.material_mark_price_discounted(k, _ms_competition) * amt
	return total


func _on_merchant_max_pressed(key: String, kind: String) -> void:
	var spin_map: Dictionary = _ms_material_spinboxes if kind == "material" else _ms_weapon_spinboxes
	if not spin_map.has(key):
		return
	var price := _merchant_item_price(key, kind)
	if price <= 0:
		return
	var remaining := _merchant_player_marks() - _merchant_cart_cost_excluding(key, kind)
	var max_qty := maxi(0, remaining / price)
	spin_map[key].value = max_qty
	_refresh_merchant_total()


func _refresh_merchant_total() -> void:
	if _ms_total_lbl == null:
		return
	var total := 0
	for k in _ms_weapon_spinboxes:
		var amt := int(_ms_weapon_spinboxes[k].value)
		if amt > 0:
			total += GlobalUnits.weapon_mark_price_discounted(k, _ms_competition) * amt
	for k in _ms_material_spinboxes:
		var amt := int(_ms_material_spinboxes[k].value)
		if amt > 0:
			total += GlobalUnits.material_mark_price_discounted(k, _ms_competition) * amt
	_ms_total_lbl.text = "Total: %d marks" % total


func _close_merchant_shop() -> void:
	if _ms_panel != null:
		_ms_panel.visible = false
	_ms_base = null
	_ms_merchant = null
	_ms_weapon_spinboxes.clear()
	_ms_material_spinboxes.clear()
	_ms_competition = false


func _on_merchant_buy_confirm() -> void:
	var base = _ms_base
	var merchant = _ms_merchant
	var weapons := GlobalUnits.empty_weapon_stock()
	var materials := GlobalUnits.empty_material_stock()
	var any := false
	for k in _ms_weapon_spinboxes:
		var amt := int(_ms_weapon_spinboxes[k].value)
		weapons[k] = amt
		if amt > 0:
			any = true
	for k in _ms_material_spinboxes:
		var amt := int(_ms_material_spinboxes[k].value)
		materials[k] = amt
		if amt > 0:
			any = true
	var merchant_id := ""
	if merchant != null:
		merchant_id = String(merchant.name)
	_close_merchant_shop()
	if base == null or merchant_id == "":
		return
	if not any:
		show_info_popup("Select items to buy")
		return
	base.do_buy_from_merchant(merchant_id, weapons, materials)
