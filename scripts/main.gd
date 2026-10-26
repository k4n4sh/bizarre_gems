extends Control

const ComboExperiment = preload("res://scripts/combo_experiment.gd")
## The game: rules of play, the flow between screens, ads and leaderboards.
##
## Layout lives in scenes: scenes/main.tscn (this node), the screens in scenes/ui/, the HUDs in
## scenes/game/. Screens report what the player pressed through signals (see Screen); this
## script decides what happens and opens the next screen with show_screen().

enum State { MENU, PLAYING, PAUSED, OVER }

const TutorialLessons = preload("res://scripts/tutorial_lessons.gd")
const TutorialController = preload("res://scripts/tutorial_controller.gd")
var _ab_active := false
var _ab_reported := true
var _ab_run := {}
var _ab_result_index := 0
var _ab_receipts: Array = []
var last_combo_report := {}

const MENU_MODES := ["classic", "bright"]

const START_TIME := 120.0
const CONTINUE_TIME := 15.0
const HINT_AFTER := 15.0
const WAVE_TIME := 5.0      ## bonus seconds when a fresh board is dealt
const CLEAR_POINTS := 25    ## bonus for knocking out every gem on a board
const CLEAR_TIME := 5.0
const RUN_BOARD_TIME := [40.0, 30.0, 20.0, 10.0]
const RUN_FULL_CLEAR_TIME := 20.0
const RUN_HAZARDS_ENABLED := false
const CHAM_EVERY := 3
const BOMB_TIME := 5.0    ## a bomb going off costs this many seconds (steps mode: 3 steps)
const BOMB_STEPS := 3
const DEFUSE_POINTS := 10
const PENTA := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]  ## combo knocks climb this scale
## false: praise for a new multiplier (x3 "Super", x4 "Wow"); true: the ladder below instead.
const PRAISE_LADDER := true
## Praise climbs a ladder as the combo grows: the combo lengths that earn praise_1, praise_2, ...
## (past the last one, every 5th strike repeats the top word).
const PRAISE_AT := [3, 5, 7, 9, 12, 15]
const PRAISE_COLORS := [Color("#9fe3ff"), Color("#7dff9a"), Color("#ffe066"), Color("#ffad42"), Color("#ff6fb5"), Color("#d79bff")]

## Palettes the screen cycles through on big combos and new boards (background top/bottom).
const SPECIAL_BANNER_SECONDS := 0.75
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

# ---- game state ----
var logic := BoardLogic.new()
var keeper := ScoreKeeper.new()
var rng := RandomNumberGenerator.new()
var mode: Dictionary = BoardLogic.CLASSIC
var visual_profile := "classic"
var state := State.MENU
var daily := false
var daily_run_date := ""  ## UTC date pinned before even the first asynchronous deal.
var _run_dims := Vector2i.ZERO
var _daily_transposed := false
var _run_starting := false
## Challenge links: classic and bright-run boards come from game_seed (one board per wave), and
## "Challenge a friend" shares mode, seed, board shape and score. A game started from such a link
## plays that exact board with the score as its target.
var game_seed := 0
var board_dims := Vector2i.ZERO  ## shape of the dealt board, before any turn to fit the screen
var challenge := {}          ## {"mode", "seed", "dims", "score"} of the game being played, or empty
var pending_challenge := {}  ## the challenge from the launch link, offered on the home screen
var wave := 1
var theme_i := 0
var dealing := false
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
var paid_crystals := 0    ## crystals already paid for this game's score (a continued game pays the rest)
var last_earned := 0      ## crystals paid by the last result screen, for the x2 reward
var best_strike := {}     ## the game's highest-scoring strike, replayed on the result screen
@onready var tutorial = TutorialController.new(self)
var tut_step: int:
	get: return tutorial.tut_step
	set(value): tutorial.tut_step = value
var tut_hits: int:
	get: return tutorial.tut_hits
	set(value): tutorial.tut_hits = value
var tut_waiting: bool:
	get: return tutorial.tut_waiting
	set(value): tutorial.tut_waiting = value
var tut_clock_running: bool:
	get: return tutorial.tut_clock_running
	set(value): tutorial.tut_clock_running = value
var tut_feedback_key: String:
	get: return tutorial.tut_feedback_key
	set(value): tutorial.tut_feedback_key = value
var tut_feedback_args: Dictionary:
	get: return tutorial.tut_feedback_args
	set(value): tutorial.tut_feedback_args = value
var tut_last_result: Dictionary:
	get: return tutorial.tut_last_result
	set(value): tutorial.tut_last_result = value
var shown_score := 0.0
var play_time := 0.0
var time_left := START_TIME
var score := 0
var cleared := 0
var used_continue := false
var used_shuffle := false
var idle := 0.0
var end_reason := ""
var last_tick := -1
var autoplay := false  # debug builds only: plays itself, for testing effects and screenshots
var _auto_t := 0.0
var _stuck_t := 0.0
## Invalidates pending deals, completion animations and ads when their game is left/replaced.
var _game_generation := 0
var _ad_request := 0
var _ad_pending := false
var _hud_safe_poll := 0.0
var best_start := 0        ## the record when this game started: the race the record bar shows
var record_beaten := false
var record_bar: RecordBar
var fly: FlyLayer

# ---- nodes of scenes/main.tscn ----
@onready var ambient: Ambient = $Ambient
@onready var game_layer: MarginContainer = %Game
@onready var board: BoardView = %Board
@onready var huds := {"classic": %HudClassic as Hud, "bright": %HudBright as Hud}
@onready var hud: Hud = %HudClassic  ## the HUD of the current mode
@onready var banner: VBoxContainer = %Banner
@onready var dim: ColorRect = %Dim
@onready var center: CenterContainer = %Center
@onready var toast: Label = %Toast
@onready var practice = %Tutorial
@onready var tut_label: Label = %Tutorial.get_node("Card/Instruction")
@onready var tut_card: VBoxContainer = %Tutorial.get_node("Card")
@onready var tut_panel: PanelContainer = %Tutorial
@onready var tut_next: Button = %Tutorial.get_node("Card/Actions/Next")
@onready var tut_hand: TextureRect = %TutorialHand
@onready var rotate_overlay: ColorRect = %RotateOverlay
# screens (scenes/ui/*.tscn)
@onready var home: Screen = %Home
@onready var modes: Screen = %Modes
@onready var map: Screen = %Map
@onready var pause: Screen = %Pause
@onready var result: Screen = %Result
@onready var level_result: Screen = %LevelResult
@onready var leaders: Screen = %Leaders
@onready var settings: Screen = %Settings
@onready var rules: Screen = %Rules
@onready var tasks: Screen = %Tasks
@onready var collection: Screen = %Collection
@onready var gift: Screen = %Gift
@onready var achievements: Screen = %Achievements
@onready var stats: Screen = %Stats
@onready var more: Screen = %More
@onready var confirm: Screen = %Confirm
## every screen by its name in snake_case ("level_result"), for Screen.navigate
var screens := {}
var leaders_return: Screen
var settings_return: Screen
var settings_from_game := false  ## settings opened mid-game: Done goes straight back to playing

# ---- layout ----
var compact := false
var ui_scale_info := ""
var safe := Rect2()  ## screen insets (cutout, gesture bar) in logical px: position = left/top, size = right/bottom
var panel_scale_tween: Tween  ## the grow-in of the panel being shown; a later re-fit replaces it
## Lists that scroll by dragging anywhere on them (touch screens start drags on buttons).
var drag_scrolls: Array[Node] = []
var _drag: ScrollContainer
var _drag_last := Vector2.ZERO
var _drag_moved := 0.0


func _ready() -> void:
	ComboExperiment.initialize()
	rng.randomize()
	board.number_font = UiKit.NUMBER_FONT
	board.feedback_font = preload("res://ui/fonts/bold.tres")
	board.feedback_exclusion = _feedback_exclusion
	board.logic = logic
	game_layer.get_node("Column").resized.connect(_layout_game)
	record_bar = RecordBar.new()
	board.get_parent().add_child(record_bar)  # placed by the column layout, above the board
	fly = FlyLayer.new()
	add_child(fly)
	move_child(fly, dim.get_index())  # over the board, under the menus
	fly.landed.connect(func(): hud.pop(hud.score_label, 1.2))
	_connect_screens()
	_apply_ui_scale()
	_set_orientation(false)
	get_window().size_changed.connect(_apply_ui_scale)
	get_viewport().size_changed.connect(_on_viewport_resized)
	board.slot_pressed.connect(_on_slot)
	board.resized.connect(func(): _relayout_board.call_deferred())
	Yandex.pause_requested.connect(_on_platform_pause)
	Yandex.resume_requested.connect(_on_platform_resume)
	Save.changed.connect(_update_hud)
	L.language_changed.connect(_on_language_changed)

	_use_mode(str(Save.mode))
	var d := _dims()
	logic.setup(d.x, d.y, rng, mode.shining, mode.kinds, mode.per_kind)
	_on_viewport_resized()
	show_screen(home)
	_update_hud()
	if OS.is_debug_build():
		autoplay = "--autoplay" in OS.get_cmdline_user_args()
		if OS.has_feature("web"):
			autoplay = autoplay or str(JavaScriptBridge.eval("location.search")).contains("autoplay")
	if Yandex.is_ready:
		_on_sdk_ready()
	else:
		Yandex.sdk_ready.connect(_on_sdk_ready, CONNECT_ONE_SHOT)


