extends Node

const Store = preload("res://Scripts/wordbook_store.gd")
const PanelScene = preload("res://Scenes/wordbook_panel.tscn")
const Sync = preload("res://Scripts/obsidian_sync.gd")
const TranslationService = preload("res://Scripts/translation_service.gd")
const Metadata = preload("res://Scripts/word_metadata_service.gd")

var app: Node
var store: Node
var panel: Control
var translation_service: Node
var metadata_service: Node
var vault_path := ""
var folder := "GriddyTranslate/单词本"
var sync_enabled := true
var last_open_uri := ""
var _pending_words: Dictionary = {}
var _collect_queue: Array[Dictionary] = []
var _collecting := false
var _sync_pending: Dictionary = {}
var _sync_known: Dictionary = {}
var _sync_thread: Thread
var _sync_generation := 0
var _sync_failed := false
var _sync_cancel: Dictionary = {}
var _open_thread: Thread
var sync_backend: Script = Sync
var _exiting := false
var _test_sync_enabled := false
var _folder_picker: FileDialog
var _folder_editor: ConfirmationDialog
var _folder_input: LineEdit

func setup(editor: Node) -> void:
	app = editor
	store = Store.new()
	add_child(store)
	var loaded: Dictionary = store.load_book()
	if not loaded.get("ok", false): app.warn.call_deferred(str(loaded.error))
	elif loaded.get("recovered", false): app.warn.call_deferred("已从完整备份恢复单词本，请检查最近的收藏。")
	translation_service = TranslationService.new()
	add_child(translation_service)
	metadata_service = Metadata.new()
	add_child(metadata_service)
	panel = PanelScene.instantiate()
	panel.name = "Wordbook"
	panel.position = Vector2(-980, 80)
	app.add_child(panel)
	panel.setup(store)
	panel.status.connect(app.warn)
	panel.ui_close.connect(app.close_active_panel)
	panel.open_obsidian.connect(open_entry)
	panel.request_speech.connect(speak_entry)
	_load_preferences()
	store.changed.connect(_on_store_changed)
	_refresh_setting_labels()
	_on_store_changed.call_deferred()

func _load_preferences() -> void:
	if OS.get_cmdline_user_args().has("--test"):
		sync_enabled = false
		LuaSingleton.get_setting("obsidian_sync")[0].value = false
		return
	var config := ConfigFile.new()
	config.load("user://translator.cfg")
	vault_path = str(config.get_value("wordbook", "obsidian_vault", ""))
	folder = str(config.get_value("wordbook", "obsidian_folder", folder))
	sync_enabled = bool(config.get_value("wordbook", "obsidian_sync", true))
	if vault_path.is_empty():
		var vaults: Array = Sync.discover_vaults()
		for vault in vaults:
			if vault.get("opened", false) or vaults.size() == 1:
				vault_path = str(vault.path)
				break
	LuaSingleton.get_setting("obsidian_sync")[0].value = sync_enabled

func save_preferences(config: ConfigFile) -> void:
	config.set_value("wordbook", "obsidian_vault", vault_path)
	config.set_value("wordbook", "obsidian_folder", folder)
	config.set_value("wordbook", "obsidian_sync", sync_enabled)

func _refresh_setting_labels() -> void:
	LuaSingleton.get_setting("obsidian_vault")[0].value = vault_path.get_file() if not vault_path.is_empty() else "选择保管库…"
	LuaSingleton.get_setting("obsidian_folder")[0].value = folder

func is_active() -> bool:
	return is_instance_valid(panel) and panel.active

func toggle_panel() -> void:
	if app.Code.node_is_transitioning: return
	if app.Code.active_overlay != null and app.Code.active_overlay != panel: return
	app.Code.toggle(panel)
	if not app.Code._show: app.get_tree().create_timer(app.Code.panel_duration() + 0.03).timeout.connect(app.restore_input_focus)

