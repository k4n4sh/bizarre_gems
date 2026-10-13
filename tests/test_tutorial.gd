extends RefCounted
## Full tutorial through the production strike/clock/wave paths, with isolated saves.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func gameplay_progress(progress) -> Dictionary:
	var data: Dictionary = progress.to_dict().duplicate(true)
	data.erase("tutorial")
	data.erase("tutorial_skipped")
	return data

func move(main) -> Vector2i:
	var at: Vector2i = main._tutorial_target()
	return main.logic.find_move() if at.x < 0 else at

func settle_wave(main) -> void:
	await main.get_tree().create_timer(1.4).timeout
	check(not main.dealing, "mandatory practice deal completes")

func run_suite(main) -> Dictionary:
	var save = main.get_node("/root/Save")
	var progress = main.get_node("/root/Progress")
	var locale = main.get_node("/root/L")
	if not save.PATH.begins_with("res://.test-user/") or not progress.PATH.begins_with("res://.test-user/"):
		return {"error": "Use the isolated fixture in test_classic_bonus_combos.ps1."}
	var before := gameplay_progress(progress)
	var records := [save.best, save.best_bright, save.best_zen, save.daily_best, save.mode]
	progress.tutorial = false
	progress.tutorial_skipped = false
	for key in locale.S:
		if str(key).begins_with("lesson_"):
			for language in locale.SUPPORTED:
				check(locale.S[key].has(language), "complete translation " + key + "/" + language)
	await main.start_game("tutorial")
	check(main.logic.gems_left() == 8, "original opening board retained")
	check(main.keeper.timed_special and main.keeper.combo_window == 3.5, "modern combo rules in tutorial")
	for index in main.TutorialLessons.STEPS.size():
		var id: String = main._tutorial_id()
		check(main.tut_step == index and not main.tut_waiting and main.score == 0, "clean start " + id)
		var cells: PackedInt32Array = main.logic.cells.duplicate()
		var clock: float = main.play_time
		var seconds: float = main.time_left
		main._process(30.0)
		check(main.play_time == clock and main.time_left == seconds and main.logic.cells == cells, "no time pressure " + id)
		main._on_slot(Vector2i(-1, -1))
		for y in 5:
			for x in 5:
				if not main.logic.is_empty(Vector2i(x, y)):
					main._on_slot(Vector2i(x, y))
		check(main.logic.cells == cells and main.tut_hits == 0 and main.score == 0, "occupied/bounds input cannot progress " + id)
		var target := move(main)
		for y in 5:
			for x in 5:
				var wrong := Vector2i(x, y)
				if main.logic.is_empty(wrong) and wrong != target and (id != "free" or main.logic.matches_from(wrong).is_empty()):
					main._on_slot(wrong)
		check(main.logic.cells == cells and main.tut_hits == 0 and main.play_time == clock, "wrong input cannot consume a fixture " + id)
		main._tutorial_help()
		check(main.board._hint.x >= 0, "hint available without spending tokens " + id)
		for hit in main.TutorialLessons.goal(id):
			var at := move(main)
			check(main.logic.in_bounds(at) and main.logic.is_empty(at), "playable target " + id + str(hit))
			var n: int = main.logic.matches_from(at).size()
			check(n == 0 if id == "miss" else n >= 2, "real match/miss " + id + str(hit))
			if id == "empty":
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				click.position = main.board.slot_center(at)
				main.board._gui_input(click)
			else:
				main._on_slot(at)
			if id in ["run", "clear"]:
				var reward_time: float = main.time_left
				var reward_score: int = main.score
				main._next_wave(at)
				main._process(100.0)
				check(main.time_left == reward_time and main.score == reward_score, "wave awards once and freezes clocks")
				await settle_wave(main)
				check(main.keeper._double_hit_slot.x == -1, "wave clears pending double hit")
			if id == "box" and hit == 0:
				check(main.tut_last_result.removed == 0 and main.logic.gems_left() == 2, "first box hit cracks, not removes")
			if id == "chameleon" and hit == 2:
				check(main.logic.kind_at(Vector2i(1, 4)) == 1, "real third-hit colour shift retained")
			if id == "special" and hit in [1, 3]:
				check(main.keeper.precise_streak == (1 if hit == 1 else 2), "pair retains special progress")
				check(is_equal_approx(main.keeper.special_window_left(main.play_time), 5.25), "pair extends the live special deadline")
			if id == "special" and hit == 4:
				check(main.tut_last_result.event == "precise", "third large hit awards precise")
		if id in ["timeout", "clock"]:
			check(main.tut_clock_running and not main.tut_waiting, "explicit clock exercise " + id)
			clock = main.play_time
			main.pause_game()
			main._process(60.0)
			check(main.play_time == clock and not main.tut_card.visible, "pause freezes exercise")
			main._resume_play()
			check(not main.board.interactive, "resumed clock does not allow extra strikes")
			main._process(3.5001 if id == "timeout" else 1.6)
		check(main.tut_waiting and not main.board.interactive, "lesson completed " + id)
		var result_score: int = main.score
		main._on_slot(target)
		check(main.score == result_score, "double click cannot consume next lesson " + id)
		var saved_language: String = locale.lang
		var saved_cells: PackedInt32Array = main.logic.cells.duplicate()
		locale.set_language("en" if saved_language != "en" else "ru")
		check(main.tut_waiting and main.tut_step == index and main.logic.cells == saved_cells and main.score == result_score, "language change preserves progress " + id)
		check(not main.tut_label.text.contains("{") and main.ui.run_best_caption.text == locale.t("lesson_practice"), "translated result and practice caption " + id)
		locale.set_language(saved_language)
		match id:
			"cross": check(main.tut_last_result.removed == 4 and main.score == 6 and main.time_left == 122, "mixed four-gem real reward")
			"miss": check(main.time_left == 119 and main.keeper.combo == 0, "real miss penalty")
			"streak": check(main.keeper.combo == 9 and main.tut_last_result.mult == 4, "all multiplier thresholds practised")
			"timeout": check(main.keeper.combo == 0 and main.keeper.combo_breaks == 1, "real series expiry")
			"special": check(main.keeper.precise_events == 1 and main.keeper.perfect_events == 1 and main.keeper.precise_streak == 0, "real special cycle resets after perfect")
			"double": check(main.tut_last_result.double_hit_points == 2 and main.score == 8, "real double-hit bonus")
			"color": check(main.keeper.color_streak_hits == 3 and main.tut_last_result.color_streak_points == 4, "real colour-chain continuation")
			"shine": check(main.score == 7 and main.time_left == 122, "real sparkle rewards")
			"classic": check(main.logic.gems_left() == 1 and not main.logic.has_any_move(), "Classic ends on a stranded gem")
			"joker": check(main.tut_last_result.removed == 2 and main.keeper._previous_color_points.has(0) and main.time_left == 120, "joker effective colour and Run time rule")
			"box": check(main.tut_last_result.double_hit_points == 0 and main.logic.gems_left() == 0, "cracking cannot prime removal bonus")
			"link": check(main.tut_last_result.removed == 3 and main.score == 6, "real linked-removal scoring")
			"run": check(main.wave == 2 and main.time_left == 160, "stuck Run board pays 40 seconds")
			"clear": check(main.wave == 5 and main.time_left == 300, "four real full-clear rewards")
			"clock": check(main.time_left == 0 and progress.tutorial, "time ending completes tutorial")
		check(gameplay_progress(progress) == before and [save.best, save.best_bright, save.best_zen, save.daily_best, save.mode] == records, "no player rewards/records changed " + id)
		main.tut_next.pressed.emit()
	check(main.state == main.State.MENU and main.mode_panel.visible and not main.tut_card.visible, "completion opens modes")
	await main.start_game("tutorial")
	check(main.tut_step == 0 and main.score == 0 and main.tut_hits == 0 and main.logic.gems_left() == 8, "replay starts clean")
	main._on_slot(move(main))
	main.ui.tut_retry.pressed.emit()
	check(main.tut_step == 0 and main.tut_hits == 0 and main.logic.gems_left() == 8 and main.score == 0, "retry restores whole lesson")
	progress.tutorial = false
	main.ui.tut_skip.pressed.emit()
	check(progress.tutorial_skipped and not progress.tutorial and main.mode_panel.visible, "skip does not claim completion")
	main.go_menu()
	main.ui.btn_home_play.pressed.emit()
	check(main.mode_panel.visible and main.state == main.State.MENU, "skip bypasses first-run gate")
	main.ui.btn_tutorial.pressed.emit()
	check(main.mode.kind == "tutorial" and main.tut_step == 0, "existing Rules replay entry works")
	main.ui.tut_exit.pressed.emit()
	check(main.state == main.State.MENU and not main.tut_hand.visible, "explicit exit works")
	# Cancel a live wave: its delayed callback must not modify a newer session.
	await main.start_game("tutorial")
	main._tutorial_step(main.TutorialLessons.STEPS.find("clear"))
	main._on_slot(move(main))
	await main.start_game("classic")
	var newer_cells: PackedInt32Array = main.logic.cells.duplicate()
	await settle_wave(main)
	check(main.mode.id == "classic" and main.logic.cells == newer_cells and main.score == 0 and main.time_left == 120, "stale tutorial wave cannot alter a new game")
	main.go_menu()
	return {"checks": checks, "failed": failures.size(), "failures": failures}