## Wire every screen's signals to what the game does about them.
func _connect_screens() -> void:
	practice.next_pressed.connect(_tutorial_next)
	practice.retry_pressed.connect(_tutorial_retry)
	practice.skip_pressed.connect(func(): tutorial.leave(true))
	practice.exit_pressed.connect(go_menu)

	# every Screen placed in main.tscn (full-screen ones next to Center, dialogs inside it) is found here
	for n in get_children() + center.get_children():
		if not n is Screen:
			continue
		var sc: Screen = n
		sc.theme = UiKit.menu_theme()
		screens[StringName(sc.name.to_snake_case())] = sc
		sc.navigate.connect(_navigate)
		sc.toast.connect(_toast)
		sc.relayout_requested.connect(func(): if sc.visible: _fit_panels.call_deferred())
		if not sc.full_screen:
			sc.resized.connect(_refit_panel.bind(sc))
	drag_scrolls = find_children("*", "ScrollContainer", true, false)

	for k in huds:
		var h: Hud = huds[k]
		h.pause_pressed.connect(pause_game)
		h.restart_pressed.connect(func(): start_game(mode.id, daily, challenge))
		h.settings_pressed.connect(_open_settings_from_hud)
		h.hint_pressed.connect(_use_hint)

	home.play_pressed.connect(func():
		if not Progress.needs_tutorial():
			show_screen(modes)
		else:
			start_game("tutorial"))
	home.daily_pressed.connect(func(): start_game("bright", true))
	home.challenge_pressed.connect(func(): start_game(str(pending_challenge.mode), false, pending_challenge))
	modes.mode_chosen.connect(func(id: String):
		if id not in MENU_MODES: return
		if id == "levels" or id == "puzzle":
			_open_map("puzzle" if id == "puzzle" else "levels")
		else:
			start_game(id))
	map.level_chosen.connect(start_level)
	map.puzzle_chosen.connect(start_puzzle)
	pause.resume_pressed.connect(_resume_play)
	confirm.leave_pressed.connect(go_menu)
	rules.tutorial_pressed.connect(func(): start_game("tutorial"))
	leaders.login_done.connect(func(): Yandex.submit_score(Save.best_for(mode.id), mode.board))
	result.again_pressed.connect(_on_again)
	result.double_pressed.connect(_on_double)
	result.continue_pressed.connect(_on_continue)
	result.shuffle_pressed.connect(_on_shuffle)
	result.share_pressed.connect(_share_challenge)
	result.menu_pressed.connect(go_menu)
	level_result.next_pressed.connect(func():
		if mode.kind == "puzzle":
			start_puzzle(puzzle_n + 1)
		else:
			start_level(level_n + 1))
	level_result.retry_pressed.connect(func():
		if mode.kind == "puzzle":
			start_puzzle(puzzle_n)
		else:
			start_level(level_n))
	level_result.map_pressed.connect(func(): _open_map("puzzle" if mode.kind == "puzzle" else "levels"))
	level_result.double_pressed.connect(_on_double)
	level_result.continue_pressed.connect(_on_level_continue)


## A screen asked for another one (Screen.navigate).
func _navigate(to: StringName) -> void:
	if to in [&"map", &"puzzle_map", &"levels", &"zen", &"puzzle"]: return
	if to == &"collection" and not Progress.COSMETICS_ENABLED:
		return
	match to:
		&"back":
			_on_back()
		&"settings":
			_open_settings(_current_screen())
		&"leaders":
			_open_leaders(_current_screen())
		&"map":
			_open_map("levels")
		&"puzzle_map":
			_open_map("puzzle")
		_:
			var s: Screen = screens.get(to)
			assert(s != null, "no screen named " + to)
			s.refresh()
			show_screen(s)


## Debug builds: ?start=map|tasks|coll|leaders|settings|more|challenge|pause|over|cover|lres|zen|bright|classic|levelN opens that screen directly.
## ?best=N sets the records first (not saved unless a game beats them), ?t=N the time left.
func _debug_start() -> void:
	if OS.is_debug_build() and ComboExperiment.is_read_only():
		start_game(ComboExperiment.target_mode)
		return
	if not (OS.is_debug_build() and OS.has_feature("web")):
		return
	var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('start') || ''"))
	var fake_best := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('best') || ''"))
	if fake_best != "":  # ?best=N: a record to race (and the near-miss line on the result)
		Save.best = int(fake_best)
		Save.best_bright = int(fake_best)
		Save.best_zen = int(fake_best)
	var direct := {"tasks": &"tasks", "coll": &"collection", "gift": &"gift", "ach": &"achievements", "stats": &"stats",
		"more": &"more", "modes": &"modes"}
	if q in ["map","pmap","zen","puzzle","lres"] or q.begins_with("level"):
		return # Browser URLs cannot expose dormant modes.
	if direct.has(q):
		_navigate(direct[q])
	elif q == "map":
		_open_map()
	elif q == "pmap":
		_open_map("puzzle")
	elif q.begins_with("level"):
		start_level(maxi(1, int(q.substr(5))))
	elif q in ["zen", "bright", "classic", "tutorial"]:
		await start_game(q)
	elif q == "daily":
		await start_game("bright", true)
	elif q == "puzzle":
		start_puzzle(1)
	elif q.begins_with("rules"):
		_navigate(&"rules")
		rules.set_page(int(q.substr(5)))
	elif q == "leaders":
		_open_leaders(home)
	elif q == "settings":
		_open_settings(home)
	elif q == "pause":
		await start_game("bright")
		pause_game()
	elif q == "over":
		await start_game("bright")
		end_game("time")
	elif q == "challenge" and not pending_challenge.is_empty():
		await start_game(str(pending_challenge.mode), false, pending_challenge)
	elif q == "cover":  # classic result with the best-strike replay (the tallest result panel)
		await start_game("classic")
		score = 6
		best_strike = {"points": 6, "n": 4, "mult": 1, "parts": [[Vector2i(0, -2), 0], [Vector2i(0, 3), 0], [Vector2i(-1, 0), 1], [Vector2i(4, 0), 1]]}
		end_game("time")
	elif q == "lres":
		start_level(1)
		_end_level()
	elif q == "leave":
		await start_game("bright")
		pause_game()
		show_screen(confirm)
	var t := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('t') || ''"))
	if t != "" and state == State.PLAYING:
		time_left = float(t)
		strikes = mini(strikes, int(t))


func _on_sdk_ready() -> void:
	L.set_language(Yandex.language())
	Save.sync_cloud()
	Yandex.loading_ready()
	pending_challenge = parse_challenge(Yandex.payload())
	home.challenge = pending_challenge
	if home.visible:
		home.refresh()
	_debug_start.call_deferred()
	Sfx.update_music()


## Texts that are translation keys in the scenes switch by themselves; the ones put together in
## code are rebuilt here.
func _on_language_changed() -> void:
	hud.configure(mode.id,_is_native_android())
	hud.set_combo(keeper.combo)
	var s := _current_screen()
	if s == rules:
		rules.set_page(rules.page)
	elif s and s != result and s != level_result:
		s.refresh()
	_update_hud()
	if mode.kind == "tutorial": tutorial.render()
	_fit_panels.call_deferred()


# ================= game flow =================

func start_game(mode_id := "", is_daily := false, ch := {}) -> void:
	_report_combo_ab("restart")
	_game_generation += 1
	_cancel_ad()
	var generation := _game_generation
	_run_starting = false
	_run_dims = Vector2i.ZERO
	_daily_transposed = false
	board.modulate.a = 1.0
	tut_label.visible = false
	tut_hand.visible = false
	practice.visible = false
	if tutorial: tutorial.tut_clock_running = false
	board.tutorial_focus = Vector2i(-1,-1)
	dealing = false
	daily = is_daily
	daily_run_date = _today() if daily else ""
	challenge = ch.duplicate(true)
	game_seed = int(ch.seed) if not ch.is_empty() else (ComboExperiment.board_seed if ComboExperiment.is_read_only() else int(rng.randi()))
	_use_mode(mode_id if mode_id != "" else str(Save.mode))
	record_bar.visible = mode.kind != "tutorial"  # before any layout: the strip takes room above the board
	if not ComboExperiment.is_read_only() and Save.mode != mode.id and mode.id in ["classic", "bright", "zen", "levels", "puzzle"]:
		Save.mode = mode.id  # the tutorial and the daily challenge don't become "last mode"
		Save.store()
	wave = 1
	if mode.kind == "levels":
		level_n = pending_level
	_set_orientation(mode.id == "classic")
	if mode.kind == "run":
		_run_starting = true
		if state == State.PLAYING:
			Yandex.gameplay(false)
		state = State.PAUSED
		board.interactive = false
		board.modulate.a = 0.0  # Participate in layout without showing the previous game's field.
		score = 0
		shown_score = 0.0
		time_left = START_TIME
		play_time = 0.0
		keeper.reset()
		_update_hud()
		show_screen(null)
		await _wait_run_layout(generation)
		if generation != _game_generation:
			return
		var area := board.size - Vector2.ONE * board.frame_pad * 2.0
		if daily:
			var canonical := BoardLogic.best_dims(Vector2(360, 640), 200)
			_daily_transposed = minf(area.x / canonical.y, area.y / canonical.x) > minf(area.x / canonical.x, area.y / canonical.y)
			_run_dims = Vector2i(canonical.y, canonical.x) if _daily_transposed else canonical
		else:
			_run_dims = challenge.dims if not challenge.is_empty() else BoardLogic.best_dims(area, 200)
		_run_starting = false
		board.modulate.a = 1.0
	_deal_board()
	level_total = logic.gems_left()
	_begin_combo_report()
	_set_theme(Progress.active_look(), true)
	score = 0
	shown_score = 0.0
	keeper.reset()
	var has_race: bool = mode.kind in ["classic", "run"]
	best_start = Save.daily_best_for(daily_run_date) if daily else Save.best_for(mode.id)
	record_beaten = false
	record_bar.setup(best_start if has_race else 0, has_race)
	board.fire = 0
	fly.clear()
	play_time = 0.0
	hud.set_combo(0)
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
	strikes_done = 0
	best_strike = {}
	board.clear_fx()
	board.refresh()
	# The new field can change cols/rows without resizing the Board Control.
	# Fit the HUD to its actual frame, not the previous mode's field used during layout settling.
	_layout_game()
	board.deal_in()
	ambient.pulse(UiKit.BRASS, 0.6)
	Sfx.play("start")
	_resume_play()
	if mode.kind == "levels" and BoardLogic.bright_level(level_n).boss:
		_banner(L.t("boss"), 0, 0.0, Color("#ff9ed2"), L.t("rule_" + str(BoardLogic.bright_level(level_n).rule)))
	elif mode.kind == "tutorial":
		_tutorial_step(0)


