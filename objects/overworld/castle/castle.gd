extends Node2D

var type_ = GlobalStuff.BUILDING_TYPE.CASTLE

enum CASTLE_TYPE { WOODEN_FORT, MOTTE_AND_BAILEY, NORMAN_KEEP, ENCLOSED_CASTLE, POLIWARDED_CASTLE, CONCENTRIC_CASTLE }

# Men each type holds INSIDE (gets the castle bonus). OUTSIDE holds double, no bonus.
const INSIDE_CAPACITY := {
	CASTLE_TYPE.WOODEN_FORT: 100,
	CASTLE_TYPE.MOTTE_AND_BAILEY: 200,
	CASTLE_TYPE.NORMAN_KEEP: 250,
	CASTLE_TYPE.ENCLOSED_CASTLE: 500,
	CASTLE_TYPE.POLIWARDED_CASTLE: 700,
	CASTLE_TYPE.CONCENTRIC_CASTLE: 1000,
}

## Standing finished level when `has_castle`; ignored while empty.
@export var castle_type: CASTLE_TYPE = CASTLE_TYPE.WOODEN_FORT
## False = empty defense plot (no standing castle).
@export var has_castle: bool = true

@export var player_owner = 1

# Designer-authored starting garrisons (Arrays of stack specs); see GlobalUnits.units_from_spec.
@export var start_inside: Array = []
@export var start_outside: Array = []

var base_map: Node = null

# Construction project (offline worksite while active).
var project_active: bool = false
## Target CASTLE_TYPE, or GlobalUnits.CASTLE_TARGET_EMPTY for dismantle-to-empty.
var project_target: int = GlobalUnits.CASTLE_TARGET_EMPTY
var project_progress: int = 0
var project_work_needed: int = 0
## Materials locked on site (paid upfront / retained from prior level).
var materials_on_site: Dictionary = {"wood": 0, "stone": 0}
## Last completed level at project start (−1 if was empty). Used for restore / refunds.
var project_base_level: int = GlobalUnits.CASTLE_TARGET_EMPTY

@onready var castle_spr: Sprite2D = $castle_spr
@onready var ground: Sprite2D = $ground


func _ready() -> void:
	refresh_visuals()


func get_inside_capacity() -> int:
	if not is_operational():
		return 0
	return INSIDE_CAPACITY.get(castle_type, 0)

func get_outside_capacity() -> int:
	return get_inside_capacity() * 2

func get_garrison_capacity(spot: int = GlobalUnits.SPOT.INSIDE) -> int:
	if not is_operational():
		return 0
	if spot == GlobalUnits.SPOT.OUTSIDE:
		return get_outside_capacity()
	return get_inside_capacity()


func is_built() -> bool:
	return has_castle


func is_under_construction() -> bool:
	return project_active


func is_operational() -> bool:
	return has_castle and not project_active


func is_army_interactable() -> bool:
	return is_operational()


## Holding-wide marks bonus fraction on Σ settlement base. Mid-build / empty = 0.
func holding_marks_bonus_fraction() -> float:
	if not is_operational():
		return 0.0
	return GlobalUnits.castle_holding_marks_bonus(int(castle_type))


func standing_level() -> int:
	if has_castle:
		return int(castle_type)
	return GlobalUnits.CASTLE_TARGET_EMPTY


func get_castle_type_name() -> String:
	return castle_type_display_name(int(castle_type))


static func castle_type_display_name(level: int) -> String:
	match level:
		CASTLE_TYPE.WOODEN_FORT: return "Wooden Fort"
		CASTLE_TYPE.MOTTE_AND_BAILEY: return "Motte-and-Bailey"
		CASTLE_TYPE.NORMAN_KEEP: return "Norman Keep"
		CASTLE_TYPE.ENCLOSED_CASTLE: return "Enclosed Castle"
		CASTLE_TYPE.POLIWARDED_CASTLE: return "Poliwarded Castle"
		CASTLE_TYPE.CONCENTRIC_CASTLE: return "Concentric Castle"
	return "Castle"


func get_stage_name() -> String:
	if project_active:
		var tgt := "empty" if project_target < 0 else castle_type_display_name(project_target)
		return "Building %s (%d / %d)" % [tgt, project_progress, project_work_needed]
	if not has_castle:
		return "Empty plot"
	return get_castle_type_name()


func setup_building() -> void:
	set_flags()
	refresh_visuals()


