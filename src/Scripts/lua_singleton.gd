extends Node

const NOTO_COLOR_EMOJI_REGULAR: FontFile = preload("res://Fonts/NotoColorEmoji-Regular.ttf")
const SYMBOLS_NERD_FONT: FontFile = preload("res://Fonts/SymbolsNerdFont-Regular.ttf")

var themes: Array = Array(DirAccess.get_files_at("res://Lua/Themes")).filter(func(file): return file.ends_with(".lua")).map(func(file): return file.trim_suffix(".lua"));
var theme: String = "One Dark Pro Darker"; # default

# TODO: change me each version
var version: String = "v1.2.2";

var gui: Dictionary = {
	"background_color":            str_to_clr("#23272e"),
	"current_line_color":          str_to_clr("#23272e"),
	"selection_color":             str_to_clr("#23272e"),
	"font_color":                  str_to_clr("#23272e"),
	"word_highlighted_color":      str_to_clr("#23272e"),
	"completion_background_color": str_to_clr("#23272e"),
	"completion_selected_color":   str_to_clr("#23272e"),
	"caret_color":                 str_to_clr("#23272e")
}

# #### SETTINGS ####
# # Info:
# Property = identifier
# Display = the setting name to display.
# Options = dropdown options. Leave empty for no dropdown.
# Icon = nerdfont unicode for the icon
# Value = initial value. Reminder this gets overwritten by the save file.
# Unit = the unit to display after the slider.
# Min = the minimum slider value.
# Max = the maximum slider value.
# Precision = whether or not the slider should go from int to float.
# Shader = whether or not to disable the previously-enabled shader setting, as they can't be stacked.

var editor_theme: Theme = load("res://theme.tres");
var fonts = load_available_fonts()
var _prepared_fonts: Dictionary = {}


func load_available_fonts() -> Array:
	var built_ins = load_built_in_fonts()
	var system = load_system_fonts()
	built_ins.append_array(system)
	return built_ins


func load_built_in_fonts() -> Array:
	return Array(editor_theme.get_font_list("MyType")).map(load_built_in_font)


func load_built_in_font(_name: String) -> Dictionary:
	var font = editor_theme.get_font(_name, "MyType");

	return { "display": font.get_font_name(), "value": font, "name": _name }


func load_system_font(font_name: String):
	var font: SystemFont = SystemFont.new()
	font.multichannel_signed_distance_field = true
	font.font_names = [font_name]

	return { "display": font.get_font_name(), "value": font, "name": font_name }


func load_system_fonts() -> Array:
	# Listing names is cheap; resolving every family opens hundreds of font
	# files before the first frame. Resolve only the font the user selects.
	var catalog: Array = []
	for font_name in OS.get_system_fonts():
		catalog.append({"display": font_name, "value": null, "name": font_name})
	return catalog

func selected_font(index: int) -> Font:
	if fonts[index].value == null:
		fonts[index].value = load_system_font(fonts[index].name).value
	return fonts[index].value


