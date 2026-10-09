extends Node

var failures := 0
var app: Node2D
var panel: Control
var book: Node
var output := ""
var original_store: Node

class FakeStore extends Node:
	signal changed
	var entries: Array[Dictionary] = []
	var updates: Array[Dictionary] = []
	var removals: Array[String] = []
	func update_entry(id: String, patch: Dictionary) -> Dictionary:
		for entry in entries:
			if entry.id != id: continue
			for field in patch: entry[field] = patch[field]
			updates.append({"id": id, "patch": patch.duplicate(true)})
			changed.emit()
			return {"ok": true, "entry": entry.duplicate(true)}
		return {"ok": false, "error": "Missing test entry"}

	func remove_entry(id: String) -> Dictionary:
		for index in entries.size():
			if entries[index].id != id: continue
			entries.remove_at(index)
			removals.append(id)
			changed.emit()
			return {"ok": true}
		return {"ok": false, "error": "Missing test entry"}

class FakeSettingsActions extends Node:
	var calls: Array[String] = []
	func is_active() -> bool: return false
	func choose_vault() -> void: calls.append("obsidian_vault")
	func choose_folder() -> void: calls.append("obsidian_folder")
	func sync_now() -> void: calls.append("obsidian_sync_now")

func _ready() -> void:
	app = get_parent()
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../qa/wordbook-ui-source")
	DirAccess.make_dir_recursive_absolute(output)
	Input.use_accumulated_input = false
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures += 1

