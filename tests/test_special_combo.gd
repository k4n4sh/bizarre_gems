extends RefCounted
## Pure rules: run_rules(). Runtime fixtures: run_in_game(main) on a fresh main menu.
## Runtime test opts into read-only Classic; restart the game afterwards.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func keeper() -> ScoreKeeper:
	var k := ScoreKeeper.new()
	k.configure_time_rewards(true)
	k.combo_window = ScoreKeeper.CLASSIC_COMBO_WINDOW
	k.timed_special = true
	return k

func sequence(k: ScoreKeeper, hits: Array, gap := 1.0) -> Array:
	var events := []
	for i in hits.size():
		events.append(k.hit(hits[i], i * gap).event)
	return events

func run_rules() -> Dictionary:
	checks = 0
	failures.clear()
	var k := keeper()
	check(k.combo_window == 3.5 and ScoreKeeper.SPECIAL_WINDOW == 5.0, "Classic defaults are 3.5 ordinary / 5.0 special seconds")
	k.hit(3, 0.0)
	check(k.special_window_left(0.0) == 5.0, "first unique action starts a five-second window")
	var pair := k.hit(2, 1.0)
	check(k.window_left(1.0) == 3.5 and k.special_window_left(1.0) == 4.5, "pair refreshes ordinary clock and extends separate special clock")
	check(k.precise_streak == 1 and pair.event == "", "ordinary hit preserves unique count without a special reward")
	k.reset()
	check(sequence(k, [3, 3, 3]) == ["", "", "precise"], "3/3/3 Precise")
	check(k.precise_streak == 3 and k.special_window_left(2.0) == 5.0, "3+ resets deadline to five seconds")
	k.reset()
	check(sequence(k, [3, 3, 3, 3]) == ["", "", "precise", "perfect"], "four hits Precise then Perfect")
	check(k.precise_streak == 0 and k.special_window_left(3.0) == 0.0, "Perfect clears progress and clock")
	k.reset()
	check(sequence(k, [3, 2, 3, 2, 3]) == ["", "", "", "", "precise"], "pairs preserve special progress")
	k.reset()
	k.hit(3, 0.0)
	for i in range(1, 11):
		var now := i * 0.1
		var before := k.special_window_left(now)
		k.hit(2, now)
		check(is_equal_approx(k.special_window_left(now) - before, 0.5), "pair %d adds exactly 0.5" % i)
		check(k.precise_streak == 1, "pair %d does not advance progress" % i)
	check(k.special_window_left(1.0) == 9.0, "ten extensions have no time or count cap")
	k.reset()
	k.hit(3, 0.0)
	k.hit(2, 2.0)
	check(k.special_window_left(2.0) == 3.5, "two seconds spent minus half-second extension")
	# Last pair at 3s keeps the ordinary clock alive at the special deadline of 5.5s.
	for end_time in [5.499, 5.5, 5.501]:
		k.reset()
		k.hit(3, 0.0)
		k.hit(2, 3.0)
		k.hit(2, end_time)
		check(k.precise_streak == (1 if end_time < 5.5 else 0), "special boundary %.3f before extending" % end_time)
		check(k.combo == 3, "special expiry does not break ordinary combo")
	k.reset()
	k.hit(3, 0.0)
	k.hit(2, 3.0)
	k.update(5.5)
	check(k.precise_streak == 0 and k.combo == 2, "frame update expires special independently")
	k.hit(3, 5.5)
	check(k.precise_streak == 1, "3+ after special expiry starts fresh")
	k.reset()
	k.hit(3, 0.0)
	check(k.hit(3, 3.5).combo == 2 and k.precise_streak == 2, "ordinary exact 3.5 remains inclusive")
	check(k.update(7.0001) and k.precise_streak == 0, "ordinary expiry clears special")
	k.reset()
	k.hit(3, 0.0)
	k.hit(3, 3.5001)
	check(k.combo == 1 and k.precise_streak == 1, "late hit resets before starting new cycle")
	k.miss()
	check(k.combo == 0 and k.precise_streak == 0 and k.special_window_left(3.0) == 0, "miss clears both")
	k.reset()
	k.hit(3, 0.0)
	k.hit(2, 3.25)
	check(k.combo == 2 and k.precise_streak == 1 and k.special_window_left(3.25) == 2.25, "pair within restored 3.5 window preserves special series")
	k.reset()
	k.hit(3, 0.0)
	k.hit(2, 3.5001)
	check(k.combo == 1 and k.precise_streak == 0 and k.special_window_left(3.5001) == 0, "pair after ordinary 3.5 window cannot preserve or revive special series")
	k.reset()
	check(sequence(k, [3,3,3,3,2,3,3,3,3]) == ["","","precise","perfect","","","","precise","perfect"], "two independent cycles")
	check(k.precise_events == 2 and k.perfect_events == 2 and k.precise_count == 4, "separate event counters")
	check(k.special_bonus_points == 60 and k.special_bonus_time == 16.0, "exact cumulative special rewards")
	k.reset()
	var results := []
	for i in 4:
		results.append(k.hit(3, float(i), 1))
	check(results[2].points == 23 and results[2].time == 6.0, "Precise: base x2 +10 +shine; base time +3 +shine")
	check(results[3].points == 33 and results[3].time == 8.0, "Perfect: base x2 +20 +shine; base time +5 +shine")
	check(k.hit(3, 4.0).event == "" and k.precise_streak == 1, "fifth triple cannot repeat Perfect")
	k.reset()
	check(sequence(k, [4,4,4,4]) == ["","","precise","perfect"], "four-gem strikes qualify")
	check(k.score == 72 and k.special_bonus_points == 30, "four-gem base scores and special rewards")
	var old := ScoreKeeper.new()
	check(sequence(old, [3,2,3,3]) == ["","","",""], "legacy pairs still reset")
	old.reset()
	check(sequence(old, [3,3,3,3,3]) == ["","","precise","perfect","perfect"], "legacy repeated Perfect retained")
	old.reset()
	old.time_bonuses = false
	sequence(old, [3,3])
	var r := old.hit(3, 2.0)
	check(r.points == 18 and r.time == 1.0 and old.special_bonus_time == 0, "Bright special points retained; extra seconds disabled")
	k.reset()
	check(k.precise_count == 0 and k.precise_events == 0 and k.perfect_events == 0 and k.special_bonus_time == 0, "round reset clears telemetry")
	return {"checks": checks, "failed": failures.size(), "failures": failures}

