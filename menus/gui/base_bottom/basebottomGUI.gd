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
@onready var map_tabs := $map_menu/margin/vbox/tabs
@onready var minimap := $map_menu/margin/vbox/tabs/Map/Minimap

@onready var parent_n = get_parent()

# Economy menu tab refs
@onready var economy_tabs := $economy_menu/margin/vbox/tabs
@onready var overview_provinces_lbl := $economy_menu/margin/vbox/tabs/overview/provinces_count_lbl
@onready var overview_money_lbl := $economy_menu/margin/vbox/tabs/overview/money_lbl
@onready var overview_population_lbl := $economy_menu/margin/vbox/tabs/overview/population_lbl
@onready var provinces_list_container := $economy_menu/margin/vbox/tabs/all_provinces/ScrollContainer/provinces_list
@onready var province_tab_name := $economy_menu/margin/vbox/tabs/province/province_name_lbl
@onready var province_tab_status := $economy_menu/margin/vbox/tabs/province/info_grid/status_lbl
@onready var province_tab_owner := $economy_menu/margin/vbox/tabs/province/info_grid/owner_lbl
@onready var province_tab_defacto := $economy_menu/margin/vbox/tabs/province/info_grid/defacto_lbl
@onready var province_tab_dejure := $economy_menu/margin/vbox/tabs/province/info_grid/dejure_lbl
@onready var province_tab_population := $economy_menu/margin/vbox/tabs/province/info_grid/population_prov_lbl
@onready var province_tab_income := $economy_menu/margin/vbox/tabs/province/info_grid/income_prov_lbl
@onready var province_tab_villages := $economy_menu/margin/vbox/tabs/province/buildings_grid/villages_val
@onready var province_tab_towns := $economy_menu/margin/vbox/tabs/province/buildings_grid/towns_val
@onready var province_tab_castles := $economy_menu/margin/vbox/tabs/province/buildings_grid/castles_val
@onready var province_tab_economy := $economy_menu/margin/vbox/tabs/province/buildings_grid/economy_val
@onready var province_tab_root := $economy_menu/margin/vbox/tabs/province
@onready var caravan_tab_root := $economy_menu/margin/vbox/tabs/caravan
@onready var caravan_tab_info := $economy_menu/margin/vbox/tabs/caravan/caravan_info
@onready var caravan_tab_send_btn := $economy_menu/margin/vbox/tabs/caravan/send_btn
@onready var caravan_tab_list := $economy_menu/margin/vbox/tabs/caravan/ScrollContainer/caravan_list

@onready var alliances_list := $war_menu/margin/vbox/tabs/Alliances/ScrollContainer/alliances_list
@onready var diplomacy_list := $war_menu/margin/vbox/tabs/Diplomacy/ScrollContainer/diplomacy_list
@onready var military_upkeep_lbl := $war_menu/margin/vbox/tabs/Military/upkeep_summary_lbl
@onready var military_strikes_lbl := $war_menu/margin/vbox/tabs/Military/strikes_lbl
@onready var military_list := $war_menu/margin/vbox/tabs/Military/ScrollContainer/military_list

var selected_province_id: String = ""
var _refreshing_alliances := false

# VIP trade UI (War → Diplomacy tab / runtime panels).
var _vt_panel: PanelContainer = null
var _vt_body: VBoxContainer = null
var _vt_base = null
var _vt_to_pid: int = -1
var _vt_offer_vip_checks: Dictionary = {}  # vip_id -> CheckBox
var _vt_offer_marks_spin: SpinBox = null
var _vt_request_marks_spin: SpinBox = null
var _incoming_trade_panel: PanelContainer = null

# Province levy / weapons UI (built under province tab at runtime).
var _prov_happiness_lbl: Label = null
var _prov_levy_lbl: Label = null
var _prov_weapons_lbl: Label = null
var _prov_recruit_btn: Button = null

# Recruit levy panel.
var _rc_panel: PanelContainer = null
var _rc_body: VBoxContainer = null
var _rc_info_lbl: Label = null
var _rc_base = null
var _rc_province_id: String = ""
var _rc_spinboxes: Dictionary = {}  # UNIT_TYPE -> SpinBox

# Send caravan panel (Economy → Caravan).
var _cv_send_panel: PanelContainer = null
var _cv_send_body: VBoxContainer = null
var _cv_send_info_lbl: Label = null
var _cv_send_from: OptionButton = null
var _cv_send_dest: OptionButton = null
var _cv_send_confirm: Button = null
var _cv_send_base = null
var _cv_send_from_ids: Array = []
var _cv_send_dest_ids: Array = []
var _cv_send_spinboxes: Dictionary = {}  # cargo key -> SpinBox

# Map caravan inspect / redirect panel.
var _cv_panel: PanelContainer = null
var _cv_body: VBoxContainer = null
var _cv_base = null
var _cv_caravan: Node2D = null
var _cv_dest: OptionButton = null
var _cv_dest_ids: Array = []

# Enemy caravan capture panel.
var _cv_cap_panel: PanelContainer = null
var _cv_cap_info: Label = null
var _cv_cap_base = null
var _cv_cap_caravan: Node2D = null
var _cv_cap_force_id: String = ""

# Merchant shop panel (tabbed: Weapons + Materials).
var _ms_panel: PanelContainer = null
var _ms_title: Label = null
var _ms_info_lbl: Label = null
var _ms_weapons_body: VBoxContainer = null
var _ms_materials_body: VBoxContainer = null
var _ms_total_lbl: Label = null
var _ms_base = null
var _ms_merchant: Node = null
var _ms_weapon_spinboxes: Dictionary = {}  # weapon key -> SpinBox
var _ms_material_spinboxes: Dictionary = {}  # material key -> SpinBox
var _ms_competition := false

# Merchant raid confirm panel.
var _mr_panel: PanelContainer = null
var _mr_info: Label = null
var _mr_base = null
var _mr_force_id: String = ""
var _mr_merchant: Node = null

# Field raid confirm panel.
var _fr_panel: PanelContainer = null
var _fr_info: Label = null
var _fr_base = null
var _fr_force_id: String = ""
var _fr_field: Node = null

# Sellswords hire panel (all-or-nothing).
var _ss_panel: PanelContainer = null
var _ss_info_lbl: Label = null
var _ss_body: VBoxContainer = null
var _ss_total_lbl: Label = null
var _ss_base = null
var _ss_band: Node = null

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
var _db_loot_send_btn: Button = null
var _db_discard_btn: Button = null

# Force cargo panel (deposit / withdraw / send-from-army / disband-send).
var _fc_panel: PanelContainer = null
var _fc_title: Label = null
var _fc_info_lbl: Label = null
var _fc_body: VBoxContainer = null
var _fc_dest: OptionButton = null
var _fc_dest_row: HBoxContainer = null
var _fc_confirm_btn: Button = null
var _fc_base = null
var _fc_force_id: String = ""
var _fc_mode: String = ""  # deposit | withdraw | send | disband_send
var _fc_spinboxes: Dictionary = {}  # weapon key -> SpinBox
var _fc_dest_ids: Array = []
var _fc_after_disband_army: Node2D = null

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
var _fm_left_vip_checks: Dictionary = {}  # vip_id -> CheckBox
var _fm_right_vip_checks: Dictionary = {}
var _fm_left_loot_spinboxes: Dictionary = {}  # weapon key -> SpinBox
var _fm_right_loot_spinboxes: Dictionary = {}
var _fm_split_loot_spinboxes: Dictionary = {}

# Building info popup (built at runtime): header with title + X, plus a body.
var _building_popup: PanelContainer = null
var _building_popup_title: Label = null
var _building_popup_body: Label = null
var _building_popup_close: Button = null
var _building_popup_deploy: Button = null
var _building_popup_node: Node = null
var _building_popup_pinned := false

# Field crop popup.
var _field_popup: PanelContainer = null
var _field_popup_title: Label = null
var _field_popup_body: Label = null
var _field_popup_btns: HBoxContainer = null
var _field_popup_field: Node = null
var _field_popup_base = null

# Province fields / labor UI.
var _prov_manage_root: VBoxContainer = null
var _prov_fields_lbl: Label = null
var _prov_populate_idle_btn: Button = null
var _prov_stock_lbl: Label = null
var _prov_labor_lbl: Label = null
var _prov_agri_lbl: Label = null
var _prov_prod_lbl: Label = null
var _prov_smith_lbl: Label = null
var _prov_labor_box: VBoxContainer = null
var _prov_labor_sliders: Dictionary = {} # category -> HSlider
var _prov_labor_updating := false
var _prov_idle_field_count: int = 0

# Populate idle fields popup.
var _populate_idle_popup: PanelContainer = null
var _populate_idle_body: Label = null

# Economy building popup (build / demolish).
var _econ_popup: PanelContainer = null
var _econ_popup_title: Label = null
var _econ_popup_body: Label = null
var _econ_popup_btns: VBoxContainer = null
var _econ_popup_building: Node = null
var _econ_popup_base = null

# Battle preview / result UI (built at runtime).
var _bt_panel: PanelContainer = null
var _bt_body: VBoxContainer = null
var _bt_title: Label = null
var _bt_base = null
var _bt_attacker_id: String = ""
var _bt_defender_id: String = ""
var _bt_building: Node = null

# First-contact castle siege prompt (start engines / assault now).
var _sg_panel: PanelContainer = null
var _sg_body: VBoxContainer = null
var _sg_title: Label = null
var _sg_base = null
var _sg_force_id: String = ""
var _sg_building: Node = null

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
	$Panel.mouse_filter = Control.MOUSE_FILTER_STOP
	$Panel/map_btn.pressed.connect(_on_map_btn_pressed)
	$Panel/economy_btn.pressed.connect(_on_economy_btn_pressed)
	$Panel/war_btn.pressed.connect(_on_war_btn_pressed)
	$Panel/settings_btn.pressed.connect(_on_settings_btn_pressed)
	msg_btn.pressed.connect(_on_msg_btn_pressed)
	_populate_gameplay_settings()
	show_province_names_chk.toggled.connect(_on_show_province_names_toggled)
	_ensure_province_levy_widgets()
	if caravan_tab_send_btn != null:
		caravan_tab_send_btn.pressed.connect(_on_caravan_tab_send_pressed)
	if economy_tabs != null and caravan_tab_root != null:
		var cv_idx := caravan_tab_root.get_index()
		economy_tabs.set_tab_title(cv_idx, "Caravan")
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
	if map_menu.visible:
		_refresh_minimap()


func _refresh_minimap() -> void:
	# Defer so the Map tab has a real size after the menu shows.
	_refresh_minimap_deferred.call_deferred()


func _refresh_minimap_deferred() -> void:
	if minimap == null or not is_instance_valid(parent_n):
		return
	if map_tabs != null:
		map_tabs.current_tab = 0
	if minimap.has_method("rebuild"):
		minimap.rebuild(parent_n)


func _on_economy_btn_pressed() -> void:
	var opening = not economy_menu.visible
	_toggle_menu(economy_menu)
	if opening and economy_menu.visible:
		_open_economy_on_province()


func is_economy_menu_open() -> bool:
	return economy_menu != null and economy_menu.visible


func _open_economy_on_province() -> void:
	if not is_instance_valid(parent_n):
		return
	var pid := ""
	if parent_n.has_method("resolve_economy_province_focus"):
		pid = parent_n.resolve_economy_province_focus()
	selected_province_id = pid
	economy_tabs.current_tab = 2
	if parent_n.has_method("set_province_focus") and pid != "":
		parent_n.set_province_focus(pid, false)
	update_economy_menu(parent_n)


func on_province_focused(province_id: String) -> void:
	selected_province_id = province_id
	if not is_economy_menu_open():
		return
	economy_tabs.current_tab = 2
	if is_instance_valid(parent_n):
		_fill_province_tab(parent_n, province_id)


## Screen-space hit test for open menus / popups (Area2D click-through guard).
func blocks_map_at_mouse() -> bool:
	var pos := get_viewport().get_mouse_position()
	for child in get_children():
		if not (child is Control):
			continue
		var c := child as Control
		if not c.visible or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if c.get_global_rect().has_point(pos):
			return true
	return false


## True when a menu/popup overlay is open (not the always-on top/bottom chrome).
func blocks_camera_pan() -> bool:
	for child in get_children():
		if not (child is Control):
			continue
		if child.name == "Panel" or child.name == "top_panel":
			continue
		if (child as Control).visible:
			return true
	return false



func _on_war_btn_pressed() -> void:
	_toggle_menu(war_menu)
	if war_menu.visible:
		refresh_military_tab()
		refresh_alliances_list()
		refresh_vip_trade_ui()


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


func _ensure_field_popup() -> void:
	if _field_popup != null:
		return
	_field_popup = PanelContainer.new()
	_field_popup.top_level = true
	_field_popup.z_index = 130
	_field_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_field_popup.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	_field_popup_title = Label.new()
	_field_popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_popup_title.add_theme_font_size_override("font_size", 16)
	_field_popup_title.text = "Field"
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide_field_popup)
	header.add_child(_field_popup_title)
	header.add_child(close_btn)
	_field_popup_body = Label.new()
	_field_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_field_popup_btns = HBoxContainer.new()
	_field_popup_btns.add_theme_constant_override("separation", 6)
	for crop_i in [0, 1, 2]:
		var btn := Button.new()
		match crop_i:
			0: btn.text = "Idle"
			1: btn.text = "Grain"
			2: btn.text = "Horses"
		btn.pressed.connect(_on_field_crop_pressed.bind(crop_i))
		_field_popup_btns.add_child(btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_field_popup_body)
	vbox.add_child(_field_popup_btns)
	margin.add_child(vbox)
	_field_popup.add_child(margin)
	add_child(_field_popup)


func show_field_popup(base_map: Node, field: Node) -> void:
	_ensure_field_popup()
	hide_building_popup()
	_field_popup_base = base_map
	_field_popup_field = field
	_rebuild_field_popup()
	_field_popup.visible = true
	_field_popup.reset_size()
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(14, 0)
	var vp := get_viewport().get_visible_rect().size
	var sz := _field_popup.size
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - sz.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - sz.y))
	_field_popup.position = pos