## Latch the real container geometry, after layout and Android portrait rotation settle.
## Leaving/restarting a game cancels this pending first deal.
func _wait_run_layout(generation: int) -> void:
	var previous := Vector4.ZERO
	var stable := 0
	while generation == _game_generation:
		await get_tree().process_frame
		if generation != _game_generation:
			return
		var viewport_size := get_viewport_rect().size
		var area := board.size - Vector2.ONE * board.frame_pad * 2.0
		var current := Vector4(viewport_size.x, viewport_size.y, area.x, area.y)
		var portrait_ready := not _is_native_android() or viewport_size.y >= viewport_size.x
		if board.is_visible_in_tree() and area.x >= 50.0 and area.y >= 50.0 and portrait_ready:
			stable = stable + 1 if current.is_equal_approx(previous) else 0
			if stable >= 2:
				return
		else:
			stable = 0
		previous = current


## Switch rules and look: "classic" is the original game, "bright" the toy-style mode.
func _use_mode(id: String) -> void:
	_reset_visual_feedback()
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
	_ab_active = ComboExperiment.is_read_only() and mode.id in ["classic", "bright"]
	_configure_keeper()
	visual_profile = "classic_run" if mode.id in ["bright", "tutorial"] and not Progress.COSMETICS_ENABLED else mode.skin
	board.skin = mode.skin
	board.visual_profile = visual_profile
	board.classic_feedback = mode.id in ["classic", "bright", "tutorial"]
	board.zoom_enabled = mode.skin == "classic" and _is_touch_device()
	board.reset_zoom()
	ambient.set_skin("classic" if visual_profile == "classic_run" else visual_profile)
	ambient.reset_velvet_palette()
	Sfx.set_skin(mode.skin)
	Sfx.update_music()
	for k in huds:
		huds[k].visible = k == mode.skin
	hud = huds[mode.skin]
	hud.configure(mode.id, _is_native_android())
	hud.set_combo(keeper.combo)
	_update_hud()
	if is_node_ready():
		_on_viewport_resized.call_deferred()


## Rule selection stays independent of the rendering skin, including practice lessons.
func _configure_keeper() -> void:
	var classic: bool = (mode.id == "classic" and not daily) or (mode.kind == "tutorial" and not TutorialLessons.run_rules(_tutorial_id()))
	var experiment: bool = _ab_active and mode.id == "classic"
	keeper.configure_time_rewards(classic and not experiment)
	keeper.configure_combo_rules(classic, _run_time_rules(),
		ComboExperiment.window_seconds() if experiment else ScoreKeeper.CLASSIC_COMBO_WINDOW,
		ComboExperiment.special_rules == "timed" if experiment else true)
	keeper.time_bonuses = mode.kind == "classic" or (mode.kind == "tutorial" and not _run_time_rules())
	keeper.hot_streak = mode.kind != "tutorial"


## Lay out a board for the current mode. The daily board uses the mode's fixed shape and a
## pinned UTC date seed (plus wave number). Transpose only AFTER canonical generation.
func _deal_board() -> void:
	if mode.kind == "tutorial":
		TutorialLessons.load_board(logic, _tutorial_id(), tut_hits)
		board_kinds = 6
		return
	if mode.skin == "bright":
		# bright: the board for this level, dealt until it opens with the level's number of moves;
		# map levels and the daily board use a fixed seed and shape, so everyone gets the same one
		var lvn := _level()
		var lv := BoardLogic.bright_level(lvn)
		if mode.kind == "puzzle":
			lv = BoardLogic.puzzle_config(puzzle_n)
		if mode.kind == "run":
			# Sequential fields share the party's geometry and use the approved Run generator.
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
				r.seed = hash("bizarre-gems-%s-%s-%d" % [daily_run_date, mode.id, wave])
			area = Vector2(360, 640)
		var d := BoardLogic.best_dims(area, lv.slots)
		if mode.kind == "run" and not daily:
			r = _game_rng()
			if _run_dims != Vector2i.ZERO:
				d = _run_dims
			board_dims = d
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
		if mode.kind == "run" and daily and _daily_transposed:
			logic.transpose()
		board_kinds = int(lv.kinds)
		goal_kind = int(lv.get("goal_kind", -1)) if mode.kind == "levels" else -1
		return
	if daily:
		var r := RandomNumberGenerator.new()
		r.seed = hash("bizarre-gems-%s-%s-%d" % [daily_run_date, mode.id, wave])
		logic.setup(mode.cols, mode.rows, r, mode.shining, mode.kinds, mode.per_kind)
		if mode.id == "classic" and _is_touch_device() and not _is_native_android():
			logic.transpose()  # the same daily board, upright in mobile browsers
	else:
		var d := _dims()
		var r := rng
		if mode.kind == "classic":
			r = _game_rng()
			if not challenge.is_empty():
				d = challenge.dims
			board_dims = d
		if _ab_active and mode.id == "classic" and ComboExperiment.fixed_layout:
			r = RandomNumberGenerator.new()
			r.seed = ComboExperiment.board_seed
		logic.setup(d.x, d.y, r, mode.shining, mode.kinds, mode.per_kind)


## The generator for this wave's board in a shareable game (see game_seed).
func _game_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("bizarre-ch-%d-%d" % [game_seed, wave])
	return r


## Launch payload "c1-<mode>-<seed>-<cols>-<rows>-<score>" -> challenge, or empty if it is not one.
static func parse_challenge(p: String) -> Dictionary:
	var a := p.split("-")
	if a.size() != 6 or a[0] != "c1" or not (a[1] in ["classic", "bright"]):
		return {}
	for i in range(2, 6):
		if not a[i].is_valid_int():
			return {}
	var cols := int(a[3])
	var rows := int(a[4])
	var gems := 270 if a[1] == "classic" else 168
	if cols < 3 or rows < 3 or cols > 1000 or rows > 1000 \
			or cols * rows <= gems or cols * rows > 1000 \
			or int(a[2]) < 0 or int(a[2]) > 4294967295 or int(a[5]) < 0:
		return {}
	return {"mode": a[1], "seed": int(a[2]), "dims": Vector2i(cols, rows), "score": int(a[5])}


func _share_challenge() -> void:
	var p := "c1-%s-%d-%d-%d-%d" % [mode.id, game_seed, board_dims.x, board_dims.y, score]
	Yandex.share(p, L.t("ch_share_text", {"n": score}), func(res: String):
		if res == "copied":
			_toast(L.t("ch_copied"))
		elif res == "fail":
			_toast(L.t("ch_fail")))


