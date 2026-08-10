extends Node

## Subtle seasonal grade on overworld world content (not menus / map name labels).

const SETTING_KEY := "show_season_tint"
const FADE_SEC := 0.75

## Multiply tints — readable, but clearly seasonal.
const SEASON_TINTS := {
	0: Color(0.86, 0.94, 1.0), # winter — cold blue (bright, not dark)
	1: Color(0.88, 1.0, 0.86), # spring — soft green
	2: Color(1.0, 0.94, 0.76), # summer — warm yellow
	3: Color(1.0, 0.86, 0.72), # autumn — warm amber
}

const TINT_ROOTS := [
	"tilemap",
	"provinces",
	"ProvinceBorders",
	"armies",
	"caravans",
	"fleets",
	"merchants",
	"sellswords",
	"PathLine",
	"WalkableOverlay",
	"weather_objects",
	"CloudShadows",
	"TileCoordsDebug",
	"WeatherObject",
]

var _map: Node2D
var _current := Color.WHITE
var _inv := Color.WHITE
var _tween: Tween
var _was_enabled := true
var _season := 0


func _ready() -> void:
	_map = get_parent() as Node2D
	_was_enabled = _is_enabled()


func _process(_delta: float) -> void:
	var enabled := _is_enabled()
	if enabled != _was_enabled:
		_was_enabled = enabled
		apply_for_season(_season, true)
		return
	# Keep label compensation on newly spawned armies / edge cases.
	if _current != Color.WHITE:
		_compensate_labels()


func setup_and_apply(season: int) -> void:
	_season = int(season)
	_was_enabled = _is_enabled()
	apply_for_season(_season, false)


func apply_for_season(season: int, animate: bool) -> void:
	_season = int(season)
	var target := _target_color(_season)
	if not animate or _current.is_equal_approx(target):
		_kill_tween()
		_set_tint(target)
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_tint, _current, target, FADE_SEC)


func _target_color(season: int) -> Color:
	if not _is_enabled():
		return Color.WHITE
	return SEASON_TINTS.get(int(season), Color.WHITE) as Color


func _is_enabled() -> bool:
	return int(GlobalSet.settings.get(SETTING_KEY, 1)) != 0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_tint(color: Color) -> void:
	_current = color
	_inv = _inverse_rgb(color)
	if _map == null:
		return
	for path in TINT_ROOTS:
		var node := _map.get_node_or_null(path) as CanvasItem
		if node != null:
			node.modulate = color
	_compensate_labels()


func _inverse_rgb(color: Color) -> Color:
	return Color(
		1.0 / maxf(color.r, 0.001),
		1.0 / maxf(color.g, 0.001),
		1.0 / maxf(color.b, 0.001),
		1.0
	)


func _compensate_labels() -> void:
	if _map == null:
		return
	var provinces := _map.get_node_or_null("provinces")
	if provinces != null:
		for prov in provinces.get_children():
			_set_label_rgb(prov.get_node_or_null("map_labels") as CanvasItem)
	var armies := _map.get_node_or_null("armies")
	if armies != null:
		for army in armies.get_children():
			_set_label_rgb(army.get_node_or_null("map_labels") as CanvasItem)
	var fleets := _map.get_node_or_null("fleets")
	if fleets != null:
		for fleet in fleets.get_children():
			_set_label_rgb(fleet.get_node_or_null("map_labels") as CanvasItem)


func _set_label_rgb(labels: CanvasItem) -> void:
	if labels == null:
		return
	var c := labels.modulate
	c.r = _inv.r
	c.g = _inv.g
	c.b = _inv.b
	labels.modulate = c
