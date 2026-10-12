extends Node
## Long-term progress for the bright modes: level stars, crystals, the tile looks the player
## owns, and today's three tasks. Stored in user://progress.cfg.

signal changed

const PATH := "user://progress.cfg"
## Presentation only: keep owned/look in saves even while cosmetics are unavailable.
const COSMETICS_ENABLED := false
const BASE_LOOK := 0
const ComboExperiment = preload("res://scripts/combo_experiment.gd")
const STAR_CRYSTALS := 5          ## crystals per newly earned star
## Price per tile look: crystals, SEASON (free while its season is on) or GIFT (7-day streak).
const SEASON := -1
const GIFT := -2
const PASS := -3  ## won on the season pass
const LOOK_PRICES := [0, 60, 90, 120, 160, 200, SEASON, SEASON, GIFT, PASS, PASS]
const NEON_LOOK := 9
const GLASS_LOOK := 10
## Season pass: a new season every calendar month, 30 tiers of XP_PER_TIER each.
const PASS_TIERS := 30
const XP_PER_TIER := 100
## Daily challenge: crystals for the first finished challenge of the day.
const DAILY_CRYSTALS := 20
## Chapter rewards: all levels passed / all stars.
const CHAPTER_DONE := 50
const CHAPTER_FULL := 100
const WINTER_LOOK := 6
const HALLOWEEN_LOOK := 7
const GOLD_LOOK := 8
## Lifetime goals; "stat" is the counter they read, same names as the task reports.
const ACHIEVEMENTS := [
	{"id": "clears10", "stat": "clear_boards", "goal": 10, "reward": 40},
	{"id": "clears100", "stat": "clear_boards", "goal": 100, "reward": 150},
	{"id": "gems1000", "stat": "gems", "goal": 1000, "reward": 50},
	{"id": "gems10000", "stat": "gems", "goal": 10000, "reward": 200},
	{"id": "combo4x10", "stat": "combo4", "goal": 10, "reward": 60},
	{"id": "perfect10", "stat": "perfects", "goal": 10, "reward": 60},
	{"id": "levels10", "stat": "levels", "goal": 10, "reward": 50},
	{"id": "levels30", "stat": "levels", "goal": 30, "reward": 120},
	{"id": "stars3x10", "stat": "stars3", "goal": 10, "reward": 80},
	{"id": "puzzles10", "stat": "puzzles", "goal": 10, "reward": 60},
	{"id": "streak7", "stat": "streak", "goal": 7, "reward": 100},
]
## Daily task pool. "max" tasks track the best single value instead of adding up.
const TASK_POOL := [
	{"id": "clear_boards", "goal": 3, "reward": 30},
	{"id": "combo4", "goal": 2, "reward": 20},
	{"id": "gems", "goal": 250, "reward": 25},
	{"id": "stars3", "goal": 2, "reward": 35},
	{"id": "levels", "goal": 3, "reward": 25},
	{"id": "run_score", "goal": 600, "reward": 30, "max": true},
	{"id": "zen_boards", "goal": 3, "reward": 25},
	{"id": "perfects", "goal": 2, "reward": 30},
]

