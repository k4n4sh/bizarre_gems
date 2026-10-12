extends SceneTree
## Run tests/test_mode_records.ps1; fixture save paths protect player data.
var checks := 0
var failures: Array[String] = []
var measurements := {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func settle(frames := 10) -> void:
	for i in frames:
		await process_frame

func earn(main) -> int:
	await settle()
	main.dealing = false
	for i in 8:
		if main.state != main.State.PLAYING:
			break
		var p: Vector2i = main.logic.find_move()
		if p.x < 0:
			break
		main.play_time += 0.5
		main._on_slot(p)
	return main.score

func _run() -> void:
	var save = root.get_node("Save")
	var progress = root.get_node("Progress")
	if not save.PATH.begins_with("res://.test-user/") or not progress.PATH.begins_with("res://.test-user/"):
		printerr("Use tests/test_mode_records.ps1: isolated save paths required.")
		quit(2)
		return
	save.sound = false
	save.music = false
	save.voice = false
	root.get_node("Sfx").update_music()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.set_process(false)
	await settle()
	var stage := "earn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--records-stage="):
			stage = arg.get_slice("=",1)
	check(not main.ComboExperiment.is_read_only(), "ordinary startup permits saving")
	main._show_panel(main.mode_panel)
	await settle()
	if stage == "earn":
		for id in ["classic","bright"]:
			check(save.best_for(id) == 0 and main.ui["card_best_"+id].text == root.get_node("L").t("best") + ": 0", "empty record rendered " + id)
		check(save.daily_best_for(main._today()) == 0, "empty Daily record")
		for config in [["classic",false],["bright",false],["bright",true]]:
			var id: String = config[0]
			var daily: bool = config[1]
			var old_bright: int = save.best_bright
			await main.start_game(id,daily)
			check(not main._ab_active and not main.ComboExperiment.is_read_only(), "ordinary game permits saving " + str(config))
			check(main.keeper.combo_window == (3.5 if id == "classic" else 3.0), "combo timing retained")
			check(main.keeper.timed_special == (id == "classic"), "special rules retained")
			var score: int = await earn(main)
			check(score > 0, "result earned through real strikes " + str(config))
			main.end_game("time")
			var best: int = save.daily_best_for(main._today()) if daily else save.best_for(id)
			check(best == score, "finished result saved " + str(config))
			main.go_menu()
			main._show_panel(main.mode_panel)
			await settle()
			if daily:
				check(save.best_bright == old_bright, "Daily separate from Bright record")
				check(main.ui.daily_card.text == root.get_node("L").t("daily_card_done",{"n":score}), "Daily shown on home entry")
			else:
				var label = main.ui["card_best_"+id]
				check(label.text == root.get_node("L").t("best") + ": " + str(score) and label.is_visible_in_tree(), "mode card updated after finish " + id)
				check(progress.local_top(main.mode.board)[0].score == score, "local leaderboard retained " + id)
			measurements["daily" if daily else id] = score
		var f := FileAccess.open("res://.test-user/expected.json",FileAccess.WRITE)
		f.store_string(JSON.stringify(measurements))
		f.close()
		var before := FileAccess.get_sha256(save.PATH)
		main.ComboExperiment.select_special("timed",42)
		await main.start_game("classic")
		await earn(main)
		main.end_game("time")
		main.go_menu()
		check(main._ab_active and main.ComboExperiment.is_read_only(), "explicit experiment remains isolated")
		check(FileAccess.get_sha256(save.PATH) == before, "experiment cannot overwrite records")
	else:
		measurements = JSON.parse_string(FileAccess.get_file_as_string("res://.test-user/expected.json"))
		for id in ["classic","bright"]:
			check(save.best_for(id) == int(measurements[id]), "record survives process restart " + id)
			var label = main.ui["card_best_"+id]
			check(label.text == root.get_node("L").t("best") + ": " + str(int(measurements[id])) and label.is_visible_in_tree(), "restored record visible " + id)
		check(save.daily_best_for(main._today()) == int(measurements.daily), "Daily survives restart")
		check(main.ui.daily_card.text == root.get_node("L").t("daily_card_done",{"n":int(measurements.daily)}), "restored Daily on home entry")
		check(save.daily_best_for("1900-01-01") == 0, "Daily scoped to its date")
	var answer := {"stage":stage,"checks":checks,"failed":failures.size(),"failures":failures,"earned":measurements}
	var report := FileAccess.open("res://.test-user/records_" + stage + ".json",FileAccess.WRITE)
	report.store_string(JSON.stringify(answer,"\t"))
	report.close()
	print("MODE_RECORDS ",JSON.stringify(answer))
	await settle(2)
	quit(0 if failures.is_empty() else 1)
