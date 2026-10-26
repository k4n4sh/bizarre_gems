class_name Hud
extends Control
## Scene-owned widgets. Geometry and animation never change game counters/timers.
signal pause_pressed
signal restart_pressed
signal settings_pressed
signal hint_pressed
signal home_pressed
@export var skin := "bright"
const HUD_IDLE := Color(.47,.59,.65,.72)
const BUTTON_STATES := ["normal", "hover", "pressed", "disabled", "focus"]
const MIDDLE_MIN := 380.0  ## Run's middle plate: score, chain, field and record side by side
@onready var score_label: Label = $Stats/Score/Block/Value
@onready var best_label: Label = $Stats/Best/Block/Value
@onready var time_label: Label = $Stats/Time/Block/Value
@onready var time_bar: ProgressBar = $Stats/Time/Block/Bar
@onready var time_delta: Label = $Stats/Time/Block/Value/Delta/Label
@onready var btn_pause: Button = $Buttons/Pause
@onready var btn_restart: Button = $Buttons/Restart
@onready var btn_settings: Button = $Buttons/Settings
@onready var btn_hint: Button = get_node_or_null("Buttons/Hint")
@onready var btn_home: Button = get_node_or_null("Buttons/Home")
@onready var plates: Control = get_node_or_null("Plates")
@onready var level_label: Label = get_node_or_null("Stats/Field/Block/Value")
@onready var chain_slot: Control = $Stats/Chain
@onready var chain_gem: TextureRect = $Stats/Chain/Block/Progress/Gem
@onready var chain_count: Label = $Stats/Chain/Block/Progress/Count
@onready var streak: PanelContainer = $Stats/Combo/Streak/Panel
@onready var run_badge: Control = get_node_or_null("Stats/Combo/RunBadge")
var combo_box: PanelContainer
var combo_mult: Label
var combo_count: Label
var combo_bar: ProgressBar
var title_label: Label
var mode_id := ""
var side_layout := false
var stat_slots: Array[Control] = []
var top_layout := false  ## Classic on desktop/web: three plates in a row, buttons outside them

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_slots.assign([$Stats/Time,$Stats/Score,$Stats/Best,$Stats/Combo,$Stats/Chain])
	if level_label: stat_slots.append($Stats/Field)
	btn_pause.pressed.connect(func(): Sfx.play("click"); pause_pressed.emit())
	btn_restart.pressed.connect(func(): Sfx.play("click"); restart_pressed.emit())
	btn_settings.pressed.connect(func(): settings_pressed.emit())
	if btn_hint: btn_hint.pressed.connect(func(): hint_pressed.emit())
	if btn_home: btn_home.pressed.connect(func(): Sfx.play("click"); home_pressed.emit())
	if plates:
		$Plates/TimeRing.source = time_bar
		$Plates/TimeRing.drain_clockwise = true
		$Plates/StreakRing.source = $Stats/Combo/Streak/Panel/VBox/Bar
	configure("bright" if skin == "bright" else "classic",false)

func configure(id: String, android: bool) -> void:
	if mode_id != id and run_badge: run_badge.reset()
	mode_id = id
	side_layout = id == "classic" and android
	$Stats/Combo/Streak.visible = id != "bright"
	if run_badge: run_badge.visible = id == "bright" # Daily and Challenge are also real Run.
	combo_box = run_badge.panel if id == "bright" else streak
	combo_mult = run_badge.label if id == "bright" else $Stats/Combo/Streak/Panel/VBox/Mult
	combo_count = $Stats/Combo/Streak/Panel/VBox/Count
	combo_bar = run_badge.bar if id == "bright" else $Stats/Combo/Streak/Panel/VBox/Bar
	chain_slot.visible = id in ["classic","bright","tutorial"]
	if level_label: $Stats/Field.visible = id != "tutorial"
	for slot in [$Stats/Time,$Stats/Score,$Stats/Best]:
		slot.get_node("Block/Caption").text = L.t("lesson_practice" if id == "tutorial" and slot == $Stats/Best else slot.name.to_lower())
		slot.get_node("Block/Bar").modulate.a = 1 if slot == $Stats/Time else 0
	$Stats/Chain/Block/Caption.text = L.t("color_streak_chain")
	if level_label:
		$Stats/Field/Block/Caption.text = L.t("run_field_caption" if id == "bright" else "level_short",{"n":""})
		$Stats/Field/Block/Bar.modulate.a = 0
	if top_layout: _top_combo(true)