func key(code: Key, control: bool = false, shift: bool = false, character: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = character
	event.ctrl_pressed = control
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func type_text(value: String) -> void:
	for character in value:
		key(character.to_upper().unicode_at(0), false, false, character.unicode_at(0))
		await get_tree().process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func screen_bounds(control: Control) -> Rect2:
	var transform := get_viewport().get_final_transform() * control.get_global_transform_with_canvas()
	var corners := [Vector2.ZERO, Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]
	var result := Rect2(transform * corners[0], Vector2.ZERO)
	for corner in corners: result = result.expand(transform * corner)
	return result

func fits(control: Control, margin: float = 8.0) -> bool:
	var bounds := screen_bounds(control)
	var window := Vector2(get_window().size)
	return bounds.position.x >= margin and bounds.position.y >= margin and bounds.end.x <= window.x - margin and bounds.end.y <= window.y - margin

func settings_row(property: String) -> Control:
	for row in app.get_node("Settings/SettingsList").get_children():
		if row.get_node("Control2/HSlider").get_meta("setting_property", "") == property: return row
	return null

func drive_selected(node: Node, drive: String) -> bool:
	if node is OptionButton and node.selected >= 0 and node.get_item_text(node.selected).to_upper().strip_edges() == drive.to_upper(): return true
	for child in node.get_children(true):
		if drive_selected(child, drive): return true
	return false

func click(control: Control) -> void:
	var point := screen_bounds(control).get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	Input.parse_input_event(move)
	Input.flush_buffered_events()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame

func sample(index: int) -> Dictionary:
	var words := ["manipulate", "take care of", "priority"]
	return {
		"id": "test-wordbook-" + str(index),
		"word": words[index] if index < words.size() else "sample " + str(index),
		"translation": ["操纵；操作", "照顾", "优先事项"][index] if index < 3 else "测试词条 " + str(index),
		"source_language": "en", "target_language": "zh-CN", "provider": "youdao",
		"phonetic": "/məˈnɪpjuleɪt/" if index == 0 else "",
		"tags": ["英语", "学习"], "notes": "A user note retained verbatim.\n".repeat(40) if index == 0 else "",
		"examples": [{"english": "The technology uses a pen to manipulate a computer.", "chinese": "这项技术使用笔来操作计算机。"}],
		"created_at": "2026-10-09T00:00:00Z", "updated_at": "2026-10-09T00:00:00Z"
	}

func run() -> void:
	get_tree().create_timer(65).timeout.connect(func(): get_tree().quit(2))
	await get_tree().create_timer(0.6).timeout
	LuaSingleton.change_setting("music", false)
	LuaSingleton.change_setting("screen_motion", true)
	panel = app.get_node("Wordbook")
	original_store = panel.store
	book = FakeStore.new()
	app.add_child(book)
	for index in 15: book.entries.append(sample(index))
	panel.setup(book)
	var source_before: String = app.Code.text
	key(KEY_B, true)
	await get_tree().create_timer(1.0).timeout
	check(panel.active and panel.visible and app.Code.active_overlay == panel, "Ctrl+B opens the wordbook through the original animated overlay")
	check(panel.search.has_focus(), "wordbook search receives native keyboard and IME focus")
	check(panel._font == app.Code.get_theme_font("font") and not panel.get_parent() is CanvasLayer, "wordbook shares the editor font and HDR world canvas")
	check(panel.rows.size() == 8 and panel.filtered.size() == 15, "wordbook paginates large books without shrinking the font")
	check(panel._hint.get_minimum_size().x <= panel.content_size().x, "shortcut hints fit the panel without horizontal clipping")
	check(fits(panel), "wordbook list fits the real window with the animated camera focused")
	await capture("wordbook-list")
	key(KEY_PAGEDOWN)
	await get_tree().process_frame
	check(panel.selected_index == 8 and panel.rows.size() == 7, "PageDown advances to the next bounded page")
	key(KEY_F, true)
	await type_text("take care")
	check(panel.filtered.size() == 1 and panel.selected_entry().word == "take care of", "native typing filters exact phrases without splitting them into words")
	check(app.Code.text == source_before, "wordbook search never types into the translation source")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	key(KEY_ENTER)
	await get_tree().process_frame
	check(panel.expanded and panel._detail.visible and panel.rows.size() == 4, "Enter expands examples and notes while keeping a readable list")
	check(panel._detail.get_content_height() > panel._detail.size.y and panel._detail.scroll_active, "long entry notes scroll inside a bounded detail region")
	check(fits(panel._detail), "expanded details remain inside the real rendered window")
	await capture("wordbook-detail")
	key(KEY_E, true)
	await get_tree().process_frame
	check(panel.editing and panel._translation_edit.has_focus(), "Ctrl+E focuses the editable translation directly")
	check(fits(panel._translation_edit) and fits(panel._tags_edit) and fits(panel._notes_edit), "all three edit fields remain visible in the real rendered window")
	await capture("wordbook-edit")
	key(KEY_A, true)
	await type_text("Updated translation")
	panel._tags_edit.text = "英语， updated, updated"
	panel._notes_edit.text = "User Markdown\n[[existing note]]\nOriginal content retained."
	key(KEY_ENTER, true)
	await get_tree().process_frame
	check(not panel.editing and book.updates.size() == 1 and book.entries[0].translation == "Updated translation", "Ctrl+Enter commits a native edit without sending a translation request")
	check(book.entries[0].tags == ["英语", "updated"] and book.entries[0].notes.contains("[[existing note]]"), "editing normalizes tags and preserves personal Markdown notes")
	check(panel.search.has_focus() and app.Code.text == source_before, "saving restores search focus and preserves the main source")
	key(KEY_E, true)
	await get_tree().process_frame
	panel._translation_edit.text = "discard this"
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not panel.editing and book.entries[0].translation == "Updated translation", "Escape cancels an edit without modifying storage")
	key(KEY_DELETE)
	await get_tree().process_frame
	check(book.removals.is_empty() and not panel._delete_id.is_empty(), "Delete first asks for a second keypress in the same panel")
	key(KEY_DOWN)
	key(KEY_DELETE)
	await get_tree().process_frame
	check(book.removals.is_empty(), "changing selection invalidates the prior deletion confirmation")
	key(KEY_DELETE)
	await get_tree().process_frame
	check(book.removals == ["test-wordbook-1"] and panel.filtered.size() == 14, "second Delete removes only the explicitly selected local entry")
	var small_position: Vector2 = panel.focus_position(panel.position)
	check(small_position == panel.position + panel.content_size() * 0.5 and panel.zoom.x > 0.0, "panel exposes bounded centered focus for the original camera")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	check(not panel.active and app.Code.active_overlay == null, "Escape returns through the original panel close animation")
	panel.setup(original_store)
	book.queue_free()
	key(KEY_COMMA, true)
	await get_tree().create_timer(1.0).timeout
	check(app.Code.active_overlay == app.get_node("Settings"), "Ctrl+comma retains the original settings animation")
	var sync_row := settings_row("obsidian_sync")
	check(sync_row != null and sync_row.get_node("Control2/CheckButton").is_visible_in_tree() and fits(sync_row.get_node("Control/RichTextLabel")) and fits(sync_row.get_node("Control2/CheckButton")), "automatic Obsidian sync row and toggle fit the adaptive settings camera")
	var action_buttons: Array[Button] = []
	for property in ["obsidian_vault", "obsidian_folder", "obsidian_sync_now"]:
		var row := settings_row(property)
		var button: Button
		if row != null:
			for node in row.get_node("Control5").get_children():
				if node is Button and not node is OptionButton: button = node; break
		check(row != null and button != null and button.is_visible_in_tree() and fits(row.get_node("Control/RichTextLabel")) and fits(button), "Obsidian settings action is visible and aligned: " + property)
		if button != null:
			action_buttons.append(button)
			check(button.get_theme_font("font") == app.Code.get_theme_font("font") and not row.get_node("Control2/HSlider").visible, "Obsidian action shares the editor font and replaces the numeric slider: " + property)
	var saved_font: int = LuaSingleton.get_setting("editor_font")[0].value
	LuaSingleton.change_setting("editor_font", 1 if saved_font != 1 else 0)
	for button in action_buttons:
		check(button.get_theme_font("font") == app.Code.get_theme_font("font"), "Obsidian action follows a later editor font change through the shared theme")
	LuaSingleton.change_setting("editor_font", saved_font)
	check(app.wordbook.vault_path.is_empty() and not app.wordbook.sync_enabled, "GUI QA keeps Obsidian disconnected and never writes the user's vault")
	await capture("settings-obsidian")
	var controller: Node = app.wordbook
	var fake_actions := FakeSettingsActions.new()
	app.add_child(fake_actions)
	app.wordbook = fake_actions
	for button in action_buttons: await click(button)
	check(fake_actions.calls == ["obsidian_vault", "obsidian_folder", "obsidian_sync_now"], "real mouse clicks route all three Obsidian actions while notices and screen motion remain active")
	app.wordbook = controller
	fake_actions.queue_free()
	var original_folder: String = controller.folder
	controller.choose_folder()
	await get_tree().create_timer(0.2).timeout
	check(controller._folder_editor.visible and controller._folder_input.is_visible_in_tree() and controller._folder_input.has_focus(), "folder setting opens a native confirmation with the path field focused")
	check(controller._folder_input.size.x >= 400 and controller._folder_input.size.y >= 24, "folder confirmation lays out a wide editable path field")
	check(controller._folder_input.position.x >= 0 and controller._folder_input.position.y >= 0 and controller._folder_input.position.x + controller._folder_input.size.x <= controller._folder_editor.size.x, "folder path field fits its native dialog bounds")
	await capture("folder-dialog")
	controller._folder_editor.hide()
	controller.choose_vault()
	await get_tree().create_timer(0.2).timeout
	check(controller._folder_picker.visible and controller._folder_picker.access == FileDialog.ACCESS_FILESYSTEM and controller._folder_picker.file_mode == FileDialog.FILE_MODE_OPEN_DIR, "vault picker opens with filesystem directory access")
	controller._folder_picker.current_dir = "D:/"
	await get_tree().create_timer(0.1).timeout
	check(drive_selected(controller._folder_picker, "D:"), "vault picker can browse the D drive instead of only the C drive")
	await capture("vault-dialog")
	controller._folder_picker.hide()
	check(controller.vault_path.is_empty() and controller.folder == original_folder and not controller.sync_enabled, "cancelling both native dialogs preserves configuration without vault writes")
	key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	print("WORD_BOOK_UI_TEST_PASS" if failures == 0 else "WORD_BOOK_UI_TEST_FAIL count=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
