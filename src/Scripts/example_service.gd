extends Node

# Real dictionary examples. Youdao supplies both the sentence and its translation.
const ENDPOINT := "https://api.dictionaryapi.dev/api/v2/entries/en/"
var cache: Dictionary = {}
var provider := "youdao"

static func example_query(value: String) -> String:
	var query := value.strip_edges().to_lower().replace("’", "'")
	if query.is_empty() or query.length() > 100: return ""
	var pattern := RegEx.new()
	pattern.compile("^[a-z]+(?:['-][a-z]+)*(?:[ \\t]+[a-z]+(?:['-][a-z]+)*)*$")
	if pattern.search(query) == null: return ""
	var whitespace := RegEx.new()
	whitespace.compile("[ \\t]+")
	query = whitespace.sub(query, " ", true)
	if query.split(" ").size() > 12: return ""
	return query

func get_example(value: String) -> Dictionary:
	var query := example_query(value)
	if query.is_empty(): return {}
	if provider == "youdao":
		var example := await youdao_example(query)
		if not example.is_empty(): return example
	# A fallback may only query the SAME complete entry; never extract a keyword.
	return await dictionary_example(query)

func dictionary_example(query: String) -> Dictionary:
	var examples: Array = []
	if cache.has(query):
		examples = cache[query]
	else:
		var request := HTTPRequest.new()
		request.timeout = 7.0
		request.body_size_limit = 1048576
		add_child(request)
		if request.request(ENDPOINT + query.uri_encode(), ["Accept: application/json"]) != OK:
			request.queue_free()
			return {}
		var response: Array = await request.request_completed
		request.queue_free()
		if response[0] != HTTPRequest.RESULT_SUCCESS: return {}
		if response[1] == 404:
			cache[query] = []
			return {}
		if response[1] != 200: return {}
		var payload = JSON.parse_string(response[3].get_string_from_utf8())
		if not payload is Array: return {}
		for entry in payload:
			if not entry is Dictionary: continue
			if example_query(str(entry.get("word", ""))) != query: continue
			for meaning in entry.get("meanings", []):
				if not meaning is Dictionary: continue
				for definition in meaning.get("definitions", []):
					if not definition is Dictionary: continue
					var sentence: String = str(definition.get("example", "")).strip_edges()
					if sentence.length() >= 12 and sentence.length() <= 140 and contains_query(sentence, query) and not sentence in examples:
						examples.append(sentence)
		if cache.size() >= 64: cache.erase(cache.keys()[0])
		cache[query] = examples
	for sentence in examples:
		if str(sentence).to_lower() != query:
			return {"english": sentence, "word": query}
	return {}

func youdao_example(value: String) -> Dictionary:
	var query := example_query(value)
	if query.is_empty(): return {}
	var key := "youdao:" + query
	if cache.has(key): return cache[key]
	var request := HTTPRequest.new()
	request.timeout = 7.0
	request.body_size_limit = 1048576
	add_child(request)
	var url := "https://dict.youdao.com/jsonapi_s?doctype=json&jsonversion=4&le=en&q=" + query.uri_encode()
	if request.request(url, ["Accept: application/json"]) != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200: return {}
	var payload = JSON.parse_string(response[3].get_string_from_utf8())
	if not payload is Dictionary: return {}
	# Sentence search results alone do not establish a dictionary entry.
	if not has_exact_youdao_entry(payload, query): return {}
	var example := extract_youdao_example(payload, query)
	if not example.is_empty():
		example["word"] = query
		if cache.size() >= 64: cache.erase(cache.keys()[0])
		cache[key] = example
	return example

static func has_exact_youdao_entry(payload: Dictionary, query: String) -> bool:
	var ec = payload.get("ec", {})
	if not ec is Dictionary: return false
	var words = ec.get("word", [])
	if words is Dictionary: words = [words]
	if not words is Array: return false
	for word in words:
		if word is Dictionary and example_query(str(word.get("return-phrase", ""))) == query and not word.get("trs", []).is_empty(): return true
	return false

static func contains_query(sentence: String, query: String) -> bool:
	# Query tokens contain no regex metacharacters. Keep phrase words together;
	# removing punctuation would incorrectly join words from different sentences.
	var pattern := RegEx.new()
	pattern.compile("\\b" + query.replace(" ", "\\s+") + "\\b")
	return pattern.search(sentence.to_lower().replace("’", "'")) != null

static func clean_sentence(value: String) -> String:
	var tags := RegEx.new()
	tags.compile("<[^>]*>")
	return tags.sub(value, "", true).xml_unescape().strip_edges()

static func extract_youdao_example(payload: Dictionary, source: String) -> Dictionary:
	var bilingual = payload.get("blng_sents_part", {})
	if bilingual is Dictionary:
		var pairs = bilingual.get("sentence-pair", [])
		if pairs is Dictionary: pairs = [pairs]
		if pairs is Array:
			for pair in pairs:
				if not pair is Dictionary: continue
				var example := valid_pair(str(pair.get("sentence", pair.get("sentence-eng", ""))), str(pair.get("sentence-translation", "")), source)
				if not example.is_empty(): return example
	# Some entries keep en/zh pairs inside nested dictionary sentence containers.
	return find_dictionary_sentence(payload.get("ec", {}), source)

static func valid_pair(english_value: String, chinese_value: String, source: String) -> Dictionary:
	var english := clean_sentence(english_value)
	var chinese := clean_sentence(chinese_value)
	if english.length() < 5 or english.length() > 240 or chinese.is_empty() or chinese.length() > 240: return {}
	if english.to_lower() == source.strip_edges().to_lower(): return {}
	var query := example_query(source)
	if query.is_empty() or not contains_query(english, query): return {}
	return {"english": english, "chinese": chinese}

static func find_dictionary_sentence(container: Variant, source: String, inside_sentence: bool = false) -> Dictionary:
	if container is Dictionary:
		if inside_sentence and container.has("en") and container.has("zh"):
			var example := valid_pair(str(container.en), str(container.zh), source)
			if not example.is_empty(): return example
		for key in container:
			var example := find_dictionary_sentence(container[key], source, inside_sentence or key == "sentence")
			if not example.is_empty(): return example
	elif container is Array:
		for item in container:
			var example := find_dictionary_sentence(item, source, inside_sentence)
			if not example.is_empty(): return example
	return {}
