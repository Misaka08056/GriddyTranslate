extends RefCounted

# Notes are local Markdown files. All writes stay below the configured managed
# folder; neither a missing vault nor a malformed note is silently replaced.
var vault_path := ""
var folder := "GriddyTranslate/单词本"
var _configured := false
var _index: Dictionary = {}
var _index_error := ""

const MANAGED_FIELDS := ["griddytranslate_id", "word", "source_language", "target_language", "phonetic", "translation_source", "created_at", "updated_at", "griddytranslate_tags"]

static func discover_vaults() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var appdata := OS.get_environment("APPDATA")
	if appdata.is_empty(): return found
	var config_path := appdata.path_join("obsidian/obsidian.json")
	if not FileAccess.file_exists(config_path): return found
	var config = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not config is Dictionary or not config.get("vaults", {}) is Dictionary: return found
	for value in config.vaults.values():
		if not value is Dictionary: continue
		var path := str(value.get("path", "")).replace("\\", "/").simplify_path()
		if not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path): continue
		found.append({"name": path.get_file(), "path": path, "opened": bool(value.get("open", false)), "timestamp": int(value.get("ts", 0))})
	found.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.opened != b.opened: return a.opened
		return a.timestamp > b.timestamp)
	return found

func configure(vault: String, relative_folder: String) -> Dictionary:
	_configured = false
	_index.clear()
	var normalized := vault.strip_edges().replace("\\", "/")
	if normalized.is_empty() or not normalized.is_absolute_path() or normalized.begins_with("res:") or normalized.begins_with("user:"):
		return _error("请选择 Obsidian 保管库的完整文件夹路径。")
	normalized = normalized.simplify_path().trim_suffix("/")
	if not DirAccess.dir_exists_absolute(normalized) or not DirAccess.dir_exists_absolute(normalized.path_join(".obsidian")):
		return _error("此文件夹不是可访问的 Obsidian 保管库（缺少 .obsidian）。")
	var normalized_folder := relative_folder.strip_edges().replace("\\", "/").trim_suffix("/")
	if not _valid_folder(normalized_folder): return _error("单词本文件夹必须位于保管库内，不能使用绝对路径或 ..。")
	vault_path = normalized
	folder = normalized_folder
	var guard := _guard_path(_managed_root())
	if not guard.ok: return guard
	_configured = true
	return {"ok": true, "error": "", "path": _managed_root()}

func sync_entry(entry: Dictionary) -> Dictionary:
	if not _configured: return _error("请先在设置中选择 Obsidian 保管库。")
	var id := str(entry.get("id", ""))
	if not _valid_id(id): return _error("词条 ID 无效，未写入 Obsidian。")
	var word := str(entry.get("word", entry.get("original", ""))).strip_edges()
	if word.is_empty(): return _error("空词条不能同步。")
	var guard := _guard_path(_managed_root())
	if not guard.ok: return guard
	var create_error := DirAccess.make_dir_recursive_absolute(_managed_root())
	if create_error != OK: return _error("无法创建 Obsidian 单词本文件夹：" + error_string(create_error))
	guard = _guard_path(_managed_root())
	if not guard.ok: return guard
	_rebuild_index()
	if not _index_error.is_empty(): return _error(_index_error)
	var path: String = str(_index.get(id, ""))
	if path.is_empty(): path = _managed_root().path_join(_filename(word, id))
	guard = _guard_path(path)
	if not guard.ok: return guard
	var existed := FileAccess.file_exists(path)
	var before := ""
	if existed:
		var old_file := FileAccess.open(path, FileAccess.READ)
		if old_file == null: return _error("无法读取现有 Obsidian 笔记。", path)
		before = old_file.get_as_text()
		old_file.close()
		if _note_id(before) != id or not _has_block(before, id):
			return _error("同名文件不是此词条的受管理笔记，已保留原文件。", path)
	var rendered := _render_note(entry, before)
	if not rendered.ok: return _error(str(rendered.error), path)
	if existed and str(rendered.text) == before:
		_index[id] = path
		return {"ok": true, "path": path, "error": "", "unchanged": true}
	var result := _atomic_write(path, str(rendered.text), existed, before.sha256_text())
	if result.ok: _index[id] = path
	return result

