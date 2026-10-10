extends CanvasLayer

const EDITOR_SCENE := "res://Scenes/editor.tscn"
const ANIMATION_SECONDS := 11.0
const TITLE := "cybertranslator"
const WORDMARK_PATH := "res://Art/Startup/cybertranslator-wordmark.png"
const WORDMARK_CONTENT := Rect2(32, 168, 2121, 418)
const BACKGROUND_PATH := "res://Art/Startup/reference-background.ogv"
const SHADER_PATH := "res://Shaders/startup_logo.gdshader"
const LOGO_COMPLETE_SECONDS := 1.08
const LOGO_HOLD_MS := 500
const EXIT_SECONDS := 0.45

var elapsed := 0.0
var enabled := true
var editor: Node
var editor_ready := false
var skipped := false
var first_frame_ms := -1
var logo_complete_ms := -1
var skip_allowed_ms := -1
var exit_started_ms := -1
var _logo_record_pending := false
var _native := false
var _native_directory := ""
var _native_wait_ms := -1
var _native_process_id := 0
var _native_heartbeat := ""
var _native_next_poll_ms := 0
var _native_next_check_ms := 0
var _loading_started := false
var _finishing := false
var _art: Control
var _background: VideoStreamPlayer
var _logo: ColorRect
var _material: ShaderMaterial
var _fade: Tween

func _ready() -> void:
	name = "Startup"
	_art = $Artwork
	_background = $Artwork/Background
	_logo = $Artwork/Logo
	var args := OS.get_cmdline_user_args()
	enabled = not args.has("--test") or args.has("--startup-animation")
	if not args.has("--test"):
		var preferences := ConfigFile.new()
		if preferences.load("user://translator.cfg") == OK:
			enabled = bool(preferences.get_value("visual", "startup_animation", true))
	_native_directory = OS.get_environment("GRIDDY_NATIVE_SPLASH_DIR")
	_native = enabled and OS.get_environment("GRIDDY_NATIVE_SPLASH_ACTIVE") == "1" and not _native_directory.is_empty()
	_native_process_id = int(OS.get_environment("GRIDDY_NATIVE_SPLASH_PID"))
	_native_next_check_ms = Time.get_ticks_msec() + 2000
	# The portable launcher owns the animation before the engine exists. Keep
	# its single continuous playback on screen while this scene loads the editor.
	# Direct runtime launches retain the same Godot animation as a fallback.
	if enabled and not _native: _build_artwork()
	_art.visible = enabled and not _native
	_art.resized.connect(_layout_artwork)
	_layout_artwork()
	DisplayServer.window_set_title("GriddyTranslate")
	# The 640x360 silent Theora background uses Godot's built-in decoder. There
	# are no external players or fonts; disabled splashes load no art assets.
	_start_loading.call_deferred()

func _start_loading() -> void:
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	first_frame_ms = Time.get_ticks_msec()
	if enabled and not _native: _background.play()
	var args := OS.get_cmdline_user_args()
	if enabled and not _native and args.has("--test") and args.has("--startup-wrap-test"):
		load("res://tests/startup_wrap_regression.gd").capture_startup_stages(self)
	var error := ResourceLoader.load_threaded_request(EDITOR_SCENE)
	if error != OK:
		push_error("Could not load the translation editor: " + str(error))
		get_tree().quit(1)
		return
	_loading_started = true

func _build_artwork() -> void:
	var wordmark: Texture2D = load(WORDMARK_PATH)
	_background.stream = load(BACKGROUND_PATH)
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	_material.set_shader_parameter("wordmark", wordmark)
	# Content bounds exclude transparent padding and faint generation specks.
	# No GPU readback or pixel scan is needed on the startup path.
	var bounds := WORDMARK_CONTENT
	var dimensions := Vector2(wordmark.get_size())
	_material.set_shader_parameter("texture_bounds", Vector4(bounds.position.x / dimensions.x, bounds.position.y / dimensions.y, bounds.size.x / dimensions.x, bounds.size.y / dimensions.y))
	_logo.material = _material
	_logo.set_meta("title", TITLE)

