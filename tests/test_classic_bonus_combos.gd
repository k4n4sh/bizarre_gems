extends RefCounted
## Run via run_runtime_suite.gd in an isolated fixture (see the .ps1 runner).

const A := Vector2i(3, 3)
const B := Vector2i(4, 3)
var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func keeper() -> ScoreKeeper:
	var k := ScoreKeeper.new()
	k.classic_bonus_combos = true
	k.configure_time_rewards(true)
	k.combo_window = ScoreKeeper.CLASSIC_COMBO_WINDOW
	k.timed_special = true
	return k


func hit(k: ScoreKeeper, n: int, now: float, color := 0, slot := A, shining := 0) -> Dictionary:
	var colors: Array[int] = []
	colors.resize(n)
	colors.fill(color)
	return k.hit(n, now, shining, slot, colors)


func rules() -> void:
	for sequence in [[A,A], [A,A,A,A,A,A], [A,B,B], [A,A,B,B], [A,B,A]]:
		var k := keeper()
		var pending := Vector2i(-1, -1)
		for i in sequence.size():
			var r := hit(k, 2, float(i), i % 2, sequence[i])
			var earns: bool = sequence[i] == pending
			check(r.double_hit_points == (roundi(r.ordinary_points * 0.5) if earns else 0),
				"position sequence %s hit %d" % [sequence, i])
			pending = Vector2i(-1, -1) if earns else sequence[i]
	for reset_kind in ["miss", "timeout", "late_hit", "reset"]:
		var k := keeper()
		hit(k, 4, 0.0)
		match reset_kind:
			"miss": k.miss()
			"timeout": k.update(3.5001)
			"reset": k.reset()
		var r := hit(k, 2, 3.5001 if reset_kind in ["timeout", "late_hit"] else 1.0)
		check(r.double_hit_points == 0 and r.color_streak_points == 0 and k.color_streak_kind == -1
			and k.color_streak_hits == 0 and k._previous_color_points.size() == 1,
			reset_kind + " starts both cycles fresh")
	var k := keeper()
	hit(k, 2, 0.0)
	check(hit(k, 2, 3.5).double_hit_points == 2, "exact 3.5 boundary remains inclusive")
	k = keeper()
	hit(k, 2, 0.0, 0, B)
	k.transpose_bonus_slot()
	check(hit(k, 2, 1.0, 1, Vector2i(B.y, B.x)).double_hit_points == 2, "logical slot follows transpose")
	k = keeper()
	hit(k, 2, 0.0)
	k.hit(2, 1.0, 0, A, [])
	check(hit(k, 2, 2.0).double_hit_points == 0, "no removed gems cannot prime a double hit")
	color_rules()
	k = keeper()
	hit(k, 3, 0.0, 0, B)
	hit(k, 2, 3.0, 0, A)
	k.update(5.5)
	check(k.precise_streak == 0 and k.combo == 2 and k.color_streak_hits == 2,
		"special timeout leaves both new combos alive")
	var r := hit(k, 2, 5.5)
	check(r.double_hit_points == 2 and r.color_streak_points == 4, "bonuses after independent special timeout")
	# Compare every existing reward and timer to a keeper with bonuses disabled.
	k = keeper()
	var control := keeper()
	control.classic_bonus_combos = false
	for i in 30:
		var n := 3 if i % 5 != 4 else 2
		r = hit(k, n, float(i), 0, A, 2)
		var old := hit(control, n, float(i), 0, A, 2)
		check(r.time == old.time and r.event == old.event and r.mult == old.mult
			and k.combo == control.combo and k.precise_streak == control.precise_streak
			and k.special_window_left(i) == control.special_window_left(i), "existing rewards and clocks hit %d" % i)
		check(r.points - r.double_hit_points - r.color_streak_points == old.points,
			"ordinary + special + shine credited once hit %d" % i)
		check(old.double_hit_points == 0 and old.color_streak_points == 0 and control.color_streak_kind == -1,
			"non-Classic opt-out hit %d" % i)
	check(k.combo_window == 3.5 and ScoreKeeper.SPECIAL_WINDOW == 5.0 and k.precise_events == control.precise_events
		and k.perfect_events == control.perfect_events, "unchanged boundaries and event counts")
	k = keeper()
	for i in 3:
		hit(k, 2, i, 1, Vector2i(i, 0))
	hit(k, 2, 3.0, 0)
	r = hit(k, 4, 4.0, 0)
	check(r.mult == 3 and r.ordinary_points == 18 and r.double_hit_points == 9
		and r.color_streak_points == 22 and r.points == 49, "activation adds first x2 share and current x3 share, plus Double Hit")
	k = keeper()
	for i in 4:
		hit(k, 2, i, i % 2, Vector2i(i, 0))
	hit(k, 5, 4.0, 0, B)
	r = hit(k, 5, 5.0, 1, B)
	check(r.ordinary_points == 21 and r.double_hit_points == 11, "positive half-point rounds up once")