func collect_current() -> void:
	var value: String = app.source_text if app.showing_translation else app.Code.text
	if app.Code.has_selection():
		if app.showing_translation and (app.translation_placement != 1 or app.Code.get_selection_to_line() >= app.result_first_line()):
			app.warn("请返回原文，选择要收藏的单词或完整短语。")
			return
		value = app.Code.get_selected_text()
	value = value.strip_edges()
	var source: String = app.source_language
	if source == "auto": source = TranslationService.detect_language(value)
	var target: String = app.target_language
	if target == "auto": target = "en" if source.begins_with("zh") else "zh-CN"
	if not valid_term(value, source):
		app.warn("请先选择一个单词或完整短语，再按 Ctrl+D 收藏；长句不会自动拆词。")
		return
	var provider: String = app.service.provider
	var key := JSON.stringify([value, source, target, provider])
	if _pending_words.has(key): return
	var job := {"word": value, "source_language": source, "target_language": target, "provider": provider, "key": key, "examples": []}
	_pending_words[key] = true
	if app.result_source_text.strip_edges() == value and app.last_source == source and app.last_target == target and app.result_provider == provider and not app.translated_text.is_empty():
		if source == "en" and target == "zh-CN" and not app.current_example.is_empty() and Metadata.matches_example(str(app.current_example.get("english", "")), value):
			job.examples = [app.current_example.duplicate(true)]
		_save_collection(job, app.translated_text)
	elif source == target:
		_save_collection(job, value)
	else:
		_collect_queue.append(job)
		if not _collecting: _run_collection_queue()

static func valid_term(value: String, language: String) -> bool:
	if value.is_empty() or value.length() > 100 or value.contains("\n") or value.contains("\r"): return false
	if language.begins_with("zh") and value.length() > 30: return false
	var whitespace := RegEx.new()
	whitespace.compile("\\s+")
	if whitespace.sub(value, " ", true).split(" ", false).size() > 12: return false
	for punctuation in ["?", "!", "。", "？", "！", ";", "；"]:
		if value.contains(punctuation): return false
	if value.contains(" ") and value.contains("."): return false
	return true

func _run_collection_queue() -> void:
	_collecting = true
	while not _collect_queue.is_empty() and not _exiting:
		var job: Dictionary = _collect_queue.pop_front()
		translation_service.provider = job.provider
		var result: Dictionary = await translation_service.translate_text(job.word, job.source_language, job.target_language)
		if _exiting: break
		if result.get("ok", false): _save_collection(job, str(result.text))
		else:
			_pending_words.erase(job.key)
			app.warn("收藏未完成：" + str(result.get("error", "请稍后重试。")))
	_collecting = false

func _save_collection(job: Dictionary, translated: String) -> void:
	var data := job.duplicate(true)
	data.translation = translated
	var result: Dictionary = store.upsert(data)
	_pending_words.erase(job.key)
	if not result.get("ok", false):
		app.warn(str(result.error))
		return
	app.warn(("已收藏：" if result.get("added", false) else "已更新收藏：") + str(job.word))
	_enrich_entry(result.entry.id)

func _enrich_entry(id: String) -> void:
	var entry: Dictionary = store.get_entry(id)
	if entry.is_empty(): return
	var identity := [entry.word, entry.source_language, entry.target_language]
	var details: Dictionary = await metadata_service.get_metadata(entry.word, entry.source_language, entry.target_language)
	if _exiting or details.is_empty(): return
	entry = store.get_entry(id)
	if entry.is_empty(): return
	if [entry.word, entry.source_language, entry.target_language] != identity: return
	var changes := {}
	if str(entry.phonetic).is_empty() and not str(details.get("phonetic", "")).is_empty(): changes.phonetic = details.phonetic
	var examples: Array = entry.examples.duplicate(true)
	for example in details.get("examples", []):
		if not examples.has(example): examples.append(example)
	if examples != entry.examples: changes.examples = examples
	if not changes.is_empty():
		var result: Dictionary = store.update_entry(id, changes)
		if not result.get("ok", false): app.warn(str(result.error))

func speak_selected(translated: bool) -> void:
	speak_entry(panel.selected_entry(), translated)

func speak_entry(entry: Dictionary, translated: bool) -> void:
	if entry.is_empty(): return
	var error: String = await app.pronunciation.speak(entry.translation if translated else entry.word, entry.target_language if translated else entry.source_language)
	if not error.is_empty(): app.warn(error)

func _on_store_changed() -> void:
	if not sync_enabled or vault_path.is_empty(): return
	if OS.get_cmdline_user_args().has("--test") and (not _test_sync_enabled or sync_backend == Sync): return
	for entry in store.entries:
		var signature := JSON.stringify(entry).sha256_text()
		if str(_sync_known.get(entry.id, "")) == signature: continue
		_sync_known[entry.id] = signature
		_sync_pending[entry.id] = entry.duplicate(true)
	for id in store.deleted_ids:
		_sync_pending[id] = {"id": id, "_delete": true}
	for id in _sync_pending.keys():
		if _current_sync_job(id).is_empty(): _sync_pending.erase(id)
	if not _sync_failed and _sync_thread == null and not _sync_pending.is_empty(): _start_sync.call_deferred()

