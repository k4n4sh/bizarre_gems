extends Node
var results: Array = []
var completed_seeds := 0
var done := false

func run_all(first_seed := 1, count := 100) -> void:
	for seed_value in range(first_seed, first_seed + count):
		results.append_array(await run_batch(get_tree(), seed_value, 1))
		completed_seeds += 1
	done = true

## Model comparison, not a human-play estimate. Same legal move trace for both rules.
## Attach this Node to the main scene, then call_deferred("run_all", 1, 100).
## Inspect done/completed_seeds/results in later game_eval calls (see README).
## Speeds include initial search; no misses/ads/shuffles. Uses the actual board and keeper.
const SPEEDS := [0.5, 1.0, 2.0, 3.25, 3.75]

func run_batch(tree: SceneTree, first_seed: int, count: int) -> Array:
	var rows := []
	for seed_value in range(first_seed, first_seed + count):
		for policy in ["greedy", "random"]:
			var trace := make_trace(seed_value, policy)
			for gap in SPEEDS:
				for timed in [false, true]:
					var row := replay(trace.hits, gap, timed)
					row.merge({"seed": seed_value, "policy": policy, "gap": gap,
						"rules": "timed" if timed else "legacy", "layout": trace.layout,
						"trace_length": trace.hits.size(), "gems_at_stuck": trace.gems_left})
					rows.append(row)
			await tree.process_frame
	return rows

func make_trace(seed_value: int, policy: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var board := BoardLogic.new()
	board.setup(23, 15, rng, BoardLogic.CLASSIC.shining, 10, 27)
	var layout := (str(board.cells) + str(board.shine)).sha256_text()
	var chooser := RandomNumberGenerator.new()
	chooser.seed = seed_value + 100000
	var hits := []
	while true:
		var moves: Array[Vector2i] = []
		var best := -1
		var best_size := 0
		for y in board.rows:
			for x in board.cols:
				var p := Vector2i(x, y)
				if not board.is_empty(p):
					continue
				var n := board.matches_from(p).size()
				if n >= 2:
					moves.append(p)
					if n > best_size:
						best_size = n
						best = moves.size() - 1
		if moves.is_empty():
			break
		var at: Vector2i = moves[best if policy == "greedy" else chooser.randi_range(0, moves.size() - 1)]
		var gone := board.matches_from(at)
		hits.append({"n": gone.size(), "shine": board.shining_count(gone)})
		board.remove(gone)
	return {"layout": layout, "hits": hits, "gems_left": board.gems_left()}

func replay(hits: Array, gap: float, timed: bool) -> Dictionary:
	var k := ScoreKeeper.new()
	k.combo_window = 3.5
	k.timed_special = timed
	var left := 120.0
	var peak := left
	var elapsed := 0.0
	var total_bonus := 0.0
	var destroyed := 0
	var strikes := 0
	var reason := "stuck"
	for hit in hits:
		if left <= gap:
			elapsed += left
			left = 0.0
			k.update(elapsed)
			reason = "time"
			break
		elapsed += gap
		left -= gap
		var result := k.hit(hit.n, elapsed, hit.shine)
		total_bonus += result.time
		left += result.time
		peak = maxf(peak, left)
		destroyed += hit.n
		strikes += 1
	return {"score": k.score, "precise": k.precise_events, "perfect": k.perfect_events,
		"special_points": k.special_bonus_points, "special_seconds": k.special_bonus_time,
		"total_bonus_seconds": total_bonus, "time_left": left, "peak_time": peak,
		"elapsed": elapsed, "destroyed": destroyed, "strikes": strikes, "reason": reason}
