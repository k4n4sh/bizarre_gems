extends RefCounted
## Run only through test_classic_bonus_combos.ps1, with isolated saves and baseline UI.
const A := Vector2i(3, 3)
const B := Vector2i(4, 3)
var checks := 0
var failures: Array[String] = []
var layouts: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func settle(tree: SceneTree, frames := 8) -> void:
	for i in frames:
		await tree.process_frame

func fixture(main, colors: Array[int], slot := A, shining := 0) -> void:
	var cells := PackedInt32Array()
	cells.resize(49)
	cells.fill(BoardLogic.EMPTY)
	for i in colors.size():
		var p: Vector2i = slot + BoardLogic.DIRS[i]
		cells[p.y * 7 + p.x] = colors[i]
	# A separate pair keeps this fixture away from automatic field/result branches.
	cells[42] = 5
	cells[44] = 5
	main.logic.load_cells(7, 7, cells)
	for i in colors.size():
		var p: Vector2i = slot + BoardLogic.DIRS[i]
		main.logic.shine[p.y * 7 + p.x] = 1 if i < shining else 0
	main.board.refresh()
	main.play_time += 0.1
	main.dealing = false

func combo_state(main) -> Dictionary:
	var k: ScoreKeeper = main.keeper
	return {"clock": main.play_time, "combo": k.combo, "special": k.precise_streak,
		"ordinary_left": k.window_left(main.play_time), "special_left": k.special_window_left(main.play_time),
		"color": k.color_streak_kind, "length": k.color_streak_hits,
		"unpaid": k._previous_color_points.duplicate(), "slot": k._double_hit_slot}

func rules() -> void:
	var modern := ScoreKeeper.new()
	modern.configure_combo_rules(false, true)
	modern.time_bonuses = false
	var classic := ScoreKeeper.new()
	classic.configure_combo_rules(true, false)
	classic.configure_time_rewards(true)
	var hit_sizes := [3, 2, 3, 2, 3, 3, 3, 3, 3, 3, 2, 4, 4, 4, 4, 4]
	for i in hit_sizes.size():
		var colors: Array[int] = []
		colors.resize(hit_sizes[i])
		colors.fill(i % 2)
		var r := modern.hit(hit_sizes[i], i * 0.3, 2, A, colors)
		var c := classic.hit(hit_sizes[i], i * 0.3, 2, A, colors)
		check(r.points == c.points and r.event == c.event and r.mult == c.mult,
			"shared points, multiplier and unique cycle %d" % i)
		check(r.time == 0 and modern.special_bonus_time == 0, "Run has no hit seconds %d" % i)
		check(modern.precise_streak == classic.precise_streak, "pair support/cycle progress %d" % i)
	modern.reset()
	for i in 10:
		var r := modern.hit(2, i * 0.1, 0, A, [0, 0])
		check(r.mult == (1 if i == 0 else (2 if i < 4 else (3 if i < 8 else 4))), "tier boundary %d" % i)
	modern.reset()
	modern.hit(2, 0.0, 0, A, [99, 99])
	var result := modern.hit(2, 0.1, 0, B, [99, 99])
	check(result.color_streak_points == 0 and modern.color_streak_kind == -1, "joker-only strikes cannot create color 99")