func _current_sync_job(id: String) -> Dictionary:
	if store.deleted_ids.has(id): return {"id": id, "_delete": true}
	return store.get_entry(id)

func set_sync_enabled(enabled: bool) -> void:
	if sync_enabled == enabled: return
	sync_enabled = enabled
	_sync_generation += 1
	_sync_failed = false
	_cancel_sync_job()
	_sync_pending.clear()
	_sync_known.clear()
	if enabled: _on_store_changed()

func sync_now() -> void:
	if vault_path.is_empty():
		app.warn("请先在设置中选择 Obsidian 保管库。")
		return
	if not sync_enabled:
		app.warn("请先开启 Obsidian 自动同步。")
		return
	_sync_known.clear()
	_sync_failed = false
	_on_store_changed()
	if store.entries.is_empty() and store.deleted_ids.is_empty(): app.warn("单词本还是空的。Ctrl+D 收藏后即可同步。")

func _start_sync() -> void:
	if _exiting or _sync_thread != null or _sync_pending.is_empty(): return
	_sync_failed = false
	var batch: Array = _sync_pending.values().duplicate(true)
	_sync_pending.clear()
	var generation := _sync_generation
	_sync_thread = Thread.new()
	_sync_cancel = {"mutex": Mutex.new(), "stop": false}
	var error := _sync_thread.start(_sync_worker.bind(batch, vault_path, folder, _sync_cancel, sync_backend))
	if error != OK:
		_sync_thread = null
		_sync_failed = true
		_sync_known.clear()
		for entry in batch: _sync_pending[entry.id] = entry
		app.warn("无法启动 Obsidian 同步，请稍后重试。")
		return
	while not _exiting and _sync_thread.is_alive(): await get_tree().process_frame
	if _exiting: return
	var result: Dictionary = _sync_thread.wait_to_finish()
	_sync_thread = null
	if generation == _sync_generation:
		_sync_failed = not result.get("ok", false)
		var acknowledged: Dictionary = store.acknowledge_deletions(result.get("deleted_ids", []))
		if not acknowledged.get("ok", false):
			_sync_failed = true
			app.warn("删除已同步，保存确认记录失败：" + str(acknowledged.get("error", "请稍后重试。")))
			return
		if not result.get("ok", false):
			_sync_failed = true
			_sync_known.clear()
			for entry in batch:
				var current: Dictionary = _current_sync_job(entry.id)
				if not current.is_empty(): _sync_pending[entry.id] = current
			app.warn("Obsidian 同步未完成：" + str(result.get("error", "请稍后重试。")))
			return
		else:
			var removed: int = result.get("deleted_ids", []).size()
			app.warn("已同步到 Obsidian（%s 个词条，删除 %s 个）" % [int(result.get("count", 0)) - removed, removed])
	if not _sync_pending.is_empty(): _start_sync.call_deferred()

func _sync_worker(entries: Array, vault: String, relative_folder: String, cancellation: Dictionary, backend_script: Script) -> Dictionary:
	var backend = backend_script.new()
	var configured: Dictionary = backend.configure(vault, relative_folder)
	if not configured.get("ok", false): return configured
	var count := 0
	var removed: Array[String] = []
	for entry in entries:
		cancellation.mutex.lock()
		var stopped: bool = cancellation.stop
		cancellation.mutex.unlock()
		if stopped: return {"ok": false, "cancelled": true, "count": count, "deleted_ids": removed, "error": "同步已停止。"}
		var result: Dictionary = backend.remove_entry(str(entry.id)) if entry.get("_delete", false) else backend.sync_entry(entry)
		if not result.get("ok", false): return {"ok": false, "count": count, "deleted_ids": removed, "error": str(result.get("error", "同步失败。"))}
		if entry.get("_delete", false): removed.append(str(entry.id))
		count += 1
	return {"ok": true, "count": count, "deleted_ids": removed}

func _cancel_sync_job() -> void:
	if _sync_cancel.is_empty(): return
	_sync_cancel.mutex.lock()
	_sync_cancel.stop = true
	_sync_cancel.mutex.unlock()

func open_selected() -> void:
	open_entry(str(panel.selected_entry().get("id", "")))

