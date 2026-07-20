extends Node2D

## Blocky hammer made of rectangles; pivots at the handle base.
## Strike is fast; raise-back is slower.

const HANDLE_LEN := 18.0
const RAISE_ANGLE := 0.85
const STRIKE_ANGLE := -0.55
## Fraction of the cycle spent on the downward strike (rest is the return).
const STRIKE_FRAC := 0.35

var _phase: float = 0.0


func _ready() -> void:
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta * 2.8
	var t := fmod(_phase, TAU) / TAU
	if t < STRIKE_FRAC:
		# Fast strike down
		var u := t / STRIKE_FRAC
		rotation = lerpf(RAISE_ANGLE, STRIKE_ANGLE, u * u)
	else:
		# Return up
		var u := (t - STRIKE_FRAC) / (1.0 - STRIKE_FRAC)
		rotation = lerpf(STRIKE_ANGLE, RAISE_ANGLE, u)
	queue_redraw()


func _draw() -> void:
	# Pivot is (0,0) = base of the handle; hammer builds upward (-Y). Tip faces left.
	draw_rect(Rect2(-2.0, -HANDLE_LEN, 4.0, HANDLE_LEN), Color(0.45, 0.28, 0.12, 0.95), true)
	draw_rect(Rect2(-8.0, -HANDLE_LEN - 6.0, 16.0, 7.0), Color(0.55, 0.55, 0.58, 0.95), true)
	draw_rect(Rect2(-11.0, -HANDLE_LEN - 7.0, 5.0, 9.0), Color(0.62, 0.62, 0.66, 0.95), true)
