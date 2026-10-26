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

## Only presentation is rebuilt. Pending ads, paid rewards and button gates remain intact.
func refresh() -> void:
	if _copy.is_empty(): return
	var r: Dictionary = _copy
	%Reward.text = L.t("reward_line",{"n":r.reward})
	%Double.text = L.t("double_ad",{"n":r.reward})
	if r.has("localization"):
		var c: Dictionary = r.localization
		%Title.text = L.t(c.title)
		%NewBest.text = L.t(c.new_best) if c.new_best != "" else (L.t("near_best",{"n":c.near}) if int(c.get("near",0)) > 0 else "")
		var line := L.t("cleared",{"n":c.cleared,"w":c.wave})+"\n"+L.t("stats",{"combo":c.combo,"precise":c.precise})
		if int(c.get("best_hot",0)) > 0: line += "\n"+L.t("best_hot",{"n":c.best_hot})
		if c.daily: line =L.t("daily")+" · "+L.t("daily_best",{"n":c.daily_best})+"\n"+line
		if c.target >= 0: line = L.t("ch_won",{"n":c.target})+"\n"+line if r.score > c.target else L.t("ch_lost",{"n":c.target,"d":c.target-r.score+1})+"\n"+line
		%Line.text = line
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
	%NewBest.add_theme_color_override("font_color", UiKit.BRASS_LIGHT if r.new_best != "" else Color("#ffb070"))
	if %NewBest.visible:
		%NewBest.pivot_offset = %NewBest.size / 2
		%NewBest.scale = Vector2.ONE * 0.6
		create_tween().tween_property(%NewBest, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	%Line.text = r.line
	var reward: int = r.reward
	%Reward.text = L.t("reward_line", {"n": reward})
	%Reward.visible = reward > 0
	%Double.text = L.t("double_ad", {"n": reward})
	%Double.visible = reward > 0
	%Continue.visible = r.can_continue
	%Shuffle.visible = r.can_shuffle
	%Share.visible = r.can_share
	set_ad_pending(false)
	refresh()


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
	%Score.add_theme_font_size_override("font_size", 52 if compact else 72)
