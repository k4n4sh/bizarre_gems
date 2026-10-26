class_name HudRing
extends Control
## A round timer for the top HUD: mirrors a ProgressBar (0..100) as an arc, with an optional
## short text in the middle. The bar stays the source of truth; the ring only draws it.

var source: Range
var color := UiKit.BRASS
var track := Color(1, 1, 1, 0.14)
var thickness := 6.0
var text := ""
var text_color := UiKit.CREAM
var _shown := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not source:
		return
	var v := source.value / maxf(1.0, source.max_value)
	if not is_equal_approx(v, _shown):
		_shown = v
		queue_redraw()


func set_text(s: String, c: Color) -> void:
	text = s
	text_color = c
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - thickness * 0.5
	if r < 4.0:
		return
	var c := size * 0.5
	draw_arc(c, r, 0, TAU, 48, track, thickness, true)
	var v := clampf(_shown, 0.0, 1.0)
	if v > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * v, maxi(4, int(48 * v)), color, thickness, true)
	if text != "":
		var fs := int(r * 0.8)
		var font := UiKit.NUMBER_FONT
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
