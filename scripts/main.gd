extends Control
## Game flow and UI. The interface is built in code so layout adapts to any
## screen Yandex Games gives us, from a phone held upright to a wide desktop.

enum State { MENU, PLAYING, PAUSED, OVER }

## Temporarily exposed modes; dormant cards and their progress stay intact.
## Daily Challenge has its own menu entry and starts Bright Run with a daily seed.
const MENU_MODES := ["classic", "bright"]
## Temporary generation policy shared by Bright Run and its Daily Challenge.
## The mechanics remain available to levels/Zen and can be restored here later.
const RUN_HAZARDS_ENABLED := false
const ComboExperiment = preload("res://scripts/combo_experiment.gd")
const MenuPreview = preload("res://scripts/menu_preview.gd")
## Menu-only styling. Gameplay and service-panel themes are intentionally separate.
const MENU_BRASS := Color("#c6a35c")
const MENU_TEXT := Color("#f4edda")
const MENU_MUTED := Color("#a6b7b7")
const MENU_PANEL := Color("#10272b")

var _ab_active := false
var _ab_reported := true
var _ab_run := {}
var _ab_result_index := 0
var last_combo_report := {}

const START_TIME := 120.0
const CONTINUE_TIME := 15.0
const HINT_AFTER := 15.0
const WAVE_TIME := 5.0      ## bonus seconds when a fresh board is dealt
const CLEAR_POINTS := 25    ## bonus for knocking out every gem on a board
const CLEAR_TIME := 5.0

const BRASS := Color("#ffc83d")        ## accent: gold
const BRASS_LIGHT := Color("#ffe9a3")
const CREAM := Color("#ffffff")
const MUTED := Color("#aab8ec")
const DANGER := Color("#ff5d6c")
const INK := Color("#141a3a")
const PANEL := Color(0.08, 0.11, 0.3, 0.97)
## Background surface/light palettes. Gem colours and the cosmetic pack stay independent.
const RUN_PALETTE_SECONDS := 0.0  # Each triggering event changes the atmosphere immediately.
const RUN_SURFACE_LUMA := 0.05*0.2126 + 0.13*0.7152 + 0.14*0.0722
## Original green plus five dyes, with the same dark fabric luminance.
const RUN_FABRICS := [Color(0.05,0.13,0.14), Color("#563367"), Color("#612c3b"),
	Color("#273f79"), Color("#096080"), Color("#765329")]
const RUN_LIGHTS := [Color(0.18,0.71,0.66), Color(0.48,0.31,0.84), Color(0.82,0.67,0.33)]
const THEMES := [
	{"top": Color("#3d63e0"), "bottom": Color("#1b2c8c")},  # original glossy tiles
	{"top": Color("#4a6fd8"), "bottom": Color("#22337f")},  # candy
	{"top": Color("#2f9bb3"), "bottom": Color("#164a6b")},  # ocean
	{"top": Color("#9c4a8f"), "bottom": Color("#45204f")},  # berry
	{"top": Color("#4f8f63"), "bottom": Color("#1f4636")},  # forest
	{"top": Color("#4b4fa3"), "bottom": Color("#1b1c4a")},  # night
	{"top": Color("#7fb3e0"), "bottom": Color("#2b4a7a")},  # winter
	{"top": Color("#4a2a5c"), "bottom": Color("#140b1f")},  # halloween
	{"top": Color("#8a6a2a"), "bottom": Color("#2b2210")},  # gold
]
## Level chapters: caves, glacier, volcano, jungle, space.
const CHAPTER_THEMES := [
	{"top": Color("#5b4a8a"), "bottom": Color("#1e1733")},
	{"top": Color("#6fa8dc"), "bottom": Color("#1f3f6b")},
	{"top": Color("#c2452d"), "bottom": Color("#3a1210")},
	{"top": Color("#3f9a55"), "bottom": Color("#103a22")},
	{"top": Color("#3b3f9e"), "bottom": Color("#090a26")},
]
const COMBO_COLORS := [Color("#3d8bff"), Color("#22c97a"), Color("#ff9a2e"), Color("#ff4dad")]

const ICONS := {
	"pause": preload("res://assets/ui/icon_pause.png"),
	"play": preload("res://assets/ui/icon_play.png"),
	"sound_on": preload("res://assets/ui/icon_sound_on.png"),
	"sound_off": preload("res://assets/ui/icon_sound_off.png"),
	"music_on": preload("res://assets/ui/icon_music_on.png"),
	"music_off": preload("res://assets/ui/icon_music_off.png"),
	"trophy": preload("res://assets/ui/icon_trophy.png"),
	"home": preload("res://assets/ui/icon_home.png"),
	"video": preload("res://assets/ui/icon_video.png"),
	"shuffle": preload("res://assets/ui/icon_shuffle.png"),
	"restart": preload("res://assets/ui/icon_restart.png"),
	"settings": preload("res://assets/ui/icon_settings.png"),
	"calendar": preload("res://assets/ui/icon_calendar.png"),
	"rotate": preload("res://assets/ui/icon_rotate.png"),
	"crown": preload("res://assets/ui/icon_crown.png"),
	"map": preload("res://assets/ui/icon_map.png"),
	"tasks": preload("res://assets/ui/icon_tasks.png"),
	"star": preload("res://assets/ui/icon_star.png"),
	"lock": preload("res://assets/ui/icon_lock.png"),
	"crystal": preload("res://assets/ui/icon_crystal.png"),
	"hint": preload("res://assets/ui/icon_hint.png"),
	"strikes": preload("res://assets/ui/icon_strikes.png"),
	"gift": preload("res://assets/ui/icon_gift.png"),
	"medal": preload("res://assets/ui/icon_medal.png"),
	"puzzle": preload("res://assets/ui/icon_puzzle.png"),
	"hand": preload("res://assets/ui/icon_hand.png"),
	"check": preload("res://assets/ui/icon_check.png"),
	"back": preload("res://assets/ui/icon_back.png"),
	"info": preload("res://assets/ui/icon_info.png"),
	"ticket": preload("res://assets/ui/icon_ticket.png"),
	"chart": preload("res://assets/ui/icon_chart.png"),
	"next": preload("res://assets/ui/icon_next.png"),
	"prev": preload("res://assets/ui/icon_prev.png"),
	"door": preload("res://assets/ui/icon_door.png"),
	"link": preload("res://assets/ui/icon_link.png"),
}

var logic := BoardLogic.new()
var keeper := ScoreKeeper.new()
var daily := false
var mode: Dictionary = BoardLogic.CLASSIC
var wave := 1
var theme_i := 0
var hue_total := 0.0
var dealing := false
## Geometry belongs to a run; Daily still generates in its canonical, seeded orientation.
var _run_dims := Vector2i.ZERO
var _daily_transposed := false
var _run_starting := false
var _run_generation := 0
var level_label: Label
var level_n := 1          ## level being played in the level map mode
var pending_level := 1
var level_total := 0      ## gems on the level board at the start
var strikes := 0          ## no-timer mode: strikes left
var strikes_max := 1
var hints := 1            ## free hints left this game / level
var puzzle_n := 1
var goal_kind := -1       ## level goal: knock out every gem of this kind (-1: none, -2: done)
var board_kinds := 6      ## kinds on the current board (chameleons cycle through them)
var strikes_done := 0     ## successful strikes this game (chameleons shift every CHAM_EVERY)
const CHAM_EVERY := 3
const BOMB_TIME := 5.0    ## a bomb going off costs this many seconds (steps mode: 3 steps)
const BOMB_STEPS := 3
const DEFUSE_POINTS := 10
var paid_crystals := 0    ## crystals already paid for this game's score (a continued game pays the rest)
var paid_xp := 0
var last_earned := 0      ## crystals paid by the last result screen, for the x2 reward
var best_strike := {}     ## the game's highest-scoring strike, replayed on the result screen
var confirm_panel: PanelContainer
var pass_panel: PanelContainer
var stats_panel: PanelContainer
var tut_step := 0
var tut_hand: TextureRect
var tut_label: Label
var btn_hint: Button
const PENTA := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]  ## combo knocks climb this scale
var ambient: Ambient
var shown_score := 0.0
var play_time := 0.0
var rng := RandomNumberGenerator.new()
var state := State.MENU
var time_left := START_TIME
var score := 0
var cleared := 0
var used_continue := false
var used_shuffle := false
var idle := 0.0
var end_reason := ""
var last_tick := -1
var leaders_return: Control
var autoplay := false  # debug builds only: plays itself, for testing effects and screenshots
var _auto_t := 0.0

var f_display: Font
var f_body: Font
var f_bold: Font
var f_num: Font

var board: BoardView
var hud: HBoxContainer
var title_label: Label
var time_caption: Label
var time_label: Label
var time_delta: Label
var time_bar: ProgressBar
var score_caption: Label
var score_label: Label
var best_caption: Label
var best_label: Label
var combo_box: PanelContainer
var combo_style: StyleBoxFlat
var combo_mult: Label
var combo_count: Label
var combo_bar: ProgressBar
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var btn_pause: Button
var btn_settings: Button
var btn_restart: Button
var hud_balance: Control  ## empty slot on the right so the score stays centred
## Rendering only. Never use this value to choose generation, clocks, audio or input rules.
var visual_profile := "classic"
var hud_classic: HBoxContainer
var board_column: VBoxContainer
var classic_sides: HBoxContainer
var classic_stats: VBoxContainer
var classic_actions: VBoxContainer
var _classic_safe_area := Rect2()
var _classic_safe_poll := 0.0
var time_row: HBoxContainer
## Each mode has its own HUD; the shared widget variables point at the active one.
var hud_sets := {}
var settings_return: Control
var compact := false
var ui_scale_info := ""
var rotate_overlay: Control
var margin: MarginContainer
var panel_style: StyleBoxFlat
var panel_style_compact: StyleBoxFlat
var dim: ColorRect
var center: CenterContainer
var toast: Label
var bar_fill: StyleBoxFlat
var bar_fill_low: StyleBoxFlat

var menu_panel: Control  ## the home screen (full screen)
var mode_panel: Control  ## mode selection (full screen)
var _menu_t := 0.0
var pause_panel: PanelContainer
var over_panel: PanelContainer
var leaders_panel: PanelContainer
var settings_panel: PanelContainer
var rules_panel: PanelContainer
var map_panel: Control         ## level map (full screen)
var level_panel: PanelContainer  ## level result with stars
var tasks_panel: PanelContainer
var collection_panel: PanelContainer
var gift_panel: PanelContainer
var ach_panel: PanelContainer
var rules_page := 0
var leaders_board := "score"
var map_kind := "levels"  ## the map screen lists "levels" or "puzzle"
var settings_from_game := false  ## settings opened mid-game: Done goes straight back to playing
var _stuck_t := 0.0
## Lists that scroll by dragging anywhere on them (touch screens start drags on buttons).
var drag_scrolls: Array[ScrollContainer] = []
var _drag: ScrollContainer
var _drag_last := Vector2.ZERO
var _drag_moved := 0.0
var ui := {}  # widgets that carry translated text


func _ready() -> void:
	ComboExperiment.initialize()
	rng.randomize()
	_load_fonts()
	theme = _make_theme()
	_build()
	_apply_ui_scale()
	_set_orientation(false)
	get_window().size_changed.connect(_apply_ui_scale)
	get_viewport().size_changed.connect(_on_viewport_resized)
	board.slot_pressed.connect(_on_slot)
	Yandex.pause_requested.connect(_on_platform_pause)
	Yandex.resume_requested.connect(_on_platform_resume)
	Save.changed.connect(_update_hud)
	L.language_changed.connect(_apply_texts)

	board.logic = logic
	_use_mode(_menu_mode())
	var d := _dims()
	logic.setup(d.x, d.y, rng, mode.shining, mode.kinds, mode.per_kind)
	_apply_texts()
	_on_viewport_resized()
	_show_panel(menu_panel)
	_update_hud()
	if OS.is_debug_build():
		autoplay = "--autoplay" in OS.get_cmdline_user_args()
		if OS.has_feature("web"):
			autoplay = autoplay or str(JavaScriptBridge.eval("location.search")).contains("autoplay")
	if Yandex.is_ready:
		_on_sdk_ready()
	else:
		Yandex.sdk_ready.connect(_on_sdk_ready, CONNECT_ONE_SHOT)


## Debug builds: ?start=map|tasks|coll|zen|bright|classic|levelN opens that screen directly.
func _debug_start() -> void:
	if not (OS.is_debug_build() and OS.has_feature("web")):
		return
	var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('start') || ''"))
	if q == "map":
		_open_map()
	elif q == "tasks":
		_refresh_tasks()
		_show_panel(tasks_panel)
	elif q == "coll":
		_refresh_collection()
		_show_panel(collection_panel)
	elif q.begins_with("level"):
		start_level(maxi(1, int(q.substr(5))))
	elif q in ["zen", "bright", "classic", "tutorial"]:
		start_game(q)
	elif q == "daily":
		start_game("bright", true)
	elif q == "puzzle":
		start_puzzle(1)
	elif q == "modes":
		_show_panel(mode_panel)
	elif q == "pmap":
		_open_map("puzzle")
	elif q == "gift":
		_refresh_gift()
		_show_panel(gift_panel)
	elif q == "ach":
		_refresh_achievements()
		_show_panel(ach_panel)
	elif q == "pass":
		_refresh_pass()
		_show_panel(pass_panel)
	elif q == "stats":
		_refresh_stats()
		_show_panel(stats_panel)
	elif q.begins_with("rules"):
		_show_rules()
		_set_rules_page(int(q.substr(5)))
	elif q == "leave":
		start_game("bright")
		pause_game()
		_ask_leave()
	var t := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('t') || ''"))
	if t != "" and state == State.PLAYING:
		time_left = float(t)
		strikes = mini(strikes, int(t))

func _on_sdk_ready() -> void:
	L.set_language(Yandex.language())
	Save.sync_cloud()
	Yandex.loading_ready()
	_debug_start.call_deferred()
	Sfx.update_music()


# ================= game flow =================

## Old saves may still name a mode whose menu card is currently hidden.
func _menu_mode() -> String:
	return str(Save.mode) if str(Save.mode) in MENU_MODES else "classic"


func start_game(mode_id := "", is_daily := false) -> void:
	_report_combo_ab("restart")
	_run_generation += 1
	var generation := _run_generation
	_run_dims = Vector2i.ZERO
	_daily_transposed = false
	_run_starting = false
	dealing = false
	board.modulate.a = 1.0
	daily = is_daily
	_use_mode(mode_id if mode_id != "" else _menu_mode())
	var classic: bool = mode.id == "classic" and not daily
	if classic:
		ComboExperiment.begin_classic()
	_ab_active = classic and ComboExperiment.is_read_only()
	keeper.configure_time_rewards(classic and not _ab_active)
	keeper.timed_special = classic and ComboExperiment.special_rules == "timed"
	keeper.combo_window = ComboExperiment.window_seconds() if classic else ScoreKeeper.COMBO_WINDOW
	if not ComboExperiment.is_read_only() and Save.mode != mode.id and mode.id in ["classic", "bright", "zen", "levels", "puzzle"]:
		Save.mode = mode.id  # the tutorial and the daily challenge don't become "last mode"
		Save.store()
	wave = 1
	if mode.kind == "levels":
		level_n = pending_level
	_set_orientation(mode.id == "classic")
	if mode.id == "bright":
		# Showing the container schedules its layout. Do not deal or start the clock yet.
		_run_starting = true
		if state == State.PLAYING:
			Yandex.gameplay(false)
		state = State.PAUSED
		board.interactive = false
		board.modulate.a = 0.0  # Retain layout participation without showing the previous board.
		score = 0
		shown_score = 0.0
		time_left = START_TIME
		keeper.reset()
		_update_combo_widget()
		_update_hud()
		_show_panel(null)
		await _wait_run_layout(generation)
		if generation != _run_generation:
			return
		var area := board.size - Vector2.ONE * board.frame_pad * 2.0
		if daily:
			var canonical := BoardLogic.best_dims(Vector2(360, 640), 200)
			_daily_transposed = minf(area.x / canonical.y, area.y / canonical.x) > minf(area.x / canonical.x, area.y / canonical.y)
			_run_dims = Vector2i(canonical.y, canonical.x) if _daily_transposed else canonical
		else:
			_run_dims = BoardLogic.best_dims(area, 200)
		_run_starting = false
		board.modulate.a = 1.0
	_deal_board()
	level_total = logic.gems_left()
	if _ab_active:
		_ab_run = {"run_id": "%s-%s" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()],
			"variant": ComboExperiment.variant if ComboExperiment.variant != "" else "B", "combo_window": keeper.combo_window,
			"special_rules": "timed" if keeper.timed_special else "legacy",
			"seed": ComboExperiment.board_seed if ComboExperiment.fixed_layout else null, "cols": logic.cols, "rows": logic.rows,
			"initial_gems": level_total, "layout_sha256": str(logic.cells).sha256_text()}
		_ab_result_index = 0
		_ab_reported = false
		print("[combo-ab] START ", JSON.stringify(_ab_run), " | saves/leaderboards disabled for this process")
	_set_theme(0 if mode.id == "bright" and not daily else Progress.active_look(), true)
	score = 0
	shown_score = 0.0
	keeper.reset()
	keeper.time_bonuses = mode.kind == "classic"
	play_time = 0.0
	_update_combo_widget()
	cleared = 0
	time_left = START_TIME
	if mode.kind == "levels":
		level_n = pending_level
		time_left = _level_time(level_n)
	strikes_max = 20
	strikes = strikes_max
	hints = 1
	if mode.kind == "puzzle":
		strikes = logic.solution.size() + 1  # just enough to clear it, plus one spare
		strikes_max = strikes
	if mode.kind == "tutorial":
		hints = 0
		time_left = 999.0
	used_continue = false
	used_shuffle = false
	paid_crystals = 0
	paid_xp = 0
	strikes_done = 0
	best_strike = {}
	board.clear_fx()
	board.refresh()
	board.deal_in()
	ambient.pulse(BRASS, 0.6)
	Sfx.play("start")
	_resume_play()
	if mode.kind == "levels" and BoardLogic.bright_level(level_n).boss:
		_banner(L.t("boss"), 0, 0.0, Color("#ff9ed2"), L.t("rule_" + str(BoardLogic.bright_level(level_n).rule)))
	elif mode.kind == "tutorial":
		_tutorial_step(0)


## Wait for actual, stable container dimensions, including Android's portrait rotation.
## A cancelled start never resumes or replaces a newer game's board.
func _wait_run_layout(generation: int) -> void:
	var previous := Vector4.ZERO
	var stable := 0
	while generation == _run_generation:
		await get_tree().process_frame
		var viewport_size := get_viewport_rect().size
		var area := board.size - Vector2.ONE * board.frame_pad * 2.0
		var current := Vector4(viewport_size.x, viewport_size.y, area.x, area.y)
		var portrait_ready := not OS.has_feature("android") or viewport_size.y >= viewport_size.x
		if board.is_visible_in_tree() and area.x >= 50.0 and area.y >= 50.0 and portrait_ready:
			stable = stable + 1 if current.is_equal_approx(previous) else 0
			if stable >= 2:
				return
		else:
			stable = 0
		previous = current