func hide_field_popup() -> void:
	if _field_popup != null:
		_field_popup.visible = false
	_field_popup_field = null
	_field_popup_base = null


func refresh_field_popup_if(base_map: Node, field: Node) -> void:
	if _field_popup == null or not _field_popup.visible:
		return
	if _field_popup_field != field:
		return
	_field_popup_base = base_map
	_rebuild_field_popup()


func _rebuild_field_popup() -> void:
	if _field_popup_base == null or _field_popup_field == null:
		return
	var body := ""
	if _field_popup_base.has_method("_building_display_body"):
		body = _field_popup_base._building_display_body(_field_popup_field)
	_field_popup_body.text = body
	var can_edit := false
	if _field_popup_field.has_method("get_controller_id"):
		can_edit = int(_field_popup_field.get_controller_id()) == int(_field_popup_base.my_pl_id)
	_field_popup_btns.visible = can_edit
	for i in _field_popup_btns.get_child_count():
		var btn: Button = _field_popup_btns.get_child(i)
		btn.disabled = not can_edit


func _on_field_crop_pressed(crop: int) -> void:
	if _field_popup_base == null or _field_popup_field == null:
		return
	if _field_popup_base.has_method("do_set_field_crop"):
		_field_popup_base.do_set_field_crop(_field_popup_field, crop)


func _ensure_populate_idle_popup() -> void:
	if _populate_idle_popup != null:
		return
	_populate_idle_popup = PanelContainer.new()
	_populate_idle_popup.top_level = true
	_populate_idle_popup.z_index = 130
	_populate_idle_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_populate_idle_popup.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.text = "Populate idle fields"
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide_populate_idle_popup)
	header.add_child(title)
	header.add_child(close_btn)
	_populate_idle_body = Label.new()
	_populate_idle_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	var grain_btn := Button.new()
	grain_btn.text = "Make grain fields"
	grain_btn.pressed.connect(_on_populate_idle_crop_pressed.bind(1))
	var horse_btn := Button.new()
	horse_btn.text = "Make horse pastures"
	horse_btn.pressed.connect(_on_populate_idle_crop_pressed.bind(2))
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(hide_populate_idle_popup)
	btns.add_child(grain_btn)
	btns.add_child(horse_btn)
	btns.add_child(cancel_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_populate_idle_body)
	vbox.add_child(btns)
	margin.add_child(vbox)
	_populate_idle_popup.add_child(margin)
	add_child(_populate_idle_popup)


func show_populate_idle_popup() -> void:
	_ensure_populate_idle_popup()
	_populate_idle_body.text = "Convert %d idle fields" % _prov_idle_field_count
	_populate_idle_popup.visible = true
	_populate_idle_popup.reset_size()
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(14, 0)
	var vp := get_viewport().get_visible_rect().size
	var sz := _populate_idle_popup.size
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - sz.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - sz.y))
	_populate_idle_popup.position = pos


func hide_populate_idle_popup() -> void:
	if _populate_idle_popup != null:
		_populate_idle_popup.visible = false


func _on_populate_idle_fields_pressed() -> void:
	if _prov_idle_field_count <= 0:
		return
	show_populate_idle_popup()


func _on_populate_idle_crop_pressed(crop: int) -> void:
	hide_populate_idle_popup()
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	if parent_n.has_method("do_populate_idle_fields"):
		parent_n.do_populate_idle_fields(selected_province_id, crop)


func _ensure_economy_building_popup() -> void:
	if _econ_popup != null:
		return
	_econ_popup = PanelContainer.new()
	_econ_popup.top_level = true
	_econ_popup.z_index = 130
	_econ_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_econ_popup.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	_econ_popup_title = Label.new()
	_econ_popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_econ_popup_title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide_economy_building_popup)
	header.add_child(_econ_popup_title)
	header.add_child(close_btn)
	_econ_popup_body = Label.new()
	_econ_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_econ_popup_btns = VBoxContainer.new()
	_econ_popup_btns.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_econ_popup_body)
	vbox.add_child(_econ_popup_btns)
	margin.add_child(vbox)
	_econ_popup.add_child(margin)
	add_child(_econ_popup)


func show_economy_building_popup(base_map: Node, building: Node) -> void:
	_ensure_economy_building_popup()
	hide_building_popup()
	hide_field_popup()
	_econ_popup_base = base_map
	_econ_popup_building = building
	_rebuild_economy_building_popup()
	_econ_popup.visible = true
	_econ_popup.reset_size()
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(14, 0)
	var vp := get_viewport().get_visible_rect().size
	var sz := _econ_popup.size
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - sz.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - sz.y))
	_econ_popup.position = pos


func hide_economy_building_popup() -> void:
	if _econ_popup != null:
		_econ_popup.visible = false
	_econ_popup_building = null
	_econ_popup_base = null


func refresh_economy_building_popup_if(base_map: Node, building: Node) -> void:
	if _econ_popup == null or not _econ_popup.visible:
		return
	if _econ_popup_building != building:
		return
	_econ_popup_base = base_map
	_rebuild_economy_building_popup()


func _rebuild_economy_building_popup() -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	var b := _econ_popup_building
	_econ_popup_title.text = _econ_popup_base._building_display_name(b) if _econ_popup_base.has_method("_building_display_name") else "Economy"
	_econ_popup_body.text = _econ_popup_base._building_display_body(b) if _econ_popup_base.has_method("_building_display_body") else ""
	for c in _econ_popup_btns.get_children():
		_econ_popup_btns.remove_child(c)
		c.queue_free()
	var pid := int(_econ_popup_base.my_pl_id)
	var prov = _econ_popup_base.find_province_for_building(b) if _econ_popup_base.has_method("find_province_for_building") else null
	var is_dejure = prov != null and prov.has_method("has_dejure") and prov.has_dejure(pid)
	var marks := 0
	if _econ_popup_base.players.has(pid):
		marks = int(_econ_popup_base.players[pid].game_data.get("marks", 0))
	if b.has_method("is_built") and b.is_built():
		var owns_building := int(b.get("player_owner")) == pid
		if b.has_method("is_blacksmith") and b.is_blacksmith() and is_dejure and owns_building:
			var recipe_lbl := Label.new()
			recipe_lbl.text = "Craft recipe:"
			_econ_popup_btns.add_child(recipe_lbl)
			var current := str(b.get_craft_weapon()) if b.has_method("get_craft_weapon") else ""
			var idle_btn := Button.new()
			idle_btn.text = "Idle"
			idle_btn.disabled = current == ""
			idle_btn.pressed.connect(_on_econ_recipe_pressed.bind(""))
			_econ_popup_btns.add_child(idle_btn)
			for wkey in GlobalUnits.BLACKSMITH_CRAFTABLE:
				var rbtn := Button.new()
				rbtn.text = GlobalUnits.blacksmith_recipe_label(str(wkey))
				rbtn.disabled = current == str(wkey)
				rbtn.pressed.connect(_on_econ_recipe_pressed.bind(str(wkey)))
				_econ_popup_btns.add_child(rbtn)
		if is_dejure:
			var dem := Button.new()
			dem.text = "Demolish"
			dem.pressed.connect(_on_econ_demolish_pressed)
			_econ_popup_btns.add_child(dem)
	else:
		if is_dejure and b.has_method("allowed_build_subtypes"):
			for sub in b.allowed_build_subtypes():
				var cost := int(b.build_cost_for(sub))
				var btn := Button.new()
				var name_ := str(b.subtype_display_name(int(sub))) if b.has_method("subtype_display_name") else "Build"
				btn.text = "%s (%d marks)" % [name_, cost]
				btn.disabled = marks < cost
				btn.pressed.connect(_on_econ_build_pressed.bind(int(sub)))
				_econ_popup_btns.add_child(btn)
		elif not is_dejure:
			var hint := Label.new()
			hint.text = "Only de jure can build here"
			_econ_popup_btns.add_child(hint)


func _on_econ_build_pressed(subtype: int) -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	if _econ_popup_base.has_method("do_build_economy"):
		_econ_popup_base.do_build_economy(_econ_popup_building, subtype)


func _on_econ_demolish_pressed() -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	if _econ_popup_base.has_method("do_demolish_economy"):
		_econ_popup_base.do_demolish_economy(_econ_popup_building)


func _on_econ_recipe_pressed(weapon_key: String) -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	if _econ_popup_base.has_method("do_set_blacksmith_recipe"):
		_econ_popup_base.do_set_blacksmith_recipe(_econ_popup_building, weapon_key)


# --- Close everything (called on player switch / end-turn) ------------------

func close_all_popups() -> void:
	hide_building_popup()
	hide_field_popup()
	hide_economy_building_popup()
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
	close_caravan_menus()
	_close_merchant_shop()
	_close_merchant_raid_menu()
	_close_field_raid_menu()
	_close_sellswords_hire()
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

	# Army loot / cargo stock (weapons + materials)
	var cargo: Dictionary = _am_base.get_force_cargo(_am_army.force_id) if _am_base.has_method("get_force_cargo") else {}
	_am_body.add_child(HSeparator.new())
	if _am_base.has_method("force_food_status_text"):
		var food_lbl := Label.new()
		food_lbl.text = _am_base.force_food_status_text(str(_am_army.force_id))
		food_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		food_lbl.custom_minimum_size = Vector2(280, 0)
		_am_body.add_child(food_lbl)
	if _am_base.has_method("force_siege_status_text"):
		var siege_txt := str(_am_base.force_siege_status_text(str(_am_army.force_id)))
		if siege_txt != "":
			var siege_lbl := Label.new()
			siege_lbl.text = siege_txt
			siege_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			siege_lbl.custom_minimum_size = Vector2(280, 0)
			_am_body.add_child(siege_lbl)
	var loot_hdr := Label.new()
	loot_hdr.text = "Loot: %s" % GlobalUnits.caravan_cargo_summary(cargo)
	loot_hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loot_hdr.custom_minimum_size = Vector2(280, 0)
	_am_body.add_child(loot_hdr)
	var loot_row := HBoxContainer.new()
	var deposit_btn := Button.new()
	deposit_btn.text = "Deposit"
	deposit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var prov_under = _am_base.province_under_force(_am_army.force_id) if _am_base.has_method("province_under_force") else null
	deposit_btn.disabled = prov_under == null or not GlobalUnits.caravan_cargo_has_any(cargo)
	deposit_btn.pressed.connect(_on_am_deposit_loot)
	loot_row.add_child(deposit_btn)
	var withdraw_btn := Button.new()
	withdraw_btn.text = "Withdraw"
	withdraw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var can_withdraw = prov_under != null and prov_under.has_method("has_dejure") and prov_under.has_dejure(_am_base.my_pl_id)
	withdraw_btn.disabled = not can_withdraw
	withdraw_btn.pressed.connect(_on_am_withdraw_loot)
	loot_row.add_child(withdraw_btn)
	_am_body.add_child(loot_row)
	var send_loot_btn := Button.new()
	send_loot_btn.text = "Send loot home"
	send_loot_btn.disabled = not GlobalUnits.caravan_cargo_has_any(cargo)
	if _am_base.has_method("list_dejure_province_ids"):
		send_loot_btn.disabled = send_loot_btn.disabled or _am_base.list_dejure_province_ids(_am_base.my_pl_id).is_empty()
	send_loot_btn.pressed.connect(_on_am_send_loot)
	_am_body.add_child(send_loot_btn)

	# VIP slot
	if _am_base.has_method("get_vips_on_force"):
		var vip_ids: Array = _am_base.get_vips_on_force(_am_army.force_id)
		if not vip_ids.is_empty():
			_am_body.add_child(HSeparator.new())
			var vip_hdr := Label.new()
			vip_hdr.text = "VIP"
			_am_body.add_child(vip_hdr)
			var ctrl = _am_army.get_controller()
			for vid in vip_ids:
				var v: Dictionary = _am_base.get_vip(str(vid))
				if v.is_empty():
					continue
				var row := HBoxContainer.new()
				var lbl := Label.new()
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl.text = _am_base.vip_display_name(str(vid))
				var bonus := GlobalVips.role_bonus(int(v.get("role", 0)))
				if int(v.get("owner", -1)) == ctrl:
					lbl.text += "  (+%.0f%%)" % (bonus * 100.0)
				row.add_child(lbl)
				var owner_id := int(v.get("owner", -1))
				if ctrl == _am_base.my_pl_id and owner_id != _am_base.my_pl_id:
					var sword_btn := Button.new()
					sword_btn.text = "Sword"
					sword_btn.pressed.connect(_on_am_put_vip_to_sword.bind(str(vid)))
					row.add_child(sword_btn)
				_am_body.add_child(row)

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


func _on_am_put_vip_to_sword(vip_id: String) -> void:
	if _am_base == null or _am_army == null:
		return
	_am_base.do_put_vip_to_sword(_am_army.force_id, vip_id)


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


func _on_am_deposit_loot() -> void:
	if _am_base == null or _am_army == null:
		return
	var base = _am_base
	var fid = _am_army.force_id
	_close_army_menu()
	_open_force_cargo_panel(base, fid, "deposit")


func _on_am_withdraw_loot() -> void:
	if _am_base == null or _am_army == null:
		return
	var base = _am_base
	var fid = _am_army.force_id
	_close_army_menu()
	_open_force_cargo_panel(base, fid, "withdraw")


func _on_am_send_loot() -> void:
	if _am_base == null or _am_army == null:
		return
	var base = _am_base
	var fid = _am_army.force_id
	_close_army_menu()
	_open_force_cargo_panel(base, fid, "send")


# --- Force cargo panel (deposit / withdraw / send) --------------------------

