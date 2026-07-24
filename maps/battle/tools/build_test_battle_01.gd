extends SceneTree

## godot --headless --path . -s res://maps/battle/tools/build_test_battle_01.gd

const OUT_PATH := "res://maps/battle/test_battle_01/test_battle_01.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := _build()
	quit(0 if err == OK else 1)


func _build() -> Error:
	var board_ps: PackedScene = load("res://maps/battle/battle_board.tscn")
	var unit_ps: PackedScene = load("res://objects/battle/battle_unit_marker.tscn")
	var script: Script = load("res://maps/battle/test_battle_01/test_battle_01.gd")
	if board_ps == null or unit_ps == null or script == null:
		push_error("Failed to load board/unit/script resources")
		return ERR_CANT_OPEN

	var root: Node2D = board_ps.instantiate()
	root.name = "TestBattle01"
	root.set_script(script)
	get_root().add_child(root)

	# Force @onready resolution
	root.terrain_layer = root.get_node("Terrain")
	root.highlight = root.get_node("Highlight")
	root.camera = root.get_node("Camera2D")
	root.info_label = root.get_node("UI/InfoLabel")
	root.paint_sample_layout()

	var units_parent: Node2D = root.get_node("Units")
	var placements := [
		{"name": "Macemen_P1", "type": "Macemen", "owner": 1, "strength": 10, "cell": Vector2i(10, 48), "facing": 0.0},
		{"name": "Pikemen_P1", "type": "Pikemen", "owner": 1, "strength": 9, "cell": Vector2i(12, 48), "facing": 0.0},
		{"name": "Archer_P1", "type": "Archer", "owner": 1, "strength": 8, "cell": Vector2i(11, 50), "facing": 0.0},
		{"name": "Knights_P1", "type": "Knights", "owner": 1, "strength": 7, "cell": Vector2i(14, 49), "facing": 0.0},
		{"name": "Swordsmen_P2", "type": "Swordsmen", "owner": 2, "strength": 10, "cell": Vector2i(10, 12), "facing": 180.0},
		{"name": "Crossbowmen_P2", "type": "Crossbowmen", "owner": 2, "strength": 8, "cell": Vector2i(12, 11), "facing": 180.0},
		{"name": "Knights_P2", "type": "Knights", "owner": 2, "strength": 6, "cell": Vector2i(14, 12), "facing": 180.0},
		{"name": "Peasant_P2", "type": "Peasant", "owner": 2, "strength": 10, "cell": Vector2i(8, 13), "facing": 180.0},
	]
	for p in placements:
		var u: Node2D = unit_ps.instantiate()
		u.name = p["name"]
		units_parent.add_child(u)
		u.set("owner_id", p["owner"])
		u.set("unit_type", p["type"])
		u.set("strength", p["strength"])
		u.set("facing_degrees", p["facing"])
		u.set("cell", p["cell"])

	_set_owner_recursive(root, root)
	root.owner = null

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("pack failed: %s" % pack_err)
		return pack_err

	var save_err := ResourceSaver.save(packed, OUT_PATH)
	if save_err != OK:
		push_error("save failed: %s" % save_err)
		return save_err

	print("Wrote ", OUT_PATH, " used_cells=", root.terrain_layer.get_used_cells().size())
	return OK


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	# Instanced sub-scenes keep their own internal ownership.
	if node != owner_node and not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)
