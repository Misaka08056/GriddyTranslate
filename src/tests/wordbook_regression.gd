extends Node

const FakeSync = preload("res://tests/fake_wordbook_sync_backend.gd")
const Controller = preload("res://Scripts/wordbook_controller.gd")
const Store = preload("res://Scripts/wordbook_store.gd")

var failures := 0
var app: Node
var controller: Node
var store: Node
var code: CodeEdit
var translation: Node
var metadata: Node
var speech: Node

class FakeTranslation extends Node:
	var provider := "youdao"
	var requests: Array[Dictionary] = []
	var delay := 0.035
	var fail := false
	func translate_text(word: String, source: String, target: String) -> Dictionary:
		var request := {"word": word, "source": source, "target": target, "provider": provider}
		requests.append(request)
		await get_tree().create_timer(delay).timeout
		if fail: return {"ok": false, "error": "simulated translation failure"}
		return {"ok": true, "text": rendered(request)}
	static func rendered(request: Dictionary) -> String:
		return "%s | %s → %s | %s" % [request.provider, request.source, request.target, request.word]
	func cancel() -> void:
		pass

class FakeMetadata extends Node:
	var requests: Array[Dictionary] = []
	var answer: Dictionary = {}
	var delay := 0.02
	func get_metadata(word: String, source: String, target: String) -> Dictionary:
		requests.append({"word": word, "source": source, "target": target})
		var snapshot := answer.duplicate(true)
		await get_tree().create_timer(delay).timeout
		return snapshot

class FakeSpeech extends Node:
	var requests: Array[Dictionary] = []
	var stops := 0
	func speak(value: String, language: String) -> String:
		requests.append({"text": value, "language": language})
		await get_tree().create_timer(0.01).timeout
		return ""
	func stop() -> void:
		stops += 1

