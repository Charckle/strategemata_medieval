extends CanvasLayer
class_name TourneyOverlay

## Full-screen tourney UI. Freezes overworld while visible.

signal finished(winner_pid: int, winner_is_npc: bool, champion_knight: Dictionary)

var base_map: Node = null
var local_pid: int = -1
var rules: Dictionary = {}
var bracket: Dictionary = {}
var entrants: Array = [] # {pid, knight, is_npc}
var control_mode: String = "watch" # watch | manage
var prize_pool: int = 0
var tourney_name: String = "Tourney"

var _root: Control
var _title: Label
var _subtitle: Label
var _log: RichTextLabel
var _status: Label
var _match_header: HBoxContainer
var _continue_btn: Button
var _aim_box: HBoxContainer
var _agg_box: HBoxContainer
var _guard_box: HBoxContainer
var _mode_box: HBoxContainer
var _waiting := false
var _decision_ready := false
var _pending_decision: Dictionary = {}
var _abort := false

var _player_knight_name: String = ""
const _SHIELD_SIZE := 28


func _ready() -> void:
	layer = 80
	_build_ui()
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(
	p_base_map: Node,
	p_local_pid: int,
	p_rules: Dictionary,
	p_entrants: Array,
	p_prize: int,
	p_name: String
) -> void:
	base_map = p_base_map
	local_pid = p_local_pid
	rules = p_rules
	entrants = p_entrants
	prize_pool = p_prize
	tourney_name = p_name
	_player_knight_name = ""
	for e in entrants:
		if int(e.get("pid", -1)) == local_pid and not bool(e.get("is_npc", false)):
			_player_knight_name = str(e.get("knight", {}).get("name", ""))
			break
	var knights: Array = []
	for e in entrants:
		# Keep the same Dictionary reference so injuries persist across rounds.
		var k: Dictionary = e.get("knight", {})
		knights.append(k)
	bracket = JoustBracket.build(knights)
	_title.text = tourney_name
	_subtitle.text = "Prize pool: %d marks  |  Field: %d knights" % [prize_pool, knights.size()]
	_append("The lists are set. Knights take their places.")
	_show_mode_select()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.03, 0.88)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 520)
	panel.position = Vector2(-360, -260)
	_root.add_child(panel)
	# Center via anchors
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 40
	panel.offset_bottom = -40

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_subtitle)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)

	_mode_box = HBoxContainer.new()
	_mode_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_box.add_theme_constant_override("separation", 12)
	var watch_btn := Button.new()
	watch_btn.text = "Watch (auto)"
	watch_btn.pressed.connect(_on_pick_mode.bind("watch"))
	var manage_btn := Button.new()
	manage_btn.text = "Manage (your passes)"
	manage_btn.pressed.connect(_on_pick_mode.bind("manage"))
	_mode_box.add_child(watch_btn)
	_mode_box.add_child(manage_btn)
	vbox.add_child(_mode_box)

	_match_header = HBoxContainer.new()
	_match_header.alignment = BoxContainer.ALIGNMENT_CENTER
	_match_header.add_theme_constant_override("separation", 10)
	_match_header.visible = false
	vbox.add_child(_match_header)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.custom_minimum_size = Vector2(0, 280)
	vbox.add_child(_log)

	_aim_box = HBoxContainer.new()
	_aim_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_aim_box.visible = false
	_agg_box = HBoxContainer.new()
	_agg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_agg_box.visible = false
	_guard_box = HBoxContainer.new()
	_guard_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_guard_box.visible = false
	vbox.add_child(_aim_box)
	vbox.add_child(_agg_box)
	vbox.add_child(_guard_box)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.visible = false
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)


func _show_mode_select() -> void:
	_mode_box.visible = true
	_status.text = "Choose how you will ride:"
	_continue_btn.visible = false


func _on_pick_mode(mode: String) -> void:
	control_mode = mode
	_mode_box.visible = false
	_status.text = "Mode: %s" % ("Watch" if mode == "watch" else "Manage")
	_run_tournament()


func _append(text: String) -> void:
	_log.append_text(text + "\n")