var stars := {}      ## level number -> best stars (0..3)
var crystals := 0
var owned: Array = [0]
var look := 0        ## selected tile look, the first one bright games start with
var task_date := ""
var tasks: Array = []
var life := {}          ## lifetime counters (gems, clear_boards, ...) for achievements
var achieved: Array = []  ## achievement ids already claimed
var gift_date := ""     ## last day the daily gift was opened
var streak := 0         ## days in a row the gift was opened
var puzzles := 0        ## puzzles solved (the next one is puzzles + 1)
var tutorial := false   ## the first-run tutorial was completed
## Local leaderboards (Android and anywhere without Yandex): board -> [{score, date}], best 10.
var local_scores := {}
var season := ""            ## season id "YYYY-MM" the XP below belongs to
var season_xp := 0
var season_claimed: Array = []  ## tiers already claimed this season
var hint_tokens := 0        ## spare hints (season pass rewards), used after the free one
var daily_reward_date := ""  ## last day the daily challenge paid its crystals
var chapter_claims: Array = []  ## "c<n>_done" / "c<n>_full" already paid
var _dirty := false
var _since := 0.0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var st: Dictionary = cfg.get_value("levels", "stars", {})
		for k in st:
			stars[int(k)] = int(st[k])
		crystals = int(cfg.get_value("shop", "crystals", 0))
		owned = cfg.get_value("shop", "owned", [0])
		look = int(cfg.get_value("shop", "look", 0))
		task_date = str(cfg.get_value("tasks", "date", ""))
		tasks = cfg.get_value("tasks", "list", [])
		life = cfg.get_value("meta", "life", {})
		achieved = cfg.get_value("meta", "achieved", [])
		gift_date = str(cfg.get_value("meta", "gift_date", ""))
		streak = int(cfg.get_value("meta", "streak", 0))
		puzzles = int(cfg.get_value("meta", "puzzles", 0))
		tutorial = bool(cfg.get_value("meta", "tutorial", false))
		local_scores = cfg.get_value("meta", "local_scores", {})
		season = str(cfg.get_value("pass", "season", ""))
		season_xp = int(cfg.get_value("pass", "xp", 0))
		season_claimed = cfg.get_value("pass", "claimed", [])
		hint_tokens = int(cfg.get_value("pass", "hints", 0))
		daily_reward_date = str(cfg.get_value("meta", "daily_reward_date", ""))
		chapter_claims = cfg.get_value("meta", "chapter_claims", [])
	refresh_tasks()
	_check_season()


func _save() -> void:
	_dirty = false
	_since = 0.0
	if ComboExperiment.is_read_only():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("levels", "stars", stars)
	cfg.set_value("shop", "crystals", crystals)
	cfg.set_value("shop", "owned", owned)
	cfg.set_value("shop", "look", look)
	cfg.set_value("tasks", "date", task_date)
	cfg.set_value("tasks", "list", tasks)
	cfg.set_value("meta", "life", life)
	cfg.set_value("meta", "achieved", achieved)
	cfg.set_value("meta", "gift_date", gift_date)
	cfg.set_value("meta", "streak", streak)
	cfg.set_value("meta", "puzzles", puzzles)
	cfg.set_value("meta", "tutorial", tutorial)
	cfg.set_value("meta", "local_scores", local_scores)
	cfg.set_value("pass", "season", season)
	cfg.set_value("pass", "xp", season_xp)
	cfg.set_value("pass", "claimed", season_claimed)
	cfg.set_value("pass", "hints", hint_tokens)
	cfg.set_value("meta", "daily_reward_date", daily_reward_date)
	cfg.set_value("meta", "chapter_claims", chapter_claims)
	cfg.save(PATH)
	Yandex.save_data(Save.cloud_data())
	changed.emit()


## Everything worth keeping across devices, for the player's Yandex cloud data.
func to_dict() -> Dictionary:
	return {"stars": stars, "crystals": crystals, "owned": owned, "look": look, "life": life, "achieved": achieved,
		"gift_date": gift_date, "streak": streak, "puzzles": puzzles, "tutorial": tutorial, "season": season,
		"season_xp": season_xp, "season_claimed": season_claimed, "hint_tokens": hint_tokens,
		"daily_reward_date": daily_reward_date, "chapter_claims": chapter_claims}


## Merge cloud progress into the local one, keeping the better of each.
func merge(d: Dictionary) -> void:
	if d.is_empty():
		return
	var st: Dictionary = d.get("stars", {})
	for k in st:
		stars[int(k)] = maxi(stars_for(int(k)), int(st[k]))
	crystals = maxi(crystals, int(d.get("crystals", 0)))
	for i in d.get("owned", []):
		if not (int(i) in owned):
			owned.append(int(i))
	var cl: Dictionary = d.get("life", {})
	for k in cl:
		life[k] = maxi(int(life.get(k, 0)), int(cl[k]))
	for a in d.get("achieved", []):
		if not (a in achieved):
			achieved.append(a)
	if str(d.get("gift_date", "")) > gift_date:
		gift_date = str(d.get("gift_date", ""))
		streak = int(d.get("streak", streak))
	puzzles = maxi(puzzles, int(d.get("puzzles", 0)))
	tutorial = tutorial or bool(d.get("tutorial", false))
	if str(d.get("season", "")) == season:
		season_xp = maxi(season_xp, int(d.get("season_xp", 0)))
		for t in d.get("season_claimed", []):
			if not (int(t) in season_claimed):
				season_claimed.append(int(t))
	hint_tokens = maxi(hint_tokens, int(d.get("hint_tokens", 0)))
	if str(d.get("daily_reward_date", "")) > daily_reward_date:
		daily_reward_date = str(d.get("daily_reward_date", ""))
	_bank_cosmetic_pass_rewards()
	for c in d.get("chapter_claims", []):
		if not (c in chapter_claims):
			chapter_claims.append(c)
	_save()


