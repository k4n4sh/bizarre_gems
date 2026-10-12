extends RefCounted
## Run with run_runtime_suite.gd in an isolated fixture, using Windows/OpenGL and WASAPI.
## Headless tests skip canvas drawing and cannot reproduce the debugger break.

var checks := 0
var failures: Array[String] = []
var observations: Array = []
var _main
var _invalid_presses := 0
var _presses := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func on_slot(p: Vector2i) -> void:
	_presses += 1
	if not _main.logic.in_bounds(p):
		_invalid_presses += 1


func settle(tree: SceneTree, frames := 5) -> void:
	for i in frames:
		await tree.process_frame


func peak(samples: PackedVector2Array) -> float:
	var value := 0.0
	for sample in samples:
		value = maxf(value, maxf(absf(sample.x), absf(sample.y)))
	return value


func run_suite(main) -> Dictionary:
	_main = main
	checks = 0
	failures.clear()
	observations.clear()
	var tree: SceneTree = main.get_tree()
	var save = main.get_node("/root/Save")
	var sfx = main.get_node("/root/Sfx")
	if not save.PATH.begins_with("res://.test-user/"):
		return {"error": "Use an isolated fixture with res://.test-user/ save paths."}
	check(DisplayServer.get_name() == "Windows", "real desktop canvas rendering enabled")
	check(AudioServer.get_driver_name() == "WASAPI", "real desktop audio driver enabled")
	save.sound = false
	save.music = true
	save.music_volume = 0.7
	sfx.set_platform_paused(false)
	sfx.apply_volumes()
	main.board.slot_pressed.connect(on_slot)
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "TransitionAudio")
	AudioServer.set_bus_send(bus, "Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	var old_bus: StringName = sfx._music.bus
	sfx._music.bus = "TransitionAudio"
	for is_daily in [false, true]:
		for keyboard in [false, true]:
			var label := "daily=%s keyboard=%s" % [is_daily, keyboard]
			await main.start_game("classic")
			await settle(tree)
			check(sfx._music.stream == sfx.MUSIC and sfx._music.playing, label + ": Classic music initially playing")
			var old_slot := Vector2i(main.logic.cols - 1, main.logic.rows - 1)
			main.board._hover = old_slot
			main.board._cursor = old_slot
			main.board._keyboard = keyboard
			main.go_menu()
			await main.start_game("bright", is_daily)
			check(not main.logic.in_bounds(old_slot), label + ": regression coordinate is outside smaller board")
			var focus: Vector2i = main.board._cursor if keyboard else main.board._hover
			check(focus == Vector2i(-1, -1) or main.logic.in_bounds(focus), label + ": refresh discards invalid cached focus")
			# Pointer bounds are independent of special-gem artwork. Ordinary gems keep
			# this fixture focused on mode transitions and index errors.
			for i in main.logic.cells.size():
				if main.logic.cells[i] == BoardLogic.JOKER:
					main.logic.cells[i] = 0
			main.board.mark_dirty()
			await settle(tree)
			check(main.state == main.State.PLAYING and not main._run_starting and main.board.interactive and main.board.modulate.a == 1.0,
				label + ": new field is visible and playable")
			check(main.logic.cells.size() == main.logic.cols * main.logic.rows and main.logic.gems_left() == main.level_total and main.logic.has_any_move(),
				label + ": complete new board data")
			# Also exercise the rendering/input boundary before any later refresh can
			# repair a stale coordinate, as can happen during a resize or new deal.
			main.board._hover = old_slot
			main.board._cursor = old_slot
			main.board.queue_redraw()
			await settle(tree)
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.pressed = true
			main.board._gui_input(key)
			check(_invalid_presses == 0, label + ": stale keyboard cursor never emits an invalid strike")
			var before := _presses
			main.board._cursor = main.logic.find_move()
			main.board._keyboard = true
			main.board._gui_input(key)
			check(_presses == before + 1 and main.score > 0, label + ": valid keyboard strikes still work")
			capture.clear_buffer()
			var position: float = sfx._music.get_playback_position()
			await tree.create_timer(0.6).timeout
			var samples := capture.get_buffer(capture.get_frames_available())
			var audio_peak := peak(samples)
			check(sfx._music.stream == sfx.MUSIC_BRIGHT and sfx._music.playing and sfx._music.get_playback_position() > position + 0.2,
				label + ": Bright theme keeps playing beyond the reported short burst")
			check(samples.size() > 0 and audio_peak > 0.001, label + ": Bright theme produces sustained audio")
			observations.append({"daily": is_daily, "keyboard": keyboard, "dims": Vector2i(main.logic.cols, main.logic.rows),
				"captured_frames": samples.size(), "peak": audio_peak, "position": sfx._music.get_playback_position()})
			main.go_menu()
	main.board.slot_pressed.disconnect(on_slot)
	save.music = false
	sfx.update_music()
	sfx._music.bus = old_bus
	AudioServer.remove_bus(bus)
	await tree.create_timer(0.1).timeout
	_main = null
	return {"checks": checks, "failed": failures.size(), "failures": failures, "observations": observations,
		"display_driver": DisplayServer.get_name(), "audio_driver": AudioServer.get_driver_name()}