func _ready() -> void:
	app = get_parent()
	controller = app.wordbook
	store = controller.store
	code = app.Code
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func pause(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout

func shortcut(key: Key, shift: bool = false, control: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.ctrl_pressed = control
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func set_source(value: String, source: String = "en", target: String = "zh-CN", provider: String = "youdao") -> void:
	app.cancel_translation()
	app.cancel_examples()
	app.showing_translation = false
	app.suppress_changes = true
	app.source_text = value
	code.editable = true
	code.text = value
	code.deselect()
	app.suppress_changes = false
	app.source_language = source
	app.target_language = target
	app.service.provider = provider
	code.grab_focus()

func set_result(word: String, translated: String, source: String = "en", target: String = "zh-CN", provider: String = "youdao") -> void:
	app.result_source_text = word
	app.translated_text = translated
	app.last_source = source
	app.last_target = target
	app.result_provider = provider
	app.current_example = {}

func run() -> void:
	await pause(0.4)
	LuaSingleton.change_setting("music", false)
	app.auto_translate = false
	app.examples_enabled = false
	app.debounce.stop()
	controller.set_sync_enabled(false)
	store.storage_path = "user://qa/wordbook-integration-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_msec()) + ".json"
	check(store.load_book().ok and store.entries.is_empty(), "integration uses an isolated empty wordbook")
	translation = FakeTranslation.new()
	metadata = FakeMetadata.new()
	speech = FakeSpeech.new()
	controller.add_child(translation)
	controller.add_child(metadata)
	app.add_child(speech)
	controller.translation_service = translation
	controller.metadata_service = metadata
	app.pronunciation.stop()
	app.pronunciation = speech
	controller.sync_backend = FakeSync
	controller.vault_path = "fake-vault-no-filesystem"
	await test_collection_snapshots()
	await test_selection_and_failure()
	await test_enrichment_races()
	await test_swap_guard()
	await test_panel_shortcuts()
	await test_background_sync()
	await test_background_cancel()
	await test_failed_batch()
	await test_open_sync_races()
	await test_background_open()
	await test_background_delete()
	await test_automatic_delete_queue()
	await test_exit_cancellation()
	print("WORDBOOK_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)

func test_collection_snapshots() -> void:
	set_source("manipulate")
	set_result("manipulate", "操纵；操作")
	app.current_example = {"english": "They manipulate the data.", "chinese": "他们操纵数据。"}
	var before: int = translation.requests.size()
	await shortcut(KEY_D)
	var entry: Dictionary = store.find_entry("manipulate", "en", "zh-CN")
	check(not entry.is_empty() and entry.translation == "操纵；操作" and entry.examples.size() == 1, "Ctrl+D reuses the exact successful translation and bilingual example")
	check(translation.requests.size() == before and code.text == "manipulate", "collecting a translated word adds no redundant request and preserves input")
	var id: String = entry.get("id", "")
	check(store.update_entry(id, {"notes": "手写笔记", "tags": ["收藏"]}).ok, "fixture has handwritten notes and tags")
	var count: int = store.entries.size()
	await shortcut(KEY_D)
	entry = store.get_entry(id)
	check(store.entries.size() == count and entry.notes == "手写笔记" and entry.tags == ["收藏"], "repeated Ctrl+D keeps the same ID and preserves handwritten fields")
	set_source("take care of")
	set_result("take care of", "照顾")
	await shortcut(KEY_D)
	entry = store.find_entry("take care of", "en", "zh-CN")
	check(not entry.is_empty() and entry.word == "take care of" and entry.translation == "照顾", "Ctrl+D collects the complete phrase without extracting a constituent word")
	set_source("US")
	set_result("US", "美国")
	app.current_example = {"english": "The teacher helps us learn.", "chinese": "老师帮助我们学习。"}
	await shortcut(KEY_D)
	entry = store.find_entry("US", "en", "zh-CN")
	check(not entry.is_empty() and entry.translation == "美国" and entry.examples.is_empty(), "collecting US cannot reuse a lower-case us example with a different meaning")
	set_source("changed term")
	set_result("old term", "旧词的译文")
	before = translation.requests.size()
	await shortcut(KEY_D)
	await pause()
	entry = store.find_entry("changed term", "en", "zh-CN")
	check(translation.requests.size() == before + 1 and entry.get("translation", "") != "旧词的译文", "a different input cannot reuse a stale successful translation")
	set_source("provider mismatch", "en", "zh-CN", "mymemory")
	set_result("provider mismatch", "错误来源的旧译文", "en", "zh-CN", "youdao")
	before = translation.requests.size()
	await shortcut(KEY_D)
	await pause()
	entry = store.find_entry("provider mismatch", "en", "zh-CN")
	check(translation.requests.size() == before + 1 and entry.provider == "mymemory" and entry.translation.begins_with("mymemory"), "changing translation provider fetches the requested source instead of reusing old text")
	set_source("language mismatch", "en", "ja")
	set_result("language mismatch", "旧中文译文", "en", "zh-CN")
	await shortcut(KEY_D)
	await pause()
	entry = store.find_entry("language mismatch", "en", "ja")
	check(not entry.is_empty() and entry.target_language == "ja" and entry.translation.contains("en → ja"), "changing the target language never saves an old translation under the new language")
	set_source("source mismatch", "fr", "zh-CN")
	set_result("source mismatch", "旧英文译文", "en", "zh-CN")
	await shortcut(KEY_D)
	await pause()
	entry = store.find_entry("source mismatch", "fr", "zh-CN")
	check(not entry.is_empty() and entry.translation.contains("fr → zh-CN"), "changing the source language also invalidates reuse")
	set_source("你好", "auto", "auto")
	set_result("old", "old")
	await shortcut(KEY_D)
	await pause()
	entry = store.find_entry("你好", "zh-CN", "en")
	check(not entry.is_empty() and entry.translation.contains("zh-CN → en"), "smart Chinese collection stores the detected source and actual English target")
	set_source("hello", "en", "en")
	before = translation.requests.size()
	await shortcut(KEY_D)
	entry = store.find_entry("hello", "en", "en")
	check(entry.get("translation", "") == "hello" and translation.requests.size() == before, "same-language collection completes without network work")

func test_selection_and_failure() -> void:
	var sentence := "This deliberately long sentence contains more than twelve words so the wordbook should request that I select a phrase first."
	set_source(sentence)
	set_result("old", "old")
	var count: int = store.entries.size()
	var before: int = translation.requests.size()
	await shortcut(KEY_D)
	check(store.entries.size() == count and translation.requests.size() == before, "a long sentence is rejected without silently choosing one word")
	var start := sentence.find("select a phrase")
	code.select(0, start, 0, start + "select a phrase".length())
	await shortcut(KEY_D)
	await pause()
	check(not store.find_entry("select a phrase", "en", "zh-CN").is_empty() and code.text == sentence, "selection from a long sentence collects exactly the selected complete phrase")
	set_source("result origin")
	set_result("result origin", "原词译文")
	app.translation_placement = 0
	app._display(true)
	await shortcut(KEY_D)
	check(store.find_entry("result origin", "en", "zh-CN").get("translation", "") == "原词译文", "Ctrl+D from replacement result view still collects the original text")
	code.select(0, 0, 0, code.text.length())
	count = store.entries.size()
	await shortcut(KEY_D)
	check(store.entries.size() == count and store.find_entry("原词译文", "en", "zh-CN").is_empty(), "selecting the translated output cannot mislabel it as the original language")
	set_source("combined origin")
	set_result("combined origin", "保留原文的译文")
	app.translation_placement = 1
	app._display(true)
	code.select(0, 0, 0, "combined origin".length())
	await shortcut(KEY_D)
	check(not store.find_entry("combined origin", "en", "zh-CN").is_empty(), "source-line selection works in the retain-original result layout")
	set_source("pending collection")
	set_result("old", "old")
	translation.delay = 0.15
	before = translation.requests.size()
	await shortcut(KEY_D)
	await shortcut(KEY_D)
	await pause(0.22)
	check(translation.requests.size() == before + 1 and not store.find_entry("pending collection", "en", "zh-CN").is_empty(), "repeated collection while waiting coalesces the same pending request")
	translation.delay = 0.035
	translation.fail = true
	set_source("failed collection")
	before = translation.requests.size()
	await shortcut(KEY_D)
	await pause()
	check(store.find_entry("failed collection", "en", "zh-CN").is_empty() and controller._pending_words.is_empty(), "translation failure does not create a misleading entry or strand its pending key")
	translation.fail = false
	await shortcut(KEY_D)
	await pause()
	check(translation.requests.size() == before + 2 and not store.find_entry("failed collection", "en", "zh-CN").is_empty(), "collection can retry after a failed translation")

func details() -> Dictionary:
	return {"phonetic": "UK /test/", "examples": [{"english": "An exact example is available.", "chinese": "这里有准确例句。"}]}

func test_enrichment_races() -> void:
	metadata.delay = 0.16
	metadata.answer = details()
	set_source("enrichment editing")
	set_result("enrichment editing", "初始译文")
	await shortcut(KEY_D)
	var entry: Dictionary = store.find_entry("enrichment editing", "en", "zh-CN")
	var id: String = entry.get("id", "")
	check(store.update_entry(id, {"translation": "手动改译文", "notes": "正在学习：不要覆盖", "tags": ["手写"], "phonetic": "我的音标"}).ok, "user edits are saved while dictionary metadata is waiting")
	await pause(0.21)
	entry = store.get_entry(id)
	check(entry.translation == "手动改译文" and entry.notes == "正在学习：不要覆盖" and entry.tags == ["手写"] and entry.phonetic == "我的音标", "late metadata preserves edited translation, notes, tags and phonetic")
	check(entry.examples.size() == 1, "late metadata can still add the missing bilingual example")
	set_source("enrichment deletion")
	set_result("enrichment deletion", "删除测试")
	await shortcut(KEY_D)
	entry = store.find_entry("enrichment deletion", "en", "zh-CN")
	id = entry.id
	check(store.remove_entry(id).ok, "delete an entry while its metadata is in flight")
	metadata.answer = {}
	await shortcut(KEY_D)
	entry = store.find_entry("enrichment deletion", "en", "zh-CN")
	var new_id: String = entry.id
	await pause(0.21)
	check(id != new_id and store.get_entry(id).is_empty() and store.get_entry(new_id).examples.is_empty(), "old metadata cannot resurrect a deleted entry or enrich a new ID for the same word")
	metadata.answer = details()
	set_source("enrichment identity")
	set_result("enrichment identity", "身份测试")
	await shortcut(KEY_D)
	entry = store.find_entry("enrichment identity", "en", "zh-CN")
	id = entry.id
	check(store.update_entry(id, {"word": "changed identity", "target_language": "ja"}).ok, "change the original word and language during dictionary lookup")
	await pause(0.21)
	entry = store.get_entry(id)
	check(entry.word == "changed identity" and entry.phonetic.is_empty() and entry.examples.is_empty(), "dictionary metadata for the previous word and language is discarded")
	metadata.answer = {}
	metadata.delay = 0.02

func test_swap_guard() -> void:
	set_source("new input")
	set_result("old input", "旧输入译文")
	var before: int = speech.stops
	await shortcut(KEY_X, true)
	check(code.text == "new input" and app.source_text == "new input" and app.translated_text == "旧输入译文" and speech.stops == before, "swap refuses to pair a stale translation with newly edited input")
	set_source("valid swap")
	set_result("valid swap", "有效交换")
	await shortcut(KEY_X, true)
	check(code.text == "有效交换" and app.source_text == "有效交换" and app.translated_text == "valid swap" and app.last_source == "zh-CN" and app.last_target == "en", "a completed matching snapshot still swaps correctly")
	var requests: int = translation.requests.size()
	await shortcut(KEY_D)
	check(store.find_entry("有效交换", "zh-CN", "en").get("translation", "") == "valid swap" and translation.requests.size() == requests, "collection after a valid swap preserves the exact reversed snapshot")

func test_panel_shortcuts() -> void:
	set_source("main text must stay intact")
	await shortcut(KEY_B)
	await pause(0.3)
	check(controller.is_active() and code.active_overlay == controller.panel and not code.has_focus(), "Ctrl+B opens the existing animated overlay and moves focus away from the main input")
	controller.panel.search.text = "manipulate"
	controller.panel._on_search_changed("manipulate")
	var selected: Dictionary = controller.panel.selected_entry()
	var before: int = speech.requests.size()
	await shortcut(KEY_P)
	await shortcut(KEY_O)
	await pause(0.05)
	check(speech.requests.size() == before + 2 and speech.requests[before].text == selected.word and speech.requests[before].language == selected.source_language and speech.requests[before + 1].text == selected.translation and speech.requests[before + 1].language == selected.target_language, "Ctrl+P and Ctrl+O pronounce the selected wordbook original and translation with their own languages")
	var requests: int = translation.requests.size()
	await shortcut(KEY_D)
	await shortcut(KEY_N)
	await shortcut(KEY_TAB)
	check(code.text == "main text must stay intact" and translation.requests.size() == requests, "wordbook shortcuts cannot collect search text, clear the main input or switch its result view")
	await shortcut(KEY_E)
	check(controller.panel.editing, "Ctrl+E enters wordbook editing")
	await shortcut(KEY_ENTER)
	check(not controller.panel.editing and code.text == "main text must stay intact", "Ctrl+Enter saves wordbook fields instead of translating or changing the main input")
	await shortcut(KEY_B)
	await pause(0.3)
	check(not controller.is_active() and code.active_overlay == null and code.has_focus() and code.text == "main text must stay intact", "closing the wordbook restores main-input focus and preserves text")

func seed_batch(values: Array) -> void:
	controller._sync_pending.clear()
	for entry in values:
		controller._sync_pending[entry.id] = entry.duplicate(true)
		controller._sync_known[entry.id] = JSON.stringify(entry).sha256_text()

func event_count(kind: String) -> int:
	var count := 0
	for event in FakeSync.events():
		if event.kind == kind: count += 1
	return count

func wait_for_idle(timeout_seconds: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while controller._sync_thread != null or controller._open_thread != null:
		if Time.get_ticks_msec() >= deadline: return false
		await get_tree().process_frame
	return true

func wait_for_open(timeout_seconds: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while controller.last_open_uri.is_empty():
		if Time.get_ticks_msec() >= deadline: return false
		await get_tree().process_frame
	return true

func event_index(kind: String, id: String = "") -> int:
	var events := FakeSync.events()
	for index in events.size():
		var event: Dictionary = events[index]
		var event_id := str(event.get("id", event.get("entry", {}).get("id", "")))
		if event.kind == kind and (id.is_empty() or event_id == id): return index
	return -1

func test_background_sync() -> void:
	FakeSync.reset(180, false, 80)
	controller.sync_enabled = true
	var entry: Dictionary = store.entries[0].duplicate(true)
	seed_batch([entry])
	var start := Time.get_ticks_msec()
	controller._start_sync()
	var frames := 0
	while controller._sync_thread != null and Time.get_ticks_msec() - start < 1500:
		frames += 1
		await get_tree().process_frame
	check(frames >= 3 and event_count("sync_complete") == 1 and controller._sync_thread == null, "slow Obsidian work runs in a background thread while UI frames continue")
	check(controller._sync_pending.is_empty(), "successful background work drains exactly its queued batch")
	FakeSync.reset(140)
	seed_batch([entry])
	controller._start_sync()
	await pause(0.035)
	var changed := entry.duplicate(true)
	changed.translation = "newer while syncing"
	controller._sync_pending[changed.id] = changed
	check(await wait_for_idle(), "queued update after a started batch eventually becomes idle")
	await pause(0.08)
	check(await wait_for_idle(), "deferred follow-up background batch also finishes")
	var completed: Array = []
	for event in FakeSync.events():
		if event.kind == "sync_complete": completed.append(event.entry)
	check(completed.size() == 2 and completed[1].translation == "newer while syncing", "an entry changed during synchronization is written again with its latest queued value")

func test_background_cancel() -> void:
	FakeSync.reset(160)
	var first: Dictionary = store.entries[0].duplicate(true)
	var second: Dictionary = store.entries[1].duplicate(true)
	controller.sync_enabled = true
	seed_batch([first, second])
	controller._start_sync()
	await pause(0.03)
	controller.set_sync_enabled(false)
	check(await wait_for_idle(), "disabling auto-sync finishes the current bounded write")
	check(event_count("sync_start") == 1 and controller._sync_pending.is_empty(), "sync cancellation stops subsequent entries and clears queued writes")
	FakeSync.reset(120, false, 170)
	controller.sync_enabled = true
	seed_batch([first, second])
	controller._start_sync()
	await pause(0.025)
	controller.set_sync_enabled(false)
	check(await wait_for_idle() and event_count("sync_start") == 0, "cancellation during configuration prevents all entry writes")

func test_failed_batch() -> void:
	FakeSync.reset(90, true)
	controller.sync_enabled = true
	var first: Dictionary = store.entries[0].duplicate(true)
	var second: Dictionary = store.entries[1].duplicate(true)
	seed_batch([first, second])
	controller._start_sync()
	await pause(0.025)
	check(store.update_entry(first.id, {"notes": "updated while failed batch ran"}).ok, "edit a queued entry during a failing background batch")
	check(await wait_for_idle(), "failed background work rejoins its thread")
	check(controller._sync_pending.size() == 2 and controller._sync_pending[first.id].notes == "updated while failed batch ran", "a failed batch retains all still-existing entries using their latest saved state")
	var before := event_count("sync_start")
	await pause(0.25)
	check(event_count("sync_start") == before and controller._sync_thread == null, "temporary failure does not create an automatic retry loop")
	FakeSync.reset(60)
	controller._start_sync()
	check(await wait_for_idle() and event_count("sync_complete") == 2 and controller._sync_pending.is_empty(), "explicit retry can finish the retained failed batch")
	controller.sync_enabled = false

func test_open_sync_races() -> void:
	var first: Dictionary = store.entries[0].duplicate(true)
	var second: Dictionary = store.entries[1].duplicate(true)
	controller.sync_enabled = true
	FakeSync.reset(110)
	controller.last_open_uri = ""
	seed_batch([first])
	# Model a store change scheduling its worker, then an immediate Open action
	# arriving in the same frame before the deferred _start_sync executes.
	controller._start_sync.call_deferred()
	controller.open_entry(first.id)
	check(await wait_for_open(), "opening immediately after collection finishes before the deferred worker race can strand it")
	check(event_count("sync_complete") == 1 and event_index("sync_complete", first.id) < event_index("open_start", first.id) and controller._sync_pending.is_empty(), "open waits for a queued but not-yet-started note write before resolving its path")
	FakeSync.reset(130)
	controller.last_open_uri = ""
	seed_batch([first])
	controller._start_sync()
	await pause(0.025)
	controller._sync_pending[second.id] = second
	controller.open_entry(second.id)
	check(await wait_for_open(), "opening an entry queued behind a running batch completes")
	check(event_count("sync_complete") == 2 and event_index("sync_complete", second.id) < event_index("open_start", second.id), "open drains the follow-up batch containing the selected new entry before resolving it")
	FakeSync.reset(65, true)
	controller.last_open_uri = ""
	seed_batch([first, second])
	controller._start_sync()
	check(await wait_for_idle() and controller._sync_failed, "a failed batch records its stopped state for open actions")
	var before := event_count("sync_start")
	controller.open_entry(first.id)
	check(await wait_for_open(), "opening after a failed batch can resolve a previous note without waiting forever")
	await pause(0.18)
	check(event_count("sync_start") == before and controller._sync_pending.size() == 2 and controller._sync_thread == null, "open leaves failed pending work available for explicit retry without starting an endless retry cycle")
	controller.set_sync_enabled(false)

func test_background_open() -> void:
	FakeSync.reset(220, false, 60)
	controller.last_open_uri = ""
	set_source("open keeps main text")
	await shortcut(KEY_B)
	await pause(0.3)
	controller.panel.search.text = "manipulate"
	controller.panel._on_search_changed("manipulate")
	var id: String = controller.panel.selected_entry().id
	await shortcut(KEY_O, true)
	var frames := 0
	while controller._open_thread != null and frames < 100:
		frames += 1
		await get_tree().process_frame
	check(controller.last_open_uri == "obsidian://open?path=" + ("fake/" + id + ".md").uri_encode() and event_count("open_complete") == 1, "Ctrl+Shift+O resolves and opens the selected stable note ID")
	check(frames >= 3 and code.text == "open keeps main text", "Obsidian note resolution stays in a background thread and preserves the main input")
	FakeSync.reset(200)
	controller.last_open_uri = ""
	controller.open_entry(id)
	await pause(0.025)
	controller._sync_generation += 1
	check(await wait_for_idle() and controller.last_open_uri.is_empty(), "an open result from a previous vault generation cannot launch the old note")
	await shortcut(KEY_B)
	await pause(0.3)

func test_background_delete() -> void:
	controller.set_sync_enabled(false)
	var result: Dictionary = store.upsert({"word": "delete sync fixture", "translation": "删除同步", "source_language": "en", "target_language": "zh-CN"})
	var id: String = result.entry.id
	check(store.remove_entry(id).ok and store.deleted_ids.has(id), "a local deletion has a durable remote deletion record")
	FakeSync.reset(120, true)
	controller.sync_enabled = true
	seed_batch([{"id": id, "_delete": true}])
	controller._start_sync()
	check(await wait_for_idle() and event_count("delete_failed") == 1, "deletion errors are returned by the background worker")
	check(store.deleted_ids.has(id) and controller._sync_pending.get(id, {}).get("_delete", false), "a failed deletion remains queued and persisted for explicit retry")
	await pause(0.2)
	check(event_count("delete_start") == 1, "failed deletion does not cause an automatic retry loop")
	FakeSync.reset(160)
	controller._start_sync()
	var frames := 0
	while controller._sync_thread != null:
		frames += 1
		await get_tree().process_frame
	check(frames >= 3 and event_count("delete_complete") == 1, "slow note recycling runs off the UI thread")
	check(not store.deleted_ids.has(id) and not controller._sync_pending.has(id), "only successful deletion acknowledges the durable record")
	controller.set_sync_enabled(false)

func test_automatic_delete_queue() -> void:
	controller.set_sync_enabled(false)
	var original_store: Node = controller.store
	var temporary := Store.new()
	temporary.storage_path = "user://qa/automatic-delete-" + str(OS.get_process_id()) + ".json"
	app.add_child(temporary)
	check(temporary.load_book().ok, "automatic deletion fixture uses an isolated local book")
	controller.store = temporary
	temporary.changed.connect(controller._on_store_changed)
	controller._test_sync_enabled = true
	FakeSync.reset(160)
	controller.set_sync_enabled(true)
	var result: Dictionary = temporary.upsert({"word": "automatic delete", "translation": "自动删除", "source_language": "en", "target_language": "zh-CN"})
	var id: String = result.entry.id
	await pause(0.04)
	check(controller._sync_thread != null, "automatic add starts its queued write")
	check(temporary.remove_entry(id).ok, "delete an entry while its original note is still being written")
	var deadline := Time.get_ticks_msec() + 3000
	while not temporary.deleted_ids.is_empty() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	await pause(0.15)
	check(event_count("sync_complete") == 1 and event_count("delete_complete") == 1 and event_index("sync_complete", id) < event_index("delete_complete", id), "automatic deletion follows an in-flight creation instead of resurrecting the deleted note")
	check(temporary.entries.is_empty() and temporary.deleted_ids.is_empty() and controller._sync_pending.is_empty(), "an empty book still synchronizes and acknowledges its last deletion")
	controller.set_sync_enabled(false)
	FakeSync.reset(70, true)
	result = temporary.upsert({"word": "delete retry", "translation": "删除重试", "source_language": "en", "target_language": "zh-CN"})
	id = result.entry.id
	temporary.remove_entry(id)
	controller.set_sync_enabled(true)
	await pause(0.3)
	check(event_count("delete_failed") == 1 and temporary.deleted_ids == [id] and controller._sync_failed, "automatic deletion failure keeps its persisted record and stops retrying")
	await pause(0.2)
	check(event_count("delete_start") == 1, "delete acknowledgment signals cannot create a failed retry loop")
	FakeSync.reset(80)
	controller.sync_now()
	deadline = Time.get_ticks_msec() + 3000
	while not temporary.deleted_ids.is_empty() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	await pause(0.12)
	check(event_count("delete_complete") == 1 and temporary.deleted_ids.is_empty(), "immediate sync retries persisted deletion even with no remaining entries")
	controller.set_sync_enabled(false)
	controller._test_sync_enabled = false
	temporary.changed.disconnect(controller._on_store_changed)
	controller.store = original_store
	temporary.queue_free()

func test_exit_cancellation() -> void:
	FakeSync.reset(130, false, 30)
	var orphan := Controller.new()
	app.add_child(orphan)
	orphan.app = app
	orphan.store = Store.new()
	orphan.add_child(orphan.store)
	orphan.store.storage_path = "user://qa/wordbook-exit-test-" + str(OS.get_process_id()) + ".json"
	orphan.sync_backend = FakeSync
	orphan.vault_path = "fake-exit-vault"
	var first: Dictionary = store.entries[0].duplicate(true)
	var second: Dictionary = store.entries[1].duplicate(true)
	orphan._sync_pending[first.id] = first
	orphan._sync_pending[second.id] = second
	orphan._start_sync()
	await pause(0.025)
	var start := Time.get_ticks_msec()
	# Scene shutdown exits the tree before objects are freed. Explicit free while
	# a worker's bound method is active is prohibited by Godot's object lock.
	app.remove_child(orphan)
	await get_tree().process_frame
	orphan.free()
	check(Time.get_ticks_msec() - start < 650 and event_count("sync_start") <= 1, "controller exit cancels further writes and joins its background thread cleanly")
