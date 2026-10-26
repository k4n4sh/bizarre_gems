extends Screen
## The home screen: floating gems over the title, a big Play, the best score, the daily
## challenge (and a friend's challenge from a link), crystals, a row of round buttons.

signal play_pressed
signal daily_pressed
signal challenge_pressed

## The challenge from the launch link ({"mode", "score", ...}), shown as a card; set by main.
var challenge := {}
var _t := 0.0


func refresh() -> void:
	%Collection.visible = Progress.COSMETICS_ENABLED
	%Best.text = L.t("best") + ": " + str(Save.best_for(str(Save.mode)))
	%Crystals.text = str(Progress.crystals)
	var due := Progress.unclaimed()
	%Tasks.badge = str(due) if due > 0 else ""
	%Gift.badge = "!" if Progress.gift_ready() else ""
	var adue := Progress.achievements_due()
	%More.badge = str(adue) if adue > 0 else ""
	%Challenge.visible = not challenge.is_empty()
	if not challenge.is_empty():
		%Challenge.text = L.t("ch_card", {"n": challenge.score, "m": L.t("mode_" + str(challenge.mode))})
	if Progress.daily_reward_ready():
		%Daily.text = L.t("daily_card", {"n": Progress.DAILY_CRYSTALS})
	else:
		%Daily.text = L.t("daily_card_done", {"n": Save.daily_best_for(Time.get_date_string_from_system(true))})


func focus_button() -> Button:
	return %Play


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var gems := %Gems.get_children()
	for i in gems.size():
		gems[i].rotation = sin(_t * 1.3 + i * 1.7) * 0.12
		gems[i].scale = Vector2.ONE * (1.0 + 0.06 * sin(_t * 2.0 + i * 2.1))
	%Play.pivot_offset = %Play.size / 2
	%Play.scale = Vector2.ONE * (1.0 + 0.035 * sin(_t * 3.0))


func layout(view: Vector2, _compact: bool) -> void:
	var short := view.y < 600
	var content_width := maxf(1,size.x-get_theme_constant("margin_left")-get_theme_constant("margin_right")-12)
	%VBox.custom_minimum_size.x = minf(content_width,960)
	%Daily.custom_minimum_size.x = minf(400,content_width)
	%Challenge.custom_minimum_size.x = %Daily.custom_minimum_size.x
	%Title.add_theme_font_size_override("font_size", 36 if short else (40 if view.x < 600 else 58))
	%Gems.visible = view.y >= 560
	%VBox.add_theme_constant_override("separation", 8 if short else 16)
	%Play.custom_minimum_size = Vector2(260, 60 if short else 68)


## Content scrolls at its readable size; even the last service is reachable on small screens.
func fit(_avail: float) -> void:
	%VBox.scale = Vector2.ONE


func _on_play_pressed() -> void:
	click()
	play_pressed.emit()


func _on_daily_pressed() -> void:
	click()
	daily_pressed.emit()


func _on_challenge_pressed() -> void:
	click()
	challenge_pressed.emit()


func _on_gift_pressed() -> void:
	click()
	navigate.emit(&"gift")


func _on_tasks_pressed() -> void:
	click()
	navigate.emit(&"tasks")


func _on_collection_pressed() -> void:
	if not Progress.COSMETICS_ENABLED:
		return
	click()
	navigate.emit(&"collection")


func _on_leaders_pressed() -> void:
	navigate.emit(&"leaders")


func _on_more_pressed() -> void:
	click()
	navigate.emit(&"more")
