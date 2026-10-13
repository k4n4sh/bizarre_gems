class_name BoardView
extends Control
## Draws the board and its effects, turns pointer and keyboard input into slot presses.

signal slot_pressed(p: Vector2i)

const SpecialGemArt = preload("res://scripts/special_gem_art.gd")
const LIGHT_FX := Color("#eed6a0")

const GEM_TEX: Array[Texture2D] = [
	preload("res://assets/gems/gem_0.png"), preload("res://assets/gems/gem_1.png"),
	preload("res://assets/gems/gem_2.png"), preload("res://assets/gems/gem_3.png"),
	preload("res://assets/gems/gem_4.png"), preload("res://assets/gems/gem_5.png"),
	preload("res://assets/gems/gem_6.png"), preload("res://assets/gems/gem_7.png"),
	preload("res://assets/gems/gem_8.png"), preload("res://assets/gems/gem_9.png"),
]
const TILE_TEX: Array[Texture2D] = [
	preload("res://assets/tiles/tile_0.png"), preload("res://assets/tiles/tile_1.png"),
	preload("res://assets/tiles/tile_2.png"), preload("res://assets/tiles/tile_3.png"),
	preload("res://assets/tiles/tile_4.png"), preload("res://assets/tiles/tile_5.png"),
	preload("res://assets/tiles/tile_6.png"), preload("res://assets/tiles/tile_7.png"),
	preload("res://assets/tiles/tile_8.png"), preload("res://assets/tiles/tile_9.png"),
]
const SLOT_TEX := preload("res://assets/ui/slot.png")
const SLOT_TILE_TEX := preload("res://assets/ui/slot_tile.png")
## colour of each gem kind in the classic skin (faceted gems), used for shards
const CLASSIC_COLORS: Array[Color] = [Color("#e2334c"), Color("#2f6ff0"), Color("#17a866"), Color("#9a4fe6"), Color("#f28a22"),
	Color("#f4c62e"), Color("#ece8f2"), Color("#f25fae"), Color("#3fd6dc"), Color("#a6dc3a")]
const SPARKLE_TEX := preload("res://assets/fx/sparkle.png")
const GLOW_TEX := preload("res://assets/fx/glow.png")
## tile colour per gem kind, matches the tile art (used for shards)
const GEM_GLOW: Array[Color] = [Color("#ff4d5e"), Color("#3d8bff"), Color("#22c97a"), Color("#a35cff"), Color("#ff9a2e"),
	Color("#ffcf33"), Color("#dfe5f0"), Color("#ff6fb5"), Color("#2fd6e0"), Color("#9be03a")]
## Rotates the hue of everything on the board; tweened when the palette changes on a big combo.
const HUE_SHADER := """
shader_type canvas_item;
uniform float hue = 0.0;
void fragment() {
	float a = hue * 6.2831853;
	vec3 c = COLOR.rgb;
	vec3 yiq = mat3(vec3(0.299, 0.596, 0.211), vec3(0.587, -0.274, -0.523), vec3(0.114, -0.322, 0.312)) * c;
	yiq.yz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * yiq.yz;
	COLOR.rgb = mat3(vec3(1.0, 1.0, 1.0), vec3(0.956, -0.272, -1.106), vec3(0.621, -0.647, 1.703)) * yiq;
}
"""
const GOLD := Color(1.0, 0.84, 0.4)
const BEAM := Color(0.97, 0.89, 0.66)
const MISS := Color(1.0, 0.36, 0.31)
const TEXT_COLORS: Array[Color] = [Color(0.97, 0.89, 0.66), Color(1.0, 0.78, 0.35), Color(1.0, 0.55, 0.3), Color(1.0, 0.42, 0.7)]
var frame_pad := 10.0

var logic: BoardLogic
var interactive := false:
	set(v):
		interactive = v
		if not v and OS.has_feature("android"):
			_cancel_android_touch()
var number_font: Font
var feedback_font: Font
var feedback_exclusion: Callable
var classic_feedback := false
var feedback_rects: Array[Rect2] = [] # Actual visible text bounds, useful for layout checks.
var cell := 30.0
var origin := Vector2.ZERO

var _hover := Vector2i(-1, -1)
var _cursor := Vector2i(-1, -1)
var _keyboard := false
var _flyers: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _texts: Array[Dictionary] = []
var _misses: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _waves: Array[Dictionary] = []
var _flash := 0.0
var _flash_color := Color.WHITE
var _shake := 0.0
var _hint := Vector2i(-1, -1)
var _hint_t := 0.0
var _frame := StyleBoxFlat.new()
var _run_surface := Color.TRANSPARENT
var _run_surface_layer: Control
var _time := 0.0
var _deal_t := 99.0  ## seconds since the board was dealt; drives the deal-in animation
var _deal_delay := PackedFloat32Array()
var _glints: Array[Dictionary] = []
var _glint_timer := 0.0
var _ripples: Array[Dictionary] = []
var _fx: Control  ## effects layer, redrawn every frame; the board itself redraws only on change
var _shake_off := Vector2.ZERO
var _shards: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _praise: Array[Dictionary] = []
var _hue_mat := ShaderMaterial.new()
## "classic": faceted gems in round hollows on velvet; "bright": glossy tiles, colour shifts.
var skin := "classic":
	set(v):
		skin = v
		_apply_skin()
## Presentation override; skin still identifies the mode's sizing/input family.
var visual_profile := "":
	set(v):
		visual_profile = v
		_apply_skin()
## Match Bright's existing red/blue/green/yellow/orange/purple kind order.
const RUN_GEM_INDICES := [0, 1, 2, 5, 4, 3]
var _gem_tex: Array[Texture2D] = GEM_TEX
## Bright mode blocks: BLOCKS[palette][kind]; the palette changes on big combos.
var BLOCKS: Array = []
## Bright mode look: 0 is the first palette, 1..5 the ones that follow on new levels and big
## combos. Every look is the same glossy tile style with the same bold shapes.
var palette := 0:
	set(v):
		palette = posmod(v, maxi(BLOCKS.size(), 1)) if Progress.COSMETICS_ENABLED else Progress.BASE_LOOK
		_apply_skin()
