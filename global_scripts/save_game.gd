extends Node

## Named saves + separate autosave under user://saves/.
## Continue = last manual save (never autosave).

const SAVES_DIR := "user://saves"
const INDEX_PATH := "user://saves/index.json"
const AUTOSAVE_ID := "autosave"

## Active manual save id for this session (empty → Save becomes Save As).
var current_manual_id: String = ""
## Pending load consumed by the map on boot.
var pending_load: Dictionary = {}


func _ready() -> void:
	_ensure_dir()


func clear_session() -> void:
	current_manual_id = ""
	pending_load = {}


func has_pending_load() -> bool:
	return not pending_load.is_empty() and pending_load.get("map_path", "") != ""


func take_pending_load() -> Dictionary:
	var s := pending_load
	pending_load = {}
	return s


func begin_load(save_id: String) -> bool:
	var state := load_save_dict(save_id)
	if state.is_empty():
		return false
	var map_path := str(state.get("map_path", GlobalSet.TEST_MAP_01))
	if map_path.is_empty() or not ResourceLoader.exists(map_path):
		push_error("Save map missing: %s" % map_path)
		return false
	pending_load = state
	if save_id != AUTOSAVE_ID:
		current_manual_id = save_id
		_set_last_manual(save_id)
	else:
		current_manual_id = ""
	GlobalSet.clear_pending_game_setup()
	GlobalSet.load_saved_continue = false
	get_tree().change_scene_to_file(map_path)
	return true


func has_last_manual() -> bool:
	var id := get_last_manual_id()
	return id != "" and FileAccess.file_exists(_path_for(id))


func get_last_manual_id() -> String:
	var idx := _read_index()
	return str(idx.get("last_manual_id", ""))


func list_saves() -> Array:
	## Array of meta dicts, newest first. Includes autosave if present.
	_ensure_dir()
	var idx := _read_index()
	var entries: Dictionary = idx.get("entries", {})
	var out: Array = []
	for id in entries.keys():
		var meta: Dictionary = entries[id].duplicate(true) if entries[id] is Dictionary else {}
		meta["id"] = str(id)
		if FileAccess.file_exists(_path_for(str(id))):
			out.append(meta)
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


