extends RefCounted
class_name GameEvents

## Shared helpers for the global event log + per-player message inbox.
## Events are plain Dictionaries so they survive RPC / JSON.

enum KIND { BATTLE, JOIN, BUILDING_CAPTURE, VIP, UPKEEP, FOOD, SIEGE, DIPLO, TOURNEY }

const INBOX_CAP := 30
## Matches OBaseMap.START_YEAR — used for inbox date prefixes.
const START_YEAR := 1100

const SEASON_NAMES := ["Winter", "Spring", "Summer", "Autumn"]


static func event_year(event: Dictionary) -> int:
	return START_YEAR + int(event.get("turn", 0)) / 4


static func event_season_name(event: Dictionary) -> String:
	var season := int(event.get("season", 0))
	if season >= 0 and season < SEASON_NAMES.size():
		return SEASON_NAMES[season]
	return str(season)


static func kind_name(kind: int) -> String:
	match kind:
		KIND.BATTLE: return "Battle"
		KIND.JOIN: return "Join offer"
		KIND.BUILDING_CAPTURE: return "Building"
		KIND.VIP: return "VIP"
		KIND.UPKEEP: return "Upkeep"
		KIND.FOOD: return "Food"
		KIND.SIEGE: return "Siege"
		KIND.DIPLO: return "Diplomacy"
		KIND.TOURNEY: return "Tourney"
	return "Event"


static func inbox_label(event: Dictionary, reader_id: int, unread: bool = false) -> String:
	var place := str(event.get("place_name", "Unknown"))
	var body := ""
	match int(event.get("kind", -1)):
		KIND.BATTLE:
			body = "Battle report — %s" % place
		KIND.JOIN:
			var verdict := "accepted" if bool(event.get("accepted", false)) else "refused"
			body = "Join offer — %s" % verdict
		KIND.BUILDING_CAPTURE:
			if reader_id == int(event.get("new_owner", -1)):
				body = "Building captured — %s" % place
			else:
				body = "Building lost — %s" % place
		KIND.VIP:
			var vk := str(event.get("vip_kind", ""))
			if vk == "sword":
				body = "VIP executed"
			elif vk == "trade_propose":
				body = "Trade offer received"
			elif vk == "trade_reject":
				body = "Trade rejected"
			elif vk == "trade_accept":
				body = "Trade completed"
			else:
				body = "VIP"
		KIND.UPKEEP:
			match str(event.get("upkeep_kind", "")):
				"cleared":
					body = "Army pay restored"
				"desertion":
					body = "Levy desertion"
				"sellswords":
					body = "Sellswords disbanded"
				_:
					body = "Army pay warning"
		KIND.FOOD:
			match str(event.get("food_kind", "")):
				"starving":
					body = "One of your armies is starving"
				"warning":
					body = "One of your armies is out of food"
				"civilian_shrink":
					body = "Province population fell"
				_:
					body = "Food"
		KIND.SIEGE:
			body = "Siege engines completed — %s" % place
		KIND.DIPLO:
			var dk := str(event.get("diplo_kind", ""))
			body = str(event.get("diplo_label", "Diplomacy"))
			if dk != "" and body == "Diplomacy":
				body = dk
		KIND.TOURNEY:
			body = str(event.get("tourney_label", "Tourney"))
		_:
			body = kind_name(int(event.get("kind", -1)))
	var dated := "%d %s — %s" % [event_year(event), event_season_name(event), body]
	if unread:
		return "* %s" % dated
	return dated


