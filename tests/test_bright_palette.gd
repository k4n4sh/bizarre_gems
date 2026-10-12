extends RefCounted
## Run through run_runtime_suite.gd in an isolated project/profile.
## GPU runs capture six palettes on one unchanged board, including with lights hidden.
const NAMES := ["green","purple","wine","blue","teal","bronze"]
var checks := 0
var failures: Array[String] = []
var pixels: Array = []
var events: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func complete(main) -> void:
	var tw: Tween = main.ambient._palette_tween
	if tw and tw.is_valid():
		tw.pause()
		tw.custom_step(main.RUN_PALETTE_SECONDS+0.1)

func freeze(main) -> void:
	main.board.set_process(false)
	main.board.clear_fx()
	main.board._deal_t = 99.0
	main.board._shake_off = Vector2.ZERO
	main.board._hover = Vector2i(-1,-1)
	main.board._fx.visible = false
	main.board.refresh()
	main.ambient.set_process(false)
	main.ambient._pulse = 0.0
	main.ambient._classic_mat.set_shader_parameter("pulse",0.0)
	main.ambient._layer.visible = false
	# Freeze the existing lights' drift for comparable screenshots.
	var sh := Shader.new()
	sh.code = Ambient.POOLS_SHADER.replace("TIME","0.0")
	main.ambient._classic_mat.shader = sh

