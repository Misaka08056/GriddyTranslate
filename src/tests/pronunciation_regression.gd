extends Node

const Speech = preload("res://Scripts/pronunciation_service.gd")
const SpeechURLs = preload("res://Scripts/speech_url_cache.gd")
var failures := 0
var app: Node2D
var code: CodeEdit

class FakePronunciation extends Node:
	signal playback_failed(message: String)
	var requests: Array = []
	var stops := 0
	func speak(text: String, language: String) -> String:
		requests.append([text, language])
		await get_tree().create_timer(0.01).timeout
		return ""
	func stop() -> void:
		stops += 1

class DelayedSpeech extends GriddyPronunciationService:
	var played: Array[String] = []
	var previous: AudioStream
	func _load_audio(text: String, _language: String, token: int) -> Dictionary:
		await get_tree().create_timer(0.20 if text == "stale source" else 0.02).timeout
		if token != _revision: return {}
		var wave := AudioStreamWAV.new()
		wave.format = AudioStreamWAV.FORMAT_16_BITS
		wave.mix_rate = 16000
		var silence := PackedByteArray()
		silence.resize(12800)
		wave.data = silence
		wave.set_meta("snapshot", text)
		return {"ok": true, "stream": wave}
	func _process(_delta: float) -> void:
		if is_instance_valid(_player) and _player.playing and _player.stream != previous:
			previous = _player.stream
			played.append(str(previous.get_meta("snapshot")))

