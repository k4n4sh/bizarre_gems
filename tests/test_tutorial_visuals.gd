extends RefCounted
## Run via Godot AI game_eval; every fixture keeps player saves read-only.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run_layout(main, resolution: Vector2i, language: String, screenshot_path := "", insets := Rect2()) -> Dictionary:
	main.ComboExperiment.select("B", 42)
	var locale = main.get_node("/root/L")
	var progress = main.get_node("/root/Progress")
	var old_language: String = locale.lang
	var old_tutorial: bool = progress.tutorial
	var vp := SubViewport.new()
	vp.size = resolution
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(vp)
	var sample = load("res://scenes/main.tscn").instantiate() if insets == Rect2() else load("res://tests/classic_android_fixture.gd").new()
	if insets != Rect2():
		sample.test_insets = insets
		sample.simulate_android = false
	var safe := Rect2(insets.position, Vector2(resolution) - insets.position - insets.size)
	vp.add_child(sample)
	sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sample.set_process(false)
	locale.set_language(language)
	sample.start_game("tutorial")
	await main.get_tree().create_timer(1.1).timeout
	check(sample.mode == BoardLogic.TUTORIAL and sample.mode.skin == "bright", "tutorial rules retained")
	check(sample.visual_profile == "classic_run" and sample.ambient.skin == "classic", "shared artwork profile")
	check(sample.logic.cols == 5 and sample.logic.rows == 5 and sample.logic.gems_left() == 8, "original handmade board")
	var original: PackedInt32Array = sample.logic.cells.duplicate()
	sample._on_slot(Vector2i(3, 0))
	check(sample.logic.cells == original and sample.tut_step == 0, "wrong guided move rejected")
	var feedback: String = sample.tut_label.text
	sample._on_slot(Vector2i(3, 0))
	check(sample.tut_label.text == feedback and feedback.contains(locale.t("tut_wrong")), "repeated wrong feedback stays in guidance row")
	check(sample.toast.modulate.a == 0.0, "wrong feedback cannot cover the final pair")
	var steps := [Vector2i(1, 0), Vector2i(1, 2), Vector2i(4, 1)]
	for step in 4:
		await main.get_tree().process_frame
		await main.get_tree().process_frame
		sample._update_hand()
		var grid := Rect2(sample.board.global_position + sample.board.origin, Vector2(5, 5) * sample.board.cell)
		var hint: Rect2 = sample.tut_label.get_global_rect()
		check(not hint.intersects(grid) and not hint.intersects(sample.hud.get_global_rect()), "guidance outside board and HUD, step " + str(step))
		check(safe.encloses(hint), "hint inside viewport")
		check(sample.tut_label.get_visible_line_count() == sample.tut_label.get_line_count(), "all translated lines visible")
		check(sample.tut_label.get_theme_font_size("font_size") >= 20, "readable guidance")
		check(safe.encloses(grid), "entire tutorial grid visible")
		if step < 3:
			var target: Vector2i = steps[step]
			check(sample._tutorial_target() == target and sample.board._hint == target, "guided coordinates and highlight " + str(step))
			var hand: Rect2 = sample.tut_hand.get_global_rect()
			var centre: Vector2 = sample.board.global_position + sample.board.slot_center(target)
			check(sample.tut_hand.visible and absf(hand.get_center().x - centre.x) < 0.1, "hand points at target")
			check(safe.encloses(hand) and not hint.intersects(hand), "hand inside viewport, outside guidance")
			var clear_gems := true
			for y in 5:
				for x in 5:
					if sample.logic.kind_at(Vector2i(x, y)) >= 0:
						var gem := Rect2(sample.board.global_position + sample.board.slot_center(Vector2i(x, y)) - Vector2.ONE * sample.board.cell * .48, Vector2.ONE * sample.board.cell * .96)
						clear_gems = clear_gems and not hand.intersects(gem)
			check(clear_gems, "hand does not cover required gems")
			if step == 0 and screenshot_path != "":
				sample._tutorial_step(0)
				await main.get_tree().process_frame
				await main.get_tree().process_frame
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png(screenshot_path)
			sample._on_slot(target)
			check(sample.logic.gems_left() == 6 - step * 2 and sample.tut_step == step + 1, "guided move progresses")
		else:
			check(not sample.tut_hand.visible, "free move has no prescribed target")
			check(sample.logic.gems_left() == 2 and sample.state == sample.State.PLAYING, "free pair remains")
			sample._on_slot(Vector2i(1, 4))
	check(sample.logic.gems_left() == 0 and sample.tut_label.text == locale.t("tut_done") and progress.tutorial, "tutorial completion")
	await main.get_tree().create_timer(1.8).timeout
	check(sample.state == sample.State.MENU and sample.mode_panel.visible and not sample.tut_label.is_visible_in_tree() and not sample.tut_hand.visible, "completion returns to mode selection")
	await sample.start_game("bright")
	check(not sample.tut_label.visible and not sample.tut_hand.visible, "guidance hidden in other modes")
	sample.go_menu()
	progress.tutorial = old_tutorial
	locale.set_language(old_language)
	vp.queue_free()
	return {"checks": checks, "failed": failures.size(), "failures": failures, "resolution": resolution, "language": language}
