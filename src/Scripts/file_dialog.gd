class_name FileDialogType
extends RichTextLabel

@onready var editor: FileManager = $".."
var active := false:
	set(value):
		active = value
		if value and is_instance_valid(editor):
			column = 0
			staged_source = editor.source_language
			staged_target = editor.target_language
			selected_index = language_index(staged_source)
			update_ui()
var selected_index := 0
var column := 0
var zoom := Vector2(1.4, 1.4)
var staged_source := "auto"
var staged_target := "auto"
signal ui_close

func _ready() -> void:
	get_viewport().size_changed.connect(refocus_after_resize)

func setup() -> void: update_ui()

func content_size() -> Vector2:
	var font: Font = get_theme_font("normal_font")
	var font_size: int = get_theme_font_size("normal_font_size")
	var width := 0.0
	for line in get_parsed_text().split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return Vector2(width + 16.0, get_content_height() + 10.0)

func focus_position(future_position: Vector2) -> Vector2:
	var bounds := content_size()
	var viewport_size := get_viewport_rect().size
	var fit_zoom := minf(1.4, minf(viewport_size.x * 0.80 / bounds.x, viewport_size.y * 0.78 / bounds.y))
	zoom = Vector2.ONE * fit_zoom
	return future_position + bounds * 0.5

func refocus_after_resize() -> void:
	if not active: return
	if editor.Code.node_is_transitioning:
		await get_tree().create_timer(editor.Code.panel_duration() + 0.03).timeout
	if active: editor.get_node("Misc/Cam").focus_on(focus_position(global_position), zoom)

func language_index(language: String) -> int:
	for index in editor.LANGUAGES.size():
		if editor.LANGUAGES[index][0] == language: return index
	return 0

func _input(event: InputEvent) -> void:
	if not active or not event is InputEventKey or not event.pressed: return
	if event.ctrl_pressed or event.meta_pressed: return
	match event.keycode:
		KEY_UP: selected_index = maxi(0, selected_index - 1)
		KEY_DOWN: selected_index = mini(editor.LANGUAGES.size() - 1, selected_index + 1)
		KEY_LEFT:
			column = 0
			selected_index = language_index(staged_source)
		KEY_RIGHT, KEY_TAB:
			column = 1 - column
			selected_index = language_index(staged_source if column == 0 else staged_target)
		KEY_ENTER:
			if column == 0:
				staged_source = editor.LANGUAGES[selected_index][0]
				column = 1
				selected_index = language_index(staged_target)
			else:
				staged_target = editor.LANGUAGES[selected_index][0]
				editor.source_language = staged_source
				editor.target_language = staged_target
				editor.revision += 1
				editor._save_preferences()
				ui_close.emit()
		_ : return
	update_ui()
	get_viewport().set_input_as_handled()

func update_ui() -> void:
	clear()
	push_color(LuaSingleton.gui.font_color)
	add_text("Languages / 语言\n\n")
	add_text(("[Original]" if column == 0 else "Original") + "  →  " + ("[Translation]" if column == 1 else "Translation") + "\n")
	add_text(staged_source + "  →  " + staged_target + "\n\n")
	for index in editor.LANGUAGES.size():
		if index == selected_index: push_bgcolor(LuaSingleton.gui.selection_color)
		add_text(("› " if index == selected_index else "  ") + editor.LANGUAGES[index][1] + "\n")
		if index == selected_index: pop()
	add_text("\n↑ ↓ select · Enter confirm · ← → direction\nEsc return")
	pop()
	size = content_size()
