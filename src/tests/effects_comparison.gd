extends Node

var app: Node2D
var code: CodeEdit
var cam: Camera2D
var output: String
var failures := 0

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	cam = app.get_node("Misc/Cam")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func capture(name: String) -> void:
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	await get_tree().create_timer(0.6).timeout
	code.text = "Hello world"
	code.gutters_draw_line_numbers = false
	code.minimap_draw = false
	code.set_caret_column(5)
	code.caret_blink = false
	cam.radius = 0.0
	cam.offset = Vector2.ZERO
	await capture("default-glow")
	LuaSingleton.change_setting("glow", false)
	check(not app.get_node("WorldEnvironment").environment.glow_enabled, "Glow setting disables original HDR glow")
	await capture("default-no-glow")
	LuaSingleton.change_setting("glow", true)
	var font_index := -1
	for index in LuaSingleton.fonts.size():
		if LuaSingleton.fonts[index].display == "Fira Code": font_index = index
	check(font_index >= 0, "original Fira Code available")
	LuaSingleton.change_setting("editor_font", font_index)
	await capture("fira-glow")
	check(code.get_theme_font("font").get("multichannel_signed_distance_field") == true, "original Fira Code MSDF active")
	LuaSingleton.change_setting("sunlight", true)
	check(app.get_node("ShaderLayer").visible, "original Sunlight shader visible")
	await capture("sunlight")
	LuaSingleton.change_setting("sunlight", false)
	LuaSingleton.change_setting("vhs", true)
	check(app.get_node("ShaderLayer").visible, "original VHS CRT shader visible")
	await capture("vhs")
	LuaSingleton.change_setting("vhs", false)
	check(not app.get_node("ShaderLayer").visible, "shader layer restores clean canvas")
	Music.set_volume(0)
	LuaSingleton.change_setting("music", true)
	check(app.get_node("AudioStreamPlayer").playing, "original music stream starts")
	check(not app.get_node("AudioTimer").is_stopped(), "original rhythm timer starts")
	var old_iter: int = Music.iter
	await get_tree().create_timer(1.6).timeout
	check(Music.iter > old_iter and not Music.data.is_empty(), "original music drives camera pulse samples")
	LuaSingleton.change_setting("music", false)
	check(not app.get_node("AudioStreamPlayer").playing, "music stops through original setting")
	if app.has_method("request_translation"):
		code.text = "你好世界 — GriddyTranslate 🌍"
		code.set_caret_column(4)
		await capture("multilingual")
		check(code.get_theme_font("font").get_fallbacks().size() >= 3, "CJK emoji and original icon fallbacks available")
	print("EFFECTS_COMPARISON_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
