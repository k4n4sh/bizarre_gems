extends RefCounted
## Stage 2 fixtures against the actual upstream main scene, with isolated autoloads.
## Refinement HUD/layout/experiment checks are ported in stages 6/8; Run economy: test_run_flow.gd.

const A := Vector2i(3, 3)
const B := Vector2i(4, 3)
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func settle(main, frames := 8) -> void:
	for i in frames:
		await main.get_tree().process_frame

func start(main, id := "classic", daily := false, challenge := {}) -> void:
	await main.start_game(id, daily, challenge)
	await settle(main)
	check(main.state == main.State.PLAYING, "mode starts: " + id + " daily=" + str(daily))

func fixture(main, colors: Array[int], slot := A, shining := 0) -> void:
	var cells := PackedInt32Array()
	cells.resize(49)
	cells.fill(BoardLogic.EMPTY)
	for i in colors.size():
		var at: Vector2i = slot + BoardLogic.DIRS[i]
		cells[at.y * 7 + at.x] = colors[i]
	cells[42] = 5
	cells[44] = 5  # An independent legal move avoids completion rewards.
	main.logic.load_cells(7, 7, cells)
	for i in colors.size():
		var at: Vector2i = slot + BoardLogic.DIRS[i]
		main.logic.shine[at.y * 7 + at.x] = 1 if i < shining else 0
	main.board.clear_fx()
	main.board.refresh()
	main.play_time += 0.1
	main.dealing = false

func receipt(main) -> Dictionary:
	return main.board._texts[-1].rewards

func snapshot(main) -> Dictionary:
	var k: ScoreKeeper = main.keeper
	return {"clock": main.play_time, "combo": k.combo, "special": k.precise_streak,
		"ordinary_left": k.window_left(main.play_time), "special_left": k.special_window_left(main.play_time),
		"color": k.color_streak_kind, "length": k.color_streak_hits,
		"unpaid": k._previous_color_points.duplicate(), "slot": k._double_hit_slot}

func configuration(main) -> void:
	for config in [["classic", false], ["bright", false], ["bright", true], ["levels", false],
			["zen", false], ["puzzle", false], ["tutorial", false], ["classic", true], ["classic", false]]:
		await start(main, config[0], config[1])
		# Stage 7 practice begins with the pinned Classic lesson and uses modern rules.
		var classic: bool = (config[0] == "classic" and not config[1]) or config[0] == "tutorial"
		var run: bool = config[0] == "bright"
		check(main.keeper.combo_window == (3.5 if classic or run else 3.0), str(config) + ": ordinary window")
		check(main.keeper.timed_special == (classic or run) and main.keeper.classic_bonus_combos == (classic or run),
			str(config) + ": rule opt-in independent of skin")
		check(main.keeper.tier_time == (1.0 if classic else 2.0) and main.keeper.streak_time == (1.0 if classic else 3.0),
			str(config) + ": modern/legacy time selection")
		check(main.keeper.time_bonuses == (config[0] in ["classic","tutorial"]) and main.keeper.hit_time_rewards == not run,
			str(config) + ": hit time eligibility")
		main.go_menu()

func balance(main) -> void:
	var source = load("res://tests/test_classic_balance.gd").new()
	await start(main)
	for hit in range(1, 31):
		var before: float = main.time_left
		source._fixture(main, 2)
		check(main.time_left - before == (1.0 if hit in [2, 5, 9, 10, 20, 30] else 0.0), "real pair %d: exact reward seconds" % hit)
		check(main.keeper.combo == hit and main.score == main.keeper.score, "real pair %d: uninterrupted combo and score" % hit)
	main.go_menu()
	await start(main)
	var times := [1.0, 1.0, 1.0, 0.0, 5.0, 6.0]
	var counts := [1, 1, 2, 2, 3, 0]
	var sizes := [3, 2, 3, 2, 3, 3]
	for i in sizes.size():
		var before: float = main.time_left
		source._fixture(main, sizes[i])
		check(main.time_left - before == times[i] and main.keeper.precise_streak == counts[i], "real special cycle hit %d" % i)
	check(main.keeper.precise_events == 1 and main.keeper.perfect_events == 1 and main.keeper.special_bonus_time == 8.0,
		"Precise/Perfect rewards credited once")
	main.go_menu()
	for event in ["precise", "perfect"]:
		await start(main)
		for hit in range(1, 10):
			source._fixture(main, 3 if hit >= (8 if event == "precise" else 7) else 2)
		var before_time: float = main.time_left
		var before_score: int = main.score
		var sfx = main.get_node("/root/Sfx")
		for player in sfx._pool:
			player.stream = null
		var save = main.get_node("/root/Save")
		save.sound = true  # Dummy audio driver: streams are assigned but nothing is heard
		source._fixture(main, 4, 2)
		save.sound = false
		check(sfx._pool.filter(func(player): return player.stream == sfx.SOUNDS[event]).size() == 1, "Classic plays one %s sound" % event)
		for player in sfx._pool:
			player.stop()
			player.stream = null
		check(main.time_left - before_time == (10.0 if event == "precise" else 12.0), "tenth hit: base/special/streak/shine seconds " + event)
		var hot_points := ScoreKeeper.hot_bonus(main.keeper.hot)  # the hot streak comes on top of these rules
		check(main.score - before_score - hot_points == (56 if event == "precise" else 78), "tenth hit: exact combined score " + event)
		check(main.keeper.precise_events == 1 and main.keeper.perfect_events == (0 if event == "precise" else 1), "no duplicate special event " + event)
		main.go_menu()