func _ensure_force_cargo_panel() -> void:
	if _fc_panel != null:
		return
	_fc_panel = PanelContainer.new()
	_fc_panel.top_level = true
	_fc_panel.z_index = 145
	_fc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fc_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var hbox := HBoxContainer.new()
	_fc_title = Label.new()
	_fc_title.text = "Loot"
	_fc_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_fc_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_force_cargo_panel)
	hbox.add_child(close_btn)
	vbox.add_child(hbox)
	_fc_info_lbl = Label.new()
	_fc_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fc_info_lbl.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(_fc_info_lbl)
	_fc_dest_row = HBoxContainer.new()
	var dest_lbl := Label.new()
	dest_lbl.text = "Destination:"
	_fc_dest_row.add_child(dest_lbl)
	_fc_dest = OptionButton.new()
	_fc_dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fc_dest_row.add_child(_fc_dest)
	vbox.add_child(_fc_dest_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fc_body = VBoxContainer.new()
	_fc_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fc_body)
	vbox.add_child(scroll)
	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_force_cargo_panel)
	btn_row.add_child(cancel_btn)
	var all_btn := Button.new()
	all_btn.text = "ALL"
	all_btn.pressed.connect(_on_fc_all_pressed)
	btn_row.add_child(all_btn)
	_fc_confirm_btn = Button.new()
	_fc_confirm_btn.text = "Confirm"
	_fc_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fc_confirm_btn.pressed.connect(_on_fc_confirm_pressed)
	btn_row.add_child(_fc_confirm_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_fc_panel.add_child(margin)
	add_child(_fc_panel)


func _open_force_cargo_panel(base_map, force_id: String, mode: String, after_disband_army: Node2D = null) -> void:
	_ensure_force_cargo_panel()
	_fc_base = base_map
	_fc_force_id = force_id
	_fc_mode = mode
	_fc_after_disband_army = after_disband_army
	match mode:
		"deposit":
			_fc_title.text = "Deposit loot"
			_fc_info_lbl.text = "Deposit into the province under this force."
			_fc_confirm_btn.text = "Deposit"
		"withdraw":
			_fc_title.text = "Withdraw loot"
			_fc_info_lbl.text = "Pull weapons and materials from this de jure province into the army."
			_fc_confirm_btn.text = "Withdraw"
		"send", "disband_send":
			_fc_title.text = "Send loot home"
			_fc_info_lbl.text = "Create a caravan from this force to a de jure province."
			_fc_confirm_btn.text = "Send caravan" if mode == "send" else "Send & disband"
		_:
			_fc_title.text = "Loot"
			_fc_confirm_btn.text = "Confirm"
	_fc_dest_row.visible = mode == "send" or mode == "disband_send"
	_fc_dest.clear()
	_fc_dest_ids.clear()
	if _fc_dest_row.visible:
		var from_cell: Vector2i = base_map.get_force_anchor_cell(force_id) if base_map.has_method("get_force_anchor_cell") else Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
		var closest := ""
		if base_map.has_method("find_closest_dejure_province_id"):
			closest = str(base_map.find_closest_dejure_province_id(base_map.my_pl_id, from_cell))
		var prefer_idx := 0
		for pid in base_map.list_dejure_province_ids(base_map.my_pl_id):
			var pdata: Dictionary = base_map.get_province_data(str(pid))
			_fc_dest.add_item(str(pdata.get("name", pid)))
			if str(pid) == closest:
				prefer_idx = _fc_dest_ids.size()
			_fc_dest_ids.append(str(pid))
		if _fc_dest_ids.is_empty():
			_close_force_cargo_panel()
			show_info_popup("No de jure provinces to send loot to")
			return
		_fc_dest.select(prefer_idx)
	for c in _fc_body.get_children():
		c.queue_free()
	_fc_spinboxes.clear()
	var available := GlobalUnits.empty_caravan_cargo()
	if mode == "withdraw":
		var prov = base_map.province_under_force(force_id)
		if prov != null:
			if prov.has_method("get_weapons_for"):
				available = GlobalUnits.add_caravan_stocks(available, prov.get_weapons_for(base_map.my_pl_id))
			for mk in GlobalUnits.MATERIAL_KEYS:
				available[mk] = int(prov.get_player_material(base_map.my_pl_id, mk)) if prov.has_method("get_player_material") else 0
	else:
		available = base_map.get_force_cargo(force_id)
	for k in GlobalUnits.WEAPON_KEYS:
		var have := int(available.get(k, 0))
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s (have %d)" % [GlobalUnits.weapon_name(k), have]
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(0, have)
		spin.step = 1
		spin.value = 0
		spin.custom_minimum_size = Vector2(90, 0)
		row.add_child(spin)
		row.add_child(_make_spin_all_button(spin))
		_fc_body.add_child(row)
		_fc_spinboxes[k] = spin
	_fc_body.add_child(HSeparator.new())
	for k in GlobalUnits.MATERIAL_KEYS:
		var have_m := int(available.get(k, 0))
		var row_m := HBoxContainer.new()
		var lbl_m := Label.new()
		lbl_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_m.text = "%s (have %d)" % [GlobalUnits.material_name(k), have_m]
		row_m.add_child(lbl_m)
		var spin_m := SpinBox.new()
		spin_m.min_value = 0
		spin_m.max_value = maxi(0, have_m)
		spin_m.step = 1
		spin_m.value = 0
		spin_m.custom_minimum_size = Vector2(90, 0)
		row_m.add_child(spin_m)
		row_m.add_child(_make_spin_all_button(spin_m))
		_fc_body.add_child(row_m)
		_fc_spinboxes[k] = spin_m
	_fc_panel.visible = true
	_fc_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_fc_panel.size = Vector2(minf(400, vp.x * 0.9), minf(480, vp.y * 0.85))
	_fc_panel.position = (vp - _fc_panel.size) * 0.5


func _on_fc_all_pressed() -> void:
	for k in _fc_spinboxes:
		var spin: SpinBox = _fc_spinboxes[k]
		spin.value = spin.max_value


func _fc_collect_cargo() -> Dictionary:
	var cargo := GlobalUnits.empty_caravan_cargo()
	for k in _fc_spinboxes:
		cargo[k] = int(_fc_spinboxes[k].value)
	return cargo


func _close_force_cargo_panel() -> void:
	if _fc_panel != null:
		_fc_panel.visible = false
	_fc_base = null
	_fc_force_id = ""
	_fc_mode = ""
	_fc_spinboxes.clear()
	_fc_dest_ids.clear()
	_fc_after_disband_army = null


func _on_fc_confirm_pressed() -> void:
	var base = _fc_base
	var force_id := _fc_force_id
	var mode := _fc_mode
	var cargo := _fc_collect_cargo()
	var dest_id := ""
	var dest_idx := _fc_dest.selected if _fc_dest != null else -1
	if dest_idx >= 0 and dest_idx < _fc_dest_ids.size():
		dest_id = str(_fc_dest_ids[dest_idx])
	var disband_army := _fc_after_disband_army
	_close_force_cargo_panel()
	if base == null or force_id == "":
		return
	if not GlobalUnits.caravan_cargo_has_any(cargo):
		show_info_popup("Select at least one item")
		return
	match mode:
		"deposit":
			base.do_force_deposit_cargo(force_id, cargo)
		"withdraw":
			base.do_force_withdraw_cargo(force_id, cargo)
		"send":
			if dest_id == "":
				show_info_popup("Pick a destination province")
				return
			base.do_force_send_caravan(force_id, dest_id, cargo)
		"disband_send":
			if dest_id == "":
				show_info_popup("Pick a destination province")
				return
			base.do_force_send_caravan(force_id, dest_id, cargo)
			if disband_army != null:
				base.request_disband_force.rpc_id(1, disband_army.force_id)


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
	_db_loot_send_btn = Button.new()
	_db_loot_send_btn.text = "Send loot & disband"
	_db_loot_send_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_db_loot_send_btn.pressed.connect(_on_disband_send_loot_pressed)
	btn_row.add_child(_db_loot_send_btn)
	_db_discard_btn = Button.new()
	_db_discard_btn.text = "Discard loot & disband"
	_db_discard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_db_discard_btn.pressed.connect(_on_disband_confirm_pressed)
	btn_row.add_child(_db_discard_btn)
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

	var cargo: Dictionary = base_map.get_force_cargo(army.force_id) if base_map.has_method("get_force_cargo") else {}
	var has_loot := GlobalUnits.caravan_cargo_has_any(cargo)
	var has_dests := false
	if has_loot and base_map.has_method("list_dejure_province_ids"):
		has_dests = not base_map.list_dejure_province_ids(my_id).is_empty()
	if has_loot:
		lines.append("Carried loot: %s" % GlobalUnits.caravan_cargo_summary(cargo))
		if has_dests:
			lines.append("Send loot home as a caravan, or discard it.")
		else:
			lines.append("No de jure provinces — loot will be discarded.")
	_db_loot_send_btn.visible = has_loot and has_dests
	_db_discard_btn.visible = has_loot
	_db_confirm_btn.visible = not has_loot

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


func _on_disband_send_loot_pressed() -> void:
	var base = _db_base
	var army := _db_army
	_close_disband_panel()
	if base == null or army == null:
		return
	_open_force_cargo_panel(base, army.force_id, "disband_send", army)


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
	_fm_left_vip_checks.clear()
	_fm_right_vip_checks.clear()
	_fm_left_loot_spinboxes.clear()
	_fm_right_loot_spinboxes.clear()
	_fm_split_loot_spinboxes.clear()


func refresh_force_menu_if_open() -> void:
	if _fm_panel != null and _fm_panel.visible:
		_rebuild_force_menu()


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

	if _fm_base.has_method("force_food_status_text"):
		var food_left := Label.new()
		food_left.text = _fm_base.force_food_status_text(_fm_left_id)
		food_left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		food_left.custom_minimum_size = Vector2(480, 0)
		_fm_body.add_child(food_left)
		var right_fid := _fm_right_force_id()
		if right_fid != "" and _fm_base.forces.has(right_fid):
			var food_right := Label.new()
			food_right.text = _fm_base.force_food_status_text(right_fid)
			food_right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			food_right.custom_minimum_size = Vector2(480, 0)
			_fm_body.add_child(food_right)
		_fm_body.add_child(HSeparator.new())

	if _fm_split_mode:
		_fm_split_spinboxes.clear()
		_fm_split_loot_spinboxes.clear()
		if _fm_withdraw_mode:
			_fm_title.text = "Withdraw your troops from %s" % left_name
		else:
			_fm_title.text = "Split: %s" % left_name
		_fm_body.add_child(_build_split_column())
		_fm_body.add_child(HSeparator.new())
		_fm_body.add_child(_build_loot_transfer_block(true, true))
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
		_fm_left_loot_spinboxes.clear()
		_fm_right_loot_spinboxes.clear()
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
		var loot_cols := HBoxContainer.new()
		loot_cols.add_theme_constant_override("separation", 20)
		loot_cols.add_child(_build_loot_transfer_block(true, false))
		loot_cols.add_child(VSeparator.new())
		loot_cols.add_child(_build_loot_transfer_block(false, false))
		_fm_body.add_child(loot_cols)
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
		else:
			# Manage garrison stock without needing a second army.
			var gfid := _fm_right_force_id()
			if gfid != "" and _fm_base.forces.has(gfid):
				var g_manage := HBoxContainer.new()
				var dep := Button.new()
				dep.text = "Deposit garrison loot"
				dep.pressed.connect(_on_fm_manage_garrison_loot.bind("deposit"))
				g_manage.add_child(dep)
				var wit := Button.new()
				wit.text = "Withdraw to garrison"
				wit.pressed.connect(_on_fm_manage_garrison_loot.bind("withdraw"))
				g_manage.add_child(wit)
				var snd := Button.new()
				snd.text = "Send garrison loot"
				snd.pressed.connect(_on_fm_manage_garrison_loot.bind("send"))
				g_manage.add_child(snd)
				_fm_body.add_child(g_manage)

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


## Loot transfer sliders. `split_mode`: amounts move with the split-off army (default 0).
func _build_loot_transfer_block(is_left: bool, split_mode: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(240, 0)
	var fid := _fm_left_id
	if not split_mode and not is_left:
		fid = _fm_right_force_id()
	var cargo: Dictionary = GlobalUnits.empty_caravan_cargo()
	if _fm_base != null and _fm_base.has_method("get_force_cargo") and fid != "":
		cargo = _fm_base.get_force_cargo(fid)
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 13)
	if split_mode:
		head.text = "Loot to move with split (default none):"
	elif is_left:
		head.text = "Loot → right (default none):"
	else:
		head.text = "Loot → left (default none):"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(220, 0)
	col.add_child(head)
	if not GlobalUnits.caravan_cargo_has_any(cargo):
		var empty := Label.new()
		empty.text = "(no loot)"
		col.add_child(empty)
		return col
	var target: Dictionary = _fm_split_loot_spinboxes if split_mode else (
		_fm_left_loot_spinboxes if is_left else _fm_right_loot_spinboxes
	)
	for k in GlobalUnits.WEAPON_KEYS:
		var have := int(cargo.get(k, 0))
		if have <= 0:
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s (%d)" % [GlobalUnits.weapon_name(k), have]
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = have
		spin.step = 1
		spin.value = 0
		spin.custom_minimum_size = Vector2(80, 0)
		row.add_child(spin)
		row.add_child(_make_spin_all_button(spin))
		col.add_child(row)
		target[k] = spin
	for k in GlobalUnits.MATERIAL_KEYS:
		var have_m := int(cargo.get(k, 0))
		if have_m <= 0:
			continue
		var row_m := HBoxContainer.new()
		var lbl_m := Label.new()
		lbl_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_m.text = "%s (%d)" % [GlobalUnits.material_name(k), have_m]
		row_m.add_child(lbl_m)
		var spin_m := SpinBox.new()
		spin_m.min_value = 0
		spin_m.max_value = have_m
		spin_m.step = 1
		spin_m.value = 0
		spin_m.custom_minimum_size = Vector2(80, 0)
		row_m.add_child(spin_m)
		row_m.add_child(_make_spin_all_button(spin_m))
		col.add_child(row_m)
		target[k] = spin_m
	return col


func _fm_collect_loot(spinboxes: Dictionary) -> Dictionary:
	var cargo := GlobalUnits.empty_caravan_cargo()
	for k in spinboxes:
		cargo[k] = int(spinboxes[k].value)
	return cargo


func _on_fm_manage_garrison_loot(mode: String) -> void:
	if _fm_base == null:
		return
	var gfid := _fm_right_force_id()
	if gfid == "" or not _fm_base.forces.has(gfid):
		return
	var base = _fm_base
	_close_force_menu()
	_open_force_cargo_panel(base, gfid, mode)


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


func _fm_collect_checked_vips(checks: Dictionary) -> Array:
	var out: Array = []
	for vid in checks:
		var cb: CheckBox = checks[vid]
		if cb != null and cb.button_pressed:
			out.append(str(vid))
	return out


func _fm_right_force_id() -> String:
	if _fm_right_is_garrison:
		if _fm_base == null or _fm_building == null:
			return ""
		# VIP special slot: town FLAT / castle INSIDE (or current spot for men).
		return _fm_base.garrison_force_id_for(_fm_building, _fm_spot)
	return _fm_right_id


func _fm_building_accepts_vip() -> bool:
	if not _fm_right_is_garrison or _fm_building == null:
		return true
	var type_ = _fm_building.get("type_")
	if type_ == null:
		return false
	return type_ == GlobalStuff.BUILDING_TYPE.TOWN or type_ == GlobalStuff.BUILDING_TYPE.CASTLE


func _on_fm_transfer_confirm() -> void:
	if _fm_base == null or not _fm_base.forces.has(_fm_left_id):
		return

	var left_to_right := _collect_out_units(_fm_left_spinboxes)
	var right_to_left := _collect_out_units(_fm_right_spinboxes)
	var cargo_l2r := _fm_collect_loot(_fm_left_loot_spinboxes)
	var cargo_r2l := _fm_collect_loot(_fm_right_loot_spinboxes)
	var vips_l2r := _fm_collect_checked_vips(_fm_left_vip_checks)
	var vips_r2l := _fm_collect_checked_vips(_fm_right_vip_checks)
	var any_loot := GlobalUnits.caravan_cargo_has_any(cargo_l2r) or GlobalUnits.caravan_cargo_has_any(cargo_r2l)
	if left_to_right.is_empty() and right_to_left.is_empty() and vips_l2r.is_empty() and vips_r2l.is_empty() and not any_loot:
		show_info_popup("Select at least one unit, VIP, or loot to transfer")
		return

	if (not vips_l2r.is_empty() or not vips_r2l.is_empty()) and _fm_right_is_garrison and not _fm_building_accepts_vip():
		show_info_popup("VIPs can only be deposited in towns and castles")
		return

	var base = _fm_base
	var left_id := _fm_left_id
	var right_id := _fm_right_force_id()

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
		var left_keeps_vip = base.get_vips_on_force(left_id).size() - vips_l2r.size() + vips_r2l.size()
		if left_keeps_vip > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Army with a VIP needs at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
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
		var bldg = _fm_building
		_close_force_menu()
		if not left_to_right.is_empty() or not right_to_left.is_empty() or any_loot:
			base.request_batch_garrison_units.rpc_id(
				1, left_id, building_key, _fm_spot, left_to_right, right_to_left, cargo_l2r, cargo_r2l
			)
		if not vips_l2r.is_empty():
			var vip_dest = base.garrison_force_id_for(bldg, base.vip_garrison_spot_for(bldg))
			base.do_transfer_vips(left_id, vip_dest, vips_l2r)
		if not vips_r2l.is_empty():
			for vid in vips_r2l:
				var v: Dictionary = base.get_vip(str(vid))
				if v.is_empty():
					continue
				var src_fid := str(v.get("force_id", ""))
				if src_fid != "":
					base.do_transfer_vips(src_fid, left_id, [str(vid)])
	else:
		if not base.forces.has(_fm_right_id):
			return
		right_id = _fm_right_id
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
		var left_keeps = base.get_vips_on_force(left_id).size() - vips_l2r.size() + vips_r2l.size()
		var right_keeps = base.get_vips_on_force(right_id).size() - vips_r2l.size() + vips_l2r.size()
		if left_keeps > 0 and left_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Army with a VIP needs at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return
		if right_keeps > 0 and right_men < GlobalUnits.MIN_SPLIT_MEN:
			show_info_popup("Army with a VIP needs at least %d men" % GlobalUnits.MIN_SPLIT_MEN)
			return

		_close_force_menu()
		if not left_to_right.is_empty() or not right_to_left.is_empty() or any_loot:
			base.request_batch_transfer_units.rpc_id(
				1, left_id, right_id, left_to_right, right_to_left, cargo_l2r, cargo_r2l
			)
		if not vips_l2r.is_empty():
			base.do_transfer_vips(left_id, right_id, vips_l2r)
		if not vips_r2l.is_empty():
			base.do_transfer_vips(right_id, left_id, vips_r2l)


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
	var cargo_out := _fm_collect_loot(_fm_split_loot_spinboxes)
	var fig = base.armies.get_node_or_null(source_id)
	if fig == null:
		return
	var army_cell: Vector2i = base.pathfinding.get_army_cell(fig)
	var free_cell = base.pathfinding.get_free_adjacent_cell(army_cell)
	if free_cell == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		show_info_popup("No free adjacent tile to place split army")
		return
	_close_force_menu()
	base.request_split_force.rpc_id(
		1, source_id, out_units, free_cell.x, free_cell.y, withdraw, withdraw_player, cargo_out
	)


func _build_force_column(is_left: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(240, 0)
	var units := _fm_left_units() if is_left else _fm_right_units()

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 14)
	var loot_fid := _fm_left_id if is_left else (_fm_right_force_id() if _fm_right_is_garrison else _fm_right_id)
	var loot_txt := ""
	if _fm_base != null and _fm_base.has_method("get_force_cargo") and loot_fid != "":
		var fcargo: Dictionary = _fm_base.get_force_cargo(loot_fid)
		if GlobalUnits.caravan_cargo_has_any(fcargo):
			loot_txt = "\nLoot: %s" % GlobalUnits.caravan_cargo_summary(fcargo)
	if is_left:
		head.text = "%s\n%d men · str %d%s" % [
			_fm_force_label(_fm_left_id, false),
			GlobalUnits.total_men(units),
			GlobalUnits.total_strength(units),
			loot_txt,
		]
	else:
		var cap_txt := ""
		if _fm_right_is_garrison:
			var cap: int = _fm_building.get_garrison_capacity(_fm_spot)
			var mult := GlobalUnits.CASTLE_INSIDE_BONUS if _fm_spot == GlobalUnits.SPOT.INSIDE else 1.0
			cap_txt = "%d/%d men · str %d" % [GlobalUnits.total_men(units), cap, GlobalUnits.total_strength(units, mult)]
		else:
			cap_txt = "%d men · str %d" % [GlobalUnits.total_men(units), GlobalUnits.total_strength(units)]
		head.text = "%s\n%s%s" % [
			"Garrison" if _fm_right_is_garrison else _fm_force_label(_fm_right_id, false),
			cap_txt,
			loot_txt,
		]
	col.add_child(head)
	col.add_child(HSeparator.new())

	if units.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		col.add_child(empty)
	else:
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

	# VIP checkboxes (special slot; not capacity).
	var vip_ids: Array = []
	if _fm_base.has_method("get_vips_on_force"):
		if is_left:
			vip_ids = _fm_base.get_vips_on_force(_fm_left_id)
		elif _fm_right_is_garrison and _fm_building_accepts_vip():
			vip_ids = _fm_base.get_building_vip_ids(_fm_building)
		elif not _fm_right_is_garrison:
			vip_ids = _fm_base.get_vips_on_force(_fm_right_id)
	if not vip_ids.is_empty() and (is_left or not _fm_right_is_garrison or _fm_building_accepts_vip()):
		col.add_child(HSeparator.new())
		var vip_lbl := Label.new()
		vip_lbl.text = "VIP (check to move)"
		col.add_child(vip_lbl)
		for vid in vip_ids:
			var row := HBoxContainer.new()
			var cb := CheckBox.new()
			cb.text = _fm_base.vip_display_name(str(vid))
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if is_left:
				_fm_left_vip_checks[str(vid)] = cb
			else:
				_fm_right_vip_checks[str(vid)] = cb
			row.add_child(cb)
			var v: Dictionary = _fm_base.get_vip(str(vid))
			var owner_id := int(v.get("owner", -1))
			var holder := int(_fm_base.holder_of_vip(str(vid)))
			if holder == _fm_base.my_pl_id and owner_id != _fm_base.my_pl_id:
				var sword_btn := Button.new()
				sword_btn.text = "Sword"
				var src_fid := str(v.get("force_id", ""))
				sword_btn.pressed.connect(_on_fm_put_vip_to_sword.bind(src_fid, str(vid)))
				row.add_child(sword_btn)
			col.add_child(row)
	return col


func _on_fm_put_vip_to_sword(force_id: String, vip_id: String) -> void:
	if _fm_base == null:
		return
	_fm_base.do_put_vip_to_sword(force_id, vip_id)
	_rebuild_force_menu()


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


func refresh_military_tab_if_open() -> void:
	if war_menu != null and war_menu.visible:
		refresh_military_tab()


func refresh_military_tab() -> void:
	if military_list == null:
		return
	var base_map = parent_n
	if not is_instance_valid(base_map) or not base_map.has_method("get_player_upkeep_preview"):
		return
	var my_id: int = int(base_map.my_pl_id)
	var preview: Dictionary = base_map.get_player_upkeep_preview(my_id)
	var total := int(preview.get("total", 0))
	var levy := int(preview.get("levy", 0))
	var sellsword := int(preview.get("sellsword", 0))
	if military_upkeep_lbl != null:
		military_upkeep_lbl.text = (
			"Projected upkeep: %d marks  (levies %d · sellswords %d)"
			% [total, levy, sellsword]
		)
	var strikes := int(preview.get("strikes", 0))
	var streak := int(preview.get("pay_streak", 0))
	if military_strikes_lbl != null:
		if strikes <= 0:
			military_strikes_lbl.text = "Pay status: clear"
		else:
			var next := ""
			match strikes:
				1:
					next = "Next miss: sellswords disband."
				2:
					next = "Next miss: levies desert 10% per stack."
				_:
					next = "Levies desert each unpaid season; sellswords leave on miss."
			var clear_txt := ""
			if streak > 0:
				clear_txt = " Paid %d/%d seasons toward clearing strikes." % [
					streak, GlobalUnits.UPKEEP_CLEAR_PAYS
				]
			else:
				clear_txt = " Pay in full %d seasons in a row to clear strikes." % GlobalUnits.UPKEEP_CLEAR_PAYS
			military_strikes_lbl.text = "Strikes: %d/%d. %s%s" % [
				strikes, GlobalUnits.UPKEEP_STRIKES_MAX, next, clear_txt
			]

	for child in military_list.get_children():
		military_list.remove_child(child)
		child.queue_free()

	var rows: Array = preview.get("forces", [])
	if rows.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No forces"
		military_list.add_child(empty_lbl)
		return

	for entry in rows:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_btn := Button.new()
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.text = "%s (%d men)" % [str(entry.get("name", "?")), int(entry.get("men", 0))]
		var fid := str(entry.get("force_id", ""))
		name_btn.pressed.connect(_on_military_force_pressed.bind(fid))
		var cost_lbl := Label.new()
		cost_lbl.text = "%d marks" % int(entry.get("total", 0))
		cost_lbl.custom_minimum_size = Vector2(72, 0)
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_btn)
		row.add_child(cost_lbl)
		col.add_child(row)
		var food_lbl := Label.new()
		food_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if bool(entry.get("in_dejure", false)):
			food_lbl.text = "  Food: de jure supply · %d grain held" % int(entry.get("grain", 0))
		else:
			var seasons := int(entry.get("food_seasons", -1))
			var tag := ""
			if bool(entry.get("starving", false)):
				tag = " · STARVING"
			elif bool(entry.get("food_warning", false)):
				tag = " · warning"
			food_lbl.text = "  Food: %d grain · need %d/season · %s season(s)%s" % [
				int(entry.get("grain", 0)),
				int(entry.get("grain_need", 0)),
				str(seasons) if seasons >= 0 else "—",
				tag,
			]
		col.add_child(food_lbl)
		military_list.add_child(col)


