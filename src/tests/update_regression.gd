extends Node

const Examples = preload("res://Scripts/example_service.gd")
var app: Node2D
var code: CodeEdit
var cam: Camera2D
var failures := 0
var output := ""

class TrackingExamples extends Examples:
	var queries: Array[String] = []
	func youdao_example(value: String) -> Dictionary:
		queries.append("youdao:" + value)
		return {}
	func dictionary_example(value: String) -> Dictionary:
		queries.append("dictionary:" + value)
		return {}

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	cam = app.get_node("Misc/Cam")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	get_tree().create_timer(160).timeout.connect(func(): get_tree().quit(2))
	await get_tree().create_timer(0.6).timeout
	var pair := Examples.extract_youdao_example({"blng_sents_part": {"sentence-pair": [{"sentence-eng": "A <b>short</b> &amp; useful example.", "sentence-translation": "一条有用的例句。"}]}}, "short")
	check(pair.get("english", "") == "A short & useful example." and pair.has("chinese"), "bilingual schema, HTML cleanup and Chinese translation")
	pair = Examples.extract_youdao_example({"ec": {"word": [{"trs": [{"sentence": {"en": "This is a dictionary example.", "zh": "这是一条例句。"}}]}]}}, "dictionary")
	check(pair.has("english") and pair.has("chinese"), "dictionary object/array variants")
	check(Examples.extract_youdao_example({"blng_sents_part": {"sentence-pair": [{"sentence": "hello", "sentence-translation": "你好"}]}}, "hello").is_empty(), "source itself is not offered as an example")
	check(Examples.example_query("  TAKE\tcare   of ") == "take care of", "preserve and normalize whole phrase")
	check(Examples.example_query("I want to manipulate the data with a computer.").is_empty() and Examples.example_query("hello\nworld").is_empty(), "sentences and paragraphs do not become keyword queries")
	check(Examples.valid_pair("You should take. Care of the data is important.", "照顾数据。", "take care of").is_empty(), "phrase match cannot cross a sentence boundary")
	check(Examples.valid_pair("A woman is reading a book.", "一个女人正在看书。", "man").is_empty(), "word match does not match a substring")
	var phrase_payload := {"ec": {"word": {"return-phrase": "take care of", "trs": [{"tran": "照顾"}]}}, "blng_sents_part": {"sentence-pair": [{"sentence": "You should care about it.", "sentence-translation": "你应该关心它。"}, {"sentence": "We need to take care of our bodies.", "sentence-translation": "我们需要照顾好自己的身体。"}]}}
	check(Examples.has_exact_youdao_entry(phrase_payload, "take care of"), "phrase requires an exact dictionary entry")
	pair = Examples.extract_youdao_example(phrase_payload, "take care of")
	check(pair.get("english", "") == "We need to take care of our bodies.", "reject single-keyword example and select complete phrase example")
	check(not Examples.has_exact_youdao_entry(phrase_payload, "I want to take care of my body"), "sentence search cannot masquerade as phrase entry")
	var tracking := TrackingExamples.new()
	app.add_child(tracking)
	await tracking.get_example("unknown phrase")
	check(tracking.queries == ["youdao:unknown phrase", "dictionary:unknown phrase"], "missing phrase fallback keeps the entire query")
	tracking.queries.clear()
	await tracking.get_example("This is a long sentence about manipulating data with many different words.")
	check(tracking.queries.is_empty(), "sentence does not make dictionary requests")
	tracking.provider = "mymemory"
	await tracking.get_example("unknown phrase")
	check(tracking.queries == ["dictionary:unknown phrase"], "MyMemory examples also keep the complete phrase")
	tracking.queue_free()
	for word in ["manipulate", "beautiful", "translate", "computer", "hello", "fuck"]:
		var example: Dictionary = await app.example_service.get_example(word)
		check(not example.is_empty(), "live dictionary example: " + word)
		if not example.is_empty(): print("EXAMPLE " + word + " -> " + str(example.english))
	for phrase in ["look up", "take care of", "in spite of", "break the ice"]:
		var example: Dictionary = await app.example_service.get_example(phrase)
		check(not example.is_empty() and example.get("word", "") == phrase and Examples.contains_query(str(example.get("english", "")), phrase), "live full-phrase example: " + phrase)
		if not example.is_empty(): print("PHRASE " + phrase + " -> " + str(example.english))
	for sentence in ["I want to manipulate the data with a computer", "I want to manipulate the data with a computer.", "hello\nworld", "unlikely purple robotic teapot"]:
		var example: Dictionary = await app.example_service.get_example(sentence)
		check(example.is_empty(), "no unrelated examples for sentence/unknown phrase: " + sentence.replace("\n", " / "))
	app.examples_enabled = false
	code.text = "manipulate"
	app.on_source_changed()
	await app.request_translation()
	check(app.showing_translation and app.last_error.is_empty(), "live Youdao main translation")
	var original: String = app.source_text
	var translated: String = app.translated_text
	LuaSingleton.change_setting("translation_placement", 1)
	check(code.text == original + "\n" + translated and not code.editable, "source preserved with next-line read-only translation")
	app.switch_view()
	check(code.text == original and code.editable, "return to editable source without appending translation to requests")
	app.switch_view()
	LuaSingleton.change_setting("translation_placement", 0)
	check(code.text == translated and app.source_text == original, "switch back to replacement without losing source")
	app.examples_enabled = true
	app.example_label.show_example("The technology uses a pen to manipulate a computer.", "这项技术使用笔来操作计算机。")
	await get_tree().create_timer(1.4).timeout
	var stable_positions: Array = app.example_label.glyph_positions.duplicate()
	var world_position: Vector2 = app.example_label.position
	var relative_error := 0.0
	var previous_code: Vector2 = code.get_global_transform_with_canvas().origin
	var previous_example: Vector2 = app.example_label.get_global_transform_with_canvas().origin
	cam.busy = true
	if cam.focus_tween != null: cam.focus_tween.kill()
	await capture("example-scramble")
	for frame in 50:
		await get_tree().process_frame
		var current_code: Vector2 = code.get_global_transform_with_canvas().origin
		var current_example: Vector2 = app.example_label.get_global_transform_with_canvas().origin
		relative_error = maxf(relative_error, ((current_code - previous_code) - (current_example - previous_example)).length())
		previous_code = current_code
		previous_example = current_example
	check(relative_error < 0.001 and app.example_label.position == world_position, "examples and input move in sync, no inverse-camera drift")
	check(stable_positions == app.example_label.glyph_positions, "scramble never changes glyph layout or wrapping")
	LuaSingleton.change_setting("screen_motion", false)
	await get_tree().process_frame
	check(cam.offset == Vector2.ZERO, "motion switch stops camera floating")
	cam.focus_temp(1.0)
	check(cam.pulse == 0.0, "motion switch also stops music zoom pulses")
	await get_tree().create_timer(2.0).timeout
	await capture("example-fixed")
	check(app.example_label.text == app.example_label.final_text, "example fully resolves")
	cam.busy = false
	LuaSingleton.change_setting("view_zoom", 150)
	await get_tree().create_timer(1.3).timeout
	check(absf(cam.zoom.x - cam.content_base_zoom() * 1.5) < 0.01, "zoom slider scales content while keeping automatic caret focus")
	LuaSingleton.change_setting("view_zoom", 100)
	LuaSingleton.change_setting("settings_animation_speed", 25)
	code.toggle(app.get_node("Settings"), true, 270)
	await get_tree().create_timer(0.4).timeout
	check(code.node_is_transitioning, "slow settings animation remains active for chosen duration")
	await get_tree().create_timer(0.5).timeout
	check(not code.node_is_transitioning and code.active_overlay == app.get_node("Settings"), "slow panel finishes and registers overlay")
	await get_tree().create_timer(3.2).timeout
	await capture("settings-options")
	await app.dismiss_for_action()
	await get_tree().process_frame
	check(code.active_overlay == null and code.has_focus(), "closing a slow panel waits for animation and restores focus")
	LuaSingleton.change_setting("settings_animation_speed", 300)
	code.toggle(app.get_node("Settings"), true, 270)
	await get_tree().create_timer(0.13).timeout
	check(not code.node_is_transitioning, "fast settings animation honors slider")
	await app.dismiss_for_action()
	LuaSingleton.change_setting("settings_animation_speed", 100)
	await get_tree().create_timer(1.3).timeout
	await capture("without-vhs")
	LuaSingleton.change_setting("vhs", true)
	await get_tree().create_timer(1.0).timeout
	await capture("vhs-fixed")
	if DisplayServer.get_name() != "headless":
		var image := get_viewport().get_texture().get_image()
		var white := 0
		var sampled := 0
		for y in range(0, image.get_height(), 12):
			for x in range(0, image.get_width(), 12):
				var color := image.get_pixel(x, y)
				if minf(color.r, minf(color.g, color.b)) > 0.94: white += 1
				sampled += 1
		check(float(white) / sampled < 0.10, "VHS/CRT stays readable with HDR glow, white coverage below 10 percent")
	LuaSingleton.change_setting("sunlight", true)
	check(not LuaSingleton.get_setting("vhs")[0].value and app.get_node("ShaderLayer").material.shader == LuaSingleton.SUNLIGHT, "shader switches are mutually exclusive")
	LuaSingleton.change_setting("vhs", false)
	check(app.get_node("ShaderLayer").visible, "turning off inactive shader keeps active shader visible")
	LuaSingleton.change_setting("sunlight", false)
	# Reproduce the top gap with a long line at minimum user zoom.
	app.cancel_examples()
	app.showing_translation = false
	code.editable = true
	code.text = "A" + "a".repeat(100)
	code.set_caret_line(0)
	code.set_caret_column(0)
	LuaSingleton.change_setting("view_zoom", 50)
	await get_tree().create_timer(1.5).timeout
	await capture("minimum-zoom-background")
	var background: ColorRect = app.get_node("BackgroundCanvas/ExternalBackground")
	check(background.get_parent() is CanvasLayer and not background.get_parent().follow_viewport_enabled, "background is independent of camera zoom")
	if DisplayServer.get_name() != "headless":
		var image := get_viewport().get_texture().get_image()
		var top := image.get_pixel(image.get_width() / 4, 8)
		var middle := image.get_pixel(image.get_width() / 4, image.get_height() / 3)
		check(Vector3(top.r - middle.r, top.g - middle.g, top.b - middle.b).length() < 0.01, "minimum zoom exposes no differently colored top strip")
	LuaSingleton.change_setting("view_zoom", 100)
	var picker = app.get_node("FileDialog")
	code.toggle(picker)
	await get_tree().create_timer(1.4).timeout
	await capture("languages-centered")
	var content_bounds: Vector2 = picker.content_size()
	var transform: Transform2D = picker.get_global_transform_with_canvas()
	var viewport_bounds: Rect2 = get_viewport().get_visible_rect()
	var top_left: Vector2 = transform * Vector2.ZERO
	var bottom_right: Vector2 = transform * content_bounds
	check(viewport_bounds.has_point(top_left) and viewport_bounds.has_point(bottom_right), "all languages and instructions fit on screen")
	check(((top_left + bottom_right) * 0.5 - viewport_bounds.size * 0.5).length() < 3.0, "language list centers on screen")
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	for index in app.LANGUAGES.size(): picker._input(down)
	check(picker.selected_index == app.LANGUAGES.size() - 1, "last language remains selectable")
	await capture("languages-last-selected")
	await app.dismiss_for_action()
	# Use an isolated test file; never change the user's actual preferences.
	var config := ConfigFile.new()
	for setting in LuaSingleton.settings: config.set_value("visual", setting.property, setting.value)
	config.save(output.path_join("preferences-test.cfg"))
	var loaded := ConfigFile.new()
	loaded.load(output.path_join("preferences-test.cfg"))
	check(loaded.get_value("visual", "view_zoom") is int and loaded.get_value("visual", "translation_placement") == 0, "slider values and new preferences keep expected types")
	if DisplayServer.get_name() != "headless":
		var fullscreen_key := InputEventKey.new()
		fullscreen_key.keycode = KEY_F11
		fullscreen_key.pressed = true
		app._input(fullscreen_key)
		await get_tree().create_timer(0.4).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and LuaSingleton.get_setting("fullscreen")[0].value, "F11 enables fullscreen and updates setting")
		LuaSingleton.change_setting("view_zoom", 50)
		await get_tree().create_timer(1.2).timeout
		await capture("fullscreen")
		code.toggle(picker)
		await get_tree().create_timer(1.4).timeout
		await capture("languages-fullscreen")
		var fullscreen_transform: Transform2D = picker.get_global_transform_with_canvas()
		var fullscreen_bounds: Rect2 = get_viewport().get_visible_rect()
		check(fullscreen_bounds.has_point(fullscreen_transform * Vector2.ZERO) and fullscreen_bounds.has_point(fullscreen_transform * picker.content_size()), "language list fits in fullscreen at minimum content zoom")
		await app.dismiss_for_action()
		app._input(fullscreen_key)
		await get_tree().create_timer(0.4).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and not LuaSingleton.get_setting("fullscreen")[0].value, "F11 restores windowed mode")
	print("UPDATE_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