func _clear_match_header() -> void:
	if _match_header == null:
		return
	for c in _match_header.get_children():
		c.queue_free()
	_match_header.visible = false


func _make_shield_tex(entrant: Dictionary) -> TextureRect:
	var shield := TextureRect.new()
	shield.custom_minimum_size = Vector2(_SHIELD_SIZE, _SHIELD_SIZE)
	shield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shield.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shield.texture = Tourney.texture_for_entrant(entrant, _SHIELD_SIZE)
	var pid := int(entrant.get("pid", -1))
	if pid >= 0 and base_map != null and base_map.has_method("player_display_name"):
		shield.tooltip_text = str(base_map.player_display_name(pid))
	elif bool(entrant.get("is_npc", false)):
		shield.tooltip_text = "Itinerant knight"
	return shield


func _entrant_for_knight(knight: Dictionary) -> Dictionary:
	var kn := str(knight.get("name", ""))
	for e in entrants:
		if not (e is Dictionary):
			continue
		if str(e.get("knight", {}).get("name", "")) == kn:
			return e
	return {"pid": -1, "is_npc": true, "heraldry": Heraldry.default_heraldry(), "knight": knight}


func _show_match_header(ka: Dictionary, kb: Dictionary) -> void:
	_clear_match_header()
	_match_header.visible = true
	var ea := _entrant_for_knight(ka)
	var eb := _entrant_for_knight(kb)
	_match_header.add_child(_make_shield_tex(ea))
	var la := Label.new()
	la.text = str(ka.get("name", "?"))
	la.add_theme_font_size_override("font_size", 15)
	_match_header.add_child(la)
	var vs := Label.new()
	vs.text = "vs"
	vs.add_theme_color_override("font_color", Color(0.85, 0.72, 0.45, 1))
	_match_header.add_child(vs)
	_match_header.add_child(_make_shield_tex(eb))
	var lb := Label.new()
	lb.text = str(kb.get("name", "?"))
	lb.add_theme_font_size_override("font_size", 15)
	_match_header.add_child(lb)


func _show_champion_header(champ: Dictionary) -> void:
	_clear_match_header()
	_match_header.visible = true
	var e := _entrant_for_knight(champ)
	_match_header.add_child(_make_shield_tex(e))
	var lbl := Label.new()
	lbl.text = "CHAMPION: %s" % str(champ.get("name", "?"))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1))
	_match_header.add_child(lbl)


func _on_continue() -> void:
	_waiting = false


func _wait_continue(label: String = "Continue") -> void:
	_continue_btn.text = label
	_continue_btn.visible = true
	_waiting = true
	while _waiting and not _abort:
		await get_tree().process_frame
	_continue_btn.visible = false


