extends Node2D

enum PROVINCE_STATUS { STABLE, DISPUTED, OCCUPIED, CONQUERED }

var resources

@export var p_name = "Gondor"
@export var player_owner = 1
@export var home_province = false
var dejure
var defacto

var status_ = PROVINCE_STATUS.STABLE

@onready var settlements = $settlements
@onready var fields = $fields
@onready var economy = $economy
@onready var defense = $defense
@onready var map_labels = $map_labels
@onready var _name_label: Label = $map_labels/name_label
@onready var _status_label: Label = $map_labels/status_label
@onready var _owner_label: Label = $map_labels/owner_label

# Reference to the overworld map (OBaseMap); set from parent hierarchy if not set.
@onready var base_map

const MAP_LABEL_LINE_HEIGHT := 18.0

var _label_center := Vector2.ZERO

func _ready() -> void:
	create_de_resorce_dict()
	dejure = player_owner
	defacto = player_owner
	status_ = get_status()
	allocate_fields_to_settlements()


func set_flags():
	for settlement in settlements.get_children():
		settlement.setup_building()

func get_status() -> PROVINCE_STATUS:
	# Placeholder: rules will be added later
	return PROVINCE_STATUS.STABLE

func sync_player_owner_to_children() -> void:
	for container in [settlements, economy, defense]:
		for child in container.get_children():
			if child.get("player_owner") != null:
				child.player_owner = player_owner
			if child.base_map == null and base_map != null:
				child.base_map = base_map


func set_ownership(new_dejure: int, new_defacto: int) -> void:
	dejure = new_dejure
	defacto = new_defacto
	player_owner = new_dejure
	status_ = get_status()
	sync_player_owner_to_children()
	refresh_map_label()


func setup_map_label() -> void:
	_label_center = get_geographic_center()
	map_labels.position = _label_center
	refresh_map_label()


func get_geographic_center() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for container in [settlements, fields, economy, defense]:
		for child in container.get_children():
			sum += child.position
			count += 1
	if count > 0:
		return sum / float(count)
	return Vector2.ZERO


func get_label_world_position() -> Vector2:
	return global_position + _label_center


func refresh_map_label() -> void:
	if base_map == null:
		return
	var players_dict: Dictionary = base_map.players if base_map.get("players") else {}
	_name_label.text = p_name
	if status_ == PROVINCE_STATUS.STABLE:
		_status_label.visible = false
		_status_label.text = ""
	else:
		_status_label.visible = true
		_status_label.text = get_status_name()
		_status_label.modulate = _get_status_color()
	_owner_label.text = _format_owner_line(players_dict)
	_layout_map_labels()


func set_map_label_alpha(alpha: float) -> void:
	var color = map_labels.modulate
	color.a = alpha
	map_labels.modulate = color
	map_labels.visible = alpha > 0.001


func set_map_label_scale(scale_factor: float) -> void:
	map_labels.scale = Vector2.ONE * scale_factor


func _format_owner_line(players_dict: Dictionary) -> String:
	var dejure_name := _player_name(players_dict, dejure)
	var defacto_name := _player_name(players_dict, defacto)
	if dejure == defacto:
		return dejure_name
	return "%s · %s" % [dejure_name, defacto_name]


func _player_name(players_dict: Dictionary, player_id: int) -> String:
	if players_dict.has(player_id):
		return str(players_dict[player_id].name_)
	return "Unknown"


func _get_status_color() -> Color:
	match status_:
		PROVINCE_STATUS.DISPUTED:
			return Color(1.0, 0.85, 0.2)
		PROVINCE_STATUS.OCCUPIED:
			return Color(1.0, 0.55, 0.2)
		PROVINCE_STATUS.CONQUERED:
			return Color(1.0, 0.3, 0.3)
		_:
			return Color.WHITE


func _layout_map_labels() -> void:
	var lines: Array[Label] = [_name_label]
	if _status_label.visible:
		lines.append(_status_label)
	lines.append(_owner_label)
	var total_h := MAP_LABEL_LINE_HEIGHT * lines.size()
	var y := -total_h / 2.0 + MAP_LABEL_LINE_HEIGHT / 2.0
	for lbl in lines:
		lbl.position = Vector2(0.0, y)
		y += MAP_LABEL_LINE_HEIGHT


func create_de_resorce_dict():
	var _resource = {
		"grain": {
			"has": 0,
			"will": 0
		},
		"population": {
			"has": {},  # player_id -> total; "all" -> sum
			"will": {}  # player_id -> predicted total; "all" -> sum
		},
		"wood": {
			"will": 0
		},
		"stone": {
			"will": 0
		},
		"iron": {
			"will": 0
		},
		"people": {
			"has": 0,
			"will": 0
		},
		"marks": {
			"will": {}  # player_id -> amount; "all" -> sum of all players
		}
	}
	resources = _resource

