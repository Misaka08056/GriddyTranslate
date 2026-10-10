extends CodeEdit

@onready var code: CodeEdit = %Code
@onready var editor: FileManager = $".."

const VARIABLE = preload("res://Icons/variable.png")
const FUNCTION = preload("res://Icons/function.png")

@onready var rich_text_labels: Array[RichTextLabel] = [
	%FileDialog,
];

var file_modified = false;

var _show = false;
var active_overlay: Variant;
var node_is_transitioning: bool;
var animation_speed := 1.0
var _visual_longest_line := ""
var _line_cache_dirty := true
var _has_wrapped_lines := false

func panel_duration() -> float:
	return 0.2 / animation_speed

func _ready() -> void:
	grab_focus()

	LuaSingleton.on_theme_load.connect(setup_theme)

	tween_fade(%FileDialog, 0)
	tween_fade(%Settings, 0)

	setup_theme()
	resized.connect(_invalidate_line_cache)

func setup_theme() -> void:
	code.begin_bulk_theme_override()
	setup_highlighter()

	%Background.color = LuaSingleton.gui.background_color;
	%ExternalBackground.color = LuaSingleton.gui.background_color;

	code.add_theme_color_override("background_color", LuaSingleton.gui.background_color)
	var line_color := LuaSingleton.readable_highlight(LuaSingleton.gui.current_line_color)
	var line_background: Color = LuaSingleton.gui.background_color.blend(line_color)
	var selection_color := LuaSingleton.readable_highlight(LuaSingleton.gui.selection_color, line_background)
	code.add_theme_color_override("current_line_color", line_color)
	code.add_theme_color_override("selection_color", selection_color)
	code.add_theme_color_override("font_color", LuaSingleton.gui.font_color)
	code.add_theme_color_override("font_selected_color", LuaSingleton.gui.font_color)
	code.add_theme_color_override("font_readonly_color", LuaSingleton.gui.font_color)
	code.add_theme_color_override("word_highlighted_color", LuaSingleton.readable_highlight(LuaSingleton.gui.word_highlighted_color, line_background.blend(selection_color)))
	code.add_theme_color_override("completion_background_color", LuaSingleton.gui.completion_background_color)
	code.add_theme_color_override("completion_selected_color", LuaSingleton.gui.completion_selected_color)
	code.add_theme_color_override("caret_color", LuaSingleton.gui.caret_color)
	code.end_bulk_theme_override()
	refresh_wrapping()

	for label in rich_text_labels:
		label.add_theme_color_override("default_color", LuaSingleton.gui.font_color)

func setup_highlighter() -> void:
	var CH: CodeHighlighter = CodeHighlighter.new();

	syntax_highlighter = CH;

	CH.number_color = LuaSingleton.keywords.binary;
	CH.symbol_color = LuaSingleton.keywords.symbol;
	CH.function_color = LuaSingleton.keywords.function;
	CH.member_variable_color = LuaSingleton.keywords.member;

	# i dont remember why this was here, but the code works without it now
	#await LuaSingleton.done_parsing;

	var kth = LuaSingleton.keywords_to_highlight;
	var crth = LuaSingleton.color_regions_to_highlight;

	for key in kth:
		CH.add_keyword_color(key, LuaSingleton.keywords[kth[key]])

	for entry in crth:
		if CH.has_color_region(entry[0]): continue

		CH.add_color_region(entry[0], entry[1], LuaSingleton.keywords[entry[2]], entry[3])

# CodeEdit functionality
func _on_code_completion_requested() -> void:
	var function_names = LuaSingleton.lua.call_function("detect_functions", [text, get_caret_line(), get_caret_column()])
	var variable_names = LuaSingleton.lua.call_function("detect_variables", [text, get_caret_line(), get_caret_column()])

	if typeof(function_names) == Variant.Type.TYPE_ARRAY:
		for each in unique_array(function_names):
			add_code_completion_option(CodeEdit.KIND_FUNCTION, each, each+"()", LuaSingleton.keywords.function, FUNCTION)
	if typeof(variable_names) == Variant.Type.TYPE_ARRAY:
		for each in unique_array(variable_names):
			add_code_completion_option(CodeEdit.KIND_VARIABLE, each, each, LuaSingleton.keywords.variable, VARIABLE)

	update_code_completion_options(true)

func unique_array(arr: Array) -> Array:
	var out := {}
	for element in arr:
		out[element] = element
	return out.values()

func _on_text_changed() -> void:
	file_modified = true;
	_line_cache_dirty = true
	editor.on_source_changed()