## Mode rules retain their skin discriminator; presentation is resolved separately.
func _use_mode(id: String) -> void:
	_reset_bonus_feedback()
	board.reset_run_surface()
	match id:
		"bright":
			mode = BoardLogic.BRIGHT
		"levels":
			mode = BoardLogic.LEVELS
		"zen":
			mode = BoardLogic.ZEN
		"puzzle":
			mode = BoardLogic.PUZZLE
		"tutorial":
			mode = BoardLogic.TUTORIAL
		_:
			mode = BoardLogic.CLASSIC
	keeper.classic_bonus_combos = mode.id == "classic" and not daily
	visual_profile = "classic_run" if mode.id in ["bright", "tutorial"] and not Progress.COSMETICS_ENABLED else mode.skin
	tut_label.visible = false
	tut_hand.visible = false
	board.skin = mode.skin
	board.visual_profile = visual_profile
	board.zoom_enabled = mode.skin == "classic" and _is_touch_device()
	board.reset_zoom()
	ambient.set_skin("classic" if visual_profile == "classic_run" else visual_profile)
	ambient.reset_velvet_palette()  # A restart cancels the old dye before waiting for layout.
	Sfx.set_skin(mode.skin)
	Sfx.update_music()
	if hud_sets.has(mode.skin):
		_apply_hud(mode.skin)
		_style_run_hud(mode.id in ["bright", "tutorial"])
		_update_combo_widget()
	_update_hud()
	if is_inside_tree() and margin:
		_on_viewport_resized.call_deferred()


## Lay out a board for the current mode. The daily board uses the mode's fixed shape and a
## date seed (plus the wave number), so everyone on the same kind of device gets the same one.
func _deal_board() -> void:
	if mode.kind == "tutorial":
		var tut := PackedInt32Array()
		for ch in "1.1.2" + "....." + "3.3.2" + "....." + "4..4.":
			tut.append(-1 if ch == "." else int(ch) - 1)
		logic.load_cells(5, 5, tut)
		return
	if mode.skin == "bright":
		# bright: the board for this level, dealt until it opens with the level's number of moves;
		# map levels and the daily board use a fixed seed and shape, so everyone gets the same one
		var lvn := _level()
		var lv := BoardLogic.bright_level(lvn)
		if mode.kind == "puzzle":
			lv = BoardLogic.puzzle_config(puzzle_n)
		if mode.kind == "run":
			# the run plays like classic: one big board for the whole clock, a touch of jokers and boxes
			lv = {"slots": 200, "kinds": 6, "per_kind": 28, "min_moves": 4, "max_moves": 999, "tries": 30,
				"jokers": 0.1, "boxes": 5, "chains": 3, "boss": false, "goal_kind": -1, "ice": 3, "bombs": 2,
				"bomb_moves": 12, "chameleons": 2}
			if not RUN_HAZARDS_ENABLED:
				lv.ice = 0
				lv.bombs = 0
		elif mode.kind == "zen":
			lv.ice = mini(wave, 4) if wave >= 2 else 0
			lv.chameleons = mini(wave - 2, 3) if wave >= 3 else 0
			lv.bombs = 1 if wave >= 4 else 0
			lv.bomb_moves = 10
		var r := rng
		var area := _board_area()
		if daily or mode.kind == "levels" or mode.kind == "puzzle":
			r = RandomNumberGenerator.new()
			if mode.kind == "levels":
				r.seed = hash("bizarre-level-%d" % lvn)
			elif mode.kind == "puzzle":
				r.seed = hash("bizarre-puzzle-%d" % puzzle_n)
			else:
				r.seed = hash("bizarre-gems-%s-%s-%d" % [_today(), mode.id, wave])
			area = Vector2(360, 640)
		var d := _run_dims
		if mode.id != "bright" or daily or d == Vector2i.ZERO:
			d = BoardLogic.best_dims(area, lv.slots)
		logic.setup_tuned(d.x, d.y, r, mode.shining, lv.kinds, lv.per_kind, lv.min_moves, lv.max_moves, lv.tries, true,
			lv.jokers, lv.boxes)
		if int(lv.get("chains", 0)) > 0:
			logic.add_chains(r, int(lv.chains))
		if int(lv.get("ice", 0)) > 0:
			logic.add_ice(r, int(lv.ice))
		if int(lv.get("bombs", 0)) > 0 and mode.kind != "puzzle":
			logic.add_bombs(r, int(lv.bombs), int(lv.get("bomb_moves", 10)))
		if int(lv.get("chameleons", 0)) > 0:
			logic.add_chameleons(r, int(lv.chameleons))
		if mode.id == "bright" and daily and _daily_transposed:
			logic.transpose()  # After seeded generation, exactly as for the first board.
		board_kinds = int(lv.kinds)
		goal_kind = int(lv.get("goal_kind", -1)) if mode.kind == "levels" else -1
		return
	if daily:
		var r := RandomNumberGenerator.new()
		r.seed = hash("bizarre-gems-%s-%s-%d" % [_today(), mode.id, wave])
		logic.setup(mode.cols, mode.rows, r, mode.shining, mode.kinds, mode.per_kind)
		if mode.id == "classic" and _is_touch_device() and not OS.has_feature("android"):
			logic.transpose()  # the same daily board, upright in mobile browsers
	else:
		var d := _dims()
		if _ab_active and ComboExperiment.fixed_layout:
			var fixed_rng := RandomNumberGenerator.new()
			fixed_rng.seed = ComboExperiment.board_seed
			logic.setup(d.x, d.y, fixed_rng, mode.shining, mode.kinds, mode.per_kind)
		else:
			logic.setup(d.x, d.y, rng, mode.shining, mode.kinds, mode.per_kind)


## A board ran out of moves: deal the next one with a time bonus, the game goes on.
func _next_wave(at: Vector2i, palette_already_changed := false) -> void:
	var full_clear := logic.gems_left() == 0
	var bonus_t := WAVE_TIME + (CLEAR_TIME if full_clear else 0.0)
	if mode.kind == "run":
		bonus_t = 10.0  # every new run board, stuck or cleared, adds 10 s; a full clear also scores
	if mode.kind == "zen":
		bonus_t = 0.0
		var nl := BoardLogic.bright_level(wave + 1)
		var add := int(round(nl.per_kind * nl.kinds * 0.33))
		strikes += add
		strikes_max = maxi(strikes_max, strikes)
		_flash_delta("+%d" % add, false, "steps")
		Progress.report("zen_boards")
	if full_clear:
		board.play_clear_wave()
		Sfx.play("clear")
		Sfx.voice("clear")
	elif mode.kind == "zen" or mode.kind == "run":
		Sfx.voice("levelup")
		Progress.report("clear_boards")
	var bonus_p := CLEAR_POINTS if full_clear else 0
	if full_clear and mode.kind == "run":
		bonus_p = 100 + 50 * (wave - 1)  # clearing a whole run board is the big score
	time_left += bonus_t
	if bonus_p > 0:
		keeper.score += bonus_p
		score = keeper.score
	wave += 1
	dealing = true
	board.interactive = false
	var title := L.t("clear_board" if full_clear else "new_board")
	if mode.skin == "bright":
		title = L.t("level_up", {"n": wave}) if mode.kind == "zen" else title
	var sub := ""
	_banner(title, bonus_p, bonus_t, BRASS_LIGHT, sub)
	if bonus_t > 0.0:
		_flash_delta("+%d" % int(bonus_t), false)
	Sfx.play("precise")
	board.play_burst(at, 50)
	board.play_confetti(70)
	if not palette_already_changed:
		_set_theme(_next_look())
	var tw := create_tween()
	tw.tween_interval(1.2 if full_clear else 0.7)
	var generation := _run_generation
	tw.tween_callback(func():
		if generation != _run_generation:
			return
		_deal_board()
		board.clear_fx()
		board.refresh()
		board.deal_in()
		dealing = false
		board.interactive = state == State.PLAYING)


## The look after the current one: the six base looks in turn; a special look (seasonal or
## gold) is only ever the starting one.
func _next_look() -> int:
	if mode.id == "bright" and not daily:
		return (theme_i + 1) % 6 if theme_i < 6 else 0
	if not Progress.COSMETICS_ENABLED:
		return Progress.BASE_LOOK
	return (theme_i + 1) % 6 if theme_i < 6 else 0


## Switch the background to palette i (the gradient fades over); the tiles keep the chosen pack.
func _set_theme(i: int, instant := false) -> void:
	if mode.skin != "bright":
		return  # the classic look keeps its colours
	var run_palette: bool = mode.id == "bright" and not daily
	theme_i = posmod(i, THEMES.size()) if run_palette or Progress.COSMETICS_ENABLED else Progress.BASE_LOOK
	var t: Dictionary = THEMES[theme_i]
	if mode.kind == "levels":
		t = CHAPTER_THEMES[BoardLogic.chapter_of(level_n) % CHAPTER_THEMES.size()]  # each chapter keeps its own sky
	board.palette = Progress.active_look()  # Presentation policy never changes mode.skin or the saved choice.
	if run_palette:
		var index := theme_i % RUN_FABRICS.size()
		var fabric: Color = RUN_FABRICS[index]
		var luminance := fabric.r*0.2126 + fabric.g*0.7152 + fabric.b*0.0722
		var surface := Color(fabric.r,fabric.g,fabric.b,0.55)
		if index != 0:
			surface = Color(fabric.r*RUN_SURFACE_LUMA/luminance,fabric.g*RUN_SURFACE_LUMA/luminance,fabric.b*RUN_SURFACE_LUMA/luminance,0.55)
		var from_surface: Color = board._frame.bg_color
		var lights := {"pool_a":RUN_LIGHTS[0],"pool_b":RUN_LIGHTS[1],"pool_c":RUN_LIGHTS[2],
			"tint_top":Color(0,0,0,0),"tint_bottom":Color(0,0,0,0)}
		if index != 0:
			lights.pool_a = fabric.lightened(0.15)
			lights.pool_b = fabric.lightened(0.08)
			lights.pool_c = fabric.lightened(0.22)
		ambient.fade_palette(t.top,t.bottom,0.0 if instant else RUN_PALETTE_SECONDS,true,
			{"fabric":fabric,"strength":0.0 if index == 0 else 1.0,"lights":lights},
			func(blend: float): board.set_run_surface(from_surface.lerp(surface,blend)))
		if not instant:
			ambient.palette_burst(fabric.lightened(0.65))
			board.shake(0.10)
	else:
		ambient.fade_palette(t.top,t.bottom,0.01 if instant else 0.9)
	if not instant and not run_palette:
		board.flash(Color.WHITE, 0.35)
		board.glow(1.0)


## Android: the app is upright, but the classic board is wide, so the screen turns
## sideways while a classic game is on and back upright for the menus and bright mode.
func _set_orientation(landscape: bool) -> void:
	if not OS.has_feature("android"):
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE if landscape
		else DisplayServer.SCREEN_SENSOR_PORTRAIT)


## Bright mode: the clock runs faster on every level (+12% per level, at most x2.2).
func _time_speed() -> float:
	return 1.0  # the clock runs at normal speed everywhere now


## Board level: the map level, or the current board number in runs.
func _level() -> int:
	if mode.kind == "levels":
		return level_n
	if mode.kind == "puzzle":
		return puzzle_n
	return wave


## Seconds for a map level: a little more than one per gem.
func _level_time(n: int) -> float:
	var lv := BoardLogic.bright_level(n)
	return (20.0 + lv.kinds * lv.per_kind * 1.1) * (1.4 if lv.boss else 1.0)


## Start map level n.
func start_level(n: int) -> void:
	pending_level = n
	start_game("levels")


