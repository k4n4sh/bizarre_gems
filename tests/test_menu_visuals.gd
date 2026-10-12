extends RefCounted
## Godot AI runtime checks. Each entry point locks experimental writes.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func result() -> Dictionary:
	return {"checks":checks,"failed":failures.size(),"failures":failures}

func run_suite(main) -> Dictionary:
	if main.state != main.State.MENU:
		return {"error":"Fresh main menu required"}
	main.ComboExperiment.select("B",42)
	main.set_process(false)
	var progress = main.get_node("/root/Progress")
	var save = main.get_node("/root/Save")
	var hashes := {}
	for path in [save.PATH,progress.PATH]:
		hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var old_tutorial: bool = progress.tutorial
	progress.tutorial = true
	main.ui.btn_home_play.pressed.emit()
	check(main.mode_panel.visible and not main.menu_panel.visible, "Play opens mode selection")
	check(main.ambient.skin == "classic" and not main.dim.visible, "menu has consistent velvet without modal dimming")
	for id in ["classic","bright","levels","zen","puzzle"]:
		var card = main.ui["card_name_"+id].get_parent().get_parent()
		check(card.visible == (id in main.MENU_MODES), "mode visibility " + id)
	for id in ["classic","bright"]:
		main.ui["card_play_"+id].pressed.emit()
		while main._run_starting:
			await main.get_tree().process_frame
		check(main.state == main.State.PLAYING and main.mode.id == id and not main.daily, "card launches " + id)
		check(main.visual_profile == ("classic" if id=="classic" else "classic_run"), "game profile " + id)
		check(main.time_left == 120 and main.score == 0, "initial gameplay unchanged")
		main.go_menu()
		check(main.ambient.skin == "classic" and main.menu_panel.visible, "home after " + id)
	main.ui.daily_card.pressed.emit()
	while main._run_starting:
		await main.get_tree().process_frame
	check(main.daily and main.mode.id == "bright" and main.state == main.State.PLAYING, "Daily button preserved")
	main.go_menu()
	progress.tutorial = false
	main.ui.btn_home_play.pressed.emit()
	check(main.mode.id == "tutorial" and main.state == main.State.PLAYING, "first-run tutorial routing preserved")
	main.go_menu()
	progress.tutorial = old_tutorial
	main._show_panel(main.mode_panel)
	main.ui.mode_back.pressed.emit()
	check(main.menu_panel.visible, "mode back button")
	for entry in [["home_gift","gift_panel"],["home_pass","pass_panel"],["home_tasks","tasks_panel"],
			["home_ach","ach_panel"],["home_stats","stats_panel"],["home_rules","rules_panel"],["home_settings","settings_panel"]]:
		main.ui[entry[0]].get_child(0).pressed.emit()
		check(main.get(entry[1]).visible, "service route " + entry[0])
		main._show_panel(main.menu_panel)
	check(not main.ui.home_coll.visible and not progress.COSMETICS_ENABLED, "collection stays disabled")
	# Draw previews after all deferred board layout settles.
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var rng_state: int = main.rng.state
	var digest: String = load("res://tests/test_visual_unification.gd").new().digest(main.logic)
	main._show_panel(main.mode_panel)
	await main.get_tree().create_timer(.3).timeout
	for id in ["classic","bright"]:
		main.ui["card_preview_"+id].queue_redraw()
	await main.get_tree().process_frame
	check(main.rng.state == rng_state, "preview drawing does not consume gameplay RNG")
	check(load("res://tests/test_visual_unification.gd").new().digest(main.logic) == digest, "preview drawing cannot alter hidden board")
	main.go_menu()
	for path in hashes:
		check(hashes[path] == (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""), "save file unchanged " + path)
	return result()

func run_layout(main, resolution: Vector2i, language: String) -> Dictionary:
	main.ComboExperiment.select("B",42)
	var localizer = main.get_node("/root/L")
	var old_language: String = localizer.lang
	var vp := SubViewport.new()
	vp.size = resolution
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(vp)
	var sample = load("res://scenes/main.tscn").instantiate()
	vp.add_child(sample)
	sample.set_process(false)
	localizer.set_language(language)
	await main.get_tree().create_timer(.35).timeout
	check(sample.ui.home_stack.size.x <= sample.ui.home_scroll.size.x, "home has no horizontal overflow")
	check(sample.ui.btn_home_play.size.x >= 260 and sample.ui.btn_home_play.size.y >= 60, "Play touch target")
	check(sample.ui.daily_card.size.x <= sample.ui.home_stack.size.x, "Daily fits content width")
	check(sample.ui.home_settings.visible and not sample.ui.home_coll.visible, "services available, collection hidden")
	sample.ui.home_scroll.ensure_control_visible(sample.ui.home_settings)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	check(sample.ui.home_scroll.get_global_rect().encloses(sample.ui.home_settings.get_global_rect()), "last service button reachable by scrolling")
	sample._show_panel(sample.mode_panel)
	await main.get_tree().create_timer(.35).timeout
	check(sample.mode_panel.size.x <= resolution.x, "mode header cannot expand screen beyond viewport")
	check(sample.ui.mode_grid.columns == (2 if resolution.x >= 880 else 1), "responsive card columns")
	check(sample.ui.mode_grid.size.x <= sample.ui.mode_scroll.size.x, "mode grid has no horizontal overflow")
	var cards := []
	for card in sample.ui.mode_cards:
		if card.visible:
			cards.append(card)
	check(cards.size() == 2, "only two ordinary modes visible")
	check(cards[0].size.y == cards[1].size.y if resolution.x >= 880 else true, "desktop card bottoms align")
	for id in ["classic","bright"]:
		var button = sample.ui["card_play_"+id]
		sample.ui.mode_scroll.ensure_control_visible(button)
		await main.get_tree().process_frame
		await main.get_tree().process_frame
		check(sample.ui.mode_scroll.get_global_rect().encloses(button.get_global_rect()), "Play button reachable by scrolling: " + id)
	localizer.set_language(old_language)
	vp.queue_free()
	var answer := result()
	answer["resolution"] = resolution
	answer["language"] = language
	return answer
