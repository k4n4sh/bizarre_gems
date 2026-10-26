class_name FlyLayer
extends Control
## Sparks that fly from knocked-out gems up to the score, like coins into a purse.
## Positions are in global canvas coordinates; `landed` fires as each wave of sparks arrives.

signal landed

const SPARKLE := preload("res://assets/fx/sparkle.png")
const GLOW := preload("res://assets/fx/glow.png")

var _orbs: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func send(from: Vector2, to: Vector2, color: Color, delay := 0.0, size := 22.0) -> void:
	var inv := get_global_transform().affine_inverse()
	var a := inv * from
	var c := inv * to
	var b := (a + c) / 2.0 + Vector2(randf_range(-90, 90), -randf_range(40, 140))
	_orbs.append({"a": a, "b": b, "c": c, "t": -delay, "dur": randf_range(0.42, 0.58), "col": color, "s": size})


func clear() -> void:
	_orbs.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _orbs.is_empty():
		return
	var arrived := false
	for o in _orbs:
		o.t += delta
		if o.t >= o.dur:
			arrived = true
	_orbs.assign(_orbs.filter(func(o): return o.t < o.dur))
	if arrived:
		landed.emit()
	queue_redraw()


func _point(o: Dictionary, q: float) -> Vector2:
	var e := q * q  # ease in: slow lift-off, fast arrival
	return o.a.lerp(o.b, e).lerp(o.b.lerp(o.c, e), e)


func _draw() -> void:
	for o in _orbs:
		if o.t < 0.0:
			continue
		var q: float = o.t / o.dur
		var s: float = o.s * (1.0 - 0.35 * q)
		for j in 3:  # a short trail
			var tq := maxf(0.0, q - j * 0.06)
			var ts := s * (1.0 - j * 0.25)
			var p := _point(o, tq)
			draw_texture_rect(GLOW, Rect2(p - Vector2.ONE * ts, Vector2.ONE * ts * 2.0), false, Color(o.col, 0.35 / (j + 1)))
		var p0 := _point(o, q)
		draw_texture_rect(SPARKLE, Rect2(p0 - Vector2.ONE * s / 2.0, Vector2.ONE * s), false, Color(o.col.lightened(0.4), 1.0))