func _on_military_force_pressed(force_id: String) -> void:
	if not is_instance_valid(parent_n) or not parent_n.has_method("jump_camera_to_force"):
		return
	parent_n.jump_camera_to_force(force_id)


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


# --- VIP trade (War → Diplomacy tab) ----------------------------------------

func refresh_vip_trade_ui() -> void:
	if diplomacy_list == null:
		return
	for child in diplomacy_list.get_children():
		diplomacy_list.remove_child(child)
		child.queue_free()
	var base = parent_n
	if not is_instance_valid(base) or not base.has_method("get_pending_vip_trades_for"):
		return

	var title := Label.new()
	title.text = "VIP Trade"
	title.add_theme_font_size_override("font_size", 16)
	diplomacy_list.add_child(title)

	var hint := Label.new()
	hint.text = "Offer VIPs you hold and/or marks. Request marks in return. Offers last until the receiver ends their turn."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(360, 0)
	diplomacy_list.add_child(hint)

	var others: Array = base.get_playing_players_except(base.my_pl_id) if base.has_method("get_playing_players_except") else []
	for pid in others:
		var row := HBoxContainer.new()
		var pname = base.player_display_name(int(pid))
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = pname
		var btn := Button.new()
		btn.text = "Propose trade"
		btn.pressed.connect(_open_vip_trade_composer.bind(int(pid)))
		row.add_child(lbl)
		row.add_child(btn)
		diplomacy_list.add_child(row)

	diplomacy_list.add_child(HSeparator.new())
	var pend_lbl := Label.new()
	pend_lbl.text = "Pending offers"
	diplomacy_list.add_child(pend_lbl)

	var trades: Array = base.get_pending_vip_trades_for(base.my_pl_id)
	if trades.is_empty():
		var empty := Label.new()
		empty.text = "(none)"
		diplomacy_list.add_child(empty)
	else:
		for t in trades:
			var from_pid := int(t.get("from", -1))
			var to_pid := int(t.get("to", -1))
			var tid := str(t.get("id", ""))
			var line := Label.new()
			var vip_txt := ""
			for vid in t.get("offer_vip_ids", []):
				if vip_txt != "":
					vip_txt += ", "
				vip_txt += base.vip_display_name(str(vid))
			if vip_txt == "":
				vip_txt = "(no VIP)"
			line.text = "%s → %s: offer %s + %d marks, request %d marks" % [
				base.player_display_name(from_pid),
				base.player_display_name(to_pid),
				vip_txt,
				int(t.get("offer_marks", 0)),
				int(t.get("request_marks", 0)),
			]
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(360, 0)
			diplomacy_list.add_child(line)
			if to_pid == base.my_pl_id:
				var brow := HBoxContainer.new()
				var accept := Button.new()
				accept.text = "Accept"
				var still_holds := true
				for vid in t.get("offer_vip_ids", []):
					if not base.player_holds_vip(from_pid, str(vid)):
						still_holds = false
						break
				if not still_holds:
					accept.disabled = true
					accept.text = "Player no longer possesses the VIP"
				else:
					accept.pressed.connect(_on_vip_trade_respond.bind(tid, true))
				var reject := Button.new()
				reject.text = "Reject"
				reject.pressed.connect(_on_vip_trade_respond.bind(tid, false))
				brow.add_child(accept)
				brow.add_child(reject)
				diplomacy_list.add_child(brow)


