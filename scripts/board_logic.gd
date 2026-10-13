class_name BoardLogic
extends RefCounted
## Pure game rules, no rendering. A board is a grid of gem kinds; EMPTY marks a free slot.
##
## A move is a press on an empty slot. From there the first gem in each of the four
## directions is taken; every kind that appears at least twice among them is knocked out.

const KINDS := 10
const PER_KIND := 27
const LONG := 23
const SHORT := 15
const EMPTY := -1
const JOKER := 99  ## wild gem: joins whichever kind is most common among a strike's hits
const SHINING := 8  ## gems with a bonus on them at the start of a game
## Game modes. Classic is the original game: 270 gems, a wide 23x15 board on desktops (tall
## on phones), and the round ends when no moves are left. Bright is the toy-style mode: fewer,
## bigger tiles, a fresh board whenever moves run out. Each has its own leaderboard.
const CLASSIC := {"id": "classic", "skin": "classic", "kind": "classic", "kinds": 10, "per_kind": 27, "cols": 23,
	"rows": 15, "slots": 345, "shining": 8, "board": "score", "waves": false}
const BRIGHT := {"id": "bright", "skin": "bright", "kind": "run", "kinds": 6, "per_kind": 28, "cols": 10, "rows": 20,
	"slots": 200, "shining": 6, "board": "score_bright", "waves": true}
## Level map: each level is one fixed, fully solvable board scored with 1-3 stars.
const LEVELS := {"id": "levels", "skin": "bright", "kind": "levels", "kinds": 6, "per_kind": 14, "cols": 7, "rows": 15,
	"slots": 108, "shining": 2, "board": "", "waves": false}
## Puzzle: a small board and just enough strikes to clear it.
const PUZZLE := {"id": "puzzle", "skin": "bright", "kind": "puzzle", "kinds": 4, "per_kind": 6, "cols": 6, "rows": 8,
	"slots": 48, "shining": 0, "board": "", "waves": false}
## First-run tutorial on a small hand-made board.
const TUTORIAL := {"id": "tutorial", "skin": "bright", "kind": "tutorial", "kinds": 4, "per_kind": 2, "cols": 5, "rows": 5,
	"slots": 25, "shining": 0, "board": "", "waves": false}
## No timer: a budget of strikes instead; new boards add strikes.
const ZEN := {"id": "zen", "skin": "bright", "kind": "zen", "kinds": 6, "per_kind": 14, "cols": 7, "rows": 15,
	"slots": 108, "shining": 2, "board": "score_zen", "waves": true}
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var cols := LONG
var rows := SHORT
var cells := PackedInt32Array()
var shine := PackedByteArray()  ## 1 where the gem is a shining (bonus) gem
## For boards built by setup_solvable: strike slots in placement order. Playing them in
## reverse order knocks out every gem on the board.
var solution: Array[Vector2i] = []
## Gems each solution strike takes (same order as `solution`), used by the hint.
var solution_groups: Array = []
## Hits a gem needs: 1 normally, 2 for a box (the first hit only cracks it).
var hp := PackedByteArray()
## Chain gems come in pairs: knocking one out also knocks out its partner (index), else -1.
var chain := PackedInt32Array()
## Frozen gems (1): they block like any gem but never match; knocking out a neighbour thaws them.
var ice := PackedByteArray()
## Bombs: strikes left before the bomb on that gem goes off (0 = no bomb). Knocking the gem
## out defuses it.
var bomb := PackedByteArray()
## Chameleons (1): the gem shifts to the next kind every few strikes.
var cham := PackedByteArray()
## Frozen gems the last remove() thawed, for the view.
var last_thawed: Array[Vector2i] = []


func _reset_extras() -> void:
	for a in ["ice", "bomb", "cham"]:
		var b := PackedByteArray()
		b.resize(cells.size())
		set(a, b)