func run_events(main) -> void:
	for daily in [false, true]:
		await main.start_game("bright", daily)
		check(main.keeper.timed_special and main.keeper.classic_bonus_combos and main.keeper.combo_window == 3.5,
			"Run/Daily modern configuration " + str(daily))
		for i in 8:
			fixture(main, [0, 0, 0], A, 2)
			main._on_slot(A)
		check(main.keeper.precise_events == 2 and main.keeper.perfect_events == 2
			and main.keeper.precise_streak == 0, "Run/Daily two complete special cycles")
		check(main.time_left == 120.0 and main.keeper.special_bonus_time == 0, "no group, shine, special or tier seconds")
		fixture(main, [0, 0], A)
		main._on_slot(A)
		fixture(main, [0, 0], A)
		main._on_slot(A)
		check(main.time_left == 120.0 and main.keeper.combo == 10, "no tenth-hit seconds")
		check(main.board._texts[-1].double and main.board._texts[-1].chain == 0
			and main.board._texts[-1].rows.size() == 3, "named simultaneous bonuses in one popup")
		main.go_menu()
	await main.start_game("bright")
	fixture(main, [0, 99], A)
	check(main.logic.joker_match_kind(A) == 0 and main.logic.matches_from(A).size() == 2, "ordinary + joker joins ordinary color")
	main._on_slot(A)
	fixture(main, [0, 99], B)
	main._on_slot(B)
	check(main.keeper.color_streak_kind == 0 and main.keeper.color_streak_hits == 2, "joker starts a real color chain")
	fixture(main, [0, 99], A)
	main._on_slot(A)
	check(main.keeper.color_streak_hits == 3, "joker continues existing color chain")
	check(main.hud_sets.bright_web.bonus.gem.texture == main.board._tex(0), "HUD uses Run's effective texture mapping")
	fixture(main, [1, 0, 99, 99], A)
	check(main.logic.joker_match_kind(A) == 1 and main.logic.matches_from(A).size() == 3, "ambiguous joker tie follows ray discovery order")
	main._on_slot(A)
	check(main.keeper._previous_color_points.has(1) and not main.keeper._previous_color_points.has(99), "chosen joker color counted once")
	fixture(main, [99, 99], B)
	main._on_slot(B)
	check(main.keeper.color_streak_kind == -1 and main.keeper._previous_color_points.is_empty(), "joker-only move remains colorless")
	main.go_menu()

func waves(main) -> void:
	var tree: SceneTree = main.get_tree()
	Engine.time_scale = 20.0  # Only accelerate actual deal tweens; game clocks are stepped explicitly.
	for full_clear in [false, true]:
		await main.start_game("bright")
		for completed in range(1, 7):
			main.keeper.miss()
			var triple: Array[int] = [0, 0, 0]
			var pair: Array[int] = [0, 0]
			var mixed: Array[int] = [0, 0, 1, 1]
			main.keeper.hit(3, main.play_time, 0, A, triple)
			main.keeper.hit(2, main.play_time, 0, B, pair)
			main.keeper.hit(4, main.play_time, 0, A, mixed)
			main.score = main.keeper.score
			var before := combo_state(main)
			if full_clear:
				main.logic.cells.fill(BoardLogic.EMPTY)
			var time_before: float = main.time_left
			var points_before: int = main.keeper.score
			main._next_wave(A)
			var expected := 40 if completed == 1 else (30 if completed == 2 else (20 if completed == 3 else 10))
			check(main.time_left == time_before + expected + (20 if full_clear else 0), "transition time %d full=%s" % [completed, full_clear])
			check(main.score == points_before + (100 + 50 * (completed - 1) if full_clear else 0), "Full Clear points only on actual empty board")
			check(main.keeper._double_hit_slot == Vector2i(-1, -1), "new board clears pending Double Hit")
			before.slot = Vector2i(-1, -1)
			check(combo_state(main) == before, "other combo states survive transition")
			var frozen_time: float = main.time_left
			main._process(10.0)
			check(main.time_left == frozen_time and combo_state(main) == before, "all clocks frozen during mandatory animation")
			main._next_wave(A)
			check(main.wave == completed + 1 and main.time_left == frozen_time, "duplicate transition cannot award again")
			check(main.banner_sub.text.contains("+%d" % expected)
				and (not full_clear or main.banner_sub.text.contains("+20")), "actual reward breakdown in banner")
			for frame in 300:
				if not main.dealing:
					break
				await tree.process_frame
			check(not main.dealing and combo_state(main) == before, "actual deal callback preserves clocks")
			var next_color := 1 if completed % 2 == 0 else 0
			var next_pair: Array[int] = [next_color, next_color]
			fixture(main, next_pair, A)
			main._on_slot(A)
			check(not main.board._texts[-1].double and main.keeper.color_streak_kind == next_color
				and main.keeper.color_streak_hits == (2 if next_color == 1 else 4),
				"new board preserves both active chain and unpaid mixed-color portion, without Double Hit")
		main.go_menu()
	Engine.time_scale = 1.0