func layout(_view: Vector2, _compact: bool) -> void:
	pass # GameComposition fits the actual field and safe area.

func layout_practice(rect: Rect2) -> void:
	_typography(false)
	_place($Stats,rect)
	var top := [$Stats/Time,$Stats/Score,$Stats/Best]
	var actions_width := minf(240,rect.size.x*.4)
	var width := (rect.size.x-actions_width-24)/3
	for i in top.size(): _place(top[i],Rect2(i*(width+8),0,width,52))
	_buttons(Rect2(rect.position+Vector2(rect.size.x-actions_width,0),Vector2(actions_width,52)))
	var y := 56.0 if rect.size.y > 64 else 0.0
	if y == 0:
		width = (rect.size.x-actions_width-40)/5
		for i in top.size(): _place(top[i],Rect2(i*(width+8),0,width,64))
	_place($Stats/Combo,Rect2(0 if y > 0 else 3*(width+8),y,rect.size.x*.46 if y > 0 else width,52))
	_place($Stats/Chain,Rect2(rect.size.x*.52 if y > 0 else 4*(width+8),y,rect.size.x*.35 if y > 0 else width,52))
	_fit_combo()

func header_height(width: float) -> float:
	return 128 if mode_id == "bright" and width < 680 else 64

func _place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size
	if node.has_method("_fit"): node.call("_fit")

func _typography(sides: bool, centered := false) -> void:
	_top_off()
	for slot in [$Stats/Time,$Stats/Score,$Stats/Best]:
		var caption: Label = slot.get_node("Block/Caption")
		var value: Label = slot.get_node("Block/Value")
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
		value.horizontal_alignment = caption.horizontal_alignment
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if sides else TextServer.AUTOWRAP_OFF
		value.add_theme_font_size_override("font_size",28 if slot == $Stats/Time or not sides else 24)
		value.add_theme_font_override("font",UiKit.NUMBER_FONT)
		slot.get_node("Block").add_theme_constant_override("separation",2 if sides else 3)
		slot.get_node("Block/Bar").visible = not sides or slot == $Stats/Time
	$Stats/Combo/Streak/Panel/VBox.add_theme_constant_override("separation",2 if sides else 3)
	combo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	combo_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if sides else TextServer.AUTOWRAP_OFF
	if mode_id != "bright":
		combo_mult.horizontal_alignment = combo_count.horizontal_alignment
		combo_mult.add_theme_font_size_override("font_size",30 if sides else 28)
		combo_mult.add_theme_font_override("font",load("res://assets/fonts/RussoOne-Regular.ttf") if sides else UiKit.NUMBER_FONT)
	$Stats/Chain/Block/Caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	$Stats/Chain/Block.add_theme_constant_override("separation",2 if sides else 3)
	$Stats/Chain/Block/Progress.alignment = BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_BEGIN
	$Stats/Chain/Block/Space.visible = not sides
	chain_count.add_theme_font_size_override("font_size",24 if sides else 28)
	$Stats/Time/Block/Bar.custom_minimum_size.y = 6 if sides else 4
	$Stats/Time.vertical_padding = 18 if sides else 0
	var delta: Control = time_delta.get_parent()
	var target: Control = time_bar if sides else time_label
	if delta.get_parent() != target:
		delta.reparent(target,false)
	delta.position = Vector2(0,7) if sides else (Vector2(0,38) if mode_id == "bright" else Vector2(55,6))
	delta.size = Vector2(49,28)
	time_delta.add_theme_font_size_override("font_size",12 if sides else 14)

