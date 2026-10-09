extends Node
class_name GriddyPronunciationService

signal playback_failed(message: String)

const DICTIONARY_ENDPOINT := "https://dict.youdao.com/dictvoice"
const SPEECH_ENDPOINT := "https://aidemo.youdao.com/trans"
const MAX_SEGMENT_BYTES := 450
const MAX_CACHE_BYTES := 8388608
const MAX_CACHE_ENTRIES := 32
const SpeechURLs = preload("res://Scripts/speech_url_cache.gd")

var _revision := 0
var _request: HTTPRequest
var _player: AudioStreamPlayer
var _cache: Dictionary = {}
var _cache_bytes := 0

func _ready() -> void:
	_ensure_player()

func _ensure_player() -> void:
	if is_instance_valid(_player): return
	_player = AudioStreamPlayer.new()
	_player.name = "PronunciationAudio"
	add_child(_player)

func _exit_tree() -> void:
	stop()

func stop() -> void:
	_revision += 1
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null

# The caller supplies a snapshot of the original or translated text and its
# actual language. Success returns when the first segment starts playing.
func speak(text: String, language: String) -> String:
	stop()
	var token := _revision
	var value := text.strip_edges()
	if value.is_empty(): return "没有可以朗读的文字。"
	if language == "auto" or language.is_empty():
		language = GriddyTranslationService.detect_language(value)
	language = SpeechURLs.normalized_language(language)
	var segments: Array[String] = []
	var result: Dictionary = {}
	var key := _audio_key(value, language)
	if _cache.has(key):
		result = {"ok": true, "stream": _cache[key].stream}
	elif not is_dictionary_query(value, language) and not SpeechURLs.get_url(value, language).is_empty():
		# The translation already returned an exact full-text voice URL. Fetch
		# that recording directly, including texts longer than our fallback
		# segment size, rather than translating them again to obtain a signature.
		result = await _load_registered_audio(value, language, token)
		if result.get("refresh", false): result = {}
	if token != _revision: return ""
	if result.is_empty():
		segments = split_segments(value)
		result = await _load_audio(segments[0], language, token)
	if token != _revision: return ""
	if not result.get("ok", false): return result.get("error", "无法获取读音，请稍后重试。")
	_ensure_player()
	_player.stream = result.stream
	_player.play()
	if segments.size() > 1: _read_remaining(segments, language, token)
	return ""

func _read_remaining(segments: Array[String], language: String, token: int) -> void:
	for index in range(1, segments.size()):
		# Fetch the next segment during playback, then wait for the current one.
		var result := await _load_audio(segments[index], language, token)
		if token != _revision: return
		if not result.get("ok", false):
			_player.stop()
			playback_failed.emit(result.get("error", "后续文字朗读失败，请稍后重试。"))
			return
		while token == _revision and _player.playing:
			await get_tree().process_frame
		if token != _revision: return
		_player.stream = result.stream
		_player.play()

static func split_segments(value: String) -> Array[String]:
	var segments: Array[String] = []
	var current := ""
	var bytes := 0
	for character in value:
		var size := character.to_utf8_buffer().size()
		if bytes + size > MAX_SEGMENT_BYTES:
			# Keep English words intact when a long sentence reaches the limit.
			var boundary := current.rfind(" ")
			if boundary >= current.length() / 2:
				segments.append(current.substr(0, boundary + 1))
				current = current.substr(boundary + 1)
				bytes = current.to_utf8_buffer().size()
			else:
				if not current.strip_edges().is_empty(): segments.append(current)
				current = ""
				bytes = 0
		current += character
		bytes += size
		if bytes >= 280 and character in ["。", "！", "？", ".", "!", "?", "\n"]:
			if not current.strip_edges().is_empty(): segments.append(current)
			current = ""
			bytes = 0
	if not current.strip_edges().is_empty(): segments.append(current)
	return segments

