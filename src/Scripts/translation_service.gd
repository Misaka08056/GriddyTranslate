extends Node
class_name GriddyTranslationService

# Public keyless MyMemory API; each q is limited to 500 UTF-8 bytes.
const ENDPOINT = "https://api.mymemory.translated.net/get"
const YOUDAO_ENDPOINT := "https://aidemo.youdao.com/trans"
const PROVIDERS := ["mymemory", "youdao"]
const MAX_BYTES = 450
var cache: Dictionary = {}
var provider := "youdao"

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

func translate_chunk(value: String, source: String, target: String) -> Dictionary:
	var selected_provider := provider
	var key := selected_provider + ":" + source + ":" + target + ":" + value
	if cache.has(key): return {"ok": true, "text": cache[key]}
	var request := HTTPRequest.new()
	request.timeout = 22.0
	request.body_size_limit = 2097152
	add_child(request)
	var url := ENDPOINT + "?q=" + value.uri_encode() + "&langpair=" + (source + "|" + target).uri_encode()
	if selected_provider == "youdao":
		url = YOUDAO_ENDPOINT + "?q=" + value.uri_encode() + "&from=" + youdao_language(source).uri_encode() + "&to=" + youdao_language(target).uri_encode()
	var error := request.request(url, ["Accept: application/json", "User-Agent: GriddyTranslate/1.0"])
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": "无法发起网络请求。Ctrl+Enter 重试。"}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "网络连接失败或超时。检查网络后按 Ctrl+Enter 重试。"}
	if response[1] == 429: return {"ok": false, "error": "免费服务请求过于频繁，请稍后重试。"}
	if response[1] != 200: return {"ok": false, "error": "翻译服务暂不可用（HTTP %s）。Ctrl+Enter 重试。" % response[1]}
	var payload = JSON.parse_string(response[3].get_string_from_utf8())
	if not payload is Dictionary: return {"ok": false, "error": "翻译服务返回了无效数据。"}
	if selected_provider == "youdao":
		var code: String = str(payload.get("errorCode", "unknown"))
		if code != "0":
			return {"ok": false, "error": "有道体验接口暂不可用（错误 %s）。可稍后重试，或在设置中切换 MyMemory。" % code}
		var values = payload.get("translation", [])
		if not values is Array or values.is_empty(): return {"ok": false, "error": "有道没有返回译文，请稍后重试。"}
		var lines := PackedStringArray()
		for line in values:
			if not line is String: return {"ok": false, "error": "有道返回了无效的译文数据。"}
			lines.append(line)
		var translated := "\n".join(lines)
		if translated.strip_edges().is_empty(): return {"ok": false, "error": "有道返回了空译文，请重试。"}
		if cache.size() >= 128: cache.erase(cache.keys()[0])
		cache[key] = translated
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
	if cache.size() >= 128: cache.erase(cache.keys()[0])
	cache[key] = translated
	return {"ok": true, "text": translated}
