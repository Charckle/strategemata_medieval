extends CanvasLayer

const ArmyNames := preload("res://global_scripts/army_names.gd")

@onready var map_menu := $map_menu
@onready var economy_menu := $economy_menu
@onready var war_menu := $war_menu
@onready var msg_menu := $msg_menu
@onready var settings_menu := $settings_menu
@onready var msg_btn := $Panel/msg_btn
@onready var msg_list := $msg_menu/margin/vbox/tabs/Inbox/ScrollContainer/msg_list
@onready var msg_empty_lbl := $msg_menu/margin/vbox/tabs/Inbox/empty_lbl
@onready var show_province_names_chk := $settings_menu/margin/vbox/tabs/Gameplay/show_province_names_row/show_province_names_chk
@onready var show_army_names_chk := $settings_menu/margin/vbox/tabs/Gameplay/show_army_names_row/show_army_names_chk
@onready var show_weather_chk := $settings_menu/margin/vbox/tabs/Video/show_weather_row/show_weather_chk
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
@onready var province_sub_tabs := $economy_menu/margin/vbox/tabs/province/sub_tabs
@onready var province_tab_status := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/info_grid/status_lbl
@onready var province_tab_owner := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/info_grid/owner_lbl
@onready var province_tab_defacto := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/info_grid/defacto_lbl
@onready var province_tab_dejure := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/info_grid/dejure_lbl
@onready var province_tab_population := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/info_grid/population_prov_lbl
@onready var province_tab_income := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/info_grid/income_prov_lbl
@onready var province_tab_villages := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/buildings_grid/villages_val
@onready var province_tab_towns := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/buildings_grid/towns_val
@onready var province_tab_castles := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/buildings_grid/castles_val
@onready var province_tab_economy := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content/buildings_grid/economy_val
@onready var province_tab_root := $economy_menu/margin/vbox/tabs/province/sub_tabs/overview/ScrollContainer/content
@onready var province_farming_root := $economy_menu/margin/vbox/tabs/province/sub_tabs/farming/ScrollContainer/content
@onready var province_army_root := $economy_menu/margin/vbox/tabs/province/sub_tabs/army/ScrollContainer/content
@onready var province_shipyard_root := $economy_menu/margin/vbox/tabs/province/sub_tabs/shipyard/ScrollContainer/content
@onready var caravan_tab_root := $economy_menu/margin/vbox/tabs/caravan
@onready var caravan_tab_info := $economy_menu/margin/vbox/tabs/caravan/caravan_info
@onready var caravan_tab_send_btn := $economy_menu/margin/vbox/tabs/caravan/send_btn
@onready var caravan_tab_list := $economy_menu/margin/vbox/tabs/caravan/ScrollContainer/caravan_list

@onready var alliances_list := $war_menu/margin/vbox/tabs/Alliances/ScrollContainer/alliances_list
@onready var diplomacy_list := $war_menu/margin/vbox/tabs/Diplomacy/ScrollContainer/diplomacy_list
@onready var military_upkeep_lbl := $war_menu/margin/vbox/tabs/Military/upkeep_summary_lbl
@onready var military_strikes_lbl := $war_menu/margin/vbox/tabs/Military/strikes_lbl
@onready var military_list := $war_menu/margin/vbox/tabs/Military/ScrollContainer/military_list
@onready var ladder_list := $war_menu/margin/vbox/tabs/Ladder/ScrollContainer/ladder_list

var selected_province_id: String = ""
var _refreshing_alliances := false
## Ladder tab sort metric key (marks / fighting / grain / dejure / defacto).
var _ladder_sort_metric: String = "fighting"

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
var _prov_ration_lbl: Label = null
var _prov_ration_btns: Dictionary = {} # RATION -> Button
var _prov_ration_row: HBoxContainer = null
var _prov_tax_lbl: Label = null
var _prov_tax_btns: Dictionary = {} # TAX -> Button
var _prov_tax_row: HBoxContainer = null
var _prov_levy_lbl: Label = null
var _prov_weapons_lbl: Label = null
var _prov_recruit_btn: Button = null
var _prov_shipyard_info: Label = null
var _prov_shipyard_stock: Label = null
var _prov_ships_spin: SpinBox = null
var _prov_ships_build_btn: Button = null
var _prov_farming_tab_index: int = 1
var _prov_army_tab_index: int = 2
var _prov_shipyard_tab_index: int = 3

# Recruit levy panel.
var _rc_blocker: ColorRect = null
var _rc_panel: PanelContainer = null
var _rc_body: VBoxContainer = null
var _rc_info_lbl: Label = null
var _rc_total_lbl: Label = null
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

# Transport fleet menus / prompts.
var _fl_panel: PanelContainer = null
var _fl_body: VBoxContainer = null
var _fl_base = null
var _fl_fleet: Node2D = null
var _fl_split_spin: SpinBox = null
var _fl_prompt: PanelContainer = null
var _fl_prompt_body: VBoxContainer = null

# Merchant shop panel (4 tabs: Buy/Sell × Weapons/Materials).
var _ms_panel: PanelContainer = null
var _ms_title: Label = null
var _ms_info_lbl: Label = null
var _ms_buy_weapons_body: VBoxContainer = null
var _ms_buy_materials_body: VBoxContainer = null
var _ms_sell_weapons_body: VBoxContainer = null
var _ms_sell_materials_body: VBoxContainer = null
var _ms_buy_total_lbl: Label = null
var _ms_sell_total_lbl: Label = null
var _ms_tabs: TabContainer = null
var _ms_buy_btn: Button = null
var _ms_sell_btn: Button = null
var _ms_base = null
var _ms_merchant: Node = null
var _ms_buy_weapon_spinboxes: Dictionary = {}
var _ms_buy_material_spinboxes: Dictionary = {}
var _ms_sell_weapon_spinboxes: Dictionary = {}
var _ms_sell_material_spinboxes: Dictionary = {}
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

# Rename army dialog.
var _rn_panel: PanelContainer = null
var _rn_edit: LineEdit = null
var _rn_error: Label = null
var _rn_base = null
var _rn_force_id: String = ""

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

# Prompt when emptying a settlement garrison while militia is off.
var _mil_prompt: PanelContainer = null
var _mil_prompt_lbl: Label = null
var _mil_pending_transfer: Dictionary = {}

# Building info popup (built at runtime): header with title + X, plus a body.
var _building_popup: PanelContainer = null
var _building_popup_title: Label = null
var _building_popup_body: Label = null
var _building_popup_close: Button = null
var _building_popup_deploy: Button = null
var _building_popup_economy: Button = null
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
var _prov_farming_manage_root: VBoxContainer = null
var _prov_fields_lbl: Label = null
var _prov_populate_idle_btn: Button = null
var _prov_stock_lbl: Label = null
var _prov_farm_stock_lbl: Label = null
var _prov_labor_lbl: RichTextLabel = null
var _prov_farm_labor_lbl: RichTextLabel = null
var _prov_agri_lbl: RichTextLabel = null
var _prov_prod_lbl: RichTextLabel = null
var _prov_smith_lbl: RichTextLabel = null
var _prov_labor_box: VBoxContainer = null
var _prov_farm_labor_box: VBoxContainer = null
var _prov_labor_sliders: Dictionary = {} # category -> HSlider
var _prov_labor_panels: Dictionary = {} # category -> PanelContainer
var _prov_labor_updating := false
var _prov_idle_field_count: int = 0
## When opening province economy from a building click, highlight this labor row.
var _labor_focus_category: String = ""

# Demolish economy building confirmation.
var _econ_demolish_prompt: PanelContainer = null
var _econ_demolish_lbl: Label = null
var _econ_demolish_building: Node = null
var _econ_demolish_base = null

const _PROV_SURPLUS_COLOR := "#6dce6d"
const _PROV_DEFICIT_COLOR := "#e85a4f"

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

# Castle construction popup (build / upgrade / dismantle).
var _castle_popup: PanelContainer = null
var _castle_popup_title: Label = null
var _castle_popup_body: Label = null
var _castle_popup_btns: VBoxContainer = null
var _castle_popup_building: Node = null
var _castle_popup_base = null

# Battle preview / result UI (built at runtime).
var _bt_panel: PanelContainer = null
var _bt_body: VBoxContainer = null
var _bt_title: Label = null
var _bt_base = null
var _bt_attacker_id: String = ""
var _bt_defender_id: String = ""
var _bt_building: Node = null
var _bt_landing_fleet_id: String = ""

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
	_populate_video_settings()
	_ensure_admin_tab()
	show_province_names_chk.toggled.connect(_on_show_province_names_toggled)
	if show_army_names_chk != null:
		show_army_names_chk.toggled.connect(_on_show_army_names_toggled)
	show_weather_chk.toggled.connect(_on_show_weather_toggled)
	_ensure_province_levy_widgets()
	if caravan_tab_send_btn != null:
		caravan_tab_send_btn.pressed.connect(_on_caravan_tab_send_pressed)
	if economy_tabs != null and caravan_tab_root != null:
		var cv_idx := caravan_tab_root.get_index()
		economy_tabs.set_tab_title(cv_idx, "Caravan")
	refresh_msg_button()


var _admin_prov_opt: OptionButton = null
var _admin_report: TextEdit = null
var _admin_prov_ids: Array = []


func _ensure_admin_tab() -> void:
	var tabs: TabContainer = settings_menu.get_node_or_null("margin/vbox/tabs")
	if tabs == null:
		return
	if tabs.get_node_or_null("Admin") != null:
		return
	var root := VBoxContainer.new()
	root.name = "Admin"
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	var lbl := Label.new()
	lbl.text = "Province"
	row.add_child(lbl)

	_admin_prov_opt = OptionButton.new()
	_admin_prov_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_admin_prov_opt.item_selected.connect(_on_admin_province_selected)
	row.add_child(_admin_prov_opt)

	var focus_btn := Button.new()
	focus_btn.text = "Focused"
	focus_btn.pressed.connect(_on_admin_use_focused)
	row.add_child(focus_btn)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_admin_report)
	row.add_child(refresh_btn)

	_admin_report = TextEdit.new()
	_admin_report.editable = false
	_admin_report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_admin_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_admin_report.custom_minimum_size = Vector2(0, 280)
	root.add_child(_admin_report)

	# Give settings room for the dump.
	settings_menu.custom_minimum_size = Vector2(720, 560)
	settings_menu.size = Vector2(720, 560)


func _on_settings_btn_pressed() -> void:
	settings_menu.custom_minimum_size = Vector2(720, 560)
	settings_menu.size = Vector2(720, 560)
	_toggle_menu(settings_menu)
	if settings_menu.visible:
		_refresh_admin_province_list()
		_refresh_admin_report()


func _refresh_admin_province_list() -> void:
	if _admin_prov_opt == null or not is_instance_valid(parent_n):
		return
	var prev := ""
	if _admin_prov_opt.selected >= 0 and _admin_prov_opt.selected < _admin_prov_ids.size():
		prev = str(_admin_prov_ids[_admin_prov_opt.selected])
	_admin_prov_opt.clear()
	_admin_prov_ids.clear()
	if parent_n.get("provinces") == null:
		return
	var provs: Array = parent_n.provinces.get_children()
	provs.sort_custom(func(a, b): return String(a.get("p_name")) < String(b.get("p_name")))
	var select_idx := 0
	for i in provs.size():
		var prov = provs[i]
		var pid := String(prov.name)
		var label := "%s (%s)" % [str(prov.get("p_name")), pid]
		_admin_prov_opt.add_item(label)
		_admin_prov_ids.append(pid)
		if pid == prev or (prev == "" and pid == selected_province_id):
			select_idx = i
	if _admin_prov_opt.item_count > 0:
		_admin_prov_opt.select(select_idx)


func _on_admin_province_selected(_idx: int) -> void:
	_refresh_admin_report()


func _on_admin_use_focused() -> void:
	if not is_instance_valid(parent_n):
		return
	var pid := ""
	if parent_n.has_method("resolve_economy_province_focus"):
		pid = str(parent_n.resolve_economy_province_focus())
	elif parent_n.get("focused_province_id") != null:
		pid = str(parent_n.focused_province_id)
	if pid == "":
		return
	for i in _admin_prov_ids.size():
		if str(_admin_prov_ids[i]) == pid:
			_admin_prov_opt.select(i)
			_refresh_admin_report()
			return


func _refresh_admin_report() -> void:
	if _admin_report == null:
		return
	if not is_instance_valid(parent_n) or not parent_n.has_method("get_admin_province_report"):
		_admin_report.text = "No map / admin report available."
		return
	if _admin_prov_opt == null or _admin_prov_opt.selected < 0 or _admin_prov_opt.selected >= _admin_prov_ids.size():
		_admin_report.text = "Select a province."
		return
	var pid := str(_admin_prov_ids[_admin_prov_opt.selected])
	_admin_report.text = parent_n.get_admin_province_report(pid)

func _populate_gameplay_settings() -> void:
	var enabled = GlobalSet.settings.get("show_province_names", 1) != 0
	show_province_names_chk.button_pressed = enabled
	if show_army_names_chk != null:
		show_army_names_chk.button_pressed = GlobalSet.settings.get("show_army_names", 1) != 0


func _populate_video_settings() -> void:
	var weather_on = GlobalSet.settings.get("show_weather", 1) != 0
	show_weather_chk.button_pressed = weather_on


func _on_show_province_names_toggled(pressed: bool) -> void:
	GlobalSet.settings["show_province_names"] = 1 if pressed else 0
	SettingsLoad.save_settings()
	if is_instance_valid(parent_n) and parent_n.has_method("refresh_province_labels"):
		parent_n.refresh_province_labels()


func _on_show_army_names_toggled(pressed: bool) -> void:
	GlobalSet.settings["show_army_names"] = 1 if pressed else 0
	SettingsLoad.save_settings()
	if is_instance_valid(parent_n) and parent_n.has_method("refresh_army_labels"):
		parent_n.refresh_army_labels()


func _on_show_weather_toggled(pressed: bool) -> void:
	GlobalSet.settings["show_weather"] = 1 if pressed else 0
	SettingsLoad.save_settings()


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
	open_economy_for_province(pid, false)


## Open the Economy menu on the Province tab for `province_id`.
func open_economy_for_province(province_id: String, sticky: bool = true) -> void:
	if not is_instance_valid(parent_n):
		return
	selected_province_id = province_id
	if economy_menu.visible:
		_bring_to_front(economy_menu)
	else:
		_toggle_menu(economy_menu)
	economy_tabs.current_tab = 2
	if province_id != "" and parent_n.has_method("set_province_focus"):
		parent_n.set_province_focus(province_id, sticky)
	update_economy_menu(parent_n)


## Open province economy Overview focused on labor (optionally one category).
func open_economy_labor_for_province(province_id: String, labor_category: String = "") -> void:
	_labor_focus_category = labor_category
	open_economy_for_province(province_id, true)
	if province_sub_tabs != null:
		province_sub_tabs.current_tab = 0 # overview (labor sliders)
	_apply_labor_focus()


func on_province_focused(province_id: String) -> void:
	selected_province_id = province_id
	if not is_economy_menu_open():
		return
	economy_tabs.current_tab = 2
	if is_instance_valid(parent_n):
		_fill_province_tab(parent_n, province_id)


## Screen-space hit test for open menus / popups (Area2D click-through guard).
func blocks_map_at_mouse() -> bool:
	# Modal levy form: block the whole map while open.
	if is_recruit_menu_open():
		return true
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
	if is_recruit_menu_open():
		return true
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
		refresh_ladder_tab()


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
	_building_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_building_popup_body.custom_minimum_size = Vector2(300, 0)
	_building_popup_economy = Button.new()
	_building_popup_economy.text = "Open province economy"
	_building_popup_economy.visible = false
	_building_popup_economy.pressed.connect(_on_building_popup_economy_pressed)
	_building_popup_deploy = Button.new()
	_building_popup_deploy.text = "Ungarrison your troops"
	_building_popup_deploy.visible = false
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_building_popup_body)
	vbox.add_child(_building_popup_economy)
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
	# Economy shortcut only on click (pinned) — hover popups vanish on mouse leave.
	_building_popup_economy.visible = pinned and _province_id_for_building(building) != ""
	if _building_popup_deploy.pressed.is_connected(_on_building_popup_deploy_pressed):
		_building_popup_deploy.pressed.disconnect(_on_building_popup_deploy_pressed)
	if deploy_cb.is_valid():
		_building_popup_deploy.text = "Ungarrison your troops"
		_building_popup_deploy.visible = true
		_building_popup_deploy.pressed.connect(_on_building_popup_deploy_pressed.bind(deploy_cb))
	else:
		_building_popup_deploy.visible = false
	_building_popup.visible = true
	_place_anchored_popup(_building_popup, get_viewport().get_mouse_position() + Vector2(14, 0), 320.0)