func continued(main) -> void:
	var tree: SceneTree = main.get_tree()
	var ad = main.get_node("/root/Yandex")
	ad.set_script(load("res://tests/rewarded_ad_fixture.gd"))
	await main.start_game("bright")
	fixture(main, [0, 0, 0], A)
	main._on_slot(A)
	fixture(main, [0, 0], B)
	main._on_slot(B)
	var old_keeper: ScoreKeeper = main.keeper
	main.time_left = 0.25
	var old_clock: float = main.play_time
	main._process(1.0)
	check(main.state == main.State.OVER and main.play_time == old_clock + 0.25, "timer exhaustion clips game time at actual stop")
	var frozen := combo_state(main)
	main._process(60.0)
	check(combo_state(main) == frozen and main.time_left == 0, "result screen freezes all remaining windows")
	main._on_continue()
	ad.resolve_reward(false)
	await settle(tree)
	check(main.state == main.State.OVER and not main.used_continue and main.time_left == 0
		and combo_state(main) == frozen, "failed ad gives no time or restoration")
	main._on_continue()
	ad.resolve_reward(true)
	await settle(tree)
	check(main.state == main.State.PLAYING and main.used_continue and main.time_left == 15
		and main.keeper == old_keeper and combo_state(main) == frozen, "successful ad resumes the same game with exact remaining windows")
	fixture(main, [0, 0], B)
	main._on_slot(B)
	check(main.board._texts[-1].double and main.keeper.color_streak_hits == 3, "pending positional and color chains continue after ad")
	main.go_menu()
	await main.start_game("bright")
	fixture(main, [0, 0, 0], A)
	main._on_slot(A)
	main.play_time += 3.5001
	main.time_left = 0
	main.end_game("time")
	check(main.keeper.combo == 0 and main.keeper.precise_streak == 0 and main.keeper._double_hit_slot.x == -1, "already expired series cannot survive continuation")
	main._on_continue()
	await main.start_game("bright")
	ad.resolve_reward(true)
	await settle(tree)
	check(main.time_left == 120 and not main.used_continue, "late ad callback cannot mutate a restarted run")
	main.go_menu()

func banners(main) -> void:
	for mode in ["classic", "bright"]:
		await main.start_game(mode)
		main._banner("PERFECT", 20, 0.0, Color.WHITE, "", 3)
		var first: Tween = main.banner_box.get_meta("banner_tween")
		main._banner("PRECISE", 10, 0.0, Color.WHITE, "", 2)
		check(main.banner_title.text == "PERFECT" and main.banner_box.get_meta("banner_tween") == first, "Perfect remains primary " + mode)
		main._banner("PERFECT", 20, 0.0, Color.WHITE, "", 3)
		check(not first.is_valid(), "rapid event replaces previous animation without a queue " + mode)
		var tw: Tween = main.banner_box.get_meta("banner_tween")
		tw.pause()
		tw.custom_step(0.74)
		check(main.banner_box.modulate.a > 0.0, "special still visible before 0.75 s " + mode)
		tw.custom_step(0.02)
		check(main.banner_box.modulate.a <= 0.001, "special gone after 0.75 s " + mode)
		main.go_menu()

func hud_geometry(sample) -> Dictionary:
	var out := {"board": sample.board.get_global_rect(), "cell": sample.board.cell,
		"dims": Vector2i(sample.logic.cols, sample.logic.rows), "origin": sample.board.origin}
	for key in ["score", "best", "time", "bar", "delta", "combo_box", "pause", "restart", "settings"]:
		var control: Control = sample.hud_sets.bright[key]
		out[key] = control.get_global_rect()
	out.hint = sample.hud_balance.get_global_rect()
	return out