func setup(c: int, r: int, rng: RandomNumberGenerator, shining := SHINING, kinds := KINDS, per_kind := PER_KIND) -> void:
	cols = c
	rows = r
	var bag := PackedInt32Array()
	for k in kinds:
		for i in per_kind:
			bag.append(k)
	while bag.size() < cols * rows:
		bag.append(EMPTY)
	_shuffle(bag, rng)
	cells = bag
	shine = PackedByteArray()
	shine.resize(cells.size())
	hp = PackedByteArray()
	hp.resize(cells.size())
	hp.fill(1)
	chain = PackedInt32Array()
	chain.resize(cells.size())
	chain.fill(-1)
	_reset_extras()
	solution.clear()
	solution_groups.clear()
	var gem_slots: Array[int] = []
	for i in cells.size():
		if cells[i] != EMPTY:
			gem_slots.append(i)
	for n in mini(shining, gem_slots.size()):
		var j := rng.randi_range(n, gem_slots.size() - 1)
		var t := gem_slots[n]
		gem_slots[n] = gem_slots[j]
		gem_slots[j] = t
		shine[gem_slots[n]] = 1


func load_cells(c: int, r: int, data: PackedInt32Array) -> void:
	cols = c
	rows = r
	cells = data.duplicate()
	shine = PackedByteArray()
	shine.resize(cells.size())
	hp = PackedByteArray()
	hp.resize(cells.size())
	hp.fill(1)
	chain = PackedInt32Array()
	chain.resize(cells.size())
	chain.fill(-1)
	_reset_extras()


func kind_at(p: Vector2i) -> int:
	return cells[p.y * cols + p.x]


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < cols and p.y < rows


func is_empty(p: Vector2i) -> bool:
	return kind_at(p) == EMPTY