func _province_id_for_building(building: Node) -> String:
	if building == null or not is_instance_valid(parent_n):
		return ""
	if parent_n.has_method("find_province_for_building"):
		var prov = parent_n.find_province_for_building(building)
		if prov != null and is_instance_valid(prov):
			return String(prov.name)
	var prov2 = building.get("province")
	if prov2 != null and is_instance_valid(prov2):
		return String(prov2.name)
	return ""


func _on_building_popup_economy_pressed() -> void:
	var pid := _province_id_for_building(_building_popup_node)
	hide_building_popup()
	if pid == "":
		return
	open_economy_for_province(pid, true)


func _on_building_popup_deploy_pressed(deploy_cb: Callable) -> void:
	hide_building_popup()
	deploy_cb.call()


## Fixed-width map popup: keep full size, flip/clamp so the whole panel stays on-screen.
func _place_anchored_popup(panel: Control, preferred: Vector2, fixed_w: float = 320.0) -> void:
	if panel == null:
		return
	panel.custom_minimum_size.x = fixed_w
	panel.reset_size()
	# Lock width; height follows content (capped to viewport).
	var vp := get_viewport().get_visible_rect().size
	var h := mini(panel.size.y, vp.y)
	panel.size = Vector2(fixed_w, maxf(h, panel.custom_minimum_size.y))
	var pos := preferred
	# Prefer right of cursor; flip left if it would clip.
	if pos.x + panel.size.x > vp.x:
		pos.x = preferred.x - panel.size.x - 14.0
	# Prefer below; flip up if needed.
	if pos.y + panel.size.y > vp.y:
		pos.y = preferred.y - panel.size.y
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - panel.size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - panel.size.y))
	panel.position = pos


func _position_building_popup() -> void:
	_place_anchored_popup(_building_popup, get_viewport().get_mouse_position() + Vector2(14, 0), 320.0)


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
	_field_popup_body.custom_minimum_size = Vector2(300, 0)
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
	_place_anchored_popup(_field_popup, get_viewport().get_mouse_position() + Vector2(14, 0), 320.0)


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
	_place_anchored_popup(_populate_idle_popup, get_viewport().get_mouse_position() + Vector2(14, 0), 360.0)


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
	_econ_popup_body.custom_minimum_size = Vector2(300, 0)
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
	_place_anchored_popup(_econ_popup, get_viewport().get_mouse_position() + Vector2(14, 0), 320.0)


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
	var has_holding = prov != null and prov.has_method("player_has_holding") and prov.player_has_holding(pid)
	var marks := 0
	if _econ_popup_base.players.has(pid):
		marks = int(_econ_popup_base.players[pid].game_data.get("marks", 0))
	if b.has_method("is_built") and b.is_built():
		var owns_building := int(b.get("player_owner")) == pid
		# Labor assignment lives on the province economy Overview tab.
		if has_holding or is_dejure:
			var labor_btn := Button.new()
			var cat := str(b.labor_category()) if b.has_method("labor_category") else ""
			labor_btn.text = "Assign workers" if cat != "" else "Open province economy"
			labor_btn.pressed.connect(_on_econ_assign_workers_pressed)
			_econ_popup_btns.add_child(labor_btn)
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
		if is_dejure and owns_building and b.has_method("can_upgrade") and b.can_upgrade():
			var up_cost := int(b.upgrade_cost()) if b.has_method("upgrade_cost") else 0
			var next_name := "Medium"
			if b.has_method("next_stage") and b.get("STAGES") != null:
				match int(b.next_stage()):
					2: next_name = "Medium"
					3: next_name = "Big"
			var up := Button.new()
			up.text = "Upgrade to %s (%d marks)" % [next_name, up_cost]
			up.disabled = marks < up_cost
			up.pressed.connect(_on_econ_upgrade_pressed)
			_econ_popup_btns.add_child(up)
		if is_dejure:
			var dem := Button.new()
			dem.text = "Demolish…"
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


func _on_econ_upgrade_pressed() -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	if _econ_popup_base.has_method("do_upgrade_economy"):
		_econ_popup_base.do_upgrade_economy(_econ_popup_building)


func _on_econ_assign_workers_pressed() -> void:
	var b := _econ_popup_building
	var pid := _province_id_for_building(b)
	var cat := ""
	if b != null and b.has_method("labor_category"):
		cat = str(b.labor_category())
	hide_economy_building_popup()
	if pid == "":
		return
	open_economy_labor_for_province(pid, cat)


func _on_econ_demolish_pressed() -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	_open_econ_demolish_prompt(_econ_popup_base, _econ_popup_building)


func _on_econ_recipe_pressed(weapon_key: String) -> void:
	if _econ_popup_base == null or _econ_popup_building == null:
		return
	if _econ_popup_base.has_method("do_set_blacksmith_recipe"):
		_econ_popup_base.do_set_blacksmith_recipe(_econ_popup_building, weapon_key)


func _ensure_econ_demolish_prompt() -> void:
	if _econ_demolish_prompt != null:
		return
	_econ_demolish_prompt = PanelContainer.new()
	_econ_demolish_prompt.top_level = true
	_econ_demolish_prompt.z_index = 150
	_econ_demolish_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_econ_demolish_prompt.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Demolish building?"
	title.add_theme_font_size_override("font_size", 16)
	_econ_demolish_lbl = Label.new()
	_econ_demolish_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_econ_demolish_lbl.custom_minimum_size = Vector2(340, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_econ_demolish_prompt)
	var ok_btn := Button.new()
	ok_btn.text = "Demolish"
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.pressed.connect(_on_econ_demolish_confirm)
	row.add_child(cancel_btn)
	row.add_child(ok_btn)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_econ_demolish_lbl)
	vbox.add_child(row)
	margin.add_child(vbox)
	_econ_demolish_prompt.add_child(margin)
	add_child(_econ_demolish_prompt)


func _open_econ_demolish_prompt(base_map: Node, building: Node) -> void:
	_ensure_econ_demolish_prompt()
	_econ_demolish_base = base_map
	_econ_demolish_building = building
	var bname := "this building"
	if base_map != null and base_map.has_method("_building_display_name"):
		bname = str(base_map._building_display_name(building))
	_econ_demolish_lbl.text = (
		"Demolish %s?\n\nThe site becomes an empty plot. Workers assigned here are freed, "
		+ "and any craft recipe is cleared. This cannot be undone."
	) % bname
	_econ_demolish_prompt.visible = true
	_econ_demolish_prompt.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_econ_demolish_prompt.size = Vector2(minf(380, vp.x * 0.9), _econ_demolish_prompt.get_combined_minimum_size().y)
	_econ_demolish_prompt.position = (vp - _econ_demolish_prompt.size) * 0.5


func _close_econ_demolish_prompt() -> void:
	if _econ_demolish_prompt != null:
		_econ_demolish_prompt.visible = false
	_econ_demolish_building = null
	_econ_demolish_base = null


func _on_econ_demolish_confirm() -> void:
	var base = _econ_demolish_base
	var building := _econ_demolish_building
	_close_econ_demolish_prompt()
	hide_economy_building_popup()
	if base != null and building != null and base.has_method("do_demolish_economy"):
		base.do_demolish_economy(building)


# --- Castle construction popup ----------------------------------------------

func _ensure_castle_popup() -> void:
	if _castle_popup != null:
		return
	_castle_popup = PanelContainer.new()
	_castle_popup.top_level = true
	_castle_popup.z_index = 130
	_castle_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_castle_popup.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	_castle_popup_title = Label.new()
	_castle_popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_castle_popup_title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide_castle_popup)
	header.add_child(_castle_popup_title)
	header.add_child(close_btn)
	_castle_popup_body = Label.new()
	_castle_popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_castle_popup_body.custom_minimum_size = Vector2(280, 0)
	_castle_popup_btns = VBoxContainer.new()
	_castle_popup_btns.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_castle_popup_body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_castle_popup_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_castle_popup_btns)
	vbox.add_child(scroll)
	margin.add_child(vbox)
	_castle_popup.add_child(margin)
	add_child(_castle_popup)


func show_castle_popup(base_map: Node, building: Node) -> void:
	_ensure_castle_popup()
	hide_building_popup()
	hide_field_popup()
	hide_economy_building_popup()
	_castle_popup_base = base_map
	_castle_popup_building = building
	_rebuild_castle_popup()
	_castle_popup.visible = true
	_place_anchored_popup(_castle_popup, get_viewport().get_mouse_position() + Vector2(14, 0), 320.0)


func hide_castle_popup() -> void:
	if _castle_popup != null:
		_castle_popup.visible = false
	_castle_popup_building = null
	_castle_popup_base = null


func refresh_castle_popup_if(base_map: Node, building: Node) -> void:
	if _castle_popup == null or not _castle_popup.visible:
		return
	if _castle_popup_building != building:
		return
	_castle_popup_base = base_map
	_rebuild_castle_popup()


func _rebuild_castle_popup() -> void:
	if _castle_popup_base == null or _castle_popup_building == null:
		return
	var b := _castle_popup_building
	var base = _castle_popup_base
	_castle_popup_title.text = (
		base._building_display_name(b) if base.has_method("_building_display_name") else "Castle"
	)
	_castle_popup_body.text = (
		base._building_display_body(b) if base.has_method("_building_display_body") else ""
	)
	for c in _castle_popup_btns.get_children():
		_castle_popup_btns.remove_child(c)
		c.queue_free()
	var pid := int(base.my_pl_id)
	var prov = base.find_province_for_building(b) if base.has_method("find_province_for_building") else null
	var is_dejure = prov != null and prov.has_method("has_dejure") and prov.has_dejure(pid)
	if prov != null:
		var econ_btn := Button.new()
		econ_btn.text = "Open province economy"
		econ_btn.pressed.connect(_on_castle_popup_economy_pressed)
		_castle_popup_btns.add_child(econ_btn)
	var wood := 0
	var stone := 0
	if prov != null and prov.has_method("get_player_material"):
		wood = int(prov.get_player_material(pid, "wood"))
		stone = int(prov.get_player_material(pid, "stone"))
	var stock_lbl := Label.new()
	stock_lbl.text = "Your stock: %d wood · %d stone" % [wood, stone]
	_castle_popup_btns.add_child(stock_lbl)
	if b.has_method("is_operational") and b.is_operational():
		var has_own := false
		if base.has_method("get_player_garrison"):
			has_own = not base.get_player_garrison(b, pid).is_empty()
		if has_own:
			var ung := Button.new()
			ung.text = "Ungarrison your troops"
			ung.pressed.connect(_on_castle_ungarrison_pressed)
			_castle_popup_btns.add_child(ung)
	if not is_dejure:
		var hint := Label.new()
		hint.text = "Only de jure can change construction here"
		_castle_popup_btns.add_child(hint)
		return
	var hdr := Label.new()
	hdr.text = "Construction target:"
	_castle_popup_btns.add_child(hdr)
	# Dismantle / cancel toward empty.
	_add_castle_target_button(GlobalUnits.CASTLE_TARGET_EMPTY, "Dismantle / clear plot", wood, stone)
	for lvl in range(6):
		var name_ := str(b.castle_type_display_name(lvl)) if b.has_method("castle_type_display_name") else "Level %d" % (lvl + 1)
		_add_castle_target_button(lvl, name_, wood, stone)


func _add_castle_target_button(target: int, label: String, wood: int, stone: int) -> void:
	var b := _castle_popup_building
	if b == null or not b.has_method("preview_retarget"):
		return
	var preview: Dictionary = b.preview_retarget(target)
	if preview.is_empty():
		# Current target / no-op — show disabled current marker when matching.
		if b.get("project_active") and int(b.get("project_target")) == target:
			var cur := Button.new()
			cur.text = "%s (current project)" % label
			cur.disabled = true
			_castle_popup_btns.add_child(cur)
		elif b.has_method("is_operational") and b.is_operational() and int(b.get("castle_type")) == target:
			var cur2 := Button.new()
			cur2.text = "%s (standing)" % label
			cur2.disabled = true
			_castle_popup_btns.add_child(cur2)
		return
	var pay: Dictionary = preview.get("pay", {})
	var pay_w := int(pay.get("wood", 0))
	var pay_s := int(pay.get("stone", 0))
	var work := int(preview.get("work_needed", 0))
	var parts: PackedStringArray = []
	if bool(preview.get("complete_immediately", false)):
		parts.append("finish now")
	elif work > 0:
		parts.append("%d work" % work)
	if pay_w > 0 or pay_s > 0:
		var cost_bits: PackedStringArray = []
		if pay_w > 0:
			cost_bits.append("%d wood" % pay_w)
		if pay_s > 0:
			cost_bits.append("%d stone" % pay_s)
		parts.append("pay " + ", ".join(cost_bits))
	var refund: Dictionary = preview.get("refund_on_complete", {"wood": 0, "stone": 0})
	var refund_now: Dictionary = preview.get("refund_now", {"wood": 0, "stone": 0})
	var rw := int(refund.get("wood", 0)) + int(refund_now.get("wood", 0))
	var rs := int(refund.get("stone", 0)) + int(refund_now.get("stone", 0))
	if rw > 0 or rs > 0:
		var rb: PackedStringArray = []
		if rw > 0:
			rb.append("%d wood" % rw)
		if rs > 0:
			rb.append("%d stone" % rs)
		parts.append("refund " + ", ".join(rb))
	var btn := Button.new()
	btn.text = label if parts.is_empty() else "%s (%s)" % [label, " · ".join(parts)]
	btn.disabled = wood < pay_w or stone < pay_s
	btn.pressed.connect(_on_castle_target_pressed.bind(target))
	_castle_popup_btns.add_child(btn)


func _on_castle_target_pressed(target: int) -> void:
	if _castle_popup_base == null or _castle_popup_building == null:
		return
	if _castle_popup_base.has_method("do_retarget_castle"):
		_castle_popup_base.do_retarget_castle(_castle_popup_building, target)


func _on_castle_ungarrison_pressed() -> void:
	if _castle_popup_base == null or _castle_popup_building == null:
		return
	var building := _castle_popup_building
	var base = _castle_popup_base
	hide_castle_popup()
	open_deploy_menu(base, building, int(base.my_pl_id))


func _on_castle_popup_economy_pressed() -> void:
	var pid := _province_id_for_building(_castle_popup_building)
	hide_castle_popup()
	if pid == "":
		return
	open_economy_for_province(pid, true)


# --- Close everything (called on player switch / end-turn) ------------------

func close_all_popups() -> void:
	hide_building_popup()
	hide_field_popup()
	hide_economy_building_popup()
	_close_econ_demolish_prompt()
	hide_castle_popup()
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
	_close_rename_army_dialog()


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

	var units: Array = _am_army.get_units()
	var fid := str(_am_army.force_id)
	var nick := ""
	if _am_base.has_method("force_display_name"):
		nick = str(_am_base.force_display_name(fid))
	if nick == "":
		nick = "Army"

	# Title: nickname + total men
	var title_lbl: Label = _am_panel.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/Title")
	if title_lbl != null:
		title_lbl.text = "%s  (%d men)" % [nick, GlobalUnits.total_men(units)]

	# Controller can rename
	var ctrl = _am_army.get_controller()
	if ctrl == _am_base.my_pl_id:
		var rename_btn := Button.new()
		rename_btn.text = "Rename"
		rename_btn.pressed.connect(_on_am_rename_pressed)
		_am_body.add_child(rename_btn)
		_am_body.add_child(HSeparator.new())

	# Roster summary
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
	var can_deposit := false
	if _am_base.has_method("can_force_deposit_cargo"):
		can_deposit = _am_base.can_force_deposit_cargo(_am_army.force_id, _am_base.my_pl_id)
	else:
		can_deposit = prov_under != null
	deposit_btn.disabled = not can_deposit or not GlobalUnits.caravan_cargo_has_any(cargo)
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