func _load_audio(text: String, language: String, token: int) -> Dictionary:
	var key := _audio_key(text, language)
	if _cache.has(key): return {"ok": true, "stream": _cache[key].stream}
	# The dictionary has excellent word/phrase recordings, but returns HTTP 500
	# for many full sentences. Signed Youdao TTS below handles those sentences.
	if is_dictionary_query(text, language):
		var dictionary_language := "chn" if language.begins_with("zh") else "eng"
		var dictionary_url := DICTIONARY_ENDPOINT + "?audio=" + text.uri_encode() + "&le=" + dictionary_language + "&type=2"
		var dictionary := await _fetch(dictionary_url, token)
		if token != _revision: return {}
		if dictionary.get("network_error", false) or dictionary.get("http_status", 0) == 429:
			return dictionary
		if dictionary.get("ok", false):
			var recording := decode_audio(dictionary.body)
			if recording != null:
				_remember(key, recording, dictionary.body.size())
				return {"ok": true, "stream": recording}
	# Keep the fast dictionary recording for words even when a translation
	# has returned a TTS URL. A missing recording can still reuse that URL.
	if not SpeechURLs.get_url(text, language).is_empty():
		var registered := await _load_registered_audio(text, language, token)
		if token != _revision: return {}
		if not registered.get("refresh", false): return registered
	var source := GriddyTranslationService.youdao_language(language)
	var target := "en" if source.begins_with("zh") else "zh-CHS"
	var speech_url := SPEECH_ENDPOINT + "?q=" + text.uri_encode() + "&from=" + source.uri_encode() + "&to=" + target
	var response := await _fetch(speech_url, token)
	if token != _revision: return {}
	if not response.get("ok", false): return response
	var payload = JSON.parse_string(response.body.get_string_from_utf8())
	if not payload is Dictionary:
		return {"ok": false, "error": "有道读音服务返回了无效数据，请稍后重试。"}
	if str(payload.get("errorCode", "unknown")) != "0":
		return {"ok": false, "error": "有道暂时无法提供此语言的读音（错误 %s），请稍后重试。" % str(payload.get("errorCode", "unknown"))}
	# speakUrl reads q itself; tSpeakUrl reads an incidental translation and
	# must never be used for the caller's original/translated text snapshot.
	var audio_url = payload.get("speakUrl", "")
	if not audio_url is String or not audio_url.begins_with("https://openapi.youdao.com/ttsapi?"):
		return {"ok": false, "error": "有道尚未提供 %s 的读音，请更换朗读语言。" % language}
	SpeechURLs.put(text, language, audio_url)
	if SpeechURLs.get_url(text, language) != audio_url:
		return {"ok": false, "error": "有道返回的读音与文字或语言不匹配，请检查所选语言后重试。"}
	var audio := await _fetch(audio_url, token)
	if token != _revision: return {}
	if not audio.get("ok", false): return audio
	var stream := decode_audio(audio.body)
	if stream == null:
		return {"ok": false, "error": "有道没有返回可播放的 %s 音频，请稍后重试。" % language}
	_remember(key, stream, audio.body.size())
	return {"ok": true, "stream": stream}

static func _audio_key(text: String, language: String) -> String:
	return SpeechURLs.normalized_language(language) + "\n" + text.strip_edges()

static func is_dictionary_query(text: String, language: String) -> bool:
	var value := text.strip_edges()
	if value.is_empty(): return false
	if language.begins_with("zh"):
		if value.length() > 4: return false
		for index in value.length():
			var code := value.unicode_at(index)
			if code < 0x4e00 or code > 0x9fff: return false
		return true
	if not language.begins_with("en") or value.length() > 48: return false
	var letters := 0
	for index in value.length():
		var code := value.unicode_at(index)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122): letters += 1
		elif value[index] not in ["'", "-"]: return false
	return letters > 0

