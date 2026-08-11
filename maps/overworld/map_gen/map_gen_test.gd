extends Control

## Editor-only sandbox: generate / validate / preview an abstract province matrix,
## then bake into a real overworld map and play.

const AUTO_REROLL_TRIES := 16

@onready var _province_spin: SpinBox = %ProvinceSpin
@onready var _reroll_btn: Button = %RerollButton
@onready var _bake_btn: Button = %BakePlayButton
@onready var _preview: MapMatrixPreview = %Preview
@onready var _status: Label = %StatusLabel
@onready var _issues: ItemList = %IssuesList
@onready var _meta: Label = %MetaLabel

var _matrix: MapMatrix = null
var _issues_cache: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_province_spin.min_value = 3
	_province_spin.max_value = 20
	_province_spin.value = 6
	_province_spin.rounded = true
	_reroll_btn.pressed.connect(_on_reroll)
	_bake_btn.pressed.connect(_on_bake_play)
	_province_spin.value_changed.connect(_on_province_count_changed)
	_reroll()


func _on_province_count_changed(_v: float) -> void:
	_reroll()


func _on_reroll() -> void:
	_reroll()


func _reroll() -> void:
	var n := int(_province_spin.value)
	_issues_cache = PackedStringArray(["generate failed"])
	for _try in AUTO_REROLL_TRIES:
		_matrix = MapMatrixGenerator.generate(n, randi())
		_issues_cache = MapMatrixValidator.validate(_matrix)
		if _issues_cache.is_empty():
			break
	_preview.set_matrix(_matrix)
	_refresh_status(_issues_cache)


func _refresh_status(issues: PackedStringArray) -> void:
	_issues.clear()
	var side := _matrix.width if _matrix else 0
	var seed_txt := str(_matrix.seed_used) if _matrix else "-"
	var plot_n := _matrix.plots.size() if _matrix else 0
	var road_n := _matrix.road_count() if _matrix else 0
	_meta.text = "Size %dx%d  |  Plots %d  |  Roads %d  |  Seed %s" % [
		side, side, plot_n, road_n, seed_txt
	]
	var valid := issues.is_empty()
	_bake_btn.disabled = not valid
	if valid:
		_status.text = "VALID"
		_status.add_theme_color_override("font_color", Color(0.35, 0.85, 0.45))
		_issues.add_item("No issues.")
	else:
		_status.text = "INVALID (%d)" % issues.size()
		_status.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
		for issue in issues:
			_issues.add_item(issue)


func _on_bake_play() -> void:
	if _matrix == null or not _issues_cache.is_empty():
		return
	_bake_btn.disabled = true
	_status.text = "Baking…"
	var map_root := MapMatrixBaker.bake(_matrix)
	if map_root == null:
		_status.text = "BAKE FAILED"
		_status.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
		_bake_btn.disabled = false
		return
	GlobalSet.clear_pending_game_setup()
	var tree := get_tree()
	var old := tree.current_scene
	tree.root.add_child(map_root)
	tree.current_scene = map_root
	if old != null:
		old.queue_free()