func _on_am_rename_pressed() -> void:
	if _am_base == null or _am_army == null:
		return
	_open_rename_army_dialog(_am_base, str(_am_army.force_id))


func _ensure_rename_army_dialog() -> void:
	if _rn_panel != null:
		return
	_rn_panel = PanelContainer.new()
	_rn_panel.top_level = true
	_rn_panel.z_index = 140
	_rn_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rn_panel.visible = false
	_rn_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Rename army"
	title.add_theme_font_size_override("font_size", 16)
	_rn_edit = LineEdit.new()
	_rn_edit.custom_minimum_size = Vector2(280, 0)
	_rn_edit.max_length = int(ArmyNames.max_name_length())
	_rn_error = Label.new()
	_rn_error.modulate = Color(1.0, 0.45, 0.35)
	_rn_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rn_error.custom_minimum_size = Vector2(280, 0)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(_on_rn_confirm)
	var reroll_btn := Button.new()
	reroll_btn.text = "Reroll"
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.pressed.connect(_on_rn_reroll)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_rename_army_dialog)
	btn_row.add_child(confirm_btn)
	btn_row.add_child(reroll_btn)
	btn_row.add_child(cancel_btn)
	vbox.add_child(title)
	vbox.add_child(_rn_edit)
	vbox.add_child(_rn_error)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_rn_panel.add_child(margin)
	add_child(_rn_panel)


func _open_rename_army_dialog(base_map, force_id: String) -> void:
	_ensure_rename_army_dialog()
	_rn_base = base_map
	_rn_force_id = force_id
	_rn_error.text = ""
	var current := ""
	if base_map.has_method("force_nickname"):
		current = str(base_map.force_nickname(force_id))
	_rn_edit.text = current
	_rn_edit.grab_focus()
	_rn_panel.visible = true
	_rn_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var sz := _rn_panel.get_combined_minimum_size()
	_rn_panel.size = sz
	_rn_panel.position = (vp - sz) * 0.5


func _close_rename_army_dialog() -> void:
	if _rn_panel != null:
		_rn_panel.visible = false
	_rn_base = null
	_rn_force_id = ""


func _on_rn_reroll() -> void:
	if _rn_base == null or _rn_force_id == "" or _rn_edit == null:
		return
	_rn_error.text = ""
	if _rn_base.has_method("do_reroll_force_name"):
		_rn_edit.text = str(_rn_base.do_reroll_force_name(_rn_force_id))
	else:
		_rn_edit.text = str(ArmyNames.mint_unique({}))


func _on_rn_confirm() -> void:
	if _rn_base == null or _rn_force_id == "" or _rn_edit == null:
		return
	var cleaned: String = ArmyNames.sanitize(_rn_edit.text)
	if cleaned == "":
		_rn_error.text = "Name cannot be blank."
		return
	_rn_error.text = ""
	if _rn_base.has_method("do_rename_force"):
		_rn_base.do_rename_force(_rn_force_id, cleaned)
	_close_rename_army_dialog()


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
			_fc_info_lbl.text = "Deposit into your stock in this province (needs de jure or a holding)."
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
	var before: Array = []
	if base.has_method("get_building_garrison"):
		before = base.get_building_garrison(building, spot)
	var after: Array = GlobalUnits.clone_units(before)
	GlobalUnits.subtract_units(after, out_units)
	var emptying := GlobalUnits.fighting_men(after) <= 0 and GlobalUnits.fighting_men(before) > 0
	var militia_off = base.has_method("settlement_militia_fights") \
		and not base.settlement_militia_fights(building)
	var is_settlement = base.has_method("is_settlement_building") \
		and base.is_settlement_building(building)
	var owns := int(building.get("player_owner") if building.get("player_owner") != null else -1) \
		== int(base.my_pl_id)
	_close_deploy_panel()
	if emptying and militia_off and is_settlement and owns:
		_open_militia_enable_prompt({
			"kind": "sortie",
			"base": base,
			"building": building,
			"spot": spot,
			"out_units": out_units,
		})
		return
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

	# Owner field army can collect stored tax from this settlement (1 MP).
	if _fm_right_is_garrison and _fm_building != null \
			and _fm_base.has_method("can_collect_settlement_tax") \
			and _fm_base.has_method("settlement_tax_marks"):
		var coffer := int(_fm_base.settlement_tax_marks(_fm_building))
		if coffer > 0:
			var tax_mp := int(GlobalUnits.TAX_COLLECT_MP)
			var can_collect := bool(_fm_base.can_collect_settlement_tax(_fm_left_id, _fm_building))
			var collect_btn := Button.new()
			collect_btn.text = "Collect tax (%d marks, %d MP)" % [coffer, tax_mp]
			if not can_collect:
				var has_mp := true
				if _fm_base.has_method("force_has_movement"):
					has_mp = _fm_base.force_has_movement(_fm_left_id, tax_mp)
				if not has_mp:
					collect_btn.text = "Collect tax (need %d MP)" % tax_mp
				else:
					collect_btn.text = "Collect tax (unavailable)"
				collect_btn.disabled = true
			else:
				collect_btn.pressed.connect(_on_fm_collect_tax)
			_fm_body.add_child(collect_btn)
			_fm_body.add_child(HSeparator.new())

	# Settlement owner: militia resistance toggle.
	if _fm_right_is_garrison and _fm_building != null \
			and _fm_base.has_method("is_settlement_building") \
			and _fm_base.is_settlement_building(_fm_building) \
			and int(_fm_building.get("player_owner") if _fm_building.get("player_owner") != null else -1) \
				== int(_fm_base.my_pl_id):
		var fights := true
		if _fm_base.has_method("settlement_militia_fights"):
			fights = _fm_base.settlement_militia_fights(_fm_building)
		var mil_btn := Button.new()
		if fights:
			mil_btn.text = "Militia: will resist (click to stand down)"
		else:
			mil_btn.text = "Militia: stand down (click to resist)"
		mil_btn.pressed.connect(_on_fm_toggle_militia)
		_fm_body.add_child(mil_btn)
		var beaten := false
		if _fm_base.has_method("settlement_militia_beaten_this_season"):
			beaten = _fm_base.settlement_militia_beaten_this_season(_fm_building)
		if beaten:
			var beaten_lbl := Label.new()
			beaten_lbl.text = "Militia already fought this season — will not rise again until next season."
			beaten_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			beaten_lbl.custom_minimum_size = Vector2(480, 0)
			beaten_lbl.add_theme_font_size_override("font_size", 12)
			_fm_body.add_child(beaten_lbl)
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


func _on_fm_collect_tax() -> void:
	if _fm_base == null or _fm_building == null or _fm_left_id == "":
		return
	if _fm_base.has_method("do_collect_settlement_tax"):
		_fm_base.do_collect_settlement_tax(_fm_left_id, _fm_building)
	_rebuild_force_menu()


func _on_fm_toggle_militia() -> void:
	if _fm_base == null or _fm_building == null:
		return
	if not _fm_base.has_method("set_settlement_militia_fights"):
		return
	var cur := true
	if _fm_base.has_method("settlement_militia_fights"):
		cur = _fm_base.settlement_militia_fights(_fm_building)
	_fm_base.set_settlement_militia_fights(_fm_building, not cur)


func _ensure_militia_enable_prompt() -> void:
	if _mil_prompt != null:
		return
	_mil_prompt = PanelContainer.new()
	_mil_prompt.top_level = true
	_mil_prompt.z_index = 150
	_mil_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_mil_prompt.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Militia"
	title.add_theme_font_size_override("font_size", 16)
	_mil_prompt_lbl = Label.new()
	_mil_prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mil_prompt_lbl.custom_minimum_size = Vector2(360, 0)
	_mil_prompt_lbl.text = (
		"You are removing the last garrison from this settlement while militia "
		+ "stand down. Turn militia resistance back on?"
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var leave_btn := Button.new()
	leave_btn.text = "Leave militia off"
	leave_btn.pressed.connect(_on_mil_prompt_leave_off)
	var enable_btn := Button.new()
	enable_btn.text = "Enable militia"
	enable_btn.pressed.connect(_on_mil_prompt_enable)
	row.add_child(leave_btn)
	row.add_child(enable_btn)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_mil_prompt_lbl)
	vbox.add_child(row)
	margin.add_child(vbox)
	_mil_prompt.add_child(margin)
	add_child(_mil_prompt)


func _open_militia_enable_prompt(pending: Dictionary) -> void:
	_ensure_militia_enable_prompt()
	_mil_pending_transfer = pending
	_mil_prompt.visible = true
	_mil_prompt.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_mil_prompt.position = (vp - _mil_prompt.size) * 0.5


func _close_militia_enable_prompt() -> void:
	if _mil_prompt != null:
		_mil_prompt.visible = false
	_mil_pending_transfer = {}


func _on_mil_prompt_leave_off() -> void:
	var pending := _mil_pending_transfer.duplicate(true)
	_close_militia_enable_prompt()
	_execute_pending_garrison_empty(pending, false)


func _on_mil_prompt_enable() -> void:
	var pending := _mil_pending_transfer.duplicate(true)
	_close_militia_enable_prompt()
	_execute_pending_garrison_empty(pending, true)


func _execute_pending_garrison_empty(pending: Dictionary, enable_militia: bool) -> void:
	if pending.is_empty():
		return
	var base = pending.get("base")
	var building = pending.get("building")
	if base == null or building == null:
		return
	if enable_militia and base.has_method("set_settlement_militia_fights"):
		base.set_settlement_militia_fights(building, true)
	var kind := str(pending.get("kind", ""))
	if kind == "batch":
		base.request_batch_garrison_units.rpc_id(
			1,
			str(pending.get("left_id", "")),
			str(pending.get("building_key", "")),
			int(pending.get("spot", GlobalUnits.SPOT.FLAT)),
			pending.get("to_garrison", []),
			pending.get("from_garrison", []),
			pending.get("cargo_l2r", {}),
			pending.get("cargo_r2l", {})
		)
		var vips_l2r: Array = pending.get("vips_l2r", [])
		var vips_r2l: Array = pending.get("vips_r2l", [])
		var left_id := str(pending.get("left_id", ""))
		if not vips_l2r.is_empty():
			var vip_dest = base.garrison_force_id_for(building, base.vip_garrison_spot_for(building))
			base.do_transfer_vips(left_id, vip_dest, vips_l2r)
		if not vips_r2l.is_empty():
			for vid in vips_r2l:
				var v: Dictionary = base.get_vip(str(vid))
				if v.is_empty():
					continue
				var src_fid := str(v.get("force_id", ""))
				if src_fid != "":
					base.do_transfer_vips(src_fid, left_id, [str(vid)])
	elif kind == "sortie":
		base.do_sortie(
			building,
			int(pending.get("spot", GlobalUnits.SPOT.FLAT)),
			pending.get("out_units", [])
		)


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
		var emptying := GlobalUnits.fighting_men(garrison_after) <= 0 \
			and GlobalUnits.fighting_men(_fm_right_units()) > 0
		var militia_off = base.has_method("settlement_militia_fights") \
			and not base.settlement_militia_fights(bldg)
		var is_settlement = base.has_method("is_settlement_building") \
			and base.is_settlement_building(bldg)
		var owns := int(bldg.get("player_owner") if bldg.get("player_owner") != null else -1) \
			== int(base.my_pl_id)
		_close_force_menu()
		if emptying and militia_off and is_settlement and owns:
			_open_militia_enable_prompt({
				"kind": "batch",
				"base": base,
				"building": bldg,
				"left_id": left_id,
				"building_key": building_key,
				"spot": _fm_spot,
				"to_garrison": left_to_right,
				"from_garrison": right_to_left,
				"cargo_l2r": cargo_l2r,
				"cargo_r2l": cargo_r2l,
				"vips_l2r": vips_l2r,
				"vips_r2l": vips_r2l,
			})
			return
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
	if _fm_base.has_method("force_display_name"):
		return str(_fm_base.force_display_name(fid))
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
		refresh_ladder_tab()


func refresh_ladder_tab() -> void:
	if ladder_list == null:
		return
	for child in ladder_list.get_children():
		ladder_list.remove_child(child)
		child.queue_free()
	var base_map = parent_n
	if not is_instance_valid(base_map) or not base_map.has_method("get_player_ladder"):
		return
	var ladder: Dictionary = base_map.get_player_ladder()
	var entries: Array = ladder.get("entries", [])
	if entries.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No players"
		ladder_list.add_child(empty_lbl)
		return

	var sort_metric := _ladder_sort_metric
	if not PlayerLadder.METRICS.has(sort_metric):
		sort_metric = "fighting"
		_ladder_sort_metric = sort_metric

	var category_btns := [
		{"label": "Marks", "metric": "marks"},
		{"label": "Arms", "metric": "fighting"},
		{"label": "Grain", "metric": "grain"},
		{"label": "Dejure", "metric": "dejure"},
		{"label": "Defacto", "metric": "defacto"},
	]
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 6)
	for col in category_btns:
		var metric: String = str(col["metric"])
		var btn := Button.new()
		var active := metric == sort_metric
		btn.text = str(col["label"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = not active
		btn.disabled = active
		btn.pressed.connect(_on_ladder_sort_pressed.bind(metric))
		cat_row.add_child(btn)
	ladder_list.add_child(cat_row)
	ladder_list.add_child(HSeparator.new())

	var ordered: Array = entries.duplicate()
	ordered.sort_custom(func(a, b):
		var ranks_a: Dictionary = a.get("ranks", {})
		var ranks_b: Dictionary = b.get("ranks", {})
		var ra := int(ranks_a.get(sort_metric, 999))
		var rb := int(ranks_b.get(sort_metric, 999))
		if ra != rb:
			return ra < rb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)

	var my_id: int = int(base_map.my_pl_id) if base_map.get("my_pl_id") != null else -1
	for e in ordered:
		var ranks: Dictionary = e.get("ranks", {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var rank_lbl := Label.new()
		rank_lbl.text = "#%d" % int(ranks.get(sort_metric, 0))
		rank_lbl.custom_minimum_size = Vector2(48, 0)
		var name_lbl := Label.new()
		name_lbl.text = str(e.get("name", "?"))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_me := int(e.get("pid", -1)) == my_id
		if is_me:
			rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		row.add_child(rank_lbl)
		row.add_child(name_lbl)
		ladder_list.add_child(row)


func _on_ladder_sort_pressed(metric: String) -> void:
	if metric.is_empty() or metric == _ladder_sort_metric:
		return
	_ladder_sort_metric = metric
	refresh_ladder_tab()


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
	var ships := int(preview.get("ships", 0))
	if military_upkeep_lbl != null:
		military_upkeep_lbl.text = (
			"Projected upkeep: %d marks  (levies %d · sellswords %d · ships %d)"
			% [total, levy, sellsword, ships]
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
		var fleet_id := str(entry.get("fleet_id", ""))
		if fleet_id != "":
			name_btn.pressed.connect(_on_military_fleet_pressed.bind(fleet_id))
		else:
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


func _on_military_fleet_pressed(fleet_id: String) -> void:
	if not is_instance_valid(parent_n):
		return
	var fleet = parent_n.get_fleet_by_id(fleet_id) if parent_n.has_method("get_fleet_by_id") else null
	if fleet == null:
		return
	if parent_n.has_method("jump_camera_to"):
		parent_n.jump_camera_to(fleet.global_position + Vector2(32, 16))
	if fleet.is_controllable_by(parent_n.my_pl_id):
		open_fleet_menu(parent_n, fleet)


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


func _make_prov_rich_label(initial: String) -> RichTextLabel:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = initial
	return lbl


func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _bb_emphasis(plain: String, delta: int) -> String:
	var escaped := _bb_escape(plain)
	if delta > 0:
		return "[b][color=%s]%s[/color][/b]" % [_PROV_SURPLUS_COLOR, escaped]
	if delta < 0:
		return "[b][color=%s]%s[/color][/b]" % [_PROV_DEFICIT_COLOR, escaped]
	return "[b]%s[/b]" % escaped


func _bb_signed(n: int) -> String:
	return _bb_emphasis("%+d" % n, n)


func _bb_ratio(have: int, need: int) -> String:
	return _bb_emphasis("%d / %d" % [have, need], have - need)


func _bb_coverage_pct(cov_pct: float) -> String:
	var delta := 0
	if cov_pct > 100.0:
		delta = 1
	elif cov_pct < 100.0:
		delta = -1
	return _bb_emphasis("%.0f%%" % cov_pct, delta)


func _ensure_province_levy_widgets() -> void:
	if _prov_happiness_lbl != null or province_tab_root == null:
		return
	province_tab_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# Content lives inside a ScrollContainer — size to children, don't expand-fill.
	province_tab_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_prov_manage_root = VBoxContainer.new()
	_prov_manage_root.add_theme_constant_override("separation", 6)
	_prov_manage_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_manage_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	province_tab_root.add_child(_prov_manage_root)
	_prov_manage_root.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prov_manage_root.add_child(columns)

	# Left: holding status (overview — no farming).
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_STOP
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	columns.add_child(left)

	_prov_stock_lbl = _make_prov_section_label("Stock: —")
	left.add_child(_prov_stock_lbl)
	_prov_prod_lbl = _make_prov_rich_label("Next season production: —")
	left.add_child(_prov_prod_lbl)
	_prov_smith_lbl = _make_prov_rich_label("Blacksmith: —")
	left.add_child(_prov_smith_lbl)
	left.add_child(HSeparator.new())
	_prov_happiness_lbl = Label.new()
	_prov_happiness_lbl.text = "Happiness: —"
	_prov_happiness_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_happiness_lbl)
	_prov_ration_lbl = Label.new()
	_prov_ration_lbl.text = "Rations: —"
	_prov_ration_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_ration_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_ration_lbl)
	_prov_ration_row = HBoxContainer.new()
	_prov_ration_row.add_theme_constant_override("separation", 4)
	_prov_ration_row.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_ration_row)
	_prov_ration_btns.clear()
	var ration_group := ButtonGroup.new()
	for level in [
		GlobalUnits.RATION.NONE,
		GlobalUnits.RATION.QUARTER,
		GlobalUnits.RATION.HALF,
		GlobalUnits.RATION.NORMAL,
		GlobalUnits.RATION.DOUBLE,
		GlobalUnits.RATION.QUADRUPLE,
	]:
		var btn := Button.new()
		btn.text = GlobalUnits.ration_name(level)
		btn.toggle_mode = true
		btn.button_group = ration_group
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_connect_ration_button(btn, level)
		_prov_ration_row.add_child(btn)
		_prov_ration_btns[level] = btn
	_prov_tax_lbl = Label.new()
	_prov_tax_lbl.text = "Tax: —"
	_prov_tax_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_tax_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_tax_lbl)
	_prov_tax_row = HBoxContainer.new()
	_prov_tax_row.add_theme_constant_override("separation", 4)
	_prov_tax_row.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(_prov_tax_row)
	_prov_tax_btns.clear()
	var tax_group := ButtonGroup.new()
	for level in GlobalUnits.TAX_LEVELS:
		var tbtn := Button.new()
		tbtn.text = GlobalUnits.tax_name(level)
		tbtn.toggle_mode = true
		tbtn.button_group = tax_group
		tbtn.mouse_filter = Control.MOUSE_FILTER_STOP
		_connect_tax_button(tbtn, level)
		_prov_tax_row.add_child(tbtn)
		_prov_tax_btns[level] = tbtn

	# Right: economy labor pool + sliders (not grain/horses).
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.35
	columns.add_child(right)

	_prov_labor_lbl = _make_prov_rich_label("Labor pool: —")
	right.add_child(_prov_labor_lbl)
	_prov_labor_box = VBoxContainer.new()
	_prov_labor_box.add_theme_constant_override("separation", 6)
	_prov_labor_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_labor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_prov_labor_box)

	_ensure_province_farming_widgets()
	_ensure_province_army_widgets()
	_ensure_province_shipyard_widgets()
	if province_sub_tabs != null:
		province_sub_tabs.set_tab_title(0, "Overview")
		province_sub_tabs.set_tab_title(_prov_farming_tab_index, "Farming")
		province_sub_tabs.set_tab_title(_prov_army_tab_index, "Army")
		province_sub_tabs.set_tab_title(_prov_shipyard_tab_index, "Shipyard")


