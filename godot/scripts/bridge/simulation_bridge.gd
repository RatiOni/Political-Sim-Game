extends Node

signal response_received(request_id: int, payload: Dictionary)
signal bridge_failed(message: String)

const PROTOCOL_VERSION := 1
const LOG_PATH := "user://logs/godot_bridge.log"
const SHUTDOWN_TIMEOUT_MS := 400

var _pipe: Dictionary = {}
var _pending: Dictionary = {}
var _next_request_id := 1
var _stdout_buffer := ""
var _failed := false
var _shutting_down := false
var _log: FileAccess

func request(command: String, args: Dictionary = {}) -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	if not _ensure_worker():
		return request_id
	_pending[request_id] = command
	_write_request(request_id, command, args)
	return request_id

func shutdown() -> void:
	if _pipe.is_empty():
		return
	_shutting_down = true
	if _is_running():
		var request_id := _next_request_id
		_next_request_id += 1
		_pending[request_id] = "shutdown"
		_write_request(request_id, "shutdown", {})
		var deadline := Time.get_ticks_msec() + SHUTDOWN_TIMEOUT_MS
		while _is_running() and Time.get_ticks_msec() < deadline:
			_poll_worker()
			OS.delay_msec(10)
	if _is_running():
		OS.kill(int(_pipe.get("pid", -1)))
	_close_pipe()

func _process(_delta: float) -> void:
	_poll_worker()

func _exit_tree() -> void:
	shutdown()

func _ensure_worker() -> bool:
	if _failed:
		return false
	if not _pipe.is_empty():
		return _is_running()
	_open_log()
	var repository_root := ProjectSettings.globalize_path("res://..").simplify_path()
	var executable := _resolve_python(repository_root)
	if executable.is_empty():
		_fail("The Ardenia Python environment could not be found. See %s." % LOG_PATH)
		return false
	var python_path := OS.get_environment("PYTHONPATH")
	OS.set_environment("PYTHONPATH", repository_root if python_path.is_empty() else repository_root + ";" + python_path)
	_pipe = OS.execute_with_pipe(
		executable, PackedStringArray(["-u", "-m", "godot_bridge.worker"]), false)
	if _pipe.is_empty() or int(_pipe.get("pid", -1)) <= 0:
		_fail("Could not start the Ardenia simulation worker. See %s." % LOG_PATH)
		return false
	_append_log("Started simulation worker (pid %s).\n" % _pipe["pid"])
	return true

func _resolve_python(repository_root: String) -> String:
	var override := OS.get_environment("ARDENIA_PYTHON_EXECUTABLE")
	if not override.is_empty():
		var candidate := override if override.is_absolute_path() else repository_root.path_join(override)
		candidate = candidate.simplify_path()
		return candidate if FileAccess.file_exists(candidate) else ""
	var local := repository_root.path_join(".venv/Scripts/python.exe").simplify_path()
	if FileAccess.file_exists(local):
		return local
	var output := []
	var exit_code := OS.execute("git", PackedStringArray([
		"-C", repository_root, "rev-parse", "--path-format=absolute", "--git-common-dir"
	]), output, true)
	if exit_code == 0 and not output.is_empty():
		var common_git_directory := str(output[0]).strip_edges().simplify_path()
		var shared := common_git_directory.get_base_dir().path_join(".venv/Scripts/python.exe").simplify_path()
		if FileAccess.file_exists(shared):
			return shared
	return ""

func _write_request(request_id: int, command: String, args: Dictionary) -> void:
	var stream: FileAccess = _pipe.get("stdio")
	if stream == null:
		_fail("The simulation worker pipe is unavailable. See %s." % LOG_PATH)
		return
	stream.store_line(JSON.stringify({
		"version": PROTOCOL_VERSION,
		"id": request_id,
		"command": command,
		"args": args,
	}))
	stream.flush()

func _poll_worker() -> void:
	if _pipe.is_empty():
		return
	var running := _is_running()
	var errors: FileAccess = _pipe.get("stderr")
	if running and errors != null:
		var error_bytes: int = errors.get_length()
		if error_bytes > 0:
			_append_log(errors.get_buffer(error_bytes).get_string_from_utf8())
	var stream: FileAccess = _pipe.get("stdio")
	if running and stream != null:
		# On process pipes FileAccess.get_length() reports bytes ready to read.
		var bytes: int = stream.get_length()
		if bytes > 0:
			_stdout_buffer += stream.get_buffer(bytes).get_string_from_utf8()
			_parse_lines()
	if not running and not _shutting_down and not _failed:
		_fail("The Ardenia simulation worker stopped unexpectedly. See %s." % LOG_PATH)

func _parse_lines() -> void:
	var newline := _stdout_buffer.find("\n")
	while newline >= 0:
		var line := _stdout_buffer.substr(0, newline).strip_edges()
		_stdout_buffer = _stdout_buffer.substr(newline + 1)
		if not line.is_empty():
			_parse_response(line)
		if _failed:
			return
		newline = _stdout_buffer.find("\n")

func _parse_response(line: String) -> void:
	var response = JSON.parse_string(line)
	if not _valid_response(response):
		_fail("The simulation worker returned an invalid protocol response. See %s." % LOG_PATH)
		return
	var request_id: int = response["id"]
	if not _pending.has(request_id):
		_fail("The simulation worker returned an unknown request id. See %s." % LOG_PATH)
		return
	_pending.erase(request_id)
	response_received.emit(request_id, response)

func _valid_response(response: Variant) -> bool:
	if not response is Dictionary \
			or response.size() != 4 \
			or not _is_json_integer(response.get("version")) \
			or int(response["version"]) != PROTOCOL_VERSION \
			or not _is_json_integer(response.get("id")) \
			or typeof(response.get("ok")) != TYPE_BOOL:
		return false
	if response["ok"]:
		return response.has("payload") and response["payload"] is Dictionary \
			and not response.has("error")
	if not response.has("error") or not response["error"] is Dictionary \
			or response.has("payload"):
		return false
	var error: Dictionary = response["error"]
	return error.size() == 2 and typeof(error.get("code")) == TYPE_STRING \
		and typeof(error.get("message")) == TYPE_STRING

func _is_json_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
		and float(value) == floorf(float(value))

func _is_running() -> bool:
	return not _pipe.is_empty() and OS.is_process_running(int(_pipe.get("pid", -1)))

func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_append_log(message + "\n")
	bridge_failed.emit(message)

func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)

func _append_log(message: String) -> void:
	if _log != null:
		_log.store_string(message)
		_log.flush()

func _close_pipe() -> void:
	for key in ["stdio", "stderr"]:
		var stream: FileAccess = _pipe.get(key)
		if stream != null:
			stream.close()
	_pipe.clear()
	_pending.clear()
	if _log != null:
		_log.close()
		_log = null
