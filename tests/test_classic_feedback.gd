extends RefCounted
## Run only through the isolated test_classic_bonus_combos.ps1 fixture.
var checks := 0
var failures: Array[String] = []
var measurements: Array = []
var tree: SceneTree

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func settle(frames := 8) -> void:
	for i in frames:
		await tree.process_frame

func geometry(main) -> Array:
	var result := [main.board.get_global_rect(), main.board.origin, main.board.cell]
	if main.simulate_android:
		for slot in main.classic_stats.get_children():
			result.append(slot.get_global_rect())
	else:
		for slot in main.hud_classic.get_children():
			result.append(slot.get_global_rect())
	for button in [main.btn_pause, main.btn_restart, main.btn_settings]:
		result.append(button.get_global_rect())
	return result

func hit(main, at: Vector2i, kind := 0, count := 2) -> void:
	# Real hit path, with a separate remaining move to avoid automatic game over.
	var cells := PackedInt32Array()
	cells.resize(main.logic.cols * main.logic.rows)
	cells.fill(-1)
	for i in count:
		var p: Vector2i = at + BoardLogic.DIRS[i]
		cells[p.y * main.logic.cols + p.x] = kind
	cells[0] = 8
	cells[2] = 8
	main.logic.load_cells(main.logic.cols, main.logic.rows, cells)
	main.board.refresh()
	main.dealing = false
	main.play_time += 0.1
	main._on_slot(at)
	main._set_hud_number(main.score_label, main.score)