func _open_vip_trade_composer(to_pid: int) -> void:
	_ensure_vip_trade_panel()
	_vt_base = parent_n
	_vt_to_pid = to_pid
	_rebuild_vip_trade_composer()
	_vt_panel.visible = true


func _ensure_vip_trade_panel() -> void:
	if _vt_panel != null:
		return
	_vt_panel = PanelContainer.new()
	_vt_panel.top_level = true
	_vt_panel.z_index = 150
	_vt_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_vt_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Propose VIP trade"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func(): _vt_panel.visible = false)
	header.add_child(title)
	header.add_child(close_btn)
	_vt_body = VBoxContainer.new()
	vbox.add_child(header)
	vbox.add_child(_vt_body)
	margin.add_child(vbox)
	_vt_panel.add_child(margin)
	add_child(_vt_panel)


func _rebuild_vip_trade_composer() -> void:
	if _vt_body == null or _vt_base == null:
		return
	for c in _vt_body.get_children():
		_vt_body.remove_child(c)
		c.queue_free()
	_vt_offer_vip_checks.clear()

	var to_name = _vt_base.player_display_name(_vt_to_pid)
	var hdr := Label.new()
	hdr.text = "Trade with %s" % to_name
	_vt_body.add_child(hdr)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)

	var offer_col := VBoxContainer.new()
	offer_col.custom_minimum_size = Vector2(220, 0)
	var offer_h := Label.new()
	offer_h.text = "Your offer"
	offer_col.add_child(offer_h)
	var held: Array = []
	for vid in _vt_base.vips:
		if _vt_base.player_holds_vip(_vt_base.my_pl_id, str(vid)):
			held.append(str(vid))
	if held.is_empty():
		var none := Label.new()
		none.text = "(no VIPs held)"
		offer_col.add_child(none)
	else:
		for vid in held:
			var cb := CheckBox.new()
			cb.text = _vt_base.vip_display_name(vid)
			_vt_offer_vip_checks[vid] = cb
			offer_col.add_child(cb)
	var om_row := HBoxContainer.new()
	var om_lbl := Label.new()
	om_lbl.text = "Marks:"
	_vt_offer_marks_spin = SpinBox.new()
	_vt_offer_marks_spin.min_value = 0
	_vt_offer_marks_spin.max_value = int(_vt_base.players[_vt_base.my_pl_id].game_data.get("marks", 0))
	_vt_offer_marks_spin.step = 10
	om_row.add_child(om_lbl)
	om_row.add_child(_vt_offer_marks_spin)
	offer_col.add_child(om_row)

	var req_col := VBoxContainer.new()
	req_col.custom_minimum_size = Vector2(220, 0)
	var req_h := Label.new()
	req_h.text = "Your request"
	req_col.add_child(req_h)
	var rm_row := HBoxContainer.new()
	var rm_lbl := Label.new()
	rm_lbl.text = "Marks:"
	_vt_request_marks_spin = SpinBox.new()
	_vt_request_marks_spin.min_value = 0
	_vt_request_marks_spin.max_value = 999999
	_vt_request_marks_spin.step = 10
	rm_row.add_child(rm_lbl)
	rm_row.add_child(_vt_request_marks_spin)
	req_col.add_child(rm_row)
	var req_note := Label.new()
	req_note.text = "(VIPs can only be offered, not requested)"
	req_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	req_note.custom_minimum_size = Vector2(200, 0)
	req_col.add_child(req_note)

	cols.add_child(offer_col)
	cols.add_child(VSeparator.new())
	cols.add_child(req_col)
	_vt_body.add_child(cols)

	var send := Button.new()
	send.text = "Send proposal"
	send.pressed.connect(_on_vip_trade_send)
	_vt_body.add_child(send)

	_vt_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_vt_panel.size = _vt_panel.get_combined_minimum_size()
	_vt_panel.position = (vp - _vt_panel.size) * 0.5


func _on_vip_trade_send() -> void:
	if _vt_base == null:
		return
	var offer_vips: Array = []
	for vid in _vt_offer_vip_checks:
		if _vt_offer_vip_checks[vid].button_pressed:
			offer_vips.append(vid)
	var offer_marks := int(_vt_offer_marks_spin.value) if _vt_offer_marks_spin != null else 0
	var request_marks := int(_vt_request_marks_spin.value) if _vt_request_marks_spin != null else 0
	if offer_vips.is_empty() and offer_marks <= 0:
		show_info_popup("Offer at least a VIP or marks")
		return
	_vt_base.do_propose_vip_trade(_vt_to_pid, offer_vips, offer_marks, request_marks)
	_vt_panel.visible = false
	refresh_vip_trade_ui()


func _on_vip_trade_respond(trade_id: String, accept: bool) -> void:
	if not is_instance_valid(parent_n):
		return
	parent_n.do_respond_vip_trade(trade_id, accept)
	refresh_vip_trade_ui()


func on_vip_trade_proposed(base_map, _trade_id: String) -> void:
	if war_menu != null and war_menu.visible:
		refresh_vip_trade_ui()
	if is_instance_valid(base_map) and has_method("refresh_msg_button"):
		refresh_msg_button()
	if is_instance_valid(base_map) and has_method("refresh_msg_list_if_open"):
		refresh_msg_list_if_open()


func on_vip_trade_resolved(_base_map, _trade_id: String, _accepted: bool, _reason: String) -> void:
	if war_menu != null and war_menu.visible:
		refresh_vip_trade_ui()
	if is_instance_valid(parent_n) and parent_n.has_method("update_visuals_and_stats"):
		parent_n.update_visuals_and_stats()


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
	var holdings_sep := false
	var other_sep := false
	for entry in list_data:
		if entry.get("holding", false) and not holdings_sep:
			holdings_sep = true
			var sep = HSeparator.new()
			provinces_list_container.add_child(sep)
			var lbl = Label.new()
			lbl.text = "Occupied holdings"
			lbl.add_theme_font_size_override("font_size", 12)
			provinces_list_container.add_child(lbl)
		elif not entry.get("owned", true) and not entry.get("holding", false) and not other_sep:
			other_sep = true
			var sep2 = HSeparator.new()
			provinces_list_container.add_child(sep2)
			var lbl2 = Label.new()
			lbl2.text = "De jure / De facto only"
			lbl2.add_theme_font_size_override("font_size", 12)
			provinces_list_container.add_child(lbl2)
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
	elif base_map.has_method("resolve_economy_province_focus"):
		selected_province_id = base_map.resolve_economy_province_focus()
		if selected_province_id != "":
			_fill_province_tab(base_map, selected_province_id)
	_fill_caravan_tab(base_map)


func _on_province_list_clicked(province_id: String) -> void:
	selected_province_id = province_id
	economy_tabs.current_tab = 2
	if is_instance_valid(parent_n) and parent_n.has_method("set_province_focus"):
		parent_n.set_province_focus(province_id, true)
	if is_instance_valid(parent_n) and parent_n.has_method("get_province_data"):
		_fill_province_tab(parent_n, province_id)


func _make_prov_section_label(initial: String) -> Label:
	var lbl := Label.new()
	lbl.text = initial
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	return lbl


func _ensure_province_levy_widgets() -> void:
	if _prov_happiness_lbl != null or province_tab_root == null:
		return
	province_tab_root.mouse_filter = Control.MOUSE_FILTER_STOP
	province_tab_root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_prov_manage_root = VBoxContainer.new()
	_prov_manage_root.add_theme_constant_override("separation", 6)
	_prov_manage_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_manage_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prov_manage_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	province_tab_root.add_child(_prov_manage_root)
	_prov_manage_root.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prov_manage_root.add_child(columns)

	# Left: holding status + levy.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_STOP
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	var fields_row := HBoxContainer.new()
	fields_row.add_theme_constant_override("separation", 8)
	fields_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_fields_lbl = _make_prov_section_label("Fields: —")
	_prov_fields_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_row.add_child(_prov_fields_lbl)
	_prov_populate_idle_btn = Button.new()
	_prov_populate_idle_btn.text = "Populate idle fields"
	_prov_populate_idle_btn.disabled = true
	_prov_populate_idle_btn.pressed.connect(_on_populate_idle_fields_pressed)
	fields_row.add_child(_prov_populate_idle_btn)
	left.add_child(fields_row)
	_prov_stock_lbl = _make_prov_section_label("Stock: —")
	left.add_child(_prov_stock_lbl)
	left.add_child(HSeparator.new())
	_prov_agri_lbl = _make_prov_section_label("Agriculture: —")
	left.add_child(_prov_agri_lbl)
	_prov_prod_lbl = _make_prov_section_label("Next season production: —")
	left.add_child(_prov_prod_lbl)
	_prov_smith_lbl = _make_prov_section_label("Blacksmith: —")
	left.add_child(_prov_smith_lbl)
	left.add_child(HSeparator.new())
	_prov_happiness_lbl = Label.new()
	_prov_happiness_lbl.text = "Happiness: —"
	_prov_happiness_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_happiness_lbl)
	_prov_levy_lbl = Label.new()
	_prov_levy_lbl.text = "Levy: —"
	_prov_levy_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_levy_lbl)
	_prov_weapons_lbl = Label.new()
	_prov_weapons_lbl.text = "Weapons: —"
	_prov_weapons_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_weapons_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_weapons_lbl)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_recruit_btn = Button.new()
	_prov_recruit_btn.text = "Recruit army"
	_prov_recruit_btn.pressed.connect(_on_province_recruit_pressed)
	actions.add_child(_prov_recruit_btn)
	left.add_child(actions)

	# Right: labor pool + sliders.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.35
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_prov_labor_lbl = _make_prov_section_label("Labor pool: —")
	right.add_child(_prov_labor_lbl)
	var labor_scroll := ScrollContainer.new()
	labor_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	labor_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	labor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(labor_scroll)
	_prov_labor_box = VBoxContainer.new()
	_prov_labor_box.add_theme_constant_override("separation", 6)
	_prov_labor_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_labor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labor_scroll.add_child(_prov_labor_box)


func _blacksmith_status_text(preview: Dictionary, holding: Dictionary) -> String:
	if not bool(holding.get("has_blacksmith", false)):
		return "Blacksmith: (none in this holding)"
	var smith: Dictionary = preview.get("blacksmith", {})
	var workers := int(smith.get("workers", 0))
	var cap := int(smith.get("worker_cap", 0))
	var crafts := int(smith.get("crafts", 0))
	var labor_crafts := int(smith.get("labor_crafts", 0))
	var free_slots := int(smith.get("free_slots", 0))
	var people_per := int(smith.get("people_per_weapon", 1))
	var bottleneck := str(smith.get("bottleneck", "ok"))
	var craft_bits: PackedStringArray = []
	var weapons_prev: Dictionary = preview.get("weapons", {})
	for wk in GlobalUnits.BLACKSMITH_CRAFTABLE:
		var amt := int(weapons_prev.get(wk, 0))
		if amt > 0:
			craft_bits.append("%d %s" % [amt, GlobalUnits.weapon_name(str(wk))])
	var craft_txt := (", ".join(craft_bits)) if not craft_bits.is_empty() else "nothing"
	var lines: PackedStringArray = []
	lines.append("Blacksmith: %d / %d workers · next season crafts %s" % [workers, cap, craft_txt])
	match bottleneck:
		"none":
			lines.append("No smith buildings.")
		"no_workers":
			lines.append("Idle — assign workers (labor cost depends on recipe).")
		"idle_recipe":
			lines.append("Workers assigned but no craft recipe set (open the smith).")
		"materials":
			lines.append(
				"Materials limit crafts: labor could make %d, stock allows %d. Add wood/iron."
				% [labor_crafts, crafts]
			)
		"can_expand":
			var more_weapons := int(free_slots / people_per)
			lines.append(
				"Not at full capacity — %d free slots (~%d more weapons if materials allow)."
				% [free_slots, more_weapons]
			)
		"partial_team":
			var need := int(smith.get("people_to_next", people_per))
			lines.append(
				"Almost another weapon — need %d more worker(s) for the next craft."
				% need
			)
		"full":
			lines.append("At full labor capacity — production maxed for current recipes/materials.")
		_:
			if crafts > 0 and free_slots == 0:
				lines.append("At full labor capacity.")
			elif crafts > 0:
				lines.append("%d free worker slots remain." % free_slots)
	return "\n".join(lines)