## A map level is over: score it in stars by the share of gems knocked out.
func _end_level() -> void:
	if state == State.OVER:
		return
	state = State.OVER
	board.interactive = false
	Yandex.gameplay(false)
	var left := logic.gems_left()
	var share := 1.0 - float(left) / maxf(1.0, level_total)
	var got := Progress.stars_for_share(share)
	var goal_failed := goal_kind >= 0
	if goal_failed:
		got = 0
	var gained := Progress.record_level(level_n, got)
	last_earned = gained * Progress.STAR_CRYSTALS
	if BoardLogic.bright_level(level_n).boss and gained > 0:
		Progress.crystals += gained * Progress.STAR_CRYSTALS * 2  # bosses pay triple
		last_earned *= 3
		Progress.flush()
	_pay_xp(10 + got * 10)
	Progress.report("games_levels")
	Progress.report("play_secs", int(play_time))
	Progress.add_local_score("stars", Progress.total_stars())
	if Yandex.is_authorized():
		Yandex.submit_score(Progress.total_stars(), "stars")
	ui.level_title.text = L.t("level_n", {"n": level_n})
	ui.level_result.text = L.t("goal_failed") if goal_failed else L.t("level_passed" if got > 0 else "level_failed")
	ui.level_line.text = L.t("level_share", {"p": int(round(share * 100))}) + ("  ·  +%d" % (gained * Progress.STAR_CRYSTALS) if gained > 0 else "")
	ui.level_next.visible = got > 0
	ui.level_stars[0].get_parent().visible = true
	ui.level_double.visible = last_earned > 0
	ui.level_double.text = L.t("double_ad", {"n": last_earned})
	ui.level_continue.visible = left > 0 and not used_continue
	ui.level_continue.text = L.t("continue_ad") if time_left <= 0.0 else L.t("shuffle_ad")
	for i in 3:
		var st: TextureRect = ui.level_stars[i]
		st.modulate = Color(0.25, 0.3, 0.5, 1)
		st.scale = Vector2.ONE
	_show_panel(level_panel)
	for i in got:
		var st: TextureRect = ui.level_stars[i]
		var tw := create_tween()
		tw.tween_interval(0.35 + i * 0.35)
		tw.tween_callback(func():
			st.modulate = BRASS
			st.pivot_offset = st.size / 2
			st.scale = Vector2.ONE * 1.5
			Sfx.play("star", 1.0 + i * 0.12))
		tw.tween_property(st, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("level" if got > 0 else "over")


# ================= puzzle, tutorial =================

func start_puzzle(n: int) -> void:
	puzzle_n = n
	start_game("puzzle")


func _end_puzzle() -> void:
	if state == State.OVER:
		return
	state = State.OVER
	board.interactive = false
	var solved := logic.gems_left() == 0
	last_earned = 0
	if solved:
		if puzzle_n > Progress.puzzles:
			last_earned = 10
			Progress.add_crystals(10)
		Progress.solved_puzzle(puzzle_n)
		_pay_xp(25)
	Progress.report("games_puzzle")
	ui.level_double.visible = last_earned > 0
	ui.level_double.text = L.t("double_ad", {"n": last_earned})
	ui.level_continue.visible = false
	ui.level_title.text = L.t("puzzle_n", {"n": puzzle_n})
	ui.level_result.text = L.t("puzzle_solved" if solved else "puzzle_failed")
	ui.level_line.text = L.t("puzzle_line", {"n": logic.solution.size()})
	ui.level_next.visible = solved
	ui.level_stars[0].get_parent().visible = false  # puzzles are solved or not, no stars
	_show_panel(level_panel)
	Sfx.play("level" if solved else "over")


## Guided strikes of the tutorial board, then one free strike.
const TUT_MOVES := [Vector2i(1, 0), Vector2i(1, 2), Vector2i(4, 1)]


func _tutorial_target() -> Vector2i:
	return TUT_MOVES[tut_step] if tut_step < TUT_MOVES.size() else Vector2i(-1, -1)


func _tutorial_step(i: int) -> void:
	tut_step = i
	var keys := ["tut1", "tut2", "tut3", "tut4"]
	tut_label.text = L.t(keys[mini(i, 3)])
	tut_label.set_meta("instruction", tut_label.text)
	tut_label.visible = true
	var target := _tutorial_target()
	tut_hand.visible = target.x >= 0
	if target.x >= 0:
		board.show_hint(target)
		_place_hand.call_deferred(target)


## The hand follows its slot every frame (see _process), so it stays put while the board lays out.
func _place_hand(target: Vector2i) -> void:
	tut_hand.set_meta("target", target)


func _update_hand() -> void:
	if not tut_hand.visible or not tut_hand.has_meta("target"):
		return
	var target: Vector2i = tut_hand.get_meta("target")
	var pos := board.global_position + board.slot_center(target) - global_position
	var side := minf(board.cell * 0.42, 56.0)
	tut_hand.size = Vector2.ONE * side
	# The reused icon's fingertip is at its top centre; leave the target visible.
	tut_hand.position = pos + Vector2(-side * 0.5, 1 + 2 * sin(Time.get_ticks_msec() / 1000.0 * 7.0))


func _tutorial_after_strike() -> void:
	if logic.gems_left() == 0:
		tut_label.text = L.t("tut_done")
		tut_hand.visible = false
		Progress.finish_tutorial()
		Sfx.play("level")
		var tw := create_tween()
		tw.tween_interval(1.6)
		tw.tween_callback(func():
			tut_label.visible = false
			state = State.MENU
			_show_panel(mode_panel))
	elif tut_step < 3:
		_tutorial_step(tut_step + 1)


func _today() -> String:
	return Time.get_date_string_from_system(true)


func _resume_play() -> void:
	if _ab_active and state == State.OVER:
		_ab_reported = false  # A continue/shuffle produces another cumulative result.
	if mode.skin == "bright":
		_set_orientation(false)  # bright modes are played upright on phones
	state = State.PLAYING
	idle = 0.0
	last_tick = -1
	board.interactive = true
	_show_panel(null)
	board.grab_focus()
	Yandex.gameplay(true)
	_update_hud()
	_check_no_moves.call_deferred()


## A board with no strike left: show the end of the game (or deal on) right away, whether it
## got stuck after a strike, a deal, a shuffle or a continue.
func _check_no_moves() -> void:
	if state != State.PLAYING or dealing or logic.has_any_move():
		return
	match mode.kind:
		"levels":
			if logic.has_chameleons() and logic.gems_left() > 1:
				logic.shuffle_remaining(rng)  # chameleons can leave a board with no way out
				board.deal_in()
				_toast(L.t("reshuffled"))
				return
			_end_level()
		"puzzle":
			_end_puzzle()
		"tutorial":
			pass
		"run":
			_next_wave(Vector2i(logic.cols / 2, logic.rows / 2))  # stuck or cleared: a fresh board, the run goes on
		_:
			if mode.waves:
				_next_wave(Vector2i(logic.cols / 2, logic.rows / 2))
			else:
				end_game("stuck")


func pause_game() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	board.interactive = false
	Yandex.gameplay(false)
	_show_panel(pause_panel)


func go_menu() -> void:
	_report_combo_ab("abandoned")
	_reset_bonus_feedback()
	_run_generation += 1
	_run_starting = false
	_run_dims = Vector2i.ZERO
	_daily_transposed = false
	dealing = false
	board.modulate.a = 1.0
	if state == State.PLAYING:
		Yandex.gameplay(false)
	state = State.MENU
	board.interactive = false
	_show_panel(menu_panel)


func end_game(reason: String) -> void:
	if mode.kind == "levels":
		_end_level()
		return
	if mode.kind == "run":
		Progress.report("run_score", score)
	_reset_bonus_feedback()
	state = State.OVER
	end_reason = reason
	board.interactive = false
	Yandex.gameplay(false)
	var is_best := false
	if _ab_active:
		_report_combo_ab(reason)
	elif daily:
		is_best = Save.submit_daily(score, _today())
	else:
		is_best = Save.submit(score, mode.id)
		Progress.add_local_score(mode.board, score)
		if Yandex.is_authorized() and mode.board != "":
			Yandex.submit_score(Save.best_for(mode.id), mode.board)
	Sfx.play("over")
	Haptics.buzz("over")
	var tiers := 0
	last_earned = 0
	if not _ab_active:
		var earned := Progress.crystals_for_score(score) - paid_crystals
		paid_crystals += earned
		var daily_paid := Progress.pay_daily() if daily else 0
		Progress.add_crystals(maxi(earned, 0))
		last_earned = maxi(earned, 0) + daily_paid
		tiers = _pay_xp(10 + mini(score / 50, 40) + (30 if daily_paid > 0 else 0))
		Progress.report("games_" + mode.id)
		Progress.report("max_combo", keeper.best_combo)
		Progress.report("play_secs", int(play_time))
		Progress.flush()
	ui.over_title.text = L.t("stuck" if reason == "stuck" else ("no_strikes" if reason == "strikes" else "times_up"))
	ui.over_score.text = str(score)
	ui.over_best.visible = is_best and score > 0
	ui.over_best.text = L.t("new_daily_best" if daily else "new_best")
	ui.over_line.text = L.t("cleared", {"n": cleared, "w": wave}) + "\n" + L.t("stats", {"combo": keeper.best_combo, "precise": keeper.precise_count})
	if daily:
		ui.over_line.text = L.t("daily") + " · " + L.t("daily_best", {"n": Save.daily_best_for(_today())}) + "\n" + ui.over_line.text
	ui.over_reward.text = L.t("reward_line", {"n": last_earned}) + ("  ·  " + L.t("pass_up") if tiers > 0 else "")
	ui.over_reward.visible = last_earned > 0
	ui.btn_double.visible = last_earned > 0
	ui.btn_double.text = L.t("double_ad", {"n": last_earned})
	_show_best_strike()
	ui.btn_continue.visible = reason == "time" and not used_continue and mode.kind != "zen"
	ui.btn_shuffle.visible = reason == "stuck" and not used_shuffle and logic.gems_left() > 1
	_show_panel(over_panel)
	_update_hud()


func _on_slot(p: Vector2i) -> void:
	if state != State.PLAYING or dealing or not logic.is_empty(p):
		return
	board.ripple(p)
	var gone := logic.matches_from(p)
	if mode.kind == "tutorial" and tut_step < 3 and p != _tutorial_target():
		# Keep feedback in the guidance row so the last pair remains visible on short phones.
		tut_label.text = L.t("tut_wrong") + "\n" + str(tut_label.get_meta("instruction"))
		return
	if mode.kind == "zen":
		strikes -= 1 if not gone.is_empty() else 2  # a miss costs two steps
	elif mode.kind == "puzzle":
		strikes -= 1
	if gone.is_empty():
		if mode.kind == "classic" or mode.kind == "run" or mode.kind == "levels":
			time_left = maxf(0.0, time_left - 1.0)
		board.play_miss(p)
		Sfx.play("miss")
		Haptics.buzz("miss")
		if keeper.miss():
			_combo_break()
		if mode.kind == "classic" or mode.kind == "run" or mode.kind == "levels":
			_flash_delta("−1", true)
		_tick_obstacles(false)
		if time_left <= 0.0:
			end_game("time")
		elif (mode.kind == "zen" or mode.kind == "puzzle") and strikes <= 0:
			if mode.kind == "puzzle":
				_end_puzzle()
			else:
				end_game("strikes")
		_update_hud()
		return
	var kinds: Array[int] = []
	for g in gone:
		kinds.append(logic.kind_at(g))
	var nshine := logic.shining_count(gone)
	var vanish := logic.vanishing(gone)
	var before := logic.cells.duplicate()
	var defused := 0
	for g in gone:
		if logic.bomb_at(g) > 0 and not logic.is_box(g):
			defused += 1
	var extra := logic.remove(gone)
	var thawed := logic.last_thawed.duplicate()
	for q in extra:
		gone.append(q)
		vanish.append(q)
		kinds.append(before[q.y * logic.cols + q.x])
	var n := gone.size()
	var vkinds: Array[int] = []
	for i in gone.size():
		if gone[i] in vanish:
			vkinds.append(kinds[i])
	var res := keeper.hit(n, play_time, nshine, p, vkinds)
	score = keeper.score
	_pop(score_label, 1.3)
	if nshine > 0:
		Sfx.play("bonus")
		board.play_burst(p, 14 * nshine, false)
		ambient.pulse(Color(1.0, 0.84, 0.4), 0.5)
	if n >= 4 and res.event == "":
		board.praise(L.t("praise_great"), p, BRASS_LIGHT)
		Sfx.voice("great")
	if res.tier_up and res.mult >= 3:
		board.praise(L.t("praise_super" if res.mult == 3 else "praise_wow"), p, COMBO_COLORS[res.mult - 1].lightened(0.35), 1.2)
		Sfx.voice("super" if res.mult == 3 else "amazing")
	# Hits still score when a box only cracks; removal counts use the destroyed gems.
	cleared += vanish.size()
	_note_best_strike(p, vanish, vkinds, res)
	if not thawed.is_empty():
		board.play_thaw(thawed)
		Sfx.play("bonus", 1.6, -4.0)
	if defused > 0:
		keeper.score += DEFUSE_POINTS * defused
		score = keeper.score
		board.praise(L.t("defused"), p, Color("#ffcf33"))
		Sfx.play("bonus", 0.8)
	strikes_done += 1
	_tick_obstacles(true)
	if extra.size() > 0:
		keeper.score += extra.size() * 2
		score = keeper.score
		board.praise(L.t("chain"), p, Color("#9fe3ff"))
	if mode.kind == "classic" or mode.kind == "levels":
		time_left += res.time  # the bright run earns time only by clearing a whole board
	idle = 0.0
	var event: String = res.event
	board.play_knock(p, vanish, vkinds, res.points, res.mult, event != "")
	if vanish.size() < gone.size():
		board.shake(0.08)  # a box cracked
	if mode.skin == "bright":
		var semi: int = PENTA[(res.combo - 1) % PENTA.size()]
		Sfx.play("knock%d" % mini(n, 4), pow(2.0, semi / 12.0))
	else:
		Sfx.play("knock%d" % mini(n, 4), 1.0 + mini(res.combo, 12) * 0.025)
	if not _ab_active:
		Progress.report("gems", vanish.size())
		if res.tier_up and res.mult == 4:
			Progress.report("combo4")
	if res.time > 0 and (mode.kind == "classic" or mode.kind == "levels"):
		_flash_delta("+%d" % int(res.time), false)
	if res.tier_up:
		if mode.skin == "bright":
			Sfx.play("combo_up", 1.0, -2.0)
		Haptics.buzz("tier")
		ambient.pulse(BRASS, 0.4)
		board.play_wave(p, 1.0)
		board.shake(0.1)
	if event == "precise":
		if mode.skin == "bright":
			Sfx.play("precise")
			Sfx.voice("incredible")
		Haptics.buzz("precise")
		ambient.pulse(BRASS_LIGHT, 0.8)
		board.play_wave(p, 2.0, true)
		board.play_burst(p, 40)
		board.flash(BRASS_LIGHT, 0.22)
		_banner(L.t("precise"), ScoreKeeper.PRECISE_POINTS, ScoreKeeper.PRECISE_TIME, BRASS_LIGHT)
		if mode.skin == "bright":
			board.play_confetti(50)
		if mode.id != "bright" or daily:
			_set_theme(_next_look())
	elif event == "perfect":
		if mode.skin == "bright":
			Sfx.play("perfect")
			Sfx.voice("perfect")
		Haptics.buzz("perfect")
		ambient.pulse(Color("#ff9ed2"), 1.0)
		board.play_wave(p, 3.0, true)
		board.play_burst(p, 90)
		board.flash(Color.WHITE, 0.4)
		board.shake(0.3)
		_banner(L.t("perfect"), ScoreKeeper.PERFECT_POINTS, ScoreKeeper.PERFECT_TIME, Color("#ff9ed2"))
		if not _ab_active:
			Progress.report("perfects")
		if mode.skin == "bright":
			board.play_confetti(90)
		if mode.id != "bright" or daily:
			_set_theme(_next_look())
	var palette_event: bool = mode.id == "bright" and not daily and (event != "" or res.combo in [30,50])
	if palette_event:
		_set_theme(_next_look())  # A special and a streak threshold on one strike count once.
	_update_combo_widget(res.tier_up)
	_show_bonus_feedback(res)
	if autoplay and (event != "" or res.tier_up):
		print("[autoplay] combo=%d mult=%d event=%s" % [res.combo, res.mult, event])
		if event != "":
			_auto_t = -2.0  # hold still so the banner can be captured
	_update_hud()
	if goal_kind >= 0 and logic.count_kind(goal_kind) == 0:
		goal_kind = -2  # done
		board.praise(L.t("goal_done"), p, Color("#5cc87a"), 1.2)
		Sfx.play("bonus")
	if mode.kind == "tutorial":
		_tutorial_after_strike()
		_update_hud()
		return
	if mode.kind == "puzzle":
		if logic.gems_left() == 0:
			board.play_clear_wave()
			Sfx.play("clear")
			dealing = true
			var tw0 := create_tween()
			tw0.tween_interval(1.2)
			tw0.tween_callback(func(): dealing = false; _end_puzzle())
		elif strikes <= 0 or not logic.has_any_move():
			_end_puzzle()
		_update_hud()
		return
	if mode.kind == "levels" and logic.gems_left() == 0:
		board.play_clear_wave()
		Sfx.play("clear")
		Sfx.voice("clear")
		Progress.report("clear_boards")
		dealing = true
		var tw := create_tween()
		tw.tween_interval(1.3)
		tw.tween_callback(func(): dealing = false; _end_level())
		return
	if not logic.has_any_move():
		if mode.kind == "levels":
			_end_level()
		elif mode.waves:
			_next_wave(p,palette_event)
		else:
			end_game("stuck")
	elif mode.kind == "zen" and strikes <= 0:
		end_game("strikes")


func _process(delta: float) -> void:
	if menu_panel.visible:
		_menu_t += delta
		for i in ui.home_gems.size():
			var g: TextureRect = ui.home_gems[i]
			g.rotation = sin(_menu_t * 1.0 + i * 1.7) * 0.06
			g.scale = Vector2.ONE * (1.0 + 0.06 * sin(_menu_t * 2.0 + i * 2.1))
		var pb: Button = ui.btn_home_play
		pb.pivot_offset = pb.size / 2
		pb.scale = Vector2.ONE * (1.0 + 0.008 * sin(_menu_t * 2.0))
	if absf(score - shown_score) > 0.5:
		shown_score = lerpf(shown_score, score, minf(1.0, delta * 10.0))
	else:
		shown_score = score
	_set_hud_number(score_label, int(round(shown_score)))
	_poll_classic_safe_area(delta)
	_update_hand()
	if state != State.PLAYING:
		return
	if mode.kind == "classic" or mode.kind == "run" or mode.kind == "levels":
		time_left -= delta * _time_speed()
	_stuck_t += delta
	if _stuck_t > 0.5:
		_stuck_t = 0.0
		_check_no_moves()
		if state != State.PLAYING:
			return
	play_time += delta
	if keeper.update(play_time):
		_combo_break()
	_update_bonus_progress()
	if keeper.combo >= 2:
		combo_bar.value = keeper.window_left(play_time) / keeper.combo_window * 100.0
	idle += delta
	if autoplay:
		_auto_t += delta
		if _auto_t > 0.45:
			_auto_t = 0.0
			_auto_move()
	if idle > HINT_AFTER:
		idle = -1000.0  # one hint per quiet spell
		board.show_hint(logic.find_move())
	var secs := int(ceil(time_left))
	if secs <= 10 and secs != last_tick and secs > 0:
		last_tick = secs
		Sfx.play("tick", 1.0, -4.0)
		_pop(time_label, 1.35)
	if time_left <= 0.0:
		time_left = 0.0
		end_game("time")
	_update_hud()


## Debug autoplay: strike the move that knocks out the most gems.
func _auto_move() -> void:
	var best := Vector2i(-1, -1)
	var best_n := 0
	for y in logic.rows:
		for x in logic.cols:
			var q := Vector2i(x, y)
			if logic.is_empty(q):
				var n := logic.matches_from(q).size()
				if n > best_n:
					best_n = n
					best = q
	if best.x >= 0:
		_on_slot(best)


# ================= hint =================

## Show the next strike of the board's solution (or, off the solution path, the strike that
## takes the most gems). One free per game or level; more for a rewarded ad on Yandex.
func _use_hint() -> void:
	if state != State.PLAYING or dealing:
		return
	if hints > 0:
		hints -= 1
		_show_hint()
		_update_hud()
		return
	if Progress.use_hint_token():
		_show_hint()
		_update_hud()
		return
	Yandex.show_rewarded(func(ok: bool):
		if ok:
			_show_hint()
		else:
			_toast(L.t("ad_failed")))


func _show_hint() -> void:
	var p := logic.next_solution_move()
	if p.x < 0:
		var best := 0
		for y in logic.rows:
			for x in logic.cols:
				var q := Vector2i(x, y)
				if logic.is_empty(q):
					var n := logic.matches_from(q).size()
					if n > best:
						best = n
						p = q
	if p.x >= 0:
		board.show_hint(p)
		Sfx.play("hint")


## Pass XP for this game up to `total` (a continued game only pays what it adds). Returns
## how many pass tiers were reached.
func _pay_xp(total: int) -> int:
	var add := maxi(0, total - paid_xp)
	paid_xp = maxi(paid_xp, total)
	return Progress.add_xp(add)


## After every strike (and miss): bombs tick down and may go off; every few hits the
## chameleons change colour.
func _tick_obstacles(hit: bool) -> void:
	if mode.skin != "bright":
		return
	for q in logic.tick_bombs():
		board.play_blast(q)
		Sfx.play("over", 1.5, -2.0)
		Haptics.buzz("perfect")
		board.praise(L.t("boom"), q, Color("#ff5d3a"), 1.2)
		if mode.kind == "zen":
			strikes = maxi(0, strikes - BOMB_STEPS)
			_flash_delta("−%d" % BOMB_STEPS, true, "steps")
		elif mode.kind != "puzzle":
			time_left = maxf(0.0, time_left - BOMB_TIME)
			_flash_delta("−%d" % int(BOMB_TIME), true)
	if hit and strikes_done % CHAM_EVERY == 0 and logic.has_chameleons():
		var changed := logic.shift_chameleons(board_kinds)
		for q in changed:
			board.play_wave(q, 0.6, true)
		if not changed.is_empty():
			Sfx.play("hint", 1.3, -6.0)
	board.refresh()


## Keep the game's best strike (the cross part of it) for the result screen.
func _note_best_strike(p: Vector2i, gone: Array[Vector2i], kinds: Array[int], res: Dictionary) -> void:
	if not best_strike.is_empty() and int(res.points) <= int(best_strike.points):
		return
	var parts := []
	for i in gone.size():
		var d := gone[i] - p
		if (d.x == 0) != (d.y == 0):
			parts.append([d, kinds[i]])
	best_strike = {"points": res.points, "n": gone.size(), "mult": res.mult, "parts": parts}


func _show_best_strike() -> void:
	ui.best_box.visible = not best_strike.is_empty() and not best_strike.parts.is_empty()
	if ui.best_box.visible:
		ui.best_caption.text = L.t("best_strike", {"n": best_strike.n, "p": best_strike.points})
		(ui.best_view as StrikeReplay).show_strike(best_strike, func(k: int) -> Texture2D: return board._tex(k), f_num)


## Rewarded video: the crystals of the last result once more.
func _on_double() -> void:
	Sfx.play("click")
	Yandex.show_rewarded(func(ok: bool):
		if not ok:
			_toast(L.t("ad_failed"))
			return
		Progress.add_crystals(last_earned)
		_toast(L.t("doubled", {"n": last_earned}))
		Sfx.play("star")
		last_earned = 0
		ui.btn_double.visible = false
		ui.level_double.visible = false
		_refresh_menu_bests())


## Rewarded video on a lost level: 15 more seconds, or a reshuffle when no move is left.
func _on_level_continue() -> void:
	Sfx.play("click")
	Yandex.show_rewarded(func(ok: bool):
		if not ok:
			_toast(L.t("ad_failed"))
			return
		used_continue = true
		if time_left <= 0.0:
			time_left = CONTINUE_TIME
			_flash_delta("+15", false)
		if not logic.has_any_move():
			logic.shuffle_remaining(rng)
			board.deal_in()
		Sfx.play("bonus")
		_resume_play())


func _ask_leave() -> void:
	Sfx.play("click")
	_show_panel(confirm_panel)


func _on_continue() -> void:
	Sfx.play("click")
	Yandex.show_rewarded(func(ok: bool):
		if not ok:
			_toast(L.t("ad_failed"))
			return
		used_continue = true
		time_left = CONTINUE_TIME
		_flash_delta("+15", false)
		Sfx.play("bonus")
		_resume_play())


func _on_shuffle() -> void:
	Sfx.play("click")
	Yandex.show_rewarded(func(ok: bool):
		if not ok:
			_toast(L.t("ad_failed"))
			return
		used_shuffle = true
		logic.shuffle_remaining(rng)
		board.clear_fx()
		board.deal_in()
		if logic.has_any_move():
			_resume_play()
		else:
			end_game("stuck"))


func _on_again() -> void:
	Sfx.play("click")
	ui.btn_again.disabled = true
	Yandex.show_fullscreen(func(_shown: bool):
		ui.btn_again.disabled = false
		start_game(mode.id, daily))


func _on_platform_pause() -> void:
	Sfx.set_platform_paused(true)
	pause_game()


func _on_platform_resume() -> void:
	Sfx.set_platform_paused(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not OS.has_feature("web"):
		pause_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


## Android back button: pause, close the open panel, and only leave the app from the menu.
func _on_back() -> void:
	if settings_panel.visible:
		_close_settings()
	elif confirm_panel.visible:
		_show_panel(pause_panel)
	elif map_panel.visible:
		_show_panel(mode_panel)
	elif rules_panel.visible or mode_panel.visible or tasks_panel.visible or collection_panel.visible or gift_panel.visible or ach_panel.visible or pass_panel.visible or stats_panel.visible:
		_show_panel(menu_panel)
	elif level_panel.visible:
		_open_map()
	elif leaders_panel.visible:
		_show_panel(leaders_return)
	elif state == State.PLAYING:
		pause_game()
	elif state == State.PAUSED:
		_ask_leave()
	elif state == State.OVER:
		go_menu()
	else:
		get_tree().quit()


## Drag-to-scroll for the menu lists: a press that moves more than a few pixels scrolls the
## list under it and is kept from the button it started on.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag = null
			for sc in drag_scrolls:
				if sc.is_visible_in_tree() and sc.get_global_rect().has_point(event.position):
					_drag = sc
			_drag_last = event.position
			_drag_moved = 0.0
		else:
			if _drag and _drag_moved > 14.0:
				get_viewport().set_input_as_handled()
			_drag = null
	elif event is InputEventMouseMotion and _drag and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var dy: float = event.position.y - _drag_last.y
		_drag_last = event.position
		_drag_moved += absf(dy)
		if _drag_moved > 14.0:
			_drag.scroll_vertical -= int(round(dy))
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if OS.is_debug_build() and event.keycode in [KEY_F6, KEY_F7] and state in [State.MENU, State.OVER]:
			debug_start_combo_ab("A" if event.keycode == KEY_F6 else "B", ComboExperiment.board_seed)
			get_viewport().set_input_as_handled()
			return
		if OS.is_debug_build() and event.keycode == KEY_N and state in [State.MENU, State.OVER]:
			debug_start_special_combo("timed", ComboExperiment.board_seed)
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			if state == State.PLAYING:
				pause_game()
			elif state == State.PAUSED:
				_resume_play()
			get_viewport().set_input_as_handled()


## F6/F7 and MCP share this entry point. Never switch rules during a live round.
func debug_start_combo_ab(variant: String, fixed_seed := 42) -> bool:
	if not OS.is_debug_build() or state not in [State.MENU, State.OVER]:
		return false
	if not ComboExperiment.select(variant, fixed_seed):
		return false
	start_game("classic")
	return true


## Special-mechanic comparison at the same ordinary 3.5-second window.
func debug_start_special_combo(rules: String, fixed_seed := 42) -> bool:
	if not OS.is_debug_build() or state not in [State.MENU, State.OVER]:
		return false
	if not ComboExperiment.select_special(rules, fixed_seed):
		return false
	start_game("classic")
	return true


func _report_combo_ab(reason: String) -> void:
	if not _ab_active or _ab_reported:
		return
	_ab_reported = true
	_ab_result_index += 1
	last_combo_report = _ab_run.duplicate(true)
	last_combo_report.merge({"result_index": _ab_result_index, "score": score,
		"destroyed_gems": cleared, "max_streak": keeper.best_combo,
		"combo_breaks": keeper.combo_breaks, "hits_at_x4": keeper.hits_at_x4,
		"precise_events": keeper.precise_events, "perfect_events": keeper.perfect_events,
		"special_bonus_points": keeper.special_bonus_points, "special_bonus_time": keeper.special_bonus_time,
		"end_reason": reason, "time_left": maxf(0.0, time_left), "play_time": play_time,
		"used_continue": used_continue, "used_shuffle": used_shuffle})
	ComboExperiment.append_report(last_combo_report)


func _exit_tree() -> void:
	_report_combo_ab("quit")


# ================= leaderboard =================

func _open_leaders(from: Control) -> void:
	leaders_board = "stars" if mode.kind == "levels" else (mode.board if mode.board != "" else "score")
	Sfx.play("click")
	leaders_return = from
	_show_panel(leaders_panel)
	_refresh_leaders()


func _build_leader_tabs(v: VBoxContainer) -> void:
	var tabs := HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for k in ["score", "score_bright", "score_zen", "stars"]:
		var board_name: String = k
		var b := _button("", "", false, func(): leaders_board = board_name; Sfx.play("click"); _refresh_leaders())
		b.add_theme_font_size_override("font_size", 15)
		ui["lb_tab_" + k] = b
		tabs.add_child(b)
	v.add_child(tabs)
	v.move_child(tabs, 1)


func _refresh_leaders() -> void:
	for k in ["score", "score_bright", "score_zen", "stars"]:
		(ui["lb_tab_" + k] as Button).theme_type_variation = "PrimaryButton" if k == leaders_board else ""
	var list: VBoxContainer = ui.leaders_list
	for c in list.get_children():
		c.queue_free()
	ui.btn_login.visible = false
	if not Yandex.available:
		# Android / no Yandex: this device's own best results
		var top := Progress.local_top(leaders_board)
		ui.leaders_status.text = L.t("leaders_local") if not top.is_empty() else L.t("leaders_local_empty")
		ui.leaders_status.visible = true
		for i in top.size():
			list.add_child(_leader_row({"rank": i + 1, "score": top[i].score, "name": str(top[i].date), "me": i == 0}))
		_fit_panels.call_deferred()
		return
	ui.leaders_status.text = L.t("leaders_loading")
	ui.leaders_status.visible = true
	Yandex.fetch_leaderboard(func(res: Dictionary):
		var entries: Array = res.get("entries", [])
		ui.leaders_status.visible = entries.is_empty()
		ui.leaders_status.text = L.t("leaders_empty")
		ui.btn_login.visible = not Yandex.is_authorized()
		for e in entries:
			list.add_child(_leader_row(e))
		_fit_panels.call_deferred(), leaders_board)


func _leader_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var me := bool(e.get("me", false))
	var col := BRASS_LIGHT if me else CREAM
	var rank := _label(str(int(e.get("rank", 0))), f_num, 20, MUTED)
	rank.custom_minimum_size.x = 44
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var name_s: String = str(e.get("name", ""))
	if name_s.is_empty():
		name_s = L.t("anon")
	if me:
		name_s += " · " + L.t("you")
	var nm := _label(name_s, f_bold if me else f_body, 20, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var sc := _label(str(int(e.get("score", 0))), f_num, 20, col)
	row.add_child(rank)
	row.add_child(nm)
	row.add_child(sc)
	return row


func _on_login() -> void:
	Yandex.open_auth(func(ok: bool):
		if ok:
			Yandex.submit_score(Save.best_for(mode.id), mode.board)
			_refresh_leaders())


# ================= UI building =================

func _load_fonts() -> void:
	var ts := TextServerManager.get_primary_interface()
	var wght := ts.name_to_tag("wght")
	f_display = load("res://assets/fonts/RussoOne-Regular.ttf")
	var manrope: FontFile = load("res://assets/fonts/Manrope-Variable.ttf")
	var mono: FontFile = load("res://assets/fonts/JetBrainsMono-Variable.ttf")
	f_body = _variation(manrope, wght, 560)
	f_bold = _variation(manrope, wght, 800)
	f_num = _variation(mono, wght, 600)


func _variation(base: FontFile, tag: int, weight: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {tag: weight}
	return v


func _box(bg: Color, border: Color, bw := 2, radius := 10, pad := Vector4(16, 10, 16, 10)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = f_body
	th.default_font_size = 21
	th.set_color("font_color", "Label", CREAM)

	th.set_stylebox("normal", "Button", _box(Color(0, 0, 0, 0.25), Color(BRASS, 0.5)))
	th.set_stylebox("hover", "Button", _box(Color(BRASS, 0.12), BRASS))
	th.set_stylebox("pressed", "Button", _box(Color(BRASS, 0.22), BRASS))
	th.set_stylebox("disabled", "Button", _box(Color(0, 0, 0, 0.2), Color(BRASS, 0.2)))
	th.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BRASS_LIGHT, 3))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		th.set_color(k, "Button", CREAM)
	th.set_color("font_disabled_color", "Button", Color(CREAM, 0.4))
	th.set_font("font", "Button", f_bold)
	th.set_constant("icon_max_width", "Button", 26)
	th.set_constant("h_separation", "Button", 10)

	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", _box(BRASS, BRASS, 2, 10, Vector4(26, 13, 26, 13)))
	th.set_stylebox("hover", "PrimaryButton", _box(Color("#e2bd68"), Color("#e2bd68"), 2, 10, Vector4(26, 13, 26, 13)))
	th.set_stylebox("pressed", "PrimaryButton", _box(Color("#b8923f"), Color("#b8923f"), 2, 10, Vector4(26, 13, 26, 13)))
	th.set_stylebox("disabled", "PrimaryButton", _box(Color(BRASS, 0.4), Color(BRASS, 0.4), 2, 10, Vector4(26, 13, 26, 13)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		th.set_color(k, "PrimaryButton", Color("#1b1408"))

	th.set_type_variation("IconButton", "Button")
	for st in ["normal", "hover", "pressed", "disabled"]:
		var b: StyleBoxFlat = th.get_stylebox(st, "Button").duplicate()
		b.content_margin_left = 10
		b.content_margin_right = 10
		th.set_stylebox(st, "IconButton", b)

	panel_style = _box(PANEL, Color(BRASS, 0.45), 2, 16, Vector4(30, 26, 30, 26))
	panel_style_compact = _box(PANEL, Color(BRASS, 0.45), 2, 14, Vector4(18, 16, 18, 16))
	th.set_stylebox("panel", "PanelContainer", panel_style)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(k, "CheckButton", CREAM)
	th.set_font("font", "CheckButton", f_bold)
	th.set_constant("icon_max_width", "CheckButton", 0)
	var on: Texture2D = load("res://assets/ui/switch_on.png")
	var off: Texture2D = load("res://assets/ui/switch_off.png")
	for k in ["checked", "checked_mirrored", "checked_disabled", "checked_disabled_mirrored"]:
		th.set_icon(k, "CheckButton", on)
	for k in ["unchecked", "unchecked_mirrored", "unchecked_disabled", "unchecked_disabled_mirrored"]:
		th.set_icon(k, "CheckButton", off)
	var knob: Texture2D = load("res://assets/ui/knob.png")
	for k in ["grabber", "grabber_highlight", "grabber_disabled"]:
		th.set_icon(k, "HSlider", knob)
	th.set_stylebox("focus", "CheckButton", _box(Color(0, 0, 0, 0), BRASS_LIGHT, 2, 8, Vector4(6, 4, 6, 4)))
	th.set_stylebox("slider", "HSlider", _box(Color(BRASS, 0.2), Color(0, 0, 0, 0), 0, 4, Vector4(0, 4, 0, 4)))
	th.set_stylebox("grabber_area", "HSlider", _box(BRASS, BRASS, 0, 4, Vector4(0, 4, 0, 4)))
	th.set_stylebox("grabber_area_highlight", "HSlider", _box(BRASS_LIGHT, BRASS_LIGHT, 0, 4, Vector4(0, 4, 0, 4)))
	th.set_stylebox("background", "ProgressBar", _box(Color(BRASS, 0.15), Color(0, 0, 0, 0), 0, 3, Vector4.ZERO))
	bar_fill = _box(BRASS, BRASS, 0, 3, Vector4.ZERO)
	bar_fill_low = _box(DANGER, DANGER, 0, 3, Vector4.ZERO)
	th.set_stylebox("fill", "ProgressBar", bar_fill)
	return th


func _label(text: String, font: Font = null, size := 0, color := CREAM) -> Label:
	var l := Label.new()
	l.text = text
	if font:
		l.add_theme_font_override("font", font)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _caption(text: String) -> Label:
	var l := _label(text, f_bold, 13, MUTED)
	l.uppercase = true
	return l


func _para(text: String) -> Label:
	var l := _label(text, f_body, 20)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, icon_name := "", primary := false, cb := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = ICONS[icon_name]
	if primary:
		b.theme_type_variation = "PrimaryButton"
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _icon_button(icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.icon = ICONS[icon_name]
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = Vector2(52, 52)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(cb)
	return b


func _build() -> void:
	ambient = Ambient.new()
	ambient.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ambient)

	margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var col := VBoxContainer.new()
	board_column = col
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# ---- HUD: pause | big score with best under it | settings, then the timer bar ----
	hud = HBoxContainer.new()
	hud.add_theme_constant_override("separation", 10)
	col.add_child(hud)
	btn_pause = _icon_button("pause", func(): Sfx.play("click"); pause_game())
	btn_pause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud.add_child(btn_pause)
	btn_restart = _icon_button("restart", func(): Sfx.play("click"); start_game(mode.id, daily))
	btn_restart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud.add_child(btn_restart)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	score_label = _label("0", f_display, 54, CREAM)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_constant_override("outline_size", 10)
	score_label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.2, 0.6))
	ui.run_score_caption = _caption("")
	ui.run_score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.run_score_caption.visible = false
	mid.add_child(ui.run_score_caption)
	mid.add_child(score_label)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 6)
	var crown := TextureRect.new()
	crown.texture = ICONS["crown"]
	crown.custom_minimum_size = Vector2(22, 22)
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.modulate = BRASS
	best_label = _label("0", f_num, 20, BRASS)
	ui.run_crown = crown
	ui.run_best_caption = _caption("")
	ui.run_best_caption.visible = false
	brow.add_child(ui.run_best_caption)
	brow.add_child(crown)
	brow.add_child(best_label)
	level_label = _label("", f_bold, 16, MUTED)
	brow.add_child(level_label)
	mid.add_child(brow)
	hud.add_child(mid)
	hud_balance = _icon_button("hint", _use_hint)  # the hint sits opposite pause/restart
	hud_balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_hint = hud_balance
	hud.add_child(hud_balance)
	btn_settings = _icon_button("settings", _open_settings_from_hud)
	btn_settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud.add_child(btn_settings)
	var trow := HBoxContainer.new()
	time_row = trow
	trow.add_theme_constant_override("separation", 10)
	time_bar = ProgressBar.new()
	time_bar.show_percentage = false
	time_bar.custom_minimum_size.y = 10
	time_bar.max_value = 100
	time_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_label = _label("120", f_num, 22)
	time_delta = _label("", f_num, 18, BRASS)
	time_delta.modulate.a = 0.0
	ui.run_time_caption = _caption("")
	ui.run_time_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.run_time_caption.visible = false
	trow.add_child(ui.run_time_caption)
	trow.add_child(time_bar)
	trow.add_child(time_label)
	trow.add_child(time_delta)
	col.add_child(trow)

	# ---- combo badge: coloured pill at the end of the timer row ----
	combo_box = PanelContainer.new()
	combo_style = _box(COMBO_COLORS[0], Color(1, 1, 1, 0.5), 2, 16, Vector4(12, 2, 12, 4))
	combo_box.add_theme_stylebox_override("panel", combo_style)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	combo_mult = _label("", f_display, 20, CREAM)
	combo_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_mult.add_theme_constant_override("outline_size", 8)
	combo_mult.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.25))
	combo_count = _label("", f_bold, 12, CREAM)
	combo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_count.uppercase = true
	combo_bar = ProgressBar.new()
	combo_bar.show_percentage = false
	combo_bar.custom_minimum_size = Vector2(80, 4)
	combo_count.visible = false
	cv.add_child(combo_mult)
	cv.add_child(combo_count)
	cv.add_child(combo_bar)
	combo_box.add_child(cv)
	combo_box.modulate.a = 0.0
	combo_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(combo_box)
	if _is_touch_device():
		# phones: settings next to pause, restart out on the right edge, away from it
		hud.move_child(btn_settings, 1)
		hud.move_child(btn_restart, hud.get_child_count() - 1)
	hud_sets["bright"] = {"roots": [hud, trow], "score": score_label, "best": best_label, "time": time_label,
		"bar": time_bar, "delta": time_delta, "combo_box": combo_box, "combo_style": combo_style, "combo_mult": combo_mult,
		"combo_count": combo_count, "combo_bar": combo_bar, "pause": btn_pause, "restart": btn_restart, "settings": btn_settings}
	_build_classic_hud(col)
	_build_classic_side_hud(col)

	# ---- board ----
	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.number_font = f_num
	col.add_child(board)
	board.resized.connect(func(): _relayout_board.call_deferred())

	# ---- combo banner (above the board, below panels) ----
	var bc := CenterContainer.new()
	bc.set_anchors_preset(Control.PRESET_FULL_RECT)
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bc)
	banner_box = VBoxContainer.new()
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_title = _label("", f_display, 64, BRASS_LIGHT)
	banner_sub = _label("", f_num, 30, CREAM)
	for l in [banner_title, banner_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 14)
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.06, 0.9))
		banner_box.add_child(l)
	banner_box.modulate.a = 0.0
	bc.add_child(banner_box)

	# ---- overlays ----
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_build_menu()
	_build_pause()
	_build_over()
	_build_leaders()
	_build_settings()
	_center_panel_headings()

	toast = _label("", f_bold, 20, INK)
	var tsb := _box(BRASS_LIGHT, BRASS_LIGHT, 0, 10, Vector4(18, 10, 18, 10))
	toast.add_theme_stylebox_override("normal", tsb)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.modulate.a = 0.0
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)

	# Tutorial guidance reserves its own row above the board, including wrapped text.
	tut_label = _label("", f_bold, 20, MENU_TEXT)
	tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tut_label.add_theme_stylebox_override("normal", _box(Color(MENU_PANEL, .96), Color(MENU_BRASS, .65), 1, 14, Vector4(16, 10, 16, 10)))
	tut_label.custom_minimum_size.y = 96
	tut_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tut_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut_label.visible = false
	tut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_column.add_child(tut_label)
	board_column.move_child(tut_label, board.get_index())
	tut_hand = TextureRect.new()
	tut_hand.texture = ICONS["hand"]
	tut_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tut_hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tut_hand.modulate = MENU_BRASS
	tut_hand.visible = false
	tut_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tut_hand)

	# phones are portrait only: in landscape the game pauses behind this notice
	var ro := ColorRect.new()
	ro.color = Color(0.03, 0.07, 0.08, 0.97)
	ro.set_anchors_preset(Control.PRESET_FULL_RECT)
	ro.mouse_filter = Control.MOUSE_FILTER_STOP
	ro.visible = false
	var rc := CenterContainer.new()
	rc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", 18)
	var ri := TextureRect.new()
	ri.texture = ICONS["rotate"]
	ri.custom_minimum_size = Vector2(72, 72)
	ri.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ri.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ri.modulate = BRASS
	ui.rotate_label = _label("", f_bold, 24, CREAM)
	ui.rotate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(ri)
	rv.add_child(ui.rotate_label)
	rc.add_child(rv)
	ro.add_child(rc)
	add_child(ro)
	rotate_overlay = ro


