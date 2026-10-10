extends OptionButton
class_name GriddySelectionMenu

# Keep the OptionButton item API while rendering the opened list in real screen
# pixels. A child hit surface consumes clicks before the native popup can open.
static var active_menu: OptionButton
var _hit: Control
var _layer: CanvasLayer
var _screen: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array[Button] = []
var _open := false
var _focused := -1
var _font: Font
var _font_size := 20
var _content_width := 0.0
var _last_palette: Array = []
var _opening_press := false
var _fade: Tween
var _source_font: Font
var _catalog: Array = []
var _row_styles: Dictionary = {}
var _styles_applied := false
var _button_palette: Array = []
var _layout_window := Vector2.ZERO
var _menu_down := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL
	add_to_group("griddy_selection_menus")
	_hit = Control.new()
	_hit.name = "SelectionHitSurface"
	_hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(_hit)
	_hit.gui_input.connect(_hit_input)
	visibility_changed.connect(_visibility_changed)
	get_viewport().size_changed.connect(_align_menu)
	process_priority = 100
	RenderingServer.frame_pre_draw.connect(_sync_menu)
	LuaSingleton.on_theme_load.connect(_theme_changed)
	_refresh_button_style()
	set_process(false)

func _hit_input(event: InputEvent) -> void:
	if disabled: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hit.accept_event()
		if event.pressed:
			grab_focus()
			if _open: close_menu()
			else:
				_opening_press = true
				open_menu()

func _input(event: InputEvent) -> void:
	if not _open:
		if has_focus() and event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.meta_pressed:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_DOWN, KEY_UP]:
				open_menu()
				get_viewport().set_input_as_handled()
				return
		if has_focus() and not event.is_echo() and _handle_action(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed and _opening_press:
				_opening_press = false
				# Let GUI dispatch receive the release and clear its mouse focus.
				# The hit surface cannot commit a row or open the native popup.
			elif event.pressed and not menu_rect().has_point(get_viewport().get_final_transform() * event.position):
				close_menu()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and handle_key(event):
		get_viewport().set_input_as_handled()
	elif _handle_action(event):
		get_viewport().set_input_as_handled()

func _handle_action(event: InputEvent) -> bool:
	if disabled: return false
	if event is InputEventKey and (event.ctrl_pressed or event.meta_pressed) and event.keycode != KEY_SPACE:
		return false
	if event.is_action_pressed("ui_accept"):
		if event.is_echo(): return true
		if _open: _commit(_focused)
		else: open_menu()
		return true
	if event.is_action_pressed("ui_cancel") and _open:
		close_menu()
		return true
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		if _open: focus_item(_next_enabled(_focused, 1 if event.is_action_pressed("ui_down") else -1))
		else: open_menu()
		return true
	return false

func handle_key(event: InputEventKey) -> bool:
	if not _open or not event.pressed: return false
	if event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: return true
	if event.keycode == KEY_TAB:
		close_menu(false)
		return false
	if event.ctrl_pressed or event.meta_pressed:
		close_menu(false)
		return false
	match event.keycode:
		KEY_ESCAPE:
			close_menu()
		KEY_UP:
			focus_item(_next_enabled(_focused, -1))
		KEY_DOWN:
			focus_item(_next_enabled(_focused, 1))
		KEY_HOME:
			focus_item(_next_enabled(-1, 1))
		KEY_END:
			focus_item(_next_enabled(item_count, -1))
		KEY_PAGEUP:
			focus_item(maxi(0, _focused - 8))
		KEY_PAGEDOWN:
			focus_item(mini(item_count - 1, _focused + 8))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_commit(_focused)
		_:
			return false
	return true

func open_menu() -> void:
	if _open or disabled or item_count == 0 or not is_visible_in_tree(): return
	if is_instance_valid(active_menu) and active_menu != self:
		active_menu.close_menu(false)
	active_menu = self
	_open = true
	grab_focus()
	_build_menu()
	var previous := _focused
	_focused = selected
	_refresh_styles()
	_style_row(previous)
	_style_row(_focused)
	_layout_window = Vector2.ZERO
	_align_menu()
	_screen.show()
	_layer.show()
	_panel.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(_panel, "modulate:a", 1.0, 0.12)
	set_process(true)
	call_deferred("_reveal_focused")

func close_menu(restore_focus: bool = true) -> void:
	if not _open: return
	_open = false
	_opening_press = false
	set_process(false)
	if _fade != null: _fade.kill()
	# CanvasLayer.hide hides drawing, but its Controls can still take GUI hits
	# on Godot 4.2. Hide the CanvasItem root as well before releasing focus.
	if is_instance_valid(_screen): _screen.hide()
	if is_instance_valid(_layer): _layer.hide()
	if active_menu == self: active_menu = null
	if restore_focus and is_visible_in_tree(): grab_focus()

func is_menu_open() -> bool:
	return _open

func menu_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size) if is_instance_valid(_panel) else Rect2()

