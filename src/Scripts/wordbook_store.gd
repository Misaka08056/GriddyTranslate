extends Node

signal changed

const DEFAULT_STORAGE_PATH := "user://wordbook.json"
const FORMAT_VERSION := 2
const TEXT_FIELDS := ["word", "translation", "source_language", "target_language", "phonetic", "provider", "notes"]

var entries: Array[Dictionary] = []
var deleted_ids: Array[String] = []
var storage_path := DEFAULT_STORAGE_PATH
var _loaded := false
var _load_blocked := false
var _last_error := ""

func _ready() -> void:
	_isolate_test_storage()

func _isolate_test_storage() -> void:
	if storage_path == DEFAULT_STORAGE_PATH and OS.get_cmdline_user_args().has("--test"):
		storage_path = "user://qa/wordbook-test-session-" + str(OS.get_process_id()) + ".json"

func load_book() -> Dictionary:
	_isolate_test_storage()
	_loaded = true
	_load_blocked = false
	_last_error = ""
	var path := ProjectSettings.globalize_path(storage_path)
	var recovered := false
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".rollback"):
			path += ".rollback"
		elif FileAccess.file_exists(path + ".bak"):
			path += ".bak"
		else:
			entries = []
			deleted_ids = []
			changed.emit()
			return {"ok": true, "count": 0, "error": ""}
		recovered = true
	var result := _read_file(path)
	if not result.ok:
		_load_blocked = true
		_last_error = str(result.error)
		return {"ok": false, "error": _last_error, "path": path, "backup_path": ProjectSettings.globalize_path(storage_path) + ".bak"}
	entries = _copy_entries(result.entries)
	deleted_ids.assign(result.deleted_ids)
	# The previous release did not record deletions. Its intact last-save backup
	# can identify that one saved deletion without sweeping unrelated vault notes.
	if result.version == 1 and not recovered:
		var backup_path := ProjectSettings.globalize_path(storage_path) + ".bak"
		if FileAccess.file_exists(backup_path):
			var previous := _read_file(backup_path)
			if previous.ok and previous.entries.size() == entries.size() + 1:
				var removed: Array[String] = []
				var unchanged := true
				for entry in previous.entries:
					var current := get_entry(str(entry.id))
					if current.is_empty(): removed.append(str(entry.id))
					elif current != entry: unchanged = false
				if unchanged and removed.size() == 1: deleted_ids.append(removed[0])
	changed.emit()
	return {"ok": true, "count": entries.size(), "error": "", "recovered": recovered}

func get_entry(id: String) -> Dictionary:
	for entry in entries:
		if entry.id == id:
			return entry.duplicate(true)
	return {}

func find_entry(word: String, source: String, target: String) -> Dictionary:
	var key := _identity(word, source, target)
	for entry in entries:
		if _identity(entry.word, entry.source_language, entry.target_language) == key:
			return entry.duplicate(true)
	return {}

func upsert(data: Dictionary) -> Dictionary:
	var ready := _ensure_loaded()
	if not ready.ok:
		return ready
	var normalized := _normalize_entry(data, false)
	if not normalized.ok:
		return normalized
	var incoming: Dictionary = normalized.entry
	var next := _copy_entries(entries)
	var existing := find_entry(incoming.word, incoming.source_language, incoming.target_language)
	var entry: Dictionary
	var added := existing.is_empty()
	if added:
		entry = incoming
		entry.id = _new_id()
		entry.created_at = _timestamp()
	else:
		entry = existing
		# Repeated collection can refresh fetched details, but cannot erase a user's notes.
		for field in ["translation", "phonetic", "provider"]:
			if not str(incoming[field]).is_empty():
				entry[field] = incoming[field]
		entry.examples = _merge_examples(entry.examples, incoming.examples)
		entry.tags = _merge_tags(entry.tags, incoming.tags)
	entry.updated_at = _timestamp()
	if added:
		next.append(entry)
	else:
		for index in range(next.size()):
			if next[index].id == entry.id:
				next[index] = entry
				break
	var saved := _commit(next)
	if not saved.ok:
		return saved
	return {"ok": true, "entry": entry.duplicate(true), "added": added, "error": ""}