# ---------------- levels and stars ----------------

func stars_for(level: int) -> int:
	return int(stars.get(level, 0))


## The highest level the player may start: one past the last level with a star.
func max_unlocked() -> int:
	var n := 1
	while stars_for(n) > 0:
		n += 1
	return n


func total_stars() -> int:
	var t := 0
	for k in stars:
		t += int(stars[k])
	return t


## Stars for a level result by share of gems knocked out.
static func stars_for_share(share: float) -> int:
	if share >= 0.999:
		return 3
	if share >= 0.85:
		return 2
	if share >= 0.6:
		return 1
	return 0


## Store a level result; returns how many new stars were earned (each pays crystals).
func record_level(level: int, got: int) -> int:
	var old := stars_for(level)
	if got > old:
		stars[level] = got
		crystals += (got - old) * STAR_CRYSTALS
	if old == 0 and got > 0:
		report("levels")
	if got == 3 and old < 3:
		report("stars3")
	_save()
	return maxi(0, got - old)


# ---------------- daily tasks ----------------

## Today's three tasks, the same for everyone (seeded by the UTC date).
func refresh_tasks() -> void:
	var today := Time.get_date_string_from_system(true)
	if task_date == today and tasks.size() == 3:
		return
	task_date = today
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bizarre-tasks-" + today)
	var pool: Array = TASK_POOL.duplicate()
	tasks = []
	for i in 3:
		var t: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		tasks.append({"id": t.id, "goal": t.goal, "reward": t.reward, "max": t.get("max", false),
			"progress": 0, "claimed": false})
	_save()


func report(id: String, amount := 1) -> void:
	refresh_tasks()
	if id == "run_score" or id.begins_with("max_"):
		life[id] = maxi(int(life.get(id, 0)), amount)
	else:
		life[id] = int(life.get(id, 0)) + amount
	for t in tasks:
		if t.id == id and int(t.progress) < int(t.goal):
			if t.get("max", false):
				t.progress = mini(int(t.goal), maxi(int(t.progress), amount))
			else:
				t.progress = mini(int(t.goal), int(t.progress) + amount)
	_dirty = true  # reports come every strike; the file and the cloud are written in batches


## Write pending progress now (end of a game, leaving a level).
func flush() -> void:
	if _dirty:
		_save()


func _process(delta: float) -> void:
	if _dirty:
		_since += delta
		if _since > 3.0:
			_save()


# ---------------- achievements ----------------

func achievement_progress(i: int) -> int:
	var a: Dictionary = ACHIEVEMENTS[i]
	return mini(int(life.get(a.stat, 0)), int(a.goal))


func achievement_done(i: int) -> bool:
	return achievement_progress(i) >= int(ACHIEVEMENTS[i].goal)


func claim_achievement(i: int) -> int:
	var a: Dictionary = ACHIEVEMENTS[i]
	if not achievement_done(i) or a.id in achieved:
		return 0
	achieved.append(a.id)
	crystals += int(a.reward)
	add_xp(40)
	_save()
	return int(a.reward)


func achievements_due() -> int:
	var n := 0
	for i in ACHIEVEMENTS.size():
		if achievement_done(i) and not (ACHIEVEMENTS[i].id in achieved):
			n += 1
	return n


# ---------------- daily gift ----------------

func gift_ready() -> bool:
	return gift_date != Time.get_date_string_from_system(true)


## Crystals for day n of a streak: 10, 15, ... 40 on day 7 and after.
static func gift_amount(day: int) -> int:
	return 10 + 5 * (clampi(day, 1, 7) - 1)