## Classic HUD, as in the first version: title, time with its bar, score, best, a small
## combo counter, then pause / restart / settings.
func _build_classic_hud(col: VBoxContainer) -> void:
	hud_classic = HBoxContainer.new()
	hud_classic.add_theme_constant_override("separation", 18)
	col.add_child(hud_classic)
	col.move_child(hud_classic, 0)
	title_label = _label("", f_display, 30, BRASS)
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud_classic.add_child(title_label)

	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 3)
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tbox.size_flags_stretch_ratio = 2.0
	tbox.custom_minimum_size.x = 110
	time_caption = _caption("")
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	var c_time := _label("120", f_num, 28)
	var c_delta := _label("", f_num, 18, BRASS)
	c_delta.modulate.a = 0.0
	tr.add_child(c_time)
	tr.add_child(c_delta)
	var c_bar := ProgressBar.new()
	c_bar.show_percentage = false
	c_bar.custom_minimum_size.y = 6
	c_bar.max_value = 100
	tbox.add_child(time_caption)
	tbox.add_child(tr)
	tbox.add_child(c_bar)
	hud_classic.add_child(tbox)

	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 3)
	score_caption = _caption("")
	var c_score := _label("0", f_num, 28)
	sbox.add_child(score_caption)
	sbox.add_child(c_score)
	hud_classic.add_child(sbox)
	var bbox := VBoxContainer.new()
	bbox.add_theme_constant_override("separation", 3)
	best_caption = _caption("")
	var c_best := _label("0", f_num, 28)
	bbox.add_child(best_caption)
	bbox.add_child(c_best)
	hud_classic.add_child(bbox)

	var c_combo := PanelContainer.new()
	var c_style := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4.ZERO)
	c_combo.add_theme_stylebox_override("panel", c_style)
	c_combo.custom_minimum_size.x = 80
	c_combo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ccv := VBoxContainer.new()
	ccv.add_theme_constant_override("separation", 2)
	var c_count := _caption("")
	var c_mult := _label("", f_display, 30, BRASS)
	var c_cbar := ProgressBar.new()
	c_cbar.show_percentage = false
	c_cbar.custom_minimum_size.y = 4
	ccv.add_child(c_count)
	ccv.add_child(c_mult)
	ccv.add_child(c_cbar)
	c_combo.add_child(ccv)
	c_combo.modulate.a = 0.0
	hud_classic.add_child(c_combo)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c_pause := _icon_button("pause", func(): Sfx.play("click"); pause_game())
	var c_restart := _icon_button("restart", func(): Sfx.play("click"); start_game(mode.id, daily))
	var c_settings := _icon_button("settings", _open_settings_from_hud)
	btns.add_child(c_pause)
	if _is_touch_device():
		btns.add_child(c_settings)
		btns.add_child(c_restart)
	else:
		btns.add_child(c_restart)
		btns.add_child(c_settings)
	hud_classic.add_child(btns)
	hud_sets["classic"] = {"roots": [hud_classic], "score": c_score, "best": c_best, "time": c_time, "bar": c_bar,
		"delta": c_delta, "combo_box": c_combo, "combo_style": c_style, "combo_mult": c_mult, "combo_count": c_count,
		"combo_bar": c_cbar, "pause": c_pause, "restart": c_restart, "settings": c_settings}
	var bonus_row := HBoxContainer.new()
	bonus_row.name = "ClassicBonusCombos"
	bonus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bonus_row.add_theme_constant_override("separation", 16)
	bonus_row.custom_minimum_size.y = 28
	bonus_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bonus_row)
	col.move_child(bonus_row, 1)
	hud_sets.classic.roots.append(bonus_row)
	hud_sets.classic.bonus = _build_bonus_widgets(bonus_row, bonus_row, false)


## Android Classic keeps both side rails on every screen; all other HUDs stay intact.
func _classic_android_sides() -> bool:
	return OS.has_feature("android") and mode.id == "classic"