## Classic and Bright Run on desktop/web. Three plates: time on the left, score, chain (and
## the Run field) and record in the middle, the streak/combo on the right. Square buttons as
## tall as the plates: outside the field frame for Classic, at the ends of the row for the
## full-width Run field (`buttons_inside`). Returns the rect for the record bar inside the
## middle plate.
func layout_top(rect: Rect2, buttons_inside := false) -> Rect2:
	_typography(false)
	top_layout = true
	_top_combo(true)
	var h := rect.size.y
	var gap := 8.0
	var b := h
	var left_buttons: Array[Button] = [btn_home, btn_pause]
	var right_buttons: Array[Button] = [btn_restart, btn_settings]
	if btn_hint: right_buttons.push_front(btn_hint)
	var button_x := [rect.position.x - gap * 2 - b * 2, rect.end.x + gap]
	var button_y := rect.position.y
	if buttons_inside:
		# On a narrow row the buttons shrink first so the middle plate keeps room for four numbers.
		var count := left_buttons.size() + right_buttons.size()
		var plates_min := floorf(clampf(rect.size.x * 0.2, 140, 230)) * 2 + gap * 2 + MIDDLE_MIN
		b = floorf(clampf((rect.size.x - plates_min) / count - gap, 52, h))
		button_y = rect.position.y + floorf((h - b) * 0.5)
		button_x = [rect.position.x, rect.end.x - right_buttons.size() * (b + gap) + gap]
		rect = Rect2(rect.position.x + left_buttons.size() * (b + gap), rect.position.y,
			rect.size.x - (left_buttons.size() + right_buttons.size()) * (b + gap), h)
	var side := floorf(clampf(rect.size.x * 0.22, 160, 230)) if not buttons_inside else floorf(clampf(rect.size.x * 0.2, 140, 230))
	var mid := rect.size.x - side * 2 - gap * 2
	var pad := 14.0
	plates.visible = true
	var plate_style := UiKit.box(Color(0.03, 0.05, 0.16, 0.55), Color(1, 1, 1, 0.12), 1, 16, Vector4.ZERO)
	var boxes := {"Time": Rect2(rect.position.x, rect.position.y, side, h),
		"Score": Rect2(rect.position.x + side + gap, rect.position.y, mid, h),
		"Streak": Rect2(rect.end.x - side, rect.position.y, side, h)}
	for k in boxes:
		var p: Panel = plates.get_node(k)
		p.add_theme_stylebox_override("panel", plate_style)
		_place(p, boxes[k])
	_place($Stats, Rect2(Vector2.ZERO, size))
	var ring := floorf(minf(52, h - 28))
	var ring_y := rect.position.y + floorf((h - ring) * 0.5)
	var time_ring: HudRing = $Plates/TimeRing
	var streak_ring: HudRing = $Plates/StreakRing
	_place(time_ring, Rect2(boxes.Time.position.x + pad, ring_y, ring, ring))
	_place(streak_ring, Rect2(boxes.Streak.position.x + pad, ring_y, ring, ring))
	var text_x := pad + ring + 12
	var text_h := minf(56.0, h - 12)
	var text_y := rect.position.y + floorf((h - text_h) * 0.5)
	_place($Stats/Time, Rect2(boxes.Time.position.x + text_x, text_y, side - text_x - pad, text_h))
	_place($Stats/Combo, Rect2(boxes.Streak.position.x + text_x, text_y, side - text_x - pad, text_h))
	_fit_combo()
	# Middle plate: one caption row for score, chain and record, the bar under the numbers.
	var inner := Rect2(boxes.Score.position + Vector2(pad + 4, 6), Vector2(mid - pad * 2 - 8, h - 12))
	var bar_h := RecordBar.COMPACT_HEIGHT
	var row_h := inner.size.y - bar_h - 4
	var middle: Array[Control] = [$Stats/Chain]
	if level_label and mode_id == "bright":
		middle.append($Stats/Field)
		$Stats/Field.visible = true
	var chain_w := 90.0 if middle.size() == 1 else 80.0
	var num_w := (inner.size.x - chain_w * middle.size()) * 0.5
	_place($Stats/Score, Rect2(inner.position, Vector2(num_w, row_h)))
	for i in middle.size():
		_place(middle[i], Rect2(inner.position + Vector2(num_w + chain_w * i, 0), Vector2(chain_w, row_h)))
	_place($Stats/Best, Rect2(inner.position + Vector2(inner.size.x - num_w, 0), Vector2(num_w, row_h)))
	_top_typography()
	# Buttons: squares in a row on each side, as tall as the plates, spaced like the plates.
	_place($Buttons, Rect2(Vector2.ZERO, size))
	var icon_pad := floorf(b * 0.16)
	var columns := [left_buttons, right_buttons]
	var xs := button_x
	for c in 2:
		for i in columns[c].size():
			var btn: Button = columns[c][i]
			btn.visible = true
			btn.expand_icon = true
			for state in BUTTON_STATES:
				var style := btn.get_theme_stylebox(state).duplicate() as StyleBox
				style.set_content_margin_all(icon_pad)
				btn.add_theme_stylebox_override(state, style)
			btn.custom_minimum_size = Vector2.ONE * b
			btn.size = Vector2.ONE * b
			btn.scale = Vector2.ONE
			btn.position = Vector2(xs[c] + i * (b + gap), button_y)
	return Rect2(inner.position.x, inner.end.y - bar_h, inner.size.x, bar_h)