func _layout_artwork() -> void:
	var scale_factor := minf(_art.size.x / 640.0, _art.size.y / 360.0)
	var frame_size := Vector2(640, 360) * scale_factor
	var origin := (_art.size - frame_size) * 0.5
	_background.position = origin
	_background.size = frame_size
	_logo.position = origin
	_logo.size = frame_size

func _process(_delta: float) -> void:
	# Godot clamps frame delta during expensive first-frame font/shader work.
	# Wall time prevents that work from adding another full splash afterward.
	if first_frame_ms >= 0: elapsed = float(Time.get_ticks_msec() - first_frame_ms) / 1000.0
	if enabled and _material != null:
		_material.set_shader_parameter("animation_time", elapsed)
		if not _logo_record_pending and logo_complete_ms < 0 and elapsed >= LOGO_COMPLETE_SECONDS:
			_logo_record_pending = true
			if DisplayServer.get_name() != "headless":
				RenderingServer.frame_post_draw.connect(_record_complete_logo, CONNECT_ONE_SHOT)
			else: _record_complete_logo()
	if _loading_started and not editor_ready:
		var status := ResourceLoader.load_threaded_get_status(EDITOR_SCENE)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_loading_started = false
			_mount_editor.call_deferred()
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Failed to load translation editor")
			get_tree().quit(1)
	if _native:
		# Native fade is complete before input is restored. Keyboard events that
		# reached this window during loading cannot edit or translate hidden text.
		if editor_ready and FileAccess.file_exists(_native_directory.path_join("done")):
			_complete()
		elif editor_ready and _native_parent_exited(): _complete()
		elif editor_ready and _native_wait_ms >= 0 and Time.get_ticks_msec() - _native_wait_ms > 45000:
			# A terminated launcher must never leave the editor permanently gated.
			_complete()
		return
	if editor_ready and not _finishing and (not enabled or skipped or elapsed >= ANIMATION_SECONDS):
		_finish()

func _native_parent_exited() -> bool:
	# Godot 4.2 on Windows only tracks processes it spawned itself; querying
	# our parent through OS.is_process_running falsely reports it as gone.
	# A regular native heartbeat avoids any subprocess on the healthy path.
	var now := Time.get_ticks_msec()
	if now >= _native_next_poll_ms:
		_native_next_poll_ms = now + 100
		var path := _native_directory.path_join("heartbeat")
		if FileAccess.file_exists(path):
			var pulse := FileAccess.get_file_as_string(path)
			if not pulse.is_empty() and pulse != _native_heartbeat:
				_native_heartbeat = pulse
				_native_next_check_ms = now + 2000
	if now < _native_next_check_ms or _native_process_id <= 0: return false
	_native_next_check_ms = now + 2000
	var launcher := OS.get_executable_path().get_base_dir().path_join("GriddyTranslate.exe")
	if not FileAccess.file_exists(launcher): return false
	# Only a stale heartbeat triggers the Win32 process check, and only an
	# explicit dead-process result releases input before a normal done marker.
	return OS.execute(launcher, PackedStringArray(["--native-parent-alive", str(_native_process_id)])) == 1

func _record_complete_logo() -> void:
	# Start the half-second hold after a full logo was actually drawn, rather
	# than counting a stalled/loading frame as time spent looking at it.
	logo_complete_ms = Time.get_ticks_msec()
	skip_allowed_ms = logo_complete_ms + LOGO_HOLD_MS

func can_skip() -> bool:
	return enabled and not _native and skip_allowed_ms >= 0 and Time.get_ticks_msec() >= skip_allowed_ms

