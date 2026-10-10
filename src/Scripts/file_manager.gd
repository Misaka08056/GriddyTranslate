class_name FileManager
extends Node2D

const Service = preload("res://Scripts/translation_service.gd")
const ExampleService = preload("res://Scripts/example_service.gd")
const ExampleReveal = preload("res://Scripts/example_reveal.gd")
const Pronunciation = preload("res://Scripts/pronunciation_service.gd")
const SelectionMenu = preload("res://Scripts/selection_menu.gd")
const NOTICE = preload("res://Scenes/notice.tscn")
const Wordbook = preload("res://Scripts/wordbook_controller.gd")
const LANGUAGES = [["auto", "Smart / 智能中英"], ["zh-CN", "Chinese / 简体中文"], ["zh-TW", "Traditional Chinese / 繁體中文"], ["en", "English / 英语"], ["ja", "Japanese / 日语"], ["ko", "Korean / 韩语"], ["fr", "French / 法语"], ["de", "German / 德语"], ["es", "Spanish / 西班牙语"], ["ru", "Russian / 俄语"], ["it", "Italian / 意大利语"], ["pt", "Portuguese / 葡萄牙语"]]
@onready var Code: CodeEdit = %Code
@onready var file_dialog = %FileDialog
@onready var canvas_layer: CanvasLayer = $CanvasLayer
var current_file := "translator"
var source_text := ""
var translated_text := ""
var source_language := "auto"
var target_language := "auto"
var last_source := "en"
var last_target := "zh-CN"
var showing_translation := false
var auto_translate := false
var busy := false
var revision := 0
var translation_generation := 0
var active_translation_key := ""
var suppress_changes := false
var last_error := ""
var source_line := 0
var source_column := 0
var service: Node
var debounce: Timer
var example_service: Node
var example_label: Control
var examples_enabled := true
var example_revision := 0
var result_source_text := ""
var translation_placement := 0
var pronunciation: Node
var wordbook: Node
var result_provider := "youdao"
var current_example: Dictionary = {}
var _startup_overlay: Node

func _ready() -> void:
	_startup_overlay = get_node_or_null("/root/Startup")
	_startup_trace("editor_enter")
	Music.attach_editor(self)
	service = Service.new()
	add_child(service)
	pronunciation = Pronunciation.new()
	add_child(pronunciation)
	pronunciation.playback_failed.connect(warn)
	example_service = ExampleService.new()
	add_child(example_service)
	example_label = ExampleReveal.new()
	example_label.name = "ExampleReveal"
	add_child(example_label)
	move_child(example_label, Code.get_index() + 1)
	get_viewport().size_changed.connect(example_label.refresh_style)
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.5
	debounce.timeout.connect(request_translation)
	add_child(debounce)
	LuaSingleton.configure_translator_settings(Code.get_theme_font("font"))
	_startup_trace("services_ready")
	_load_preferences()
	wordbook = Wordbook.new()
	wordbook.name = "WordbookController"
	add_child(wordbook)
	wordbook.setup(self)
	_startup_trace("wordbook_ready")
	DirAccess.make_dir_recursive_absolute("user://themes")
	for file in DirAccess.get_files_at("res://Lua/Themes"):
		if file.ends_with(".lua"):
			var theme_path := "user://themes/" + file
			var theme_source := FileAccess.get_file_as_string("res://Lua/Themes/" + file)
			if not FileAccess.file_exists(theme_path) or FileAccess.get_file_as_string(theme_path) != theme_source:
				var destination := FileAccess.open(theme_path, FileAccess.WRITE)
				if destination != null: destination.store_string(theme_source)
	LuaSingleton.setup_theme(LuaSingleton.theme)
	_startup_trace("theme_ready")
	for setting in LuaSingleton.settings:
		LuaSingleton.handle_internal_setting_change(setting.property, setting.value)
	_startup_trace("preferences_applied")
	Code.gutters_draw_line_numbers = false
	Code.code_completion_enabled = false
	Code.minimap_draw = false
	Code.draw_tabs = false
	Code.draw_spaces = false
	Code.text = ""
	Code.grab_focus()
	DisplayServer.window_set_title("GriddyTranslate")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--visual-test"):
		call_deferred("_run_visual_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--regression-test"):
		call_deferred("_run_regression_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--sequence-test"):
		call_deferred("_run_sequence_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--effects-test"):
		call_deferred("_run_effects_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--examples-test"):
		call_deferred("_run_examples_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--update-test"):
		call_deferred("_run_update_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--slider-test"):
		call_deferred("_run_slider_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--pronunciation-test"):
		call_deferred("_run_pronunciation_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--menu-test"):
		call_deferred("_run_menu_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--dispatch-test"):
		call_deferred("_run_dispatch_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--translation-performance-test"):
		call_deferred("_run_translation_performance_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--notice-test"):
		add_child(load("res://tests/notice_regression.gd").new())
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--theme-rendering-test"):
		call_deferred("_run_theme_rendering_test")
	for suite in ["wordbook-storage", "obsidian", "wordbook-ui", "wordbook", "wordbook-live"]:
		if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--" + suite + "-test"):
			_run_wordbook_test.call_deferred(suite)
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--startup-wrap-test"):
		call_deferred("_run_startup_wrap_test")
	if OS.get_cmdline_user_args().has("--test") and OS.get_cmdline_user_args().has("--native-startup-test"):
		add_child(load("res://tests/native_startup_regression.gd").new())
	set_meta("ready_ms", Time.get_ticks_msec())

