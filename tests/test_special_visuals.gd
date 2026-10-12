extends RefCounted
## MCP runtime regression. Run on a fresh menu; storage is locked for this process.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func fixture(b) -> void:
	b.logic.load_cells(6, 4, PackedInt32Array([0,1,2,3,4,5,99,1,2,3,4,5,0,1,2,3,4,99,2,-1,2,3,-1,3]))
	b.logic.hp[7] = 2
	b.logic.hp[12] = 2
	b.logic.chain[8] = 13
	b.logic.chain[13] = 8
	b.logic.ice[9] = 1
	b.logic.ice[12] = 1
	b.logic.ice[14] = 1
	b.logic.bomb[10] = 8
	b.logic.bomb[14] = 2
	b.logic.bomb[16] = 1
	b.logic.cham[11] = 1
	b.logic.cham[15] = 1
	b.logic.cham[16] = 1
	b.logic.shine[17] = 1
	b.refresh()
	b._deal_t = 99
	b.queue_redraw()

func run_suite(main) -> Dictionary:
	if main.state != main.State.MENU:
		return {"error":"Fresh menu required"}
	main.ComboExperiment.select("B", 42)
	main.set_process(false)
	var save = main.get_node("/root/Save")
	var progress = main.get_node("/root/Progress")
	var hashes := {}
	for path in [save.PATH, progress.PATH]:
		hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var visual = load("res://tests/test_visual_unification.gd").new()
	var hits = load("res://tests/test_special_combo.gd").new()
	# Same actual strike handler, fixtures and timing; only visual profile changes.
	var observations := []
	for daily in [false,true]:
		var reference := {}
		for profile in ["classic","classic_run"]:
			await main.start_game("bright", daily)
			main.board.visual_profile = profile
			for i in 20:
				main._process(.15)
				hits.fixture(main, 3)
			var result := {"score":main.score,"time":main.time_left,"combo":main.keeper.combo,
				"precise":main.keeper.precise_events,"perfect":main.keeper.perfect_events,"cleared":main.cleared,
				"hash":visual.digest(main.logic)}
			if profile == "classic":
				reference = result
			else:
				check(result == reference, "presentation-independent 20 real strikes: daily=" + str(daily))
				check(result.combo == 20 and result.precise == 1 and result.perfect == 17, "legacy long combo events retained")
			observations.append(result)
			main.go_menu()
	await main.start_game("bright")
	var b = main.board
	b.set_process(false)
	fixture(b)
	var board_hash: String = visual.digest(main.logic)
	var dimensions := Vector2i(main.logic.cols,main.logic.rows)
	var clock: float = main.time_left
	var score: int = main.score
	var rng_state: int = main.rng.state
	var positions: Array[Vector2i] = [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0)]
	var kinds: Array[int] = [0,1,2]
	for profile in ["classic","classic_run"]:
		b.visual_profile = profile
		b.clear_fx()
		b._shake = 0
		b.play_knock(Vector2i(2,2),positions,kinds,28,4,true)
		b.play_wave(Vector2i(2,2),3,true)
		b.play_burst(Vector2i(2,2),90,true)
		b.play_confetti(90)
		b.flash(Color.WHITE,.4)
		b.shake(.3)
		b.play_thaw(positions)
		b.play_blast(Vector2i(4,2))
		b.play_clear_wave()
		b.praise("Perfect",Vector2i(2,2),Color("#f2deb0"),1.2)
		b.glow()
		if profile == "classic":
			check(b._flyers.size() == 3, "Classic whole-gem flyers retained")
			check(b._confetti.size() == 90, "legacy paper effect retained")
			check(is_equal_approx(b._flash,.3) and is_equal_approx(b._shake,.35), "Classic impact strengths retained")
			check(b._waves[0].rainbow, "Classic colourful special waves retained")
		else:
			check(b._flyers.is_empty() and b._confetti.is_empty(), "new renderer uses jewel fragments only")
			check(b._flash <= .12 and b._shake <= .12, "board stays readable during impact")
			check(not b._waves[0].rainbow, "new waves use stable palette")
		b._process(.1)
		b.queue_redraw()
		b._fx.queue_redraw()
		await main.get_tree().process_frame
		await main.get_tree().process_frame
		check(visual.digest(main.logic) == board_hash, "drawing all states does not mutate gems: " + profile)
		check(Vector2i(main.logic.cols,main.logic.rows) == dimensions, "drawing preserves board dimensions")
		check(main.time_left == clock and main.score == score, "effects do not modify score or time")
		check(main.rng.state == rng_state, "effects do not consume gameplay RNG")
	b.clear_fx()
	for i in 30:
		b.play_knock(Vector2i(2,2),positions,kinds,28,4,true)
		b.play_wave(Vector2i(2,2),3,true)
		b.play_burst(Vector2i(2,2),90)
		b.play_confetti(90)
		b.praise("Perfect",Vector2i(2,2),Color.WHITE)
	b._process(.1)
	check(b._sparks.size() <= 120 and b._shards.size() <= 96 and b._waves.size() <= 6, "extreme burst keeps bounded decorative density")
	check(b._texts.size() <= 8 and b._praise.size() <= 2, "overlapping decorative labels bounded")
	for i in 80:
		b._process(.1)
	check(b._sparks.is_empty() and b._shards.is_empty() and b._waves.is_empty() and b._beams.is_empty(), "transient effects fully expire")
	check(visual.digest(main.logic) == board_hash and main.rng.state == rng_state, "stress and expiry preserve game state")
	main.go_menu()
	for path in hashes:
		check(hashes[path] == (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""), "stored progress and records unchanged: " + path)
	return {"checks":checks,"failed":failures.size(),"failures":failures,"long_combos":observations}
