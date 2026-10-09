extends Control

# This panel lives in the original world canvas. Code.toggle supplies its
# slide/fade and camera focus, so fonts and HDR glow follow the editor.
signal ui_close
signal open_obsidian(id: String)
signal request_speech(entry: Dictionary, translated: bool)
signal status(message: String)

const PANEL_SIZE := Vector2(820, 670)
var store: Node
var zoom := Vector2.ONE
var active := false:
	set(value):
		active = value
		if not is_node_ready(): return
		if value:
			_apply_theme()
			refresh()
			_focus_search.call_deferred()
		else:
			_cancel_edit()
			_delete_id = ""
			search.release_focus()

var selected_index := 0
var expanded := false
var editing := false
var filtered: Array[Dictionary] = []
var rows: Array[Button] = []
var _delete_id := ""
var _delete_until := 0
var _editing_id := ""
var _font: Font
var _title: Label
var _count: Label
var search: LineEdit
var _rows_root: VBoxContainer
var _detail: RichTextLabel
var _hint: Label
var _page: Label
var _edit_root: Control
var _translation_edit: TextEdit
var _tags_edit: LineEdit
var _notes_edit: TextEdit
var _form_labels: Array[Label] = []

func _ready() -> void:
	size = PANEL_SIZE
	_font = get_parent().get_node("Code").get_theme_font("font")
	_build_ui()
	_apply_theme()
	LuaSingleton.on_theme_load.connect(_apply_theme)
	LuaSingleton.on_settings_change.connect(_apply_theme)
	get_viewport().size_changed.connect(_refocus_after_resize)
	visibility_changed.connect(_on_visibility_changed)
	refresh()

func setup(store_node: Node) -> void:
	if is_instance_valid(store) and store.has_signal("changed") and store.changed.is_connected(refresh):
		store.changed.disconnect(refresh)
	store = store_node
	if is_instance_valid(store) and store.has_signal("changed"):
		store.changed.connect(refresh)
	if is_node_ready(): refresh()

func _build_ui() -> void:
	_title = _label("Wordbook / 单词本", Vector2.ZERO, Vector2(600, 38), 26)
	_count = _label("", Vector2(630, 7), Vector2(190, 28), 17)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	search = LineEdit.new()
	search.name = "Search"
	search.position = Vector2(0, 53)
	search.size = Vector2(820, 42)
	search.placeholder_text = "输入搜索 · 单词、译文、标签"
	search.context_menu_enabled = false
	add_child(search)
	search.text_changed.connect(_on_search_changed)
	_rows_root = VBoxContainer.new()
	_rows_root.name = "Entries"
	_rows_root.position = Vector2(0, 116)
	_rows_root.size = Vector2(820, 424)
	_rows_root.add_theme_constant_override("separation", 5)
	add_child(_rows_root)
	_detail = RichTextLabel.new()
	_detail.name = "Detail"
	_detail.position = Vector2(14, 339)
	_detail.size = Vector2(792, 263)
	_detail.selection_enabled = true
	_detail.scroll_active = true
	_detail.bbcode_enabled = true
	_detail.visible = false
	add_child(_detail)
	_page = _label("", Vector2(0, 606), Vector2(820, 24), 14)
	_hint = _label("", Vector2(0, 632), Vector2(820, 38), 13)
	_build_edit_form()

func _label(value: String, at: Vector2, bounds: Vector2, font_size: int) -> Label:
	var node := Label.new()
	node.text = value
	node.position = at
	node.size = bounds
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", font_size)
	add_child(node)
	return node