## Width the top layout needs outside the field frame on each side (two buttons in a row).
func top_side_room(height: float) -> float:
	return height * 2 + 8 * 2


func _top_typography() -> void:
	for slot in [$Stats/Time, $Stats/Score, $Stats/Best, $Stats/Chain, $Stats/Combo/Streak]:
		slot.top_align = slot != $Stats/Time and slot != $Stats/Combo/Streak
	for slot in [$Stats/Score, $Stats/Best]:
		slot.get_node("Block/Bar").visible = false
		slot.get_node("Block/Value").add_theme_font_size_override("font_size", 26)
	$Stats/Time/Block/Bar.visible = false
	$Stats/Best/Block/Caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_label.add_theme_color_override("font_color", UiKit.MUTED)
	$Stats/Chain/Block/Caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Stats/Chain/Block/Progress.alignment = BoxContainer.ALIGNMENT_CENTER
	$Stats/Chain/Block/Space.visible = false
	if level_label and $Stats/Field.visible:
		$Stats/Field.top_align = true
		$Stats/Field/Block/Bar.visible = false
		$Stats/Field/Block/Caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_label.add_theme_font_size_override("font_size", 26)
	$Stats/Combo/Streak/Panel/VBox/Bar.visible = false
	time_delta.get_parent().position = Vector2(62, 6)
	for slot in [$Stats/Time, $Stats/Score, $Stats/Best, $Stats/Chain, $Stats/Combo/Streak]:
		slot.call_deferred("_fit")
	if level_label: $Stats/Field.call_deferred("_fit")


func _top_off() -> void:
	if not top_layout: return
	top_layout = false
	plates.visible = false
	btn_home.visible = false
	for b in [btn_pause, btn_restart, btn_settings, btn_hint]:
		if not b: continue
		b.expand_icon = false
		for state in BUTTON_STATES: b.remove_theme_stylebox_override(state)
	for slot in [$Stats/Score, $Stats/Best]:
		slot.get_node("Block/Value").remove_theme_font_size_override("font_size")
	_top_combo(false)
	for slot in [$Stats/Time, $Stats/Score, $Stats/Best, $Stats/Chain, $Stats/Combo/Streak]: slot.top_align = false
	if level_label:
		$Stats/Field.top_align = false
		$Stats/Field/Block/Caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		level_label.remove_theme_font_size_override("font_size")
	best_label.remove_theme_color_override("font_color")
	$Stats/Best/Block/Caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	$Stats/Combo/Streak/Panel/VBox/Bar.visible = true
	set_combo(0)


