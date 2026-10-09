extends Node

const Speech = preload("res://Scripts/pronunciation_service.gd")
const SpeechURLs = preload("res://Scripts/speech_url_cache.gd")

class TimedSpeech extends "res://Scripts/pronunciation_service.gd":
	var requests: Array = []
	func _fetch(url: String, token: int) -> Dictionary:
		var start := Time.get_ticks_msec()
		var response: Dictionary = await super._fetch(url, token)
		var endpoint := "dict" if url.begins_with(DICTIONARY_ENDPOINT) else ("trans" if url.begins_with(SPEECH_ENDPOINT) else "tts")
		requests.append({"endpoint": endpoint, "milliseconds": Time.get_ticks_msec() - start, "ok": response.get("ok", false), "status": response.get("http_status", 200 if response.get("ok", false) else 0)})
		return response

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var mode := "baseline" if OS.get_cmdline_user_args().has("--baseline") else "optimized"
	var results: Array = []
	var failed := false
	if OS.get_cmdline_user_args().has("--reuse-translation"):
		mode = "reused-translation"
		var reuse: Dictionary = await measure_translation_urls()
		results = reuse.results
		failed = reuse.failed
		save_results(results, mode, failed)
		return
	var cases := [
		["english_word", "manipulate", "en"],
		["chinese_word", "你好", "zh-CN"],
		["chinese_sentence", "这是一个中文译文的朗读测试。请把完整的句子读出来。", "zh-CN"],
		["english_sentence", "This is a test of the source language pronunciation. Please read the whole sentence clearly.", "en"]
	]
	for item in cases:
		for repetition in 3:
			SpeechURLs.clear()
			var speech := TimedSpeech.new()
			add_child(speech)
			speech._player.volume_db = -80.0
			var start := Time.get_ticks_msec()
			var error: String = await speech.speak(item[1], item[2])
			var elapsed := Time.get_ticks_msec() - start
			var value := {"mode": mode, "case": item[0], "repetition": repetition + 1, "first_audio_ms": elapsed, "requests": speech.requests.duplicate(true), "error": error, "duration": speech._player.stream.get_length() if speech._player.stream != null else 0.0}
			failed = failed or not error.is_empty() or not speech._player.playing
			results.append(value)
			print("SPEECH_PERFORMANCE " + JSON.stringify(value))
			speech.stop()
			speech.queue_free()
			await get_tree().process_frame
	save_results(results, mode, failed)

func measure_translation_urls() -> Dictionary:
	var results: Array = []
	var failed := false
	for item in [
		["chinese_sentence", "这是一个中文译文的朗读测试。请把完整的句子读出来。", "zh-CN", "en"],
		["english_sentence", "This is a test of the source language pronunciation. Please read the whole sentence clearly.", "en", "zh-CN"]
	]:
		SpeechURLs.clear()
		var request := TimedSpeech.new()
		add_child(request)
		var url := Speech.SPEECH_ENDPOINT + "?q=" + str(item[1]).uri_encode() + "&from=" + GriddyTranslationService.youdao_language(item[2]) + "&to=" + GriddyTranslationService.youdao_language(item[3])
		var response: Dictionary = await request._fetch(url, request._revision)
		request.queue_free()
		if not response.get("ok", false):
			failed = true
			continue
		var payload = JSON.parse_string(response.body.get_string_from_utf8())
		if not payload is Dictionary or str(payload.get("errorCode", "")) != "0":
			failed = true
			continue
		var translated := "\n".join(PackedStringArray(payload.get("translation", [])))
		SpeechURLs.put(item[1], item[2], payload.get("speakUrl", ""))
		SpeechURLs.put(translated, item[3], payload.get("tSpeakUrl", ""))
		for side in [["original", item[1], item[2]], ["translation", translated, item[3]]]:
			for repetition in 3:
				var speech := TimedSpeech.new()
				add_child(speech)
				speech._player.volume_db = -80.0
				var start := Time.get_ticks_msec()
				var error: String = await speech.speak(side[1], side[2])
				var elapsed := Time.get_ticks_msec() - start
				var count := speech.requests.size()
				speech.stop()
				start = Time.get_ticks_msec()
				await speech.speak(side[1], side[2])
				var replay := Time.get_ticks_msec() - start
				var value := {"mode": "reused-translation", "case": item[0] + "_" + side[0], "repetition": repetition + 1, "first_audio_ms": elapsed, "replay_ms": replay, "requests": speech.requests.duplicate(true), "error": error, "duration": speech._player.stream.get_length() if speech._player.stream != null else 0.0}
				failed = failed or not error.is_empty() or count != 1 or speech.requests.size() != count or not speech._player.playing
				results.append(value)
				print("SPEECH_PERFORMANCE " + JSON.stringify(value))
				speech.stop()
				speech.queue_free()
				await get_tree().process_frame
	return {"results": results, "failed": failed}

func save_results(results: Array, mode: String, failed: bool) -> void:
	var output := OS.get_environment("GRIDDY_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../qa")
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("speech-performance-" + mode + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("SPEECH_PERFORMANCE_COMPLETE failures=" + str(1 if failed else 0))
	get_tree().quit(1 if failed else 0)