func _on_prov_labor_category_changed(category: String, value: float) -> void:
	if _prov_labor_updating:
		return
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	if parent_n.has_method("do_set_holding_labor_category"):
		parent_n.do_set_holding_labor_category(selected_province_id, category, int(value))


func _labor_category_label(cat: String) -> String:
	match cat:
		"grain": return "Grain fields"
		"horses": return "Horse pastures"
		"wood": return "Woodcutters"
		"stone": return "Stone quarries"
		"iron": return "Iron mines"
		"silver": return "Silver mines"
		"blacksmith": return "Blacksmiths"
	return cat.capitalize()


func _rebuild_labor_sliders(holding: Dictionary) -> void:
	if _prov_labor_box == null:
		return
	for c in _prov_labor_box.get_children():
		_prov_labor_box.remove_child(c)
		c.queue_free()
	_prov_labor_sliders.clear()
	var pop := int(holding.get("population", 0))
	var labor: Dictionary = holding.get("labor", {})
	var caps: Dictionary = holding.get("labor_caps", {})
	var show_cats: Array = []
	if bool(holding.get("has_grain_work", false)) or int(holding.get("planted_grain", 0)) > 0 \
			or int(holding.get("grain_fields", 0)) > 0:
		show_cats.append("grain")
	if bool(holding.get("has_horse_work", false)):
		show_cats.append("horses")
	if bool(holding.get("has_wood", false)) or int(caps.get("wood", 0)) > 0:
		show_cats.append("wood")
	if bool(holding.get("has_stone", false)) or int(caps.get("stone", 0)) > 0:
		show_cats.append("stone")
	if bool(holding.get("has_iron", false)) or int(caps.get("iron", 0)) > 0:
		show_cats.append("iron")
	if bool(holding.get("has_silver", false)) or int(caps.get("silver", 0)) > 0:
		show_cats.append("silver")
	if bool(holding.get("has_blacksmith", false)) or int(caps.get("blacksmith", 0)) > 0:
		show_cats.append("blacksmith")
	_prov_labor_updating = true
	for cat in show_cats:
		_add_labor_slider_row(str(cat), labor, caps, pop, holding)
	_prov_labor_updating = false


func _labor_slider_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.05, 0.55)
	sb.border_color = Color(0.35, 0.25, 0.14, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	return sb


func _add_labor_slider_row(
	cat: String, labor: Dictionary, caps: Dictionary, pop: int, holding: Dictionary = {}
) -> void:
	var cur := int(labor.get(cat, 0))
	var cap := int(caps.get(cat, 0))
	var others := 0
	for other_cat in GlobalUnits.LABOR_CATEGORIES:
		if str(other_cat) == cat:
			continue
		others += int(labor.get(other_cat, 0))
	var max_v := maxi(0, mini(pop - others, cap))
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _labor_slider_panel_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_STOP
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Show assigned / building-cap; slider max may be lower if people are scarce.
	var base_txt := "%s %d/%d" % [_labor_category_label(cat), cur, cap]
	if max_v <= 0 and cap > 0:
		base_txt += " (no free people)"
	elif max_v < cap and cur >= max_v:
		base_txt += " (people cap %d)" % max_v
	if cat == "blacksmith":
		var preview: Dictionary = holding.get("economy_preview", {})
		var smith: Dictionary = preview.get("blacksmith", {})
		var crafts := int(smith.get("crafts", 0))
		var free_slots := int(smith.get("free_slots", 0))
		var bn := str(smith.get("bottleneck", ""))
		match bn:
			"full":
				base_txt += " · full (%d crafts)" % crafts
			"materials":
				base_txt += " · materials limit (%d crafts)" % crafts
			"can_expand":
				base_txt += " · %d free · %d crafts" % [free_slots, crafts]
			"idle_recipe":
				base_txt += " · set recipe"
			"no_workers":
				base_txt += " · no workers"
			_:
				if cap > 0:
					base_txt += " · %d crafts" % crafts
	lbl.text = base_txt
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = maxi(max_v, 0)
	slider.step = 1
	slider.value = clampi(cur, 0, max_v)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 18
	slider.editable = max_v > 0
	_connect_labor_slider(slider, cat)
	col.add_child(lbl)
	col.add_child(slider)
	panel.add_child(col)
	_prov_labor_box.add_child(panel)
	_prov_labor_sliders[cat] = slider


func _connect_labor_slider(slider: HSlider, cat: String) -> void:
	# Separate function so `cat` is captured per slider (not loop-shared).
	slider.value_changed.connect(func(v: float): _on_prov_labor_category_changed(cat, v))


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
		province_tab_income.text = "Income: —"
		province_tab_villages.text = "Villages: — / —"
		province_tab_towns.text = "Towns: — / —"
		province_tab_castles.text = "Castles: — / —"
		province_tab_economy.text = "Economy: — / —"
		_prov_idle_field_count = 0
		if _prov_manage_root != null:
			_prov_manage_root.visible = false
		hide_populate_idle_popup()
		return
	province_tab_name.text = data.get("name", "—")
	province_tab_status.text = "Status: %s" % data.get("status_name", "—")
	province_tab_owner.text = "Owner: %s" % data.get("owner_name", "—")
	province_tab_defacto.text = "De facto: %s" % data.get("defacto_name", "—")
	province_tab_dejure.text = "De jure: %s" % data.get("dejure_name", "—")
	province_tab_population.text = "Population: %s (next: %s)" % [data.get("population_has", 0), data.get("population_will", 0)]
	if data.get("viewer_has_dejure", false):
		province_tab_income.text = "Income: %s" % data.get("marks_will", 0)
	else:
		province_tab_income.text = "Income: 0 (no de jure)"

	var v = data.get("villages", {"control": 0, "all": 0})
	province_tab_villages.text = "Villages: %d / %d" % [v.get("control", 0), v.get("all", 0)]
	var t = data.get("towns", {"control": 0, "all": 0})
	province_tab_towns.text = "Towns: %d / %d" % [t.get("control", 0), t.get("all", 0)]
	var c = data.get("castles", {"control": 0, "all": 0})
	province_tab_castles.text = "Castles: %d / %d" % [c.get("control", 0), c.get("all", 0)]
	var e = data.get("economy", {"control": 0, "all": 0})
	province_tab_economy.text = "Economy: %d / %d" % [e.get("control", 0), e.get("all", 0)]

	# Only your holdings / de jure provinces expose management UI.
	var has_holding := bool(data.get("viewer_has_holding", false))
	var has_dejure := bool(data.get("viewer_has_dejure", false))
	var can_manage := has_holding or has_dejure
	if _prov_manage_root != null:
		_prov_manage_root.visible = can_manage
	if not can_manage:
		_prov_idle_field_count = 0
		hide_populate_idle_popup()
		return

	var holding: Dictionary = data.get("holding", {})
	if _prov_fields_lbl != null:
		if has_holding and not holding.is_empty():
			var preview: Dictionary = holding.get("economy_preview", {})
			_prov_idle_field_count = int(holding.get("idle_fields", 0))
			var grain_n := int(holding.get("grain_fields", 0))
			var planted_n := int(holding.get("planted_grain", 0))
			var season_i := int(parent_n.season) if is_instance_valid(parent_n) else -1
			var in_winter := season_i == 0
			if in_winter:
				_prov_fields_lbl.text = (
					"Fields: %d grain (%d planned), %d horse, %d idle"
					% [
						grain_n,
						grain_n,
						int(holding.get("horse_fields", 0)),
						_prov_idle_field_count,
					]
				)
			else:
				_prov_fields_lbl.text = (
					"Fields: %d grain (%d sown), %d horse, %d idle"
					% [
						grain_n,
						planted_n,
						int(holding.get("horse_fields", 0)),
						_prov_idle_field_count,
					]
				)
			if _prov_populate_idle_btn != null:
				_prov_populate_idle_btn.visible = true
				_prov_populate_idle_btn.disabled = _prov_idle_field_count <= 0
			_prov_stock_lbl.text = (
				"Stock: grain %d · wood %d · stone %d · iron %d · horses %d · grain pot %.0f"
				% [
					int(holding.get("grain_stock", 0)),
					int(holding.get("wood_stock", 0)),
					int(holding.get("stone_stock", 0)),
					int(holding.get("iron_stock", 0)),
					int(holding.get("horses", 0)),
					float(holding.get("grain_potential", 0.0)),
				]
			)
			var pop := int(holding.get("population", 0))
			var assigned := int(holding.get("labor_assigned", 0))
			_prov_labor_lbl.text = "Labor pool: %d / %d people assigned (sliders below)" % [assigned, pop]
			var cov := float(holding.get("grain_coverage", 1.0)) * 100.0
			var grain_need := int(holding.get("grain_labor_need", 0))
			var horse_need := int(holding.get("horse_labor_need", 0))
			var labor_map: Dictionary = holding.get("labor", {})
			if in_winter:
				var seed_each := int(holding.get("seed_per_field", GlobalUnits.GRAIN_SEED_PER_FIELD))
				var stock := int(holding.get("grain_stock", 0))
				var needed := grain_n * seed_each
				var can_sow := 0
				if seed_each > 0:
					can_sow = mini(grain_n, int(stock / seed_each))
				_prov_agri_lbl.text = (
					"Grain plan: %d fields · seed %d needed / %d stock → %d will sow · horse pastures %d / %d workers"
					% [
						grain_n, needed, stock, can_sow,
						int(labor_map.get("horses", 0)), horse_need,
					]
				)
			else:
				_prov_agri_lbl.text = (
					"Agriculture: grain coverage %.0f%% (%d / %d workers) · horse pastures %d / %d workers"
					% [
						cov,
						int(labor_map.get("grain", 0)), grain_need,
						int(labor_map.get("horses", 0)), horse_need,
					]
				)
			_prov_prod_lbl.text = (
				"Next season production: wood %+d · stone %+d · iron %+d · marks %+d"
				% [
					int(preview.get("wood", 0)),
					int(preview.get("stone", 0)),
					int(preview.get("iron", 0)),
					int(preview.get("marks", 0)),
				]
			)
			_prov_smith_lbl.text = _blacksmith_status_text(preview, holding)
			_rebuild_labor_sliders(holding)
		else:
			_prov_idle_field_count = 0
			_prov_fields_lbl.text = "Fields: (no settlement holding here)"
			if _prov_populate_idle_btn != null:
				_prov_populate_idle_btn.visible = false
				_prov_populate_idle_btn.disabled = true
			_prov_stock_lbl.text = "Stock: —"
			_prov_labor_lbl.text = "Labor pool: —"
			_prov_agri_lbl.text = "Agriculture: —"
			_prov_prod_lbl.text = "Next season production: —"
			_prov_smith_lbl.text = "Blacksmith: —"
			_rebuild_labor_sliders({})
			hide_populate_idle_popup()

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

	_prov_recruit_btn.visible = has_dejure


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
	_close_siege_prompt()
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
	var siege_lvl := -1
	if _bt_building != null:
		def_str = _bt_base.get_building_battle_strength(_bt_building, _bt_attacker_id)
		def_men = GlobalUnits.fighting_men(_bt_base.get_all_building_garrison(_bt_building))
		def_name = _bt_base._building_display_name(_bt_building) if _bt_base.has_method("_building_display_name") else "Building"
		_bt_title.text = "Assault"
		if _bt_building.get("type_") != null and _bt_building.type_ == GlobalStuff.BUILDING_TYPE.CASTLE \
				and _bt_base.has_method("get_force_siege_level_vs"):
			siege_lvl = int(_bt_base.get_force_siege_level_vs(_bt_attacker_id, _bt_building))
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

	if siege_lvl >= 0:
		var siege_lbl := Label.new()
		var bonus := GlobalUnits.siege_inside_bonus(siege_lvl)
		siege_lbl.text = "Siege engines: %d/%d (castle inside ×%.1f)" % [
			siege_lvl, GlobalUnits.SIEGE_MAX_LEVEL, bonus
		]
		siege_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		siege_lbl.custom_minimum_size = Vector2(360, 0)
		siege_lbl.add_theme_font_size_override("font_size", 12)
		_bt_body.add_child(siege_lbl)

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


# --- Siege prompt (first castle assault) ------------------------------------

func _ensure_siege_prompt() -> void:
	if _sg_panel != null:
		return
	_sg_panel = PanelContainer.new()
	_sg_panel.top_level = true
	_sg_panel.z_index = 145
	_sg_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_sg_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_sg_title = Label.new()
	_sg_title.text = "Siege"
	_sg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_sg_title)
	vbox.add_child(HSeparator.new())
	_sg_body = VBoxContainer.new()
	_sg_body.add_theme_constant_override("separation", 6)
	vbox.add_child(_sg_body)
	margin.add_child(vbox)
	_sg_panel.add_child(margin)
	add_child(_sg_panel)


func open_siege_prompt(base_map, force_id: String, building: Node) -> void:
	_close_battle_menu()
	_ensure_siege_prompt()
	_sg_base = base_map
	_sg_force_id = force_id
	_sg_building = building
	_rebuild_siege_prompt()


func _close_siege_prompt() -> void:
	if _sg_panel != null:
		_sg_panel.visible = false
	_sg_base = null
	_sg_force_id = ""
	_sg_building = null


