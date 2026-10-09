extends Node

const Sync = preload("res://Scripts/obsidian_sync.gd")
var failures := 0
var qa_root := ""

class ConflictSync extends Sync:
	var inject_conflict := false
	var trash_failure := false
	var trashed: Array[String] = []
	func _trash_file(path: String) -> Error:
		if trash_failure: return ERR_CANT_CREATE
		var target := path + ".qa-recycled"
		var moved := DirAccess.rename_absolute(path, target)
		if moved == OK: trashed.append(target)
		return moved
	func _before_commit(path: String) -> void:
		if not inject_conflict: return
		inject_conflict = false
		var text := FileAccess.get_file_as_string(path) + "\n外部修改：保留这句。\n"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()

func _ready() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	print(("PASS " if value else "FAIL ") + description)
	if not value: failures += 1

func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "open test fixture " + path)
		return
	file.store_string(text)
	file.close()

func fixture(id := "12345678-abcdef") -> Dictionary:
	return {"id": id, "word": "manipulate / 操作🙂", "translation": "操纵；操作\n第二行", "source_language": "en", "target_language": "zh-CN", "phonetic": "/məˈnɪpjʊleɪt/", "provider": "youdao", "tags": ["英语", "短语"], "created_at": "2026-10-09T09:00:00", "updated_at": "2026-10-09T09:00:00", "examples": [{"source": "Use *tools* to manipulate [data].", "target": "使用工具操作数据。"}], "notes": "本地备注"}