## tile colour per kind for each look (used for crumbs and confetti), matches gen_assets
const PALETTE_COLORS := [
	["#ff4d5e", "#3d8bff", "#22c97a", "#ffcf33", "#ff9a2e", "#a35cff"],
	["#ff6fb5", "#ffb547", "#c27bff", "#ff8a5c", "#ff4d6d", "#ffd84d"],
	["#ff9a5c", "#f2a3c7", "#ffcf4d", "#4fc3f7", "#2fd6c7", "#8fa6ff"],
	["#d8283c", "#ff5d7a", "#8a4fd6", "#ffd84d", "#ff9a2e", "#7ccf3a"],
	["#6abf4b", "#b97a3c", "#e2453c", "#ff8fc7", "#2f8a4f", "#4fd18b"],
	["#ff9a5c", "#fff1a8", "#ff7eb6", "#5fd4ff", "#ff5a4f", "#c3cfff"],
	["#3d8bdf", "#ff6f7a", "#4fb88b", "#ffffff", "#ffcf4d", "#8fd3ff"],
	["#ff8a1d", "#f2f2f2", "#7b4fd6", "#ff5d3a", "#ffe08a", "#cfd8dc"],
	["#e2334c", "#2f6ff0", "#17a866", "#f4c62e", "#f28a22", "#9a4fe6"],
	["#ff3d8b", "#33e1ff", "#7dff5a", "#ffe53d", "#ff8a1f", "#b06bff"],
	["#d8283c", "#2a6fd6", "#1fa36a", "#e8b622", "#e8701c", "#8a3fcf"],
]
const ICE_TEX := preload("res://assets/tiles/ice.png")
const BOMB_TEX := preload("res://assets/tiles/bomb.png")
const CHAM_TEX := preload("res://assets/tiles/chameleon.png")
const LINK_TEX := preload("res://assets/ui/icon_link.png")
var _confetti: Array[Dictionary] = []
## Pinch zoom (classic on touch screens): 1..3x around the board.
## Android uses one finger to aim; only two fingers can zoom and pan.
var zoom_enabled := false
var zoom := 1.0
var pan := Vector2.ZERO
var _touches := {}
var _pinch := {}
var _press_pos := Vector2.ZERO
var _pressing := false
var _moved := false
var _gestured := false
var _android_touch_id := -1
var _android_captured := false
var _android_blocked := false
var _clear_t := 99.0  ## time since a full clear: a wave of light sweeps over the slots
const JOKER_TEX := preload("res://assets/tiles/joker.png")
const BOX_TEX := preload("res://assets/tiles/box.png")
var _glow := 0.0
var _slot_tex: Texture2D = SLOT_TEX
var _colors: Array[Color] = CLASSIC_COLORS
var hue := 0.0:
	set(v):
		hue = v
		_hue_mat.set_shader_parameter("hue", v)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(OS.has_feature("android"))
	_frame.bg_color = Color(0.04, 0.07, 0.2, 0.55)
	_frame.border_color = Color(1, 1, 1, 0.14)
	_frame.set_border_width_all(3)
	_frame.set_corner_radius_all(20)
	_frame.shadow_color = Color(0, 0, 0, 0.45)
	_frame.shadow_size = 18
	clip_contents = true
	resized.connect(_relayout)
	# Bright Run's surface can fade without rebuilding every gem's draw commands.
	_run_surface_layer = Control.new()
	_run_surface_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_surface_layer.show_behind_parent = true
	_run_surface_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_surface_layer.visible = false
	add_child(_run_surface_layer)
	_run_surface_layer.draw.connect(func():
		if logic == null:
			return
		_run_surface_layer.draw_set_transform(_shake_off)
		var grid_size := Vector2(logic.cols,logic.rows)*cell
		_run_surface_layer.draw_style_box(_frame,Rect2(origin-Vector2.ONE*frame_pad,grid_size+Vector2.ONE*frame_pad*2)))
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	for t in PALETTE_COLORS.size():
		var set: Array[Texture2D] = []
		for k in 6:
			set.append(load("res://assets/tiles/look_%d_%d.png" % [t, k]))
		BLOCKS.append(set)
	var sh := Shader.new()
	sh.code = HUE_SHADER
	_hue_mat.shader = sh
	_fx.use_parent_material = true
	_apply_skin()


func _refined() -> bool:
	return visual_profile == "classic_run"


func _trim_refined_fx() -> void:
	if not _refined():
		return
	# Visual budgets only; never throttle strikes, score or game time.
	if _sparks.size() > 120: _sparks = _sparks.slice(-120)
	if _shards.size() > 96: _shards = _shards.slice(-96)
	if _waves.size() > 6: _waves = _waves.slice(-6)
	if _texts.size() > 8: _texts = _texts.slice(-8)
	if _praise.size() > 2: _praise = _praise.slice(-2)


func _uses_tiles() -> bool:
	return (visual_profile if visual_profile != "" else skin) == "bright"


func _apply_skin() -> void:
	var bright := _uses_tiles()
	var blocks := bright and not BLOCKS.is_empty()
	_gem_tex = GEM_TEX
	if bright:
		_gem_tex = BLOCKS[palette] if blocks else TILE_TEX
	if visual_profile == "classic_run":
		_gem_tex = []
		for i in RUN_GEM_INDICES:
			_gem_tex.append(GEM_TEX[i])
	_slot_tex = SLOT_TILE_TEX if bright else SLOT_TEX
	_colors = CLASSIC_COLORS
	if bright:
		_colors = GEM_GLOW
		if blocks:
			var cols: Array[Color] = []
			for hexc in PALETTE_COLORS[palette]:
				cols.append(Color(hexc))
			_colors = cols
	if visual_profile == "classic_run":
		_colors = []
		for i in RUN_GEM_INDICES:
			_colors.append(CLASSIC_COLORS[i])
	material = null  # palettes are real colour sets now, no hue rotation
	if not bright:
		hue = 0.0
	if bright:
		_frame.bg_color = Color(0.04, 0.07, 0.2, 0.55)
		_frame.border_color = Color(1, 1, 1, 0.14)
		_frame.set_border_width_all(3)
		_frame.set_corner_radius_all(20)
	else:
		_frame.bg_color = Color(0.05, 0.13, 0.14, 0.55)
		_frame.border_color = Color(0.82, 0.67, 0.33, 0.55)
		_frame.set_border_width_all(2)
		_frame.set_corner_radius_all(14)
	if _refined() and _run_surface.a > 0.0:
		_frame.bg_color = _run_surface
	queue_redraw()


## Only the existing translucent surface changes; all gems/slots/effects keep their colours.
func set_run_surface(color: Color) -> void:
	_run_surface = color
	_frame.bg_color = color
	if not _run_surface_layer.visible:
		_run_surface_layer.visible = true
		queue_redraw()
	_run_surface_layer.queue_redraw()


func reset_run_surface() -> void:
	if _run_surface.a == 0.0:
		return
	_run_surface = Color.TRANSPARENT
	_run_surface_layer.visible = false
	_apply_skin()


func _relayout() -> void:
	if logic == null:
		return
	var avail := size - Vector2.ONE * frame_pad * 2
	var base := maxf(8.0, floorf(minf(avail.x / logic.cols, avail.y / logic.rows)))
	cell = base * zoom
	var bs := Vector2(logic.cols, logic.rows) * cell
	origin = ((size - bs) / 2 + pan).floor()
	# when zoomed in, keep the board covering the view (no empty margins beyond its edges)
	for ax in 2:
		if bs[ax] + frame_pad * 2 > size[ax]:
			origin[ax] = clampf(origin[ax], size[ax] - bs[ax] - frame_pad, frame_pad)
			pan[ax] = origin[ax] - (size[ax] - bs[ax]) / 2
		else:
			pan[ax] = 0.0
			origin[ax] = floorf((size[ax] - bs[ax]) / 2)
	queue_redraw()