func _rebuild_siege_prompt() -> void:
	if _sg_base == null or not _sg_base.forces.has(_sg_force_id) \
			or _sg_building == null or not is_instance_valid(_sg_building):
		_close_siege_prompt()
		return
	for c in _sg_body.get_children():
		_sg_body.remove_child(c)
		c.queue_free()

	var bname := "Castle"
	if _sg_base.has_method("_building_display_name") and _sg_building is Node2D:
		bname = _sg_base._building_display_name(_sg_building)
	_sg_title.text = "Assault %s" % bname

	var info := Label.new()
	info.text = (
		"Build siege engines while camped here. Engines improve each season "
		+ "(up to %d), lowering the defenders' castle bonus.\n\n"
		+ "Assault now with no engines — the garrison fights at ×%.1f inside."
	) % [GlobalUnits.SIEGE_MAX_LEVEL, GlobalUnits.siege_inside_bonus(0)]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(360, 0)
	_sg_body.add_child(info)
	_sg_body.add_child(HSeparator.new())

	var build_btn := Button.new()
	build_btn.text = "Start building siege engines"
	build_btn.pressed.connect(_on_sg_start_building)
	_sg_body.add_child(build_btn)

	var assault_btn := Button.new()
	assault_btn.text = "Assault now"
	assault_btn.pressed.connect(_on_sg_assault_now)
	_sg_body.add_child(assault_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_close_siege_prompt)
	_sg_body.add_child(cancel_btn)

	_sg_panel.visible = true
	_sg_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_sg_panel.size = Vector2(minf(420, vp.x * 0.9), _sg_panel.get_combined_minimum_size().y)
	_sg_panel.position = (vp - _sg_panel.size) * 0.5


func _on_sg_start_building() -> void:
	if _sg_base == null or _sg_building == null:
		return
	var base = _sg_base
	var fid := _sg_force_id
	var building = _sg_building
	_close_siege_prompt()
	if base.has_method("do_start_siege"):
		base.do_start_siege(fid, building)


func _on_sg_assault_now() -> void:
	if _sg_base == null or _sg_building == null:
		return
	var base = _sg_base
	var fid := _sg_force_id
	var building = _sg_building
	_close_siege_prompt()
	open_battle_menu(base, fid, "", building)


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
	var raid_mp := int(base_map.RAID_MP_COST) if base_map.get("RAID_MP_COST") != null else 2
	var capt_mp := int(base_map.CAPTURE_MP_COST) if base_map.get("CAPTURE_MP_COST") != null else 2
	var raze_mp := int(base_map.RAZE_MP_COST) if base_map.get("RAZE_MP_COST") != null else 4
	var has_raid_mp = base_map.force_has_movement(force_id, raid_mp) if base_map.has_method("force_has_movement") else true
	var has_capt_mp = base_map.force_has_movement(force_id, capt_mp) if base_map.has_method("force_has_movement") else true
	var has_raze_mp = base_map.force_has_movement(force_id, raze_mp) if base_map.has_method("force_has_movement") else true

	var loot = base_map.compute_raid_loot(building)
	var can_raid = base_map.can_raid_building(building)
	var is_razed = base_map.is_building_razed(building) if base_map.has_method("is_building_razed") else false

	var capt_btn := Button.new()
	capt_btn.text = "Capture (%d MP)" % capt_mp
	capt_btn.disabled = not has_capt_mp
	if not has_capt_mp:
		capt_btn.text = "Capture (need %d MP)" % capt_mp
	capt_btn.pressed.connect(_on_ba_capture)
	_ba_body.add_child(capt_btn)

	var raid_btn := Button.new()
	raid_btn.text = "Raid (%d marks, %d MP)" % [loot, raid_mp]
	raid_btn.disabled = not can_raid or loot <= 0 or not has_raid_mp
	if is_razed:
		raid_btn.text = "Raid (razed)"
		raid_btn.disabled = true
	elif not can_raid:
		raid_btn.text = "Raid (already raided this season)"
	elif not has_raid_mp:
		raid_btn.text = "Raid (need %d MP)" % raid_mp
	raid_btn.pressed.connect(_on_ba_raid)
	_ba_body.add_child(raid_btn)

	if not is_castle:
		var raze_btn := Button.new()
		raze_btn.text = "Raze (%d MP)" % raze_mp
		if is_razed or (base_map.has_method("can_raze_building") and not base_map.can_raze_building(building)):
			raze_btn.disabled = true
			raze_btn.text = "Raze (already razed)" if is_razed else "Raze"
		elif not has_raze_mp:
			raze_btn.disabled = true
			raze_btn.text = "Raze (need %d MP)" % raze_mp
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


# --- Province recruit -------------------------------------------------------

func _on_province_recruit_pressed() -> void:
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	open_recruit_menu(parent_n, selected_province_id)


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


# --- Caravans (Economy tab + map menus) -------------------------------------

func _fill_caravan_tab(base_map: Node) -> void:
	if caravan_tab_list == null:
		return
	for child in caravan_tab_list.get_children():
		child.queue_free()
	if not base_map.has_method("list_caravans_for_player"):
		return
	var mine: Array = base_map.list_caravans_for_player(base_map.my_pl_id)
	if mine.is_empty():
		var empty := Label.new()
		empty.text = "No caravans on the road."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caravan_tab_list.add_child(empty)
		return
	for c in mine:
		var dest_id := str(c.dest_province_id)
		var dest_name := dest_id
		var dest_data: Dictionary = base_map.get_province_data(dest_id)
		if not dest_data.is_empty():
			dest_name = str(dest_data.get("name", dest_id))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text = "→ %s\n%s" % [dest_name, GlobalUnits.caravan_cargo_summary(c.cargo)]
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Open"
		btn.pressed.connect(_on_caravan_list_open.bind(c))
		row.add_child(btn)
		row.add_child(HSeparator.new())
		caravan_tab_list.add_child(row)


func _on_caravan_list_open(caravan: Node2D) -> void:
	if not is_instance_valid(caravan) or not is_instance_valid(parent_n):
		return
	open_caravan_menu(parent_n, caravan)


func _on_caravan_tab_send_pressed() -> void:
	if not is_instance_valid(parent_n):
		return
	open_send_caravan_menu(parent_n, selected_province_id)


func close_caravan_menus() -> void:
	_close_send_caravan_menu()
	_close_caravan_menu()
	_close_caravan_capture_menu()


func _ensure_send_caravan_panel() -> void:
	if _cv_send_panel != null:
		return
	_cv_send_panel = PanelContainer.new()
	_cv_send_panel.top_level = true
	_cv_send_panel.z_index = 140
	_cv_send_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_cv_send_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Send caravan"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_send_caravan_menu)
	header.add_child(close_btn)
	vbox.add_child(header)
	_cv_send_info_lbl = Label.new()
	_cv_send_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cv_send_info_lbl.custom_minimum_size = Vector2(340, 0)
	vbox.add_child(_cv_send_info_lbl)
	var from_row := HBoxContainer.new()
	var from_lbl := Label.new()
	from_lbl.text = "From:"
	from_row.add_child(from_lbl)
	_cv_send_from = OptionButton.new()
	_cv_send_from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cv_send_from.item_selected.connect(_on_send_caravan_from_changed)
	from_row.add_child(_cv_send_from)
	vbox.add_child(from_row)
	var dest_row := HBoxContainer.new()
	var dest_lbl := Label.new()
	dest_lbl.text = "To:"
	dest_row.add_child(dest_lbl)
	_cv_send_dest = OptionButton.new()
	_cv_send_dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest_row.add_child(_cv_send_dest)
	vbox.add_child(dest_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cv_send_body = VBoxContainer.new()
	_cv_send_body.add_theme_constant_override("separation", 4)
	_cv_send_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cv_send_body)
	vbox.add_child(scroll)
	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_send_caravan_menu)
	btn_row.add_child(cancel_btn)
	_cv_send_confirm = Button.new()
	_cv_send_confirm.text = "Send caravan"
	_cv_send_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cv_send_confirm.pressed.connect(_on_send_caravan_confirm)
	btn_row.add_child(_cv_send_confirm)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_cv_send_panel.add_child(margin)
	add_child(_cv_send_panel)


func open_send_caravan_menu(base_map: Node, prefer_from_id: String = "") -> void:
	_ensure_send_caravan_panel()
	_cv_send_base = base_map
	_cv_send_from.clear()
	_cv_send_from_ids.clear()
	var list_data: Array = base_map.get_all_provinces_list_data(base_map.my_pl_id)
	var prefer_idx := 0
	for entry in list_data:
		var pid := str(entry.get("id", ""))
		var data: Dictionary = base_map.get_province_data(pid)
		if not data.get("viewer_has_dejure", false):
			continue
		_cv_send_from.add_item(str(data.get("name", pid)))
		if pid == prefer_from_id:
			prefer_idx = _cv_send_from_ids.size()
		_cv_send_from_ids.append(pid)
	if _cv_send_from_ids.is_empty():
		_cv_send_base = null
		show_info_popup("You need de jure ownership in a province to send a caravan")
		return
	_cv_send_from.select(prefer_idx)
	_rebuild_send_caravan_dest_and_cargo()
	_cv_send_panel.visible = true
	_cv_send_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_cv_send_panel.size = Vector2(minf(440, vp.x * 0.9), minf(520, vp.y * 0.85))
	_cv_send_panel.position = (vp - _cv_send_panel.size) * 0.5


func _on_send_caravan_from_changed(_idx: int) -> void:
	_rebuild_send_caravan_dest_and_cargo()


func _rebuild_send_caravan_dest_and_cargo() -> void:
	var base = _cv_send_base
	if base == null or _cv_send_from == null:
		return
	var from_idx := _cv_send_from.selected
	if from_idx < 0 or from_idx >= _cv_send_from_ids.size():
		return
	var from_id := str(_cv_send_from_ids[from_idx])
	var data: Dictionary = base.get_province_data(from_id)
	var blocked := ""
	if base.has_method("get_caravan_spawn_blocked_reason"):
		blocked = str(base.get_caravan_spawn_blocked_reason(from_id))
	if blocked != "":
		_cv_send_info_lbl.text = "From %s.\nCannot send: %s" % [data.get("name", from_id), blocked]
	else:
		_cv_send_info_lbl.text = (
			"From %s. Cargo is taken now; the caravan walks each season to the destination town. "
			+ "Whoever holds that town receives the goods."
		) % data.get("name", from_id)
	if _cv_send_confirm != null:
		_cv_send_confirm.disabled = blocked != ""
		_cv_send_confirm.tooltip_text = blocked

	_cv_send_dest.clear()
	_cv_send_dest_ids.clear()
	for prov in base.provinces.get_children():
		var pid := str(prov.name)
		if pid == from_id:
			continue
		var pdata: Dictionary = base.get_province_data(pid)
		if pdata.is_empty():
			continue
		_cv_send_dest.add_item(str(pdata.get("name", pid)))
		_cv_send_dest_ids.append(pid)

	for child in _cv_send_body.get_children():
		child.queue_free()
	_cv_send_spinboxes.clear()
	var weapons: Dictionary = data.get("weapons", {})
	var prov = base.provinces.get_node_or_null(from_id) if base.get("provinces") != null else null
	var pid := int(base.my_pl_id)
	var stock_keys: Array = []
	for k in GlobalUnits.WEAPON_KEYS:
		stock_keys.append(k)
	for k in GlobalUnits.MATERIAL_KEYS:
		stock_keys.append(k)
	for k in stock_keys:
		var have := 0
		var label_name := ""
		if k in GlobalUnits.WEAPON_KEYS:
			have = int(weapons.get(k, 0))
			label_name = GlobalUnits.weapon_name(k)
		else:
			if prov != null and prov.has_method("get_player_material"):
				have = int(prov.get_player_material(pid, k))
			label_name = GlobalUnits.material_name(k)
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s (have %d)" % [label_name, have]
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(0, have)
		spin.step = 1
		spin.value = 0
		spin.custom_minimum_size = Vector2(90, 0)
		row.add_child(spin)
		_cv_send_body.add_child(row)
		_cv_send_spinboxes[k] = spin


func _close_send_caravan_menu() -> void:
	if _cv_send_panel != null:
		_cv_send_panel.visible = false
	_cv_send_base = null
	_cv_send_spinboxes.clear()
	_cv_send_from_ids.clear()
	_cv_send_dest_ids.clear()


func _on_send_caravan_confirm() -> void:
	var base = _cv_send_base
	var from_idx := _cv_send_from.selected if _cv_send_from != null else -1
	var dest_idx := _cv_send_dest.selected if _cv_send_dest != null else -1
	var from_id := ""
	var to_id := ""
	if from_idx >= 0 and from_idx < _cv_send_from_ids.size():
		from_id = str(_cv_send_from_ids[from_idx])
	if dest_idx >= 0 and dest_idx < _cv_send_dest_ids.size():
		to_id = str(_cv_send_dest_ids[dest_idx])
	var cargo := GlobalUnits.empty_caravan_cargo()
	var any := false
	for k in _cv_send_spinboxes:
		var amt := int(_cv_send_spinboxes[k].value)
		cargo[k] = amt
		if amt > 0:
			any = true
	_close_send_caravan_menu()
	if base == null or from_id == "" or to_id == "":
		show_info_popup("Pick source and destination provinces")
		return
	if not any:
		show_info_popup("Select goods to send")
		return
	base.do_send_caravan(from_id, to_id, cargo)


func _ensure_caravan_menu() -> void:
	if _cv_panel != null:
		return
	_cv_panel = PanelContainer.new()
	_cv_panel.top_level = true
	_cv_panel.z_index = 130
	_cv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_cv_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.name = "Title"
	title.text = "Caravan"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_caravan_menu)
	header.add_child(title)
	header.add_child(close_btn)
	_cv_body = VBoxContainer.new()
	_cv_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_cv_body)
	margin.add_child(vbox)
	_cv_panel.add_child(margin)
	add_child(_cv_panel)


func open_caravan_menu(base_map: Node, caravan: Node2D) -> void:
	_ensure_caravan_menu()
	_cv_base = base_map
	_cv_caravan = caravan
	_rebuild_caravan_menu()


func refresh_caravan_menu_if(base_map: Node, caravan: Node2D) -> void:
	if _cv_panel == null or not _cv_panel.visible:
		return
	if _cv_caravan != caravan:
		return
	_cv_base = base_map
	_rebuild_caravan_menu()


func _close_caravan_menu() -> void:
	if _cv_panel != null:
		_cv_panel.visible = false
	_cv_base = null
	_cv_caravan = null
	_cv_dest = null
	_cv_dest_ids.clear()


