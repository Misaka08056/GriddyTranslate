extends Node

var failures := 0
var app: Node
var code: CodeEdit
var output := ""
var lua: Node

const STARTUP_TITLE := "cybertranslator"
const WORDMARK_PATH := "res://Art/Startup/cybertranslator-wordmark.png"
const BACKGROUND_PATH := "res://Art/Startup/reference-background.ogv"
const SHADER_PATH := "res://Shaders/startup_logo.gdshader"

# Called by the lightweight startup scene only in isolated test mode, before
# the editor is loaded. Capture the actual playback; do not seek or replace
# animation time, which would hide failures in its real sequence.
static func capture_startup_stages(splash: Node) -> void:
	if OS.get_cmdline_user_args().has("--startup-skip"):
		await exercise_startup_skip(splash)
		return
	var destination := OS.get_environment("GRIDDY_TEST_OUTPUT")
	if destination.is_empty(): destination = ProjectSettings.globalize_path("res://../qa/startup-wrap-source")
	DirAccess.make_dir_recursive_absolute(destination)
	var stages := [
		{"seconds": 0.55, "name": "startup-glitch"},
		{"seconds": 1.45, "name": "startup-logo"},
		{"seconds": 4.4, "name": "startup-pulse"},
		{"seconds": 10.25, "name": "startup-final-glitch"},
	]
	var records: Array = []
	var tree := splash.get_tree()
	for stage in stages:
		while is_instance_valid(splash) and not splash.skipped and float(splash.elapsed) < float(stage.seconds):
			await tree.process_frame
		if not is_instance_valid(splash) or splash.skipped: return
		var capture_error := OK
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not is_instance_valid(splash) or splash.skipped: return
			capture_error = splash.get_viewport().get_texture().get_image().save_png(destination.path_join(str(stage.name) + ".png"))
		records.append({"name": stage.name, "target_seconds": stage.seconds, "actual_seconds": float(splash.elapsed), "process_id": OS.get_process_id(), "capture_error": capture_error})
		var file := FileAccess.open(destination.path_join("stage-times.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(records, "\t"))
		file.close()

# This starts before the heavy editor scene loads. Testing only from run()
# could miss the locked interval if editor initialization takes > 1.58 s.
static func exercise_startup_skip(splash: Node) -> void:
	var tree := splash.get_tree()
	var root := tree.root
	var checks: Array = []
	root.set_meta("startup_skip_gate_checks", checks)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	checks.append({"value": not splash.can_skip(), "description": "first startup frame does not permit an early skip"})
	checks.append({"value": bool(splash.consume_startup_input(escape)), "description": "locked startup consumes pressed keys"})
	_send_escape()
	await tree.process_frame
	checks.append({"value": is_instance_valid(splash) and not splash.skipped and not splash._finishing, "description": "a real early Escape neither skips nor queues the startup transition"})
	if not is_instance_valid(splash):
		root.set_meta("startup_skip_gate_complete", true)
		return
	while is_instance_valid(splash) and int(splash.logo_complete_ms) < 0:
		await tree.process_frame
	if not is_instance_valid(splash):
		checks.append({"value": false, "description": "startup survives until the complete logo is rendered"})
		root.set_meta("startup_skip_gate_complete", true)
		return
	var logo_ms := int(splash.logo_complete_ms)
	var allowed_ms := int(splash.skip_allowed_ms)
	checks.append({"value": allowed_ms - logo_ms >= 500, "description": "skip deadline is at least half a second after the complete logo frame"})
	# Probe the visible logo interval as well as the initial fragmented logo.
	while is_instance_valid(splash) and Time.get_ticks_msec() < logo_ms + 250:
		await tree.process_frame
	if is_instance_valid(splash):
		checks.append({"value": not splash.can_skip(), "description": "complete logo remains unskippable during its first half second"})
		_send_escape()
		await tree.process_frame
		checks.append({"value": is_instance_valid(splash) and not splash.skipped and not splash._finishing, "description": "Escape during the complete-logo hold is consumed without queuing a skip"})
	while is_instance_valid(splash) and not splash.can_skip():
		await tree.process_frame
	if not is_instance_valid(splash):
		checks.append({"value": false, "description": "startup survives the skip lock"})
		root.set_meta("startup_skip_gate_complete", true)
		return
	checks.append({"value": Time.get_ticks_msec() - logo_ms >= 500 and not splash.skipped, "description": "opening the skip gate does not replay the earlier Escape"})
	# Let run() inspect the loaded editor and original artwork before exiting.
	while is_instance_valid(splash) and (not splash.editor_ready or not root.has_meta("startup_regression_started")):
		await tree.process_frame
	if not is_instance_valid(splash):
		checks.append({"value": false, "description": "startup remains present until the editor is ready"})
		root.set_meta("startup_skip_gate_complete", true)
		return
	var editor: Node = splash.editor
	var skip_ms := Time.get_ticks_msec()
	_send_escape()
	checks.append({"value": is_instance_valid(splash) and splash.skipped and splash._finishing, "description": "a real permitted Escape starts the animated exit"})
	var exit_ms := int(splash.exit_started_ms) if is_instance_valid(splash) else -1
	checks.append({"value": exit_ms >= skip_ms and not editor.has_meta("input_ready_ms"), "description": "skipping keeps the overlay present while its exit animation plays"})
	await tree.create_timer(0.12).timeout
	_send_escape()
	checks.append({"value": is_instance_valid(splash) and int(splash.exit_started_ms) == exit_ms and not editor.has_meta("input_ready_ms"), "description": "another Escape cannot truncate or restart the exit animation"})
	while is_instance_valid(splash):
		await tree.process_frame
	var input_ms := int(editor.get_meta("input_ready_ms", -1))
	checks.append({"value": input_ms - exit_ms >= 400 and input_ms - skip_ms < 1600, "description": "skip restores input after its full 0.45-second exit rather than the remaining eleven-second sequence"})
	root.set_meta("startup_skip_gate_complete", true)

static func _send_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func _ready() -> void:
	app = get_parent()
	lua = get_node('/root/LuaSingleton')
	code = app.get_node("Code")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../qa/startup-wrap-source")
	DirAccess.make_dir_recursive_absolute(output)
	run.call_deferred()

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var expected_animation := args.has("--startup-animation")
	var expected_skip := args.has("--startup-skip")
	var splash := get_node_or_null("/root/Startup")
	check(app.get_meta("startup_title", "") == STARTUP_TITLE, "startup title is cybertranslator")
	if expected_animation:
		check(splash != null and splash.editor_ready, "lightweight splash loads the original editor asynchronously")
	if expected_animation and splash != null:
		check(splash.enabled, "startup animation can be exercised with isolated test preferences")
		check(is_equal_approx(float(splash.ANIMATION_SECONDS), 11.0), "startup retains the full eleven-second reference sequence")
		var background: VideoStreamPlayer = splash.get_node("Artwork/Background")
		check(background.stream is VideoStreamTheora and background.stream.resource_path == BACKGROUND_PATH, "startup background uses Godot's portable native Theora resource")
		check(background.is_playing() and background.volume_db <= -70.0, "reference background plays silently while the editor loads")
		var logo: ColorRect = splash.get_node("Artwork/Logo")
		check(logo.get_meta("title", "") == STARTUP_TITLE, "rendered wordmark identifies cybertranslator")
		var material: ShaderMaterial = logo.material
		check(material != null and material.shader.resource_path == SHADER_PATH, "startup wordmark uses the dedicated animated glitch shader")
		if material != null:
			var texture: Texture2D = material.get_shader_parameter("wordmark")
			check(texture != null and texture.resource_path == WORDMARK_PATH, "startup loads the cybertranslator wordmark texture")
			if texture != null:
				var image := texture.get_image()
				check(image != null and image.get_used_rect().has_area() and image.detect_alpha() != Image.ALPHA_NONE, "wordmark has visible lettering and a transparent background")
		check(is_equal_approx(float(splash.EXIT_SECONDS), 0.45), "startup uses the same 0.45-second exit for skip and natural completion")
		get_tree().root.set_meta("startup_regression_started", true)
		if expected_skip:
			while not get_tree().root.has_meta("startup_skip_gate_complete"):
				await get_tree().process_frame
			var gate_checks: Array = get_tree().root.get_meta("startup_skip_gate_checks", [])
			check(gate_checks.size() >= 10, "skip regression exercises both locked input and animated exit")
			for result in gate_checks:
				check(bool(result.value), str(result.description))
		else:
			var natural_exit_ms := -1
			while is_instance_valid(splash):
				if splash._finishing and natural_exit_ms < 0:
					natural_exit_ms = int(splash.exit_started_ms)
					check(not app.has_meta("input_ready_ms"), "natural completion keeps the overlay until its exit animation finishes")
					_send_escape()
					check(is_instance_valid(splash) and int(splash.exit_started_ms) == natural_exit_ms, "input during the natural exit does not cut it short")
				await get_tree().process_frame
			check(natural_exit_ms >= 0 and int(app.get_meta("input_ready_ms", 0)) - natural_exit_ms >= 400, "natural completion plays the full exit animation before restoring input")
			check(int(app.get_meta("input_ready_ms", 0)) - int(app.get_meta("splash_first_frame_ms", 0)) >= 11000, "natural startup completes the full reference sequence before restoring input")
			var records: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("stage-times.json")))
			check(records is Array and records.size() == 4, "four reference animation phases are sampled during real playback")
			if records is Array and records.size() == 4:
				var previous_time := -1.0
				for record in records:
					var target_time := float(record.target_seconds)
					var actual_time := float(record.actual_seconds)
					check(int(record.get("process_id", -1)) == OS.get_process_id() and int(record.get("capture_error", -1)) == OK, "reference capture belongs to this run and saves successfully: " + str(record.name))
					check(actual_time >= target_time and actual_time <= target_time + 0.6 and actual_time > previous_time, "reference capture occurs in its real phase: " + str(record.name))
					if DisplayServer.get_name() != "headless":
						check(FileAccess.file_exists(output.path_join(str(record.name) + ".png")), "rendered reference capture exists: " + str(record.name))
					previous_time = actual_time
	else:
		check(not ResourceLoader.has_cached(BACKGROUND_PATH) and not ResourceLoader.has_cached(WORDMARK_PATH) and not ResourceLoader.has_cached(SHADER_PATH), "disabled startup loads neither video, wordmark nor shader assets")
		if is_instance_valid(splash):
			check(not splash.enabled, "isolated startup preference disables the animation")
			while is_instance_valid(splash): await get_tree().process_frame
	await get_tree().process_frame
	check(get_node_or_null("/root/Startup") == null and code.has_focus(), "completed startup releases its canvas and restores input focus")
	check(app.has_meta("first_frame_ms") and app.has_meta("input_ready_ms"), "startup records the first visible frame and usable input timing")
	check(app.get_node("AudioStreamPlayer").stream == null, "disabled background music is not loaded at startup")
	check(app.wordbook.panel.get_child_count() == 0, "hidden wordbook text and edit controls are not built at startup")
	var resolved := 0
	var lazy_index := -1
	for index in lua.fonts.size():
		var entry: Dictionary = lua.fonts[index]
		if entry.value == null and lazy_index < 0: lazy_index = index
		elif entry.value is SystemFont: resolved += 1
	check(resolved == 0 and lazy_index >= 0, "system-font catalog keeps unselected font files unloaded")
	if lazy_index >= 0:
		lua.change_setting("editor_font", lazy_index)
		check(lua.fonts[lazy_index].value is SystemFont, "choosing a system font resolves that family on demand")
	lua.change_setting("editor_font", 0)
	lua.change_setting("screen_motion", false)
	app.auto_translate = false
	app.examples_enabled = false
	app.showing_translation = false
	code.editable = true
	var original := "Automatic wrapping preserves the complete source text and its undo history. ".repeat(5) + "\n" + "中文翻译也会自动换行，不会把软换行送给在线翻译器。".repeat(3)
	code.text = original
	app.on_source_changed()
	lua.change_setting("auto_wrap", true)
	lua.change_setting("wrap_characters", 20)
	await get_tree().process_frame
	var narrow := code.get_line_wrap_count(0)
	check(narrow > 2 and code.get_line_wrap_count(1) > 0, "English and Chinese paragraphs both wrap without horizontal overflow")
	check(code.text == original, "soft wrapping preserves the editor's original text")
	check(app.source_text == original, "soft wrapping preserves the source sent to translation")
	check(code.get_line_count() == 2, "soft wrapping preserves the original paragraph boundaries")
	lua.change_setting("wrap_characters", 60)
	await get_tree().process_frame
	check(code.get_line_wrap_count(0) < narrow, "wrap-length slider changes the displayed line width immediately")
	check(code.get_longest_line().length() < original.length(), "automatic camera zoom uses visible wrapped rows")
	code.set_caret_line(1)
	code.set_caret_column(code.get_line(1).length())
	await get_tree().create_timer(1.1).timeout
	await capture("wrapped-chinese")
	var camera: Camera2D = app.get_node("Misc/Cam")
	check(absf(camera.zoom.x - camera.content_base_zoom()) < 0.02, "caret focus settles correctly on the final wrapped row")
	code.select_all()
	check(code.get_selected_text() == original, "copy and selection preserve the original paragraphs")
	code.deselect()
	lua.change_setting("auto_wrap", false)
	check(code.get_line_wrap_count(0) == 0 and code.text == original, "turning wrapping off restores the original unbroken display")
	lua.change_setting("auto_wrap", true)
	lua.change_setting("wrap_characters", 40)
	app.source_text = "Original text " .repeat(12)
	app.result_source_text = app.source_text
	app.translated_text = "保留原文并在下一行显示翻译。".repeat(8)
	app.translation_placement = 1
	app._display(true)
	await get_tree().create_timer(1.3).timeout
	check(code.text == app.result_source_text + "\n" + app.translated_text and code.get_line_wrap_count(1) > 0, "retained source and translation both wrap without changing result placement")
	var transform := get_viewport().get_final_transform() * code.get_global_transform_with_canvas()
	var left := (transform * Vector2.ZERO).x
	var right := (transform * Vector2(code.size.x, 0)).x
	check(left >= 0 and right <= get_window().size.x, "wrapped rows fit horizontally even when the caret is at the beginning")
	await capture("wrapped-source-and-translation")
	lua.change_setting("wrap_characters", 10)
	app.source_text = "take care of"
	app.result_source_text = app.source_text
	app.translated_text = "照顾"
	app._display(true)
	app.examples_enabled = true
	app.example_label.show_example("Please take care of yourself.", "请照顾好你自己。")
	await get_tree().create_timer(1.3).timeout
	var example_transform: Transform2D = get_viewport().get_final_transform() * app.example_label.get_global_transform_with_canvas()
	var example_left: float = (example_transform * Vector2.ZERO).x
	var example_right: float = (example_transform * Vector2(app.example_label.size.x, 0)).x
	check(example_left >= 0 and example_right <= get_window().size.x, "examples remain visible beneath a narrowly wrapped complete phrase")
	await capture("wrapped-phrase-example")
	app.cancel_examples()
	var timing := {"splash_ms": app.get_meta("splash_first_frame_ms", -1), "editor_ms": app.get_meta("first_frame_ms", -1), "input_ms": app.get_meta("input_ready_ms", -1)}
	var file := FileAccess.open(output.path_join("timing.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(timing, "\t"))
	print("STARTUP_WRAP_COMPLETE failures=" + str(failures))
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
