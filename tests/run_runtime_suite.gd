extends SceneTree
## CLI adapter for the existing in-game regression suites. Use an isolated project/profile.
## --script res://tests/run_runtime_suite.gd -- --suite=test_cosmetics --combo-ab=B
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var suite := "test_bright_palette"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			suite = arg.get_slice("=",1)
	root.get_node("Save").sound = false
	root.get_node("Save").music = false
	root.get_node("Save").voice = false
	root.get_node("Sfx").update_music()
	root.size = Vector2i(1280,720)
	var main = load("res://scenes/main.tscn").instantiate()
	if "--palette-phone" in OS.get_cmdline_user_args():
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(480,1008)
		main.set_script(load("res://tests/bright_run_fixture.gd"))
		main.simulate_android = true
	root.add_child(main)
	current_scene = main
	main.set_process(false)
	for i in 12:
		await process_frame
	var test = load("res://tests/%s.gd" % ("test_menu_visuals" if suite == "test_menu_layouts" else suite)).new()
	var report: Dictionary
	if suite == "test_special_combo":
		report = {"rules":test.run_rules(),"runtime":await test.run_in_game(main)}
	elif suite == "test_tutorial_visuals" or suite == "test_menu_layouts":
		if suite == "test_menu_layouts":
			test = load("res://tests/test_menu_visuals.gd").new()
		report = {"layouts":[]}
		for resolution in [Vector2i(480,860),Vector2i(480,1008),Vector2i(1280,720)]:
			for language in ["ru","en","tr"]:
				report.layouts.append(await test.run_layout(main,resolution,language))
	else:
		report = await test.run_suite(main)
	var serialized := JSON.stringify(report)
	var path := OS.get_environment("RUNTIME_TEST_OUTPUT")
	if not path.is_empty():
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RUNTIME_SUITE ",suite," ",serialized)
	quit(1 if failed(report) else 0)

func failed(value) -> bool:
	if value is Dictionary:
		if value.has("error") or int(value.get("failed",0)) > 0:
			return true
		for child in value.values():
			if failed(child):
				return true
	elif value is Array:
		for child in value:
			if failed(child):
				return true
	return false
