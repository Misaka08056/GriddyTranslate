extends Node
var failures := 0
var states: Array = []
var output := ""
var app: Node2D
var code: CodeEdit
var cam: Camera2D
var translator := false

func _ready() -> void:
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	app = get_parent()
	code = app.get_node("Code")
	cam = app.get_node("Misc/Cam")
	translator = app.has_method("request_translation")
	call_deferred("run")

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func record(name: String) -> void:
	states.append({"name": name, "camera": [cam.position.x, cam.position.y], "zoom": [cam.zoom.x, cam.zoom.y], "offset": [cam.offset.x, cam.offset.y], "settings_x": app.get_node("Settings").position.x, "settings_alpha": app.get_node("Settings").modulate.a, "settings_visible": app.get_node("Settings").visible, "camera_busy": cam.busy, "show": code._show, "transitioning": code.node_is_transitioning, "overlay": str(code.active_overlay)})
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func press(key: int, ctrl: bool = true) -> void:
	# Drive the same original toggle method; action polling is frame-dependent.
	if key == KEY_COMMA:
		code.toggle(app.get_node("Settings"), true, 270)
		return
	if key == KEY_T:
		code.toggle(app.get_node("ThemePicker/ThemeChooser"), false, 340)
		return
	if key == KEY_L or (key == KEY_O and not translator):
		code.toggle(app.get_node("FileDialog"))
		return
	if key == KEY_ESCAPE:
		app.close_active_panel()
		return
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = key
	event.ctrl_pressed = ctrl
	get_viewport().push_input(event)

func release(key: int, ctrl: bool = true) -> void:
	var event := InputEventKey.new()
	event.pressed = false
	event.keycode = key
	event.ctrl_pressed = ctrl
	get_viewport().push_input(event)

func run() -> void:
	get_tree().create_timer(120).timeout.connect(func():
		print("FAIL test timeout")
		get_tree().quit(2))
	await get_tree().create_timer(0.6).timeout
	code.text = "Hello world"
	if translator: app.on_source_changed()
	code.gutters_draw_line_numbers = false
	code.minimap_draw = false
	code.set_caret_line(0)
	code.set_caret_column(5)
	await get_tree().create_timer(2.0).timeout
	var env: Environment = app.get_node("WorldEnvironment").environment
	check(env.glow_enabled and env.glow_hdr_threshold == 0.0 and env.glow_blend_mode == 0, "original HDR glow configuration")
	check(cam.radius == 4 and cam.speed == 2 and cam.max_zoom == Vector2(10,10), "original camera parameters")
	check(cam.zoom.x > 7, "caret-focused zoom")
	await record("input")
	# Freeze only the comparison frame; live motion assertions remain above/below.
	cam.radius = 0
	cam.offset = Vector2.ZERO
	code.caret_blink = false
	var metrics: Vector2 = cam.get_font_metrics()
	var deterministic_position := code.get_caret_draw_pos() - Vector2(2 * metrics.x, 0)
	cam.position = deterministic_position
	cam.zoom = Vector2.ONE * clampf(10.0 - float(code.get_longest_line().length() + 1) / 7.0, 1, 10)
	await get_tree().create_timer(1.4).timeout
	await record("input-deterministic")
	cam.radius = 4
	code.caret_blink = true
	var old_x: float = app.get_node("Settings").position.x
	press(KEY_COMMA)
	await get_tree().process_frame
	release(KEY_COMMA)
	await get_tree().create_timer(0.06).timeout
	check(cam.busy, "settings command moves camera focus")
	check(app.get_node("Settings").position.x >= old_x, "settings starts at original position")
	await record("settings-early")
	await get_tree().create_timer(0.16).timeout
	await record("settings-slide-end")
	await get_tree().create_timer(1.2).timeout
	await record("settings-focused")
	check(abs(app.get_node("Settings").position.x - old_x - 270) < 0.1, "original settings slide distance")
	check(cam.zoom.is_equal_approx(Vector2.ONE), "original settings camera zoom")
	if translator:
		check(not app.get_node("Settings").has_node("VideoStreamPlayer"), "settings side animation removed as requested")
	else:
		check(app.get_node("Settings").get_node("VideoStreamPlayer").is_playing(), "original reference cat video retained")
	press(KEY_COMMA)
	await get_tree().process_frame
	release(KEY_COMMA)
	await get_tree().create_timer(1.8).timeout
	check(not cam.busy and code.has_focus(), "settings closes and restores caret focus")
	await record("back-to-input")
	code.set_caret_column(10)
	var previous_camera := cam.position
	await get_tree().create_timer(1.5).timeout
	check(cam.position.distance_to(previous_camera) > 25, "camera follows caret movement")
	await record("caret-moved")
	press(KEY_T)
	await get_tree().process_frame
	release(KEY_T)
	await get_tree().create_timer(1.4).timeout
	check(code.active_overlay == app.get_node("ThemePicker/ThemeChooser"), "original theme shortcut and overlay")
	await record("themes")
	press(KEY_T)
	await get_tree().process_frame
	release(KEY_T)
	await get_tree().create_timer(1.4).timeout
	if translator:
		press(KEY_L)
		await get_tree().process_frame
		release(KEY_L)
		await get_tree().create_timer(1.4).timeout
		check(code.active_overlay == app.get_node("FileDialog"), "languages use original file-picker animation")
		await record("languages")
		press(KEY_ESCAPE, false)
		await get_tree().process_frame
		release(KEY_ESCAPE, false)
		await get_tree().create_timer(1.4).timeout
		check(code.active_overlay == null and code.has_focus(), "Escape restores original input")
		code.text = "Hello world"
		app.on_source_changed()
		await app.request_translation()
		check(app.last_error.is_empty(), "live translation: " + app.last_error)
		check(app.showing_translation and ("你" in code.text or "世界" in code.text), "translation shown in original canvas")
		await get_tree().create_timer(2.0).timeout
		await record("translation")
		press(KEY_TAB)
		await get_tree().process_frame
		release(KEY_TAB)
		await get_tree().create_timer(1.6).timeout
		check(not app.showing_translation and code.text == "Hello world", "Ctrl+Tab restores original text")
		# Exercise InputMap with actual Ctrl+comma key attributes, not only the toggle method.
		var physical := InputEventKey.new()
		physical.keycode = KEY_COMMA
		physical.physical_keycode = KEY_COMMA
		physical.ctrl_pressed = true
		physical.pressed = true
		check(InputMap.event_is_action(physical, "ui_settings"), "Ctrl+comma matches original InputMap")
		Input.parse_input_event(physical)
		Input.flush_buffered_events()
		await get_tree().create_timer(1.4).timeout
		physical = physical.duplicate()
		physical.pressed = false
		Input.parse_input_event(physical)
		Input.flush_buffered_events()
		check(code.active_overlay == app.get_node("Settings"), "physical Ctrl+comma opens settings")
		await get_tree().create_timer(0.2).timeout
		physical = physical.duplicate()
		physical.pressed = true
		Input.parse_input_event(physical)
		Input.flush_buffered_events()
		await get_tree().create_timer(1.4).timeout
		physical = physical.duplicate()
		physical.pressed = false
		Input.parse_input_event(physical)
		Input.flush_buffered_events()
		check(code.active_overlay == null and code.has_focus(), "physical Ctrl+comma closes settings")
	var file := FileAccess.open(output.path_join("states.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(states, "\t"))
	print("ORIGINAL_VISUAL_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
