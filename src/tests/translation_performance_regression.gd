extends Node

const Service = preload("res://Scripts/translation_service.gd")
const SpeechURLs = preload("res://Scripts/speech_url_cache.gd")
var failures := 0
var app: Node

class ControlledTransport extends Service:
	var calls: Array = []
	var active := 0
	var peak := 0
	var finished: Array[String] = []
	func _transport(value: String, source: String, target: String, selected_provider: String, token: int) -> Dictionary:
		calls.append([selected_provider, source, target, value])
		active += 1
		peak = maxi(peak, active)
		var delay := 90 if value.begins_with("A") else 20
		if value.begins_with("HOLD"): delay = 1500
		var until := Time.get_ticks_msec() + delay
		while Time.get_ticks_msec() < until and token == _generation:
			await get_tree().process_frame
		active -= 1
		if token != _generation: return _cancelled()
		finished.append(value.substr(0, 1))
		if value.begins_with("FAIL"): return {"ok": false, "error": "controlled chunk failure"}
		if selected_provider == "mymemory": return {"ok": true, "payload": {"responseStatus": 200, "responseData": {"translatedText": value}}}
		return {"ok": true, "payload": {"errorCode": "0", "query": value, "translation": [value], "l": youdao_language(source) + "2" + youdao_language(target)}}

func _ready() -> void:
	app = get_parent()
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func collect_chunk(service: Node, value: String, results: Dictionary, label: String) -> void:
	results[label] = await service.translate_chunk(value, "en", "zh-CN")

func collect_text(service: Node, value: String, results: Dictionary, label: String) -> void:
	results[label] = await service.translate_text(value, "en", "zh-CN")

func wait_for(results: Dictionary, count: int) -> void:
	while results.size() < count: await get_tree().process_frame