## Open today's gift. Returns {"crystals", "day", "look"} (look = -1 unless a look was unlocked).
func open_gift() -> Dictionary:
	if not gift_ready():
		return {}
	var today := Time.get_date_string_from_system(true)
	var yesterday := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today) - 86400)
	streak = streak + 1 if gift_date == yesterday else 1
	gift_date = today
	var amount := gift_amount(streak)
	crystals += amount
	life["streak"] = maxi(int(life.get("streak", 0)), streak)
	var unlocked := -1
	if streak % 7 == 0 and not owns(GOLD_LOOK):
		owned.append(GOLD_LOOK)
		unlocked = GOLD_LOOK
	_save()
	return {"crystals": amount, "day": streak, "look": unlocked}


# ---------------- seasons ----------------

## The seasonal look available today, or -1.
static func season_look() -> int:
	var d := Time.get_date_dict_from_system(true)
	if d.month == 12 or d.month <= 2:
		return WINTER_LOOK
	if (d.month == 10 and d.day >= 15) or (d.month == 11 and d.day <= 5):
		return HALLOWEEN_LOOK
	return -1


func claim_season() -> bool:
	if not COSMETICS_ENABLED:
		return false
	var s2 := season_look()
	if s2 < 0 or owns(s2):
		return false
	owned.append(s2)
	look = s2
	_save()
	return true


func solved_puzzle(n: int) -> void:
	if n > puzzles:
		puzzles = n
		report("puzzles")
	_save()


## Keep a result in this device's top 10 for a board ("score", "score_bright", "stars", ...).
func add_local_score(board: String, value: int) -> void:
	if board == "" or value <= 0:
		return
	var list: Array = local_scores.get(board, [])
	if board == "stars":
		list = []  # one entry: the current total
	list.append({"score": value, "date": Time.get_date_string_from_system()})
	list.sort_custom(func(a, b): return int(a.score) > int(b.score))
	local_scores[board] = list.slice(0, 10)
	_save()


func local_top(board: String) -> Array:
	return local_scores.get(board, [])


func finish_tutorial() -> void:
	tutorial = true
	_save()


func task_done(i: int) -> bool:
	return int(tasks[i].progress) >= int(tasks[i].goal)


func claim(i: int) -> int:
	if i < 0 or i >= tasks.size() or not task_done(i) or bool(tasks[i].claimed):
		return 0
	tasks[i].claimed = true
	crystals += int(tasks[i].reward)
	add_xp(25)
	_save()
	return int(tasks[i].reward)


func unclaimed() -> int:
	var n := 0
	for i in tasks.size():
		if task_done(i) and not bool(tasks[i].claimed):
			n += 1
	return n


# ---------------- tile looks ----------------

## Resolve presentation without overwriting the saved choice.
func active_look() -> int:
	return look if COSMETICS_ENABLED else BASE_LOOK


func owns(i: int) -> bool:
	return i in owned


func buy(i: int) -> bool:
	if not COSMETICS_ENABLED:
		return false
	if owns(i) or int(LOOK_PRICES[i]) < 0 or crystals < int(LOOK_PRICES[i]):
		return false
	crystals -= int(LOOK_PRICES[i])
	owned.append(i)
	look = i
	_save()
	return true


func select(i: int) -> void:
	if not COSMETICS_ENABLED:
		return
	if owns(i):
		look = i
		_save()


# ---------------- season pass ----------------

static func season_id() -> String:
	var d := Time.get_date_dict_from_system(true)
	return "%04d-%02d" % [d.year, d.month]


## A new month starts a new season: XP and claimed tiers reset, owned rewards stay.
func _check_season() -> void:
	# Bank earned cosmetic entitlements even before an old season rolls over.
	var banked := _bank_cosmetic_pass_rewards()
	var id := season_id()
	if season != id:
		season = id
		season_xp = 0
		season_claimed = []
		_save()
	elif banked:
		_save()


func season_tier() -> int:
	_check_season()
	return mini(season_xp / XP_PER_TIER, PASS_TIERS)


## Add pass XP. Returns how many tiers were reached by it.
func add_xp(n: int) -> int:
	_check_season()
	var before := season_tier()
	season_xp = mini(season_xp + maxi(n, 0), PASS_TIERS * XP_PER_TIER)
	_dirty = true
	return season_tier() - before