func _ensure_province_farming_widgets() -> void:
	if _prov_farming_manage_root != null or province_farming_root == null:
		return
	province_farming_root.mouse_filter = Control.MOUSE_FILTER_STOP
	province_farming_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_prov_farming_manage_root = VBoxContainer.new()
	_prov_farming_manage_root.add_theme_constant_override("separation", 8)
	_prov_farming_manage_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_farming_manage_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	province_farming_root.add_child(_prov_farming_manage_root)

	var title := Label.new()
	title.text = "Fields & agriculture"
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_farming_manage_root.add_child(title)

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
	_prov_farming_manage_root.add_child(fields_row)

	_prov_farm_stock_lbl = _make_prov_section_label("Stock: —")
	_prov_farming_manage_root.add_child(_prov_farm_stock_lbl)
	_prov_agri_lbl = _make_prov_rich_label("Agriculture: —")
	_prov_farming_manage_root.add_child(_prov_agri_lbl)

	_prov_farming_manage_root.add_child(HSeparator.new())

	var labor_title := Label.new()
	labor_title.text = "Farm labor"
	labor_title.add_theme_font_size_override("font_size", 16)
	labor_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_farming_manage_root.add_child(labor_title)

	_prov_farm_labor_lbl = _make_prov_rich_label("Workers: —")
	_prov_farming_manage_root.add_child(_prov_farm_labor_lbl)
	_prov_farm_labor_box = VBoxContainer.new()
	_prov_farm_labor_box.add_theme_constant_override("separation", 6)
	_prov_farm_labor_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_farm_labor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prov_farming_manage_root.add_child(_prov_farm_labor_box)


func _ensure_province_army_widgets() -> void:
	if _prov_levy_lbl != null or province_army_root == null:
		return
	province_army_root.mouse_filter = Control.MOUSE_FILTER_STOP
	province_army_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Levy & recruitment"
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	province_army_root.add_child(title)

	_prov_levy_lbl = Label.new()
	_prov_levy_lbl.text = "Levy: —"
	_prov_levy_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_levy_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	province_army_root.add_child(_prov_levy_lbl)

	_prov_weapons_lbl = Label.new()
	_prov_weapons_lbl.text = "Weapons: —"
	_prov_weapons_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_weapons_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	province_army_root.add_child(_prov_weapons_lbl)

	_prov_recruit_btn = Button.new()
	_prov_recruit_btn.text = "Recruit army"
	_prov_recruit_btn.pressed.connect(_on_province_recruit_pressed)
	province_army_root.add_child(_prov_recruit_btn)


func _ensure_province_shipyard_widgets() -> void:
	if _prov_shipyard_info != null or province_shipyard_root == null:
		return
	province_shipyard_root.mouse_filter = Control.MOUSE_FILTER_STOP
	province_shipyard_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Shipyard"
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	province_shipyard_root.add_child(title)

	_prov_shipyard_info = Label.new()
	_prov_shipyard_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_shipyard_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_shipyard_info.text = "Cost per ship: —"
	province_shipyard_root.add_child(_prov_shipyard_info)

	_prov_shipyard_stock = Label.new()
	_prov_shipyard_stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prov_shipyard_stock.mouse_filter = Control.MOUSE_FILTER_STOP
	_prov_shipyard_stock.text = "Available: —"
	province_shipyard_root.add_child(_prov_shipyard_stock)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var lbl := Label.new()
	lbl.text = "Ships to build:"
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(lbl)
	_prov_ships_spin = SpinBox.new()
	_prov_ships_spin.min_value = 1
	_prov_ships_spin.max_value = 100
	_prov_ships_spin.value = 1
	_prov_ships_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prov_ships_spin.value_changed.connect(_on_prov_ships_spin_changed)
	row.add_child(_prov_ships_spin)
	province_shipyard_root.add_child(row)

	_prov_ships_build_btn = Button.new()
	_prov_ships_build_btn.text = "Build transport ships"
	_prov_ships_build_btn.pressed.connect(_on_province_build_ships_pressed)
	province_shipyard_root.add_child(_prov_ships_build_btn)


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
			# Producing weapon counts: bold green (same surplus style as production).
			craft_bits.append(
				"%s %s" % [_bb_emphasis(str(amt), amt), _bb_escape(GlobalUnits.weapon_name(str(wk)))]
			)
	var craft_txt := (", ".join(craft_bits)) if not craft_bits.is_empty() else "nothing"
	var lines: PackedStringArray = []
	lines.append(
		"Blacksmith: %d / %d workers · next season crafts %s"
		% [workers, cap, craft_txt]
	)
	match bottleneck:
		"none":
			lines.append("No smith buildings.")
		"no_workers":
			lines.append("Idle — assign workers (labor cost depends on recipe).")
		"idle_recipe":
			lines.append("Workers assigned but no craft recipe set (open the smith).")
		"materials":
			lines.append(
				"Materials limit crafts: labor could make %s, stock allows %s. Add wood/iron."
				% [_bb_emphasis(str(labor_crafts), labor_crafts), _bb_emphasis(str(crafts), crafts)]
			)
		"can_expand":
			var more_weapons := int(free_slots / people_per)
			lines.append(
				"Not at full capacity — %d free slots (~%s more weapons if materials allow)."
				% [free_slots, _bb_emphasis(str(more_weapons), more_weapons)]
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


func _connect_ration_button(btn: Button, level: int) -> void:
	btn.pressed.connect(func(): _on_prov_ration_pressed(level))


func _on_prov_ration_pressed(level: int) -> void:
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	if parent_n.has_method("do_set_holding_ration"):
		parent_n.do_set_holding_ration(selected_province_id, level)


func _connect_tax_button(btn: Button, level: int) -> void:
	btn.pressed.connect(func(): _on_prov_tax_pressed(level))


func _on_prov_tax_pressed(level: int) -> void:
	if selected_province_id == "" or not is_instance_valid(parent_n):
		return
	if parent_n.has_method("do_set_holding_tax"):
		parent_n.do_set_holding_tax(selected_province_id, level)


func _update_prov_tax_buttons(holding: Dictionary, has_holding: bool) -> void:
	if _prov_tax_row == null:
		return
	_prov_tax_row.visible = has_holding
	if _prov_tax_lbl != null:
		_prov_tax_lbl.visible = has_holding
	if not has_holding:
		return
	var level := int(holding.get("tax", GlobalUnits.TAX_DEFAULT))
	var stored := int(holding.get("tax_marks_stored", 0))
	var next_m := int(holding.get("tax_marks_next", 0))
	var next_wallet := int(holding.get("tax_marks_next_wallet", 0))
	var next_coffer := int(holding.get("tax_marks_next_coffer", 0))
	var castle_b := int(holding.get("tax_castle_bonus_next", 0))
	var auto_w := bool(holding.get("tax_auto_wallet", false))
	var rate := GlobalUnits.tax_marks_per_person(level)
	if _prov_tax_lbl != null:
		if auto_w:
			var castle_txt := (" · castle +%d" % castle_b) if castle_b > 0 else ""
			_prov_tax_lbl.text = (
				"Tax: %s (%d/person) · next +%d to wallet%s · stored %d in coffers"
				% [GlobalUnits.tax_name(level), rate, next_wallet, castle_txt, stored]
			)
		else:
			_prov_tax_lbl.text = (
				"Tax: %s (%d/person) · next +%d to coffers (no de jure) · stored %d (collect with army)"
				% [GlobalUnits.tax_name(level), rate, next_coffer if next_coffer > 0 else next_m, stored]
			)
	for lv in _prov_tax_btns:
		var btn: Button = _prov_tax_btns[lv]
		btn.set_pressed_no_signal(int(lv) == level)


func _update_prov_ration_buttons(holding: Dictionary, has_holding: bool) -> void:
	if _prov_ration_row == null:
		return
	_prov_ration_row.visible = has_holding
	if _prov_ration_lbl != null:
		_prov_ration_lbl.visible = has_holding
	if not has_holding:
		return
	var requested := int(holding.get("ration", GlobalUnits.RATION_DEFAULT))
	var effective := int(holding.get("ration_effective", requested))
	var affordable := bool(holding.get("ration_affordable", true))
	var avail := int(holding.get("ration_grain_available", 0))
	var promised := GlobalUnits.ration_grain_need(
		int(holding.get("population", 0)), requested
	)
	if _prov_ration_lbl != null:
		if affordable:
			_prov_ration_lbl.text = (
				"Rations: %s · need %d grain / %d available after seed+armies"
				% [GlobalUnits.ration_name(requested), promised, avail]
			)
			_prov_ration_lbl.remove_theme_color_override("font_color")
		else:
			_prov_ration_lbl.text = (
				"Rations: %s promised, will feed as %s · need %d / have %d (seed+armies first)"
				% [
					GlobalUnits.ration_name(requested),
					GlobalUnits.ration_name(effective),
					promised,
					avail,
				]
			)
			_prov_ration_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	var red := Color(1.0, 0.35, 0.3)
	for level in _prov_ration_btns:
		var btn: Button = _prov_ration_btns[level]
		btn.set_pressed_no_signal(int(level) == requested)
		if int(level) == requested and not affordable:
			btn.add_theme_color_override("font_color", red)
			btn.add_theme_color_override("font_pressed_color", red)
			btn.add_theme_color_override("font_hover_color", red)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_pressed_color")
			btn.remove_theme_color_override("font_hover_color")


func _labor_category_label(cat: String) -> String:
	match cat:
		"grain": return "Grain fields"
		"horses": return "Horse pastures"
		"wood": return "Woodcutters"
		"stone": return "Stone quarries"
		"iron": return "Iron mines"
		"silver": return "Silver mines"
		"blacksmith": return "Blacksmiths"
		"castle": return "Castle construction"
	return cat.capitalize()


func _clear_labor_box(box: VBoxContainer) -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild_labor_sliders(holding: Dictionary) -> void:
	_clear_labor_box(_prov_labor_box)
	_clear_labor_box(_prov_farm_labor_box)
	_prov_labor_sliders.clear()
	_prov_labor_panels.clear()
	if holding.is_empty():
		return
	var pop := int(holding.get("population", 0))
	var labor: Dictionary = holding.get("labor", {})
	var caps: Dictionary = holding.get("labor_caps", {})
	var farm_cats: Array = []
	var econ_cats: Array = []
	if bool(holding.get("has_grain_work", false)) or int(holding.get("planted_grain", 0)) > 0 \
			or int(holding.get("grain_fields", 0)) > 0:
		farm_cats.append("grain")
	if bool(holding.get("has_horse_work", false)):
		farm_cats.append("horses")
	if bool(holding.get("has_wood", false)) or int(caps.get("wood", 0)) > 0:
		econ_cats.append("wood")
	if bool(holding.get("has_stone", false)) or int(caps.get("stone", 0)) > 0:
		econ_cats.append("stone")
	if bool(holding.get("has_iron", false)) or int(caps.get("iron", 0)) > 0:
		econ_cats.append("iron")
	if bool(holding.get("has_silver", false)) or int(caps.get("silver", 0)) > 0:
		econ_cats.append("silver")
	if bool(holding.get("has_blacksmith", false)) or int(caps.get("blacksmith", 0)) > 0:
		econ_cats.append("blacksmith")
	if bool(holding.get("has_castle_work", false)) or int(caps.get("castle", 0)) > 0:
		econ_cats.append("castle")
	_prov_labor_updating = true
	for cat in farm_cats:
		_add_labor_slider_row(str(cat), labor, caps, pop, holding, _prov_farm_labor_box)
	for cat in econ_cats:
		_add_labor_slider_row(str(cat), labor, caps, pop, holding, _prov_labor_box)
	_prov_labor_updating = false
	_apply_labor_focus()


func _labor_slider_panel_style(focused: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if focused:
		sb.bg_color = Color(0.22, 0.16, 0.08, 0.75)
		sb.border_color = Color(0.92, 0.72, 0.28, 1.0)
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0.12, 0.08, 0.05, 0.55)
		sb.border_color = Color(0.35, 0.25, 0.14, 0.85)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	return sb


func _apply_labor_focus() -> void:
	if _labor_focus_category == "":
		return
	var cat := _labor_focus_category
	_labor_focus_category = "" # one-shot
	if _prov_labor_panels.has(cat):
		var panel: PanelContainer = _prov_labor_panels[cat]
		panel.add_theme_stylebox_override("panel", _labor_slider_panel_style(true))
		call_deferred("_scroll_to_labor_panel", panel)
	if _prov_labor_sliders.has(cat):
		var slider: HSlider = _prov_labor_sliders[cat]
		if is_instance_valid(slider):
			slider.call_deferred("grab_focus")


func _scroll_to_labor_panel(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or province_tab_root == null:
		return
	var scroll = province_tab_root.get_parent()
	if not (scroll is ScrollContainer):
		return
	var sc := scroll as ScrollContainer
	var target_y := panel.global_position.y - sc.global_position.y + sc.scroll_vertical
	sc.scroll_vertical = maxi(0, int(target_y) - 24)


func _add_labor_slider_row(
	cat: String,
	labor: Dictionary,
	caps: Dictionary,
	pop: int,
	holding: Dictionary = {},
	parent_box: VBoxContainer = null
) -> void:
	if parent_box == null:
		return
	var cur := int(labor.get(cat, 0))
	var cap := int(caps.get(cat, 0))
	var others := 0
	for other_cat in GlobalUnits.LABOR_CATEGORIES:
		if str(other_cat) == cat:
			continue
		others += int(labor.get(other_cat, 0))
	# Headroom for raising this category (free people vs building/farm cap).
	var max_v := maxi(0, mini(pop - others, cap))
	# Allow dragging down from current even when there is no free headroom.
	var slider_max := maxi(max_v, cur)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _labor_slider_panel_style(false))
	_prov_labor_panels[cat] = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_STOP
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := _make_prov_rich_label("")
	# Show assigned / need (farm) or building-cap (economy); slider max may be lower if people are scarce.
	var suffix := ""
	if max_v <= 0 and cap > 0:
		suffix = " (no free people)"
	elif max_v < cap and cur >= max_v:
		suffix = " (people cap %d)" % max_v
	if cat == "blacksmith":
		var preview: Dictionary = holding.get("economy_preview", {})
		var smith: Dictionary = preview.get("blacksmith", {})
		var crafts := int(smith.get("crafts", 0))
		var free_slots := int(smith.get("free_slots", 0))
		var bn := str(smith.get("bottleneck", ""))
		match bn:
			"full":
				suffix += " · full (%d crafts)" % crafts
			"materials":
				suffix += " · materials limit (%d crafts)" % crafts
			"can_expand":
				suffix += " · %d free · %d crafts" % [free_slots, crafts]
			"idle_recipe":
				suffix += " · set recipe"
			"no_workers":
				suffix += " · no workers"
			_:
				if cap > 0:
					suffix += " · %d crafts" % crafts
	var ratio_bb: String
	if cat == "grain":
		ratio_bb = _bb_ratio(cur, int(holding.get("grain_labor_need", cap)))
	elif cat == "horses":
		ratio_bb = _bb_ratio(cur, int(holding.get("horse_labor_need", cap)))
	else:
		ratio_bb = "%d/%d" % [cur, cap]
	lbl.text = "%s %s%s" % [_bb_escape(_labor_category_label(cat)), ratio_bb, _bb_escape(suffix)]
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)
	slider_row.mouse_filter = Control.MOUSE_FILTER_STOP
	slider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = slider_max
	slider.step = 1
	slider.value = clampi(cur, 0, slider_max)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 18
	# Editable to lower workers even at 0 headroom; locked only when already 0 and no free people.
	slider.editable = slider_max > 0
	_connect_labor_slider(slider, cat)
	slider_row.add_child(slider)
	var max_btn := Button.new()
	max_btn.text = "MAX"
	# MAX only when there is real headroom — not when 0 workers and nowhere to go.
	max_btn.disabled = max_v <= 0 or max_v <= cur
	max_btn.focus_mode = Control.FOCUS_NONE
	max_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_connect_labor_max_button(max_btn, slider, max_v)
	slider_row.add_child(max_btn)
	col.add_child(lbl)
	col.add_child(slider_row)
	panel.add_child(col)
	parent_box.add_child(panel)
	_prov_labor_sliders[cat] = slider


