extends SceneTree
## Rule tests. Run:  godot --headless --path . --script res://tests/test_logic.gd

var failed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)


func board_from(rows: Array[String]) -> BoardLogic:
	# '.' is an empty slot, digits are gem kinds
	var b := BoardLogic.new()
	var cells := PackedInt32Array()
	for r in rows:
		for ch in r:
			cells.append(-1 if ch == "." else int(ch))
	b.load_cells(rows[0].length(), rows.size(), cells)
	return b


func _init() -> void:
	print("BoardLogic")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var b := BoardLogic.new()
	b.setup(BoardLogic.LONG, BoardLogic.SHORT, rng)
	var counts := {}
	for k in b.cells:
		counts[k] = counts.get(k, 0) + 1
	check(b.cells.size() == 345, "board has 23x15 slots")
	check(counts.get(-1, 0) == 75, "75 empty slots")
	var all27 := true
	for k in BoardLogic.KINDS:
		all27 = all27 and counts.get(k, 0) == 27
	check(all27, "each of 10 kinds appears 27 times")

	# pair on a row, gap skipping
	var t := board_from(["1..1", "....", "2..3"])
	var m := t.matches_from(Vector2i(1, 0))
	check(m.size() == 2 and Vector2i(0, 0) in m and Vector2i(3, 0) in m, "left/right pair is knocked out")
	check(t.matches_from(Vector2i(1, 1)).is_empty(), "no pair from a middle slot is a miss")

	# first gem only: the 1 behind the 2 must not count
	var u := board_from(["1", ".", "2", "1", ".", "1"])
	var mu := u.matches_from(Vector2i(0, 1))
	check(mu.is_empty(), "only the first gem in each direction counts")
	var mu2 := u.matches_from(Vector2i(0, 4))
	check(mu2.size() == 2, "vertical pair through an empty slot")

	# cross with three of a kind and two pairs
	var x := board_from([".5.", "5.5", ".7."])
	check(x.matches_from(Vector2i(1, 1)).size() == 3, "three of a kind is knocked out together")
	var y := board_from([".5.", "6.6", ".5."])
	check(y.matches_from(Vector2i(1, 1)).size() == 4, "two different pairs both go")

	check(BoardLogic.points_for(2) == 2 and BoardLogic.points_for(3) == 4 and BoardLogic.points_for(4) == 6, "scoring 2/4/6")
	check(BoardLogic.bonus_for(2) == 0 and BoardLogic.bonus_for(3) == 1 and BoardLogic.bonus_for(4) == 2, "time bonus 0/1/2")

	# transpose keeps every move
	var before := 0
	for yy in b.rows:
		for xx in b.cols:
			if b.is_empty(Vector2i(xx, yy)):
				before += b.matches_from(Vector2i(xx, yy)).size()
	b.transpose()
	var after := 0
	for yy in b.rows:
		for xx in b.cols:
			if b.is_empty(Vector2i(xx, yy)):
				after += b.matches_from(Vector2i(xx, yy)).size()
	check(b.cols == 15 and b.rows == 23 and before == after, "transpose keeps every move")

	# shuffle keeps gem counts and finds a move
	var s := board_from(["1.2", "...", "3.1"])
	check(not s.has_any_move(), "stuck board detected")
	var left := s.gems_left()
	s.shuffle_remaining(rng)
	check(s.gems_left() == left, "shuffle keeps the gems")

	# play a full random game to the end
	b.setup(BoardLogic.LONG, BoardLogic.SHORT, rng)
	var moves := 0
	while b.has_any_move() and moves < 1000:
		var p := b.find_move()
		b.remove(b.matches_from(p))
		moves += 1
	check(not b.has_any_move() and moves > 20, "greedy play reaches a stuck board (%d moves, %d gems left)" % [moves, b.gems_left()])

	var tall := BoardLogic.best_dims(Vector2(540, 1150))
	var wide := BoardLogic.best_dims(Vector2(1250, 620))
	check(tall.y > tall.x and wide.x > wide.y, "board shape follows the screen (%s tall, %s wide)" % [tall, wide])
	var ok_sizes := true
	for a in [Vector2(540, 1150), Vector2(1250, 620), Vector2(700, 700), Vector2(380, 1400), Vector2(2000, 500)]:
		var d := BoardLogic.best_dims(a)
		ok_sizes = ok_sizes and d.x * d.y >= 317 and d.x * d.y <= 372
	check(ok_sizes, "every shape has 345 slots ±8% for the 270 gems")
	var sq := BoardLogic.new()
	sq.setup(tall.x, tall.y, rng)
	var gems := 0
	for kk in sq.cells:
		if kk >= 0: gems += 1
	check(gems == 270, "270 gems on a %dx%d board" % [tall.x, tall.y])
	var cm := BoardLogic.BRIGHT
	var phone := BoardLogic.best_dims(Vector2(540, 1150), cm.slots)
	var small := BoardLogic.new()
	small.setup(phone.x, phone.y, rng, cm.shining, cm.kinds, cm.per_kind)
	var cnt := {}
	for kk in small.cells:
		cnt[kk] = cnt.get(kk, 0) + 1
	check(phone.y > phone.x and absi(phone.x * phone.y - cm.slots) <= cm.slots * 0.08,
		"bright phone board %s has about %d slots" % [phone, cm.slots])
	check(cnt.size() == cm.kinds + 1 and cnt.get(0, 0) == cm.per_kind, "compact board: 6 kinds x 14 gems")

	var sh := BoardLogic.new()
	sh.setup(BoardLogic.LONG, BoardLogic.SHORT, rng)
	var shining := 0
	var on_gems := true
	for i in sh.cells.size():
		if sh.shine[i] == 1:
			shining += 1
			on_gems = on_gems and sh.cells[i] >= 0
	check(shining == BoardLogic.SHINING and on_gems, "8 shining gems, all on gems")
	var before_t := shining
	sh.transpose()
	var after_t := 0
	for v in sh.shine: after_t += v
	check(after_t == before_t, "transpose keeps shining gems")
	var mv := sh.find_move()
	var gone := sh.matches_from(mv)
	var nsh := sh.shining_count(gone)
	sh.remove(gone)
	var shine_left := 0
	for v in sh.shine: shine_left += v
	check(shine_left == before_t - nsh, "removing gems clears their shine")
	sh.shuffle_remaining(rng)
	var ok_after := true
	for i in sh.cells.size():
		if sh.shine[i] == 1: ok_after = ok_after and sh.cells[i] >= 0
	check(ok_after, "shuffle moves the shine together with its gem")

	var l1 := BoardLogic.bright_level(1)
	var l6 := BoardLogic.bright_level(6)
	var l9 := BoardLogic.bright_level(9)
	check(l1.slots < l6.slots and l1.kinds < l6.kinds and l9.slots <= 120, "levels grow the board and add kinds")
	var tl := BoardLogic.new()
	var d1 := BoardLogic.best_dims(Vector2(360, 640), l1.slots)
	var mv1 := tl.setup_tuned(d1.x, d1.y, rng, 1, l1.kinds, l1.per_kind, l1.min_moves, l1.max_moves, l1.tries)
	check(mv1 >= l1.min_moves and tl.count_moves() == mv1, "level 1 opens with %d+ moves (%d on %s)" % [l1.min_moves, mv1, d1])
	var d9 := BoardLogic.best_dims(Vector2(360, 640), l9.slots)
	var mv9 := tl.setup_tuned(d9.x, d9.y, rng, 1, l9.kinds, l9.per_kind, l9.min_moves, l9.max_moves, l9.tries)
	check(mv9 >= l9.min_moves, "level 9 deal opens with at least %d moves (%d)" % [l9.min_moves, mv9])
	var bx := board_from(["123", "4.5", "678"])
	check(bx.area(Vector2i(1, 1)).size() == 8 and bx.area(Vector2i(0, 0)).size() == 3, "bomb area is 3x3 and clipped at edges")

	var all_clear := true
	var sizes := []
	for lvn in [1, 3, 5, 8]:
		var lvd := BoardLogic.bright_level(lvn)
		var dd := BoardLogic.best_dims(Vector2(360, 640), lvd.slots)
		var sb := BoardLogic.new()
		var placed := sb.setup_solvable(dd.x, dd.y, rng, 1, lvd.kinds, lvd.kinds * lvd.per_kind)
		sizes.append("L%d %dx%d %d gems" % [lvn, dd.x, dd.y, placed])
		var steps := sb.solution.duplicate()
		steps.reverse()
		for sp in steps:
			var g := sb.matches_from(sp)
			all_clear = all_clear and not g.is_empty()
			sb.remove(g)
		all_clear = all_clear and sb.gems_left() == 0
	check(all_clear, "solvable boards clear completely by their own solution (%s)" % ", ".join(sizes))
	var special_ok := true
	var specials := []
	for lvn in [6, 9, 12]:
		var lvd := BoardLogic.bright_level(lvn)
		var dd := BoardLogic.best_dims(Vector2(360, 640), lvd.slots)
		var sb := BoardLogic.new()
		sb.setup_solvable(dd.x, dd.y, rng, 1, lvd.kinds, lvd.kinds * lvd.per_kind, lvd.jokers, lvd.boxes)
		var nj := 0
		var nb := 0
		for i in sb.cells.size():
			if sb.cells[i] == BoardLogic.JOKER: nj += 1
			if sb.hp[i] >= 2: nb += 1
		specials.append("L%d: %d jokers, %d boxes" % [lvn, nj, nb])
		var hint_ok := sb.next_solution_move() == sb.solution[sb.solution.size() - 1]
		var steps := sb.solution.duplicate()
		steps.reverse()
		for sp in steps:
			var g := sb.matches_from(sp)
			special_ok = special_ok and not g.is_empty()
			sb.remove(g)
		special_ok = special_ok and sb.gems_left() == 0 and hint_ok
	check(special_ok, "boards with jokers and boxes still clear fully, hint = next solution strike (%s)" % ", ".join(specials))
	var jb := board_from([".1.", "2.2", ".1."])
	jb.cells[1] = BoardLogic.JOKER  # top becomes a joker: hits are joker, 2, 2, 1
	check(jb.matches_from(Vector2i(1, 1)).size() == 3, "a joker joins the most common kind")
	var bxb := board_from(["1.1"])
	bxb.hp[0] = 2
	bxb.remove(bxb.matches_from(Vector2i(1, 0)))
	check(bxb.kind_at(Vector2i(0, 0)) == 1 and bxb.kind_at(Vector2i(2, 0)) == -1 and not bxb.is_box(Vector2i(0, 0)), "a box cracks on the first hit")

	var cb := board_from(["1.1", "...", "2.2"])
	cb.chain[0] = 6
	cb.chain[6] = 0
	var extra := cb.remove(cb.matches_from(Vector2i(1, 0)))
	check(extra.size() == 1 and cb.kind_at(Vector2i(0, 2)) == -1 and cb.gems_left() == 1, "a chain gem pulls its partner out")
	# Regression: chain partners already in the cross are not extra removals.
	var direct_chain := board_from(["1.1"])
	direct_chain.chain[0] = 2
	direct_chain.chain[2] = 0
	var direct_hits := direct_chain.matches_from(Vector2i(1, 0))
	var direct_extra := direct_chain.remove(direct_hits)
	check(direct_extra.is_empty() and direct_chain.gems_left() == 0,
		"chain partners inside one cross are removed once, with no extra positions")

	# Regression: an outside partner is reported exactly once and outside the direct hit.
	var outside_chain := board_from(["1.1", "...", "1.."])
	outside_chain.chain[0] = 6
	outside_chain.chain[6] = 0
	var outside_hits := outside_chain.matches_from(Vector2i(1, 0))
	var outside_extra := outside_chain.remove(outside_hits)
	check(outside_extra.size() == 1 and outside_extra[0] == Vector2i(0, 2)
		and not (outside_extra[0] in outside_hits) and outside_chain.gems_left() == 0,
		"an outside chain partner is one unique extra removal")

	# Regression: cracking a box is a hit, but not a destroyed gem.
	var cracked_box := board_from(["1.1"])
	cracked_box.hp[0] = 2
	var box_hits := cracked_box.matches_from(Vector2i(1, 0))
	var box_vanish := cracked_box.vanishing(box_hits)
	var box_extra := cracked_box.remove(box_hits)
	check(box_vanish.size() == 1 and box_vanish[0] == Vector2i(2, 0)
		and box_extra.is_empty() and cracked_box.gems_left() == 1 and cracked_box.hp[0] == 1,
		"a cracked box stays on the board and is not counted as destroyed")

	# Even if a chain points at a box, only actual removals belong in extra.
	var chained_box := board_from(["1.1", "...", "1.."])
	chained_box.hp[6] = 2
	chained_box.chain[0] = 6
	chained_box.chain[6] = 0
	var chained_box_extra := chained_box.remove(chained_box.matches_from(Vector2i(1, 0)))
	check(chained_box_extra.is_empty() and chained_box.gems_left() == 1 and chained_box.hp[6] == 1,
		"a chain that only cracks its partner reports no extra removal")

	var chained_ok := true
	var made_total := 0
	for lvn in [8, 10, 12]:
		var lvd := BoardLogic.bright_level(lvn)
		var dd := BoardLogic.best_dims(Vector2(360, 640), lvd.slots)
		var cbd := BoardLogic.new()
		cbd.setup_solvable(dd.x, dd.y, rng, 1, lvd.kinds, lvd.kinds * lvd.per_kind, lvd.jokers, lvd.boxes)
		made_total += cbd.add_chains(rng, lvd.chains)
		chained_ok = chained_ok and cbd.replay_clears()
	check(chained_ok and made_total > 0, "chained boards stay fully clearable (%d chains)" % made_total)
	check(BoardLogic.bright_level(10).boss and BoardLogic.bright_level(10).slots > BoardLogic.bright_level(9).slots,
		"every tenth level is a bigger boss board")
	var pz := BoardLogic.puzzle_config(3)
	var pd := BoardLogic.best_dims(Vector2(360, 640), pz.slots)
	var pb := BoardLogic.new()
	pb.setup_tuned(pd.x, pd.y, rng, 0, pz.kinds, pz.per_kind, pz.min_moves, pz.max_moves, pz.tries, true)
	check(pb.replay_clears() and pb.solution.size() >= 3, "puzzle boards clear in %d strikes" % pb.solution.size())

	var tb := BoardLogic.new()
	var tl3 := BoardLogic.bright_level(5)
	var td := BoardLogic.best_dims(Vector2(360, 640), tl3.slots)
	tb.setup_solvable(td.x, td.y, rng, 1, tl3.kinds, tl3.kinds * tl3.per_kind, 0.25, 2)
	tb.transpose()
	check(tb.replay_clears() and tb.next_solution_move().x >= 0, "a turned board keeps a working solution and hint")

	var tuned := BoardLogic.new()
	var l3 := BoardLogic.bright_level(3)
	var d3 := BoardLogic.best_dims(Vector2(360, 640), l3.slots)
	var m3 := tuned.setup_tuned(d3.x, d3.y, rng, 1, l3.kinds, l3.per_kind, l3.min_moves, l3.max_moves, l3.tries, true)
	check(m3 >= 1 and not tuned.solution.is_empty(), "tuned solvable deal keeps its solution (%d opening moves)" % m3)

	# ice: a frozen gem blocks and never matches; knocking out a neighbour thaws it
	var ib := board_from(["1.1", "...", "2.2"])
	ib.ice[0] = 1
	check(ib.matches_from(Vector2i(1, 0)).is_empty(), "a frozen gem does not match")
	ib.ice[0] = 0
	var ib2 := board_from(["21.1", "....", "2..."])
	ib2.ice[1] = 1
	check(ib2.matches_from(Vector2i(2, 0)).is_empty(), "the frozen 1 blocks the row")
	ib2.remove(ib2.matches_from(Vector2i(0, 1)))
	check(ib2.ice[1] == 0 and Vector2i(1, 0) in ib2.last_thawed, "knocking out a neighbour thaws the ice")
	check(ib2.matches_from(Vector2i(2, 0)).size() == 2, "a thawed gem matches again")
	# bombs tick on every strike and go off at zero
	var bb := board_from(["1.1", "..."])
	bb.bomb[0] = 2
	check(bb.tick_bombs().is_empty() and bb.bomb[0] == 1, "a bomb ticks down")
	var went := bb.tick_bombs()
	check(went.size() == 1 and went[0] == Vector2i(0, 0), "a bomb goes off at zero")
	bb.bomb[2] = 3
	bb.remove(bb.matches_from(Vector2i(1, 0)))
	check(not bb.has_bombs(), "knocking a bomb gem out defuses it")
	# chameleons shift kind
	var chb := board_from(["1.2"])
	chb.cham[0] = 1
	chb.shift_chameleons(3)
	check(chb.cells[0] == 2 and chb.matches_from(Vector2i(1, 0)).size() == 2, "a chameleon turns into the next kind")
	# frozen solvable boards still clear by their solution
	var fr := RandomNumberGenerator.new()
	fr.seed = 7
	var fb := BoardLogic.new()
	fb.setup_tuned(8, 12, fr, 0, 5, 12, 2, 999, 10, true, 0.0, 2)
	var frozen := fb.add_ice(fr, 5)
	check(frozen >= 3 and fb.replay_clears(), "ice is only placed where the board stays clearable (%d frozen)" % frozen)
	var lv40 := BoardLogic.bright_level(40)
	check(BoardLogic.chapter_of(20) == 0 and BoardLogic.chapter_of(21) == 1 and lv40.rule == "ice" and lv40.ice >= 8,
		"chapters of 20; the second chapter's boss is icy")

	print("ScoreKeeper")
	var k := ScoreKeeper.new()
	var r := k.hit(2, 0.0)
	check(r.points == 2 and r.mult == 1 and r.combo == 1, "first strike scores plain points")
	r = k.hit(2, 1.0)
	check(r.mult == 2 and r.points == 4 and r.tier_up, "second strike in the window doubles")
	check(r.time == ScoreKeeper.TIER_TIME, "a new multiplier gives +2 s")
	r = k.hit(2, 5.0)
	check(r.combo == 1 and r.mult == 1, "a pause longer than the window resets the combo")
	k.hit(2, 5.5)
	check(k.miss(), "a miss breaks a running combo")
	check(k.combo == 0, "combo is zero after a miss")
	for i in 9:
		r = k.hit(2, 6.0 + i)
	check(r.combo == 9 and r.mult == 4 and k.best_combo == 9, "nine in a row reach x4")
	check(k.update(30.0) and k.combo == 0, "update() expires the combo")

	k.reset()
	r = k.hit(3, 0.0)
	check(r.event == "" and r.time == 1.0, "one 3-gem strike is not a precise combo yet")
	k.hit(4, 1.0)
	r = k.hit(3, 2.0)
	check(r.event == "precise" and r.time == 1.0 + ScoreKeeper.PRECISE_TIME, "3rd big strike in a row: precise combo")
	check(r.points == BoardLogic.points_for(3) * 2 + ScoreKeeper.PRECISE_POINTS, "precise bonus adds on top of x2")
	r = k.hit(4, 3.0)
	check(r.event == "perfect" and r.time == 2.0 + ScoreKeeper.PERFECT_TIME, "4th big strike: perfect combo")
	r = k.hit(3, 4.0)
	check(r.event == "perfect" and k.precise_count == 3, "every big strike after that is perfect too")
	r = k.hit(2, 5.0)
	check(r.event == "" and k.precise_streak == 0, "a 2-gem strike ends the precise streak")

	var tight := ScoreKeeper.new()
	tight.time_bonuses = false
	tight.hit(3, 0.0); tight.hit(4, 0.5); r = tight.hit(3, 1.0)
	check(r.event == "precise" and r.time == 1.0, "without time bonuses only +1 s / +2 s for 3 / 4 gems remain")

	k.reset()
	r = k.hit(2, 0.0, 1)
	check(r.points == 2 + ScoreKeeper.SHINE_POINTS and r.time == ScoreKeeper.SHINE_TIME, "a shining gem adds +5 points and +2 s")

	print("FAILED: %d" % failed if failed else "all passed")
	quit(1 if failed else 0)
