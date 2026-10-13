extends "res://scripts/main.gd"
## Real game containers and input; only device detection, scaling and safe insets are simulated.
var simulate_android := false
var test_insets := Rect2()

func _bright_web_hud() -> bool:
	return mode.id == "bright" and not simulate_android

func _is_touch_device() -> bool:
	return simulate_android

func _safe_insets() -> Rect2:
	return test_insets

func _apply_ui_scale() -> void:
	pass