func _connect_labor_slider(slider: HSlider, cat: String) -> void:
	# Separate function so `cat` is captured per slider (not loop-shared).
	slider.value_changed.connect(func(v: float): _on_prov_labor_category_changed(cat, v))


func _connect_labor_max_button(btn: Button, slider: HSlider, max_v: int) -> void:
	btn.pressed.connect(func():
		if max_v <= 0:
			return
		slider.value = max_v
	)


func _set_province_sub_tab_hidden(tab_index: int, hidden: bool) -> void:
	if province_sub_tabs == null:
		return
	if tab_index < 0 or tab_index >= province_sub_tabs.get_tab_count():
		return
	province_sub_tabs.set_tab_hidden(tab_index, hidden)
	if hidden and province_sub_tabs.current_tab == tab_index:
		province_sub_tabs.current_tab = 0


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
		if _prov_farming_manage_root != null:
			_prov_farming_manage_root.visible = false
		_set_province_sub_tab_hidden(_prov_farming_tab_index, true)
		_set_province_sub_tab_hidden(_prov_army_tab_index, true)
		_set_province_sub_tab_hidden(_prov_shipyard_tab_index, true)
		hide_populate_idle_popup()
		return
	province_tab_name.text = data.get("name", "—")
	province_tab_status.text = "Status: %s" % data.get("status_name", "—")
	province_tab_owner.text = "Owner: %s" % data.get("owner_name", "—")
	province_tab_defacto.text = "De facto: %s" % data.get("defacto_name", "—")
	province_tab_dejure.text = "De jure: %s" % data.get("dejure_name", "—")
	province_tab_population.text = "Population: %s (next: %s)" % [data.get("population_has", 0), data.get("population_will", 0)]
	if data.get("viewer_has_holding", false):
		if bool(data.get("tax_auto_wallet", false)):
			var castle_b := int(data.get("tax_castle_bonus_next", 0))
			var castle_bit := (" (incl. castle +%d)" % castle_b) if castle_b > 0 else ""
			province_tab_income.text = "Tax next: %s → wallet%s · stored %s" % [
				data.get("tax_marks_next_wallet", data.get("marks_will", 0)),
				castle_bit,
				data.get("tax_marks_stored", 0),
			]
		else:
			province_tab_income.text = "Tax next: %s → coffers (no de jure) · stored %s" % [
				data.get("tax_marks_next_coffer", data.get("tax_marks_next", data.get("marks_will", 0))),
				data.get("tax_marks_stored", 0),
			]
	elif data.get("viewer_has_dejure", false):
		province_tab_income.text = "Tax next: %s" % data.get("marks_will", 0)
	else:
		province_tab_income.text = "Tax: — (no holding)"

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
	if _prov_farming_manage_root != null:
		_prov_farming_manage_root.visible = can_manage
	_set_province_sub_tab_hidden(_prov_farming_tab_index, not can_manage)
	_set_province_sub_tab_hidden(_prov_army_tab_index, not can_manage)
	var can_ships := false
	if has_dejure and is_instance_valid(parent_n) and parent_n.has_method("province_coastal_towns_for"):
		can_ships = not parent_n.province_coastal_towns_for(parent_n.my_pl_id, province_id).is_empty()
	_set_province_sub_tab_hidden(_prov_shipyard_tab_index, not can_ships)
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
			if _prov_farm_stock_lbl != null:
				_prov_farm_stock_lbl.text = (
					"Stock: grain %d · horses %d · grain pot %.0f"
					% [
						int(holding.get("grain_stock", 0)),
						int(holding.get("horses", 0)),
						float(holding.get("grain_potential", 0.0)),
					]
				)
			var pop := int(holding.get("population", 0))
			var assigned := int(holding.get("labor_assigned", 0))
			var free_people := pop - assigned
			_prov_labor_lbl.text = (
				"Labor pool: %d / %d people assigned · free %s"
				% [assigned, pop, _bb_emphasis(str(free_people), free_people)]
			)
			var cov := float(holding.get("grain_coverage", 1.0)) * 100.0
			var grain_need := int(holding.get("grain_labor_need", 0))
			var horse_need := int(holding.get("horse_labor_need", 0))
			var labor_map: Dictionary = holding.get("labor", {})
			var grain_have := int(labor_map.get("grain", 0))
			var horse_have := int(labor_map.get("horses", 0))
			if _prov_farm_labor_lbl != null:
				_prov_farm_labor_lbl.text = (
					"Grain workers %s · Horse workers %s"
					% [_bb_ratio(grain_have, grain_need), _bb_ratio(horse_have, horse_need)]
				)
			var people_per := int(holding.get("people_per_grain_field", GlobalUnits.people_per_grain_field(season_i)))
			if in_winter:
				var seed_each := int(holding.get("seed_per_field", GlobalUnits.GRAIN_SEED_PER_FIELD))
				var stock := int(holding.get("grain_stock", 0))
				var needed := grain_n * seed_each
				var by_labor := int(holding.get("sowable_by_labor", 0))
				var by_seed := grain_n
				if seed_each > 0:
					by_seed = mini(grain_n, int(stock / seed_each))
				var will_sow := mini(grain_n, mini(by_labor, by_seed))
				_prov_agri_lbl.text = (
					"Sow: %d fields · %d people/field · seed %s · labor can sow %s → %s will sow · horses %s"
					% [
						grain_n,
						people_per,
						_bb_ratio(stock, needed),
						_bb_emphasis(str(by_labor), by_labor - grain_n),
						_bb_emphasis(str(will_sow), will_sow - grain_n),
						_bb_ratio(horse_have, horse_need),
					]
				)
			else:
				_prov_agri_lbl.text = (
					"Agriculture: %d people/field · grain coverage %s (%s workers) · horse pastures %s"
					% [
						people_per,
						_bb_coverage_pct(cov),
						_bb_ratio(grain_have, grain_need),
						_bb_ratio(horse_have, horse_need),
					]
				)
			var wood_p := int(preview.get("wood", 0))
			var stone_p := int(preview.get("stone", 0))
			var iron_p := int(preview.get("iron", 0))
			var marks_p := int(preview.get("marks", 0))
			_prov_prod_lbl.text = (
				"Next season production: wood %s · stone %s · iron %s · marks %s"
				% [_bb_signed(wood_p), _bb_signed(stone_p), _bb_signed(iron_p), _bb_signed(marks_p)]
			)
			_prov_smith_lbl.text = _blacksmith_status_text(preview, holding)
			_rebuild_labor_sliders(holding)
			_update_prov_ration_buttons(holding, true)
			_update_prov_tax_buttons(holding, true)
		else:
			_prov_idle_field_count = 0
			_prov_fields_lbl.text = "Fields: (no settlement holding here)"
			if _prov_populate_idle_btn != null:
				_prov_populate_idle_btn.visible = false
				_prov_populate_idle_btn.disabled = true
			_prov_stock_lbl.text = "Stock: —"
			if _prov_farm_stock_lbl != null:
				_prov_farm_stock_lbl.text = "Stock: —"
			_prov_labor_lbl.text = "Labor pool: —"
			if _prov_farm_labor_lbl != null:
				_prov_farm_labor_lbl.text = "Workers: —"
			_prov_agri_lbl.text = "Agriculture: —"
			_prov_prod_lbl.text = "Next season production: —"
			_prov_smith_lbl.text = "Blacksmith: —"
			_rebuild_labor_sliders({})
			_update_prov_ration_buttons({}, false)
			_update_prov_tax_buttons({}, false)
			hide_populate_idle_popup()

	_prov_happiness_lbl.text = "Happiness: %.0f (avg of your settlements)" % float(data.get("happiness", 100))

	# Army tab
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
	_prov_recruit_btn.disabled = not has_dejure

	# Shipyard tab
	if can_ships:
		_fill_province_shipyard(base_map, province_id, holding)


func _fill_province_shipyard(base_map: Node, province_id: String, holding: Dictionary) -> void:
	if _prov_shipyard_info == null:
		return
	_prov_shipyard_info.text = (
		"Cost per ship: %d wood + %d marks.\nCapacity: %d men/ship. Movement: %d MP."
		% [
			GlobalUnits.TRANSPORT_SHIP_WOOD_COST,
			GlobalUnits.TRANSPORT_SHIP_MARKS_COST,
			GlobalUnits.TRANSPORT_SHIP_CAPACITY,
			GlobalUnits.TRANSPORT_SHIP_MP,
		]
	)
	var wood := int(holding.get("wood_stock", 0))
	var marks := 0
	if base_map.get("players") != null and base_map.players.has(base_map.my_pl_id):
		marks = int(base_map.players[base_map.my_pl_id].game_data.get("marks", 0))
	var towns: Array = []
	if base_map.has_method("province_coastal_towns_for"):
		towns = base_map.province_coastal_towns_for(base_map.my_pl_id, province_id)
	var max_by_wood := wood / GlobalUnits.TRANSPORT_SHIP_WOOD_COST if GlobalUnits.TRANSPORT_SHIP_WOOD_COST > 0 else 0
	var max_by_marks := marks / GlobalUnits.TRANSPORT_SHIP_MARKS_COST if GlobalUnits.TRANSPORT_SHIP_MARKS_COST > 0 else 0
	var max_affordable := maxi(0, mini(max_by_wood, max_by_marks))
	_prov_shipyard_stock.text = (
		"Coastal towns: %d · Available: %d wood · %d marks · can afford %d ship(s)"
		% [towns.size(), wood, marks, max_affordable]
	)
	if _prov_ships_spin != null:
		_prov_ships_spin.max_value = maxi(1, max_affordable) if max_affordable > 0 else 1
		if int(_prov_ships_spin.value) > int(_prov_ships_spin.max_value):
			_prov_ships_spin.value = _prov_ships_spin.max_value
	_refresh_prov_ships_build_btn(max_affordable)


func _refresh_prov_ships_build_btn(max_affordable: int = -1) -> void:
	if _prov_ships_build_btn == null or _prov_ships_spin == null:
		return
	var count := int(_prov_ships_spin.value)
	if max_affordable < 0:
		max_affordable = int(_prov_ships_spin.max_value)
	_prov_ships_build_btn.disabled = count < 1 or max_affordable < 1 or count > max_affordable
	_prov_ships_build_btn.text = "Build %d transport ship%s" % [count, "" if count == 1 else "s"]


func _on_prov_ships_spin_changed(_value: float) -> void:
	_refresh_prov_ships_build_btn()


func _on_province_build_ships_pressed() -> void:
	if not is_instance_valid(parent_n) or selected_province_id == "":
		return
	if _prov_ships_spin == null:
		return
	var count := int(_prov_ships_spin.value)
	if count < 1:
		return
	if parent_n.has_method("do_build_transport_ships"):
		parent_n.do_build_transport_ships(selected_province_id, count)


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


func open_battle_menu(
	base_map,
	attacker_id: String,
	defender_army_id: String,
	building: Node,
	landing_fleet_id: String = ""
) -> void:
	_close_siege_prompt()
	_ensure_battle_menu()
	_bt_base = base_map
	_bt_attacker_id = attacker_id
	_bt_defender_id = defender_army_id
	_bt_building = building
	_bt_landing_fleet_id = landing_fleet_id
	_rebuild_battle_menu()