func _build_edit_form() -> void:
	_edit_root = Control.new()
	_edit_root.name = "Edit"
	_edit_root.position = Vector2(0, 112)
	_edit_root.size = Vector2(820, 490)
	_edit_root.visible = false
	add_child(_edit_root)
	for item in [["Translation / 译文", 0], ["Tags / 标签（逗号分隔）", 150], ["Notes / 我的笔记", 231]]:
		var label := Label.new()
		label.text = item[0]
		label.position = Vector2(0, item[1])
		label.add_theme_font_size_override("font_size", 15)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edit_root.add_child(label)
		_form_labels.append(label)
	_translation_edit = _text_edit("Translation", Vector2(0, 30), Vector2(820, 106))
	_tags_edit = LineEdit.new()
	_tags_edit.name = "Tags"
	_tags_edit.position = Vector2(0, 181)
	_tags_edit.size = Vector2(820, 36)
	_tags_edit.context_menu_enabled = false
	_edit_root.add_child(_tags_edit)
	_notes_edit = _text_edit("Notes", Vector2(0, 262), Vector2(820, 226))
	_translation_edit.focus_next = _translation_edit.get_path_to(_tags_edit)
	_tags_edit.focus_next = _tags_edit.get_path_to(_notes_edit)
	_notes_edit.focus_next = _notes_edit.get_path_to(_translation_edit)
	_translation_edit.focus_previous = _translation_edit.get_path_to(_notes_edit)
	_tags_edit.focus_previous = _tags_edit.get_path_to(_translation_edit)
	_notes_edit.focus_previous = _notes_edit.get_path_to(_tags_edit)

func _text_edit(node_name: String, at: Vector2, bounds: Vector2) -> TextEdit:
	var node := TextEdit.new()
	node.name = node_name
	node.position = at
	node.size = bounds
	node.context_menu_enabled = false
	node.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	node.caret_blink = true
	_edit_root.add_child(node)
	return node

func _apply_theme() -> void:
	if not is_node_ready() or not is_instance_valid(search): return
	if not is_visible_in_tree(): return
	var code := get_parent().get_node_or_null("Code")
	_font = code.get_theme_font("font") if code is Control else LuaSingleton.editor_theme.get_font("font", "MyType")
	var color: Color = LuaSingleton.gui.font_color
	for node in [_title, _count, _page, _hint] + _form_labels:
		node.add_theme_font_override("font", _font)
		node.add_theme_color_override("font_color", color)
	_count.modulate.a = 0.65
	_page.modulate.a = 0.65
	_hint.modulate.a = 0.75
	for node in [search, _translation_edit, _tags_edit, _notes_edit]:
		node.add_theme_font_override("font", _font)
		node.add_theme_font_size_override("font_size", 18)
		node.add_theme_color_override("font_color", color)
		node.add_theme_color_override("caret_color", LuaSingleton.gui.caret_color)
		node.add_theme_color_override("selection_color", LuaSingleton.readable_highlight(LuaSingleton.gui.selection_color))
		node.add_theme_color_override("font_selected_color", color)
		node.add_theme_color_override("font_placeholder_color", Color(color.r, color.g, color.b, 0.45))
		var box := StyleBoxFlat.new()
		var bg: Color = LuaSingleton.gui.background_color
		box.bg_color = Color(bg.r, bg.g, bg.b, 0.40) if node != search else Color.TRANSPARENT
		box.border_color = Color(color.r, color.g, color.b, 0.18)
		box.border_width_bottom = 1
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		node.add_theme_stylebox_override("normal", box)
		var focused := box.duplicate() as StyleBoxFlat
		focused.border_color = Color(color.r, color.g, color.b, 0.55)
		node.add_theme_stylebox_override("focus", focused)
	_detail.add_theme_font_override("normal_font", _font)
	_detail.add_theme_font_override("bold_font", _font)
	_detail.add_theme_font_override("italics_font", _font)
	_detail.add_theme_font_override("bold_italics_font", _font)
	_detail.add_theme_font_size_override("normal_font_size", 18)
	_detail.add_theme_color_override("default_color", color)
	_render_rows()
	_render_detail()

