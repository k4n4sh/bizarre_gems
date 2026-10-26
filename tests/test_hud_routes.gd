extends SceneTree
## Same viewport and generated field, different production navigation histories. Isolated Dummy only.
var checks := 0
var failures: Array[String] = []
var observations := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	_run.call_deferred()
func settle(count := 24) -> void:
	for i in count: await process_frame
func same_geometry(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if a is Rect2: return a.is_equal_approx(b)
	if a is Vector2: return a.is_equal_approx(b)
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_geometry(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not same_geometry(a[i],b[i]): return false
		return true
	return a == b
func geometry(main) -> Dictionary:
	var result := {"dims":Vector2i(main.logic.cols,main.logic.rows),"board":main.board.get_rect(),
		"cell":main.board.cell,"origin":main.board.origin,"column":main.game_layer.get_node("Column").get_rect(),
		"stats":main.hud.get_node("Stats").get_rect(),"buttons":main.hud.get_node("Buttons").get_rect()}
	for slot in main.hud.stat_slots:
		result["slot_"+slot.name] = [slot.get_rect(),slot.visible]
	for button in [main.hud.btn_pause,main.hud.btn_restart,main.hud.btn_hint,main.hud.btn_settings]:
		result["button_"+button.name] = [button.get_rect(),button.scale]
	result["badge"] = main.hud.run_badge.get_rect()
	return result
func launch(main, variant: String, ch: Dictionary) -> void:
	main.rng.seed = 826174 # Identical seeded normal Run before every route, without changing generation code.
	if variant == "daily": main.home.get_node("%Daily").pressed.emit()
	elif variant == "challenge":
		main.pending_challenge = ch
		main.home.challenge = ch
		main.home.refresh()
		main.home.get_node("%Challenge").pressed.emit()
	else:
		if not main.modes.visible: main.home.get_node("%Play").pressed.emit()
		main.modes.get_node("%Cards").get_node("Bright").play_button().pressed.emit()
	while main._run_starting: await process_frame
	await settle()
func layout_contract(main, android: bool, label: String) -> void:
	var frame := Rect2(main.board.position+main.board.origin-Vector2.ONE*main.board.frame_pad,
		Vector2(main.logic.cols,main.logic.rows)*main.board.cell+Vector2.ONE*main.board.frame_pad*2)
	var stats: Rect2 = main.hud.get_node("Stats").get_rect()
	if main.hud.top_layout:
		top_contract(main,frame,label)
		return
	check(main.hud.mode_id == "bright" and main.hud.run_badge.visible and not main.practice.visible,label+" real Run HUD, no practice")
	if android: return # The accepted portrait arrangement is intentionally distinct.
	check(stats.size.x == frame.size.x and stats.position.x == frame.position.x,label+" header measures actual field frame")
	check(stats.size.y == (128 if frame.size.x < 680 else 64),label+" adaptive row count uses actual width")
	var strip: Control = main.record_bar
	var strip_room: float = strip.custom_minimum_size.y+6.0 if strip.visible else 0.0
	check(is_equal_approx(stats.end.y+16+strip_room,frame.position.y),label+" header above actual field")
	check(not strip.visible or (strip.position.y >= stats.end.y and is_equal_approx(strip.get_rect().end.y+6.0,frame.position.y)
		and is_equal_approx(strip.position.x,frame.position.x)),label+" record bar between header and field")
## Landscape web Run: one row of plates and buttons as wide as the field frame, just above it,
## with the record bar inside the middle plate.
func top_contract(main, frame: Rect2, label: String) -> void:
	var hud = main.hud
	var plates: Rect2 = hud.get_node("Plates/Time").get_rect().merge(hud.get_node("Plates/Streak").get_rect())
	check(hud.mode_id == "bright" and not hud.run_badge.visible and hud.get_node("Stats/Combo/Streak").visible and not main.practice.visible,label+" real Run HUD with the combo plate, no practice")
	var row: Rect2 = hud.btn_home.get_rect().merge(hud.btn_settings.get_rect())
	check(row.position.x <= frame.position.x+1 and row.end.x >= frame.end.x-1 and row.position.x >= -1 and row.end.x <= main.board.get_parent().size.x+1,label+" top row spans the field frame, inside the window")
	check(plates.end.y < frame.position.y and frame.position.y-plates.end.y <= 12,label+" top row just above the field")
	var middle: Rect2 = hud.get_node("Plates/Score").get_rect()
	var strip: Control = main.record_bar
	check(not strip.visible or (middle.encloses(Rect2(strip.position,Vector2(strip.size.x,strip.COMPACT_HEIGHT)))),label+" record bar inside the middle plate "+str([middle,strip.get_rect()]))
func badge_cycle(main, baseline: Dictionary, label: String) -> void:
	for length in [2,5,9,12345,0]:
		main.hud.set_combo(length,true)
		await settle(3)
		check(same_geometry(geometry(main),baseline),label+" badge pulse/appearance preserves reservations "+str(length))
	main.hud.fade_combo()
	await create_timer(.4).timeout
	var faded: bool = main.hud.combo_mult.text == "0" if main.hud.top_layout else main.hud.combo_box.modulate.a == 0
	check(same_geometry(geometry(main),baseline) and faded,label+" fade preserves geometry")
func resize_cycle(main, vp: SubViewport, baseline: Dictionary, label: String, physical_fullscreen: bool) -> void:
	var original := vp.size
	var cells: PackedInt32Array = main.logic.cells.duplicate()
	var dims := Vector2i(main.logic.cols,main.logic.rows)
	var expanded := Vector2i(1440,900)
	var window := root.get_window()
	var mode := window.mode
	if physical_fullscreen: window.mode = Window.MODE_FULLSCREEN
	for extent in [expanded,Vector2i(620,600),original]:
		vp.size = extent
		await settle()
		check(main.logic.cells == cells and Vector2i(main.logic.cols,main.logic.rows) == dims,label+" resize preserves latched field")
		layout_contract(main,false,label+str(extent))
		if extent == expanded:
			var geometry_fullscreen := geometry(main)
			if physical_fullscreen:
				check(window.mode == Window.MODE_FULLSCREEN,label+" native fullscreen entered")
				window.mode = mode
			await settle()
			if physical_fullscreen:
				check(window.mode == mode,label+" native window mode restored")
			check(same_geometry(geometry(main),geometry_fullscreen),label+" same viewport/field in windowed and fullscreen")
	check(same_geometry(geometry(main),baseline),label+" resize/fullscreen round trip restores geometry")
func capture(vp: SubViewport, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(OS.get_environment("VISUAL_CAPTURE_DIR").path_join("routes_"+label+".png")) == OK,"capture "+label)
func _run() -> void:
	await process_frame
	if not root.has_node("TestIsolation") or AudioServer.get_driver_name() != "Dummy": quit(1); return
	root.get_node("Yandex").set_script(load("res://tests/progress_sdk_fixture.gd"))
	root.get_node("Progress").tutorial = true
	for screen in [[1280,720,false],[960,540,false],[800,600,false],[480,850,false],[360,640,false],[480,850,true]]:
		var resolution := Vector2i(screen[0],screen[1])
		var native: bool = screen[2]
		var vp := SubViewport.new()
		vp.size = resolution
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var main = load("res://scenes/main.tscn").instantiate()
		main.set_script(load("res://tests/hud_platform_fixture.gd"))
		main.simulate_android = native
		main.test_insets = Rect2(8,12,8,10)
		vp.add_child(main)
		main.set_process(false)
		await settle()
		for variant in ["bright","daily","challenge"]:
			var ch := {"mode":"bright","seed":826174,"dims":Vector2i(18,11),"score":100} if variant == "challenge" else {}
			main.go_menu()
			await launch(main,variant,ch)
			var direct := geometry(main)
			var cells: PackedInt32Array = main.logic.cells.duplicate()
			var label: String = str(resolution)+str(native)+variant
			layout_contract(main,native,label+" direct")
			await capture(vp,str(resolution.x)+str(native)+variant+"_direct")
			for route in ["skip","exit","finish","playing"]:
				main.go_menu()
				main.rules.tutorial_pressed.emit()
				await settle()
				if route == "skip": main.practice.get_node("Card/Actions/Skip").pressed.emit()
				elif route == "exit": main.practice.get_node("Card/Actions/Exit").pressed.emit()
				elif route == "finish":
					main._tutorial_step(19)
					main._on_slot(main._tutorial_target())
					main._process(1.6)
					main.tut_next.pressed.emit()
				if route == "playing":
					main.rng.seed = 826174
					await main.start_game("bright",variant == "daily",ch)
					await settle()
				else:
					await settle()
					check(main.state == main.State.MENU and not main.practice.is_visible_in_tree(),label+route+" leaves practice")
					await launch(main,variant,ch)
				var after_tutorial := geometry(main)
				check(same_geometry(after_tutorial,direct),label+route+" route geometry identical")
				check(main.logic.cells == cells,label+route+" identical generated field")
				layout_contract(main,native,label+route)
				if route == "skip":
					observations.append({"viewport":resolution,"native":native,"variant":variant,"direct":direct,"tutorial":after_tutorial})
					await capture(vp,str(resolution.x)+str(native)+variant+"_tutorial")
			await badge_cycle(main,direct,label)
			main.rng.seed = 826174
			main.hud.btn_restart.pressed.emit()
			while main._run_starting: await process_frame
			await settle()
			check(same_geometry(geometry(main),direct) and main.logic.cells == cells,label+" HUD restart identical")
			main.end_game("time")
			main.result.get_node("%Again").pressed.emit()
			main.rng.seed = 826174
			root.get_node("Yandex").resolve_fullscreen()
			await settle()
			while main._run_starting: await process_frame
			await settle()
			check(same_geometry(geometry(main),direct) and main.logic.cells == cells,label+" fullscreen SDK callback restart identical")
			if not native:
				await resize_cycle(main,vp,direct,label,DisplayServer.get_name() != "headless" and resolution == Vector2i(1280,720))
			main.go_menu()
		vp.queue_free()
		await settle(2)
	print("HUD_ROUTES ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"observations":observations}))
	if not failures.is_empty(): push_error("FAIL HUD routes")
	for player in root.get_node("Sfx").get_children():
		if player is AudioStreamPlayer: player.stop()
	await create_timer(.1).timeout
	print("HUD_ROUTES_DONE")
	quit(0 if failures.is_empty() else 1)