func _run_tournament() -> void:
	if bracket.is_empty():
		_finish(-1, true, {})
		return
	var round_idx := 0
	while true:
		var rounds: Array = bracket.get("rounds", [])
		if round_idx >= rounds.size():
			break
		var current_round: Array = rounds[round_idx]
		var rname := JoustBracket.round_name(int(bracket.get("total_rounds", 1)), round_idx)
		_append("")
		_append("[b]%s[/b]" % rname)
		_status.text = rname
		await _wait_continue("Begin %s" % rname)

		for match_data in current_round:
			if not (match_data is Dictionary):
				continue
			var ka: Dictionary = match_data.get("knight_a", {})
			var kb: Dictionary = match_data.get("knight_b", {})
			_append("")
			_show_match_header(ka, kb)
			_append("— %s  vs  %s —" % [ka.get("name", "?"), kb.get("name", "?")])
			var is_player := (
				str(ka.get("name", "")) == _player_knight_name
				or str(kb.get("name", "")) == _player_knight_name
			)
			if is_player:
				_append("[color=gold]*** YOUR MATCH ***[/color]")

			var result: Dictionary
			if is_player and control_mode == "manage":
				result = await _run_managed_match(ka, kb)
			else:
				var engine := JoustEngine.new(rules)
				result = engine.run_match(ka, kb)
				for pass_events in result.get("events_per_pass", []):
					if pass_events is Array:
						var lines := JoustNarrator.narrate_pass(pass_events, true)
						for line in lines:
							_append(str(line))
							await get_tree().create_timer(0.04).timeout

			match_data["winner"] = result.get("winner")
			match_data["loser"] = result.get("loser")
			match_data["finished"] = true
			await _wait_continue("Next")

			if is_player and _player_knight_name != "":
				var pk = ka if str(ka.get("name", "")) == _player_knight_name else kb
				if not JoustKnight.can_fight(pk):
					_append("Your knight can no longer continue. The tournament goes on without you...")

		# Heal player knight between rounds
		if _player_knight_name != "":
			for e in entrants:
				var k: Dictionary = e.get("knight", {})
				if str(k.get("name", "")) == _player_knight_name:
					var healed := JoustKnight.heal_between_matches(k)
					for h in healed:
						_append(str(h))

		if not JoustBracket.advance(bracket):
			break
		round_idx = int(bracket.get("current_round", round_idx + 1))

	var champ = JoustBracket.champion(bracket)
	_append("")
	if champ is Dictionary:
		_show_champion_header(champ)
		_append("[b]CHAMPION: %s[/b]" % champ.get("name", "?"))
		_status.text = "Champion: %s" % champ.get("name", "?")
	await _wait_continue("Claim the lists")

	var winner_pid := -1
	var winner_is_npc := true
	var champ_knight: Dictionary = {}
	if champ is Dictionary:
		champ_knight = champ
		if champ.has("owner_pid") or champ.has("is_npc_knight"):
			winner_pid = int(champ.get("owner_pid", -1))
			winner_is_npc = bool(champ.get("is_npc_knight", winner_pid < 0))
		else:
			for e in entrants:
				if str(e.get("knight", {}).get("name", "")) == str(champ.get("name", "")):
					winner_pid = int(e.get("pid", -1))
					winner_is_npc = bool(e.get("is_npc", true))
					champ_knight["owner_pid"] = winner_pid
					champ_knight["is_npc_knight"] = winner_is_npc
					break
	_finish(winner_pid, winner_is_npc, champ_knight if champ is Dictionary else {})


func _run_managed_match(ka: Dictionary, kb: Dictionary) -> Dictionary:
	JoustKnight.reset_for_match(ka)
	JoustKnight.reset_for_match(kb)
	var engine := JoustEngine.new(rules)
	var all_events: Array = []
	var pass_num := 0
	var num_passes := int(rules.get("num_passes", 3))
	var player := ka if str(ka.get("name", "")) == _player_knight_name else kb
	var opponent := kb if player == ka else ka

	while pass_num < num_passes:
		pass_num += 1
		var score_a_before := int(ka.get("score", 0))
		var score_b_before := int(kb.get("score", 0))

		_status.text = "Pass %d — set your strategy" % pass_num
		_append("Pass %d — Your score %d | Opponent %d | Fatigue %.0f%%" % [
			pass_num,
			int(player.get("score", 0)),
			int(opponent.get("score", 0)),
			(1.0 - JoustKnight.fatigue_factor(player.get("horse", {}))) * 100.0,
		])
		var decision := await _prompt_decision()
		var dec_a := decision if player == ka else JoustStrategy.ai_decide(ka, engine.build_context(ka, kb, pass_num))
		var dec_b := decision if player == kb else JoustStrategy.ai_decide(kb, engine.build_context(kb, ka, pass_num))
		var events := engine.resolve_single_pass(ka, kb, pass_num, dec_a, dec_b)
		all_events.append(events)
		var lines := JoustNarrator.narrate_pass(events, true)
		for line in lines:
			_append(str(line))
			await get_tree().create_timer(0.04).timeout

		if bool(rules.get("lance_tip_clash_voids_round", false)):
			var voided := false
			for e in events:
				if e is Dictionary and str(e.get("type", "")) == "lance_tip_clash":
					voided = true
					break
			if voided:
				ka["score"] = score_a_before
				kb["score"] = score_b_before
				pass_num -= 1
				continue

		if bool(ka.get("disqualified", false)) or bool(kb.get("disqualified", false)):
			break
		if not JoustKnight.can_fight(ka) or not JoustKnight.can_fight(kb):
			break
		if bool(rules.get("unhorse_wins_match", false)):
			var end_u := false
			for e in events:
				if e is Dictionary and str(e.get("type", "")) == "fall" and int(e.get("fall_type", -1)) == JoustTypes.FallType.UNHORSED:
					end_u = true
					break
			if end_u:
				break

	var outcome := engine.determine_winner(ka, kb)
	var final := {
		"type": "match_end",
		"winner": str(outcome["winner"].get("name", "")),
		"loser": str(outcome["loser"].get("name", "")),
		"final_score_winner": int(outcome["winner"].get("score", 0)),
		"final_score_loser": int(outcome["loser"].get("score", 0)),
		"reason": str(outcome["reason"]),
	}
	all_events.append([final])
	for line in JoustNarrator.narrate_pass([final], true):
		_append(str(line))
	return {
		"events_per_pass": all_events,
		"winner": outcome["winner"],
		"loser": outcome["loser"],
		"final_event": final,
	}


