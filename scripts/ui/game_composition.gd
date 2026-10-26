extends Control
## Geometry only: scene-owned HUD/board nodes, independent of game state and generation.
## Preserve refinement's board sizing reservations even when the visible Run header is compact.

const STRIP_GAP := 6.0
const TOP_HEIGHT := 96.0  ## Classic top plates (desktop/web)
const TOP_GAP := 12.0

func arrange_practice(board: BoardView, hud: Hud, card: PanelContainer) -> void:
	if size.x < 1 or size.y < 1: return
	var header := 116.0 if size.x < 680 else 64.0
	hud.position = Vector2.ZERO
	hud.size = size
	hud.layout_practice(Rect2(0,0,size.x,header))
	var area := Vector2(size.x,maxf(1,size.y-header-10))
	var wide := area.x >= 820 and area.x > area.y*1.25
	var width := clampf(area.x*.24,280,320) if wide else minf(area.x,420)
	card.size.x = width
	var height := card.get_combined_minimum_size().y
	card.size.y = height
	var gap := 28.0 if wide else 10.0
	var side := maxf(1,floorf(minf(area.y,area.x-width-gap) if wide else minf(area.x,area.y-height-gap)))
	board.size = Vector2.ONE*side
	if wide:
		var left := floorf((area.x-width-gap-side)*.5)
		card.position = Vector2(left,header+10+floorf((area.y-height)*.5))
		board.position = Vector2(left+width+gap,header+10+floorf((area.y-side)*.5))
	else:
		var top := maxf(0,floorf((area.y-height-gap-side)*.5))
		card.position = Vector2(floorf((area.x-width)*.5),header+10+top)
		board.position = Vector2(floorf((area.x-side)*.5),header+10+top+height+gap)
	board.refresh()

## `strip` (the record bar) sits just above the board frame, in room reserved for it.
func arrange(board: BoardView, hud: Hud, mode_id: String, android: bool,
		view: Vector2, insets: Rect2, strip: Control = null) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var strip_room := strip.custom_minimum_size.y + STRIP_GAP if strip and strip.visible else 0.0
	var sides := mode_id == "classic" and android
	if sides:
		var side_inset := maxf(ceilf(insets.position.x), ceilf(insets.size.x))
		var vertical_inset := maxf(ceilf(insets.position.y), ceilf(insets.size.y))
		var safe_height := view.y - vertical_inset * 2 - 8
		var fit_cell := maxf(8, floorf(minf((view.x-side_inset*4-140-16-6)/BoardLogic.LONG, (safe_height-6)/BoardLogic.SHORT)))
		var board_width := fit_cell * BoardLogic.LONG + 6
		board.position = Vector2(floorf((size.x-board_width)/2), 0)
		board.size = Vector2(board_width, size.y)
		board.refresh()
		hud.position = Vector2.ZERO
		hud.size = size
		hud.layout_sides(board.get_rect(), view, insets)
		_place_strip(strip, board)
		return
	if mode_id == "classic" and hud.plates:
		_arrange_top(board, hud, strip)
		return
	var run := mode_id == "bright"
	var reservation := (148.0 if hud.skin == "bright" else 74.0) + strip_room
	board.position = Vector2(0, reservation)
	board.size = Vector2(size.x, maxf(1, size.y-reservation))
	board.refresh()
	hud.position = Vector2.ZERO
	hud.size = size
	var left := maxf(0, board.origin.x-board.frame_pad)
	var right := minf(size.x, board.origin.x+board.logic.cols*board.cell+board.frame_pad)
	var width := maxf(1, right-left)
	if run and not android:
		var header_height := hud.header_height(width)
		var frame_height := board.logic.rows*board.cell+board.frame_pad*2
		var top := maxf(0, floorf((size.y-header_height-16-strip_room-frame_height)/2))
		board.position.y = top+header_height+16+strip_room-board.origin.y+board.frame_pad
		hud.layout_header(Rect2(left, top, width, header_height))
	elif hud.skin == "bright" and android:
		hud.layout_portrait(Rect2(0, 0, size.x, 138))
	else:
		hud.layout_header(Rect2(left, 0, width, 64))
	_place_strip(strip, board)


## Right above the frame and as wide as it; hidden where the board leaves no room on top.
func _place_strip(strip: Control, board: BoardView) -> void:
	if not strip or not strip.visible:
		return
	if strip is RecordBar: strip.compact = false
	var h := strip.custom_minimum_size.y
	var frame_top := board.position.y+board.origin.y-board.frame_pad
	var left := board.position.x+maxf(0, board.origin.x-board.frame_pad)
	var width := minf(board.logic.cols*board.cell+board.frame_pad*2, size.x-left)
	strip.position = Vector2(left, frame_top-STRIP_GAP-h)
	strip.size = Vector2(maxf(1, width), h)
	strip.modulate.a = 1.0 if strip.position.y >= 0 else 0.0


## Classic on desktop/web: plates right above the field frame, the record bar inside the
## middle plate, and room on both sides for the button columns.
func _arrange_top(board: BoardView, hud: Hud, strip: Control) -> void:
	var plate_h := TOP_HEIGHT
	var room := hud.top_side_room(plate_h)
	board.position = Vector2(room, plate_h + TOP_GAP)
	board.size = Vector2(maxf(1, size.x - room * 2), maxf(1, size.y - plate_h - TOP_GAP))
	board.refresh()
	var frame := Vector2(board.logic.cols, board.logic.rows) * board.cell + Vector2.ONE * board.frame_pad * 2
	var top := maxf(0, floorf((size.y - plate_h - TOP_GAP - frame.y) / 2))
	board.position.y = top + plate_h + TOP_GAP - board.origin.y + board.frame_pad
	var left := board.position.x + board.origin.x - board.frame_pad
	hud.position = Vector2.ZERO
	hud.size = size
	var bar := hud.layout_top(Rect2(left, top, frame.x, plate_h))
	if strip and strip.visible:
		if strip is RecordBar: strip.compact = true
		strip.position = bar.position
		strip.size = bar.size
		strip.modulate.a = 1.0