func _side_label(text: String, font: Font, font_size: int, color := CREAM) -> Label:
	var label := _label(text, font, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_FILL
	label.add_theme_constant_override("line_spacing", 0)
	return label


func _side_stat(caption: Label, value: Label) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.add_child(caption)
	block.add_child(value)
	return block


func _build_classic_side_hud(col: VBoxContainer) -> void:
	classic_sides = HBoxContainer.new()
	classic_sides.name = "ClassicAndroidSides"
	classic_sides.add_theme_constant_override("separation", 4)
	classic_sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	classic_sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	classic_sides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	classic_sides.visible = false
	col.add_child(classic_sides)
	classic_stats = VBoxContainer.new()
	classic_stats.name = "Statistics"
	classic_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	classic_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	classic_stats.add_theme_constant_override("separation", 4)
	classic_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	classic_sides.add_child(classic_stats)

	var c_time := _side_label("120", f_num, 28)
	var c_delta := _side_label("", f_num, 16, BRASS)
	c_delta.modulate.a = 0.0
	var c_time_caption := _side_label("", f_bold, 12, MUTED)
	c_time_caption.uppercase = true
	var timer := _side_stat(c_time_caption, c_time)
	var c_bar := ProgressBar.new()
	c_bar.show_percentage = false
	c_bar.custom_minimum_size.y = 6
	c_bar.max_value = 100
	timer.add_child(c_bar)
	timer.add_child(c_delta)
	classic_stats.add_child(timer)

	var c_score := _side_label("0", f_num, 24)
	var c_score_caption := _side_label("", f_bold, 12, MUTED)
	c_score_caption.uppercase = true
	classic_stats.add_child(_side_stat(c_score_caption, c_score))
	var c_best := _side_label("0", f_num, 24)
	var c_best_caption := _side_label("", f_bold, 12, MUTED)
	c_best_caption.uppercase = true
	classic_stats.add_child(_side_stat(c_best_caption, c_best))

	var c_combo := PanelContainer.new()
	var c_style := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4.ZERO)
	c_combo.add_theme_stylebox_override("panel", c_style)
	var combo := VBoxContainer.new()
	combo.add_theme_constant_override("separation", 2)
	var c_count := _side_label("", f_bold, 12, MUTED)
	c_count.uppercase = true
	var c_mult := _side_label("", f_display, 30, BRASS)
	var c_cbar := ProgressBar.new()
	c_cbar.show_percentage = false
	c_cbar.custom_minimum_size.y = 4
	combo.add_child(c_count)
	combo.add_child(c_mult)
	combo.add_child(c_cbar)
	c_combo.add_child(combo)
	c_combo.modulate.a = 0.0
	classic_stats.add_child(c_combo)

	classic_actions = VBoxContainer.new()
	classic_actions.name = "Actions"
	classic_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	classic_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	classic_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	classic_actions.add_theme_constant_override("separation", 16)
	classic_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	classic_sides.add_child(classic_actions)
	var c_pause := _icon_button("pause", func(): Sfx.play("click"); pause_game())
	var c_restart := _icon_button("restart", func(): Sfx.play("click"); start_game(mode.id, daily))
	var c_settings := _icon_button("settings", _open_settings_from_hud)
	for button in [c_pause, c_restart, c_settings]:
		classic_actions.add_child(button)
	hud_sets["classic_android"] = {"roots": [classic_sides], "score": c_score, "best": c_best, "time": c_time, "bar": c_bar,
		"delta": c_delta, "combo_box": c_combo, "combo_style": c_style, "combo_mult": c_mult, "combo_count": c_count,
		"combo_bar": c_cbar, "pause": c_pause, "restart": c_restart, "settings": c_settings,
		"captions": {"time": c_time_caption, "score": c_score_caption, "best": c_best_caption}}
	hud_sets.classic_android.bonus = _build_bonus_widgets(classic_stats, classic_actions, true)


## Compact score-only feedback, in the HUD rather than over playable cells.
func _build_bonus_widgets(progress_parent: BoxContainer, event_parent: BoxContainer, sides: bool) -> Dictionary:
	var progress := HBoxContainer.new()
	progress.name = "ColorStreakProgress"
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	progress.add_theme_constant_override("separation", 4)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_parent.add_child(progress)
	var gem := TextureRect.new()
	gem.custom_minimum_size = Vector2(18, 18)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(gem)
	var count := _label("", f_num, 11 if sides else 14, MUTED)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(count)
	progress.modulate.a = 0.0
	progress.visible = not sides
	var events: BoxContainer = VBoxContainer.new() if sides else HBoxContainer.new()
	events.name = "BonusEvents"
	events.add_theme_constant_override("separation", 4 if sides else 16)
	events.mouse_filter = Control.MOUSE_FILTER_IGNORE
	events.visible = not sides
	event_parent.add_child(events)
	var double_hit := _label("DOUBLE HIT!", f_bold, 12 if sides else 14, BRASS_LIGHT)
	var color_streak := _label("COLOR STREAK!", f_bold, 12 if sides else 14, CREAM)
	for label in [double_hit, color_streak]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if sides:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.y = 34
		var parent: BoxContainer = progress_parent if sides and label == double_hit else events
		parent.add_child(label)
		label.modulate.a = 0.0
		label.visible = not sides
	return {"progress": progress, "gem": gem, "count": count, "events": events,
		"double_hit": double_hit, "color_streak": color_streak}


func _set_classic_side_layout(enabled: bool) -> void:
	if not board:
		return
	var parent: Control = classic_sides if enabled else board_column
	if board.get_parent() != parent:
		if not enabled:
			board.custom_minimum_size.x = 0.0
			board.custom_maximum_size.x = -1.0
			board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board.reparent(parent, false)
	if enabled:
		classic_sides.move_child(board, 1)
		title_label.visible = false


func _constrain_side_width(node: Control, width: float) -> void:
	node.custom_maximum_size.x = width
	for child in node.get_children():
		if child is Control:
			_constrain_side_width(child, width)


func _layout_classic_sides(view: Vector2, insets: Rect2) -> void:
	var side_inset := maxf(ceilf(insets.position.x),ceilf(insets.size.x))
	var vertical_inset := maxf(ceilf(insets.position.y),ceilf(insets.size.y))
	var safe_height := view.y - vertical_inset*2.0 - 8.0
	# Center on the full screen. HUD blocks sit halfway from its edges to the frame.
	# Reserve enough outer space for cutouts without shifting any of those centres.
	var fit_cell := maxf(8.0, floorf(minf((view.x - side_inset*4.0 - 140.0 - 16.0 - 6.0) / 23.0,
		(safe_height - 6.0) / 15.0)))
	var board_width := fit_cell * 23.0 + 6.0
	var content := floorf(clampf((view.x-board_width)*0.5-side_inset*2.0-8.0,70.0,80.0))
	board.size_flags_horizontal = Control.SIZE_FILL
	board.custom_minimum_size.x = board_width
	board.custom_maximum_size.x = board_width
	classic_stats.custom_minimum_size.x = content
	classic_actions.custom_minimum_size.x = content
	# Center each compact HUD block between the screen edge and the board frame.
	# The outer margin and the gap to the board are both 4 px.
	for block in classic_stats.get_children():
		block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		block.custom_minimum_size.x = content
		_constrain_side_width(block, content)
	for block in classic_actions.get_children():
		block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if block is Button:
			block.custom_minimum_size = Vector2.ONE * content
			block.custom_maximum_size.x = content
		else:
			block.custom_minimum_size.x = content
			_constrain_side_width(block, content)
	hud_sets.classic_android.time.add_theme_font_size_override("font_size", 26 if content < 74.0 else 28)
	_classic_safe_area = insets


func _set_hud_number(label: Label, value: int) -> void:
	var text := str(value)
	if _classic_android_sides():
		var width := maxf(classic_stats.custom_minimum_size.x, 70.0)
		var font_size := 18
		if text.length() <= 6:
			var measured := f_num.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
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


func _poll_classic_safe_area(delta: float) -> void:
	if not _classic_android_sides():
		return
	_classic_safe_poll += delta
	if _classic_safe_poll >= 0.25:
		_classic_safe_poll = 0.0
		if _safe_insets() != _classic_safe_area:
			_on_viewport_resized()


## Show the HUD that belongs to `id` and point the shared widget variables at it.
func _apply_hud(id: String) -> void:
	if id == "classic" and _classic_android_sides():
		id = "classic_android"
	for k in hud_sets:
		for n in hud_sets[k].roots:
			n.visible = k == id
	var set: Dictionary = hud_sets[id]
	score_label = set.score
	best_label = set.best
	time_label = set.time
	time_bar = set.bar
	time_delta = set.delta
	combo_box = set.combo_box
	combo_style = set.combo_style
	combo_mult = set.combo_mult
	combo_count = set.combo_count
	combo_bar = set.combo_bar
	btn_pause = set.pause
	btn_restart = set.restart
	btn_settings = set.settings
	_set_classic_side_layout(id == "classic_android")


## Keep Bright's two-row geometry: _dims() uses the remaining board area.
## This changes paint and typography only; hidden modes retain their original HUD.
func _style_run_hud(unified: bool) -> void:
	var run: Dictionary = hud_sets.bright
	ui.run_score_caption.visible = unified
	ui.run_best_caption.visible = unified
	ui.run_time_caption.visible = unified
	ui.run_crown.visible = not unified
	hud.custom_minimum_size.y = 93 if unified else 0
	time_row.custom_minimum_size.y = 35 if unified else 0
	run.score.add_theme_font_override("font", f_num if unified else f_display)
	run.score.add_theme_font_size_override("font_size", 28 if unified else 54)
	run.score.add_theme_constant_override("outline_size", 0 if unified else 10)
	run.bar.custom_minimum_size.y = 6 if unified else 10
	run.best.add_theme_color_override("font_color", CREAM if unified else BRASS)
	run.combo_mult.add_theme_constant_override("outline_size", 0 if unified else 8)
	run.combo_mult.add_theme_color_override("font_color", BRASS if unified else CREAM)
	run.combo_style.border_color = Color.TRANSPARENT if unified else Color(1, 1, 1, 0.5)
	run.combo_style.bg_color = Color.TRANSPARENT if unified else COMBO_COLORS[0]


func _panel() -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	center.add_child(p)
	return [p, v]


func _row(children: Array) -> HFlowContainer:
	var r := HFlowContainer.new()
	r.alignment = FlowContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("h_separation", 10)
	r.add_theme_constant_override("v_separation", 10)
	for c in children:
		r.add_child(c)
	return r


## Local overrides keep other screens and gameplay HUD unchanged.
func _style_menu_button(b: Button, primary: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := MENU_BRASS if primary else Color(MENU_PANEL, .85)
		var edge := Color(MENU_BRASS, .6)
		if state_name == "hover":
			fill = fill.lightened(.12)
			edge = MENU_TEXT
		elif state_name == "pressed":
			fill = fill.darkened(.15)
		elif state_name == "focus":
			fill = Color.TRANSPARENT
			edge = MENU_TEXT
		elif state_name == "disabled":
			fill.a = .35
			edge.a = .25
		b.add_theme_stylebox_override(state_name, _box(fill, edge, 2 if state_name == "focus" else 1, 10, Vector4(16,12,16,12)))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:
		b.add_theme_color_override(key, Color("#112326") if primary else MENU_TEXT)


## Home screen: floating gems over a big title, one big Play button, the best score, and a row
## of round buttons (leaderboard, daily board, how to play, settings).
func _build_menu() -> void:
	var home := MarginContainer.new()
	home.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		home.add_theme_constant_override("margin_" + side, 24)
	menu_panel = home
	add_child(home)
	move_child(home, center.get_index())
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	ui.home_stack = v
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	ui.home_scroll = scroll
	drag_scrolls.append(scroll)
	home.add_child(scroll)
	var content := CenterContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	content.add_child(v)

	var gems := HBoxContainer.new()
	gems.alignment = BoxContainer.ALIGNMENT_CENTER
	gems.add_theme_constant_override("separation", 22)
	ui.home_gems = []
	for k in [1, 0, 2]:
		var t := TextureRect.new()
		t.texture = load("res://assets/gems/gem_%d.png" % k)
		t.custom_minimum_size = Vector2(76, 76)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.pivot_offset = Vector2(38, 38)
		gems.add_child(t)
		ui.home_gems.append(t)
	v.add_child(gems)

	ui.menu_title = _label("", f_display, 58, MENU_TEXT)
	ui.menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.menu_title.add_theme_constant_override("outline_size", 0)
	ui.menu_title.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.15, 0.85))
	ui.menu_tag = _para("")
	ui.menu_tag.add_theme_color_override("font_color", MENU_MUTED)
	v.add_child(ui.menu_title)
	v.add_child(ui.menu_tag)

	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	v.add_child(gap)
	ui.btn_home_play = _button("", "play", true, func():
		Sfx.play("click")
		if Progress.tutorial:
			_show_panel(mode_panel)
		else:
			start_game("tutorial"))
	_style_menu_button(ui.btn_home_play, true)
	ui.btn_home_play.custom_minimum_size = Vector2(280, 68)
	ui.btn_home_play.add_theme_font_size_override("font_size", 28)
	ui.btn_home_play.add_theme_constant_override("icon_max_width", 34)
	ui.btn_home_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ui.btn_home_play)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 8)
	brow.add_child(_crown(24))
	ui.home_best = _label("", f_num, 18, MENU_MUTED)
	brow.add_child(ui.home_best)
	v.add_child(brow)
	ui.daily_card = _button("", "calendar", false, func(): Sfx.play("click"); start_game("bright", true))
	_style_menu_button(ui.daily_card, false)
	ui.daily_card.add_theme_font_size_override("font_size", 17)
	ui.daily_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.daily_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ui.daily_card.custom_minimum_size = Vector2(300, 0)
	v.add_child(ui.daily_card)

	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 8
	v.add_child(gap2)
	var crow2 := HBoxContainer.new()
	crow2.alignment = BoxContainer.ALIGNMENT_CENTER
	crow2.add_theme_constant_override("separation", 6)
	crow2.add_child(_icon_tex("crystal", 24, Color("#7fd8ff")))
	ui.home_crystals = _label("0", f_num, 18, MENU_TEXT)
	crow2.add_child(ui.home_crystals)
	v.add_child(crow2)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 10)
	ui.home_leaders = _round_button("trophy", func(): _open_leaders(menu_panel))
	ui.home_rules = _round_button("info", func(): Sfx.play("click"); _show_rules())
	ui.home_pass = _round_button("ticket", func(): Sfx.play("click"); _refresh_pass(); _show_panel(pass_panel))
	ui.home_stats = _round_button("chart", func(): Sfx.play("click"); _refresh_stats(); _show_panel(stats_panel))
	ui.home_settings = _round_button("settings", func(): _open_settings(menu_panel))
	ui.home_tasks = _round_button("tasks", func(): Sfx.play("click"); _refresh_tasks(); _show_panel(tasks_panel))
	ui.home_coll = _round_button("crystal", func(): Sfx.play("click"); _refresh_collection(); _show_panel(collection_panel))
	ui.home_coll.visible = Progress.COSMETICS_ENABLED
	ui.home_gift = _round_button("gift", func(): Sfx.play("click"); _refresh_gift(); _show_panel(gift_panel))
	ui.home_ach = _round_button("medal", func(): Sfx.play("click"); _refresh_achievements(); _show_panel(ach_panel))
	for b in [ui.home_gift, ui.home_pass, ui.home_tasks, ui.home_ach, ui.home_coll, ui.home_leaders, ui.home_stats, ui.home_rules, ui.home_settings]:
		row.add_child(b)
	v.add_child(row)
	_build_modes()
	_build_rules()
	_build_map()
	_build_level_result()
	_build_tasks()
	_build_collection()
	_build_gift()
	_build_achievements()
	_build_pass()
	_build_stats()
	_build_confirm()


func _crown(px: int) -> TextureRect:
	var c := TextureRect.new()
	c.texture = ICONS["crown"]
	c.custom_minimum_size = Vector2(px, px)
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.modulate = BRASS
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


## Round icon button with a caption under it, for the home screen's bottom row.
func _round_button(icon_name: String, cb: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var b := Button.new()
	b.icon = ICONS[icon_name]
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(56, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_constant_override("icon_max_width", 30)
	_style_menu_button(b, false)
	b.pressed.connect(cb)
	var cap := _label("", f_bold, 13, MENU_MUTED)
	cap.custom_minimum_size.x = 90
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	box.add_child(cap)
	box.set_meta("caption", cap)
	return box


## Mode selection: a card per mode with a preview, a short description, its best and Play.
func _build_modes() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 16)
	mode_panel = root
	add_child(root)
	move_child(root, center.get_index())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)
	var head := HBoxContainer.new()
	var back := _icon_button("back", func(): Sfx.play("click"); _show_panel(menu_panel))
	_style_menu_button(back, false)
	ui.mode_back = back
	ui.mode_title = _label("", f_display, 32, MENU_TEXT)
	ui.mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.mode_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(52, 52)
	head.add_child(back)
	head.add_child(ui.mode_title)
	head.add_child(balance)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drag_scrolls.append(scroll)
	var flow := GridContainer.new()
	flow.columns = 2
	flow.add_theme_constant_override("h_separation", 24)
	flow.add_theme_constant_override("v_separation", 20)
	ui.mode_grid = flow
	ui.mode_scroll = scroll
	scroll.follow_focus = true
	ui.mode_cards = []
	for id in (["levels", "bright", "zen", "puzzle", "classic"] if OS.has_feature("android")
			else ["classic", "levels", "bright", "zen", "puzzle"]):
		var card := PanelContainer.new()
		var accent: Color = MENU_BRASS if id in MENU_MODES else BRASS
		card.add_theme_stylebox_override("panel", _box(Color(MENU_PANEL, .94), Color(accent,.65), 1, 14, Vector4(18, 18, 18, 20)))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 10)
		var pv := MenuPreview.new()
		pv.visual_profile = "classic" if id == "classic" else "classic_run"
		pv.number_font = f_num
		pv.custom_minimum_size = Vector2(0, 180)
		ui["card_preview_" + id] = pv
		cv.add_child(pv)
		ui["card_name_" + id] = _label("", f_display, 28, MENU_TEXT)
		ui["card_desc_" + id] = _para("")
		ui["card_desc_" + id].add_theme_font_size_override("font_size", 17)
		ui["card_desc_" + id].add_theme_color_override("font_color", MENU_MUTED)
		ui["card_desc_" + id].size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(ui["card_name_" + id])
		cv.add_child(ui["card_desc_" + id])
		var br := HBoxContainer.new()
		br.add_theme_constant_override("separation", 6)
		br.add_child(_crown(20))
		ui["card_best_" + id] = _label("", f_num, 18, MENU_MUTED)
		br.add_child(ui["card_best_" + id])
		cv.add_child(br)
		var mode_id: String = id
		if id == "levels":
			ui["card_play_" + id] = _button("", "map", true, func(): Sfx.play("click"); _open_map())
		elif id == "puzzle":
			ui["card_play_" + id] = _button("", "puzzle", true, func(): Sfx.play("click"); _open_map("puzzle"))
		else:
			ui["card_play_" + id] = _button("", "play", true, func(): Sfx.play("click"); start_game(mode_id))
		_style_menu_button(ui["card_play_" + id], true)
		cv.add_child(ui["card_play_" + id])
		card.add_child(cv)
		flow.add_child(card)
		card.visible = id in MENU_MODES
		ui.mode_cards.append(card)
	cc.add_child(flow)
	scroll.add_child(cc)
	v.add_child(scroll)


func _build_map() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 16)
	map_panel = root
	add_child(root)
	move_child(root, center.get_index())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	root.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(_icon_button("back", func(): Sfx.play("click"); _show_panel(mode_panel)))
	ui.map_title = _label("", f_display, 34, BRASS)
	ui.map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ui.map_title)
	var sbox := HBoxContainer.new()
	sbox.add_theme_constant_override("separation", 4)
	ui.map_star_icon = _icon_tex("star", 22, BRASS)
	sbox.add_child(ui.map_star_icon)
	ui.map_stars = _label("0", f_num, 20, BRASS)
	sbox.add_child(ui.map_stars)
	sbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sbox)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag_scrolls.append(scroll)
	ui.map_list = VBoxContainer.new()
	ui.map_list.add_theme_constant_override("separation", 14)
	cc.add_child(ui.map_list)
	scroll.add_child(cc)
	v.add_child(scroll)


