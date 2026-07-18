extends RefCounted
class_name GameEvents

## Shared helpers for the global event log + per-player message inbox.
## Events are plain Dictionaries so they survive RPC / JSON.

enum KIND { BATTLE, JOIN, BUILDING_CAPTURE, VIP, UPKEEP, FOOD, SIEGE }

const INBOX_CAP := 30

const SEASON_NAMES := ["Winter", "Spring", "Summer", "Autumn"]


static func kind_name(kind: int) -> String:
	match kind:
		KIND.BATTLE: return "Battle"
		KIND.JOIN: return "Join offer"
		KIND.BUILDING_CAPTURE: return "Building"
		KIND.VIP: return "VIP"
		KIND.UPKEEP: return "Upkeep"
		KIND.FOOD: return "Food"
		KIND.SIEGE: return "Siege"
	return "Event"


static func inbox_label(event: Dictionary, reader_id: int) -> String:
	var place := str(event.get("place_name", "Unknown"))
	match int(event.get("kind", -1)):
		KIND.BATTLE:
			return "Battle report — %s" % place
		KIND.JOIN:
			var verdict := "accepted" if bool(event.get("accepted", false)) else "refused"
			return "Join offer — %s" % verdict
		KIND.BUILDING_CAPTURE:
			if reader_id == int(event.get("new_owner", -1)):
				return "Building captured — %s" % place
			return "Building lost — %s" % place
		KIND.VIP:
			var vk := str(event.get("vip_kind", ""))
			if vk == "sword":
				return "VIP executed"
			if vk == "trade_propose":
				return "Trade offer received"
			if vk == "trade_reject":
				return "Trade rejected"
			if vk == "trade_accept":
				return "Trade completed"
			return "VIP"
		KIND.UPKEEP:
			match str(event.get("upkeep_kind", "")):
				"cleared":
					return "Army pay restored"
				"desertion":
					return "Levy desertion"
				"sellswords":
					return "Sellswords disbanded"
				_:
					return "Army pay warning"
		KIND.FOOD:
			match str(event.get("food_kind", "")):
				"starving":
					return "One of your armies is starving"
				"warning":
					return "One of your armies is out of food"
				_:
					return "Army food"
		KIND.SIEGE:
			return "Siege engines completed — %s" % place
	return kind_name(int(event.get("kind", -1)))


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
				_:
					return "Army food"
		KIND.SIEGE:
			return "Siege engines completed"
	return "Status report"


static func report_body(event: Dictionary, reader_id: int, player_name_cb: Callable) -> String:
	var lines: PackedStringArray = []
	var turn := int(event.get("turn", 0))
	var season := int(event.get("season", 0))
	var season_txt = SEASON_NAMES[season] if season >= 0 and season < SEASON_NAMES.size() else str(season)
	lines.append("%s, turn %d" % [season_txt, turn])
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
		_:
			lines.append("No details available.")
	return "\n".join(lines)


static func _battle_body(event: Dictionary, reader_id: int, player_name_cb: Callable) -> PackedStringArray:
	var lines: PackedStringArray = []
	var atk_side: Array = event.get("attacker_side_ids", [])
	var def_side: Array = event.get("defender_side_ids", [])
	var on_atk := atk_side.has(reader_id)
	var on_def := def_side.has(reader_id)
	var attacker_won := bool(event.get("attacker_won", false))
	var is_siege := bool(event.get("is_siege", false))
	var def_label := "garrison" if is_siege else "army"

	if on_atk and not on_def:
		if attacker_won:
			lines.append("Victory!")
		else:
			lines.append("Defeat — your army was destroyed.")
	elif on_def and not on_atk:
		if attacker_won:
			lines.append("Defeat — your %s was overwhelmed." % def_label)
		else:
			lines.append("Victory — your %s held the field." % def_label)
	else:
		# Spectator edge case / both sides (shouldn't happen often).
		lines.append("Attacker victory." if attacker_won else "Defender victory.")

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
