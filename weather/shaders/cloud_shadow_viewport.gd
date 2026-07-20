extends SubViewport


func _ready() -> void:
	transparent_bg = true
	_sync_size()
	get_tree().root.size_changed.connect(_sync_size)


func _sync_size() -> void:
	size = get_tree().root.get_visible_rect().size