func refresh() -> void:
	if not is_node_ready() or not is_instance_valid(search): return
	var current := selected_entry()
	var wanted_id := str(current.get("id", ""))
	filtered.clear()
	var query := search.text.strip_edges().to_lower()
	if is_instance_valid(store):
		for entry in store.entries:
			var haystack := str(entry.get("word", "")) + "\n" + str(entry.get("translation", "")) + "\n" + str(entry.get("notes", ""))
			for tag in entry.get("tags", []): haystack += "\n" + str(tag)
			if query.is_empty() or haystack.to_lower().contains(query): filtered.append(entry.duplicate(true))
	selected_index = clampi(selected_index, 0, maxi(0, filtered.size() - 1))
	if not wanted_id.is_empty():
		for index in filtered.size():
			if str(filtered[index].get("id", "")) == wanted_id:
				selected_index = index
				break
	_count.text = str(filtered.size()) + " entries / 词条"
	_render_rows()
	_render_detail()
	_update_hints()

func selected_entry() -> Dictionary:
	if selected_index < 0 or selected_index >= filtered.size(): return {}
	return filtered[selected_index].duplicate(true)

func _page_size() -> int:
	return 4 if expanded else 8

func _render_rows() -> void:
	if not is_instance_valid(_rows_root): return
	for row in rows:
		_rows_root.remove_child(row)
		row.queue_free()
	rows.clear()
	_rows_root.visible = not editing
	_rows_root.size.y = 208 if expanded else 424
	if editing: return
	var page_start := (selected_index / _page_size()) * _page_size()
	var page_end := mini(page_start + _page_size(), filtered.size())
	if filtered.is_empty():
		var row := Button.new()
		row.disabled = true
		row.text = "还没有词条 · 在翻译界面按 Ctrl+D 收藏" if search.text.is_empty() else "没有匹配的词条"
		row.custom_minimum_size = Vector2(820, 100)
		row.flat = true
		row.add_theme_font_override("font", _font)
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_color_override("font_disabled_color", LuaSingleton.gui.font_color)
		_rows_root.add_child(row)
		rows.append(row)
		return
	for index in range(page_start, page_end):
		var entry: Dictionary = filtered[index]
		var row := Button.new()
		row.name = "Entry" + str(index)
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(820, 48)
		var plain := StyleBoxFlat.new()
		plain.bg_color = Color.TRANSPARENT
		plain.content_margin_left = 14
		plain.content_margin_right = 14
		var selected := index == selected_index
		var color: Color = LuaSingleton.gui.selection_color
		if selected:
			plain.bg_color = Color(color.r, color.g, color.b, 0.42)
			plain.border_width_left = 2
			plain.border_color = LuaSingleton.gui.caret_color
		row.add_theme_stylebox_override("normal", plain)
		var hover := plain.duplicate() as StyleBoxFlat
		if not selected:
			var font_color: Color = LuaSingleton.gui.font_color
			hover.bg_color = Color(font_color.r, font_color.g, font_color.b, 0.08)
		row.add_theme_stylebox_override("hover", hover)
		row.add_theme_stylebox_override("pressed", hover)
		_rows_root.add_child(row)
		rows.append(row)
		var word := Label.new()
		word.text = str(entry.get("word", "")).replace("\n", " ")
		word.position = Vector2(16, 8)
		word.size = Vector2(285, 34)
		word.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		word.clip_text = true
		word.mouse_filter = Control.MOUSE_FILTER_IGNORE
		word.add_theme_font_override("font", _font)
		word.add_theme_font_size_override("font_size", 21)
		word.add_theme_color_override("font_color", LuaSingleton.gui.font_color)
		row.add_child(word)
		var translation := Label.new()
		translation.text = str(entry.get("translation", "")).replace("\n", " ")
		translation.position = Vector2(320, 10)
		translation.size = Vector2(482, 31)
		translation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		translation.clip_text = true
		translation.mouse_filter = Control.MOUSE_FILTER_IGNORE
		translation.add_theme_font_override("font", _font)
		translation.add_theme_font_size_override("font_size", 18)
		translation.add_theme_color_override("font_color", LuaSingleton.gui.font_color)
		translation.modulate.a = 0.75
		row.add_child(translation)
		row.pressed.connect(_select_row.bind(index))

