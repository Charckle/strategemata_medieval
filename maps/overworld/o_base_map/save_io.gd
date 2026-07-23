extends RefCounted
class_name MapSaveIO

## Full mid-turn serialize / restore for o_base_map.

const SAVE_VERSION := 1
const BUILDING_META_KEYS := [
	"militia_fights", "militia_loyal_to", "last_militia_battle_turn",
	"militia_in_field", "militia_raised_men", "last_raze_turn",
	"smoke_kind", "smoke_turn", "raze_seasons_left", "seat_destroyed",
]


static func export_state(map: Node) -> Dictionary:
	var map_path := str(map.scene_file_path)
	if map_path.is_empty():
		map_path = GlobalSet.TEST_MAP_01
	var year := int(map.START_YEAR) + int(map.turn) / 4
	return {
		"version": SAVE_VERSION,
		"map_path": map_path,
		"world_seed": int(map.world_seed),
		"season": int(map.season),
		"turn": int(map.turn),
		"year": year,
		"my_pl_id": int(map.my_pl_id),
		"alliances": _stringify_keys(map.alliances.duplicate(true)),
		"players": _export_players(map.players),
		"counters": {
			"next_runtime_force": int(map._next_runtime_force),
			"next_vip_id": int(map._next_vip_id),
			"next_vip_trade_id": int(map._next_vip_trade_id),
			"next_event_id": int(map._next_event_id),
			"next_fleet_id": int(map._next_fleet_id),
			"next_caravan_id": int(map._next_caravan_id),
			"next_merchant_id": int(map._next_merchant_id),
			"next_sellswords_id": int(map._next_sellswords_id),
		},
		"forces": _export_forces(map),
		"fleets": _export_fleets(map),
		"caravans": _export_caravans(map),
		"merchants": _export_merchants(map),
		"merchant_raiders": _stringify_keys(map.merchant_raiders.duplicate(true)),
		"sellswords": _export_sellswords(map),
		"vips": _stringify_keys(map.vips.duplicate(true)),
		"vip_trades": _stringify_keys(map.vip_trades.duplicate(true)),
		"events": map.export_events_state(),
		"score": {
			"stats_history": map.stats_history.duplicate(true),
			"landless_seasons": _stringify_keys(map.landless_seasons.duplicate(true)),
			"endless_solo": bool(map.endless_solo),
			"game_outcome_done": bool(map.game_outcome_done),
		},
		"provinces": _export_provinces(map),
	}


static func apply_state(map: Node, state: Dictionary) -> void:
	if state.is_empty():
		push_error("Empty save state")
		return

	map.world_seed = int(state.get("world_seed", 0))
	map.season = int(state.get("season", 0))
	map.turn = int(state.get("turn", 0))
	map.my_pl_id = int(state.get("my_pl_id", 0))
	map.alliances = _import_alliances(state.get("alliances", {}))
	map.players = _import_players(state.get("players", {}))
	Heraldry.ensure_all(map.players)
	if GlobalStuff.has_method("ensure_order_colors"):
		GlobalStuff.ensure_order_colors(map.players)

	var counters: Dictionary = state.get("counters", {})
	map._next_runtime_force = int(counters.get("next_runtime_force", 0))
	map._next_vip_id = int(counters.get("next_vip_id", 1))
	map._next_vip_trade_id = int(counters.get("next_vip_trade_id", 1))
	map._next_event_id = int(counters.get("next_event_id", 1))
	map._next_fleet_id = int(counters.get("next_fleet_id", 1))
	map._next_caravan_id = int(counters.get("next_caravan_id", 1))
	map._next_merchant_id = int(counters.get("next_merchant_id", 1))
	map._next_sellswords_id = int(counters.get("next_sellswords_id", 1))

	var score: Dictionary = state.get("score", {})
	map.stats_history = score.get("stats_history", []).duplicate(true) if score.get("stats_history") is Array else []
	map.landless_seasons = _int_key_dict(score.get("landless_seasons", {}))
	map.endless_solo = bool(score.get("endless_solo", false))
	map.game_outcome_done = bool(score.get("game_outcome_done", false))

	map.vips = state.get("vips", {}).duplicate(true) if state.get("vips") is Dictionary else {}
	map.vip_trades = state.get("vip_trades", {}).duplicate(true) if state.get("vip_trades") is Dictionary else {}
	map.merchant_raiders = _int_key_dict(state.get("merchant_raiders", {}))

	# Provinces / buildings before forces (garrison keys use building paths).
	for prov in map.provinces.get_children():
		prov.base_map = map
	_import_provinces(map, state.get("provinces", {}))

	_clear_container(map.armies)
	_clear_container(map.fleets)
	_clear_container(map.caravans)
	_clear_container(map.merchants)
	_clear_container(map.sellswords)

	# Graph + building blockers first (no camps yet); then place mobiles.
	for prov in map.provinces.get_children():
		prov.sync_player_owner_to_children()
		prov.recompute_control()
		prov.set_flags()
		prov.setup_map_label()
		if prov.has_method("refresh_field_visuals"):
			prov.refresh_field_visuals(int(map.season))

	map.pathfinding.initialize()

	map.forces = _import_forces(state.get("forces", {}))
	_restore_fleets(map, state.get("fleets", []))
	_restore_mobile_armies(map, state.get("forces", {}))
	_restore_caravans(map, state.get("caravans", []))
	_restore_merchants(map, state.get("merchants", []))
	_restore_sellswords(map, state.get("sellswords", []))

	var events_state: Dictionary = state.get("events", {})
	if events_state is Dictionary:
		events_state = events_state.duplicate(true)
		if events_state.get("player_inboxes") is Dictionary:
			events_state["player_inboxes"] = _int_key_dict(events_state["player_inboxes"])
		if events_state.get("player_msg_unread") is Dictionary:
			events_state["player_msg_unread"] = _int_key_dict(events_state["player_msg_unread"])
	map.import_events_state(events_state)

	map.pathfinding.rebuild_occupancy()
	map.refresh_all_building_flags()
	map.province_borders.rebuild()
	map.build_province_neighbors()
	map.refresh_all_vip_crowns()
	map._init_weather()
	map.update_visuals_and_stats()
	map.update_all_army_visuals()
	map.refresh_army_labels()
	if map.has_method("persist_score_state"):
		map.persist_score_state()


