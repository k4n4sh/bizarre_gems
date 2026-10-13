extends RefCounted
## Short deterministic checks; run_runtime_suite.gd in an isolated project/profile.
## Tests ordinary startup before any explicit experiment enables the write lock.

var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func run_suite(main) -> Dictionary:
	checks = 0
	failures.clear()
	if main.state != main.State.MENU or main.ComboExperiment.is_read_only():
		return {"error": "Fresh ordinary main menu required; use an isolated test profile."}
	if not main.get_node("/root/Save").PATH.begins_with("res://.test-user/") \
			or not main.get_node("/root/Progress").PATH.begins_with("res://.test-user/"):
		return {"error": "Use the isolated fixture created by tests/test_mode_records.ps1."}
	check(main.ComboExperiment.variant == "" and main.ComboExperiment.window_seconds() == 3.5,
		"ordinary startup uses 3.5 seconds without selecting an experiment")
	_rules()
	# A single keeper is reused across modes: rewards must be restored in both directions.
	for config in [["classic", false], ["bright", false], ["bright", true],
			["levels", false], ["zen", false], ["puzzle", false], ["tutorial", false],
			["classic", true], ["classic", false]]:
		await main.start_game(config[0], config[1])
		var classic: bool = config[0] == "classic" and not config[1]
		var label := str(config)
		var training: bool = config[0] == "tutorial"
		var modern: bool = classic or config[0] == "bright" or training
		check(main.keeper.combo_window == (3.5 if modern else 3.0), label + ": window")
		check(main.keeper.tier_time == (1.0 if classic or training else 2.0), label + ": tier seconds")
		check(main.keeper.streak_time == (1.0 if classic or training else 3.0), label + ": tenth-hit seconds")
		check(main.keeper.timed_special == modern, label + ": special rules")
		check(main.keeper.time_bonuses == (main.mode.kind == "classic" or training), label + ": bonus eligibility")
		check(not main._ab_active and not main.ComboExperiment.fixed_layout
			and not main.ComboExperiment.is_read_only(), label + ": ordinary game and saving")
		if classic or config[0] == "bright":
			check(main.time_left == 120.0, label + ": starting reserve")
		main.go_menu()
	await main.start_game("classic")
	for hit in range(1, 31):
		var before: float = main.time_left
		_fixture(main, 2)
		check(main.time_left - before == (1.0 if hit in [2, 5, 9, 10, 20, 30] else 0.0),
			"real pair %d: exact reward, no double credit" % hit)
		check(main.keeper.combo == hit and main.score == main.keeper.score,
			"real pair %d: uninterrupted series and score" % hit)
	main.go_menu()
	await main.start_game("classic")
	var times := [1.0, 1.0, 1.0, 0.0, 5.0, 6.0]
	var unique_counts := [1, 1, 2, 2, 3, 0]
	var hits := [3, 2, 3, 2, 3, 3]
	for i in hits.size():
		var before: float = main.time_left
		_fixture(main, hits[i])
		check(main.time_left - before == times[i], "real unique cycle hit %d: summed seconds" % (i + 1))
		check(main.keeper.precise_streak == unique_counts[i], "real unique cycle hit %d: unique count" % (i + 1))
	check(main.keeper.precise_events == 1 and main.keeper.perfect_events == 1
		and main.keeper.special_bonus_time == 8.0, "real cycle: unchanged Precise/Perfect rewards")
	main.go_menu()
	for event in ["precise", "perfect"]:
		await main.start_game("classic")
		for hit in range(1, 10):
			_fixture(main, 3 if hit >= (8 if event == "precise" else 7) else 2)
		var before_time: float = main.time_left
		var before_score: int = main.score
		_fixture(main, 4, 2)
		check(main.time_left - before_time == (10.0 if event == "precise" else 12.0),
			"real tenth hit: base + " + event + " + streak + two shining gems credited once")
		check(main.score - before_score == (56 if event == "precise" else 78),
			"real tenth hit: base/special/shine unchanged, +12 color share, +12 Double Hit only in Perfect sequence")
		check(main.keeper.precise_events == 1 and main.keeper.perfect_events == (0 if event == "precise" else 1),
			"real tenth hit: no duplicate special event for " + event)
		main.go_menu()
	return {"checks": checks, "failed": failures.size(), "failures": failures}