static func report_title(event: Dictionary, reader_id: int) -> String:
	match int(event.get("kind", -1)):
		KIND.BATTLE:
			return "Battle report"
		KIND.JOIN:
			return "Join offer"
		KIND.BUILDING_CAPTURE:
			if reader_id == int(event.get("new_owner", -1)):
				return "Building captured"
			return "Building lost"
		KIND.VIP:
			match str(event.get("vip_kind", "")):
				"trade_propose":
					return "Trade offer"
				"trade_reject":
					return "Trade rejected"
				"trade_accept":
					return "Trade completed"
				"sword":
					return "VIP executed"
			return "VIP report"
		KIND.UPKEEP:
			return "Army pay"
		KIND.FOOD:
			match str(event.get("food_kind", "")):
				"starving":
					return "One of your armies is starving"
				"warning":
					return "One of your armies is out of food"
				"civilian_shrink":
					return "Province population fell"
				_:
					return "Food"
		KIND.SIEGE:
			return "Siege engines completed"
		KIND.DIPLO:
			return str(event.get("diplo_label", "Diplomacy"))
		KIND.TOURNEY:
			return str(event.get("tourney_label", "Tourney"))
	return "Status report"


static func report_body(event: Dictionary, reader_id: int, player_name_cb: Callable) -> String:
	var lines: PackedStringArray = []
	lines.append("%d %s" % [event_year(event), event_season_name(event)])
	var place := str(event.get("place_name", ""))
	if place != "":
		lines.append("Location: %s" % place)
	lines.append("")

	match int(event.get("kind", -1)):
		KIND.BATTLE:
			lines.append_array(_battle_body(event, reader_id, player_name_cb))
		KIND.JOIN:
			lines.append_array(_join_body(event))
		KIND.BUILDING_CAPTURE:
			lines.append_array(_building_body(event, reader_id, player_name_cb))
		KIND.VIP:
			var txt := str(event.get("text", ""))
			if txt != "":
				lines.append(txt)
			else:
				lines.append("VIP update.")
		KIND.UPKEEP:
			var ut := str(event.get("text", ""))
			if ut != "":
				lines.append(ut)
			else:
				lines.append("Army pay update.")
		KIND.FOOD:
			var ft := str(event.get("text", ""))
			if ft != "":
				lines.append(ft)
			else:
				lines.append("Army food update.")
		KIND.SIEGE:
			var st := str(event.get("text", ""))
			if st != "":
				lines.append(st)
			else:
				lines.append("An army has completed all its siege engines.")
		KIND.DIPLO:
			var dt := str(event.get("text", ""))
			if dt != "":
				lines.append(dt)
			else:
				lines.append("Diplomatic update.")
		KIND.TOURNEY:
			var tt := str(event.get("text", ""))
			if tt != "":
				lines.append(tt)
			else:
				lines.append("Tourney update.")
		_:
			lines.append("No details available.")
	return "\n".join(lines)


## Reader-facing battle outcome for UI coloring.
## Returns {} if not a battle; else { "text": String, "won": bool }.
## Spectator / both-sides: "won" is absolute attacker_won.
static func battle_outcome(event: Dictionary, reader_id: int) -> Dictionary:
	if int(event.get("kind", -1)) != KIND.BATTLE:
		return {}
	var atk_side: Array = event.get("attacker_side_ids", [])
	var def_side: Array = event.get("defender_side_ids", [])
	var on_atk := _side_has(atk_side, reader_id)
	var on_def := _side_has(def_side, reader_id)
	var attacker_won := bool(event.get("attacker_won", false))
	var is_siege := bool(event.get("is_siege", false))
	var def_label := "garrison" if is_siege else "army"
	if on_atk and not on_def:
		if attacker_won:
			return {"text": "Victory!", "won": true}
		return {"text": "Defeat — your army was destroyed.", "won": false}
	if on_def and not on_atk:
		if attacker_won:
			return {"text": "Defeat — your %s was overwhelmed." % def_label, "won": false}
		return {"text": "Victory — your %s held the field." % def_label, "won": true}
	return {
		"text": "Attacker victory." if attacker_won else "Defender victory.",
		"won": attacker_won,
	}


static func _side_has(side_ids: Array, reader_id: int) -> bool:
	for pid in side_ids:
		if int(pid) == reader_id:
			return true
	return false


