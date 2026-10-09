extends Node
class_name GriddyTranslationService

const SpeechURLs = preload("res://Scripts/speech_url_cache.gd")
# MyMemory limits q to 500 UTF-8 bytes. The public Youdao demo accepts at
# most 1000 characters; POST avoids the encoded GET URL length limit.
const ENDPOINT = "https://api.mymemory.translated.net/get"
const YOUDAO_ENDPOINT := "https://aidemo.youdao.com/trans"
const PROVIDERS := ["mymemory", "youdao"]
const MAX_BYTES = 450
var cache: Dictionary = {}
var provider := "youdao"
const YOUDAO_MAX_UNITS := 1000
const MAX_CONCURRENT := 2
var _generation := 0
var _job_id := 0
var _pending: Dictionary = {}
var _requests: Array[HTTPRequest] = []
var _active_fetches := 0

static func youdao_language(language: String) -> String:
	if language == "zh-CN": return "zh-CHS"
	if language == "zh-TW": return "zh-CHT"
	return language

static func detect_language(value: String) -> String:
	var han := 0
	var latin := 0
	for i in value.length():
		var c := value.unicode_at(i)
		if c >= 0x3040 and c <= 0x30ff: return "ja"
		if c >= 0xac00 and c <= 0xd7af: return "ko"
		if c >= 0x0400 and c <= 0x04ff: return "ru"
		if c >= 0x4e00 and c <= 0x9fff: han += 1
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122): latin += 1
	return "zh-CN" if han > 0 and han * 3 >= latin else "en"

static func split_chunks(value: String) -> Array[String]:
	var chunks: Array[String] = []
	var current := ""
	var byte_count := 0
	for character in value:
		var char_bytes: int = character.to_utf8_buffer().size()
		if byte_count + char_bytes > MAX_BYTES:
			chunks.append(current)
			current = ""
			byte_count = 0
		current += character
		byte_count += char_bytes
		if byte_count >= 280 and character in ["。", "！", "？", ".", "!", "?", "\n"]:
			chunks.append(current)
			current = ""
			byte_count = 0
	if not current.is_empty(): chunks.append(current)
	return chunks

static func split_for_provider(value: String, selected_provider: String = "youdao") -> Array[String]:
	if selected_provider != "youdao": return split_chunks(value)
	var chunks: Array[String] = []
	var start := 0
	while start < value.length():
		var end := start
		var units := 0
		var sentence_boundary := -1
		var word_boundary := -1
		while end < value.length():
			var char_units := 2 if value.unicode_at(end) > 0xffff else 1
			if units + char_units > YOUDAO_MAX_UNITS: break
			units += char_units
			var character := value.substr(end, 1)
			end += 1
			if units >= 600:
				if character in ["。", "！", "？", ".", "!", "?", "\n"]: sentence_boundary = end
				if character in [" ", "\t", "\r", "\n"]: word_boundary = end
		if end < value.length():
			if sentence_boundary > start: end = sentence_boundary
			elif word_boundary > start: end = word_boundary
		chunks.append(value.substr(start, end - start))
		start = end
	return chunks

func cancel() -> void:
	_generation += 1
	for request in _requests:
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_requests.clear()
	for state in _pending.values():
		state.result = _cancelled()
		state.done = true
	_pending.clear()

func _exit_tree() -> void:
	cancel()

func _cancelled() -> Dictionary:
	return {"ok": false, "cancelled": true, "error": ""}

func translate_chunk(value: String, source: String, target: String) -> Dictionary:
	var selected_provider := provider
	var token := _generation
	var key := selected_provider + ":" + source + ":" + target + ":" + value
	if cache.has(key): return {"ok": true, "text": cache[key], "cache_hit": true}
	var state: Dictionary
	if _pending.has(key):
		state = _pending[key]
	else:
		_job_id += 1
		state = {"id": _job_id, "done": false, "result": {}}
		_pending[key] = state
		_run_pending(key, state, value, source, target, selected_provider, token)
	# HTTPRequest.cancel_request does not emit request_completed. The explicit
	# state and generation wake every caller, including coalesced requests.
	while not state.done and token == _generation:
		await get_tree().process_frame
	if token != _generation: return _cancelled()
	return state.result.duplicate()

func _run_pending(key: String, state: Dictionary, value: String, source: String, target: String, selected_provider: String, token: int) -> void:
	var response: Dictionary = await _request_payload(value, source, target, selected_provider, token)
	var result: Dictionary = _cancelled() if token != _generation else response
	if result.get("ok", false):
		result = _parse_payload(response.payload, value, source, target, selected_provider)
		if result.ok:
			if cache.size() >= 128: cache.erase(cache.keys()[0])
			cache[key] = result.text
	state.result = result
	state.done = true
	if _pending.has(key) and int(_pending[key].id) == int(state.id): _pending.erase(key)

func translate_text(value: String, source: String, target: String) -> Dictionary:
	var selected_provider := provider
	var token := _generation
	var chunks := split_for_provider(value, selected_provider)
	if chunks.is_empty(): return {"ok": true, "text": ""}
	var results: Array = []
	results.resize(chunks.size())
	var state := {"next": 0, "active": 0, "results": results, "error": {}}
	for worker in mini(MAX_CONCURRENT, chunks.size()):
		_translate_worker(chunks, state, source, target, selected_provider, token)
	while int(state.active) > 0 and state.error.is_empty() and token == _generation:
		await get_tree().process_frame
	if token != _generation or provider != selected_provider: return _cancelled()
	if not state.error.is_empty():
		var failure: Dictionary = state.error.duplicate()
		# The app owns one translation operation at a time. Stop its outstanding
		# chunks on failure so an immediate retry cannot inherit a timeout slot.
		cancel()
		return failure
	var combined := ""
	for index in chunks.size():
		var piece := chunks[index]
		if piece.strip_edges().is_empty():
			combined += piece
			continue
		var leading := piece.substr(0, piece.length() - piece.lstrip(" \t\r\n").length())
		var trailing := piece.substr(piece.rstrip(" \t\r\n").length())
		combined += leading + str(state.results[index].text).strip_edges() + trailing
	return {"ok": true, "text": combined}