class MockSpeech extends "res://Scripts/pronunciation_service.gd":
	var fetches: Array[String] = []
	var wav := PackedByteArray()
	var text := ""
	var language := "zh-CN"
	var fail_first := ""
	var fail_all_audio := false
	var fail_dictionary := false
	func _fetch(url: String, token: int) -> Dictionary:
		fetches.append(url)
		await get_tree().create_timer(0.01).timeout
		if token != _revision: return {}
		if url.begins_with(DICTIONARY_ENDPOINT) and fail_dictionary:
			return {"ok": false, "http_status": 500, "error": "no dictionary recording"}
		if fetches.size() == 1 and fail_first == "json":
			return {"ok": true, "body": '{"errorCode":"202"}'.to_utf8_buffer()}
		if fetches.size() == 1 and fail_first == "403":
			return {"ok": false, "http_status": 403, "error": "expired signature"}
		if url.begins_with(SPEECH_ENDPOINT):
			var voice_language := "zh-CHS" if language == "zh-CN" else language
			var signed := "https://openapi.youdao.com/ttsapi?q=" + text.uri_encode() + "&langType=" + voice_language + "&sign=refreshed"
			return {"ok": true, "body": JSON.stringify({"errorCode": "0", "speakUrl": signed}).to_utf8_buffer()}
		if fail_all_audio: return {"ok": true, "body": '{"errorCode":"203"}'.to_utf8_buffer()}
		return {"ok": true, "body": wav}

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	if OS.get_cmdline_user_args().has("--pronunciation-performance"):
		add_child(load("res://tests/pronunciation_performance.gd").new())
		return
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func shortcut(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = true
	event.pressed = true
	app._input(event)

func run() -> void:
	await get_tree().create_timer(0.5).timeout
	LuaSingleton.change_setting("music", false)
	await test_shortcuts()
	await test_replacement_and_segments()
	await test_shared_speech_urls()
	await test_online_audio()
	print("PRONUNCIATION_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)

func test_shortcuts() -> void:
	var real: Node = app.pronunciation
	real.stop()
	var fake := FakePronunciation.new()
	app.add_child(fake)
	app.pronunciation = fake
	app.auto_translate = false
	app.showing_translation = false
	app.source_language = "auto"
	app.translated_text = ""
	code.editable = true
	code.text = "This is the complete source sentence."
	app.on_source_changed()
	var original: String = code.text
	shortcut(KEY_P)
	await get_tree().create_timer(0.04).timeout
	check(fake.requests == [[original, "en"]], "Ctrl+P speaks the exact input snapshot with detected original language")
	check(code.text == original, "Ctrl+P preserves input text")
	shortcut(KEY_O)
	await get_tree().create_timer(0.04).timeout
	check(fake.requests.size() == 1 and code.text == original, "Ctrl+O without translation does not speak input or alter it")
	app.source_text = original
	app.result_source_text = original
	app.translated_text = "这是完整的译文。"
	app.last_target = "zh-CN"
	app.target_language = "ja"
	app.translation_placement = 1
	app._display(true)
	var combined: String = code.text
	shortcut(KEY_O)
	await get_tree().create_timer(0.04).timeout
	check(not fake.requests.is_empty() and fake.requests.back() == ["这是完整的译文。", "zh-CN"], "Ctrl+O reads only translation using its actual generated language")
	shortcut(KEY_P)
	await get_tree().create_timer(0.04).timeout
	check(not fake.requests.is_empty() and fake.requests.back() == [original, "en"] and code.text == combined, "Ctrl+P on the combined view reads retained original without changing view")
	shortcut(KEY_L)
	await get_tree().create_timer(code.panel_duration() + 0.10).timeout
	check(code.active_overlay == app.file_dialog and app.file_dialog.active, "Ctrl+L still opens the language selector")
	shortcut(KEY_ESCAPE)
	await get_tree().create_timer(code.panel_duration() + 0.10).timeout
	check(code.active_overlay == null and code.text == combined, "language selector closes without losing translation text")
	app.pronunciation = real
	fake.queue_free()

func test_replacement_and_segments() -> void:
	var speech := DelayedSpeech.new()
	add_child(speech)
	speech._player.volume_db = -80.0
	speech.speak("stale source", "en")
	await get_tree().create_timer(0.03).timeout
	var error: String = await speech.speak("new snapshot", "en")
	await get_tree().create_timer(0.23).timeout
	check(error.is_empty() and speech.played == ["new snapshot"], "a new read cancels an older pending snapshot so stale audio never plays")
	speech.stop()
	speech.played.clear()
	speech.previous = null
	var text := "Read the entire original sentence. ".repeat(28).strip_edges()
	var segments := Speech.split_segments(text)
	check(segments.size() > 1 and "".join(segments) == text, "long text segments preserve the entire source in order")
	var within_limit := true
	for segment in segments:
		within_limit = within_limit and segment.to_utf8_buffer().size() <= Speech.MAX_SEGMENT_BYTES
	check(within_limit, "speech segments fit the service UTF-8 limit")
	await speech.speak(text, "en")
	await get_tree().create_timer(2.0).timeout
	print("SPEECH_SEGMENTS expected=" + str(segments.size()) + " played=" + str(speech.played.size()))
	check(speech.played == segments, "all long-text audio segments actually play sequentially")
	speech.speak("stale source", "en")
	await get_tree().create_timer(0.03).timeout
	speech.stop()
	var count := speech.played.size()
	await get_tree().create_timer(0.23).timeout
	check(not speech._player.playing and speech.played.size() == count, "stop cancels playback and pending results")
	speech.queue_free()

func test_online_audio() -> void:
	var speech := Speech.new()
	add_child(speech)
	speech._player.volume_db = -80.0
	var cases := [
		["manipulate", "en", 0.4],
		["你好", "zh-CN", 0.3],
		["This is a test of the source language pronunciation. Please read the whole sentence clearly.", "en", 4.0],
		["这是一个中文译文的朗读测试。请把完整的句子读出来。", "zh-CN", 4.0]
	]
	for item in cases:
		var error: String = await speech.speak(item[0], item[1])
		check(error.is_empty(), "live Youdao speech request succeeds for " + item[1] + " (" + str(item[0].length()) + " characters): " + error)
		var playing: bool = speech._player.playing and speech._player.stream != null
		check(playing, "decoded online audio enters AudioStreamPlayer playback")
		if playing:
			var duration: float = speech._player.stream.get_length()
			print("SPEECH_DURATION language=" + item[1] + " characters=" + str(item[0].length()) + " seconds=" + str(duration))
			check(duration >= item[2], "online recording duration covers the requested text rather than one keyword")
		speech.stop()
	var error: String = await speech.speak("manipulate", "en")
	var cached: AudioStream = speech._player.stream
	speech.stop()
	error = await speech.speak("manipulate", "en")
	check(error.is_empty() and speech._player.stream == cached, "repeated speech uses bounded in-memory audio cache")
	speech.stop()
	var result: Dictionary = await speech._fetch("http://127.0.0.1:1/unavailable", speech._revision)
	check(not result.get("ok", false) and not result.get("error", "").is_empty(), "failed network request returns a readable error")
	check(Speech.decode_audio("<html>not audio at all</html>".to_utf8_buffer()) == null, "invalid service response cannot become audio")
	var cancellation := {"returned": false}
	observe_cancelled_speech(speech, cancellation)
	check(is_instance_valid(speech._request), "speech opens a cancellable asynchronous HTTP request")
	speech.stop()
	await get_tree().create_timer(0.10).timeout
	check(cancellation.returned and speech._request == null and not speech._player.playing, "cancel_request releases the old coroutine without a completion signal or stale playback")
	speech.queue_free()

func wave_fixture() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(6444)
	for position in [0, 8, 12, 36]:
		var text: String = {0: "RIFF", 8: "WAVE", 12: "fmt ", 36: "data"}[position]
		var bytes := text.to_ascii_buffer()
		for index in 4: data[position + index] = bytes[index]
	data.encode_u32(4, data.size() - 8)
	data.encode_u32(16, 16)
	data.encode_u16(20, 1)
	data.encode_u16(22, 1)
	data.encode_u32(24, 16000)
	data.encode_u32(28, 32000)
	data.encode_u16(32, 2)
	data.encode_u16(34, 16)
	data.encode_u32(40, data.size() - 44)
	return data

func mock_speech(text: String, language: String = "zh-CN") -> MockSpeech:
	var speech := MockSpeech.new()
	speech.wav = wave_fixture()
	speech.text = text
	speech.language = language
	add_child(speech)
	speech._player.volume_db = -80.0
	return speech

func fixture_url(text: String, language: String = "zh-CN") -> String:
	var voice_language := "zh-CHS" if language == "zh-CN" else ("en-USA" if language == "en" else language)
	return "https://openapi.youdao.com/ttsapi?q=" + text.uri_encode() + "&langType=" + voice_language + "&sign=original"

func test_shared_speech_urls() -> void:
	SpeechURLs.clear()
	var full := "这是已经请求过翻译的完整原文，点击朗读应直接下载对应音频。".repeat(12)
	var url := fixture_url(full)
	SpeechURLs.put(full, "zh-CHS", url)
	var speech := mock_speech(full)
	check(speech.fetches.is_empty(), "recording a translation voice URL does not send a background audio request")
	var error: String = await speech.speak("  " + full + "\n", "zh-CN")
	check(error.is_empty() and speech.fetches == [url] and speech._player.playing, "exact full-text registered voice plays with one request even above the fallback segment limit")
	var first_audio: AudioStream = speech._player.stream
	speech.stop()
	error = await speech.speak(full, "zh-CN")
	check(error.is_empty() and speech.fetches.size() == 1 and speech._player.stream == first_audio, "repeated registered speech starts from audio memory without another request")
	speech.stop()
	speech.queue_free()
	SpeechURLs.clear()
	var sentence := "这是需要完整朗读的中文句子。"
	SpeechURLs.put(sentence, "en", fixture_url(sentence, "en"))
	SpeechURLs.put(sentence, "zh-CN", fixture_url(sentence), "mymemory")
	speech = mock_speech(sentence)
	error = await speech.speak(sentence, "zh-CN")
	check(error.is_empty() and speech.fetches.size() == 2 and speech.fetches[0].begins_with(Speech.SPEECH_ENDPOINT), "different language or provider metadata cannot supply the current voice snapshot")
	speech.stop()
	speech.queue_free()
	for failure in ["403", "json"]:
		SpeechURLs.clear()
		SpeechURLs.put(sentence, "zh-CN", fixture_url(sentence))
		speech = mock_speech(sentence)
		speech.fail_first = failure
		error = await speech.speak(sentence, "zh-CN")
		check(error.is_empty() and speech.fetches.size() == 3 and speech.fetches[1].begins_with(Speech.SPEECH_ENDPOINT), "expired " + failure + " voice signature refreshes once through the same Youdao service")
		speech.stop()
		speech.queue_free()
	SpeechURLs.clear()
	SpeechURLs.put(sentence, "zh-CN", fixture_url(sentence))
	speech = mock_speech(sentence)
	speech.fail_all_audio = true
	error = await speech.speak(sentence, "zh-CN")
	check(not error.is_empty() and speech.fetches.size() == 3 and not speech._player.playing, "invalid refreshed audio fails clearly after one refresh instead of retrying indefinitely")
	speech.queue_free()
	SpeechURLs.clear()
	SpeechURLs.put(sentence, "zh-CN", fixture_url(sentence))
	for key in SpeechURLs._entries: SpeechURLs._entries[key].expires = 0
	speech = mock_speech(sentence)
	error = await speech.speak(sentence, "zh-CN")
	check(error.is_empty() and speech.fetches.size() == 2 and speech.fetches[0].begins_with(Speech.SPEECH_ENDPOINT), "expired metadata is discarded before making an audio request")
	speech.stop()
	speech.queue_free()
	check(Speech.is_dictionary_query("manipulate", "en") and Speech.is_dictionary_query("你好", "zh-CN"), "recorded dictionary words retain their direct fast path")
	check(not Speech.is_dictionary_query("hello world", "en") and not Speech.is_dictionary_query(sentence, "zh-CN"), "sentences and phrases skip the unnecessary dictionary HTTP 500 attempt")
	for item in [["manipulate", "en"], ["你好", "zh-CN"]]:
		SpeechURLs.clear()
		var word_url := fixture_url(item[0], item[1])
		SpeechURLs.put(item[0], item[1], word_url)
		speech = mock_speech(item[0], item[1])
		error = await speech.speak(item[0], item[1])
		check(error.is_empty() and speech.fetches.size() == 1 and speech.fetches[0].begins_with(Speech.DICTIONARY_ENDPOINT), "translated " + item[1] + " word keeps the faster direct dictionary recording")
		speech.stop()
		speech.queue_free()
		speech = mock_speech(item[0], item[1])
		speech.fail_dictionary = true
		error = await speech.speak(item[0], item[1])
		check(error.is_empty() and speech.fetches.size() == 2 and speech.fetches[1] == word_url, "missing dictionary recording reuses the existing signed word URL without another translation")
		speech.stop()
		speech.queue_free()
	SpeechURLs.clear()

func observe_cancelled_speech(speech: Node, state: Dictionary) -> void:
	await speech.speak("This is a unique full sentence used to verify cancellation of a pending online speech request.", "en")
	state.returned = true
