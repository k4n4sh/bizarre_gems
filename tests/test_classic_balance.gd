extends RefCounted
## Rules from refinement@bcee016; run only through the isolated combo suite.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

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
		check(r.mult == mult and r.points - r.hot_points == 2 * mult, "pair %d: unchanged points and tier threshold" % hit)
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
