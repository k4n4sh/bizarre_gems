extends Screen
## The end of a timed game: score, records, rewards, the best strike replayed, what next.

signal again_pressed
signal double_pressed
signal continue_pressed
signal shuffle_pressed
signal share_pressed
signal menu_pressed
var _copy := {}
var _strike := {}

func _ready() -> void:
	L.language_changed.connect(refresh)
	%BestStrike.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 1, 12, Vector4(10, 8, 12, 8)))

## Only presentation is rebuilt. Pending ads, paid rewards and button gates remain intact.
func refresh() -> void:
	if _copy.is_empty(): return
	var r: Dictionary = _copy
	%Reward.text = L.t("reward_line",{"n":r.reward})
	_double_text(r.reward)
	if r.has("localization"):
		var c: Dictionary = r.localization
		%Title.text = L.t(c.title)
		%NewBest.text = L.t(c.new_best) if c.new_best != "" else (L.t("near_best",{"n":c.near}) if int(c.get("near",0)) > 0 else "")
		var stats := [["res_gems", c.cleared], ["res_combo", c.combo], ["res_precise", c.precise]]
		if int(c.get("best_hot",0)) > 0: stats.append(["res_hot", c.best_hot])
		_show_stats(stats)
		# Daily and Challenge add one line of context above the numbers.
		var line := ""
		if c.daily: line = L.t("daily")+" · "+L.t("daily_best",{"n":c.daily_best})
		if c.target >= 0: line = L.t("ch_won",{"n":c.target}) if r.score > c.target else L.t("ch_lost",{"n":c.target,"d":c.target-r.score+1})
		%Line.text = line
		%Line.visible = line != ""
	if not _strike.is_empty(): %Caption.text = L.t("best_strike",{"n":_strike.n,"p":_strike.points})


## r: title, score, new_best (text or ""), near ("just N short" or ""), line, reward (crystals), can_continue, can_shuffle, can_share
func show_result(r: Dictionary) -> void:
	_copy = r.duplicate(true)
	%Title.text = r.title
	%Score.text = str(r.score)
	# a new record, or how little was missing for one
	var near: String = r.get("near", "")
	%NewBest.text = r.new_best if r.new_best != "" else near
	%NewBest.visible = %NewBest.text != ""
	%Badge.visible = %NewBest.visible
	# A pill: gold for a new record, warm orange for "just short of it".
	var tint := UiKit.BRASS if r.new_best != "" else Color("#ff9a2e")
	%Badge.add_theme_stylebox_override("panel", UiKit.box(Color(tint, 0.16), Color(tint, 0.55), 1, 99, Vector4(14, 4, 14, 4)))
	%NewBest.add_theme_color_override("font_color", UiKit.BRASS_LIGHT if r.new_best != "" else Color("#ffb070"))
	if %Badge.visible:
		%Badge.pivot_offset = %Badge.size / 2
		%Badge.scale = Vector2.ONE * 0.6
		create_tween().tween_property(%Badge, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	%Line.text = r.line
	var reward: int = r.reward
	%Reward.text = L.t("reward_line", {"n": reward})
	%RewardRow.visible = reward > 0
	_double_text(reward)
	%Double.visible = reward > 0
	%Stats.visible = r.has("localization")
	%Continue.visible = r.can_continue
	%Shuffle.visible = r.can_shuffle
	%Share.visible = r.can_share
	set_ad_pending(false)
	refresh()


## Caption/value pairs in one row: [[string key, number], ...].
func _show_stats(stats: Array) -> void:
	for child in %Stats.get_children():
		child.queue_free()
	for pair in stats:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var caption := Label.new()
		caption.theme_type_variation = &"Caption"
		caption.uppercase = true
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text = L.t(pair[0])
		var value := Label.new()
		value.theme_type_variation = &"Number"
		value.add_theme_font_size_override("font_size", 24)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.text = str(pair[1])
		cell.add_child(caption)
		cell.add_child(value)
		%Stats.add_child(cell)


## The ad button next to the reward stays short; the full offer is in its tooltip.
func _double_text(reward: int) -> void:
	%Double.text = "×2"
	%Double.tooltip_text = L.t("double_ad", {"n": reward})


func set_ad_pending(pending: bool) -> void:
	for button in [%Double, %Continue, %Shuffle, %Again]:
		button.disabled = pending


## The game's best strike, looped; `tile` maps a gem kind to its texture.
func show_best_strike(strike: Dictionary, tile: Callable) -> void:
	_strike = strike.duplicate(true)
	%BestStrike.visible = not strike.is_empty() and not strike.parts.is_empty()
	if %BestStrike.visible:
		%Caption.text = L.t("best_strike", {"n": strike.n, "p": strike.points})
		(%Replay as StrikeReplay).show_strike(strike, tile, UiKit.NUMBER_FONT)


func hide_double() -> void:
	%Double.visible = false


func hide_shuffle() -> void:
	%Shuffle.visible = false


func _on_again_pressed() -> void:
	click()
	%Again.disabled = true  # until the ad before the next game is over
	again_pressed.emit()


func _on_double_pressed() -> void:
	click()
	double_pressed.emit()


func _on_continue_pressed() -> void:
	click()
	continue_pressed.emit()


func _on_shuffle_pressed() -> void:
	click()
	shuffle_pressed.emit()


func _on_share_pressed() -> void:
	click()
	share_pressed.emit()


func _on_leaders_pressed() -> void:
	navigate.emit(&"leaders")


func _on_menu_pressed() -> void:
	click()
	menu_pressed.emit()


func layout(_view: Vector2, compact: bool) -> void:
	%Score.add_theme_font_size_override("font_size", 48 if compact else 60)
	custom_minimum_size.x = minf(custom_minimum_size.x, 460)
