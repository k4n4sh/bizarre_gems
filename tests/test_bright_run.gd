extends SceneTree
## Run in an isolated project/profile: --script res://tests/test_bright_run.gd -- --combo-ab=B
## BRIGHT_RUN_OUTPUT optionally names the JSON report outside the project.
var checks := 0
var failures: Array[String] = []
var measurements: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func settle(n := 8) -> void:
	for i in n:
		await process_frame

func ready_run(main) -> void:
	for i in 300:
		if not main._run_starting and not main.dealing:
			return
		await process_frame
	check(false, "start/deal completed within 300 frames")

func snapshot(main) -> Dictionary:
	return {"wave":main.wave,"daily":main.daily,"viewport":main.get_viewport_rect().size,
		"board":main.board.size,"area":main._board_area(),"cols":main.logic.cols,"rows":main.logic.rows,
		"slots":main.logic.cells.size(),"cell":main.board.cell,"origin":main.board.origin,
		"position":main.board.global_position,"grid":Vector2(main.logic.cols,main.logic.rows)*main.board.cell}

func digest(b) -> String:
	return (str(b.cells)+str(b.shine)+str(b.hp)+str(b.chain)+str(b.ice)+str(b.bomb)+str(b.cham)).sha256_text()

## Independent reconstruction of the seeded rules, in canonical orientation.
func daily_reference(main, wave: int) -> BoardLogic:
	var r := RandomNumberGenerator.new()
	r.seed = hash("bizarre-gems-%s-bright-%d" % [main._today(), wave])
	var d := BoardLogic.best_dims(Vector2(360,640),200)
	var b := BoardLogic.new()
	b.setup_tuned(d.x,d.y,r,main.mode.shining,6,28,4,999,30,true,0.1,5)
	b.add_chains(r,3)
	if main.RUN_HAZARDS_ENABLED:
		b.add_ice(r,3)
		b.add_bombs(r,2,12)
	b.add_chameleons(r,2)
	if main._daily_transposed:
		b.transpose()
	return b