func _icon_tex(name: String, px: int, col := CREAM) -> TextureRect:
	var t := TextureRect.new()
	t.texture = ICONS[name]
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = col
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## Rebuild the map: levels in chapters of 20 (a header with the chapter's name, stars and
## rewards over each), or the puzzles in one grid. Unlocked ones first, then a few locked.
func _refresh_map() -> void:
	var list: VBoxContainer = ui.map_list
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var puzzles := map_kind == "puzzle"
	var top := Progress.puzzles + 1 if puzzles else Progress.max_unlocked()
	var shown := int(ceil((top + 10) / 5.0)) * 5
	ui.map_title.text = L.t("mode_puzzle" if puzzles else "mode_levels")
	ui.map_stars.text = str(Progress.puzzles) if puzzles else str(Progress.total_stars())
	ui.map_star_icon.texture = ICONS["check" if puzzles else "star"]
	if puzzles:
		list.add_child(_map_grid(1, shown, top, true))
		return
	var csz := BoardLogic.CHAPTER_SIZE
	for c in BoardLogic.chapter_of(shown) + 1:
		list.add_child(_chapter_header(c))
		list.add_child(_map_grid(c * csz + 1, mini((c + 1) * csz, shown), top, false))


func _chapter_header(c: int) -> Control:
	var th: Dictionary = CHAPTER_THEMES[c % CHAPTER_THEMES.size()]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(th.top, 0.55), Color(th.top.lightened(0.35), 0.8), 2, 14, Vector4(14, 8, 14, 8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(L.t("chapter_n", {"n": c + 1}) + " · " + L.t("chapter_%d" % (c % CHAPTER_THEMES.size())), f_display, 20, CREAM))
	var rule := _label(L.t("boss_rule") + " " + L.t("rule_" + str(BoardLogic.CHAPTER_RULES[c % BoardLogic.CHAPTER_RULES.size()])), f_body, 13, MUTED)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(rule)
	row.add_child(info)
	var st := Progress.chapter_stats(c)
	row.add_child(_icon_tex("star", 18, BRASS))
	row.add_child(_label("%d/%d" % [st.stars, st.max], f_num, 16, BRASS))
	var chapter: int = c
	for what in Progress.chapter_due(c):
		var kind: String = what
		var b := _button("+%d" % (Progress.CHAPTER_DONE if kind == "done" else Progress.CHAPTER_FULL), "crystal", true, func():
			var n := Progress.claim_chapter(chapter, kind)
			if n > 0:
				Sfx.play("level")
				_toast(L.t("chapter_reward", {"n": n}))
				_refresh_map())
		b.add_theme_font_size_override("font_size", 15)
		row.add_child(b)
	box.add_child(row)
	return box


func _map_grid(from: int, to: int, top: int, puzzles: bool) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for n in range(from, to + 1):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.add_theme_font_override("font", f_display)
		b.add_theme_font_size_override("font_size", 24)
		var locked := n > top
		if locked:
			b.icon = ICONS["lock"]
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.disabled = true
		else:
			b.text = str(n)
			var lvl: int = n
			if puzzles:
				b.pressed.connect(func(): Sfx.play("click"); start_puzzle(lvl))
			else:
				b.pressed.connect(func(): Sfx.play("click"); start_level(lvl))
			if n == top:
				b.theme_type_variation = "PrimaryButton"
			if n % 10 == 0 and not puzzles:
				b.icon = ICONS["medal"]
				b.add_theme_constant_override("icon_max_width", 18)
		cell.add_child(b)
		var srow := HBoxContainer.new()
		srow.alignment = BoxContainer.ALIGNMENT_CENTER
		srow.add_theme_constant_override("separation", 0)
		if puzzles:
			srow.add_child(_icon_tex("check", 18, Color("#5cc87a") if n <= Progress.puzzles else Color(1, 1, 1, 0.12)))
		else:
			var got := Progress.stars_for(n)
			for i in 3:
				srow.add_child(_icon_tex("star", 18, BRASS if i < got else Color(1, 1, 1, 0.15)))
		cell.add_child(srow)
		grid.add_child(cell)
	return grid


func _build_level_result() -> void:
	var pv := _panel()
	level_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.level_title = _label("", f_display, 40, BRASS)
	ui.level_result = _label("", f_bold, 22, CREAM)
	v.add_child(ui.level_title)
	v.add_child(ui.level_result)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 14)
	ui.level_stars = []
	for i in 3:
		var st := _icon_tex("star", 64, Color(0.25, 0.3, 0.5, 1))
		srow.add_child(st)
		ui.level_stars.append(st)
	v.add_child(srow)
	ui.level_line = _para("")
	ui.level_line.add_theme_color_override("font_color", MUTED)
	v.add_child(ui.level_line)
	ui.level_next = _button("", "play", true, func():
		Sfx.play("click")
		if mode.kind == "puzzle":
			start_puzzle(puzzle_n + 1)
		else:
			start_level(level_n + 1))
	ui.level_retry = _button("", "restart", false, func():
		Sfx.play("click")
		if mode.kind == "puzzle":
			start_puzzle(puzzle_n)
		else:
			start_level(level_n))
	ui.level_double = _button("", "video", false, _on_double)
	ui.level_continue = _button("", "video", false, _on_level_continue)
	v.add_child(ui.level_continue)
	v.add_child(ui.level_double)
	ui.level_map = _button("", "map", false, func():
		Sfx.play("click")
		_open_map("puzzle" if mode.kind == "puzzle" else "levels"))
	v.add_child(_row([ui.level_next, ui.level_retry, ui.level_map]))


func _open_map(kind := "levels") -> void:
	map_kind = kind
	_set_orientation(false)
	state = State.MENU
	_refresh_map()
	_show_panel(map_panel)


func _build_tasks() -> void:
	var pv := _panel()
	tasks_panel = pv[0]
	var v: VBoxContainer = pv[1]
	var head := HBoxContainer.new()
	ui.tasks_title = _label("", f_display, 34, BRASS)
	ui.tasks_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ui.tasks_title)
	head.add_child(_icon_tex("crystal", 24, Color("#7fd8ff")))
	ui.tasks_crystals = _label("0", f_num, 22, Color("#7fd8ff"))
	head.add_child(ui.tasks_crystals)
	v.add_child(head)
	ui.tasks_list = VBoxContainer.new()
	ui.tasks_list.add_theme_constant_override("separation", 10)
	v.add_child(ui.tasks_list)
	ui.btn_close_tasks = _button("", "", true, func(): Sfx.play("click"); _show_panel(menu_panel))
	v.add_child(_row([ui.btn_close_tasks]))


func _refresh_tasks() -> void:
	Progress.refresh_tasks()
	ui.tasks_crystals.text = str(Progress.crystals)
	var list: VBoxContainer = ui.tasks_list
	for c in list.get_children():
		c.queue_free()
	for i in Progress.tasks.size():
		var t: Dictionary = Progress.tasks[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := _para(L.t("task_" + str(t.id), {"n": t.goal}))
		name.add_theme_font_size_override("font_size", 18)
		info.add_child(name)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.max_value = float(t.goal)
		bar.value = float(t.progress)
		info.add_child(bar)
		row.add_child(info)
		var idx: int = i
		if bool(t.claimed):
			row.add_child(_label("✓", f_bold, 26, Color("#5cc87a")))
		elif Progress.task_done(i):
			var b := _button("+%d" % int(t.reward), "crystal", true, func():
				Progress.claim(idx)
				Sfx.play("star")
				_refresh_tasks()
				_refresh_menu_bests())
			row.add_child(b)
		else:
			row.add_child(_label("%d/%d" % [int(t.progress), int(t.goal)], f_num, 18, MUTED))
		list.add_child(row)


func _build_collection() -> void:
	var pv := _panel()
	collection_panel = pv[0]
	var v: VBoxContainer = pv[1]
	var head := HBoxContainer.new()
	ui.coll_title = _label("", f_display, 34, BRASS)
	ui.coll_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ui.coll_title)
	head.add_child(_icon_tex("crystal", 24, Color("#7fd8ff")))
	ui.coll_crystals = _label("0", f_num, 22, Color("#7fd8ff"))
	head.add_child(ui.coll_crystals)
	v.add_child(head)
	ui.coll_hint = _para("")
	ui.coll_hint.add_theme_color_override("font_color", MUTED)
	ui.coll_hint.add_theme_font_size_override("font_size", 16)
	v.add_child(ui.coll_hint)
	ui.coll_grid = GridContainer.new()
	ui.coll_grid.columns = 3
	ui.coll_grid.add_theme_constant_override("h_separation", 10)
	ui.coll_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(ui.coll_grid)
	ui.btn_close_coll = _button("", "", true, func(): Sfx.play("click"); _show_panel(menu_panel))
	v.add_child(_row([ui.btn_close_coll]))


func _refresh_collection() -> void:
	if not Progress.COSMETICS_ENABLED:
		return
	ui.coll_crystals.text = str(Progress.crystals)
	var grid: GridContainer = ui.coll_grid
	for c in grid.get_children():
		grid.remove_child(c)  # out of the layout right away so the panel can be measured
		c.queue_free()
	for i in Progress.LOOK_PRICES.size():
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		var tiles := HBoxContainer.new()
		tiles.alignment = BoxContainer.ALIGNMENT_CENTER
		for k in [0, 2, 4]:
			var t := TextureRect.new()
			t.texture = load("res://assets/tiles/look_%d_%d.png" % [i, k])
			t.custom_minimum_size = Vector2(34, 34)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tiles.add_child(t)
		card.add_child(tiles)
		var nm := _label(L.t("look_%d" % i), f_bold, 15, CREAM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		var idx: int = i
		var b: Button
		if Progress.look == i:
			b = _button(L.t("selected"), "", false)
			b.disabled = true
		elif not Progress.owns(i) and int(Progress.LOOK_PRICES[i]) == Progress.SEASON:
			if Progress.season_look() == i:
				b = _button(L.t("season_claim"), "gift", true, func(): Progress.claim_season(); Sfx.play("star"); _refresh_collection())
			else:
				b = _button(L.t("season_only"), "", false)
				b.disabled = true
		elif not Progress.owns(i) and int(Progress.LOOK_PRICES[i]) == Progress.PASS:
			b = _button(L.t("pass_only", {"n": 10 if i == Progress.NEON_LOOK else 30}), "", false)
			b.disabled = true
		elif not Progress.owns(i) and int(Progress.LOOK_PRICES[i]) == Progress.GIFT:
			b = _button(L.t("gift_only"), "", false)
			b.disabled = true
		elif Progress.owns(i):
			b = _button(L.t("select"), "", false, func(): Progress.select(idx); Sfx.play("click"); _refresh_collection())
		else:
			b = _button(str(Progress.LOOK_PRICES[i]), "crystal", true, func():
				if Progress.buy(idx):
					Sfx.play("star")
				else:
					_toast(L.t("not_enough"))
				_refresh_collection()
				_refresh_menu_bests())
			b.disabled = Progress.crystals < int(Progress.LOOK_PRICES[i])
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size.x = 0  # three cards a row: let the buttons be as narrow as their text
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(b)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
	if collection_panel.visible:
		_fit_panels.call_deferred()


func _build_gift() -> void:
	var pv := _panel()
	gift_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.gift_title = _label("", f_display, 32, BRASS)
	v.add_child(ui.gift_title)
	ui.gift_days = HFlowContainer.new()
	ui.gift_days.alignment = FlowContainer.ALIGNMENT_CENTER
	ui.gift_days.add_theme_constant_override("h_separation", 6)
	ui.gift_days.add_theme_constant_override("v_separation", 6)
	v.add_child(ui.gift_days)
	ui.gift_line = _para("")
	ui.gift_line.add_theme_color_override("font_color", MUTED)
	ui.gift_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ui.gift_line)
	ui.btn_gift = _button("", "gift", true, _open_gift)
	ui.btn_close_gift = _button("", "", false, func(): Sfx.play("click"); _show_panel(menu_panel))
	v.add_child(_row([ui.btn_gift, ui.btn_close_gift]))


func _refresh_gift() -> void:
	for c in ui.gift_days.get_children():
		c.queue_free()
	var ready := Progress.gift_ready()
	var next_day := (Progress.streak % 7) + 1 if ready else ((Progress.streak - 1) % 7) + 1
	for d in range(1, 8):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var day_label := _label(L.t("day_n", {"n": d}), f_bold, 13, MUTED)
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var amt := _label("+%d" % Progress.gift_amount(d), f_num, 18, BRASS if d == next_day else CREAM)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amt.custom_minimum_size = Vector2(52, 0)
		amt.add_theme_stylebox_override("normal", _box(Color(BRASS, 0.25) if d == next_day else Color(0, 0, 0, 0.25),
			BRASS if d == next_day else Color(1, 1, 1, 0.1), 2, 10, Vector4(6, 8, 6, 8)))
		box.add_child(day_label)
		box.add_child(amt)
		ui.gift_days.add_child(box)
	ui.btn_gift.visible = ready
	ui.btn_gift.text = L.t("take")
	ui.gift_line.text = L.t("gift_day7" if Progress.COSMETICS_ENABLED else "gift_daily_crystals") if ready else L.t("gift_tomorrow")


func _open_gift() -> void:
	var r := Progress.open_gift()
	if r.is_empty():
		return
	Sfx.play("level")
	_toast(L.t("gift_got", {"n": r.crystals}) + ("  ·  " + L.t("gift_look") if Progress.COSMETICS_ENABLED and int(r.look) >= 0 else ""))
	_refresh_gift()
	_refresh_menu_bests()


func _build_achievements() -> void:
	var pv := _panel()
	ach_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.ach_title = _label("", f_display, 32, BRASS)
	v.add_child(ui.ach_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 360
	drag_scrolls.append(scroll)
	ui.ach_scroll = scroll
	ui.ach_list = VBoxContainer.new()
	ui.ach_list.add_theme_constant_override("separation", 8)
	ui.ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ui.ach_list)
	v.add_child(scroll)
	ui.btn_close_ach = _button("", "", true, func(): Sfx.play("click"); _show_panel(menu_panel))
	v.add_child(_row([ui.btn_close_ach]))


func _refresh_achievements() -> void:
	for c in ui.ach_list.get_children():
		ui.ach_list.remove_child(c)
		c.queue_free()
	for i in Progress.ACHIEVEMENTS.size():
		var a: Dictionary = Progress.ACHIEVEMENTS[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var got_it: bool = a.id in Progress.achieved
		row.add_child(_icon_tex("medal", 28, BRASS if got_it or Progress.achievement_done(i) else Color(1, 1, 1, 0.25)))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := _para(L.t("ach_" + str(a.id), {"n": a.goal}))
		name.add_theme_font_size_override("font_size", 17)
		info.add_child(name)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
		bar.max_value = float(a.goal)
		bar.value = float(Progress.achievement_progress(i))
		info.add_child(bar)
		row.add_child(info)
		var idx: int = i
		if got_it:
			row.add_child(_label("✓", f_bold, 24, Color("#5cc87a")))
		elif Progress.achievement_done(i):
			row.add_child(_button("+%d" % int(a.reward), "crystal", true, func():
				Progress.claim_achievement(idx)
				Sfx.play("star")
				_refresh_achievements()
				_refresh_menu_bests()))
		else:
			row.add_child(_label("%d/%d" % [Progress.achievement_progress(i), int(a.goal)], f_num, 15, MUTED))
		ui.ach_list.add_child(row)
	_fit_panels.call_deferred()


func _build_pass() -> void:
	var pv := _panel()
	pass_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.pass_title = _label("", f_display, 32, BRASS)
	v.add_child(ui.pass_title)
	ui.pass_sub = _para("")
	ui.pass_sub.add_theme_color_override("font_color", MUTED)
	ui.pass_sub.add_theme_font_size_override("font_size", 17)
	v.add_child(ui.pass_sub)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	ui.pass_bar = ProgressBar.new()
	ui.pass_bar.show_percentage = false
	ui.pass_bar.custom_minimum_size.y = 12
	ui.pass_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.pass_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.pass_xp = _label("", f_num, 16, BRASS_LIGHT)
	brow.add_child(ui.pass_bar)
	brow.add_child(ui.pass_xp)
	v.add_child(brow)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.pass_scroll = scroll
	drag_scrolls.append(scroll)
	ui.pass_list = VBoxContainer.new()
	ui.pass_list.add_theme_constant_override("separation", 6)
	ui.pass_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ui.pass_list)
	v.add_child(scroll)
	ui.btn_close_pass = _button("", "", true, func(): Sfx.play("click"); _show_panel(menu_panel))
	v.add_child(_row([ui.btn_close_pass]))


func _refresh_pass() -> void:
	var tier := Progress.season_tier()
	var month := int(Progress.season.substr(5, 2))
	ui.pass_title.text = L.t("pass_title")
	ui.pass_sub.text = L.t("pass_sub", {"m": L.t("month_%d" % month), "n": tier, "max": Progress.PASS_TIERS})
	var in_tier := Progress.season_xp - tier * Progress.XP_PER_TIER
	ui.pass_bar.max_value = Progress.XP_PER_TIER
	ui.pass_bar.value = Progress.XP_PER_TIER if tier >= Progress.PASS_TIERS else in_tier
	ui.pass_xp.text = L.t("pass_max") if tier >= Progress.PASS_TIERS else "%d/%d" % [in_tier, Progress.XP_PER_TIER]
	var list: VBoxContainer = ui.pass_list
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for t in range(1, Progress.PASS_TIERS + 1):
		var r := Progress.pass_reward(t)
		if not Progress.COSMETICS_ENABLED and r.kind == "look":
			if t in Progress.season_claimed or not Progress.owns(int(r.n)):
				continue  # Earned new packs are banked silently; no cosmetic-only controls.
			r = {"kind": "crystals", "n": 200}  # Existing duplicate-pack compensation.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var num := _label(str(t), f_display, 20, BRASS if t <= tier else MUTED)
		num.custom_minimum_size.x = 34
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(num)
		var pic: Control
		var text := ""
		match str(r.kind):
			"crystals":
				pic = _icon_tex("crystal", 30, Color("#7fd8ff"))
				text = L.t("pass_crystals", {"n": r.n})
			"hints":
				pic = _icon_tex("hint", 30, BRASS_LIGHT)
				text = L.t("pass_hints", {"n": r.n})
			"look":
				var tr := TextureRect.new()
				tr.texture = load("res://assets/tiles/look_%d_1.png" % int(r.n))
				tr.custom_minimum_size = Vector2(34, 34)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic = tr
				text = L.t("pass_look", {"name": L.t("look_%d" % int(r.n))})
		row.add_child(pic)
		var lbl := _para(text)
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lbl)
		var tt: int = t
		if t in Progress.season_claimed:
			row.add_child(_label("✓", f_bold, 24, Color("#5cc87a")))
		elif Progress.pass_claimable(t):
			var b := _button(L.t("take"), "", true, func():
				var got := Progress.claim_pass(tt)
				if not got.is_empty():
					Sfx.play("star")
					_refresh_pass()
					_refresh_menu_bests())
			b.add_theme_font_size_override("font_size", 15)
			row.add_child(b)
		else:
			row.add_child(_icon_tex("lock", 22, Color(1, 1, 1, 0.3)))
		list.add_child(row)
	_fit_panels.call_deferred()


func _build_stats() -> void:
	var pv := _panel()
	stats_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.stats_title = _label("", f_display, 32, BRASS)
	v.add_child(ui.stats_title)
	ui.stats_list = GridContainer.new()
	ui.stats_list.columns = 2
	ui.stats_list.add_theme_constant_override("h_separation", 16)
	ui.stats_list.add_theme_constant_override("v_separation", 8)
	v.add_child(ui.stats_list)
	ui.btn_close_stats = _button("", "", true, func(): Sfx.play("click"); _show_panel(menu_panel))
	v.add_child(_row([ui.btn_close_stats]))


