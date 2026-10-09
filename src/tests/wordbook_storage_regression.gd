extends Node

const Store = preload("res://Scripts/wordbook_store.gd")
var failures := 0
var directory := ""

func _ready() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value:
		failures += 1

func run() -> void:
	directory = ProjectSettings.globalize_path("user://qa/wordbook-storage-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_msec()))
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "wordbook test uses an isolated writable directory")
	test_crud_merge_and_reload()
	test_corruption_protection()
	test_write_failure()
	test_interrupted_commit_recovery()
	test_invalid_payloads()
	test_persistent_deletions()
	print("WORDBOOK_STORAGE_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)

func test_persistent_deletions() -> void:
	var store := make_store("deletion-queue")
	var result: Dictionary = store.upsert(data("offline deletion"))
	check(result.ok, "create a deletion persistence fixture")
	var id: String = result.entry.id
	check(store.remove_entry(id).ok and store.deleted_ids == [id], "deletion saves a tombstone with the local removal")
	var reloaded := make_store("deletion-queue")
	check(reloaded.load_book().ok and reloaded.entries.is_empty() and reloaded.deleted_ids == [id], "pending deletion survives a restart even when the wordbook is empty")
	check(reloaded.upsert(data("another word")).ok and reloaded.deleted_ids == [id], "subsequent edits cannot discard an offline deletion")
	check(reloaded.acknowledge_deletions([id]).ok and reloaded.deleted_ids.is_empty(), "only a completed remote deletion clears its persisted tombstone")
	var final_store := make_store("deletion-queue")
	check(final_store.load_book().ok and final_store.deleted_ids.is_empty() and final_store.entries.size() == 1, "confirmed deletions do not return after restart")
	var legacy := make_store("legacy-deletion")
	result = legacy.upsert(data("legacy removed word"))
	var legacy_id: String = result.entry.id
	var before: Dictionary = JSON.parse_string(read_text(legacy.storage_path))
	before.version = 1
	before.erase("deleted_ids")
	write_text(legacy.storage_path + ".bak", JSON.stringify(before))
	write_text(legacy.storage_path, JSON.stringify({"version": 1, "entries": []}))
	check(legacy.load_book().ok and legacy.deleted_ids == [legacy_id], "the latest saved deletion from a valid legacy backup is carried into sync")
	var invalid := make_store("bad-deletion")
	write_text(invalid.storage_path, JSON.stringify({"version": 2, "entries": [], "deleted_ids": [32]}))
	check(not invalid.load_book().ok and not invalid.upsert(data()).ok, "invalid deletion records block writes instead of silently dropping pending work")

func make_store(name: String) -> Node:
	var store := Store.new()
	store.storage_path = directory.path_join(name + ".json")
	add_child(store)
	return store

func data(word: String = "manipulate") -> Dictionary:
	return {"word": word, "translation": "操纵；操作", "source_language": "en", "target_language": "zh-CN", "phonetic": "/məˈnɪpjʊleɪt/", "provider": "youdao", "examples": [{"english": "They manipulate the data.", "chinese": "他们操纵数据。"}], "tags": ["英语", "动词"], "notes": "自己的学习笔记 ✨"}

func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func test_crud_merge_and_reload() -> void:
	var store := make_store("crud")
	var loads: Dictionary = store.load_book()
	check(loads.ok and store.entries.is_empty(), "empty wordbook loads without creating a file")
	check(not FileAccess.file_exists(store.storage_path), "no input is persisted before the user collects a word")
	var result: Dictionary = store.upsert(data())
	check(result.ok and result.added and store.entries.size() == 1, "collect adds an entry")
	if not result.ok:
		return
	var id: String = result.entry.id
	check(id.length() == 32 and result.entry.created_at.ends_with("Z"), "entry has a stable random ID and UTC timestamps")
	var existing: Dictionary = store.get_entry(id)
	existing.translation = "outside mutation"
	check(store.get_entry(id).translation == "操纵；操作", "get_entry does not expose mutable stored dictionaries")
	var repeated := data("  manipulate  ")
	repeated.translation = "熟练地操作"
	repeated.notes = "不要替换我的笔记"
	repeated.tags = ["动词", "收藏"]
	repeated.examples.append({"english": "She can manipulate the device.", "chinese": "她能操作设备。"})
	result = store.upsert(repeated)
	check(result.ok and not result.added and result.entry.id == id and store.entries.size() == 1, "same complete phrase and language pair merge into the existing ID")
	check(result.entry.notes == "自己的学习笔记 ✨" and result.entry.tags == ["英语", "动词", "收藏"], "repeat collection preserves handwritten notes and merges tags")
	check(result.entry.examples.size() == 2 and result.entry.translation == "熟练地操作", "repeat collection merges examples without duplicates and refreshes the translation")
	check(FileAccess.file_exists(store.storage_path + ".bak"), "a successful replacement retains the previous revision backup")
	result = store.update_entry(id, {"translation": "控制", "tags": ["复习", "复习"], "notes": "编辑后的笔记\n第二行"})
	check(result.ok and result.entry.notes == "编辑后的笔记\n第二行" and result.entry.tags == ["复习"], "explicit editing updates notes, translation and tags")
	check(store.upsert(data("Manipulate")).ok and store.entries.size() == 2, "identity preserves case-sensitive word meaning")
	var another_language := data()
	another_language.target_language = "ja"
	check(store.upsert(another_language).ok and store.entries.size() == 3, "same word in another language pair has its own entry")
	check(store.upsert(data("take care of")).ok and store.find_entry("take care of", "en", "zh-CN").word == "take care of", "complete phrases are stored without choosing a constituent word")
	check(store.upsert(data("😀 中文 é 日本語")).ok, "Unicode text and emoji survive collection")
	var reload := make_store("crud")
	loads = reload.load_book()
	check(loads.ok and reload.entries == store.entries, "all saved fields reload exactly from UTF-8 JSON")
	result = reload.update_entry(id, {"id": "replacement", "created_at": "replacement"})
	check(result.ok and result.entry.id == id and result.entry.created_at == store.get_entry(id).created_at, "editing cannot replace stable IDs or creation timestamps")
	result = reload.update_entry(id, {"word": "Manipulate"})
	check(not result.ok and reload.get_entry(id).word == "manipulate", "editing into an existing identity is rejected without losing either entry")
	var before: int = reload.entries.size()
	result = reload.remove_entry(id)
	check(result.ok and result.entry.id == id and reload.entries.size() == before - 1 and reload.get_entry(id).is_empty(), "deletion removes exactly the selected entry")
	check(not reload.remove_entry(id).ok and not reload.update_entry(id, {"translation": "x"}).ok, "operations on missing IDs return an error")
	store.queue_free()
	reload.queue_free()

func test_corruption_protection() -> void:
	var store := make_store("corrupt")
	check(store.upsert(data()).ok, "corruption fixture saved")
	check(store.upsert(data("valid second word")).ok, "corruption fixture has a valid backup")
	var before: Array = store.entries.duplicate(true)
	var broken := "{\"version\":1,\"entries\":[ truncated 💥"
	write_text(store.storage_path, broken)
	var result: Dictionary = store.load_book()
	check(not result.ok and not str(result.error).is_empty(), "malformed JSON is reported instead of silently resetting the collection")
	check(read_text(store.storage_path) == broken and store.entries == before, "failed load retains both the original damaged file and previous memory")
	check(not store.upsert(data("must not overwrite")).ok and read_text(store.storage_path) == broken, "corrupt collection blocks writes even when a valid backup exists")
	var running := make_store("corrupt-running")
	check(running.upsert(data()).ok, "live-corruption fixture saved")
	before = running.entries.duplicate(true)
	write_text(running.storage_path, broken)
	check(not running.upsert(data("new word")).ok and running.entries == before and read_text(running.storage_path) == broken, "external corruption after load is also protected from overwrite")
	store.queue_free()
	running.queue_free()

func test_write_failure() -> void:
	var store := make_store("blocked")
	check(store.load_book().ok, "write-failure fixture starts empty")
	check(DirAccess.make_dir_recursive_absolute(store.storage_path) == OK, "a directory intentionally blocks the file destination")
	var result: Dictionary = store.upsert(data())
	check(not result.ok and not str(result.error).is_empty() and store.entries.is_empty(), "failed disk write leaves memory unchanged and returns a useful error")
	check(not FileAccess.file_exists(store.storage_path + ".bak"), "failed first save creates no misleading backup")
	store.queue_free()

func test_interrupted_commit_recovery() -> void:
	var store := make_store("interrupted")
	var result: Dictionary = store.upsert(data())
	check(result.ok, "interrupted-commit fixture saved")
	var id: String = result.entry.id
	check(DirAccess.rename_absolute(store.storage_path, store.storage_path + ".rollback") == OK, "simulate interruption after moving the original aside")
	var reload := make_store("interrupted")
	result = reload.load_book()
	check(result.ok and result.recovered and reload.get_entry(id).word == "manipulate", "interrupted save recovers the intact original rollback file")
	check(reload.upsert(data("recovered new word")).ok and FileAccess.file_exists(reload.storage_path) and FileAccess.file_exists(reload.storage_path + ".bak"), "saving after recovery restores the main file and preserves the old collection as backup")
	var backup := make_store("backup-only")
	check(backup.upsert(data()).ok and backup.upsert(data("second")).ok, "backup-only recovery fixture saved")
	check(DirAccess.remove_absolute(backup.storage_path) == OK, "simulate a missing main file with an intact backup")
	result = backup.load_book()
	check(result.ok and result.recovered and backup.entries.size() == 1, "missing main file can load the previous valid backup with a recovery indication")
	store.queue_free()
	reload.queue_free()
	backup.queue_free()

func test_invalid_payloads() -> void:
	var store := make_store("invalid")
	var value := data()
	value.word = "  "
	check(not store.upsert(value).ok and not FileAccess.file_exists(store.storage_path), "empty words are rejected before any save")
	value = data()
	value.tags = [42]
	check(not store.upsert(value).ok and store.entries.is_empty(), "invalid tags do not corrupt persisted entries")
	value = data()
	value.examples = [{"english": 42}]
	check(not store.upsert(value).ok, "invalid examples are rejected")
	value = data()
	value.target_language = ""
	check(not store.upsert(value).ok, "entries require both languages")
	write_text(store.storage_path, '{"version":999,"entries":[]}')
	check(not store.load_book().ok and not store.upsert(data()).ok, "unknown file versions are preserved without downgrade overwrite")
	store.queue_free()
