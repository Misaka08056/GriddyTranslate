extends Node

const Menu = preload("res://Scripts/selection_menu.gd")
var app: Node2D
var code: CodeEdit
var failures := 0
var output := ""
var mouse_pixel := Vector2.ZERO
var mouse_down := false

class FakeSpeech extends Node:
	var calls: Array = []
	func stop() -> void: pass
	func speak(text: String, language: String) -> String:
		calls.append([text, language])
		return ""

class FakeTranslation extends Node:
	var provider := "youdao"
	var calls: Array = []
	func translate_chunk(text: String, _source: String, _target: String) -> Dictionary:
		calls.append(text)
		return {"ok": true, "text": "快捷键测试译文。"}

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../qa/menu-source")
	DirAccess.make_dir_recursive_absolute(output)
	Input.use_accumulated_input = false
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func key(keycode: Key, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = control
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func click_at(pixel: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse_down = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func move_to(pixel: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = event.position
	event.relative = pixel - mouse_pixel
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_down else 0
	mouse_pixel = pixel
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func fits(menu: OptionButton) -> bool:
	var bounds: Rect2 = menu.menu_rect()
	var window := Vector2(get_window().size)
	return bounds.position.x >= 10 and bounds.position.y >= 10 and bounds.end.x <= window.x - 10 and bounds.end.y <= window.y - 10

func aligned(menu: OptionButton) -> bool:
	var anchor: Rect2 = menu.anchor_rect()
	var bounds: Rect2 = menu.menu_rect()
	var window := Vector2(get_window().size)
	var expected_left := clampf(anchor.position.x, 12.0, window.x - bounds.size.x - 12.0)
	return absf(bounds.position.x - expected_left) <= 1.1

func dropdown(property: String) -> OptionButton:
	var list: Node = app.get_node("Settings/SettingsList")
	for row in list.get_children():
		if row.get_node("Control2/HSlider").get_meta("setting_property", "") == property:
			return row.get_node("Control5/OptionButton")
	return null

func stable_menu(menu: OptionButton, description: String) -> void:
	var original: Rect2 = menu.menu_rect()
	var trigger: Rect2 = menu.anchor_rect()
	var camera: Camera2D = app.get_node("Misc/Cam")
	var initial_motion := camera.offset
	var drift := 0.0
	var relative_drift := 0.0
	var original_gap := original.position - trigger.position
	var other_motion := 0.0
	for frame in 24:
		await RenderingServer.frame_post_draw
		var current: Rect2 = menu.menu_rect()
		drift = maxf(drift, current.position.distance_to(original.position) + current.size.distance_to(original.size))
		var current_trigger: Rect2 = menu.anchor_rect()
		relative_drift = maxf(relative_drift, (current.position - current_trigger.position).distance_to(original_gap))
		other_motion = maxf(other_motion, camera.offset.distance_to(initial_motion))
	check(relative_drift < 0.10, description + " follows its trigger in the same frame without relative jitter")
	check(drift > 0.05, description + " floats together with its trigger instead of staying fixed on screen")
	check(other_motion > 0.05 and camera.motion_enabled, description + " leaves the camera and surrounding UI moving")

func run() -> void:
	get_tree().create_timer(100).timeout.connect(func(): get_tree().quit(2))
	await get_tree().create_timer(0.6).timeout
	LuaSingleton.change_setting("music", false)
	LuaSingleton.change_setting("screen_motion", true)
	key(KEY_T, true)
	await get_tree().create_timer(1.2).timeout
	var theme_menu: OptionButton = app.get_node("ThemePicker/ThemeChooser")
	check(code.active_overlay == theme_menu and theme_menu.has_focus(), "Ctrl+T retains the animated theme chooser and keyboard focus")
	var source_left := (get_viewport().get_final_transform() * code.get_global_transform_with_canvas()).origin.x
	check(theme_menu.anchor_rect().end.x < source_left - 12.0, "Ctrl+T trigger sits to the left of the source input with a clear gap")
	click_at(theme_menu.anchor_rect().get_center(), true)
	await get_tree().process_frame
	click_at(theme_menu.anchor_rect().get_center(), false)
	await get_tree().create_timer(0.20).timeout
	check(theme_menu.is_menu_open() and not theme_menu.get_popup().visible, "actual button click opens only the redesigned menu")
	check(aligned(theme_menu) and fits(theme_menu), "theme menu aligns to the rendered button and fits the real window")
	check(theme_menu.menu_rect().end.x < source_left - 12.0, "expanded theme list also leaves the source input clear")
	var combined: Transform2D = get_viewport().get_final_transform() * theme_menu._layer.transform
	check(combined.is_equal_approx(Transform2D.IDENTITY), "menu canvas cancels viewport stretch so text uses real screen pixels")
	check(theme_menu._font.multichannel_signed_distance_field, "opened menu uses MSDF text")
	await capture("theme-menu-dark")
	await stable_menu(theme_menu, "theme menu")
	var saved_rows := app.get_node("Settings/SettingsList").get_children()
	var previous: int = theme_menu._focused
	key(KEY_DOWN)
	await get_tree().create_timer(0.08).timeout
	check(theme_menu._focused != previous and theme_menu.selected == previous, "arrow key previews an item without committing the current theme")
	check(theme_menu._last_palette[0] == LuaSingleton.gui.background_color, "theme preview updates the whole menu palette immediately")
	check(saved_rows == app.get_node("Settings/SettingsList").get_children(), "theme preview preserves existing settings controls")
	var row: Button = theme_menu._rows[previous]
	var point := get_viewport().get_final_transform() * row.get_global_transform_with_canvas() * (row.size * 0.5)
	move_to(point)
	await get_tree().create_timer(0.10).timeout
	check(theme_menu._focused == previous, "actual mouse hover previews the theme without committing it")
	await capture("theme-menu")
	await get_tree().create_timer(0.5).timeout
	check(aligned(theme_menu), "menu continues tracking the button while the original screen motion runs")
	key(KEY_ESCAPE)
	await get_tree().create_timer(0.08).timeout
	check(not theme_menu.is_menu_open() and code.active_overlay == theme_menu, "first Escape closes only the menu and retains its parent panel")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	await get_tree().create_timer(0.18).timeout
	check(theme_menu.is_menu_open() and not theme_menu.get_popup().visible, "mapped ui_accept action opens the custom list without a native popup")
	key(KEY_ESCAPE)
	key(KEY_ENTER)
	await get_tree().create_timer(0.18).timeout
	check(theme_menu.is_menu_open() and not theme_menu.get_popup().visible, "keyboard Enter reopens the custom menu without a native popup")
	key(KEY_DOWN)
	key(KEY_ENTER)
	await get_tree().create_timer(0.10).timeout
	check(not theme_menu.is_menu_open() and LuaSingleton.theme == theme_menu.get_item_text(theme_menu.selected), "Enter commits the focused theme through the original item_selected signal")
	theme_menu.selected = LuaSingleton.themes.find("One Dark Pro Darker")
	LuaSingleton.theme = "One Dark Pro Darker"
	app.preview_theme(theme_menu.selected)
	key(KEY_ESCAPE)
	await get_tree().create_timer(1.2).timeout
	key(KEY_COMMA, true)
	await get_tree().create_timer(1.2).timeout
	var source_menu := dropdown("translation_provider")
	check(source_menu != null and source_menu.get_script() == Menu, "settings translation source uses the same redesigned selection component")
	if source_menu == null:
		finish()
		return
	app.warn("Selection menu test: this notice must not block clicking.")
	var notices_ignore := true
	var showing_notice := false
	for notice in app.canvas_layer.get_children():
		if notice is Control:
			showing_notice = showing_notice or notice.is_visible_in_tree()
			notices_ignore = notices_ignore and notice.mouse_filter == Control.MOUSE_FILTER_IGNORE
			for child in notice.get_children():
				if child is Control: notices_ignore = notices_ignore and child.mouse_filter == Control.MOUSE_FILTER_IGNORE
	check(notices_ignore and showing_notice, "visible notice and all its children ignore mouse input")
	move_to(source_menu.anchor_rect().get_center())
	await get_tree().process_frame
	click_at(source_menu.anchor_rect().get_center(), true)
	await get_tree().process_frame
	click_at(source_menu.anchor_rect().get_center(), false)
	await get_tree().create_timer(0.18).timeout
	check(source_menu.is_menu_open() and fits(source_menu) and aligned(source_menu), "settings source list opens at its own on-screen button")
	await capture("source-menu")
	await stable_menu(source_menu, "translation-source menu")
	var source_row: Button = source_menu._rows[0]
	var source_point := get_viewport().get_final_transform() * source_row.get_global_transform_with_canvas() * (source_row.size * 0.5)
	click_at(source_point, true)
	await get_tree().process_frame
	click_at(source_point, false)
	await get_tree().create_timer(0.08).timeout
	check(not source_menu.is_menu_open() and source_menu.selected == 0 and app.service.provider == "mymemory", "actual menu-row click commits through the existing settings API")
	source_menu.open_menu()
	await get_tree().create_timer(0.15).timeout
	click_at(Vector2(16, 16), true)
	click_at(Vector2(16, 16), false)
	await get_tree().process_frame
	check(not source_menu.is_menu_open() and code.active_overlay != null, "outside click closes the list without dismissing settings")
	var fonts := dropdown("editor_font")
	fonts.open_menu()
	await get_tree().create_timer(0.18).timeout
	check(fonts.is_menu_open() and fits(fonts) and fonts.item_count > 15, "long font list fits the window and scrolls instead of running offscreen")
	fonts.focus_item(fonts.item_count - 1)
	await get_tree().create_timer(0.08).timeout
	check(fonts._scroll.scroll_vertical > 0, "keyboard selection reveals the last item of a long list")
	await capture("font-menu")
	await stable_menu(fonts, "font menu")
	var font_rows: Array = fonts._rows.duplicate()
	fonts.close_menu()
	await get_tree().create_timer(0.15).timeout
	fonts.open_menu()
	await get_tree().create_timer(0.18).timeout
	check(font_rows == fonts._rows, "reopening the long font menu reuses rows and prepared fonts")
	get_window().size = Vector2i(1024, 640)
	await get_tree().create_timer(0.2).timeout
	check(fits(fonts) and aligned(fonts), "open menu realigns and fits after window resize")
	await stable_menu(fonts, "resized font menu")
	fonts.close_menu()
	await get_tree().create_timer(0.15).timeout
	for property in ["caret_type", "translation_placement"]:
		var menu := dropdown(property)
		menu.open_menu()
		await get_tree().create_timer(0.18).timeout
		check(fits(menu) and aligned(menu), property + " menu stays aligned and inside the window")
		await stable_menu(menu, property)
		menu.close_menu()
		await get_tree().create_timer(0.15).timeout
	await test_shortcut_routing(fonts)
	fonts.close_menu()
	fonts.open_menu()
	app.get_node("Settings").hide()
	await get_tree().process_frame
	check(not fonts.is_menu_open(), "hiding a parent removes its screen-layer menu")
	finish()

func test_shortcut_routing(fonts: OptionButton) -> void:
	var real_speech: Node = app.pronunciation
	var real_translation: Node = app.service
	var speech := FakeSpeech.new()
	var translation := FakeTranslation.new()
	add_child(speech)
	add_child(translation)
	app.pronunciation = speech
	app.service = translation
	app.auto_translate = false
	app.examples_enabled = false
	app.showing_translation = false
	app.source_language = "auto"
	code.editable = true
	code.text = "Menu shortcut snapshot."
	app.on_source_changed()
	fonts.open_menu()
	key(KEY_P, true)
	await get_tree().create_timer(0.05).timeout
	check(not fonts.is_menu_open() and speech.calls == [["Menu shortcut snapshot.", "en"]], "open menu passes Ctrl+P to the original pronunciation shortcut")
	fonts.open_menu()
	key(KEY_L, true)
	await get_tree().create_timer(0.05).timeout
	check(not fonts.is_menu_open() and not fonts.get_popup().visible, "Ctrl+L closes the menu and preserves the existing language-picker shortcut routing")
	fonts.open_menu()
	key(KEY_ENTER, true)
	await get_tree().create_timer(1.3).timeout
	check(not fonts.is_menu_open() and translation.calls == ["Menu shortcut snapshot."] and app.translated_text == "快捷键测试译文。", "Ctrl+Enter translates instead of reopening or committing a selection menu")
	app.pronunciation = real_speech
	app.service = real_translation
	speech.queue_free()
	translation.queue_free()
	key(KEY_COMMA, true)
	await get_tree().create_timer(1.2).timeout

func finish() -> void:
	print("MENU_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