func _load_registered_audio(text: String, language: String, token: int) -> Dictionary:
	var url := SpeechURLs.get_url(text, language)
	if url.is_empty(): return {"refresh": true}
	var audio := await _fetch(url, token)
	if token != _revision: return {}
	if not audio.get("ok", false):
		if audio.get("http_status", 0) in [401, 403, 404, 410]:
			SpeechURLs.erase(text, language)
			return {"refresh": true}
		return audio
	var stream := decode_audio(audio.body)
	if stream == null:
		# An expired signature can arrive as an HTTP 200 JSON error. Invalidate
		# it and obtain a fresh Youdao signature once through the normal path.
		SpeechURLs.erase(text, language)
		return {"refresh": true}
	_remember(_audio_key(text, language), stream, audio.body.size())
	return {"ok": true, "stream": stream}

func _fetch(url: String, token: int) -> Dictionary:
	if token != _revision: return {}
	var request := HTTPRequest.new()
	request.timeout = 18.0
	request.use_threads = true
	request.body_size_limit = 2097152
	add_child(request)
	_request = request
	var completed := {"done": false, "result": 0, "status": 0, "body": PackedByteArray()}
	request.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		completed.result = result
		completed.status = status
		completed.body = body
		completed.done = true
	)
	var error := request.request(url, ["Accept: audio/mpeg, audio/wav, application/json", "User-Agent: GriddyTranslate/1.0"])
	if error != OK:
		request.queue_free()
		if _request == request: _request = null
		return {"ok": false, "network_error": true, "error": "无法发起读音请求，请检查网络后重试。"}
	# cancel_request does not emit request_completed. Waiting only on that
	# signal would strand an older coroutine when the next shortcut cancels it.
	while token == _revision and not completed.done:
		await get_tree().process_frame
	if token != _revision: return {}
	request.queue_free()
	if _request == request: _request = null
	if completed.result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "network_error": true, "error": "读音网络连接失败或超时，请检查网络后重试。"}
	if completed.status == 429:
		return {"ok": false, "http_status": 429, "error": "有道读音请求过于频繁，请稍后重试。"}
	if completed.status != 200:
		return {"ok": false, "http_status": completed.status, "error": "有道读音服务暂不可用（HTTP %s），请稍后重试。" % completed.status}
	return {"ok": true, "body": completed.body}

func _remember(key: String, stream: AudioStream, bytes: int) -> void:
	if bytes > MAX_CACHE_BYTES: return
	while not _cache.is_empty() and (_cache.size() >= MAX_CACHE_ENTRIES or _cache_bytes + bytes > MAX_CACHE_BYTES):
		var oldest = _cache.keys()[0]
		_cache_bytes -= _cache[oldest].bytes
		_cache.erase(oldest)
	_cache[key] = {"stream": stream, "bytes": bytes}
	_cache_bytes += bytes

static func decode_audio(data: PackedByteArray) -> AudioStream:
	if data.size() < 32: return null
	if data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WAVE":
		return _decode_wave(data)
	var mp3_header := data.slice(0, 3).get_string_from_ascii() == "ID3"
	mp3_header = mp3_header or (data[0] == 0xff and (data[1] & 0xe0) == 0xe0)
	if not mp3_header: return null
	var stream := AudioStreamMP3.new()
	stream.data = data
	return stream if stream.get_length() > 0.0 else null

static func _decode_wave(data: PackedByteArray) -> AudioStream:
	var offset := 12
	var channels := 0
	var rate := 0
	var bits := 0
	var pcm := PackedByteArray()
	while offset + 8 <= data.size():
		var chunk := data.slice(offset, offset + 4).get_string_from_ascii()
		var length := data.decode_u32(offset + 4)
		var start := offset + 8
		if length > data.size() - start: return null
		if chunk == "fmt " and length >= 16:
			if data.decode_u16(start) != 1: return null
			channels = data.decode_u16(start + 2)
			rate = data.decode_u32(start + 4)
			bits = data.decode_u16(start + 14)
		elif chunk == "data":
			pcm = data.slice(start, start + length)
		offset = start + length + (length % 2)
	if channels not in [1, 2] or bits not in [8, 16] or rate < 8000 or rate > 192000 or pcm.is_empty(): return null
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = rate
	wave.stereo = channels == 2
	if bits == 8:
		for index in pcm.size(): pcm[index] = pcm[index] ^ 128
	wave.data = pcm
	return wave