func _select_row(index: int) -> void:
	if selected_index == index:
		expanded = not expanded
	else:
		selected_index = index
	_delete_id = ""
	_render_rows()
	_render_detail()
	_update_hints()
	_focus_search()

func _render_detail() -> void:
	if not is_instance_valid(_detail): return
	_detail.visible = expanded and not editing and not filtered.is_empty()
	_detail.clear()
	if not _detail.visible: return
	var entry := selected_entry()
	_detail.push_color(LuaSingleton.gui.font_color)
	_detail.push_font_size(23)
	_detail.add_text(str(entry.get("word", "")))
	_detail.pop()
	var phonetic := str(entry.get("phonetic", ""))
	if not phonetic.is_empty(): _detail.add_text("  " + phonetic)
	_detail.add_text("\n" + str(entry.get("translation", "")) + "\n")
	var tags: Array = entry.get("tags", [])
	var tag_line := ""
	for tag in tags: tag_line += "  #" + str(tag)
	_detail.push_color(_muted_color())
	_detail.push_font_size(14)
	_detail.add_text(str(entry.get("source_language", "")).to_upper() + " → " + str(entry.get("target_language", "")).to_upper() + " · " + str(entry.get("provider", "")) + tag_line + "\n")
	_detail.pop()
	_detail.pop()
	for example in entry.get("examples", []):
		if not example is Dictionary: continue
		_detail.add_text("\n" + str(example.get("english", "")) + "\n")
		_detail.push_color(_muted_color())
		_detail.add_text(str(example.get("chinese", "")) + "\n")
		_detail.pop()
	var notes := str(entry.get("notes", ""))
	if not notes.is_empty():
		_detail.add_text("\nNotes / 我的笔记\n" + notes)
	_detail.pop()
	_detail.scroll_to_line(0)

func _muted_color() -> Color:
	var color: Color = LuaSingleton.gui.font_color
	return Color(color.r, color.g, color.b, 0.65)

func _update_hints() -> void:
	if editing:
		_page.text = "正在编辑 · " + str(selected_entry().get("word", ""))
		_hint.text = "Tab 切换字段 · Ctrl+Enter 保存 · Esc 取消"
		return
	if filtered.is_empty():
		_page.text = ""
	else:
		var start := (selected_index / _page_size()) * _page_size()
		_page.text = "%d–%d / %d   ·   PgUp / PgDn 翻页" % [start + 1, mini(start + _page_size(), filtered.size()), filtered.size()]
	if not _delete_id.is_empty():
		_hint.text = "再按 Delete 删除此词条 · Obsidian 笔记移到回收站 · Esc 取消"
	else:
		_hint.text = "↑ ↓ 选择 · Enter 详情 · Ctrl+E 编辑 · Delete 删除 · Esc 返回\nCtrl+P 原词 · Ctrl+O 译文 · Ctrl+Shift+O Obsidian"

func _on_search_changed(_value: String) -> void:
	selected_index = 0
	_delete_id = ""
	filtered.clear()
	refresh()

func _focus_search() -> void:
	if active and not editing and is_visible_in_tree(): search.grab_focus()

func handle_key(event: InputEventKey) -> bool:
	if not active or not event.pressed: return false
	var key := event.keycode if event.keycode != 0 else event.physical_keycode
	var control := event.ctrl_pressed or event.meta_pressed
	if editing:
		if control and key == KEY_ENTER:
			if not event.echo: _save_edit()
			return true
		if not control and not event.alt_pressed and key == KEY_ESCAPE:
			_cancel_edit()
			return true
		return false
	if control:
		if key == KEY_E:
			if not event.echo: _begin_edit()
			return true
		if key == KEY_F:
			_focus_search()
			search.select_all()
			return true
		return false
	if event.alt_pressed: return false
	match key:
		KEY_UP: _move_selection(-1)
		KEY_DOWN: _move_selection(1)
		KEY_PAGEUP: _move_selection(-_page_size())
		KEY_PAGEDOWN: _move_selection(_page_size())
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo and not filtered.is_empty():
				expanded = not expanded
				_delete_id = ""
				_render_rows()
				_render_detail()
				_update_hints()
		KEY_DELETE:
			if not event.echo: _delete_selected()
		KEY_ESCAPE:
			if not _delete_id.is_empty():
				_delete_id = ""
				_update_hints()
			elif not search.text.is_empty(): search.text = ""; _on_search_changed("")
			elif expanded:
				expanded = false
				_render_rows()
				_render_detail()
				_update_hints()
			else: return false
		_: return false
	return true

