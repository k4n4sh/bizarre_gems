extends "res://tests/test_combo_runtime.gd"
## Refinement waves/continuation/transition regressions adapted to upstream scenes.
## Daily rollover and Challenge tests cover the new pinned-date/seed contracts.

func ready_deal(main) -> void:
	for i in 300:
		if not main.dealing and not main._run_starting:
			return
		await main.get_tree().process_frame
	check(false, "deal completes within 300 frames")

func digest(b: BoardLogic) -> String:
	return (str(b.cells) + str(b.shine) + str(b.hp) + str(b.chain) + str(b.ice) + str(b.bomb) + str(b.cham)).sha256_text()

func reference_board(day: String, wave: int, transpose: bool) -> BoardLogic:
	var r := RandomNumberGenerator.new()
	r.seed = hash("bizarre-gems-%s-bright-%d" % [day, wave])
	var d := BoardLogic.best_dims(Vector2(360, 640), 200)
	var b := BoardLogic.new()
	b.setup_tuned(d.x, d.y, r, BoardLogic.BRIGHT.shining, 6, 28, 4, 999, 30, true, 0.1, 5)
	b.add_chains(r, 3)
	b.add_chameleons(r, 2)
	if transpose:
		b.transpose()
	return b

func waves(main) -> void:
	Engine.time_scale = 20.0
	for full_clear in [false, true]:
		await start(main, "bright")
		for completed in range(1, 13):
			var triple: Array[int] = [0, 0, 0]
			var pair: Array[int] = [0, 0]
			var mixed: Array[int] = [0, 0, 1, 1]
			main.keeper.reset()
			main.keeper.hit(3, main.play_time, 0, A, triple)
			main.keeper.hit(2, main.play_time, 0, B, pair)
			main.keeper.hit(4, main.play_time, 0, A, mixed)
			main.score = main.keeper.score
			var before := snapshot(main)
			if full_clear:
				main.logic.cells.fill(BoardLogic.EMPTY)
			var seconds: float = main.time_left
			var points: int = main.score
			main._next_wave(A)
			var expected := 40 if completed == 1 else (30 if completed == 2 else (20 if completed == 3 else 10))
			check(main.time_left == seconds + expected + (20 if full_clear else 0), "transition %d clear=%s exact seconds" % [completed, full_clear])
			check(main.score == points + (100 + 50 * (completed - 1) if full_clear else 0), "Full Clear points %d clear=%s" % [completed, full_clear])
			before.slot = Vector2i(-1, -1)
			check(snapshot(main) == before, "transition preserves all non-positional states")
			seconds = main.time_left
			main._process(60.0)
			check(main.time_left == seconds and snapshot(main) == before, "mandatory transition freezes clocks")
			main._next_wave(A)
			check(main.wave == completed + 1 and main.time_left == seconds, "duplicate transition gives no reward")
			var sub: Label = main.banner.get_node("BannerSub")
			check(sub.text.contains("+%d" % expected) and (not full_clear or sub.text.contains("+20")), "banner states actual time economy")
			await ready_deal(main)
			check(snapshot(main) == before and main.board.interactive, "deal preserves remaining windows and enables input")
			var next_color := 1 if completed % 2 == 0 else 0
			var next_pair: Array[int] = [next_color, next_color]
			fixture(main, next_pair)
			main._on_slot(A)
			check(receipt(main).double_hit_points == 0 and main.keeper.color_streak_kind == next_color
				and main.keeper.color_streak_hits == (2 if next_color == 1 else 4), "new field uses unpaid mixed color without Double Hit")
		main.go_menu()
	Engine.time_scale = 1.0

func automatic_transitions(main) -> void:
	Engine.time_scale = 20.0
	await start(main, "bright")
	main.logic.load_cells(3, 1, PackedInt32Array([0, -1, 0]))
	main._on_slot(Vector2i(1, 0))
	check(main.cleared == 2 and main.wave == 2 and main.dealing and not main.board.interactive,
		"actual last strike enters a locked field transition")
	check(main.time_left == 180 and main.score == main.keeper.score and main.score == 102,
		"actual last strike grants first-board/full-clear time and score once")
	check(main.keeper.combo == 1 and main.keeper._double_hit_slot == Vector2i(-1, -1),
		"actual last strike retains combo and drops positional state")
	await ready_deal(main)
	check(main.logic.has_any_move() and main.board.interactive, "automatic clear transition deals playable board")
	main.go_menu()
	await start(main, "bright")
	main.logic.load_cells(3, 1, PackedInt32Array([0, -1, 1]))
	main._check_no_moves()
	check(main.wave == 2 and main.dealing and main.time_left == 160 and main.score == 0,
		"actual no-moves branch gives transition time without full-clear rewards")
	main._on_slot(Vector2i(1, 0))
	check(main.score == 0 and main.keeper.combo == 0, "mandatory transition rejects strikes")
	await ready_deal(main)
	main.go_menu()
	Engine.time_scale = 1.0