func _prompt_decision() -> Dictionary:
	_clear_decision_boxes()
	_aim_box.visible = true
	_agg_box.visible = true
	_guard_box.visible = true
	_pending_decision = {}
	_decision_ready = false

	_add_choice(_aim_box, "Aim: Center", {"aim": JoustTypes.AimTarget.SHIELD_CENTER})
	_add_choice(_aim_box, "Aim: Edge", {"aim": JoustTypes.AimTarget.SHIELD_EDGE})
	_add_choice(_aim_box, "Aim: Armor", {"aim": JoustTypes.AimTarget.ARMOR})
	_add_choice(_aim_box, "Aim: High", {"aim": JoustTypes.AimTarget.HIGH})

	while not _decision_ready or not _pending_decision.has("aim"):
		await get_tree().process_frame
	_aim_box.visible = false
	_decision_ready = false
	var aim := int(_pending_decision.get("aim", 0))
	_pending_decision = {"aim": aim}

	_add_choice(_agg_box, "Speed: Careful", {"aggression": JoustTypes.Aggression.CONSERVATIVE})
	_add_choice(_agg_box, "Speed: Normal", {"aggression": JoustTypes.Aggression.NORMAL})
	_add_choice(_agg_box, "Speed: Hard", {"aggression": JoustTypes.Aggression.AGGRESSIVE})
	while not _decision_ready or not _pending_decision.has("aggression"):
		await get_tree().process_frame
	_agg_box.visible = false
	_decision_ready = false
	var agg := int(_pending_decision.get("aggression", 1))
	_pending_decision = {"aim": aim, "aggression": agg}

	_add_choice(_guard_box, "Guard: High", {"shield_guard": JoustTypes.ShieldGuard.HIGH})
	_add_choice(_guard_box, "Guard: Center", {"shield_guard": JoustTypes.ShieldGuard.CENTER})
	_add_choice(_guard_box, "Guard: Low", {"shield_guard": JoustTypes.ShieldGuard.LOW})
	while not _decision_ready or not _pending_decision.has("shield_guard"):
		await get_tree().process_frame
	_guard_box.visible = false
	var guard := int(_pending_decision.get("shield_guard", 1))
	_clear_decision_boxes()
	return {"aim": aim, "aggression": agg, "shield_guard": guard}


func _clear_decision_boxes() -> void:
	for box in [_aim_box, _agg_box, _guard_box]:
		for c in box.get_children():
			c.queue_free()
		box.visible = false


func _add_choice(box: HBoxContainer, text: String, partial: Dictionary) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(func():
		for k in partial.keys():
			_pending_decision[k] = partial[k]
		_decision_ready = true
	)
	box.add_child(btn)
	box.visible = true


func _finish(winner_pid: int, winner_is_npc: bool, champ: Dictionary) -> void:
	finished.emit(winner_pid, winner_is_npc, champ)
	queue_free()