func bonuses(main) -> void:
	await start(main)
	# Six successive real pairs at the same slot, without replacing this field between hits.
	var cells := PackedInt32Array()
	cells.resize(91)
	cells.fill(BoardLogic.EMPTY)
	for distance in range(1, 7):
		cells[3 * 13 + 6 - distance] = 0
		cells[3 * 13 + 6 + distance] = 0
	cells[78] = 8
	cells[80] = 8
	main.logic.load_cells(13, 7, cells)
	main.board.refresh()
	for i in 6:
		main.play_time += 0.1
		main._on_slot(Vector2i(6, 3))
	var hot_total := 0  # the hot streak comes on top of these rules
	for h in range(1, 7):
		hot_total += ScoreKeeper.hot_bonus(h)
	check(main.score - hot_total == 59 and main.keeper.score - hot_total == 59 and main.cleared == 12 and main.keeper.color_streak_hits == 6,
		"six real pairs: three Double Hits and continuous Color Chain, exact score 59")
	check(main.time_left == 122.0 and main.keeper.combo == 6, "six pairs: two tier seconds")
	check(receipt(main).double_hit_points == 3 and receipt(main).color_streak_points == 6,
		"view receives the keeper's simultaneous bonus values")
	main._on_slot(Vector2i(12, 0))
	check(main.keeper.color_streak_kind == -1 and main.keeper._double_hit_slot.x == -1, "real miss clears both bonus states")
	fixture(main, [0, 0, 0, 0])
	main._on_slot(A)
	fixture(main, [0, 0, 1, 1], B)
	main._on_slot(B)
	check(main.keeper.color_streak_kind == 0 and main.keeper.color_streak_hits == 2, "real mixed cross activates only the eligible color share")
	fixture(main, [1, 1], B)
	var before: int = main.score
	main._on_slot(B)
	check(main.score - before == 16 and receipt(main).double_hit_points == 2 and receipt(main).color_streak_points == 10,
		"real mixed -> blue: base 4 + Double Hit 2 + unpaid blue 6+4")
	fixture(main, [1, 1])
	main._on_slot(A)
	main.play_time += 3.5001
	main._process(0.0)
	check(main.keeper.color_streak_kind == -1 and main.keeper._previous_color_points.is_empty() and main.keeper._double_hit_slot.x == -1,
		"frame timeout clears color shares and position")
	main.go_menu()

func removals_and_jokers(main) -> void:
	for id in ["classic", "bright"]:
		await start(main, id)
		fixture(main, [0, 0])
		main._on_slot(A)
		fixture(main, [0, 0], B)
		main.logic.hp[(B.y * 7 + B.x) + 1] = 2
		var before: int = main.cleared
		main._on_slot(B)
		check(main.cleared - before == 1 and receipt(main).color_streak_points == 0 and main.keeper.color_streak_kind == -1,
			id + ": one removed gem + box damage cannot activate a color pair")
		fixture(main, [0, 0])
		main.logic.hp[A.y * 7 + A.x - 1] = 2
		main.logic.hp[A.y * 7 + A.x + 1] = 2
		main._on_slot(A)
		check(receipt(main).double_hit_points == 0 and receipt(main).color_streak_points == 0
			and main.keeper._double_hit_slot.x == -1 and main.keeper._previous_color_points.is_empty(), id + ": no removal clears bonus progress")
		fixture(main, [0, 0])
		main._on_slot(A)
		check(receipt(main).double_hit_points == 0 and receipt(main).color_streak_points == 0, id + ": box damage cannot prime later bonuses")
		main.go_menu()
	await start(main)
	fixture(main, [0, 0])
	var direct_index := A.y * 7 + A.x + 1
	main.logic.cells[0] = 1
	main.logic.chain[direct_index] = 0
	main.logic.chain[0] = direct_index
	var before: int = main.cleared
	main._on_slot(A)
	check(main.cleared - before == 3 and main.keeper._previous_color_points[0] == 4.0 * 2.0 / 3.0,
		"linked outside gem contributes its actual color and denominator once")
	fixture(main, [0, 0], B)
	main._on_slot(B)
	check(receipt(main).color_streak_points == 7, "linked mixed share rounds once: 8/3 + 4 -> 7")
	main.go_menu()
	await start(main, "bright")
	fixture(main, [0, 99])
	check(main.logic.joker_match_kind(A) == 0, "Run joker adopts the direct match color before removal")
	main._on_slot(A)
	fixture(main, [0, 99], B)
	main._on_slot(B)
	check(main.keeper.color_streak_kind == 0 and main.keeper.color_streak_hits == 2 and receipt(main).color_streak_points == 6,
		"joker participates in a real color chain")
	check(main.best_strike.parts.any(func(part): return part[1] == 99), "replay retains the stored joker kind")
	fixture(main, [1, 0, 99, 99])
	check(main.logic.joker_match_kind(A) == 1 and main.logic.matches_from(A).size() == 3, "joker tie follows ray order")
	main._on_slot(A)
	check(main.keeper._previous_color_points.has(1) and not main.keeper._previous_color_points.has(99), "effective color stays separate from stored kind")
	fixture(main, [99, 99], B)
	main._on_slot(B)
	check(main.keeper.color_streak_kind == -1 and main.keeper._previous_color_points.is_empty(), "joker-only strike is colorless")
	main.go_menu()

