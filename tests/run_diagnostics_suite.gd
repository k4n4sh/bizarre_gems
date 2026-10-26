extends SceneTree
## The write lock intentionally lasts until this disposable process exits.
var checks := 0
var failures: Array[String] = []
const A := Vector2i(3,3)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	_run.call_deferred()
func sample_board(main, count: int) -> void:
	var cells := PackedInt32Array()
	cells.resize(49)
	cells.fill(BoardLogic.EMPTY)
	for at in [Vector2i(1,3),Vector2i(5,3),Vector2i(3,1),Vector2i(3,5)].slice(0,count): cells[at.y*7+at.x] = 0
	cells[42] = 5
	cells[44] = 5
	main.logic.load_cells(7,7,cells)
	main.board.refresh()
func _run() -> void:
	await process_frame
	if not root.has_node("TestIsolation") or AudioServer.get_driver_name() != "Dummy": quit(1); return
	root.get_node("Yandex").set_script(load("res://tests/progress_sdk_fixture.gd"))
	root.get_node("Save").sound = false
	root.get_node("Save").music = false
	root.get_node("Sfx").update_music()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	for i in 12: await process_frame
	var original: Dictionary = await load("res://tests/test_combo_ab.gd").new().run_suite(main)
	print("COMBO_AB ",JSON.stringify(original))
	check(not original.has("error") and original.failed == 0,"pinned A/B scenarios adapted to scene HUD and approved Run")
	var saved: Dictionary = root.get_node("Save").cloud_data().duplicate(true)
	var files := {}
	for path in [root.get_node("Save").PATH,root.get_node("Progress").PATH]:
		files[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	for id in ["classic","bright"]:
		main.go_menu()
		check(main.debug_start_special_combo("timed",42) if id == "classic" else main.debug_start_run_combo(42),id+" diagnostic entry")
		while main._run_starting: await process_frame
		for i in 12: await process_frame
		check(main.keeper.timed_special and main.keeper.combo_window == 3.5,id+" approved ordinary/special windows")
		check(main.keeper.time_bonuses == (id == "classic") and main.keeper.hit_time_rewards == (id == "classic"),id+" actual time-reward contract")
		var events := []
		for n in [3,2,3,3,3]:
			sample_board(main,n)
			var before: float = main.time_left
			main._on_slot(A)
			var recorded: Dictionary = main._ab_receipts[-1]
			events.append(recorded.receipt.event)
			check(recorded.score == main.score and recorded.removed == n,id+" receipt from production strike")
			check(is_equal_approx(main.time_left-before,recorded.receipt.time if id == "classic" else 0.0),id+" actual bonus seconds")
			main._process(.5)
		check("precise" in events and "perfect" in events,id+" Precise and Perfect through real handlers")
		check(main._ab_receipts[1].receipt.double_hit_points > 0 and main._ab_receipts[1].receipt.color_streak_points > 0,id+" Double Hit and Color Chain in diagnostics receipts")
		main.end_game("time")
		check(main.last_earned == 0 and not main.result.get_node("%NewBest").visible,id+" no awards/record")
		check(main.last_combo_report.receipts == main._ab_receipts and main.last_combo_report.mode == id,id+" report captures actual mode/receipts")
		var report_file := FileAccess.get_file_as_string(main.ComboExperiment.REPORT_PATH)
		main._report_combo_ab("quit")
		check(FileAccess.get_file_as_string(main.ComboExperiment.REPORT_PATH) == report_file,id+" one result per completion")
		main.go_menu()
	var simulation = load("res://tests/simulate_special_combo.gd").new()
	var trace: Dictionary = simulation.make_trace(42,"greedy")
	check(trace == simulation.make_trace(42,"greedy"),"deterministic simulation uses actual BoardLogic")
	for gap in simulation.SPEEDS:
		for timed in [false,true]:
			for id in ["classic","bright"]:
				var row: Dictionary = simulation.replay(trace.hits,gap,timed,id)
				check(row.score >= 0 and row.destroyed <= 240 and row.time_left >= 0,"actual keeper simulation "+str([gap,timed,id]))
				if id == "bright": check(row.total_bonus_seconds == 0,"Run simulation has no hit seconds")
	var progress = root.get_node("Progress")
	progress.report("gems",999)
	progress.add_crystals(999)
	progress.pay_daily("2099-01-01")
	progress.finish_tutorial()
	progress.skip_tutorial()
	progress.open_gift()
	progress._save()
	root.get_node("Save").store()
	check(root.get_node("Save").cloud_data() == saved,"lock protects memory progress/settings across modes and claims")
	for path in files: check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "") == files[path],"process write lock preserves "+path)
	print("DIAGNOSTICS_SUITE ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	simulation.free()
	main.queue_free()
	for player in root.get_node("Sfx").get_children():
		if player is AudioStreamPlayer: player.stop(); player.stream = null
	await create_timer(.2).timeout
	if not failures.is_empty(): push_error("FAIL diagnostics suite")
	print("DIAGNOSTICS_SUITE_DONE")
	quit(1 if not failures.is_empty() else 0)