## Quietly preserve earned new packs while their claim controls are hidden.
## Duplicate-pack compensation stays manually claimable as the existing 200 crystals.
func _bank_cosmetic_pass_rewards() -> bool:
	if COSMETICS_ENABLED:
		return false
	var changed_rewards := false
	for t in range(1, mini(season_xp / XP_PER_TIER, PASS_TIERS) + 1):
		var reward := pass_reward(t)
		if reward.kind == "look" and t not in season_claimed and not owns(int(reward.n)):
			owned.append(int(reward.n))
			season_claimed.append(t)
			changed_rewards = true
	return changed_rewards


## Reward of tier t: {"kind": "crystals"|"hints"|"look", "n": amount or look index}.
static func pass_reward(t: int) -> Dictionary:
	match t:
		5, 20:
			return {"kind": "hints", "n": 3 if t == 5 else 5}
		10:
			return {"kind": "look", "n": NEON_LOOK}
		15:
			return {"kind": "crystals", "n": 100}
		25:
			return {"kind": "crystals", "n": 150}
		30:
			return {"kind": "look", "n": GLASS_LOOK}
	return {"kind": "crystals", "n": 15 + (t / 5) * 5}


func pass_claimable(t: int) -> bool:
	return t <= season_tier() and not (t in season_claimed)


## Claim tier t. A look the player already owns pays 200 crystals instead.
func claim_pass(t: int) -> Dictionary:
	if not pass_claimable(t):
		return {}
	var r := pass_reward(t)
	season_claimed.append(t)
	match str(r.kind):
		"crystals":
			crystals += int(r.n)
		"hints":
			hint_tokens += int(r.n)
		"look":
			if owns(int(r.n)):
				r = {"kind": "crystals", "n": 200}
				crystals += 200
			else:
				owned.append(int(r.n))
	_save()
	return r


func pass_due() -> int:
	var n := 0
	for t in range(1, season_tier() + 1):
		if not (t in season_claimed):
			n += 1
	return n


func use_hint_token() -> bool:
	if hint_tokens <= 0:
		return false
	hint_tokens -= 1
	_dirty = true
	return true


# ---------------- daily challenge ----------------

func daily_reward_ready() -> bool:
	return daily_reward_date != Time.get_date_string_from_system(true)


## Pay the daily challenge crystals once a day. Returns the crystals paid (0 if already).
func pay_daily() -> int:
	if not daily_reward_ready():
		return 0
	daily_reward_date = Time.get_date_string_from_system(true)
	crystals += DAILY_CRYSTALS
	report("dailies")
	_save()
	return DAILY_CRYSTALS


# ---------------- chapters ----------------

## Stars and passed levels of chapter c (from 0).
func chapter_stats(c: int) -> Dictionary:
	var passed := 0
	var got := 0
	for n in range(c * BoardLogic.CHAPTER_SIZE + 1, (c + 1) * BoardLogic.CHAPTER_SIZE + 1):
		var st := stars_for(n)
		got += st
		if st > 0:
			passed += 1
	return {"passed": passed, "stars": got, "max": BoardLogic.CHAPTER_SIZE * 3}


## Rewards of chapter c that can be claimed now: "done" (all levels passed), "full" (all stars).
func chapter_due(c: int) -> Array:
	var st := chapter_stats(c)
	var out := []
	if st.passed >= BoardLogic.CHAPTER_SIZE and not ("c%d_done" % c in chapter_claims):
		out.append("done")
	if st.stars >= st.max and not ("c%d_full" % c in chapter_claims):
		out.append("full")
	return out


func claim_chapter(c: int, what: String) -> int:
	if not (what in chapter_due(c)):
		return 0
	chapter_claims.append("c%d_%s" % [c, what])
	var n := CHAPTER_DONE if what == "done" else CHAPTER_FULL
	crystals += n
	_save()
	return n


# ---------------- crystals from games ----------------

## Crystals a finished game pays for its score: one per 100 points, at most 30.
static func crystals_for_score(score: int) -> int:
	return clampi(score / 100, 1 if score > 0 else 0, 30)


func add_crystals(n: int) -> void:
	crystals += n
	_save()