func shared_runtime(main) -> void:
	for daily in [false, true]:
		await start(main, "bright", daily)
		for i in 8:
			fixture(main, [0, 0, 0], A, 2)
			main._on_slot(A)
		check(main.keeper.precise_events == 2 and main.keeper.perfect_events == 2 and main.keeper.precise_streak == 0,
			"Run/Daily: two complete special cycles " + str(daily))
		for i in 2:
			fixture(main, [0, 0])
			main._on_slot(A)
		check(main.time_left == 120.0 and main.keeper.special_bonus_time == 0 and main.keeper.combo == 10,
			"Run/Daily: no group, shine, special, tier or tenth-hit seconds " + str(daily))
		main.go_menu()

func pause_and_transpose(main) -> void:
	await start(main)
	fixture(main, [0, 0, 0])
	main._on_slot(A)
	fixture(main, [0, 0], B)
	main._on_slot(B)
	var before := snapshot(main)
	main.pause_game()
	main._process(60.0)
	check(snapshot(main) == before, "pause freezes ordinary/special and bonus states")
	main._resume_play()
	check(snapshot(main) == before, "resume preserves both clocks")
	# Drive the actual relayout path into exactly one transpose, then hit its logical slot.
	main.challenge = {"mode": "classic", "seed": 42, "dims": Vector2i(5, 7), "score": 100}
	var cells := PackedInt32Array()
	cells.resize(35)
	cells.fill(-1)
	cells[6] = 1
	cells[16] = 1
	cells[30] = 2
	cells[32] = 2
	main.logic.load_cells(5, 7, cells)
	# A synthetic canonical shape drives the real transpose branch deterministically.
	main.mode = main.mode.duplicate()
	main.mode.cols = 7
	main.mode.rows = 5
	var k: ScoreKeeper = main.keeper
	k.miss()
	k.hit(2, main.play_time, 0, Vector2i(1, 2), [0, 0])
	main.score = main.keeper.score
	main._relayout_board()
	check(Vector2i(main.logic.cols, main.logic.rows) == Vector2i(7, 5) and main.keeper._double_hit_slot == Vector2i(2, 1),
		"actual board relayout transposes pending logical slot")
	main._on_slot(Vector2i(2, 1))
	check(receipt(main).double_hit_points == 2, "same logical slot still earns Double Hit after transpose")
	main.go_menu()

func finite_classic(main) -> void:
	for partial in [false, true]:
		await start(main)
		main.logic.load_cells(3, 3, PackedInt32Array([1, -1, 1, -1, -1, -1, 2 if partial else -1, -1, 3 if partial else -1]))
		main.board.refresh()
		main._on_slot(Vector2i(1, 0))
		check(main.state == main.State.OVER and main.end_reason == "stuck" and main.wave == 1 and not main.dealing,
			"Classic ends on its sole field, partial=" + str(partial))
		check(main.cleared == 2 and main.logic.gems_left() == (2 if partial else 0), "Classic completion preserves actual removals")
		check(main.keeper._double_hit_slot.x == -1 and main.keeper.color_streak_kind == -1, "Classic finish clears positional/color states")
		main.go_menu()
	await start(main)
	main.logic.load_cells(3, 1, PackedInt32Array([1, -1, 2]))
	main._check_no_moves()
	check(main.state == main.State.OVER and main.wave == 1, "no-move check ends Classic without a strike")
	var frozen_cells: PackedInt32Array = main.logic.cells.duplicate()
	main.state = main.State.PLAYING
	main._next_wave(Vector2i(1, 0))
	check(main.wave == 1 and main.logic.cells == frozen_cells and not main.dealing, "Classic cannot enter the next-field method")
	main.go_menu()
	var ch: Dictionary = main.parse_challenge("c1-classic-42-23-15-100")
	await start(main, "classic", false, ch)
	var canonical: PackedInt32Array = main.logic.cells.duplicate()
	main.go_menu()
	await start(main, "classic", false, ch)
	check(main.logic.cells == canonical and main.challenge.score == 100 and not main.mode.waves
		and main.keeper.timed_special and main.keeper.classic_bonus_combos, "seeded Classic Challenge retains target/deal and approved rules")
	main.go_menu()

