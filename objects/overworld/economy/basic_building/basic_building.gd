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


func worker_cap() -> int:
	if not is_built():
		return 0
	match int(stage):
		1: return GlobalUnits.ECONOMY_WORKERS_SMALL # SMALL
		2: return GlobalUnits.ECONOMY_WORKERS_MEDIUM
		3: return GlobalUnits.ECONOMY_WORKERS_BIG
		_: return GlobalUnits.ECONOMY_WORKERS_SMALL


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
	match sub as SUBTYPES:
		SUBTYPES.WOODCUTTER: return GlobalUnits.ECONOMY_COST_WOODCUTTER
		SUBTYPES.BLACKSMITH: return GlobalUnits.ECONOMY_COST_BLACKSMITH
		SUBTYPES.STONEQUARRY, SUBTYPES.IRONMINE, SUBTYPES.SILVERMINE:
			return GlobalUnits.ECONOMY_COST_MINE
		_: return 0


func can_build(sub: int) -> bool:
	return allowed_build_subtypes().has(sub as SUBTYPES)


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
		SUBTYPES.WOODCUTTER: {STAGES.SMALL: preload("uid://c43brywdf0lxo")},
		SUBTYPES.STONEQUARRY: {STAGES.SMALL: preload("uid://ft668a4yuq1k")},
		SUBTYPES.BLACKSMITH: {
			STAGES.SMALL: preload("uid://cyg7nwmf3kopv"),
			STAGES.MEDIUM: preload("uid://cyg7nwmf3kopv"),
			STAGES.BIG: preload("uid://cyg7nwmf3kopv"),
		},
		SUBTYPES.IRONMINE: {
			STAGES.SMALL: preload("uid://cuidag43bhr3p"),
			STAGES.MEDIUM: preload("uid://cuidag43bhr3p"),
			STAGES.BIG: preload("uid://cuidag43bhr3p"),
		},
		SUBTYPES.SILVERMINE: {
			STAGES.SMALL: preload("uid://bwmwh435mm4nd"),
			STAGES.MEDIUM: preload("uid://bwmwh435mm4nd"),
			STAGES.BIG: preload("uid://bwmwh435mm4nd"),
		},
	}
	var subtype_tex: Dictionary = textures.get(subtype, {})
	var tex = subtype_tex.get(stage, subtype_tex.get(STAGES.SMALL, null))
	if tex != null:
		building_spr.texture = tex
	else:
		building_spr.texture = preload("uid://c43brywdf0lxo")


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