func run() -> void:
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	await get_tree().create_timer(0.5).timeout
	LuaSingleton.change_setting("music", false)
	var unicode := "原文🙂 café。".repeat(500)
	var youdao_chunks := Service.split_for_provider(unicode, "youdao")
	var memory_chunks := Service.split_for_provider(unicode, "mymemory")
	check("".join(youdao_chunks) == unicode and "".join(memory_chunks) == unicode, "provider-aware splitting preserves all Unicode and whitespace")
	check(youdao_chunks.all(func(piece: String): return piece.to_utf16_buffer().size() / 2 <= 1000), "Youdao chunks respect the verified 1000 UTF16 unit limit")
	check(memory_chunks.all(func(piece: String): return piece.to_utf8_buffer().size() <= 450), "MyMemory keeps its 450-byte request limit")
	check(youdao_chunks.size() < memory_chunks.size(), "Youdao avoids the previous excessive UTF8 byte segmentation")
	var transport := ControlledTransport.new()
	add_child(transport)
	var long_text := "A".repeat(1000) + "B".repeat(1000) + "C".repeat(1000)
	var result: Dictionary = await transport.translate_text(long_text, "en", "zh-CN")
	check(result.ok and result.text == long_text and transport.finished[0] == "B", "concurrent chunks finish out of order and are combined in original order")
	check(transport.peak == 2 and transport.active == 0, "long translation uses at most two simultaneous requests")
	var duplicate_results := {}
	collect_chunk(transport, "same pending sentence", duplicate_results, "one")
	collect_chunk(transport, "same pending sentence", duplicate_results, "two")
	await wait_for(duplicate_results, 2)
	check(transport.calls.filter(func(call: Array): return call[3] == "same pending sentence").size() == 1 and duplicate_results.one == duplicate_results.two, "identical pending requests share a single provider request")
	var count := transport.calls.size()
	result = await transport.translate_chunk("same pending sentence", "en", "zh-CN")
	check(result.ok and result.get("cache_hit", false) and transport.calls.size() == count, "repeated successful translation uses the cache without network")
	transport.provider = "mymemory"
	result = await transport.translate_chunk("same pending sentence", "en", "zh-CN")
	check(result.ok and transport.calls.size() == count + 1 and transport.cache.keys().any(func(key: String): return key.begins_with("youdao:")) and transport.cache.keys().any(func(key: String): return key.begins_with("mymemory:")), "translation cache keys keep provider namespaces separate")
	transport.queue_free()
	await get_tree().process_frame
	transport = ControlledTransport.new()
	add_child(transport)
	var independent := {}
	for index in 5: collect_chunk(transport, "independent " + str(index), independent, str(index))
	await wait_for(independent, 5)
	check(transport.peak == 2 and transport.calls.size() == 5, "global request limit also bounds independent chunk callers")
	var cancelled := {}
	collect_chunk(transport, "HOLD cancellation", cancelled, "one")
	collect_chunk(transport, "HOLD cancellation", cancelled, "two")
	await get_tree().create_timer(0.02).timeout
	var cancellation_started := Time.get_ticks_msec()
	transport.cancel()
	await wait_for(cancelled, 2)
	check(cancelled.one.get("cancelled", false) and cancelled.two.get("cancelled", false) and Time.get_ticks_msec() - cancellation_started < 150, "cancel immediately wakes every caller of a shared pending request")
	var cancelled_text := {}
	collect_text(transport, "HOLD" + "x".repeat(996) + "B".repeat(1000) + "C".repeat(1000), cancelled_text, "batch")
	await get_tree().create_timer(0.02).timeout
	transport.cancel()
	await wait_for(cancelled_text, 1)
	check(cancelled_text.batch.get("cancelled", false), "cancel stops a multi-chunk translation without returning partial text")
	await get_tree().create_timer(0.02).timeout
	check(transport.active == 0 and transport._active_fetches == 0 and transport._pending.is_empty(), "cancel releases all active request slots and pending records")
	check(not transport.cache.has("youdao:en:zh-CN:HOLD cancellation"), "cancelled responses never enter the successful translation cache")
	transport.cache.clear()
	var failure_start := Time.get_ticks_msec()
	result = await transport.translate_text("FAIL" + "x".repeat(996) + "HOLD" + "x".repeat(996), "en", "zh-CN")
	await get_tree().create_timer(0.02).timeout
	check(not result.ok and result.error == "controlled chunk failure" and Time.get_ticks_msec() - failure_start < 200 and transport.active == 0, "first chunk failure cancels outstanding work so retry inherits no timeout slot")
	var truncated: Dictionary = transport._parse_payload({"errorCode": "0", "query": "short", "translation": ["译文"]}, "complete source", "en", "zh-CN", "youdao")
	check(not truncated.ok, "provider query echo detects a silently shortened input")
	test_speech_registry(transport)
	transport.cancel()
	await get_tree().process_frame
	transport.queue_free()
	if OS.get_cmdline_user_args().has("--benchmark"): await benchmark_live()
	await get_tree().process_frame
	print("TRANSLATION_PERFORMANCE_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)

func voice_url(value: String, language: String) -> String:
	return "https://openapi.youdao.com/ttsapi?q=" + value.uri_encode() + "&langType=" + language.uri_encode()

func test_speech_registry(transport: Node) -> void:
	SpeechURLs.clear()
	var source := "A complete sentence with spaces and a + sign."
	var translated := "这是完整译文。"
	var payload := {"errorCode": "0", "query": source, "translation": [translated], "l": "en2zh-CHS", "speakUrl": voice_url(source, "en-USA"), "tSpeakUrl": voice_url(translated, "zh-CHS")}
	var result: Dictionary = transport._parse_payload(payload, source, "en", "zh-CN", "youdao")
	check(result.ok and not SpeechURLs.get_url(source, "en").is_empty() and not SpeechURLs.get_url(translated, "zh-CN").is_empty(), "successful translation shares validated original and translated speech URLs")
	check(SpeechURLs.get_url(source, "zh-CN").is_empty() and SpeechURLs.get_url(source, "en", "mymemory").is_empty(), "speech URL keys do not mix languages or providers")
	SpeechURLs.put("wrong full snapshot", "en", voice_url("wrong full", "en-USA"))
	check(SpeechURLs.get_url("wrong full snapshot", "en").is_empty(), "a truncated speech URL cannot masquerade as the full text")
	SpeechURLs.put("wrong language", "en", voice_url("wrong language", "zh-CHS"))
	check(SpeechURLs.get_url("wrong language", "en").is_empty(), "URL language must match the requested speech language")
	SpeechURLs.put("這是繁體中文。", "zh-TW", voice_url("這是繁體中文。", "zh-CHS"))
	check(not SpeechURLs.get_url("這是繁體中文。", "zh-TW").is_empty() and SpeechURLs.get_url("這是繁體中文。", "zh-CN").is_empty(), "Mandarin voice accepts traditional text without merging Chinese writing-system cache keys")
	for pair in [["ja", "ja-JPN"], ["ko", "ko-KOR"], ["fr", "fr-FRA"], ["de", "de-DEU"], ["ru", "ru-RUS"], ["es", "es-ESP"], ["pt", "pt-PRT"], ["it", "it-ITA"]]:
		var text := "locale fixture " + str(pair[0])
		SpeechURLs.put(text, pair[0], voice_url(text, pair[1]))
		check(not SpeechURLs.get_url(text, pair[0]).is_empty() and SpeechURLs.get_url(text, "en").is_empty(), "regional voice alias " + str(pair[1]) + " matches only its language")
	SpeechURLs.erase(source, "en")
	check(SpeechURLs.get_url(source, "en").is_empty(), "an expired signed URL can be explicitly invalidated")
	for index in 70:
		var text := "entry " + str(index)
		SpeechURLs.put(text, "en", voice_url(text, "en-USA"))
	check(SpeechURLs._entries.size() == 64 and SpeechURLs.get_url("entry 0", "en").is_empty(), "speech URL registry stays bounded and evicts oldest entries")
	for key in SpeechURLs._entries.keys(): SpeechURLs._entries[key].expires = Time.get_ticks_msec() - 1
	check(SpeechURLs.get_url("entry 69", "en").is_empty() and SpeechURLs._entries.is_empty(), "signed URLs expire before stale links can be reused")

func benchmark_live() -> void:
	# This optional source-only comparison lives in qa. The packaged suite
	# above has no external files or developer-machine dependency.
	var path := ProjectSettings.globalize_path("res://").path_join("../qa/translation-performance-probe/baseline_service.gd")
	if not FileAccess.file_exists(path):
		print("BENCHMARK baseline unavailable outside the source checkout")
		return
	var legacy: Node = load(path).new()
	var current := Service.new()
	add_child(legacy)
	add_child(current)
	var paragraph := "First marker ORBITALALPHA.\n"
	for index in 26: paragraph += "Section %02d: the translator must preserve this sentence completely and respond quickly.\n" % index
	paragraph += "Last marker NEBULAFINISH."
	for value in ["manipulate", "The software should respond quickly when I translate a sentence.", paragraph]:
		var source := Service.detect_language(value)
		var target := "en" if source == "zh-CN" else "zh-CN"
		var started := Time.get_ticks_msec()
		var old_ok := true
		var old_error := ""
		for piece in Service.split_chunks(value):
			var result: Dictionary = await legacy.translate_chunk(piece, source, target)
			if not result.ok:
				old_ok = false
				old_error = str(result.get("error", ""))
				break
		var old_msec := Time.get_ticks_msec() - started
		started = Time.get_ticks_msec()
		var result: Dictionary = await current.translate_text(value, source, target)
		var new_msec := Time.get_ticks_msec() - started
		print("BENCHMARK " + JSON.stringify({"chars": value.length(), "bytes": value.to_utf8_buffer().size(), "source": source, "target": target, "old_chunks": Service.split_chunks(value).size(), "new_chunks": Service.split_for_provider(value, "youdao").size(), "old_msec": old_msec, "new_msec": new_msec, "old_ok": old_ok, "new_ok": result.ok, "old_error": old_error, "new_error": str(result.get("error", ""))}))
		check(old_ok and result.ok and not str(result.get("text", "")).is_empty(), "live old/new requests both return usable translations")
	current.cancel()
	await get_tree().create_timer(0.05).timeout
	legacy.queue_free()
	current.queue_free()
	await get_tree().process_frame