func _run_startup_wrap_test() -> void:
	add_child(load("res://tests/startup_wrap_regression.gd").new())

func _startup_trace(stage: String) -> void:
	if OS.get_cmdline_user_args().has("--startup-profile"):
		print("STARTUP_STAGE %s=%d" % [stage, Time.get_ticks_msec()])

func _run_wordbook_test(suite: String) -> void:
	var scripts := {"wordbook-storage": "wordbook_storage_regression", "obsidian": "obsidian_sync_regression", "wordbook-ui": "wordbook_ui_regression", "wordbook": "wordbook_regression", "wordbook-live": "wordbook_live_validation"}
	add_child(load("res://tests/" + str(scripts[suite]) + ".gd").new())

func _run_translation_performance_test() -> void:
	add_child(load("res://tests/translation_performance_regression.gd").new())

func _run_dispatch_test() -> void:
	add_child(load("res://tests/translation_dispatch_regression.gd").new())

func _run_menu_test() -> void:
	add_child(load("res://tests/menu_regression.gd").new())

func _run_theme_rendering_test() -> void:
	add_child(load("res://tests/theme_rendering_regression.gd").new())

func _run_pronunciation_test() -> void:
	add_child(load("res://tests/pronunciation_regression.gd").new())

func _run_slider_test() -> void:
	add_child(load("res://tests/slider_regression.gd").new())

func _run_update_test() -> void:
	add_child(load("res://tests/update_regression.gd").new())

func _run_visual_test() -> void:
	var runner = load("res://tests/original_visual.gd").new()
	add_child(runner)

func _run_regression_test() -> void:
	var runner = load("res://tests/faithful_regression.gd").new()
	add_child(runner)

func _run_sequence_test() -> void:
	add_child(load("res://tests/comparison_sequence.gd").new())

func _run_effects_test() -> void:
	add_child(load("res://tests/effects_comparison.gd").new())

func _run_examples_test() -> void:
	add_child(load("res://tests/example_visual.gd").new())

