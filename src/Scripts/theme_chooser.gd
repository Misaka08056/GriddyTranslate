extends "res://Scripts/selection_menu.gd"

@onready var editor: FileManager = $"../.."
@onready var code = %Code

var zoom: Vector2;

func _ready():
	super._ready()
	fit_to_longest_item = false
	clip_text = true
	size = Vector2(350, 40)
	get_viewport().size_changed.connect(_refocus)
	await LuaSingleton.on_theme_load;

	for _theme in LuaSingleton.themes:
		add_item(_theme)

	selected = LuaSingleton.themes.find(LuaSingleton.theme)

	zoom = Vector2(1,1)

func focus_position(future_position: Vector2) -> Vector2:
	# Keep the compact trigger to the left of the source canvas, with its
	# expanded list aligned to the same left edge.
	return future_position + Vector2(size.x * 0.8, size.y * 0.5)

func _refocus() -> void:
	if code.active_overlay == self:
		editor.get_node("Misc/Cam").focus_on(focus_position(global_position), zoom)
