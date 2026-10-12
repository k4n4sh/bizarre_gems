extends Node
## Player progress: best score and audio settings. Stored locally and, on Yandex Games,
## in the player's cloud data so it follows them across devices.

signal changed

const PATH := "user://save.cfg"
const ComboExperiment = preload("res://scripts/combo_experiment.gd")

var best := 0          ## classic (desktop) board
var best_bright := 0  ## bright run
var best_zen := 0     ## no-timer mode
var mode := "bright" if OS.has_feature("android") else "classic"  ## last mode the player started
var sound := true
var music := true
var vibration := true
var voice := true  ## announcer call-outs
var sound_volume := 1.0
var music_volume := 0.7
var daily_date := ""
var daily_best := 0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		best = int(cfg.get_value("game", "best", 0))
		best_bright = int(cfg.get_value("game", "best_bright", cfg.get_value("game", "best_compact", 0)))
		best_zen = int(cfg.get_value("game", "best_zen", 0))
		mode = str(cfg.get_value("game", "mode", "classic"))
		if not (mode in ["classic", "bright", "zen", "levels", "puzzle"]):
			mode = "bright"  # removed modes (duel) and the tutorial are never the last mode
		sound = bool(cfg.get_value("audio", "sound", true))
		music = bool(cfg.get_value("audio", "music", true))
		vibration = bool(cfg.get_value("audio", "vibration", true))
		voice = bool(cfg.get_value("audio", "voice", true))
		sound_volume = float(cfg.get_value("audio", "sound_volume", 1.0))
		music_volume = float(cfg.get_value("audio", "music_volume", 0.7))
		daily_date = str(cfg.get_value("daily", "date", ""))
		daily_best = int(cfg.get_value("daily", "best", 0))


## Merge cloud data once the SDK is up. The higher best score wins.
func sync_cloud() -> void:
	if ComboExperiment.is_read_only():
		return
	Yandex.load_data(func(d: Dictionary):
		if ComboExperiment.is_read_only() or d.is_empty():
			return
		var newer := false
		if int(d.get("best", 0)) > best:
			best = int(d.get("best", 0))
			newer = true
		if int(d.get("best_bright", 0)) > best_bright:
			best_bright = int(d.get("best_bright", 0))
			newer = true
		Progress.merge(d.get("progress", {}))
		if newer:
			_write_local()
			changed.emit()
		Yandex.save_data(cloud_data()))


## Best score of today's daily board. Returns true on a new daily record.
func submit_daily(score: int, date: String) -> bool:
	if ComboExperiment.is_read_only():
		return false
	if daily_date != date:
		daily_date = date
		daily_best = 0
	if score <= daily_best:
		return false
	daily_best = score
	store()
	return true


func daily_best_for(date: String) -> int:
	return daily_best if daily_date == date else 0


func best_for(mode: String) -> int:
	match mode:
		"bright":
			return best_bright
		"zen":
			return best_zen
		"levels":
			return Progress.total_stars()
	return best


## Returns true on a new record for this board mode.
## The player's cloud data: settings, best scores and bright-mode progress.
func cloud_data() -> Dictionary:
	var d := _data()
	d["progress"] = Progress.to_dict()
	return d


func submit(score: int, mode := "classic") -> bool:
	if ComboExperiment.is_read_only():
		return false
	if score <= best_for(mode):
		return false
	if mode == "levels":
		return false
	if mode == "bright":
		best_bright = score
	elif mode == "zen":
		best_zen = score
	else:
		best = score
	store()
	return true


func store() -> void:
	_write_local()
	Yandex.save_data(cloud_data())
	changed.emit()


func _data() -> Dictionary:
	return {"best": best, "best_bright": best_bright, "best_zen": best_zen, "mode": mode, "sound": sound, "music": music, "vibration": vibration,
		"sound_volume": sound_volume, "music_volume": music_volume, "daily_date": daily_date, "daily_best": daily_best}


func _write_local() -> void:
	if ComboExperiment.is_read_only():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.set_value("game", "best_bright", best_bright)
	cfg.set_value("game", "best_zen", best_zen)
	cfg.set_value("game", "mode", mode)
	cfg.set_value("audio", "sound", sound)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "vibration", vibration)
	cfg.set_value("audio", "voice", voice)
	cfg.set_value("audio", "sound_volume", sound_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("daily", "date", daily_date)
	cfg.set_value("daily", "best", daily_best)
	cfg.save(PATH)