## A board ran out of moves: deal the next one with a time bonus, the game goes on.
func _next_wave(at: Vector2i, palette_already_changed := false) -> void:
	if dealing or state != State.PLAYING or not (mode.waves or (mode.kind == "tutorial" and _run_time_rules())):
		return
	if _run_time_rules():
		if keeper.update(play_time):
			_combo_break()
		keeper.reset_double_hit()  # Only the pending position belongs to the old board.
	var full_clear := logic.gems_left() == 0
	var bonus_t := WAVE_TIME + (CLEAR_TIME if full_clear else 0.0)
	var board_time := 0.0
	if _run_time_rules():
		board_time = RUN_BOARD_TIME[clampi(wave - 1, 0, RUN_BOARD_TIME.size() - 1)]
		bonus_t = board_time + (RUN_FULL_CLEAR_TIME if full_clear else 0.0)
	if mode.kind == "zen":
		bonus_t = 0.0
		var nl := BoardLogic.bright_level(wave + 1)
		var add := int(round(nl.per_kind * nl.kinds * 0.33))
		strikes += add
		strikes_max = maxi(strikes_max, strikes)
		hud.flash_delta("+%d" % add, false, "steps")
		_report_progress("zen_boards")
	if full_clear:
		board.play_clear_wave()
		Sfx.play("clear")
	elif mode.kind == "zen" or _run_time_rules():
		_report_progress("clear_boards")
	var bonus_p := CLEAR_POINTS if full_clear else 0
	if full_clear and _run_time_rules():
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
	if _run_time_rules():
		sub = L.t("run_board_time", {"s": int(board_time)})
		if full_clear:
			sub += "\n" + L.t("run_full_clear_reward", {"s": int(RUN_FULL_CLEAR_TIME), "p": bonus_p})
	_banner(title, bonus_p, bonus_t, UiKit.BRASS_LIGHT, sub)
	if bonus_t > 0.0:
		hud.flash_delta("+%d" % int(bonus_t), false)
	Sfx.play("precise")
	board.play_burst(at, 50)
	board.play_confetti(70)
	if not palette_already_changed:
		_set_theme(_next_look())
	var tw := create_tween()
	tw.tween_interval(1.2 if full_clear else 0.7)
	var generation := _game_generation
	tw.tween_callback(func():
		if generation != _game_generation:
			return
		_deal_board()
		board.clear_fx()
		board.refresh()
		board.deal_in()
		dealing = false
		board.interactive = state == State.PLAYING
		if mode.kind == "tutorial": tutorial.wave_done(full_clear,bonus_t,bonus_p))


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
		t = UiKit.CHAPTER_THEMES[BoardLogic.chapter_of(level_n) % UiKit.CHAPTER_THEMES.size()]  # each chapter keeps its own sky
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
	if not _is_native_android():
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
	_cancel_ad()
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
	_report_progress("games_levels")
	_report_progress("play_secs", int(play_time))
	Progress.add_local_score("stars", Progress.total_stars())
	if Yandex.is_authorized():
		Yandex.submit_score(Progress.total_stars(), "stars")
	level_result.show_result({
		"title": L.t("level_n", {"n": level_n}),
		"outcome": L.t("goal_failed") if goal_failed else L.t("level_passed" if got > 0 else "level_failed"),
		"line": L.t("level_share", {"p": int(round(share * 100))}) + ("  ·  +%d" % (gained * Progress.STAR_CRYSTALS) if gained > 0 else ""),
		"stars": got, "can_next": got > 0, "reward": last_earned,
		"continue_text": "" if left == 0 or used_continue else L.t("continue_ad" if time_left <= 0.0 else "shuffle_ad"),
	})
	show_screen(level_result)
	level_result.play_stars(got)
	Sfx.play("level" if got > 0 else "over")


# ================= puzzle, tutorial =================

func start_puzzle(n: int) -> void:
	puzzle_n = n
	start_game("puzzle")


func _end_puzzle() -> void:
	if state == State.OVER:
		return
	_cancel_ad()
	state = State.OVER
	board.interactive = false
	var solved := logic.gems_left() == 0
	last_earned = 0
	if solved:
		if puzzle_n > Progress.puzzles:
			last_earned = 10
			Progress.add_crystals(10)
		Progress.solved_puzzle(puzzle_n)
	_report_progress("games_puzzle")
	level_result.show_result({
		"title": L.t("puzzle_n", {"n": puzzle_n}),
		"outcome": L.t("puzzle_solved" if solved else "puzzle_failed"),
		"line": L.t("puzzle_line", {"n": logic.solution.size()}),
		"stars": -1, "can_next": solved, "reward": last_earned, "continue_text": "",  # puzzles are solved or not, no stars
	})
	show_screen(level_result)
	Sfx.play("level" if solved else "over")


## Practice delegates sequencing to a separate controller; compatibility accessors contain no duplicate state.
func _tutorial_id() -> String: return tutorial.lesson_id()
func _tutorial_target() -> Vector2i: return tutorial.target()
func _tutorial_step(i: int) -> void: tutorial.step(i)
func _tutorial_next() -> void: tutorial.next()
func _tutorial_retry() -> void: tutorial.retry()
func _tutorial_help() -> void: tutorial.help()
func _tutorial_feedback(key: String, args := {}) -> void: tutorial.feedback(key,args)
func _tutorial_done(key := "", args := {}) -> void: tutorial.done(key,args)
func _run_time_rules() -> bool:
	return mode.kind == "run" or (mode.kind == "tutorial" and TutorialLessons.run_rules(_tutorial_id()))
func _classic_time_rules() -> bool:
	return mode.kind in ["classic","levels"] or (mode.kind == "tutorial" and not _run_time_rules())

func _place_hand(target: Vector2i) -> void:
	tut_hand.set_meta("target", target)

func _update_hand() -> void:
	if not tut_hand.visible or not tut_hand.has_meta("target"):
		return
	var target: Vector2i = tut_hand.get_meta("target")
	var pos := board.global_position + board.slot_center(target) - global_position
	var side := minf(board.cell * 0.34, 48.0)
	tut_hand.size = Vector2.ONE * side
	# The reused icon's fingertip is at its top centre; leave the target visible.
	tut_hand.position = pos + Vector2(-side * 0.5, board.cell * (0.03 + 0.02 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)))

func _today() -> String:
	return Time.get_date_string_from_system(true)


func _resume_play() -> void:
	if _ab_active and state == State.OVER:
		_ab_reported = false
	if _run_starting:
		return
	if mode.skin == "bright":
		_set_orientation(false)  # bright modes are played upright on phones
	state = State.PLAYING
	idle = 0.0
	last_tick = -1
	board.interactive = not dealing and not (mode.kind == "tutorial" and (tut_waiting or tut_clock_running))
	show_screen(null)
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
	Engine.time_scale = 1.0
	board.interactive = false
	Yandex.gameplay(false)
	show_screen(pause)


func go_menu() -> void:
	_report_combo_ab("abandoned")
	_ab_active = false
	_cancel_ad()
	Progress.flush()
	_reset_visual_feedback()
	keeper.reset_bonus_combos()
	_game_generation += 1
	_run_starting = false
	_run_dims = Vector2i.ZERO
	_daily_transposed = false
	board.modulate.a = 1.0
	tut_label.visible = false
	tut_hand.visible = false
	practice.visible = false
	if tutorial: tutorial.tut_clock_running = false
	board.tutorial_focus = Vector2i(-1,-1)
	dealing = false
	if state == State.PLAYING:
		Yandex.gameplay(false)
	state = State.MENU
	board.interactive = false
	board.fire = 0
	Engine.time_scale = 1.0
	fly.clear()
	show_screen(home)


func end_game(reason: String) -> void:
	if state == State.OVER or state == State.MENU:
		return  # A result is accounted once, including after repeated end requests.
	if mode.kind == "levels":
		_end_level()
		return
	_cancel_ad()
	if mode.kind == "tutorial":
		tutorial.done("lesson_" + _tutorial_id() + "_result", {"p":score,"s":time_left})
		return
	if mode.kind == "run":
		_report_progress("run_score", score)
	# Result screens freeze play_time; a first Run time-continue retains eligible clocks.
	if mode.kind == "run" and reason == "time" and not used_continue:
		if keeper.update(play_time):
			_combo_break()
	else:
		keeper.reset_bonus_combos()
		_reset_visual_feedback()
	state = State.OVER
	end_reason = reason
	board.interactive = false
	board.fire = 0
	Engine.time_scale = 1.0
	Yandex.gameplay(false)
	var is_best := false
	if ComboExperiment.is_read_only():
		_report_combo_ab(reason)
	elif daily:
		is_best = Save.submit_daily(score, daily_run_date)
	else:
		is_best = Save.submit(score, mode.id)
		Progress.add_local_score(mode.board, score)
		if Yandex.is_authorized() and mode.board != "":
			Yandex.submit_score(Save.best_for(mode.id), mode.board)
	Sfx.play("over")
	Haptics.buzz("over")
	last_earned = 0
	if not ComboExperiment.is_read_only():
		var earned := Progress.crystals_for_score(score) - paid_crystals
		paid_crystals += earned
		var daily_paid := Progress.pay_daily(daily_run_date) if daily else 0
		Progress.add_crystals(maxi(earned, 0))
		last_earned = maxi(earned, 0) + daily_paid
	_report_progress("games_" + mode.id)
	_report_progress("max_combo", keeper.best_combo)
	_report_progress("max_hot", keeper.best_hot)
	_report_progress("play_secs", int(play_time))
	Progress.flush()
	var line := L.t("cleared", {"n": cleared, "w": wave}) + "\n" + L.t("stats", {"combo": keeper.best_combo, "precise": keeper.precise_count})
	if keeper.best_hot >= ScoreKeeper.HOT_AT:
		line += "\n" + L.t("best_hot", {"n": keeper.best_hot})
	# just short of the record: say by how much, so "again" is hard to resist
	var near_n := 0
	if not is_best and best_start > 0 and score > 0 and (best_start - score) * 5 <= best_start:
		near_n = best_start - score + 1
	if daily:
		line = L.t("daily") + " · " + L.t("daily_best", {"n": Save.daily_best_for(daily_run_date)}) + "\n" + line
	if not challenge.is_empty():
		var target := int(challenge.score)
		line = (L.t("ch_won", {"n": target}) if score > target else L.t("ch_lost", {"n": target, "d": target - score + 1})) + "\n" + line
	result.show_result({
		"localization": {"title":"stuck" if reason == "stuck" else ("no_strikes" if reason == "strikes" else "times_up"),
			"new_best":("new_daily_best" if daily else "new_best") if is_best and score > 0 else "",
			"cleared":cleared,"wave":wave,"combo":keeper.best_combo,"precise":keeper.precise_count,
			"daily":daily,"daily_best":Save.daily_best_for(daily_run_date) if daily else 0,"target":int(challenge.score) if not challenge.is_empty() else -1,
			"near":near_n,"best_hot":keeper.best_hot if keeper.best_hot >= ScoreKeeper.HOT_AT else 0},
		"title": L.t("stuck" if reason == "stuck" else ("no_strikes" if reason == "strikes" else "times_up")),
		"score": score,
		"new_best": L.t("new_daily_best" if daily else "new_best") if is_best and score > 0 else "",
		"line": line,
		"near": L.t("near_best", {"n": near_n}) if near_n > 0 else "",
		"reward": last_earned,
		"can_continue": reason == "time" and not used_continue and mode.kind != "zen",
		"can_shuffle": reason == "stuck" and not used_shuffle and logic.gems_left() > 1,
		"can_share": Yandex.can_share() and mode.id in ["classic", "bright"] and not daily and score > 0,
	})
	result.show_best_strike(best_strike, func(k: int) -> Texture2D: return board._tex(k))
	show_screen(result)
	_update_hud()


