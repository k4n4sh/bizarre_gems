extends "res://scripts/yandex.gd"
## Test-only deferred ad result. Never installed in the live project's autoloads.
var pending_reward: Callable

func show_rewarded(done: Callable) -> void:
	pending_reward = done

func resolve_reward(ok: bool) -> void:
	var done := pending_reward
	pending_reward = Callable()
	if done.is_valid():
		done.call_deferred(ok)