func _move_selection(delta: int) -> void:
	if filtered.is_empty(): return
	selected_index = clampi(selected_index + delta, 0, filtered.size() - 1)
	_delete_id = ""
	_render_rows()
	_render_detail()
	_update_hints()

func _begin_edit() -> void:
	var entry := selected_entry()
	if entry.is_empty(): return
	editing = true
	_editing_id = str(entry.get("id", ""))
	_delete_id = ""
	_translation_edit.text = str(entry.get("translation", ""))
	_tags_edit.text = ", ".join(entry.get("tags", []))
	_notes_edit.text = str(entry.get("notes", ""))
	_edit_root.show()
	_rows_root.hide()
	_detail.hide()
	search.editable = false
	_update_hints()
	_translation_edit.grab_focus()

func _cancel_edit() -> void:
	if not editing: return
	editing = false
	_editing_id = ""
	_edit_root.hide()
	search.editable = true
	refresh()
	_focus_search()

func _save_edit() -> void:
	if not editing or not is_instance_valid(store): return
	var tags: Array[String] = []
	for tag in _tags_edit.text.replace("，", ",").split(","):
		var value: String = tag.strip_edges().trim_prefix("#")
		if not value.is_empty() and not tags.has(value): tags.append(value)
	var result: Dictionary = store.update_entry(_editing_id, {"translation": _translation_edit.text, "tags": tags, "notes": _notes_edit.text})
	if not result.get("ok", false):
		status.emit(str(result.get("error", "保存失败")))
		return
	_cancel_edit()
	status.emit("词条已保存")

func _delete_selected() -> void:
	var entry := selected_entry()
	if entry.is_empty() or not is_instance_valid(store): return
	var id := str(entry.get("id", ""))
	if _delete_id != id or Time.get_ticks_msec() > _delete_until:
		_delete_id = id
		_delete_until = Time.get_ticks_msec() + 5000
		_update_hints()
		return
	var result: Dictionary = store.remove_entry(id)
	_delete_id = ""
	refresh()
	status.emit("词条已删除，Obsidian 删除将按同步设置执行" if result.get("ok", false) else str(result.get("error", "删除失败")))

func content_size() -> Vector2:
	return PANEL_SIZE

func focus_position(future_position: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	zoom = Vector2.ONE * minf(1.3, minf(viewport_size.x * 0.84 / PANEL_SIZE.x, viewport_size.y * 0.82 / PANEL_SIZE.y))
	return future_position + PANEL_SIZE * 0.5

func _refocus_after_resize() -> void:
	if not active: return
	var code := get_parent().get_node_or_null("Code")
	if code != null and code.node_is_transitioning:
		await get_tree().create_timer(code.panel_duration() + 0.03).timeout
	if active:
		var cam := get_parent().get_node_or_null("Misc/Cam")
		if cam != null: cam.focus_on(focus_position(global_position), zoom)

func _on_visibility_changed() -> void:
	if not visible and active: active = false

func _process(_delta: float) -> void:
	if not active: return
	var code := get_parent().get_node_or_null("Code")
	if code is Control and code.get_theme_font("font") != _font: _apply_theme()
	if not _delete_id.is_empty() and Time.get_ticks_msec() > _delete_until:
		_delete_id = ""
		_update_hints()
