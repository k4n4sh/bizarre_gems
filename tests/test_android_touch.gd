extends SceneTree
## Focused input checks, run only via test_android_touch.ps1's isolated view fixture.
var checks := 0
var failures: Array[String] = []
var board
var hits: Array[Vector2i] = []
var ui_clicks := 0
const INVALID := Vector2i(-1, -1)
const A := Vector2i(1, 2)
const B := Vector2i(2, 3)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	_run.call_deferred()


func point(slot: Vector2i) -> Vector2:
	return board.get_global_transform_with_canvas() * board.slot_center(slot)


func touch(id: int, pressed: bool, pos: Vector2, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.pressed = pressed
	event.position = pos
	event.canceled = canceled
	root.push_input(event)


func drag(id: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = pos
	root.push_input(event)


func mouse(pressed: bool, pos: Vector2, emulated := true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pos
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	root.push_input(event)


func motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(event)


func fresh() -> void:
	board._cancel_android_touch(true)
	board.reset_zoom()
	board.interactive = true
	hits.clear()


func single_finger(label: String) -> void:
	fresh()
	var before: PackedInt32Array = board.logic.cells.duplicate()
	touch(7, true, point(A))
	mouse(true, point(A))
	check(hits.is_empty() and board._hover == A, label + " immediate aim, no press hit")
	touch(7, false, point(A))
	mouse(false, point(A))
	touch(7, false, point(A))
	motion(point(A))
	check(hits == [A] and board._hover == INVALID, label + " fast tap exactly once, no ghost hover")
	check(board.logic.cells == before, label + " view emits only; rules remain in existing hit handler")
	fresh()
	board.zoom = 2.0
	board._relayout()
	var old_pan: Vector2 = board.pan
	touch(23, true, point(A))
	drag(23, point(B))
	motion(point(A))
	check(hits.is_empty() and board._hover == B, label + " drag follows cells, emulated mouse cannot move aim")
	check(board.zoom == 2.0 and board.pan == old_pan, label + " one finger does not pan zoomed board")
	touch(23, false, point(B))
	check(hits == [B] and board._hover == INVALID, label + " drag commits release cell once")
	fresh()
	touch(7, true, point(A))
	touch(7, false, point(B))
	check(hits == [B], label + " release position used even without final drag event")
	fresh()
	touch(7, true, point(A))
	touch(7, false, point(A), true)
	check(hits.is_empty() and board._hover == INVALID, label + " canceled touch never hits")
	fresh()
	board.zoom = 2.0
	board._relayout()
	var outside: Vector2 = board.get_global_transform_with_canvas() * Vector2(-8, board.size.y / 2)
	check(board.slot_at(board.get_global_transform_with_canvas().affine_inverse() * outside).x >= 0, label + " outside point is a clipped zoomed cell")
	touch(7, true, point(A))
	drag(7, outside)
	check(board._hover == INVALID and hits.is_empty(), label + " leaving visible board hides aim")
	touch(7, false, outside)
	check(hits.is_empty(), label + " release outside visible board cancels")
	fresh()
	touch(7, true, point(A))
	drag(7, Vector2(2, 2))
	drag(7, point(B))
	touch(7, false, point(B))
	check(hits == [B], label + " leaving and returning while held can still aim")


func multi_finger(label: String) -> void:
	fresh()
	touch(7, true, point(A))
	touch(99, true, point(B))
	check(board._hover == INVALID and board._android_blocked, label + " second ID cancels pending hit immediately")
	var old_zoom: float = board.zoom
	var second := point(B) + Vector2(70, 80)
	drag(99, second)
	check(board.zoom > old_zoom if board.zoom_enabled else board.zoom == old_zoom, label + " existing pinch zoom policy preserved")
	var old_pan: Vector2 = board.pan
	drag(7, point(A) + Vector2(30, 20))
	drag(99, second + Vector2(30, 20))
	check(board.pan != old_pan if board.zoom_enabled else board.pan == old_pan, label + " two finger pan policy preserved")
	touch(99, false, second)
	drag(7, point(A))
	check(board._hover == INVALID, label + " remaining finger cannot resume aiming")
	touch(4, true, point(B))
	touch(7, false, point(A))
	touch(4, false, point(B))
	check(hits.is_empty() and board._touches.is_empty(), label + " all mixed IDs released without hits")
	touch(23, true, point(A))
	touch(23, false, point(A))
	check(hits == [A], label + " fresh touch after all fingers up works")
	fresh()
	touch(7, true, point(A))
	touch(99, true, point(B))
	touch(4, true, point(A))
	touch(99, false, point(B), true)
	touch(7, false, point(A))
	touch(4, false, point(A))
	check(hits.is_empty() and not board._android_blocked, label + " three IDs and canceled multi touch reset safely")
	fresh()
	touch(7, true, point(A))
	touch(99, true, Vector2(420, 30)) # HUD, outside the board's GUI.
	touch(99, false, Vector2(420, 30))
	touch(7, false, point(A))
	check(hits.is_empty(), label + " second finger outside field still cancels hit")


func interruption(label: String) -> void:
	for kind in ["pause", "restart", "hidden", "focus"]:
		fresh()
		touch(7, true, point(A))
		match kind:
			"pause": board.interactive = false; board.interactive = true
			"restart": board.reset_zoom()
			"hidden": board.hide(); board.show()
			"focus": board._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		drag(7, point(B))
		touch(7, false, point(B))
		check(hits.is_empty() and board._hover == INVALID, label + " " + kind + " cancels held touch")
		touch(23, true, point(A))
		touch(23, false, point(A))
		check(hits == [A], label + " fresh touch after " + kind + " works")


func _run() -> void:
	check(not root.has_node("Save") and not root.has_node("Yandex") and not root.has_node("Sfx"), "no saves, SDK or game scene in fixture")
	check(root.get_node("Progress").get_script().resource_path == "res://scripts/progress_stub.gd", "progress is a constants-only stub")
	board = load("res://scripts/board_view.gd").new()
	board.position = Vector2(40, 100)
	board.size = Vector2(400, 680)
	board.logic = BoardLogic.new()
	var cells := PackedInt32Array()
	cells.resize(24)
	cells.fill(BoardLogic.EMPTY)
	board.logic.load_cells(4, 6, cells)
	board.slot_pressed.connect(func(slot): hits.append(slot))
	root.add_child(board)
	var button := Button.new()
	button.position = Vector2(40, 20)
	button.size = Vector2(140, 52)
	button.text = "Pause"
	button.pressed.connect(func(): ui_clicks += 1)
	root.add_child(button)
	await process_frame
	for skin in ["classic", "bright"]:
		board.skin = skin
		board.visual_profile = "classic_run" if skin == "bright" else "classic"
		board.zoom_enabled = skin == "classic"
		single_finger(skin)
		multi_finger(skin)
		interruption(skin)
	fresh()
	touch(7, true, point(A))
	await process_frame
	await process_frame
	check(hits.is_empty() and board._hover == A, "held touch across frames never hits")
	touch(7, false, point(A))
	check(hits == [A], "held touch hits once on release")
	fresh()
	Input.emulate_mouse_from_touch = true
	var native_touch := InputEventScreenTouch.new()
	native_touch.index = 0
	native_touch.position = point(A)
	native_touch.pressed = true
	Input.parse_input_event(native_touch)
	Input.flush_buffered_events()
	check(hits.is_empty() and board._hover == A, "Godot automatic mouse emulation preserves aim-only press")
	native_touch = InputEventScreenTouch.new()
	native_touch.index = 0
	native_touch.position = point(A)
	Input.parse_input_event(native_touch)
	Input.flush_buffered_events()
	check(hits == [A] and board._hover == INVALID, "Godot automatic mouse emulation produces exactly one release hit")
	Input.emulate_mouse_from_touch = false
	fresh()
	var ui_pos := Vector2(90, 40)
	touch(7, true, ui_pos)
	mouse(true, ui_pos)
	touch(7, false, ui_pos)
	mouse(false, ui_pos)
	check(ui_clicks == 1 and hits.is_empty(), "UI touch keeps button functional and never hits board")
	touch(7, true, ui_pos)
	drag(7, point(A))
	touch(7, false, point(A))
	check(hits.is_empty(), "drag from UI into board never starts aiming")
	fresh()
	board.scale = Vector2(0.8, 0.9)
	touch(7, true, point(A))
	drag(7, point(B))
	touch(7, false, point(B))
	check(hits == [B], "viewport touch coordinates follow board canvas transform")
	board.queue_free()
	await process_frame
	# One small invariant for the unchanged production platform gate.
	board = load("res://scripts/desktop_board_view.gd").new()
	board.position = Vector2(40, 100)
	board.size = Vector2(400, 680)
	board.logic = BoardLogic.new()
	board.logic.load_cells(4, 6, cells)
	board.slot_pressed.connect(func(slot): hits.append(slot))
	root.add_child(board)
	board.interactive = true
	hits.clear()
	mouse(true, point(A), false)
	check(hits == [A], "non-Android mouse still hits on press")
	mouse(false, point(A), false)
	check(hits == [A], "non-Android release does not add a hit")
	print("ANDROID_TOUCH ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
