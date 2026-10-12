extends "res://scripts/main.gd"
## The real Control layout, with only platform detection, insets and root scaling substituted.
var simulate_android := true
var test_insets := Rect2()
var suppress_focus_pause := false

func pause_game() -> void:
	# Hidden rendering fixtures must keep running when another app owns focus.
	if not suppress_focus_pause:
		super.pause_game()

func _classic_android_sides() -> bool:
	return simulate_android and mode.id == "classic"

func _safe_insets() -> Rect2:
	return test_insets

func _apply_ui_scale() -> void:
	pass