func _close_battle_menu() -> void:
	if _bt_panel != null:
		_bt_panel.visible = false
	_bt_base = null
	_bt_attacker_id = ""
	_bt_defender_id = ""
	_bt_building = null
	_bt_landing_fleet_id = ""


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
	var militia_men := 0
	var settlement_mp := 0
	if _bt_building != null:
		if _bt_base.has_method("get_settlement_defense_preview") \
				and _bt_base.has_method("is_settlement_building") \
				and _bt_base.is_settlement_building(_bt_building):
			var preview: Dictionary = _bt_base.get_settlement_defense_preview(
				_bt_building, _bt_attacker_id
			)
			def_str = int(preview.get("strength", 0))
			def_men = int(preview.get("men", 0))
			militia_men = int(preview.get("militia_men", 0))
			if _bt_base.get("SETTLEMENT_BATTLE_MP_COST") != null:
				settlement_mp = int(_bt_base.SETTLEMENT_BATTLE_MP_COST)
		else:
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
		if _bt_landing_fleet_id != "" and _bt_base.has_method("get_landing_defender_battle_strength"):
			def_str = _bt_base.get_landing_defender_battle_strength(_bt_defender_id, _bt_attacker_id)
		else:
			def_str = GlobalUnits.fighting_strength(def_units)
		def_men = GlobalUnits.fighting_men(def_units)
		if _bt_base.has_method("force_display_name") and _bt_base.forces.has(_bt_defender_id):
			def_name = str(_bt_base.force_display_name(_bt_defender_id))
		else:
			def_name = "Enemy army"
		_bt_title.text = "Landing assault" if _bt_landing_fleet_id != "" else "Battle"

	var atk_name := "Your army"
	if _bt_base.has_method("force_display_name") and _bt_base.forces.has(_bt_attacker_id):
		atk_name = str(_bt_base.force_display_name(_bt_attacker_id))

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
	if militia_men > 0:
		them.text = "%s\n%d fighting · strength %d\n(includes %d militia)" % [
			def_name, def_men, def_str, militia_men
		]
	else:
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

	if _bt_landing_fleet_id != "":
		var land_lbl := Label.new()
		land_lbl.text = "Landing assault: shore defenders fight at ×%.1f. Costs %d ship MP." % [
			GlobalUnits.LANDING_DEFENDER_BONUS, GlobalUnits.TRANSPORT_LANDING_MP
		]
		land_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		land_lbl.custom_minimum_size = Vector2(360, 0)
		land_lbl.add_theme_font_size_override("font_size", 12)
		_bt_body.add_child(land_lbl)
	elif settlement_mp > 0:
		var mil_lbl := Label.new()
		mil_lbl.text = "Settlement assault costs %d MP. Militia rise from the population if they resist." % settlement_mp
		mil_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mil_lbl.custom_minimum_size = Vector2(360, 0)
		mil_lbl.add_theme_font_size_override("font_size", 12)
		_bt_body.add_child(mil_lbl)

	var hint := Label.new()
	if _bt_landing_fleet_id != "":
		hint.text = (
			"Strength is modified by luck when you attack. "
			+ "Win to land survivors on the shore; lose and the landing force is wiped. "
			+ "Stand ground cancels (no MP spent)."
		)
	elif settlement_mp > 0:
		hint.text = (
			"Strength is modified by luck when you attack. "
			+ "Stand ground cancels (no MP spent, militia stay home)."
		)
	else:
		hint.text = "Strength is modified by luck when you attack. Stand ground leaves both armies in place."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(360, 0)
	hint.add_theme_font_size_override("font_size", 12)
	_bt_body.add_child(hint)

	_bt_body.add_child(HSeparator.new())

	var attack_btn := Button.new()
	attack_btn.text = "Attack"
	if settlement_mp > 0:
		attack_btn.text = "Attack (%d MP)" % settlement_mp
		if _bt_base.has_method("force_has_movement") \
				and not _bt_base.force_has_movement(_bt_attacker_id, settlement_mp):
			attack_btn.disabled = true
			attack_btn.text = "Attack (need %d MP)" % settlement_mp
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
	var landing_fleet := _bt_landing_fleet_id
	_close_battle_menu()
	base.do_battle_attack(atk, def, building, landing_fleet)


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
	var is_settlement = type_ == GlobalStuff.BUILDING_TYPE.TOWN or type_ == GlobalStuff.BUILDING_TYPE.VILLAGE
	var raid_mp := int(base_map.RAID_MP_COST) if base_map.get("RAID_MP_COST") != null else 4
	var capt_mp := int(base_map.CAPTURE_MP_COST) if base_map.get("CAPTURE_MP_COST") != null else 2
	var raze_mp := int(base_map.RAZE_MP_COST) if base_map.get("RAZE_MP_COST") != null else 8
	var has_raid_mp = base_map.force_has_movement(force_id, raid_mp) if base_map.has_method("force_has_movement") else true
	var has_capt_mp = base_map.force_has_movement(force_id, capt_mp) if base_map.has_method("force_has_movement") else true
	var has_raze_mp = base_map.force_has_movement(force_id, raze_mp) if base_map.has_method("force_has_movement") else true

	var loot = base_map.compute_raid_loot(building)
	var raze_loot = base_map.compute_raze_loot(building) if base_map.has_method("compute_raze_loot") else int(floor(float(loot) * 1.5))
	var coffer := 0
	if base_map.has_method("settlement_tax_marks"):
		coffer = int(base_map.settlement_tax_marks(building))
	var can_raid = base_map.can_raid_building(building)
	var can_raze = base_map.can_raze_building(building) if base_map.has_method("can_raze_building") else false
	var is_razed = base_map.is_building_razed(building) if base_map.has_method("is_building_razed") else false
	var no_pop = is_settlement and int(building.get("population") if building.get("population") != null else 0) <= 0

	var capt_btn := Button.new()
	capt_btn.text = "Capture (%d MP)" % capt_mp
	capt_btn.disabled = not has_capt_mp
	if not has_capt_mp:
		capt_btn.text = "Capture (need %d MP)" % capt_mp
	capt_btn.pressed.connect(_on_ba_capture)
	_ba_body.add_child(capt_btn)

	var raid_btn := Button.new()
	if coffer > 0 and loot > coffer:
		raid_btn.text = "Raid (%d marks incl. %d tax, %d MP)" % [loot, coffer, raid_mp]
	elif coffer > 0:
		raid_btn.text = "Raid (%d tax marks, %d MP)" % [loot, raid_mp]
	else:
		raid_btn.text = "Raid (%d marks, %d MP)" % [loot, raid_mp]
	raid_btn.disabled = not can_raid or loot <= 0 or not has_raid_mp
	if is_razed:
		raid_btn.text = "Raid (razed)"
		raid_btn.disabled = true
	elif no_pop:
		raid_btn.text = "Raid (no population)"
		raid_btn.disabled = true
	elif not can_raid:
		raid_btn.text = "Raid (already raided this season)"
	elif not has_raid_mp:
		raid_btn.text = "Raid (need %d MP)" % raid_mp
	raid_btn.pressed.connect(_on_ba_raid)
	_ba_body.add_child(raid_btn)

	if not is_castle:
		var raze_btn := Button.new()
		if raze_loot > 0:
			raze_btn.text = "Raze (%d marks, %d MP)" % [raze_loot, raze_mp]
		else:
			raze_btn.text = "Raze (%d MP)" % raze_mp
		raze_btn.disabled = not can_raze or not has_raze_mp
		if is_razed:
			raze_btn.disabled = true
			raze_btn.text = "Raze (already razed)"
		elif no_pop:
			raze_btn.disabled = true
			raze_btn.text = "Raze (no population)"
		elif not can_raze:
			raze_btn.disabled = true
			var last_raze := int(building.get_meta("last_raze_turn", -1))
			var cur_turn := int(base_map.turn) if base_map.get("turn") != null else -2
			if is_settlement and last_raze == cur_turn:
				raze_btn.text = "Raze (already razed this season)"
			else:
				raze_btn.text = "Raze"
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


func is_recruit_menu_open() -> bool:
	return _rc_panel != null and _rc_panel.visible


func _ensure_recruit_panel() -> void:
	if _rc_panel != null:
		return
	# Full-screen catcher so map/army clicks cannot steal focus while recruiting.
	_rc_blocker = ColorRect.new()
	_rc_blocker.name = "RecruitLevyBlocker"
	_rc_blocker.top_level = true
	_rc_blocker.z_index = 139
	_rc_blocker.color = Color(0, 0, 0, 0.4)
	_rc_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_rc_blocker.focus_mode = Control.FOCUS_ALL
	_rc_blocker.visible = false
	_rc_blocker.gui_input.connect(_on_recruit_blocker_gui_input)
	add_child(_rc_blocker)

	_rc_panel = PanelContainer.new()
	_rc_panel.name = "RecruitLevyPanel"
	_rc_panel.top_level = true
	_rc_panel.z_index = 140
	_rc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rc_panel.focus_mode = Control.FOCUS_ALL
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
	_rc_total_lbl = Label.new()
	_rc_total_lbl.text = "Selected: 0 / need %d" % GlobalUnits.MIN_SPLIT_MEN
	vbox.add_child(_rc_total_lbl)
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


func _on_recruit_blocker_gui_input(event: InputEvent) -> void:
	# Eat map clicks; keep the levy form open and focused.
	if event is InputEventMouseButton and event.pressed:
		if _rc_panel != null:
			_rc_panel.grab_focus()
		get_viewport().set_input_as_handled()


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
		spin.value_changed.connect(_on_recruit_spin_changed)
		row.add_child(spin)
		var max_btn := Button.new()
		max_btn.text = "MAX"
		max_btn.pressed.connect(_on_recruit_max_pressed.bind(ut))
		row.add_child(max_btn)
		_rc_body.add_child(row)
		_rc_spinboxes[ut] = spin

	_refresh_recruit_total()
	var vp := get_viewport().get_visible_rect().size
	_rc_blocker.size = vp
	_rc_blocker.position = Vector2.ZERO
	_rc_blocker.visible = true
	_rc_blocker.move_to_front()
	_rc_panel.visible = true
	_rc_panel.reset_size()
	_rc_panel.size = Vector2(minf(420, vp.x * 0.9), _rc_panel.get_combined_minimum_size().y)
	_rc_panel.position = (vp - _rc_panel.size) * 0.5
	_rc_panel.move_to_front()
	_rc_panel.grab_focus()
	# Prefer focusing the first usable spin so typing goes into the levy form.
	for ut in _rc_spinboxes:
		var spin: SpinBox = _rc_spinboxes[ut]
		if spin.max_value > 0.0:
			spin.get_line_edit().grab_focus()
			break


func _close_recruit_menu() -> void:
	if _rc_blocker != null:
		_rc_blocker.visible = false
	if _rc_panel != null:
		_rc_panel.visible = false
	_rc_base = null
	_rc_province_id = ""
	_rc_spinboxes.clear()


func _commit_recruit_spinboxes() -> void:
	for ut in _rc_spinboxes:
		var spin: SpinBox = _rc_spinboxes[ut]
		if spin == null or not is_instance_valid(spin):
			continue
		# Commit typed LineEdit text before reading .value (Godot focus quirk).
		spin.apply()


func _recruit_composition_from_spins() -> Array:
	_commit_recruit_spinboxes()
	var composition: Array = []
	for ut in _rc_spinboxes:
		var spin: SpinBox = _rc_spinboxes[ut]
		if spin == null or not is_instance_valid(spin):
			continue
		var cnt := int(spin.value)
		if cnt > 0:
			composition.append({"type": int(ut), "count": cnt})
	return composition


func _refresh_recruit_total(_v: float = 0.0) -> void:
	if _rc_total_lbl == null:
		return
	var total := 0
	for ut in _rc_spinboxes:
		var spin: SpinBox = _rc_spinboxes[ut]
		if spin == null or not is_instance_valid(spin):
			continue
		total += maxi(0, int(spin.value))
	_rc_total_lbl.text = "Selected: %d / need %d" % [total, GlobalUnits.MIN_SPLIT_MEN]


func _on_recruit_spin_changed(_v: float) -> void:
	_refresh_recruit_total()


func _on_recruit_max_pressed(ut: int) -> void:
	if not _rc_spinboxes.has(ut) or _rc_base == null or _rc_province_id == "":
		return
	var data: Dictionary = _rc_base.get_province_data(_rc_province_id)
	if data.is_empty():
		return
	_commit_recruit_spinboxes()
	var max_men := mini(int(data.get("levy_remaining", 0)), int(data.get("owned_population", 0)))
	var weapons: Dictionary = data.get("weapons", {})
	var used_by_others := 0
	for other_ut in _rc_spinboxes:
		if other_ut == ut:
			continue
		used_by_others += int(_rc_spinboxes[other_ut].value)
	var type_max := maxi(0, max_men - used_by_others)
	var cost: Dictionary = GlobalUnits.weapon_cost_for_type(ut)
	if not cost.is_empty():
		for k in cost:
			var per := int(cost[k])
			if per <= 0:
				continue
			type_max = mini(type_max, int(weapons.get(k, 0)) / per)
	_rc_spinboxes[ut].value = type_max
	_refresh_recruit_total()


func _on_recruit_confirm() -> void:
	var base = _rc_base
	var province_id := _rc_province_id
	if base == null or province_id == "":
		_close_recruit_menu()
		return
	var composition: Array = _recruit_composition_from_spins()
	var total := GlobalUnits.composition_total_men(composition)
	if total < GlobalUnits.MIN_SPLIT_MEN:
		show_info_popup("Need at least %d men (selected %d)" % [GlobalUnits.MIN_SPLIT_MEN, total])
		_refresh_recruit_total()
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
	# Keep the form open until the map accepts the raise (spawn tile, etc.).
	if base.do_recruit_levy(province_id, composition):
		_close_recruit_menu()
	else:
		_refresh_recruit_total()
		if _rc_info_lbl != null:
			_rc_info_lbl.text = "RAISE FAILED — check the popup near the cursor for the reason."


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
	var raid_mp := int(base_map.FIELD_RAID_MP_COST) if base_map.get("FIELD_RAID_MP_COST") != null else 2
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

func _ms_make_scroll_tab(tab_name: String) -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	tab.add_theme_constant_override("separation", 4)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	tab.add_child(scroll)
	tab.set_meta("body", body)
	return tab


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
	_ms_info_lbl.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_ms_info_lbl)
	_ms_tabs = TabContainer.new()
	_ms_tabs.custom_minimum_size = Vector2(560, 380)
	_ms_tabs.tab_changed.connect(_on_merchant_tab_changed)
	var buy_w := _ms_make_scroll_tab("Buy Weapons")
	_ms_buy_weapons_body = buy_w.get_meta("body")
	_ms_tabs.add_child(buy_w)
	var buy_m := _ms_make_scroll_tab("Buy Materials")
	_ms_buy_materials_body = buy_m.get_meta("body")
	_ms_tabs.add_child(buy_m)
	var sell_w := _ms_make_scroll_tab("Sell Weapons")
	_ms_sell_weapons_body = sell_w.get_meta("body")
	_ms_tabs.add_child(sell_w)
	var sell_m := _ms_make_scroll_tab("Sell Materials")
	_ms_sell_materials_body = sell_m.get_meta("body")
	_ms_tabs.add_child(sell_m)
	vbox.add_child(_ms_tabs)
	_ms_buy_total_lbl = Label.new()
	_ms_buy_total_lbl.text = "Buy total: 0 marks"
	vbox.add_child(_ms_buy_total_lbl)
	_ms_sell_total_lbl = Label.new()
	_ms_sell_total_lbl.text = "Sell payout: 0 marks"
	vbox.add_child(_ms_sell_total_lbl)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_close_merchant_shop)
	btn_row.add_child(cancel_btn)
	_ms_sell_btn = Button.new()
	_ms_sell_btn.text = "Sell"
	_ms_sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_sell_btn.pressed.connect(_on_merchant_sell_confirm)
	btn_row.add_child(_ms_sell_btn)
	_ms_buy_btn = Button.new()
	_ms_buy_btn.text = "Buy"
	_ms_buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_buy_btn.pressed.connect(_on_merchant_buy_confirm)
	btn_row.add_child(_ms_buy_btn)
	vbox.add_child(btn_row)
	margin.add_child(vbox)
	_ms_panel.add_child(margin)
	add_child(_ms_panel)
	_on_merchant_tab_changed(0)


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
	var info := "Trade in %s.\nYour marks: %d" % [pname, marks]
	if _ms_competition:
		info += "\nCompetition: 15% buy discount / sell bonus (2+ merchants here)"
	_ms_info_lbl.text = info

	var owned_w := GlobalUnits.empty_weapon_stock()
	var owned_m := GlobalUnits.empty_material_stock()
	if prov != null and base_map.players.has(base_map.my_pl_id):
		var pid: int = base_map.my_pl_id
		if prov.has_method("get_weapons_for"):
			owned_w = prov.get_weapons_for(pid)
		for k in GlobalUnits.MATERIAL_KEYS:
			if prov.has_method("get_player_material"):
				owned_m[k] = prov.get_player_material(pid, k)

	for child in _ms_buy_weapons_body.get_children():
		child.queue_free()
	_ms_buy_weapon_spinboxes.clear()
	for k in GlobalUnits.WEAPON_KEYS:
		_ms_add_shop_row(
			_ms_buy_weapons_body,
			_ms_buy_weapon_spinboxes,
			k,
			GlobalUnits.weapon_name(k),
			GlobalUnits.weapon_mark_price_discounted(k, _ms_competition),
			"buy",
			"weapon",
			9999
		)

	for child in _ms_buy_materials_body.get_children():
		child.queue_free()
	_ms_buy_material_spinboxes.clear()
	for k in GlobalUnits.MATERIAL_KEYS:
		_ms_add_shop_row(
			_ms_buy_materials_body,
			_ms_buy_material_spinboxes,
			k,
			GlobalUnits.material_name(k),
			GlobalUnits.material_mark_price_discounted(k, _ms_competition),
			"buy",
			"material",
			9999
		)

	for child in _ms_sell_weapons_body.get_children():
		child.queue_free()
	_ms_sell_weapon_spinboxes.clear()
	for k in GlobalUnits.WEAPON_KEYS:
		var have := maxi(0, int(owned_w.get(k, 0)))
		_ms_add_shop_row(
			_ms_sell_weapons_body,
			_ms_sell_weapon_spinboxes,
			k,
			"%s (own %d)" % [GlobalUnits.weapon_name(k), have],
			GlobalUnits.weapon_mark_sell_price(k, _ms_competition),
			"sell",
			"weapon",
			have
		)

	for child in _ms_sell_materials_body.get_children():
		child.queue_free()
	_ms_sell_material_spinboxes.clear()
	for k in GlobalUnits.MATERIAL_KEYS:
		var have := maxi(0, int(owned_m.get(k, 0)))
		_ms_add_shop_row(
			_ms_sell_materials_body,
			_ms_sell_material_spinboxes,
			k,
			"%s (own %d)" % [GlobalUnits.material_name(k), have],
			GlobalUnits.material_mark_sell_price(k, _ms_competition),
			"sell",
			"material",
			have
		)

	_refresh_merchant_totals()
	_ms_panel.visible = true
	_ms_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_ms_panel.size = Vector2(minf(720, vp.x * 0.9), minf(640, vp.y * 0.85))
	_ms_panel.position = (vp - _ms_panel.size) * 0.5
	if _ms_tabs != null:
		_on_merchant_tab_changed(_ms_tabs.current_tab)