func _refresh_stats() -> void:
	var grid: GridContainer = ui.stats_list
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var life: Dictionary = Progress.life
	var games := 0
	var fav := ""
	var fav_n := 0
	for id in ["classic", "bright", "zen", "levels", "puzzle"]:
		var n := int(life.get("games_" + id, 0))
		games += n
		if n > fav_n:
			fav_n = n
			fav = id
	var mins := int(life.get("play_secs", 0)) / 60
	var rows := [
		["stat_games", str(games)],
		["stat_fav", L.t("mode_" + fav) if fav != "" else "—"],
		["stat_time", L.t("stat_minutes", {"n": mins})],
		["stat_gems", str(int(life.get("gems", 0)))],
		["stat_boards", str(int(life.get("clear_boards", 0)))],
		["stat_combo", str(int(life.get("max_combo", 0)))],
		["stat_perfects", str(int(life.get("perfects", 0)))],
		["stat_levels", str(Progress.max_unlocked() - 1)],
		["stat_stars", str(Progress.total_stars())],
		["stat_puzzles", str(Progress.puzzles)],
		["stat_dailies", str(int(life.get("dailies", 0)))],
		["stat_best", str(maxi(Save.best, maxi(Save.best_bright, Save.best_zen)))],
	]
	for r in rows:
		var k := _label(L.t(r[0]), f_body, 18, MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var val := _label(r[1], f_num, 19, CREAM)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)


## "Leave the game?" before a running game is thrown away.
func _build_confirm() -> void:
	var pv := _panel()
	confirm_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.confirm_title = _label("", f_display, 32, BRASS)
	ui.confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ui.confirm_title)
	ui.confirm_line = _para("")
	ui.confirm_line.add_theme_color_override("font_color", MUTED)
	ui.confirm_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ui.confirm_line)
	ui.btn_leave = _button("", "door", false, func(): Sfx.play("click"); go_menu())
	ui.btn_stay = _button("", "play", true, func(): Sfx.play("click"); _show_panel(pause_panel))
	v.add_child(_row([ui.btn_stay, ui.btn_leave]))


func _refresh_menu_bests() -> void:
	ui.home_best.text = L.t("best") + ": " + str(Save.best_for(_menu_mode()))
	ui.home_crystals.text = str(Progress.crystals)
	var due := Progress.unclaimed()
	(ui.home_tasks.get_meta("caption") as Label).text = L.t("tasks") + (" (%d)" % due if due > 0 else "")
	for id in ["classic", "levels", "bright", "zen", "puzzle"]:
		var line := L.t("best") + ": " + str(Save.best_for(id))
		if id == "levels":
			line = L.t("stars_total") + ": " + str(Progress.total_stars())
		elif id == "puzzle":
			line = L.t("puzzles_solved", {"n": Progress.puzzles})
		ui["card_best_" + id].text = line
	(ui.home_gift.get_meta("caption") as Label).text = L.t("gift") + (" !" if Progress.gift_ready() else "")
	var adue := Progress.achievements_due()
	(ui.home_ach.get_meta("caption") as Label).text = L.t("achievements") + (" (%d)" % adue if adue > 0 else "")
	var pdue := Progress.pass_due()
	(ui.home_pass.get_meta("caption") as Label).text = L.t("pass") + (" (%d)" % pdue if pdue > 0 else "")
	if Progress.daily_reward_ready():
		ui.daily_card.text = L.t("daily_card", {"n": Progress.DAILY_CRYSTALS})
	else:
		ui.daily_card.text = L.t("daily_card_done", {"n": Save.daily_best_for(_today())})


## How to play: a few short pages turned with the arrows or a swipe.
const RULE_PAGES := [
	{"icon": "hand", "keys": ["rule1", "rule2"]},
	{"icon": "star", "keys": ["rule3", "rule4"], "pay": ["pay2", "pay3", "pay4", "pay_combo", "pay_precise"]},
	{"icon": "map", "keys": ["rule_bright"]},
	{"icon": "puzzle", "special": true},
	{"icon": "calendar", "keys": ["rule5", "rule_daily", "rule_pass"], "pay": ["pay_shine"]},
]
const SPECIALS := ["joker", "box", "chain", "ice", "bomb", "chameleon"]


func _build_rules() -> void:
	var pv := _panel()
	rules_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.how = _label("", f_display, 36, BRASS)
	v.add_child(ui.how)
	var holder := VBoxContainer.new()
	holder.custom_minimum_size.y = 330
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.rules_pages = []
	for pi in RULE_PAGES.size():
		var page_def: Dictionary = RULE_PAGES[pi]
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(_icon_tex(page_def.icon, 30, BRASS))
		ui["rp_%d" % pi] = _label("", f_display, 24, BRASS_LIGHT)
		head.add_child(ui["rp_%d" % pi])
		page.add_child(head)
		for k in page_def.get("keys", []):
			ui[k] = _para("")
			ui[k].add_theme_font_size_override("font_size", 18)
			page.add_child(ui[k])
		if page_def.get("pay", []).size() > 0:
			var pay := VBoxContainer.new()
			pay.add_theme_constant_override("separation", 4)
			for k in page_def.pay:
				ui[k] = _label("", f_num, 16, BRASS_LIGHT)
				ui[k].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				pay.add_child(ui[k])
			page.add_child(pay)
		if page_def.get("special", false):
			for sp in SPECIALS:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 12)
				row.add_child(_special_icon(sp))
				ui["sp_" + sp] = _para("")
				ui["sp_" + sp].add_theme_font_size_override("font_size", 16)
				ui["sp_" + sp].size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(ui["sp_" + sp])
				page.add_child(row)
		holder.add_child(page)
		ui.rules_pages.append(page)
	v.add_child(holder)
	# swipe left / right to turn the page
	holder.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				holder.set_meta("x", ev.position.x)
			elif holder.has_meta("x"):
				var dx: float = ev.position.x - float(holder.get_meta("x"))
				holder.remove_meta("x")
				if absf(dx) > 50.0:
					_set_rules_page(rules_page + (1 if dx < 0 else -1)))
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	ui.rules_prev = _icon_button("prev", func(): Sfx.play("click"); _set_rules_page(rules_page - 1))
	ui.rules_next = _icon_button("next", func(): Sfx.play("click"); _set_rules_page(rules_page + 1))
	ui.rules_dots = HBoxContainer.new()
	ui.rules_dots.add_theme_constant_override("separation", 8)
	ui.rules_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for pi in RULE_PAGES.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		ui.rules_dots.add_child(dot)
	nav.add_child(ui.rules_prev)
	nav.add_child(ui.rules_dots)
	nav.add_child(ui.rules_next)
	v.add_child(nav)
	ui.btn_close_rules = _button("", "", true, func(): Sfx.play("click"); _show_panel(menu_panel))
	ui.btn_tutorial = _button("", "hand", false, func(): Sfx.play("click"); start_game("tutorial"))
	v.add_child(_row([ui.btn_tutorial, ui.btn_close_rules]))
	_set_rules_page(0)


## A small picture of a special gem for the rules: a tile with its overlay.
func _special_icon(sp: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(40, 40)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var base := TextureRect.new()
	base.texture = load("res://assets/tiles/joker.png") if sp == "joker" else load("res://assets/tiles/look_0_1.png")
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.add_child(base)
	var over := {"box": "res://assets/tiles/box.png", "ice": "res://assets/tiles/ice.png", "chameleon": "res://assets/tiles/chameleon.png"}
	if over.has(sp):
		var o := TextureRect.new()
		o.texture = load(over[sp])
		o.set_anchors_preset(Control.PRESET_FULL_RECT)
		o.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.add_child(o)
	elif sp == "bomb":
		var o := TextureRect.new()
		o.texture = load("res://assets/tiles/bomb.png")
		o.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		o.position = Vector2(20, -4)
		o.size = Vector2(24, 24)
		c.add_child(o)
	elif sp == "chain":
		var badge := Panel.new()  # the white link glyph on a dark disc, like on the board
		badge.add_theme_stylebox_override("panel", _box(Color(0.15, 0.12, 0.3, 0.9), Color(1, 1, 1, 0.6), 1, 11, Vector4.ZERO))
		badge.position = Vector2(20, -4)
		badge.size = Vector2(22, 22)
		var o := TextureRect.new()
		o.texture = ICONS["link"]
		o.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		o.position = Vector2(3, 3)
		o.size = Vector2(16, 16)
		badge.add_child(o)
		c.add_child(badge)
	return c


func _set_rules_page(i: int) -> void:
	rules_page = clampi(i, 0, RULE_PAGES.size() - 1)
	for pi in ui.rules_pages.size():
		ui.rules_pages[pi].visible = pi == rules_page
	ui.rules_prev.disabled = rules_page == 0
	ui.rules_next.disabled = rules_page == RULE_PAGES.size() - 1
	for pi in ui.rules_dots.get_child_count():
		var dot: Panel = ui.rules_dots.get_child(pi)
		dot.add_theme_stylebox_override("panel", _box(BRASS if pi == rules_page else Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0, 5, Vector4.ZERO))


func _show_rules() -> void:
	_set_rules_page(0)
	_show_panel(rules_panel)


func _build_pause() -> void:
	var pv := _panel()
	pause_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.pause_title = _label("", f_display, 40, BRASS)
	v.add_child(ui.pause_title)
	ui.btn_resume = _button("", "play", true, func(): Sfx.play("click"); _resume_play())
	ui.btn_menu_pause = _button("", "home", false, _ask_leave)
	ui.btn_settings_pause = _icon_button("settings", func(): _open_settings(pause_panel))
	v.add_child(_row([ui.btn_resume, ui.btn_menu_pause, ui.btn_settings_pause]))


func _build_over() -> void:
	var pv := _panel()
	over_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.over_title = _label("", f_display, 40, BRASS)
	ui.over_score = _label("0", f_num, 72)
	ui.over_best = _label("", f_bold, 22, BRASS_LIGHT)
	ui.over_line = _para("")
	ui.over_line.add_theme_color_override("font_color", MUTED)
	v.add_child(ui.over_title)
	v.add_child(ui.over_score)
	v.add_child(ui.over_best)
	v.add_child(ui.over_line)
	ui.over_reward = _label("", f_bold, 20, Color("#7fd8ff"))
	ui.over_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ui.over_reward)
	ui.best_box = VBoxContainer.new()
	ui.best_box.add_theme_constant_override("separation", 2)
	ui.best_caption = _label("", f_bold, 15, MUTED)
	ui.best_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.best_view = StrikeReplay.new()
	ui.best_view.custom_minimum_size = Vector2(220, 180)
	ui.best_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ui.best_box.add_child(ui.best_caption)
	ui.best_box.add_child(ui.best_view)
	v.add_child(ui.best_box)
	ui.btn_double = _button("", "video", false, _on_double)
	v.add_child(ui.btn_double)
	ui.btn_continue = _button("", "video", false, _on_continue)
	v.add_child(ui.btn_continue)
	ui.btn_shuffle = _button("", "shuffle", false, _on_shuffle)
	v.add_child(ui.btn_shuffle)
	ui.btn_again = _button("", "restart", true, _on_again)
	ui.btn_leaders_over = _button("", "trophy", false, func(): _open_leaders(over_panel))
	ui.btn_menu_over = _button("", "home", false, func(): Sfx.play("click"); go_menu())
	v.add_child(_row([ui.btn_again, ui.btn_leaders_over, ui.btn_menu_over]))


func _build_leaders() -> void:
	var pv := _panel()
	leaders_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.leaders_title = _label("", f_display, 36, BRASS)
	v.add_child(ui.leaders_title)
	_build_leader_tabs(v)
	ui.leaders_status = _para("")
	ui.leaders_status.add_theme_color_override("font_color", MUTED)
	v.add_child(ui.leaders_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 0
	ui.leaders_scroll = scroll
	drag_scrolls.append(scroll)
	ui.leaders_list = VBoxContainer.new()
	ui.leaders_list.add_theme_constant_override("separation", 6)
	ui.leaders_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ui.leaders_list)
	v.add_child(scroll)
	ui.btn_login = _button("", "", false, _on_login)
	ui.btn_login.visible = false
	v.add_child(ui.btn_login)
	ui.btn_close_leaders = _button("", "", true, func(): Sfx.play("click"); _show_panel(leaders_return))
	v.add_child(_row([ui.btn_close_leaders]))


func _build_settings() -> void:
	var pv := _panel()
	settings_panel = pv[0]
	var v: VBoxContainer = pv[1]
	ui.settings_title = _label("", f_display, 36, BRASS)
	v.add_child(ui.settings_title)
	ui.chk_sound = _check(Save.sound, func(on: bool):
		Save.sound = on
		Save.store()
		Sfx.play("click"))
	ui.sld_sound = _slider(Save.sound_volume, func(x: float):
		Save.sound_volume = x, func(): Save.store(); Sfx.play("knock3"))
	v.add_child(_setting_row(ui.chk_sound, ui.sld_sound))
	ui.chk_music = _check(Save.music, func(on: bool):
		Save.music = on
		Save.store()
		Sfx.play("click")
		Sfx.update_music())
	ui.sld_music = _slider(Save.music_volume, func(x: float):
		Save.music_volume = x
		Sfx.apply_volumes()
		Sfx.update_music(), func(): Save.store())
	v.add_child(_setting_row(ui.chk_music, ui.sld_music))
	ui.chk_voice = _check(Save.voice, func(on: bool):
		Save.voice = on
		Save.store()
		Sfx.voice("great"))
	v.add_child(ui.chk_voice)
	ui.chk_voice.visible = Sfx.ANNOUNCER_ENABLED
	ui.chk_vibration = _check(Save.vibration, func(on: bool):
		Save.vibration = on
		Save.store()
		Haptics.buzz("test"))
	ui.chk_vibration.visible = Haptics.available() or OS.is_debug_build()
	v.add_child(ui.chk_vibration)
	ui.btn_settings_done = _button("", "", true, func(): Sfx.play("click"); _close_settings())
	v.add_child(_row([ui.btn_settings_done]))
	ui.scale_info = _label("", f_num, 12, MUTED)
	ui.scale_info.visible = OS.is_debug_build()
	v.add_child(ui.scale_info)