func color_rules() -> void:
	for sequence in [[2,2], [3,2], [4,3], [3,3], [4,2], [4,4], [2,2,2,2,2,2], [6,2], [8,2]]:
		var k := keeper()
		var first := 0
		for i in sequence.size():
			var r := hit(k, sequence[i], float(i), 0, Vector2i(i, 0))
			var expected: int = 0 if i == 0 else (first + int(r.ordinary_points) if i == 1 else int(r.ordinary_points))
			check(r.color_streak_points == expected and r.color_streak_started == (i == 1),
				"color chain %s strike %d: activation/continuation reward" % [sequence, i])
			check(k.color_streak_hits == (0 if i == 0 else i + 1)
				and k.color_streak_kind == (-1 if i == 0 else 0), "only an active chain has a count and color")
			first = int(r.ordinary_points) if i == 0 else first
	var k := keeper()
	var ordinary := 0
	var bonus := 0
	for i in 40:
		var r := hit(k, 2, float(i), 0, Vector2i(i, 0))
		ordinary += int(r.ordinary_points)
		bonus += int(r.color_streak_points)
		if i > 0:
			check(bonus == ordinary, "unbounded linear chain never repays previous strikes " + str(i))
	check(k.color_streak_hits == 40, "no artificial chain length cap")
	k = keeper()
	hit(k, 2, 0.0, 0, A)
	check(hit(k, 2, 1.0, 1, B).color_streak_points == 0 and k.color_streak_kind == -1,
		"different colors do not activate")
	check(hit(k, 4, 2.0, 1, A).color_streak_points == 16 and k.color_streak_kind == 1,
		"new blue pair activates from the immediately preceding strike")
	check(hit(k, 4, 3.0, 0, B).color_streak_points == 0 and k.color_streak_hits == 0,
		"color change ends the chain and only primes a new one")
	check(hit(k, 2, 4.0, 0, A).color_streak_points == 18 and k.color_streak_hits == 2,
		"activation uses the previous x2 and current x3 multiplier once")
	# Switching through mixed strikes pays each color portion once, never the whole mixed score.
	k = keeper()
	hit(k, 2, 0.0, 0, A)
	check(hit(k, 2, 1.0, 0, B).color_streak_points == 6, "2 + 2 activation pays 2 + 4")
	var mixed: Array[int] = [0,0,1,1]
	var r := k.hit(4, 2.0, 0, A, mixed)
	check(r.color_streak_points == 6 and not r.color_streak_started and k.color_streak_hits == 3,
		"active red takes its half of a mixed strike")
	check(not k._previous_color_points.has(0) and k._previous_color_points[1] == 6.0,
		"only unpaid blue portion is available for a switch")
	r = hit(k, 2, 3.0, 1, B)
	check(r.color_streak_points == 10 and r.color_streak_started and k.color_streak_kind == 1
		and k.color_streak_hits == 2, "red -> red/blue -> blue pays 6 + 4 blue points")
	r = k.hit(4, 4.0, 0, A, mixed)
	check(r.color_streak_points == 9 and not r.color_streak_started and k.color_streak_kind == 1,
		"active blue remains preferred when red also participates")
	check(hit(k, 2, 5.0, 0, B).color_streak_points == 15 and k.color_streak_kind == 0,
		"switching back uses the latest unpaid red share, not an older paid share")
	# A singleton cannot participate, even when it is the formerly active color.
	k = keeper()
	var red_with_single_blue: Array[int] = [0,0,0,1]
	k.hit(4, 0.0, 0, A, red_with_single_blue)
	check(not k._previous_color_points.has(1), "single blue gem does not prime a chain")
	check(hit(k, 2, 1.0, 1, B).color_streak_points == 0, "blue pair cannot match previous blue singleton")
	k = keeper()
	hit(k, 2, 0.0, 0, A)
	hit(k, 2, 1.0, 0, B)
	var one_red: Array[int] = [0,1,1]
	r = k.hit(3, 2.0, 0, A, one_red)
	check(r.color_streak_points == 0 and k.color_streak_kind == -1 and not k._previous_color_points.has(0),
		"a singleton ends active red and cannot prime another red chain")
	check(hit(k, 2, 3.0, 0, B).color_streak_points == 0, "paid/singleton red cannot be reimbursed after interruption")
	check(hit(k, 2, 4.0, 0, A).color_streak_points == 10, "fresh red activation has no older rewards")
	# Stable selection is independent of discovery order and uses unrounded shares.
	for colors in [[1,1,0,0], [0,0,1,1]]:
		k = keeper()
		var typed: Array[int] = []
		typed.assign(colors)
		k.hit(4, 0.0, 0, A, typed)
		r = k.hit(4, 1.0, 0, B, typed)
		check(r.color_streak_points == 9 and k.color_streak_kind == 0, "equal candidates prefer lowest color id")
	k = keeper()
	var uneven: Array[int] = [0,0,1,1,1]
	k.hit(5, 0.0, 0, A, uneven)
	r = k.hit(5, 1.0, 0, B, uneven)
	check(k.color_streak_kind == 1 and r.color_streak_points == 13,
		"best candidate: 4.2 + 8.4 rounds once to 13, not 4 + 8")
	var more_red: Array[int] = [0,0,0,0,1,1]
	r = k.hit(6, 2.0, 0, A, more_red)
	check(k.color_streak_kind == 1 and r.color_streak_points == 5 and not r.color_streak_started,
		"active color has priority over a more lucrative new candidate")
	check(hit(k, 2, 3.0, 0, B).color_streak_points == 15, "fractional previous share survives until switch rounding")
	k = keeper()
	hit(k, 2, 0.0, 0, A)
	r = k.hit(4, 1.0, 0, B, [0,0,1])
	check(r.color_streak_points == 10, "shares divide by actual removals, not matched/cracked gem count")
	for reason in ["miss", "timeout", "late_hit", "reset"]:
		k = keeper()
		hit(k, 2, 0.0, 0, A)
		k.hit(4, 1.0, 0, B, mixed)
		match reason:
			"miss": k.miss()
			"timeout": k.update(4.5001)
			"reset": k.reset()
		r = hit(k, 2, 4.5001 if reason in ["timeout", "late_hit"] else 2.0, 1, A)
		check(r.color_streak_points == 0 and k.color_streak_hits == 0,
			reason + " clears both active chain and unpaid mixed components")