func _on_merchant_tab_changed(tab: int) -> void:
	# Tabs 0–1 are Buy; 2–3 are Sell.
	var is_buy := tab < 2
	if _ms_buy_btn != null:
		_ms_buy_btn.visible = is_buy
	if _ms_sell_btn != null:
		_ms_sell_btn.visible = not is_buy
	if _ms_buy_total_lbl != null:
		_ms_buy_total_lbl.visible = is_buy
	if _ms_sell_total_lbl != null:
		_ms_sell_total_lbl.visible = not is_buy


func _ms_add_shop_row(
	body: VBoxContainer,
	spin_map: Dictionary,
	key: String,
	display_name: String,
	price: int,
	mode: String,
	kind: String,
	max_qty: int
) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = "%s — %d marks each" % [display_name, price]
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = maxi(0, max_qty)
	spin.step = 1
	spin.value = 0
	spin.custom_minimum_size = Vector2(90, 0)
	spin.value_changed.connect(_on_merchant_qty_changed)
	row.add_child(spin)
	var max_btn := Button.new()
	max_btn.text = "MAX"
	max_btn.pressed.connect(_on_merchant_max_pressed.bind(key, mode, kind))
	row.add_child(max_btn)
	body.add_child(row)
	spin_map[key] = spin


func _on_merchant_qty_changed(_value: float) -> void:
	_refresh_merchant_totals()


func _merchant_player_marks() -> int:
	if _ms_base == null or not _ms_base.players.has(_ms_base.my_pl_id):
		return 0
	return int(_ms_base.players[_ms_base.my_pl_id].game_data.get("marks", 0))


func _merchant_item_price(key: String, mode: String, kind: String) -> int:
	if mode == "sell":
		if kind == "material":
			return GlobalUnits.material_mark_sell_price(key, _ms_competition)
		return GlobalUnits.weapon_mark_sell_price(key, _ms_competition)
	if kind == "material":
		return GlobalUnits.material_mark_price_discounted(key, _ms_competition)
	return GlobalUnits.weapon_mark_price_discounted(key, _ms_competition)


func _merchant_buy_cost_excluding(exclude_key: String, exclude_kind: String) -> int:
	var total := 0
	for k in _ms_buy_weapon_spinboxes:
		if exclude_kind == "weapon" and k == exclude_key:
			continue
		var amt := int(_ms_buy_weapon_spinboxes[k].value)
		if amt > 0:
			total += GlobalUnits.weapon_mark_price_discounted(k, _ms_competition) * amt
	for k in _ms_buy_material_spinboxes:
		if exclude_kind == "material" and k == exclude_key:
			continue
		var amt := int(_ms_buy_material_spinboxes[k].value)
		if amt > 0:
			total += GlobalUnits.material_mark_price_discounted(k, _ms_competition) * amt
	return total


func _on_merchant_max_pressed(key: String, mode: String, kind: String) -> void:
	var spin_map: Dictionary
	if mode == "sell":
		spin_map = _ms_sell_material_spinboxes if kind == "material" else _ms_sell_weapon_spinboxes
	else:
		spin_map = _ms_buy_material_spinboxes if kind == "material" else _ms_buy_weapon_spinboxes
	if not spin_map.has(key):
		return
	if mode == "sell":
		spin_map[key].value = spin_map[key].max_value
		_refresh_merchant_totals()
		return
	var price := _merchant_item_price(key, mode, kind)
	if price <= 0:
		return
	var remaining := _merchant_player_marks() - _merchant_buy_cost_excluding(key, kind)
	var max_qty := maxi(0, remaining / price)
	spin_map[key].value = max_qty
	_refresh_merchant_totals()


func _refresh_merchant_totals() -> void:
	var buy_total := 0
	for k in _ms_buy_weapon_spinboxes:
		var amt := int(_ms_buy_weapon_spinboxes[k].value)
		if amt > 0:
			buy_total += GlobalUnits.weapon_mark_price_discounted(k, _ms_competition) * amt
	for k in _ms_buy_material_spinboxes:
		var amt := int(_ms_buy_material_spinboxes[k].value)
		if amt > 0:
			buy_total += GlobalUnits.material_mark_price_discounted(k, _ms_competition) * amt
	if _ms_buy_total_lbl != null:
		_ms_buy_total_lbl.text = "Buy total: %d marks" % buy_total
	var sell_total := 0
	for k in _ms_sell_weapon_spinboxes:
		var amt := int(_ms_sell_weapon_spinboxes[k].value)
		if amt > 0:
			sell_total += GlobalUnits.weapon_mark_sell_price(k, _ms_competition) * amt
	for k in _ms_sell_material_spinboxes:
		var amt := int(_ms_sell_material_spinboxes[k].value)
		if amt > 0:
			sell_total += GlobalUnits.material_mark_sell_price(k, _ms_competition) * amt
	if _ms_sell_total_lbl != null:
		_ms_sell_total_lbl.text = "Sell payout: %d marks" % sell_total


func _close_merchant_shop() -> void:
	if _ms_panel != null:
		_ms_panel.visible = false
	_ms_base = null
	_ms_merchant = null
	_ms_buy_weapon_spinboxes.clear()
	_ms_buy_material_spinboxes.clear()
	_ms_sell_weapon_spinboxes.clear()
	_ms_sell_material_spinboxes.clear()
	_ms_competition = false


func _ms_collect_cart(weapon_spins: Dictionary, material_spins: Dictionary) -> Dictionary:
	var weapons := GlobalUnits.empty_weapon_stock()
	var materials := GlobalUnits.empty_material_stock()
	var any := false
	for k in weapon_spins:
		var amt := int(weapon_spins[k].value)
		weapons[k] = amt
		if amt > 0:
			any = true
	for k in material_spins:
		var amt := int(material_spins[k].value)
		materials[k] = amt
		if amt > 0:
			any = true
	return {"weapons": weapons, "materials": materials, "any": any}


func _ms_clear_spinboxes(spin_map: Dictionary) -> void:
	for k in spin_map:
		spin_map[k].value = 0


func _ms_refresh_info_and_sell_stock() -> void:
	if _ms_base == null or _ms_merchant == null or not is_instance_valid(_ms_merchant):
		return
	if _ms_panel == null or not _ms_panel.visible:
		return
	var merchant := _ms_merchant
	var base = _ms_base
	var prov = merchant.get("province")
	var pname := "Province"
	if prov != null and prov.get("p_name") != null:
		pname = str(prov.p_name)
	_ms_competition = base.merchant_competition_in_province(prov)
	var marks := 0
	if base.players.has(base.my_pl_id):
		marks = int(base.players[base.my_pl_id].game_data.get("marks", 0))
	var info := "Trade in %s.\nYour marks: %d" % [pname, marks]
	if _ms_competition:
		info += "\nCompetition: 15% buy discount / sell bonus (2+ merchants here)"
	_ms_info_lbl.text = info

	# Preserve sell cart quantities while updating max/owned labels.
	var sell_w_vals := {}
	for k in _ms_sell_weapon_spinboxes:
		sell_w_vals[k] = int(_ms_sell_weapon_spinboxes[k].value)
	var sell_m_vals := {}
	for k in _ms_sell_material_spinboxes:
		sell_m_vals[k] = int(_ms_sell_material_spinboxes[k].value)

	var owned_w := GlobalUnits.empty_weapon_stock()
	var owned_m := GlobalUnits.empty_material_stock()
	if prov != null and base.players.has(base.my_pl_id):
		var pid: int = base.my_pl_id
		if prov.has_method("get_weapons_for"):
			owned_w = prov.get_weapons_for(pid)
		for k in GlobalUnits.MATERIAL_KEYS:
			if prov.has_method("get_player_material"):
				owned_m[k] = prov.get_player_material(pid, k)

	for child in _ms_sell_weapons_body.get_children():
		child.queue_free()
	_ms_sell_weapon_spinboxes.clear()
	for k in GlobalUnits.WEAPON_KEYS:
		var have := maxi(0, int(owned_w.get(k, 0)))
		_ms_add_shop_row(
			_ms_sell_weapons_body,
			_ms_sell_weapon_spinboxes,
			k,
			"%s (own %d)" % [GlobalUnits.weapon_name(k), have],
			GlobalUnits.weapon_mark_sell_price(k, _ms_competition),
			"sell",
			"weapon",
			have
		)
		if _ms_sell_weapon_spinboxes.has(k):
			_ms_sell_weapon_spinboxes[k].value = mini(int(sell_w_vals.get(k, 0)), have)

	for child in _ms_sell_materials_body.get_children():
		child.queue_free()
	_ms_sell_material_spinboxes.clear()
	for k in GlobalUnits.MATERIAL_KEYS:
		var have := maxi(0, int(owned_m.get(k, 0)))
		_ms_add_shop_row(
			_ms_sell_materials_body,
			_ms_sell_material_spinboxes,
			k,
			"%s (own %d)" % [GlobalUnits.material_name(k), have],
			GlobalUnits.material_mark_sell_price(k, _ms_competition),
			"sell",
			"material",
			have
		)
		if _ms_sell_material_spinboxes.has(k):
			_ms_sell_material_spinboxes[k].value = mini(int(sell_m_vals.get(k, 0)), have)

	# Refresh buy prices (competition) without wiping buy cart.
	var buy_w_vals := {}
	for k in _ms_buy_weapon_spinboxes:
		buy_w_vals[k] = int(_ms_buy_weapon_spinboxes[k].value)
	var buy_m_vals := {}
	for k in _ms_buy_material_spinboxes:
		buy_m_vals[k] = int(_ms_buy_material_spinboxes[k].value)

	for child in _ms_buy_weapons_body.get_children():
		child.queue_free()
	_ms_buy_weapon_spinboxes.clear()
	for k in GlobalUnits.WEAPON_KEYS:
		_ms_add_shop_row(
			_ms_buy_weapons_body,
			_ms_buy_weapon_spinboxes,
			k,
			GlobalUnits.weapon_name(k),
			GlobalUnits.weapon_mark_price_discounted(k, _ms_competition),
			"buy",
			"weapon",
			9999
		)
		if _ms_buy_weapon_spinboxes.has(k):
			_ms_buy_weapon_spinboxes[k].value = int(buy_w_vals.get(k, 0))

	for child in _ms_buy_materials_body.get_children():
		child.queue_free()
	_ms_buy_material_spinboxes.clear()
	for k in GlobalUnits.MATERIAL_KEYS:
		_ms_add_shop_row(
			_ms_buy_materials_body,
			_ms_buy_material_spinboxes,
			k,
			GlobalUnits.material_name(k),
			GlobalUnits.material_mark_price_discounted(k, _ms_competition),
			"buy",
			"material",
			9999
		)
		if _ms_buy_material_spinboxes.has(k):
			_ms_buy_material_spinboxes[k].value = int(buy_m_vals.get(k, 0))

	_refresh_merchant_totals()


func refresh_merchant_shop_if_open() -> void:
	_ms_refresh_info_and_sell_stock()


func _on_merchant_buy_confirm() -> void:
	var base = _ms_base
	var merchant = _ms_merchant
	var cart := _ms_collect_cart(_ms_buy_weapon_spinboxes, _ms_buy_material_spinboxes)
	var merchant_id := ""
	if merchant != null:
		merchant_id = String(merchant.name)
	if base == null or merchant_id == "":
		_close_merchant_shop()
		return
	if not cart["any"]:
		show_info_popup("Select items to buy")
		return
	_ms_clear_spinboxes(_ms_buy_weapon_spinboxes)
	_ms_clear_spinboxes(_ms_buy_material_spinboxes)
	_refresh_merchant_totals()
	base.do_buy_from_merchant(merchant_id, cart["weapons"], cart["materials"])


func _on_merchant_sell_confirm() -> void:
	var base = _ms_base
	var merchant = _ms_merchant
	var cart := _ms_collect_cart(_ms_sell_weapon_spinboxes, _ms_sell_material_spinboxes)
	var merchant_id := ""
	if merchant != null:
		merchant_id = String(merchant.name)
	if base == null or merchant_id == "":
		_close_merchant_shop()
		return
	if not cart["any"]:
		show_info_popup("Select items to sell")
		return
	_ms_clear_spinboxes(_ms_sell_weapon_spinboxes)
	_ms_clear_spinboxes(_ms_sell_material_spinboxes)
	_refresh_merchant_totals()
	base.do_sell_to_merchant(merchant_id, cart["weapons"], cart["materials"])


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


# --- Transport fleets -------------------------------------------------------

func _ensure_fleet_menu() -> void:
	if _fl_panel != null:
		return
	_fl_panel = PanelContainer.new()
	_fl_panel.top_level = true
	_fl_panel.z_index = 140
	_fl_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fl_panel.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Transport fleet"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_fleet_menu)
	header.add_child(title)
	header.add_child(close_btn)
	_fl_body = VBoxContainer.new()
	_fl_body.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_fl_body)
	margin.add_child(vbox)
	_fl_panel.add_child(margin)
	add_child(_fl_panel)


func open_fleet_menu(base_map: Node, fleet: Node2D) -> void:
	_ensure_fleet_menu()
	_fl_base = base_map
	_fl_fleet = fleet
	_rebuild_fleet_menu()


func _close_fleet_menu() -> void:
	if _fl_panel != null:
		_fl_panel.visible = false
	_fl_base = null
	_fl_fleet = null
	_fl_split_spin = null


