@tool
extends EditorPlugin

var waited := 0.0
var done := false

func _process(delta: float) -> void:
	if done: return
	waited += delta
	if waited < 2.0: return
	var filesystem := get_editor_interface().get_resource_filesystem()
	if filesystem.is_scanning() or filesystem.get_file_type("res://Fonts/FiraCode-Regular.ttf").is_empty(): return
	done = true
	reimport()

func reimport() -> void:
	var filesystem := get_editor_interface().get_resource_filesystem()
	filesystem.reimport_files(PackedStringArray(["res://Fonts/FiraCode-Regular.ttf", "res://Fonts/SymbolsNerdFont-Regular.ttf"]))
	print("ORIGINAL_FONTS_REIMPORTED")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
