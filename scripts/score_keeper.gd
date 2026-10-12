class_name ScoreKeeper
extends RefCounted
## Scoring with combos. Time is game time in seconds (pauses don't count).
##
## Combo: successful strikes in a row, each within combo_window of the previous one.
## A miss or a pause longer than the window resets it. Points are multiplied by the combo tier.
##
## Legacy special combo is consecutive 3+ hits. Classic opts into timed_special:
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
## combo length -> multiplier (first entry whose length is reached, checked from the top)
const TIERS := [[9, 4], [5, 3], [2, 2], [0, 1]]

## Extra seconds for combos, streaks, precise/perfect combos and shining gems. Bright mode
## turns them off (its timer also speeds up per level), so a round can't go on forever.
var time_bonuses := true
var combo_window := COMBO_WINDOW
var combo_breaks := 0  ## Loss of an established series (2+), by miss or timeout.
var hits_at_x4 := 0    ## Includes the strike that first reaches x4.
var score := 0
var combo := 0
var best_combo := 0
var precise_streak := 0
var precise_count := 0  ## Combined events, retained for existing result UI.
var timed_special := false
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
	return had


## A successful strike that knocked out n gems, `shining` of them shining gems.
## Returns {points, time, combo, mult, tier_up, event, shine} where event is "", "precise" or "perfect".
func hit(n: int, now: float, shining := 0) -> Dictionary:
	update(now)  # Expire both clocks before a hit can refresh or extend them.
	var old_mult := multiplier_for(combo)
	combo += 1
	best_combo = maxi(best_combo, combo)
	_last_hit = now
	var mult := multiplier_for(combo)
	if mult == 4:
		hits_at_x4 += 1
	var points := BoardLogic.points_for(n) * mult
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
		time += TIER_TIME
	if combo % STREAK_EVERY == 0:
		time += STREAK_TIME
	if not time_bonuses:
		time = float(BoardLogic.bonus_for(n))  # only the basic +1 s / +2 s for 3 / 4 gems
	score += points
	return {"points": points, "time": time, "combo": combo, "mult": mult, "tier_up": mult > old_mult, "event": event, "shine": shining}