func _mount_editor() -> void:
	if OS.get_cmdline_user_args().has("--startup-profile"):
		print("STARTUP_STAGE resources_loaded=" + str(Time.get_ticks_msec()))
	var scene: PackedScene = ResourceLoader.load_threaded_get(EDITOR_SCENE)
	editor = scene.instantiate()
	get_tree().root.add_child(editor)
	get_tree().current_scene = editor
	editor_ready = true
	editor.set_meta("startup_title", TITLE)
	editor.set_meta("splash_first_frame_ms", first_frame_ms)
	editor.set_meta("native_startup", _native)
	_native_wait_ms = Time.get_ticks_msec()
	# A key can free this overlay before the editor's first draw. Bind the
	# one-shot callback to the script resource and persistent editor, so its
	# bookkeeping survives both immediate skips and disabled animations.
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(Callable(get_script(), "_record_editor_frame").bind(editor, first_frame_ms), CONNECT_ONE_SHOT)
	else:
		_record_editor_frame(editor, first_frame_ms)

static func _record_editor_frame(target: Node, splash_frame_ms: int) -> void:
	if not is_instance_valid(target): return
	var frame_ms := Time.get_ticks_msec()
	target.set_meta("first_frame_ms", frame_ms)
	if bool(target.get_meta("native_startup", false)):
		var ready := FileAccess.open(OS.get_environment("GRIDDY_NATIVE_SPLASH_DIR").path_join("ready"), FileAccess.WRITE)
		if ready != null:
			ready.store_string(str(frame_ms))
			ready.close()
	if OS.get_cmdline_user_args().has("--startup-profile"):
		print("STARTUP_TIMING splash_ms=%d editor_ms=%d" % [splash_frame_ms, frame_ms])

func _input(event: InputEvent) -> void:
	if consume_startup_input(event): get_viewport().set_input_as_handled()

func consume_startup_input(event: InputEvent) -> bool:
	if not enabled or is_queued_for_deletion(): return false
	if event is InputEventKey or event is InputEventMouseButton:
		if _native or _finishing: return true
		var requested: bool = event.pressed and not (event is InputEventKey and event.echo)
		if requested and can_skip():
			skipped = true
			if editor_ready: _finish()
		# Earlier presses are consumed without being queued for later. Releases
		# and repeated keys also stay out of the underlying translation editor.
		return true
	return false

func _finish() -> void:
	_finishing = true
	exit_started_ms = Time.get_ticks_msec()
	set_process(false)
	_background.paused = true
	# Both a skip and natural completion disperse the title into signal slices
	# before dissolving the background. Further input cannot cut this short.
	if enabled:
		_fade = create_tween()
		_fade.tween_method(_set_exit_progress, 0.0, 1.0, EXIT_SECONDS)
		_fade.tween_callback(_complete)
	else:
		_complete()

func _set_exit_progress(value: float) -> void:
	if _material != null: _material.set_shader_parameter("exit_progress", value)
	_art.modulate.a = 1.0 - smoothstep(0.18, 1.0, value)

func _complete() -> void:
	if is_queued_for_deletion(): return
	if _fade != null: _fade.kill()
	set_process_input(false)
	_background.stop()
	_art.hide()
	if is_instance_valid(editor):
		editor.set_meta("input_ready_ms", Time.get_ticks_msec())
		if _native: editor.set_meta("native_completed", FileAccess.file_exists(_native_directory.path_join("done")))
		editor.set_meta("logo_complete_ms", logo_complete_ms)
		editor.set_meta("skip_allowed_ms", skip_allowed_ms)
		editor.set_meta("exit_started_ms", exit_started_ms)
		editor.restore_input_focus()
	if _native: _cleanup_native_handshake()
	queue_free()

func _cleanup_native_handshake() -> void:
	# Only remove the small, known handshake files from this launch's Windows
	# temp folder. Never recursively delete an environment-provided path.
	var directory := _native_directory.replace("\\", "/").simplify_path()
	var temporary := OS.get_environment("TEMP").replace("\\", "/").simplify_path()
	var leaf := directory.get_file()
	if temporary.is_empty() or directory.get_base_dir().to_lower() != temporary.to_lower(): return
	if not leaf.begins_with("GTS") or not leaf.ends_with(".tmp"): return
	for marker in ["shown", "logo", "ready", "exiting", "skip", "done", "cancel", "heartbeat"]:
		DirAccess.remove_absolute(directory.path_join(marker))
	DirAccess.remove_absolute(directory)
