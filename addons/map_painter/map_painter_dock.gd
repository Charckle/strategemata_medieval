@tool
extends Control

const MapPainterOps := preload("res://addons/map_painter/map_painter_ops.gd")

signal brush_changed
signal status_message(text: String)

enum Brush {
	OFF,
	TERRAIN,
	TERRAIN_ERASE,
	ROAD,
	ROAD_ERASE,
	FIELD,
	VILLAGE,
	TOWN,
	CASTLE,
	ECON_OPEN,
	ECON_STONE,
	ECON_IRON,
	ECON_SILVER,
	ECON_RANDOM,
	ECON_WOODCUTTER,
	ECON_STONEQUARRY,
	ECON_IRONMINE,
	ECON_SILVERMINE,
	ECON_BLACKSMITH,
	ERASE_OBJECT,
	SELECT_PROVINCE,
}

var brush: Brush = Brush.OFF
var terrain_atlas: Vector2i = Vector2i(0, 0)
var field_crop: int = 0
var player_owner: int = 0
var active_province_path: NodePath = NodePath()
var province_name_draft: String = "New Province"
var new_map_name: String = "new_map"
var new_map_folder: String = "res://maps/overworld/test_maps"

var _brush_option: OptionButton
var _terrain_option: OptionButton
var _crop_option: OptionButton
var _owner_spin: SpinBox
var _province_option: OptionButton
var _province_name_edit: LineEdit
var _map_name_edit: LineEdit
var _status: Label
var _plugin: EditorPlugin


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_build_ui()
	_emit_brush()


func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(root)

	var title := Label.new()
	title.text = "Map Painter"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Open a map scene (inherits o_base_map), then pick a brush."
	root.add_child(_status)

	root.add_child(_section("New map"))
	var map_row := HBoxContainer.new()
	root.add_child(map_row)
	_map_name_edit = LineEdit.new()
	_map_name_edit.text = new_map_name
	_map_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_name_edit.text_changed.connect(func(t): new_map_name = t)
	map_row.add_child(_map_name_edit)
	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.pressed.connect(_on_create_map)
	map_row.add_child(create_btn)

	root.add_child(_section("Brush"))
	_brush_option = OptionButton.new()
	var brush_items := [
		["Off", Brush.OFF],
		["Terrain", Brush.TERRAIN],
		["Erase terrain", Brush.TERRAIN_ERASE],
		["Road", Brush.ROAD],
		["Erase road", Brush.ROAD_ERASE],
		["Field", Brush.FIELD],
		["Village", Brush.VILLAGE],
		["Town (2×2)", Brush.TOWN],
		["Castle (2×2)", Brush.CASTLE],
		["Economy: open plot", Brush.ECON_OPEN],
		["Economy: stone deposit", Brush.ECON_STONE],
		["Economy: iron deposit", Brush.ECON_IRON],
		["Economy: silver deposit", Brush.ECON_SILVER],
		["Economy: random deposit", Brush.ECON_RANDOM],
		["Economy: woodcutter", Brush.ECON_WOODCUTTER],
		["Economy: stone quarry", Brush.ECON_STONEQUARRY],
		["Economy: iron mine", Brush.ECON_IRONMINE],
		["Economy: silver mine", Brush.ECON_SILVERMINE],
		["Economy: blacksmith", Brush.ECON_BLACKSMITH],
		["Erase object", Brush.ERASE_OBJECT],
		["Pick province (click building)", Brush.SELECT_PROVINCE],
	]
	for item in brush_items:
		_brush_option.add_item(item[0])
		_brush_option.set_item_metadata(_brush_option.item_count - 1, item[1])
	_brush_option.item_selected.connect(_on_brush_selected)
	root.add_child(_brush_option)

	root.add_child(_section("Terrain tile"))
	_terrain_option = OptionButton.new()
	for t in MapPainterOps.TERRAIN_TILES:
		var label: String = t["label"]
		if t["walkable"]:
			label += " *"
		_terrain_option.add_item(label)
		_terrain_option.set_item_metadata(_terrain_option.item_count - 1, t["atlas"])
	_terrain_option.item_selected.connect(func(i):
		terrain_atlas = _terrain_option.get_item_metadata(i)
		_emit_brush()
	)
	root.add_child(_terrain_option)

	root.add_child(_section("Field crop"))
	_crop_option = OptionButton.new()
	_crop_option.add_item("Idle", 0)
	_crop_option.add_item("Grain", 1)
	_crop_option.add_item("Horses", 2)
	_crop_option.item_selected.connect(func(i):
		field_crop = i
		_emit_brush()
	)
	root.add_child(_crop_option)

	root.add_child(_section("Player owner"))
	_owner_spin = SpinBox.new()
	_owner_spin.min_value = 0
	_owner_spin.max_value = 16
	_owner_spin.value = player_owner
	_owner_spin.value_changed.connect(func(v):
		player_owner = int(v)
		_emit_brush()
	)
	root.add_child(_owner_spin)

	root.add_child(_section("Active province"))
	_province_option = OptionButton.new()
	_province_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_province_option.item_selected.connect(_on_province_selected)
	root.add_child(_province_option)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh province list"
	refresh_btn.pressed.connect(refresh_provinces)
	root.add_child(refresh_btn)

	var pname_row := HBoxContainer.new()
	root.add_child(pname_row)
	_province_name_edit = LineEdit.new()
	_province_name_edit.text = province_name_draft
	_province_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_province_name_edit.text_changed.connect(func(t): province_name_draft = t)
	pname_row.add_child(_province_name_edit)
	var add_prov := Button.new()
	add_prov.text = "Add"
	add_prov.pressed.connect(_on_add_province)
	pname_row.add_child(add_prov)

	var sync_btn := Button.new()
	sync_btn.text = "Sync ownership → buildings"
	sync_btn.pressed.connect(_on_sync_ownership)
	root.add_child(sync_btn)

	var validate_btn := Button.new()
	validate_btn.text = "Validate map"
	validate_btn.pressed.connect(_on_validate)
	root.add_child(validate_btn)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "LMB paint · RMB erase (terrain/road/object) · Select a brush other than Off, then click the 2D viewport."
	root.add_child(help)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	return l


