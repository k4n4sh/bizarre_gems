extends RefCounted
## Run via run_runtime_suite.gd in an isolated project/profile.
## Use --headless --audio-driver WASAPI on Windows to verify actual audio output.

var checks := 0
var failures: Array[String] = []
var observations: Array = []
var finished_events := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func peak(samples: PackedVector2Array) -> float:
	var value := 0.0
	for sample in samples:
		value = maxf(value, maxf(absf(sample.x), absf(sample.y)))
	return value


func _finished() -> void:
	finished_events += 1


func check_decoder(stream: AudioStream, filename: String, length: float) -> void:
	check(stream is AudioStreamOggVorbis, filename + ": imported as Ogg Vorbis")
	if not stream is AudioStreamOggVorbis:
		return
	check(stream.resource_path.get_file() == filename, filename + ": original filename retained")
	check(stream.loop and stream.loop_offset == 0.0 and stream.beat_count == 0, filename + ": full-file native loop from zero")
	check(absf(stream.get_length() - length) < 0.001, filename + ": original duration retained")
	var playback := stream.instantiate_playback()
	var frames := int(AudioServer.get_mix_rate() * 0.25)
	playback.start(stream.get_length() - 0.05)
	var samples := playback.mix_audio(1.0, frames)
	check(samples.size() == frames and peak(samples) > 0.01, filename + ": decoder produces audio across the end")
	check(playback.is_playing() and playback.get_loop_count() >= 1 and playback.get_playback_position() < 1.0, filename + ": decoder wraps without stopping")
	var loops := playback.get_loop_count()
	playback.seek(stream.get_length() - 0.05)
	playback.mix_audio(1.0, frames)
	check(playback.is_playing() and playback.get_loop_count() > loops, filename + ": subsequent loop remains active")
	playback.stop()


func run_suite(main) -> Dictionary:
	checks = 0
	failures.clear()
	observations.clear()
	finished_events = 0
	var tree: SceneTree = main.get_tree()
	var save = main.get_node("/root/Save")
	var sfx = main.get_node("/root/Sfx")
	if not save.PATH.begins_with("res://.test-user/"):
		return {"error": "Use an isolated fixture with res://.test-user/ save paths."}
	var preferences := {"music": save.music, "music_volume": save.music_volume, "sound": save.sound}
	save.sound = false
	save.music = true
	save.music_volume = 0.7
	sfx.set_platform_paused(false)
	sfx.apply_volumes()
	sfx.update_music()
	check_decoder(sfx.MUSIC, "classic theme loop.ogg", 85.333333)
	check_decoder(sfx.MUSIC_BRIGHT, "bright run theme loop.ogg", 76.8)
	check(not FileAccess.file_exists("res://assets/audio/music.wav") and not FileAccess.file_exists("res://assets/audio/music_bright.wav"), "obsolete music assets removed")
	for config in [["classic", false], ["bright", false], ["bright", true]]:
		await main.start_game(config[0], config[1])
		var expected: AudioStream = sfx.MUSIC if config[0] == "classic" else sfx.MUSIC_BRIGHT
		check(sfx._music.stream == expected and sfx._music.playing, "real mode selects and plays its theme " + str(config))
		main.pause_game()
		check(sfx._music.playing, "ordinary game pause retains existing music behavior " + str(config))
		main.go_menu()
	for id in ["levels", "puzzle", "tutorial", "zen"]:
		main._use_mode(id)
		check(sfx._music.stream == sfx.MUSIC_BRIGHT, "existing hidden-mode music mapping retained " + id)
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "MusicRegression")
	AudioServer.set_bus_send(bus, "Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	var old_bus: StringName = sfx._music.bus
	sfx._music.bus = "MusicRegression"
	sfx._music.finished.connect(_finished)
	for skin in ["classic", "bright"]:
		sfx.set_skin(skin)
		sfx.update_music()
		await tree.create_timer(0.15).timeout
		capture.clear_buffer()
		sfx._music.seek(sfx._music.stream.get_length() - 0.12)
		await tree.create_timer(0.45).timeout
		var playback: AudioStreamPlayback = sfx._music.get_stream_playback()
		var samples := capture.get_buffer(capture.get_frames_available())
		var audio_peak := peak(samples)
		check(samples.size() > 0 and audio_peak > 0.001, skin + ": live mixer outputs non-silent PCM across loop")
		check(sfx._music.playing and playback.get_loop_count() >= 1 and sfx._music.get_playback_position() < 1.0, skin + ": real player wraps and keeps playing")
		check(finished_events == 0, skin + ": looping never emits finished or restarts the player")
		observations.append({"skin": skin, "track": sfx._music.stream.resource_path, "length": sfx._music.stream.get_length(),
			"loops": playback.get_loop_count(), "captured_frames": samples.size(), "peak": audio_peak})
		var before: float = sfx._music.get_playback_position()
		sfx.set_skin(skin)
		check(sfx._music.get_stream_playback() == playback and sfx._music.get_playback_position() >= before, skin + ": selecting same theme preserves playback")
		save.music_volume = 0.25
		sfx.apply_volumes()
		check(is_equal_approx(sfx._music.volume_db, -9.0 + linear_to_db(0.25)), skin + ": existing volume curve retained")
		save.music = false
		sfx.update_music()
		check(not sfx._music.playing, skin + ": music switch stops playback")
		sfx.set_skin("bright" if skin == "classic" else "classic")
		check(not sfx._music.playing, skin + ": changing mode respects disabled music")
		save.music = true
		for volume in [0.0, 0.01]:
			save.music_volume = volume
			sfx.apply_volumes()
			sfx.update_music()
			check(not sfx._music.playing, skin + ": existing low-volume cutoff " + str(volume))
		save.music_volume = 0.7
		sfx.apply_volumes()
		sfx.update_music()
		check(sfx._music.playing, skin + ": music resumes independently of disabled effects")
		sfx.set_platform_paused(true)
		check(not sfx._music.playing and AudioServer.is_bus_mute(0), skin + ": platform pause silences music")
		sfx.set_platform_paused(false)
		check(sfx._music.playing and not AudioServer.is_bus_mute(0), skin + ": platform resume restores music")
	sfx._music.finished.disconnect(_finished)
	sfx._music.bus = old_bus
	AudioServer.remove_bus(bus)
	for key in preferences:
		save.set(key, preferences[key])
	sfx.apply_volumes()
	sfx.update_music()
	main._use_mode("classic")
	return {"checks": checks, "failed": failures.size(), "failures": failures, "observations": observations,
		"audio_driver": AudioServer.get_driver_name(), "platform": OS.get_name()}