func _on_slot(p: Vector2i) -> void:
	if state != State.PLAYING or dealing or (mode.kind == "tutorial" and (tut_waiting or tut_clock_running)) or not logic.in_bounds(p):
		return
	if not logic.is_empty(p):
		if mode.kind == "tutorial": tutorial.feedback("lesson_occupied")
		return
	board.ripple(p)
	var gone := logic.matches_from(p)
	if mode.kind == "tutorial":
		var target := _tutorial_target()
		if target.x >= 0 and p != target:
			tutorial.feedback("lesson_wrong")
			return
		if gone.is_empty() and _tutorial_id() != "miss":
			tutorial.feedback("lesson_no_match")
			return
		play_time += 0.25 # Pinned controlled practice time still exercises the real combo deadlines.
	var practice_score_before := score
	var practice_time_before := time_left
	if mode.kind == "zen":
		strikes -= 1 if not gone.is_empty() else 2  # a miss costs two steps
	elif mode.kind == "puzzle":
		strikes -= 1
	if gone.is_empty():
		if _classic_time_rules() or _run_time_rules():
			time_left = maxf(0.0, time_left - 1.0)
		board.play_miss(p)
		Sfx.play("miss")
		Haptics.buzz("miss")
		if keeper.miss():
			_combo_break()
		board.fire = 0
		if keeper.lost_hot >= ScoreKeeper.HOT_AT:
			_toast(L.t("fire_out", {"n": keeper.lost_hot}))
			Sfx.play("fire_out", 1.0, -3.0)
		if _classic_time_rules() or _run_time_rules():
			hud.flash_delta("−1", true)
		_tick_obstacles(false)
		if time_left <= 0.0:
			end_game("time")
		elif (mode.kind == "zen" or mode.kind == "puzzle") and strikes <= 0:
			if mode.kind == "puzzle":
				_end_puzzle()
			else:
				end_game("strikes")
		if mode.kind == "tutorial":
			tutorial.tut_last_result = {"points":0,"time":time_left-practice_time_before,"miss":true}
			tutorial.done()
		_update_hud()
		return
	var kinds: Array[int] = []
	for g in gone:
		kinds.append(logic.kind_at(g))
	var nshine := logic.shining_count(gone)
	var joker_color := logic.joker_match_kind(p) if _run_time_rules() else BoardLogic.EMPTY
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
	var color_kinds: Array[int] = vkinds.duplicate()
	if joker_color >= 0:
		for i in color_kinds.size():
			if color_kinds[i] == BoardLogic.JOKER:
				color_kinds[i] = joker_color
	var res := keeper.hit(n, play_time, nshine, p, color_kinds)
	score = keeper.score
	hud.pop(hud.score_label, 1.3)
	if nshine > 0:
		Sfx.play("bonus")
		board.play_burst(p, 14 * nshine, false)
		ambient.pulse(Color(1.0, 0.84, 0.4), 0.5)
	var step := -1
	if PRAISE_LADDER:
		step = PRAISE_AT.find(res.combo)
		if step < 0 and res.combo > PRAISE_AT[-1] and res.combo % 5 == 0:
			step = PRAISE_AT.size() - 1
	if step >= 0:
		board.praise(L.t("praise_%d" % (step + 1)), p, PRAISE_COLORS[step], 1.0 + step * 0.12)
	elif n >= 4 and res.event == "":
		board.praise(L.t("praise_great"), p, UiKit.BRASS_LIGHT)
	if not PRAISE_LADDER and res.tier_up and res.mult >= 3:
		board.praise(L.t("praise_super" if res.mult == 3 else "praise_wow"), p, UiKit.COMBO_COLORS[res.mult - 1].lightened(0.35), 1.2)
	if res.ignited:
		if step < 0:
			board.praise(L.t("on_fire"), p, Color("#ff9a2e"), 1.15)
		Sfx.play("fire")
		Haptics.buzz("tier")
	board.fire = 0 if keeper.hot < ScoreKeeper.HOT_AT else (2 if keeper.hot >= ScoreKeeper.HOT_AT * 2 else 1)
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
	if _classic_time_rules():
		time_left += res.time  # the bright run earns time only by clearing a whole board
	idle = 0.0
	if _ab_active:
		_ab_receipts.append({"at":str(p),"game_time":play_time,"removed":vanish.size(),
			"receipt":res.duplicate(true),"score":score,"time_left":time_left})
	var event: String = res.event
	board.play_knock(p, vanish, vkinds, res.points, res.mult, event != "", res)
	_send_sparks(vanish, vkinds)
	if vanish.size() < gone.size():
		board.shake(0.08)  # a box cracked
	if mode.skin == "bright":
		var semi: int = PENTA[(res.combo - 1) % PENTA.size()]
		Sfx.play("knock%d" % mini(n, 4), pow(2.0, semi / 12.0))
	else:
		Sfx.play("knock%d" % mini(n, 4), 1.0 + mini(res.combo, 12) * 0.025)
	_report_progress("gems", vanish.size())
	if res.tier_up and res.mult == 4:
		_report_progress("combo4")
	if res.time > 0 and _classic_time_rules():
		hud.flash_delta("+%d" % int(res.time), false)
	if res.tier_up:
		if mode.skin == "bright":
			Sfx.play("combo_up", 1.0, -2.0)
		Haptics.buzz("tier")
		ambient.pulse(UiKit.BRASS, 0.4)
		board.play_wave(p, 1.0)
		board.shake(0.1)
		board.glow(0.9, UiKit.COMBO_COLORS[clampi(res.mult, 1, 4) - 1])
		if res.mult >= 3:
			_hitstop(0.05)
	if event == "precise":
		if mode.skin == "bright":
			Sfx.play("precise")
		Haptics.buzz("precise")
		ambient.pulse(UiKit.BRASS_LIGHT, 0.8)
		board.play_wave(p, 2.0, true)
		board.play_burst(p, 40)
		board.flash(UiKit.BRASS_LIGHT, 0.22)
		_hitstop(0.06)
		_banner(L.t("precise"), ScoreKeeper.PRECISE_POINTS, 0.0 if _run_time_rules() else ScoreKeeper.PRECISE_TIME, UiKit.BRASS_LIGHT, "", 2)
		if mode.skin == "bright":
			board.play_confetti(50)
		if mode.id != "bright" or daily:
			_set_theme(_next_look())
	elif event == "perfect":
		if mode.skin == "bright":
			Sfx.play("perfect")
		Haptics.buzz("perfect")
		ambient.pulse(Color("#ff9ed2"), 1.0)
		board.play_wave(p, 3.0, true)
		board.play_burst(p, 90)
		board.flash(Color.WHITE, 0.4)
		board.shake(0.3)
		_hitstop(0.09)
		_banner(L.t("perfect"), ScoreKeeper.PERFECT_POINTS, 0.0 if _run_time_rules() else ScoreKeeper.PERFECT_TIME, Color("#ff9ed2"), "", 3)
		_report_progress("perfects")
		if mode.skin == "bright":
			board.play_confetti(90)
		if mode.id != "bright" or daily:
			_set_theme(_next_look())
	var palette_event: bool = mode.id == "bright" and not daily and (event != "" or res.combo in [30, 50])
	if palette_event:
		_set_theme(_next_look())  # One atmosphere change per strike, including a special + threshold.
	_show_bonus_feedback(res, p)
	hud.set_combo(keeper.combo, res.tier_up)
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
		var receipt := res.duplicate(true)
		receipt.merge({"awarded_points":score-practice_score_before,"awarded_time":time_left-practice_time_before,"removed":vanish.size()}, true)
		tutorial.after_strike(receipt,p)
		_update_hud()
		return
	if mode.kind == "puzzle":
		if logic.gems_left() == 0:
			board.play_clear_wave()
			Sfx.play("clear")
			dealing = true
			var tw0 := create_tween()
			tw0.tween_interval(1.2)
			var generation := _game_generation
			tw0.tween_callback(func():
				if generation == _game_generation:
					dealing = false
					_end_puzzle())
		elif strikes <= 0 or not logic.has_any_move():
			_end_puzzle()
		_update_hud()
		return
	if mode.kind == "levels" and logic.gems_left() == 0:
		board.play_clear_wave()
		Sfx.play("clear")
		_report_progress("clear_boards")
		dealing = true
		var tw := create_tween()
		tw.tween_interval(1.3)
		var generation := _game_generation
		tw.tween_callback(func():
			if generation == _game_generation:
				dealing = false
				_end_level())
		return
	if not logic.has_any_move():
		if mode.kind == "levels":
			_end_level()
		elif mode.waves:
			_next_wave(p, palette_event)
		else:
			end_game("stuck")
	elif mode.kind == "zen" and strikes <= 0:
		end_game("strikes")