var settings: Array = [
	{
		"property": "caret_type",
		"display": "Caret type",
		"options": [{"display": "Line", "value": 0}, {"display": "Block", "value": 1}],
		"icon": "",
		"value": CodeEdit.CARET_TYPE_LINE,
	},
	{
		"property": "caret_blink",
		"display": "Caret Blink / 光标闪烁",
		"options": [],
		"icon": "|",
		"value": true
	},
	{
		"property": "editor_font",
		"display": "Editor Font",
		"options": fonts,
		"icon": "",
		"value": 0
	},
	{
		"property": "caret_interval",
		"display": "Blink Interval / 闪烁间隔",
		"options": [],
		"icon": "",
		"value": 0.6,
		"unit": "sec.",
		"min": 0.1, "max": 3,
		"precision": true,
	},
	{
		"property": "draw_line_numbers",
		"display": "Draw Line Number",
		"options": [],
		"icon": "",
		"value": true
	},
	{
		"property": "code_completion",
		"display": "Code Completion",
		"options": [],
		"icon": "",
		"value": true
	},
	{
		"property": "indentation_size",
		"display": "Indentation Size",
		"options": [],
		"icon": "󰌒",
		"value": 4,
		"unit": "tabs",
		"min": 1, "max": 8,
	},
	{
		"property": "indentation_automatic",
		"display": "Automatic Indentation",
		"options": [],
		"icon": "󰁨",
		"value": true
	},
	{
		"property": "indentation_use_spaces",
		"display": "Indentation: use spaces",
		"options": [],
		"icon": "󱁐",
		"value": false
	},
	{
		"property": "auto_brace_completion",
		"display": "Auto Brace Completion",
		"options": [],
		"icon": "󰅩",
		"value": true
	},
	{
		"property": "auto_brace_highlight_matching",
		"display": "Highlight Matching Braces",
		"options": [],
		"icon": "󱃖",
		"value": true
	},
	{
		"property": "smooth_scrolling",
		"display": "Smooth Scrolling",
		"options": [],
		"icon": "󱕒",
		"value": true
	},
	{
		"property": "v_scroll_speed",
		"display": "Scrolling Speed",
		"options": [],
		"icon": "",
		"value": 150,
		"unit": "px/s",
		"min": 10, "max": 900,
	},
	{
		"property": "minimap",
		"display": "Minimap",
		"options": [],
		"icon": "󰍍",
		"value": true
	},
	{
		"property": "minimap_width",
		"display": "Minimap Width",
		"options": [],
		"icon": "",
		"value": 80,
		"unit": "px",
		"min": 20, "max": 500,
	},
	{
		"property": "glow",
		"display": "Glow",
		"options": [],
		"icon": "󰌶",
		"value": true,
	},
	{
		"property": "sunlight",
		"display": "Shader: Sunlight",
		"options": [],
		"icon": "",
		"value": false,
		"shader": true
	},
	{
		"property": "vhs",
		"display": "Shader: VHS and CRT",
		"options": [],
		"icon": "",
		"value": false,
		"shader": true
	},
	{
		"property": "music",
		"display": "Music",
		"options": [],
		"icon": "󰝚",
		"value": false,
	},
	{
		"property": "music_volume",
		"display": "Music: Volume",
		"options": [],
		"icon": "",
		"value": 100,
		"unit": "%",
		"min": 0, "max": 100,
	},
	{
		"property": "discord_sdk",
		"display": "Discord SDK",
		"options": [],
		"icon": "󰙯",
		"value": true,
	},
];

var keywords: Dictionary = {
	"reserved":   str_to_clr("c678cc"),
	"annotation": str_to_clr("a2b429"),
	"string":     str_to_clr("98c379"),
	"binary":     str_to_clr("d19a66"),
	"symbol":     str_to_clr("839fb6"),
	"variable":   str_to_clr("e5c07b"),
	"operator":   str_to_clr("56b6c2"),
	"comments":   str_to_clr("7f848e"),
	"error":      str_to_clr("d31820"),
	"function":   str_to_clr("437ed9"),
	"member":     str_to_clr("e06c75")
}

var keywords_to_highlight: Dictionary = {}
var color_regions_to_highlight: Array = []
var comments: Array = []

var discord_sdk: bool = false;

const SUNLIGHT = preload("res://Shaders/sunlight.gdshader")
const VHS_AND_CRT = preload("res://Shaders/vhs_and_crt.gdshader")

var editor: FileManager:
	get: return get_node_or_null("/root/Editor")
var code: CodeEdit:
	get: return get_node_or_null("/root/Editor/Code")
var world_environment: WorldEnvironment:
	get: return get_node_or_null("/root/Editor/WorldEnvironment")
var shader_layer: ColorRect:
	get: return get_node_or_null("/root/Editor/ShaderLayer")





signal done_parsing;
signal on_theme_load;
signal on_settings_change;




func get_setting(property: String) -> Array:
	var i = -1;

	for setting in settings:
		i += 1;

		if setting["property"] == property:
			return [setting, i]

	return [{}, -1]

