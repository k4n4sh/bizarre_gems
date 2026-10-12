extends RefCounted
## Godot AI game_eval on a fresh menu. Run with the single production switch false and true.
## Player data is restored in memory; all writes are locked before fixtures are applied.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run_suite(main) -> Dictionary:
	if main.state != main.State.MENU:
		return {"error": "Fresh menu required"}
	var p = main.get_node("/root/Progress")
	var enabled: bool = p.COSMETICS_ENABLED
	main.ComboExperiment.select("B", 42)
	var original := {}
	for property in p.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = p.get(property.name)
			original[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
	p.owned = [0, 3, 6, 8, 9]
	p.look = 3
	p.crystals = 321
	p.season = p.season_id()
	p.season_xp = 0
	p.season_claimed = []
	check(main.ui.home_coll.visible == enabled, "menu collection visibility")
	main._refresh_collection()
	main._show_panel(main.collection_panel)
	check(main.collection_panel.visible == enabled, "collection direct route guarded")
	main._show_panel(main.settings_panel)
	check(main.settings_panel.visible and not main.collection_panel.visible, "settings remain available")
	main._show_panel(main.menu_panel)
	check(p.active_look() == (3 if enabled else 0) and p.look == 3, "saved non-default choice resolved without mutation")
	var signatures := []
	for config in [["classic", false], ["bright", false], ["bright", true]]:
		main.rng.seed = 8181
		await main.start_game(config[0], config[1])
		var expected_skin := "classic" if config[0] == "classic" else "bright"
		check(main.mode.skin == expected_skin and main.board.skin == expected_skin, "base mode skin unchanged " + str(config))
		check(main.keeper.combo_window == (3.5 if config[0] == "classic" else 3.0), "combo window unchanged " + str(config))
		var data := str(main.logic.cells) + str(main.logic.shine) + str(main.logic.hp) + str(main.logic.chain) + str(main.logic.ice) + str(main.logic.bomb) + str(main.logic.cham)
		signatures.append({"mode": config, "hash": data.sha256_text(), "gems": main.logic.gems_left(),
			"time": main.time_left, "kinds": main.mode.kinds, "skin": main.mode.skin})
		if config[0] == "classic":
			check(main.logic.gems_left() == 270, "Classic retains 270 gems")
		else:
			check(main.board.palette == (3 if enabled else 0), "selected/base Bright tile pack")
			main._set_theme(7, true)
			var run_palette: bool = not config[1]
			check(main.theme_i == (7 if enabled or run_palette else 0), "background cycle independent from dormant cosmetics")
			main._set_theme(main._next_look(), true)
			check(enabled or (main.theme_i == 0 and main.board.palette == 0), "gem pack stays base during background cycle")
			if run_palette:
				main._set_theme(main._next_look(), true)
				check(main.theme_i == 1 and main.board.palette == (3 if enabled else 0), "background advances without enabling cosmetic packs")
			main.board.palette = 6
			check(main.board.palette == (6 if enabled else 0), "board setter cannot bypass presentation policy")
		check(p.look == 3, "mode start never overwrites saved cosmetic choice")
		main.go_menu()
	if not enabled:
		var owned_before: Array = p.owned.duplicate()
		check(not p.buy(1), "buy blocked")
		p.select(6)
		check(not p.claim_season(), "season claim blocked")
		check(p.look == 3 and p.owned == owned_before and p.crystals == 321, "blocked cosmetics do not mutate currency/ownership/choice")
	else:
		p.select(6)
		check(p.look == 6 and p.active_look() == 6, "previously owned choice restored on enable")
		check(p.buy(1) and p.owns(1) and p.crystals == 261, "shop restored on enable")
	p.owned = [0]
	p.look = 3
	p.crystals = 321
	p.season_claimed = []
	p.season_xp = 0
	p.hint_tokens = 0
	p.add_xp(3000)
	check(p.season_xp == 3000, "pass XP unchanged")
	check(p.owns(p.NEON_LOOK) == not enabled and p.owns(p.GLASS_LOOK) == not enabled, "new pass skins banked only when disabled")
	check(p.look == 3 and p.crystals == 321, "banking never equips or changes crystals")
	check(p.claim_pass(5) == {"kind":"hints","n":3} and p.hint_tokens == 3, "hint reward unchanged")
	check(p.claim_pass(15) == {"kind":"crystals","n":100} and p.crystals == 421, "crystal reward unchanged")
	if not enabled:
		check(p.claim_pass(10).is_empty(), "banked tier cannot pay twice")
		check(not p.pass_claimable(10), "banked tier has no cosmetic claim action")
	# Existing duplicate-skin compensation is still available.
	p.season_claimed = []
	p.owned = [0, p.NEON_LOOK, p.GLASS_LOOK]
	p._check_season()
	main._refresh_pass()
	check(p.claim_pass(10) == {"kind":"crystals","n":200}, "duplicate compensation retained")
	p.owned = [0]
	p.season_claimed = []
	main._refresh_pass()
	var row_count: int = main.ui.pass_list.get_child_count()
	check(row_count == (30 if enabled else 28), "cosmetic-only pass rows hidden")
	var today := Time.get_date_string_from_system(true)
	p.gift_date = Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today) - 86400)
	p.streak = 6
	var before_gift: int = p.crystals
	main._refresh_gift()
	check(main.ui.gift_line.text == main.get_node("/root/L").t("gift_day7" if enabled else "gift_daily_crystals"), "gift copy follows cosmetics switch")
	var gift: Dictionary = p.open_gift()
	check(gift.crystals == 40 and p.crystals == before_gift + 40, "day-seven crystals retained")
	check(p.owns(p.GOLD_LOOK) and p.look == 3, "gift entitlement preserved without equipping")
	check(p.open_gift().is_empty(), "gift cannot be claimed twice")
	var cloud: Dictionary = p.to_dict()
	check(cloud.look == 3 and p.GOLD_LOOK in cloud.owned, "cloud data retains cosmetics")
	for key in original:
		p.set(key, original[key])
	main.go_menu()
	return {"enabled":enabled,"checks":checks,"failed":failures.size(),"failures":failures,"mode_signatures":signatures}