func load_save_dict(save_id: String) -> Dictionary:
	var path := _path_for(save_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func write_autosave(state: Dictionary) -> bool:
	return _write_save(AUTOSAVE_ID, "Autosave", state, true)


## Overwrite current manual save. Returns false if no current → caller should Save As.
func save_current(state: Dictionary) -> bool:
	if current_manual_id.is_empty() or current_manual_id == AUTOSAVE_ID:
		return false
	var idx := _read_index()
	var entries: Dictionary = idx.get("entries", {})
	var display := str(entries.get(current_manual_id, {}).get("display_name", "Save"))
	return _write_save(current_manual_id, display, state, false)


func save_as(display_name: String, state: Dictionary) -> String:
	var name_ := display_name.strip_edges()
	if name_.is_empty():
		name_ = "Save"
	var id := _mint_id(name_)
	if _write_save(id, name_, state, false):
		current_manual_id = id
		_set_last_manual(id)
		return id
	return ""


## Save As onto an existing manual id (overwrite confirmation already handled by UI).
func save_as_overwrite(save_id: String, display_name: String, state: Dictionary) -> bool:
	if save_id.is_empty() or save_id == AUTOSAVE_ID:
		return false
	var name_ := display_name.strip_edges()
	if name_.is_empty():
		name_ = str(_read_index().get("entries", {}).get(save_id, {}).get("display_name", "Save"))
	if _write_save(save_id, name_, state, false):
		current_manual_id = save_id
		_set_last_manual(save_id)
		return true
	return false


func rename_save(save_id: String, new_display_name: String) -> bool:
	if save_id == AUTOSAVE_ID:
		return false
	var name_ := new_display_name.strip_edges()
	if name_.is_empty():
		return false
	var idx := _read_index()
	var entries: Dictionary = idx.get("entries", {})
	if not entries.has(save_id):
		return false
	entries[save_id]["display_name"] = name_
	idx["entries"] = entries
	_write_index(idx)
	return true


func delete_save(save_id: String) -> bool:
	var path := _path_for(save_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var idx := _read_index()
	var entries: Dictionary = idx.get("entries", {})
	entries.erase(save_id)
	idx["entries"] = entries
	if str(idx.get("last_manual_id", "")) == save_id:
		idx["last_manual_id"] = _newest_manual_id(entries)
	_write_index(idx)
	if current_manual_id == save_id:
		current_manual_id = ""
	return true


func find_save_id_by_display_name(display_name: String) -> String:
	var want := display_name.strip_edges().to_lower()
	if want.is_empty():
		return ""
	var idx := _read_index()
	var entries: Dictionary = idx.get("entries", {})
	for id in entries.keys():
		if str(id) == AUTOSAVE_ID:
			continue
		if str(entries[id].get("display_name", "")).strip_edges().to_lower() == want:
			return str(id)
	return ""


func build_meta_from_state(state: Dictionary, display_name: String, is_autosave: bool) -> Dictionary:
	var lord := ""
	var players = state.get("players", {})
	var my_id := int(state.get("my_pl_id", 0))
	if players is Dictionary and players.has(str(my_id)):
		lord = str(players[str(my_id)].get("name_", ""))
	elif players is Dictionary and players.has(my_id):
		lord = str(players[my_id].get("name_", ""))
	if lord.is_empty() and players is Dictionary:
		for k in players.keys():
			var p = players[k]
			if p is Dictionary and int(p.get("type", -1)) == int(GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL):
				lord = str(p.get("name_", ""))
				break
	var season := int(state.get("season", 0))
	var season_name = GlobalStuff.get_season_name(season)
	return {
		"display_name": display_name,
		"is_autosave": is_autosave,
		"map_path": str(state.get("map_path", "")),
		"turn": int(state.get("turn", 0)),
		"season": season,
		"season_name": season_name,
		"year": int(state.get("year", 1100)),
		"lord_name": lord,
		"saved_at": int(Time.get_unix_time_from_system()),
	}


func _write_save(save_id: String, display_name: String, state: Dictionary, is_autosave: bool) -> bool:
	_ensure_dir()
	var out := state.duplicate(true)
	out["save_id"] = save_id
	var meta := build_meta_from_state(out, display_name, is_autosave)
	out["meta"] = meta
	var path := _path_for(save_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save: %s" % path)
		return false
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	var idx := _read_index()
	var entries: Dictionary = idx.get("entries", {})
	entries[save_id] = meta
	idx["entries"] = entries
	if not is_autosave:
		idx["last_manual_id"] = save_id
	_write_index(idx)
	return true


func _set_last_manual(save_id: String) -> void:
	var idx := _read_index()
	idx["last_manual_id"] = save_id
	_write_index(idx)


func _newest_manual_id(entries: Dictionary) -> String:
	var best_id := ""
	var best_t := -1
	for id in entries.keys():
		if str(id) == AUTOSAVE_ID:
			continue
		var t := int(entries[id].get("saved_at", 0))
		if t > best_t:
			best_t = t
			best_id = str(id)
	return best_id


func _mint_id(display_name: String) -> String:
	var slug := ""
	for ch in display_name.to_lower():
		var o := ch.unicode_at(0)
		if (o >= 97 and o <= 122) or (o >= 48 and o <= 57):
			slug += ch
		elif ch == " " or ch == "-" or ch == "_":
			slug += "_"
	if slug.is_empty():
		slug = "save"
	slug = slug.substr(0, 24)
	var id := "%s_%d" % [slug, int(Time.get_unix_time_from_system())]
	var n := 1
	while FileAccess.file_exists(_path_for(id)):
		id = "%s_%d_%d" % [slug, int(Time.get_unix_time_from_system()), n]
		n += 1
	return id


func _path_for(save_id: String) -> String:
	return "%s/%s.json" % [SAVES_DIR, save_id]


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)


func _read_index() -> Dictionary:
	_ensure_dir()
	if not FileAccess.file_exists(INDEX_PATH):
		return {"last_manual_id": "", "entries": {}}
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return {"last_manual_id": "", "entries": {}}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"last_manual_id": "", "entries": {}}
	if not parsed.has("entries") or not (parsed["entries"] is Dictionary):
		parsed["entries"] = {}
	return parsed


func _write_index(idx: Dictionary) -> void:
	_ensure_dir()
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save index")
		return
	file.store_string(JSON.stringify(idx, "\t"))
	file.close()