func remove_entry(id: String) -> Dictionary:
	if not _configured: return _error("请先在设置中选择 Obsidian 保管库。")
	if not _valid_id(id): return _error("词条 ID 无效，未删除 Obsidian 笔记。")
	_rebuild_index()
	if not _index_error.is_empty(): return _error(_index_error)
	var path := str(_index.get(id, ""))
	if path.is_empty(): return {"ok": true, "missing": true, "error": ""}
	var guard := _guard_path(path)
	if not guard.ok: return guard
	var content := FileAccess.get_file_as_string(path)
	if _note_id(content) != id or not _has_block(content, id):
		return _error("笔记管理标记缺失或损坏，未删除 Obsidian 文件。", path)
	var result := _trash_file(path)
	if result != OK: return _error("无法将 Obsidian 笔记移到回收站，请检查权限或 iCloud 文件状态。", path)
	_index.erase(id)
	return {"ok": true, "path": path, "error": ""}

func _trash_file(path: String) -> Error:
	return OS.move_to_trash(path)

func sync_all(entries: Array) -> Dictionary:
	var count := 0
	for entry in entries:
		if not entry is Dictionary: return {"ok": false, "count": count, "error": "发现无效词条，已停止同步。"}
		var result := sync_entry(entry)
		if not result.ok: return {"ok": false, "count": count, "error": result.error, "path": result.get("path", "")}
		count += 1
	return {"ok": true, "count": count, "error": ""}

func entry_path(id: String) -> String:
	if not _configured or not _valid_id(id): return ""
	_rebuild_index()
	if not _index_error.is_empty(): return ""
	return str(_index.get(id, ""))

func open_uri(id: String) -> String:
	return str(resolve_uri(id).get("uri", ""))

func resolve_uri(id: String) -> Dictionary:
	if not _configured: return _error("请先在设置中选择 Obsidian 保管库。")
	if not _valid_id(id): return _error("词条 ID 无效，无法查找 Obsidian 笔记。")
	_rebuild_index()
	if not _index_error.is_empty(): return _error(_index_error)
	var path := str(_index.get(id, ""))
	return {"ok": true, "uri": "obsidian://open?path=" + path.uri_encode() if not path.is_empty() else "", "error": ""}

func _managed_root() -> String:
	return vault_path.path_join(folder)

static func _valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 96: return false
	for character in id:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(character): return false
	return true

static func _valid_folder(value: String) -> bool:
	if value.is_empty() or value.is_absolute_path() or value.begins_with("/"): return false
	for part in value.split("/", true):
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" "): return false
		for character in '<>:"|?*':
			if part.contains(character): return false
		for index in part.length():
			if part.unicode_at(index) < 32: return false
		if _reserved_name(part): return false
	return true

static func _reserved_name(value: String) -> bool:
	var stem := value.get_slice(".", 0).to_upper()
	return stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

static func _filename(word: String, id: String) -> String:
	var name := ""
	for character in word:
		if '<>:"/\\|?*'.contains(character) or character.unicode_at(0) < 32:
			name += "_"
		else: name += character
		if name.length() >= 60: break
	name = name.strip_edges().trim_suffix(".")
	if name.is_empty() or _reserved_name(name): name = "word"
	return name + "--" + id + ".md"

func _guard_path(path: String) -> Dictionary:
	var root := _managed_root().replace("\\", "/").simplify_path()
	var candidate := path.replace("\\", "/").simplify_path()
	if candidate.to_lower() != root.to_lower() and not candidate.to_lower().begins_with(root.to_lower() + "/"):
		return _error("目标路径超出配置的单词本文件夹。", candidate)
	if OS.get_name() == "Windows": return _windows_guard(candidate)
	var current := candidate
	while not current.is_empty():
		var parent := current.get_base_dir()
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(current.get_file()): return _error("单词本路径包含重定向链接，已停止同步。", candidate)
		if parent == current: break
		current = parent
	return {"ok": true, "error": ""}

