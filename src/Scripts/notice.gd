extends Control

const ENTER_TIME := 0.32
const EXIT_TIME := 0.24
const HOLD_TIME := 5.0
@onready var rich_text_label: RichTextLabel = $RichTextLabel
var _frame := StyleBoxFlat.new()
var _accent := StyleBoxFlat.new()
var _animation: Tween
var _lifetime: Timer
var _closing := false
var _presented := false
var _layout_revision := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_frame.set_border_width_all(0)
	_frame.set_corner_radius_all(0)
	_frame.anti_aliasing = false
	_accent.set_corner_radius_all(0)
	_accent.anti_aliasing = false
	rich_text_label.theme = LuaSingleton.editor_theme
	rich_text_label.add_theme_font_size_override("normal_font_size", 24)
	_lifetime = Timer.new()
	_lifetime.one_shot = true
	_lifetime.timeout.connect(dismiss)
	add_child(_lifetime)
	LuaSingleton.on_theme_load.connect(_refresh_style)
	LuaSingleton.on_settings_change.connect(_refresh_style)
	get_viewport().size_changed.connect(_layout_notice)
	_refresh_style()

func _refresh_style() -> void:
	var background: Color = LuaSingleton.gui.background_color
	_frame.bg_color = LuaSingleton.gui.completion_background_color.lerp(background, 0.25)
	_accent.bg_color = LuaSingleton.keywords.reserved
	rich_text_label.add_theme_color_override("default_color", LuaSingleton.gui.font_color)
	queue_redraw()
	_layout_notice()

func set_notice(message: String) -> void:
	rich_text_label.text = message
	await _layout_notice()
	if _closing or _presented: return
	_presented = true
	pivot_offset = Vector2(0, size.y * 0.5)
	position.x = -size.x - 120.0
	scale = Vector2(0.98, 0.98)
	_animation = create_tween().set_parallel(true)
	_animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.tween_property(self, "position:x", 0.0, ENTER_TIME)
	_animation.tween_property(self, "scale", Vector2.ONE, ENTER_TIME)
	_animation.tween_property(self, "modulate:a", 1.0, ENTER_TIME * 0.75)
	_animation.chain().tween_callback(func():
		if not _closing: _lifetime.start(HOLD_TIME)
	)

func _layout_notice() -> void:
	if not is_node_ready(): return
	_layout_revision += 1
	var revision := _layout_revision
	var width := _prepare_notice_layout()
	await get_tree().process_frame
	if revision != _layout_revision or not is_inside_tree(): return
	size = Vector2(width, maxf(82.0, rich_text_label.get_content_height() + 34.0))
	pivot_offset = Vector2(0, size.y * 0.5)
	queue_redraw()

func _prepare_notice_layout() -> float:
	# Release font and canvas-transform temporaries before the async phase.
	# Godot 4.2 can retain them if a replacement notice cancels that wait.
	var font: Font = rich_text_label.get_theme_font("normal_font")
	var text_width := 0.0
	for line in rich_text_label.get_parsed_text().split("\n"):
		text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x)
	var origin_x := get_canvas_transform().origin.x
	var available := maxf(160.0, get_viewport_rect().size.x - origin_x - 24.0)
	var width := minf(clampf(text_width + 50.0, 320.0, 540.0), available)
	rich_text_label.position = Vector2(25, 17)
	rich_text_label.size = Vector2(width - 45.0, 1.0)
	return width

func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	draw_style_box(_accent, Rect2(Vector2.ZERO, Vector2(8, size.y)))

func dismiss() -> void:
	if _closing: return
	_closing = true
	_lifetime.stop()
	if _animation != null: _animation.kill()
	_animation = create_tween().set_parallel(true)
	_animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_animation.tween_property(self, "position:x", position.x - 34.0, EXIT_TIME)
	_animation.tween_property(self, "scale", Vector2(0.98, 0.98), EXIT_TIME)
	_animation.tween_property(self, "modulate:a", 0.0, EXIT_TIME)
	_animation.chain().tween_callback(queue_free)
