extends SceneTree
## godot --headless --path . --script res://tests/test_classic_android_layout.gd -- --combo-ab=B
## CLASSIC_LAYOUT_OUTPUT optionally names an external JSON report.
var checks := 0
var failures: Array[String] = []
var measurements: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func settle(count := 12) -> void:
	for tick in count:
		await process_frame

func inside(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(0.01).encloses(inner)

func inspect_controls(node: Control, safe: Rect2, context: String) -> void:
	check(inside(safe, node.get_global_rect()), context + " safe bounds: " + str(node.get_path()))
	check(node.size.y + 0.01 >= node.get_combined_minimum_size().y, context + " content height: " + str(node.get_path()))
	if node is Label:
		check(node.visible_characters == -1 and node.max_lines_visible == -1, context + " full label")
		check(node.text.is_empty() or node.get_visible_line_count() == node.get_line_count(), context + " every wrapped line")
	for child in node.get_children():
		if child is Control:
			inspect_controls(child, safe, context)

func _run() -> void:
	var locale = root.get_node("L")
	var old_lang: String = locale.lang
	# Silence this process only; the A/B argument prevents persistence.
	root.get_node("Save").sound = false
	root.get_node("Save").music = false
	root.get_node("Save").voice = false
	root.get_node("Sfx").update_music()
	# physical W/H, physical left/top/right/bottom, expected integer logical cell.
	var screens := [
		["16:9",1920,1080,0,0,0,0,30],
		["16:9 HD",1280,720,0,0,0,0,30],
		["19.5:9",2340,1080,0,0,0,0,31],
		["20:9",2400,1080,0,0,0,0,31],
		["20:9 HD",1600,720,0,0,0,0,31],
		["20:9 cutout",2400,1080,90,0,0,72,28],
		["16:9 system bars",1920,1080,72,54,72,72,27],
		["19.5:9 asymmetric",2340,1080,96,24,36,48,28],
		["narrow 3:2",1620,1080,0,0,0,0,32],
		["4:3 tablet",1600,1200,0,0,0,0,27],
	]
	var numbers := [0,999999,123456789012345,9223372036854775807]
	for screen in screens:
		var base := 600 if float(screen[1]) / screen[2] < 1.6 else 480
		var extent := Vector2i(floori(float(screen[1]) * base / screen[2]),base)
		var scale_px := Vector2(screen[1],screen[2]) / Vector2(extent)
		var vp := SubViewport.new()
		vp.size = extent
		root.add_child(vp)
		var main = load("res://tests/classic_android_fixture.gd").new()
		main.test_insets = Rect2(screen[3] / scale_px.x,screen[4] / scale_px.y,screen[5] / scale_px.x,screen[6] / scale_px.y)
		vp.add_child(main)
		main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main.set_process(false)
		await settle()
		main._use_mode("classic")
		main.state = main.State.PLAYING
		main.rng.seed = 8181
		main._deal_board()
		main._resume_play()
		main._on_viewport_resized()
		await settle()
		for language in ["ru","en","tr"]:
			locale.set_language(language)
			main._apply_texts()
			for value in numbers:
				main.score = 0 # Int64 stress is presentation only; avoid float score animation.
				main.time_left = 9999.0
				main._update_hud()
				main._set_hud_number(main.score_label,value)
				main._set_hud_number(main.best_label,value)
				for combo in [0,12345]:
					main.keeper.combo = combo
					main.keeper._last_hit = main.play_time
					main._update_combo_widget(true)
					main.time_delta.text = "+999"
					main.time_delta.modulate.a = 1.0
					await settle()
					main.board.refresh()
					var context: String = str(screen[0]) + "/" + language + "/" + str(value) + "/" + str(combo)
					var inset: Rect2 = main.test_insets
					var safe := Rect2(inset.position.ceil(),Vector2(extent) - inset.position.ceil() - inset.size.ceil())
					var grid := Rect2(main.board.global_position + main.board.origin,Vector2(23,15) * main.board.cell)
					check(main.logic.cols == 23 and main.logic.rows == 15 and main.logic.cells.size() == 345,context + " all 345 slots")
					check(main.logic.gems_left() == 270,context + " original gem count")
					check(inside(safe,grid) and inside(main.board.get_global_rect(),grid),context + " entire grid visible")
					check(main.board.cell == screen[7],context + " expected cell, got " + str(main.board.cell))
					check(main.board.get_parent() == main.classic_sides and main.classic_sides.get_child(1) == main.board,context + " two-side structure")
					check(not main.hud_classic.visible and not main.title_label.visible,context + " no upper HUD/title")
					check(main.classic_stats.get_global_rect().end.x <= main.board.global_position.x,context + " left statistics")
					check(main.classic_actions.global_position.x >= main.board.get_global_rect().end.x,context + " right actions")
					check(not main.classic_stats.get_global_rect().intersects(grid) and not main.classic_actions.get_global_rect().intersects(grid),context + " no overlap")
					check(main.score_label.text.replace("\u2009","").replace("\n","") == str(value) and main.best_label.text.replace("\u2009","").replace("\n","") == str(value),context + " all score digits")
					check(main.score_label.get_theme_font_size("font_size") >= 18 and main.best_label.get_theme_font_size("font_size") >= 18,context + " readable numbers")
					check(main.combo_mult.text == "×4" if combo > 0 else main.combo_box.modulate.a == 0.0,context + " combo state")
					check(main.combo_box.scale == Vector2.ONE,context + " pulse stays inside rail")
					check(absf(main.classic_stats.size.x - main.classic_actions.size.x) <= 1.0,context + " equal rail widths")
					var left_space := grid.position.x - safe.position.x
					var right_space := safe.end.x - grid.end.x
					check(absf(left_space - right_space) <= 1.0,context + " grid centered in safe area")
					check(main.board.size.x == 23 * main.board.cell + 6,context + " exact board width")
					check(main.time_bar.size.x <= 80 and main.classic_stats.get_child(0).size.x == main.btn_pause.size.x,context + " compact matching content widths")
					for block in main.classic_stats.get_children():
						var outer_gap: float = block.global_position.x - safe.position.x
						var inner_gap: float = main.board.global_position.x - block.get_global_rect().end.x
						check(absf(outer_gap - inner_gap) <= 1.0,context + " statistics midway between safe edge and board")
					for button in [main.btn_pause,main.btn_restart,main.btn_settings]:
						var inner_gap: float = button.global_position.x - main.board.get_global_rect().end.x
						var outer_gap: float = safe.end.x - button.get_global_rect().end.x
						check(absf(outer_gap - inner_gap) <= 1.0,context + " buttons midway between board and safe edge")
					for label in [main.time_label,main.score_label,main.best_label,main.combo_count,main.combo_mult]:
						check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,context + " statistics centered within compact block")
					inspect_controls(main.classic_stats,safe,context)
					inspect_controls(main.classic_actions,safe,context)
					for button in [main.btn_pause,main.btn_restart,main.btn_settings]:
						check(button.size.x >= 64 and button.size.y >= 64 and not button.disabled and button.mouse_filter != Control.MOUSE_FILTER_IGNORE,context + " accessible action")
		measurements.append({"screen":screen[0],"physical":[screen[1],screen[2]],"logical":[extent.x,extent.y],"safe_physical":screen.slice(3,7),"cell":main.board.cell,"cell_physical":[main.board.cell*scale_px.x,main.board.cell*scale_px.y],"board":[main.board.size.x,main.board.size.y],"rails":[main.classic_stats.size.x,main.classic_actions.size.x],"grid":[main.board.global_position.x+main.board.origin.x,main.board.global_position.y+main.board.origin.y,23*main.board.cell,15*main.board.cell],"content_width":main.btn_pause.size.x,"safe_grid_spaces":[main.board.global_position.x+main.board.origin.x-ceilf(main.test_insets.position.x),extent.x-ceilf(main.test_insets.size.x)-(main.board.global_position.x+main.board.origin.x+23*main.board.cell)],"hud_grid_gaps":[main.board.global_position.x+main.board.origin.x-main.classic_stats.get_child(0).get_global_rect().end.x,main.btn_pause.global_position.x-(main.board.global_position.x+main.board.origin.x+23*main.board.cell)],"hud_safe_edge_gaps":[main.classic_stats.get_child(0).global_position.x-ceilf(main.test_insets.position.x),extent.x-ceilf(main.test_insets.size.x)-main.btn_pause.get_global_rect().end.x],"hud_frame_gaps":[main.board.global_position.x-main.classic_stats.get_child(0).get_global_rect().end.x,main.btn_pause.global_position.x-main.board.get_global_rect().end.x]})
		var every_center := true
		for y in 15:
			for x in 23:
				var center: Vector2 = main.board.origin + (Vector2(x,y) + Vector2.ONE * 0.5) * main.board.cell
				every_center = every_center and main.board.slot_at(center) == Vector2i(x,y)
		check(every_center,str(screen[0]) + " every cell center accessible")
		main.btn_pause.pressed.emit()
		check(main.state == main.State.PAUSED and main.pause_panel.visible,str(screen[0]) + " pause callback")
		main._resume_play()
		main.btn_settings.pressed.emit()
		check(main.state == main.State.PAUSED and main.settings_panel.visible,str(screen[0]) + " settings callback")
		main._close_settings()
		main.btn_restart.pressed.emit()
		main.set_process(false)
		await settle()
		check(main.state == main.State.PLAYING and main.time_left == 120 and main.score == 0 and main.logic.cells.size() == 345,str(screen[0]) + " restart callback")
		# A transient portrait frame must not transpose or lose any Classic slots.
		vp.size = Vector2i(480,1040)
		main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main._on_viewport_resized()
		await settle()
		main._relayout_board()
		check(main.logic.cols == 23 and main.logic.rows == 15 and main.logic.cells.size() == 345,str(screen[0]) + " transient orientation keeps shape")
		check(main.board.get_parent() == main.classic_sides and main.classic_stats.visible and main.classic_actions.visible,str(screen[0]) + " transient orientation retains both rails")
		vp.size = extent
		main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main._on_viewport_resized()
		await settle()
		# System insets can change without the viewport dimensions changing.
		main.test_insets.position.x += 5.5
		main._poll_classic_safe_area(0.25)
		await settle()
		check(main.margin.get_theme_constant("margin_left") == 4 + ceili(main.test_insets.position.x),str(screen[0]) + " live safe area")
		# Other modes regain the original parent and HUD; Classic can be entered again.
		main._use_mode("bright")
		await settle()
		check(main.board.get_parent() == main.board_column and not main.classic_sides.visible and main.hud.visible,str(screen[0]) + " Bright retains old HUD")
		main._use_mode("classic")
		main._deal_board()
		await settle()
		check(main.board.get_parent() == main.classic_sides and main.logic.cells.size() == 345,str(screen[0]) + " return to Classic")
		vp.queue_free()
		await settle(2)
	locale.set_language(old_lang)
	var result := {"checks":checks,"failed":failures.size(),"failures":failures,"measurements":measurements}
	var output := OS.get_environment("CLASSIC_LAYOUT_OUTPUT")
	if output != "":
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
	print("CLASSIC_ANDROID_LAYOUT ",checks," checks; ",failures.size()," failures")
	for failure in failures.slice(0,20):
		printerr(failure)
	await settle(2)
	quit(0 if failures.is_empty() else 1)