# --- export helpers ---------------------------------------------------------

static func _export_players(players: Dictionary) -> Dictionary:
	var out := {}
	for pid in players.keys():
		var p = players[pid]
		out[str(pid)] = {
			"player_id": int(p.player_id),
			"type": int(p.type),
			"owner_peer_id": int(p.owner_peer_id),
			"local_slot": int(p.local_slot),
			"name_": str(p.name_),
			"status": int(p.status),
			"ended_turn": bool(p.ended_turn),
			"color": p.color.duplicate(true) if p.color is Dictionary else {},
			"heraldry": p.heraldry.duplicate(true) if p.heraldry is Dictionary else {},
			"game_data": p.game_data.duplicate(true) if p.game_data is Dictionary else {},
		}
	return out


static func _import_alliances(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in raw.keys():
		var pid := int(k)
		var arr: Array = []
		var src = raw[k]
		if src is Array:
			for v in src:
				arr.append(int(v))
		out[pid] = arr
	return out


static func _import_players(raw: Dictionary) -> Dictionary:
	var out := {}
	for k in raw.keys():
		var d: Dictionary = raw[k] if raw[k] is Dictionary else {}
		var pid := int(d.get("player_id", int(k)))
		var gd = d.get("game_data", {})
		if not (gd is Dictionary):
			gd = {}
		else:
			gd = gd.duplicate(true)
		var p = GlobalStuff.PlayerData.new(
			pid,
			int(d.get("type", GlobalStuff.PLAYER_TYPE.HUMAN_LOCAL)) as GlobalStuff.PLAYER_TYPE,
			int(d.get("owner_peer_id", 1)),
			int(d.get("local_slot", 0)),
			str(d.get("name_", "Lord")),
			gd
		)
		p.status = int(d.get("status", GlobalStuff.PLAYER_STATUS.PLAYING)) as GlobalStuff.PLAYER_STATUS
		p.ended_turn = bool(d.get("ended_turn", false))
		var col = d.get("color", {})
		if col is Dictionary:
			p.color = col.duplicate(true)
		var h = d.get("heraldry", {})
		if h is Dictionary:
			p.heraldry = h.duplicate(true)
		out[pid] = p
	return out


static func _export_forces(map: Node) -> Dictionary:
	var out := {}
	for fid in map.forces.keys():
		var entry: Dictionary = map.forces[fid].duplicate(true)
		var loc: Dictionary = entry.get("location", {})
		if str(loc.get("kind", "")) == "cell":
			var fig = map.armies.get_node_or_null(str(fid))
			if fig != null and map.pathfinding != null:
				var cell: Vector2i = map.pathfinding.get_army_cell(fig)
				entry["cell"] = {"x": cell.x, "y": cell.y}
				entry["movement_left"] = int(fig.movement_left)
		out[str(fid)] = entry
	return out


static func _import_forces(raw: Dictionary) -> Dictionary:
	var out := {}
	for k in raw.keys():
		var entry: Dictionary = raw[k].duplicate(true) if raw[k] is Dictionary else {}
		# Drop figure-only extras from the live registry; restore uses them separately.
		entry.erase("cell")
		entry.erase("movement_left")
		if entry.get("units") is Array:
			entry["units"] = GlobalUnits.units_from_spec(entry["units"])
		if entry.get("cargo") is Dictionary:
			entry["cargo"] = GlobalUnits.sanitize_caravan_cargo(entry["cargo"])
		out[str(k)] = entry
	return out


static func _export_fleets(map: Node) -> Array:
	var out: Array = []
	if map.fleets == null:
		return out
	for fig in map.fleets.get_children():
		var cell := Vector2i.ZERO
		if map.pathfinding != null:
			cell = map.pathfinding.get_army_cell(fig)
		out.append({
			"id": str(fig.name),
			"player_owner": int(fig.player_owner),
			"ship_count": int(fig.ship_count),
			"cell": {"x": cell.x, "y": cell.y},
			"movement_left": int(fig.movement_left),
			"aboard_force_ids": fig.aboard_force_ids.duplicate() if fig.aboard_force_ids is Array else [],
		})
	return out


static func _export_caravans(map: Node) -> Array:
	var out: Array = []
	if map.caravans == null:
		return out
	for fig in map.caravans.get_children():
		var cell := Vector2i.ZERO
		if map.pathfinding != null and map.pathfinding.has_method("get_caravan_cell"):
			cell = map.pathfinding.get_caravan_cell(fig)
		elif map.pathfinding != null:
			cell = map.pathfinding.get_army_cell(fig)
		out.append({
			"id": str(fig.name),
			"player_owner": int(fig.player_owner),
			"dest_province_id": str(fig.dest_province_id),
			"cargo": fig.cargo.duplicate(true) if fig.cargo is Dictionary else {},
			"cell": {"x": cell.x, "y": cell.y},
			"movement_left": int(fig.movement_left),
			"path_fail_streak": int(fig.path_fail_streak),
			"path_fail_notified": bool(fig.path_fail_notified),
		})
	return out


static func _export_merchants(map: Node) -> Array:
	var out: Array = []
	if map.merchants == null:
		return out
	for m in map.merchants.get_children():
		var cell: Vector2i = m.cell if m.get("cell") != null else Vector2i.ZERO
		var prov = m.get("province")
		var prov_id := String(prov.name) if prov != null else ""
		out.append({
			"id": str(m.name),
			"display_name": str(m.display_name),
			"province": prov_id,
			"cell": {"x": cell.x, "y": cell.y},
			"seasons_left": int(m.seasons_left),
			"camp_hidden": bool(m.camp_hidden),
		})
	return out


static func _export_sellswords(map: Node) -> Array:
	var out: Array = []
	if map.sellswords == null:
		return out
	for s in map.sellswords.get_children():
		var cell: Vector2i = s.cell if s.get("cell") != null else Vector2i.ZERO
		var prov = s.get("province")
		var prov_id := String(prov.name) if prov != null else ""
		out.append({
			"id": str(s.name),
			"province": prov_id,
			"cell": {"x": cell.x, "y": cell.y},
			"seasons_left": int(s.seasons_left),
			"offer": s.offer.duplicate(true) if s.offer is Array else [],
			"original_offer": s.original_offer.duplicate(true) if s.original_offer is Array else [],
		})
	return out


static func _export_provinces(map: Node) -> Dictionary:
	var out := {}
	for prov in map.provinces.get_children():
		var pid := String(prov.name)
		var buildings := {}
		for container_name in ["settlements", "economy", "defense"]:
			var container = prov.get_node_or_null(container_name)
			if container == null:
				continue
			for b in container.get_children():
				var rel := "%s/%s" % [container_name, b.name]
				buildings[rel] = _export_building(b)
		var fields := {}
		var fields_node = prov.get_node_or_null("fields")
		if fields_node != null:
			for f in fields_node.get_children():
				fields[str(f.name)] = {
					"crop": int(f.crop) if f.get("crop") != null else 0,
					"planted": bool(f.planted) if f.get("planted") != null else false,
					"neglected": bool(f.neglected) if f.get("neglected") != null else false,
					"display_horses": int(f.display_horses) if f.get("display_horses") != null else 0,
					"grown_stage": int(f.grown_stage) if f.get("grown_stage") != null else 0,
				}
		out[pid] = {
			"player_owner": int(prov.player_owner),
			"home_province": bool(prov.home_province),
			"dejure": int(prov.dejure) if prov.dejure != null else int(prov.player_owner),
			"defacto": int(prov.defacto) if prov.defacto != null else int(prov.player_owner),
			"resources": _deep_stringify(prov.resources) if prov.resources is Dictionary else {},
			"holdings": _deep_stringify(prov.holdings) if prov.holdings is Dictionary else {},
			"season_start_population": int(prov.season_start_population),
			"levied_this_season": int(prov.levied_this_season),
			"buildings": buildings,
			"fields": fields,
		}
	return out


static func _export_building(b: Node) -> Dictionary:
	var d := {
		"player_owner": int(b.player_owner) if b.get("player_owner") != null else 0,
	}
	if b.get("population") != null:
		d["population"] = int(b.population)
	if b.get("happiness") != null:
		d["happiness"] = float(b.happiness)
	if b.get("tax_marks") != null:
		d["tax_marks"] = int(b.tax_marks)
	if b.get("stage") != null:
		d["stage"] = int(b.stage)
	if b.get("has_castle") != null:
		d["has_castle"] = bool(b.has_castle)
	if b.get("castle_type") != null:
		d["castle_type"] = int(b.castle_type)
	if b.get("project_active") != null:
		d["project_active"] = bool(b.project_active)
		d["project_target"] = int(b.project_target)
		d["project_progress"] = int(b.project_progress)
		d["project_work_needed"] = int(b.project_work_needed)
		d["project_base_level"] = int(b.project_base_level)
		d["peak_completed_level"] = int(b.peak_completed_level)
		d["pending_peak_archers"] = bool(b._pending_peak_archers)
		d["materials_on_site"] = b.materials_on_site.duplicate(true) if b.materials_on_site is Dictionary else {}
	if b.get("slot_kind") != null:
		d["slot_kind"] = int(b.slot_kind)
		d["deposit_type"] = int(b.deposit_type)
		d["subtype"] = int(b.subtype)
		d["craft_weapon"] = str(b.craft_weapon)
	var meta := {}
	for key in BUILDING_META_KEYS:
		if b.has_meta(key):
			meta[key] = b.get_meta(key)
	if not meta.is_empty():
		d["meta"] = meta
	return d


# --- restore helpers --------------------------------------------------------

static func _import_provinces(map: Node, raw: Dictionary) -> void:
	for prov_name in raw.keys():
		var prov = map.provinces.get_node_or_null(str(prov_name))
		if prov == null:
			continue
		var d: Dictionary = raw[prov_name] if raw[prov_name] is Dictionary else {}
		prov.player_owner = int(d.get("player_owner", prov.player_owner))
		prov.home_province = bool(d.get("home_province", false))
		prov.dejure = int(d.get("dejure", prov.player_owner))
		prov.defacto = int(d.get("defacto", prov.player_owner))
		prov.resources = _deep_intify(d.get("resources", {}))
		prov.holdings = _deep_intify(d.get("holdings", {}))
		prov.season_start_population = int(d.get("season_start_population", 0))
		prov.levied_this_season = int(d.get("levied_this_season", 0))
		var buildings: Dictionary = d.get("buildings", {})
		for rel in buildings.keys():
			var b = prov.get_node_or_null(NodePath(str(rel)))
			if b == null:
				continue
			_import_building(b, buildings[rel] if buildings[rel] is Dictionary else {})
		var fields: Dictionary = d.get("fields", {})
		var fields_node = prov.get_node_or_null("fields")
		if fields_node != null:
			for fname in fields.keys():
				var f = fields_node.get_node_or_null(str(fname))
				if f == null:
					continue
				var fd: Dictionary = fields[fname] if fields[fname] is Dictionary else {}
				if f.get("crop") != null:
					f.crop = int(fd.get("crop", f.crop))
				if f.get("planted") != null:
					f.planted = bool(fd.get("planted", false))
				if f.get("neglected") != null:
					f.neglected = bool(fd.get("neglected", false))
				if f.get("display_horses") != null:
					f.display_horses = int(fd.get("display_horses", 0))
				if f.get("grown_stage") != null:
					f.grown_stage = int(fd.get("grown_stage", f.grown_stage))


static func _import_building(b: Node, d: Dictionary) -> void:
	if b.get("player_owner") != null:
		b.player_owner = int(d.get("player_owner", b.player_owner))
	if b.get("population") != null and d.has("population"):
		b.population = int(d["population"])
	if b.get("happiness") != null and d.has("happiness"):
		b.happiness = float(d["happiness"])
	if b.get("tax_marks") != null and d.has("tax_marks"):
		b.tax_marks = int(d["tax_marks"])
	if b.get("stage") != null and d.has("stage"):
		b.stage = int(d["stage"])
	if b.get("has_castle") != null and d.has("has_castle"):
		b.has_castle = bool(d["has_castle"])
	if b.get("castle_type") != null and d.has("castle_type"):
		b.castle_type = int(d["castle_type"])
	if b.get("project_active") != null:
		b.project_active = bool(d.get("project_active", false))
		b.project_target = int(d.get("project_target", b.project_target))
		b.project_progress = int(d.get("project_progress", 0))
		b.project_work_needed = int(d.get("project_work_needed", 0))
		b.project_base_level = int(d.get("project_base_level", b.project_base_level))
		b.peak_completed_level = int(d.get("peak_completed_level", b.peak_completed_level))
		b._pending_peak_archers = bool(d.get("pending_peak_archers", false))
		var mats = d.get("materials_on_site", {})
		if mats is Dictionary:
			b.materials_on_site = mats.duplicate(true)
	if b.get("slot_kind") != null:
		b.slot_kind = int(d.get("slot_kind", b.slot_kind))
		b.deposit_type = int(d.get("deposit_type", b.deposit_type))
		b.subtype = int(d.get("subtype", b.subtype))
		b.craft_weapon = str(d.get("craft_weapon", b.craft_weapon))
	var meta = d.get("meta", {})
	if meta is Dictionary:
		for key in meta.keys():
			b.set_meta(str(key), meta[key])
	if b.has_method("refresh_visuals"):
		b.refresh_visuals()
	elif b.has_method("update_sprite"):
		b.update_sprite()
	elif b.has_method("setup_building"):
		b.setup_building()


static func _restore_fleets(map: Node, raw: Array) -> void:
	for item in raw:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var fid := str(d.get("id", ""))
		if fid.is_empty():
			continue
		var cell := Vector2i(int(d.get("cell", {}).get("x", 0)), int(d.get("cell", {}).get("y", 0)))
		var fig = map._spawn_fleet(
			fid,
			int(d.get("player_owner", 0)),
			int(d.get("ship_count", 1)),
			cell,
			int(d.get("movement_left", -1))
		)
		if fig != null:
			fig.aboard_force_ids = d.get("aboard_force_ids", []).duplicate() if d.get("aboard_force_ids") is Array else []


static func _restore_mobile_armies(map: Node, forces_raw: Dictionary) -> void:
	for fid in forces_raw.keys():
		var entry: Dictionary = forces_raw[fid] if forces_raw[fid] is Dictionary else {}
		var loc: Dictionary = entry.get("location", {})
		if str(loc.get("kind", "")) != "cell":
			continue
		if not map.forces.has(str(fid)):
			continue
		var cell_d = entry.get("cell", {})
		var cell := Vector2i(int(cell_d.get("x", 0)), int(cell_d.get("y", 0)))
		var mp := int(entry.get("movement_left", 0))
		_spawn_army_from_force(map, str(fid), cell, mp)


static func _spawn_army_from_force(map: Node, fid: String, cell: Vector2i, starting_mp: int) -> void:
	if map.armies.get_node_or_null(fid) != null:
		return
	var entry: Dictionary = map.forces[fid]
	var units: Array = entry.get("units", [])
	var controller := int(entry.get("controller", GlobalUnits.primary_owner(units)))
	var fig = map.ARMY_FIGURE_SCENE.instantiate()
	fig.name = fid
	map.armies.add_child(fig)
	fig.base_map = map
	fig.bind_force(fid)
	map.pathfinding.place_army_at_cell(fig, cell)
	if starting_mp < 0:
		fig.reset_movement()
	else:
		fig.movement_left = clampi(starting_mp, 0, fig.effective_max_mp())
	# Keep controller / cargo / siege from imported forces entry.
	entry["controller"] = controller
	entry["location"] = {"kind": "cell"}


static func _restore_caravans(map: Node, raw: Array) -> void:
	for item in raw:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var cid := str(d.get("id", ""))
		if cid.is_empty():
			continue
		var cell := Vector2i(int(d.get("cell", {}).get("x", 0)), int(d.get("cell", {}).get("y", 0)))
		map._spawn_caravan(
			cid,
			int(d.get("player_owner", 0)),
			str(d.get("dest_province_id", "")),
			d.get("cargo", {}) if d.get("cargo") is Dictionary else {},
			cell
		)
		var fig = map.caravans.get_node_or_null(cid)
		if fig != null:
			fig.movement_left = int(d.get("movement_left", fig.movement_left))
			fig.path_fail_streak = int(d.get("path_fail_streak", 0))
			fig.path_fail_notified = bool(d.get("path_fail_notified", false))


static func _restore_merchants(map: Node, raw: Array) -> void:
	for item in raw:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var mid := str(d.get("id", ""))
		var prov = map._get_province_by_id(str(d.get("province", "")))
		if prov == null:
			continue
		var cell := Vector2i(int(d.get("cell", {}).get("x", 0)), int(d.get("cell", {}).get("y", 0)))
		var m = map.MERCHANT_SCENE.instantiate()
		m.name = mid if not mid.is_empty() else ("merchant_%d" % map._next_merchant_id)
		m.display_name = str(d.get("display_name", "Merchant"))
		m.base_map = map
		m.seasons_left = int(d.get("seasons_left", 1))
		m.camp_hidden = bool(d.get("camp_hidden", false))
		map.merchants.add_child(m)
		m.place_at_cell(cell, prov)
		map.pathfinding.block_cell_for_object(cell, m)


static func _restore_sellswords(map: Node, raw: Array) -> void:
	for item in raw:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var sid := str(d.get("id", ""))
		var prov = map._get_province_by_id(str(d.get("province", "")))
		if prov == null:
			continue
		var cell := Vector2i(int(d.get("cell", {}).get("x", 0)), int(d.get("cell", {}).get("y", 0)))
		var s = map.SELLSWORDS_SCENE.instantiate()
		s.name = sid if not sid.is_empty() else ("sellswords_%d" % map._next_sellswords_id)
		s.base_map = map
		s.seasons_left = int(d.get("seasons_left", 1))
		s.offer = d.get("offer", []).duplicate(true) if d.get("offer") is Array else []
		s.original_offer = d.get("original_offer", []).duplicate(true) if d.get("original_offer") is Array else []
		map.sellswords.add_child(s)
		s.place_at_cell(cell, prov)
		map.pathfinding.block_cell_for_object(cell, s)


static func _clear_container(node: Node) -> void:
	if node == null:
		return
	while node.get_child_count() > 0:
		var ch := node.get_child(0)
		node.remove_child(ch)
		ch.free()


# --- JSON key helpers -------------------------------------------------------

static func _stringify_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var v = d[k]
		if v is Dictionary:
			out[str(k)] = _stringify_keys(v)
		elif v is Array:
			out[str(k)] = _stringify_array(v)
		else:
			out[str(k)] = v
	return out


static func _stringify_array(a: Array) -> Array:
	var out: Array = []
	for v in a:
		if v is Dictionary:
			out.append(_stringify_keys(v))
		elif v is Array:
			out.append(_stringify_array(v))
		else:
			out.append(v)
	return out


static func _deep_stringify(v: Variant) -> Variant:
	if v is Dictionary:
		return _stringify_keys(v)
	if v is Array:
		return _stringify_array(v)
	return v


static func _int_key_dict(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in raw.keys():
		var key = int(k) if str(k).is_valid_int() else k
		var v = raw[k]
		if v is Dictionary:
			# Nested player-id maps (holdings etc.) — intify one level of keys when numeric.
			out[key] = _int_key_dict(v) if _keys_look_numeric(v) else v.duplicate(true)
		else:
			out[key] = v
	return out


static func _keys_look_numeric(d: Dictionary) -> bool:
	for k in d.keys():
		if not str(k).is_valid_int():
			return false
	return not d.is_empty()


static func _deep_intify(raw: Variant) -> Variant:
	if raw is Dictionary:
		var out := {}
		for k in raw.keys():
			var key = int(k) if str(k).is_valid_int() else k
			out[key] = _deep_intify(raw[k])
		return out
	if raw is Array:
		var arr: Array = []
		for v in raw:
			arr.append(_deep_intify(v))
		return arr
	return raw