func update_entry(id: String, changes: Dictionary) -> Dictionary:
	var ready := _ensure_loaded()
	if not ready.ok:
		return ready
	var entry := get_entry(id)
	if entry.is_empty():
		return _error("找不到这个词条。")
	for field in TEXT_FIELDS + ["examples", "tags"]:
		if changes.has(field):
			entry[field] = changes[field]
	var normalized := _normalize_entry(entry, true)
	if not normalized.ok:
		return normalized
	entry = normalized.entry
	var duplicate := find_entry(entry.word, entry.source_language, entry.target_language)
	if not duplicate.is_empty() and duplicate.id != id:
		return _error("同一语言对中已经有这个词条。")
	entry.updated_at = _timestamp()
	var next := _copy_entries(entries)
	for index in range(next.size()):
		if next[index].id == id:
			next[index] = entry
			break
	var saved := _commit(next)
	if not saved.ok:
		return saved
	return {"ok": true, "entry": entry.duplicate(true), "error": ""}

func remove_entry(id: String) -> Dictionary:
	var ready := _ensure_loaded()
	if not ready.ok:
		return ready
	var entry := get_entry(id)
	if entry.is_empty():
		return _error("找不到这个词条。")
	var next := _copy_entries(entries)
	for index in range(next.size()):
		if next[index].id == id:
			next.remove_at(index)
			break
	var deletions := deleted_ids.duplicate()
	if not deletions.has(id): deletions.append(id)
	var saved := _commit(next, deletions)
	if not saved.ok:
		return saved
	return {"ok": true, "entry": entry, "error": ""}

func acknowledge_deletions(ids: Array) -> Dictionary:
	var ready := _ensure_loaded()
	if not ready.ok: return ready
	var remaining := deleted_ids.duplicate()
	for id in ids: remaining.erase(str(id))
	if remaining == deleted_ids: return {"ok": true, "error": ""}
	return _commit(_copy_entries(entries), remaining)

func _ensure_loaded() -> Dictionary:
	if not _loaded:
		var result := load_book()
		if not result.ok:
			return result
	if _load_blocked:
		return _error(_last_error)
	return {"ok": true}

func _normalize_entry(data: Dictionary, existing: bool) -> Dictionary:
	var entry := {}
	for field in TEXT_FIELDS:
		var value: Variant = data.get(field, "")
		if not value is String:
			return _error("词条字段格式错误：" + field)
		entry[field] = value
	entry.word = str(entry.word).strip_edges()
	entry.source_language = str(entry.source_language).strip_edges()
	entry.target_language = str(entry.target_language).strip_edges()
	if entry.word.is_empty():
		return _error("请先选择或输入要收藏的单词或短语。")
	if entry.source_language.is_empty() or entry.target_language.is_empty():
		return _error("词条缺少原文或译文语言。")
	var examples_value: Variant = data.get("examples", [])
	var tags_value: Variant = data.get("tags", [])
	if not examples_value is Array or not tags_value is Array:
		return _error("词条例句或标签格式错误。")
	var examples: Array[Dictionary] = []
	for example in examples_value:
		if not example is Dictionary or not example.get("english", "") is String or not example.get("chinese", "") is String:
			return _error("词条例句格式错误。")
		var clean := {"english": str(example.get("english", "")).strip_edges(), "chinese": str(example.get("chinese", "")).strip_edges()}
		if not clean.english.is_empty() or not clean.chinese.is_empty():
			if not examples.has(clean):
				examples.append(clean)
	var tags: Array[String] = []
	for tag in tags_value:
		if not tag is String:
			return _error("词条标签格式错误。")
		var clean_tag := str(tag).strip_edges()
		if not clean_tag.is_empty() and not tags.has(clean_tag):
			tags.append(clean_tag)
	entry.examples = examples
	entry.tags = tags
	if existing:
		for field in ["id", "created_at", "updated_at"]:
			if not data.get(field, "") is String or str(data.get(field, "")).is_empty():
				return _error("词条标识或时间格式错误：" + field)
			entry[field] = data[field]
	return {"ok": true, "entry": entry, "error": ""}