func reset_zoom() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	if OS.has_feature("android"):
		_cancel_android_touch()
	else:
		_touches.clear()
	_pinch.clear()
	_relayout()


func refresh() -> void:
	# A new board can be smaller than the previous one; cached input uses grid coordinates.
	if logic:
		if not logic.in_bounds(_hover):
			_hover = Vector2i(-1, -1)
		if not logic.in_bounds(_cursor):
			_cursor = Vector2i(-1, -1)
	_relayout()


## Animate gems dropping in, in a wave from the board centre.
func deal_in() -> void:
	_deal_t = 0.0
	queue_redraw()
	_deal_delay.resize(logic.cols * logic.rows)
	var c := Vector2(logic.cols - 1, logic.rows - 1) / 2.0
	var far := c.length()
	for y in logic.rows:
		for x in logic.cols:
			_deal_delay[y * logic.cols + x] = Vector2(x, y).distance_to(c) / far * 0.45 + randf() * 0.12


func _deal_scale(i: int) -> float:
	if _deal_t >= 1.0 or i >= _deal_delay.size():
		return 1.0
	var t := clampf((_deal_t - _deal_delay[i]) / 0.3, 0.0, 1.0)
	if t <= 0.0:
		return 0.0
	# ease-out-back: a small overshoot before settling
	var u := t - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u


func clear_fx() -> void:
	feedback_rects.clear()
	_flyers.clear(); _beams.clear(); _texts.clear(); _misses.clear(); _sparks.clear(); _waves.clear()
	_shards.clear(); _pops.clear(); _praise.clear(); _confetti.clear()
	_flash = 0.0
	_hint = Vector2i(-1, -1)


func slot_center(p: Vector2i) -> Vector2:
	return origin + (Vector2(p) + Vector2(0.5, 0.5)) * cell


func slot_at(pos: Vector2) -> Vector2i:
	var q := ((pos - origin) / cell).floor()
	var p := Vector2i(int(q.x), int(q.y))
	return p if logic and logic.in_bounds(p) else Vector2i(-1, -1)


# ---------------- effects ----------------

## mult is the combo multiplier (1..4): more sparks and a hotter colour for the score text.
func play_knock(from: Vector2i, gone: Array[Vector2i], kinds: Array[int], points: int, mult := 1, rainbow := false) -> void:
	var c := slot_center(from)
	for i in gone.size():
		var h := slot_center(gone[i])
		_beams.append({"a": c, "b": h, "t": 0.0, "rainbow": rainbow, "w": 1.0 + (mult - 1) * 0.5})
		if _refined():
			_beams[-1].rainbow = false
			for j in 4 + mult:
				var a := randf() * TAU
				_shards.append({"p":h,"v":Vector2.from_angle(a)*cell*randf_range(1.5,3.5),
					"r":a,"vr":randf_range(-4,4),"s":cell*randf_range(.055,.11),
					"c":_col(kinds[i]).lightened(.22),"t":0.0,"life":randf_range(.25,.45)})
			for j in 2 + mult:
				_sparks.append({"p":h,"v":Vector2.from_angle(randf()*TAU)*cell*2,
					"t":0.0,"life":.3,"s":.16,"c":LIGHT_FX})
			continue
		if not _uses_tiles():
			var away := signf(h.x - c.x)
			if away == 0.0:
				away = randf_range(-1, 1)
			_flyers.append({"k": kinds[i], "p": h, "v": Vector2(away * cell * randf_range(2, 4), -cell * randf_range(6, 9)),
				"r": 0.0, "vr": randf_range(-7, 7)})
			for j in 3 + mult * 2:
				var a2 := randf() * TAU
				_sparks.append({"p": h, "v": Vector2.from_angle(a2) * cell * randf_range(2, 5 + mult), "t": 0.0,
					"life": randf_range(0.35, 0.6), "s": randf_range(0.25, 0.5), "c": _spark_color(rainbow)})
			continue
		_pops.append({"p": h, "t": 0.0})
		var base: Color = _col(kinds[i])
		for j in 9:
			var a := randf() * TAU
			_shards.append({"p": h, "v": Vector2.from_angle(a) * cell * randf_range(2.5, 6.0) + Vector2(0, -cell * 3.0),
				"r": randf() * TAU, "vr": randf_range(-9, 9), "s": cell * randf_range(0.12, 0.22),
				"c": base.lightened(randf_range(0.0, 0.35)), "t": 0.0, "life": randf_range(0.5, 0.8)})
		for j in 4 + mult * 3:
			var a := randf() * TAU
			_sparks.append({"p": h, "v": Vector2.from_angle(a) * cell * randf_range(2, 5 + mult), "t": 0.0,
				"life": randf_range(0.35, 0.6), "s": randf_range(0.25, 0.5), "c": _spark_color(rainbow)})
	var col: Color = TEXT_COLORS[clampi(mult, 1, 4) - 1]
	if classic_feedback:
		_texts.assign(_texts.filter(func(t): return t.get("slot", Vector2i(-1, -1)) != from))
	_texts.append({"p": c, "s": "+%d" % points, "t": 0.0, "c": col, "k": 1.0 + (mult - 1) * 0.18})
	if classic_feedback:
		# Extend the existing score popup into one packet per hit. Logical coordinates
		# are resolved each frame, so zoom, pan and resizing cannot leave text behind.
		_texts[-1].merge({"slot": from, "life": 0.55, "rows": [{"s": "+%d" % points, "c": col}],
			"chain": -1, "double": false, "started": false, "special": rainbow})
		if not rainbow and not _praise.is_empty():
			_texts[-1].rows.push_front({"s": _praise[-1].s, "c": _praise[-1].c})
		_praise.clear() # Generic praise shares this packet, so it cannot appear late.
		while _texts.size() > 3:
			_texts.pop_front()
	_hint = Vector2i(-1, -1)
	_trim_refined_fx()
	queue_redraw()  # gems were removed


## Attach awarded bonus values to that hit's existing score popup; never score in the view.
func play_bonus_feedback(at: Vector2i, result: Dictionary, kind: int, count: int,
		start_title: String, chain_title: String, double_title: String, total_title := "") -> void:
	if not classic_feedback or _texts.is_empty():
		return
	var packet: Dictionary = _texts[-1]
	if packet.get("slot", Vector2i(-1, -1)) != at:
		return
	var rows: Array = []
	if int(result.color_streak_points) > 0:
		packet.chain = kind
		packet.started = bool(result.color_streak_started)
		packet.life = 0.72 if packet.started else 0.5
		rows.append({"s": "%s  +%d" % [start_title if packet.started else chain_title, result.color_streak_points],
			"c": _col(kind).lightened(0.38), "gem": kind})
	if int(result.double_hit_points) > 0:
		packet.double = true
		rows.append({"s": "%s  +%d" % [double_title, result.double_hit_points], "c": LIGHT_FX, "secondary": not rows.is_empty()})
	if not rows.is_empty():
		# Keep the original total below the itemised bonuses. No extra score popup.
		rows.append({"s": packet.s if total_title.is_empty() else total_title, "c": packet.c, "total": true})
		packet.rows = rows
		packet.chain_length = count
		_praise.clear() # Generic praise yields to the named rewards from this hit.
	_fx.queue_redraw()