func _input(event: InputEvent) -> void:
	# Scene input is dispatched in reverse tree order. Forward to the splash
	# first so Escape/Ctrl shortcuts cannot be consumed by the editor behind it.
	if is_instance_valid(_startup_overlay) and _startup_overlay.consume_startup_input(event):
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed: return
	if event.echo:
		if is_instance_valid(wordbook) and wordbook.is_active() and wordbook.panel.handle_key(event): get_viewport().set_input_as_handled()
		return
	if is_instance_valid(SelectionMenu.active_menu):
		if event.keycode == KEY_F11:
			SelectionMenu.active_menu.close_menu(false)
		elif SelectionMenu.active_menu.handle_key(event):
			get_viewport().set_input_as_handled()
			return
	var control: bool = event.ctrl_pressed or event.meta_pressed
	var key: int = event.keycode
	if is_instance_valid(wordbook) and wordbook.is_active():
		if wordbook.panel.handle_key(event):
			get_viewport().set_input_as_handled()
			return
		if not (key == KEY_ESCAPE or key == KEY_F11 or (control and key in [KEY_B, KEY_P, KEY_O])): return
	if key == KEY_F11:
		LuaSingleton.change_setting("fullscreen", not LuaSingleton.get_setting("fullscreen")[0].value)
		LuaSingleton.on_settings_change.emit()
	elif control and key == KEY_COMMA: Code.toggle(%Settings, true, (18 * 7.5) * 2)
	elif control and key == KEY_T: Code.toggle(%ThemeChooser, false, 340)
	elif control and key == KEY_I: Code.toggle(%Info, true, 1500)
	elif control and key == KEY_B: wordbook.toggle_panel()
	elif control and key == KEY_D:
		# Capture the selection before closing an overlay can change focus.
		if Code.active_overlay == null: wordbook.collect_current()
	elif control and event.shift_pressed and key == KEY_O: wordbook.open_selected()
	elif control and key == KEY_P:
		if wordbook.is_active(): wordbook.speak_selected(false)
		else: play_pronunciation(false)
	elif control and key == KEY_O:
		if wordbook.is_active(): wordbook.speak_selected(true)
		else: play_pronunciation(true)
	elif control and key == KEY_L:
		Code.toggle(%FileDialog)
		if Code._show == false: get_tree().create_timer(Code.panel_duration() + 0.03).timeout.connect(restore_input_focus)
	elif key == KEY_ESCAPE: close_active_panel()
	elif control and key == KEY_ENTER:
		if not await dismiss_for_action(): return
		request_translation()
	elif control and key == KEY_TAB:
		if Code.active_overlay == null: switch_view()
	elif control and key in [KEY_EQUAL, KEY_PLUS, KEY_MINUS, KEY_0]:
		var current_zoom: int = int(LuaSingleton.get_setting("view_zoom")[0].value)
		var next_zoom := 100 if key == KEY_0 else clampi(current_zoom + (-10 if key == KEY_MINUS else 10), 50, 200)
		LuaSingleton.change_setting("view_zoom", next_zoom)
		LuaSingleton.on_settings_change.emit()
	elif control and event.shift_pressed and key == KEY_C:
		if not translated_text.is_empty():
			DisplayServer.clipboard_set(translated_text)
			warn("Translation copied / 已复制译文")
	elif control and event.shift_pressed and key == KEY_X:
		if not await dismiss_for_action(): return
		swap_texts()
	elif control and key == KEY_N:
		if not await dismiss_for_action(): return
		pronunciation.stop()
		cancel_translation()
		revision += 1
		source_text = ""
		translated_text = ""
		debounce.stop()
		_display(false)
	else: return
	get_viewport().set_input_as_handled()

func play_pronunciation(translated: bool) -> void:
	var value: String = translated_text if translated else (source_text if showing_translation else Code.text)
	if value.strip_edges().is_empty():
		pronunciation.stop()
		warn("请先翻译，再按 Ctrl+O 播放译文读音。" if translated else "请先输入原文，再按 Ctrl+P 播放读音。")
		return
	var language: String = last_target if translated else source_language
	if language == "auto": language = Service.detect_language(value)
	var error: String = await pronunciation.speak(value, language)
	if not error.is_empty(): warn(error)