func _process(delta: float) -> void:
	if absf(score - shown_score) > 0.5:
		shown_score = lerpf(shown_score, score, minf(1.0, delta * 10.0))
	else:
		shown_score = score
	hud.set_number(hud.score_label, int(round(shown_score)))
	_hud_safe_poll += delta
	if _hud_safe_poll >= .25:
		_hud_safe_poll = 0.0
		if safe != _safe_insets():
			_on_viewport_resized()
	_update_hand()
	if state != State.PLAYING:
		return
	if mode.kind == "tutorial":
		tutorial.process(delta)
		return
	if mode.kind == "run" and dealing:
		return  # The transition's mandatory input lock must not consume combo windows.
	# Stop Run's combo clock at actual time exhaustion.
	var game_delta := minf(delta, maxf(time_left, 0.0)) if mode.kind == "run" else delta
	if _classic_time_rules() or _run_time_rules():
		time_left -= game_delta * _time_speed()
	if mode.kind == "run":
		play_time += game_delta
	_stuck_t += game_delta
	if _stuck_t > 0.5:
		_stuck_t = 0.0
		_check_no_moves()
		if state != State.PLAYING or (mode.kind == "run" and dealing):
			return
	if mode.kind != "run":
		play_time += game_delta
	if keeper.update(play_time):
		_combo_break()
	if keeper.combo >= 2:
		hud.combo_bar.value = keeper.window_left(play_time) / keeper.combo_window * 100.0
	idle += game_delta
	if autoplay:
		_auto_t += game_delta
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
		hud.pop(hud.time_label, 1.35)
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
	if state != State.PLAYING or dealing or _ad_pending:
		return
	if mode.kind == "tutorial":
		tutorial.help()  # Practice never spends tokens or asks for a reward.
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
	var generation := _game_generation
	var request := _begin_ad()
	Yandex.show_rewarded(func(ok: bool):
		if not _consume_ad(request, generation):
			return
		if generation != _game_generation or state not in [State.PLAYING, State.PAUSED] or _run_starting or dealing:
			return
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
			hud.flash_delta("−%d" % BOMB_STEPS, true, "steps")
		elif mode.kind != "puzzle":
			time_left = maxf(0.0, time_left - BOMB_TIME)
			hud.flash_delta("−%d" % int(BOMB_TIME), true)
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


## One pending SDK request per game; each response can be consumed only once.
func _set_ad_pending(pending: bool) -> void:
	_ad_pending = pending
	result.set_ad_pending(pending)
	level_result.set_ad_pending(pending)


func _cancel_ad() -> void:
	_ad_request += 1
	_set_ad_pending(false)


func _begin_ad() -> int:
	_ad_request += 1
	_set_ad_pending(true)
	return _ad_request


func _consume_ad(request: int, generation: int) -> bool:
	if generation != _game_generation or request != _ad_request or not _ad_pending:
		return false
	_set_ad_pending(false)
	return true


## Practice uses real rules without writing ordinary counters/achievements.
func _report_progress(id: String, amount := 1) -> void:
	if mode.kind != "tutorial" and not ComboExperiment.is_read_only():
		Progress.report(id, amount)


## Rewarded video: the crystals of this result once more.
func _on_double() -> void:
	if _ad_pending or state != State.OVER or mode.kind == "tutorial" or last_earned <= 0:
		return
	var generation := _game_generation
	var request := _begin_ad()
	var earned := last_earned
	Yandex.show_rewarded(func(ok: bool):
		if not _consume_ad(request, generation):
			return
		if generation != _game_generation or state != State.OVER or last_earned <= 0:
			return
		if not ok:
			_toast(L.t("ad_failed"))
			return
		Progress.add_crystals(earned)
		_toast(L.t("doubled", {"n": earned}))
		Sfx.play("star")
		last_earned = 0
		result.hide_double()
		level_result.hide_double())


## Rewarded video on a lost level: 15 more seconds, or a reshuffle when no move is left.
func _on_level_continue() -> void:
	if _ad_pending or state != State.OVER or mode.kind != "levels" or used_continue or logic.gems_left() == 0:
		return
	var generation := _game_generation
	var request := _begin_ad()
	Yandex.show_rewarded(func(ok: bool):
		if not _consume_ad(request, generation):
			return
		if generation != _game_generation or state != State.OVER or used_continue:
			return
		if not ok:
			_toast(L.t("ad_failed"))
			return
		used_continue = true
		if time_left <= 0.0:
			time_left = CONTINUE_TIME
			hud.flash_delta("+15", false)
		if not logic.has_any_move():
			logic.shuffle_remaining(rng)
			board.deal_in()
		Sfx.play("bonus")
		_resume_play())


func _on_continue() -> void:
	if _ad_pending or state != State.OVER or end_reason != "time" or used_continue \
			or mode.kind not in ["classic", "run"]:
		return
	var generation := _game_generation
	var request := _begin_ad()
	Yandex.show_rewarded(func(ok: bool):
		if not _consume_ad(request, generation):
			return
		if generation != _game_generation or state != State.OVER \
				or end_reason != "time" or used_continue:
			return
		if not ok:
			_toast(L.t("ad_failed"))
			return
		used_continue = true
		time_left = CONTINUE_TIME
		hud.flash_delta("+15", false)
		Sfx.play("bonus")
		_resume_play())


func _on_shuffle() -> void:
	if _ad_pending or state != State.OVER or end_reason != "stuck" or used_shuffle or logic.gems_left() <= 1:
		return
	var generation := _game_generation
	var request := _begin_ad()
	Yandex.show_rewarded(func(ok: bool):
		if not _consume_ad(request, generation):
			return
		if generation != _game_generation or state != State.OVER or end_reason != "stuck" or used_shuffle:
			return
		if not ok:
			_toast(L.t("ad_failed"))
			return
		used_shuffle = true
		result.hide_shuffle()
		logic.shuffle_remaining(rng)
		board.clear_fx()
		board.deal_in()
		if logic.has_any_move():
			_resume_play()
		else:
			end_game("stuck"))


func _on_again() -> void:
	if _ad_pending or state != State.OVER or mode.kind == "tutorial":
		return
	var generation := _game_generation
	var request := _begin_ad()
	Yandex.show_fullscreen(func(_shown: bool):
		if not _consume_ad(request, generation):
			return
		if generation == _game_generation and state == State.OVER:
			start_game(mode.id, daily, challenge))


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
	if settings.visible:
		_close_settings()
	elif confirm.visible:
		show_screen(pause)
	elif map.visible:
		show_screen(modes)
	elif rules.visible or modes.visible or tasks.visible or collection.visible or gift.visible or achievements.visible or stats.visible or more.visible:
		show_screen(home)
	elif level_result.visible:
		_open_map("puzzle" if mode.kind == "puzzle" else "levels")
	elif leaders.visible:
		show_screen(leaders_return)
	elif state == State.PLAYING:
		pause_game()
	elif state == State.PAUSED:
		show_screen(confirm)
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
		if OS.is_debug_build() and state in [State.MENU, State.OVER]:
			if event.keycode in [KEY_F6, KEY_F7]:
				debug_start_combo_ab("A" if event.keycode == KEY_F6 else "B",ComboExperiment.board_seed)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_N:
				debug_start_special_combo("timed",ComboExperiment.board_seed)
				get_viewport().set_input_as_handled()
				return
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			if state == State.PLAYING:
				pause_game()
			elif state == State.PAUSED:
				_resume_play()
			get_viewport().set_input_as_handled()


func _begin_combo_report() -> void:
	if not _ab_active: return
	_ab_run = {"run_id":"%s-%s" % [Time.get_datetime_string_from_system(true),Time.get_ticks_usec()],
		"variant":ComboExperiment.variant,"mode":mode.id,"daily":daily,
		"combo_window":keeper.combo_window,"special_rules":"timed" if keeper.timed_special else "legacy",
		"tier_time":keeper.tier_time,"streak_time":keeper.streak_time,"hit_time_rewards":keeper.hit_time_rewards,
		"seed":ComboExperiment.board_seed,"cols":logic.cols,"rows":logic.rows,
		"initial_gems":level_total,"layout_sha256":str(logic.cells).sha256_text()}
	_ab_receipts.clear()
	_ab_result_index = 0
	_ab_reported = false
	print("[combo-ab] START ",JSON.stringify(_ab_run)," | saves/leaderboards disabled for this process")


func debug_start_run_combo(fixed_seed := 42) -> bool:
	if not OS.is_debug_build() or state not in [State.MENU, State.OVER]: return false
	if not ComboExperiment.select_run(fixed_seed): return false
	start_game("bright")
	return true


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
		"used_continue": used_continue, "used_shuffle": used_shuffle,
		"wave":wave, "receipts":_ab_receipts.duplicate(true)})
	ComboExperiment.append_report(last_combo_report)