## Bright Run's top row uses the plain streak plate with a ring instead of the coloured badge.
func _top_combo(on: bool) -> void:
	if not run_badge: return
	var plate := on and mode_id == "bright"
	$Stats/Combo/Streak.visible = plate or mode_id != "bright"
	run_badge.visible = not plate and mode_id == "bright"
	combo_box = streak if plate else run_badge.panel
	combo_mult = $Stats/Combo/Streak/Panel/VBox/Mult if plate else run_badge.label
	combo_bar = $Stats/Combo/Streak/Panel/VBox/Bar if plate else run_badge.bar


func _buttons(rect: Rect2, vertical := false) -> void:
	_place($Buttons,rect)
	var actions: Array[Button] = [btn_pause,btn_restart]
	if btn_hint: actions.append(btn_hint)
	actions.append(btn_settings)
	var gap := 16.0 if vertical else 8.0
	var side := stat_slots[0].size.x if vertical else 52.0
	var extent := Vector2(side,side*actions.size()+gap*(actions.size()-1)) if vertical else Vector2(side*actions.size()+gap*(actions.size()-1),side)
	var fit := minf(1,minf(rect.size.x/maxf(1,extent.x),rect.size.y/maxf(1,extent.y)))
	for i in actions.size():
		actions[i].custom_minimum_size = Vector2.ONE*side
		actions[i].size = Vector2.ONE*side
		actions[i].scale = Vector2.ONE*fit
		var origin := (rect.size-extent*fit)*.5
		if not vertical:
			origin.x = rect.size.x-extent.x*fit
		actions[i].position = origin+(Vector2(0,i*(side+gap)) if vertical else Vector2(i*(side+gap),0))*fit

func layout_header(rect: Rect2) -> void:
	_typography(false)
	_place($Stats,rect)
	var gap := floorf(clampf(rect.size.x*.015,4,16))
	var count := stat_slots.size()
	var buttons_width := floorf(rect.size.x*(.30 if mode_id == "bright" else .22))
	if rect.size.y > 64:
		var top: Array[Control] = [$Stats/Time,$Stats/Score,$Stats/Best]
		var width := (rect.size.x-buttons_width-gap*3)/3
		for i in top.size(): _place(top[i],Rect2(i*(width+gap),0,width,64))
		_buttons(Rect2(rect.position+Vector2(rect.size.x-buttons_width,0),Vector2(buttons_width,64)))
		var badge_width := floorf(rect.size.x*.46)
		_place($Stats/Combo,Rect2(0,64,badge_width,64))
		_place($Stats/Chain,Rect2(badge_width+gap,64,(rect.size.x-badge_width-gap*2)*.55,64))
		_place($Stats/Field,Rect2(rect.size.x-(rect.size.x-badge_width-gap*2)*.45,64,(rect.size.x-badge_width-gap*2)*.45,64))
	else:
		var badge_width := floorf(rect.size.x*.23) if mode_id == "bright" else 0.0
		var normal_width := maxf(1,(rect.size.x-buttons_width-gap*count-badge_width)/(count-1 if badge_width > 0 else count))
		var x := 0.0
		for slot in stat_slots:
			var width := badge_width if slot == $Stats/Combo and badge_width > 0 else normal_width
			_place(slot,Rect2(x,0,width,64))
			x += width+gap
		_buttons(Rect2(rect.position+Vector2(rect.size.x-buttons_width,0),Vector2(buttons_width,64)))
	_fit_combo()

func _fit_combo() -> void:
	_place($Stats/Combo/Streak,Rect2(Vector2.ZERO,$Stats/Combo.size))
	if run_badge: _place(run_badge,Rect2(Vector2.ZERO,$Stats/Combo.size))

