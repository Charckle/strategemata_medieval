@tool
class_name BattleUnitMarker
extends Node2D

enum ShapeKind { INFANTRY_CIRCLE, RANGED_TRIANGLE, CAVALRY_DIAMOND }

@export var unit_type: String = "Macemen":
	set(value):
		unit_type = value
		_apply_shape_from_type()
		_refresh()

@export var owner_id: int = 1:
	set(value):
		owner_id = value
		_refresh()

@export var strength: int = 10:
	set(value):
		strength = value
		_refresh()

@export var shape_kind: ShapeKind = ShapeKind.INFANTRY_CIRCLE:
	set(value):
		shape_kind = value
		_refresh()

@export var facing_degrees: float = 0.0:
	set(value):
		facing_degrees = value
		_refresh()

@export var cell: Vector2i = Vector2i.ZERO:
	set(value):
		cell = value
		_snap_to_cell()

const TILE_SIZE := 32

@onready var _body: Polygon2D = $Body
@onready var _outline: Polygon2D = $Outline
@onready var _label: Label = $Label


func _ready() -> void:
	_apply_shape_from_type()
	_snap_to_cell()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_snap_to_cell()
		_refresh()


func _apply_shape_from_type() -> void:
	var t := unit_type.to_lower()
	if t in ["archer", "archers", "crossbowmen", "crossbowman"]:
		shape_kind = ShapeKind.RANGED_TRIANGLE
	elif t in ["knights", "knight", "cavalry"]:
		shape_kind = ShapeKind.CAVALRY_DIAMOND
	else:
		shape_kind = ShapeKind.INFANTRY_CIRCLE


func _snap_to_cell() -> void:
	position = Vector2(cell.x * TILE_SIZE + TILE_SIZE * 0.5, cell.y * TILE_SIZE + TILE_SIZE * 0.5)


func _refresh() -> void:
	if _body == null or _outline == null or _label == null:
		return
	var poly := _shape_polygon(shape_kind)
	_body.polygon = poly
	_outline.polygon = poly
	_body.color = _owner_color(owner_id)
	_outline.color = Color(0, 0, 0, 0.85)
	_outline.z_index = -1
	# Slightly larger outline via scale on a duplicate isn't available; thicken by drawing under.
	_outline.scale = Vector2(1.15, 1.15)
	_body.rotation_degrees = facing_degrees
	_outline.rotation_degrees = facing_degrees
	_label.text = "%s\n%s" % [unit_type, strength]
	_label.modulate = Color.WHITE


func _owner_color(owner: int) -> Color:
	match owner:
		1:
			return Color(0.85, 0.2, 0.2)
		2:
			return Color(0.2, 0.35, 0.9)
		3:
			return Color(0.9, 0.75, 0.15)
		4:
			return Color(0.55, 0.25, 0.75)
		_:
			return Color(0.7, 0.7, 0.7)


func _shape_polygon(kind: ShapeKind) -> PackedVector2Array:
	var r := 11.0
	match kind:
		ShapeKind.INFANTRY_CIRCLE:
			return _circle_poly(r, 16)
		ShapeKind.RANGED_TRIANGLE:
			return PackedVector2Array([
				Vector2(0, -r),
				Vector2(r * 0.9, r * 0.75),
				Vector2(-r * 0.9, r * 0.75),
			])
		ShapeKind.CAVALRY_DIAMOND:
			return PackedVector2Array([
				Vector2(0, -r),
				Vector2(r, 0),
				Vector2(0, r),
				Vector2(-r, 0),
			])
	return _circle_poly(r, 16)


func _circle_poly(radius: float, points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := TAU * float(i) / float(points)
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out
