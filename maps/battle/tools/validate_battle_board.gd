extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://maps/battle/test_battle_01/test_battle_01.tscn")
	var root: Node = scene.instantiate()
	get_root().add_child(root)
	await process_frame

	var layer: TileMapLayer = root.get_node("Terrain")
	var used := layer.get_used_cells().size()
	var samples := [Vector2i(0, 0), Vector2i(22, 20), Vector2i(30, 10), Vector2i(15, 12), Vector2i(33, 36)]
	print("used_cells=", used)
	for cell in samples:
		var data: TileData = layer.get_cell_tile_data(cell)
		if data == null:
			print(cell, " NO DATA")
			continue
		print(cell, " terrain=", data.get_custom_data("terrain"), " walkable=", data.get_custom_data("walkable"))

	var units := root.get_node("Units").get_children().size()
	print("units=", units)
	quit(0 if used == 2400 and units == 8 else 1)