func change_setting(property: String, value: Variant) -> void:
	for setting in settings:
		if setting["property"] == property:
			if setting.value is int and setting.options.is_empty(): value = int(value)
			setting["value"] = value
			handle_internal_setting_change(property, value)
			if setting.get("shader", false): on_settings_change.emit()
			return

func toggle_shader(shader: Shader, value: bool) -> void:
	if value:
		shader_layer.show()
		shader_layer.material.shader = shader
	elif shader_layer.material.shader == shader:
		shader_layer.material.shader = null
		shader_layer.hide()



func handle_internal_setting_change(property: String, value: Variant) -> void:
	# oh my god he's about to do it
	var p = property;

	if p == "caret_type":
		code.caret_type = value
	if p == "caret_blink":
		code.caret_blink = value
	if p == "caret_interval":
		code.caret_blink_interval = value;
	if p == "draw_line_numbers":
		code.gutters_draw_line_numbers = value;
	if p == "code_completion":
		code.code_completion_enabled = value
	if p == "indentation_size":
		code.indent_size = value
	if p == "indentation_automatic":
		code.indent_automatic = value
	if p == "indentation_use_spaces":
		code.indent_use_spaces = value
	if p == "auto_brace_completion":
		code.auto_brace_completion_enabled = value
	if p == "auto_brace_highlight_matching":
		code.auto_brace_completion_highlight_matching = value
	if p == "smooth_scrolling":
		code.scroll_smooth = value
	if p == "v_scroll_speed":
		code.scroll_v_scroll_speed = value
	if p == "minimap":
		code.minimap_draw = value
	if p == "minimap_width":
		code.minimap_width = value
	if p == "editor_font":
		if value < 0 or value >= fonts.size(): return
		var selected_font: Font = prepare_font(selected_font(value))
		editor_theme.set_font("normal_font", "RichTextLabel", selected_font)
		editor_theme.set_font("font", "Label", selected_font)
		editor_theme.set_font("font", "CodeEdit", selected_font)
		editor_theme.set_font("font", "Button", selected_font)
		code.refresh_wrapping()
		if is_instance_valid(editor.example_label): editor.example_label.refresh_style()

	if p == "translation_auto":
		editor.auto_translate = value
		editor.on_auto_translation_changed()
	if p == "display_examples":
		editor.examples_enabled = value
		editor.on_examples_changed()
	if p == "translation_provider":
		editor.on_provider_changed(value)
	if p == "translation_placement":
		editor.on_translation_placement_changed(value)
	if p in ["auto_wrap", "wrap_characters"]:
		code.refresh_wrapping()
	if p == "obsidian_sync" and is_instance_valid(editor.wordbook):
		editor.wordbook.set_sync_enabled(value)
	if p == "screen_motion":
		editor.get_node("Misc/Cam").set_motion_enabled(value)
	if p == "settings_animation_speed":
		code.animation_speed = float(value) / 100.0
		editor.get_node("Misc/Cam").transition_speed = 1.0 / code.animation_speed
	if p == "view_zoom":
		editor.get_node("Misc/Cam").user_zoom = float(value) / 100.0
	if p == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(get_setting("borderless")[0].value))
	if p == "borderless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(value))
	# SHADERS
	if p == "glow":
		world_environment.environment.glow_enabled = value
	if p == "sunlight":
		if value: get_setting("vhs")[0].value = false
		toggle_shader(SUNLIGHT, value)
	if p == "vhs":
		if value: get_setting("sunlight")[0].value = false
		toggle_shader(VHS_AND_CRT, value)
	# MUSIC
	if p == "music":
		Music.set_enabled(value)
	if p == "music_volume":
		Music.set_volume(value)
	if p == "discord_sdk":
		discord_sdk = value;


func prepare_font(original: Font) -> Font:
	var key := original.get_instance_id()
	if _prepared_fonts.has(key):
		var cached: Font = _prepared_fonts[key].get_ref()
		if cached != null: return cached
	var result: Font = original.duplicate()
	var cjk := SystemFont.new()
	cjk.multichannel_signed_distance_field = true
	cjk.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	result.set_fallbacks([NOTO_COLOR_EMOJI_REGULAR, SYMBOLS_NERD_FONT, cjk])
	_prepared_fonts[key] = weakref(result)
	return result

