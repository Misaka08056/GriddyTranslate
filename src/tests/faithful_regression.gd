extends Node
var failures := 0
var app: Node2D
var code: CodeEdit

class FakeService extends Node:
	var failed := false
	var provider := "youdao"
	func translate_chunk(value: String, _source: String, _target: String) -> Dictionary:
		await get_tree().create_timer(0.15).timeout
		return {"ok": false, "error": "Test network unavailable"} if failed else {"ok": true, "text": "translated:" + value}

class FakeExampleService extends Node:
	var requests := 0
	var provider := "youdao"
	func get_example(_value: String) -> Dictionary:
		requests += 1
		await get_tree().create_timer(0.15).timeout
		return {"english": "Hello, everyone.", "word": "hello"}

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func source(value: String) -> void:
	app.showing_translation = false
	code.editable = true
	code.text = value
	app.on_source_changed()

func run() -> void:
	await get_tree().create_timer(0.5).timeout
	var real_service: Node = app.service
	var real_example_service: Node = app.example_service
	var fake := FakeService.new()
	app.add_child(fake)
	app.service = fake
	var fake_examples := FakeExampleService.new()
	app.add_child(fake_examples)
	app.example_service = fake_examples
	app.examples_enabled = false
	source("old")
	app.request_translation()
	check(app.busy, "request waits asynchronously")
	source("new")
	await get_tree().create_timer(0.3).timeout
	check(app.translated_text.is_empty() and not app.showing_translation, "stale response discarded")
	await app.request_translation()
	check(app.translated_text == "translated:new" and app.showing_translation, "result uses original canvas")
	app.switch_view()
	check(code.text == "new" and code.editable, "return restores editable source")
	fake.failed = true
	source("failure")
	await app.request_translation()
	check(app.last_error == "Test network unavailable", "network error exposed")
	check(app.translated_text == "translated:new" and code.text == "failure", "error preserves source and previous result")
	fake.failed = false
	app.auto_translate = true
	source("automatic")
	await get_tree().create_timer(1.7).timeout
	check(app.translated_text == "translated:automatic", "automatic translation debounce")
	app.auto_translate = false
	app.swap_texts()
	check(code.editable and code.text == "translated:automatic", "swap restores source editor")
	check(app.source_language == "zh-CN" and app.target_language == "en", "swap language direction")
	var lua = get_node("/root/LuaSingleton")
	lua.handle_internal_setting_change("editor_font", 1)
	await get_tree().process_frame
	check(code.get_theme_font("font").get_font_name() == "Fira Code", "original font setting updates active canvas")
	check(code.get_theme_font("font").get("multichannel_signed_distance_field") == true, "Fira Code retains original MSDF rendering")
	check(lua.SYMBOLS_NERD_FONT.has_char(0xf245), "original settings icons have glyphs")
	check(code.get_theme_color("font_readonly_color") == lua.gui.font_color, "translation preserves original text brightness")
	for name in lua.themes:
		lua.setup_theme(name)
		check(code.get_theme_color("font_color") == lua.gui.font_color, "original Lua theme " + name)
	lua.setup_theme("One Dark Pro Darker")
	var picker = app.get_node("FileDialog")
	code.toggle(picker)
	await get_tree().create_timer(0.3).timeout
	picker.selected_index = 4
	picker.column = 0
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	picker._input(event)
	check(picker.staged_source == "ja" and app.source_language == "zh-CN", "language picker stages source without changing active request")
	picker.selected_index = 3
	picker._input(event)
	check(app.source_language == "ja" and app.target_language == "en", "language picker commits both languages")
	await get_tree().create_timer(0.3).timeout
	check(code.active_overlay == null and code.has_focus(), "language commit returns focus after original slide")
	code.toggle(picker)
	await get_tree().create_timer(0.3).timeout
	picker.selected_index = 3
	picker.column = 0
	picker._input(event)
	app.close_active_panel()
	await get_tree().create_timer(0.3).timeout
	check(app.source_language == "ja", "Escape cancels uncommitted language changes")
	app.source_language = "en"
	app.target_language = "zh-CN"
	app.examples_enabled = true
	source("hello")
	await app.request_translation()
	app.switch_view()
	await get_tree().create_timer(0.5).timeout
	check(not app.example_label.has_example, "stale example lookup cannot reappear on source view")
	app.switch_view()
	await get_tree().create_timer(0.45).timeout
	check(app.example_label.has_example and app.example_label.revealing and app.example_label.text != app.example_label.final_text, "example starts as gradually revealed scramble")
	await get_tree().create_timer(3.0).timeout
	check(not app.example_label.revealing and app.example_label.text == "Hello, everyone.\ntranslated:Hello, everyone.", "scramble resolves into bilingual example")
	var sentence_requests := fake_examples.requests
	app.switch_view()
	source("I want to manipulate the data with a computer.")
	await app.request_translation()
	await get_tree().create_timer(0.3).timeout
	check(fake_examples.requests == sentence_requests and not app.example_label.has_example, "sentence translation skips example lookup and removes previous word example")
	lua.change_setting("display_examples", false)
	check(not app.example_label.has_example and not app.example_label.visible, "settings switch disables and removes examples")
	var previous_requests := fake_examples.requests
	app.switch_view()
	app.switch_view()
	await get_tree().create_timer(0.4).timeout
	check(fake_examples.requests == previous_requests, "disabled examples make no dictionary requests")
	app.target_language = "en"
	app.source_language = "zh-CN"
	app.last_source = "zh-CN"
	app.last_target = "en"
	lua.change_setting("display_examples", true)
	await get_tree().create_timer(0.3).timeout
	check(fake_examples.requests == previous_requests, "examples only run for English to Chinese")
	lua.change_setting("translation_provider", 0)
	check(app.service.provider == "mymemory" and app.example_service.provider == "mymemory", "settings select MyMemory for translation and examples")
	lua.change_setting("translation_provider", 1)
	check(app.service.provider == "youdao" and app.example_service.provider == "youdao", "settings select Youdao without hidden fallback")
	app.service = real_service
	app.example_service = real_example_service
	print("FAITHFUL_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
