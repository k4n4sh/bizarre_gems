extends RefCounted
## Run through Godot AI game_eval on a fresh 1280x720 menu.
## Classic golden is retained; Bright golden reflects settled geometry and disabled hazards.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func digest(b) -> String:
	return (str(b.cells) + str(b.shine) + str(b.hp) + str(b.chain) + str(b.ice) + str(b.bomb) + str(b.cham)).sha256_text()

func run_suite(main) -> Dictionary:
	if main.state != main.State.MENU:
		return {"error":"Fresh 1280x720 menu required"}
	main.ComboExperiment.select("B", 42)
	var goldens := [
		"83d6bae23fd9c824842712141d622f08e81e9ededcc2a42fe9d59a4ca0ff4c09",
		"cf72bf5d87b7931d3f27d6d8b524a38c54c081a028a269edd3cbd279507ba9d8"]
	var observations := []
	var configs := [["classic",false],["bright",false],["bright",true]]
	for i in configs.size():
		var config: Array = configs[i]
		main.rng.seed = 8181
		await main.start_game(config[0], config[1])
		var before := digest(main.logic)
		if i < 2:
			check(before == goldens[i], "board golden including all special states " + str(config))
		else:
			check(main.logic.cells.size() == 198 and not main.logic.has_bombs() and main.logic.ice.count(0) == main.logic.ice.size(), "Daily canonical slots and updated hazards policy")
		check(main.mode.skin == ("classic" if i == 0 else "bright"), "rule discriminator retained")
		check(main.board.skin == main.mode.skin, "mode sizing family retained")
		check(main.visual_profile == ("classic" if i == 0 else "classic_run") and main.board.visual_profile == main.visual_profile, "unified rendering profile")
		check(main.ambient.skin == "classic", "velvet backdrop")
		check(main.time_left == 120 and main.score == 0, "initial clock and score")
		check(main.keeper.combo_window == (3.5 if i == 0 else 3.0), "combo windows retained")
		check(main.logic.gems_left() == 270 if i == 0 else main.mode.kinds == 6, "mode gem count/kinds")
		if i > 0:
			check(main.hud.custom_minimum_size.y == 93 and main.time_row.custom_minimum_size.y == 35, "HUD reserves previous board area")
			check(main.score_label.get_theme_font("font") == main.f_num, "Classic numerical typeface")
			for k in 6:
				check(main.board._tex(k) == main.board.GEM_TEX[main.board.RUN_GEM_INDICES[k]], "faceted gem mapping " + str(k))
			check(main.board._tex(main.logic.JOKER) == main.board.JOKER_TEX, "joker still distinct")
			main.board.visual_profile = "bright"
			main.board.visual_profile = "classic_run"
			check(digest(main.logic) == before and main.score == 0 and main.time_left == 120, "presentation cannot mutate rules")
			if config[1]:
				await main.start_game("bright", true)
				check(digest(main.logic) == before, "Daily restart deterministic")
		observations.append({"mode":config,"hash":before,"cols":main.logic.cols,"rows":main.logic.rows})
		main.go_menu()
		check(main.ambient.skin == "classic", "menu backdrop is independent of last played mode")
	check(not main.get_node("/root/Progress").COSMETICS_ENABLED, "cosmetics remain disabled")
	return {"checks":checks,"failed":failures.size(),"failures":failures,"boards":observations}