func open_entry(id: String) -> void:
	if id.is_empty(): return
	if vault_path.is_empty():
		app.warn("请先在设置中选择 Obsidian 保管库。")
		return
	# Drain queued writes too: a saved entry can precede the deferred worker by
	# one frame, and successful batches can have a follow-up batch waiting.
	var generation := _sync_generation
	while not _exiting:
		if generation != _sync_generation: return
		if _sync_thread != null:
			await get_tree().process_frame
			continue
		if _sync_pending.is_empty() or _sync_failed or not sync_enabled: break
		_start_sync()
		await get_tree().process_frame
	if _exiting: return
	if _open_thread != null: return
	_open_thread = Thread.new()
	var error := _open_thread.start(_resolve_open_uri.bind(id, vault_path, folder, sync_backend))
	if error != OK:
		_open_thread = null
		app.warn("无法查找 Obsidian 笔记，请稍后重试。")
		return
	while not _exiting and _open_thread.is_alive(): await get_tree().process_frame
	if _exiting: return
	var result: Dictionary = _open_thread.wait_to_finish()
	_open_thread = null
	if generation != _sync_generation: return
	if not result.get("ok", false):
		app.warn(str(result.get("error", "无法查找 Obsidian 笔记。")))
		return
	last_open_uri = str(result.get("uri", ""))
	if last_open_uri.is_empty():
		app.warn("这个词条还未同步到 Obsidian，请在设置中执行立即同步。")
		return
	if not OS.get_cmdline_user_args().has("--test"):
		var opened := OS.shell_open(last_open_uri)
		if opened != OK: app.warn("无法打开 Obsidian，请检查它是否已安装。")

func _resolve_open_uri(id: String, vault: String, relative_folder: String, backend_script: Script) -> Dictionary:
	var backend = backend_script.new()
	var configured: Dictionary = backend.configure(vault, relative_folder)
	if not configured.get("ok", false): return configured
	if backend.has_method("resolve_uri"): return backend.resolve_uri(id)
	return {"ok": true, "uri": backend.open_uri(id)}

func choose_vault() -> void:
	if not is_instance_valid(_folder_picker):
		_folder_picker = FileDialog.new()
		_folder_picker.title = "选择 Obsidian 保管库（含 .obsidian 的文件夹）"
		_folder_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_folder_picker.access = FileDialog.ACCESS_FILESYSTEM
		_folder_picker.min_size = Vector2i(720, 480)
		app.canvas_layer.add_child(_folder_picker)
		_folder_picker.dir_selected.connect(_set_vault)
	if DirAccess.dir_exists_absolute(vault_path): _folder_picker.current_dir = vault_path
	_folder_picker.popup_centered_ratio(0.75)

func _set_vault(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path.path_join(".obsidian")):
		app.warn("请选择 Obsidian 保管库根目录，其中应有 .obsidian 文件夹。")
		return
	vault_path = path.simplify_path()
	_sync_generation += 1
	_sync_failed = false
	_cancel_sync_job()
	_sync_pending.clear()
	_sync_known.clear()
	_refresh_setting_labels()
	app._save_preferences()
	LuaSingleton.on_settings_change.emit()
	_on_store_changed()

func choose_folder() -> void:
	if not is_instance_valid(_folder_editor):
		_folder_editor = ConfirmationDialog.new()
		_folder_editor.title = "Obsidian 中的单词本文件夹"
		_folder_editor.min_size = Vector2i(620, 150)
		_folder_input = LineEdit.new()
		_folder_input.placeholder_text = "GriddyTranslate/单词本"
		_folder_editor.add_child(_folder_input)
		_folder_editor.confirmed.connect(_set_folder)
		app.canvas_layer.add_child(_folder_editor)
	_folder_input.text = folder
	_folder_editor.popup_centered()
	_folder_input.grab_focus()

func _set_folder() -> void:
	var value := _folder_input.text.strip_edges().replace("\\", "/")
	if not Sync._valid_folder(value):
		app.warn("请填写保管库内的相对文件夹路径。")
		return
	folder = value
	_sync_generation += 1
	_sync_failed = false
	_cancel_sync_job()
	_sync_pending.clear()
	_sync_known.clear()
	_refresh_setting_labels()
	app._save_preferences()
	LuaSingleton.on_settings_change.emit()
	_on_store_changed()

func _exit_tree() -> void:
	_exiting = true
	_cancel_sync_job()
	if is_instance_valid(translation_service): translation_service.cancel()
	if _sync_thread != null and _sync_thread.is_started(): _sync_thread.wait_to_finish()
	if _open_thread != null and _open_thread.is_started(): _open_thread.wait_to_finish()