func clear_combo_feedback() -> void:
	_texts.assign(_texts.filter(func(t): return not t.has("slot")))
	feedback_rects.clear()
	if classic_feedback:
		_praise.clear()


func _feedback_blocked() -> Rect2:
	return feedback_exclusion.call() if feedback_exclusion.is_valid() else Rect2()


func _feedback_row_size(row: Dictionary, base: int) -> int:
	return maxi(10, base - (3 if row.get("total", false) or row.get("secondary", false) else 0))


## Lay out the whole packet at once; try nearby free zones, then the safe board edges.
## Newest hits win. Older packets without a free rectangle are omitted, never queued.
func _feedback_layout(packet: Dictionary, occupied: Array[Rect2]) -> Dictionary:
	var safe := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	var fs := int(clampf(cell * 0.56, 14.0, 22.0))
	if packet.started and not packet.special:
		fs += 2
	var font := feedback_font if feedback_font else number_font
	var width := 0.0
	for row in packet.rows:
		width = maxf(width, font.get_string_size(row.s, HORIZONTAL_ALIGNMENT_LEFT, -1, _feedback_row_size(row, fs)).x + (fs + 5 if row.has("gem") else 0))
	if width + 12 > safe.size.x:
		fs = maxi(9, floori(fs * (safe.size.x - 12) / width))
		width = 0.0
		for row in packet.rows:
			width = maxf(width, font.get_string_size(row.s, HORIZONTAL_ALIGNMENT_LEFT, -1, _feedback_row_size(row, fs)).x + (fs + 5 if row.has("gem") else 0))
	var line := ceilf(font.get_height(fs)) + 2.0
	var extent := Vector2(ceilf(width) + 12, line * packet.rows.size() + 8)
	var center := slot_center(packet.slot)
	var rise: float = minf(16.0, cell * 0.5) * packet.t / packet.life
	var gap := minf(cell * 0.65, 24.0)
	var candidates: Array[Vector2] = [
		center + Vector2(-extent.x * 0.5, -gap - extent.y - rise),
		center + Vector2(-extent.x * 0.5, gap - rise),
		center + Vector2(gap, -extent.y * 0.5 - rise),
		center + Vector2(-gap - extent.x, -extent.y * 0.5 - rise),
		Vector2(center.x - extent.x * 0.5, safe.position.y),
		Vector2(center.x - extent.x * 0.5, safe.end.y - extent.y)]
	for candidate in candidates:
		var pos := Vector2(clampf(candidate.x, safe.position.x, maxf(safe.position.x, safe.end.x - extent.x)),
			clampf(candidate.y, safe.position.y, maxf(safe.position.y, safe.end.y - extent.y)))
		var rect := Rect2(pos, extent)
		if safe.encloses(rect) and not occupied.any(func(other): return other.grow(4).intersects(rect)):
			return {"rect": rect, "font_size": fs, "line": line}
	return {}


func _draw_classic_feedback() -> void:
	feedback_rects.clear()
	if not number_font:
		return
	var occupied: Array[Rect2] = []
	var exclusion := _feedback_blocked()
	if exclusion.has_area():
		occupied.append(exclusion)
	var font := feedback_font if feedback_font else number_font
	for i in range(_texts.size() - 1, -1, -1):
		var packet: Dictionary = _texts[i]
		if not packet.has("slot"):
			continue
		var center := slot_center(packet.slot)
		var q: float = packet.t / packet.life
		var alpha := clampf((1.0 - q) * 2.8, 0.0, 1.0)
		var weight := 0.5 if exclusion.has_area() else 1.0
		# A smooth coloured ring for chains; two short opposing slashes for Double Hit.
		if packet.chain >= 0 and packet.t < 0.42:
			var phase: float = packet.t / 0.42
			var radius := cell * (0.35 + phase * (1.0 if packet.started else 0.55))
			_fx.draw_arc(center, radius, 0, TAU, 40, Color(_col(packet.chain).lightened(0.25), (1.0 - phase) * weight), 2.0, true)
		if packet.double and packet.t < 0.22:
			var sharp: float = 1.0 - packet.t / 0.22
			for side in [-1, 1]:
				var p := center + Vector2(side * cell * (0.35 + (1.0 - sharp) * 0.45), 0)
				_fx.draw_line(p + Vector2(-cell * 0.12, cell * 0.24), p + Vector2(cell * 0.12, -cell * 0.24), Color(LIGHT_FX, sharp * weight), 3.0, true)
		var layout := _feedback_layout(packet, occupied)
		if layout.is_empty():
			continue
		var rect: Rect2 = layout.rect
		occupied.append(rect)
		feedback_rects.append(rect)
		var fs: int = layout.font_size
		# Text uses board-local coordinates without shake, and always stays inside it.
		_fx.draw_set_transform(Vector2.ZERO)
		for row_index in packet.rows.size():
			var row: Dictionary = packet.rows[row_index]
			var row_size := _feedback_row_size(row, fs)
			var row_width := font.get_string_size(row.s, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size).x
			var icon_space := float(fs + 5) if row.has("gem") else 0.0
			var x := rect.get_center().x - (row_width + icon_space) * 0.5
			var y: float = rect.position.y + 4 + layout.line * row_index
			if row.has("gem"):
				_fx.draw_texture_rect(_tex(row.gem), Rect2(Vector2(x, y + (layout.line - fs) * 0.5), Vector2.ONE * fs), false, Color(1, 1, 1, alpha))
			var pos := Vector2(x + icon_space, y + font.get_ascent(row_size))
			var opacity := alpha * (0.7 if row.get("total", false) else 1.0)
			_fx.draw_string_outline(font, pos, row.s, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size, 4, Color(0.02, 0.05, 0.06, opacity))
			_fx.draw_string(font, pos, row.s, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size, Color(row.c, opacity))
		_fx.draw_set_transform(_shake_off)


## Ice breaking off thawed gems: pale shards.
func play_thaw(ps: Array[Vector2i]) -> void:
	for q in ps:
		var h := slot_center(q)
		for j in (6 if _refined() else 10):
			var a := randf() * TAU
			_shards.append({"p": h, "v": Vector2.from_angle(a) * cell * randf_range(2.0, 5.0) + Vector2(0, -cell * 2.0),
				"r": randf() * TAU, "vr": randf_range(-9, 9), "s": cell * randf_range(0.1, 0.2),
				"c": Color(0.85, 0.96, 1.0).lightened(randf() * 0.1), "t": 0.0, "life": randf_range(0.4, 0.7)})
	queue_redraw()