func allocate_fields_to_settlements() -> void:
	var field_list: Array = fields.get_children()
	var settlement_list: Array = settlements.get_children()

	if settlement_list.is_empty() or field_list.is_empty():
		return

	var num_fields := field_list.size()
	var num_settlements := settlement_list.size()
	var fields_per_settlement := int(ceil(num_fields / float(num_settlements)))

	for settlement in settlement_list:
		settlement.fields.clear()
	for f in field_list:
		f.owner_building = null

	for settlement in settlement_list:
		var needed := fields_per_settlement
		while needed > 0:
			var best_field = null
			var best_dist := INF
			for f in field_list:
				if f.owner_building != null:
					continue
				var d = settlement.global_position.distance_squared_to(f.global_position)
				if d < best_dist:
					best_dist = d
					best_field = f
			if best_field == null:
				break
			best_field.owner_building = settlement
			settlement.fields.append(best_field)
			needed -= 1


func recalculate_settlements_growth() -> void:
	var settlement_list: Array = settlements.get_children()
	for settlement in settlement_list:
		if settlement.has_method("calculate_predicted_growth"):
			settlement.calculate_predicted_growth()
	update_population_in_resources()


func update_population_in_resources() -> void:
	var settlement_list: Array = settlements.get_children()
	var has_by_player: Dictionary = {}
	var will_by_player: Dictionary = {}
	for s in settlement_list:
		if s.get("player_owner") == null:
			continue
		var pid = s.player_owner
		var pop = s.population if s.get("population") != null else 0
		var pred = s.predicted_growth if s.get("predicted_growth") != null else 0
		has_by_player[pid] = has_by_player.get(pid, 0) + pop
		will_by_player[pid] = will_by_player.get(pid, 0) + pop + pred
	var has_total := 0
	var will_total := 0
	for pid in has_by_player:
		has_total += has_by_player[pid]
		will_total += will_by_player[pid]
	has_by_player["all"] = has_total
	will_by_player["all"] = will_total
	resources["population"]["has"] = has_by_player
	resources["population"]["will"] = will_by_player


func apply_predicted_growth_to_settlements() -> void:
	var settlement_list: Array = settlements.get_children()
	for settlement in settlement_list:
		settlement.population += settlement.predicted_growth
	update_population_in_resources()


func recalculate_marks_will_by_player() -> void:
	var settlement_list: Array = settlements.get_children()
	for s in settlement_list:
		if s.has_method("calculate_predicted_marks"):
			s.calculate_predicted_marks()
	var will_by_player: Dictionary = {}
	for s in settlement_list:
		if s.get("player_owner") == null or s.get("predicted_marks") == null:
			continue
		var pid = s.player_owner
		will_by_player[pid] = will_by_player.get(pid, 0) + s.predicted_marks
	var total := 0
	for pid in will_by_player:
		total += will_by_player[pid]
	will_by_player["all"] = total
	resources["marks"]["will"] = will_by_player


func _count_buildings_in_node(node: Node, control_player_id: int) -> Dictionary:
	var control := 0
	var all_count := 0
	for child in node.get_children():
		all_count += 1
		if child.get("player_owner") != null and child.player_owner == control_player_id:
			control += 1
	return {"control": control, "all": all_count}


func get_building_counts() -> Dictionary:
	var ctrl = defacto
	var villages := _count_by_type(settlements, GlobalStuff.BUILDING_TYPE.VILLAGE, ctrl)
	var towns := _count_by_type(settlements, GlobalStuff.BUILDING_TYPE.TOWN, ctrl)
	# defense/economy: count all children (castles may not have type_ set yet)
	var castles := _count_buildings_in_node(defense, ctrl)
	var economy_buildings := _count_buildings_in_node(economy, ctrl)
	return {
		"villages": villages,
		"towns": towns,
		"castles": castles,
		"economy": economy_buildings
	}


func _count_by_type(node: Node, btype: int, control_player_id: int) -> Dictionary:
	var control := 0
	var all_count := 0
	for child in node.get_children():
		if child.get("type_") != null and child.type_ == btype:
			if child.get("player_owner") != null:
				all_count += 1
			if child.player_owner == control_player_id:
				control += 1
	return {"control": control, "all": all_count}


func get_status_name() -> String:
	match status_:
		PROVINCE_STATUS.STABLE: return "Stable"
		PROVINCE_STATUS.DISPUTED: return "Disputed"
		PROVINCE_STATUS.OCCUPIED: return "Occupied"
		PROVINCE_STATUS.CONQUERED: return "Conquered"
		_: return "Unknown"

func get_display_data(players_dict: Dictionary) -> Dictionary:
	var owner_name := ""
	var defacto_name := ""
	var dejure_name := ""
	if players_dict.has(player_owner):
		owner_name = players_dict[player_owner].name_
	if players_dict.has(defacto):
		defacto_name = players_dict[defacto].name_
	if players_dict.has(dejure):
		dejure_name = players_dict[dejure].name_
	var counts = get_building_counts()
	return {
		"name": p_name,
		"status": status_,
		"status_name": get_status_name(),
		"owner_name": owner_name,
		"defacto_name": defacto_name,
		"dejure_name": dejure_name,
		"population_has": resources["population"]["has"].get("all", 0),
		"population_will": resources["population"]["will"].get("all", 0),
		"marks_will": resources["marks"]["will"].get("all", 0),
		"villages": counts["villages"],
		"towns": counts["towns"],
		"castles": counts["castles"],
		"economy": counts["economy"]
	}