func layout_sides(board_rect: Rect2, view: Vector2, insets: Rect2) -> void:
	_typography(true,true)
	var side_inset := maxf(ceilf(insets.position.x),ceilf(insets.size.x))
	var vertical_inset := maxf(ceilf(insets.position.y),ceilf(insets.size.y))
	var safe_height := view.y-vertical_inset*2-8
	var content := floorf(clampf((view.x-board_rect.size.x)*.5-side_inset*2-8,70,80))
	# Match the reference HBox's 4px gaps on both sides of the board.
	_place($Stats,Rect2(0,0,maxf(1,board_rect.position.x-4),size.y))
	var gap := roundf(clampf(safe_height*.016,4,8))
	var height := minf(74,floorf((safe_height-16-4*gap)/10)*2)
	var top := floorf((size.y-height*5-gap*4)/2)
	for i in 5: _place(stat_slots[i],Rect2(floorf(($Stats.size.x-content)/2),top+i*(height+gap),content,height))
	time_label.add_theme_font_size_override("font_size",26 if content < 74 else 28)
	$Stats/Time.call_deferred("_fit") # Fit after the font's queued minimum-size update.
	if level_label: $Stats/Field.visible = false
	_buttons(Rect2(board_rect.end.x+4,0,size.x-board_rect.end.x-4,size.y),true)
	_fit_combo()

func layout_portrait(rect: Rect2) -> void:
	_typography(false,true)
	_place($Stats,rect)
	var outer := 112.0
	var mid := maxf(1,rect.size.x-outer*2)
	_place($Stats/Score,Rect2(outer,0,mid,52))
	_place($Stats/Best,Rect2(outer,52,mid*.6,40))
	_place($Stats/Field,Rect2(outer+mid*.6,52,mid*.4,40))
	var gap := 6.0
	var badge_width := floorf(rect.size.x*.46)
	var chain_width := floorf(rect.size.x*.20)
	_place($Stats/Time,Rect2(0,94,rect.size.x-badge_width-chain_width-gap*2,44))
	_place($Stats/Combo,Rect2(rect.size.x-badge_width-chain_width-gap,94,badge_width,44))
	_place($Stats/Chain,Rect2(rect.size.x-chain_width,94,chain_width,44))
	_place($Buttons,rect)
	var actions := [btn_pause,btn_restart,btn_hint,btn_settings]
	for i in actions.size():
		actions[i].custom_minimum_size = Vector2(52,52)
		actions[i].size = Vector2(52,52)
		actions[i].scale = Vector2.ONE
		actions[i].position = Vector2(i*60 if i < 2 else rect.size.x-(4-i)*60+8,20)
	_fit_combo()

func set_time(text: String, fraction: float, low: bool) -> void:
	time_label.text = text
	time_label.add_theme_color_override("font_color",UiKit.DANGER if low else UiKit.CREAM)
	time_bar.theme_type_variation = &"ProgressBarLow" if low else &""
	time_bar.value = clampf(fraction,0,1)*100
	if plates: $Plates/TimeRing.color = UiKit.DANGER if low else UiKit.COMBO_COLORS[1]

func set_buttons(playing: bool, can_restart: bool) -> void:
	btn_pause.disabled = not playing
	btn_restart.disabled = not can_restart

func set_combo(streak_length: int, pulse := false) -> void:
	var multiplier := ScoreKeeper.multiplier_for(streak_length) if streak_length >= 2 else 1
	if mode_id == "bright" and not top_layout:
		run_badge.show_combo(streak_length,multiplier,pulse)
		return
	var tint: Color = UiKit.COMBO_COLORS[multiplier-1].lightened(.3)
	if top_layout:
		# The ring carries the multiplier; the plate shows the caption and the streak length.
		combo_count.text = L.t("combo" if mode_id == "bright" else "streak_caption")
		combo_mult.text = str(streak_length if streak_length >= 2 else 0)
		$Plates/StreakRing.color = UiKit.COMBO_COLORS[multiplier-1]
		$Plates/StreakRing.set_text("×%d" % multiplier, tint)
	else:
		combo_count.text = L.t("streak_caption")+(" %d" % streak_length if streak_length >= 2 else "")
		combo_mult.text = "×%d" % multiplier
	combo_mult.add_theme_color_override("font_color",tint)
	_activity(streak,streak_length >= 2)
	if pulse: pop(combo_mult)

