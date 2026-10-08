extends SceneTree
const Service = preload("res://Scripts/translation_service.gd")
var failures := 0
var app: Control
var out_dir := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures += 1

func key(code: int, ctrl: bool = true, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(out_dir.path_join(name + ".png")) == OK, "screenshot " + name)

func run() -> void:
	out_dir = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(out_dir)
	create_timer(100).timeout.connect(func():
		print("FAIL overall timeout")
		quit(2))
	check(Service.detect_language("Hello world") == "en", "English detection")
	check(Service.detect_language("你好世界") == "zh-CN", "Chinese detection")
	check(Service.detect_language("こんにちは") == "ja", "Japanese detection")
	var long_text := "你好🙂 café，世界。\n".repeat(100)
	var chunks: Array[String] = Service.split_chunks(long_text)
	check("".join(chunks) == long_text, "chunking preserves unicode and whitespace")
	for chunk in chunks: check(chunk.to_utf8_buffer().size() <= 450, "UTF-8 byte limit")
	app = load("res://Scenes/editor.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.5).timeout
	check(app.source_edit.has_focus(), "startup focuses source")
	check(app.overlay_kind.is_empty(), "startup has no panels")
	check(app.theme_names.size() == 18, "18 original themes")
	await snapshot("empty")
	app.source_edit.text = "Hello world"
	app._text_changed()
	key(KEY_ENTER)
	await process_frame
	while app.busy: await create_timer(0.1).timeout
	check(app.last_error.is_empty(), "live English to Chinese: " + app.last_error)
	check("你" in app.target_edit.text or "世界" in app.target_edit.text, "Chinese translation: " + app.target_edit.text)
	await create_timer(0.4).timeout
	await snapshot("translation")
	key(KEY_X, true, true)
	await process_frame
	check(app.settings.source == "zh-CN" and app.settings.target == "en", "swap languages")
	check(app.target_edit.text == "Hello world", "swap texts")
	await app._translate()
	check(app.last_error.is_empty() and not app.target_edit.text.is_empty(), "live Chinese to English")
	for pair in [[KEY_L, "languages"], [KEY_T, "themes"], [KEY_COMMA, "settings"], [KEY_I, "help"]]:
		key(pair[0])
		await create_timer(0.4).timeout
		check(app.overlay_kind == pair[1], "shortcut " + pair[1])
		check(app.overlay.position.y >= 0 and app.overlay.position.y + app.overlay.size.y <= app.size.y, "panel fits " + pair[1])
		await snapshot(pair[1])
		key(KEY_ESCAPE, false)
		await process_frame
		check(app.overlay_kind.is_empty() and app.source_edit.has_focus(), "Escape returns focus")
	key(KEY_N)
	await process_frame
	check(app.source_edit.text.is_empty() and app.target_edit.text.is_empty(), "clear shortcut")
	print("SMOKE_COMPLETE failures=" + str(failures))
	quit(0 if failures == 0 else 1)