func _rebuild_caravan_menu() -> void:
	if _cv_body == null or _cv_caravan == null or _cv_base == null:
		return
	for child in _cv_body.get_children():
		child.queue_free()
	_cv_dest = null
	_cv_dest_ids.clear()
	var c := _cv_caravan
	if not is_instance_valid(c):
		_close_caravan_menu()
		return
	var dest_id := str(c.dest_province_id)
	var dest_name := dest_id
	var dest_data: Dictionary = _cv_base.get_province_data(dest_id)
	if not dest_data.is_empty():
		dest_name = str(dest_data.get("name", dest_id))
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(280, 0)
	info.text = "Destination: %s\nCargo: %s" % [dest_name, GlobalUnits.caravan_cargo_summary(c.cargo)]
	_cv_body.add_child(info)
	var dest_row := HBoxContainer.new()
	var dest_lbl := Label.new()
	dest_lbl.text = "New destination:"
	dest_row.add_child(dest_lbl)
	_cv_dest = OptionButton.new()
	_cv_dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var select_i := 0
	for prov in _cv_base.provinces.get_children():
		var pid := str(prov.name)
		var pdata: Dictionary = _cv_base.get_province_data(pid)
		if pdata.is_empty():
			continue
		if pid == dest_id:
			select_i = _cv_dest_ids.size()
		_cv_dest.add_item(str(pdata.get("name", pid)))
		_cv_dest_ids.append(pid)
	_cv_dest.select(select_i)
	dest_row.add_child(_cv_dest)
	_cv_body.add_child(dest_row)
	var set_btn := Button.new()
	set_btn.text = "Set destination"
	set_btn.pressed.connect(_on_caravan_set_dest)
	_cv_body.add_child(set_btn)
	_cv_panel.visible = true
	_cv_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_cv_panel.size = Vector2(minf(380, vp.x * 0.9), _cv_panel.get_combined_minimum_size().y)
	_cv_panel.position = (vp - _cv_panel.size) * 0.5


func _on_caravan_set_dest() -> void:
	var base = _cv_base
	var c = _cv_caravan
	var idx := _cv_dest.selected if _cv_dest != null else -1
	var dest_id := ""
	if idx >= 0 and idx < _cv_dest_ids.size():
		dest_id = str(_cv_dest_ids[idx])
	if base == null or c == null or dest_id == "":
		return
	base.do_redirect_caravan(String(c.name), dest_id)
	show_info_popup("Caravan destination updated")


func _ensure_caravan_capture_menu() -> void:
	if _cv_cap_panel != null:
		return
	_cv_cap_panel = PanelContainer.new()
	_cv_cap_panel.top_level = true
	_cv_cap_panel.z_index = 140
	_cv_cap_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_cv_cap_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Enemy caravan"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_caravan_capture_menu)
	header.add_child(title)
	header.add_child(close_btn)
	_cv_cap_info = Label.new()
	_cv_cap_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cv_cap_info.custom_minimum_size = Vector2(280, 0)
	var take_btn := Button.new()
	take_btn.text = "Take ownership"
	take_btn.pressed.connect(_on_caravan_capture_take)
	var destroy_btn := Button.new()
	destroy_btn.text = "Destroy"
	destroy_btn.pressed.connect(_on_caravan_capture_destroy)
	var ignore_btn := Button.new()
	ignore_btn.text = "Ignore"
	ignore_btn.pressed.connect(_close_caravan_capture_menu)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_cv_cap_info)
	vbox.add_child(take_btn)
	vbox.add_child(destroy_btn)
	vbox.add_child(ignore_btn)
	margin.add_child(vbox)
	_cv_cap_panel.add_child(margin)
	add_child(_cv_cap_panel)


func open_caravan_capture_menu(base_map: Node, army: Node2D, caravan: Node2D) -> void:
	_ensure_caravan_capture_menu()
	_cv_cap_base = base_map
	_cv_cap_caravan = caravan
	_cv_cap_force_id = str(army.force_id) if army != null and army.get("force_id") != null else ""
	var owner_name := "?"
	if base_map.players.has(caravan.player_owner):
		owner_name = str(base_map.players[caravan.player_owner].name)
	_cv_cap_info.text = "Owner: %s\nCargo: %s\nTake it to redirect, or destroy it (no loot)." % [
		owner_name, GlobalUnits.caravan_cargo_summary(caravan.cargo)
	]
	_cv_cap_panel.visible = true
	_cv_cap_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_cv_cap_panel.size = Vector2(minf(360, vp.x * 0.9), _cv_cap_panel.get_combined_minimum_size().y)
	_cv_cap_panel.position = (vp - _cv_cap_panel.size) * 0.5


func _close_caravan_capture_menu() -> void:
	if _cv_cap_panel != null:
		_cv_cap_panel.visible = false
	_cv_cap_base = null
	_cv_cap_caravan = null
	_cv_cap_force_id = ""


func _on_caravan_capture_take() -> void:
	var base = _cv_cap_base
	var c = _cv_cap_caravan
	var fid := _cv_cap_force_id
	_close_caravan_capture_menu()
	if base != null and c != null and is_instance_valid(c):
		if fid != "" and base.has_method("do_clear_force_siege"):
			base.do_clear_force_siege(fid)
		base.do_capture_caravan(String(c.name))


func _on_caravan_capture_destroy() -> void:
	var base = _cv_cap_base
	var c = _cv_cap_caravan
	var fid := _cv_cap_force_id
	_close_caravan_capture_menu()
	if base != null and c != null and is_instance_valid(c):
		if fid != "" and base.has_method("do_clear_force_siege"):
			base.do_clear_force_siege(fid)
		base.do_destroy_caravan(String(c.name))


# --- Merchant raid ----------------------------------------------------------

func _ensure_merchant_raid_menu() -> void:
	if _mr_panel != null:
		return
	_mr_panel = PanelContainer.new()
	_mr_panel.top_level = true
	_mr_panel.z_index = 142
	_mr_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_mr_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Raid merchant"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	_mr_info = Label.new()
	_mr_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mr_info.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_mr_info)
	var btn_row := HBoxContainer.new()
	var no_btn := Button.new()
	no_btn.text = "No"
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_btn.pressed.connect(_close_merchant_raid_menu)
	btn_row.add_child(no_btn)
	var yes_btn := Button.new()
	yes_btn.text = "Yes"
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.pressed.connect(_on_merchant_raid_confirm)
	btn_row.add_child(yes_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_mr_panel.add_child(margin)
	add_child(_mr_panel)


func open_merchant_raid_menu(base_map: Node, force_id: String, merchant: Node) -> void:
	_ensure_merchant_raid_menu()
	_mr_base = base_map
	_mr_force_id = force_id
	_mr_merchant = merchant
	var mname := str(merchant.get("display_name") if merchant.get("display_name") != null else "Merchant")
	var raid_mp := int(base_map.RAID_MP_COST) if base_map.get("RAID_MP_COST") != null else 2
	_mr_info.text = "Raid %s?\nCosts %d movement points." % [mname, raid_mp]
	_mr_panel.visible = true
	_mr_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_mr_panel.size = Vector2(minf(340, vp.x * 0.9), _mr_panel.get_combined_minimum_size().y)
	_mr_panel.position = (vp - _mr_panel.size) * 0.5


func _close_merchant_raid_menu() -> void:
	if _mr_panel != null:
		_mr_panel.visible = false
	_mr_base = null
	_mr_force_id = ""
	_mr_merchant = null


func _on_merchant_raid_confirm() -> void:
	var base = _mr_base
	var force_id := _mr_force_id
	var merchant = _mr_merchant
	_close_merchant_raid_menu()
	if base == null or force_id == "" or merchant == null or not is_instance_valid(merchant):
		return
	base.do_raid_merchant(force_id, String(merchant.name))


# --- Field raid -------------------------------------------------------------

func _ensure_field_raid_menu() -> void:
	if _fr_panel != null:
		return
	_fr_panel = PanelContainer.new()
	_fr_panel.top_level = true
	_fr_panel.z_index = 142
	_fr_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fr_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Raid field"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	_fr_info = Label.new()
	_fr_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fr_info.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(_fr_info)
	var btn_row := HBoxContainer.new()
	var no_btn := Button.new()
	no_btn.text = "No"
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_btn.pressed.connect(_close_field_raid_menu)
	btn_row.add_child(no_btn)
	var yes_btn := Button.new()
	yes_btn.name = "YesBtn"
	yes_btn.text = "Raid"
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.pressed.connect(_on_field_raid_confirm)
	btn_row.add_child(yes_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_fr_panel.add_child(margin)
	add_child(_fr_panel)


func open_field_raid_menu(base_map: Node, force_id: String, field: Node) -> void:
	_ensure_field_raid_menu()
	_fr_base = base_map
	_fr_force_id = force_id
	_fr_field = field
	var preview := {"summary": "Raid this field?", "ok": true}
	if base_map.has_method("field_raid_preview"):
		preview = base_map.field_raid_preview(field)
	var raid_mp := int(base_map.RAID_MP_COST) if base_map.get("RAID_MP_COST") != null else 2
	var crop_name = field.get_crop_name() if field.has_method("get_crop_name") else "Field"
	_fr_info.text = "%s\n%s\nCosts %d movement points." % [
		crop_name,
		str(preview.get("summary", "Raid this field?")),
		raid_mp,
	]
	var yes_btn: Button = _fr_panel.find_child("YesBtn", true, false)
	if yes_btn != null:
		var can := bool(preview.get("ok", false))
		if base_map.has_method("force_has_movement") and not base_map.force_has_movement(force_id, raid_mp):
			can = false
			yes_btn.text = "Need %d MP" % raid_mp
		else:
			yes_btn.text = "Raid"
		yes_btn.disabled = not can
	_fr_panel.visible = true
	_fr_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_fr_panel.size = Vector2(minf(340, vp.x * 0.9), _fr_panel.get_combined_minimum_size().y)
	_fr_panel.position = (vp - _fr_panel.size) * 0.5


func _close_field_raid_menu() -> void:
	if _fr_panel != null:
		_fr_panel.visible = false
	_fr_base = null
	_fr_force_id = ""
	_fr_field = null


func _on_field_raid_confirm() -> void:
	var base = _fr_base
	var force_id := _fr_force_id
	var field = _fr_field
	_close_field_raid_menu()
	if base == null or force_id == "" or field == null or not is_instance_valid(field):
		return
	if base.has_method("do_raid_field"):
		base.do_raid_field(force_id, field)


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
	_ms_title = Label.new()
	_ms_title.text = "Merchant"
	_ms_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_title.add_theme_font_size_override("font_size", 16)
	header.add_child(_ms_title)
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
	var mname := str(merchant.get("display_name") if merchant.get("display_name") != null else "Merchant")
	if _ms_title != null:
		_ms_title.text = mname
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


# --- Sellswords hire --------------------------------------------------------

func _ensure_sellswords_hire() -> void:
	if _ss_panel != null:
		return
	_ss_panel = PanelContainer.new()
	_ss_panel.top_level = true
	_ss_panel.z_index = 140
	_ss_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ss_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Sellswords"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_sellswords_hire)
	header.add_child(close_btn)
	vbox.add_child(header)
	_ss_info_lbl = Label.new()
	_ss_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ss_info_lbl.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(_ss_info_lbl)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	_ss_body = VBoxContainer.new()
	_ss_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ss_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_ss_body)
	vbox.add_child(scroll)
	_ss_total_lbl = Label.new()
	_ss_total_lbl.text = "Total: 0 marks"
	vbox.add_child(_ss_total_lbl)
	var btn_row := HBoxContainer.new()
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_sellswords_hire)
	btn_row.add_child(cancel_btn)
	var hire_btn := Button.new()
	hire_btn.text = "Hire"
	hire_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire_btn.pressed.connect(_on_sellswords_hire_confirm)
	btn_row.add_child(hire_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_ss_panel.add_child(margin)
	add_child(_ss_panel)


func open_sellswords_hire(base_map: Node, band: Node) -> void:
	_ensure_sellswords_hire()
	_ss_base = base_map
	_ss_band = band
	var prov = band.get("province")
	var pname := "Province"
	if prov != null and prov.get("p_name") != null:
		pname = str(prov.p_name)
	var marks := 0
	if base_map.players.has(base_map.my_pl_id):
		marks = int(base_map.players[base_map.my_pl_id].game_data.get("marks", 0))
	var stay := int(band.get("seasons_left")) if band.get("seasons_left") != null else 0
	_ss_info_lbl.text = "Hiring in %s.\nYour marks: %d\nStaying: %d season(s)" % [pname, marks, stay]

	for child in _ss_body.get_children():
		child.queue_free()
	var offer: Array = band.get("offer") if band.get("offer") != null else []
	var total := 0
	for entry in offer:
		var ut := int(entry.get("type", GlobalUnits.UNIT_TYPE.PEASANT))
		var cnt := int(entry.get("count", 0))
		var cost := GlobalUnits.sellsword_stack_mark_price(ut, cnt)
		total += cost
		var row := Label.new()
		row.text = "%d %s — %d marks" % [cnt, GlobalUnits.unit_name(ut), cost]
		_ss_body.add_child(row)
	_ss_total_lbl.text = "Total: %d marks (all or nothing)" % total

	_ss_panel.visible = true
	_ss_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_ss_panel.size = Vector2(minf(420, vp.x * 0.9), minf(320, vp.y * 0.75))
	_ss_panel.position = (vp - _ss_panel.size) * 0.5


func _close_sellswords_hire() -> void:
	if _ss_panel != null:
		_ss_panel.visible = false
	_ss_base = null
	_ss_band = null


func _on_sellswords_hire_confirm() -> void:
	var base = _ss_base
	var band = _ss_band
	var band_id := ""
	if band != null:
		band_id = String(band.name)
	_close_sellswords_hire()
	if base == null or band_id == "":
		return
	base.do_hire_sellswords(band_id)
