extends Control

# Modified from GriddyCode v1.2.2: original theme, fonts, palettes, music and shaders.
const Service = preload("res://Scripts/translation_service.gd")
const FONT = preload("res://Fonts/FiraCode-Regular.ttf")
const MUSIC = preload("res://Music/ES_Social Feedia - Heyson.wav")
const CRT = preload("res://Shaders/vhs_and_crt.gdshader")
const SUNLIGHT = preload("res://Shaders/sunlight.gdshader")
const LANGUAGES = [["auto", "智能中英 / 自动识别"], ["zh-CN", "简体中文"], ["zh-TW", "繁體中文"], ["en", "English"], ["ja", "日本語"], ["ko", "한국어"], ["fr", "Français"], ["de", "Deutsch"], ["es", "Español"], ["ru", "Русский"], ["it", "Italiano"], ["pt", "Português"]]
var source_edit: TextEdit
var target_edit: TextEdit
var canvas: Control
var divider: ColorRect
var backdrop: ColorRect
var effect: ColorRect
var shade: ColorRect
var overlay: PanelContainer
var overlay_content: VBoxContainer
var overlay_title: Label
var toast: Label
var service: Node
var debounce: Timer
var music: AudioStreamPlayer
var environment: WorldEnvironment
var settings := {"source": "auto", "target": "auto", "theme": "One Dark Pro Darker", "auto": false, "motion": true, "glow": true, "effect": 0, "music": false, "font_size": 29}
var palette: Dictionary = {}
var theme_names: Array[String] = []
var revision := 0
var busy := false
var pending := false
var overlay_kind := ""
var last_source := "en"
var last_target := "zh-CN"
var last_error := ""
var clock := 0.0
var desired_font_size := 29.0
var animated_font_size := 29.0
var toast_revision := 0
var overlay_animation: Tween

func _ready() -> void:
	_load_settings()
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial"])
	var main_font: Font = FONT.duplicate()
	main_font.set_fallbacks([fallback])
	theme = theme.duplicate()
	theme.default_font = main_font
	for type in ["Label", "Button", "OptionButton", "CheckButton", "PopupMenu", "TextEdit"]:
		theme.set_font("font", type, main_font)
		theme.set_font_size("font_size", type, 22)
	add_theme_font_override("font", main_font)
	add_theme_font_size_override("font_size", 22)
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CANVAS
	environment.environment.glow_enabled = true
	environment.environment.glow_hdr_threshold = 1.3
	environment.environment.glow_intensity = 0.35
	add_child(environment)
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	source_edit = _make_editor(false)
	source_edit.placeholder_text = "输入或粘贴原文…\n\nCtrl + Enter 翻译"
	target_edit = _make_editor(true)
	target_edit.placeholder_text = "译文"
	divider = ColorRect.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(divider)
	effect = ColorRect.new()
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect)
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.48)
	shade.hide()
	add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _close_overlay())
	overlay = PanelContainer.new()
	overlay.hide()
	add_child(overlay)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 32)
	overlay.add_child(margin)
	overlay_content = VBoxContainer.new()
	overlay_content.add_theme_constant_override("separation", 14)
	margin.add_child(overlay_content)
	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_size_override("font_size", 18)
	toast.modulate.a = 0.0
	add_child(toast)
	service = Service.new()
	add_child(service)
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 1.2
	debounce.timeout.connect(_translate)
	add_child(debounce)
	music = AudioStreamPlayer.new()
	music.stream = MUSIC
	music.volume_db = -17
	music.finished.connect(func():
		if settings.music: music.play())
	add_child(music)
	for file in DirAccess.get_files_at("res://Lua/Themes"):
		if file.ends_with(".lua"): theme_names.append(file.trim_suffix(".lua"))
	theme_names.sort()
	source_edit.text_changed.connect(_text_changed)
	resized.connect(_layout)
	_apply_preferences()
	_layout()
	source_edit.grab_focus()
	DisplayServer.window_set_title("GriddyTranslate")

