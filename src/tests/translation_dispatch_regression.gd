extends Node

var failures := 0
var app: Node2D
var fake: Node

class SlowService extends Node:
	var provider := "youdao"
	var starts: Array[Dictionary] = []
	var cancellations := 0
	var delays := {"old error": 0.18, "new result": 0.4, "old success": 0.4, "fast result": 0.03, "obsolete auto": 0.9}
	func cancel() -> void:
		cancellations += 1
		# Deliberately let the old coroutine complete: a cancelled adapter can
		# still deliver an already queued response, which must remain harmless.
	func translate_text(value: String, source: String, target: String) -> Dictionary:
		starts.append({"value": value, "provider": provider, "source": source, "target": target, "time": Time.get_ticks_msec()})
		await get_tree().create_timer(float(delays.get(value, 0.03))).timeout
		if value == "old error": return {"ok": false, "error": "Obsolete error"}
		return {"ok": true, "text": "translated:" + value}

func _ready() -> void:
	app = get_parent()
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition: failures += 1

func source(value: String) -> void:
	app.showing_translation = false
	app.Code.editable = true
	app.Code.text = value
	app.on_source_changed()

func run() -> void:
	await get_tree().create_timer(0.2).timeout
	var real_service: Node = app.service
	fake = SlowService.new()
	app.add_child(fake)
	app.service = fake
	app.examples_enabled = false
	app.auto_translate = false
	app.translated_text = ""

	source("old error")
	app.request_translation()
	var cancellation_count: int = fake.cancellations
	app.request_translation()
	check(fake.starts.size() == 1 and fake.cancellations == cancellation_count, "repeated manual request keeps the same active HTTP snapshot")
	source("new result")
	var started := Time.get_ticks_msec()
	app.request_translation()
	check(fake.starts.size() == 2 and int(fake.starts[-1].time) - started < 50, "manual replacement starts immediately without waiting for old HTTP or debounce")
	await get_tree().create_timer(0.24).timeout
	check(app.busy and app.last_error.is_empty() and app.translated_text.is_empty(), "obsolete error cannot clear replacement busy state or show an error")
	await get_tree().create_timer(0.24).timeout
	check(not app.busy and app.translated_text == "translated:new result", "latest snapshot applies normally")

	source("old success")
	app.request_translation()
	source("fast result")
	await app.request_translation()
	await get_tree().create_timer(0.45).timeout
	check(app.translated_text == "translated:fast result" and app.showing_translation, "late successful response cannot overwrite the newer result")

	source("old success")
	app.request_translation()
	app.on_provider_changed(0)
	app.request_translation()
	check(fake.starts[-1].provider == "mymemory" and app.busy, "provider change cancels old work and dispatches the selected provider immediately")
	app.source_language = "ja"
	app.target_language = "en"
	app.on_languages_changed()
	app.request_translation()
	check(fake.starts[-1].source == "ja" and fake.starts[-1].target == "en", "language change immediately dispatches a distinct snapshot")
	await get_tree().create_timer(0.45).timeout
	check(app.last_source == "ja" and app.last_target == "en", "only the current language direction is committed")

	app.source_language = "en"
	app.target_language = "zh-CN"
	source("obsolete auto")
	app.request_translation()
	app.auto_translate = true
	var before: int = fake.starts.size()
	var edit_time := Time.get_ticks_msec()
	source("latest auto")
	await get_tree().create_timer(0.68).timeout
	check(fake.starts.size() == before + 1 and int(fake.starts[-1].time) - edit_time >= 450 and int(fake.starts[-1].time) - edit_time < 650, "automatic translation starts after a 500ms typing pause without waiting for old request")
	check(app.translated_text == "translated:latest auto", "automatic replacement displays the final typed text")
	await get_tree().create_timer(0.4).timeout
	check(fake.starts.size() == before + 1 and app.debounce.is_stopped(), "obsolete completion does not restart automatic debounce")

	app.auto_translate = false
	source("old success")
	app.request_translation()
	var clear := InputEventKey.new()
	clear.keycode = KEY_N
	clear.ctrl_pressed = true
	clear.pressed = true
	app._input(clear)
	await get_tree().create_timer(0.5).timeout
	check(app.source_text.is_empty() and app.translated_text.is_empty() and not app.busy, "new document cancels translation without resurrecting cleared text")
	app.service = real_service
	print("DISPATCH_REGRESSION_COMPLETE failures=" + str(failures))
	get_tree().quit(0 if failures == 0 else 1)
