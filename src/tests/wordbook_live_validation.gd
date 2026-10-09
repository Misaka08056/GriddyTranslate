extends Node

const Metadata = preload("res://Scripts/word_metadata_service.gd")
const Sync = preload("res://Scripts/obsidian_sync.gd")
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures += 1

func run() -> void:
	get_tree().create_timer(55.0).timeout.connect(func(): get_tree().quit(2))
	var metadata := Metadata.new()
	add_child(metadata)
	var report := {"metadata": {}, "vault": {}}
	for word in ["manipulate", "give up", "US", "us", "Polish"]:
		var details: Dictionary = await metadata.get_metadata(word, "en", "zh-CN")
		report.metadata[word] = details
		check(not details.is_empty(), "Youdao metadata returned for " + word)
		if word == "manipulate":
			check(not str(details.get("phonetic", "")).is_empty(), "manipulate has genuine Youdao phonetics")
			check(not details.get("examples", []).is_empty(), "manipulate has a bilingual dictionary example")
		if word == "give up":
			check(not details.get("examples", []).is_empty(), "full phrase retains a phrase-level example")
	check(report.metadata.get("US", {}) != report.metadata.get("us", {}), "case-sensitive metadata distinguishes US and us")
	check(await metadata.get_metadata("This is a whole sentence with punctuation.", "en", "zh-CN") == {}, "sentences do not request invented dictionary metadata")
	var vaults := Sync.discover_vaults()
	check(not vaults.is_empty(), "existing Obsidian registry can be read")
	for vault in vaults:
		if not vault.get("opened", false): continue
		var backend := Sync.new()
		var configured: Dictionary = backend.configure(str(vault.path), "GriddyTranslate/单词本")
		report.vault = {"name": vault.name, "path": vault.path, "configure": configured}
		check(configured.get("ok", false), "current iCloud Obsidian vault passes read-only path configuration")
		break
	var output := OS.get_environment("GRIDDY_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("user://qa/wordbook-live")
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("validation.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("WORDBOOK_LIVE_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