static func _battle_body(event: Dictionary, reader_id: int, player_name_cb: Callable) -> PackedStringArray:
	var lines: PackedStringArray = []
	var atk_side: Array = event.get("attacker_side_ids", [])
	var def_side: Array = event.get("defender_side_ids", [])
	var on_atk := _side_has(atk_side, reader_id)
	var on_def := _side_has(def_side, reader_id)
	var attacker_won := bool(event.get("attacker_won", false))

	# Outcome line is rendered separately (colored) in the event report UI.

	var atk_dead := int(event.get("attacker_dead", 0))
	var atk_wounded := int(event.get("attacker_wounded", 0))
	var def_dead := int(event.get("defender_dead", 0))
	var def_wounded := int(event.get("defender_wounded", 0))
	var hostages := int(event.get("hostage_men", 0))

	if on_atk and not on_def:
		lines.append("Your dead: %d  Your wounded: %d" % [atk_dead, atk_wounded])
		lines.append("Enemy dead: %d  Enemy wounded: %d" % [def_dead, def_wounded])
		if attacker_won and hostages > 0:
			lines.append(_hostage_fate_line(event, hostages, true))
		if attacker_won:
			_append_loot_line(lines, event)
			_append_wages_line(lines, event)
	elif on_def and not on_atk:
		lines.append("Your dead: %d  Your wounded: %d" % [def_dead, def_wounded])
		lines.append("Enemy dead: %d  Enemy wounded: %d" % [atk_dead, atk_wounded])
		if attacker_won and hostages > 0:
			lines.append(_hostage_fate_line(event, hostages, false))
		if not attacker_won:
			_append_loot_line(lines, event)
	else:
		lines.append("Attacker dead: %d  wounded: %d" % [atk_dead, atk_wounded])
		lines.append("Defender dead: %d  wounded: %d" % [def_dead, def_wounded])
		if attacker_won and hostages > 0:
			lines.append(_hostage_fate_line(event, hostages, true))
		_append_loot_line(lines, event)

	var atk_names := _side_names(atk_side, player_name_cb)
	var def_names := _side_names(def_side, player_name_cb)
	if atk_names != "":
		lines.append("Attackers: %s" % atk_names)
	if def_names != "":
		lines.append("Defenders: %s" % def_names)

	return lines


## Structured before/after roster tables for the event report UI.
## Returns Array of {
##   "side", "side_ids", "won", "before_men", "after_men",
##   "rows": [{ "label", "before", "after" }]
## }.
static func roster_tables(event: Dictionary) -> Array:
	if not event.has("attacker_units_before") and not event.has("defender_units_before"):
		return []
	var attacker_won := bool(event.get("attacker_won", false))
	var out: Array = []
	out.append(_roster_table_data(
		"Attacker",
		event.get("attacker_side_ids", []),
		attacker_won,
		event.get("attacker_units_before", []),
		event.get("attacker_units_after", [])
	))
	out.append(_roster_table_data(
		"Defender",
		event.get("defender_side_ids", []),
		not attacker_won,
		event.get("defender_units_before", []),
		event.get("defender_units_after", [])
	))
	return out


static func _roster_table_data(
	side: String,
	side_ids: Array,
	won: bool,
	before: Array,
	after: Array
) -> Dictionary:
	var before_counts := _roster_counts(before)
	var after_counts := _roster_counts(after)
	var keys: Array = []
	for k in before_counts.keys():
		if not keys.has(k):
			keys.append(k)
	for k in after_counts.keys():
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	var rows: Array = []
	for k in keys:
		var label := str(k)
		var sep := label.find("|")
		if sep >= 0:
			label = label.substr(sep + 1)
		rows.append({
			"label": label,
			"before": int(before_counts.get(k, 0)),
			"after": int(after_counts.get(k, 0)),
		})
	return {
		"side": side,
		"side_ids": side_ids.duplicate(),
		"won": won,
		"before_men": GlobalUnits.total_men(before),
		"after_men": GlobalUnits.total_men(after),
		"rows": rows,
	}