func _windows_guard(path: String) -> Dictionary:
	return _windows_guard_paths([path])

func _windows_guard_paths(paths: Array) -> Dictionary:
	# iCloud placeholders are reparse points too, but do not redirect filenames.
	# Only normal paths and Windows CLOUD/CLOUD_1..F tags are allowed. Querying
	# tags does not hydrate files or read the contents of unrelated notes.
	if paths.is_empty(): return {"ok": true, "error": ""}
	var encoded_paths := Marshalls.raw_to_base64(JSON.stringify(paths).to_utf8_buffer())
	var script := "$ErrorActionPreference='Stop';try{$paths=ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded_paths + "')));$seen=@{};foreach($candidate in $paths){$p=$candidate;while($p){if($seen.ContainsKey($p)){break};$seen[$p]=$true;if([IO.File]::Exists($p)-or[IO.Directory]::Exists($p)){$i=Get-Item -LiteralPath $p -Force;if(([int]$i.Attributes-band 1024)-ne 0){$r=& \"$env:SystemRoot\\System32\\fsutil.exe\" reparsepoint query $p 2>&1;if($LASTEXITCODE-ne 0){exit 3};$m=[regex]::Match(($r-join \"`n\"),'0x([0-9a-fA-F]{8})');if(-not $m.Success){exit 3};$tag=[Convert]::ToUInt32($m.Groups[1].Value,16);if(($tag-band [uint32]4294905855)-ne [uint32]2415919130){exit 2}}};$next=[IO.Path]::GetDirectoryName($p);if($next-eq $p){break};$p=$next}};exit 0}catch{exit 3}"
	var output: Array = []
	var result := OS.execute("powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())], output, true, false)
	if result == 0: return {"ok": true, "error": ""}
	if result == 2: return _error("单词本路径包含链接或不支持的重解析点，已停止同步以保护库外文件。", str(paths[0]))
	return _error("无法验证 Obsidian 文件路径，请检查访问权限。", str(paths[0]))

func _rebuild_index() -> void:
	_index.clear()
	_index_error = ""
	if not DirAccess.dir_exists_absolute(_managed_root()): return
	var pending: Array[String] = [_managed_root()]
	var note_paths: Array[String] = []
	while not pending.is_empty():
		var directory_path: String = pending.pop_back()
		var guard := _guard_path(directory_path)
		if not guard.ok:
			_index_error = guard.error
			return
		var directory := DirAccess.open(directory_path)
		if directory == null:
			_index_error = "无法读取 Obsidian 单词本文件夹。"
			return
		directory.list_dir_begin()
		var filename := directory.get_next()
		while not filename.is_empty():
			if filename.begins_with("."):
				filename = directory.get_next()
				continue
			var path := directory_path.path_join(filename)
			if directory.current_is_dir():
				pending.append(path)
			elif filename.to_lower().ends_with(".md"):
				note_paths.append(path)
			filename = directory.get_next()
		directory.list_dir_end()
	var files_guard := _windows_guard_paths(note_paths) if OS.get_name() == "Windows" else {"ok": true}
	if not files_guard.ok:
		_index_error = files_guard.error
		return
	for path in note_paths:
		if OS.get_name() != "Windows":
			var guard := _guard_path(path)
			if not guard.ok:
				_index_error = guard.error
				return
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_index_error = "无法读取 Obsidian 单词本中的笔记。"
			return
		var content := file.get_as_text()
		file.close()
		var id := _note_id(content)
		if id.is_empty(): id = _block_id(content)
		if not id.is_empty():
			if _index.has(id):
				_index_error = "保管库中有两篇相同词条 ID 的笔记，请先解决副本冲突。"
				return
			_index[id] = path

static func _note_id(content: String) -> String:
	var text := content.replace("\r\n", "\n").trim_prefix("\ufeff")
	if not text.begins_with("---\n"): return ""
	var finish := text.find("\n---\n", 4)
	if finish < 0: return ""
	for line in text.substr(4, finish - 4).split("\n"):
		if line.begins_with("griddytranslate_id:"):
			var value := line.substr(line.find(":") + 1).strip_edges()
			if value.begins_with('"'):
				var decoded = JSON.parse_string(value)
				return str(decoded) if decoded is String and _valid_id(decoded) else ""
			return value if _valid_id(value) else ""
	return ""

static func _block_id(content: String) -> String:
	var marker := "<!-- GriddyTranslate:begin "
	var start := content.find(marker)
	if start < 0 or content.count(marker) != 1: return ""
	start += marker.length()
	var finish := content.find(" -->", start)
	if finish < 0: return ""
	var id := content.substr(start, finish - start)
	return id if _valid_id(id) else ""

static func _begin(id: String) -> String:
	return "<!-- GriddyTranslate:begin " + id + " -->"

static func _end(id: String) -> String:
	return "<!-- GriddyTranslate:end " + id + " -->"

static func _has_block(content: String, id: String) -> bool:
	return content.count(_begin(id)) == 1 and content.count(_end(id)) == 1 and content.find(_end(id)) > content.find(_begin(id))

func _render_note(entry: Dictionary, original: String) -> Dictionary:
	var id := str(entry.id)
	var metadata := _metadata(entry)
	var block := _managed_block(entry)
	if original.is_empty():
		var tags: Array = ["单词本"]
		for tag in entry.get("tags", []):
			if not tags.has(str(tag)): tags.append(str(tag))
		metadata += "tags: " + JSON.stringify(tags) + "\n"
		return {"ok": true, "text": "---\n" + metadata + "---\n\n# " + _markdown(str(entry.get("word", ""))) + "\n\n" + block + "\n\n## 我的笔记\n\n"}
	if not _has_block(original, id): return _error("笔记管理标记缺失或重复，已保留原内容。")
	var text := original.replace("\r\n", "\n")
	var bom := "\ufeff" if text.begins_with("\ufeff") else ""
	text = text.trim_prefix(bom) if not bom.is_empty() else text
	var finish := text.find("\n---\n", 4)
	if not text.begins_with("---\n") or finish < 0: return _error("笔记 frontmatter 无效，已保留原内容。")
	var yaml_lines := text.substr(4, finish - 4).split("\n")
	var retained: Array[String] = []
	var skipping := false
	for line in yaml_lines:
		if not line.begins_with(" ") and not line.begins_with("\t") and not line.is_empty():
			var key := line.get_slice(":", 0)
			skipping = MANAGED_FIELDS.has(key)
		if not skipping: retained.append(line)
	var body := text.substr(finish + 5)
	var block_start := body.find(_begin(id))
	var block_end := body.find(_end(id)) + _end(id).length()
	body = body.substr(0, block_start) + block + body.substr(block_end)
	var unknown := "\n".join(retained)
	if not unknown.is_empty(): unknown += "\n"
	var result := bom + "---\n" + metadata + unknown + "---\n" + body
	if original.contains("\r\n"): result = result.replace("\n", "\r\n")
	return {"ok": true, "text": result}

static func _metadata(entry: Dictionary) -> String:
	var values := {"griddytranslate_id": entry.get("id", ""), "word": entry.get("word", ""), "source_language": entry.get("source_language", ""), "target_language": entry.get("target_language", ""), "phonetic": entry.get("phonetic", ""), "translation_source": entry.get("provider", entry.get("translation_source", "")), "created_at": entry.get("created_at", ""), "updated_at": entry.get("updated_at", ""), "griddytranslate_tags": entry.get("tags", [])}
	var result := ""
	for key in MANAGED_FIELDS: result += key + ": " + JSON.stringify(values[key]) + "\n"
	return result

static func _managed_block(entry: Dictionary) -> String:
	var result := _begin(str(entry.id)) + "\n\n## 释义\n\n" + _markdown(str(entry.get("translation", ""))) + "\n"
	var phonetic := str(entry.get("phonetic", "")).strip_edges()
	if not phonetic.is_empty(): result += "\n音标：" + _markdown(phonetic) + "\n"
	var examples = entry.get("examples", [])
	if examples is Array and not examples.is_empty():
		result += "\n## 例句\n"
		for example in examples:
			if example is Dictionary:
				var source := str(example.get("source", example.get("english", example.get("text", ""))))
				var target := str(example.get("target", example.get("chinese", example.get("translation", ""))))
				if not source.is_empty(): result += "\n" + _markdown(source) + "\n"
				if not target.is_empty(): result += "\n" + _markdown(target) + "\n"
			elif example is String: result += "\n" + _markdown(example) + "\n"
	var notes := str(entry.get("notes", "")).strip_edges()
	if not notes.is_empty(): result += "\n## 单词本笔记\n\n" + _markdown(notes) + "\n"
	return result + "\n" + _end(str(entry.id))

static func _markdown(value: String) -> String:
	# Literal fetched text cannot inject HTML, management delimiters or Markdown.
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\\", "\\\\").replace("`", "\\`").replace("*", "\\*").replace("_", "\\_").replace("[", "\\[").replace("]", "\\]").replace("#", "\\#").replace("\r", "").replace("\n", "  \n")

func _atomic_write(path: String, text: String, existed: bool, expected_hash: String) -> Dictionary:
	var temporary := path + ".griddy-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec()) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _error("无法写入 Obsidian 笔记，请检查目录权限。", path)
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("Obsidian 笔记写入失败：" + error_string(write_error), path)
	_before_commit(path)
	var guard := _guard_path(path)
	if not guard.ok:
		DirAccess.remove_absolute(temporary)
		return guard
	var exists_now := FileAccess.file_exists(path)
	if exists_now != existed or (exists_now and FileAccess.get_sha256(path) != expected_hash):
		DirAccess.remove_absolute(temporary)
		return _error("Obsidian 笔记在同步期间被修改，已保留外部修改。请再次同步。", path)
	if OS.get_name() == "Windows":
		var committed := _windows_commit(temporary, path, existed, expected_hash)
		if not committed.ok: DirAccess.remove_absolute(temporary)
		return committed
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("无法替换 Obsidian 笔记：" + error_string(rename_error), path)
	return {"ok": true, "path": path, "error": ""}

func _windows_commit(temporary: String, path: String, existed: bool, expected_hash: String) -> Dictionary:
	# Godot 4.2 Windows rename deletes an existing destination before renaming.
	# .NET File.Replace uses ReplaceFileW, so a failed replacement leaves the
	# existing note present. Hash again inside this process just before the swap.
	var arguments := {"temporary": temporary, "path": path, "existed": existed, "hash": expected_hash}
	var encoded := Marshalls.raw_to_base64(JSON.stringify(arguments).to_utf8_buffer())
	var script := "$ErrorActionPreference='Stop';try{$a=ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded + "')));$exists=[IO.File]::Exists($a.path);if($exists-ne $a.existed){exit 5};if($exists){$sha=[Security.Cryptography.SHA256]::Create();try{$bytes=[IO.File]::ReadAllBytes($a.path);$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()};if($hash-ne $a.hash){exit 5};[IO.File]::Replace($a.temporary,$a.path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($a.temporary,$a.path)};exit 0}catch{exit 6}"
	var output: Array = []
	var result := OS.execute("powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())], output, true, false)
	if result == 0: return {"ok": true, "path": path, "error": ""}
	if result == 5: return _error("Obsidian 笔记在同步期间被修改，已保留外部修改。请再次同步。", path)
	return _error("无法原子更新 Obsidian 笔记，现有文件已保留。请检查权限或 iCloud 文件状态。", path)

func _before_commit(_path: String) -> void:
	pass

static func _error(message: String, path := "") -> Dictionary:
	return {"ok": false, "error": message, "path": path}