func fade_combo() -> void:
	if mode_id == "bright" and not top_layout: run_badge.fade_combo()
	else: set_combo(0)

func reset_feedback() -> void:
	if run_badge:
		run_badge.reset()

func update_progress(keeper: ScoreKeeper, now: float, active: bool, board: BoardView, field: int) -> void:
	combo_bar.value = keeper.window_left(now)/keeper.combo_window*100
	var chain_active := keeper.classic_bonus_combos and keeper.color_streak_hits >= 2 and active
	_activity($Stats/Chain/Block,chain_active)
	chain_gem.texture = board._tex(keeper.color_streak_kind) if chain_active else BoardView.GEM_TEX[6]
	chain_count.text = str(keeper.color_streak_hits) if chain_active else "0"
	if mode_id == "bright": level_label.text = str(field)

func _activity(control: Control, active: bool) -> void:
	if control.has_meta("hud_active") and control.get_meta("hud_active") == active: return
	control.set_meta("hud_active",active)
	var previous: Tween = control.get_meta("activity_tween") if control.has_meta("activity_tween") else null
	if previous and previous.is_valid(): previous.kill()
	if active: control.modulate = Color.WHITE
	else:
		var tween := create_tween()
		tween.tween_property(control,"modulate",HUD_IDLE,.25)
		control.set_meta("activity_tween",tween)

func flash_delta(text: String, negative: bool, unit := "time") -> void:
	time_delta.text = text+(" "+L.t("steps_unit") if unit == "steps" else (" с" if L.lang == "ru" else (" sn" if L.lang == "tr" else " s")))
	time_delta.add_theme_color_override("font_color",UiKit.DANGER if negative else UiKit.BRASS)
	var previous: Tween = time_delta.get_meta("delta_tween") if time_delta.has_meta("delta_tween") else null
	if previous and previous.is_valid(): previous.kill()
	time_delta.modulate.a = 1
	var tween := create_tween()
	tween.tween_interval(.35)
	tween.tween_property(time_delta,"modulate:a",0,.4)
	time_delta.set_meta("delta_tween",tween)

func pop(control: Control, strength := 1.3) -> void:
	var previous: Tween = control.get_meta("hud_pulse") if control.has_meta("hud_pulse") else null
	if previous and previous.is_valid(): previous.kill()
	control.scale = Vector2.ONE
	control.modulate = Color(strength,strength,strength)
	var tween := create_tween()
	tween.tween_property(control,"modulate",Color.WHITE,.22)
	control.set_meta("hud_pulse",tween)

func set_number(label: Label, value: int) -> void:
	var text := str(value)
	if side_layout:
		var width := maxf($Stats/Score.size.x, 70.0)
		var font_size := 18
		if text.length() <= 6:
			var measured := UiKit.NUMBER_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			font_size = clampi(floori(24.0 * (width - 4.0) / maxf(measured, 1.0)), 18, 24)
		else:
			# Keep every digit. Spaces allow large scores to wrap at whole thousands.
			var grouped := ""
			for i in text.length():
				if i > 0 and (text.length() - i) % 3 == 0:
					grouped += "\u2009"
				grouped += text[i]
			text = grouped
			if width < 74.0:
				# Six-digit lines fit at 18 px even in the narrowest symmetric rail.
				# Line breaks remain at whole-thousands boundaries; every digit is kept.
				var digits := str(value)
				text = ""
				var head := digits.length() % 6
				if head == 0:
					head = 6
				text = digits.substr(0, head)
				for start in range(head, digits.length(), 6):
					text += "\n" + digits.substr(start, 6)
		label.add_theme_font_size_override("font_size", font_size)
	label.text = text
