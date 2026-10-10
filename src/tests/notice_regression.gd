extends Node

var app: Node
var failures := 0
var output := ""

func _ready() -> void:
	app = get_parent()
	output = OS.get_environment("GRIDDY_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("user://qa/notice")
	DirAccess.make_dir_recursive_absolute(output)
	run.call_deferred()

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func current_notice() -> Control:
	for node in app.canvas_layer.get_children():
		if node.has_method("dismiss") and not node._closing: return node
	return null

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(2))
	await get_tree().create_timer(0.5).timeout
	LuaSingleton.change_setting("music", false)
	app.Code.text = "GriddyTranslate"
	app.warn("已收藏：manipulate · 操纵；操作")
	var notice := current_notice()
	await get_tree().process_frame
	# Advance the real tween at a known point. Wall-clock timers can resume
	# before a tween, or after first-use MSDF generation skipped that interval.
	while not notice._presented: await get_tree().process_frame
	notice._animation.pause()
	notice._animation.custom_step(0.08)
	await RenderingServer.frame_post_draw
	check(notice.position.x < -5 and notice.modulate.a > 0 and notice.modulate.a < 1, "notice enters from the left with an interpolated fade")
	await capture("notice-enter")
	notice._animation.play()
	await get_tree().create_timer(0.4).timeout
	check(absf(notice.position.x) < 0.01 and notice.modulate.a == 1 and notice.scale.is_equal_approx(Vector2.ONE), "notice settles at its original top-left anchor without continued shaking")
	check(notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.rich_text_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "notice and message allow mouse input to reach underlying controls")
	check(notice.rich_text_label.get_content_height() + 34 <= notice.size.y + 1, "the frame contains all shaped text with vertical padding")
	await capture("notice-visible")
	var palettes: Array = []
	for theme in LuaSingleton.themes:
		LuaSingleton.setup_theme(theme)
		app.warn("已收藏：manipulate · 操纵；操作")
		notice = current_notice()
		await get_tree().create_timer(0.4).timeout
		check(notice._accent.bg_color == LuaSingleton.keywords.reserved and notice.rich_text_label.get_theme_color("default_color") == LuaSingleton.gui.font_color, "notice colors follow theme " + theme)
		var palette := [notice._frame.bg_color, notice._frame.border_color, notice._accent.bg_color]
		if not palettes.has(palette): palettes.append(palette)
		await capture("notice-theme-" + str(theme).replace(" ", "-"))
	check(palettes.size() > 1, "different themes produce distinct notice palettes")
	LuaSingleton.setup_theme("One Dark Pro Darker")
	app.warn("后台同步暂未完成。这是一条较长的通知，用于检查中文、English 和完整短语在边框内换行显示，不会截断最后一行。")
	var replacement := current_notice()
	await get_tree().create_timer(0.5).timeout
	check(not is_instance_valid(notice) and is_instance_valid(replacement), "a replacement notice dismisses the previous card instead of overlapping messages")
	check(replacement.size.y > 82 and replacement.rich_text_label.get_content_height() + 34 <= replacement.size.y + 1, "long bilingual notices grow vertically and keep the final line visible")
	await capture("notice-long")
	replacement.dismiss()
	replacement._animation.pause()
	replacement._animation.custom_step(0.10)
	await RenderingServer.frame_post_draw
	check(is_instance_valid(replacement) and replacement.modulate.a < 1 and replacement.modulate.a > 0 and replacement.position.x < 0, "dismissal slides and fades rather than disappearing immediately")
	await capture("notice-exit")
	replacement._animation.play()
	await get_tree().create_timer(0.25).timeout
	check(not is_instance_valid(replacement), "dismissed notices release their nodes after the exit animation")
	app.warn("这条通知会在停留后自动消失。")
	var timed := current_notice()
	await get_tree().create_timer(5.85).timeout
	check(not is_instance_valid(timed), "notice lifetime includes entry, reading time and animated exit")
	print("NOTICE_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