func capture(vp: SubViewport, name: String) -> void:
	var output := OS.get_environment("CLASSIC_FEEDBACK_CAPTURE_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "capture " + name)

func check_rail(main, extent: Vector2, context: String) -> void:
	var inset: Rect2 = main.test_insets
	var safe := Rect2(inset.position, extent - inset.position - inset.size)
	var slots: Array = main.classic_stats.get_children()
	check(slots.size() == 5, context + " exactly five permanent blocks")
	var center: float = main.btn_restart.get_global_rect().get_center().y
	var record: Control = slots[2].get_child(0)
	check(absf(record.get_global_rect().get_center().y - center) <= 1.1, context + " whole record block centered on restart")
	var interval: float = slots[1].get_global_rect().get_center().y - slots[0].get_global_rect().get_center().y
	check(not main.time_delta.get_global_rect().intersects(slots[1].get_child(0).get_global_rect()), context + " time delta does not overlap score")
	for i in 5:
		var slot: Control = slots[i]
		var content: Control = slot.get_child(0)
		check(slot.visible and content.visible, context + " permanent slot " + str(i))
		check(safe.grow(1).encloses(content.get_global_rect()), context + " safe content " + str(i))
		check(not content.get_global_rect().intersects(main.board.get_global_rect()), context + " outside board " + str(i))
		check(absf(content.get_global_rect().get_center().y - (center + (i - 2) * interval)) <= 2.0,
			context + " equally spaced visual centres " + str(i))
		if i > 0:
			check(not content.get_global_rect().intersects(slots[i - 1].get_child(0).get_global_rect()), context + " no block overlap")
	for button in [main.btn_pause, main.btn_restart, main.btn_settings]:
		check(button.size.x >= 64 and button.size.y >= 64 and safe.encloses(button.get_global_rect()), context + " usable action bounds")

func check_packets(main, context: String) -> void:
	# Same layout function used by rendering, also available with the headless driver.
	var occupied: Array[Rect2] = []
	var excluded: Rect2 = main._feedback_exclusion()
	if excluded.has_area():
		occupied.append(excluded)
	var visible := 0
	for i in range(main.board._texts.size() - 1, -1, -1):
		var packet: Dictionary = main.board._texts[i]
		if not packet.has("slot"):
			continue
		var layout: Dictionary = main.board._feedback_layout(packet, occupied)
		if layout.is_empty():
			continue
		var rect: Rect2 = layout.rect
		check(Rect2(Vector2.ZERO, main.board.size).encloses(rect), context + " popup stays inside board")
		for other in occupied:
			check(not other.intersects(rect), context + " no text/banner intersection")
		occupied.append(rect)
		visible += 1
	check(visible > 0, context + " newest reward remains readable")
	check(main.board._texts.size() <= 3 and main.board._fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, context + " bounded noninteractive effects")

func run_suite(main) -> Dictionary:
	if not main.get_node("/root/Save").PATH.begins_with("res://.test-user/"):
		return {"error": "Isolated fixture required"}
	tree = main.get_tree()
	var locale = main.get_node("/root/L")
	var configurations := [
		[1280,720,false,Rect2()], [960,540,false,Rect2()], [800,600,false,Rect2()],
		[640,480,false,Rect2()], [480,1008,false,Rect2()],
		[853,480,true,Rect2()], [1066,480,true,Rect2()], [1040,480,true,Rect2(42,11,16,22)],
		[853,480,true,Rect2(32,24,32,32)], [800,600,true,Rect2()], [720,480,true,Rect2()],
		[640,360,true,Rect2()], [480,320,true,Rect2()]]
	for config in configurations:
		var vp := SubViewport.new()
		vp.size = Vector2i(config[0], config[1])
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		tree.root.add_child(vp)
		var sample = load("res://tests/classic_android_fixture.gd").new()
		sample.simulate_android = config[2]
		sample.suppress_focus_pause = true
		sample.test_insets = config[3]
		vp.add_child(sample)
		sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sample.set_process(false)
		await sample.start_game("classic")
		await settle(12)
		sample.board.set_process(false) # Freeze effect age while comparing/capturing frames.
		sample.board._deal_t = 99
		sample.board.queue_redraw()
		var context := "%dx%d_%s" % [vp.size.x, vp.size.y, "android" if config[2] else "desktop"]
		if config[3] != Rect2():
			context += "_safe"
		var widgets: Dictionary = sample.hud_sets["classic_android" if config[2] else "classic"].bonus
		for language in ["ru", "en", "tr"]:
			locale.set_language(language)
			sample._apply_texts()
			sample.keeper.reset()
			sample._update_hud()
			sample._update_combo_widget()
			await tree.create_timer(0.28).timeout
			await settle()
			check(sample.combo_mult.text == "×1" and sample.combo_box.modulate.is_equal_approx(sample.HUD_IDLE), context + " idle streak")
			check(widgets.count.text == "0" and widgets.gem.texture == BoardView.GEM_TEX[6], context + " neutral chain")
			var before := geometry(sample)
			if config[2]:
				check_rail(sample, Vector2(vp.size), context + language)
			if language == "ru":
				await capture(vp, context + "_idle")
			hit(sample, Vector2i(8,7))
			hit(sample, Vector2i(8,7))
			await settle()
			check(geometry(sample) == before, context + language + " activation never moves field or HUD")
			check(sample.score_label.scale == Vector2.ONE and sample.time_label.scale == Vector2.ONE, context + " number pulses stay inside slots")
			check(widgets.count.text == "2" and widgets.progress.modulate == Color.WHITE, context + " active chain")
			check(sample.board._texts[-1].rows[0].s.ends_with("+6") and sample.board._texts[-1].rows[1].s.ends_with("+2"), context + " exact awarded points")
			check_packets(sample, context + " activation")
			if language == "ru":
				await capture(vp, context + "_active")
			hit(sample, Vector2i(8,7))
			check(not sample.board._texts[-1].started and widgets.count.text == "3", context + " compact continuation")
			for i in 16:
				hit(sample, Vector2i(8,7), 0, 3) # Also triggers real Precise and Perfect.
			check(sample.board._texts.size() == 1, context + " repeated cell replaces old messages")
			var dominant: String = sample.banner_title.text
			sample._banner(locale.t("precise"), 10, 3, Color.WHITE, "", 2)
			check(sample.banner_title.text == dominant and sample.banner_box.get_meta("priority") == 3, context + " Perfect keeps highest priority")
			await settle()
			check(geometry(sample) == before, context + " simultaneous rewards keep geometry")
			check_packets(sample, context + " special and rapid hits")
			if language == "en":
				await capture(vp, context + "_special")
			# Existing large score/time stress, without changing the real score or timers.
			sample._set_hud_number(sample.score_label, 9223372036854775807)
			sample._set_hud_number(sample.best_label, 9223372036854775807)
			sample._flash_delta("+999", false)
			await settle()
			check(geometry(sample) == before, context + " large values do not resize slots")
			if config[2]:
				check_rail(sample, Vector2(vp.size), context + " long values " + language)
			sample.play_time += 3.6
			sample.keeper.update(sample.play_time)
			sample._combo_break()
			sample._update_bonus_progress()
			await tree.create_timer(0.8).timeout
			sample.board._process(0.8)
			await settle()
			check(geometry(sample) == before and sample.board._texts.is_empty(), context + " expired effects leave no layout changes or popups")
		# Re-resolve real logical coordinates at zoom/pan and all four board edges.
		sample.banner_box.modulate.a = 0
		sample.board.set_process(false)
		var empty_slots: Array[Vector2i] = []
		var empty_kinds: Array[int] = []
		for zoom in [1.0, 1.6, 2.4]:
			sample.board.zoom = zoom
			sample.board.pan = Vector2(35,-27)
			sample.board._relayout()
			for at in [Vector2i(0,0), Vector2i(22,0), Vector2i(0,14), Vector2i(22,14)]:
				sample.board.play_knock(at, empty_slots, empty_kinds, 14)
				sample.board.play_bonus_feedback(at, {"color_streak_points":6,"color_streak_started":true,"double_hit_points":2}, 1, 2,
					locale.t("color_chain_start"), locale.t("color_chain_length", {"n":2}), locale.t("double_hit"))
				check_packets(sample, context + " edges and zoom")
		# A resize must change the anchor, not retain the old pixel position.
		sample.board.reset_zoom()
		var last: Dictionary = sample.board._texts[-1]
		var old_position: Vector2 = sample.board.slot_center(last.slot)
		vp.size += Vector2i(80,40)
		sample._on_viewport_resized()
		await settle()
		check(sample.board.slot_center(last.slot) != old_position, context + " anchor follows resize")
		sample.logic.transpose()
		sample.board.transposed()
		check(sample.board._texts[-1].slot == Vector2i(14,22), context + " logical anchor follows transpose")
		sample.go_menu()
		check(sample.board._texts.is_empty() and sample.banner_box.modulate.a == 0, context + " exit clears feedback")
		if config[0] == 1280:
			await sample.start_game("classic")
			hit(sample, Vector2i(8,7))
			hit(sample, Vector2i(8,7))
			sample.end_game("time")
			check(sample.board._texts.is_empty() and sample.banner_box.modulate.a == 0, "finish clears visual messages")
			await sample.start_game("classic")
			check(sample.board._texts.is_empty(), "restart starts with no old messages")
		measurements.append({"layout":context,"safe_insets":str(config[3]),"checks":checks})
		vp.queue_free()
		await settle(2)
	locale.set_language("ru")
	return {"checks":checks,"failed":failures.size(),"failures":failures,"layouts":measurements}
