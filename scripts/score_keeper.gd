class_name ScoreKeeper
extends RefCounted
## Scoring with combos. Time is game time in seconds (pauses don't count).
##
## Combo: successful strikes in a row, each within combo_window of the previous one.
## A miss or a pause longer than the window resets it. Points are multiplied by the combo tier.
##
## Legacy special combo is consecutive 3+ hits. Classic and Bright Run opt into timed_special:
## 5 seconds per 3+ hit; pairs extend by 0.5 seconds; Perfect ends the cycle.

const COMBO_WINDOW := 3.0  ## Legacy/non-Classic default.
const CLASSIC_COMBO_WINDOW := 3.5
const SPECIAL_WINDOW := 5.0
const PAIR_EXTENSION := 0.5
const PRECISE_MIN := 3
const PRECISE_AT := 3
const PERFECT_AT := 4
const PRECISE_POINTS := 10
const PRECISE_TIME := 3.0
const PERFECT_POINTS := 20
const PERFECT_TIME := 5.0
const SHINE_POINTS := 5
const SHINE_TIME := 2.0
const TIER_TIME := 2.0       ## seconds for reaching a new combo multiplier
const STREAK_EVERY := 10     ## every this many hits in a row...
const STREAK_TIME := 3.0     ## ...give this many seconds
const CLASSIC_TIER_TIME := 1.0
const CLASSIC_STREAK_TIME := 1.0
const DOUBLE_HIT_BONUS := 0.5
const COLOR_STREAK_BONUS := 1.0
const COLOR_STREAK_MIN_GEMS := 2  ## A color must contribute at least a pair to participate.
## combo length -> multiplier (first entry whose length is reached, checked from the top)
const TIERS := [[9, 4], [5, 3], [2, 2], [0, 1]]

## Extra seconds for combos, streaks, precise/perfect combos and shining gems. Bright mode
## turns them off; its time economy comes from completed boards.
var time_bonuses := true
var hit_time_rewards := true  ## Bright Run disables even the basic group seconds.
var tier_time := TIER_TIME
var streak_time := STREAK_TIME
var combo_window := COMBO_WINDOW
var combo_breaks := 0  ## Loss of an established series (2+), by miss or timeout.
var hits_at_x4 := 0    ## Includes the strike that first reaches x4.
var score := 0
var combo := 0
var best_combo := 0
var precise_streak := 0
var precise_count := 0  ## Combined events, retained for existing result UI.
var timed_special := false
## Explicit rule opt-in, independent of the shared rendering skin and special combo.
var classic_bonus_combos := false
var color_streak_kind := BoardLogic.EMPTY
var color_streak_hits := 0  ## Active chain length; no pending progress is shown.
## Only unpaid eligible color portions of the immediately previous successful strike.
var _previous_color_points: Dictionary = {}
var _double_hit_slot := Vector2i(-1, -1)
var precise_events := 0
var perfect_events := 0
var special_bonus_points := 0
var special_bonus_time := 0.0
var _special_deadline := -1.0
var _last_hit := -1000.0


static func multiplier_for(c: int) -> int:
	for t in TIERS:
		if c >= t[0]:
			return t[1]
	return 1


## Ordinary Classic opts in; other modes and explicit experiments keep legacy rewards.
func configure_time_rewards(classic: bool) -> void:
	tier_time = CLASSIC_TIER_TIME if classic else TIER_TIME
	streak_time = CLASSIC_STREAK_TIME if classic else STREAK_TIME


## Share current combo rules; leave other modes and explicit Classic experiments intact.
func configure_combo_rules(classic: bool, run: bool, classic_window := CLASSIC_COMBO_WINDOW, classic_timed := true) -> void:
	combo_window = CLASSIC_COMBO_WINDOW if run else (classic_window if classic else COMBO_WINDOW)
	timed_special = run or (classic and classic_timed)
	classic_bonus_combos = classic or run
	hit_time_rewards = not run


func reset() -> void:
	combo_breaks = 0
	hits_at_x4 = 0
	score = 0
	combo = 0
	best_combo = 0
	precise_streak = 0
	precise_count = 0
	precise_events = 0
	perfect_events = 0
	special_bonus_points = 0
	special_bonus_time = 0.0
	_special_deadline = -1.0
	_last_hit = -1000.0
	reset_bonus_combos()


## Seconds left before the combo expires, 0 when there is no combo.
func window_left(now: float) -> float:
	if combo < 2:
		return 0.0
	return maxf(0.0, combo_window - (now - _last_hit))


## Call every frame. Returns true when the combo just ran out.
func update(now: float) -> bool:
	if combo > 0 and now - _last_hit > combo_window:
		return miss()
	if timed_special and precise_streak > 0 and now >= _special_deadline:
		_reset_special()
	return false


func special_window_left(now: float) -> float:
	return maxf(0.0, _special_deadline - now) if timed_special and precise_streak > 0 else 0.0


func _reset_special() -> void:
	precise_streak = 0
	_special_deadline = -1.0


## Returns true when a running combo (2+) was broken.
func miss() -> bool:
	var had := combo >= 2
	if had:
		combo_breaks += 1
	combo = 0
	_reset_special()
	reset_bonus_combos()
	return had


func reset_bonus_combos() -> void:
	reset_double_hit()
	color_streak_kind = BoardLogic.EMPTY
	color_streak_hits = 0
	_previous_color_points.clear()