# UI animations
func toggle(node: Object, apply_background: bool = true, factor: float = (18 * 7.5)) -> void:
	# fuck me
	# _show is a boolean to show the editor
	# _show is NOT a boolean to show the overlay

	# i dont know what the fuck is happening here, but ill try explaining it
	if active_overlay != node and active_overlay != null: return # we already have an overlay active, and this function call isn't from it trying to hide, so fuck off
	if active_overlay == node && !_show: return # if the active overlay is the node trying to toggle, and it wants to show even tho it's already shown, it shall fuck off
	if node_is_transitioning: return # node is already trying to go, stop spamming the keys; DO NOT FUCKING REMOVE.
	if node == %Settings:
		%SettingsList.release_slider_interactions()
		%SettingsList.set_sliders_interactive(false)

	var opacity = 0 if _show else 1;

	tween_fade(node, opacity)

	var future_pos = slide_from_left(node, opacity, factor)

	if node.has_method("focus_position") and "active" in node:
		node.active = !_show;

		if _show && !editor.current_file:
			editor.warn("[color=yellow]WARNING[/color]: You are currently in an empty file. No autosave will be performed.")

	if apply_background:
		tween_fade(%Background, opacity, !_show)
	elif not apply_background and !_show:
		node.grab_focus()

	if _show:
		%Cam.focus_die()
		if !node is FileDialogType:
			code.grab_focus()
	else:
		var focus_zoom: Vector2 = node.zoom if ("zoom" in node) else Vector2.ONE
		if node.name == "Info":
			future_pos.x += 700
			future_pos.y += 500
		if node.name == "Settings":
			var bounds := Vector2(650, maxf(maxf(%SettingsList.size.y, LuaSingleton.settings.size() * 30.0) + 28, 600))
			future_pos += %SettingsList.position + bounds * 0.5
			var viewport_size := get_viewport_rect().size
			focus_zoom = Vector2.ONE * minf(1.0, minf(viewport_size.x * 0.86 / bounds.x, viewport_size.y * 0.86 / bounds.y))
		if node.name == "Comments":
			future_pos.x += 200
			future_pos.y += 300
		if node.has_method("focus_position"):
			future_pos = node.focus_position(future_pos)

		%Cam.focus_on(future_pos, node.zoom if ("zoom" in node) else focus_zoom)
		code.release_focus()

	_show = !_show;

func tween_fade(node: Object, opacity: float, ignore_gui: bool = false) -> void:
	var tween = create_tween()
	var color = node.modulate;

	if opacity == 1:
		node.show()

	color.a = opacity

	tween.tween_property(node, "modulate", color, panel_duration())

	tween.tween_callback(func() -> void:
		if opacity == 0:
			node.hide()

			if !ignore_gui: active_overlay = null;
			if node is CommentsOverlay:
				node.container.setup()

		else:
			node.show()
			if !ignore_gui: active_overlay = node;
	)

func slide_from_left(node: Object, __show: bool, factor: float) -> Vector2:
	node_is_transitioning = true;

	var tween = create_tween()
	var pos = node.global_position;

	var future_pos = Vector2(pos.x + factor, pos.y) if __show else Vector2(pos.x - factor, pos.y)

	tween.tween_property(node, "position", future_pos, panel_duration())
	tween.tween_callback(func() -> void:
		node_is_transitioning = false;
		if node == %Settings and __show:
			%SettingsList.set_sliders_interactive(true)
	)

	return future_pos

func _on_file_dialog_ui_close():
	toggle(%FileDialog)
	get_tree().create_timer(panel_duration() + 0.03).timeout.connect(editor.restore_input_focus)


# MISC

func get_longest_line(lines: Array = []) -> String:
	if wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY:
		if _line_cache_dirty:
			_visual_longest_line = ""
			_has_wrapped_lines = false
			for line in get_line_count():
				var visual_lines := get_line_wrapped_text(line)
				_has_wrapped_lines = _has_wrapped_lines or visual_lines.size() > 1
				for visual_line in visual_lines:
					if visual_line.length() > _visual_longest_line.length(): _visual_longest_line = visual_line
			_line_cache_dirty = false
		return _visual_longest_line
	if lines.is_empty(): lines = Array(text.split("\n"))
	var longestLine := ""

	for line in lines:
		if line.length() > longestLine.length():
			longestLine = line

	return longestLine

func has_wrapped_content() -> bool:
	if wrap_mode != TextEdit.LINE_WRAPPING_BOUNDARY: return false
	get_longest_line()
	return _has_wrapped_lines

func _invalidate_line_cache() -> void:
	_line_cache_dirty = true

func refresh_wrapping() -> void:
	var enabled: bool = LuaSingleton.get_setting("auto_wrap")[0].get("value", false)
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if enabled else TextEdit.LINE_WRAPPING_NONE
	if enabled:
		var columns: int = int(LuaSingleton.get_setting("wrap_characters")[0].get("value", 40))
		var font: Font = get_theme_font("font")
		var font_size: int = get_theme_font_size("font_size")
		var margins: float = get_theme_stylebox("normal").get_minimum_size().x
		# Soft wrapping keeps the complete original text, selection, undo history
		# and dictionary phrase queries intact. A Chinese glyph spans ~2 columns.
		size.x = maxf(48.0, font.get_string_size("0".repeat(columns), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + margins + 16.0)
	else:
		size.x = 2044.0
	_line_cache_dirty = true
	if is_instance_valid(editor.example_label): editor.example_label.refresh_style()

func _process(_event):
	# Shortcut dispatch is centralized in FileManager.
	pass

func _on_gui_input(_event):
	# Shortcut dispatch is centralized in FileManager; original animations above are unchanged.
	pass

func _on_caret_changed() -> void:
	pass