func readable_highlight(color: Color, beneath: Color = Color.TRANSPARENT) -> Color:
	# Some upstream themes use their text color as an opaque occurrence fill.
	# Preserve valid palettes, but soften fills that would erase the glyphs.
	if beneath.a == 0.0: beneath = gui.background_color
	if _text_contrast(beneath.blend(color)) < 3.0:
		color.a = minf(color.a, 0.18)
		for step in 6:
			if _text_contrast(beneath.blend(color)) >= 3.0: break
			color.a *= 0.5
	return color

func _text_contrast(background: Color) -> float:
	var foreground: Color = gui.font_color.srgb_to_linear()
	var fill := background.srgb_to_linear()
	var text_light := foreground.r * 0.2126 + foreground.g * 0.7152 + foreground.b * 0.0722
	var fill_light := fill.r * 0.2126 + fill.g * 0.7152 + fill.b * 0.0722
	return (maxf(text_light, fill_light) + 0.05) / (minf(text_light, fill_light) + 0.05)

func configure_translator_settings(default_font: Font) -> void:
	# The original canvas uses Godot's default font until a font is chosen.
	# Represent that actual default in the existing dropdown and preserve it on restart.
	fonts.push_front({"display": "GriddyCode Default", "value": default_font.duplicate(), "name": "griddycode-default"})
	var preserved: Array = []
	for setting in settings:
		if setting.property in ["caret_type", "caret_blink", "editor_font", "caret_interval", "smooth_scrolling", "v_scroll_speed", "glow", "sunlight", "vhs", "music", "music_volume"]:
			preserved.append(setting)
	settings = preserved
	settings.append({"property": "translation_auto", "display": "Auto Translation", "icon": "󰗊", "value": false, "options": []})
	settings.append({"property": "display_examples", "display": "Show Examples / 显示例句", "icon": "󰉿", "value": true, "options": []})
	settings.append({"property": "translation_provider", "display": "Translation Source / 翻译来源", "icon": "󰗊", "value": 1, "options": [{"display": "MyMemory / 免密钥", "value": "mymemory"}, {"display": "有道 / 免密钥体验", "value": "youdao"}]})
	settings.append({"property": "translation_placement", "display": "译文位置 / Translation Layout", "icon": "󰉿", "value": 0, "options": [{"display": "替换原文", "value": 0}, {"display": "保留原文 · 下一行译文", "value": 1}]})
	settings.append({"property": "auto_wrap", "display": "自动换行 / Auto Wrap", "icon": "󰌑", "value": true, "options": []})
	settings.append({"property": "wrap_characters", "display": "每行长度 / Wrap Length", "icon": "󰘖", "value": 40, "min": 10, "max": 120, "unit": "字符宽", "options": []})
	settings.append({"property": "startup_animation", "display": "开屏动画 / Startup Animation", "icon": "󰕧", "value": true, "options": []})
	settings.append({"property": "screen_motion", "display": "屏幕晃动 / Screen Motion", "icon": "󰁨", "value": true, "options": []})
	settings.append({"property": "settings_animation_speed", "display": "设置动画速度 / Animation Speed", "icon": "󱕒", "value": 100, "min": 25, "max": 300, "unit": "%", "options": []})
	settings.append({"property": "view_zoom", "display": "缩放比例 / Zoom", "icon": "", "value": 100, "min": 50, "max": 200, "unit": "%", "options": []})
	settings.append({"property": "fullscreen", "display": "全屏 / Fullscreen · F11", "icon": "󰊓", "value": false, "options": []})
	settings.append({"property": "borderless", "display": "无边框 / Borderless", "icon": "󰊓", "value": false, "options": []})
	settings.append({"property": "obsidian_sync", "display": "Obsidian 自动同步", "icon": "󰘓", "value": true, "options": []})
	settings.append({"property": "obsidian_vault", "display": "Obsidian 保管库", "icon": "󰉋", "value": "选择保管库…", "options": [], "action": true})
	settings.append({"property": "obsidian_folder", "display": "单词本同步文件夹", "icon": "󰉋", "value": "GriddyTranslate/单词本", "options": [], "action": true})
	settings.append({"property": "obsidian_sync_now", "display": "Obsidian 立即同步", "icon": "󰘓", "value": "同步", "options": [], "action": true})

