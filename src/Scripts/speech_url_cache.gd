extends RefCounted

# Signed URLs already returned by an explicitly requested Youdao translation.
# Sharing them avoids translating the same snapshot again just to obtain TTS.
const MAX_ENTRIES := 64
const TTL_MSEC := 240000
static var _entries: Dictionary = {}

static func normalized_language(language: String) -> String:
	if language.to_lower() in ["zh-chs", "zh-cn", "zh-hans"]: return "zh-CN"
	if language.to_lower() in ["zh-cht", "zh-tw", "zh-hant"]: return "zh-TW"
	if language.to_lower() in ["en-usa", "en-us", "en-gbr", "en-gb"]: return "en"
	var aliases := {"ja-jpn": "ja", "ko-kor": "ko", "fr-fra": "fr", "de-deu": "de", "ru-rus": "ru", "es-esp": "es", "pt-prt": "pt", "pt-bra": "pt", "it-ita": "it"}
	if aliases.has(language.to_lower()): return str(aliases[language.to_lower()])
	return language.to_lower()

static func _key(text: String, language: String, provider: String) -> String:
	return provider + "\n" + normalized_language(language) + "\n" + text.strip_edges()

static func voice_language_matches(requested: String, actual: String) -> bool:
	var first := normalized_language(requested)
	var second := normalized_language(actual)
	# Youdao uses its Mandarin voice for both Chinese writing systems. This
	# applies only to audio validation; simplified/traditional cache keys stay
	# separate and the exact text check below still prevents substitutions.
	return first == second or (first in ["zh-CN", "zh-TW"] and second in ["zh-CN", "zh-TW"])

static func put(text: String, language: String, url: String, provider: String = "youdao") -> void:
	if text.strip_edges().is_empty() or not url.begins_with("https://openapi.youdao.com/ttsapi?"): return
	if url.length() > 32768 or text.length() > 5000: return
	var parameters: Dictionary = {}
	for parameter in url.get_slice("?", 1).split("&"):
		var separator := parameter.find("=")
		if separator >= 0:
			var name := parameter.substr(0, separator).uri_decode()
			parameters[name] = parameter.substr(separator + 1).replace("+", " ").uri_decode()
	# A successful translation response can still contain a shortened or
	# different-language TTS URL. Never present that audio as the full snapshot.
	if str(parameters.get("q", "")).strip_edges() != text.strip_edges(): return
	if not voice_language_matches(language, str(parameters.get("langType", ""))): return
	_prune()
	var key := _key(text, language, provider)
	_entries.erase(key)
	while _entries.size() >= MAX_ENTRIES: _entries.erase(_entries.keys()[0])
	_entries[key] = {"url": url, "expires": Time.get_ticks_msec() + TTL_MSEC}

static func get_url(text: String, language: String, provider: String = "youdao") -> String:
	_prune()
	var key := _key(text, language, provider)
	if not _entries.has(key): return ""
	return str(_entries[key].url)

static func clear() -> void:
	_entries.clear()

static func erase(text: String, language: String, provider: String = "youdao") -> void:
	_entries.erase(_key(text, language, provider))

static func _prune() -> void:
	var now := Time.get_ticks_msec()
	for key in _entries.keys():
		if int(_entries[key].expires) <= now: _entries.erase(key)
