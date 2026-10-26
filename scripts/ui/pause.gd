extends Screen
## Pause: a short summary of the game, resume, restart, settings, and leave to the menu (asks first).

signal resume_pressed
signal restart_pressed


## Score, time left and how far the record is (`to_record` <= 0 hides it). Set by main.gd.
func set_summary(score: int, time_text: String, to_record: int) -> void:
	$VBox/Summary/Score/Value.text = str(score)
	$VBox/Summary/Time/Value.text = time_text
	%ToRecord.visible = to_record > 0
	$VBox/Summary/ToRecord/Value.text = str(to_record)


func _on_resume_pressed() -> void:
	click()
	resume_pressed.emit()


func _on_restart_pressed() -> void:
	click()
	restart_pressed.emit()


func _on_menu_pressed() -> void:
	click()
	navigate.emit(&"confirm")


func _on_settings_pressed() -> void:
	navigate.emit(&"settings")


func layout(_view: Vector2, _compact: bool) -> void:
	custom_minimum_size.x = minf(custom_minimum_size.x, 420)