func _make_editor(readonly: bool) -> TextEdit:
	var editor := TextEdit.new()
	editor.editable = not readonly
	editor.context_menu_enabled = false
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.caret_blink = true
	editor.scroll_smooth = true
	editor.scroll_v_scroll_speed = 140.0
	editor.highlight_current_line = not readonly
	editor.add_theme_font_override("font", get_theme_font("font"))
	editor.add_theme_font_size_override("font_size", int(settings.font_size))
	for name in ["normal", "focus", "read_only"]:
		var style := StyleBoxEmpty.new()
		style.content_margin_left = 6
		style.content_margin_right = 14
		style.content_margin_top = 8
		editor.add_theme_stylebox_override(name, style)
	canvas.add_child(editor)
	return editor

func _layout() -> void:
	if not is_instance_valid(source_edit): return
	var margin := clampf(size.x * 0.055, 30.0, 90.0)
	var top := clampf(size.y * 0.15, 64.0, 135.0)
	var pane_width := (size.x - margin * 2 - 54) / 2.0
	source_edit.position = Vector2(margin, top)
	source_edit.size = Vector2(pane_width, size.y - top * 2)
	target_edit.position = Vector2(margin + pane_width + 54, top)
	target_edit.size = source_edit.size
	divider.position = Vector2(size.x / 2, top + 8)
	divider.size = Vector2(1, size.y - top * 2 - 16)
	toast.position = Vector2(margin, size.y - 54)
	toast.size = Vector2(size.x - margin * 2, 28)
	if overlay.visible: _center_overlay()

func _process(delta: float) -> void:
	clock += delta
	var drift := Vector2(sin(clock * 0.8), cos(clock * 0.7)) * 1.6 if settings.motion and overlay_kind.is_empty() else Vector2.ZERO
	canvas.position = canvas.position.lerp(drift, minf(delta * 4, 1))
	animated_font_size = lerpf(animated_font_size, desired_font_size, minf(delta * 5, 1))
	var current_size := roundi(animated_font_size)
	if source_edit.get_theme_font_size("font_size") != current_size:
		source_edit.add_theme_font_size_override("font_size", current_size)
		target_edit.add_theme_font_size_override("font_size", current_size)
	divider.modulate.a = 0.5 + 0.5 * sin(clock * 4) if busy else lerpf(divider.modulate.a, 1.0, minf(delta * 5, 1))

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.keycode
	var control: bool = event.ctrl_pressed or event.meta_pressed
	if key == KEY_ESCAPE and not overlay_kind.is_empty(): _close_overlay()
	elif control and key == KEY_ENTER:
		_close_overlay()
		_translate()
	elif control and key == KEY_L: _toggle_overlay("languages")
	elif control and key == KEY_T: _toggle_overlay("themes")
	elif control and key == KEY_COMMA: _toggle_overlay("settings")
	elif control and key == KEY_I: _toggle_overlay("help")
	elif control and event.shift_pressed and key == KEY_C:
		if not target_edit.text.is_empty():
			DisplayServer.clipboard_set(target_edit.text)
			_notify("已复制译文")
	elif control and event.shift_pressed and key == KEY_X: _swap()
	elif control and key == KEY_N:
		revision += 1
		pending = false
		source_edit.text = ""
		target_edit.text = ""
		_text_changed()
		source_edit.grab_focus()
	elif control and key == KEY_TAB:
		if source_edit.has_focus(): target_edit.grab_focus()
		else: source_edit.grab_focus()
	else: return
	get_viewport().set_input_as_handled()

func _text_changed() -> void:
	revision += 1
	last_error = ""
	target_edit.modulate.a = 0.42 if not target_edit.text.is_empty() else 1.0
	desired_font_size = float(settings.font_size) - clampf(float(source_edit.text.length() - 140) / 130.0, 0, 6)
	debounce.stop()
	if source_edit.text.strip_edges().is_empty():
		target_edit.text = ""
		target_edit.placeholder_text = "译文"
		pending = false
	elif settings.auto: debounce.start()

