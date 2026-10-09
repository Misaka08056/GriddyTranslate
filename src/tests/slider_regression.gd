extends Node

# Exercise Godot's real GUI hit testing and Slider drag handling. Assigning a
# Range value or emitting drag_started would miss the moving-canvas bug.
var app: Node2D
var code: CodeEdit
var cam: Camera2D
var failures := 0
var output := ""
var mouse_position := Vector2.ZERO
var mouse_down := false
var drag_starts := 0
var drag_ends := 0

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	cam = app.get_node("Misc/Cam")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	Input.use_accumulated_input = false
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures += 1

func key(keycode: int, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = control
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func move_mouse(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - mouse_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_down else 0
	mouse_position = position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func left_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = mouse_position
	event.global_position = mouse_position
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse_down = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func find_slider(property: String) -> HSlider:
	var display: String = LuaSingleton.get_setting(property)[0].display
	for row in app.get_node("Settings/SettingsList").get_children():
		var label: RichTextLabel = row.get_node("Control/RichTextLabel")
		if label.get_parsed_text().ends_with(display):
			var slider: HSlider = row.get_node("Control2/HSlider")
			slider.drag_started.connect(func(): drag_starts += 1)
			slider.drag_ended.connect(func(_changed: bool): drag_ends += 1)
			return slider
	check(false, "slider exists: " + property)
	return null

func track_point(slider: HSlider, ratio: float) -> Vector2:
	var grabber: Texture2D = slider.get_theme_icon("grabber")
	var margin := float(grabber.get_width()) * 0.5
	var local := Vector2(margin + (slider.size.x - margin * 2.0) * ratio, slider.size.y * 0.5)
	# parse_input_event receives window pixels, unlike Viewport.push_input,
	# whose coordinates are already in logical viewport units. Include the
	# project's root stretch (1920x1080 rendered into the test window).
	return get_viewport().get_final_transform() * slider.get_global_transform_with_canvas() * local

func press_grabber(slider: HSlider) -> void:
	var ratio := (slider.value - slider.min_value) / (slider.max_value - slider.min_value)
	move_mouse(track_point(slider, ratio))
	var previous_starts := drag_starts
	left_button(true)
	await get_tree().process_frame
	if drag_starts == previous_starts:
		print("MOUSE_DIAGNOSTIC point=" + str(mouse_position) + " hovered=" + str(get_viewport().gui_get_hovered_control()) + " filter=" + str(slider.mouse_filter) + " viewport=" + str(get_viewport().get_visible_rect()) + " final=" + str(get_viewport().get_final_transform()))
	check(drag_starts > previous_starts, "mouse press starts native slider drag")

func screen_transform(control: CanvasItem) -> Transform2D:
	return get_viewport().get_final_transform() * control.get_global_transform_with_canvas()

func transform_drift(current: Transform2D, original: Transform2D, size: Vector2) -> float:
	var drift := (current.origin - original.origin).length()
	for point in [Vector2(size.x, 0.0), Vector2(0.0, size.y)]:
		drift = maxf(drift, (current * point - original * point).length())
	return drift

func drag_and_hold(slider: HSlider, ratio: float, label: String) -> void:
	if slider == null: return
	var original_preference: bool = LuaSingleton.get_setting("screen_motion")[0].value
	var row: Node = slider.get_parent().get_parent()
	var value_label: RichTextLabel = row.get_node("Control4/Value")
	var other_label: RichTextLabel = row.get_node("Control/RichTextLabel")
	var original_slider_local: Transform2D = slider.get_transform()
	var original_value_local: Transform2D = value_label.get_transform()
	await press_grabber(slider)
	var stable_slider: Transform2D = screen_transform(slider)
	var stable_value: Transform2D = screen_transform(value_label)
	var moving_label: Transform2D = screen_transform(other_label)
	var initial_offset: Vector2 = cam.offset
	var initial_phase: float = cam.d
	var start := mouse_position
	var target := track_point(slider, ratio)
	if label == "integer animation speed": await capture("slider-drag-start")
	if label == "drag during unfinished opening focus": await capture("slider-opening-start")
	for frame in 12:
		move_mouse(start.lerp(target, float(frame + 1) / 12.0))
		await get_tree().process_frame
	var held_value := slider.value
	var greatest_drift := 0.0
	var greatest_label_drift := 0.0
	var other_label_motion := 0.0
	var greatest_value_drift := 0.0
	# Rendering is uncapped; require elapsed time as well as multiple frames so
	# a fast GPU cannot turn the held-pointer test into a few milliseconds.
	var held_until := Time.get_ticks_msec() + 600
	var held_frames := 0
	while held_frames < 48 or Time.get_ticks_msec() < held_until:
		move_mouse(target)
		await get_tree().process_frame
		held_frames += 1
		greatest_drift = maxf(greatest_drift, transform_drift(screen_transform(slider), stable_slider, slider.size))
		greatest_label_drift = maxf(greatest_label_drift, transform_drift(screen_transform(value_label), stable_value, value_label.size))
		other_label_motion = maxf(other_label_motion, transform_drift(screen_transform(other_label), moving_label, other_label.size))
		greatest_value_drift = maxf(greatest_value_drift, absf(slider.value - held_value))
	check(greatest_drift < 0.02, label + ": slider screen position and scale stay fixed during native drag")
	check(greatest_label_drift < 0.02, label + ": numeric value screen position and scale stay fixed during native drag")
	check(cam.d > initial_phase and cam.offset.distance_to(initial_offset) > 0.05 and other_label_motion > 0.05, label + ": camera and other settings continue their original motion while dragging")
	if greatest_drift >= 0.02 or greatest_label_drift >= 0.02:
		print("TRANSFORM_DIAGNOSTIC slider=" + str(greatest_drift) + " value=" + str(greatest_label_drift) + " other=" + str(other_label_motion))
	check(greatest_value_drift < 0.001, label + ": a fixed mouse endpoint never changes the value")
	if greatest_value_drift >= 0.001:
		print("VALUE_DIAGNOSTIC held=" + str(held_value) + " final=" + str(slider.value) + " drift=" + str(greatest_value_drift) + " local=" + str((get_viewport().get_final_transform() * slider.get_global_transform_with_canvas()).affine_inverse() * mouse_position))
	var expected := snappedf(slider.min_value + (slider.max_value - slider.min_value) * ratio, slider.step)
	check(absf(held_value - expected) <= slider.step + 0.001, label + ": actual drag reaches the intended track value")
	check(is_equal_approx(float(LuaSingleton.get_setting(property_for_slider(slider))[0].value), slider.value), label + ": displayed slider value reaches the application setting")
	if label == "integer animation speed": await capture("slider-drag-held")
	if label == "drag during unfinished opening focus": await capture("slider-opening-held")
	var previous_ends := drag_ends
	left_button(false)
	await get_tree().process_frame
	check(drag_ends > previous_ends, label + ": mouse release ends native drag")
	await get_tree().create_timer(0.24).timeout
	check(slider.get_transform().is_equal_approx(original_slider_local) and value_label.get_transform().is_equal_approx(original_value_local), label + ": slider and value return to their row after mouse release")
	check(cam.d > initial_phase, label + ": normal motion continues after mouse release")
	check(LuaSingleton.get_setting("screen_motion")[0].value == original_preference, label + ": interaction does not overwrite screen motion preference")

func property_for_slider(slider: HSlider) -> String:
	var row: Node = slider.get_parent().get_parent()
	var label: RichTextLabel = row.get_node("Control/RichTextLabel")
	for setting in LuaSingleton.settings:
		if label.get_parsed_text().ends_with(str(setting.display)): return str(setting.property)
	return ""

func capture(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	get_tree().create_timer(45.0).timeout.connect(func():
		print("FAIL slider regression timed out")
		get_tree().quit(2))
	await get_tree().create_timer(0.6).timeout
	LuaSingleton.change_setting("music", false)
	LuaSingleton.change_setting("screen_motion", true)
	LuaSingleton.change_setting("translation_auto", false)
	LuaSingleton.change_setting("settings_animation_speed", 100)
	# Keep the content camera at zoom 1 so the controls remain visible while its
	# one-second focus tween is in progress. Test preferences remain isolated.
	code.text = "Precision mouse interaction regression ".repeat(4)
	await get_tree().create_timer(1.5).timeout
	key(KEY_COMMA, true)
	await get_tree().create_timer(1.2).timeout
	check(code.active_overlay == app.get_node("Settings"), "Ctrl+comma opens the original settings panel")
	var animation_slider := find_slider("settings_animation_speed")
	var caret_slider := find_slider("caret_interval")
	await drag_and_hold(animation_slider, 0.65, "integer animation speed")
	var before_arrow := animation_slider.value
	key(KEY_RIGHT)
	await get_tree().process_frame
	check(is_equal_approx(animation_slider.value, before_arrow + 1.0), "right arrow adjusts integer slider by exactly one")
	key(KEY_LEFT)
	await get_tree().process_frame
	check(is_equal_approx(animation_slider.value, before_arrow), "left arrow restores the integer value")
	await drag_and_hold(caret_slider, 0.45, "fractional caret blink interval")
	before_arrow = caret_slider.value
	key(KEY_RIGHT)
	await get_tree().process_frame
	check(is_equal_approx(caret_slider.value, before_arrow + 0.1), "right arrow adjusts caret interval by exactly 0.1 seconds")
	key(KEY_LEFT)
	await get_tree().process_frame
	check(is_equal_approx(caret_slider.value, before_arrow), "left arrow restores the fractional value")
	await capture("settings-slider-stable")
	# Leave and reopen with a normal one-second camera focus. The panel slide
	# finishes first; begin native dragging while camera focus is still active.
	key(KEY_ESCAPE)
	await get_tree().create_timer(1.2).timeout
	LuaSingleton.change_setting("settings_animation_speed", 100)
	key(KEY_COMMA, true)
	await get_tree().create_timer(0.30).timeout
	check(not code.node_is_transitioning and cam.focus_tween != null and cam.focus_tween.is_running(), "panel accepts input while camera focus tween is still running")
	await drag_and_hold(caret_slider, 0.60, "drag during unfinished opening focus")
	await get_tree().create_timer(0.9).timeout
	check(code.active_overlay == app.get_node("Settings") and (cam.focus_tween == null or not cam.focus_tween.is_running()), "opening focus finishes while slider interaction remains independent")
	# Esc before left-button release exercises cancellation rather than merely
	# the normal drag_ended cleanup. The user's preference must remain enabled.
	var cancelled_row: Node = animation_slider.get_parent().get_parent()
	var cancelled_value: RichTextLabel = cancelled_row.get_node("Control4/Value")
	var escape_slider_local: Transform2D = animation_slider.get_transform()
	var escape_value_local: Transform2D = cancelled_value.get_transform()
	await press_grabber(animation_slider)
	var escape_phase: float = cam.d
	key(KEY_ESCAPE)
	await get_tree().create_timer(0.5).timeout
	check(code.active_overlay == null and not app.get_node("Settings").visible, "Esc closes settings during native dragging")
	if code.active_overlay != null or app.get_node("Settings").visible:
		print("ESC_DIAGNOSTIC overlay=" + str(code.active_overlay) + " visible=" + str(app.get_node("Settings").visible) + " transitioning=" + str(code.node_is_transitioning) + " show=" + str(code._show) + " duration=" + str(code.panel_duration()))
	check(cam.d > escape_phase and LuaSingleton.get_setting("screen_motion")[0].value, "Esc keeps the user's screen motion preference enabled")
	check(not animation_slider.is_set_as_top_level() and not cancelled_value.is_set_as_top_level() and animation_slider.get_transform().is_equal_approx(escape_slider_local) and cancelled_value.get_transform().is_equal_approx(escape_value_local), "Esc clears temporary slider and numeric-value stabilization before mouse release")
	left_button(false)
	await get_tree().create_timer(1.1).timeout
	check(code.has_focus() and not cam.busy, "closing during a drag restores input and automatic camera focus")
	print("SLIDER_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