func ui_layouts(main) -> void:
	var tree: SceneTree = main.get_tree()
	for config in [[1280,720,false], [900,600,false], [480,1008,false], [480,860,true], [480,1008,true], [720,1280,true]]:
		var vp := SubViewport.new()
		vp.size = Vector2i(config[0], config[1])
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		tree.root.add_child(vp)
		var old = load("res://tests/baseline_bright_fixture.gd").new()
		var sample = load("res://tests/bright_run_fixture.gd").new()
		old.simulate_android = config[2]
		sample.simulate_android = config[2]
		for view in [old, sample]:
			vp.add_child(view)
			view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			view.set_process(false)
			await view.start_game("bright")
			await settle(tree, 12)
		var baseline := hud_geometry(old)
		var current := hud_geometry(sample)
		for key in ["board", "cell", "dims", "origin"]:
			check(current[key] == baseline[key], "field geometry unchanged %s %s" % [config, key])
		if config[2]:
			check(current == baseline, "Android HUD rectangles unchanged from base commit " + str(config))
			check(sample.hud.visible and sample.time_row.visible and not sample.hud_sets.bright_web.roots[0].visible, "Android retains two rows")
		else:
			check(not sample.hud.visible and not sample.time_row.visible and sample.hud_sets.bright_web.roots[0].visible, "browser uses horizontal header")
			check(sample.hud_sets.bright_web.slots.size() == 5 and sample.btn_hint == sample.hud_sets.bright_web.hint,
				"five fixed statistics plus active hint button")
			var set: Dictionary = sample.hud_sets.bright_web
			var rendered_width: float = sample.logic.cols * sample.board.cell + sample.board.frame_pad * 2
			check(absf(set.row.size.x - rendered_width) <= 1.0, "header fits the actual first Run grid")
			var before: Rect2 = sample.board.get_global_rect()
			for language in ["ru", "en", "tr"]:
				sample.get_node("/root/L").set_language(language)
				fixture(sample, [3,3], A)
				sample._on_slot(A)
				fixture(sample, [3,3], B)
				sample._on_slot(B)
				await settle(tree)
				check(sample.board.get_global_rect() == before and set.combo_box.get_meta("hud_active")
					and set.bonus.progress.get_meta("hud_active"), "active bonuses preserve fixed HUD " + language)
				check(set.bonus.gem.texture == sample.board._tex(3), "Run remapped cyan indicator " + language)
				var occupied: Array[Rect2] = []
				var exclusion: Rect2 = sample._feedback_exclusion()
				if exclusion.has_area():
					occupied.append(exclusion)
				for packet in sample.board._texts:
					var placement: Dictionary = sample.board._feedback_layout(packet, occupied)
					if not placement.is_empty():
						check(not occupied.any(func(rect): return rect.intersects(placement.rect)), "Run bonus messages avoid each other and the special banner")
						occupied.append(placement.rect)
				for slot in set.slots + [set.buttons]:
					check(not slot.get_global_rect().intersects(sample.board.get_global_rect()), "header stays outside playable field")
				sample.keeper.miss()
				sample._update_combo_widget()
				sample._update_bonus_progress()
				check(not set.combo_box.get_meta("hud_active") and not set.bonus.progress.get_meta("hud_active"), "inactive statistics stay present and muted")
			sample._flash_delta("+60", false)
			await settle(tree)
			check(not sample.time_delta.get_global_rect().intersects(sample.board.get_global_rect())
				and not sample.time_delta.get_global_rect().intersects(sample.score_label.get_global_rect()),
				"transition seconds do not overlap the field or score")
		layouts.append({"screen": config, "baseline": baseline, "current": current})
		old.visible = false
		if DisplayServer.get_name() != "headless" and not OS.get_environment("COMBO_SCREENSHOT_DIR").is_empty():
			sample.get_node("/root/L").set_language("ru")
			await sample.start_game("bright")
			await settle(tree)
			check(sample.time_delta.modulate.a == 0.0, "restart clears previous transition-time notification")
			if not config[2]:
				var width: float = sample.logic.cols * sample.board.cell + sample.board.frame_pad * 2
				check(absf(sample.hud_sets.bright_web.row.size.x - width) <= 1.0, "header refits after a different previous board shape")
			for i in 2:
				var move: Vector2i = sample.logic.find_move()
				sample.play_time += 0.1
				sample._on_slot(move)
				sample._set_hud_number(sample.score_label, sample.score)
			await settle(tree)
			await RenderingServer.frame_post_draw
			var label := "%dx%d_%s" % [config[0], config[1], "android" if config[2] else "web"]
			vp.get_texture().get_image().save_png(OS.get_environment("COMBO_SCREENSHOT_DIR").path_join(label + ".png"))
		old.go_menu()
		sample.go_menu()
		vp.queue_free()
		await tree.process_frame
	main.get_node("/root/L").set_language("ru")

func run_suite(main) -> Dictionary:
	if not main.get_node("/root/Save").PATH.begins_with("res://.test-user/") \
			or not main.get_node("/root/Progress").PATH.begins_with("res://.test-user/") \
			or not FileAccess.file_exists("res://tests/baseline_bright_fixture.gd"):
		return {"error": "Use test_classic_bonus_combos.ps1 with suite=test_unified_combos."}
	rules()
	await run_events(main)
	await waves(main)
	await continued(main)
	await banners(main)
	await ui_layouts(main)
	return {"checks": checks, "failed": failures.size(), "failures": failures, "layouts": layouts}
