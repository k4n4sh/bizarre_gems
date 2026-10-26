extends RefCounted
## Pinned packet/priority tests adapted to scene-owned upstream nodes. Permanent HUD rails,
## Android touch and stable stat slots are deferred to stage 6, not asserted here.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func settle(main, count := 6) -> void:
	for i in count:
		await main.get_tree().process_frame

func packets(main, label: String) -> void:
	var occupied: Array[Rect2] = []
	var exclusion: Rect2 = main._feedback_exclusion()
	if exclusion.has_area():
		occupied.append(exclusion)
	var visible := 0
	for i in range(main.board._texts.size()-1,-1,-1):
		var packet: Dictionary = main.board._texts[i]
		if not packet.has("slot"):
			continue
		var layout: Dictionary = main.board._feedback_layout(packet,occupied)
		if layout.is_empty():
			continue
		var rect: Rect2 = layout.rect
		check(Rect2(Vector2.ZERO,main.board.size).encloses(rect), label+" popup inside board")
		for other in occupied:
			check(not rect.intersects(other), label+" popup avoids other texts/banner")
		occupied.append(rect)
		visible += 1
	check(visible > 0, label+" newest reward readable")
	check(main.board._texts.size() <= 3 and main.board._fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, label+" bounded noninteractive feedback")

func capture(main, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	main.board.queue_redraw()
	main.board._fx.queue_redraw()
	await settle(main)
	await RenderingServer.frame_post_draw
	check(main.get_viewport().get_texture().get_image().save_png(OS.get_environment("VISUAL_CAPTURE_DIR").path_join("feedback_"+label+".png")) == OK, "capture " + label)

func run_suite(main) -> Dictionary:
	var hit = load("res://tests/test_combo_runtime.gd").new()
	var pair: Array[int] = [0,0]
	var triple: Array[int] = [0,0,0]
	var blue_pair: Array[int] = [1,1]
	var locale = main.get_node("/root/L")
	var old_language: String = locale.lang
	for mode in ["classic", "bright"]:
		await main.start_game(mode)
		main.board._fx.visible = true
		main.board.set_process(false)
		main.board._deal_t = 99
		for language in ["ru", "en", "tr"]:
			locale.set_language(language)
			main.keeper.reset()
			main._reset_visual_feedback()
			for i in 2:
				hit.fixture(main,pair)
				main._on_slot(hit.A)
			var packet: Dictionary = main.board._texts[-1]
			var award: Dictionary = packet.rewards
			check(award.color_streak_points == 6 and award.double_hit_points == 2, "real reference awards")
			check(packet.rows[0].s == locale.t("color_chain_start")+"  +6" and packet.rows[1].s == locale.t("double_hit")+"  +2", mode+language+" exact names/amounts")
			check(packet.rows[2].s == locale.t("hit_total",{"n":award.points}), "actual total, no visual recalculation")
			check(packet.rows[0].c == main.board._col(0).lightened(.38) and packet.rows[1].c == main.board.LIGHT_FX, "reference colours")
			check(packet.started and packet.double and packet.life == .72, "start duration/indicators")
			packets(main, mode+language+" start")
			await capture(main, mode+"_"+language+"_double_chain")
			hit.fixture(main,pair)
			main._on_slot(hit.A)
			packet = main.board._texts[-1]
			check(not packet.started and packet.life == .5 and packet.rows[0].s == locale.t("color_chain_length",{"n":3})+"  +4", "compact continuation exact receipt")
			for i in 4:
				hit.fixture(main,triple)
				main._on_slot(hit.A)
			check(main.banner.get_meta("priority") == 3, "real Perfect highest priority")
			var title: String = main.get_node("%BannerTitle").text
			main._banner(locale.t("precise"),10,3,Color.WHITE,"",2)
			check(main.get_node("%BannerTitle").text == title, "Precise cannot replace visible Perfect")
			main._banner("board",100,60,Color.WHITE,"actual field award",0)
			check(main.get_node("%BannerTitle").text == title and main.get_node("%BannerSub").text.ends_with("actual field award"), "field award joins dominant special")
			await settle(main)
			packets(main,mode+language+" special")
			await capture(main,mode+"_"+language+"_special")
			var tween: Tween = main.banner.get_meta("banner_tween")
			tween.pause()
			tween.custom_step(main.SPECIAL_BANNER_SECONDS + .01)
			check(main.banner.modulate.a == 0, "special banner expires after .75s")
			main.board._process(.8)
			check(main.board._texts.is_empty(), "short local messages expire")
		# Shape/size/zoom/transpose all resolve logical anchors, not stored pixels.
		main._reset_visual_feedback()
		var blank := PackedInt32Array()
		blank.resize(22 * 14)
		blank.fill(BoardLogic.EMPTY)
		main.logic.load_cells(22,14,blank)
		main.board.refresh()
		var original_size: Vector2 = main.board.size
		var empty_slots: Array[Vector2i] = []
		var empty_kinds: Array[int] = []
		for extent in [Vector2(420,500),Vector2(800,400),Vector2(320,300)]:
			main.board.size = extent
			for zoom in [1.0,1.6,2.4]:
				main.board.zoom = zoom
				main.board.pan = Vector2(35,-27)
				main.board._relayout()
				for at in [Vector2i(0,0),Vector2i(22,0),Vector2i(0,14),Vector2i(22,14)]:
					main.board.play_knock(at,empty_slots,empty_kinds,14)
					main.board.play_bonus_feedback(at,{"color_streak_points":6,"color_streak_started":true,"double_hit_points":2},1,2,locale.t("color_chain_start"),locale.t("color_chain_length",{"n":2}),locale.t("double_hit"))
					packets(main,"edges/zoom/resize")
		main.board.reset_zoom()
		main.logic.transpose()
		main.board.transposed()
		check(main.board._texts[-1].slot == Vector2i(14,22), "transpose keeps logical feedback anchor")
		main.board.size = original_size
		main.go_menu()
		check(main.board._texts.is_empty() and main.banner.modulate.a == 0, "menu clears feedback")
		await main.start_game(mode)
		hit.fixture(main,blue_pair); main._on_slot(hit.A)
		hit.fixture(main,blue_pair); main._on_slot(hit.A)
		var combo: int = main.keeper.combo
		main.pause_game()
		main._process(20)
		main._resume_play()
		check(main.keeper.combo == combo, "pause/resume preserves combo")
		main.end_game("time")
		check(mode == "bright" or main.board._texts.is_empty(), "Classic result clears messages")
		check(mode != "bright" or main.keeper.combo == combo, "eligible Run result preserves keeper")
		await main.start_game(mode)
		check(main.board._texts.is_empty() and main.banner.modulate.a == 0, "restart clears messages")
		main.go_menu()
	locale.set_language(old_language)
	return {"checks":checks,"failed":failures.size(),"failures":failures}
