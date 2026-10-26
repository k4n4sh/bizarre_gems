extends SceneTree
## Scene contracts and pinned geometry: only tools/test_isolated.ps1, optional -Render.
var checks := 0
var failures: Array[String] = []
var observations: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func settle(count := 8) -> void:
	for i in count: await process_frame

func geometry(main) -> Array:
	var result := [main.board.get_global_rect(),main.board.cell,main.board.origin]
	for slot in main.hud.stat_slots: result.append(slot.get_global_rect())
	for button in [main.hud.btn_pause,main.hud.btn_restart,main.hud.btn_settings]: result.append(button.get_global_rect())
	return result

func capture(vp: SubViewport, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(OS.get_environment("VISUAL_CAPTURE_DIR").path_join("hud_"+label+".png")) == OK,"capture "+label)

func bounds(main, context: String) -> void:
	var hud = main.hud
	var inset: Rect2 = main.test_insets
	var safe := Rect2(inset.position,main.get_viewport_rect().size-inset.position-inset.size)
	var frame := Rect2(main.board.global_position+main.board.origin-Vector2.ONE*main.board.frame_pad,Vector2(main.logic.cols,main.logic.rows)*main.board.cell+Vector2.ONE*main.board.frame_pad*2)
	check(safe.grow(1).encloses(frame),context+" field inside safe area")
	for slot in hud.stat_slots:
		if not slot.is_visible_in_tree(): continue
		check(safe.grow(1).encloses(slot.get_global_rect()),context+" slot safe "+slot.name)
		check(not frame.intersects(slot.get_global_rect()),context+" slot outside field "+slot.name)
	for button in [hud.btn_pause,hud.btn_restart,hud.btn_settings]:
		check(safe.grow(1).encloses(button.get_global_rect()),context+" button safe")
		check(not frame.intersects(button.get_global_rect()),context+" button outside field")
	if hud.mode_id == "bright":
		var badge_rect: Rect2 = hud.combo_box.get_global_rect()
		check(hud.get_node("Stats/Combo").get_global_rect().grow(1).encloses(badge_rect),context+" animated badge stays in reservation")
		check(not badge_rect.intersects(hud.chain_slot.get_global_rect()),context+" badge clear of chain")
		check(not badge_rect.intersects(hud.time_label.get_global_rect()),context+" badge clear of time")