func _check(on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.toggled.connect(cb)
	return c


func _slider(value: float, on_change: Callable, on_release: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(150, 36)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(on_change)
	s.drag_ended.connect(func(_changed: bool): on_release.call())
	return s


func _setting_row(check: CheckButton, slider: HSlider) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 14)
	r.add_child(check)
	r.add_child(slider)
	return r


func _open_settings(from: Control) -> void:
	Sfx.play("click")
	settings_return = from
	ui.chk_sound.set_pressed_no_signal(Save.sound)
	ui.chk_music.set_pressed_no_signal(Save.music)
	ui.chk_vibration.set_pressed_no_signal(Save.vibration)
	ui.chk_voice.set_pressed_no_signal(Save.voice)
	ui.sld_sound.set_value_no_signal(Save.sound_volume)
	ui.sld_music.set_value_no_signal(Save.music_volume)
	var vs := get_viewport_rect().size
	ui.scale_info.text = "%s, view %dx%d" % [ui_scale_info, int(vs.x), int(vs.y)]
	_show_panel(settings_panel)


func _open_settings_from_hud() -> void:
	settings_from_game = state == State.PLAYING
	if settings_from_game:
		state = State.PAUSED
		board.interactive = false
		Yandex.gameplay(false)
	_open_settings(_current_panel())


func _close_settings() -> void:
	if settings_from_game:
		settings_from_game = false
		Sfx.play("click")
		_resume_play()
		return
	_show_panel(settings_return)


func _current_panel() -> Control:
	for p in [menu_panel, mode_panel, pause_panel, over_panel, leaders_panel, rules_panel, map_panel, level_panel, tasks_panel, collection_panel, gift_panel, ach_panel, pass_panel, stats_panel, confirm_panel]:
		if p.visible:
			return p
	return null


func _center_panel_headings() -> void:
	for l in [ui.menu_title, ui.menu_tag, ui.pause_title, ui.over_title, ui.over_score, ui.over_best, ui.over_line,
			ui.leaders_title, ui.settings_title, ui.how]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _apply_texts() -> void:
	title_label.text = L.t("title")
	time_caption.text = L.t("time")
	score_caption.text = L.t("score")
	best_caption.text = L.t("best")
	for key in hud_sets.classic_android.captions:
		hud_sets.classic_android.captions[key].text = L.t(key)
	ui.run_score_caption.text = L.t("score")
	ui.run_best_caption.text = L.t("best")
	ui.run_time_caption.text = L.t("time")
	ui.menu_title.text = L.t("title")
	ui.menu_tag.text = L.t("tagline")
	ui.how.text = L.t("how_title")
	for k in ["rule1", "rule2", "rule3", "rule4", "rule5", "rule_bright", "rule_daily", "rule_pass", "pay2", "pay3", "pay4", "pay_combo", "pay_precise", "pay_shine"]:
		ui[k].text = L.t(k)
	for pi in RULE_PAGES.size():
		ui["rp_%d" % pi].text = L.t("rp_%d" % pi)
	for sp in SPECIALS:
		ui["sp_" + sp].text = L.t("sp_" + sp)
	ui.btn_close_pass.text = L.t("close")
	ui.btn_close_stats.text = L.t("close")
	ui.stats_title.text = L.t("stats_title")
	ui.confirm_title.text = L.t("leave_title")
	ui.confirm_line.text = L.t("leave_line")
	ui.btn_leave.text = L.t("leave")
	ui.btn_stay.text = L.t("stay")
	ui.btn_home_play.text = L.t("play")
	ui.mode_title.text = L.t("choose_mode")
	for id in ["classic", "levels", "bright", "zen", "puzzle"]:
		ui["card_name_" + id].text = L.t("mode_" + id)
		ui["card_desc_" + id].text = L.t("mode_%s_desc" % id)
		ui["card_play_" + id].text = L.t("open_map" if id == "levels" or id == "puzzle" else "play")
	ui.map_title.text = L.t("mode_levels")
	ui.level_next.text = L.t("next")
	ui.level_retry.text = L.t("again")
	ui.level_map.text = L.t("map")
	ui.tasks_title.text = L.t("tasks")
	ui.btn_close_tasks.text = L.t("close")
	ui.coll_title.text = L.t("collection")
	ui.coll_hint.text = L.t("collection_hint")
	ui.btn_close_coll.text = L.t("close")
	ui.btn_tutorial.text = L.t("tutorial")
	ui.gift_title.text = L.t("gift_title")
	ui.btn_close_gift.text = L.t("close")
	ui.ach_title.text = L.t("achievements")
	ui.btn_close_ach.text = L.t("close")
	for k in ["score", "score_bright", "score_zen", "stars"]:
		ui["lb_tab_" + k].text = L.t("lb_" + k)
	for pair in [[ui.home_leaders, "leaders"], [ui.home_pass, "pass"], [ui.home_stats, "stats_title"], [ui.home_rules, "how_title"], [ui.home_settings, "settings"],
			[ui.home_tasks, "tasks"], [ui.home_coll, "collection"], [ui.home_gift, "gift"], [ui.home_ach, "achievements"]]:
		(pair[0].get_meta("caption") as Label).text = L.t(pair[1])
	_refresh_menu_bests()
	ui.btn_close_rules.text = L.t("close")
	ui.btn_shuffle.text = L.t("shuffle_ad")
	ui.pause_title.text = L.t("paused")
	ui.btn_resume.text = L.t("resume")
	ui.btn_menu_pause.text = L.t("menu")
	ui.over_best.text = L.t("new_best")
	ui.btn_continue.text = L.t("continue_ad")
	ui.btn_again.text = L.t("again")
	ui.btn_leaders_over.text = L.t("leaders")
	ui.btn_menu_over.text = L.t("menu")
	ui.leaders_title.text = L.t("leaders")
	ui.btn_login.text = L.t("login")
	ui.btn_close_leaders.text = L.t("close")
	ui.settings_title.text = L.t("settings")
	ui.chk_sound.text = L.t("sounds")
	ui.chk_music.text = L.t("music_opt")
	ui.chk_vibration.text = L.t("vibration")
	ui.chk_voice.text = L.t("voice")
	ui.btn_settings_done.text = L.t("done")
	ui.rotate_label.text = L.t("rotate")
	_fit_panels.call_deferred()


## Little scale bump for HUD numbers.
func _pop(c: Control, k := 1.25) -> void:
	c.pivot_offset = Vector2(0, c.size.y / 2)
	c.scale = Vector2.ONE * k
	create_tween().tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_panel(p: Control) -> void:
	if p == collection_panel and not Progress.COSMETICS_ENABLED:
		p = menu_panel  # Also closes debug/deep-link routes to the dormant shop.
	tut_hand.visible = p == null and mode.kind == "tutorial" and tut_step < TUT_MOVES.size()
	var was_dim := dim.visible
	var menu_surface := p == menu_panel or p == mode_panel
	if menu_surface:
		board.reset_run_surface()
		ambient.reset_velvet_palette()
	ambient.set_skin("classic" if menu_surface else (mode.skin if state == State.MENU else ("classic" if visual_profile == "classic_run" else visual_profile)))
	if p == menu_panel or p == mode_panel:
		_set_orientation(false)
	var on_menu := p == menu_panel or p == mode_panel or p == map_panel
	if on_menu:
		_refresh_menu_bests()
	# the game layer stays out of sight behind the menus and anything opened from them
	margin.visible = not on_menu and state != State.MENU
	for x in [menu_panel, mode_panel, pause_panel, over_panel, leaders_panel, settings_panel, rules_panel, map_panel, level_panel, tasks_panel, collection_panel, gift_panel, ach_panel, pass_panel, stats_panel, confirm_panel]:
		x.visible = x == p
	dim.visible = p != null and not menu_surface
	btn_pause.disabled = state != State.PLAYING
	btn_restart.disabled = state != State.PLAYING and state != State.PAUSED
	if p:
		# fade and grow in; the dim layer only fades when it was hidden before
		if not was_dim:
			dim.modulate.a = 0.0
			create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
		p.modulate.a = 0.0
		p.scale = Vector2.ONE * 0.94
		await get_tree().process_frame  # let wrapped text settle so the panel's height is real
		if not p.visible:
			return
		_fit_panels()
		p.pivot_offset = p.size / 2
		var fit := _panel_fit(p)
		p.scale = Vector2.ONE * fit * 0.94
		var tw := create_tween().set_parallel()
		tw.tween_property(p, "modulate:a", 1.0, 0.18)
		tw.tween_property(p, "scale", Vector2.ONE * fit, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var first: Button = ui.get("card_play_" + _menu_mode()) if p == mode_panel else _first_button(p)
		if first:
			first.grab_focus.call_deferred()


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and c.visible:
			return c
		var b := _first_button(c)
		if b:
			return b
	return null


func _update_hud() -> void:
	_update_bonus_progress()
	var secs := int(ceil(time_left))
	time_label.text = str(secs)
	if mode.kind == "zen":
		time_label.text = L.t("steps_n", {"n": maxi(strikes, 0)})
	elif mode.kind == "puzzle":
		time_label.text = L.t("moves_left", {"n": maxi(strikes, 0)})
	elif mode.kind == "tutorial":
		time_label.text = ""
	var low := state == State.PLAYING and secs <= 15
	time_label.add_theme_color_override("font_color", DANGER if low else CREAM)
	time_bar.add_theme_stylebox_override("fill", bar_fill_low if low else bar_fill)
	time_bar.value = clampf(time_left / START_TIME, 0.0, 1.0) * 100.0
	if mode.kind == "zen" or mode.kind == "puzzle":
		time_bar.value = clampf(float(strikes) / strikes_max, 0.0, 1.0) * 100.0
	elif mode.kind == "tutorial":
		time_bar.value = 100.0
	elif mode.kind == "levels":
		time_bar.value = clampf(time_left / _level_time(level_n), 0.0, 1.0) * 100.0
	_set_hud_number(best_label, maxi(Save.best_for(mode.id), score))
	if level_label:
		level_label.text = "· " + L.t("level_short", {"n": _level()})
		level_label.visible = mode.kind == "levels" or mode.kind == "zen" or mode.kind == "puzzle"
		if goal_kind >= 0:
			level_label.text += "  ·  " + L.t("goal_left", {"n": logic.count_kind(goal_kind)})
	btn_pause.disabled = state != State.PLAYING
	btn_restart.disabled = state != State.PLAYING and state != State.PAUSED
	# the hint button shows an ad badge once the free hint and the spare ones are used up
	btn_hint.icon = ICONS["hint" if hints > 0 or Progress.hint_tokens > 0 else "video"]
	btn_hint.text = str(Progress.hint_tokens) if hints <= 0 and Progress.hint_tokens > 0 else ""


func _flash_delta(text: String, negative: bool, unit := "time") -> void:
	if unit == "steps":
		time_delta.text = text + " " + L.t("steps_unit")
	else:
		time_delta.text = text + (" с" if L.lang == "ru" else (" sn" if L.lang == "tr" else " s"))
	time_delta.add_theme_color_override("font_color", DANGER if negative else BRASS)
	time_delta.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(time_delta, "modulate:a", 0.0, 0.4)


func _toast(text: String) -> void:
	toast.text = text
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(toast, "modulate:a", 0.0, 0.3)


# ================= combo UI =================

func _update_bonus_progress() -> void:
	var active: bool = keeper.classic_bonus_combos and mode.id == "classic" and keeper.color_streak_hits >= 2 \
		and state in [State.PLAYING, State.PAUSED]
	for id in ["classic", "classic_android"]:
		if not hud_sets.has(id) or not hud_sets[id].has("bonus"):
			continue
		var widgets: Dictionary = hud_sets[id].bonus
		widgets.progress.modulate.a = 1.0 if active and keeper.color_streak_kind >= 0 else 0.0
		if id == "classic_android":
			widgets.progress.visible = active and keeper.color_streak_kind >= 0
		if keeper.color_streak_kind >= 0 and keeper.color_streak_kind < BoardView.GEM_TEX.size():
			widgets.gem.texture = BoardView.GEM_TEX[keeper.color_streak_kind]
		widgets.count.text = ("×%d\n%s" % [keeper.color_streak_hits, L.t("color_streak_chain")]) if active else ""


func _show_bonus_feedback(res: Dictionary) -> void:
	if not keeper.classic_bonus_combos:
		return
	for id in ["classic", "classic_android"]:
		var widgets: Dictionary = hud_sets[id].bonus
		if int(res.color_streak_points) > 0:
			# Continuation pulses the count without expanding into the board or repeating a banner.
			var count: Label = widgets.count
			var previous_pulse: Tween = count.get_meta("color_chain_tween") if count.has_meta("color_chain_tween") else null
			if previous_pulse and previous_pulse.is_valid():
				previous_pulse.kill()
			count.modulate = Color(1.4, 1.4, 1.4)
			var pulse := create_tween()
			pulse.tween_property(count, "modulate", Color.WHITE, 0.2)
			count.set_meta("color_chain_tween", pulse)
		for event in ["double_hit", "color_streak"]:
			if event == "color_streak" and not bool(res.color_streak_started):
				continue
			if int(res[event + "_points"]) > 0:
				var label: Label = widgets[event]
				var previous: Tween = label.get_meta("bonus_tween") if label.has_meta("bonus_tween") else null
				if previous and previous.is_valid():
					previous.kill()
				label.modulate.a = 1.0
				label.visible = true
				if id != "classic_android" or event == "color_streak":
					widgets.events.visible = true
				var tw := create_tween()
				tw.tween_interval(0.8)
				tw.tween_property(label, "modulate:a", 0.0, 0.25)
				if id == "classic_android":
					tw.tween_callback(func():
						label.visible = false
						if event == "color_streak":
							widgets.events.visible = false)
				label.set_meta("bonus_tween", tw)


func _reset_bonus_feedback() -> void:
	keeper.reset_bonus_combos()
	for id in ["classic", "classic_android"]:
		if not hud_sets.has(id) or not hud_sets[id].has("bonus"):
			continue
		var widgets: Dictionary = hud_sets[id].bonus
		widgets.progress.modulate.a = 0.0
		var count: Label = widgets.count
		var pulse: Tween = count.get_meta("color_chain_tween") if count.has_meta("color_chain_tween") else null
		if pulse and pulse.is_valid():
			pulse.kill()
		count.modulate = Color.WHITE
		count.text = ""
		if id == "classic_android":
			widgets.progress.visible = false
			widgets.events.visible = false
		for event in ["double_hit", "color_streak"]:
			var label: Label = widgets[event]
			var previous: Tween = label.get_meta("bonus_tween") if label.has_meta("bonus_tween") else null
			if previous and previous.is_valid():
				previous.kill()
			label.modulate.a = 0.0
			if id == "classic_android":
				label.visible = false


func _update_combo_widget(pulse := false) -> void:
	combo_bar.value = keeper.window_left(play_time) / keeper.combo_window * 100.0
	var c := keeper.combo
	if c < 2:
		combo_box.modulate.a = 0.0
		return
	var m := ScoreKeeper.multiplier_for(c)
	combo_count.text = L.t("combo_count", {"n": c})
	if visual_profile in ["classic", "classic_run"]:
		combo_mult.text = ("×%d" % m) if mode.id == "classic" else ("×%d · %d" % [m, c])
		combo_mult.add_theme_color_override("font_color", COMBO_COLORS[clampi(m, 1, 4) - 1].lightened(0.3))
	else:
		combo_mult.text = "%s ×%d · %d" % [L.t("combo").to_upper(), m, c]
		combo_style.bg_color = COMBO_COLORS[clampi(m, 1, 4) - 1]
	combo_box.modulate.a = 1.0
	if pulse and _classic_android_sides():
		# Pulse colour without expanding the rail into the board or a display cutout.
		combo_mult.modulate = Color(1.3, 1.3, 1.3)
		create_tween().tween_property(combo_mult, "modulate", Color.WHITE, 0.3)
	elif pulse:
		combo_box.pivot_offset = combo_box.size / 2
		combo_box.scale = Vector2.ONE * 1.35
		create_tween().tween_property(combo_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _combo_break() -> void:
	if mode.skin == "bright":
		Sfx.play("combo_break", 1.0, -6.0)
	var tw := create_tween()
	tw.tween_property(combo_box, "modulate:a", 0.0, 0.35)


func _banner(title: String, pts: int, secs: float, color: Color, sub := "") -> void:
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", color)
	if sub != "":
		banner_sub.text = sub
	elif secs <= 0.0 or not keeper.time_bonuses:
		banner_sub.text = L.t("points_only", {"p": pts}) if pts > 0 else ""
	else:
		banner_sub.text = L.t("bonus_line", {"p": pts, "s": int(secs)})
	var vs := get_viewport_rect().size
	banner_title.add_theme_font_size_override("font_size", int(clampf(vs.x / 13.0, 34.0, 64.0)))
	banner_box.pivot_offset = banner_box.size / 2
	banner_box.scale = Vector2.ONE * 0.4
	banner_box.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(banner_box, "scale", Vector2.ONE * 1.08, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner_box, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.9)
	tw.parallel().tween_property(banner_box, "position:y", banner_box.position.y - 30, 1.3)
	tw.tween_property(banner_box, "modulate:a", 0.0, 0.35)


# ================= layout =================

## Board shape for the current screen: wide screens get 23x15, tall ones 15x23.
## Board shape for the free space under the HUD: tall phones get tall boards, wide screens wide ones.
func _dims() -> Vector2i:
	if mode.id == "classic" and (not _is_touch_device() or OS.has_feature("android") or _classic_android_sides()):
		return Vector2i(mode.cols, mode.rows)  # the original wide board (desktop, Android turned sideways)
	var slots: int = mode.slots
	if mode.kind == "run":
		slots = 200
	elif mode.skin == "bright":
		slots = BoardLogic.bright_level(_level()).slots
	return BoardLogic.best_dims(_board_area(), slots)


func _board_area() -> Vector2:
	var a := board.size - Vector2.ONE * board.frame_pad * 2.0
	if a.x < 50.0 or a.y < 50.0:
		a = get_viewport_rect().size - Vector2(32, 200)
	return a


## Fit the board to its area. Before a game starts the board is re-dealt in the best shape;
## during a game it is only transposed (when that shape fits better) or rescaled.
func _relayout_board() -> void:
	if mode.id == "bright" and (_run_starting or _run_dims != Vector2i.ZERO):
		# Resize the rendering only; never regenerate or transpose an active run.
		board.refresh()
		return
	var d := _dims()
	if Vector2i(logic.cols, logic.rows) != d:
		if state == State.MENU:
			_deal_board()
			board.clear_fx()
		elif Vector2i(logic.rows, logic.cols) == d:
			logic.transpose()
			keeper.transpose_bonus_slot()
			board.transposed()
	# a board dealt before the screen turned (Android leaving a sideways classic game) gets
	# turned to match: a tall screen gets a tall board, a wide one a wide board
	var area := get_viewport_rect().size  # the screen itself; the board may not have caught up yet
	var screen_tall := area.y > area.x * 1.15
	var screen_wide := area.x > area.y * 1.15
	if (screen_tall and logic.cols > logic.rows) or (screen_wide and logic.rows > logic.cols):
		if not (mode.id == "classic" and (not _is_touch_device() or _classic_android_sides())):
			logic.transpose()
			keeper.transpose_bonus_slot()
			board.transposed()
	board.refresh()


func _on_viewport_resized() -> void:
	var s := get_viewport_rect().size
	var turn := _is_touch_device() and s.x > s.y * 1.05 and not OS.has_feature("android")
	rotate_overlay.visible = turn
	if turn:
		pause_game()
	compact = s.x < 640 or s.y < 600
	title_label.visible = s.x >= 980 and not _classic_android_sides()
	hud_classic.add_theme_constant_override("separation", 10 if compact else 18)
	var sides := _classic_android_sides()
	var m := 4 if sides else (6 if compact else 16)
	var inset := _safe_insets()
	var rounded := Rect2(inset.position.ceil(), inset.size.ceil()) if sides else inset
	if sides:
		var vertical_inset := maxf(rounded.position.y,rounded.size.y)
		rounded = Rect2(0.0,vertical_inset,0.0,vertical_inset)
	margin.add_theme_constant_override("margin_left", m + int(rounded.position.x))
	margin.add_theme_constant_override("margin_top", m + int(rounded.position.y))
	margin.add_theme_constant_override("margin_right", m + int(rounded.size.x))
	margin.add_theme_constant_override("margin_bottom", m + int(rounded.size.y))
	hud.add_theme_constant_override("separation", 10 if compact else 22)
	combo_box.custom_minimum_size.x = 64 if sides or compact else 96
	var w := clampf(s.x - (24 if compact else 40), 260, 620)
	for p in [pause_panel, over_panel, leaders_panel, settings_panel, rules_panel, level_panel, tasks_panel, collection_panel,
			gift_panel, ach_panel, pass_panel, stats_panel, confirm_panel]:
		p.custom_minimum_size.x = w
		p.add_theme_stylebox_override("panel", panel_style_compact if compact else panel_style)
	var short := s.y < 600
	ui.menu_title.add_theme_font_size_override("font_size", 36 if short else (40 if s.x < 600 else 58))
	ui.mode_title.add_theme_font_size_override("font_size", 24 if s.x < 440 else 32)
	ui.home_gems[0].get_parent().visible = s.y >= 560
	ui.home_stack.add_theme_constant_override("separation", 8 if short else 16)
	ui.home_stack.custom_minimum_size.x = clampf(s.x - 64, 240, 960)
	ui.daily_card.custom_minimum_size.x = minf(400, s.x - 72)
	ui.btn_home_play.custom_minimum_size = Vector2(260, 60 if short else 68)
	ui.mode_grid.columns = 2 if s.x >= 880 else 1
	for card in ui.mode_cards:
		card.custom_minimum_size.x = 400 if s.x >= 880 else clampf(s.x - 64, 260, 440)
	ui.over_score.add_theme_font_size_override("font_size", 52 if compact else 72)
	board.frame_pad = 3.0 if sides else (5.0 if compact else 10.0)
	if sides:
		_layout_classic_sides(s, inset)
	_relayout_board.call_deferred()
	_fit_panels.call_deferred()


## Scale for a panel that is taller than the screen, so all of it shows (1 when it fits).
func _panel_fit(p: Control) -> float:
	if p == menu_panel or p == mode_panel or p == map_panel:
		return 1.0  # full-screen layouts arrange themselves
	var avail := get_viewport_rect().size.y - (12.0 if compact else 32.0)
	var h := p.size.y
	return clampf(avail / maxf(h, 1.0), 0.5, 1.0)


## Shrink the scrolling middle of tall panels so the whole panel fits the screen.
func _fit_panels() -> void:
	var avail := get_viewport_rect().size.y - (12.0 if compact else 32.0)
	for pair in [[leaders_panel, ui.leaders_scroll, ui.leaders_list], [pass_panel, ui.pass_scroll, ui.pass_list],
			[ach_panel, ui.ach_scroll, ui.ach_list]]:
		var panel: Control = pair[0]
		var scroll: ScrollContainer = pair[1]
		var content: Control = pair[2]
		scroll.custom_minimum_size.y = 0
		var fixed := panel.get_combined_minimum_size().y
		# wrapped text overstates its minimum height until laid out, so prefer the real height
		var want := content.size.y if content.size.y > 0.0 else content.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = clampf(avail - fixed, 80.0, maxf(80.0, want))
	for p in [pause_panel, over_panel, leaders_panel, settings_panel, rules_panel, level_panel, tasks_panel, collection_panel,
			gift_panel, ach_panel, pass_panel, stats_panel, confirm_panel]:
		if p.visible:
			p.pivot_offset = p.size / 2
			p.scale = Vector2.ONE * _panel_fit(p)


## Pick the logical resolution from the kind of device, not from DPI (DPI reports are
## unreliable on some phones and browsers). The short side of the screen always maps to the
## same number of logical pixels, so the UI takes the same share of the screen everywhere:
## phones 480, tablets 600, desktops 720 (and the UI grows with a bigger window).
func _apply_ui_scale() -> void:
	var win := get_window()
	var px := Vector2(win.size)
	if px.x <= 0.0 or px.y <= 0.0:
		return
	var base := 720
	if _is_touch_device():
		var aspect := maxf(px.x, px.y) / minf(px.x, px.y)
		base = 480 if aspect >= 1.6 else 600
	ui_scale_info = "%dx%d px, base %d, touch %s" % [int(px.x), int(px.y), base, _is_touch_device()]
	if win.content_scale_size != Vector2i(base, base):
		win.content_scale_size = Vector2i(base, base)


## Screen areas covered by a camera cutout, rounded corners or the gesture bar, in logical
## pixels: position = (left, top), size = (right, bottom). Only the Android app needs this;
## browsers already keep the page inside the safe area.
func _safe_insets() -> Rect2:
	if not OS.has_feature("android"):
		return Rect2()
	var win := get_window()
	var safe := DisplayServer.get_display_safe_area()
	var screen := Rect2i(win.position, win.size)
	if safe.size.x <= 0 or screen.size.y <= 0:
		return Rect2()
	var k := get_viewport_rect().size.y / float(screen.size.y)
	var left := maxi(0, safe.position.x - screen.position.x)
	var top := maxi(0, safe.position.y - screen.position.y)
	var right := maxi(0, screen.end.x - safe.end.x)
	var bottom := maxi(0, screen.end.y - safe.end.y)
	var kx := get_viewport_rect().size.x / float(screen.size.x) if _classic_android_sides() else k
	return Rect2(left * kx, top * k, right * kx, bottom * k)


func _is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