func setup_discord_sdk(_detail: String, _state: String) -> void:
	pass

# LUA
var lua: LuaAPI = LuaAPI.new()
var theme_lua: LuaAPI = LuaAPI.new()
var _theme_bindings_ready := false
var _loaded_theme := ""
var _loaded_theme_modified := -1

func str_to_clr(string: String) -> Color:
	return Color.from_string(string, "#ff0000");


func _lua_highlight(keyword: String, color: String):
	if !(color in keywords.keys()):
		print("ERROR: provided color property (\"%s\") at \"%s\" is invalid." % [color, keyword])
		return

	keywords_to_highlight[keyword] = color;

func _lua_highlight_region(start: String, end: String, color: String, line_only: bool = false):
	if !(color in keywords.keys()):
		print("ERROR: provided color (\"%s\") at color region (start: \"%s\", end: \"%s\") is invalid." % [color, start, end])
		return

	color_regions_to_highlight.append([start, end, color, line_only])

func _lua_set_keywords(property: String, new_color: String) -> void:
	if !(property in keywords.keys()):
		print("ERROR: provided color property (\"%s\") in theme (KEYWORD) is invalid." % [property])
		return

	keywords[property] = str_to_clr(new_color)

func _lua_disable_glow() -> void:
	editor.warn("[color=yellow]WARNING[/color]: This theme disabled the \"glow\".")
	handle_internal_setting_change("glow", false)

func _lua_set_gui(property: String, new_color: String) -> void:
	if !(property in gui.keys()):
		print("ERROR: provided color property (\"%s\") in theme (GUI) is invalid." % [property])
		return

	gui[property] = str_to_clr(new_color)

func _add_comment(comment: String) -> void:
	comments.append(comment)

func _splitstr(input: String, separator: String):
	return input.split(separator)

func _trim(input: String):
	return input.strip_edges()

func setup_extension(extension):
	# FILE EXTENSIONS
	lua.bind_libraries(["base", "table", "string"])

	lua.push_variant("highlight", _lua_highlight)
	lua.push_variant("highlight_region", _lua_highlight_region)
	lua.push_variant("add_comment", _add_comment)

	lua.push_variant("splitstr", _splitstr)
	lua.push_variant("trim", _trim)

	var err: LuaError = lua.do_file("user://langs/" + extension + ".lua")
	if err is LuaError:
		editor.warn("[color=yellow]WARNING[/color]: This file isn’t supported. Highlighting, autocomplete, comments and other features won’t work properly.")
		print("ERROR %d: %s" % [err.type, err.message])
		return

	done_parsing.emit()

func setup_theme(given_theme: String) -> void:
	var path := "user://themes/" + given_theme + ".lua"
	var modified := FileAccess.get_modified_time(path)
	if _loaded_theme == given_theme and _loaded_theme_modified == modified: return
	if not _theme_bindings_ready:
		theme_lua.bind_libraries(["base", "table", "string"])
		theme_lua.push_variant("disable_glow", _lua_disable_glow)
		theme_lua.push_variant("set_keywords", _lua_set_keywords)
		theme_lua.push_variant("set_gui", _lua_set_gui)
		_theme_bindings_ready = true
	var theme_err: LuaError = theme_lua.do_file(path)
	if theme_err is LuaError:
		editor.warn("[color=yellow]WARNING[/color]: Failed to load theme: " + theme_err.message)
		print("ERROR %d: %s" % [theme_err.type, theme_err.message])
		return
	_loaded_theme = given_theme
	_loaded_theme_modified = modified
	on_theme_load.emit()
