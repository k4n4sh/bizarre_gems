extends RefCounted
## Layout checks for every lesson, instruction/error/result, and supported language.
var checks := 0
var failures: Array[String] = []
var minimum_cell := INF

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func settle(tree: SceneTree) -> void:
	for frame in 6:
		await tree.process_frame

func hud_geometry(sample) -> Dictionary:
	var result := {"board": sample.board.get_global_rect()}
	for key in ["score_label", "best_label", "time_label", "time_bar", "combo_box", "btn_pause", "btn_restart", "btn_settings", "btn_hint"]:
		var control: Control = sample.get(key)
		result[key] = control.get_global_rect() if control.is_visible_in_tree() else "hidden"
	return result

func geometry(sample, safe: Rect2, label: String) -> void:
	sample._update_hand()
	var grid := Rect2(sample.board.global_position + sample.board.origin, Vector2(5, 5) * sample.board.cell)
	var card: Rect2 = sample.tut_panel.get_global_rect()
	var hint: Rect2 = sample.tut_label.get_global_rect()
	minimum_cell = minf(minimum_cell, sample.board.cell)
	check(safe.encloses(card) and safe.encloses(grid), label + ": card and grid inside safe viewport")
	check(not card.intersects(grid) and not card.intersects(sample.hud.get_global_rect())
		and not card.intersects(sample.time_row.get_global_rect()), label + ": guidance outside board/HUD")
	check(sample.tut_label.get_visible_line_count() == sample.tut_label.get_line_count(), label + ": all translated lines visible")
	check(sample.tut_label.get_theme_font_size("font_size") >= 17, label + ": readable guidance")
	if safe.size.x < safe.size.y:
		check(grid.size.y > card.size.y, label + ": board has more height than guidance")
		check(grid.size.x >= 280, label + ": phone grid stays large")
	else:
		check(sample._tutorial_wide() and card.end.x < grid.position.x, label + ": card left, board right")
		check(card.size.x <= 340 and grid.size.x > card.size.x * 1.4, label + ": bounded card and dominant board")
		check(absf(card.get_center().y - grid.get_center().y) <= 2, label + ": columns vertically balanced")
		var composition := card.merge(sample.board.get_global_rect())
		check(absf(composition.get_center().x - sample.tut_layout.get_global_rect().get_center().x) <= 2, label + ": composition centred")
	check(sample.board.cell >= 28, label + ": usable small-board cells")
	check(sample.btn_hint == sample.hud_balance and sample.btn_hint.icon == sample.ICONS.hint, label + ": existing HUD bulb retained")
	for action in [sample.ui.tut_retry, sample.ui.tut_skip, sample.ui.tut_exit, sample.tut_next]:
		if action.visible:
			check(card.encloses(action.get_global_rect()) and action.size.y >= 44, label + ": visible touch action fits")
	check(not sample.tut_next.visible or sample.tut_next.size.x < card.size.x * .6, label + ": Next stays compact")
	if sample.tut_hand.visible:
		var hand: Rect2 = sample.tut_hand.get_global_rect()
		check(safe.encloses(hand) and not hint.intersects(hand), label + ": hand fits outside guidance")
		for y in 5:
			for x in 5:
				if sample.logic.kind_at(Vector2i(x, y)) >= 0:
					var gem := Rect2(sample.board.global_position + sample.board.slot_center(Vector2i(x, y)) - Vector2.ONE * sample.board.cell * .48, Vector2.ONE * sample.board.cell * .96)
					check(not hand.intersects(gem), label + ": hand leaves gems visible")

