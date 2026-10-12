extends Node
## Bridge to the Yandex Games SDK.
##
## The web export's <head> defines window.YG (see export_presets.cfg, html/head_include),
## which wraps the SDK and degrades to no-ops when the SDK is missing. Outside the browser
## every call here is a stub, so the game runs the same in the editor.

signal sdk_ready
signal pause_requested
signal resume_requested

const MIN_FULLSCREEN_GAP_MS := 61_000
const ComboExperiment = preload("res://scripts/combo_experiment.gd")

var available := false
var is_ready := false
var _yg: JavaScriptObject
var _keep: Array = []  # JS callbacks must stay referenced while JS can call them
var _last_fullscreen_ms := -MIN_FULLSCREEN_GAP_MS


func _ready() -> void:
	if OS.has_feature("web"):
		_yg = JavaScriptBridge.get_interface("YG")
	if _yg == null:
		_finish_ready.call_deferred(false)
		return
	_yg.onPause(_cb(func(_a): pause_requested.emit()))
	_yg.onResume(_cb(func(_a): resume_requested.emit()))
	_yg.whenReady(_cb(func(a): _finish_ready.call_deferred(bool(a[0]))))


func _finish_ready(ok: bool) -> void:
	available = ok
	is_ready = true
	sdk_ready.emit()


func _cb(f: Callable) -> JavaScriptObject:
	var c := JavaScriptBridge.create_callback(f)
	_keep.append(c)
	return c


func language() -> String:
	if _yg:
		return str(_yg.lang())
	return OS.get_locale_language()


## Tell the platform the game has loaded and is ready to play.
func loading_ready() -> void:
	if _yg:
		_yg.loadingReady()


## Gameplay markers: true while the player is actively playing.
func gameplay(active: bool) -> void:
	if _yg:
		_yg.gameplay(active)


## Interstitial between games. Calls done(shown) when the ad is closed or skipped.
func show_fullscreen(done: Callable) -> void:
	var now := Time.get_ticks_msec()
	if _yg == null or not available or now - _last_fullscreen_ms < MIN_FULLSCREEN_GAP_MS:
		done.call_deferred(false)
		return
	_last_fullscreen_ms = now
	_yg.showFullscreen(_cb(func(a): done.call_deferred(bool(a[0]))))


## Rewarded video. Calls done(rewarded). Outside Yandex the reward is granted for testing.
func show_rewarded(done: Callable) -> void:
	if _yg == null:
		done.call_deferred(true)
		return
	_yg.showRewarded(_cb(func(a): done.call_deferred(bool(a[0]))))


func is_authorized() -> bool:
	return _yg != null and bool(_yg.isAuthorized())


func open_auth(done: Callable) -> void:
	if _yg == null:
		done.call_deferred(false)
		return
	_yg.openAuth(_cb(func(a): done.call_deferred(bool(a[0]))))


## `board` is the leaderboard's technical name in the Yandex console.
func submit_score(score: int, board := "score") -> void:
	if ComboExperiment.is_read_only():
		return
	if _yg and available:
		_yg.setScore(board, score)


## done(result) where result is {} when unavailable, else {"entries": [...], "userRank": int}.
func fetch_leaderboard(done: Callable, board := "score") -> void:
	if _yg == null or not available:
		done.call_deferred({})
		return
	_yg.getEntries(board, _cb(func(a): done.call_deferred(_parse(str(a[0])))))


func load_data(done: Callable) -> void:
	if _yg == null or not available:
		done.call_deferred({})
		return
	_yg.loadData(_cb(func(a): done.call_deferred(_parse(str(a[0])))))


func save_data(data: Dictionary) -> void:
	if ComboExperiment.is_read_only():
		return
	if _yg and available:
		_yg.saveData(JSON.stringify(data))


func _parse(s: String) -> Dictionary:
	if s.is_empty():
		return {}
	var v = JSON.parse_string(s)
	return v if v is Dictionary else {}