func fixture(main, colors: Array[int], slot := A) -> void:
	var cells := PackedInt32Array()
	cells.resize(49)
	cells.fill(BoardLogic.EMPTY)
	for i in colors.size():
		var at: Vector2i = slot + BoardLogic.DIRS[i]
		cells[at.y * 7 + at.x] = colors[i]
	# Another move prevents end-game side effects during a scenario.
	cells[42] = 3
	cells[44] = 3
	main.logic.load_cells(7, 7, cells)
	main.board.refresh()
	main.dealing = false
	main.play_time += 0.1


func runtime(main) -> void:
	await main.start_game("classic")
	check(main.keeper.classic_bonus_combos, "ordinary Classic enables bonuses")
	# Six real consecutive removals from one unmodified logical cell.
	var cells := PackedInt32Array()
	cells.resize(91)
	cells.fill(-1)
	for distance in range(1, 7):
		cells[3 * 13 + 6 - distance] = 0
		cells[3 * 13 + 6 + distance] = 0
	cells[78] = 8
	cells[80] = 8
	main.logic.load_cells(13, 7, cells)
	main.board.refresh()
	main.dealing = false
	for i in 6:
		main.play_time += 0.1
		main._on_slot(Vector2i(6, 3))
	check(main.score == 59 and main.keeper.score == 59 and main.cleared == 12
		and main.keeper.color_streak_hits == 6,
		"six real pairs: three unchanged double hits and one continuous color chain")
	check(main.keeper.combo == 6 and main.time_left == 122.0, "six pairs keep exact original tier time")
	var widgets: Dictionary = main.hud_sets.classic.bonus
	check(main.board._texts[-1].double and main.board._texts[-1].chain == 0
		and main.board._texts[-1].rows.size() == 3,
		"simultaneous bonuses share one field popup with separate awarded values")
	var earned: int = main.score
	# No available matching rays from this empty slot: the ordinary miss path.
	main._on_slot(Vector2i(12, 0))
	check(main.score == earned and main.keeper.color_streak_kind == -1 and main.keeper._double_hit_slot.x == -1,
		"real miss resets both without bonus points")
	fixture(main, [0,0,0,0])
	main._on_slot(A)
	fixture(main, [0,0,1,1], B)
	main._on_slot(B)
	check(main.keeper.color_streak_hits == 2 and main.keeper.color_streak_kind == 0,
		"real mixed cross activates color from its proportional share")
	var before_switch: int = main.score
	fixture(main, [1,1], B)
	main._on_slot(B)
	check(main.keeper.color_streak_kind == 1 and main.keeper.color_streak_hits == 2
		and main.score - before_switch == 16,
		"real mixed -> blue transition: base 4 + Double Hit 2 + unpaid blue 6 + 4")
	fixture(main, [1,1])
	main._on_slot(A)
	main.play_time += 3.5001
	main._process(0.0)
	check(main.keeper.color_streak_kind == -1 and main.keeper._previous_color_points.is_empty()
		and not widgets.progress.get_meta("hud_active"),
		"frame timeout clears the chain and unpaid previous portions")
	fixture(main, [0,0])
	main._on_slot(A)
	await main.start_game("classic")
	check(main.keeper.color_streak_kind == -1 and main.keeper._double_hit_slot.x == -1 and main.score == 0,
		"restart clears state and score")
	fixture(main, [0,0])
	main._on_slot(A)
	main.end_game("time")
	check(main.keeper.color_streak_kind == -1 and main.keeper._double_hit_slot.x == -1, "finish clears new states")
	main._resume_play()
	fixture(main, [0,0])
	main._on_slot(A)
	check(main.keeper.color_streak_hits == 0 and main.keeper.color_streak_kind == -1
		and main.keeper._previous_color_points.has(0), "continue primes a new chain without an immediate bonus")
	main.go_menu()
	check(main.keeper.color_streak_kind == -1 and main.keeper._double_hit_slot.x == -1, "exit clears states")
	for config in [["bright",false], ["bright",true], ["levels",false], ["zen",false],
			["puzzle",false], ["classic",true], ["classic",false]]:
		# Tutorial now validates its own real fixtures in test_tutorial.gd.
		await main.start_game(config[0], config[1])
		var active: bool = config == ["classic",false] or config[0] == "bright"
		check(main.keeper.classic_bonus_combos == active, "mode eligibility " + str(config))
		main.tut_step = 3
		for i in 2:
			fixture(main, [0,0,0])
			main._on_slot(A)
		check(main.score == (28 if active else 12), "mode score isolation " + str(config))
		main.go_menu()