func set_flags() -> void:
	var flag := get_node_or_null("Flag")
	if flag != null:
		flag.visible = is_operational()
		if flag.visible:
			flag.setup_flag()
	var outside_flag := get_node_or_null("OutsideFlag")
	if outside_flag != null:
		outside_flag.visible = is_operational()
		if outside_flag.visible:
			outside_flag.setup_flag()
	refresh_vip_crown()


func refresh_vip_crown() -> void:
	var crown := get_node_or_null("crown")
	if crown == null:
		return
	var show := false
	if is_operational() and base_map != null and base_map.has_method("building_has_any_vip"):
		show = base_map.building_has_any_vip(self)
	crown.visible = show


const CASTLE_TEXTURES := {
	CASTLE_TYPE.WOODEN_FORT: preload("res://sprites/overworld/objects/province/castle/wooden_fort.png"),
	CASTLE_TYPE.MOTTE_AND_BAILEY: preload("res://sprites/overworld/objects/province/castle/castle_mot_and_baily.png"),
	CASTLE_TYPE.NORMAN_KEEP: preload("res://sprites/overworld/objects/province/castle/norman_keep.png"),
	CASTLE_TYPE.ENCLOSED_CASTLE: preload("res://sprites/overworld/objects/province/castle/enclosed_castle.png"),
	CASTLE_TYPE.POLIWARDED_CASTLE: preload("res://sprites/overworld/objects/province/castle/poliwarded_castle.png"),
	CASTLE_TYPE.CONCENTRIC_CASTLE: preload("res://sprites/overworld/objects/province/castle/concentric_castle.png"),
}


func refresh_visuals() -> void:
	if castle_spr == null:
		return
	if not has_castle and not project_active:
		castle_spr.visible = false
		return
	castle_spr.visible = true
	var show_level := standing_level()
	if project_active and project_target >= 0:
		show_level = project_target
	elif project_active and project_base_level >= 0:
		show_level = project_base_level
	if show_level < 0:
		castle_spr.visible = false
		return
	var tex: Texture2D = CASTLE_TEXTURES.get(show_level, CASTLE_TEXTURES[CASTLE_TYPE.WOODEN_FORT])
	if tex != null:
		castle_spr.texture = tex
	castle_spr.modulate = Color(0.75, 0.75, 0.7, 1.0) if project_active else Color.WHITE


func get_garrison_units() -> Array:
	if base_map == null:
		return []
	return base_map.get_all_building_garrison(self)


func get_inside_garrison_units() -> Array:
	if base_map == null:
		return []
	return base_map.get_building_garrison(self, GlobalUnits.SPOT.INSIDE)


func get_outside_garrison_units() -> Array:
	if base_map == null:
		return []
	return base_map.get_building_garrison(self, GlobalUnits.SPOT.OUTSIDE)


func get_owner_set() -> Array:
	return GlobalUnits.owners_in(get_garrison_units())


## Top flag: inside garrison owners only.
func get_banner_pids() -> Array:
	return GlobalUnits.owners_in(get_inside_garrison_units())


## Left corner flag: outside garrison owners only.
func get_outside_banner_pids() -> Array:
	return GlobalUnits.owners_in(get_outside_garrison_units())


func shows_ownership_triangle() -> bool:
	return false

func get_pathfinding_blocked_tile_centers() -> Array:
	return [
		global_position + Vector2(32, 32),
		global_position + Vector2(64, 16),
		global_position + Vector2(64, 48),
		global_position + Vector2(96, 32)
	]


func materials_for_standing() -> Dictionary:
	return GlobalUnits.castle_material_cost(standing_level())