func dismiss_for_action() -> bool:
	# Consume the shortcut before waiting; otherwise CodeEdit also receives it.
	get_viewport().set_input_as_handled()
	if Code.node_is_transitioning: return false
	if Code.active_overlay != null:
		close_active_panel()
		await get_tree().create_timer(Code.panel_duration() + 0.05).timeout
	return Code.active_overlay == null

func restore_input_focus() -> void:
	if Code.active_overlay == null and not Code.node_is_transitioning:
		Code.grab_focus()

func on_source_changed() -> void:
	if suppress_changes or showing_translation: return
	if is_instance_valid(pronunciation): pronunciation.stop()
	cancel_translation()
	cancel_examples()
	source_text = Code.text
	revision += 1
	last_error = ""
	debounce.stop()
	if auto_translate and not source_text.strip_edges().is_empty(): debounce.start()

func on_auto_translation_changed() -> void:
	if not is_instance_valid(debounce): return
	debounce.stop()
	if auto_translate and not source_text.strip_edges().is_empty() and not showing_translation: debounce.start()

func cancel_examples() -> void:
	example_revision += 1
	current_example.clear()
	if is_instance_valid(example_label): example_label.cancel()

func on_examples_changed() -> void:
	cancel_examples()
	if examples_enabled and showing_translation:
		show_examples(example_revision)

func on_translation_placement_changed(value: int) -> void:
	translation_placement = value
	if showing_translation:
		# Refresh the read-only result without changing panel focus or re-querying.
		suppress_changes = true
		Code.text = result_display_text()
		Code.set_caret_line(result_first_line())
		Code.set_caret_column(0)
		suppress_changes = false
		if is_instance_valid(example_label): example_label.refresh_style()

func result_display_text() -> String:
	return result_source_text + "\n" + translated_text if translation_placement == 1 else translated_text

func result_first_line() -> int:
	return result_source_text.count("\n") + 1 if translation_placement == 1 else 0

func on_provider_changed(index: int) -> void:
	if not is_instance_valid(service) or index < 0 or index >= Service.PROVIDERS.size(): return
	cancel_translation()
	service.provider = Service.PROVIDERS[index]
	example_service.provider = service.provider
	revision += 1
	cancel_examples()
	debounce.stop()
	if auto_translate and not showing_translation and not source_text.strip_edges().is_empty(): debounce.start()

func on_languages_changed() -> void:
	cancel_translation()
	if is_instance_valid(pronunciation): pronunciation.stop()
	revision += 1
	cancel_examples()
	debounce.stop()
	if auto_translate and not showing_translation and not source_text.strip_edges().is_empty(): debounce.start()

func cancel_translation() -> void:
	# Invalidate the coroutine before cancellation can wake an older HTTP wait.
	translation_generation += 1
	busy = false
	active_translation_key = ""
	if is_instance_valid(service) and service.has_method("cancel"): service.cancel()

func show_examples(token: int) -> void:
	if not examples_enabled or not showing_translation or last_source != "en" or not last_target.begins_with("zh"): return
	if ExampleService.example_query(result_source_text).is_empty(): return
	var example: Dictionary = await example_service.get_example(result_source_text)
	if token != example_revision or not examples_enabled or not showing_translation or example.is_empty(): return
	var result: Dictionary
	if example.has("chinese") and last_target == "zh-CN":
		result = {"ok": true, "text": example.chinese}
	else:
		result = await service.translate_chunk(example.english, "en", last_target)
	if token != example_revision or not examples_enabled or not showing_translation or not result.ok: return
	current_example = {"english": str(example.english), "chinese": str(result.text)}
	example_label.show_example(example.english, str(result.text))

