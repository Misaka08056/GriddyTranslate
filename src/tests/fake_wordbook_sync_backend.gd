extends RefCounted

# No filesystem or shell access: this backend only models slow local work.
static var _mutex := Mutex.new()
static var _events: Array[Dictionary] = []
static var _delay_ms := 120
static var _configure_delay_ms := 0
static var _fail := false

var _vault := ""

static func reset(delay_ms: int = 120, fail: bool = false, configure_delay_ms: int = 0) -> void:
	_mutex.lock()
	_events.clear()
	_delay_ms = delay_ms
	_fail = fail
	_configure_delay_ms = configure_delay_ms
	_mutex.unlock()

static func events() -> Array[Dictionary]:
	_mutex.lock()
	var copy: Array[Dictionary] = []
	for event in _events:
		copy.append(event.duplicate(true))
	_mutex.unlock()
	return copy

static func _record(event: Dictionary) -> void:
	_mutex.lock()
	_events.append(event.duplicate(true))
	_mutex.unlock()

func configure(vault: String, relative_folder: String) -> Dictionary:
	_vault = vault
	_mutex.lock()
	var delay_ms := _configure_delay_ms
	_mutex.unlock()
	_record({"kind": "configure", "vault": vault, "folder": relative_folder})
	if delay_ms > 0: OS.delay_msec(delay_ms)
	return {"ok": true, "error": ""}

func sync_entry(entry: Dictionary) -> Dictionary:
	_mutex.lock()
	var delay_ms := _delay_ms
	var fail := _fail
	_mutex.unlock()
	_record({"kind": "sync_start", "vault": _vault, "entry": entry})
	if delay_ms > 0: OS.delay_msec(delay_ms)
	if fail:
		_record({"kind": "sync_failed", "vault": _vault, "id": entry.id})
		return {"ok": false, "error": "simulated temporary iCloud access failure"}
	_record({"kind": "sync_complete", "vault": _vault, "entry": entry})
	return {"ok": true, "error": ""}

func open_uri(id: String) -> String:
	_mutex.lock()
	var delay_ms := _delay_ms
	_mutex.unlock()
	_record({"kind": "open_start", "vault": _vault, "id": id})
	if delay_ms > 0: OS.delay_msec(delay_ms)
	_record({"kind": "open_complete", "vault": _vault, "id": id})
	return "obsidian://open?path=" + ("fake/" + id + ".md").uri_encode()

func remove_entry(id: String) -> Dictionary:
	_mutex.lock()
	var delay_ms := _delay_ms
	var fail := _fail
	_mutex.unlock()
	_record({"kind": "delete_start", "vault": _vault, "id": id})
	if delay_ms > 0: OS.delay_msec(delay_ms)
	_record({"kind": "delete_failed" if fail else "delete_complete", "vault": _vault, "id": id})
	return {"ok": not fail, "error": "simulated deletion failure" if fail else ""}