func daily_rollover(main) -> void:
	var save = main.get_node("/root/Save")
	var progress = main.get_node("/root/Progress")
	var ad = main.get_node("/root/Yandex")
	ad.set_script(load("res://tests/run_flow_ad_fixture.gd"))
	main.test_day = "2026-10-14"
	progress.daily_reward_date = "2026-10-13"
	# A date change during the asynchronous first layout must not change even board one.
	main.start_game("bright", true)
	main.test_day = "2026-10-15"
	await ready_deal(main)
	check(main.daily_run_date == "2026-10-14", "UTC date fixed before asynchronous first deal")
	for wave in range(1, 5):
		if wave > 1:
			main._next_wave(A)
			Engine.time_scale = 20.0
			await ready_deal(main)
			Engine.time_scale = 1.0
		check(digest(main.logic) == digest(reference_board("2026-10-14", wave, main._daily_transposed)), "Daily wave %d still uses original UTC date" % wave)
	main.score = 123
	main.keeper.score = 123
	main.end_game("time")
	check(save.daily_date == "2026-10-14" and save.daily_best_for("2026-10-14") == 123, "Daily record written to party date")
	check(progress.daily_reward_date == "2026-10-14" and main.last_earned >= progress.DAILY_CRYSTALS, "Daily reward belongs to party date")
	check(main.result.get_node("%Line").text.contains("123"), "Daily result reads party-date record")
	var crystals: int = progress.crystals
	main._on_continue()
	ad.resolve_reward(true)
	await settle(main)
	check(main.state == main.State.PLAYING and main.daily_run_date == "2026-10-14", "continue after midnight retains Daily date")
	main.end_game("time")
	check(progress.crystals == crystals, "continued Daily never pays same score/date twice")
	await start(main, "bright", true)
	check(main.daily_run_date == "2026-10-15" and digest(main.logic) == digest(reference_board("2026-10-15", 1, main._daily_transposed)), "new Daily adopts current UTC date")
	main.end_game("time")
	check(progress.daily_reward_date == "2026-10-15", "new day earns its own daily reward")
	check(progress.pay_daily("2026-10-14") == 0 and progress.daily_reward_date == "2026-10-15", "late older date cannot rewind daily reward marker")
	main.go_menu()
	# The retained hidden Classic Daily also uses its start-date seed.
	main.test_day = "2026-10-16"
	await start(main, "classic", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bizarre-gems-2026-10-16-classic-1")
	var b := BoardLogic.new()
	b.setup(22, 14, rng, 8, 10, 24)
	check(digest(main.logic) == digest(b), "Classic Daily canonical seeded generation retained")
	main.test_day = "2026-10-17"
	main._deal_board()
	check(digest(main.logic) == digest(b), "Classic Daily redeal retains pinned date")
	main.go_menu()

func challenges(main) -> void:
	var ad = main.get_node("/root/Yandex")
	for id in ["classic", "bright"]:
		await start(main, id)
		var hashes: Array[String] = [digest(main.logic)]
		var shape: Vector2i = main.board_dims
		var seed: int = main.game_seed
		main.score = 456
		main._share_challenge()
		await settle(main)
		var payload: Dictionary = main.parse_challenge(ad.shared_payload)
		check(not payload.is_empty() and payload.mode == id and payload.seed == seed and payload.dims == shape and payload.score == 456, id + " Share round-trip includes seed/shape/target")
		check(ad.shared_text.contains("456"), "Share localized target text")
		if id == "bright":
			for wave in range(2, 5):
				main._next_wave(A)
				Engine.time_scale = 20.0
				await ready_deal(main)
				Engine.time_scale = 1.0
				hashes.append(digest(main.logic))
				check(main._run_dims == shape, "Run Share shape stays fixed")
		main.go_menu()
		# Replaying a challenge from another viewport must reproduce all board data.
		var tree: SceneTree = main.get_tree()
		var original_size := tree.root.size
		tree.root.size = Vector2i(480, 1008)
		await start(main, id, false, payload)
		for wave in range(1, hashes.size() + 1):
			if wave > 1:
				main._next_wave(A)
				Engine.time_scale = 20.0
				await ready_deal(main)
				Engine.time_scale = 1.0
			var canonical: BoardLogic = main.logic
			# Classic keeps upstream's screen-fit transpose; compare in shared orientation.
			if id == "classic" and main.logic.cols != shape.x:
				canonical = BoardLogic.new()
				canonical.load_cells(main.logic.cols, main.logic.rows, main.logic.cells)
				for prop in ["shine", "hp", "chain", "ice", "bomb", "cham"]:
					canonical.set(prop, main.logic.get(prop).duplicate())
				canonical.transpose()
			check(digest(canonical) == hashes[wave - 1], "%s Challenge wave %d reproduces full seeded data" % [id, wave])
			check(main.keeper.timed_special and main.keeper.classic_bonus_combos, "Challenge uses approved combo rules")
			if id == "bright":
				check(not main.logic.has_bombs() and not main.logic.ice.has(1), "Run Challenge hazards disabled")
		main.score = 457
		main.keeper.score = 457
		main.end_game("time")
		check(main.result.get_node("%Line").text.contains(main.get_node("/root/L").t("ch_won", {"n": 456})), "Challenge target result retained")
		main.go_menu()
		tree.root.size = original_size
		await settle(main)
	for invalid in ["", "c1-zen-42-10-20-100", "c1-bright-42-3-3-100", "c1-classic-42-10-20-100",
			"c1-bright-4294967296-10-20-100", "c1-classic-42-1001-3-100", "c1-bright-X-10-20-100",
			"c1-bright-42-12-14-100", "c1-classic-42-4294967319-15-100"]:
		check(main.parse_challenge(invalid).is_empty(), "invalid/undersized challenge rejected: " + invalid)

func paused_hint_reward(main) -> void:
	var ad = main.get_node("/root/Yandex")
	await start(main, "bright")
	main.hints = 0
	main.get_node("/root/Progress").hint_tokens = 0
	main._use_hint()
	main._on_platform_pause()  # Real SDK pauses a running game during its video.
	var before := snapshot(main)
	ad.resolve_reward(true)
	await settle(main)
	check(main.state == main.State.PAUSED and main.logic.in_bounds(main.board._hint)
		and main.logic.matches_from(main.board._hint).size() >= 2, "same-game paid hint survives platform ad pause")
	main._process(60.0)
	check(snapshot(main) == before and main.time_left == 120, "ad pause preserves all Run clocks")
	main._on_platform_resume()
	main.go_menu()

func stale_callbacks(main) -> void:
	var ad = main.get_node("/root/Yandex")
	for action in ["_on_continue", "_on_shuffle", "_on_again", "_on_level_continue", "_on_double", "_use_hint"]:
		await start(main, "levels" if action == "_on_level_continue" else "bright")
		if action == "_use_hint":
			main.hints = 0
			main.get_node("/root/Progress").hint_tokens = 0
		else:
			main.end_game("stuck" if action == "_on_shuffle" else "time")
			if action == "_on_double":
				main.last_earned = 10
		main.call(action)
		await start(main, "bright")
		var before := digest(main.logic)
		var generation: int = main._game_generation
		var crystals: int = main.get_node("/root/Progress").crystals
		var hint: Vector2i = main.board._hint
		if action == "_on_again":
			ad.resolve_fullscreen()
		else:
			ad.resolve_reward(true)
		await settle(main)
		check(main._game_generation == generation and digest(main.logic) == before and main.time_left == 120
			and not main.used_continue and not main.used_shuffle, action + " stale callback cannot mutate new Run")
		check(main.get_node("/root/Progress").crystals == crystals and main.board._hint == hint,
			action + " stale callback cannot pay currency or reveal a new board's hint")
	main.go_menu()
	Engine.time_scale = 20.0
	for id in ["levels", "puzzle", "tutorial"]:
		await start(main, id)
		main.logic.load_cells(3, 1, PackedInt32Array([0, -1, 0]))
		if id == "tutorial":
			main.tut_step = 3
		main._on_slot(Vector2i(1, 0))
		await start(main, "bright")
		var before := digest(main.logic)
		await main.get_tree().create_timer(2.0).timeout
		check(main.state == main.State.PLAYING and main.wave == 1 and digest(main.logic) == before,
			id + " old completion tween cannot end a new Run")
		check(not main.tut_label.visible and not main.tut_hand.visible, "previous tutorial overlay never leaks into Run")
		main.go_menu()
	Engine.time_scale = 1.0

func transitions(main) -> void:
	# Headless portion of refinement test_mode_transition; native canvas/audio later.
	for is_daily in [false, true]:
		for keyboard in [false, true]:
			await start(main)
			var old_slot := Vector2i(main.logic.cols - 1, main.logic.rows - 1)
			main.board._hover = old_slot
			main.board._cursor = old_slot
			main.board._keyboard = keyboard
			main.go_menu()
			await start(main, "bright", is_daily)
			check(not main.logic.in_bounds(old_slot), "transition uses smaller field")
			var focus: Vector2i = main.board._cursor if keyboard else main.board._hover
			check(focus == Vector2i(-1, -1) or main.logic.in_bounds(focus), "refresh clears invalid cached coordinate")
			var presses: Array[Vector2i] = []
			var collect := func(p: Vector2i): presses.append(p)
			main.board.slot_pressed.connect(collect)
			main.board._cursor = old_slot
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.pressed = true
			main.board._gui_input(key)
			check(presses.is_empty(), "stale keyboard cursor cannot emit invalid strike")
			main.board._cursor = main.logic.find_move()
			main.board._gui_input(key)
			check(presses.size() == 1 and main.score > 0, "valid keyboard strike still works")
			main.board.slot_pressed.disconnect(collect)
			main.go_menu()

func run_suite(main) -> Dictionary:
	if not main.has_node("/root/TestIsolation"):
		return {"error": "Use the isolated test runner."}
	await waves(main)
	await automatic_transitions(main)
	await daily_rollover(main)
	await challenges(main)
	await paused_hint_reward(main)
	await stale_callbacks(main)
	await transitions(main)
	main.get_node("/root/Yandex").set_script(load("res://scripts/yandex.gd"))
	return {"checks": checks, "failed": failures.size(), "failures": failures}