func _run() -> void:
	await process_frame
	root.get_node("Save").sound = false
	root.get_node("Save").music = false
	root.get_node("Sfx").update_music()
	var locale = root.get_node("L")
	var screens := [[1280,720,false,Rect2()],[960,540,false,Rect2()],[800,600,false,Rect2(20,12,16,10)],
		[480,850,false,Rect2(12,24,8,18)],[853,480,true,Rect2()],[1066,480,true,Rect2(40,8,12,16)],
		[800,600,true,Rect2()],[480,850,true,Rect2(12,24,8,18)]]
	for screen in screens:
		var vp := SubViewport.new()
		vp.size = Vector2i(screen[0],screen[1])
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var scene = load("res://scenes/main.tscn").instantiate()
		scene.set_script(load("res://tests/hud_platform_fixture.gd"))
		scene.simulate_android = screen[2]
		scene.test_insets = screen[3]
		vp.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scene.set_process(false)
		await settle()
		for mode in ["classic","bright","daily","challenge"]:
			if mode == "classic" and screen[2] and screen[0] < screen[1]: continue
			if mode != "classic" and screen[2] and screen[0] > screen[1]: continue
			var ch := {"mode":"bright","seed":8181,"dims":Vector2i(18,11),"score":100} if mode == "challenge" else {}
			await scene.start_game("classic" if mode == "classic" else "bright",mode == "daily",ch)
			scene._on_viewport_resized()
			await settle()
			scene.board.set_process(false)
			scene.board._deal_t = 99
			scene.board.queue_redraw()
			var shape := [scene.logic.cols,scene.logic.rows]
			var base := geometry(scene)
			var hud = scene.hud
			var context := "%dx%d_%s_%s" % [vp.size.x,vp.size.y,str(screen[2]),mode]
			check(hud.side_layout == (mode == "classic" and screen[2]),context+" native layout selection")
			check(mode == "classic" or hud.run_badge.is_visible_in_tree(),context+" Run/Daily/Challenge badge present")
			check(mode != "classic" or hud.run_badge == null,context+" Classic has no coloured badge instance")
			if mode != "classic":
				check(not hud.get_node("Stats/Combo/Streak").is_visible_in_tree(),context+" no duplicate ordinary series")
			if mode == "classic" and screen[2]:
				var expected_cell := maxf(8,floorf(minf((vp.size.x-maxf(screen[3].position.x,screen[3].size.x)*4-140-16-6)/BoardLogic.LONG,(vp.size.y-maxf(screen[3].position.y,screen[3].size.y)*2-8-6)/BoardLogic.SHORT)))
				check(scene.board.cell == expected_cell,context+" pinned side cell geometry")
				check(absf(hud.best_label.get_parent().get_global_rect().get_center().y-hud.btn_restart.get_global_rect().get_center().y) <= 1.1,context+" whole record block centred on restart")
			for language in ["ru","en","tr"]:
				locale.set_language(language)
				scene.keeper.reset()
				for length in [0,1,2,5,9,46,12345]:
					scene.keeper.combo = length
					scene.keeper._last_hit = scene.play_time
					scene.keeper.color_streak_kind = 1
					scene.keeper.color_streak_hits = 4
					scene._update_hud()
					hud.set_combo(length,true)
					if mode != "classic" and length >= 2:
						check(hud.combo_box.scale.is_equal_approx(Vector2.ONE*1.35),context+" exact initial upstream pulse scale")
					hud.set_number(hud.score_label,9223372036854775807)
					hud.set_number(hud.best_label,9223372036854775807)
					hud.flash_delta("+999",false)
					await settle(3)
					check(geometry(scene) == base,context+language+" invariant slots with long values/activation")
					check(hud.score_label.text.replace("\u2009","").replace("\n","") == "9223372036854775807",context+" all digits")
					check(hud.chain_count.text == "4" and hud.chain_gem.texture == scene.board._tex(1),context+" independent Color Chain")
					if mode != "classic":
						var m := ScoreKeeper.multiplier_for(length)
						if length >= 2:
							check(hud.combo_mult.text == "%s ×%d · %d" % [locale.t("combo").to_upper(),m,length],context+" upstream label")
							check((hud.combo_box.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == UiKit.COMBO_COLORS[m-1],context+" upstream tier colour")
							check(hud.combo_box.scale.x >= .96 and hud.combo_box.scale.x <= 1.36,context+" original Back pulse stays bounded")
						else: check(hud.combo_box.modulate.a == 0,context+" hidden below 2")
					else:
						var multiplier_text := "×%d" % (ScoreKeeper.multiplier_for(length) if length >= 2 else 1)
						# Desktop Classic shows the multiplier inside the streak ring.
						var shown: String = hud.get_node("Plates/StreakRing").text if hud.top_layout else hud.combo_mult.text
						check(shown == multiplier_text,context+" reference multiplier")
					bounds(scene,context+language)
					if length == 9 and language == "ru":
						await capture(vp,context+"_active")
						hud.set_number(hud.score_label,12345)
						hud.set_number(hud.best_label,67890)
						await settle(3)
						await capture(vp,context+"_normal")
				var clock: float = scene.play_time
				hud.update_progress(scene.keeper,clock+1.75,true,scene.board,scene.wave)
				check(is_equal_approx(hud.combo_bar.value,50),context+" half of ordinary 3.5s")
				var tw: Tween = hud.run_badge._pulse if mode != "classic" else null
				if tw and tw.is_valid(): tw.pause(); tw.custom_step(.4)
				check(mode == "classic" or hud.combo_box.scale.is_equal_approx(Vector2.ONE),context+" pulse settles")
				hud.fade_combo()
				await create_timer(.4).timeout
				check(mode == "classic" or hud.combo_box.modulate.a == 0,context+" fade .35s")
			check(shape == [scene.logic.cols,scene.logic.rows],context+" HUD never changes logical shape")
			observations.append({"mode":context,"cell":scene.board.cell,"header":hud.get_node("Stats").size})
			scene.go_menu()
		for hidden in ["levels","zen","puzzle","tutorial"]:
			scene._use_mode(hidden)
			check(not scene.hud.run_badge.visible,"no badge in "+hidden)
			scene.go_menu()
		scene.queue_free()
		await settle(2)
		vp.queue_free()
		await settle(2)
	locale.set_language("ru")
	print("HUD_LAYOUT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"observations":observations}))
	if not failures.is_empty(): push_error("FAIL HUD layout")
	print("HUD_LAYOUT_DONE")
	quit(0 if failures.is_empty() else 1)