func set_status(text: String) -> void:
	if _status:
		_status.text = text
	status_message.emit(text)


func refresh_provinces() -> void:
	if _province_option == null or _plugin == null:
		return
	_province_option.clear()
	var map_root := _plugin.call("get_map_root") as Node
	if map_root == null:
		_province_option.add_item("(no map open)")
		active_province_path = NodePath()
		return
	var provinces := MapPainterOps.list_provinces(map_root)
	if provinces.is_empty():
		_province_option.add_item("(no provinces)")
		active_province_path = NodePath()
		return
	var select_i := 0
	for i in provinces.size():
		var p: Node = provinces[i]
		var label := "%s  [owner %s]" % [str(p.get("p_name")), str(p.get("player_owner"))]
		_province_option.add_item(label)
		_province_option.set_item_metadata(i, map_root.get_path_to(p))
		if map_root.get_path_to(p) == active_province_path:
			select_i = i
	_province_option.select(select_i)
	active_province_path = _province_option.get_item_metadata(select_i)
	_emit_brush()


func get_active_province(map_root: Node) -> Node:
	if map_root == null or active_province_path.is_empty():
		return null
	return map_root.get_node_or_null(active_province_path)


func select_province_node(map_root: Node, province: Node) -> void:
	if map_root == null or province == null:
		return
	active_province_path = map_root.get_path_to(province)
	refresh_provinces()


func _on_brush_selected(index: int) -> void:
	brush = _brush_option.get_item_metadata(index) as Brush
	_emit_brush()


func _on_province_selected(index: int) -> void:
	active_province_path = _province_option.get_item_metadata(index)
	_emit_brush()


func _emit_brush() -> void:
	brush_changed.emit()


func _on_create_map() -> void:
	var path := MapPainterOps.create_new_map_scene(new_map_folder, new_map_name)
	if path.is_empty():
		set_status("Failed to create map.")
		return
	EditorInterface.open_scene_from_path(path)
	set_status("Created and opened %s" % path)
	refresh_provinces()


func _on_add_province() -> void:
	var map_root := _plugin.call("get_map_root") as Node
	if map_root == null:
		set_status("Open a map scene first.")
		return
	MapPainterOps.ensure_tile_layers(map_root)
	var prov := MapPainterOps.create_province(map_root, province_name_draft, player_owner)
	active_province_path = map_root.get_path_to(prov)
	EditorInterface.mark_scene_as_unsaved()
	refresh_provinces()
	set_status("Added province '%s'. Select object brushes to paint into it." % province_name_draft)


func _on_sync_ownership() -> void:
	var map_root := _plugin.call("get_map_root") as Node
	var prov := get_active_province(map_root)
	if prov == null:
		set_status("No active province.")
		return
	prov.set("player_owner", player_owner)
	MapPainterOps.sync_province_ownership(prov)
	EditorInterface.mark_scene_as_unsaved()
	refresh_provinces()
	set_status("Synced ownership for '%s' → %d" % [str(prov.get("p_name")), player_owner])


func _on_validate() -> void:
	var map_root := _plugin.call("get_map_root") as Node
	if map_root == null:
		set_status("Open a map scene first.")
		return
	var issues := MapPainterOps.validate_map(map_root)
	if issues.is_empty():
		set_status("Validate: OK — no issues found.")
	else:
		set_status("Validate (%d):\n- %s" % [issues.size(), "\n- ".join(issues)])
