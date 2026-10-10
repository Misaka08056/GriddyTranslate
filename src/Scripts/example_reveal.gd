extends Control

const GLITCH_GLYPHS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$%&@!?<>░▒▓译码零幻"
var app: Node2D
var final_text := ""
var text := ""
var has_example := false
var revealing := false
var phase := 0
var elapsed := 0.0
var glyph_elapsed := 0.0
var resolved_characters := 0
var revealed_characters := 0
var rng := RandomNumberGenerator.new()
var font: Font
var font_size := 16
var glyph_positions: Array[Vector2] = []
signal reveal_finished

func _ready() -> void:
	app = get_parent()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	hide()
	LuaSingleton.on_theme_load.connect(refresh_style)

func show_example(english: String, chinese: String) -> void:
	final_text = english + "\n" + chinese
	text = ""
	elapsed = 0.0
	glyph_elapsed = 0.0
	phase = 0
	resolved_characters = 0
	revealed_characters = 0
	has_example = true
	revealing = true
	refresh_style()
	show()

func cancel() -> void:
	has_example = false
	revealing = false
	final_text = ""
	text = ""
	hide()

func refresh_style() -> void:
	if not has_example: return
	font = app.Code.get_theme_font("font")
	var base_zoom: float = app.get_node("Misc/Cam").content_base_zoom()
	var viewport_size := get_viewport_rect().size
	var logical_width := 1080.0 * viewport_size.x / maxf(viewport_size.y, 1.0)
	# Geometry stays in CodeEdit's world canvas, sharing its camera transforms.
	scale = Vector2.ONE * 2.0 / base_zoom
	size = Vector2(logical_width * 0.70 / 2.0, 160.0)
	var caret: Vector2 = app.Code.get_caret_draw_pos()
	var remaining_lines: int = app.Code.get_line_count() - 1 - app.Code.get_caret_line()
	for line in range(app.Code.get_caret_line(), app.Code.get_line_count()):
		remaining_lines += app.Code.get_line_wrap_count(line)
	remaining_lines -= app.Code.get_caret_wrap_index()
	position = app.Code.position + caret + Vector2(-logical_width * 0.36 / base_zoom, (remaining_lines + 1.4) * app.Code.get_line_height())
	if app.Code.has_wrapped_content():
		position.x = app.Code.position.x + app.Code.size.x * 0.5 - logical_width * 0.36 / base_zoom
	layout_glyphs()
	queue_redraw()

func layout_glyphs() -> void:
	glyph_positions.clear()
	var pen := Vector2(0, font.get_ascent(font_size))
	var line_height := font.get_height(font_size) + 4.0
	for index in final_text.length():
		var character := final_text.substr(index, 1)
		if character == "\n":
			glyph_positions.append(pen)
			pen = Vector2(0, pen.y + line_height)
			continue
		if character.unicode_at(0) < 128 and character != " " and (index == 0 or final_text.substr(index - 1, 1) in [" ", "\n"]):
			var end := index
			while end < final_text.length() and not final_text.substr(end, 1) in [" ", "\n"]: end += 1
			var word_width := font.get_string_size(final_text.substr(index, end - index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if pen.x > 0 and pen.x + word_width > size.x: pen = Vector2(0, pen.y + line_height)
		var width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if pen.x + width > size.x: pen = Vector2(0, pen.y + line_height)
		glyph_positions.append(pen)
		pen.x += width

func _draw() -> void:
	if not has_example or font == null: return
	for index in mini(text.length(), glyph_positions.size()):
		var character := text.substr(index, 1)
		if character in [" ", "\n", "\t"]: continue
		var character_width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var final_width := font.get_string_size(final_text.substr(index, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var draw_position := glyph_positions[index] + Vector2((final_width - character_width) * 0.5, 0)
		draw_string(font, draw_position, character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LuaSingleton.gui.font_color)

func _process(delta: float) -> void:
	if not has_example: return
	visible = app.showing_translation and app.examples_enabled and not app.Code._show
	if not visible or not revealing: return
	elapsed += delta
	glyph_elapsed += delta
	if glyph_elapsed < 0.045: return
	glyph_elapsed = 0.0
	var length := final_text.length()
	if phase == 0:
		revealed_characters = mini(length, int(elapsed / 0.9 * length))
		text = scramble(revealed_characters, 0)
		if elapsed >= 0.9:
			phase = 1
			elapsed = 0.0
	else:
		resolved_characters = mini(length, int(elapsed / 1.8 * length))
		text = scramble(length, resolved_characters)
		if elapsed >= 1.8:
			text = final_text
			revealing = false
			phase = 2
			reveal_finished.emit()
	queue_redraw()

func scramble(length: int, settled: int) -> String:
	var value := ""
	for index in length:
		var character := final_text.substr(index, 1)
		if index < settled or character in [" ", "\n", "\t"]:
			value += character
		else:
			value += GLITCH_GLYPHS.substr(rng.randi_range(0, GLITCH_GLYPHS.length() - 1), 1)
	return value
