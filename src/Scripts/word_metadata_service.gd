extends Node

const Examples = preload("res://Scripts/example_service.gd")
var cache: Dictionary = {}

func get_metadata(word: String, source: String, target: String) -> Dictionary:
	var query := Examples.example_query(word)
	if source != "en" or query.is_empty(): return {}
	var original := word.strip_edges().replace("’", "'")
	var key := original + "\n" + target
	if cache.has(key): return cache[key].duplicate(true)
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.use_threads = true
	request.body_size_limit = 1048576
	add_child(request)
	var error := request.request("https://dict.youdao.com/jsonapi_s?doctype=json&jsonversion=4&le=en&q=" + original.uri_encode(), ["Accept: application/json"])
	if error != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200: return {}
	var payload = JSON.parse_string(response[3].get_string_from_utf8())
	if not payload is Dictionary or not Examples.has_exact_youdao_entry(payload, query): return {}
	var words = payload.get("ec", {}).get("word", [])
	if words is Dictionary: words = [words]
	var phonetic := ""
	var matched := false
	for entry in words:
		if not entry is Dictionary: continue
		if Examples.example_query(str(entry.get("return-phrase", ""))) != query: continue
		if str(entry.get("return-phrase", "")).strip_edges().replace("’", "'") != original: continue
		matched = true
		var parts := PackedStringArray()
		for field in [["ukphone", "UK"], ["usphone", "US"]]:
			var value := str(entry.get(field[0], "")).strip_edges()
			if not value.is_empty(): parts.append(str(field[1]) + " /" + value + "/")
		phonetic = " · ".join(parts)
		if phonetic.is_empty(): phonetic = str(entry.get("phone", "")).strip_edges()
		break
	if not matched: return {}
	var examples: Array = []
	if target == "zh-CN":
		var example: Dictionary = Examples.extract_youdao_example(payload, query)
		if not example.is_empty():
			if matches_example(str(example.english), original): examples.append(example)
	var result := {"phonetic": phonetic, "examples": examples}
	if cache.size() >= 64: cache.erase(cache.keys()[0])
	cache[key] = result
	return result.duplicate(true)

static func matches_example(sentence: String, word: String) -> bool:
	if Examples.example_query(word).is_empty(): return false
	var original := word.strip_edges().replace("’", "'")
	var whitespace := RegEx.new()
	whitespace.compile("\\s+")
	original = whitespace.sub(original, " ", true)
	var exact := RegEx.new()
	exact.compile("\\b" + original.replace(" ", "\\s+") + "\\b")
	return exact.search(sentence.replace("’", "'")) != null
