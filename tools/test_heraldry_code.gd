extends SceneTree

## Headless round-trip check: godot --headless --path . -s tools/test_heraldry_code.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var H: Node = root.get_node_or_null("Heraldry")
	if H == null:
		push_error("Heraldry autoload missing")
		quit(1)
		return
	var failed := 0
	failed += _check(H, H.default_heraldry(), "default")
	failed += _check(H, H.council_heraldry(), "council")
	failed += _check(H, {
		"division": H.DIVISION.PER_PALE,
		"fields": [
			{"base": "gules", "ink": "or", "pattern": 2, "charge": 1, "charge_type": 0},
			{"base": "azure", "ink": "argent", "pattern": 0, "charge": 2, "charge_type": 1},
		],
	}, "pale")
	failed += _check(H, {
		"division": H.DIVISION.QUARTERED,
		"fields": [
			{"base": "vert", "ink": "or", "pattern": 1, "charge": 0, "charge_type": 0},
			{"base": "sable", "ink": "argent", "pattern": 3, "charge": 1, "charge_type": 1},
			{"base": "purpure", "ink": "or", "pattern": 4, "charge": 2, "charge_type": 0},
			{"base": "or", "ink": "gules", "pattern": 0, "charge": 1, "charge_type": 1},
		],
	}, "quartered")
	for i in 40:
		var h: Dictionary = H.random_heraldry()
		failed += _check(H, h, "random_%d" % i)
	if not H.from_code("!!!").is_empty():
		push_error("expected invalid !!!")
		failed += 1
	if not H.from_code("").is_empty():
		push_error("expected empty string to fail")
		failed += 1
	print("heraldry code test: %s (%d failures)" % ["OK" if failed == 0 else "FAIL", failed])
	quit(0 if failed == 0 else 1)


func _check(H: Node, h: Dictionary, label: String) -> int:
	var n: Dictionary = H.normalize(h)
	var code: String = H.to_code(n)
	var back: Dictionary = H.from_code(code)
	if back.is_empty():
		push_error("[%s] decode failed for code=%s" % [label, code])
		return 1
	var n2: Dictionary = H.normalize(back)
	if int(n["division"]) != int(n2["division"]):
		push_error("[%s] division mismatch code=%s" % [label, code])
		return 1
	var f1: Array = n["fields"]
	var f2: Array = n2["fields"]
	if f1.size() != f2.size():
		push_error("[%s] field count mismatch code=%s" % [label, code])
		return 1
	for i in f1.size():
		for k in ["base", "ink", "pattern", "charge", "charge_type"]:
			if str(f1[i][k]) != str(f2[i][k]):
				push_error("[%s] field %d.%s mismatch %s vs %s code=%s len=%d" % [
					label, i, k, str(f1[i][k]), str(f2[i][k]), code, code.length()
				])
				return 1
	print("  %s -> %s (%d chars)" % [label, code, code.length()])
	return 0