func anchor_rect() -> Rect2:
	var transform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var top_left := transform * Vector2.ZERO
	var bottom_right := transform * size
	return Rect2(top_left, bottom_right - top_left)

func focus_item(index: int, reveal: bool = true) -> void:
	if index < 0 or index >= item_count or is_item_disabled(index): return
	if _focused == index: return
	var previous := _focused
	_focused = index
	_style_row(previous)
	_style_row(index)
	if reveal: _reveal_focused()
	item_focused.emit(index)

func _hover_item(index: int) -> void:
	# Hover already points to a visible row. Scrolling to it during a preview
	# can move a neighboring row beneath the stationary pointer.
	focus_item(index, false)

func _row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseMotion and not event.relative.is_zero_approx():
		_hover_item(index)

func _commit(index: int) -> void:
	if index < 0 or index >= item_count or is_item_disabled(index): return
	selected = index
	close_menu()
	item_selected.emit(index)

func _next_enabled(from: int, direction: int) -> int:
	var candidate := clampi(from + direction, 0, item_count - 1)
	while candidate >= 0 and candidate < item_count:
		if not is_item_disabled(candidate): return candidate
		candidate += direction
	return _focused

func _build_menu() -> void:
	var source_font := get_theme_font("font")
	var screen_scale := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().y
	var font_size := clampi(roundi(get_theme_font_size("font_size") * absf(screen_scale)), 16, 20)
	var catalog: Array = []
	for index in item_count: catalog.append([get_item_text(index), is_item_disabled(index)])
	if is_instance_valid(_layer) and source_font == _source_font and font_size == _font_size and catalog == _catalog:
		return
	if is_instance_valid(_layer):
		_layer.queue_free()
	_rows.clear()
	_source_font = source_font
	_font_size = font_size
	_catalog = catalog
	_styles_applied = false
	_layer = CanvasLayer.new()
	_layer.name = "SelectionMenuScreenLayer"
	_layer.layer = 90
	# Keep this a separate GUI root as well as a separate rendering canvas.
	# Nesting it below the world-space OptionButton limits GUI hit discovery
	# to that button's original rectangle on Godot 4.2.
	get_tree().current_scene.add_child(_layer)
	_screen = Control.new()
	_screen.name = "SelectionMenuScreen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_screen)
	_panel = PanelContainer.new()
	_panel.name = "SelectionMenuPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "SelectionMenuScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "SelectionMenuItems"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)
	_font = LuaSingleton.prepare_font(source_font)
	if _font is FontFile or _font is SystemFont:
		_font.multichannel_signed_distance_field = true
	_content_width = 0.0
	for index in item_count:
		_content_width = maxf(_content_width, _font.get_string_size(get_item_text(index), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x + 54.0)
		var row := Button.new()
		row.name = "Choice" + str(index)
		row.text = get_item_text(index)
		row.tooltip_text = row.text
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.custom_minimum_size.y = _font_size + 16
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.focus_mode = Control.FOCUS_NONE
		row.disabled = is_item_disabled(index)
		row.add_theme_font_override("font", _font)
		row.add_theme_font_size_override("font_size", _font_size)
		row.add_theme_constant_override("outline_size", 0)
		row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		row.gui_input.connect(_row_input.bind(index))
		row.pressed.connect(_commit.bind(index))
		_list.add_child(row)
		_rows.append(row)

func _refresh_styles() -> void:
	if not is_instance_valid(_panel): return
	_refresh_button_style()
	var background: Color = LuaSingleton.gui.background_color
	var foreground: Color = LuaSingleton.gui.font_color
	var accent: Color = LuaSingleton.gui.caret_color
	if _styles_applied and _last_palette == [background, foreground, accent]: return
	_last_palette = [background, foreground, accent]
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = background.lerp(Color.BLACK, 0.10)
	panel_style.bg_color.a = 0.98
	panel_style.border_color = foreground.lerp(background, 0.65)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(7)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel_style.shadow_color = Color(0, 0, 0, 0.12)
	panel_style.shadow_size = 5
	_panel.add_theme_stylebox_override("panel", panel_style)
	# Share row styles. Focus changes touch only the old and new row.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.set_corner_radius_all(4)
	var focused: StyleBoxFlat = normal.duplicate()
	focused.bg_color = foreground.lerp(background, 0.83)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = foreground.lerp(background, 0.79)
	_row_styles = {"normal": normal, "focused": focused, "hover": hover}
	for key in ["normal", "focused", "hover"]:
		var marked: StyleBoxFlat = _row_styles[key].duplicate()
		marked.border_width_left = 2
		marked.border_color = accent
		_row_styles["selected_" + key] = marked
	for index in _rows.size():
		var row := _rows[index]
		row.begin_bulk_theme_override()
		_style_row(index, false)
		row.add_theme_color_override("font_color", foreground * 1.06)
		row.add_theme_color_override("font_hover_color", foreground * 1.10)
		row.add_theme_color_override("font_pressed_color", foreground * 1.10)
		row.add_theme_color_override("font_disabled_color", foreground.lerp(background, 0.55))
		row.end_bulk_theme_override()
	_styles_applied = true

func _style_row(index: int, bulk: bool = true) -> void:
	if index < 0 or index >= _rows.size() or _row_styles.is_empty(): return
	var prefix := "selected_" if index == selected else ""
	var row := _rows[index]
	if bulk: row.begin_bulk_theme_override()
	row.add_theme_stylebox_override("normal", _row_styles[prefix + ("focused" if index == _focused else "normal")])
	row.add_theme_stylebox_override("hover", _row_styles[prefix + "hover"])
	row.add_theme_stylebox_override("pressed", _row_styles[prefix + "hover"])
	if bulk: row.end_bulk_theme_override()

func _theme_changed() -> void:
	if not is_visible_in_tree(): return
	_refresh_button_style()
	if _open: _refresh_styles()

func _refresh_button_style() -> void:
	if not is_inside_tree() or not is_visible_in_tree(): return
	var background: Color = LuaSingleton.gui.background_color
	var foreground: Color = LuaSingleton.gui.font_color
	if _button_palette == [background, foreground]: return
	_button_palette = [background, foreground]
	var original := get_theme_stylebox("normal")
	var normal := StyleBoxFlat.new()
	normal.bg_color = foreground.lerp(background, 0.95)
	normal.border_color = foreground.lerp(background, 0.72)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		normal.set_content_margin(side, original.get_content_margin(side))
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = foreground.lerp(background, 0.87)
	begin_bulk_theme_override()
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_color_override("font_color", foreground)
	add_theme_color_override("font_hover_color", foreground)
	add_theme_color_override("font_pressed_color", foreground)
	add_theme_color_override("font_focus_color", foreground)
	add_theme_constant_override("modulate_arrow", 1)
	end_bulk_theme_override()

func _align_menu() -> void:
	if not _open or not is_instance_valid(_panel): return
	var viewport_size := Vector2(get_window().size)
	# Canvas item stretching otherwise scales an already positioned menu again.
	# Counter it so one list unit and one font pixel equal one window pixel.
	_layer.transform = get_viewport().get_final_transform().affine_inverse()
	var anchor := anchor_rect()
	# Height and direction stay steady. The width may follow an unfinished
	# focus zoom, using cached measurements rather than reshaping every row.
	var target_width := roundf(clampf(maxf(anchor.size.x, _content_width), minf(220.0, viewport_size.x - 24.0), viewport_size.x - 24.0))
	if _layout_window != viewport_size:
		_layout_window = viewport_size
		var width := clampf(maxf(anchor.size.x, _content_width), minf(220.0, viewport_size.x - 24.0), viewport_size.x - 24.0)
		var below := viewport_size.y - anchor.end.y - 16.0
		var above := anchor.position.y - 16.0
		_menu_down = below >= minf(160.0, above)
		var available := below if _menu_down else above
		var height := minf((_font_size + 18.0) * item_count + 12.0, minf(viewport_size.y * 0.72, maxf(available - 10.0, 40.0)))
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.size = Vector2(roundf(width), roundf(height))
	if not is_equal_approx(_panel.size.x, target_width): _panel.size.x = target_width
	var width := _panel.size.x
	var height := _panel.size.y
	var left := clampf(anchor.position.x, 12.0, viewport_size.x - width - 12.0)
	var top := anchor.end.y + 4.0 if _menu_down else anchor.position.y - height - 4.0
	_panel.position = Vector2(left, clampf(top, 12.0, viewport_size.y - height - 12.0))

func _sync_menu() -> void:
	if not _open: return
	var camera := get_tree().current_scene.get_node_or_null("Misc/Cam")
	if is_instance_valid(camera): camera.force_update_scroll()
	_align_menu()

func _reveal_focused() -> void:
	if _open and _focused >= 0 and _focused < _rows.size():
		_scroll.ensure_control_visible(_rows[_focused])

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or modulate.a <= 0.02:
		close_menu(false)
		return
	_sync_menu()
	if _last_palette != [LuaSingleton.gui.background_color, LuaSingleton.gui.font_color, LuaSingleton.gui.caret_color]:
		_refresh_styles()

func _visibility_changed() -> void:
	if not is_visible_in_tree(): close_menu(false)
	else: _refresh_button_style()

func _exit_tree() -> void:
	close_menu(false)
	if is_instance_valid(_layer): _layer.queue_free()
	if RenderingServer.frame_pre_draw.is_connected(_sync_menu):
		RenderingServer.frame_pre_draw.disconnect(_sync_menu)
