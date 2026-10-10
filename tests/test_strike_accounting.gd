extends RefCounted
## Integration regressions for the real Main._on_slot handler.
## Run through Godot AI game_eval on a freshly launched main menu:
## load("res://tests/test_strike_accounting.gd").new().run_suite(get_tree().current_scene)
## Fixtures leave another legal move, so no result screen, reward or save is triggered.
## Progress reports are restored synchronously before the next process frame.

var checks := 0
var failures: Array[String] = []
var results: Array = []


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func run_suite(main) -> Dictionary:
	checks = 0
	failures.clear()
	results.clear()
	if main.state != main.State.MENU:
		return {"error": "Run this suite from the main menu."}
	var progress = main.get_node("/root/Progress")
	if progress.task_date != Time.get_date_string_from_system(true):
		return {"error": "Restart the project after the UTC date changes before running this suite."}
	var progress_before := {
		"life": progress.life.duplicate(true), "tasks": progress.tasks.duplicate(true),
		"_dirty": progress._dirty, "_since": progress._since,
	}
	var main_before := {}
	for key in ["logic", "keeper", "mode", "state", "time_left", "score", "shown_score",
			"cleared", "play_time", "strikes_done", "goal_kind", "dealing", "idle", "best_strike"]:
		main_before[key] = main.get(key)
	main._use_mode("classic")
	_case(main, progress, "both partners in cross", "direct", 0, 0, 2, 2, 0.0)
	_case(main, progress, "partner outside cross", "outside", 0, 0, 3, 6, 1.0)
	_case(main, progress, "box cracks but stays", "box", 0, 0, 1, 2, 0.0)
	_case(main, progress, "outside partner at x2", "outside", 1, 0, 3, 10, 3.0)
	_case(main, progress, "direct pair with shining bonus", "direct", 0, 1, 2, 7, 2.0)
	for key in progress_before:
		progress.set(key, progress_before[key])
	for key in main_before:
		main.set(key, main_before[key])
	main.board.logic = main.logic
	main.board.clear_fx()
	main._use_mode(str(main.mode.id))
	main.board.refresh()
	main._show_panel(main.menu_panel)
	main._update_hud()
	return {"checks": checks, "failed": failures.size(), "failures": failures, "cases": results}


func _case(main, progress, label: String, kind: String, prior_hits: int, shining: int,
		want_removed: int, want_points: int, want_time: float) -> void:
	var b := BoardLogic.new()
	var rows := ["1.1..", ".....", "1.2.2"] if kind == "outside" else ["1.1..", ".....", "2.2.."]
	var cells := PackedInt32Array()
	for row in rows:
		for ch in row:
			cells.append(-1 if ch == "." else int(ch))
	b.load_cells(5, 3, cells)
	if kind == "box":
		b.hp[0] = 2
	else:
		var partner := 10 if kind == "outside" else 2
		b.chain[0] = partner
		b.chain[partner] = 0
	b.shine[2] = shining
	main.logic = b
	main.board.logic = b
	main.board.clear_fx()
	main.board.refresh()
	main.keeper = ScoreKeeper.new()
	for i in prior_hits:
		main.keeper.hit(2, float(i))
	main.score = main.keeper.score
	main.cleared = 0
	main.best_strike = {}
	main.time_left = 120.0
	main.play_time = float(prior_hits)
	main.strikes_done = 0
	main.goal_kind = -1
	main.dealing = false
	main.state = main.State.PLAYING
	var before_gems := b.gems_left()
	var before_score = main.score
	var before_report := int(progress.life.get("gems", 0))
	main._on_slot(Vector2i(1, 0))
	var removed := before_gems - b.gems_left()
	var points = main.score - before_score
	var seconds = main.time_left - 120.0
	_check(removed == want_removed, label + ": actual unique removals")
	_check(main.cleared == removed, label + ": cleared equals actual removals")
	_check(int(progress.life.get("gems", 0)) - before_report == removed, label + ": reported gems equal actual removals")
	_check(int(main.best_strike.get("n", -1)) == removed, label + ": best strike counts only destroyed gems")
	_check(points == want_points and main.score == main.keeper.score, label + ": score and chain bonus")
	_check(is_equal_approx(seconds, want_time), label + ": time bonus")
	_check(main.state == main.State.PLAYING and b.has_any_move(), label + ": no completion or rewards")
	if kind == "box":
		_check(b.kind_at(Vector2i(0, 0)) == 1 and b.hp[0] == 1, label + ": box stays cracked")
	results.append({"case": label, "removed": removed, "cleared": main.cleared,
		"points": points, "time": seconds, "best_strike_gems": main.best_strike.get("n", -1)})
	main.state = main.State.MENU