## A replacement board invalidates only the pending positional pair.
func reset_double_hit() -> void:
	_double_hit_slot = Vector2i(-1, -1)


## Keep the pending logical slot attached to the same cell when the board turns.
func transpose_bonus_slot() -> void:
	_double_hit_slot = Vector2i(_double_hit_slot.y, _double_hit_slot.x)


## Each color portion can be rewarded once. Other portions of a mixed strike remain
## eligible to start a different chain on the next strike, never on a later one.
func _color_streak_for_hit(ordinary_points: int, removed_kinds: Array[int]) -> Dictionary:
	var counts := {}
	for kind in removed_kinds:
		if kind >= 0 and kind != BoardLogic.JOKER:
			counts[kind] = int(counts.get(kind, 0)) + 1
	var current: Dictionary = {}
	for kind in counts:
		if int(counts[kind]) >= COLOR_STREAK_MIN_GEMS:
			current[kind] = ordinary_points * float(counts[kind]) / removed_kinds.size()
	var reward := 0.0
	var started := false
	if color_streak_hits >= 2 and current.has(color_streak_kind):
		color_streak_hits += 1
		reward = float(current[color_streak_kind])
	else:
		color_streak_kind = BoardLogic.EMPTY
		color_streak_hits = 0
		var best := -1.0
		for kind in current:
			if not _previous_color_points.has(kind):
				continue
			var combined := float(_previous_color_points[kind]) + float(current[kind])
			if combined > best or (combined == best and int(kind) < color_streak_kind):
				best = combined
				color_streak_kind = int(kind)
		if color_streak_kind != BoardLogic.EMPTY:
			color_streak_hits = 2
			reward = best
			started = true
	# Exclude the portion paid now from the next pair, even if the active chain ends.
	current.erase(color_streak_kind)
	_previous_color_points = current
	# Preserve fractional shares of both strikes until the one final rounding.
	return {"points": roundi(reward * COLOR_STREAK_BONUS), "started": started}


## A successful strike that knocked out n gems, `shining` of them shining gems.
## Slot and actually removed kinds are required for Classic bonus combos.
## Bonus points use only ordinary_points, excluding special/shining/other rewards.
func hit(n: int, now: float, shining := 0, slot := Vector2i(-1, -1), removed_kinds: Array[int] = []) -> Dictionary:
	update(now)  # Expire both clocks before a hit can refresh or extend them.
	var old_mult := multiplier_for(combo)
	combo += 1
	best_combo = maxi(best_combo, combo)
	_last_hit = now
	var mult := multiplier_for(combo)
	if mult == 4:
		hits_at_x4 += 1
	var ordinary_points := BoardLogic.points_for(n) * mult
	var points := ordinary_points
	var time := float(BoardLogic.bonus_for(n))
	var event := ""
	if n >= PRECISE_MIN:
		precise_streak += 1
		if timed_special:
			_special_deadline = now + SPECIAL_WINDOW
		if precise_streak >= PERFECT_AT:
			event = "perfect"
			points += PERFECT_POINTS
			time += PERFECT_TIME
			perfect_events += 1
			special_bonus_points += PERFECT_POINTS
			if time_bonuses:
				special_bonus_time += PERFECT_TIME
			if timed_special:
				_reset_special()
		elif precise_streak == PRECISE_AT:
			event = "precise"
			points += PRECISE_POINTS
			time += PRECISE_TIME
			precise_events += 1
			special_bonus_points += PRECISE_POINTS
			if time_bonuses:
				special_bonus_time += PRECISE_TIME
		if event != "":
			precise_count += 1
	elif timed_special:
		if n == 2 and precise_streak > 0:
			_special_deadline += PAIR_EXTENSION  # Deliberately uncapped; never revives an expired series.
	else:
		precise_streak = 0
	points += shining * SHINE_POINTS
	time += shining * SHINE_TIME
	if mult > old_mult and mult > 1:
		time += tier_time
	if combo % STREAK_EVERY == 0:
		time += streak_time
	if not time_bonuses:
		time = float(BoardLogic.bonus_for(n))  # only the basic +1 s / +2 s for 3 / 4 gems
	if not hit_time_rewards:
		time = 0.0
	var double_hit_points := 0
	var color_streak_points := 0
	var color_streak_started := false
	if classic_bonus_combos:
		if slot.x >= 0 and slot.y >= 0 and not removed_kinds.is_empty():
			if slot == _double_hit_slot:
				# All score bonuses round to nearest integer; positive halves round up.
				double_hit_points = roundi(ordinary_points * DOUBLE_HIT_BONUS)
				_double_hit_slot = Vector2i(-1, -1)
			else:
				_double_hit_slot = slot
			var color_reward := _color_streak_for_hit(ordinary_points, removed_kinds)
			color_streak_points = int(color_reward.points)
			color_streak_started = bool(color_reward.started)
		else:
			reset_bonus_combos()  # No removal cannot prime or earn these bonuses.
	points += double_hit_points + color_streak_points
	score += points
	return {"points": points, "ordinary_points": ordinary_points, "double_hit_points": double_hit_points,
		"color_streak_points": color_streak_points, "color_streak_started": color_streak_started,
		"time": time, "combo": combo, "mult": mult,
		"tier_up": mult > old_mult, "event": event, "shine": shining}
