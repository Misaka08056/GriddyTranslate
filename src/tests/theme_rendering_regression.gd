extends Node

var app: Node
var code: CodeEdit
var failures := 0
var output := ""
var theme_events := 0
var sample_bounds: Array[Rect2] = []

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	run.call_deferred()

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

func ink_range(image: Image, bounds: Rect2) -> float:
	var low := 1.0
	var high := 0.0
	var inner := Rect2i(bounds.grow(-4)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var light := luminance(image.get_pixel(x, y))
			low = minf(low, light)
			high = maxf(high, light)
	return high - low

func measure_samples() -> void:
	# Read the positions produced by the editor's own draw pass. This avoids
	# creating additional shaped-text or Font measurement caches in the test.
	var points: Array[Vector2] = []
	for column in [0, 10, 11, 21]:
		code.set_caret_column(column)
		await RenderingServer.frame_post_draw
		points.append(code.get_caret_draw_pos())
	var top := code.get_theme_stylebox("normal").get_content_margin(SIDE_TOP)
	for index in [0, 2]:
		sample_bounds.append(Rect2(Vector2(points[index].x, top), Vector2(points[index + 1].x - points[index].x, code.get_line_height())))
	code.set_caret_column(10)

func text_bounds(index: int) -> Rect2:
	var local := sample_bounds[index]
	var transform := get_viewport().get_final_transform() * code.get_global_transform_with_canvas()
	return Rect2(transform * Vector2(local.position), transform.basis_xform(Vector2(local.size)))

func run() -> void:
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	await get_tree().create_timer(0.5).timeout
	LuaSingleton.change_setting("music", false)
	LuaSingleton.change_setting("screen_motion", false)
	app.auto_translate = false
	app.examples_enabled = false
	code.text = "manipulate manipulate\n中文翻译"
	code.set_caret_column(10)
	code.caret_blink = false
	var camera: Camera2D = app.get_node("Misc/Cam")
	camera.focus_on(Vector2(95, 25), Vector2(3.5, 3.5))
	await get_tree().create_timer(1.1).timeout
	await measure_samples()
	for theme in LuaSingleton.themes:
		LuaSingleton.change_setting("glow", true)
		LuaSingleton.setup_theme(theme)
		code.select(0, 0, 0, 10)
		await get_tree().create_timer(0.06).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(output.path_join("selection-" + str(theme).replace(" ", "-") + ".png"))
		var selected_ink := ink_range(image, text_bounds(0))
		var repeated_ink := ink_range(image, text_bounds(1))
		print("INK " + str(theme) + " selected=" + str(selected_ink) + " repeated=" + str(repeated_ink))
		check(selected_ink > 0.07 and repeated_ink > 0.07, "selected and repeated words remain readable in " + str(theme))
		check(code.get_selected_text() == "manipulate", "theme preserves selected text in " + str(theme))
		if theme == "Rose Pine Moon":
			LuaSingleton.change_setting("glow", false)
			code.add_theme_color_override("word_highlighted_color", LuaSingleton.gui.font_color)
			await RenderingServer.frame_post_draw
			var unreadable := get_viewport().get_texture().get_image()
			check(ink_range(unreadable, text_bounds(0)) < 0.07, "pixel check detects the original opaque highlight that erases selected glyphs")
			code.setup_theme()
			LuaSingleton.change_setting("glow", true)
	var settings: Node = app.get_node("Settings/SettingsList")
	var original_rows := settings.get_children()
	var elapsed: Array[float] = []
	var frames: Array[float] = []
	code.deselect()
	var menu: OptionButton = app.get_node("ThemePicker/ThemeChooser")
	code.toggle(menu, false, 18 * 28)
	await get_tree().create_timer(1.2).timeout
	menu.open_menu()
	await get_tree().create_timer(0.3).timeout
	var last_presented := Time.get_ticks_usec()
	for index in LuaSingleton.themes.size():
		var started := Time.get_ticks_usec()
		menu.focus_item(index)
		elapsed.append((Time.get_ticks_usec() - started) / 1000.0)
		await RenderingServer.frame_post_draw
		var presented := Time.get_ticks_usec()
		frames.append((presented - last_presented) / 1000.0)
		last_presented = presented
	check(original_rows == settings.get_children(), "theme previews keep existing settings controls, focus and option catalogs")
	LuaSingleton.on_theme_load.connect(func(): theme_events += 1)
	var last := LuaSingleton.themes.size() - 1
	for repeat in 3: app.preview_theme(last)
	check(theme_events == 0, "committing or rehovering an already applied theme does not reload it")
	elapsed.sort()
	frames.sort()
	var metrics := {"theme_count": elapsed.size(), "preview_cpu_ms_median": elapsed[elapsed.size() / 2], "preview_cpu_ms_max": elapsed.back(), "preview_frame_ms_median": frames[frames.size() / 2], "preview_frame_ms_p95": frames[mini(frames.size() - 1, floori(frames.size() * 0.95))], "preview_frame_ms_max": frames.back()}
	print("THEME_TIMING " + JSON.stringify(metrics))
	check(metrics.preview_cpu_ms_max < 40.0 and metrics.preview_frame_ms_p95 < 50.0, "continuous theme previews avoid the previous long CPU stalls and dropped frames")
	var report := FileAccess.open(output.path_join("timings.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(metrics, "\t"))
	menu.close_menu()
	app.close_active_panel()
	for notice in app.canvas_layer.get_children():
		if notice.has_method("dismiss"): notice.dismiss()
	await get_tree().create_timer(1.3).timeout
	await RenderingServer.frame_post_draw
	print("THEME_RENDERING_COMPLETE failures=" + str(failures))
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