## A bomb went off: a hot burst and a hard shake.
func play_blast(p: Vector2i) -> void:
	var h := slot_center(p)
	_waves.append({"p": h, "t": 0.0, "k": 2.5, "rainbow": false})
	for j in 26:
		var a := randf() * TAU
		_sparks.append({"p": h, "v": Vector2.from_angle(a) * cell * randf_range(3, 9), "t": 0.0,
			"life": randf_range(0.4, 0.8), "s": randf_range(0.3, 0.6), "c": [Color("#ff5d3a"), Color("#ffcf33"), Color("#ffffff")][j % 3]})
	shake(0.35)
	flash(Color("#ff5d3a"), 0.3)
	queue_redraw()


## Expanding ring from a slot; strength 1 for a combo step, 2-3 for precise/perfect.
func play_wave(at: Vector2i, strength := 1.0, rainbow := false) -> void:
	if _refined():
		rainbow = false
	_waves.append({"p": slot_center(at), "t": 0.0, "k": strength, "rainbow": rainbow})
	if strength >= 2.0:
		_waves.append({"p": slot_center(at), "t": -0.12, "k": strength * 0.7, "rainbow": rainbow})


## Firework of sparks over the whole board.
func play_burst(at: Vector2i, count: int, rainbow := true) -> void:
	if _refined():
		count = mini(count, 32)
	var c := slot_center(at)
	for i in count:
		var a := randf() * TAU
		_sparks.append({"p": c, "v": Vector2.from_angle(a) * cell * randf_range(4, 16), "t": 0.0,
			"life": randf_range(0.6, 1.2), "s": randf_range(0.12, 0.3) if _refined() else randf_range(0.35, 0.9), "c": _spark_color(rainbow)})
	_trim_refined_fx()


func flash(color: Color, strength := 0.35) -> void:
	_flash_color = color
	_flash = minf(strength, .12) if _refined() else strength


func shake(amount := 0.18) -> void:
	_shake = maxf(_shake, minf(amount, .12) if _refined() else amount)


func _spark_color(rainbow: bool) -> Color:
	if _refined():
		return [LIGHT_FX, Color("#b9e1df"), Color("#d4c5e8")][randi() % 3]
	return Color.from_hsv(randf(), 0.55, 1.0) if rainbow else Color(1, 0.95, 0.8)


## Big word of praise floating up from a slot ("Great!").
func _tex(k: int) -> Texture2D:
	return JOKER_TEX if k == BoardLogic.JOKER else _gem_tex[k % _gem_tex.size()]


func _col(k: int) -> Color:
	return Color(1, 1, 1) if k == BoardLogic.JOKER else _colors[k % _colors.size()]


## Full clear: a ring of light runs out from the centre over every slot.
func play_clear_wave() -> void:
	_clear_t = 0.0


## Confetti raining over the board (bright mode celebrations).
func play_confetti(count := 60) -> void:
	if _refined():
		# Small jewel flecks from the frame instead of paper falling over the board.
		for i in mini(count / 3, 24):
			var side := -1.0 if i % 2 == 0 else 1.0
			var p := Vector2(origin.x if side < 0 else origin.x + logic.cols * cell,
				origin.y + randf() * logic.rows * cell)
			_shards.append({"p":p,"v":Vector2(-side*cell*randf_range(.3,1),-cell*randf_range(1,3)),
				"r":randf()*TAU,"vr":2.0,"s":cell*.08,"c":LIGHT_FX,"t":0.0,"life":.65})
		_trim_refined_fx()
		return
	for i in count:
		_confetti.append({"p": Vector2(randf_range(0, size.x), randf_range(-size.y * 0.3, 0)),
			"v": Vector2(randf_range(-40, 40), randf_range(120, 260)), "r": randf() * TAU, "vr": randf_range(-6, 6),
			"s": Vector2(randf_range(6, 11), randf_range(10, 18)) * maxf(cell / 40.0, 0.6),
			"c": _colors[randi() % _colors.size()].lightened(0.15), "t": 0.0, "ph": randf() * TAU})


## Make the board frame flash.
func glow(strength := 1.0) -> void:
	_glow = maxf(_glow, strength)


func praise(text: String, at: Vector2i, color: Color, big := 1.0) -> void:
	_praise.append({"p": slot_center(at), "s": text, "c": color, "k": big, "t": 0.0})


## Small ring where the player pressed.
func ripple(at: Vector2i) -> void:
	_ripples.append({"p": slot_center(at), "t": 0.0})


func play_miss(at: Vector2i) -> void:
	_misses.append({"p": slot_center(at), "t": 0.0})
	_shake = 0.18


func show_hint(p: Vector2i) -> void:
	_hint = p
	_hint_t = 0.0


## The board changed outside the view (shuffle, new game): rebuild the static layer.
func mark_dirty() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	_trim_refined_fx()
	_time += delta
	if _deal_t < 1.0:
		_deal_t += delta
		queue_redraw()
	_glint_timer -= delta
	if _glint_timer <= 0.0 and logic:
		_glint_timer = randf_range(0.12, 0.3)
		var i := randi() % logic.cells.size()
		if logic.cells[i] >= 0:
			_glints.append({"i": i, "t": 0.0})
	_age(_glints, delta, 0.6)
	_age(_ripples, delta, 0.35)
	_age(_beams, delta, 0.3)
	_age(_texts, delta, 0.9)
	_age(_misses, delta, 0.45)
	_age(_waves, delta, 0.6)
	_age(_pops, delta, 0.22)
	_glow = maxf(0.0, _glow - delta * 1.5)
	_clear_t += delta
	if not _confetti.is_empty():
		for cf in _confetti:
			cf.t += delta
			cf.p += Vector2(cf.v.x + sin(cf.t * 4.0 + cf.ph) * 50.0, cf.v.y) * delta
			cf.r += cf.vr * delta
		_confetti = _confetti.filter(func(cf): return cf.p.y < size.y + 20 and cf.t < 4.0)
	_age(_praise, delta, 1.1)
	if not _shards.is_empty():
		var g2 := cell * 22.0
		for sd in _shards:
			sd.t += delta
			sd.v.y += g2 * delta
			sd.p += sd.v * delta
			sd.r += sd.vr * delta
		_shards = _shards.filter(func(sd): return sd.t < sd.life)
	if not _flyers.is_empty():
		var g := cell * 26.0
		for f in _flyers:
			f.v.y += g * delta
			f.p += f.v * delta
			f.r += f.vr * delta
		_flyers = _flyers.filter(func(f): return f.p.y < size.y + cell * 2)
	if not _sparks.is_empty():
		for sp in _sparks:
			sp.t += delta
			sp.p += sp.v * delta
			sp.v *= 0.9
		_sparks = _sparks.filter(func(sp): return sp.t < sp.life)
	_flash = maxf(0.0, _flash - delta * 1.4)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		_shake_off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * cell * 0.08 if _shake > 0.0 else Vector2.ZERO
		queue_redraw()
	_hint_t += delta
	_fx.queue_redraw()