## Work / pay preview for switching the project (or starting one) to `new_target`.
## Returns {} if invalid. Keys: work_needed, progress_keep, pay, refund_on_complete,
## complete_immediately, restore_mode, expel.
func preview_retarget(new_target: int) -> Dictionary:
	if new_target < GlobalUnits.CASTLE_TARGET_EMPTY or new_target > int(CASTLE_TYPE.CONCENTRIC_CASTLE):
		return {}
	if project_active and new_target == project_target:
		return {}
	var base_lvl := standing_level() if not project_active else project_base_level
	var on_site := materials_on_site.duplicate() if project_active else materials_for_standing()
	if not project_active and not has_castle:
		on_site = {"wood": 0, "stone": 0}

	# Mid-project: retarget down to a finished level whose work is already met → instant complete.
	if project_active and new_target >= 0:
		var need_t := GlobalUnits.castle_work_required(new_target)
		if project_progress >= need_t and new_target != project_target:
			var want := GlobalUnits.castle_material_cost(new_target)
			return {
				"work_needed": 0,
				"progress_keep": 0,
				"pay": {"wood": 0, "stone": 0},
				"refund_now": {
					"wood": maxi(0, int(on_site.get("wood", 0)) - int(want.get("wood", 0))),
					"stone": maxi(0, int(on_site.get("stone", 0)) - int(want.get("stone", 0))),
				},
				"refund_on_complete": {"wood": 0, "stone": 0},
				"complete_immediately": true,
				"restore_mode": false,
				"expel": false,
				"base_level": base_lvl,
				"materials_after": want,
			}

	# Restore to previous completed level (cancel upgrade / abandon toward empty base).
	if project_active and new_target == base_lvl and base_lvl >= 0:
		var restore_work := int(ceil(float(project_progress) * 0.5))
		var want_b := GlobalUnits.castle_material_cost(base_lvl)
		return {
			"work_needed": restore_work,
			"progress_keep": 0,
			"pay": {"wood": 0, "stone": 0},
			"refund_now": {"wood": 0, "stone": 0},
			"refund_on_complete": {
				"wood": maxi(0, int(on_site.get("wood", 0)) - int(want_b.get("wood", 0))),
				"stone": maxi(0, int(on_site.get("stone", 0)) - int(want_b.get("stone", 0))),
			},
			"complete_immediately": restore_work <= 0,
			"restore_mode": true,
			"expel": false,
			"base_level": base_lvl,
			"materials_after": on_site,
		}

	# Cancel mid-build toward empty (from empty base, or dismantle cancel path).
	if project_active and new_target < 0:
		var clear_work := int(ceil(float(project_progress) * 0.5))
		return {
			"work_needed": clear_work,
			"progress_keep": 0,
			"pay": {"wood": 0, "stone": 0},
			"refund_now": {"wood": 0, "stone": 0},
			"refund_on_complete": on_site.duplicate(),
			"complete_immediately": clear_work <= 0,
			"restore_mode": false,
			"expel": false,
			"base_level": base_lvl,
			"materials_after": on_site,
		}

	# Fresh project from resting state, or retarget to a different build/delevel target.
	var from_lvl := base_lvl
	var pay := {"wood": 0, "stone": 0}
	var refund_on_complete := {"wood": 0, "stone": 0}
	var work_needed := 0
	var progress_keep := 0
	var expel := false
	var materials_after := on_site.duplicate()

	if new_target < 0:
		# Dismantle standing castle to empty.
		if from_lvl < 0:
			return {}
		work_needed = int(ceil(float(GlobalUnits.castle_work_required(from_lvl)) * 0.5))
		refund_on_complete = GlobalUnits.castle_material_cost(from_lvl)
		materials_after = GlobalUnits.castle_material_cost(from_lvl)
		expel = not project_active and has_castle
	elif from_lvl < 0 or new_target > from_lvl:
		# Build or upgrade (full target work). Mid-project progress carries when going up.
		work_needed = GlobalUnits.castle_work_required(new_target)
		progress_keep = project_progress if project_active else 0
		var want := GlobalUnits.castle_material_cost(new_target)
		pay = {
			"wood": maxi(0, int(want["wood"]) - int(on_site.get("wood", 0))),
			"stone": maxi(0, int(want["stone"]) - int(on_site.get("stone", 0))),
		}
		materials_after = want
		expel = not project_active and has_castle
		if progress_keep >= work_needed and work_needed > 0:
			return {
				"work_needed": 0,
				"progress_keep": 0,
				"pay": pay,
				"refund_now": {"wood": 0, "stone": 0},
				"refund_on_complete": {"wood": 0, "stone": 0},
				"complete_immediately": true,
				"restore_mode": false,
				"expel": expel,
				"base_level": from_lvl if not project_active else project_base_level,
				"materials_after": want,
			}
	else:
		# Delevel standing (or mid-project) to lower finished level: half work difference.
		if new_target == from_lvl and not project_active:
			return {}
		var w_from := GlobalUnits.castle_work_required(from_lvl)
		var w_to := GlobalUnits.castle_work_required(new_target)
		work_needed = int(ceil(float(maxi(0, w_from - w_to)) * 0.5))
		refund_on_complete = GlobalUnits.castle_material_refund(from_lvl, new_target)
		materials_after = on_site.duplicate() if project_active else GlobalUnits.castle_material_cost(from_lvl)
		# If mid-upgrade materials already exceed target, keep on site until finish.
		if not project_active:
			materials_after = GlobalUnits.castle_material_cost(from_lvl)
		expel = not project_active and has_castle
		progress_keep = 0
		if work_needed <= 0:
			var want_d := GlobalUnits.castle_material_cost(new_target)
			return {
				"work_needed": 0,
				"progress_keep": 0,
				"pay": {"wood": 0, "stone": 0},
				"refund_now": GlobalUnits.castle_material_refund(from_lvl, new_target),
				"refund_on_complete": {"wood": 0, "stone": 0},
				"complete_immediately": true,
				"restore_mode": false,
				"expel": expel,
				"base_level": from_lvl,
				"materials_after": want_d,
			}

	return {
		"work_needed": work_needed,
		"progress_keep": progress_keep,
		"pay": pay,
		"refund_now": {"wood": 0, "stone": 0},
		"refund_on_complete": refund_on_complete,
		"complete_immediately": false,
		"restore_mode": false,
		"expel": expel,
		"base_level": from_lvl if not project_active else project_base_level,
		"materials_after": materials_after,
	}


