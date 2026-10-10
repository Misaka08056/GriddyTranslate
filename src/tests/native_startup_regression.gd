extends Node

var failures := 0
var app: Node

func _ready() -> void:
	app = get_parent()
	run.call_deferred()

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func run() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
	var splash := get_node_or_null("/root/Startup")
	var expected := OS.get_cmdline_user_args().has("--startup-animation")
	if expected: check(splash != null, "portable entry point retains the startup coordinator until the editor is usable")
	check(bool(app.get_meta("native_startup", false)) == expected, "editor records the portable startup mode")
	check(not ResourceLoader.has_cached("res://Art/Startup/cybertranslator-wordmark.png") and not ResourceLoader.has_cached("res://Art/Startup/reference-background.ogv") and not ResourceLoader.has_cached("res://Shaders/startup_logo.gdshader"), "portable startup avoids loading duplicate animation assets in the engine")
	if is_instance_valid(splash):
		check(bool(splash._native) == expected, "native animation follows the isolated startup preference")
		check(not splash.get_node("Artwork").visible, "native startup never draws a second Godot splash")
		if expected:
			# The native window covers this viewport, but the underlying editor
			# must still consume input if it briefly receives OS focus.
			var press := InputEventKey.new()
			press.keycode = KEY_A
			press.unicode = 97
			press.pressed = true
			Input.parse_input_event(press)
			var release: InputEventKey = press.duplicate()
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			await get_tree().process_frame
			check(app.get_node("Code").text.is_empty(), "input cannot edit the hidden translator during native startup")
			while is_instance_valid(splash) and not FileAccess.file_exists(splash._native_directory.path_join("ready")):
				await get_tree().process_frame
			check(app.has_meta("first_frame_ms"), "native handoff waits for the editor's actual first drawn frame")
		while is_instance_valid(splash): await get_tree().process_frame
	await get_tree().process_frame
	if expected: check(bool(app.get_meta("native_completed", false)), "native coordinator waits for the launcher's completed exit marker")
	check(app.get_node("Code").has_focus() and app.has_meta("input_ready_ms"), "native exit restores a usable focused translation canvas")
	if OS.get_cmdline_user_args().has("--borderless-test"):
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "borderless startup retains the saved window style after handoff")
		var viewport_size := get_viewport().get_visible_rect().size
		var window_size := Vector2(DisplayServer.window_get_size())
		check(absf(viewport_size.x / viewport_size.y - window_size.x / window_size.y) < 0.005, "expanded canvas fills a non-16:9 borderless window without letterbox bands")
	if expected:
		check(int(app.get_meta("startup_warm_frames", 0)) >= 6, "native cover waits for several settled editor frames before fading")
	var destination := OS.get_environment("GRIDDY_TEST_OUTPUT")
	var typed := InputEventKey.new()
	typed.keycode = KEY_A
	typed.unicode = 97
	typed.pressed = true
	Input.parse_input_event(typed)
	var typed_release: InputEventKey = typed.duplicate()
	typed_release.pressed = false
	Input.parse_input_event(typed_release)
	Input.flush_buffered_events()
	await get_tree().process_frame
	check(app.get_node("Code").text == "a", "a real key edits the translator immediately after the startup exit")
	if not destination.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(destination.path_join("native-editor.png")) == OK, "the unpacked renderer captures the focused editable canvas after exit")
	if not destination.is_empty():
		var file := FileAccess.open(destination.path_join("runtime-result.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"failures": failures, "process_id": OS.get_process_id(), "native": expected, "native_completed": app.get_meta("native_completed", false), "editor_ms": app.get_meta("first_frame_ms", -1), "input_ms": app.get_meta("input_ready_ms", -1), "warm_frames": app.get_meta("startup_warm_frames", 0), "warm_ms": app.get_meta("startup_warm_ms", 0)}, "\t"))
			file.close()
	print("NATIVE_STARTUP_COMPLETE failures=" + str(failures))
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