func _age(list: Array[Dictionary], delta: float, life: float) -> void:
	if list.is_empty():
		return
	for e in list:
		e.t += delta
	var keep := list.filter(func(e): return e.t < e.get("life", life))
	list.assign(keep)


# ---------------- drawing ----------------

## Static layer: frame, slots, halos and gems. Rebuilt only when something changes.
func _draw() -> void:
	if logic == null:
		return
	var off := _shake_off
	draw_set_transform(off)
	var grid_size := Vector2(logic.cols, logic.rows) * cell
	if _run_surface_layer.visible:
		_run_surface_layer.queue_redraw()  # Follow the existing origin, zoom and shake.
	else:
		draw_style_box(_frame, Rect2(origin - Vector2.ONE * frame_pad, grid_size + Vector2.ONE * frame_pad * 2))

	var focus := _cursor if _keyboard else _hover
	if interactive and logic.in_bounds(focus) and logic.is_empty(focus):
		var lane := Color(0.82, 0.67, 0.33, 0.08)
		draw_rect(Rect2(origin.x, origin.y + focus.y * cell, grid_size.x, cell), lane)
		draw_rect(Rect2(origin.x + focus.x * cell, origin.y, cell, grid_size.y), lane)

	if _refined() and logic.in_bounds(focus):
		var partner := logic.chain[focus.y * logic.cols + focus.x]
		if partner >= 0:
			var q := Vector2i(partner % logic.cols, partner / logic.cols)
			draw_line(slot_center(focus), slot_center(q), Color(LIGHT_FX,.45), 1.5, true)
			draw_arc(slot_center(q), cell*.46, 0, TAU, 24, LIGHT_FX, 1.5, true)
	var gem := cell * (0.96 if skin == "bright" else 0.97)
	var slot := cell * (0.96 if _uses_tiles() else 0.84)
	for y in logic.rows:
		for x in logic.cols:
			if not _uses_tiles() and logic.cells[y * logic.cols + x] >= 0:
				continue  # classic hollows only show where a gem is missing
			var ctr := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			draw_texture_rect(_slot_tex, Rect2(ctr - Vector2.ONE * slot / 2, Vector2.ONE * slot), false)
	for y in logic.rows:
		for x in logic.cols:
			var i := y * logic.cols + x
			var k := logic.cells[i]
			if k < 0:
				continue
			var gs := gem * _deal_scale(i)
			if gs <= 0.5:
				continue
			var ctr := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			if _refined() and k == BoardLogic.JOKER:
				SpecialGemArt.joker(self, ctr, gs)
			else:
				draw_texture_rect(_tex(k), Rect2(ctr - Vector2.ONE * gs / 2, Vector2.ONE * gs), false)
			if _refined():
				SpecialGemArt.overlays(self, ctr, gs, logic.hp[i] >= 2, logic.chain[i] >= 0,
					logic.ice[i] == 1, logic.bomb[i], logic.cham[i] == 1, number_font)
				continue
			if logic.hp.size() > i and logic.hp[i] >= 2:
				draw_texture_rect(BOX_TEX, Rect2(ctr - Vector2.ONE * gs / 2, Vector2.ONE * gs), false)
			if logic.chain.size() > i and logic.chain[i] >= 0:
				var ls := gs * 0.42
				var lp := ctr + Vector2(gs * 0.5 - ls, -gs * 0.5)
				if not _uses_tiles():
					draw_circle(lp + Vector2.ONE * ls / 2, ls * 0.54, Color(0.02, 0.06, 0.07, 0.9))
				draw_texture_rect(LINK_TEX, Rect2(lp, Vector2.ONE * ls), false, Color(0.15, 0.12, 0.3, 0.85) if _uses_tiles() else Color("#e5d39b"))
			if logic.ice.size() > i:
				if logic.ice[i] == 1:
					draw_texture_rect(ICE_TEX, Rect2(ctr - Vector2.ONE * gs / 2, Vector2.ONE * gs), false)
				if logic.cham[i] == 1:
					draw_texture_rect(CHAM_TEX, Rect2(ctr - Vector2.ONE * gs / 2, Vector2.ONE * gs), false)
				if logic.bomb[i] > 0:
					var bs := gs * (0.55 if _uses_tiles() else 0.65)
					var bp := ctr + Vector2(gs * 0.5 - bs * 0.85, -gs * 0.5 - bs * 0.12)
					draw_texture_rect(BOMB_TEX, Rect2(bp, Vector2.ONE * bs), false)
					if number_font:
						var low := logic.bomb[i] <= 2
						var fs := int(bs * 0.5)
						draw_string(number_font, bp + Vector2(0, bs * 0.74), str(logic.bomb[i]), HORIZONTAL_ALIGNMENT_CENTER, bs * 0.94,
							fs, Color("#ff6b5a") if low else Color.WHITE)

	if interactive and logic.in_bounds(focus):
		var col := Color(0.82, 0.67, 0.33, 1.0 if _keyboard else 0.6)
		draw_rect(Rect2(origin + Vector2(focus) * cell + Vector2.ONE * 2, Vector2.ONE * (cell - 4)), col, false, 2.0)


