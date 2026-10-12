extends RefCounted
## On a freshly launched main menu, via Godot AI game_eval:
## load("res://tests/test_combo_ab.gd").new().run_suite(get_tree().current_scene)
## Real game handlers with deterministic game-time steps; restart the process afterwards.

var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func run_suite(main) -> Dictionary:
	if main.state != main.State.MENU or main._ab_active:
		return {"error": "Run on a freshly launched main menu."}
	checks = 0
	failures.clear()
	_check_keeper()
	check(main.ComboExperiment.variant == "" and main.ComboExperiment.window_seconds() == 3.5, "ordinary Classic defaults to 3.5 without selecting A/B")
	check(main.ComboExperiment.special_rules == "timed" and not main.ComboExperiment.fixed_layout and not main.ComboExperiment.is_read_only(), "ordinary Classic retains timed special rules, random layout and saving")
	var save = main.get_node("/root/Save")
	var progress = main.get_node("/root/Progress")
	var saved: Dictionary = save.cloud_data().duplicate(true)
	var files := {}
	for path in [save.PATH, progress.PATH]:
		files[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var reports := []
	var layouts := []
	for variant in ["A", "B"]:
		check(main.debug_start_combo_ab(variant, 42), variant + ": debug start")
		main._ab_run["automated_test"] = true
		var expected := 3.0 if variant == "A" else 3.5
		check(main.keeper.combo_window == expected, variant + ": configured window")
		check(not main.keeper.timed_special, variant + ": explicit A/B retains legacy special rules")
		check(main.keeper.tier_time == 2.0 and main.keeper.streak_time == 3.0, variant + ": explicit A/B retains legacy time rewards")
		check(main.logic.gems_left() == 270 and main.time_left == 120.0, variant + ": original board and timer")
		layouts.append(main.logic.cells.duplicate())
		check(not main.debug_start_combo_ab("B" if variant == "A" else "A", 7), variant + ": cannot switch during play")
		main._on_slot(main.logic.find_move())
		main._process(0.5)
		main._on_slot(main.logic.find_move())
		main._process(expected / 2.0)
		check(absf(main.combo_bar.value - 50.0) < 0.1, variant + ": half-window HUD")
		var paused_time: float = main.play_time
		main.pause_game()
		main._process(10.0)
		check(main.play_time == paused_time and main.keeper.combo == 2, variant + ": pause freezes combo")
		main._resume_play()
		await main.start_game("classic")
		main._ab_run["automated_test"] = true
		var steps := 0
		while main.state == main.State.PLAYING and steps < 300:
			if steps > 0:
				main._process(3.25)
			if main.state == main.State.PLAYING:
				main._on_slot(main.logic.find_move())
			steps += 1
		check(main.state == main.State.OVER, variant + ": normal completion")
		var report: Dictionary = main.last_combo_report.duplicate(true)
		reports.append(report)
		check(report.combo_window == expected and report.special_rules == "legacy", variant + ": report contains actual experimental rules")
		check(report.score == main.score and report.destroyed_gems == 270 - main.logic.gems_left(), variant + ": report totals")
		check(report.max_streak == main.keeper.best_combo and report.combo_breaks == main.keeper.combo_breaks, variant + ": report series")
		check(report.hits_at_x4 == main.keeper.hits_at_x4 and report.end_reason == main.end_reason, variant + ": report x4 and reason")
		check(is_equal_approx(report.time_left, maxf(0.0, main.time_left)), variant + ": report time")
		check(main.last_earned == 0 and not main.ui.over_best.visible, variant + ": no rewards or record")
		var report_file := FileAccess.get_file_as_string(main.ComboExperiment.REPORT_PATH)
		var lines := report_file.strip_edges().split("\n")
		check(JSON.parse_string(lines[-1]) is Dictionary and lines[-1] == JSON.stringify(report), variant + ": JSONL round-trip")
		main._report_combo_ab("quit")
		check(FileAccess.get_file_as_string(main.ComboExperiment.REPORT_PATH) == report_file, variant + ": no duplicate result")
	check(layouts[0] == layouts[1], "A/B initial cells identical")
	check(reports[0].layout_sha256 == reports[1].layout_sha256, "A/B layout hash identical")
	check(reports[0].max_streak == 1 and reports[0].hits_at_x4 == 0, "A: 3.25-second gaps expire combo")
	check(reports[1].max_streak >= 9 and reports[1].hits_at_x4 > 0, "B: 3.25-second gaps preserve combo")
	check(save.cloud_data() == saved, "Classic A/B changes no records or progress in memory")
	check(not save.submit(999999999, "classic"), "record submission blocked")
	check(not save.submit_daily(999999999, "2099-01-01"), "daily record submission blocked")
	save.store()
	progress._save()
	for path in files:
		var after := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		check(after == files[path], path + ": unchanged after games and save attempts")
	await main.start_game("bright")
	check(not main._ab_active and main.keeper.combo_window == 3.0, "Bright window unchanged")
	main.go_menu()
	check(main.ComboExperiment.is_read_only(), "write lock survives leaving Classic")
	return {"checks": checks, "failed": failures.size(), "failures": failures, "reports": reports}


func _check_keeper() -> void:
	check(ScoreKeeper.new().combo_window == 3.0, "original default")
	for window in [3.0, 3.5]:
		var k := ScoreKeeper.new()
		k.combo_window = window
		k.hit(2, 0.0)
		k.hit(2, 1.0)
		check(not k.update(1.0 + window), "exact boundary inclusive")
		check(k.update(1.001 + window) and k.combo_breaks == 1, "timeout counted")
		k.update(20.0)
		k.miss()
		check(k.combo_breaks == 1, "no double-count")
		k.reset()
		k.hit(2, 0.0)
		k.hit(2, 1.0)
		var r := k.hit(2, 1.001 + window)
		check(r.combo == 1 and k.combo_breaks == 1, "hit expires without process tick")
		k.reset()
		k.hit(2, 0.0)
		check(not k.miss() and k.combo_breaks == 0, "single hit is not established combo")
		for i in 10:
			k.hit(2, float(i))
		check(k.hits_at_x4 == 2 and k.best_combo == 10, "every x4 hit counted")
		k.miss()
		check(k.combo_breaks == 1, "miss counted")
		k.reset()
		check(k.combo_breaks == 0 and k.hits_at_x4 == 0, "counters reset")
	var a := ScoreKeeper.new()
	var b := ScoreKeeper.new()
	b.combo_window = 3.5
	for i in 15:
		check(a.hit(3 if i % 5 != 0 else 2, i * 0.5, i % 2) == b.hit(3 if i % 5 != 0 else 2, i * 0.5, i % 2),
			"points, multipliers and bonuses identical within both windows")