func _rules() -> void:
	var k := ScoreKeeper.new()
	k.configure_time_rewards(true)
	k.combo_window = ScoreKeeper.CLASSIC_COMBO_WINDOW
	k.timed_special = true
	var seconds := 0.0
	var points := 0
	for hit in range(1, 31):
		var r := k.hit(2, float(hit))
		var mult := 4 if hit >= 9 else (3 if hit >= 5 else (2 if hit >= 2 else 1))
		check(r.mult == mult and r.points == 2 * mult, "pair %d: unchanged points and tier threshold" % hit)
		check(r.time == (1.0 if hit in [2, 5, 9, 10, 20, 30] else 0.0), "pair %d: exact seconds" % hit)
		check(r.tier_up == (hit in [2, 5, 9]), "pair %d: tier awarded once" % hit)
		seconds += r.time
		points += r.points
	check(seconds == 6.0 and k.score == points, "30 pairs: exactly six reward seconds")
	k.reset()
	check(k.tier_time == 1.0 and k.streak_time == 1.0 and k.combo_window == 3.5,
		"round reset preserves selected balance")
	for n in [2, 3, 4, 8]:
		k.reset()
		var r := k.hit(n, 0.0)
		check(r.time == (0.0 if n == 2 else (1.0 if n == 3 else 2.0)), "unchanged base time for %d gems" % n)
	k.reset()
	check(k.hit(2, 0.0, 3).time == 6.0, "every shining gem gives exactly two seconds")
	k.hit(2, 3.5)
	check(k.combo == 2 and not k.update(7.0), "exact ordinary boundary remains inclusive")
	check(k.update(7.0001) and k.combo == 0, "ordinary timeout resets series")
	check(k.hit(2, 8.0).time == 0.0 and k.hit(2, 9.0).time == 1.0,
		"new series earns its tier once after timeout")
	k.miss()
	check(k.hit(2, 10.0).time == 0.0 and k.hit(2, 11.0).time == 1.0,
		"new series earns its tier once after miss")
	k.configure_time_rewards(false)
	k.reset()
	for hit in range(1, 31):
		var r := k.hit(2, float(hit))
		check(r.time == (2.0 if hit in [2, 5, 9] else (3.0 if hit in [10, 20, 30] else 0.0)),
			"legacy pair %d: original time balance" % hit)
	k.reset()
	k.time_bonuses = false
	for hit in range(1, 31):
		var r := k.hit(4, float(hit), 2)
		check(r.time == 2.0, "disabled extra bonuses hit %d: only base time retained" % hit)
	check(k.special_bonus_time == 0.0, "disabled extra bonuses: no credited special seconds")


func _fixture(main, n: int, shining := 0) -> void:
	var rows := ["1.1..", ".....", ".....", "3.3.."]
	if n == 3:
		rows = [".1...", "1.1..", ".....", "3.3.."]
	elif n == 4:
		rows = [".1...", "2.2..", ".1...", "3.3.."]
	var cells := PackedInt32Array()
	for row in rows:
		for ch in row:
			cells.append(-1 if ch == "." else int(ch))
	main.logic.load_cells(5, 4, cells)
	for index in cells.size():
		if cells[index] >= 0 and shining > 0:
			main.logic.shine[index] = 1
			shining -= 1
	main.board.refresh()
	main.play_time += 1.0
	main.dealing = false
	main._on_slot(Vector2i(1, 0) if n == 2 else Vector2i(1, 1))
