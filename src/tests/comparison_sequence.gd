extends Node

var app: Node2D
var code: CodeEdit
var cam: Camera2D
var output: String
var frames := 0
var states: Array = []

func _ready() -> void:
	app = get_parent()
	code = app.get_node("Code")
	cam = app.get_node("Misc/Cam")
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture := get_viewport().get_texture().get_image()
	capture.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	capture.save_png(output.path_join("frame-%04d.png" % frames))
	states.append({"frame": frames, "position": [cam.position.x, cam.position.y], "zoom": cam.zoom.x, "settings_x": app.get_node("Settings").position.x, "settings_alpha": app.get_node("Settings").modulate.a})
	frames += 1

func hold(count: int) -> void:
	for i in count: await frame()

func run() -> void:
	# Launch with --fixed-fps 30 so both apps use the same simulation timeline.
	await get_tree().create_timer(0.6).timeout
	code.gutters_draw_line_numbers = false
	code.minimap_draw = false
	code.caret_blink = false
	code.text = ""
	code.set_caret_line(0)
	code.set_caret_column(0)
	cam.position = Vector2(92, 48)
	cam.zoom = Vector2(10, 10)
	cam.offset = Vector2.ZERO
	cam.d = 0.0
	for count in range(1, 12):
		code.text = "Hello world".substr(0, count)
		code.set_caret_column(count)
		await hold(4)
	await hold(34)
	code.set_caret_column(2)
	await hold(35)
	code.toggle(app.get_node("Settings"), true, 270)
	await hold(52)
	code.toggle(app.get_node("Settings"), true, 270)
	await hold(45)
	code.toggle(app.get_node("ThemePicker/ThemeChooser"), false, 504)
	await hold(42)
	code.toggle(app.get_node("ThemePicker/ThemeChooser"), false, 504)
	await hold(42)
	var file := FileAccess.open(output.path_join("motion.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(states, "\t"))
	print("COMPARISON_SEQUENCE_COMPLETE frames=" + str(frames))
	get_tree().quit()