## Effects layer, drawn on top every frame: shining gems, glints, beams, sparks, texts.
func _draw_fx() -> void:
	if logic == null:
		return
	var c := _fx
	var off := _shake_off
	c.draw_set_transform(off)
	var gem := cell * 0.96
	# shining gems: no marker, just a sparkle that flares up every second or so
	for i in logic.shine.size():
		if logic.shine[i] == 0 or logic.cells[i] < 0:
			continue
		var flare := sin(_time * 2.6 + i * 1.7)
		if flare < 0.35:
			continue
		var f := (flare - 0.35) / 0.65
		var ctr := origin + (Vector2(i % logic.cols, i / logic.cols) + Vector2(0.62, 0.32)) * cell
		var ss := cell * 0.7 * f
		c.draw_set_transform(ctr + off, _time * 2.0 + i)
		c.draw_texture_rect(SPARKLE_TEX, Rect2(-Vector2.ONE * ss / 2, Vector2.ONE * ss), false, Color(1, 0.97, 0.85, f))
		c.draw_set_transform(off)
	for gl in _glints:
		var gi: int = gl.i
		if gi >= logic.cells.size() or logic.cells[gi] < 0:
			continue
		var gp := origin + (Vector2(gi % logic.cols, gi / logic.cols) + Vector2(0.3, 0.3)) * cell
		var ga: float = sin(gl.t / 0.6 * PI)
		var gsz := cell * 0.45 * ga
		c.draw_texture_rect(SPARKLE_TEX, Rect2(gp - Vector2.ONE * gsz / 2, Vector2.ONE * gsz), false, Color(1, 1, 1, ga * 0.9))
	for rp in _ripples:
		var q: float = rp.t / 0.35
		c.draw_arc(rp.p, cell * (0.3 + q * 0.6), 0, TAU, 16, Color(BEAM, (1.0 - q) * 0.7), 2.0)
	if _hint.x >= 0:
		var a := 0.45 + 0.35 * sin(_hint_t * 8.0)
		c.draw_circle(slot_center(_hint), cell * 0.32, Color(BEAM, a * 0.35))
		c.draw_arc(slot_center(_hint), cell * 0.36, 0, TAU, 20, Color(BEAM, a), 2.0)
	for b in _beams:
		var a: float = 1.0 - b.t / 0.3
		var bc := Color.from_hsv(fmod(b.t * 3.0 + b.a.x * 0.002, 1.0), 0.5, 1.0) if b.rainbow and not _refined() else BEAM
		c.draw_line(b.a, b.b, Color(bc, a * 0.35), (4.0 + 6.0 * a) * b.w * (.55 if _refined() else 1.0))
		c.draw_line(b.a, b.b, Color(bc, a), (1.0 + 3.0 * a) * b.w)
	for w in _waves:
		if w.t < 0.0:
			continue
		var q: float = w.t / 0.6
		var reach: float = minf(4.5 * w.k, 4.0) if _refined() else 4.5 * w.k
		var rad: float = cell * (0.5 + q * reach)
		var wc := Color.from_hsv(fmod(q * 2.0, 1.0), 0.45, 1.0) if w.rainbow and not _refined() else BEAM
		c.draw_arc(w.p, rad, 0, TAU, 40, Color(wc, (1.0 - q) * 0.8), (2.0 + 4.0 * (1.0 - q)) * w.k * (.45 if _refined() else 1.0))
	for sp in _sparks:
		var a: float = 1.0 - sp.t / sp.life
		var sz: float = cell * sp.s * (0.6 + a * 0.6)
		var sc: Color = sp.get("c", Color(1, 0.95, 0.8))
		c.draw_texture_rect(SPARKLE_TEX, Rect2(sp.p - Vector2.ONE * sz / 2, Vector2.ONE * sz), false, Color(sc, a))
	for f in _flyers:  # classic: knocked-out gems fly off whole, spinning
		c.draw_set_transform(f.p + off, f.r)
		c.draw_texture_rect(_tex(f.k), Rect2(-Vector2.ONE * gem / 2, Vector2.ONE * gem), false)
	c.draw_set_transform(off)
	for pp in _pops:
		var q: float = pp.t / 0.22
		c.draw_circle(pp.p, cell * (0.3 + q * 0.35), Color(1, 1, 1, (1.0 - q) * 0.75))
	for sd in _shards:
		var a: float = 1.0 - sd.t / sd.life
		var r: float = sd.r
		var k: float = sd.s
		var tri := PackedVector2Array([Vector2(cos(r), sin(r)) * k, Vector2(cos(r + PI / 2), sin(r + PI / 2)) * k,
			Vector2(cos(r + PI), sin(r + PI)) * k, Vector2(cos(r + PI * 1.5), sin(r + PI * 1.5)) * k])
		c.draw_set_transform(sd.p + off)
		c.draw_colored_polygon(tri, Color(sd.c, a))
	c.draw_set_transform(off)
	for m in _misses:
		var a: float = 1.0 - m.t / 0.45
		var q := cell * 0.22
		c.draw_line(m.p - Vector2(q, q), m.p + Vector2(q, q), Color(MISS, a), 3.0)
		c.draw_line(m.p + Vector2(q, -q), m.p + Vector2(-q, q), Color(MISS, a), 3.0)
	if number_font:
		for t in _texts:
			if t.has("slot"):
				continue
			var a: float = 1.0 - t.t / 0.9
			var pop: float = 1.0 + 0.35 * maxf(0.0, 1.0 - t.t / 0.15)
			var fs := int(maxf(16.0, cell * 0.75) * t.k * pop)
			if _refined():
				fs = mini(fs, int(maxf(18.0, cell * .55)))
			var p: Vector2 = t.p - Vector2(cell * 2.0, t.t * cell * 1.6 - fs * 0.35)
			c.draw_string(number_font, p + Vector2(1, 2), t.s, HORIZONTAL_ALIGNMENT_CENTER, cell * 4, fs, Color(0, 0, 0, a * 0.6))
			c.draw_string(number_font, p, t.s, HORIZONTAL_ALIGNMENT_CENTER, cell * 4, fs, Color(t.c, a))
	if number_font:
		for pr in _praise:
			if classic_feedback and (not _texts.is_empty() or _feedback_blocked().has_area()):
				continue
			var q: float = pr.t / 1.1
			var a: float = clampf((1.0 - q) * 2.5, 0.0, 1.0)
			var pop: float = 1.0 + 0.5 * maxf(0.0, 1.0 - pr.t / 0.12)
			var fs := int(maxf(26.0, cell * 0.9) * pr.k * pop)
			if _refined():
				fs = mini(fs, int(maxf(22.0, cell * .65)))
			var w := maxf(size.x, cell * 8)
			var pos: Vector2 = Vector2(clampf(pr.p.x - w / 2, -w / 2 + size.x / 2, size.x / 2 - w / 2), pr.p.y - cell * 0.8 - q * cell * 1.8)
			c.draw_string_outline(number_font, pos, pr.s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 2 if _refined() else int(fs * 0.22), Color(0.05, 0.05, 0.15, a))
			c.draw_string(number_font, pos, pr.s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(pr.c, a))
	_draw_classic_feedback()
	if _clear_t < 1.6:
		var cc := Vector2(logic.cols - 1, logic.rows - 1) / 2.0
		var far := cc.length() + 1.0
		for y in logic.rows:
			for x in logic.cols:
				var d := Vector2(x, y).distance_to(cc) / far
				var a := 1.0 - absf(_clear_t / 1.0 - d) * 5.0
				if a > 0.0:
					var pos := origin + Vector2(x, y) * cell
					if _refined():
						c.draw_arc(pos+Vector2.ONE*cell/2,cell*.4,0,TAU,16,Color(LIGHT_FX,a*.38),1.3,true)
					else:
						c.draw_rect(Rect2(pos + Vector2.ONE * 2, Vector2.ONE * (cell - 4)), Color(1, 0.95, 0.7, a * 0.7))
	for cf in _confetti:
		var a: float = clampf(4.0 - cf.t, 0.0, 1.0)
		c.draw_set_transform(cf.p, cf.r, Vector2(1.0, absf(cos(cf.t * 6.0 + cf.ph))))
		c.draw_rect(Rect2(-cf.s / 2, cf.s), Color(cf.c, a))
	c.draw_set_transform(off)
	if _glow > 0.0:
		var gs := Vector2(logic.cols, logic.rows) * cell
		var fr := Rect2(origin - Vector2.ONE * frame_pad, gs + Vector2.ONE * frame_pad * 2)
		c.draw_rect(fr.grow(2.0), Color(LIGHT_FX, _glow * .5) if _refined() else Color(1, 1, 1, _glow * 0.8), false, (2.0 if _refined() else 4.0) + _glow * 4.0)
	if _flash > 0.0:
		c.draw_set_transform(Vector2.ZERO)
		var grid_size := Vector2(logic.cols, logic.rows) * cell
		c.draw_rect(Rect2(origin - Vector2.ONE * frame_pad, grid_size + Vector2.ONE * frame_pad * 2), Color(_flash_color, _flash))