func request_translation() -> void:
	debounce.stop()
	if not showing_translation: source_text = Code.text
	if source_text.strip_edges().is_empty(): return
	if source_text.length() > 5000:
		warn("Maximum 5000 characters / 单次最多 5000 字")
		return
	var source := source_language
	if source == "auto": source = Service.detect_language(source_text)
	var target := target_language
	if target == "auto": target = "en" if source.begins_with("zh") else "zh-CN"
	var request_revision := revision
	var value := source_text
	var request_key := JSON.stringify([service.provider, source, target, value])
	# Repeated Ctrl+Enter joins the current snapshot without restarting its HTTP.
	if busy and active_translation_key == request_key: return
	if busy: cancel_translation()
	last_error = ""
	if source == target:
		last_source = source
		last_target = target
		result_provider = service.provider
		result_source_text = value
		translated_text = value
		_display(true)
		return
	translation_generation += 1
	var token := translation_generation
	busy = true
	active_translation_key = request_key
	var result: Dictionary
	if service.has_method("translate_text"):
		result = await service.translate_text(value, source, target)
	else:
		result = await _translate_chunks(value, source, target, token)
	# A cancelled request may finish after its replacement. It must not clear
	# the new request's busy state or apply an obsolete translation/error.
	if token != translation_generation: return
	busy = false
	active_translation_key = ""
	if request_revision != revision or result.get("cancelled", false): return
	if not result.get("ok", false):
		last_error = str(result.get("error", "翻译服务暂不可用。Ctrl+Enter 重试。"))
		if not last_error.is_empty(): warn(last_error)
		return
	last_source = source
	last_target = target
	result_provider = service.provider
	result_source_text = value
	translated_text = str(result.text)
	if Code.active_overlay == null: _display(true)

func _translate_chunks(value: String, source: String, target: String, token: int) -> Dictionary:
	# Keep the legacy chunk API available for alternate service adapters.
	var combined := ""
	for piece in Service.split_chunks(value):
		if token != translation_generation: return {"ok": false, "cancelled": true}
		if piece.strip_edges().is_empty():
			combined += piece
			continue
		var result: Dictionary = await service.translate_chunk(piece, source, target)
		if token != translation_generation: return {"ok": false, "cancelled": true}
		if not result.get("ok", false): return result
		var leading: String = piece.substr(0, piece.length() - piece.lstrip(" \t\r\n").length())
		var trailing: String = piece.substr(piece.rstrip(" \t\r\n").length())
		combined += leading + str(result.text).strip_edges() + trailing
	return {"ok": true, "text": combined}

func _display(target: bool) -> void:
	cancel_examples()
	if not showing_translation:
		source_line = Code.get_caret_line()
		source_column = Code.get_caret_column()
	showing_translation = target
	suppress_changes = true
	Code.editable = not target
	Code.text = result_display_text() if target else source_text
	Code.set_caret_line(result_first_line() if target else mini(source_line, Code.get_line_count() - 1))
	Code.set_caret_column(0 if target else mini(source_column, Code.get_line(Code.get_caret_line()).length()))
	suppress_changes = false
	Code.grab_focus()
	%Cam.focus_die()
	if target and examples_enabled: show_examples(example_revision)

func switch_view() -> void:
	if translated_text.is_empty():
		warn("Ctrl + Enter to translate / 按 Ctrl + Enter 翻译")
		return
	if not showing_translation: source_text = Code.text
	_display(not showing_translation)

func swap_texts() -> void:
	if translated_text.is_empty() or busy: return
	var original: String = source_text if showing_translation else Code.text
	if original != result_source_text:
		warn("原文已修改，请先按 Ctrl+Enter 翻译，再交换语言。")
		return
	pronunciation.stop()
	var previous := source_text
	source_text = translated_text
	translated_text = previous
	result_source_text = source_text
	source_language = last_target
	target_language = last_source
	var old_language := last_source
	last_source = last_target
	last_target = old_language
	revision += 1
	_display(false)
	file_dialog.setup()
	_save_preferences()