func _translate() -> void:
	debounce.stop()
	if source_edit.text.strip_edges().is_empty(): return
	if busy:
		pending = true
		return
	var text_to_translate := source_edit.text
	if text_to_translate.length() > 5000:
		_notify("单次最多 5000 字，请分段翻译。")
		return
	var source: String = settings.source
	if source == "auto": source = Service.detect_language(text_to_translate)
	var target: String = settings.target
	if target == "auto": target = "en" if source.begins_with("zh") else "zh-CN"
	last_source = source
	last_target = target
	if source == target:
		target_edit.text = text_to_translate
		target_edit.modulate.a = 1.0
		return
	busy = true
	pending = false
	last_error = ""
	var request_revision := revision
	target_edit.placeholder_text = "翻译中…"
	var combined := ""
	for piece in Service.split_chunks(text_to_translate):
		if request_revision != revision: break
		if piece.strip_edges().is_empty():
			combined += piece
			continue
		var translated: Dictionary = await service.translate_chunk(piece, source, target)
		if request_revision != revision: break
		if not translated.ok:
			last_error = translated.error
			_notify(last_error, 7.0)
			break
		var leading: String = piece.substr(0, piece.length() - piece.lstrip(" \t\r\n").length())
		var trailing: String = piece.substr(piece.rstrip(" \t\r\n").length())
		combined += leading + str(translated.text).strip_edges() + trailing
	if request_revision == revision and last_error.is_empty():
		target_edit.text = combined
		target_edit.modulate.a = 0.25
		create_tween().tween_property(target_edit, "modulate:a", 1.0, 0.28)
	busy = false
	target_edit.placeholder_text = "译文" if last_error.is_empty() else "暂时无法翻译\nCtrl + Enter 重试"
	if pending or (settings.auto and request_revision != revision):
		pending = false
		debounce.start()

func _swap() -> void:
	if target_edit.text.is_empty() or target_edit.modulate.a < 0.9: return
	var previous := source_edit.text
	source_edit.text = target_edit.text
	target_edit.text = previous
	settings.source = last_target
	settings.target = last_source
	var language := last_source
	last_source = last_target
	last_target = language
	revision += 1
	_save_settings()
	source_edit.grab_focus()
	_notify("已交换原文、译文和语言方向")

