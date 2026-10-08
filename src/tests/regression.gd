extends SceneTree
var failures := 0
var app: Control

class FakeService extends Node:
	var failed := false
	func translate_chunk(value: String, _source: String, _target: String) -> Dictionary:
		await get_tree().create_timer(0.15).timeout
		return {"ok": false, "error": "Test network unavailable"} if failed else {"ok": true, "text": "translated:" + value}

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func run() -> void:
	app = load("res://Scenes/editor.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var real_service: Node = app.service
	var fake := FakeService.new()
	app.add_child(fake)
	app.service = fake
	app.source_edit.text = "old"
	app._text_changed()
	app._translate()
	check(app.busy, "request waits asynchronously")
	app.source_edit.text = "new"
	app._text_changed()
	await create_timer(0.25).timeout
	check(app.target_edit.text.is_empty(), "stale network result discarded")
	await app._translate()
	check(app.target_edit.text == "translated:new", "new source translated")
	fake.failed = true
	app.source_edit.text = "failure"
	app._text_changed()
	await app._translate()
	check(app.last_error == "Test network unavailable", "network error visible")
	check(app.target_edit.text == "translated:new", "error preserves previous output")
	fake.failed = false
	app.settings.auto = true
	app.source_edit.text = "automatic"
	app._text_changed()
	await create_timer(1.7).timeout
	check(app.target_edit.text == "translated:automatic", "debounced automatic translation")
	app.settings.auto = false
	app._toggle_overlay("languages")
	await create_timer(0.3).timeout
	check(not app.source_edit.has_focus(), "modal removes source focus")
	var options: Array = app.overlay_content.find_children("*", "OptionButton", true, false)
	check(options.size() == 2 and options[0].has_focus(), "language picker keyboard focus")
	options[0].item_selected.emit(4)
	options[1].item_selected.emit(3)
	check(app.settings.source == "ja" and app.settings.target == "en", "independent language choices")
	app._close_overlay()
	app._toggle_overlay("settings")
	await create_timer(0.3).timeout
	var toggles: Array = app.overlay_content.find_children("*", "CheckButton", true, false)
	toggles[1].toggled.emit(false)
	check(not app.settings.motion and not app.settings.music, "independent settings toggles")
	app._close_overlay()
	for name in app.theme_names:
		app.settings.theme = name
		app._apply_theme()
		check(app.palette.has("background_color"), "theme loads " + name)
	app.service = real_service
	print("REGRESSION_COMPLETE failures=" + str(failures))
	app.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
