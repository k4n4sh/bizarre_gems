extends RefCounted
## Pinned test adapted to the FINAL bcee016 contract: zero-duration changes, no queue,
## timed Perfect cycles, ordinary thresholds 30/50. Its old fade/queue assertions were stale.
const NAMES := ["green", "purple", "wine", "blue", "teal", "bronze"]
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func freeze(main) -> void:
	main.board.set_process(false)
	main.board.clear_fx()
	main.board._deal_t = 99
	main.board._shake_off = Vector2.ZERO
	main.board._hover = Vector2i(-1,-1)
	main.board._fx.visible = false
	main.board.refresh()
	var bar: RecordBar = main.record_bar  # its fill eases in: settle it like the board
	bar.set_process(false)
	bar._fill = 1.0 if bar.beaten or bar.best <= 0 else clampf(float(bar.score) / bar.best, 0.0, 1.0)
	bar.queue_redraw()
	main.ambient.set_process(false)
	main.ambient._pulse = 0
	main.ambient._classic_mat.set_shader_parameter("pulse", 0.0)
	main.ambient._layer.visible = false
	var shader := Shader.new()
	shader.code = Ambient.POOLS_SHADER.replace("TIME", "0.0")
	main.ambient._classic_mat.shader = shader

func capture(main, label: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	# The scene-owned HUD has activity/value/delta tweens independent of board processing.
	# Compare settled pixels; keep the strict equality check of the original green intact.
	await main.get_tree().create_timer(.8).timeout
	for i in 3:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	check(img.save_png(OS.get_environment("VISUAL_CAPTURE_DIR").path_join("palette_" + label + ".png")) == OK, "save " + label)
	return img

func rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

func strike(main, count: int) -> void:
	var hit = load("res://tests/test_combo_runtime.gd").new()
	var colors: Array[int] = []
	colors.resize(count)
	colors.fill(1)
	hit.fixture(main, colors)
	main._on_slot(hit.A)

func restart(main) -> void:
	main.go_menu()
	await main.start_game("bright")
	freeze(main)
	check(main.theme_i == 0 and main.board._frame.bg_color.is_equal_approx(Color(.05,.13,.14,.55)), "party starts original green")

func run_suite(main) -> Dictionary:
	await restart(main)
	var data: String = load("res://tests/test_visual_unification.gd").new().digest(main.logic)
	var p = main.get_node("/root/Progress")
	var cosmetics := [p.look, p.owned.duplicate(), p.crystals]
	var geometry := [main.logic.cols, main.logic.rows, main.board.cell, main.board.origin]
	var rng_state: int = main.rng.state
	var textures := []
	for k in 6:
		textures.append(main.board._tex(k))
	check(main.RUN_PALETTE_SECONDS == 0.0, "pinned immediate transition duration")
	check(main.board.material == null and main.ambient._velvet.material == main.ambient._fabric_mat, "dye only on velvet")
	check(main.board._run_surface_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "surface cannot intercept input")
	var green := await capture(main, "initial")
	main.ambient._velvet.material = null
	main.board.reset_run_surface()
	var original := await capture(main, "original")
	if green != null:
		check(green.get_data() == original.get_data(), "initial green pixel-identical to original texture/frame")
	for lights in [true, false]:
		main.ambient._classic_pools.visible = lights
		var images: Array[Image] = []
		var colors: Array[Vector3] = []
		for i in 6:
			main._set_theme(i, true)
			var color: Color = main.board._frame.bg_color
			var luminance := color.r*.2126 + color.g*.7152 + color.b*.0722
			check(is_equal_approx(luminance, main.RUN_SURFACE_LUMA) and is_equal_approx(color.a, .55), "constant surface luminance " + NAMES[i])
			var dye: Color = main.ambient._fabric_mat.get_shader_parameter("fabric_color")
			check(dye.is_equal_approx(main.RUN_FABRICS[i]), "fabric dye " + NAMES[i])
			check(main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == (0.0 if i == 0 else 1.0), "fabric strength " + NAMES[i])
			var img := await capture(main, NAMES[i] + ("" if lights else "_surfaces"))
			if img == null:
				continue
			images.append(img)
			var average := Vector3.ZERO
			var low := INF
			var high := -INF
			var count := 0
			for y in range(int(main.board.global_position.y)+20, img.get_height()-25, 3):
				var sample := img.get_pixel(3, y)
				average += rgb(sample)
				var l := sample.r*.2126 + sample.g*.7152 + sample.b*.0722
				low = minf(low,l)
				high = maxf(high,l)
				count += 1
			colors.append(average/maxi(1,count))
			check(high-low > .015, "velvet texture variation " + NAMES[i])
			if i > 0:
				for j in i:
					check(colors[i].distance_to(colors[j]) > .035, "distinct rendered velvet " + NAMES[i]+"/"+NAMES[j])
				for idx in main.logic.cells.size():
					if main.logic.cells[idx] < 0 or main.logic.cells[idx] >= 6:
						continue
					var at: Vector2 = main.board.global_position + main.board.slot_center(Vector2i(idx%main.logic.cols, idx/main.logic.cols))
					check(img.get_pixel(int(at.x),int(at.y)) == images[0].get_pixel(int(at.x),int(at.y)), "gem centre unchanged " + NAMES[i]+" #"+str(idx))
	main.ambient._classic_pools.visible = true
	check(load("res://tests/test_visual_unification.gd").new().digest(main.logic) == data and main.rng.state == rng_state, "palettes leave cells/RNG unchanged")
	check(main.score == 0 and main.time_left == 120 and geometry == [main.logic.cols, main.logic.rows, main.board.cell, main.board.origin], "palettes leave geometry/clock/score unchanged")
	for k in 6:
		check(main.board._tex(k) == textures[k], "gem texture fixed " + str(k))
	await restart(main)
	for n in range(1,51):
		var before: int = main.theme_i
		strike(main,2)
		check(main.keeper.combo == n, "ordinary streak " + str(n))
		check(main.theme_i == ((before+1)%6 if n in [30,50] else before), "approved ordinary palette trigger " + str(n))
	var chosen: int = main.theme_i
	main._on_slot(Vector2i(6,1))
	main._process(4)
	check(main.keeper.combo == 0 and main.theme_i == chosen, "miss/expiry preserve atmosphere")
	await restart(main)
	for n in range(1,9):
		var before: int = main.theme_i
		strike(main,3)
		check(main.theme_i == ((before+1)%6 if n in [3,4,7,8] else before), "timed special immediate trigger " + str(n))
	check(main.keeper.precise_events == 2 and main.keeper.perfect_events == 2, "timed cycles retained")
	main.pause_game()
	var stopped: int = main.theme_i
	main._process(10)
	check(main.theme_i == stopped, "pause has no deferred palette event")
	main._resume_play()
	await restart(main)
	for i in 27:
		strike(main,2)
	for i in 3:
		strike(main,3)
	check(main.keeper.combo == 30 and main.keeper.precise_events == 1 and main.theme_i == 1, "special + threshold change once")
	main.logic.load_cells(3,3,PackedInt32Array([-1,1,-1,1,-1,1,-1,-1,-1]))
	main.board.refresh()
	main.play_time += .1
	main._on_slot(Vector2i(1,1))
	check(main.keeper.perfect_events == 1 and main.wave == 2 and main.theme_i == 2, "Perfect + full clear change once")
	while main.dealing:
		await main.get_tree().process_frame
	freeze(main)
	var dimensions := Vector2i(main.logic.cols,main.logic.rows)
	for i in 3:
		var before: int = main.theme_i
		main._next_wave(Vector2i.ZERO)
		check(main.theme_i == (before+1)%6, "next field changes once")
		while main.dealing:
			await main.get_tree().process_frame
		check(Vector2i(main.logic.cols,main.logic.rows) == dimensions, "field geometry stable")
		check(not main.logic.has_bombs() and main.logic.ice.count(0) == main.logic.ice.size(), "hazards remain disabled")
	main._set_theme(main._next_look())
	check(main.theme_i == 0 and main.ambient._fabric_mat.get_shader_parameter("fabric_strength") == 0.0, "six palette cycle restores green")
	# Exercise cancellation of the supported nonzero Ambient tween without changing Run duration.
	var theme: Dictionary = main.THEMES[1]
	main.ambient.fade_palette(theme.top,theme.bottom,.8,true,{"fabric":main.RUN_FABRICS[1],"strength":1.0,"lights":{"pool_a":Color.WHITE}},func(t): main.board.set_run_surface(Color(.1,.1,.1,.55)))
	var old_fade: Tween = main.ambient._palette_tween
	main.start_game("bright")
	check(not old_fade.is_valid() and main.ambient._velvet.material == null, "restart cancels old dye before layout")
	while main._run_starting:
		await main.get_tree().process_frame
	freeze(main)
	check(main.theme_i == 0, "restart starts green")
	check([p.look,p.owned,p.crystals] == cosmetics, "dyes do not modify cosmetic data/currency")
	for config in [["classic",false],["bright",true]]:
		main.go_menu()
		await main.start_game(config[0],config[1])
		freeze(main)
		check(main.ambient._velvet.material == null and not main.ambient._velvet_tinted and main.board._run_surface.a == 0 and not main.board._run_surface_layer.visible, "original surfaces restored " + str(config))
		var frame: Color = main.board._frame.bg_color
		for i in 4:
			strike(main,3)
		check(main.board._frame.bg_color == frame and main.ambient._velvet.material == null, "specials cannot dye other modes")
	main.board._fx.visible = true
	main.go_menu()
	return {"checks":checks,"failed":failures.size(),"failures":failures}