func _apply_theme() -> void:
	palette = {"background_color": "23272e", "font_color": "abb2bf", "selection_color": "3d4556", "current_line_color": "2c313c", "caret_color": "528bff", "reserved": "c678dd", "string": "98c379", "function": "61afef"}
	var theme_script := FileAccess.get_file_as_string("res://Lua/Themes/" + str(settings.theme) + ".lua")
	var pattern := RegEx.new()
	pattern.compile('set_(?:gui|keywords)\\("([^"]+)"\\s*,\\s*"#?([0-9a-fA-F]{6,8})"\\)')
	for entry in pattern.search_all(theme_script): palette[entry.get_string(1)] = entry.get_string(2)
	var background := _color("background_color")
	backdrop.color = background
	var ui_text := Color("abb2bf") if background.get_luminance() < 0.5 else Color("30343b")
	for type in ["Label", "Button", "OptionButton", "CheckButton", "PopupMenu"]:
		theme.set_color("font_color", type, ui_text)
		theme.set_color("font_hover_color", type, ui_text)
		theme.set_color("font_focus_color", type, ui_text)
		theme.set_color("font_pressed_color", type, ui_text)
	for editor in [source_edit, target_edit]:
		editor.add_theme_color_override("font_color", _color("font_color"))
		editor.add_theme_color_override("font_readonly_color", _color("font_color"))
		editor.add_theme_color_override("font_placeholder_color", Color(_color("font_color"), 0.32))
		editor.add_theme_color_override("selection_color", _color("selection_color"))
		editor.add_theme_color_override("caret_color", _color("caret_color"))
		editor.add_theme_color_override("current_line_color", Color(_color("current_line_color"), 0.3))
	target_edit.add_theme_color_override("font_readonly_color", _color("string"))
	divider.color = Color(_color("reserved"), 0.24)
	toast.add_theme_color_override("font_color", _color("function"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = background.lightened(0.035) if background.get_luminance() < 0.5 else background.darkened(0.025)
	panel.border_color = Color(_color("reserved"), 0.35)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(5)
	overlay.add_theme_stylebox_override("panel", panel)
	theme.set_stylebox("panel", "PopupMenu", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		theme.set_stylebox(state, "OptionButton", panel)
	overlay.add_theme_color_override("font_color", _color("font_color"))
	environment.environment.glow_enabled = settings.glow and background.get_luminance() < 0.5

func _color(name: String) -> Color:
	return Color.from_string(str(palette.get(name, "abb2bf")), Color.WHITE)

func _apply_preferences() -> void:
	desired_font_size = float(settings.font_size)
	if settings.music and not music.playing: music.play()
	elif not settings.music: music.stop()
	effect.visible = int(settings.effect) != 0
	if effect.visible:
		var material := ShaderMaterial.new()
		material.shader = CRT if int(settings.effect) == 1 else SUNLIGHT
		effect.material = material
	_apply_theme()

func _toggle_overlay(kind: String) -> void:
	if overlay_kind == kind:
		_close_overlay()
		return
	if overlay_animation: overlay_animation.kill()
	for child in overlay_content.get_children():
		overlay_content.remove_child(child)
		child.queue_free()
	overlay_kind = kind
	overlay_title = Label.new()
	overlay_title.add_theme_font_size_override("font_size", 30)
	overlay_title.add_theme_color_override("font_color", _color("reserved"))
	overlay_content.add_child(overlay_title)
	match kind:
		"languages": _language_panel()
		"themes": _theme_panel()
		"settings": _settings_panel()
		"help": _help_panel()
	var footnote := Label.new()
	footnote.text = "Esc 返回翻译"
	footnote.add_theme_font_size_override("font_size", 16)
	footnote.modulate.a = 0.45
	overlay_content.add_child(footnote)
	shade.show()
	overlay.show()
	source_edit.release_focus()
	target_edit.release_focus()
	call_deferred("_focus_overlay")
	overlay.reset_size()
	_center_overlay()
	call_deferred("_center_overlay")
	overlay.position.x -= 40
	overlay.modulate.a = 0
	canvas.modulate.a = 0.35
	overlay_animation = create_tween().set_parallel(true)
	overlay_animation.tween_property(overlay, "position:x", (size.x - overlay.size.x) / 2, 0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	overlay_animation.tween_property(overlay, "modulate:a", 1.0, 0.2)

func _center_overlay() -> void:
	overlay.custom_minimum_size.x = minf(640, size.x - 60)
	overlay.position = (size - overlay.size) / 2

func _focus_overlay() -> void:
	if overlay_kind.is_empty(): return
	for control in overlay_content.find_children("*", "BaseButton", true, false):
		control.grab_focus()
		return

func _close_overlay() -> void:
	if overlay_kind.is_empty(): return
	if overlay_animation: overlay_animation.kill()
	overlay_kind = ""
	overlay.hide()
	shade.hide()
	canvas.modulate.a = 1.0
	source_edit.grab_focus()
	_save_settings()

func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	overlay_content.add_child(row)
	return row

func _option(row: HBoxContainer, names: Array, selected: int) -> OptionButton:
	var choice := OptionButton.new()
	choice.custom_minimum_size.x = 245
	for item in names: choice.add_item(str(item))
	choice.selected = selected
	row.add_child(choice)
	return choice

func _language_panel() -> void:
	overlay_title.text = "语言 · Ctrl + L"
	for field in ["source", "target"]:
		var names: Array = []
		var selected := 0
		for i in LANGUAGES.size():
			names.append(LANGUAGES[i][1])
			if LANGUAGES[i][0] == settings[field]: selected = i
		var choice := _option(_row("原文" if field == "source" else "译文"), names, selected)
		choice.item_selected.connect(func(index):
			settings[field] = LANGUAGES[index][0]
			revision += 1
			target_edit.modulate.a = 0.42
			_save_settings()
			if settings.auto and not source_edit.text.is_empty(): debounce.start())
	var note := Label.new()
	note.text = "智能方向：中文 → 英文；其他语言 → 中文。\n自动识别适合中、英、日、韩、俄；其他语言请手动选择。"
	note.add_theme_font_size_override("font_size", 16)
	note.modulate.a = 0.6
	overlay_content.add_child(note)

func _theme_panel() -> void:
	overlay_title.text = "主题 · Ctrl + T"
	var choice := _option(_row("GriddyCode 原版主题"), theme_names, maxi(0, theme_names.find(settings.theme)))
	choice.item_selected.connect(func(index):
		settings.theme = theme_names[index]
		_apply_theme()
		_save_settings())
	choice.grab_focus()

func _settings_panel() -> void:
	overlay_title.text = "设置 · Ctrl + ,"
	for pair in [["auto", "停顿后自动翻译"], ["motion", "Griddy 镜头浮动"], ["glow", "Glow 发光"], ["music", "GriddyCode 背景音乐"]]:
		var field: String = pair[0]
		var checkbox := CheckButton.new()
		checkbox.button_pressed = settings[field]
		_row(pair[1]).add_child(checkbox)
		checkbox.toggled.connect(func(value):
			settings[field] = value
			_apply_preferences()
			_save_settings()
			if field == "auto":
				if value and not source_edit.text.is_empty(): debounce.start()
				else: debounce.stop())
	var effects := _option(_row("屏幕效果"), ["关闭", "VHS / CRT", "Sunlight"], int(settings.effect))
	effects.item_selected.connect(func(index):
		settings.effect = index
		_apply_preferences()
		_save_settings())
	var fonts := _option(_row("文字大小"), ["24", "29", "34", "40"], maxi(0, [24, 29, 34, 40].find(int(settings.font_size))))
	fonts.item_selected.connect(func(index):
		settings.font_size = [24, 29, 34, 40][index]
		_apply_preferences()
		_save_settings())

func _help_panel() -> void:
	overlay_title.text = "GriddyTranslate · Ctrl + I"
	for pair in [["Ctrl + Enter", "翻译 / 重试"], ["Ctrl + L", "原文与目标语言"], ["Ctrl + T", "主题"], ["Ctrl + ,", "设置"], ["Ctrl + Shift + C", "复制译文"], ["Ctrl + Shift + X", "交换原文与译文"], ["Ctrl + Tab", "切换原文 / 译文焦点"], ["Ctrl + N", "清空，开始新的翻译"]]:
		var value := Label.new()
		value.text = pair[1]
		_row(pair[0]).add_child(value)
	var note := Label.new()
	note.text = "基于 GriddyCode v1.2.2 修改 · MyMemory 免费在线翻译\n翻译时原文会发送到服务商；免费额度和可用性由服务商决定。\n仅保存主题、语言和设置，不保存翻译正文。"
	note.add_theme_font_size_override("font_size", 15)
	note.modulate.a = 0.55
	overlay_content.add_child(note)

func _notify(message: String, duration: float = 3.0) -> void:
	toast_revision += 1
	var token := toast_revision
	toast.text = message
	toast.modulate.a = 1.0
	await get_tree().create_timer(duration).timeout
	if token == toast_revision: create_tween().tween_property(toast, "modulate:a", 0.0, 0.35)

func _load_settings() -> void:
	if OS.get_cmdline_user_args().has("--test"): return
	var config := ConfigFile.new()
	if config.load("user://translator.cfg") != OK: return
	for key in settings:
		var value = config.get_value("settings", key, settings[key])
		if typeof(value) == typeof(settings[key]): settings[key] = value
	if not int(settings.font_size) in [24, 29, 34, 40]: settings.font_size = 29
	settings.effect = clampi(int(settings.effect), 0, 2)
	var codes: Array = []
	for language in LANGUAGES: codes.append(language[0])
	for field in ["source", "target"]:
		if not settings[field] in codes: settings[field] = "auto"
	if not FileAccess.file_exists("res://Lua/Themes/" + str(settings.theme) + ".lua"): settings.theme = "One Dark Pro Darker"

func _save_settings() -> void:
	if OS.get_cmdline_user_args().has("--test"): return
	var config := ConfigFile.new()
	for key in settings: config.set_value("settings", key, settings[key])
	config.save("user://translator.cfg")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()
		get_tree().quit()
