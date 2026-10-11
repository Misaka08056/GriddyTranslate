extends Node

var app: Node
var code: CodeEdit
var fake: Node
var failures := 0

class TestService extends Node:
	var provider := "youdao"
	var starts: Array[Dictionary] = []
	func cancel() -> void: pass
	func translate_text(value: String, _source: String, _target: String) -> Dictionary:
		starts.append({"text": value, "time": Time.get_ticks_msec()})
		await get_tree().create_timer(0.4 if value.begins_with("slow") else 0.02).timeout
		return {"ok": true, "text": "translated:" + value}

func _ready() -> void:
	app = get_parent()
	code = app.Code
	run.call_deferred()

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func key(codepoint: int, control: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = codepoint
	event.ctrl_pressed = control
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	release.echo = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func edit(value: String) -> void:
	app.showing_translation = false
	code.editable = true
	code.text = value
	code.set_caret_line(0)
	code.set_caret_column(value.length())
	code.grab_focus()
	app.on_source_changed()

func run() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	while get_node_or_null("/root/Startup") != null: await get_tree().process_frame
	var real_service: Node = app.service
	fake = TestService.new()
	app.add_child(fake)
	app.service = fake
	app.examples_enabled = false
	LuaSingleton.change_setting("screen_motion", false)
	check(is_equal_approx(app.debounce.wait_time, 0.5), "existing installations retain the default half-second delay")
	LuaSingleton.change_setting("translation_delay", 100)
	LuaSingleton.change_setting("translation_auto", true)
	edit("moving caret")
	await get_tree().create_timer(0.03).timeout
	var revision: int = app.revision
	var column := code.get_caret_column()
	key(KEY_LEFT)
	key(KEY_RIGHT, false, true)
	app.on_source_changed() # A redundant signal must not schedule the same text.
	await get_tree().create_timer(0.16).timeout
	check(fake.starts.is_empty() and app.debounce.is_stopped() and app.revision == revision, "arrow navigation/repeats cancel pending automatic translation without changing its source revision")
	check(code.text == "moving caret" and code.get_caret_column() == column, "navigation still reaches CodeEdit and preserves the original text")
	edit("automatic after edit")
	await get_tree().create_timer(0.18).timeout
	check(fake.starts.size() == 1 and app.translated_text == "translated:automatic after edit", "a real text edit starts automatic translation after the chosen delay")
	edit("slow automatic")
	await get_tree().create_timer(0.15).timeout
	check(app.busy, "automatic request is in flight before caret repositioning")
	key(KEY_LEFT)
	await get_tree().create_timer(0.43).timeout
	check(not app.busy and not app.showing_translation and code.text == "slow automatic", "late automatic results cannot replace text while the user navigates it")
	edit("slow manual")
	app.request_translation()
	key(KEY_LEFT)
	await get_tree().create_timer(0.45).timeout
	check(app.translated_text == "translated:slow manual", "caret navigation does not cancel a translation explicitly requested by the user")
	LuaSingleton.change_setting("translation_delay", 400)
	var before: int = fake.starts.size()
	edit("adjusted delay")
	await get_tree().create_timer(0.16).timeout
	check(fake.starts.size() == before, "the adjusted delay prevents an early translation")
	LuaSingleton.change_setting("translation_delay", 200)
	var adjusted := Time.get_ticks_msec()
	await get_tree().create_timer(0.28).timeout
	check(fake.starts.size() == before + 1 and int(fake.starts[-1].time) - adjusted >= 180, "changing a pending delay restarts its timer with the chosen value")
	LuaSingleton.change_setting("translation_auto", false)

	# Inspect real rendered pixels below the text, where a tall focus outline
	# used to leave a bright vertical stripe at CodeEdit's right edge.
	edit("a".repeat(100))
	var camera: Camera2D = app.get_node("Misc/Cam")
	camera.busy = true
	camera.zoom = Vector2.ONE * 3
	camera.global_position = Vector2(code.size.x * 0.5, 0)
	camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var transform := get_viewport().get_final_transform() * code.get_global_transform_with_canvas()
	var edge := int((transform * Vector2(code.size.x, 0)).x)
	var longest := 0
	for x in range(maxi(0, edge - 7), mini(image.get_width(), edge + 3)):
		var bright := 0
		for y in range(image.get_height() * 2 / 3, image.get_height() - 10):
			var color := image.get_pixel(x, y)
			if minf(color.r, minf(color.g, color.b)) > 0.35: bright += 1
		longest = maxi(longest, bright)
	check(edge > 7 and edge < image.get_width() - 3 and longest < image.get_height() / 8, "focused wrapped canvas has no bright screen-height edge in the rendered image")
	var output := OS.get_environment("GRIDDY_TEST_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		check(image.save_png(output.path_join("focused-canvas.png")) == OK, "focused-canvas screenshot saves successfully")
	LuaSingleton.change_setting("translation_delay", 100)
	LuaSingleton.change_setting("translation_auto", true)
	before = fake.starts.size()
	edit("slow in settings")
	await get_tree().create_timer(0.15).timeout
	key(KEY_COMMA, true)
	await get_tree().create_timer(1.1).timeout
	check(fake.starts.size() == before + 1 and not app.showing_translation and code.text == "slow in settings", "a late automatic response cannot replace text after the settings panel opens")
	var list: Control = app.get_node("Settings/SettingsList")
	var inline_row: Control
	for row in list.get_children():
		if not row.is_queued_for_deletion() and row.get_node("Control2/HSlider").get_meta("setting_property", "") == "translation_delay": inline_row = row
	check(inline_row != null, "automatic-translation row contains its delay control")
	if inline_row != null:
		var slider: HSlider = inline_row.get_node("Control2/HSlider")
		var toggle: CheckButton = inline_row.get_node("Control2/CheckButton")
		var label: RichTextLabel = inline_row.get_node("Control4/Value")
		check(slider.visible and toggle.visible and slider.position.x > toggle.position.x + toggle.size.x and label.position.x > slider.position.x + slider.size.x, "toggle, delay track and value are visible side by side without overlapping")
		slider.value = 900
		check(is_equal_approx(app.debounce.wait_time, 0.9) and LuaSingleton.get_setting("translation_auto")[0].value, "inline delay slider applies its value without changing the auto-translation switch")
		await RenderingServer.frame_post_draw
		if not output.is_empty(): check(get_viewport().get_texture().get_image().save_png(output.path_join("inline-delay.png")) == OK, "inline-controls screenshot saves successfully")
	LuaSingleton.change_setting("translation_auto", false)
	key(KEY_ESCAPE)
	await get_tree().create_timer(1.1).timeout
	LuaSingleton.change_setting("wrap_characters", 20)
	edit("a".repeat(100))
	code.set_caret_column(2)
	await get_tree().process_frame
	camera.global_position = camera.editor_focus_position()
	camera.zoom = Vector2.ONE * camera.content_base_zoom()
	var first := camera.global_position
	code.set_caret_column(10)
	await get_tree().create_timer(1.2).timeout
	check(camera.global_position.x - first.x > 40 and camera.global_position.distance_to(camera.editor_focus_position()) < 1, "camera follows horizontal caret movement within a wrapped row")
	var row := camera.global_position
	code.set_caret_column(80)
	await get_tree().create_timer(1.2).timeout
	check(camera.global_position.y - row.y > code.get_line_height() and camera.global_position.distance_to(camera.editor_focus_position()) < 1, "camera follows the caret onto later soft-wrapped rows")
	app.service = real_service
	fake.queue_free()
	print("EDITING_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