func _run() -> void:
	root.get_node("Save").sound = false
	root.get_node("Save").music = false
	root.get_node("Save").voice = false
	root.get_node("Sfx").update_music()
	Engine.time_scale = 20.0  # Accelerate wave animations, not the disabled game clock.
	root.content_scale_size = Vector2i.ZERO
	var screens := [
		["Android compact",480,860,true], ["Android regression",480,1008,true],
		["Android 19.5:9",480,1040,true], ["Android 20:9",480,1066,true],
		["Android tablet",600,960,true],
		["desktop regression",1135,720,false], ["desktop HD",1280,720,false],
		["desktop FHD",1920,1080,false]]
	for screen in screens:
		root.size = Vector2i(screen[1],screen[2])
		var main = load("res://scenes/main.tscn").instantiate()
		main.set_script(load("res://tests/bright_run_fixture.gd"))
		main.simulate_android = screen[3]
		root.add_child(main)
		main.set_process(false)
		await settle()
		for is_daily in [false,true]:
			var context := str(screen[0])+" daily="+str(is_daily)
			main.start_game("bright",is_daily)
			check(main._run_starting and main.state != main.State.PLAYING and not main.board.interactive,
				context+" timer/input blocked before layout")
			var time_before: float = main.time_left
			main._process(1.0)
			main._on_slot(main.logic.find_move())
			check(main.time_left == time_before and main.score == 0,context+" no early timer or hit")
			await ready_run(main)
			await settle()
			check(main.state == main.State.PLAYING and main.board.interactive and main.board.modulate.a == 1,
				context+" first field visible and playable")
			var first := snapshot(main)
			var daily_hashes: Array[String] = []
			check(main.board.size.x >= 50 and main.board.size.y >= 50,context+" actual board area")
			var expected := BoardLogic.best_dims(main._board_area(),200)
			if not is_daily:
				check(Vector2i(main.logic.cols,main.logic.rows) == expected,context+" first shape from actual area")
			else:
				check(digest(main.logic) == digest(daily_reference(main,1)),context+" first Daily seeded data")
			for wave in range(1,8):
				if wave > 1:
					# Both real branches: a stuck board and a fully cleared board.
					if wave % 2 == 0:
						main.logic.cells.fill(BoardLogic.EMPTY)
					main._next_wave(Vector2i(main.logic.cols/2,main.logic.rows/2))
					await ready_run(main)
					await settle()
				var current := snapshot(main)
				check(main.logic.ice.count(0) == main.logic.ice.size(),context+" no ice flags")
				check(main.logic.bomb.count(0) == main.logic.bomb.size(),context+" no bombs or countdowns")
				check(main.logic.tick_bombs().is_empty(),context+" no hidden bomb effect")
				measurements.append({"screen":screen[0],"data":current,"hash":digest(main.logic)})
				for key in ["viewport","board","area","cols","rows","slots","cell","origin","position","grid"]:
					check(current[key] == first[key],context+" wave %d stable %s" % [wave,key])
				for y in main.logic.rows:
					for x in main.logic.cols:
						var p := Vector2i(x,y)
						check(main.board.slot_at(main.board.slot_center(p)) == p,context+" input mapping")
				if is_daily:
					check(digest(main.logic) == digest(daily_reference(main,wave)),context+" wave %d deterministic" % wave)
					daily_hashes.append(digest(main.logic))
			var cells = main.logic.cells.duplicate()
			var score: int = main.score
			var time: float = main.time_left
			root.size = Vector2i(screen[1]+160,screen[2]+120)
			await settle()
			check(main.logic.cells == cells and main.score == score and main.time_left == time and main.wave == 7,
				context+" resize preserves party")
			check(main.logic.cols == first.cols and main.logic.rows == first.rows,context+" resize retains dimensions")
			check(main.board.cell != first.cell,context+" actual resize rescales")
			# Use the real board input path (Android's emulated left click).
			var move: Vector2i = main.logic.find_move()
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			event.position = main.board.slot_center(move)
			main.board._gui_input(event)
			check(main.score > score and main.logic.cells != cells,context+" input after resize")
			await main.start_game("bright",is_daily)
			check(main.wave == 1 and main.score == 0 and main.time_left == 120,context+" new party resets")
			if not is_daily:
				check(main._run_dims == BoardLogic.best_dims(main._board_area(),200),context+" new geometry selected")
			else:
				check(digest(main.logic) == digest(daily_reference(main,1)),context+" Daily restart reproducible")
				for wave in range(2,8):
					main._next_wave(Vector2i.ZERO)
					await ready_run(main)
					check(digest(main.logic) == daily_hashes[wave-1],context+" actual Daily replay wave %d" % wave)
			# Cancel a pending start, then cancel a delayed old-wave callback.
			main.start_game("bright",is_daily)
			main.go_menu()
			await settle()
			check(main.state == main.State.MENU and not main._run_starting,context+" start cancellation")
			await main.start_game("bright",is_daily)
			main._next_wave(Vector2i.ZERO)
			await main.start_game("bright",is_daily)
			var new_digest := digest(main.logic)
			await settle(20)
			check(main.wave == 1 and digest(main.logic) == new_digest,context+" old wave cannot overwrite restart")
			main.go_menu()
			root.size = Vector2i(screen[1],screen[2])
			await settle()
		main.queue_free()
		await settle()
	# A genuinely unavailable layout must keep waiting, without freezing fallback dimensions.
	var vp := SubViewport.new()
	vp.size = Vector2i(32,32)
	root.add_child(vp)
	var pending = load("res://scenes/main.tscn").instantiate()
	pending.set_script(load("res://tests/bright_run_fixture.gd"))
	vp.add_child(pending)
	pending.set_process(false)
	pending.start_game("bright")
	await settle()
	check(pending._run_starting and pending._run_dims == Vector2i.ZERO and pending.time_left == 120,
		"tiny initial viewport never locks fallback shape or starts timer")
	vp.size = Vector2i(480,1008)
	await ready_run(pending)
	check(pending.state == pending.State.PLAYING and pending._run_dims == BoardLogic.best_dims(pending._board_area(),200),
		"pending first deal completes from eventual actual layout")
	pending.go_menu()
	# Unchanged modes still use their own level/Zen obstacle rules.
	for id in ["levels","zen"]:
		pending.daily = false
		pending._use_mode(id)
		pending.wave = 4
		pending.level_n = 20
		pending.rng.seed = 8181
		pending._deal_board()
		check(pending.logic.ice.has(1),id+" ice generation retained")
		check(pending.logic.has_bombs(),id+" bomb generation retained")
	vp.queue_free()
	await settle()
	Engine.time_scale = 1.0
	var report := {"checks":checks,"failed":failures.size(),"failures":failures,"measurements":measurements}
	var path := OS.get_environment("BRIGHT_RUN_OUTPUT")
	if not path.is_empty():
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BRIGHT_RUN ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