func _read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("无法读取单词本，原文件已保留：" + path)
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK:
		return _error("单词本文件损坏，已停止写入并保留原文件：" + path)
	var value: Variant = json.data
	if not value is Dictionary or (value.get("version", 0) != 1 and value.get("version", 0) != FORMAT_VERSION) or not value.get("entries", null) is Array:
		return _error("单词本版本或结构不兼容，原文件已保留：" + path)
	var loaded: Array[Dictionary] = []
	var ids := {}
	var identities := {}
	for data in value.entries:
		if not data is Dictionary:
			return _error("单词本词条格式损坏，原文件已保留：" + path)
		var result := _normalize_entry(data, true)
		if not result.ok:
			return _error("单词本词条格式损坏，原文件已保留：" + path)
		var entry: Dictionary = result.entry
		var identity := _identity(entry.word, entry.source_language, entry.target_language)
		if ids.has(entry.id) or identities.has(identity):
			return _error("单词本出现重复标识或词条，原文件已保留：" + path)
		ids[entry.id] = true
		identities[identity] = true
		loaded.append(entry)
	var deletions_value: Variant = value.get("deleted_ids", [])
	if not deletions_value is Array: return _error("单词本删除记录损坏，原文件已保留：" + path)
	var deletions: Array[String] = []
	for id in deletions_value:
		if not id is String or str(id).is_empty() or ids.has(id) or deletions.has(id):
			return _error("单词本删除记录损坏，原文件已保留：" + path)
		deletions.append(id)
	return {"ok": true, "entries": loaded, "deleted_ids": deletions, "version": value.version, "error": ""}

func _commit(next: Array[Dictionary], pending_deletions: Variant = null) -> Dictionary:
	var next_deleted: Array = deleted_ids.duplicate() if pending_deletions == null else pending_deletions
	var path := ProjectSettings.globalize_path(storage_path)
	if FileAccess.file_exists(path) and not _read_file(path).ok:
		_load_blocked = true
		_last_error = "单词本文件在运行期间被修改或损坏，已停止写入并保留原文件：" + path
		return _error(_last_error)
	var directory_result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_result != OK:
		return _error("无法创建单词本保存文件夹。")
	var temporary := path + ".tmp-" + _new_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("无法写入单词本，现有词条未改变。")
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "entries": next, "deleted_ids": next_deleted}, "\t", false))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("单词本写入失败，现有词条未改变。")
	# Validate the finished temporary file before replacing a user's collection.
	if not _read_file(temporary).ok:
		DirAccess.remove_absolute(temporary)
		return _error("单词本保存校验失败，现有词条未改变。")
	var backup := path + ".bak"
	var rollback := path + ".rollback"
	var had_original := FileAccess.file_exists(path)
	if had_original:
		if FileAccess.file_exists(rollback):
			# A valid current file means a previous commit finished. Keep its recovery
			# copy as the backup before beginning another replacement.
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				DirAccess.remove_absolute(temporary)
				return _error("无法更新单词本备份，现有词条未改变。")
			if DirAccess.rename_absolute(rollback, backup) != OK:
				DirAccess.remove_absolute(temporary)
				return _error("无法保留单词本恢复备份，现有词条未改变。")
		# Retain the old backup until the new file has been committed successfully.
		if DirAccess.rename_absolute(path, rollback) != OK:
			DirAccess.remove_absolute(temporary)
			return _error("无法替换单词本文件，现有词条未改变。")
	if DirAccess.rename_absolute(temporary, path) != OK:
		if had_original:
			DirAccess.rename_absolute(rollback, path)
		DirAccess.remove_absolute(temporary)
		return _error("单词本保存失败，现有词条未改变。")
	if FileAccess.file_exists(rollback):
		# If replacing the backup fails, the rollback copy remains available for recovery.
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(rollback, backup)
	entries = _copy_entries(next)
	deleted_ids.assign(next_deleted)
	changed.emit()
	return {"ok": true, "error": ""}

func _copy_entries(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in values:
		result.append(value.duplicate(true))
	return result

func _identity(word: String, source: String, target: String) -> String:
	return JSON.stringify([word.strip_edges(), source.strip_edges(), target.strip_edges()])

func _merge_examples(previous: Array, incoming: Array) -> Array:
	var result := previous.duplicate(true)
	for example in incoming:
		if not result.has(example):
			result.append(example.duplicate(true))
	return result

func _merge_tags(previous: Array, incoming: Array) -> Array:
	var result := previous.duplicate()
	for tag in incoming:
		if not result.has(tag):
			result.append(tag)
	return result

func _new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _timestamp() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"

func _error(message: String) -> Dictionary:
	return {"ok": false, "entry": {}, "error": message}