func _rebuild_fleet_menu() -> void:
	if _fl_body == null or _fl_fleet == null or _fl_base == null:
		return
	for child in _fl_body.get_children():
		child.queue_free()
	var f := _fl_fleet
	if not is_instance_valid(f):
		_close_fleet_menu()
		return
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	info.text = "%d ships · capacity %d/%d men\nMovement: %d / %d\nUpkeep: %d marks/season" % [
		f.ship_count,
		f.men_aboard(),
		f.capacity(),
		f.movement_left,
		f.effective_max_mp(),
		f.ship_count * GlobalUnits.UPKEEP_TRANSPORT_SHIP,
	]
	_fl_body.add_child(info)
	_fl_body.add_child(HSeparator.new())

	var move_btn := Button.new()
	move_btn.text = "Move  (MP: %d)" % f.movement_left
	move_btn.disabled = f.movement_left <= 0
	move_btn.pressed.connect(_on_fl_move_pressed)
	_fl_body.add_child(move_btn)

	var aboard_hdr := Label.new()
	aboard_hdr.text = "Armies aboard"
	_fl_body.add_child(aboard_hdr)
	if f.aboard_force_ids.is_empty():
		var empty := Label.new()
		empty.text = "(none)"
		_fl_body.add_child(empty)
	else:
		for fid in f.aboard_force_ids:
			var btn := Button.new()
			var men := 0
			if _fl_base.forces.has(fid):
				men = GlobalUnits.total_men(_fl_base.forces[fid]["units"])
			btn.text = "%s — %d men" % [_fl_base.force_display_name(str(fid)), men]
			var can_open = _fl_base.get_force_controller(str(fid)) == _fl_base.my_pl_id \
					or GlobalUnits.men_of_owner(_fl_base.forces.get(fid, {}).get("units", []), _fl_base.my_pl_id) > 0
			btn.disabled = not can_open
			btn.pressed.connect(_on_fl_open_aboard_army.bind(str(fid)))
			_fl_body.add_child(btn)

	_fl_body.add_child(HSeparator.new())
	var split_row := HBoxContainer.new()
	var split_lbl := Label.new()
	split_lbl.text = "Split off ships:"
	split_row.add_child(split_lbl)
	_fl_split_spin = SpinBox.new()
	_fl_split_spin.min_value = 1
	_fl_split_spin.max_value = maxi(1, f.ship_count - 1)
	_fl_split_spin.value = 1
	_fl_split_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_row.add_child(_fl_split_spin)
	_fl_body.add_child(split_row)
	var split_btn := Button.new()
	split_btn.text = "Split fleet"
	split_btn.disabled = f.has_army_aboard() or f.ship_count < 2
	if f.has_army_aboard():
		split_btn.text = "Split (empty fleet first)"
	split_btn.pressed.connect(_on_fl_split_pressed)
	_fl_body.add_child(split_btn)

	var disband_btn := Button.new()
	disband_btn.text = "Disband fleet"
	disband_btn.disabled = f.has_army_aboard()
	disband_btn.pressed.connect(_on_fl_disband_pressed)
	_fl_body.add_child(disband_btn)

	_fl_panel.visible = true
	_fl_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_fl_panel.size = Vector2(minf(360, vp.x * 0.9), _fl_panel.get_combined_minimum_size().y)
	_fl_panel.position = (vp - _fl_panel.size) * 0.5


func _on_fl_move_pressed() -> void:
	var fleet := _fl_fleet
	var base = _fl_base
	_close_fleet_menu()
	if fleet != null and base != null:
		base.pathfinding.select_army(fleet)


func _on_fl_open_aboard_army(force_id: String) -> void:
	var base = _fl_base
	_close_fleet_menu()
	if base == null:
		return
	open_aboard_army_menu(base, force_id)


func _on_fl_split_pressed() -> void:
	if _fl_base == null or _fl_fleet == null or _fl_split_spin == null:
		return
	var n := int(_fl_split_spin.value)
	var fid := String(_fl_fleet.name)
	var base = _fl_base
	_close_fleet_menu()
	base.do_fleet_split(fid, n)


func _on_fl_disband_pressed() -> void:
	if _fl_base == null or _fl_fleet == null:
		return
	var fid := String(_fl_fleet.name)
	var base = _fl_base
	_close_fleet_menu()
	base.do_fleet_disband(fid)


func open_aboard_army_menu(base_map: Node, force_id: String) -> void:
	if base_map == null or not base_map.forces.has(force_id):
		return
	# Reuse army menu layout with a lightweight proxy node (not in the scene tree).
	var proxy := Node2D.new()
	proxy.set_script(preload("res://objects/overworld/army/army_map_unit/armiy_figure.gd"))
	proxy.base_map = base_map
	proxy.force_id = force_id
	proxy.player_owner = base_map.get_force_controller(force_id)
	proxy.movement_points = 0
	proxy.movement_left = 0
	_ensure_army_menu()
	_am_base = base_map
	_am_army = proxy
	_rebuild_army_menu()
	# Hide move/split for aboard; keep disband / inspect.
	for child in _am_body.get_children():
		if child is Button:
			var t := str(child.text)
			if t.begins_with("Move") or t.begins_with("Split"):
				child.visible = false
			elif t.begins_with("Disband"):
				child.disabled = base_map.get_force_controller(force_id) != base_map.my_pl_id
			elif t.begins_with("Deposit") or t.begins_with("Withdraw") or t.begins_with("Send"):
				child.disabled = true


func open_fleet_stack_picker(base_map: Node, stack: Array) -> void:
	_ensure_fleet_prompt()
	_clear_fleet_prompt()
	var title := Label.new()
	title.text = "Fleets on this tile"
	title.add_theme_font_size_override("font_size", 16)
	_fl_prompt_body.add_child(title)
	for f in stack:
		if f == null or not is_instance_valid(f):
			continue
		var btn := Button.new()
		var own := "?"
		if base_map.players.has(f.player_owner):
			own = str(base_map.players[f.player_owner].name_)
		btn.text = "%s — %d ships (%d/%d men)" % [
			own, f.ship_count, f.men_aboard(), f.capacity()
		]
		btn.pressed.connect(func():
			_close_fleet_prompt()
			if f.is_controllable_by(base_map.my_pl_id):
				open_fleet_menu(base_map, f)
			else:
				show_info_popup("Enemy transport fleet")
		)
		_fl_prompt_body.add_child(btn)
	_show_fleet_prompt()


func open_fleet_embark_picker(base_map: Node, army: Node2D, fleets: Array) -> void:
	_ensure_fleet_prompt()
	_clear_fleet_prompt()
	var title := Label.new()
	title.text = "Embark onto which fleet?"
	title.add_theme_font_size_override("font_size", 16)
	_fl_prompt_body.add_child(title)
	for f in fleets:
		if f == null or not is_instance_valid(f):
			continue
		var btn := Button.new()
		btn.text = "%d ships — %d/%d men (MP %d)" % [
			f.ship_count, f.men_aboard(), f.capacity(), f.movement_left
		]
		var fleet_ref: Node2D = f
		btn.pressed.connect(func():
			_close_fleet_prompt()
			open_fleet_embark_prompt(base_map, fleet_ref, army)
		)
		_fl_prompt_body.add_child(btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_fleet_prompt)
	_fl_prompt_body.add_child(cancel)
	_show_fleet_prompt()


func open_fleet_embark_prompt(base_map: Node, fleet: Node2D, army: Node2D) -> void:
	_ensure_fleet_prompt()
	_clear_fleet_prompt()
	var men := GlobalUnits.total_men(army.get_units()) if army.has_method("get_units") else 0
	var free_cap = fleet.free_capacity()
	var army_mp := int(army.movement_left)
	var fleet_mp := int(fleet.movement_left)
	var title := Label.new()
	title.text = "Embark army?"
	title.add_theme_font_size_override("font_size", 16)
	_fl_prompt_body.add_child(title)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	info.text = "Army: %d men (MP %d)\nFleet free space: %d (MP %d)\nCosts %d army MP + %d ship MP" % [
		men, army_mp, free_cap, fleet_mp,
		GlobalUnits.TRANSPORT_EMBARK_ARMY_MP, GlobalUnits.TRANSPORT_EMBARK_FLEET_MP
	]
	_fl_prompt_body.add_child(info)
	if men > free_cap:
		var warn := Label.new()
		warn.text = "Not enough space — split the army first."
		_fl_prompt_body.add_child(warn)
		var ok := Button.new()
		ok.text = "OK"
		ok.pressed.connect(_close_fleet_prompt)
		_fl_prompt_body.add_child(ok)
		_show_fleet_prompt()
		return
	if army_mp < GlobalUnits.TRANSPORT_EMBARK_ARMY_MP:
		var warn_a := Label.new()
		warn_a.text = "Not enough army movement points (need %d)." % GlobalUnits.TRANSPORT_EMBARK_ARMY_MP
		_fl_prompt_body.add_child(warn_a)
		var ok_a := Button.new()
		ok_a.text = "OK"
		ok_a.pressed.connect(_close_fleet_prompt)
		_fl_prompt_body.add_child(ok_a)
		_show_fleet_prompt()
		return
	if fleet_mp < GlobalUnits.TRANSPORT_EMBARK_FLEET_MP:
		var warn2 := Label.new()
		warn2.text = "Not enough ship movement points (need %d)." % GlobalUnits.TRANSPORT_EMBARK_FLEET_MP
		_fl_prompt_body.add_child(warn2)
		var ok2 := Button.new()
		ok2.text = "OK"
		ok2.pressed.connect(_close_fleet_prompt)
		_fl_prompt_body.add_child(ok2)
		_show_fleet_prompt()
		return
	if int(fleet.player_owner) != int(base_map.my_pl_id) \
			or int(army.get_controller()) != int(base_map.my_pl_id):
		var warn3 := Label.new()
		warn3.text = "Can only embark your own army onto your own fleet."
		_fl_prompt_body.add_child(warn3)
		var ok3 := Button.new()
		ok3.text = "OK"
		ok3.pressed.connect(_close_fleet_prompt)
		_fl_prompt_body.add_child(ok3)
		_show_fleet_prompt()
		return
	var row := HBoxContainer.new()
	var yes := Button.new()
	yes.text = "Embark"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func():
		_close_fleet_prompt()
		base_map.do_fleet_embark(String(fleet.name), str(army.force_id))
	)
	var no := Button.new()
	no.text = "Cancel"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(_close_fleet_prompt)
	row.add_child(yes)
	row.add_child(no)
	_fl_prompt_body.add_child(row)
	_show_fleet_prompt()


func open_fleet_disembark_prompt(base_map: Node, fleet: Node2D, land_cell: Vector2i) -> void:
	_ensure_fleet_prompt()
	_clear_fleet_prompt()
	var shore_army: Node2D = null
	if base_map.pathfinding != null and base_map.pathfinding.occupancy.has(land_cell):
		var occ: Node2D = base_map.pathfinding.occupancy[land_cell]
		if occ != null and not (occ.has_method("is_caravan") and occ.is_caravan()) \
				and not (occ.has_method("is_fleet") and occ.is_fleet()):
			shore_army = occ

	var title := Label.new()
	if shore_army == null:
		title.text = "Land army"
	elif base_map.are_friendly_players(fleet.get_controller(), shore_army.get_controller()):
		title.text = "Land / merge"
	else:
		title.text = "Landing assault"
	title.add_theme_font_size_override("font_size", 16)
	_fl_prompt_body.add_child(title)

	if fleet.aboard_force_ids.is_empty():
		var empty := Label.new()
		empty.text = "No armies aboard to land."
		_fl_prompt_body.add_child(empty)
		var ok := Button.new()
		ok.text = "OK" if shore_army == null else "Cancel"
		ok.pressed.connect(_close_fleet_prompt)
		_fl_prompt_body.add_child(ok)
		_show_fleet_prompt()
		return
	if fleet.movement_left < GlobalUnits.TRANSPORT_LANDING_MP:
		var warn := Label.new()
		warn.text = "Need %d ship MP to land." % GlobalUnits.TRANSPORT_LANDING_MP
		_fl_prompt_body.add_child(warn)
		var ok2 := Button.new()
		ok2.text = "OK"
		ok2.pressed.connect(_close_fleet_prompt)
		_fl_prompt_body.add_child(ok2)
		_show_fleet_prompt()
		return

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	if shore_army == null:
		info.text = "Choose an army to land (costs %d ship MP):" % GlobalUnits.TRANSPORT_LANDING_MP
	elif base_map.are_friendly_players(fleet.get_controller(), shore_army.get_controller()):
		info.text = "Choose an army to merge into the shore force (costs %d ship MP):" % GlobalUnits.TRANSPORT_LANDING_MP
	else:
		info.text = (
			"Choose an army to assault the shore (defender ×%.1f, costs %d ship MP):"
			% [GlobalUnits.LANDING_DEFENDER_BONUS, GlobalUnits.TRANSPORT_LANDING_MP]
		)
	_fl_prompt_body.add_child(info)

	for fid in fleet.aboard_force_ids:
		var btn := Button.new()
		var men := 0
		if base_map.forces.has(fid):
			men = GlobalUnits.total_men(base_map.forces[fid]["units"])
		btn.text = "%s — %d men" % [base_map.force_display_name(str(fid)), men]
		var force_id := str(fid)
		btn.pressed.connect(func():
			_close_fleet_prompt()
			_on_fleet_land_army_chosen(base_map, fleet, force_id, land_cell, shore_army)
		)
		_fl_prompt_body.add_child(btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_fleet_prompt)
	_fl_prompt_body.add_child(cancel)
	_show_fleet_prompt()


func _on_fleet_land_army_chosen(
	base_map: Node, fleet: Node2D, force_id: String, land_cell: Vector2i, shore_army: Node2D
) -> void:
	if shore_army == null:
		base_map.do_fleet_disembark(String(fleet.name), force_id, land_cell)
		return
	if base_map.are_friendly_players(fleet.get_controller(), shore_army.get_controller()):
		_ensure_fleet_prompt()
		_clear_fleet_prompt()
		var title := Label.new()
		title.text = "Merge landing army?"
		title.add_theme_font_size_override("font_size", 16)
		_fl_prompt_body.add_child(title)
		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(300, 0)
		info.text = "Merge into the shore army? Costs %d ship MP." % GlobalUnits.TRANSPORT_LANDING_MP
		_fl_prompt_body.add_child(info)
		var row := HBoxContainer.new()
		var yes := Button.new()
		yes.text = "Merge"
		yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		yes.pressed.connect(func():
			_close_fleet_prompt()
			base_map.do_fleet_landing_merge(String(fleet.name), force_id, str(shore_army.force_id))
		)
		var no := Button.new()
		no.text = "Cancel"
		no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		no.pressed.connect(_close_fleet_prompt)
		row.add_child(yes)
		row.add_child(no)
		_fl_prompt_body.add_child(row)
		_show_fleet_prompt()
		return
	open_battle_menu(base_map, force_id, str(shore_army.force_id), null, String(fleet.name))


func open_fleet_combine_prompt(
	base_map: Node, mover: Node2D, target: Node2D, dest_cell: Vector2i
) -> void:
	_ensure_fleet_prompt()
	_clear_fleet_prompt()
	var title := Label.new()
	title.text = "Fleets"
	title.add_theme_font_size_override("font_size", 16)
	_fl_prompt_body.add_child(title)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	info.text = "Combine into one fleet, or stack on the same tile?"
	_fl_prompt_body.add_child(info)
	var combine_btn := Button.new()
	combine_btn.text = "Combine fleets"
	combine_btn.pressed.connect(func():
		_close_fleet_prompt()
		# Combine absorbs mover into target (works when adjacent or stacked).
		base_map.do_fleet_combine(String(target.name), String(mover.name))
	)
	_fl_prompt_body.add_child(combine_btn)
	var stack_btn := Button.new()
	stack_btn.text = "Stack (same tile)"
	stack_btn.pressed.connect(func():
		_close_fleet_prompt()
		if base_map.pathfinding.get_army_cell(mover) != dest_cell:
			base_map.do_fleet_stack_move(String(mover.name), dest_cell)
	)
	_fl_prompt_body.add_child(stack_btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_fleet_prompt)
	_fl_prompt_body.add_child(cancel)
	_show_fleet_prompt()


func _ensure_fleet_prompt() -> void:
	if _fl_prompt != null:
		return
	_fl_prompt = PanelContainer.new()
	_fl_prompt.top_level = true
	_fl_prompt.z_index = 145
	_fl_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_fl_prompt.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_fl_prompt_body = VBoxContainer.new()
	_fl_prompt_body.add_theme_constant_override("separation", 8)
	margin.add_child(_fl_prompt_body)
	_fl_prompt.add_child(margin)
	add_child(_fl_prompt)


func _clear_fleet_prompt() -> void:
	if _fl_prompt_body == null:
		return
	for child in _fl_prompt_body.get_children():
		child.queue_free()


func _close_fleet_prompt() -> void:
	if _fl_prompt != null:
		_fl_prompt.visible = false
	_clear_fleet_prompt()


func _show_fleet_prompt() -> void:
	_fl_prompt.visible = true
	_fl_prompt.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_fl_prompt.size = Vector2(minf(360, vp.x * 0.9), _fl_prompt.get_combined_minimum_size().y)
	_fl_prompt.position = (vp - _fl_prompt.size) * 0.5