func layouts(main) -> void:
	var tree: SceneTree = main.get_tree()
	for config in [[Vector2i(1280,720),false], [Vector2i(480,1008),false],
			[Vector2i(853,480),true], [Vector2i(1066,480),true]]:
		var vp := SubViewport.new()
		vp.size = config[0]
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		tree.root.add_child(vp)
		var sample = load("res://tests/classic_android_fixture.gd").new() if config[1] else load("res://scenes/main.tscn").instantiate()
		if config[1]:
			sample.test_insets = Rect2(24, 8, 12, 16)
		vp.add_child(sample)
		sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sample.set_process(false)
		await sample.start_game("classic")
		for i in 12:
			await tree.process_frame
		var widgets: Dictionary = sample.hud_sets["classic_android" if config[1] else "classic"].bonus
		sample.keeper.reset()
		hit(sample.keeper, 2, 0.0)
		sample._update_bonus_progress()
		check(not widgets.progress.get_meta("hud_active") and widgets.count.text == "0", "pending strike leaves a neutral counter")
		hit(sample.keeper, 2, 1.0)
		sample._update_bonus_progress()
		hit(sample.keeper, 2, 2.0)
		sample._update_bonus_progress()
		check(widgets.count.text == "3", "chain length is not a score multiplier")
		hit(sample.keeper, 2, 3.0, 1, B)
		sample._update_bonus_progress()
		check(not widgets.progress.get_meta("hud_active") and widgets.count.text == "0", "broken chain returns to neutral")
		hit(sample.keeper, 2, 4.0, 1, B)
		sample._update_bonus_progress()
		check(widgets.gem.texture == BoardView.GEM_TEX[1], "indicator switches to new active color")
		for language in ["ru", "en", "tr"]:
			main.get_node("/root/L").set_language(language)
			sample._update_bonus_progress()
			for i in 4:
				await tree.process_frame
			check(widgets.count.text == "2" and widgets.caption.text == main.get_node("/root/L").t("color_streak_chain"),
				"localized chain caption with unambiguous length " + language)
			for control in [widgets.progress, widgets.gem, widgets.count]:
				check(Rect2(Vector2.ZERO, Vector2(vp.size)).encloses(control.get_global_rect())
					and not sample.board.get_global_rect().intersects(control.get_global_rect()),
					"bonus HUD stays outside board %s %s" % [config, language])
		# Desktop clicks at different pixels of the same slot.
		sample.keeper.reset()
		sample.board.zoom_enabled = false
		for i in 2:
			fixture(sample, [0,0])
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = sample.board.slot_center(A) + Vector2(i, -i)
			mouse.pressed = true
			sample.board._gui_input(mouse)
		check(sample.score == 14 and sample.keeper.combo == 2, "two mouse clicks: unchanged Double Hit plus new color activation " + str(config))
		# Exercise the existing touch -> emulated mouse path, including a zoomed/panned board.
		sample.keeper.reset()
		sample.board.zoom_enabled = true
		for i in 2:
			fixture(sample, [0,0])
			sample.board.zoom = 1.5 if i == 1 else 1.0
			sample.board.pan = Vector2(10,-8) if i == 1 else Vector2.ZERO
			sample.board._relayout()
			var pos: Vector2 = sample.board.slot_center(A) + Vector2(i, -i)
			check(sample.board.slot_at(pos) == A, "pixel jitter, resize, zoom keep logical coordinates")
			var touch := InputEventScreenTouch.new()
			touch.position = pos
			touch.pressed = true
			sample.board._gui_input(touch)
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = pos
			mouse.pressed = true
			sample.board._gui_input(mouse)
			touch.pressed = false
			sample.board._gui_input(touch)
			mouse.pressed = false
			sample.board._gui_input(mouse)
		check(sample.score == 14 and sample.keeper.combo == 2, "two synthetic touch taps: unchanged Double Hit plus color activation " + str(config))
		sample.go_menu()
		vp.queue_free()
		await tree.process_frame
	main.get_node("/root/L").set_language("ru")


func run_suite(main) -> Dictionary:
	if not main.get_node("/root/Save").PATH.begins_with("res://.test-user/") \
			or not main.get_node("/root/Progress").PATH.begins_with("res://.test-user/"):
		return {"error": "Run the isolated tests/test_classic_bonus_combos.ps1 fixture."}
	rules()
	await runtime(main)
	await layouts(main)
	return {"checks": checks, "failed": failures.size(), "failures": failures}
