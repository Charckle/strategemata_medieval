extends Node2D

## OPEN pads: woodcutter / blacksmith. DEPOSIT pads: only the matching mine/quarry.
enum SLOT_KIND { OPEN, DEPOSIT }
enum DEPOSIT_TYPE { NONE, STONE, IRON, SILVER }
enum SUBTYPES { WOODCUTTER, IRONMINE, GOLDMINE, SILVERMINE, STONEQUARRY, BLACKSMITH }
enum STAGES { EMPTY, SMALL, MEDIUM, BIG, RAZED }

var type_ = GlobalStuff.BUILDING_TYPE.ECONOMY

@export var slot_kind: SLOT_KIND = SLOT_KIND.OPEN
@export var deposit_type: DEPOSIT_TYPE = DEPOSIT_TYPE.NONE
@export var subtype: SUBTYPES = SUBTYPES.WOODCUTTER
@export var stage: STAGES = STAGES.EMPTY
@export var player_owner = 1

## Blacksmith only: weapon key from GlobalUnits.BLACKSMITH_CRAFTABLE, or "" idle.
@export var craft_weapon: String = "maces"

const GARRISON_CAPACITY := 50
@export var start_garrison: Array = []

var base_map

@onready var building_spr: Sprite2D = $building_spr
@onready var ground: Sprite2D = $ground


func get_garrison_capacity(_spot: int = GlobalUnits.SPOT.FLAT) -> int:
	return GARRISON_CAPACITY


func setup_building() -> void:
	set_flags()


func set_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag != null:
		flag.setup_flag()


func get_garrison_units() -> Array:
	if base_map == null:
		return []
	return base_map.get_all_building_garrison(self)


func get_owner_set() -> Array:
	return GlobalUnits.owners_in(get_garrison_units())


func get_banner_pids() -> Array:
	return get_owner_set()


func shows_ownership_triangle() -> bool:
	return false


func get_pathfinding_blocked_tile_centers() -> Array:
	return [global_position + Vector2(32, 16)]


func _ready() -> void:
	update_for_stage()


func is_built() -> bool:
	var st := int(stage)
	return st != int(STAGES.EMPTY) and st != int(STAGES.RAZED)


func _stage_index() -> int:
	## 0=Small, 1=Medium, 2=Big; -1 if not a sized built stage.
	match int(stage):
		1: return 0 # SMALL
		2: return 1 # MEDIUM
		3: return 2 # BIG
		_: return -1


func worker_cap() -> int:
	if not is_built():
		return 0
	var idx := _stage_index()
	if idx < 0:
		return GlobalUnits.economy_workers_for(int(subtype), 0)
	return GlobalUnits.economy_workers_for(int(subtype), idx)


func labor_category() -> String:
	if not is_built():
		return ""
	match int(subtype):
		0: return "wood" # WOODCUTTER
		1: return "iron" # IRONMINE
		3: return "silver" # SILVERMINE
		4: return "stone" # STONEQUARRY
		5: return "blacksmith"
		_: return ""


func allowed_build_subtypes() -> Array:
	if is_built():
		return []
	if slot_kind == SLOT_KIND.OPEN:
		return [SUBTYPES.WOODCUTTER, SUBTYPES.BLACKSMITH]
	match deposit_type:
		DEPOSIT_TYPE.STONE: return [SUBTYPES.STONEQUARRY]
		DEPOSIT_TYPE.IRON: return [SUBTYPES.IRONMINE]
		DEPOSIT_TYPE.SILVER: return [SUBTYPES.SILVERMINE]
		_: return []


func build_cost_for(sub: int) -> int:
	return GlobalUnits.economy_stage_cost(sub, 0)


func can_build(sub: int) -> bool:
	return allowed_build_subtypes().has(sub as SUBTYPES)


func can_upgrade() -> bool:
	if not is_built():
		return false
	var idx := _stage_index()
	return idx == 0 or idx == 1


func next_stage() -> int:
	match int(stage):
		1: return int(STAGES.MEDIUM) # SMALL → MEDIUM
		2: return int(STAGES.BIG) # MEDIUM → BIG
		_: return int(stage)


func upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	var idx := _stage_index()
	# Cost of the stage we are upgrading into (Medium=1, Big=2).
	return GlobalUnits.economy_stage_cost(int(subtype), idx + 1)


func apply_build(sub: int, owner_id: int) -> void:
	subtype = sub as SUBTYPES
	stage = STAGES.SMALL
	player_owner = owner_id
	if int(subtype) == int(SUBTYPES.BLACKSMITH):
		craft_weapon = "maces"
	else:
		craft_weapon = ""
	update_for_stage()
	set_flags()


func apply_upgrade() -> void:
	if not can_upgrade():
		return
	match int(stage):
		1: stage = STAGES.MEDIUM
		2: stage = STAGES.BIG
		_: return
	update_for_stage()
	set_flags()


func apply_demolish() -> void:
	stage = STAGES.EMPTY
	craft_weapon = ""
	update_for_stage()
	set_flags()


func is_blacksmith() -> bool:
	return is_built() and int(subtype) == int(SUBTYPES.BLACKSMITH)


func set_craft_weapon(weapon_key: String) -> void:
	if weapon_key != "" and weapon_key not in GlobalUnits.BLACKSMITH_CRAFTABLE:
		return
	craft_weapon = weapon_key


