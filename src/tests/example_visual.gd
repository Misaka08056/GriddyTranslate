extends Node

var app: Node2D
var code: CodeEdit
var output: String
var failures := 0

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func capture(name: String, small: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if small: image.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	image.save_png(output.path_join(name + ".png"))

func run() -> void:
	get_tree().create_timer(140).timeout.connect(func():
		print("FAIL examples test timeout")
		get_tree().quit(2))
	await get_tree().create_timer(0.6).timeout
	check(not app.get_node("Settings").has_node("VideoStreamPlayer"), "settings right-hand animation removed")
	code.text = "Hello world"
	app.on_source_changed()
	await app.request_translation()
	check(app.service.provider == "youdao" and app.showing_translation and "世界" in code.text, "live Youdao English to Chinese")
	var waited := 0.0
	while not app.example_label.has_example and waited < 24.0:
		await get_tree().create_timer(0.04).timeout
		waited += 0.04
	check(app.example_label.has_example, "live bilingual dictionary example")
	if app.example_label.has_example:
		print("EXAMPLE " + app.example_label.final_text)
		await get_tree().create_timer(0.1).timeout
		await capture("example-garbage")
		for frame in 48:
			await capture("reveal-%03d" % frame, true)
			await get_tree().create_timer(1.0 / 15.0).timeout
			if frame == 16: await capture("example-resolving")
		await capture("example-complete")
		check(not app.example_label.revealing and app.example_label.text == app.example_label.final_text, "garbage resolves to real English and Chinese")
	code.toggle(app.get_node("Settings"), true, 270)
	await get_tree().create_timer(1.4).timeout
	await capture("settings-new-options")
	check(not app.example_label.visible, "examples stay hidden behind settings")
	LuaSingleton.change_setting("display_examples", false)
	code.toggle(app.get_node("Settings"), true, 270)
	await get_tree().create_timer(1.4).timeout
	check(not app.example_label.has_example and code.has_focus(), "examples switch off and input focus returns")
	app.switch_view()
	LuaSingleton.change_setting("translation_provider", 0)
	await app.request_translation()
	check(app.service.provider == "mymemory" and app.showing_translation and app.last_error.is_empty(), "live MyMemory source selected in settings")
	check(app.service.cache.keys().any(func(key): return key.begins_with("youdao:")) and app.service.cache.keys().any(func(key): return key.begins_with("mymemory:")), "providers use separate caches")
	app.switch_view()
	code.text = "你好世界"
	app.on_source_changed()
	app.source_language = "zh-CN"
	app.target_language = "en"
	LuaSingleton.change_setting("translation_provider", 1)
	await app.request_translation()
	check(app.service.provider == "youdao" and app.last_error.is_empty() and "world" in code.text.to_lower(), "live Youdao Chinese to English")
	print("EXAMPLE_VISUAL_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
