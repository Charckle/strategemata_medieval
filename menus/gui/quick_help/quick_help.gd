extends Control

## First-run / reopenable quick guide. Fullscreen dim + multi-page panel.
## open() → browse pages → closed signal when dismissed.

signal closed

const DIALOG_SIZE := Vector2(640, 480)

const PAGES: Array = [
	{
		"title": "Overview",
		"body": (
			"You play a lord in a seasonal campaign. Each turn is one season "
			+ "(Winter → Spring → Summer → Autumn).\n\n"
			+ "Use the bottom bar for Map, Economy, War, Messages, and Settings. "
			+ "Click provinces, buildings, armies, and fleets on the map to manage them.\n\n"
			+ "Press End Turn when you are done. Seasons advance food, taxes, "
			+ "production, and upkeep.\n\n"
			+ "Win by leaving no non-allied rival lords in play "
			+ "(defeat them or bring them into alliance). "
			+ "Stay landless too long and you lose."
		),
	},
	{
		"title": "Economy",
		"body": (
			"Marks are your treasury. Grain feeds your people and armies.\n\n"
			+ "Open Economy to see your provinces. In a province you set tax and "
			+ "rations, assign field work (grain and horses), and manage buildings "
			+ "such as blacksmiths and merchants.\n\n"
			+ "If you hold de jure, tax goes straight to your wallet. Without de jure, "
			+ "it piles up in settlement coffers — collect it with an army. "
			+ "Low rations or harsh taxes hurt happiness and population; "
			+ "generous policy costs more grain or marks.\n\n"
			+ "Armed men and transport ships take seasonal upkeep. Miss pays and "
			+ "you get strikes, desertion, or sellswords leaving."
		),
	},
	{
		"title": "Warfare",
		"body": (
			"Levy peasants from your provinces, then arm them with weapons from "
			+ "stock (or buy / craft more). Hire sellswords when camps appear.\n\n"
			+ "Select an army and move it with left-click. Armies spend movement "
			+ "points each season. Move onto an enemy to fight, siege, or raid.\n\n"
			+ "War → Military shows your forces and upkeep. War → Diplomacy lets "
			+ "you send messages, trade, ask for passage, or form alliances "
			+ "(one message per lord per season).\n\n"
			+ "Garrisons hold castles; field armies take ground and collect taxes."
		),
	},
	{
		"title": "Caravans",
		"body": (
			"Caravans move cargo between your holdings: grain, weapons, horses, "
			+ "and other goods.\n\n"
			+ "Send one from Economy → Caravan (province to province), or from an "
			+ "army / loot menu when you have cargo to ship home.\n\n"
			+ "Caravans path toward their destination on the map. Enemy armies that "
			+ "reach them can capture or loot the cargo.\n\n"
			+ "Use caravans to feed distant armies, rearm provinces, or bring loot "
			+ "home — but protect valuable shipments."
		),
	},
	{
		"title": "Sea",
		"body": (
			"Coastal provinces with a shipyard can build transport ships "
			+ "(wood and marks). Ships form fleets on the water.\n\n"
			+ "Move an army next to your fleet to embark (costs army and fleet "
			+ "movement). Sail the fleet, then disembark onto a shore tile to land "
			+ "or attack.\n\n"
			+ "Each ship carries a limited number of men and pays seasonal upkeep. "
			+ "Fleets are how you cross seas and strike distant coasts."
		),
	},
	{
		"title": "Jousting",
		"body": (
			"Tourneys are optional contests you host or join.\n\n"
			+ "Open War → Diplomacy → Tourney. Hosting costs marks (the prize pool); "
			+ "guests pay an entry fee. Other lords may accept or refuse.\n\n"
			+ "When the tourney is fought, knights tilt in a short minigame. "
			+ "You can keep named knights on a roster for later events.\n\n"
			+ "You cannot end your turn while a tourney is in progress. "
			+ "Finish or resolve it first."
		),
	},
]

var _dialog: PanelContainer
var _title_lbl: Label
var _body_lbl: RichTextLabel
var _page_lbl: Label
var _back_btn: Button
var _next_btn: Button
var _close_btn: Button
var _page_idx := 0
var _built := false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func open(start_page: int = 0) -> void:
	if not _built:
		_build_ui()
	_page_idx = clampi(start_page, 0, PAGES.size() - 1)
	_refresh_page()
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog = PanelContainer.new()
	_dialog.custom_minimum_size = DIALOG_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.07, 0.98)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.05, 0.03, 0.015, 1)
	sb.set_corner_radius_all(4)
	_dialog.add_theme_stylebox_override("panel", sb)
	center.add_child(_dialog)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_bottom", 16)
	_dialog.add_child(m)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	m.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)

	var header_title := Label.new()
	header_title.text = "Quick guide"
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title.add_theme_font_size_override("font_size", 22)
	header.add_child(header_title)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(90, 32)
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 18)
	col.add_child(_title_lbl)

	_body_lbl = RichTextLabel.new()
	_body_lbl.bbcode_enabled = false
	_body_lbl.fit_content = false
	_body_lbl.scroll_active = true
	_body_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_lbl.custom_minimum_size = Vector2(0, 280)
	col.add_child(_body_lbl)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(100, 36)
	_back_btn.pressed.connect(_on_back_pressed)
	footer.add_child(_back_btn)

	_page_lbl = Label.new()
	_page_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_page_lbl)

	_next_btn = Button.new()
	_next_btn.text = "Next"
	_next_btn.custom_minimum_size = Vector2(100, 36)
	_next_btn.pressed.connect(_on_next_pressed)
	footer.add_child(_next_btn)


func _refresh_page() -> void:
	var page: Dictionary = PAGES[_page_idx]
	_title_lbl.text = str(page.get("title", ""))
	_body_lbl.text = str(page.get("body", ""))
	_page_lbl.text = "%d / %d" % [_page_idx + 1, PAGES.size()]
	_back_btn.disabled = _page_idx <= 0
	if _page_idx >= PAGES.size() - 1:
		_next_btn.text = "Done"
	else:
		_next_btn.text = "Next"


func _on_back_pressed() -> void:
	if _page_idx <= 0:
		return
	_page_idx -= 1
	_refresh_page()


func _on_next_pressed() -> void:
	if _page_idx >= PAGES.size() - 1:
		close()
		return
	_page_idx += 1
	_refresh_page()