func get_craft_weapon() -> String:
	if not is_blacksmith():
		return ""
	return craft_weapon


func update_for_stage() -> void:
	change_sprite()


func change_sprite() -> void:
	# Ground pad is always the shared economy base; deposit/building art sits on building_spr.
	if ground != null:
		ground.visible = true
		ground.texture = preload("uid://hyku2irqn8sl")
	if building_spr == null:
		return
	var unbuilt := stage == STAGES.EMPTY or stage == STAGES.RAZED
	if unbuilt:
		var deposit_tex := _unbuilt_deposit_texture()
		if deposit_tex != null:
			building_spr.visible = true
			building_spr.texture = deposit_tex
		else:
			building_spr.visible = false
		return
	building_spr.visible = true
	var textures := {
		SUBTYPES.WOODCUTTER: {
			STAGES.SMALL: preload("res://sprites/overworld/objects/province/economy/woodcutter/woodcutter.png"),
			STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/economy/woodcutter/woodcutter_lvl2.png"),
			STAGES.BIG: preload("res://sprites/overworld/objects/province/economy/woodcutter/woodcutter_lvl3.png"),
		},
		SUBTYPES.STONEQUARRY: {
			STAGES.SMALL: preload("res://sprites/overworld/objects/province/economy/stonequarry/stonequarry.png"),
			STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/economy/stonequarry/stonequarry_lvl2.png"),
			STAGES.BIG: preload("res://sprites/overworld/objects/province/economy/stonequarry/stonequarry_lvl3.png"),
		},
		SUBTYPES.BLACKSMITH: {
			STAGES.SMALL: preload("res://sprites/overworld/objects/province/economy/blacksmith/blacksmith.png"),
			STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/economy/blacksmith/blacksmith_lvl2.png"),
			STAGES.BIG: preload("res://sprites/overworld/objects/province/economy/blacksmith/blacksmith_lvl3.png"),
		},
		SUBTYPES.IRONMINE: {
			STAGES.SMALL: preload("res://sprites/overworld/objects/province/economy/iron_mine/iron_mine.png"),
			STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/economy/iron_mine/iron_mine_lvl2.png"),
			STAGES.BIG: preload("res://sprites/overworld/objects/province/economy/iron_mine/iron_mine_lvl3.png"),
		},
		SUBTYPES.SILVERMINE: {
			STAGES.SMALL: preload("res://sprites/overworld/objects/province/economy/silver_mine/silver_mine.png"),
			STAGES.MEDIUM: preload("res://sprites/overworld/objects/province/economy/silver_mine/silver_mine_lvl2.png"),
			STAGES.BIG: preload("res://sprites/overworld/objects/province/economy/silver_mine/silver_mine_lvl3.png"),
		},
	}
	var subtype_tex: Dictionary = textures.get(subtype, {})
	var tex = subtype_tex.get(stage, subtype_tex.get(STAGES.SMALL, null))
	if tex != null:
		building_spr.texture = tex
	else:
		building_spr.texture = preload("res://sprites/overworld/objects/province/economy/woodcutter/woodcutter.png")


func _unbuilt_deposit_texture() -> Texture2D:
	if slot_kind != SLOT_KIND.DEPOSIT:
		return null
	match deposit_type:
		DEPOSIT_TYPE.STONE:
			return preload("uid://bur7n2w0ha3lc")
		DEPOSIT_TYPE.IRON:
			return preload("uid://dcu7coff4tvb")
		DEPOSIT_TYPE.SILVER:
			return preload("uid://cf1w5fxqumsj1")
		_:
			return null


func get_subtype_name() -> String:
	if stage == STAGES.EMPTY:
		return _empty_pad_name()
	return subtype_display_name(int(subtype))


static func subtype_display_name(sub: int) -> String:
	match sub:
		SUBTYPES.WOODCUTTER: return "Woodcutter"
		SUBTYPES.IRONMINE: return "Iron Mine"
		SUBTYPES.GOLDMINE: return "Gold Mine"
		SUBTYPES.SILVERMINE: return "Silver Mine"
		SUBTYPES.STONEQUARRY: return "Stone Quarry"
		SUBTYPES.BLACKSMITH: return "Blacksmith"
	return "Economy Building"


func _empty_pad_name() -> String:
	if slot_kind == SLOT_KIND.OPEN:
		return "Empty plot"
	match deposit_type:
		DEPOSIT_TYPE.STONE: return "Stone deposit"
		DEPOSIT_TYPE.IRON: return "Iron deposit"
		DEPOSIT_TYPE.SILVER: return "Silver deposit"
		_: return "Empty deposit"


func get_stage_name() -> String:
	match stage:
		STAGES.EMPTY: return "Empty"
		STAGES.SMALL: return "Small"
		STAGES.MEDIUM: return "Medium"
		STAGES.BIG: return "Big"
		STAGES.RAZED: return "Razed"
	return ""


func get_slot_description() -> String:
	if slot_kind == SLOT_KIND.OPEN:
		return "Open plot (woodcutter or blacksmith)"
	match deposit_type:
		DEPOSIT_TYPE.STONE: return "Stone deposit (quarry only)"
		DEPOSIT_TYPE.IRON: return "Iron deposit (mine only)"
		DEPOSIT_TYPE.SILVER: return "Silver deposit (mine only)"
	return "Deposit"