## Sortable key → men. Prefix keeps unit types ordered; label follows after "|".
static func _roster_counts(units: Array) -> Dictionary:
	var counts: Dictionary = {}
	for s in units:
		var n := int(s.get("count", 0))
		if n <= 0:
			continue
		var ut := int(s.get("type", GlobalUnits.UNIT_TYPE.PEASANT))
		var src := int(s.get("source", GlobalUnits.SOURCE.LEVY))
		var st := GlobalUnits.stack_status(s)
		var label := "%s (%s)" % [GlobalUnits.unit_name(ut), GlobalUnits.source_name(src)]
		if st != GlobalUnits.STATUS.FIGHTING:
			label += " [%s]" % GlobalUnits.status_name(st)
		if bool(s.get("join_pending", false)):
			label += " (join)"
		if GlobalUnits.is_militia_stack(s):
			label += " (militia)"
		var key := "%02d|%s" % [ut, label]
		counts[key] = int(counts.get(key, 0)) + n
	return counts


static func _hostage_fate_line(event: Dictionary, hostages: int, attacker_view: bool) -> String:
	var fate := str(event.get("hostage_fate", "none"))
	match fate:
		"taken":
			if attacker_view:
				return "Enemy wounded: %d — taken as hostages" % hostages
			return "Your wounded: %d — taken as hostages" % hostages
		"sword":
			if attacker_view:
				return "Enemy wounded: %d — put to the sword" % hostages
			return "Your wounded: %d — put to the sword" % hostages
		"pending":
			if attacker_view:
				return "Enemy wounded: %d — fate undecided" % hostages
			return "Your wounded: %d — fate undecided" % hostages
		_:
			return "Enemy wounded: %d" % hostages


static func _append_loot_line(lines: PackedStringArray, event: Dictionary) -> void:
	var loot: Dictionary = event.get("loot", {})
	if loot.is_empty() or not GlobalUnits.weapon_stock_has_any(loot):
		return
	lines.append("Loot: %s" % GlobalUnits.weapon_stock_summary(loot))


static func _append_wages_line(lines: PackedStringArray, event: Dictionary) -> void:
	var wages := int(event.get("captured_wages", 0))
	if wages <= 0:
		return
	lines.append("You captured the army's wages (%d marks)." % wages)


static func _join_body(event: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var count := int(event.get("count", 0))
	var type_name := str(event.get("unit_name", "Units"))
	var source_name := str(event.get("source_name", ""))
	var who := "%d %s" % [count, type_name]
	if source_name != "":
		who += " (%s)" % source_name
	if bool(event.get("accepted", false)):
		lines.append("%s accepted your offer and joined your ranks." % who)
	else:
		lines.append("%s refused your offer to join." % who)
	return lines


static func _building_body(event: Dictionary, reader_id: int, player_name_cb: Callable) -> PackedStringArray:
	var lines: PackedStringArray = []
	var place := str(event.get("place_name", "Building"))
	var prev := int(event.get("previous_owner", -1))
	var new_o := int(event.get("new_owner", -1))
	var prev_name := str(player_name_cb.call(prev))
	var new_name := str(player_name_cb.call(new_o))
	if reader_id == new_o:
		lines.append("You captured %s." % place)
		if prev >= 0:
			lines.append("Previous owner: %s" % prev_name)
	elif reader_id == prev:
		lines.append("You lost %s to %s." % [place, new_name])
	else:
		lines.append("%s changed hands from %s to %s." % [place, prev_name, new_name])
	return lines


static func _side_names(ids: Array, player_name_cb: Callable) -> String:
	var names: PackedStringArray = []
	for pid in ids:
		names.append(str(player_name_cb.call(int(pid))))
	return ", ".join(names)


static func world_pos_of(event: Dictionary) -> Vector2:
	return Vector2(float(event.get("world_x", 0.0)), float(event.get("world_y", 0.0)))