func fixture(main, n: int) -> void:
	var rows := [".1...", "1.1..", ".....", "2.2.."] if n == 3 else ["1.1..", ".....", ".....", "2.2.."]
	if n == 4:
		rows = [".1...", "2.2..", ".1...", "3.3.."]
	var cells := PackedInt32Array()
	for row in rows:
		for ch in row:
			cells.append(-1 if ch == "." else int(ch))
	main.logic.load_cells(5, 4, cells)
	main.board.refresh()
	main._on_slot(Vector2i(1, 1) if n >= 3 else Vector2i(1, 0))

func run_in_game(main) -> Dictionary:
	checks = 0
	failures.clear()
	if main.state != main.State.MENU or main._ab_active:
		return {"error": "Fresh main menu required."}
	var save = main.get_node("/root/Save")
	var progress = main.get_node("/root/Progress")
	var before: Dictionary = save.cloud_data().duplicate(true)
	var hashes := {}
	for path in [save.PATH, progress.PATH]:
		hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	main.ComboExperiment.select_special("timed", 42)
	await main.start_game("classic")
	check(main.keeper.combo_window == 3.5 and main.keeper.timed_special and main._ab_active, "explicit special experiment retains 3.5 window and isolates saves")
	check(main.ComboExperiment.fixed_layout, "explicit experiment uses its fixed seed")
	main.go_menu()
	var observations := []
	for hits in [[3,3,3], [3,3,3,3], [3,2,3,2,3], [3,3,3,3,3,3,3,3]]:
		check(main.debug_start_special_combo("timed", 42), "start special test")
		main._ab_run["fixture_test"] = true
		for n in hits:
			main._process(1.0)
			fixture(main, n)
		var want_perfect := 2 if hits.size() == 8 else (1 if hits.size() == 4 else 0)
		var want_precise := 2 if hits.size() == 8 else 1
		check(main.keeper.precise_events == want_precise and main.keeper.perfect_events == want_perfect, "real handler events " + str(hits))
		var left: float = main.keeper.special_window_left(main.play_time)
		var clock: float = main.play_time
		main.pause_game()
		main._process(20.0)
		check(main.play_time == clock and main.keeper.special_window_left(main.play_time) == left, "pause freezes both clocks")
		main._resume_play()
		observations.append({"hits": hits, "precise": main.keeper.precise_events, "perfect": main.keeper.perfect_events,
			"score": main.score, "special_points": main.keeper.special_bonus_points, "special_seconds": main.keeper.special_bonus_time})
		main.go_menu()
	# A real miss clears both clocks.
	main.debug_start_special_combo("timed", 42)
	main._ab_run["fixture_test"] = true
	fixture(main, 3)
	fixture(main, 3)
	main._on_slot(Vector2i(4, 2))
	check(main.keeper.combo == 0 and main.keeper.precise_streak == 0, "real handler miss clears both")
	main.go_menu()
	check(save.cloud_data() == before, "Classic results do not change progress or records")
	for is_daily in [false, true]:
		await main.start_game("bright", is_daily)
		check(main.keeper.timed_special and main.keeper.combo_window == 3.5 and not main._ab_active, "Bright/Daily share current combo rules")
		for n in [3,2,3,3]:
			fixture(main, n)
		check(main.keeper.precise_events == 1, "Bright/Daily pair preserves special progress")
		main.keeper.reset()
		for n in [3,3,3,3,3]:
			fixture(main, n)
		check(main.keeper.precise_events == 1 and main.keeper.perfect_events == 1, "Bright/Daily Perfect completes its cycle")
		main.go_menu()
	save.store()
	progress._save()
	for path in hashes:
		check(hashes[path] == (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""), "unchanged save file " + path)
	return {"checks": checks, "failed": failures.size(), "failures": failures, "observations": observations}
