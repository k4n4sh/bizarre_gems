class_name RecordBar
extends Control
## The strip between the HUD and the board: the race to the record ("Best 1520 · 340 to go"),
## and the flame of the hot streak on its right. main.gd feeds it the score and the streak.

const FLAME_FROM := 3  ## the flame shows from this streak on, dim until ScoreKeeper.HOT_AT

var best := 0        ## the record when the game started; 0 = no record yet (or a mode without one)
var race := true     ## false: only the flame (level and puzzle modes have no record to chase)
var score := 0
var beaten := false
var hot := 0
var _fill := 0.0     ## shown fill of the bar, eased towards the score
var _pulse := 0.0    ## glow after the record falls
var _pop := 0.0      ## bump of the flame when the streak grows
var _t := 0.0
var _bg := UiKit.box(Color(0.03, 0.05, 0.16, 0.55), Color(1, 1, 1, 0.12), 1, 99, Vector4.ZERO)
var _bar := UiKit.box(UiKit.BRASS, Color(0, 0, 0, 0), 0, 99, Vector4.ZERO)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 30


func setup(record: int, has_race: bool) -> void:
	best = record
	race = has_race
	score = 0
	beaten = false
	hot = 0
	_fill = 0.0
	_pulse = 0.0
	queue_redraw()


func set_hot(n: int) -> void:
	if n > hot and n >= FLAME_FROM:
		_pop = 1.0
	hot = n


## The record just fell: the bar turns gold and glows.
func celebrate() -> void:
	beaten = true
	_pulse = 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var target := 1.0 if beaten or best <= 0 else clampf(float(score) / best, 0.0, 1.0)
	_fill = lerpf(_fill, target, minf(1.0, delta * 8.0))
	_pulse = maxf(0.0, _pulse - delta * 0.8)
	_pop = maxf(0.0, _pop - delta * 4.0)
	queue_redraw()


func _draw() -> void:
	var h := size.y
	if h < 8.0 or size.x < 40.0:
		return  # not laid out yet
	var chip := h * 2.4 if hot >= FLAME_FROM else 0.0
	if race:
		var pill := Rect2(0, h * 0.06, size.x - chip - (h * 0.25 if chip > 0.0 else 0.0), h * 0.88)
		_draw_race(pill)
	if chip > 0.0:
		_draw_flame_chip(Rect2(size.x - chip, 0, chip, h))


func _draw_race(pill: Rect2) -> void:
	if pill.size.x < 60.0:
		return
	var font := UiKit.NUMBER_FONT
	var fs := int(pill.size.y * 0.66)
	if _pulse > 0.0:
		draw_style_box(UiKit.box(Color(0, 0, 0, 0), Color(UiKit.BRASS_LIGHT, _pulse), int(2 + _pulse * 3), 99, Vector4.ZERO),
			pill.grow(2.0 + _pulse * 4.0))
	draw_style_box(_bg, pill)
	var fw := pill.size.x * _fill
	if fw >= pill.size.y * 0.5:
		_bar.bg_color = UiKit.BRASS.lerp(Color("#ff9a2e"), 0.25 + 0.25 * sin(_t * 6.0)) if beaten else Color(UiKit.BRASS, 0.75)
		draw_style_box(_bar, Rect2(pill.position, Vector2(fw, pill.size.y)))
	var left := ""
	var right := ""
	if best <= 0:
		left = L.t("record_first")
	elif beaten:
		left = L.t("record_new")
		right = "+%d" % (score - best)
	else:
		left = L.t("record_label", {"n": best})
		right = L.t("record_left", {"n": best - score + 1})
	var pad := pill.size.y * 0.55
	var base := pill.position.y + pill.size.y * 0.5 + fs * 0.36
	var w := pill.size.x - pad * 2
	_text(font, Vector2(pill.position.x + pad, base), left, HORIZONTAL_ALIGNMENT_LEFT, w, fs)
	if right != "":
		_text(font, Vector2(pill.position.x + pad, base), right, HORIZONTAL_ALIGNMENT_RIGHT, w, fs)


func _text(font: Font, pos: Vector2, s: String, align: HorizontalAlignment, w: float, fs: int) -> void:
	if beaten:  # dark on the solid gold bar
		draw_string(font, pos, s, align, w, fs, UiKit.INK)
		return
	draw_string_outline(font, pos, s, align, w, fs, maxi(2, fs / 5), Color(0.05, 0.05, 0.15, 0.85))
	draw_string(font, pos, s, align, w, fs, UiKit.CREAM)


## The flame and the streak number. Dim embers below HOT_AT, a real fire from it, hotter
## (white-blue core) from twice that.
func _draw_flame_chip(r: Rect2) -> void:
	var lit := hot >= ScoreKeeper.HOT_AT
	var hotter := hot >= ScoreKeeper.HOT_AT * 2
	var h := r.size.y * (0.95 if lit else 0.7) * (1.0 + _pop * 0.35)
	var c := Vector2(r.position.x + r.size.y * 0.5, r.position.y + r.size.y * 0.55)
	var a := 1.0 if lit else 0.55
	_flame(c, h, h * 0.62, Color(1.0, 0.32, 0.12, a))
	_flame(c + Vector2(0, h * 0.1), h * 0.72, h * 0.44, Color(1.0, 0.62, 0.15, a))
	_flame(c + Vector2(0, h * 0.2), h * 0.42, h * 0.26, Color(0.75, 0.9, 1.0, a) if hotter else Color(1.0, 0.92, 0.5, a))
	var font := UiKit.NUMBER_FONT
	var fs := int(r.size.y * (0.7 if lit else 0.6) * (1.0 + _pop * 0.3))
	var pos := Vector2(r.position.x + r.size.y * 1.0, r.position.y + r.size.y * 0.5 + fs * 0.36)
	draw_string_outline(font, pos, str(hot), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 5), Color(0.05, 0.05, 0.15, 0.85))
	draw_string(font, pos, str(hot), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.75, 0.35) if lit else UiKit.MUTED)


## A flickering teardrop: tip up, centred at c, h tall and w wide.
func _flame(c: Vector2, h: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var sway := sin(_t * 9.0 + h) * 0.18 + sin(_t * 23.0) * 0.06
	for i in 28:
		var t := TAU * i / 28.0
		var x := sin(t) * pow(sin(t / 2.0), 1.6)
		var y := cos(t)  # 1 at the tip
		var up := (y + 1.0) * 0.5
		pts.append(c + Vector2((x + sway * up * up) * w * 0.5, -y * h * 0.5))
	draw_colored_polygon(pts, col)
