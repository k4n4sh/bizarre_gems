extends RefCounted
## Deterministic practice boards. Flow stays in main.gd; strikes use BoardLogic/ScoreKeeper.

const STEPS := ["empty", "rays", "vertical", "free", "cross", "miss", "streak", "timeout", "special",
	"double", "color", "shine", "classic", "joker", "box", "link", "chameleon", "run", "clear", "clock"]
const CENTER := Vector2i(2, 2)
const OPENING := "1.1.2.....3.3.2.....4..4."

static func goal(id: String) -> int:
	return {"streak": 9, "timeout": 2, "special": 6, "double": 2, "color": 3,
		"box": 2, "chameleon": 4, "clear": 4}.get(id, 1)

static func run_rules(id: String) -> bool:
	return id in ["joker", "box", "link", "chameleon", "run", "clear"]

static func target(id: String, hit: int) -> Vector2i:
	match id:
		"empty": return Vector2i(1, 0)
		"rays": return Vector2i(1, 2)
		"vertical": return Vector2i(4, 1)
		"free": return Vector2i(-1, -1)
		"streak", "timeout", "special": return Vector2i(2, 1) if hit % 2 == 1 else CENTER
		"color": return Vector2i(2, 1) if hit == 1 else CENTER
		"chameleon": return Vector2i(2, 4) if hit == 3 else Vector2i(2, 1)
	return CENTER

static func load_board(logic: BoardLogic, id: String, hit := 0) -> void:
	var cham_kind := logic.kind_at(Vector2i(1, 4)) if id == "chameleon" and hit > 0 else 0
	var cells := PackedInt32Array()
	cells.resize(25)
	cells.fill(BoardLogic.EMPTY)
	if id in ["empty", "rays", "vertical", "free"]:
		for i in OPENING.length():
			cells[i] = -1 if OPENING[i] == "." else int(OPENING[i]) - 1
		logic.load_cells(5, 5, cells)
		logic.solution.clear()
		logic.solution_groups.clear()
		# Replaying any opening lesson reconstructs its exact prerequisite removals.
		var prior := STEPS.find(id)
		for i in prior:
			logic.remove(logic.matches_from(target(STEPS[i], 0)))
		return
	var at := target(id, hit)
	var colors: Array[int] = [hit % 4, hit % 4]
	if id == "special":
		if hit not in [1, 3]:
			colors.append(hit % 4)
	elif id == "classic":
		colors = [0, 0, 0]
	elif id == "cross":
		colors = [0, 0, 1, 1]
	elif id == "miss":
		colors = [0, 1, 2, 3]
	elif id == "joker":
		colors = [0, BoardLogic.JOKER]
	elif id == "color":
		colors = [0, 0]
	elif id == "chameleon":
		at = Vector2i(2, 1)
		colors = [2, 2]
	for i in colors.size():
		var p: Vector2i = at + BoardLogic.DIRS[i]
		cells[p.y * 5 + p.x] = colors[i]
	if id == "double":
		cells[10] = 1
		cells[14] = 1
	elif id in ["classic", "run"]:
		cells[0] = 5  # A stranded gem: no move does not mean an empty board.
	elif id == "chameleon":
		cells[21] = 0
		cells[23] = 1
	logic.load_cells(5, 5, cells)
	logic.solution.clear()
	logic.solution_groups.clear()
	if id == "shine":
		logic.shine[13] = 1
	elif id == "box":
		logic.hp[11] = 2
		logic.hp[13] = 2
	elif id == "link":
		logic.cells[0] = 3
		logic.chain[13] = 0
		logic.chain[0] = 13
	elif id == "chameleon":
		logic.cham[21] = 1
		logic.cells[21] = cham_kind  # Retain the result of the real obstacle tick.
