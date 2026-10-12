extends Node
## Sound effects and background music. Effects share a small pool of players.

const SOUNDS := {
	"knock2": preload("res://assets/audio/knock2.wav"),
	"knock3": preload("res://assets/audio/knock3.wav"),
	"knock4": preload("res://assets/audio/knock4.wav"),
	"miss": preload("res://assets/audio/miss.wav"),
	"tick": preload("res://assets/audio/tick.wav"),
	"click": preload("res://assets/audio/click.wav"),
	"start": preload("res://assets/audio/start.wav"),
	"over": preload("res://assets/audio/over.wav"),
	"bonus": preload("res://assets/audio/bonus.wav"),
	"combo_up": preload("res://assets/audio/combo_up.wav"),
	"combo_break": preload("res://assets/audio/combo_break.wav"),
	"precise": preload("res://assets/audio/precise.wav"),
	"perfect": preload("res://assets/audio/perfect.wav"),
}
const MUSIC := preload("res://assets/audio/classic theme loop.ogg")
const MUSIC_BRIGHT := preload("res://assets/audio/bright run theme loop.ogg")
## Bright mode swaps in its own poppy effects where one exists (b_<name>).
const BRIGHT := {
	"knock2": preload("res://assets/audio/b_knock2.wav"), "knock3": preload("res://assets/audio/b_knock3.wav"),
	"knock4": preload("res://assets/audio/b_knock4.wav"), "miss": preload("res://assets/audio/b_miss.wav"),
	"combo_up": preload("res://assets/audio/b_combo_up.wav"), "combo_break": preload("res://assets/audio/b_combo_break.wav"),
	"precise": preload("res://assets/audio/b_precise.wav"), "perfect": preload("res://assets/audio/b_perfect.wav"),
	"start": preload("res://assets/audio/b_start.wav"), "bonus": preload("res://assets/audio/b_bonus.wav"),
	"over": preload("res://assets/audio/b_over.wav"), "tick": preload("res://assets/audio/b_tick.wav"),
	"star": preload("res://assets/audio/b_star.wav"), "hint": preload("res://assets/audio/b_hint.wav"),
	"level": preload("res://assets/audio/b_level.wav"), "clear": preload("res://assets/audio/b_clear.wav"),
}

## Keep the announcer system and saved preference available for a future return.
const ANNOUNCER_ENABLED := false

## Announcer call-outs for big moments.
const VOICES := {
	"great": preload("res://assets/audio/voice_great.wav"), "super": preload("res://assets/audio/voice_super.wav"),
	"amazing": preload("res://assets/audio/voice_amazing.wav"), "incredible": preload("res://assets/audio/voice_incredible.wav"),
	"perfect": preload("res://assets/audio/voice_perfect.wav"), "clear": preload("res://assets/audio/voice_clear.wav"),
	"levelup": preload("res://assets/audio/voice_levelup.wav"),
}

var skin := "classic"
var _voice: AudioStreamPlayer

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _platform_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	_music = AudioStreamPlayer.new()
	_music.stream = MUSIC
	apply_volumes()
	add_child(_music)


func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not Save.sound or _platform_paused:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	if skin == "bright" and BRIGHT.has(name):
		p.stream = BRIGHT[name]
	elif SOUNDS.has(name):
		p.stream = SOUNDS[name]
	else:
		p.stream = BRIGHT[name]  # bright-only events also play in classic
	p.pitch_scale = pitch * randf_range(0.985, 1.015)  # no two hits sound exactly alike
	p.volume_db = volume_db + linear_to_db(maxf(Save.sound_volume, 0.001))
	p.play()


## Switch the sound set and the music for a mode ("classic" or "bright").
func set_skin(s: String) -> void:
	if s == skin and _music.stream != null:
		return
	skin = s
	var was_playing := _music.playing
	_music.stop()
	_music.stream = MUSIC_BRIGHT if s == "bright" else MUSIC
	if was_playing:
		update_music()


func apply_volumes() -> void:
	_music.volume_db = -9.0 + linear_to_db(maxf(Save.music_volume, 0.001))


## Speak a call-out; a newer one cuts off the one still talking.
func voice(name: String) -> void:
	if not ANNOUNCER_ENABLED or not Save.sound or not Save.voice or _platform_paused or not VOICES.has(name) or skin != "bright":
		return  # call-outs belong to the bright modes; classic stays calm
	_voice.stream = VOICES[name]
	_voice.volume_db = linear_to_db(maxf(Save.sound_volume, 0.001)) + 2.0
	_voice.play()


func update_music() -> void:
	var want := Save.music and Save.music_volume > 0.01 and not _platform_paused
	if want and not _music.playing:
		_music.play()
	elif not want and _music.playing:
		_music.stop()


## Silence everything while an ad or the platform overlay is on screen.
func set_platform_paused(v: bool) -> void:
	_platform_paused = v
	AudioServer.set_bus_mute(0, v)
	update_music()