func _exit_tree() -> void:
	_report_combo_ab("quit")


# ================= screens =================

func _open_leaders(from: Screen) -> void:
	Sfx.play("click")
	leaders.board = "stars" if mode.kind == "levels" else (mode.board if mode.board != "" else "score")
	leaders_return = from
	show_screen(leaders)
	leaders.refresh()


func _open_map(kind := "levels") -> void:
	map.kind = kind
	_set_orientation(false)
	state = State.MENU
	map.refresh()
	show_screen(map)


func _open_settings(from: Screen) -> void:
	Sfx.play("click")
	settings_return = from
	var vs := get_viewport_rect().size
	settings.open("%s, view %dx%d" % [ui_scale_info, int(vs.x), int(vs.y)])
	show_screen(settings)


func _open_settings_from_hud() -> void:
	settings_from_game = state == State.PLAYING
	if settings_from_game:
		state = State.PAUSED
		board.interactive = false
		Yandex.gameplay(false)
	_open_settings(_current_screen())


func _close_settings() -> void:
	if settings_from_game:
		settings_from_game = false
		_resume_play()
		return
	show_screen(settings_return)


func _current_screen() -> Screen:
	for s in screens.values():
		if s.visible:
			return s
	return null


## Show one screen (null: none, the game is played) and hide the others. Dialogs fade and grow
## in over the dimmed game; full-screen menus hide the game layer.
func show_screen(p: Screen) -> void:
	if p == map: p = modes # Dormant maps remain available to internal tests, never user navigation.
	if p == collection and not Progress.COSMETICS_ENABLED:
		p = home  # Includes direct/debug routes to the dormant scene.
	var was_dim := dim.visible
	if p == home or p == modes:
		_set_orientation(false)
		p.refresh()
	var menu_surface := p == home or p == modes
	if menu_surface:
		board.reset_run_surface()
		ambient.reset_velvet_palette()
	ambient.set_skin("classic" if state == State.MENU or menu_surface else ("classic" if visual_profile == "classic_run" else visual_profile))
	var on_menu := p == home or p == modes or p == map
	# the game layer stays out of sight behind the menus and anything opened from them
	game_layer.visible = not on_menu and state != State.MENU
	for s in screens.values():
		s.visible = s == p
	dim.visible = p != null and not menu_surface
	practice.visible = mode.kind == "tutorial" and state == State.PLAYING and p == null
	if mode.kind == "tutorial":
		tut_hand.visible = practice.visible and board.tutorial_focus.x >= 0
	hud.set_buttons(state == State.PLAYING, state == State.PLAYING or state == State.PAUSED)
	if not p:
		return
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
	create_tween().tween_property(p, "modulate:a", 1.0, 0.18)
	if panel_scale_tween:
		panel_scale_tween.kill()
	panel_scale_tween = create_tween()
	panel_scale_tween.tween_property(p, "scale", Vector2.ONE * fit, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var first := p.focus_button()
	if not first:
		first = _first_button(p)
	if p == rules:
		rules.focus_page.call_deferred()
	elif first:
		first.grab_focus.call_deferred()


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and c.visible:
			return c
		var b := _first_button(c)
		if b:
			return b
	return null


# ================= HUD, messages =================

func _update_hud() -> void:
	var secs := int(ceil(time_left))
	var text := str(secs)
	var fraction := time_left / START_TIME
	match mode.kind:
		"zen":
			text = L.t("steps_n", {"n": maxi(strikes, 0)})
			fraction = float(strikes) / strikes_max
		"puzzle":
			text = L.t("moves_left", {"n": maxi(strikes, 0)})
			fraction = float(strikes) / strikes_max
		"tutorial":
			text = str(secs)
			fraction = time_left / START_TIME
		"levels":
			fraction = time_left / _level_time(level_n)
	hud.set_time(text, fraction, state == State.PLAYING and secs <= 15)
	hud.set_number(hud.best_label, maxi(Save.best_for(mode.id), score))
	if mode.kind == "tutorial": hud.best_label.text = "—"
	hud.update_progress(keeper,play_time,state in [State.PLAYING,State.PAUSED],board,wave)
	record_bar.score = score
	record_bar.set_hot(keeper.hot)
	if state == State.PLAYING and record_bar.race and best_start > 0 and not record_beaten and score > best_start:
		_record_broken()
	hud.set_buttons(state == State.PLAYING, state == State.PLAYING or state == State.PAUSED)
	var bright: Hud = huds.bright
	if mode.kind != "run":
		bright.level_label.text = "· " + L.t("level_short", {"n": _level()})
	bright.level_label.visible = mode.kind in ["run", "levels", "zen", "puzzle"]
	if goal_kind >= 0:
		bright.level_label.text += "  ·  " + L.t("goal_left", {"n": logic.count_kind(goal_kind)})
	# the hint button shows an ad badge once the free hint and the spare ones are used up
	bright.btn_hint.icon = UiKit.icon("hint" if mode.kind == "tutorial" or hints > 0 or Progress.hint_tokens > 0 else "video")
	bright.btn_hint.text = str(Progress.hint_tokens) if mode.kind != "tutorial" and hints <= 0 and Progress.hint_tokens > 0 else ""
	if mode.kind == "tutorial":
		bright.btn_hint.disabled = tut_waiting or tut_clock_running or dealing
		bright.btn_hint.tooltip_text = L.t("lesson_help")


## The score just passed the record, mid-game: make a moment of it.
func _record_broken() -> void:
	record_beaten = true
	record_bar.celebrate()
	_banner(L.t("new_daily_best" if daily else "new_best"), 0, 0.0, UiKit.BRASS, L.t("record_sub", {"n": best_start}))
	var mid := Vector2i(logic.cols / 2, logic.rows / 2)
	board.play_confetti(120)
	board.play_burst(mid, 60)
	board.glow(1.0, UiKit.BRASS)
	board.flash(UiKit.BRASS_LIGHT, 0.3)
	ambient.pulse(UiKit.BRASS, 1.0)
	Sfx.play("record")
	Haptics.buzz("perfect")
	_hitstop(0.12)


## Sparks fly from the knocked-out gems to the score (a few, not one per gem).
func _send_sparks(gone: Array[Vector2i], kinds: Array[int]) -> void:
	var to := hud.score_label.get_global_rect().get_center()
	var bt := board.get_global_transform()
	var sz := clampf(board.cell * 0.8, 14.0, 30.0)
	for i in mini(gone.size(), 6):
		fly.send(bt * board.slot_center(gone[i]), to, board._col(kinds[i]), i * 0.035, sz)


## Freeze the game for a blink on a big moment, so the hit lands.
func _hitstop(secs: float) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(secs, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _toast(text: String) -> void:
	toast.text = text
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(toast, "modulate:a", 0.0, 0.3)


func _combo_break() -> void:
	if mode.skin == "bright":
		Sfx.play("combo_break", 1.0, -6.0)
	hud.fade_combo()


## A big title over the board ("Precise combo!") with the points and seconds it gave.
func _banner(title: String, pts: int, secs: float, color: Color, sub := "", priority := 0) -> void:
	if mode.id in ["classic", "bright"] and banner.has_meta("banner_tween"):
		if banner.modulate.a > 0.03 and int(banner.get_meta("priority", 0)) > priority:
			if secs > 0.0 and sub != "":
				# A last-hit special remains primary; the actual board rewards share its notice.
				%BannerSub.text += "\n" + sub
				_fit_banner_text()
			return # Perfect remains the main event; secondary rewards still show locally.
		var previous: Tween = banner.get_meta("banner_tween")
		if previous and previous.is_valid():
			previous.kill()
	banner.set_meta("priority", priority)
	%BannerTitle.text = title
	%BannerTitle.add_theme_color_override("font_color", color)
	if sub != "":
		%BannerSub.text = sub
	elif secs <= 0.0 or not keeper.time_bonuses:
		%BannerSub.text = L.t("points_only", {"p": pts}) if pts > 0 else ""
	else:
		%BannerSub.text = L.t("bonus_line", {"p": pts, "s": int(secs)})
	_fit_banner_text()
	banner.pivot_offset = banner.size / 2
	banner.scale = Vector2.ONE * 0.4
	banner.modulate.a = 1.0
	var tw := create_tween()
	banner.set_meta("banner_tween", tw)
	tw.tween_property(banner, "scale", Vector2.ONE * 1.08, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.12)
	var short_special: bool = mode.id in ["classic", "bright", "tutorial"] and priority in [2, 3]
	tw.tween_interval(SPECIAL_BANNER_SECONDS - 0.55 if short_special else 0.9)
	if mode.id != "classic" and not short_special:
		tw.parallel().tween_property(banner, "position:y", banner.position.y - 30, 1.3)
	tw.tween_property(banner, "modulate:a", 0.0, 0.25 if short_special else 0.35)


# ================= layout =================

## Board shape for the free space under the HUD.
func _dims() -> Vector2i:
	if mode.kind == "run" and _run_dims != Vector2i.ZERO:
		return _run_dims
	if mode.id == "classic" and (not _is_touch_device() or _is_native_android()):
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
	_layout_game()
	if mode.kind == "tutorial": return # Fixed lesson coordinates never transpose.
	if mode.kind == "run" and (_run_starting or _run_dims != Vector2i.ZERO):
		board.refresh()  # Resize rendering only; logical coordinates persist for the entire Run.
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
		if not (mode.id == "classic" and not _is_touch_device() and challenge.is_empty()):
			logic.transpose()
			keeper.transpose_bonus_slot()
			board.transposed()
	board.refresh()


func _on_viewport_resized() -> void:
	var s := get_viewport_rect().size
	var turn := _is_touch_device() and s.x > s.y * 1.05 and not _is_native_android()
	rotate_overlay.visible = turn
	if turn:
		pause_game()
	compact = s.x < 640 or s.y < 600
	for k in huds:
		huds[k].layout(s, compact)
	safe = _safe_insets()
	_inset_margins(game_layer, 6 if compact else 16)
	_inset_margins(home, 24)
	_inset_margins(modes, 16)
	_inset_margins(map, 16)
	# panels centre in the safe part of the screen; the hint line and toasts keep clear of it too
	center.offset_left = safe.position.x
	center.offset_top = safe.position.y
	center.offset_right = -safe.size.x
	center.offset_bottom = -safe.size.y
	tut_label.add_theme_font_size_override("font_size",17 if s.x < 400 else (18 if compact else 20))
	toast.offset_bottom = -40.0 - safe.size.y
	toast.offset_top = toast.offset_bottom - toast.size.y
	var w := clampf(s.x - (24 if compact else 40), 260, 620)
	for p in screens.values():
		if not p.full_screen:
			p.custom_minimum_size.x = w
			p.theme_type_variation = &"PanelCompact" if compact else &""
		p.layout(s, compact)
	board.frame_pad = 3.0 if mode.id == "classic" and _is_native_android() else (5.0 if compact else 10.0)
	record_bar.custom_minimum_size.y = 30.0 if compact else 36.0
	if mode.id == "classic" and _is_native_android():
		# Refinement centres both rails on the full screen; the cell/rail calculation
		# reserves horizontal cutouts. Vertical margins use the larger safe inset.
		var side := 4
		var vertical := maxi(ceili(safe.position.y),ceili(safe.size.y))+4
		for edge in ["left","right"]:
			game_layer.add_theme_constant_override("margin_"+edge,side)
		for edge in ["top","bottom"]:
			game_layer.add_theme_constant_override("margin_"+edge,vertical)
	_layout_game.call_deferred()
	_relayout_board.call_deferred()
	_fit_panels.call_deferred()


## Height a dialog may take: the screen minus the insets and a margin.
func _avail_height() -> float:
	return get_viewport_rect().size.y - safe.position.y - safe.size.y - (12.0 if compact else 32.0)


## Scale for a panel that is taller than the screen, so all of it shows (1 when it fits).
func _panel_fit(p: Screen) -> float:
	if p.full_screen:
		return 1.0  # full-screen layouts arrange themselves
	var width := get_viewport_rect().size.x-safe.position.x-safe.size.x-24
	return clampf(minf(_avail_height()/maxf(p.size.y,1),width/maxf(p.size.x,1)),0.5,1)


## Shrink the scrolling middle of tall dialogs, then scale whatever is still too tall.
func _fit_panels() -> void:
	var avail := _avail_height()
	for p in screens.values():
		if p.visible:
			p.fit(avail)
	for p in screens.values():
		if p.visible and not p.full_screen:
			p.pivot_offset = p.size / 2
			p.scale = Vector2.ONE * _panel_fit(p)


## A panel whose height changes after it was fitted (wrapped text measured too tall on its first
## frame, the best-strike replay appearing) is fitted again: otherwise it keeps a scale and pivot
## made for the old height and slides off the bottom of the screen.
func _refit_panel(p: Screen) -> void:
	if not p.visible:
		return
	p.pivot_offset = p.size / 2
	if panel_scale_tween and panel_scale_tween.is_running():
		panel_scale_tween.kill()
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


func _inset_margins(c: Control, m: int) -> void:
	c.add_theme_constant_override("margin_left", m + int(safe.position.x))
	c.add_theme_constant_override("margin_top", m + int(safe.position.y))
	c.add_theme_constant_override("margin_right", m + int(safe.size.x))
	c.add_theme_constant_override("margin_bottom", m + int(safe.size.y))



## Screen areas covered by a camera cutout, rounded corners or the gesture bar, in logical
## pixels: position = (left, top), size = (right, bottom). The Android app draws under them
## (immersive mode); a browser page gets CSS env(safe-area-inset-*), which is 0 unless the page
## itself extends under the cutout. Debug web builds fake a cutout with ?inset=N (top, or left
## in landscape) to check the layouts.
func _safe_insets() -> Rect2:
	if OS.has_feature("web"):
		var css := str(JavaScriptBridge.eval("(function(){var d=document.createElement('div');" +
			"d.style.cssText='position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';" +
			"document.body.appendChild(d);var c=getComputedStyle(d);var r=[c.paddingLeft,c.paddingTop,c.paddingRight,c.paddingBottom].map(function(x){return parseFloat(x)/innerHeight;}).join(',');" +
			"d.remove();var q=new URLSearchParams(location.search).get('inset');return q?r+','+q:r;})()"))
		var v := css.split(",")
		if v.size() < 4:
			return Rect2()
		var k := get_viewport_rect().size.y  # the page reports fractions of its height
		var r := Rect2(float(v[0]) * k, float(v[1]) * k, float(v[2]) * k, float(v[3]) * k)
		if v.size() > 4 and OS.is_debug_build():
			var n := float(v[4])
			var s := get_viewport_rect().size
			r = Rect2(n, 0, 0, 0) if s.x > s.y else Rect2(0, n, 0, 0)
		return r
	if not _is_native_android():
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
	return Rect2(left * k, top * k, right * k, bottom * k)


func _is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _is_native_android() -> bool:
	return OS.has_feature("android")


func _layout_game() -> void:
	if not is_node_ready() or not hud:
		return
	var column = game_layer.get_node("Column")
	if mode.kind == "tutorial":
		column.arrange_practice(board,hud,practice)
	else:
		column.arrange(board,hud,mode.id,_is_native_android(),get_viewport_rect().size,safe,record_bar)


func _fit_banner_text() -> void:
	var vs := get_viewport_rect().size
	%BannerTitle.add_theme_font_size_override("font_size", int(clampf(vs.x / 13.0, 34.0, 64.0)))
	if mode.id in ["classic", "bright", "tutorial"]:
		var width := maxf(100.0, minf(board.size.x, vs.x) / 1.08 - 36.0)
		var title_size: int = %BannerTitle.get_theme_font_size("font_size")
		var measured := (%BannerTitle as Label).get_theme_font("font").get_string_size(%BannerTitle.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		%BannerTitle.add_theme_font_size_override("font_size", maxi(16, floori(title_size * minf(1.0, width / maxf(measured, 1.0)))))
		var sub_width := 0.0
		for line in %BannerSub.text.split("\n"):
			sub_width = maxf(sub_width, UiKit.NUMBER_FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x)
		%BannerSub.add_theme_font_size_override("font_size", maxi(14, floori(30.0 * minf(1.0, width / maxf(sub_width, 1.0)))))
		banner.get_parent().queue_sort()
	else:
		%BannerSub.add_theme_font_size_override("font_size", 30)

func _feedback_exclusion() -> Rect2:
	if not banner or banner.modulate.a <= 0.03:
		return Rect2()
	var transform := board.get_global_transform().affine_inverse() * banner.get_global_transform()
	return (transform * Rect2(Vector2.ZERO, banner.size)).grow(12.0)


func _show_bonus_feedback(res: Dictionary, at: Vector2i) -> void:
	if not keeper.classic_bonus_combos:
		return
	# All values come from the completed hit. Presentation never calculates rewards.
	board.play_bonus_feedback(at, res, keeper.color_streak_kind, keeper.color_streak_hits,
		L.t("color_chain_start"), L.t("color_chain_length", {"n": keeper.color_streak_hits}), L.t("double_hit"),
		L.t("hit_total", {"n": res.points}))
	if int(res.color_streak_points) > 0:
		hud.pop(hud.chain_count,1.35)

## Presentation reset only; game/continue contracts own ScoreKeeper state.
func _reset_visual_feedback() -> void:
	if hud:
		hud.reset_feedback()
	board.clear_combo_feedback()
	if banner.has_meta("banner_tween"):
		var previous: Tween = banner.get_meta("banner_tween")
		if previous and previous.is_valid():
			previous.kill()
	banner.modulate.a = 0.0