# ---------------- input ----------------

## Observe all touch IDs, including a second finger on the HUD. Only _gui_input
## can start aiming, so touching another Control never starts a board action.
func _input(event: InputEvent) -> void:
	if not OS.has_feature("android"):
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and not event.canceled:
			_touches[event.index] = pos
			if not interactive or not is_visible_in_tree():
				_cancel_android_touch()
			elif _touches.size() > 1:
				_android_blocked = true
				_android_touch_id = -1
				_hover = Vector2i(-1, -1)
				queue_redraw()
				if _android_captured and zoom_enabled and _touches.size() == 2:
					_begin_pinch()
				else:
					_pinch.clear()
		else:
			var commit: bool = _touches.has(event.index) and event.index == _android_touch_id \
				and not event.canceled and not _android_blocked and interactive and is_visible_in_tree()
			var selected := _android_slot_at(pos) if commit else Vector2i(-1, -1)
			_touches.erase(event.index)
			if event.canceled:
				_cancel_android_touch()
			elif _touches.is_empty():
				_cancel_android_touch()
			elif _android_captured and zoom_enabled and _touches.size() == 2:
				_begin_pinch()
			else:
				_pinch.clear()
			# Clear the gesture before emitting: the existing hit handler may pause,
			# finish or replace the board synchronously. Duplicate releases do nothing.
			if selected.x >= 0:
				grab_focus()
				slot_pressed.emit(selected)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		_touches[event.index] = pos
		if not interactive or not is_visible_in_tree():
			_cancel_android_touch()
		elif _android_captured and zoom_enabled and _touches.size() == 2 and not _pinch.is_empty():
			_apply_pinch()
		elif event.index == _android_touch_id and not _android_blocked:
			_hover = _android_slot_at(pos)
			queue_redraw()


## A zoomed board extends beyond its clipped Control; those hidden cells cannot
## receive a release over the HUD or outside the visible board area.
func _android_slot_at(pos: Vector2) -> Vector2i:
	return slot_at(pos) if Rect2(Vector2.ZERO, size).has_point(pos) else Vector2i(-1, -1)


func _cancel_android_touch(forget_touches := false) -> void:
	if forget_touches:
		_touches.clear()
	_android_touch_id = -1
	_android_captured = false
	_android_blocked = not _touches.is_empty()
	_pinch.clear()
	_hover = Vector2i(-1, -1)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if OS.has_feature("android"):
		if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
			accept_event()
			return
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			if event is InputEventScreenTouch and event.pressed and not event.canceled \
					and interactive and not _android_blocked and _touches.size() == 1:
				var selected := _android_slot_at(event.position)
				if selected.x >= 0:
					_android_touch_id = event.index
					_android_captured = true
					_keyboard = false
					_hover = selected
					queue_redraw()
			accept_event()
			return
	if zoom_enabled and _zoom_input(event):
		accept_event()
		return
	if event is InputEventMouseMotion:
		_keyboard = false
		var p := slot_at(event.position)
		if p != _hover:
			_hover = p
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_keyboard = false
		var p := slot_at(event.position)
		if p.x >= 0:
			grab_focus()
			slot_pressed.emit(p)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var dirs := {KEY_LEFT: Vector2i(-1, 0), KEY_RIGHT: Vector2i(1, 0), KEY_UP: Vector2i(0, -1), KEY_DOWN: Vector2i(0, 1),
			KEY_A: Vector2i(-1, 0), KEY_D: Vector2i(1, 0), KEY_W: Vector2i(0, -1), KEY_S: Vector2i(0, 1)}
		if dirs.has(event.keycode):
			_keyboard = true
			if not logic.in_bounds(_cursor):
				_cursor = Vector2i(logic.cols / 2, logic.rows / 2)
			else:
				var d: Vector2i = dirs[event.keycode]
				_cursor = Vector2i(posmod(_cursor.x + d.x, logic.cols), posmod(_cursor.y + d.y, logic.rows))
			queue_redraw()
			accept_event()
		elif event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and logic.in_bounds(_cursor):
			slot_pressed.emit(_cursor)
			accept_event()


func _notification(what: int) -> void:
	if OS.has_feature("android"):
		if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
			_cancel_android_touch(true)
		elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
			_cancel_android_touch()
		elif what == NOTIFICATION_MOUSE_EXIT and _android_touch_id >= 0:
			return # Emulated mouse notifications must not overwrite the finger's aim.
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2i(-1, -1)
		queue_redraw()


## Zoom-aware input: two fingers pinch and pan; with zoom on, one finger pans by dragging and
## a strike fires on release of a short tap. Returns true when the event was used here.
func _zoom_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			_begin_pinch()
			_gestured = true
		elif _touches.size() < 2:
			_pinch.clear()
		return _touches.size() >= 2 or not _pinch.is_empty()
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and not _pinch.is_empty():
			_apply_pinch()
			return true
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_moved = false
			_gestured = _touches.size() >= 2
			_press_pos = event.position
			return true
		if _pressing:
			_pressing = false
			if not _moved and not _gestured:
				var p := slot_at(event.position)
				if p.x >= 0:
					grab_focus()
					slot_pressed.emit(p)
			return true
	if event is InputEventMouseMotion and _pressing:
		if (event.position - _press_pos).length() > 12.0:
			_moved = true
		if _moved and zoom > 1.0 and _touches.size() < 2:
			pan += event.relative
			_relayout()
		return true
	return false


func _begin_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch = {"d": maxf(1.0, (pts[0] - pts[1]).length()), "z": zoom, "mid": (pts[0] + pts[1]) / 2, "pan": pan}


func _apply_pinch() -> void:
	var pts: Array = _touches.values()
	var d := maxf(1.0, (pts[0] - pts[1]).length())
	var mid: Vector2 = (pts[0] + pts[1]) / 2
	var z := clampf(_pinch.z * d / _pinch.d, 1.0, 3.0)
	if z < 1.05:
		z = 1.0
	# Keep the existing zoom limits and zoom-around-midpoint/pan calculation.
	var anchor: Vector2 = _pinch.mid - size / 2 - _pinch.pan
	zoom = z
	pan = _pinch.pan + anchor * (1.0 - z / _pinch.z) + (mid - _pinch.mid)
	_relayout()


## Keep the keyboard cursor on the same slot after a transpose.
func transposed() -> void:
	var packets: Array[Dictionary] = []
	for text in _texts:
		if text.has("slot"):
			text.slot = Vector2i(text.slot.y, text.slot.x)
			packets.append(text)
	if _cursor.x >= 0:
		_cursor = Vector2i(_cursor.y, _cursor.x)
	_hover = Vector2i(-1, -1)
	reset_zoom()
	clear_fx()
	_texts.append_array(packets)