func run_layout(main, resolution: Vector2i, language: String, screenshot_path := "", insets := Rect2()) -> Dictionary:
	checks = 0
	failures.clear()
	minimum_cell = INF
	main.ComboExperiment.select("B", 42)
	var locale = main.get_node("/root/L")
	var progress = main.get_node("/root/Progress")
	var old_language: String = locale.lang
	var old_tutorial: bool = progress.tutorial
	var old_skipped: bool = progress.tutorial_skipped
	var vp := SubViewport.new()
	vp.size = resolution
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(vp)
	var sample = load("res://tests/classic_android_fixture.gd").new()
	sample.suppress_focus_pause = true  # The hidden capture window can lose OS focus.
	sample.test_insets = insets
	sample.simulate_android = resolution.x < resolution.y
	var safe := Rect2(insets.position, Vector2(resolution) - insets.position - insets.size)
	vp.add_child(sample)
	sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sample.set_process(false)
	locale.set_language(language)
	await sample.start_game("tutorial")
	check(sample.mode == BoardLogic.TUTORIAL and sample.visual_profile == "classic_run", "existing mode and shared artwork retained")
	check(sample.TutorialLessons.STEPS.size() == 20, "all twenty lessons retained")
	sample._tutorial_step(3)
	var hint_tokens: int = progress.hint_tokens
	var free_hints: int = sample.hints
	sample.btn_hint.pressed.emit()
	check(sample.board._hint.x >= 0 and progress.hint_tokens == hint_tokens and sample.hints == free_hints, "HUD bulb gives a free tutorial hint")
	for index in sample.TutorialLessons.STEPS.size():
		sample._tutorial_step(index)
		var id: String = sample._tutorial_id()
		await settle(main.get_tree())
		geometry(sample, safe, id + "/instruction")
		sample._tutorial_feedback("lesson_wrong")
		await settle(main.get_tree())
		geometry(sample, safe, id + "/error")
		sample._tutorial_help()
		await settle(main.get_tree())
		geometry(sample, safe, id + "/hint")
		var messages := ["lesson_receipt", "lesson_idle", "lesson_occupied", "lesson_pair_support", "lesson_precise_award", "lesson_box_cracked", "lesson_board_receipt"]
		if "--tutorial-ui-refine" in OS.get_cmdline_user_args():
			messages = ["lesson_pair_support", "lesson_precise_award"] if id == "special" else []
		for feedback in messages:
			sample._tutorial_feedback(feedback, {"p": 12, "s": 60, "n": 4, "m": 2, "w": 1})
			await settle(main.get_tree())
			geometry(sample, safe, id + "/" + feedback)
		sample._tutorial_done("", {"p": 20, "s": 5, "n": 4, "m": 4, "base": 8, "double": 4, "color": 4, "combo": 9, "w": 4})
		await settle(main.get_tree())
		geometry(sample, safe, id + "/result")
		var directory := OS.get_environment("TUTORIAL_SCREENSHOT_DIR")
		if DisplayServer.get_name() != "headless" and directory != "" and id in ["special", "clock"]:
			# Capture actual completed hits, rather than the synthetic geometry state above.
			sample._tutorial_step(index)
			for hit in sample.TutorialLessons.goal(id):
				sample._on_slot(sample._tutorial_target())
			if id == "clock":
				sample._process(1.6)
			sample._set_hud_number(sample.score_label, sample.score)
			await main.get_tree().create_timer(.9).timeout
			await settle(main.get_tree())
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(directory.path_join("%dx%d_%s_%s.png" % [resolution.x, resolution.y, language, id]))
	if screenshot_path != "" and DisplayServer.get_name() != "headless":
		sample._tutorial_step(0)
		await settle(main.get_tree())
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(screenshot_path)
	var screenshot_directory := OS.get_environment("TUTORIAL_SCREENSHOT_DIR")
	if DisplayServer.get_name() != "headless" and screenshot_directory != "":
		sample._tutorial_step(0)
		sample._set_hud_number(sample.score_label, sample.score)
		await main.get_tree().create_timer(.9).timeout
		await settle(main.get_tree())
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(screenshot_directory.path_join("%dx%d_%s_opening.png" % [resolution.x, resolution.y, language]))
	await sample.start_game("bright")
	check(not sample.tut_layout.visible and sample.board.get_parent() == sample.board_column
		and not sample.tut_card.visible and not sample.tut_hand.visible and sample.board.tutorial_focus.x < 0, "ordinary mode restores board parent and hides tutorial")
	check(sample.hud.custom_minimum_size.y == 93 and sample.time_row.custom_minimum_size.y == 35
		and sample.hud_balance.custom_minimum_size == Vector2(52,52), "ordinary HUD sizes restored")
	if FileAccess.file_exists("res://tests/ui_before_fixture.gd"):
		var before = load("res://tests/ui_before_fixture.gd").new()
		before.suppress_focus_pause = true
		before.simulate_android = sample.simulate_android
		vp.add_child(before)
		before.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		before.set_process(false)
		for ordinary_mode in ["classic", "bright"]:
			await before.start_game(ordinary_mode)
			await sample.start_game(ordinary_mode)
			await settle(main.get_tree())
			check(hud_geometry(sample) == hud_geometry(before), "ordinary field/HUD geometry unchanged: " + ordinary_mode)
		before.go_menu()
		before.queue_free()
	sample.go_menu()
	progress.tutorial = old_tutorial
	progress.tutorial_skipped = old_skipped
	locale.set_language(old_language)
	vp.queue_free()
	return {"checks": checks, "failed": failures.size(), "failures": failures.duplicate(), "resolution": resolution, "language": language, "insets": insets, "minimum_cell": minimum_cell}