func _translate_worker(chunks: Array[String], state: Dictionary, source: String, target: String, selected_provider: String, token: int) -> void:
	state.active += 1
	while int(state.next) < chunks.size() and state.error.is_empty() and token == _generation and provider == selected_provider:
		var index := int(state.next)
		state.next += 1
		var piece := chunks[index]
		var result: Dictionary = {"ok": true, "text": piece}
		if not piece.strip_edges().is_empty(): result = await translate_chunk(piece, source, target)
		if token != _generation: break
		state.results[index] = result
		if not result.get("ok", false): state.error = result
	state.active -= 1

func _request_payload(value: String, source: String, target: String, selected_provider: String, token: int) -> Dictionary:
	while _active_fetches >= MAX_CONCURRENT and token == _generation:
		await get_tree().process_frame
	if token != _generation: return _cancelled()
	_active_fetches += 1
	var result: Dictionary = await _transport(value, source, target, selected_provider, token)
	_active_fetches -= 1
	return _cancelled() if token != _generation else result

func _transport(value: String, source: String, target: String, selected_provider: String, token: int) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = 22.0
	request.body_size_limit = 2097152
	add_child(request)
	_requests.append(request)
	var completed := {"done": false, "result": 0, "status": 0, "body": PackedByteArray()}
	request.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		completed.result = result
		completed.status = status
		completed.body = body
		completed.done = true)
	var url := ENDPOINT + "?q=" + value.uri_encode() + "&langpair=" + (source + "|" + target).uri_encode()
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: GriddyTranslate/1.0"])
	var method := HTTPClient.METHOD_GET
	var body := ""
	if selected_provider == "youdao":
		url = YOUDAO_ENDPOINT
		method = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/x-www-form-urlencoded; charset=UTF-8")
		body = "q=" + value.uri_encode() + "&from=" + youdao_language(source).uri_encode() + "&to=" + youdao_language(target).uri_encode()
	var error := request.request(url, headers, method, body)
	if error != OK:
		_requests.erase(request)
		request.queue_free()
		return {"ok": false, "error": "无法发起网络请求。Ctrl+Enter 重试。"}
	while token == _generation and not completed.done:
		await get_tree().process_frame
	_requests.erase(request)
	if is_instance_valid(request) and not request.is_queued_for_deletion(): request.queue_free()
	if token != _generation: return _cancelled()
	if completed.result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "网络连接失败或超时。检查网络后按 Ctrl+Enter 重试。"}
	if completed.status == 429: return {"ok": false, "error": "免费服务请求过于频繁，请稍后重试。"}
	if completed.status != 200: return {"ok": false, "error": "翻译服务暂不可用（HTTP %s）。Ctrl+Enter 重试。" % completed.status}
	var payload = JSON.parse_string(completed.body.get_string_from_utf8())
	if not payload is Dictionary: return {"ok": false, "error": "翻译服务返回了无效数据。"}
	return {"ok": true, "payload": payload}

func _parse_payload(payload: Dictionary, value: String, source: String, target: String, selected_provider: String) -> Dictionary:
	if selected_provider == "youdao":
		var code: String = str(payload.get("errorCode", "unknown"))
		if code != "0": return {"ok": false, "error": "有道体验接口暂不可用（错误 %s）。可稍后重试，或在设置中切换 MyMemory。" % code}
		if payload.has("query") and (not payload.query is String or payload.query.strip_edges() != value.strip_edges()):
			return {"ok": false, "error": "有道返回的原文不完整，请缩短内容后重试。"}
		var values = payload.get("translation", [])
		if not values is Array or values.is_empty(): return {"ok": false, "error": "有道没有返回译文，请稍后重试。"}
		var lines := PackedStringArray()
		for line in values:
			if not line is String: return {"ok": false, "error": "有道返回了无效的译文数据。"}
			lines.append(line)
		var translated := "\n".join(lines)
		if translated.strip_edges().is_empty(): return {"ok": false, "error": "有道返回了空译文，请重试。"}
		var languages: PackedStringArray = str(payload.get("l", "")).split("2")
		if languages.size() == 2:
			if SpeechURLs.normalized_language(languages[0]) == SpeechURLs.normalized_language(source):
				SpeechURLs.put(value, source, str(payload.get("speakUrl", "")))
			if SpeechURLs.normalized_language(languages[1]) == SpeechURLs.normalized_language(target):
				SpeechURLs.put(translated, target, str(payload.get("tSpeakUrl", "")))
		return {"ok": true, "text": translated}
	if payload.get("quotaFinished", false) or int(payload.get("responseStatus", 0)) == 429:
		return {"ok": false, "error": "今日免费翻译额度已用完，请在额度恢复后重试。"}
	if int(payload.get("responseStatus", 0)) != 200:
		return {"ok": false, "error": "暂不支持此语言组合，或服务暂不可用。Ctrl+L 更换语言。"}
	var data = payload.get("responseData", {})
	if not data is Dictionary or not data.get("translatedText", "") is String:
		return {"ok": false, "error": "没有收到有效译文，请稍后重试。"}
	var translated: String = data.get("translatedText", "").xml_unescape()
	if translated.is_empty(): return {"ok": false, "error": "服务返回了空译文，请重试。"}
	return {"ok": true, "text": translated}