## First gem met in each direction from p (up to four positions).
func hits_from(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		var q := p + d
		while in_bounds(q) and kind_at(q) == EMPTY:
			q += d
		if in_bounds(q):
			out.append(q)
	return out


## Positions that a press on p would knock out. Empty when the press is a miss.
func matches_from(p: Vector2i) -> Array[Vector2i]:
	var hits: Array[Vector2i] = []
	for h in hits_from(p):
		if not is_frozen(h):
			hits.append(h)  # a frozen gem blocks the way but never matches
	var count := {}
	var jokers := 0
	for h in hits:
		var k := kind_at(h)
		if k == JOKER:
			jokers += 1
		else:
			count[k] = count.get(k, 0) + 1
	# jokers join the most common kind among the hits (the first one on a tie)
	var join := _joker_join_kind(count)
	if join >= 0:
		count[join] += jokers
	var out: Array[Vector2i] = []
	for h in hits:
		var k := kind_at(h)
		if k == JOKER:
			if (join >= 0 and count[join] >= 2) or (join < 0 and jokers >= 2):
				out.append(h)
		elif count[k] >= 2:
			out.append(h)
	return out


## Read before removal. Uses the same ray order and tie rule as matches_from().
## This effective color is only for Color Chain; stored joker kinds remain unchanged.
func joker_match_kind(p: Vector2i) -> int:
	var count := {}
	for h in hits_from(p):
		var kind := kind_at(h)
		if not is_frozen(h) and kind != JOKER:
			count[kind] = int(count.get(kind, 0)) + 1
	return _joker_join_kind(count)


static func _joker_join_kind(count: Dictionary) -> int:
	var join := EMPTY
	for kind in count:
		if join < 0 or count[kind] > count[join]:
			join = kind
	return join


func is_frozen(p: Vector2i) -> bool:
	return ice.size() > 0 and ice[p.y * cols + p.x] == 1


func bomb_at(p: Vector2i) -> int:
	return bomb[p.y * cols + p.x] if bomb.size() > 0 else 0


func is_chameleon(p: Vector2i) -> bool:
	return cham.size() > 0 and cham[p.y * cols + p.x] == 1


func is_box(p: Vector2i) -> bool:
	return hp.size() > 0 and hp[p.y * cols + p.x] >= 2


## The gems of `ps` that a strike actually removes (boxes only crack).
func vanishing(ps: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in ps:
		if not is_box(q):
			out.append(q)
	return out


func is_shining(p: Vector2i) -> bool:
	return shine[p.y * cols + p.x] == 1


func shining_count(ps: Array[Vector2i]) -> int:
	var n := 0
	for p in ps:
		if is_shining(p):
			n += 1
	return n


## Remove a strike's gems. Boxes only crack; a chain gem pulls its partner out with it.
## Returns unique positions actually removed through chains, excluding the direct strike.
func remove(ps: Array[Vector2i]) -> Array[Vector2i]:
	var extra: Array[Vector2i] = []
	var queue: Array[Vector2i] = ps.duplicate()
	var seen := {}
	last_thawed.clear()
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		var i := p.y * cols + p.x
		if seen.has(i) or cells[i] == EMPTY:
			continue
		seen[i] = true
		if hp.size() > i and hp[i] >= 2:
			hp[i] -= 1  # a box cracks and stays
			continue
		cells[i] = EMPTY
		if not (p in ps):
			extra.append(p)
		shine[i] = 0
		if ice.size() > i:
			bomb[i] = 0
			cham[i] = 0
			for d in DIRS:
				var q := p + d
				if in_bounds(q) and ice[q.y * cols + q.x] == 1:
					ice[q.y * cols + q.x] = 0
					last_thawed.append(q)
		if chain.size() > i and chain[i] >= 0:
			var j := chain[i]
			chain[i] = -1
			if chain[j] == i:
				chain[j] = -1
			if cells[j] != EMPTY:
				var q := Vector2i(j % cols, j / cols)
				queue.append(q)
	return extra


func has_any_move() -> bool:
	for y in rows:
		for x in cols:
			var p := Vector2i(x, y)
			if is_empty(p) and not matches_from(p).is_empty():
				return true
	return false


func find_move() -> Vector2i:
	for y in rows:
		for x in cols:
			var p := Vector2i(x, y)
			if is_empty(p) and not matches_from(p).is_empty():
				return p
	return Vector2i(-1, -1)


## How many empty slots are a valid move right now.
func count_moves() -> int:
	var n := 0
	for y in rows:
		for x in cols:
			var p := Vector2i(x, y)
			if is_empty(p) and not matches_from(p).is_empty():
				n += 1
	return n


## Gems in the square of side 2r+1 around p (the bomb booster).
func area(p: Vector2i, r := 1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := p + Vector2i(dx, dy)
			if in_bounds(q) and not is_empty(q):
				out.append(q)
	return out


## Bright mode level: the board grows and gains kinds as levels go up.
static func bright_level(level: int) -> Dictionary:
	var lv := maxi(level, 1)
	var boss := lv % 10 == 0  # every tenth level is a boss: bigger, with more special gems
	var slots := mini(36 + (lv - 1) * 12, 120) + (30 if boss else 0)
	var kinds := 4 if lv <= 2 else (5 if lv <= 4 else 6)
	# early boards are airier (more empty slots = more possible moves), later ones fill up
	var density := minf(0.6 + 0.03 * (lv - 1), 0.78)
	var per_kind := maxi(2, int(round(slots * density)) / kinds)
	# early levels promise many opening moves; from level 8 the deal leans stingy
	var min_moves := maxi(2, 10 - (lv - 1) * 2)
	# no upper cap: solvable boards almost never open with few moves, and chasing that made
	# late deals take seconds; difficulty comes from size, kinds, density, boxes and jokers
	var max_moves := 999
	var lvd := {"slots": slots, "kinds": kinds, "per_kind": per_kind, "min_moves": min_moves, "max_moves": max_moves,
		"tries": 15,
		"jokers": (0.35 if boss else 0.25) if lv >= 6 else 0.0,
		"boxes": 6 if boss else clampi(lv - 6, 0, 6),
		"chains": (2 if boss else 0) + (mini(1 + (lv - 8) / 2, 4) if lv >= 8 else 0),
		"boss": boss,
		# some levels also ask to knock out every gem of one kind (index into the level's kinds)
		"goal_kind": (lv * 7) % kinds if lv >= 5 and lv % 3 == 2 else -1}
	# obstacles come in one by one: ice from 12, bombs from 16, chameleons from 25
	var ch := chapter_of(lv)
	lvd.ice = clampi((lv - 9) / 3, 0, 5) if lv >= 12 else 0
	lvd.bombs = mini(1 + (lv - 16) / 8, 3) if lv >= 16 else 0
	lvd.bomb_moves = maxi(6, 10 - (lv - 16) / 10)
	lvd.chameleons = mini(1 + (lv - 25) / 10, 3) if lv >= 25 else 0
	lvd.chapter = ch
	lvd.rule = ""
	if boss:
		# each chapter's bosses bend the rules their own way
		lvd.rule = CHAPTER_RULES[ch % CHAPTER_RULES.size()]
		match lvd.rule:
			"boxes":
				lvd.boxes += 6
			"ice":
				lvd.ice += 8
			"bombs":
				lvd.bombs += 3
				lvd.bomb_moves = 7
			"chains":
				lvd.chains += 4
			"chameleons":
				lvd.chameleons += 4
	return lvd


## Levels come in chapters of 20; chapter c (from 0) has its own backdrop and boss rule.
const CHAPTER_SIZE := 20
const CHAPTER_RULES := ["boxes", "ice", "bombs", "chains", "chameleons"]


static func chapter_of(level: int) -> int:
	return (maxi(level, 1) - 1) / CHAPTER_SIZE


## Build a board that can be cleared completely by the cross rule alone. It is made
## backwards from an empty grid: each step picks an empty strike slot and puts 2-4 gems of
## one kind where that strike would hit first, making sure the strike would take exactly
## those gems. Undoing the steps in reverse order is then a full solution.
func setup_solvable(c: int, r: int, rng: RandomNumberGenerator, shining: int, kinds: int, gems: int,
		joker_rate := 0.0, boxes := 0) -> int:
	cols = c
	rows = r
	cells = PackedInt32Array()
	cells.resize(c * r)
	cells.fill(EMPTY)
	shine = PackedByteArray()
	shine.resize(c * r)
	hp = PackedByteArray()
	hp.resize(c * r)
	hp.fill(1)
	chain = PackedInt32Array()
	chain.resize(c * r)
	chain.fill(-1)
	_reset_extras()
	solution.clear()
	solution_groups.clear()
	var used := PackedInt32Array()
	used.resize(kinds)
	var placed := 0
	var boxed := 0
	var fails := 0
	while placed < gems and fails < 3000:
		# now and then, turn an existing gem into a box: a strike that hits it first cracks it
		if boxed < boxes and placed >= 4 and rng.randf() < 0.3:
			if _try_box_step(rng, gems - placed):
				boxed += 1
				placed = gems_left_count()
				continue
		var p := Vector2i(rng.randi_range(0, c - 1), rng.randi_range(0, r - 1))
		if not is_empty(p):
			fails += 1
			continue
		var rays := _rays(p)
		var open_dirs: Array[int] = []
		for d in 4:
			if not rays.cands[d].is_empty():
				open_dirs.append(d)
		if open_dirs.size() < 2:
			fails += 1
			continue
		var roll := rng.randf()
		var want := 4 if roll < 0.06 else (3 if roll < 0.25 else 2)
		if joker_rate > 0.0 and rng.randf() < joker_rate:
			want = maxi(want, 3)  # a joker only ever completes a group of 3+
		want = mini(mini(want, open_dirs.size()), gems - placed)
		if want < 2:
			break
		_shuffle_ints(open_dirs, rng)
		var chosen := open_dirs.slice(0, want)
		var others := _other_hits(rays.hits, chosen)
		if others.has(-1):
			fails += 1
			continue
		var kind := -1
		for k in kinds:
			if not (k in others) and (kind < 0 or used[k] < used[kind]):
				kind = k
		if kind < 0:
			fails += 1
			continue
		var group: Array[Vector2i] = []
		for d in chosen:
			var ray: Array = rays.cands[d]
			var pos: Vector2i = ray[rng.randi_range(0, ray.size() - 1)]
			cells[pos.y * cols + pos.x] = kind
			group.append(pos)
		if want >= 3 and joker_rate > 0.0 and rng.randf() < joker_rate:
			var jpos: Vector2i = group[rng.randi_range(0, group.size() - 1)]
			cells[jpos.y * cols + jpos.x] = JOKER
		used[kind] += want
		placed += want
		solution.append(p)
		solution_groups.append(group)
	var gem_slots: Array[int] = []
	for i2 in cells.size():
		if cells[i2] != EMPTY and cells[i2] != JOKER and hp[i2] < 2:
			gem_slots.append(i2)
	for n in mini(shining, gem_slots.size()):
		var j2 := rng.randi_range(n, gem_slots.size() - 1)
		var t := gem_slots[n]
		gem_slots[n] = gem_slots[j2]
		gem_slots[j2] = t
		shine[gem_slots[n]] = 1
	return gems_left_count()


## Empty slots in front of the first gem in each direction from p, and that gem's kind
## (-2 at the board edge).
func _rays(p: Vector2i) -> Dictionary:
	var cands: Array = []
	var hits: Array[int] = []
	for d in DIRS:
		var q := p + d
		var ray: Array[Vector2i] = []
		while in_bounds(q) and is_empty(q):
			ray.append(q)
			q += d
		cands.append(ray)
		hits.append(kind_at(q) if in_bounds(q) else -2)
	return {"cands": cands, "hits": hits}


## Kinds of the first gems in the directions not chosen. A strike must take only the chosen
## gems, so these may not pair up with each other or contain a joker; returns [-1] if they do.
func _other_hits(hits: Array[int], chosen: Array) -> Array[int]:
	var others: Array[int] = []
	for d in 4:
		if not (d in chosen) and hits[d] >= 0:
			if hits[d] == JOKER or hits[d] in others:
				return [-1]
			others.append(hits[d])
	return others


## Make an existing gem X a box: find an empty strike slot whose first hit in one direction
## is X and add gems of X's kind in other directions, so that strike cracks X.
func _try_box_step(rng: RandomNumberGenerator, budget: int) -> bool:
	var gems_at: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			var q := Vector2i(x, y)
			if not is_empty(q) and kind_at(q) != JOKER and hp[y * cols + x] < 2:
				gems_at.append(q)
	if gems_at.is_empty() or budget < 1:
		return false
	var xpos: Vector2i = gems_at[rng.randi_range(0, gems_at.size() - 1)]
	var kind := kind_at(xpos)
	for attempt in 8:
		var d := rng.randi_range(0, 3)
		var p := xpos - DIRS[d] * rng.randi_range(1, maxi(cols, rows))
		if not in_bounds(p) or not is_empty(p):
			continue
		var rays := _rays(p)
		if rays.hits[d] != kind or rays.cands[d].size() != absi((xpos - p).x) + absi((xpos - p).y) - 1:
			continue  # X must be the first gem that way
		var open_dirs: Array[int] = []
		for e in 4:
			if e != d and not rays.cands[e].is_empty():
				open_dirs.append(e)
		if open_dirs.is_empty():
			continue
		_shuffle_ints(open_dirs, rng)
		var chosen := open_dirs.slice(0, mini(1 + rng.randi_range(0, 1), mini(open_dirs.size(), budget)))
		var all_chosen := chosen.duplicate()
		all_chosen.append(d)
		var others := _other_hits(rays.hits, all_chosen)
		if others.has(-1) or kind in others:
			continue
		var group: Array[Vector2i] = [xpos]
		for e in chosen:
			var ray: Array = rays.cands[e]
			var pos: Vector2i = ray[rng.randi_range(0, ray.size() - 1)]
			cells[pos.y * cols + pos.x] = kind
			group.append(pos)
		hp[xpos.y * cols + xpos.x] = 2
		solution.append(p)
		solution_groups.append(group)
		return true
	return false


func gems_left_count() -> int:
	return gems_left()


static func _shuffle_ints(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## The next strike of the stored solution that is still exactly valid on the current board
## (its slot is empty and it takes exactly its recorded gems), or (-1, -1).
func next_solution_move() -> Vector2i:
	for i in range(solution.size() - 1, -1, -1):
		var p: Vector2i = solution[i]
		if not in_bounds(p) or not is_empty(p):
			continue
		var want: Array = solution_groups[i]
		var got := matches_from(p)
		if got.size() != want.size():
			continue
		var same := true
		for q in want:
			same = same and q in got
		if same:
			return p
	return Vector2i(-1, -1)


## Puzzle n: a small board meant to be cleared in a counted number of strikes.
static func puzzle_config(n: int) -> Dictionary:
	var k := 3 if n < 5 else (4 if n < 12 else 5)
	var slots := mini(30 + n * 2, 80)
	return {"slots": slots, "kinds": k, "per_kind": maxi(2, int(round(slots * 0.7)) / k), "min_moves": 2,
		"max_moves": 999, "tries": 15, "jokers": 0.2 if n >= 10 else 0.0, "boxes": 1 if n >= 15 else 0,
		"chains": 1 if n >= 20 else 0, "boss": false, "goal_kind": -1, "ice": (1 if n < 14 else 2) if n >= 8 else 0,
		"bombs": 0, "bomb_moves": 0, "chameleons": 0, "chapter": 0, "rule": ""}


## Deal repeatedly and keep the first layout whose number of opening moves falls in
## [min_moves, max_moves]; if none does in `tries`, keep the closest one. Returns its moves.
func setup_tuned(c: int, r: int, rng: RandomNumberGenerator, shining: int, kinds: int, per_kind: int,
		min_moves: int, max_moves := 999, tries := 40, solvable := false, joker_rate := 0.0, boxes := 0) -> int:
	var best_cells := PackedInt32Array()
	var best_shine := PackedByteArray()
	var best_hp := PackedByteArray()
	var best_groups: Array = []
	var best_solution: Array[Vector2i] = []
	var best_gap := 1 << 30
	var best_moves := 0
	for t in tries:
		if solvable:
			setup_solvable(c, r, rng, shining, kinds, kinds * per_kind, joker_rate, boxes)
		else:
			setup(c, r, rng, shining, kinds, per_kind)
		var m := count_moves()
		if m >= min_moves and m <= max_moves:
			return m
		var gap := (min_moves - m) if m < min_moves else (m - max_moves)
		if gap < best_gap:
			best_gap = gap
			best_cells = cells.duplicate()
			best_shine = shine.duplicate()
			best_solution = solution.duplicate()
			best_groups = solution_groups.duplicate(true)
			best_hp = hp.duplicate()
			best_moves = m
	cells = best_cells
	shine = best_shine
	hp = best_hp
	solution = best_solution
	solution_groups = best_groups
	return best_moves


func clone() -> BoardLogic:
	var b := BoardLogic.new()
	b.cols = cols
	b.rows = rows
	b.cells = cells.duplicate()
	b.shine = shine.duplicate()
	b.hp = hp.duplicate()
	b.chain = chain.duplicate()
	b.ice = ice.duplicate()
	b.bomb = bomb.duplicate()
	b.cham = cham.duplicate()
	b.solution = solution.duplicate()
	b.solution_groups = solution_groups.duplicate(true)
	return b


## True if playing the stored solution in reverse order (with all the real rules: boxes,
## jokers, chains) knocks out every gem.
func replay_clears() -> bool:
	var b := clone()
	for i in range(b.solution.size() - 1, -1, -1):
		var p: Vector2i = b.solution[i]
		if not b.is_empty(p):
			continue  # its gems already went with a chain partner earlier
		var g := b.matches_from(p)
		if not g.is_empty():
			b.remove(g)
	return b.gems_left() == 0


## Link up to `pairs` pairs of same-kind gems into chains, keeping only links that leave the
## board fully clearable by its solution.
func add_chains(rng: RandomNumberGenerator, pairs: int) -> int:
	var made := 0
	for attempt in pairs * 6:
		if made >= pairs:
			break
		var by_kind := {}
		for i in cells.size():
			if cells[i] >= 0 and cells[i] != JOKER and hp[i] < 2 and chain[i] < 0:
				if not by_kind.has(cells[i]):
					by_kind[cells[i]] = []
				by_kind[cells[i]].append(i)
		var ks := by_kind.keys().filter(func(k): return by_kind[k].size() >= 2)
		if ks.is_empty():
			break
		var list: Array = by_kind[ks[rng.randi_range(0, ks.size() - 1)]]
		var a: int = list[rng.randi_range(0, list.size() - 1)]
		var b2: int = list[rng.randi_range(0, list.size() - 1)]
		if a == b2:
			continue
		chain[a] = b2
		chain[b2] = a
		if replay_clears():
			made += 1
		else:
			chain[a] = -1
			chain[b2] = -1
	return made


## Freeze up to n gems, keeping only freezes that leave the board clearable by its solution.
func add_ice(rng: RandomNumberGenerator, n: int) -> int:
	var made := 0
	for attempt in n * 6:
		if made >= n:
			break
		var i := _random_plain_gem(rng)
		if i < 0:
			break
		ice[i] = 1
		if replay_clears():
			made += 1
		else:
			ice[i] = 0
	return made


## Put bombs on up to n gems, each going off after `moves` strikes.
func add_bombs(rng: RandomNumberGenerator, n: int, moves: int) -> int:
	var made := 0
	for attempt in n * 4:
		if made >= n:
			break
		var i := _random_plain_gem(rng)
		if i >= 0:
			bomb[i] = moves
			made += 1
	return made


func add_chameleons(rng: RandomNumberGenerator, n: int) -> int:
	var made := 0
	for attempt in n * 4:
		if made >= n:
			break
		var i := _random_plain_gem(rng)
		if i >= 0:
			cham[i] = 1
			made += 1
	return made


## A gem with nothing special on it (not a joker, box, chain, ice, bomb or chameleon), or -1.
func _random_plain_gem(rng: RandomNumberGenerator) -> int:
	var list: Array[int] = []
	for i in cells.size():
		if cells[i] >= 0 and cells[i] != JOKER and hp[i] < 2 and chain[i] < 0 and ice[i] == 0 and bomb[i] == 0 and cham[i] == 0:
			list.append(i)
	return list[rng.randi_range(0, list.size() - 1)] if not list.is_empty() else -1


## One strike passed: every bomb ticks down. Returns the positions of bombs that went off.
func tick_bombs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in bomb.size():
		if bomb[i] > 0 and cells[i] != EMPTY:
			bomb[i] -= 1
			if bomb[i] == 0:
				out.append(Vector2i(i % cols, i / cols))
	return out


func has_bombs() -> bool:
	for v in bomb:
		if v > 0:
			return true
	return false


func has_chameleons() -> bool:
	for i in cham.size():
		if cham[i] == 1 and cells[i] != EMPTY:
			return true
	return false


## Chameleons step to the next kind. Returns the gems that changed.
func shift_chameleons(kinds: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in cham.size():
		if cham[i] == 1 and cells[i] >= 0 and cells[i] != JOKER:
			cells[i] = (cells[i] + 1) % kinds
			out.append(Vector2i(i % cols, i / cols))
	return out


func count_kind(k: int) -> int:
	var n := 0
	for v in cells:
		if v == k:
			n += 1
	return n


func gems_left() -> int:
	var n := 0
	for k in cells:
		if k != EMPTY:
			n += 1
	return n


## Swap rows and columns. The cross rule is symmetric, so every move stays valid.
func transpose() -> void:
	var out := PackedInt32Array()
	out.resize(cells.size())
	var sh := PackedByteArray()
	sh.resize(cells.size())
	var hh := PackedByteArray()
	hh.resize(cells.size())
	for y in rows:
		for x in cols:
			out[x * rows + y] = cells[y * cols + x]
			sh[x * rows + y] = shine[y * cols + x]
			hh[x * rows + y] = hp[y * cols + x] if hp.size() == cells.size() else 1
	var ch := PackedInt32Array()
	ch.resize(cells.size())
	ch.fill(-1)
	if chain.size() == cells.size():
		for y in rows:
			for x in cols:
				var j0 := chain[y * cols + x]
				if j0 >= 0:
					ch[x * rows + y] = (j0 % cols) * rows + (j0 / cols)
	shine = sh
	hp = hh
	chain = ch
	for a in ["ice", "bomb", "cham"]:
		var src: PackedByteArray = get(a)
		if src.size() == cells.size():
			var dst := PackedByteArray()
			dst.resize(cells.size())
			for y in rows:
				for x in cols:
					dst[x * rows + y] = src[y * cols + x]
			set(a, dst)
	# the cross rule doesn't care about orientation, so the solution just turns with the board
	for i in solution.size():
		solution[i] = Vector2i(solution[i].y, solution[i].x)
	for g in solution_groups:
		for j in g.size():
			g[j] = Vector2i(g[j].y, g[j].x)
	var c := cols
	cols = rows
	rows = c
	cells = out


## Re-deal the remaining gems over the whole board until at least one move exists.
func shuffle_remaining(rng: RandomNumberGenerator) -> void:
	if chain.size() == cells.size():
		chain.fill(-1)  # chains don't survive a reshuffle
	for attempt in 30:
		# shuffle gems and their shine flags with the same permutation
		for i in range(cells.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t := cells[i]
			cells[i] = cells[j]
			cells[j] = t
			var u := shine[i]
			shine[i] = shine[j]
			shine[j] = u
			if hp.size() == cells.size():
				var w := hp[i]
				hp[i] = hp[j]
				hp[j] = w
			if ice.size() == cells.size():
				var v1 := ice[i]
				ice[i] = ice[j]
				ice[j] = v1
				var v2 := bomb[i]
				bomb[i] = bomb[j]
				bomb[j] = v2
				var v3 := cham[i]
				cham[i] = cham[j]
				cham[j] = v3
		if has_any_move():
			return


## Grid shape that gives the biggest cells in the given area for about `slots` slots
## (within -8%..+8%). The gem count is fixed by the mode; only the shape changes.
static func best_dims(area: Vector2, slots := 345) -> Vector2i:
	var fallback := Vector2i(LONG, SHORT) if slots >= 300 else Vector2i(7, 15)
	if area.x <= 0.0 or area.y <= 0.0:
		return fallback
	var lo := int(slots * 0.92)
	var hi := int(slots * 1.08)
	var best := fallback
	var best_cell := -1.0
	for c in range(5, 40):
		for r in [floori(float(slots) / c), ceili(float(slots) / c)]:
			var n: int = c * r
			if r < 5 or n < lo or n > hi:
				continue
			var cell := minf(area.x / c, area.y / r)
			var closer := absi(n - slots) < absi(best.x * best.y - slots)
			if cell > best_cell + 0.01 or (absf(cell - best_cell) <= 0.01 and closer):
				best_cell = cell
				best = Vector2i(c, r)
	return best


static func bonus_for(n: int) -> int:
	if n >= 4:
		return 2
	if n == 3:
		return 1
	return 0


static func points_for(n: int) -> int:
	return n + bonus_for(n)


static func _shuffle(a: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t