## Pending refund stored when a project that refunds on complete is set.
var _pending_refund: Dictionary = {"wood": 0, "stone": 0}


func apply_retarget_state(new_target: int, preview: Dictionary) -> void:
	if preview.is_empty():
		return
	if bool(preview.get("complete_immediately", false)):
		_finish_as_level(new_target, preview)
		return

	var was_active := project_active
	if not was_active:
		project_base_level = standing_level()
	else:
		project_base_level = int(preview.get("base_level", project_base_level))

	project_active = true
	project_target = new_target
	project_progress = int(preview.get("progress_keep", 0))
	project_work_needed = int(preview.get("work_needed", 0))
	materials_on_site = (preview.get("materials_after", materials_on_site) as Dictionary).duplicate()
	_pending_refund = (preview.get("refund_on_complete", {"wood": 0, "stone": 0}) as Dictionary).duplicate()
	# Offline while project runs; keep standing type for display when upgrading/dismantling.
	if project_base_level >= 0:
		castle_type = project_base_level as CASTLE_TYPE
	refresh_visuals()
	set_flags()


func add_construction_work(amount: int) -> bool:
	if not project_active or amount <= 0:
		return false
	project_progress = mini(project_work_needed, project_progress + amount)
	refresh_visuals()
	return project_progress >= project_work_needed and project_work_needed > 0


func complete_project() -> Dictionary:
	## Returns refund dict to apply to province stockpile.
	if not project_active:
		return {"wood": 0, "stone": 0}
	var target := project_target
	var refund := _pending_refund.duplicate()
	var mats := (
		{"wood": 0, "stone": 0} if target < 0
		else GlobalUnits.castle_material_cost(target)
	)
	_finish_as_level(target, {"materials_after": mats, "refund_now": refund})
	return take_completion_refund()


func _finish_as_level(level: int, preview: Dictionary) -> void:
	var refund_now: Dictionary = preview.get("refund_now", {"wood": 0, "stone": 0})
	project_active = false
	project_progress = 0
	project_work_needed = 0
	project_target = GlobalUnits.CASTLE_TARGET_EMPTY
	project_base_level = GlobalUnits.CASTLE_TARGET_EMPTY
	if level < 0:
		has_castle = false
		materials_on_site = {"wood": 0, "stone": 0}
	else:
		has_castle = true
		castle_type = level as CASTLE_TYPE
		materials_on_site = (preview.get(
			"materials_after", GlobalUnits.castle_material_cost(level)
		) as Dictionary).duplicate()
	_pending_refund = {
		"wood": int(refund_now.get("wood", 0)),
		"stone": int(refund_now.get("stone", 0)),
	}
	refresh_visuals()
	set_flags()


func take_completion_refund() -> Dictionary:
	var r := _pending_refund.duplicate()
	_pending_refund = {"wood": 0, "stone": 0}
	return r


func construction_summary() -> String:
	if not project_active:
		if not has_castle:
			return "Empty castle plot"
		return "%s (operational)" % get_castle_type_name()
	var tgt := "dismantle (empty)" if project_target < 0 else castle_type_display_name(project_target)
	return "Constructing %s — %d / %d work" % [tgt, project_progress, project_work_needed]