func run_contract(main) -> void:
	var tree: SceneTree = main.get_tree()
	await start(main, "bright")
	fixture(main, [0, 0, 0])
	main._on_slot(A)
	fixture(main, [0, 0], B)
	main._on_slot(B)
	var before := snapshot(main)
	before.slot = Vector2i(-1, -1)
	main._next_wave(A)
	check(snapshot(main) == before, "Run transition preserves non-positional states")
	var frozen_time: float = main.time_left
	main._process(60.0)
	check(main.time_left == frozen_time and snapshot(main) == before, "mandatory transition freezes all game clocks")
	var wave: int = main.wave
	main._next_wave(A)
	check(main.wave == wave and main.time_left == frozen_time, "duplicate transition cannot reward twice")
	Engine.time_scale = 20.0
	await tree.create_timer(1.4).timeout
	Engine.time_scale = 1.0
	check(not main.dealing and snapshot(main) == before, "real deal callback preserves combo clocks")
	fixture(main, [0, 0])
	main._on_slot(A)
	check(receipt(main).double_hit_points == 0 and main.keeper.color_streak_hits == 3,
		"new field continues Color Chain without positional payout")
	main._next_wave(A)
	await start(main)
	var replacement: PackedInt32Array = main.logic.cells.duplicate()
	Engine.time_scale = 20.0
	await tree.create_timer(1.4).timeout
	Engine.time_scale = 1.0
	check(main.mode.id == "classic" and main.logic.cells == replacement and main.keeper.combo == 0,
		"old Run deal callback cannot replace a new Classic game")
	main.go_menu()
	var ad = main.get_node("/root/Yandex")
	ad.set_script(load("res://tests/rewarded_ad_fixture.gd"))
	await start(main, "bright")
	fixture(main, [0, 0, 0])
	main._on_slot(A)
	fixture(main, [0, 0], B)
	main._on_slot(B)
	var keeper: ScoreKeeper = main.keeper
	main.time_left = 0.25
	var clock: float = main.play_time
	main._process(1.0)
	check(main.state == main.State.OVER and is_equal_approx(main.play_time, clock + 0.25), "Run time exhaustion clips elapsed clock")
	before = snapshot(main)
	main._process(60.0)
	check(snapshot(main) == before, "Run result screen freezes remaining clocks")
	main._on_continue()
	ad.resolve_reward(false)
	await settle(main)
	check(main.state == main.State.OVER and not main.used_continue and snapshot(main) == before, "failed reward preserves frozen states")
	main._on_continue()
	var callback: Callable = ad.pending_reward
	ad.resolve_reward(true)
	await settle(main)
	check(main.state == main.State.PLAYING and main.used_continue and main.time_left == 15.0
		and main.keeper == keeper and snapshot(main) == before, "reward continue preserves the same eligible keeper")
	callback.call_deferred(true)
	await settle(main)
	check(main.time_left == 15.0 and snapshot(main) == before, "duplicate rewarded callback does not reapply state")
	fixture(main, [0, 0], B)
	main._on_slot(B)
	check(receipt(main).double_hit_points == 2 and main.keeper.color_streak_hits == 3, "continued field retains valid pending Double Hit/Color Chain")
	main.go_menu()
	await start(main, "bright")
	fixture(main, [0, 0])
	main._on_slot(A)
	main.end_game("time")
	main._on_continue()
	await start(main)
	ad.resolve_reward(true)
	await settle(main)
	check(main.mode.id == "classic" and main.time_left == 120.0 and not main.used_continue and main.keeper.combo == 0,
		"stale rewarded callback cannot mutate a replacement game")
	main.go_menu()
	ad.set_script(load("res://scripts/yandex.gd"))

func run_suite(main) -> Dictionary:
	if not main.has_node("/root/TestIsolation"):
		return {"error": "Use the isolated test runner."}
	await configuration(main)
	await balance(main)
	await bonuses(main)
	await removals_and_jokers(main)
	await shared_runtime(main)
	await pause_and_transpose(main)
	await finite_classic(main)
	await run_contract(main)
	return {"checks": checks, "failed": failures.size(), "failures": failures}