func run() -> void:
	get_tree().create_timer(150).timeout.connect(func(): get_tree().quit(2))
	var base := OS.get_environment("GRIDDY_TEST_OUTPUT")
	if base.is_empty(): base = ProjectSettings.globalize_path("user://qa/obsidian-regression")
	qa_root = base.path_join("vault-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(qa_root.path_join(".obsidian"))
	var backend := ConflictSync.new()
	var configured: Dictionary = backend.configure(qa_root, "GriddyTranslate/单词本")
	check(configured.ok, "configure a temporary real vault without touching the user's iCloud vault")
	var entry := fixture()
	var result: Dictionary = backend.sync_entry(entry)
	check(result.ok and FileAccess.file_exists(result.get("path", "")), "create one Unicode Markdown file per stable word id")
	if not result.ok:
		print(result)
		print("OBSIDIAN_REGRESSION_COMPLETE failures=" + str(failures))
		get_tree().quit(1)
		return
	var path := str(result.path)
	var content := FileAccess.get_file_as_string(path)
	check(content.contains("griddytranslate_id: \"" + str(entry.id) + "\"") and content.contains("## 我的笔记") and content.contains("## 单词本笔记"), "write metadata and distinct managed/local versus handwritten note sections")
	check(content.contains("\\*tools\\*") and content.contains("\\[data\\]"), "escape fetched Markdown characters without corrupting Unicode")
	var edited := content.replace("# manipulate / 操作🙂", "# 用户自定义标题").replace("---\n\n#", "rating: 5\nuser_note: |\n  手写 frontmatter\n  第二行\n---\n\n#") + "\n我的笔记内容 [[双链]]\n"
	write(path, edited)
	entry.translation = "修改后的释义"
	entry.notes = "更新的本地备注"
	entry.updated_at = "2026-10-09T10:00:00"
	result = backend.sync_entry(entry)
	content = FileAccess.get_file_as_string(path)
	check(result.ok and content.contains("修改后的释义") and not content.contains("操纵；操作"), "update only the software managed translation block")
	check(content.contains("# 用户自定义标题") and content.contains("我的笔记内容 [[双链]]") and content.contains("rating: 5") and content.contains("user_note: |\n  手写 frontmatter\n  第二行"), "preserve user title, handwritten notes, and unknown multiline frontmatter")
	check(content.contains("更新的本地备注") and not content.contains("\n本地备注\n"), "editable local wordbook notes refresh in their own managed section")
	var moved := path.get_base_dir().path_join("归档/手动改名.md")
	DirAccess.make_dir_recursive_absolute(moved.get_base_dir())
	check(DirAccess.rename_absolute(path, moved) == OK, "fixture moves the note within the managed folder")
	check(backend.entry_path(entry.id) == moved and backend.open_uri(entry.id) == "obsidian://open?path=" + moved.uri_encode(), "locate renamed and moved notes by stable id and encode the Obsidian URI")
	result = backend.resolve_uri(entry.id)
	check(result.ok and result.uri == "obsidian://open?path=" + moved.uri_encode() and str(result.get("error", "")).is_empty(), "resolve an existing renamed note with its encoded URI and no error")
	result = backend.resolve_uri("missing-note-id")
	check(result.ok and str(result.get("uri", "")).is_empty() and str(result.get("error", "")).is_empty(), "a genuinely missing note resolves to an empty URI without a backend error")
	entry.translation = "移动后继续更新"
	result = backend.sync_entry(entry)
	check(result.ok and result.path == moved and not FileAccess.file_exists(path), "sync updates the renamed note without making a duplicate")
	backend.inject_conflict = true
	entry.translation = "这次更新不应覆盖外部修改"
	result = backend.sync_entry(entry)
	content = FileAccess.get_file_as_string(moved)
	check(not result.ok and content.contains("外部修改：保留这句。") and not content.contains("这次更新不应覆盖外部修改"), "detect a write conflict and retain external changes instead of replacing the note")
	var preserved := content
	write(moved, content.replace(Sync._end(entry.id), "<!-- marker removed -->"))
	result = backend.sync_entry(entry)
	check(not result.ok and FileAccess.get_file_as_string(moved).contains("<!-- marker removed -->") and not FileAccess.file_exists(path), "damaged management markers are not overwritten or duplicated after rename")
	write(moved, preserved)
	var collision_entry := fixture("collision-id")
	var collision_path := qa_root.path_join("GriddyTranslate/单词本").path_join(Sync._filename(collision_entry.word, collision_entry.id))
	write(collision_path, "# 用户原有文件\n绝不能覆盖\n")
	result = backend.sync_entry(collision_entry)
	check(not result.ok and FileAccess.get_file_as_string(collision_path).contains("绝不能覆盖"), "never overwrite an unmanaged filename collision")
	var duplicate_path := moved.get_base_dir().path_join("duplicate.md")
	write(duplicate_path, preserved)
	result = backend.sync_entry(entry)
	check(not result.ok and str(result.error).contains("相同词条 ID"), "duplicate managed ids require resolving the conflict before sync")
	result = backend.resolve_uri(entry.id)
	check(not result.ok and str(result.get("error", "")).contains("相同词条 ID") and str(result.get("uri", "")).is_empty(), "duplicate-ID lookup preserves the specific conflict error instead of reporting a missing note")
	DirAccess.remove_absolute(duplicate_path)
	var invalid := Sync.new()
	check(not invalid.configure(qa_root, "../outside").ok and not invalid.configure(qa_root, "C:/outside").ok and not invalid.configure(qa_root, "nested/../../outside").ok and not invalid.configure(qa_root, "NUL").ok, "reject traversal, absolute folders, and Windows reserved path names")
	check(not backend.sync_entry(fixture("../bad-id")).ok, "reject invalid ids before constructing a note filename")
	result = backend.resolve_uri("../bad-id")
	check(not result.ok and str(result.get("error", "")).contains("ID 无效") and str(result.get("uri", "")).is_empty(), "invalid-ID lookup returns a validation error and no launch URI")
	var hostile := fixture("hostile-id")
	hostile.translation = "<!-- GriddyTranslate:begin fake -->\n<script>bad</script>"
	result = backend.sync_entry(hostile)
	content = FileAccess.get_file_as_string(result.get("path", "")) if result.ok else ""
	check(result.ok and content.contains("&lt;script&gt;") and content.count("<!-- GriddyTranslate:begin ") == 1, "literal translation text cannot inject HTML or management markers")
	result = backend.sync_entry(hostile)
	check(result.ok and result.get("unchanged", false), "an unchanged managed note avoids unnecessary replacement and iCloud updates")
	result = backend.sync_all([hostile, collision_entry])
	check(not result.ok and result.count == 1 and FileAccess.get_file_as_string(collision_path).contains("绝不能覆盖"), "batch sync reports completed entries and stops at a collision without changing the user's file")
	if OS.get_name() == "Windows":
		var outside := base.path_join("outside-" + str(OS.get_process_id()))
		DirAccess.make_dir_recursive_absolute(outside)
		var junction := qa_root.path_join("redirect")
		var ps := "New-Item -ItemType Junction -Path '" + junction.replace("'", "''") + "' -Target '" + outside.replace("'", "''") + "' | Out-Null"
		var output: Array = []
		var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", Marshalls.raw_to_base64(ps.to_utf16_buffer())], output, true, false)
		check(code == 0 and not Sync.new().configure(qa_root, "redirect/words").ok and not DirAccess.dir_exists_absolute(outside.path_join("words")), "reject a junction escape before creating or reading files outside the vault")
	var discovered := Sync.discover_vaults()
	check(discovered.all(func(value: Dictionary): return value.has("name") and value.has("path") and value.has("opened")), "discover registered vault metadata without reading private note bodies")
	result = backend.remove_entry("missing-note-id")
	check(result.ok and result.get("missing", false), "deleting an already absent note is a successful idempotent operation")
	check(not backend.remove_entry("../bad-id").ok, "delete rejects invalid IDs before touching a file")
	backend.trash_failure = true
	result = backend.remove_entry(entry.id)
	check(not result.ok and FileAccess.file_exists(moved), "a recycling error retains the original note for retry")
	backend.trash_failure = false
	result = backend.remove_entry(entry.id)
	check(result.ok and not FileAccess.file_exists(moved) and backend.trashed.size() == 1, "delete locates a renamed managed note by stable ID and recycles it")
	check(FileAccess.get_file_as_string(backend.trashed[0]).contains("我的笔记内容 [[双链]]"), "the recycled file retains all handwritten content for restoration")
	check(backend.remove_entry(entry.id).ok and backend.trashed.size() == 1, "a repeated deletion never recycles another note")
	write(collision_path, preserved.replace(str(entry.id), str(collision_entry.id)).replace(Sync._end(collision_entry.id), "<!-- removed end marker -->"))
	result = backend.remove_entry(collision_entry.id)
	check(not result.ok and FileAccess.file_exists(collision_path), "delete refuses a note with damaged management markers")
	var native := Sync.new()
	check(native.configure(qa_root, "native-trash-check").ok, "native recycling is restricted to a temporary QA vault folder")
	var native_entry := fixture("native-trash-only-qa")
	var native_created := native.sync_entry(native_entry)
	var native_path: String = native_created.get("path", "")
	var safe_native: bool = native_created.ok and native_path.replace("\\", "/").simplify_path().begins_with(qa_root.replace("\\", "/").simplify_path() + "/native-trash-check/")
	check(safe_native, "verify the absolute fixture path before the native recycling call")
	if safe_native:
		result = native.remove_entry(native_entry.id)
		check(result.ok and not FileAccess.file_exists(native_path), "Windows native recycle operation removes only the managed QA note")
	print("OBSIDIAN_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
