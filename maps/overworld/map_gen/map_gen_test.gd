extends Control

## Editor-only sandbox: generate / validate / preview an abstract province matrix.

@onready var _province_spin: SpinBox = %ProvinceSpin
@onready var _reroll_btn: Button = %RerollButton
@onready var _preview: MapMatrixPreview = %Preview
@onready var _status: Label = %StatusLabel
@onready var _issues: ItemList = %IssuesList
@onready var _meta: Label = %MetaLabel

var _matrix: MapMatrix = null


func _ready() -> void:
	_province_spin.min_value = 3
	_province_spin.max_value = 20
	_province_spin.value = 6
	_province_spin.rounded = true
	_reroll_btn.pressed.connect(_on_reroll)
	_province_spin.value_changed.connect(_on_province_count_changed)
	_reroll()


func _on_province_count_changed(_v: float) -> void:
	_reroll()


func _on_reroll() -> void:
	_reroll()


func _reroll() -> void:
	var n := int(_province_spin.value)
	_matrix = MapMatrixGenerator.generate(n, randi())
	_preview.set_matrix(_matrix)
	var issues := MapMatrixValidator.validate(_matrix)
	_refresh_status(issues)


func _refresh_status(issues: PackedStringArray) -> void:
	_issues.clear()
	var side := _matrix.width if _matrix else 0
	var seed_txt := str(_matrix.seed_used) if _matrix else "-"
	var plot_n := _matrix.plots.size() if _matrix else 0
	var road_n := _matrix.road_count() if _matrix else 0
	_meta.text = "Size %dx%d  |  Plots %d  |  Roads %d  |  Seed %s" % [
		side, side, plot_n, road_n, seed_txt
	]
	if issues.is_empty():
		_status.text = "VALID"
		_status.add_theme_color_override("font_color", Color(0.35, 0.85, 0.45))
		_issues.add_item("No issues.")
	else:
		_status.text = "INVALID (%d)" % issues.size()
		_status.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
		for issue in issues:
			_issues.add_item(issue)