func _exit_tree() -> void:
	cancel_translation()
	if is_instance_valid(pronunciation): pronunciation.stop()

func close_active_panel() -> void:
	if is_instance_valid(SelectionMenu.active_menu):
		SelectionMenu.active_menu.close_menu()
		return
	if Code.node_is_transitioning: return
	if Code.active_overlay != null:
		var node = Code.active_overlay
		if node == %Settings: Code.toggle(node, true, (18 * 7.5) * 2)
		elif node == %Info: Code.toggle(node, true, 1500)
		elif node == %ThemeChooser: Code.toggle(node, false, 340)
		else:
			Code.toggle(node)
			get_tree().create_timer(Code.panel_duration() + 0.03).timeout.connect(restore_input_focus)
	elif showing_translation: _display(false)

func warn(message: String) -> void:
	for previous in canvas_layer.get_children():
		if previous.has_method("dismiss"): previous.dismiss()
	var notice = NOTICE.instantiate()
	canvas_layer.add_child(notice)
	notice.set_notice(message)

func preview_theme(index: int) -> void:
	LuaSingleton.setup_theme(%ThemeChooser.get_item_text(index))
func _on_theme_chooser_item_focused(index): preview_theme(index)
func _on_theme_chooser_item_selected(index):
	preview_theme(index)
	LuaSingleton.theme = %ThemeChooser.get_item_text(index)
	_save_preferences()
func _on_auto_save_timer_timeout() -> void: _save_preferences()

func _load_preferences() -> void:
	if OS.get_cmdline_user_args().has("--test"): return
	var config := ConfigFile.new()
	if config.load("user://translator.cfg") != OK: return
	var saved_theme: String = config.get_value("settings", "theme", LuaSingleton.theme)
	if LuaSingleton.themes.has(saved_theme): LuaSingleton.theme = saved_theme
	source_language = config.get_value("settings", "source", "auto")
	target_language = config.get_value("settings", "target", "auto")
	for setting in LuaSingleton.settings:
		var value = config.get_value("visual", setting.property, setting.value)
		if typeof(value) == typeof(setting.value): setting.value = value
		elif value is float and setting.value is int and setting.options.is_empty(): setting.value = int(value)
		if setting.has("min") and (setting.value is float or setting.value is int): setting.value = clamp(setting.value, setting.min, setting.max)
	var selected_font: String = config.get_value("settings", "font", "griddycode-default")
	var font_setting: Dictionary = LuaSingleton.get_setting("editor_font")[0]
	font_setting.value = 0
	for index in LuaSingleton.fonts.size():
		if LuaSingleton.fonts[index].name == selected_font:
			font_setting.value = index
			break
	var selected_provider: String = config.get_value("settings", "provider", "youdao")
	var provider_setting: Dictionary = LuaSingleton.get_setting("translation_provider")[0]
	provider_setting.value = maxi(0, Service.PROVIDERS.find(selected_provider))
	auto_translate = config.get_value("settings", "auto", false)
	LuaSingleton.get_setting("translation_auto")[0].value = auto_translate

func _save_preferences() -> void:
	if OS.get_cmdline_user_args().has("--test"): return
	var config := ConfigFile.new()
	config.set_value("settings", "theme", LuaSingleton.theme)
	config.set_value("settings", "source", source_language)
	config.set_value("settings", "target", target_language)
	config.set_value("settings", "auto", auto_translate)
	var selected_font: int = LuaSingleton.get_setting("editor_font")[0].value
	config.set_value("settings", "font", LuaSingleton.fonts[selected_font].name)
	config.set_value("settings", "provider", Service.PROVIDERS[LuaSingleton.get_setting("translation_provider")[0].value])
	if is_instance_valid(wordbook): wordbook.save_preferences(config)
	for setting in LuaSingleton.settings: config.set_value("visual", setting.property, setting.value)
	config.save("user://translator.cfg")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_preferences()
		get_tree().quit()