func capture(main, label: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	for i in 3:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := OS.get_environment("BRIGHT_SCREENSHOT_DIR")
	if not path.is_empty():
		check(img.save_png(path.path_join("bright_"+label+".png")) == OK,"save "+label)
	return img

func rgb(c: Color) -> Vector3:
	return Vector3(c.r,c.g,c.b)

func samples(main, img: Image, board_surface: bool) -> Array[Color]:
	var values: Array[Color] = []
	if board_surface:
		# Intersections expose the field surface, excluding gems and slot ornaments.
		for y in range(1,main.logic.rows):
			for x in range(1,main.logic.cols):
				var p: Vector2 = main.board.global_position+main.board.origin+Vector2(x,y)*main.board.cell
				values.append(img.get_pixel(int(p.x),int(p.y)))
	else:
		# Exposed velvet at the side of the board, below the HUD.
		for y in range(int(main.board.global_position.y)+20,img.get_height()-25,3):
			values.append(img.get_pixel(3,y))
	return values

func average(values: Array[Color]) -> Vector3:
	var total := Vector3.ZERO
	for c in values:
		total += rgb(c)
	return total/maxi(values.size(),1)

func snapshot_palettes(main, suffix: String) -> void:
	var images: Array[Image] = []
	var velvet: Array = []
	var surface: Array = []
	for i in 6:
		main._set_theme(i,true)
		var img := await capture(main,NAMES[i]+suffix)
		if img == null:
			continue
		images.append(img)
		var v := samples(main,img,false)
		var s := samples(main,img,true)
		velvet.append(average(v))
		surface.append(average(s))
		var lo := INF
		var hi := -INF
		for c in v:
			var l := c.r*0.2126+c.g*0.7152+c.b*0.0722
			lo = minf(lo,l)
			hi = maxf(hi,l)
		check(hi-lo > 0.015,"velvet retains texture/shadow variation "+NAMES[i]+suffix)
		pixels.append({"palette":NAMES[i]+suffix,"velvet":velvet[-1],"surface":surface[-1],"velvet_luma_range":hi-lo})
	if images.is_empty():
		return
	for i in range(1,6):
		for j in range(i):
			check(velvet[i].distance_to(velvet[j]) > 0.035,"distinct velvet hues "+NAMES[i]+"/"+NAMES[j]+suffix)
			check(surface[i].distance_to(surface[j]) > 0.035,"distinct field hues "+NAMES[i]+"/"+NAMES[j]+suffix)
		# Opaque gem centres must keep their actual rendered colour.
		for idx in main.logic.cells.size():
			if main.logic.cells[idx] < 0 or main.logic.cells[idx] >= 6:
				continue
			var p: Vector2 = main.board.global_position+main.board.slot_center(Vector2i(idx%main.logic.cols,idx/main.logic.cols))
			check(images[i].get_pixel(int(p.x),int(p.y)) == images[0].get_pixel(int(p.x),int(p.y)),"gem centre unchanged "+NAMES[i]+suffix+" #"+str(idx))
		var white_pixels := 0
		var unchanged := true
		for y in 90:
			for x in 80:
				var c := images[0].get_pixel(x,y)
				if c.r > 0.98 and c.g > 0.98 and c.b > 0.98:
					white_pixels += 1
					unchanged = unchanged and images[i].get_pixel(x,y) == c
		check(white_pixels > 0 and unchanged,"opaque HUD glyphs unchanged "+NAMES[i]+suffix)

func strike(main, size: int) -> void:
	main.play_time += 0.5  # Within the unchanged three-second combo window.
	load("res://tests/test_special_combo.gd").new().fixture(main,size)
	events.append({"combo":main.keeper.combo,"precise":main.keeper.precise_events,"perfect":main.keeper.perfect_events,
		"palette":main.theme_i,"pending":main._palette_pending})

func restart(main) -> void:
	main.go_menu()
	await main.start_game("bright")
	freeze(main)
	check(main.theme_i == 0 and not main._palette_pending,"new party clears pending events and starts green")
	check(main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == 0.0 and
		main.board._frame.bg_color == Color(0.05,0.13,0.14,0.55),"new party restores original surfaces")

func run_suite(main) -> Dictionary:
	main.ComboExperiment.select("B",8181)
	main.rng.seed = 8181
	await main.start_game("bright")
	freeze(main)
	var p = main.get_node("/root/Progress")
	var cosmetics := [p.look,p.owned.duplicate(),p.crystals]
	var verifier = load("res://tests/test_visual_unification.gd").new()
	var data: String = verifier.digest(main.logic)
	var rng_state: int = main.rng.state
	var time: float = main.time_left
	var shape := [main.logic.cols,main.logic.rows,main.board.cell,main.board.origin,main.board.global_position]
	var textures := []
	for k in 6:
		textures.append(main.board._tex(k))
	check(not p.COSMETICS_ENABLED and main.theme_i == 0,"cosmetics disabled, initial green")
	check(main.board.material == null and main.ambient._velvet.material == main.ambient._fabric_mat,"dye attached only to velvet")
	check(main.board._run_surface_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,"surface layer never intercepts input")
	# Compare initial green with the unmodified texture and original board StyleBox.
	var green := await capture(main,"initial")
	main.ambient._velvet.material = null
	main.board.reset_run_surface()
	var original := await capture(main,"original")
	if green != null:
		check(green.get_data() == original.get_data(),"initial green pixel-identical to original texture/frame")
	await snapshot_palettes(main,"")
	main.ambient._classic_pools.visible = false
	await snapshot_palettes(main,"_surfaces_only")
	main.ambient._classic_pools.visible = true
	check(verifier.digest(main.logic) == data and main.rng.state == rng_state and main.time_left == time and main.score == 0,
		"surface colours leave cells/RNG/clock/score unchanged")
	check(shape == [main.logic.cols,main.logic.rows,main.board.cell,main.board.origin,main.board.global_position],"palette leaves geometry unchanged")
	for k in 6:
		check(main.board._tex(k) == textures[k],"gem textures unchanged "+str(k))
	main._set_theme(0,true)
	main.play_time = 10.0
	main._set_theme(main._next_look())
	check(main.theme_i == 1 and main.board._frame.bg_color.is_equal_approx(Color(0.05,0.13,0.14,0.55)),"fade starts without a jump")
	main.ambient._palette_tween.pause()
	main.ambient._palette_tween.custom_step(main.RUN_PALETTE_SECONDS/2.0)
	var strength: float = main.ambient._fabric_mat.get_shader_parameter("fabric_strength")
	check(strength > 0.1 and strength < 0.9 and main.board._frame.bg_color != Color(0.05,0.13,0.14,0.55),"both surfaces pass through intermediate colours")
	await capture(main,"transition_half")
	complete(main)
	check(main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == 1.0,"surface fade completes")
	# Direct restart while fading must cancel the old callback before awaiting UI layout.
	main.play_time += main.RUN_PALETTE_GAP+0.1
	main._set_theme(main._next_look())
	var old_fade: Tween = main.ambient._palette_tween
	main.start_game("bright")
	check(not old_fade.is_valid() and main.ambient._velvet.material == null and not main._palette_pending,
		"direct restart cancels dye before first layout frame")
	while main._run_starting:
		await main.get_tree().process_frame
	freeze(main)
	check(main.theme_i == 0 and main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == 0.0,
		"direct restart first board is green")
	# Real handler: normal strikes change colour only at streak length 10, 20, 30.
	await restart(main)
	for n in range(1,31):
		var before: int = main.theme_i
		strike(main,2)
		check(main.keeper.combo == n,"ordinary streak semantics "+str(n))
		check(main.theme_i == ((before+1)%6 if n%10 == 0 else before),"only tenth ordinary strike switches palette "+str(n))
		check(not main._palette_pending,"intermediate strikes never queue events "+str(n))
		if n%10 == 0:
			if DisplayServer.get_name() != "headless" and n == 10:
				await main.get_tree().create_timer(main.RUN_PALETTE_SECONDS+0.1).timeout
				check(main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == 1.0,"combo 10 fade finishes in real time")
				await capture(main,"event_combo10")
			else:
				complete(main)
	var chosen: int = main.theme_i
	main._on_slot(Vector2i(4,2))  # No matching objects along this cross in the fixture.
	check(main.keeper.combo == 0 and main.theme_i == chosen,"miss leaves chosen atmosphere intact")
	main._process(4.0)
	check(main.theme_i == chosen,"combo expiry does not reset green")
	# Precise then Perfect during its fade: retain one pending reward.
	await restart(main)
	for i in 3:
		strike(main,3)
	check(main.keeper.precise_events == 1 and main.theme_i == 1,"real Precise switches atmosphere")
	for i in 3:
		strike(main,3)
	check(main.keeper.perfect_events == 3 and main.theme_i == 1 and main._palette_pending,"Perfect events during fade coalesce into one waiting reward")
	if DisplayServer.get_name() != "headless":
		await capture(main,"event_precise_start")
		await main.get_tree().create_timer(main.RUN_PALETTE_SECONDS/2.0).timeout
		await capture(main,"event_precise_half")
		await main.get_tree().create_timer(main.RUN_PALETTE_SECONDS/2.0+0.1).timeout
		await capture(main,"event_precise")
	else:
		complete(main)
	complete(main)
	main.pause_game()
	main._process(10.0)
	check(main.theme_i == 1 and main._palette_pending,"pause cannot dispatch waiting palette")
	main._resume_play()
	main._process(main.RUN_PALETTE_GAP)
	check(main.theme_i == 2 and not main._palette_pending,"waiting Perfect reaches next transition without another hit")
	if DisplayServer.get_name() != "headless":
		await main.get_tree().create_timer(main.RUN_PALETTE_SECONDS+0.1).timeout
		await capture(main,"event_perfect")
	else:
		complete(main)
	main._process(main.RUN_PALETTE_GAP)
	check(main.theme_i == 2 and not main._palette_pending,"coalesced queue drains only once")
	# A strike meeting both thresholds must not create an extra waiting colour.
	await restart(main)
	for i in 7:
		strike(main,2)
	for i in 3:
		strike(main,3)
	check(main.keeper.combo == 10 and main.keeper.precise_events == 1 and main.theme_i == 1 and not main._palette_pending,
		"Precise plus combo 10 is one event")
	complete(main)
	# Full clear and Perfect can also be emitted by a single strike.
	await restart(main)
	for i in 3:
		strike(main,3)
	complete(main)
	main.play_time += main.RUN_PALETTE_GAP
	main.keeper._last_hit = main.play_time
	main.logic.load_cells(3,3,PackedInt32Array([-1,1,-1,1,-1,1,-1,-1,-1]))
	main.board.refresh()
	main._on_slot(Vector2i(1,1))
	check(main.keeper.perfect_events == 1 and main.wave == 2 and main.theme_i == 2 and not main._palette_pending,
		"Perfect plus full-clear wave is one event")
	while main.dealing:
		await main.get_tree().process_frame
	complete(main)
	freeze(main)
	# Real wave callbacks retain geometry and hazard exclusions.
	var dims := Vector2i(main.logic.cols,main.logic.rows)
	var geometry := [main.board.cell,main.board.origin,main.board.global_position]
	for wave in 3:
		main.play_time += main.RUN_PALETTE_GAP+0.1
		var before: int = main.theme_i
		main._next_wave(Vector2i.ZERO)
		check(main.theme_i == (before+1)%6,"real next-wave trigger")
		while main.dealing:
			await main.get_tree().process_frame
		if DisplayServer.get_name() != "headless" and wave == 0:
			await main.get_tree().create_timer(main.RUN_PALETTE_SECONDS+0.1).timeout
			freeze(main)
			await capture(main,"event_wave")
		else:
			complete(main)
		check(Vector2i(main.logic.cols,main.logic.rows) == dims and [main.board.cell,main.board.origin,main.board.global_position] == geometry,
			"wave surface transition keeps geometry")
		check(main.logic.ice.count(0) == main.logic.ice.size() and main.logic.bomb.count(0) == main.logic.bomb.size(),"hazards stay disabled")
	main.play_time += main.RUN_PALETTE_GAP+0.1
	main._set_theme(main._next_look())
	complete(main)
	check(main.theme_i == 0 and main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == 0.0,"six-colour cycle returns to original velvet")
	await restart(main)
	await capture(main,"restart_green")
	check([p.look,p.owned,p.crystals] == cosmetics,"cosmetic selection/ownership/currency unchanged")
	# Ordinary Run's material/queue cannot leak into Classic or Daily.
	for config in [["classic",false],["bright",true]]:
		main.go_menu()
		await main.start_game(config[0],config[1])
		freeze(main)
		check(main.ambient._velvet.material == null and not main.ambient._velvet_tinted and main.board._run_surface.a == 0.0 and
			not main.board._run_surface_layer.visible and not main._palette_pending,"original surfaces restored "+str(config))
		var frame: Color = main.board._frame.bg_color
		for i in 10:
			strike(main,2)
		check(main.board._frame.bg_color == frame and main.ambient._velvet.material == null,"combo 10 does not dye other modes "+str(config))
		for i in 4:
			strike(main,3)
		check(main.board._frame.bg_color == frame and main.ambient._velvet.material == null,"specials do not dye other modes "+str(config))
	main.go_menu()
	return {"checks":checks,"failed":failures.size(),"failures":failures,"pixels":pixels,"events":events}

